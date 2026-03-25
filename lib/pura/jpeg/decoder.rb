# frozen_string_literal: true

module Pura
  module Jpeg
    class DecodeError < StandardError; end

    class Decoder
      # JPEG markers
      SOI  = 0xFFD8
      EOI  = 0xFFD9
      SOF0 = 0xFFC0 # Baseline DCT
      SOF2 = 0xFFC2 # Progressive DCT
      DHT  = 0xFFC4
      DQT  = 0xFFDB
      DRI  = 0xFFDD
      SOS  = 0xFFDA
      APP0 = 0xFFE0
      COM  = 0xFFFE

      def initialize(data)
        @data = data.b
        @pos = 0
        @quant_tables = {}
        @huff_tables = { dc: {}, ac: {} }
        @width = 0
        @height = 0
        @components = []
        @restart_interval = 0
      end

      def self.decode(input)
        data = input.is_a?(String) && File.exist?(input) ? File.binread(input) : input
        new(data).decode
      end

      def decode
        marker = read_u16
        raise DecodeError, "not a JPEG file (missing SOI marker)" unless marker == SOI

        loop do
          marker = next_marker
          case marker
          when SOF0
            parse_sof0
          when SOF2
            raise DecodeError, "progressive JPEG is not supported"
          when 0xFFC9
            raise DecodeError, "arithmetic coding is not supported"
          when DHT
            parse_dht
          when DQT
            parse_dqt
          when DRI
            parse_dri
          when SOS
            parse_sos
            return decode_scan
          when APP0..0xFFEF, COM
            skip_segment
          when EOI
            raise DecodeError, "unexpected EOI before SOS"
          else
            skip_segment
          end
        end
      end

      private

      def read_u8
        raise DecodeError, "unexpected end of data" if @pos >= @data.bytesize

        val = @data.getbyte(@pos)
        @pos += 1
        val
      end

      def read_u16
        (read_u8 << 8) | read_u8
      end

      def read_bytes(n)
        raise DecodeError, "unexpected end of data" if @pos + n > @data.bytesize

        result = @data.byteslice(@pos, n)
        @pos += n
        result
      end

      def next_marker
        loop do
          b = read_u8
          next unless b == 0xFF

          loop do
            b = read_u8
            next if b == 0xFF
            return (0xFF << 8) | b unless b.zero?

            break
          end
        end
      end

      def skip_segment
        length = read_u16
        @pos += length - 2
      end

      def parse_sof0
        read_u16
        precision = read_u8
        raise DecodeError, "only 8-bit precision is supported (got #{precision})" unless precision == 8

        @height = read_u16
        @width = read_u16
        num_components = read_u8

        @components = Array.new(num_components) do
          id = read_u8
          sampling = read_u8
          h_sampling = (sampling >> 4) & 0x0F
          v_sampling = sampling & 0x0F
          quant_table_id = read_u8
          { id: id, h: h_sampling, v: v_sampling, qt: quant_table_id }
        end

        @max_h = @components.map { |c| c[:h] }.max
        @max_v = @components.map { |c| c[:v] }.max
      end

      def parse_dqt
        length = read_u16
        end_pos = @pos + length - 2

        while @pos < end_pos
          info = read_u8
          precision = (info >> 4) & 0x0F
          table_id = info & 0x0F

          table = Array.new(64)
          if precision.zero?
            64.times { |i| table[i] = read_u8 }
          else
            64.times { |i| table[i] = read_u16 }
          end
          @quant_tables[table_id] = table
        end
      end

      def parse_dht
        length = read_u16
        end_pos = @pos + length - 2

        while @pos < end_pos
          info = read_u8
          table_class = (info >> 4) & 0x0F # 0=DC, 1=AC
          table_id = info & 0x0F

          counts = Array.new(16) { read_u8 }
          symbols = []
          counts.each { |c| c.times { symbols << read_u8 } }

          # Build fast 8-bit lookup table + slow fallback for longer codes
          fast, slow = build_huffman_lookup(counts, symbols)

          if table_class.zero?
            @huff_tables[:dc][table_id] = [fast, slow]
          else
            @huff_tables[:ac][table_id] = [fast, slow]
          end
        end
      end

      def build_huffman_lookup(counts, symbols)
        # fast_table[byte] = (symbol << 8) | length, or 0 for no match
        fast_table = Array.new(256, 0)
        slow_table = {}

        code = 0
        si = 0
        counts.each_with_index do |count, bits|
          bit_length = bits + 1
          count.times do
            sym = symbols[si]
            if bit_length <= 8
              fill_count = 1 << (8 - bit_length)
              base = code << (8 - bit_length)
              entry = (sym << 8) | bit_length
              fill_count.times do |j|
                fast_table[base + j] = entry
              end
            else
              slow_table[bit_length] ||= {}
              slow_table[bit_length][code] = sym
            end
            si += 1
            code += 1
          end
          code <<= 1
        end
        [fast_table, slow_table]
      end

      def parse_dri
        read_u16
        @restart_interval = read_u16
      end

      def parse_sos
        read_u16
        num_components = read_u8

        @scan_components = Array.new(num_components) do
          id = read_u8
          table_sel = read_u8
          dc_table = (table_sel >> 4) & 0x0F
          ac_table = table_sel & 0x0F
          comp = @components.find { |c| c[:id] == id }
          raise DecodeError, "unknown component id #{id} in SOS" unless comp

          comp.merge(dc_table: dc_table, ac_table: ac_table)
        end

        @ss = read_u8
        @se = read_u8
        @ah_al = read_u8
      end

      def decode_scan
        raw = extract_entropy_data

        # Inline bit reader state for maximum performance
        @br_data = raw
        @br_pos = 0
        @br_buf = 0
        @br_bits = 0
        @br_size = raw.bytesize

        mcu_width = (@width + (@max_h * 8) - 1) / (@max_h * 8)
        mcu_height = (@height + (@max_v * 8) - 1) / (@max_v * 8)

        # Flat component buffers: [flat_array, width]
        comp_buffers = @scan_components.map do |comp|
          full_w = mcu_width * comp[:h] * 8
          full_h = mcu_height * comp[:v] * 8
          [Array.new(full_w * full_h, 0), full_w]
        end

        prev_dc = Array.new(@scan_components.size, 0)
        restart_count = 0

        # Reusable buffers
        block_buf = Array.new(64, 0)
        dezigzag_buf = Array.new(64, 0)
        idct_row = Array.new(64, 0.0)
        idct_out = Array.new(64, 0)

        mcu_height.times do |mcu_y|
          mcu_width.times do |mcu_x|
            if @restart_interval.positive? && restart_count.positive? && (restart_count % @restart_interval).zero?
              @br_bits = 0
              @br_buf = 0
              prev_dc.fill(0)
            end

            @scan_components.each_with_index do |comp, ci|
              buf = comp_buffers[ci][0]
              buf_w = comp_buffers[ci][1]
              dc_fast, dc_slow = @huff_tables[:dc][comp[:dc_table]]
              ac_fast, ac_slow = @huff_tables[:ac][comp[:ac_table]]
              qt = @quant_tables[comp[:qt]]

              comp[:v].times do |v|
                comp[:h].times do |h|
                  prev_dc[ci] = decode_block_opt(
                    dc_fast, dc_slow, ac_fast, ac_slow, qt,
                    prev_dc[ci], block_buf, dezigzag_buf
                  )

                  idct_fast(dezigzag_buf, idct_row, idct_out)

                  bx = ((mcu_x * comp[:h]) + h) * 8
                  by = ((mcu_y * comp[:v]) + v) * 8
                  bi = 0
                  row_base = (by * buf_w) + bx
                  8.times do |_row|
                    idx = row_base
                    buf[idx]     = idct_out[bi]
                    buf[idx + 1] = idct_out[bi + 1]
                    buf[idx + 2] = idct_out[bi + 2]
                    buf[idx + 3] = idct_out[bi + 3]
                    buf[idx + 4] = idct_out[bi + 4]
                    buf[idx + 5] = idct_out[bi + 5]
                    buf[idx + 6] = idct_out[bi + 6]
                    buf[idx + 7] = idct_out[bi + 7]
                    bi += 8
                    row_base += buf_w
                  end
                end
              end
            end
            restart_count += 1
          end
        end

        build_image_fast(comp_buffers, mcu_width, mcu_height)
      end

      def extract_entropy_data
        result = String.new(encoding: Encoding::BINARY, capacity: @data.bytesize - @pos)

        while @pos < @data.bytesize
          byte = @data.getbyte(@pos)
          @pos += 1

          if byte == 0xFF
            raise DecodeError, "unexpected end of data in entropy segment" if @pos >= @data.bytesize

            next_byte = @data.getbyte(@pos)
            @pos += 1

            if next_byte.zero?
              result << 0xFF.chr
            elsif next_byte.between?(0xD0, 0xD7)
              # Restart marker - skip
            elsif next_byte == 0xFF
              @pos -= 1
            else
              @pos -= 2
              break
            end
          else
            result << byte.chr
          end
        end
        result
      end

      # --- Inline bit reader operations ---

      BUF_MASKS = (0..31).map { |i| (1 << i) - 1 }.freeze

      def br_ensure(n)
        while @br_bits < n
          if @br_pos < @br_size
            @br_buf = ((@br_buf & BUF_MASKS[@br_bits]) << 8) | @br_data.getbyte(@br_pos)
            @br_pos += 1
            @br_bits += 8
          else
            # Pad with zero bits at end of data
            pad = n - @br_bits
            @br_buf = (@br_buf & BUF_MASKS[@br_bits]) << pad
            @br_bits = n
            break
          end
        end
      end

      def br_read_bits(n)
        br_ensure(n)
        @br_bits -= n
        (@br_buf >> @br_bits) & BUF_MASKS[n]
      end

      def br_read_bit
        br_ensure(1)
        @br_bits -= 1
        (@br_buf >> @br_bits) & 1
      end

      # --- Huffman decode with fast table ---

      def decode_huffman_fast(fast_table, slow_table)
        # Ensure at least 8 bits in buffer for fast path
        br_ensure(8)
        peek = (@br_buf >> (@br_bits - 8)) & 0xFF

        entry = fast_table[peek]
        if entry != 0
          len = entry & 0xFF
          @br_bits -= len
          return entry >> 8
        end

        # Slow path: consume 8 bits already peeked, then scan longer codes
        code = peek
        @br_bits -= 8

        9.upto(16) do |length|
          code = (code << 1) | br_read_bit
          return slow_table[length][code] if slow_table[length]&.key?(code)
        end
        raise DecodeError, "invalid Huffman code"
      end

      def decode_block_opt(dc_fast, dc_slow, ac_fast, ac_slow, quant_table, prev_dc, block, result)
        # Clear block
        64.times { |i| block[i] = 0 }

        # DC coefficient
        dc_cat = decode_huffman_fast(dc_fast, dc_slow)
        if dc_cat.positive?
          dc_value = br_read_bits(dc_cat)
          dc_value -= BUF_MASKS[dc_cat] if dc_value < (1 << (dc_cat - 1))
        else
          dc_value = 0
        end
        dc_value += prev_dc
        block[0] = dc_value

        # AC coefficients
        i = 1
        while i < 64
          rs = decode_huffman_fast(ac_fast, ac_slow)
          r = (rs >> 4) & 0x0F
          s = rs & 0x0F

          if s.zero?
            break unless r == 15

            i += 16

          # EOB

          else
            i += r
            break if i >= 64

            val = br_read_bits(s)
            val -= BUF_MASKS[s] if val < (1 << (s - 1))
            block[i] = val
            i += 1
          end
        end

        # De-zigzag and dequantize into result buffer
        64.times do |j|
          result[ZIGZAG[j]] = block[j] * quant_table[j]
        end

        dc_value
      end

      # Pre-scaled IDCT cosine table: includes 0.5 * C(u) factor
      # IDCT_COS[u][x] = 0.5 * C(u) * cos((2x+1)*u*pi/16)
      # where C(0) = 1/sqrt(2), C(u) = 1 for u > 0
      INV_SQRT2 = 1.0 / Math.sqrt(2.0)
      IDCT_COS = Array.new(8) do |u|
        scale = u.zero? ? 0.5 * INV_SQRT2 : 0.5
        Array.new(8) do |x|
          scale * Math.cos(((2.0 * x) + 1.0) * u * Math::PI / 16.0)
        end
      end.freeze

      # Flatten IDCT_COS for faster access: IDCT_COS_FLAT[u * 8 + x]
      IDCT_COS_FLAT = IDCT_COS.flatten.freeze

      def idct_fast(block, tmp, output)
        # Row pass: tmp[row*8+x] = Σ_u block[row*8+u] * IDCT_COS_FLAT[u*8+x]
        8.times do |row|
          off = row * 8
          b0 = block[off]
          b1 = block[off + 1]
          b2 = block[off + 2]
          b3 = block[off + 3]
          b4 = block[off + 4]
          b5 = block[off + 5]
          b6 = block[off + 6]
          b7 = block[off + 7]

          # Skip row if all AC coefficients are zero (common case)
          if b1.zero? && b2.zero? && b3.zero? && b4.zero? && b5.zero? && b6.zero? && b7.zero?
            dc = b0 * IDCT_COS_FLAT[0]
            tmp[off] = dc
            tmp[off + 1] = dc
            tmp[off + 2] = dc
            tmp[off + 3] = dc
            tmp[off + 4] = dc
            tmp[off + 5] = dc
            tmp[off + 6] = dc
            tmp[off + 7] = dc
            next
          end

          8.times do |x|
            tmp[off + x] = (b0 * IDCT_COS_FLAT[x]) +
                           (b1 * IDCT_COS_FLAT[8 + x]) +
                           (b2 * IDCT_COS_FLAT[16 + x]) +
                           (b3 * IDCT_COS_FLAT[24 + x]) +
                           (b4 * IDCT_COS_FLAT[32 + x]) +
                           (b5 * IDCT_COS_FLAT[40 + x]) +
                           (b6 * IDCT_COS_FLAT[48 + x]) +
                           (b7 * IDCT_COS_FLAT[56 + x])
          end
        end

        # Column pass: output[y*8+col] = clamp(Σ_v tmp[v*8+col] * IDCT_COS_FLAT[v*8+y] + 128)
        8.times do |col|
          t0 = tmp[col]
          t1 = tmp[8 + col]
          t2 = tmp[16 + col]
          t3 = tmp[24 + col]
          t4 = tmp[32 + col]
          t5 = tmp[40 + col]
          t6 = tmp[48 + col]
          t7 = tmp[56 + col]

          8.times do |y|
            val = ((t0 * IDCT_COS_FLAT[y]) +
                   (t1 * IDCT_COS_FLAT[8 + y]) +
                   (t2 * IDCT_COS_FLAT[16 + y]) +
                   (t3 * IDCT_COS_FLAT[24 + y]) +
                   (t4 * IDCT_COS_FLAT[32 + y]) +
                   (t5 * IDCT_COS_FLAT[40 + y]) +
                   (t6 * IDCT_COS_FLAT[48 + y]) +
                   (t7 * IDCT_COS_FLAT[56 + y]) + 128.0).round
            val = 0 if val.negative?
            val = 255 if val > 255
            output[(y * 8) + col] = val
          end
        end
      end

      # Zigzag order mapping
      ZIGZAG = [
        0,  1, 8, 16, 9, 2, 3, 10,
        17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34,
        27, 20, 13,  6,  7, 14, 21, 28,
        35, 42, 49, 56, 57, 50, 43, 36,
        29, 22, 15, 23, 30, 37, 44, 51,
        58, 59, 52, 45, 38, 31, 39, 46,
        53, 60, 61, 54, 47, 55, 62, 63
      ].freeze

      def build_image_fast(comp_buffers, _mcu_width, _mcu_height)
        w = @width
        h = @height
        pixel_count = w * h

        if @scan_components.size == 1
          # Grayscale
          pixels = String.new(encoding: Encoding::BINARY, capacity: pixel_count * 3)
          buf = comp_buffers[0][0]
          buf_w = comp_buffers[0][1]
          h.times do |y|
            row_off = y * buf_w
            w.times do |x|
              gray = buf[row_off + x]
              pixels << gray.chr << gray.chr << gray.chr
            end
          end
        else
          # YCbCr to RGB with integer math
          y_buf = comp_buffers[0][0]
          y_buf_w = comp_buffers[0][1]
          cb_buf = comp_buffers[1][0]
          cb_buf_w = comp_buffers[1][1]
          cr_buf = comp_buffers[2][0]
          cr_buf_w = comp_buffers[2][1]

          cb_comp = @scan_components[1]
          cr_comp = @scan_components[2]
          cb_h = cb_comp[:h]
          cb_v = cb_comp[:v]
          cr_h = cr_comp[:h]
          cr_v = cr_comp[:v]
          max_h = @max_h
          max_v = @max_v

          out_bytes = Array.new(pixel_count * 3)
          oi = 0

          h.times do |row|
            y_row_off = row * y_buf_w
            cb_row_off = (row * cb_v / max_v) * cb_buf_w
            cr_row_off = (row * cr_v / max_v) * cr_buf_w

            w.times do |col|
              yy = y_buf[y_row_off + col]
              cb = cb_buf[cb_row_off + (col * cb_h / max_h)]
              cr = cr_buf[cr_row_off + (col * cr_h / max_h)]

              # Integer YCbCr to RGB
              cr_off = cr - 128
              cb_off = cb - 128

              r = yy + (((91_881 * cr_off) + 32_768) >> 16)
              g = yy - (((22_554 * cb_off) + (46_802 * cr_off) + 32_768) >> 16)
              b = yy + (((116_130 * cb_off) + 32_768) >> 16)

              r = 0 if r.negative?
              r = 255 if r > 255
              g = 0 if g.negative?
              g = 255 if g > 255
              b = 0 if b.negative?
              b = 255 if b > 255

              out_bytes[oi] = r
              out_bytes[oi + 1] = g
              out_bytes[oi + 2] = b
              oi += 3
            end
          end

          pixels = out_bytes.pack("C*")
        end

        Image.new(w, h, pixels)
      end
    end

    # BitReader is no longer used (inlined into Decoder) but kept for compatibility
    class BitReader
      def initialize(data)
        @data = data
        @pos = 0
        @bit_pos = 0
        @current_byte = 0
      end

      def read_bit
        if @bit_pos.zero?
          raise DecodeError, "unexpected end of entropy data" if @pos >= @data.bytesize

          @current_byte = @data.getbyte(@pos)
          @pos += 1
          @bit_pos = 8
        end
        @bit_pos -= 1
        (@current_byte >> @bit_pos) & 1
      end

      def read_bits(n)
        value = 0
        n.times { value = (value << 1) | read_bit }
        value
      end

      def align_byte
        @bit_pos = 0
      end
    end
  end
end

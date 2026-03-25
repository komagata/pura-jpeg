# frozen_string_literal: true

module Pura
  module Jpeg
    class Encoder
      # Standard JPEG luminance quantization table (ITU-T T.81, Annex K)
      LUMINANCE_QUANT_TABLE = [
        16, 11, 10, 16,  24,  40,  51,  61,
        12, 12, 14, 19,  26,  58,  60,  55,
        14, 13, 16, 24,  40,  57,  69,  56,
        14, 17, 22, 29,  51,  87,  80,  62,
        18, 22, 37, 56,  68, 109, 103,  77,
        24, 35, 55, 64,  81, 104, 113,  92,
        49, 64, 78, 87, 103, 121, 120, 101,
        72, 92, 95, 98, 112, 100, 103, 99
      ].freeze

      # Standard JPEG chrominance quantization table
      CHROMINANCE_QUANT_TABLE = [
        17, 18, 24, 47, 99, 99, 99, 99,
        18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99,
        47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99
      ].freeze

      # Zigzag order mapping (same as decoder)
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

      # Pre-scaled FDCT cosine table: includes C(u) factor
      # FDCT_COS[u * 8 + x] = C(u) * cos((2x+1)*u*pi/16)
      # where C(0) = 1/sqrt(2), C(u) = 1 for u > 0
      INV_SQRT2 = 1.0 / Math.sqrt(2.0)
      FDCT_COS = Array.new(64) do |i|
        u = i / 8
        x = i % 8
        scale = u.zero? ? INV_SQRT2 : 1.0
        scale * Math.cos(((2.0 * x) + 1.0) * u * Math::PI / 16.0)
      end.freeze

      # --- Standard Huffman table data (ITU-T T.81, Annex K) ---

      # DC Luminance
      DC_LUM_BITS = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0].freeze
      DC_LUM_VALS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].freeze

      # DC Chrominance
      DC_CHR_BITS = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0].freeze
      DC_CHR_VALS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].freeze

      # AC Luminance
      AC_LUM_BITS = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D].freeze
      AC_LUM_VALS = [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
        0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
        0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
        0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
        0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
        0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
        0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
        0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
        0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
        0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
        0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4,
        0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
        0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
        0xF9, 0xFA
      ].freeze

      # AC Chrominance
      AC_CHR_BITS = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77].freeze
      AC_CHR_VALS = [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
        0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
        0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
        0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
        0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34,
        0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
        0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38,
        0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
        0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
        0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
        0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
        0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96,
        0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
        0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
        0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
        0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2,
        0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
        0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9,
        0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
        0xF9, 0xFA
      ].freeze

      # Build Huffman code table from bits/vals arrays
      def self.build_huffman_from_spec(bits, vals)
        table = {}
        code = 0
        vi = 0
        bits.each_with_index do |count, i|
          bit_length = i + 1
          count.times do
            table[vals[vi]] = [code, bit_length]
            vi += 1
            code += 1
          end
          code <<= 1
        end
        table
      end

      # Standard DC Huffman tables
      DC_LUMINANCE_HUFFMAN = build_huffman_from_spec(DC_LUM_BITS, DC_LUM_VALS).freeze
      DC_CHROMINANCE_HUFFMAN = build_huffman_from_spec(DC_CHR_BITS, DC_CHR_VALS).freeze

      # Standard AC Huffman tables
      AC_LUMINANCE_HUFFMAN = build_huffman_from_spec(AC_LUM_BITS, AC_LUM_VALS).freeze
      AC_CHROMINANCE_HUFFMAN = build_huffman_from_spec(AC_CHR_BITS, AC_CHR_VALS).freeze

      def initialize(image, quality: 85, subsampling: :s420)
        @image = image
        @quality = quality.clamp(1, 100)
        @subsampling = subsampling
        @lum_qt = scale_quant_table(LUMINANCE_QUANT_TABLE, @quality)
        @chr_qt = scale_quant_table(CHROMINANCE_QUANT_TABLE, @quality)
      end

      def self.encode(image, output_path, quality: 85, subsampling: :s420)
        encoder = new(image, quality: quality, subsampling: subsampling)
        data = encoder.encode
        File.binwrite(output_path, data)
        data.bytesize
      end

      def encode
        width = @image.width
        height = @image.height
        y_data, cb_data, cr_data = rgb_to_ycbcr(width, height)

        if @subsampling == :s444
          h_max = 1
          v_max = 1
          y_h = 1
          y_v = 1
        else # :s420
          h_max = 2
          v_max = 2
          y_h = 2
          y_v = 2
        end
        c_h = 1
        c_v = 1

        # Subsample chroma if needed
        if @subsampling == :s420
          cb_sub = subsample_420(cb_data, width, height)
          cr_sub = subsample_420(cr_data, width, height)
          c_width = (width + 1) / 2
          c_height = (height + 1) / 2
        else
          cb_sub = cb_data
          cr_sub = cr_data
          c_width = width
          c_height = height
        end

        # Pad to MCU boundaries
        mcu_w = h_max * 8
        mcu_h = v_max * 8
        padded_w = (width + mcu_w - 1) / mcu_w * mcu_w
        padded_h = (height + mcu_h - 1) / mcu_h * mcu_h

        y_padded = pad_component(y_data, width, height, padded_w, padded_h)

        c_padded_w = padded_w / h_max * c_h
        c_padded_h = padded_h / v_max * c_v
        cb_padded = pad_component(cb_sub, c_width, c_height, c_padded_w, c_padded_h)
        cr_padded = pad_component(cr_sub, c_width, c_height, c_padded_w, c_padded_h)

        # Build JPEG output
        out = String.new(encoding: Encoding::BINARY, capacity: width * height)

        write_u16(out, 0xFFD8) # SOI
        write_app0(out) # APP0/JFIF
        write_dqt(out, 0, @lum_qt)      # DQT luminance
        write_dqt(out, 1, @chr_qt)      # DQT chrominance
        write_sof0(out, width, height, y_h, y_v, c_h, c_v)
        write_dht(out, 0, 0, DC_LUM_BITS, DC_LUM_VALS)   # DC luminance
        write_dht(out, 1, 0, AC_LUM_BITS, AC_LUM_VALS)   # AC luminance
        write_dht(out, 0, 1, DC_CHR_BITS, DC_CHR_VALS)   # DC chrominance
        write_dht(out, 1, 1, AC_CHR_BITS, AC_CHR_VALS)   # AC chrominance
        write_sos(out)
        write_scan_data(out, y_padded, cb_padded, cr_padded,
                        padded_w, padded_h, c_padded_w, c_padded_h,
                        y_h, y_v, c_h, c_v)
        write_u16(out, 0xFFD9) # EOI

        out
      end

      private

      def scale_quant_table(base_table, quality)
        scale = if quality < 50
                  5000 / quality
                else
                  200 - (quality * 2)
                end

        base_table.map do |val|
          q = ((val * scale) + 50) / 100
          q = 1 if q < 1
          q = 255 if q > 255
          q
        end
      end

      # Integer RGB to YCbCr using fixed-point (<<16) arithmetic
      def rgb_to_ycbcr(width, height)
        pixels = @image.pixels
        size = width * height
        y_data = Array.new(size)
        cb_data = Array.new(size)
        cr_data = Array.new(size)

        size.times do |i|
          offset = i * 3
          r = pixels.getbyte(offset)
          g = pixels.getbyte(offset + 1)
          b = pixels.getbyte(offset + 2)

          y_data[i] = (0.299 * r) + (0.587 * g) + (0.114 * b)
          cb_data[i] = (-0.168736 * r) - (0.331264 * g) + (0.5 * b) + 128.0
          cr_data[i] = (0.5 * r) - (0.418688 * g) - (0.081312 * b) + 128.0
        end

        [y_data, cb_data, cr_data]
      end

      def subsample_420(data, width, height)
        sw = (width + 1) / 2
        sh = (height + 1) / 2
        result = Array.new(sw * sh)

        sh.times do |sy|
          sw.times do |sx|
            x0 = sx * 2
            y0 = sy * 2
            x1 = [x0 + 1, width - 1].min
            y1 = [y0 + 1, height - 1].min

            sum = data[(y0 * width) + x0] +
                  data[(y0 * width) + x1] +
                  data[(y1 * width) + x0] +
                  data[(y1 * width) + x1]
            result[(sy * sw) + sx] = sum * 0.25
          end
        end
        result
      end

      def pad_component(data, width, height, padded_w, padded_h)
        return data if width == padded_w && height == padded_h

        result = Array.new(padded_w * padded_h, 0.0)
        height.times do |y|
          src_off = y * width
          dst_off = y * padded_w
          width.times do |x|
            result[dst_off + x] = data[src_off + x]
          end
          edge = data[src_off + width - 1]
          (width...padded_w).each do |x|
            result[dst_off + x] = edge
          end
        end
        last_row_off = (height - 1) * padded_w
        (height...padded_h).each do |y|
          dst_off = y * padded_w
          padded_w.times do |x|
            result[dst_off + x] = result[last_row_off + x]
          end
        end
        result
      end

      # 2-pass separable FDCT with pre-scaled cosine table
      # 1024 multiplications instead of 4096
      def fdct(block)
        tmp = Array.new(64, 0.0)

        # Pass 1: transform rows
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

          8.times do |u|
            uoff = u * 8
            tmp[(u * 8) + row] = (b0 * FDCT_COS[uoff]) +
                                 (b1 * FDCT_COS[uoff + 1]) +
                                 (b2 * FDCT_COS[uoff + 2]) +
                                 (b3 * FDCT_COS[uoff + 3]) +
                                 (b4 * FDCT_COS[uoff + 4]) +
                                 (b5 * FDCT_COS[uoff + 5]) +
                                 (b6 * FDCT_COS[uoff + 6]) +
                                 (b7 * FDCT_COS[uoff + 7])
          end
        end

        # Pass 2: transform columns (of intermediate result)
        result = Array.new(64, 0.0)
        8.times do |u|
          uoff = u * 8
          8.times do |v|
            voff = v * 8
            t0 = tmp[voff]
            t1 = tmp[voff + 1]
            t2 = tmp[voff + 2]
            t3 = tmp[voff + 3]
            t4 = tmp[voff + 4]
            t5 = tmp[voff + 5]
            t6 = tmp[voff + 6]
            t7 = tmp[voff + 7]

            result[uoff + v] = 0.25 * ((t0 * FDCT_COS[uoff]) +
                                        (t1 * FDCT_COS[uoff + 1]) +
                                        (t2 * FDCT_COS[uoff + 2]) +
                                        (t3 * FDCT_COS[uoff + 3]) +
                                        (t4 * FDCT_COS[uoff + 4]) +
                                        (t5 * FDCT_COS[uoff + 5]) +
                                        (t6 * FDCT_COS[uoff + 6]) +
                                        (t7 * FDCT_COS[uoff + 7]))
          end
        end
        result
      end

      def quantize(dct_block, quant_table)
        result = Array.new(64)
        64.times do |i|
          result[i] = (dct_block[i] / quant_table[i]).round
        end
        result
      end

      def zigzag_reorder(block)
        result = Array.new(64)
        64.times do |i|
          result[i] = block[ZIGZAG[i]]
        end
        result
      end

      def extract_block(data, data_width, bx, by)
        block = Array.new(64)
        8.times do |row|
          base = ((by + row) * data_width) + bx
          off = row * 8
          block[off]     = data[base] - 128.0
          block[off + 1] = data[base + 1] - 128.0
          block[off + 2] = data[base + 2] - 128.0
          block[off + 3] = data[base + 3] - 128.0
          block[off + 4] = data[base + 4] - 128.0
          block[off + 5] = data[base + 5] - 128.0
          block[off + 6] = data[base + 6] - 128.0
          block[off + 7] = data[base + 7] - 128.0
        end
        block
      end

      # --- Optimized BitWriter: buffers bits and flushes in bulk ---

      class BitWriter
        def initialize
          @data = String.new(encoding: Encoding::BINARY, capacity: 4096)
          @buf = 0
          @buf_bits = 0
        end

        def write_bits(value, length)
          @buf = (@buf << length) | (value & ((1 << length) - 1))
          @buf_bits += length

          while @buf_bits >= 8
            @buf_bits -= 8
            byte = (@buf >> @buf_bits) & 0xFF
            @data << byte.chr
            @data << "\x00" if byte == 0xFF
          end

          # Prevent buffer growth
          @buf &= (1 << @buf_bits) - 1 if @buf_bits.positive?
        end

        def flush
          return unless @buf_bits.positive?

          byte = (@buf << (8 - @buf_bits)) & 0xFF
          byte |= (1 << (8 - @buf_bits)) - 1
          @data << byte.chr
          @data << "\x00" if byte == 0xFF
          @buf = 0
          @buf_bits = 0
        end

        def bytes
          @data
        end
      end

      # --- Huffman encoding helpers ---

      def encode_dc(bw, value, prev_dc, dc_table)
        diff = value - prev_dc
        category = bit_category(diff)
        code, code_len = dc_table[category]
        bw.write_bits(code, code_len)
        bw.write_bits(encode_coefficient(diff, category), category) if category.positive?
        value
      end

      def encode_ac(bw, coefficients, ac_table)
        last_nonzero = 63
        last_nonzero -= 1 while last_nonzero.positive? && coefficients[last_nonzero].zero?

        if last_nonzero.zero?
          code, code_len = ac_table[0x00]
          bw.write_bits(code, code_len)
          return
        end

        zero_run = 0
        i = 1
        while i <= last_nonzero
          if coefficients[i].zero?
            zero_run += 1
            i += 1
            next
          end

          while zero_run >= 16
            code, code_len = ac_table[0xF0]
            bw.write_bits(code, code_len)
            zero_run -= 16
          end

          category = bit_category(coefficients[i])
          rs = (zero_run << 4) | category
          code, code_len = ac_table[rs]
          bw.write_bits(code, code_len)
          bw.write_bits(encode_coefficient(coefficients[i], category), category)
          zero_run = 0
          i += 1
        end

        return unless last_nonzero < 63

        code, code_len = ac_table[0x00]
        bw.write_bits(code, code_len)
      end

      def bit_category(value)
        return 0 if value.zero?

        v = value.abs
        cat = 0
        while v.positive?
          cat += 1
          v >>= 1
        end
        cat
      end

      def encode_coefficient(value, category)
        if value >= 0
          value
        else
          value + (1 << category) - 1
        end
      end

      # --- JPEG segment writers ---

      def write_u8(out, val)
        out << (val & 0xFF).chr
      end

      def write_u16(out, val)
        out << ((val >> 8) & 0xFF).chr << (val & 0xFF).chr
      end

      def write_app0(out)
        write_u16(out, 0xFFE0)
        write_u16(out, 16)
        out << "JFIF\x00"
        out << "\x01\x01"
        write_u8(out, 0)
        write_u16(out, 1)
        write_u16(out, 1)
        write_u8(out, 0)
        write_u8(out, 0)
      end

      def write_dqt(out, table_id, quant_table)
        write_u16(out, 0xFFDB)
        write_u16(out, 67)
        write_u8(out, table_id)
        64.times do |i|
          write_u8(out, quant_table[ZIGZAG[i]])
        end
      end

      def write_sof0(out, width, height, y_h, y_v, c_h, c_v)
        write_u16(out, 0xFFC0)
        write_u16(out, 17)
        write_u8(out, 8)
        write_u16(out, height)
        write_u16(out, width)
        write_u8(out, 3)

        # Y
        write_u8(out, 1)
        write_u8(out, (y_h << 4) | y_v)
        write_u8(out, 0)

        # Cb
        write_u8(out, 2)
        write_u8(out, (c_h << 4) | c_v)
        write_u8(out, 1)

        # Cr
        write_u8(out, 3)
        write_u8(out, (c_h << 4) | c_v)
        write_u8(out, 1)
      end

      def write_dht(out, table_class, table_id, bits, vals)
        write_u16(out, 0xFFC4)
        total_vals = bits.sum
        write_u16(out, 2 + 1 + 16 + total_vals)
        write_u8(out, (table_class << 4) | table_id)
        bits.each { |b| write_u8(out, b) }
        vals.each { |v| write_u8(out, v) }
      end

      def write_sos(out)
        write_u16(out, 0xFFDA)
        write_u16(out, 12)
        write_u8(out, 3)

        write_u8(out, 1)
        write_u8(out, 0x00) # Y: DC0, AC0
        write_u8(out, 2)
        write_u8(out, 0x11) # Cb: DC1, AC1
        write_u8(out, 3)
        write_u8(out, 0x11) # Cr: DC1, AC1

        write_u8(out, 0)   # Ss
        write_u8(out, 63)  # Se
        write_u8(out, 0)   # Ah/Al
      end

      def write_scan_data(out, y_data, cb_data, cr_data,
                          y_width, y_height, c_width, _c_height,
                          y_h, y_v, c_h, c_v)
        bw = BitWriter.new

        h_max = [y_h, c_h].max
        v_max = [y_v, c_v].max
        mcu_cols = y_width / (h_max * 8)
        mcu_rows = y_height / (v_max * 8)

        prev_dc_y = 0
        prev_dc_cb = 0
        prev_dc_cr = 0

        mcu_rows.times do |mcu_row|
          mcu_cols.times do |mcu_col|
            # Y blocks
            y_v.times do |v|
              y_h.times do |h|
                bx = ((mcu_col * y_h) + h) * 8
                by = ((mcu_row * y_v) + v) * 8
                block = extract_block(y_data, y_width, bx, by)
                dct = fdct(block)
                quant = quantize(dct, @lum_qt)
                zz = zigzag_reorder(quant)
                prev_dc_y = encode_dc(bw, zz[0], prev_dc_y, DC_LUMINANCE_HUFFMAN)
                encode_ac(bw, zz, AC_LUMINANCE_HUFFMAN)
              end
            end

            # Cb block(s)
            c_v.times do |v|
              c_h.times do |h|
                bx = ((mcu_col * c_h) + h) * 8
                by = ((mcu_row * c_v) + v) * 8
                block = extract_block(cb_data, c_width, bx, by)
                dct = fdct(block)
                quant = quantize(dct, @chr_qt)
                zz = zigzag_reorder(quant)
                prev_dc_cb = encode_dc(bw, zz[0], prev_dc_cb, DC_CHROMINANCE_HUFFMAN)
                encode_ac(bw, zz, AC_CHROMINANCE_HUFFMAN)
              end
            end

            # Cr block(s)
            c_v.times do |v|
              c_h.times do |h|
                bx = ((mcu_col * c_h) + h) * 8
                by = ((mcu_row * c_v) + v) * 8
                block = extract_block(cr_data, c_width, bx, by)
                dct = fdct(block)
                quant = quantize(dct, @chr_qt)
                zz = zigzag_reorder(quant)
                prev_dc_cr = encode_dc(bw, zz[0], prev_dc_cr, DC_CHROMINANCE_HUFFMAN)
                encode_ac(bw, zz, AC_CHROMINANCE_HUFFMAN)
              end
            end
          end
        end

        bw.flush
        out << bw.bytes
      end
    end
  end
end

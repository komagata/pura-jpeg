# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-jpeg"

class TestEncoder < Minitest::Test
  FIXTURE_DIR = File.join(__dir__, "fixtures")
  TMP_DIR = File.join(__dir__, "tmp")

  def setup
    FileUtils.mkdir_p(TMP_DIR)
  end

  def teardown
    Dir.glob(File.join(TMP_DIR, "*")).each { |f| File.delete(f) }
    FileUtils.rm_f(TMP_DIR)
  end

  def test_encode_produces_valid_jpeg
    image = create_red_image(64, 64)
    out_path = File.join(TMP_DIR, "test_encode.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 85)

    data = File.binread(out_path)
    # Starts with SOI marker
    assert_equal 0xFF, data.getbyte(0)
    assert_equal 0xD8, data.getbyte(1)
    # Ends with EOI marker
    assert_equal 0xFF, data.getbyte(data.bytesize - 2)
    assert_equal 0xD9, data.getbyte(data.bytesize - 1)
  end

  def test_encode_decode_roundtrip_dimensions
    image = create_red_image(64, 64)
    out_path = File.join(TMP_DIR, "test_roundtrip.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 95)

    decoded = Pura::Jpeg.decode(out_path)
    assert_equal 64, decoded.width
    assert_equal 64, decoded.height
  end

  def test_encode_decode_roundtrip_pixels
    image = create_red_image(64, 64)
    out_path = File.join(TMP_DIR, "test_roundtrip_pixels.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 95)

    decoded = Pura::Jpeg.decode(out_path)
    r, g, b = decoded.pixel_at(32, 32)
    # With high quality, red should still be close to original
    assert_in_delta 255, r, 30, "red channel should be near 255"
    assert_in_delta 0, g, 30, "green channel should be near 0"
    assert_in_delta 0, b, 30, "blue channel should be near 0"
  end

  def test_encode_decode_roundtrip_from_fixture
    path = File.join(FIXTURE_DIR, "test_64x64.jpg")
    image = Pura::Jpeg.decode(path)
    out_path = File.join(TMP_DIR, "test_fixture_roundtrip.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 90)

    decoded = Pura::Jpeg.decode(out_path)
    assert_equal image.width, decoded.width
    assert_equal image.height, decoded.height

    # Check pixel similarity
    total = image.width * image.height * 3
    mismatched = 0
    total.times do |i|
      diff = (image.pixels.getbyte(i) - decoded.pixels.getbyte(i)).abs
      mismatched += 1 if diff > 20
    end
    error_rate = mismatched.to_f / total
    assert error_rate < 0.15, "too many pixel mismatches: #{(error_rate * 100).round(2)}%"
  end

  def test_encode_444_subsampling
    image = create_red_image(32, 32)
    out_path = File.join(TMP_DIR, "test_444.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 85, subsampling: :s444)

    decoded = Pura::Jpeg.decode(out_path)
    assert_equal 32, decoded.width
    assert_equal 32, decoded.height
  end

  def test_encode_different_qualities
    image = create_gradient_image(64, 64)

    out_low = File.join(TMP_DIR, "test_q10.jpg")
    out_high = File.join(TMP_DIR, "test_q95.jpg")

    Pura::Jpeg.encode(image, out_low, quality: 10)
    Pura::Jpeg.encode(image, out_high, quality: 95)

    size_low = File.size(out_low)
    size_high = File.size(out_high)

    # Higher quality should produce larger files
    assert size_high > size_low, "quality 95 (#{size_high}) should be larger than quality 10 (#{size_low})"
  end

  def test_encode_non_multiple_of_8_dimensions
    image = create_red_image(50, 37)
    out_path = File.join(TMP_DIR, "test_odd_size.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 85)

    decoded = Pura::Jpeg.decode(out_path)
    assert_equal 50, decoded.width
    assert_equal 37, decoded.height
  end

  def test_encode_non_multiple_of_16_with_420
    image = create_red_image(33, 17)
    out_path = File.join(TMP_DIR, "test_odd_420.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 85, subsampling: :s420)

    decoded = Pura::Jpeg.decode(out_path)
    assert_equal 33, decoded.width
    assert_equal 17, decoded.height
  end

  private

  def create_red_image(width, height)
    pixels = "\xFF\x00\x00".b * (width * height)
    Pura::Jpeg::Image.new(width, height, pixels)
  end

  def create_gradient_image(width, height)
    pixels = String.new(encoding: Encoding::BINARY, capacity: width * height * 3)
    height.times do |y|
      width.times do |x|
        r = (x * 255 / [width - 1, 1].max)
        g = (y * 255 / [height - 1, 1].max)
        b = 128
        pixels << r.chr << g.chr << b.chr
      end
    end
    Pura::Jpeg::Image.new(width, height, pixels)
  end
end

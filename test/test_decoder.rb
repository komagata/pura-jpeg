# frozen_string_literal: true

require "English"
require "minitest/autorun"
require_relative "../lib/pura-jpeg"

class TestDecoder < Minitest::Test
  FIXTURE_DIR = File.join(__dir__, "fixtures")

  def test_decode_basic_jpeg
    path = File.join(FIXTURE_DIR, "test_64x64.jpg")
    image = Pura::Jpeg.decode(path)

    assert_equal 64, image.width
    assert_equal 64, image.height
    assert_equal 64 * 64 * 3, image.pixels.bytesize
  end

  def test_decode_444_jpeg
    path = File.join(FIXTURE_DIR, "test_444.jpg")
    image = Pura::Jpeg.decode(path)

    assert_equal 64, image.width
    assert_equal 64, image.height
    assert_equal 64 * 64 * 3, image.pixels.bytesize
  end

  def test_decode_422_jpeg
    path = File.join(FIXTURE_DIR, "test_422.jpg")
    image = Pura::Jpeg.decode(path)

    assert_equal 64, image.width
    assert_equal 64, image.height
    assert_equal 64 * 64 * 3, image.pixels.bytesize
  end

  def test_pixel_values_reasonable
    path = File.join(FIXTURE_DIR, "test_64x64.jpg")
    image = Pura::Jpeg.decode(path)

    r, g, b = image.pixel_at(32, 32)
    assert_in_delta 255, r, 30, "red channel should be near 255"
    assert_in_delta 0, g, 30, "green channel should be near 0"
    assert_in_delta 0, b, 30, "blue channel should be near 0"
  end

  def test_to_rgb_array
    path = File.join(FIXTURE_DIR, "test_64x64.jpg")
    image = Pura::Jpeg.decode(path)
    arr = image.to_rgb_array

    assert_equal 64 * 64, arr.size
    assert_equal 3, arr[0].size
  end

  def test_to_ppm
    path = File.join(FIXTURE_DIR, "test_64x64.jpg")
    image = Pura::Jpeg.decode(path)
    ppm = image.to_ppm

    assert ppm.start_with?("P6\n64 64\n255\n".b)
    assert_equal "P6\n64 64\n255\n".bytesize + (64 * 64 * 3), ppm.bytesize
  end

  def test_decode_matches_ffmpeg
    path = File.join(FIXTURE_DIR, "test_64x64.jpg")
    image = Pura::Jpeg.decode(path)

    ffmpeg_rgb = `ffmpeg -v quiet -i #{path} -f rawvideo -pix_fmt rgb24 pipe:1 2>/dev/null`
    return skip("ffmpeg not available") unless $CHILD_STATUS.success?

    assert_equal ffmpeg_rgb.bytesize, image.pixels.bytesize

    total_pixels = image.width * image.height
    mismatched = 0
    total_pixels.times do |i|
      offset = i * 3
      3.times do |c|
        diff = (image.pixels.getbyte(offset + c) - ffmpeg_rgb.getbyte(offset + c)).abs
        mismatched += 1 if diff > 2
      end
    end
    error_rate = mismatched.to_f / (total_pixels * 3)
    assert error_rate < 0.05, "too many pixel mismatches: #{(error_rate * 100).round(2)}%"
  end

  def test_image_class
    pixels = "\xFF\x00\x00".b * 4
    image = Pura::Jpeg::Image.new(2, 2, pixels)

    assert_equal 2, image.width
    assert_equal 2, image.height
    assert_equal [255, 0, 0], image.pixel_at(0, 0)
    assert_equal [255, 0, 0], image.pixel_at(1, 1)

    assert_raises(IndexError) { image.pixel_at(2, 0) }
    assert_raises(IndexError) { image.pixel_at(-1, 0) }
  end

  def test_image_wrong_pixel_size
    assert_raises(ArgumentError) do
      Pura::Jpeg::Image.new(2, 2, "\xFF\x00\x00".b)
    end
  end

  def test_not_a_jpeg
    assert_raises(Pura::Jpeg::DecodeError) do
      Pura::Jpeg.decode(__FILE__)
    end
  end

  def test_encoder_works
    pixels = "\xFF\x00\x00".b * (8 * 8)
    image = Pura::Jpeg::Image.new(8, 8, pixels)
    out_path = File.join(__dir__, "fixtures", "tmp_encoder_test.jpg")
    Pura::Jpeg.encode(image, out_path, quality: 85)
    assert File.exist?(out_path)
    data = File.binread(out_path)
    assert_equal 0xFF, data.getbyte(0)
    assert_equal 0xD8, data.getbyte(1)
  ensure
    File.delete(out_path) if out_path && File.exist?(out_path)
  end

  def test_version
    assert_match(/\d+\.\d+\.\d+/, Pura::Jpeg::VERSION)
  end
end

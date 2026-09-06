# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/pura-jpeg"

class TestBinaryInput < Minitest::Test
  def test_decode_binary_data_with_null_bytes
    path = File.join(__dir__, "fixtures", "test_64x64.jpg")
    data = File.binread(path)
    assert_includes data, "\0"
    assert_equal Pura::Jpeg.decode(path).pixels, Pura::Jpeg.decode(data).pixels
  end
end

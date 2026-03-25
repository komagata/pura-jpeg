# frozen_string_literal: true

require_relative "pura/jpeg/version"
require_relative "pura/jpeg/image"
require_relative "pura/jpeg/decoder"
require_relative "pura/jpeg/encoder"

module Pura
  module Jpeg
    def self.decode(input)
      Decoder.decode(input)
    end

    def self.encode(image, output_path, quality: 85, subsampling: :s420)
      Encoder.encode(image, output_path, quality: quality, subsampling: subsampling)
    end
  end
end

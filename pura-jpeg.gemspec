# frozen_string_literal: true

require_relative "lib/pura/jpeg/version"

Gem::Specification.new do |spec|
  spec.name = "pura-jpeg"
  spec.version = Pura::Jpeg::VERSION
  spec.authors = ["komagata"]
  spec.summary = "Pure Ruby JPEG decoder/encoder"
  spec.description = "A pure Ruby JPEG decoder and encoder with zero C extension dependencies. " \
                     "Supports Baseline JPEG with Huffman coding, IDCT, and YCbCr color conversion."
  spec.homepage = "https://github.com/komagata/pura-jpeg"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*.rb", "bin/*", "LICENSE", "README.md"]
  spec.bindir = "bin"
  spec.executables = ["pura-jpeg"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end

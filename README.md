# pura-jpeg

A pure Ruby JPEG decoder/encoder with zero C extension dependencies.

Part of the **pura-*** series — pure Ruby image codec gems.

## Features

- Baseline JPEG decoding and encoding (SOF0)
- Image resizing (bilinear / nearest-neighbor interpolation)
- Huffman coding, fast integer IDCT/FDCT, YCbCr ↔ RGB conversion
- 4:2:0, 4:2:2, and 4:4:4 chroma subsampling
- No native extensions, no FFI, no external dependencies
- CLI tool included

## Installation

```bash
gem install pura-jpeg
```

## Usage

```ruby
require "pura-jpeg"

# Decode
image = Pura::Jpeg.decode("photo.jpg")
image.width      #=> 1920
image.height     #=> 1080
image.pixels     #=> Raw RGB byte string

# Resize
thumb = image.resize(200, 200)
fitted = image.resize_fit(800, 600)   # maintain aspect ratio

# Encode
Pura::Jpeg.encode(thumb, "thumb.jpg", quality: 80)
```

## CLI

```bash
pura-jpeg decode input.jpg --info
pura-jpeg resize input.jpg --width 200 --height 200 --out thumb.jpg
pura-jpeg resize input.jpg --fit 800x600 --out fitted.jpg
```

## Why pure Ruby?

- **`gem install` and go** — no `brew install`, no `apt install`, no C compiler needed
- **Works everywhere Ruby works** — CRuby, ruby.wasm, mruby, JRuby, TruffleRuby
- **Edge/Wasm ready** — runs in Cloudflare Workers, browsers (via ruby.wasm), sandboxed environments where you can't install system libraries
- **Perfect for dev/CI** — no ImageMagick or libvips setup. `rails new` → image upload → it just works
- **Unix philosophy** — one format, one gem, composable

## Benchmark

Decode performance on a 400×400 baseline JPEG. Only pure implementations in scripting languages — no C extensions, no compiled languages.

| Decoder | Time | Language |
|---------|------|---------|
| jpeg-js (V8 JIT) | 36 ms | Pure JavaScript |
| jpeg-js (`--jitless`) | 143 ms | Pure JavaScript (interpreter) |
| **pura-jpeg** (+YJIT) | **188 ms** | **Pure Ruby** |
| pura-jpeg | 291 ms | Pure Ruby (interpreter) |
| ptjd | 5,448 ms | Pure Tcl |

Tested on Ruby 4.0.2 + YJIT. These are the only three pure scripting-language JPEG implementations that exist. Python, Perl, PHP, and Lua all rely on C extensions.

### Full pipeline (Ruby 4.0.2 + YJIT, 400×400)

| Operation | Time |
|-----------|------|
| Decode | 188 ms |
| Encode (quality 85) | 211 ms |
| Resize (400→200) | 37 ms |
| Resize + Encode | 74 ms |

## Related gems

| Gem | Format | Status |
|-----|--------|--------|
| **pura-jpeg** | JPEG | ✅ Available |
| pura-png | PNG | 🔜 Planned |
| pura-webp | WebP | 🔜 Planned |
| pura-gif | GIF | 🔜 Planned |

## License

MIT

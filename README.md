# pura-jpeg

A pure Ruby JPEG decoder/encoder without additional image-processing libraries.

Part of the **pura-*** series — pure Ruby image codec gems.

## Features

- Baseline JPEG decoding and encoding (SOF0)
- Image resizing (bilinear / nearest-neighbor interpolation)
- Huffman coding, fast integer IDCT/FDCT, YCbCr ↔ RGB conversion
- 4:2:0, 4:2:2, and 4:4:4 chroma subsampling
- No image-specific native extension or FFI dependency
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

## Benchmark

These historical measurements include ffmpeg process startup. They do not compare against an in-process C codec or establish Rails pipeline throughput.

400×400 image, Ruby 4.0.2 + YJIT.

### Decode

| Decoder | Time | Language |
|---------|------|----------|
| jpeg-js (V8 JIT) | 39 ms | Pure JavaScript |
| jpeg-js (`--jitless`) | 143 ms | Pure JavaScript (interpreter) |
| ffmpeg (C) | 55 ms | C |
| **pura-jpeg** | **304 ms** | **Pure Ruby** |
| ptjd | 5,448 ms | Pure Tcl |

### Encode

| Encoder | Time | vs ffmpeg |
|---------|------|-----------|
| ffmpeg (C) | 62 ms | — |
| **pura-jpeg** | **238 ms** | 3.8× slower |

### Full pipeline (decode → resize → encode)

| Operation | Time |
|-----------|------|
| Decode | 304 ms |
| Encode (quality 85) | 243 ms |
| Full pipeline | ~547 ms |


## Why pure Ruby?

- **`gem install` and go** — no `brew install`, no `apt install`, no C compiler needed
- **Perfect for dev/CI** — no ImageMagick or libvips setup. `rails new` → image upload → it just works
- **Unix philosophy** — one format, one gem, composable

## Related gems

| Gem | Format | Status |
|-----|--------|--------|
| **pura-jpeg** | JPEG | ✅ Available |
| [pura-png](https://github.com/komagata/pura-png) | PNG | ✅ Available |
| [pura-bmp](https://github.com/komagata/pura-bmp) | BMP | ✅ Available |
| [pura-gif](https://github.com/komagata/pura-gif) | GIF | ✅ Available |
| [pura-tiff](https://github.com/komagata/pura-tiff) | TIFF | ✅ Available |
| [pura-ico](https://github.com/komagata/pura-ico) | ICO | ✅ Available |
| [pura-webp](https://github.com/komagata/pura-webp) | WebP | ✅ Available |
| [pura-image](https://github.com/komagata/pura-image) | All formats | ✅ Available |

## Pixel model and limitations

Images contain 8-bit RGB pixels. Baseline JPEG only; progressive JPEG is unsupported. EXIF orientation and color profiles are not applied or retained. `decode` accepts a file path or a binary JPEG string.

`crop(x, y, width, height)` requires integer coordinates, positive dimensions, and a region entirely inside the image; invalid regions raise `ArgumentError`.

## License

MIT

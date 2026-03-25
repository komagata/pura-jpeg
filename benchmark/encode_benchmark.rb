# frozen_string_literal: true

require_relative "../lib/pura-jpeg"

module EncodeBenchmark
  def self.run(input)
    unless File.exist?(input)
      puts "Generating test image with ffmpeg..."
      unless generate_test_image(input)
        $stderr.puts "Error: could not generate test image. Provide an existing JPEG file."
        exit 1
      end
    end

    # Decode the input image first
    image = Pura::Jpeg.decode(input)
    puts "Benchmark: encoding #{image.width}x#{image.height} image"
    puts "=" * 60

    results = []

    # pura-jpeg encode
    results << bench("pura-jpeg") do
      out_path = "/tmp/pura-jpeg_bench_encode_#{$$}.jpg"
      Pura::Jpeg.encode(image, out_path, quality: 85)
      size = File.size(out_path)
      File.delete(out_path) if File.exist?(out_path)
      size
    end

    # ffmpeg encode (pipe raw RGB in, JPEG out)
    results << bench("ffmpeg") do
      out_path = "/tmp/pura-jpeg_bench_ffmpeg_#{$$}.jpg"
      IO.popen(
        ["ffmpeg", "-v", "quiet", "-y",
         "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", "#{image.width}x#{image.height}",
         "-i", "pipe:0",
         "-q:v", "2",
         out_path],
        "wb"
      ) do |io|
        io.write(image.pixels)
      end
      if $?.success? && File.exist?(out_path)
        size = File.size(out_path)
        File.delete(out_path)
        size
      else
        nil
      end
    end

    # Print results table
    puts
    puts format("%-15s %12s %15s %s", "Encoder", "Time (ms)", "Output (bytes)", "Status")
    puts "-" * 60
    results.each do |r|
      time_str = r[:time] ? format("%.2f", r[:time] * 1000) : "N/A"
      size_str = r[:output_size] ? r[:output_size].to_s : "N/A"
      status = r[:note] || "ok"
      puts format("%-15s %12s %15s %s", r[:name], time_str, size_str, status)
    end

    puts
    puts "Memory usage (current process): #{memory_usage_kb} KB"
  end

  def self.bench(name)
    GC.start
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output_size = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    if output_size
      { name: name, time: elapsed, output_size: output_size }
    else
      { name: name, time: nil, output_size: nil, note: "failed" }
    end
  rescue => e
    { name: name, time: nil, output_size: nil, note: "error: #{e.message}" }
  end

  def self.generate_test_image(path)
    return false unless command_exists?("ffmpeg")
    system(
      "ffmpeg", "-v", "quiet", "-y",
      "-f", "lavfi", "-i", "testsrc=duration=0.04:size=640x480:rate=1",
      "-frames:v", "1", "-q:v", "2", path
    )
    $?.success?
  end

  def self.memory_usage_kb
    if RUBY_PLATFORM =~ /darwin/
      `ps -o rss= -p #{$$}`.strip.to_i
    elsif File.exist?("/proc/#{$$}/status")
      File.read("/proc/#{$$}/status")[/VmRSS:\s+(\d+)/, 1].to_i
    else
      0
    end
  end

  def self.command_exists?(cmd)
    system("which #{cmd} > /dev/null 2>&1")
  end
end

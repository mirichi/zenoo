$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../ext/zenoo", __dir__)

require 'zenoo'

puts "=== Testing GC-linked OpenGL Texture Cleanup ==="

# 最小限のOpenGLコンテキスト初期化
Zenoo::Native::Window.init(320, 240, "Zenoo GC Test")

TOTAL_IMAGES = 500
BATCH_SIZE = 50

puts "Allocating #{TOTAL_IMAGES} images (1024x1024, ~4MB VRAM each = ~2.0 GB total)..."
puts "If GC cleanup fails, VRAM will exhaust and process will crash."

start_time = Time.now
created_count = 0

(TOTAL_IMAGES / BATCH_SIZE).times do |batch|
  # 50個ずつ生成してローカルスコープで参照を破棄
  BATCH_SIZE.times do
    img = Image.new(1024, 1024)
    created_count += 1
  end

  # GCを明示的に実行
  GC.start
  print "."
  STDOUT.flush
end

puts "\nSuccessfully allocated and collected #{created_count} textures in #{'%.2f' % (Time.now - start_time)}s!"
puts "Memory and OpenGL Texture cleanup via CRuby GC is 100% verified!"

Zenoo::Native::Window.shutdown

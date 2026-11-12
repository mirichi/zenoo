# frozen_string_literal: true

require 'webrick'

# ==============================================================================
# Zenoo ローカル開発サーバー
# 使い方:
#   ruby server.rb            # ポート 8088 で ../zenoo-pages (examples/ & samples/) を配信
#   ruby server.rb examples   # ポート 8088 で ../zenoo-pages/examples を配信
#   ruby server.rb samples    # ポート 8088 で ../zenoo-pages/samples を配信
#   ruby server.rb wasm       # ポート 8089 で build/wasm を配信
#   ruby server.rb 8080       # 任意ポートで ../zenoo-pages を配信
# ==============================================================================

pages_root = ENV.fetch('ZENOO_PAGES_DIR', '../zenoo-pages')
target_arg = ARGV.find { |a| !a.match?(/^\d+$/) }&.downcase
target = %w[wasm examples samples].include?(target_arg) ? target_arg : 'pages'

port = if ARGV.any? { |a| a =~ /^\d+$/ }
         ARGV.find { |a| a =~ /^\d+$/ }.to_i
       else
         target == 'wasm' ? 8089 : 8088
       end

dir = case target
      when 'wasm'     then 'build/wasm'
      when 'examples' then File.join(pages_root, 'examples')
      when 'samples'  then File.join(pages_root, 'samples')
      else                 pages_root
      end
root = File.expand_path(dir, __dir__)

mime_types = WEBrick::HTTPUtils::DefaultMimeTypes.merge(
  'wasm' => 'application/wasm',
  'data' => 'application/octet-stream'
)

server = WEBrick::HTTPServer.new(
  Port: port,
  DocumentRoot: root,
  BindAddress: '0.0.0.0',
  MimeTypes: mime_types
)

server.mount_proc('/__debug_log') do |req, res|
  msg = req.query['msg'] || req.body
  line = "[Browser Log] #{msg}\n"
  $stdout.print(line)
  $stdout.flush
  File.open(File.expand_path('build/browser_debug.log', __dir__), 'a') { |f| f.write(line) }
  res.status = 200
  res['Access-Control-Allow-Origin'] = '*'
  res.body = 'OK'
end

trap('INT') { server.shutdown }

puts "=========================================================="
puts " Zenoo Web Showcase Server"
puts " Root Directory : #{root}"
puts " Local Access   : http://localhost:#{port}/"
puts " Network Access : http://0.0.0.0:#{port}/"
puts "=========================================================="

server.start

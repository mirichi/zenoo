# frozen_string_literal: true

require 'webrick'

# ==============================================================================
# Zenoo ローカル開発サーバー
# 使い方:
#   ruby server.rb          # ポート 8088 で docs/ (全デモポータル) を配信
#   ruby server.rb wasm     # ポート 8089 で build/wasm を配信
#   ruby server.rb 8080     # 任意ポートで docs/ を配信
# ==============================================================================

target = ARGV.first&.downcase == 'wasm' ? 'wasm' : 'docs'
port = if ARGV.any? { |a| a =~ /^\d+$/ }
         ARGV.find { |a| a =~ /^\d+$/ }.to_i
       else
         target == 'wasm' ? 8089 : 8088
       end

dir = target == 'wasm' ? 'build/wasm' : 'docs'
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

trap('INT') { server.shutdown }

puts "=========================================================="
puts " Zenoo Web Showcase Server"
puts " Root Directory : #{root}"
puts " Local Access   : http://localhost:#{port}/"
puts " Network Access : http://0.0.0.0:#{port}/"
puts "=========================================================="

server.start

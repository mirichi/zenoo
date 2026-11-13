# category: Window
# title: draw_triangle の各機能
# desc: draw_triangle の単色塗りつぶし、頂点グラデーション、シームレス連結、半透明・加算ブレンドを確認するサンプル

require_relative '../lib/zenoo'

Window.loop do
  # 1. 単色塗りつぶし
  Window.draw_triangle(110, 60, 40, 180, 180, 180, color: [80, 120, 200])

  # 2. 頂点グラデーション (Symbol 配列)
  Window.draw_triangle(290, 60, 220, 180, 360, 180, color: [:red, :green, :blue])

  # 3. 頂点グラデーション (RGBA 配列)
  Window.draw_triangle(470, 60, 400, 180, 540, 180, color: [[255, 220, 80], [240, 80, 140], [80, 160, 255]])

  # 4. 2つの三角形を継ぎ目なく連結 (共有辺にシームが出ない)
  Window.draw_triangle(40, 240, 180, 240, 180, 360, color: [[80, 180, 255], [140, 240, 180], [80, 120, 220]])
  Window.draw_triangle(40, 240, 180, 360, 40, 360, color: [[80, 180, 255], [80, 120, 220], [180, 100, 220]])

  # 5. 半透明の重ね描画 (blend: :alpha)
  Window.draw_triangle(280, 240, 220, 360, 340, 360, color: [240, 80, 100, 160])
  Window.draw_triangle(320, 255, 260, 375, 380, 375, color: [80, 180, 255, 160])

  # 6. 加算ブレンド (blend: :add)
  Window.draw_triangle(470, 240, 410, 360, 530, 360, color: [200, 70, 50], blend: :add)
  Window.draw_triangle(510, 255, 450, 375, 570, 375, color: [50, 140, 220], blend: :add)
end

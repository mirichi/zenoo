# category: Window
# title: 基本図形の描画
# desc: draw_rect, draw_circle, draw_triangle, draw_line で基本図形を描画する最小サンプル

require_relative '../lib/zenoo'

Window.loop do
  Window.draw_rect(40, 40, 100, 100, color: [80, 120, 200])
  Window.draw_circle(240, 90, 50, color: [220, 80, 80])
  Window.draw_triangle(360, 40, 310, 140, 410, 140, color: [80, 180, 100])
  Window.draw_line(460, 140, 560, 40, color: [240, 200, 80])
end

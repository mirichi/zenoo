# category: Window
# title: draw_line の各機能
# desc: draw_line の線幅、端点形状 (cap)、ボーダー、シャドウ、加算ブレンドを単機能ずつ確認するサンプル

require_relative '../lib/zenoo'

Window.loop do
  # 1. 基本の細線 (width: 1)
  Window.draw_line(60, 70, 240, 70, color: :white)

  # 2. 太い線 (width: 16)
  Window.draw_line(60, 120, 240, 120, width: 16, color: [80, 140, 220])

  # 3. 斜め線 (SDF アンチエイリアス)
  Window.draw_line(320, 60, 500, 140, width: 8, color: [240, 200, 80])

  # 端点延長の比較用ガイド線 (x = 60, x = 240)
  Window.draw_line(60, 185, 60, 335, color: [70, 85, 110])
  Window.draw_line(240, 185, 240, 335, color: [70, 85, 110])

  # 4. cap: :butt (平端・始点終点ちょうど)
  Window.draw_line(60, 210, 240, 210, width: 18, cap: :butt, color: [80, 180, 120])

  # 5. cap: :round (丸端・太さの半分だけ両端が伸びる)
  Window.draw_line(60, 260, 240, 260, width: 18, cap: :round, color: [80, 180, 120])

  # 6. cap: :square (角端・太さの半分だけ両端が伸びる)
  Window.draw_line(60, 310, 240, 310, width: 18, cap: :square, color: [80, 180, 120])

  # 7. ボーダー付き線分
  Window.draw_line(320, 220, 520, 220, width: 20, cap: :round, color: [60, 120, 220], border_color: [240, 220, 100], border_width: 3)

  # 8. シャドウ / ネオン発光
  Window.draw_line(320, 295, 520, 295, width: 10, cap: :round, color: :white, shadow_blur: 20, shadow_color: [0, 220, 255, 220])

  # 9. 加算ブレンド (blend: :add で交差部分が明るく加算)
  Window.draw_line(600, 180, 740, 320, width: 16, cap: :round, color: [200, 60, 40], blend: :add)
  Window.draw_line(740, 180, 600, 320, width: 16, cap: :round, color: [40, 140, 220], blend: :add)
end

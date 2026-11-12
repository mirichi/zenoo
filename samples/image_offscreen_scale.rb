# category: Image
# title: オフスクリーン描画からの拡大表示
# desc: 160x90 の Image にオフスクリーン描画し、640x360 の画面へ 4倍拡大して描画するサンプル

require_relative '../lib/zenoo'

screen = Image.new(160, 90)
screen.texture_filter = :nearest
frame = 0

Window.loop(640, 360, "Zenoo - Offscreen Image Scale") do
  if Input.mouse_push?(:left)
    screen.texture_filter = (screen.texture_filter == :nearest ? :linear : :nearest)
  end

  frame += 1

  # 160x90 の小さな Image にオフスクリーン描画
  Image.render_to(screen) do
    Window.clear([20, 24, 34, 255])
    Window.draw_rect(0, 0, 160, 90, border_color: [70, 120, 200], border_width: 1)
    Window.draw_line(0, 45, 160, 45, color: [35, 45, 65])
    Window.draw_line(80, 0, 80, 90, color: [35, 45, 65])

    Window.draw_text(6, 6, "160x90 Image -> 4x", size: 12, color: :cyan)
    Window.draw_text(6, 22, "オフスクリーン拡大描画", size: 10, color: :white)
    Window.draw_text(6, 36, "Filter: :#{screen.texture_filter}", size: 9, color: [255, 220, 100])

    cx = 128 + Math.cos(frame * 0.04) * 14
    cy = 62 + Math.sin(frame * 0.04) * 10
    Window.draw_rect(10, 54, 24, 24, color: [80, 140, 220], radius: 4)
    Window.draw_circle(cx, cy, 10, color: [230, 90, 110])

    Window.draw_text(6, 76, "Click: :nearest / :linear", size: 7, color: [160, 170, 190])
  end

  # 640x360 の画面へ 4 倍拡大して描画
  Window.clear([0, 0, 0, 255])
  Window.draw(0, 0, screen, scale: 4.0, anchor: :top_left, pivot: :top_left)
end

# category: Window
# title: Camera によるスクロール・ズーム・シェイク
# desc: Camera のターゲット追従、ズーム、シェイク、ワールド/画面座標変換を確認する最小サンプル

require_relative '../lib/zenoo'

player = [640.0, 360.0]
cam = Camera.new(x: player[0], y: player[1], target: player, smooth_speed: 0.8, bounds: [0, 0, 2000, 1200])

Window.loop do
  player[0] = (player[0] + Input.x * 8.0).clamp(20.0, 1980.0)
  player[1] = (player[1] + Input.y * 8.0).clamp(20.0, 1180.0)
  cam.zoom = (cam.zoom + (Input.key_down?(:z) ? 0.02 : (Input.key_down?(:x) ? -0.02 : 0.0))).clamp(0.5, 2.5)
  cam.shake(15, 0.3) if Input.key_push?(:space) || Input.mouse_push?(:left)
  cam.update

  Window.camera(cam) do
    Window.draw_rect(0, 0, 2000, 1200, color: [24, 30, 44], border_color: [80, 140, 220], border_width: 4)
    for gx in 1...10
      Window.draw_line(gx * 200, 0, gx * 200, 1200, color: [45, 58, 82])
    end
    for gy in 1...6
      Window.draw_line(0, gy * 200, 2000, gy * 200, color: [45, 58, 82])
    end
    wx, wy = Window.to_world(Input.mouse_x, Input.mouse_y)
    Window.draw_circle(wx, wy, 12, border_color: :yellow, border_width: 2)
    Window.draw_rect(player[0] - 20, player[1] - 20, 40, 40, color: [80, 200, 140])
  end

  Window.draw_text(16, 16, "[Arrow] Move  [Z/X] Zoom (#{cam.zoom.round(2)})  [Space/Click] Shake  Pos: (#{cam.x.to_i}, #{cam.y.to_i})", size: 16)
end

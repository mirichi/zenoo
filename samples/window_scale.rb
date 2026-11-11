# category: Window
# title: 解像度とスケーリング
# desc: 仮想解像度・Window.scale・dpi_scale・viewport_scale・scale_mode の動作を確認するサンプル

require_relative '../lib/zenoo'

scales = [0.5, 1.0, 1.5, 2.0]
scale_idx = 1

Window.loop(640, 360, "Zenoo - Window.scale", scale: scales[scale_idx]) do
  if Input.mouse_push?(:left)
    scale_idx = (scale_idx + 1) % scales.length
    Window.scale = scales[scale_idx]
  end

  if Input.key_push?(:m)
    Window.scale_mode = (Window.scale_mode == :fit ? :integer : :fit)
  end

  win_w, win_h = Window.window_size

  # 仮想解像度の外枠と中央十字
  Window.draw_rect(0, 0, Window.width, Window.height, border_color: [80, 140, 220], border_width: 2)
  Window.draw_line(0, Window.height / 2, Window.width, Window.height / 2, color: [50, 70, 100])
  Window.draw_line(Window.width / 2, 0, Window.width / 2, Window.height, color: [50, 70, 100])

  # 各種サイズ・倍率の表示
  Window.draw_text(24, 24, "Virtual Size   : #{Window.width} x #{Window.height}", size: 18)
  Window.draw_text(24, 52, "Window Size    : #{win_w} x #{win_h}", size: 18)
  Window.draw_text(24, 80, "Window.scale   : #{Window.scale.round(2)}", size: 18, color: :cyan)
  Window.draw_text(24, 108, "dpi_scale      : #{Window.dpi_scale.round(2)}", size: 18, color: :yellow)
  Window.draw_text(24, 136, "viewport_scale : #{Window.viewport_scale.round(2)}", size: 18, color: [120, 240, 140])
  Window.draw_text(24, 164, "scale_mode     : #{Window.scale_mode}", size: 18)

  Window.draw_text(24, 220, "Click           : Change scale (0.5 / 1.0 / 1.5 / 2.0)", size: 15, color: [180, 190, 210])
  Window.draw_text(24, 244, "[M]             : Toggle scale_mode (:fit / :integer)", size: 15, color: [180, 190, 210])

  # マウスカーソル位置（仮想座標へ自動変換される）
  Window.draw_circle(Input.mouse_x, Input.mouse_y, 8, color: [255, 220, 80])
end

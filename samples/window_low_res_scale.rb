# category: Window
# title: 極小解像度からの拡大描画
# desc: 160x90 の小さな仮想画面に描いた文字や図形を scale: 4 で拡大描画するサンプル

require_relative '../lib/zenoo'

scales = [2.0, 4.0, 6.0]
scale_idx = 1
frame = 0

Window.loop(160, 90, "Zenoo - Low Res Scale", scale: scales[scale_idx]) do
  if Input.mouse_push?(:left)
    scale_idx = (scale_idx + 1) % scales.length
    Window.scale = scales[scale_idx]
  end

  frame += 1

  # 160x90 仮想画面の外枠と背景グリッド
  Window.draw_rect(0, 0, Window.width, Window.height, border_color: [70, 120, 200], border_width: 1)
  Window.draw_line(0, 45, 160, 45, color: [35, 45, 65])
  Window.draw_line(80, 0, 80, 90, color: [35, 45, 65])

  # 小さな仮想画面上に文字を描画（拡大しても SDF で滑らかに表示される）
  Window.draw_text(6, 6, "160x90 -> #{Window.scale.to_i}x", size: 12, color: :cyan)
  Window.draw_text(6, 22, "極小画面からの拡大描画", size: 10, color: :white)
  Window.draw_text(6, 36, "SDF Text stays sharp!", size: 8, color: [255, 220, 100])

  # 図形と動くアイコン
  cx = 128 + Math.cos(frame * 0.04) * 14
  cy = 62 + Math.sin(frame * 0.04) * 10
  Window.draw_rect(10, 54, 24, 24, color: [80, 140, 220], radius: 4)
  Window.draw_circle(cx, cy, 10, color: [230, 90, 110])

  Window.draw_text(6, 76, "Click: scale (2x/4x/6x)", size: 7, color: [160, 170, 190])
end

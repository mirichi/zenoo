# category: Window
# title: draw_rect の各機能
# desc: draw_rect の角丸、ボーダー、シャドウ、回転、画像埋め込みを単機能ずつ確認するサンプル

require_relative '../lib/zenoo'

# チェック柄の Image を生成 (100x100)
checker = Image.new(100, 100)
Image.render_to(checker) do
  Window.clear([220, 225, 235])
  for gy in 0...5
    for gx in 0...5
      if (gx + gy).odd?
        Window.draw_rect(gx * 20, gy * 20, 20, 20, color: [150, 160, 180])
      end
    end
  end
end

Window.loop do
  # 1. 角丸矩形
  Window.draw_rect(40, 60, 100, 100, color: [80, 120, 200], radius: 20)

  # 2. ボーダー
  Window.draw_rect(180, 60, 100, 100, border_color: [240, 220, 100], border_width: 4)

  # 3. シャドウ
  Window.draw_rect(320, 60, 100, 100, color: [80, 120, 200], shadow_blur: 20, shadow_color: [0, 200, 255, 200])

  # 4. 回転描画
  Window.draw_rect(460, 60, 100, 100, color: [80, 120, 200], angle: 30)

  # 5. チェック状の Image を角丸矩形の中に描画
  Window.draw_rect(600, 60, 100, 100, radius: 20, image: checker)
end

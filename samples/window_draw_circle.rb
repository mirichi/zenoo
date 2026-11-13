# category: Window
# title: draw_circle の各機能
# desc: draw_circle の塗りつぶし、ボーダー、シャドウ、画像埋め込み、回転、楕円描画を単機能ずつ確認するサンプル

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
  # 1. 基本の円
  Window.draw_circle(90, 110, 50, color: [80, 120, 200])

  # 2. ボーダー
  Window.draw_circle(230, 110, 50, border_color: [240, 220, 100], border_width: 4)

  # 3. シャドウ
  Window.draw_circle(370, 110, 50, color: [80, 120, 200], shadow_blur: 20, shadow_color: [0, 200, 255, 200])

  # 4. チェック状の Image を円の中に描画 (r: 50 等倍)
  Window.draw_circle(510, 110, 50, image: checker)

  # 5. テクスチャを貼った円を回転描画
  Window.draw_circle(650, 110, 50, angle: 30, image: checker)

  # 6. 描画半径を変えてテクスチャを拡大描画 (r: 50 -> 100)
  Window.draw_circle(850, 160, 100, image: checker)

  # 7. 楕円 (塗りつぶし + ボーダー)
  Window.draw_circle(130, 330, 80, 45, color: [80, 120, 200], border_color: [240, 220, 100], border_width: 3)

  # 8. 楕円 (シャドウ + 回転)
  Window.draw_circle(350, 330, 80, 45, color: [200, 90, 120], shadow_blur: 20, shadow_color: [255, 100, 150, 200], angle: -25)

  # 9. テクスチャを貼った楕円を回転描画
  Window.draw_circle(590, 330, 90, 50, angle: 25, image: checker)
end

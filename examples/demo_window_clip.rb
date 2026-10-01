# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Hardware Clipping & Viewport Demo (Window.clip)
# ==============================================================================
# - local: false => 元の画面座標系のまま矩形外をクリップ (Ebitengine SubImage 風)
# - local: true  => クリップ矩形の左上を (0, 0) とするローカル相対座標系 (UI ウィンドウ風)
# ==============================================================================

test_frames = ENV["ZENOO_TEST_FRAMES"] ? ENV["ZENOO_TEST_FRAMES"].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo - Hardware Clipping Demo (Window.clip)") do
  frame_count += 1
  break if test_frames > 0 && frame_count >= test_frames

  t = Window.time

  # 1. 背景クリア
  Window.clear([18, 20, 28, 255])

  # タイトル
  Window.draw_text(40, 30, "Zenoo Hardware Clipping (glScissor) & Dual Coordinate Systems", size: 26, color: :white)
  Window.draw_text(40, 65, "Demonstrating Global Mask (local: false) vs Local Viewport (local: true)", size: 16, color: [140, 160, 190, 255])

  # --------------------------------------------------------------------------
  # 左パネル: local: false (Ebitengine SubImage 風 / グローバル親座標系マスク)
  # --------------------------------------------------------------------------
  # 枠の描画
  Window.draw_card(60, 120, 540, 520, radius: 12.0, color: [26, 30, 42, 255], border_width: 2.0, border_color: [60, 80, 120, 255])
  Window.draw_text(80, 140, "1. Global Mask (local: false)", size: 20, color: :cyan)
  Window.draw_text(80, 170, "Coordinates remain global (screen space). Only clipped to rect.", size: 14, color: [170, 180, 200, 255])

  # クリップ領域 (80, 210, 500, 400)
  Window.draw_rect(80, 210, 500, 400, [15, 17, 24, 255]) # クリップ背景
  Window.clip(80, 210, 500, 400, local: false) do
    # ここでは座標系は画面全体のまま！
    # アニメーションする巨大な図形を描画 (クリップ枠外は自動で切れる)
    cx = 330 + Math.cos(t * 1.5) * 200
    cy = 410 + Math.sin(t * 1.2) * 150

    Window.draw_card(cx - 120, cy - 120, 240, 240, radius: 24.0, color: [240, 80, 110, 200])
    Window.draw_triangle(cx, cy - 150, cx - 140, cy + 120, cx + 140, cy + 120, [80, 200, 255, 180])

    # 画面全体を横断する対角線
    Window.draw_line(0, 0, 1280, 720, :yellow)

    Window.draw_text(100, 230, "World Object at (#{cx.round}, #{cy.round})", size: 16, color: :white)
  end

  # --------------------------------------------------------------------------
  # 右パネル: local: true (UI ウィンドウ / スクロール領域用ローカル相対座標系)
  # --------------------------------------------------------------------------
  # 枠の描画
  Window.draw_card(680, 120, 540, 520, radius: 12.0, color: [26, 30, 42, 255], border_width: 2.0, border_color: [60, 140, 100, 255])
  Window.draw_text(700, 140, "2. Local Viewport (local: true)", size: 20, color: [80, 230, 140, 255])
  Window.draw_text(700, 170, "Origin (0, 0) is top-left of the viewport. Ideal for UI & ScrollViews.", size: 14, color: [170, 180, 200, 255])

  # クリップ領域 (700, 210, 500, 400)
  Window.draw_rect(700, 210, 500, 400, [15, 17, 24, 255])
  Window.clip(700, 210, 500, 400, local: true) do
    # ここでの (0, 0) は画面上の (700, 210) に対応！
    scroll_y = (t * 60) % 600 # 自動スクロール

    # 仮想スクロールコンテンツを描画
    10.times do |i|
      item_y = i * 70 - scroll_y + 30
      Window.draw_card(20, item_y, 460, 55, radius: 8.0, color: [38, 44, 60, 255], border_width: 1.0, border_color: [70, 85, 115, 255])
      Window.draw_text(40, item_y + 15, "Scroll Item ##{i + 1} (Local Y: #{item_y.round})", size: 16, color: :white)
      Window.draw_rect(420, item_y + 12, 40, 30, (i.even? ? :cyan : :magenta))
    end

    # ネストされたサブビューポート (ローカル座標 150, 260 に 180x100 で配置)
    Window.draw_rect(150, 260, 180, 100, [10, 12, 16, 255])
    Window.clip(150, 260, 180, 100, local: true) do
      # ここでの (0, 0) はさらにネストされた領域の左上！
      Window.draw_card(0, 0, 180, 100, radius: 6.0, color: [45, 30, 60, 255], border_width: 1.5, border_color: :yellow)
      Window.draw_text(10, 10, "Nested View", size: 14, color: :yellow)
      Window.draw_triangle(20, 40, 160, 40, 90, 150, :cyan)
    end

    # クリップ内の要素で、Z値が一番高い手前バッジ (z: 20.0)
    Window.draw_card(10, 10, 140, 36, radius: 6.0, color: [230, 70, 110, 240], z: 20.0)
    Window.draw_text(18, 18, "Local Z: 20.0", size: 14, color: :white, z: 20.0)
  end

  # --------------------------------------------------------------------------
  # 3. クリップ内外を跨ぐグローバル Z ソートの検証バッジ (z: 10.0)
  # --------------------------------------------------------------------------
  # クリップの枠線・背景・通常アイテム(z: 0.0)よりも手前、かつ Local Z: 20.0 よりは奥に描画される
  badge_x = 620 + Math.sin(t * 2.0) * 40
  Window.draw_card(badge_x, 240, 150, 50, radius: 10.0, color: [240, 180, 40, 245], border_width: 2.0, border_color: :white, z: 10.0)
  Window.draw_text(badge_x + 12, 255, "Global Z: 10.0", size: 15, color: :black, z: 10.0)
end

puts "Clip demo executed successfully! (#{frame_count} frames)" if test_frames > 0

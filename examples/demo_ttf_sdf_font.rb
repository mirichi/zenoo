# frozen_string_literal: true
# ==============================================================================
# Zenoo - High Quality SDF Text & Font Rendering Demo
# Siv3D v0.8 スタイルの高品質テキスト描画 (SDFフォント、組版、アウトライン、シャドウ、文字アニメーション)
# ==============================================================================

require_relative '../lib/zenoo'

WINDOW_W = 1280
WINDOW_H = 720

def draw_header(fps)
  Window.draw_card(30, 20, 1220, 80, radius: 12.0, color: [24, 30, 48, 230], border: [1.0, [60, 80, 120, 180]], shadow: [10.0, [0, 0, 0, 100]])
  Window.draw_text(50, 36, "Zenoo Text Engine", size: 32, color: :white,
                   outline: { width: 1.2, color: [0, 200, 255, 180] },
                   shadow: { offset: [2, 2], blur: 3.0, color: [0, 0, 0, 200] }, font: Font::MPLUS)
  Window.draw_text(420, 48, "SDF Dynamic Atlas Rendering  |  Siv3D v0.8 Architecture", size: 16, color: [140, 170, 220], font: Font::MPLUS)
  Window.draw_text(1100, 48, "FPS: #{fps.round(1)}", size: 18, color: [100, 255, 160], font: Font::MPLUS)
end

def draw_styling_card(left_w)
  Window.draw_card(30, 120, left_w, 245, radius: 12.0, color: [24, 30, 48, 200], border: [1.0, [50, 65, 100]], shadow: [8.0, [0, 0, 0, 80]])
  Window.draw_text(50, 130, "[1] Text Styling & Effects (袋文字・ドロップシャドウ・視認性比較)", size: 18, color: :cyan, font: Font::MPLUS)

  # --- (A) 明るい背景サブカード (黒い影や太いフチが最高に映える) ---
  light_card_x = 45
  light_card_y = 158
  light_card_w = 365
  light_card_h = 195
  Window.draw_card(light_card_x, light_card_y, light_card_w, light_card_h, radius: 8.0, color: [240, 244, 252, 255], border: [1.0, [180, 200, 230]], shadow: [4.0, [0, 0, 0, 60]])
  Window.draw_text(light_card_x + 15, light_card_y + 8, "Light Background (黒い影・太フチ)", size: 14, color: [60, 80, 120], font: Font::MPLUS)

  Window.draw_text(light_card_x + 15, light_card_y + 32, "白抜き袋文字 (太フチ)", size: 23, color: :white,
                   outline: { width: 3.0, color: [20, 20, 30, 255] }, font: Font::MPLUS)
  Window.draw_text(light_card_x + 15, light_card_y + 68, "POPな袋文字 (黄+赤フチ)", size: 23, color: [255, 235, 50],
                   outline: { width: 3.0, color: [210, 20, 20, 255] }, font: Font::MPLUS)
  Window.draw_text(light_card_x + 15, light_card_y + 106, "クッキリ落ちる黒い影", size: 24, color: [20, 80, 190],
                   shadow: { offset: [3, 4], blur: 2.0, color: [0, 0, 0, 220] }, font: Font::MPLUS)
  Window.draw_text(light_card_x + 15, light_card_y + 146, "袋文字 ＋ 影の複合", size: 25, color: [255, 240, 80],
                   outline: { width: 2.5, color: [30, 30, 40, 255] },
                   shadow: { offset: [3, 4], blur: 2.5, color: [0, 0, 0, 190] }, font: Font::MPLUS)

  # --- (B) 暗い背景サブカード (発光シャドウ・白フチ袋文字) ---
  dark_card_x = 425
  dark_card_y = 158
  dark_card_w = 365
  dark_card_h = 195
  Window.draw_card(dark_card_x, dark_card_y, dark_card_w, dark_card_h, radius: 8.0, color: [14, 18, 28, 255], border: [1.0, [40, 55, 85]], shadow: [4.0, [0, 0, 0, 100]])
  Window.draw_text(dark_card_x + 15, dark_card_y + 8, "Dark Background (発光シャドウ・白フチ)", size: 14, color: [140, 170, 220], font: Font::MPLUS)

  Window.draw_text(dark_card_x + 15, dark_card_y + 32, "黒文字 ＋ 太い白フチ", size: 23, color: [30, 35, 50],
                   outline: { width: 3.0, color: :white }, font: Font::MPLUS)
  Window.draw_text(dark_card_x + 15, dark_card_y + 68, "ネオン袋文字 (水色+紺)", size: 23, color: [80, 240, 255],
                   outline: { width: 2.8, color: [0, 30, 70, 255] }, font: Font::MPLUS)
  Window.draw_text(dark_card_x + 15, dark_card_y + 106, "ネオン発光 (Cyan Glow)", size: 24, color: :white,
                   shadow: { offset: [0, 0], blur: 5.0, color: [0, 220, 255, 240] }, font: Font::MPLUS)
  Window.draw_text(dark_card_x + 15, dark_card_y + 146, "ネオン発光 (Pink Glow)", size: 24, color: [255, 240, 250],
                   shadow: { offset: [0, 0], blur: 5.0, color: [255, 40, 160, 240] }, font: Font::MPLUS)
end

def draw_layout_card(left_w, layout)
  Window.draw_card(30, 380, left_w, 180, radius: 12.0, color: [24, 30, 48, 200], border: [1.0, [50, 65, 100]], shadow: [8.0, [0, 0, 0, 80]])
  Window.draw_text(50, 395, "[2] Immutable TextLayout (組版・自動折り返し・中央寄せ)", size: 18, color: :cyan, font: Font::MPLUS)
  Window.draw_text(60, 430, layout, color: [230, 235, 245],
                   shadow: { offset: [1, 1], blur: 1.5, color: [0, 0, 0, 140] })
end

def draw_wave_card(left_w, time)
  Window.draw_card(30, 580, left_w, 120, radius: 12.0, color: [24, 30, 48, 200], border: [1.0, [50, 65, 100]], shadow: [8.0, [0, 0, 0, 80]])
  Window.draw_text(50, 592, "[3] Per-Character Dynamic Animation (ブロック修飾 / 再生成ゼロ)", size: 18, color: :cyan, font: Font::MPLUS)

  wave_str = "Siv3D Style Dynamic Wave & Rainbow Effect! ★"
  Window.draw_text(60, 630, wave_str, size: 26, outline: { width: 1.0, color: :black }, font: Font::MPLUS) do |char|
    wave_offset = Math.sin(time * 5.0 + char.index * 0.35) * 8.0
    char.y += wave_offset
    hue = (time * 80.0 + char.index * 15.0) % 360.0
    char.color = Color.hsv(hue, 0.85, 1.0)
    if char.char == "★"
      char.scale = 1.2 + Math.sin(time * 8.0) * 0.25
    end
  end
end

def draw_atlas_card(right_x, right_w)
  Window.draw_card(right_x, 120, right_w, 140, radius: 12.0, color: [24, 30, 48, 200], border: [1.0, [50, 65, 100]], shadow: [8.0, [0, 0, 0, 80]])
  Window.draw_text(right_x + 20, 132, "Retro 8x8 Font (Font::SINCLAIR)", size: 16, color: :cyan, font: Font::MPLUS)
  Window.draw_text(right_x + 20, 158, "10 PRINT \"ZENOO 2D ENGINE\"\n20 LET SCORE = 1982\n30 GOTO 10", size: 15, color: [100, 255, 180], font: Font::SINCLAIR, shadow: { offset: [1, 1], blur: 1.5, color: [0, 0, 0, 200] })
  Window.draw_text(right_x + 20, 230, "Public Domain (Unlicense) 8x8 TTF", size: 12, color: [160, 180, 210], font: Font::SINCLAIR)

  Window.draw_card(right_x, 280, right_w, 420, radius: 12.0, color: [24, 30, 48, 200], border: [1.0, [50, 65, 100]], shadow: [8.0, [0, 0, 0, 80]])
  Window.draw_text(right_x + 20, 295, "Live SDF Texture Atlas (1024x1024)", size: 18, color: :cyan, font: Font::MPLUS)
  Window.draw_text(right_x + 20, 322, "文字が動的にラスタライズされてアトラスへ追加されます", size: 13, color: [150, 170, 200], font: Font::MPLUS)

  atlas = Font.atlas_image
  if atlas
    preview_size = 360.0
    px = right_x + 30
    py = 350.0
    Window.draw_rect(px - 2, py - 2, preview_size + 4, preview_size + 4, [40, 50, 70])
    Window.draw_card(px, py, preview_size, preview_size, radius: 4.0, image: atlas, color: :white)
  end
end

puts "=== [DEMO] Initializing Demo... ==="

left_w = 780
right_x = 830
right_w = 420
novel_text = "吾輩は猫である。名前はまだ無い。\nどこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。"
sample_layout = nil

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0
Window.loop(WINDOW_W, WINDOW_H, "Zenoo - High Quality SDF Text & Font Rendering Demo") do
  time = Window.time
  fps = Window.fps
  frame_count += 1
  if frame_count <= 3 || frame_count % 60 == 0
    puts "=== [DEMO] Loop Frame #{frame_count}, Time: #{time.round(2)}, FPS: #{fps.round(1)} ==="
  end

  sample_layout ||= TextLayout.new(novel_text, 20, 1.3, 720, :left, font: Font::MPLUS)

  Window.clear([16, 20, 32, 255])


  draw_header(fps)
  draw_styling_card(left_w)
  draw_layout_card(left_w, sample_layout)
  draw_wave_card(left_w, time)
  draw_atlas_card(right_x, right_w)

  if test_max > 0 && frame_count >= test_max
    puts "Font demo test completed successfully! (#{frame_count} frames)"
    break
  end
end

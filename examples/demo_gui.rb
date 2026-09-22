# frozen_string_literal: true

require_relative '../lib/zenoo'

# ====================================================
# カスタムレンダラー例 (ユーザーによる描画差し替えデモ)
# ====================================================
class RetroFlatRenderer < Zenoo::GUI::Renderer
  def initialize
    @col_normal  = Color.new(50, 50, 60)
    @col_hover   = Color.new(80, 80, 100)
    @col_active  = Color.new(120, 140, 180)
    @col_border  = Color.new(200, 200, 220)
    @col_accent  = Color.new(255, 200, 0)
    @col_white   = Color::WHITE
    @col_dark    = Color.new(20, 20, 25)
  end

  def draw_button(x, y, w, h, label, state, theme)
    bg = @col_normal
    bg = @col_hover if state == :hover
    bg = @col_active if state == :active

    # シンプルな矩形と枠線 (フラット・レトロ調)
    Window.draw_rect(x, y, w, h, bg)
    Window.draw_rect(x, y, w, 2.0, @col_border)
    Window.draw_rect(x, y + h - 2.0, w, 2.0, @col_border)
    Window.draw_rect(x, y, 2.0, h, @col_border)
    Window.draw_rect(x + w - 2.0, y, 2.0, h, @col_border)

    if label
      text_str = label.to_s
      text_len = text_str.length
      if text_len > 0
        f_size = theme.font_size.to_i
        f_size = 14 if f_size <= 0

        text_w = text_len.to_f * f_size.to_f
        pad_x = 12.0
        avail_w = w.to_f - pad_x * 2.0
        if avail_w > 8.0 && text_w > avail_w
          f_size = (avail_w / text_len.to_f).to_i
          f_size = 8 if f_size < 8
          text_w = text_len.to_f * f_size.to_f
        end

        tx = x.to_f + (w.to_f - text_w) / 2.0
        ty = y.to_f + (h.to_f - f_size.to_f) / 2.0
        Window.draw_text(tx, ty, text_str, font: Font::SINCLAIR, size: f_size, color: @col_white)
      end
    end
  end

  def draw_slider(x, y, w, h, label, value, min, max, state, theme)
    range = (max.to_f - min.to_f)
    range = 1.0 if range <= 0.0001
    ratio = (value.to_f - min.to_f) / range
    ratio = 0.0 if ratio < 0.0
    ratio = 1.0 if ratio > 1.0

    # ラベル (Sinclair 8x8 フォント)
    Window.draw_text(x, y, label.to_s, font: Font::SINCLAIR, size: 14, color: @col_white) if label

    track_y = y + 20.0
    track_h = 10.0
    # 背景
    Window.draw_rect(x, track_y, w, track_h, @col_dark)
    # 進行度
    Window.draw_rect(x, track_y, w * ratio, track_h, @col_accent)
    # つまみ
    knob_x = x + w * ratio - 5.0
    Window.draw_rect(knob_x, track_y - 3.0, 10.0, track_h + 6.0, @col_white)
  end

  def draw_label(x, y, text, size, color, theme)
    Window.draw_text(x, y, text.to_s, font: Font::SINCLAIR, size: (size || 16), color: (color || @col_white))
  end

  def hit_test_button(x, y, w, h, px, py, theme)
    px >= x && px <= (x + w) && py >= y && py <= (y + h)
  end

  def hit_test_slider(x, y, w, h, px, py, theme)
    px >= x && px <= (x + w) && py >= y && py <= (y + h)
  end
end

# ====================================================
# メインアプリケーション
# ====================================================
card_renderer = Zenoo::GUI::CardRenderer.new
flat_renderer = RetroFlatRenderer.new
using_custom = false

# GUI デモは 8x8 Sinclair フォントで精密にレイアウト調整されているため、テーマに SINCLAIR を設定
GUI.theme.font = Font::SINCLAIR

# GUI の状態変数
counter = 0
r_val = 20.0
g_val = 28.0
b_val = 40.0
radius_val = 12.0
slider_w = 360.0

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo Immediate Mode GUI Demo") do
  # 毎フレームの背景クリア (スライダーで調整した背景色)
  bg_color = Color.new(r_val.to_i, g_val.to_i, b_val.to_i)
  Window.clear(bg_color)

  # 左側パネル: GUI コントロール
  GUI.label("=== Zenoo GUI Demo ===", 40.0, 35.0, 18, Color::WHITE)
  GUI.label("FPS: #{Window.fps.to_i}", 40.0, 65.0, 14, Color.new(160, 170, 190))

  # --- ボタン群 (幅360pxに綺麗に整列) ---
  btn_half_w = 172.0
  if GUI.button("Count (+1)", 40.0, 110.0, btn_half_w, 42.0)
    counter += 1
  end

  if GUI.button("Reset (0)", 228.0, 110.0, btn_half_w, 42.0)
    counter = 0
  end

  # レンダラー差し替えボタン (幅360px)
  renderer_btn_text = using_custom ? "Style: Retro Flat -> Card" : "Style: Modern Card -> Flat"
  if GUI.button(renderer_btn_text, 40.0, 165.0, slider_w, 42.0)
    using_custom = !using_custom
    GUI.renderer = using_custom ? flat_renderer : card_renderer
  end

  GUI.label("Counter: #{counter}", 40.0, 225.0, 16, Color.new(0, 220, 255))

  # --- スライダー群 (幅360px以内に収まる見出し) ---
  GUI.label("--- Color & Style ---", 40.0, 265.0, 14, Color::WHITE)

  r_val = GUI.slider("Red Channel",   40.0, 295.0, slider_w, 40.0, r_val, 0.0, 255.0)
  g_val = GUI.slider("Green Channel", 40.0, 350.0, slider_w, 40.0, g_val, 0.0, 255.0)
  b_val = GUI.slider("Blue Channel",  40.0, 405.0, slider_w, 40.0, b_val, 0.0, 255.0)

  radius_val = GUI.slider("Corner Radius", 40.0, 460.0, slider_w, 40.0, radius_val, 0.0, 30.0)
  GUI.theme.corner_radius = radius_val.to_f

  # --- 右側: リアルタイム・プレビューカード ---
  preview_x = 440.0
  preview_y = 110.0
  preview_w = 780.0
  preview_h = 540.0

  Window.draw_card(
    preview_x, preview_y, preview_w, preview_h,
    radius: radius_val,
    color: Color.new(30, 34, 45, 240),
    border_width: 2.0,
    border_color: Color.new(0, 200, 255, 180),
    shadow_blur: 16.0,
    shadow_color: Color.new(0, 0, 0, 150)
  )

  GUI.label("Live Card Preview", preview_x + 30.0, preview_y + 30.0, 20, Color::WHITE)
  GUI.label("Values controlled via GUI sliders:", preview_x + 30.0, preview_y + 65.0, 14, Color.new(160, 170, 190))

  info_text1 = "Background RGB : (#{r_val.to_i}, #{g_val.to_i}, #{b_val.to_i})"
  info_text2 = "Corner Radius  : #{radius_val.to_i} px"
  info_text3 = "Active Renderer: #{using_custom ? "RetroFlatRenderer (Custom)" : "CardRenderer (Default)"}"
  GUI.label(info_text1, preview_x + 30.0, preview_y + 110.0, 14, Color.new(255, 180, 0))
  GUI.label(info_text2, preview_x + 30.0, preview_y + 138.0, 14, Color.new(0, 255, 180))
  GUI.label(info_text3, preview_x + 30.0, preview_y + 166.0, 14, Color.new(180, 150, 255))

  # プレビュー内部にミニカードを描画 (幅200, 高さ140)
  mini_x = preview_x + 30.0
  mini_y = preview_y + 210.0
  mini_w = 200.0
  mini_h = 140.0
  Window.draw_card(
    mini_x, mini_y, mini_w, mini_h,
    radius: radius_val,
    color: Color.new(r_val.to_i, g_val.to_i, b_val.to_i, 255),
    border_width: 1.5,
    border_color: Color::WHITE,
    shadow_blur: 8.0,
    shadow_color: Color.new(0, 0, 0, 160)
  )

  # ミニカード中央に完全センタリング (12文字 * 12px = 144px -> (200 - 144) / 2 = 28px)
  card_label_x = mini_x + (mini_w - 12.0 * 12.0) / 2.0
  card_label_y = mini_y + (mini_h - 12.0) / 2.0
  GUI.label("Dynamic Card", card_label_x, card_label_y, 12, Color::WHITE)

  # 自動テスト終了判定
  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "GUI demo test completed successfully! (#{frame_count} frames)"
      break
    end
  end
end

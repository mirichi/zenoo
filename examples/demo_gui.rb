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
    Window.draw_rect(x, y, w, h, color: bg, border_color: @col_border, border_width: 2.0)

    if label
      text_str = label.to_s
      if text_str.length > 0
        f_size = theme.font_size.to_i
        f_size = 14 if f_size <= 0
        f_font = theme.font || Font::MPLUS

        text_w = f_font.text_width(text_str, f_size)
        pad_x = 12.0
        avail_w = w.to_f - pad_x * 2.0
        if avail_w > 8.0 && text_w > avail_w
          ratio = avail_w / text_w
          f_size = (f_size * ratio).to_i
          f_size = 8 if f_size < 8
          text_w = f_font.text_width(text_str, f_size)
        end

        tx = x.to_f + (w.to_f - text_w) / 2.0
        ty = y.to_f + (h.to_f - f_size.to_f) / 2.0
        Window.draw_text(tx, ty, text_str, font: f_font, size: f_size, color: @col_white)
      end
    end
  end

  def draw_slider(x, y, w, h, label, value, min, max, state, theme)
    range = (max.to_f - min.to_f)
    range = 1.0 if range <= 0.0001
    ratio = (value.to_f - min.to_f) / range
    ratio = 0.0 if ratio < 0.0
    ratio = 1.0 if ratio > 1.0

    f_font = theme.font || Font::MPLUS
    Window.draw_text(x, y, label.to_s, font: f_font, size: 14, color: @col_white) if label

    track_y = y + 20.0
    track_h = 10.0
    # 背景
    Window.draw_rect(x, track_y, w, track_h, color: @col_dark)
    # 進行度
    Window.draw_rect(x, track_y, w * ratio, track_h, color: @col_accent)
    # つまみ
    knob_x = x + w * ratio - 5.0
    Window.draw_rect(knob_x, track_y - 3.0, 10.0, track_h + 6.0, color: @col_white)
  end

  def draw_label(x, y, text, size, color, theme)
    f_font = theme.font || Font::MPLUS
    Window.draw_text(x, y, text.to_s, font: f_font, size: (size || 16), color: (color || @col_white))
  end

  def draw_text_box(x, y, w, h, text, focused, cursor_pos, blink_on, theme)
    bg = focused ? @col_active : @col_normal
    border = focused ? @col_accent : @col_border

    Window.draw_rect(x, y, w, h, color: bg, border_color: border, border_width: 2.0)

    f_size = 14
    pad_x = 8.0
    ty = y + (h - f_size) / 2.0
    str = text.to_s
    font = theme.font || Font::MPLUS
    Window.draw_text(x + pad_x, ty, str, font: font, size: f_size, color: @col_white)

    if focused && blink_on
      sub_str = str[0...cursor_pos] || ""
      caret_x = x + pad_x + font.text_width(sub_str, f_size)
      Window.draw_rect(caret_x, ty, 2.0, f_size, color: @col_accent)
    end
  end

  def hit_test_button(x, y, w, h, px, py, theme)
    px >= x && px <= (x + w) && py >= y && py <= (y + h)
  end

  def hit_test_slider(x, y, w, h, px, py, theme)
    px >= x && px <= (x + w) && py >= y && py <= (y + h)
  end

  def hit_test_text_box(x, y, w, h, px, py, theme)
    px >= x && px <= (x + w) && py >= y && py <= (y + h)
  end

  # ----------------------------------------------------
  # 対角2隅カット (左上 & 右下 45度面取り) のクラシック・サイバーパネル描画
  # ----------------------------------------------------
  def draw_panel(x, y, w, h, title, theme, opts = {})
    rx = x.to_f
    ry = y.to_f
    rw = w.to_f
    rh = h.to_f

    # コーナー半径スライダーの値を「45度カットの切り落とし幅」にリアルタイム反映
    cut = (opts[:radius] || theme.corner_radius || 12.0).to_f
    cut = 0.0 if cut < 0.0
    max_cut = [rw * 0.45, rh * 0.45].min
    cut = max_cut if cut > max_cut

    bg_col     = opts[:color] || Color.new(24, 28, 36, 245)
    border_col = opts[:border_color] || @col_accent
    border_w   = (opts[:border_width] || 2.0).to_f

    # 1. 対角2隅カット (左上・右下) のパス
    Window.draw_path do |c|
      c.fill_style   = bg_col
      c.stroke_style = border_col
      c.line_width   = border_w

      # 頂点 (時計回り)
      c.move_to(rx + cut, ry)           # 左上カット開始
      c.line_to(rx + rw, ry)            # 右上 (直角)
      c.line_to(rx + rw, ry + rh - cut) # 右下カット開始
      c.line_to(rx + rw - cut, ry + rh) # 右下カット終了
      c.line_to(rx, ry + rh)            # 左下 (直角)
      c.line_to(rx, ry + cut)           # 左上カット終了
      c.close_path

      c.fill
      c.stroke if border_w > 0.0
    end

    # 2. タイトルがある場合は、サイバー・クラシック調のタイトルバーを描画
    if title && !title.to_s.empty?
      pad        = (opts[:padding] || 16.0).to_f
      f_font     = opts[:font] || theme.font || Font::MPLUS
      title_size = (opts[:title_size] || 20).to_i
      title_col  = opts[:title_color] || @col_white

      # タイトルバーの高さ
      bar_h = title_size.to_f + 14.0

      # タイトルバー背景 (左上が45度カットされた帯)
      Window.draw_path do |c|
        c.fill_style = Color.new(45, 55, 75, 220)
        c.move_to(rx + cut, ry)
        c.line_to(rx + rw, ry)
        c.line_to(rx + rw, ry + bar_h)
        c.line_to(rx, ry + bar_h)
        c.line_to(rx, ry + [cut, bar_h].min)
        c.close_path
        c.fill
      end

      # タイトルバー下のアクセント境界線
      Window.draw_rect(rx, ry + bar_h, rw, 1.5, color: border_col)

      # タイトル文字 (左上のカットに被らないよう配置)
      title_x = rx + [cut + 6.0, pad].max
      title_y = ry + (bar_h - title_size.to_f) / 2.0
      Window.draw_text(title_x, title_y, title.to_s, font: f_font, size: title_size, color: title_col)
    end
  end
end

# ====================================================
# メインアプリケーション
# ====================================================
card_renderer = Zenoo::GUI::CardRenderer.new
flat_renderer = RetroFlatRenderer.new
using_custom = false

# 日本語に対応した M+ 1p フォントをテーマに設定
GUI.theme.font = Font::MPLUS
GUI.theme.font_size = 18

# GUI の状態変数
counter = 0
r_val = 20.0
g_val = 28.0
b_val = 40.0
radius_val = 12.0
slider_w = 360.0
input_name = "Zenoo Developer"
input_message = "Rubyで2Dゲーム開発！"

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo Immediate Mode GUI Demo") do
  # 毎フレームの背景クリア (スライダーで調整した背景色)
  bg_color = Color.new(r_val.to_i, g_val.to_i, b_val.to_i)
  Window.clear(bg_color)

  # 起点カーソル位置
  GUI.cursor(30.0, 20.0)

  # 画面全体の2カラムレイアウト (GUI.row で2つのパネルを横並び)
  GUI.row(spacing: 30) do
    # ----------------------------------------------------
    # 左側: コントロールパネル (GUI.panel + 自動レイアウト)
    # ----------------------------------------------------
    GUI.panel("=== Zenoo GUI Demo ===", w: 380.0, h: 680.0) do
      GUI.label("FPS: #{Window.fps.to_i}", size: 16, color: Color.new(160, 170, 190))

      # --- ボタン群 (GUI.row で横並び) ---
      btn_half_w = 168.0
      GUI.row(spacing: 12) do
        counter += 1 if GUI.button("Count (+1)", w: btn_half_w, h: 46.0)
        counter = 0  if GUI.button("Reset (0)",  w: btn_half_w, h: 46.0)
      end

      # レンダラー差し替えボタン
      renderer_btn_text = using_custom ? "Style: Classic Chamfer -> Modern Card" : "Style: Modern Card -> Classic Chamfer"
      if GUI.button(renderer_btn_text, w: 348.0, h: 46.0)
        using_custom = !using_custom
        GUI.renderer = using_custom ? flat_renderer : card_renderer
      end

      GUI.label("Counter: #{counter}", size: 20, color: Color.new(0, 220, 255))

      # --- スライダー群 (自動縦並び) ---
      GUI.label("--- Color & Style ---", size: 18, color: Color::WHITE)

      r_val = GUI.slider("Red Channel",   r_val, 0.0, 255.0, w: 348.0, h: 42.0)
      g_val = GUI.slider("Green Channel", g_val, 0.0, 255.0, w: 348.0, h: 42.0)
      b_val = GUI.slider("Blue Channel",  b_val, 0.0, 255.0, w: 348.0, h: 42.0)

      radius_val = GUI.slider("Corner Radius", radius_val, 0.0, 30.0, w: 348.0, h: 42.0)
      GUI.theme.corner_radius = radius_val.to_f
    end

    # ----------------------------------------------------
    # 右側: リアルタイム・プレビューパネル (GUI.panel + 自動レイアウト)
    # ----------------------------------------------------
    GUI.panel("Live Card Preview", w: 810.0, h: 680.0,
              radius: radius_val,
              color: Color.new(30, 34, 45, 240),
              border_width: 2.0,
              border_color: Color.new(0, 200, 255, 180),
              shadow_blur: 16.0,
              shadow_color: Color.new(0, 0, 0, 150),
              padding: 24.0) do
      GUI.label("Values controlled via GUI sliders:", size: 16, color: Color.new(160, 170, 190))

      info_text1 = "Background RGB : (#{r_val.to_i}, #{g_val.to_i}, #{b_val.to_i})"
      info_text2 = "Corner Radius  : #{radius_val.to_i} px (#{using_custom ? "Chamfer Size" : "Round Radius"})"
      info_text3 = "Active Renderer: #{using_custom ? "RetroFlatRenderer (Classic Chamfer)" : "CardRenderer (Modern SDF Card)"}"
      GUI.label(info_text1, size: 18, color: Color.new(255, 180, 0))
      GUI.label(info_text2, size: 18, color: Color.new(0, 255, 180))
      GUI.label(info_text3, size: 18, color: Color.new(180, 150, 255))

      # プレビュー内部の動的ミニカード (ネストした panel)
      GUI.panel("Dynamic Card", w: 240.0, h: 110.0,
                radius: radius_val,
                color: Color.new(r_val.to_i, g_val.to_i, b_val.to_i, 255),
                border_width: 1.5,
                border_color: Color::WHITE,
                shadow_blur: 8.0,
                shadow_color: Color.new(0, 0, 0, 160),
                title_size: 16)

      # --- テキストボックス入力デモ ---
      GUI.label("--- Text Input (IMGUI TextBox) ---", size: 20, color: Color::WHITE)
      GUI.label("クリックでフォーカス、英数字・日本語入力、Backspace、左右キー移動対応:", size: 15, color: Color.new(160, 170, 190))

      GUI.row(spacing: 20) do
        input_name = GUI.text_box("Name", input_name, w: 230.0, h: 44.0)
        input_message = GUI.text_box("Message", input_message, w: 500.0, h: 44.0)
      end

      GUI.label("名前: #{input_name}", size: 18, color: Color.new(0, 255, 200))
      GUI.label("メッセージ: #{input_message}", size: 18, color: Color.new(255, 200, 80))
    end
  end

  # 自動テスト終了判定
  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "GUI demo test completed successfully! (#{frame_count} frames)"
      exit
    end
  end
end

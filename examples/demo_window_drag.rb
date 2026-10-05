# frozen_string_literal: true

require_relative '../lib/zenoo'

# 日本語フォントとテーマの設定
GUI.theme.font = Font::MPLUS
GUI.theme.font_size = 16

class WindowDemoApp
  attr_accessor :bg_r, :bg_g, :bg_b, :counter, :user_text, :desktop_click_count

  def initialize
    @bg_r = 25.0
    @bg_g = 30.0
    @bg_b = 42.0
    @counter = 0
    @user_text = "Zenoo Multi-Window"
    @desktop_click_count = 0
  end

  def draw_desktop
    # ----------------------------------------------------
    # 1. デスクトップ領域 (背景UI)
    # ウィンドウをこの上にドラッグすると、クリック貫通が防止されることを確認できます
    # ----------------------------------------------------
    GUI.cursor(30.0, 30.0)
    GUI.label("=== Zenoo Multi-Window Demo ===", size: 22, color: Color::WHITE)
    GUI.label("タイトルバーをドラッグしてウィンドウを移動できます。クリックしたウィンドウが最前面になります。", size: 15, color: Color.new(160, 180, 210))

    GUI.cursor(30.0, 100.0)
    GUI.row(spacing: 12) do
      if GUI.button("Desktop Button (+1)", w: 180.0, h: 42.0)
        @desktop_click_count += 1
      end
      GUI.label("Desktop Clicks: #{@desktop_click_count}", size: 18, color: Color.new(255, 200, 80))
    end
  end

  def draw_color_adjuster
    # ----------------------------------------------------
    # 2. ウィンドウ 1: Color Adjuster
    # ----------------------------------------------------
    GUI.window("Color Adjuster", x: 60.0, y: 180.0, w: 340.0, h: 320.0) do
      GUI.label("Adjust window background color:", size: 15, color: Color.new(170, 190, 220))

      @bg_r = GUI.slider("Red",   @bg_r, 10.0, 80.0, w: 300.0, h: 38.0)
      @bg_g = GUI.slider("Green", @bg_g, 10.0, 80.0, w: 300.0, h: 38.0)
      @bg_b = GUI.slider("Blue",  @bg_b, 10.0, 80.0, w: 300.0, h: 38.0)

      GUI.row(spacing: 10) do
        @counter += 1 if GUI.button("Counter (+1)", w: 145.0, h: 40.0)
        @counter = 0  if GUI.button("Reset (0)",   w: 145.0, h: 40.0)
      end
      GUI.label("Count: #{@counter}", size: 18, color: Color.new(0, 220, 255))
      nil
    end
  end

  def draw_system_inspector
    # ----------------------------------------------------
    # 3. ウィンドウ 2: System Inspector
    # ----------------------------------------------------
    GUI.window("System Inspector", x: 440.0, y: 140.0, w: 380.0, h: 380.0) do
      GUI.label("Performance & Focus Info:", size: 16, color: Color.new(0, 255, 200))
      GUI.label("FPS: #{Window.fps.to_i}", size: 16, color: Color::WHITE)

      active_title = GUI.active_window_id || "(None / Desktop)"
      hovered_title = GUI.hovered_window_id || "(Desktop)"
      GUI.label("Active Window : #{active_title}", size: 15, color: Color.new(255, 180, 0))
      GUI.label("Hovered Window: #{hovered_title}", size: 15, color: Color.new(150, 220, 255))

      GUI.label("--- Window Z-Layers ---", size: 15, color: Color.new(160, 170, 190))
      GUI.window_order.each do |wid|
        win = GUI.windows[wid]
        is_top = (wid == GUI.window_order.last)
        tag = is_top ? " [TOP]" : ""
        col = is_top ? Color.new(0, 255, 180) : Color.new(160, 170, 180)
        GUI.label(" - #{win.title}: Z=#{win.z.to_i}#{tag} at (#{win.x.to_i}, #{win.y.to_i})", size: 14, color: col)
      end

      GUI.label("--- Text Input ---", size: 15, color: Color::WHITE)
      @user_text = GUI.text_box("Input", @user_text, w: 340.0, h: 40.0)
      nil
    end
  end

  def draw_clipping_demo
    # ----------------------------------------------------
    # 4. ウィンドウ 3: Viewport & Clipping Demo
    # 枠外へはみ出た図形が Window.clip(local: true) でマスクされる様子を確認
    # ----------------------------------------------------
    GUI.window("Viewport & Clipping", x: 860.0, y: 220.0, w: 360.0, h: 360.0) do
      GUI.label("Hardware Cliping Test:", size: 16, color: Color.new(255, 150, 200))
      GUI.label("下の大きなカードは枠外でクリップされます", size: 13, color: Color.new(160, 170, 190))

      # 相対座標系 (0, 0) からの直接描画
      # ウィンドウ枠 (w: 360, h: 360) をあえて大きくはみ出すカードを描画
      Window.draw_rect(
        10.0, 60.0, 450.0, 240.0,
        radius: 16.0,
        color: Color.new(50, 40, 70, 220),
        border_width: 2.0,
        border_color: Color.new(255, 100, 180, 200),
        shadow_blur: 12.0
      )

      Window.draw_text(
        24.0, 80.0,
        "This card extends beyond window bounds!",
        size: 15,
        color: Color::WHITE
      )

      GUI.cursor(20.0, 160.0)
      if GUI.button("Clipped Button", w: 180.0, h: 40.0)
        puts "Clipped button clicked!"
      end
      nil
    end
  end

  def step_frame
    # 背景クリア
    bg_color = Color.new(@bg_r.to_i, @bg_g.to_i, @bg_b.to_i)
    Window.clear(bg_color)

    draw_desktop
    draw_color_adjuster
    draw_system_inspector
    draw_clipping_demo
  end
end

app = WindowDemoApp.new
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo GUI.window - Multi-Window Drag & Occlusion Demo") do
  app.step_frame

  # 自動テスト終了判定
  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "Multi-Window demo test completed successfully! (#{frame_count} frames)"
      exit 0
    end
  end
end

# frozen_string_literal: true

require_relative '../lib/zenoo'

# サンプル用状態変数
chk_sound    = true
chk_fullscreen = false
chk_vsync    = true
radio_quality = 1 # 0: Low, 1: Medium, 2: High
tab_index    = 0
spin_count   = 5
spin_volume  = 80
spin_scale   = 1.25

dropdown_items = ["Linear Filtering", "Nearest Neighbor", "Bicubic Smooth", "CRT Shader"]
selected_dropdown = 0

list_items = [
  "Warrior (HP: 120, ATK: 15)",
  "Mage (HP: 70, ATK: 28)",
  "Rogue (HP: 85, ATK: 22)",
  "Paladin (HP: 140, ATK: 12)",
  "Archer (HP: 80, ATK: 20)",
  "Berserker (HP: 100, ATK: 25)",
  "Cleric (HP: 90, ATK: 10)",
  "Assassin (HP: 75, ATK: 30)"
]
selected_hero = 0

scrollbar_val = 0.0

# スライダー・テキストボックス用状態変数
slider_bgm   = 75.0
slider_sfx   = 90.0
slider_fov   = 90.0
slider_speed = 1.0
user_name    = "Player1"
user_status  = "Ready to play!"

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame = 0

Window.loop(1280, 720, "Zenoo - Extended GUI Widgets & Resizable Windows", msaa: 4) do
  Window.clear(Color.new(20, 22, 28))

  # 背景の軽い装飾グリッド
  grid_w = 40.0
  x = 0.0
  while x < 1280.0
    Window.draw_line(x, 0, x, 720, color: Color.new(28, 30, 38))
    x += grid_w
  end
  y = 0.0
  while y < 720.0
    Window.draw_line(0, y, 1280, y, color: Color.new(28, 30, 38))
    y += grid_w
  end

  Window.draw_text(30.0, 20.0, "Zenoo GUI Extended Widgets Demo", size: 24, color: Color::WHITE)
  Window.draw_text(30.0, 52.0, "Drag the bottom-right corner of resizable windows to change their size.", size: 14, color: Color.new(160, 160, 175))

  # -------------------------------------------------------------------
  # ウィンドウ 1: コントロール全般 (Resizable: true, サイズ変更可能)
  # -------------------------------------------------------------------
  GUI.window("Controls Showcase [Resizable]", x: 40, y: 90, w: 420, h: 580, resizable: true, min_w: 320, min_h: 300) do |win|
    GUI.label("Window Size: #{win.w.to_i} x #{win.h.to_i} (Drag corner to resize)", size: 12, color: Color.new(140, 200, 255))
    GUI.spacer(4)

    # 1. タブ
    tab_index = GUI.tabs(["Settings", "Audio/Display", "Controls"], tab_index)
    GUI.spacer(10)

    case tab_index
    when 0
      GUI.label("=== Checkboxes ===", size: 15, color: Color.new(255, 200, 80))
      chk_sound      = GUI.checkbox("Enable Sound Effects", chk_sound)
      chk_fullscreen = GUI.checkbox("Fullscreen Mode (F11)", chk_fullscreen)
      chk_vsync      = GUI.checkbox("VSync (60 FPS Lock)", chk_vsync)

      GUI.spacer(10)
      GUI.divider

      GUI.label("=== Radio Buttons (Graphics Quality) ===", size: 15, color: Color.new(255, 200, 80))
      radio_quality = 0 if GUI.radio("Low Quality (Fastest)", radio_quality == 0)
      radio_quality = 1 if GUI.radio("Medium Quality (Balanced)", radio_quality == 1)
      radio_quality = 2 if GUI.radio("High Quality (Ultra)", radio_quality == 2)

      GUI.spacer(10)
      GUI.divider

      GUI.label("=== Spinners / SpinBoxes ===", size: 15, color: Color.new(255, 200, 80))
      spin_count  = GUI.spinner("Enemy Count", spin_count, min: 1, max: 50, step: 1)
      spin_volume = GUI.spinner("Master Vol", spin_volume, min: 0, max: 100, step: 5)
      spin_scale  = GUI.spinner("UI Scale", spin_scale, min: 0.5, max: 3.0, step: 0.25, format: "%.2fx")

    when 1
      GUI.label("=== Sliders (Audio Volumes) ===", size: 15, color: Color.new(255, 200, 80))
      slider_bgm = GUI.slider("BGM Vol", slider_bgm, 0.0, 100.0)
      slider_sfx = GUI.slider("SFX Vol", slider_sfx, 0.0, 100.0)

      GUI.spacer(10)
      GUI.divider

      GUI.label("=== Dropdown / ComboBox ===", size: 15, color: Color.new(255, 200, 80))
      GUI.label("Texture Filter Mode:", size: 13, color: Color.new(180, 180, 190))
      selected_dropdown = GUI.dropdown("filter_dropdown", selected_dropdown, dropdown_items)

      GUI.spacer(12)
      GUI.divider

      GUI.label("=== Standalone ScrollBar ===", size: 15, color: Color.new(255, 200, 80))
      GUI.label("Scroll Value: #{scrollbar_val.round(1)} / 200.0", size: 13, color: Color.new(180, 180, 190))
      scrollbar_val = GUI.scrollbar(scrollbar_val, 300.0, 100.0, w: 14.0, h: 140.0)

    when 2
      GUI.label("=== Keyboard Bindings ===", size: 15, color: Color.new(255, 200, 80))
      GUI.label("Move: WASD / Arrow Keys", size: 13)
      GUI.label("Action / Shoot: Space / Left Click", size: 13)
      GUI.label("Pause: ESC", size: 13)
      GUI.label("Resize: Drag right-bottom triangle mark", size: 13, color: Color.new(120, 220, 160))
    end
  end

  # -------------------------------------------------------------------
  # ウィンドウ 2: リストボックス & スクロールビュー (Resizable: true)
  # -------------------------------------------------------------------
  GUI.window("Lists & ScrollView [Resizable]", x: 490, y: 90, w: 380, h: 580, resizable: true, min_w: 280, min_h: 260) do |win|
    GUI.label("=== ListBox (Scrollable with Wheel) ===", size: 15, color: Color.new(255, 200, 80))
    GUI.label("Selected: #{list_items[selected_hero]}", size: 13, color: Color.new(100, 220, 255))
    selected_hero = GUI.listbox("hero_select", selected_hero, list_items, h: 160.0)

    GUI.spacer(14)
    GUI.divider

    GUI.label("=== ScrollView Container ===", size: 15, color: Color.new(255, 200, 80))
    GUI.label("Scrollable sub-area with automatic scrollbar:", size: 12, color: Color.new(170, 170, 180))

    view_h = [win.h - 380.0, 120.0].max
    GUI.scroll_view("demo_scroll_view", h: view_h) do
      1.upto(12) do |idx|
        GUI.button("Scroll Item ##{idx}")
      end
    end
  end

  # -------------------------------------------------------------------
  # ウィンドウ 3: テキストボックス & スライダー (Non-Resizable)
  # -------------------------------------------------------------------
  GUI.window("Profile & Inputs [Fixed]", x: 900, y: 90, w: 340, h: 580, resizable: false) do
    GUI.label("=== Text Box Input ===", size: 15, color: Color.new(255, 200, 80))
    GUI.label("Player Name:", size: 13, color: Color.new(180, 180, 190))
    user_name = GUI.text_box("Name", user_name)

    GUI.spacer(6)
    GUI.label("Status Message:", size: 13, color: Color.new(180, 180, 190))
    user_status = GUI.text_box("Status", user_status)

    GUI.spacer(10)
    GUI.divider

    GUI.label("=== Gameplay Sliders ===", size: 15, color: Color.new(255, 200, 80))
    slider_fov   = GUI.slider("Camera FOV", slider_fov, 60.0, 120.0)
    slider_speed = GUI.slider("Game Speed", slider_speed, 0.25, 3.0)

    GUI.spacer(10)
    GUI.divider

    GUI.label("Input Status:", size: 14, color: Color.new(130, 220, 180))
    GUI.label("Name: #{user_name}", size: 13, color: Color::WHITE)
    GUI.label("FOV: #{slider_fov.to_i} deg / Speed: #{slider_speed.round(2)}x", size: 13, color: Color::WHITE)

    GUI.spacer(12)
    GUI.row(cols: 2, spacing: 8) do
      GUI.button("Save Profile")
      if GUI.button("Reset Defaults")
        user_name    = "Player1"
        user_status  = "Ready to play!"
        slider_fov   = 90.0
        slider_speed = 1.0
      end
    end
  end

  frame += 1
  break if test_max > 0 && frame >= test_max
end

puts "GUI extended widgets demo test completed successfully! (#{frame} frames)"

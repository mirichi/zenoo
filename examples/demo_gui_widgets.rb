# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo UI (Retained Mode / Sprite-based) Showcase Demo
# - Sprite を継承した保持モード UI ウィジェット群のデモ
# - Flexbox レイアウト (VBox / HBox / Panel / flex: 1 / gap / padding)
# - リサイズ・ドラッグ移動・最前面化に対応した UI::Window
# - ハードウェアシザークリッピングによる UI::ScrollView / UI::Table
# - ポーリング (if btn.clicked?) と コールバック (button { ... }) の両対応
# - Sprite ならではの Tween アニメーション連携 (ボタンのバウンス・回転演出)
# ==============================================================================

# プロシージャルなアイコン画像を生成 (ImageBox 用)
def create_badge_icon
  img = Image.new(48, 48)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    Window.draw_circle(24, 24, 20, color: [40, 120, 230], border_color: [140, 210, 255], border_width: 2.5)
    Window.draw_triangle(24, 10, 13, 34, 35, 34, color: [255, 225, 80])
    Window.draw_circle(24, 26, 5, color: :white)
  end
  img
end

badge_icon = create_badge_icon

# ルートステージ (画面全体の UI ツリー親)
stage = UI::Stage.new(theme: :relaxed)

# -------------------------------------------------------------------
# ウィンドウ 1: コントロール & タブ切り替え (Resizable: true)
# -------------------------------------------------------------------
win_controls = stage.window(
  "Controls & Tabs [Resizable]",
  35, 85, width: 410, height: 590,
  resizable: true, min_width: 320, min_height: 340
)

lbl_win_size = win_controls.label(
  "Window Size: 410 x 590 (Drag bottom-right corner)",
  size: 12, color: [130, 195, 255]
)

page_settings = nil
page_audio    = nil
page_tween    = nil

win_controls.tabs(["Settings", "Audio & Sliders", "Custom & Tween"], 0, height: 34) do |idx, _|
  page_settings.visible = (idx == 0)
  page_audio.visible    = (idx == 1)
  page_tween.visible    = (idx == 2)
end

# タブ 0: チェックボックス・スイッチ・ラジオ・スピナー
page_settings = win_controls.vbox(padding: 0, gap: 6, flex: 1) do |box|
  box.label("=== Checkbox & Switch ===", size: 15, color: [255, 205, 85])
  box.checkbox("Enable Sound Effects", true)
  box.switch("Fullscreen Mode (F11)", false)
  box.switch("VSync (60 FPS Lock)", true)

  box.divider

  box.label("=== Radio Buttons (Graphics Quality) ===", size: 15, color: [255, 205, 85])
  box.radio_button("Low Quality (Fastest)", false, group: :quality, value: :low)
  box.radio_button("Medium Quality (Balanced)", true, group: :quality, value: :medium)
  box.radio_button("High Quality (Ultra)", false, group: :quality, value: :high)

  box.divider

  box.label("=== Spinners ===", size: 15, color: [255, 205, 85])
  box.spinner("Enemy Count", 5, min: 1, max: 50, step: 1, label_width: 120)
  box.spinner("Master Vol", 80, min: 0, max: 100, step: 5, label_width: 120)
  box.spinner("UI Scale", 1.25, min: 0.5, max: 3.0, step: 0.25, format: "%.2fx", label_width: 120)
end

# タブ 1: スライダー・プログレスバー・ドロップダウン
sl_bgm   = nil
prog_bar = nil
page_audio = win_controls.vbox(padding: 0, gap: 10, flex: 1, visible: false) do |box|
  box.label("=== Sliders & ProgressBar ===", size: 15, color: [255, 205, 85])
  sl_bgm = box.stacked_slider("BGM Volume", 75.0, 0.0, 100.0, format: "%.0f", unit: "%")
  box.stacked_slider("SFX Volume", 90.0, 0.0, 100.0, format: "%.0f", unit: "%")

  box.label("Live Audio Level Meter:", size: 13, color: [180, 190, 210])
  prog_bar = box.progress_bar(75.0, 0.0, 100.0, height: 24, show_percentage: true)

  box.divider

  box.label("=== Dropdown (Popup Overlay) ===", size: 15, color: [255, 205, 85])
  box.label("Texture Filter Mode:", size: 13, color: [180, 190, 210])
  dropdown_items = ["Linear Filtering", "Nearest Neighbor", "Bicubic Smooth", "CRT Retro Shader"]
  box.dropdown(dropdown_items, 0)
end

sl_bgm.on_change do |val|
  prog_bar.value = val
end

# タブ 2: on_draw によるカスタム描画 & Tween 演出
btn_bounce = nil
btn_spin   = nil
page_tween = win_controls.vbox(padding: 0, gap: 10, flex: 1, visible: false) do |box|
  box.label("=== Custom on_draw & Tween ===", size: 15, color: [255, 205, 85])

  box.custom(height: 54, interactive: true) do |w|
    x = w.screen_left
    y = w.screen_top
    rw = w.screen_width
    rh = w.screen_height
    hov = w.hovered?
    bg_col = hov ? [45, 65, 95, 240] : [30, 40, 58, 220]
    bd_col = hov ? [120, 200, 255] : [70, 100, 150]
    Window.draw_rect(x, y, rw, rh, radius: 8.0, color: bg_col, border_width: 1.5, border_color: bd_col, camera: false)
    badge_col = hov ? [255, 220, 80] : [100, 220, 150]
    Window.draw_circle(x + 24.0, y + rh * 0.5, 12.0, color: badge_col, camera: false)
    Window.draw_text(x + 48.0, y + 10.0, "Custom Widget (via on_draw)", size: 14, color: :white, camera: false)
    Window.draw_text(x + 48.0, y + 28.0, hov ? "Hovered! (Interactive)" : "Hover me!", size: 12, color: [160, 180, 210], camera: false)
  end

  box.hbox(padding: 0, height: 60, gap: 12, align: :center) do |row|
    row.image_box(badge_icon, width: 52, height: 52, bg_color: [20, 26, 38], border_color: [70, 110, 170], border_width: 1.5, radius: 8)
    row.vbox(padding: 0, gap: 4, flex: 1) do |col|
      col.label("UI::ImageBox Widget", size: 15, color: :white)
      col.label("Supports :contain, :stretch, :center", size: 12, color: [160, 175, 200])
    end
  end

  btn_bounce = box.button("Click to Tween Bounce!", height: 38)
  btn_spin   = box.button("Click to Spin 360 deg!", height: 38)
end

btn_bounce.on_click do |btn|
  btn.kill_tweens
  btn.scale = 0.85
  btn.tween.to(0.45, scale: 1.0, ease: :elastic_out)
end

btn_spin.on_click do |btn|
  btn.kill_tweens
  btn.angle = 0.0
  btn.tween.to(0.5, angle: 360.0, ease: :cubic_out)
end

# -------------------------------------------------------------------
# ウィンドウ 2: テーブル & スクロールビュー (Resizable: true)
# -------------------------------------------------------------------
win_lists = stage.window(
  "Table & ScrollView [Resizable]",
  470, 85, width: 390, height: 590,
  resizable: true, min_width: 280, min_height: 300
)

hero_rows = [
  ["Warrior",  120, 15, true],
  ["Mage",      70, 28, true],
  ["Rogue",     85, 22, false],
  ["Paladin",  140, 12, true],
  ["Archer",    80, 20, true],
  ["Berserker", 100, 25, false],
  ["Cleric",    90, 10, true],
  ["Assassin",  75, 30, true]
]

win_lists.label("=== Table (Scrollable with Wheel) ===", size: 15, color: [255, 205, 85])
lbl_selected_hero = win_lists.label("Selected: #{hero_rows[0][0]} (HP: #{hero_rows[0][1]})", size: 13, color: [100, 220, 255])

win_lists.table([["Class", 110], ["HP", 60], ["ATK", 60], "Active"], hero_rows, 0, height: 155, item_height: 22) do |_idx, row|
  lbl_selected_hero.text = "Selected: #{row[0]} (HP: #{row[1]}, ATK: #{row[2]})"
end

win_lists.divider

win_lists.label("=== ScrollView Container (flex: 1) ===", size: 15, color: [255, 205, 85])
lbl_scroll_log = win_lists.label("Click any item inside ScrollView:", size: 12, color: [170, 180, 195])

win_lists.scroll_view(flex: 1, gap: 6, padding: 8) do |scroller|
  1.upto(14) do |idx|
    scroller.button("Scroll Action Item ##{idx}", height: 34) do
      lbl_scroll_log.text = "Clicked: Scroll Action Item ##{idx}!"
    end
  end
end

# -------------------------------------------------------------------
# ウィンドウ 3: テキスト入力 & フォーム (Fixed Size)
# -------------------------------------------------------------------
tb_name   = nil
tb_status = nil
sl_fov    = nil
sl_speed  = nil
lbl_summary_name = nil
lbl_summary_stat = nil
lbl_summary_cfg  = nil
btn_save  = nil
btn_reset = nil

stage.window(
  "Profile & Text Input [Fixed]",
  885, 85, width: 355, height: 590,
  resizable: false
) do |win|
  win.label("=== TextBox Input (IME & Clipboard) ===", size: 15, color: [255, 205, 85])
  win.label("Player Name:", size: 13, color: [180, 190, 205])
  tb_name = win.text_box("Player1", placeholder: "Enter name...")

  win.label("Status Message:", size: 13, color: [180, 190, 205])
  tb_status = win.text_box("Ready to adventure!", placeholder: "Enter status...")

  win.divider

  win.label("=== Gameplay Sliders ===", size: 15, color: [255, 205, 85])
  sl_fov   = win.stacked_slider("Camera FOV", 90.0, 60.0, 120.0, format: "%.0f", unit: " deg")
  sl_speed = win.stacked_slider("Game Speed", 1.0, 0.25, 3.0, unit: "x", format: "%.2f")

  win.divider

  win.label("=== Live Profile Summary ===", size: 14, color: [120, 225, 180])
  lbl_summary_name = win.label("Name: Player1", size: 13, color: :white)
  lbl_summary_stat = win.label("Status: Ready to adventure!", size: 13, color: [200, 210, 225])
  lbl_summary_cfg  = win.label("FOV: 90 deg / Speed: 1.00x", size: 13, color: [140, 200, 255])

  win.spacer(8, flex: 1)

  win.hbox(padding: 0, height: 38, gap: 10) do |row|
    btn_save  = row.button("Save Profile", flex: 1)
    btn_reset = row.button("Reset Defaults", flex: 1)
  end
end

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame = 0

Window.loop(1280, 720, "Zenoo - Sprite-based Retained Mode UI Showcase", msaa: 4) do
  Window.clear([18, 22, 30])

  grid_w = 40.0
  x = 0.0
  while x < 1280.0
    Window.draw_line(x, 0, x, 720, color: [26, 30, 40])
    x += grid_w
  end
  y = 0.0
  while y < 720.0
    Window.draw_line(0, y, 1280, y, color: [26, 30, 40])
    y += grid_w
  end

  Window.draw_text(35.0, 18.0, "Zenoo Retained-Mode UI (Sprite-based Widgets)", size: 24, color: :white)
  Window.draw_text(35.0, 48.0, "Drag windows to move/bring-to-front or resize from bottom-right.", size: 14, color: [160, 170, 190])

  stage.update

  lbl_win_size.text = "Window Size: #{win_controls.width.to_i} x #{win_controls.height.to_i} (Drag bottom-right corner)"
  lbl_summary_name.text = "Name: #{tb_name.text}"
  lbl_summary_stat.text = "Status: #{tb_status.text}"
  lbl_summary_cfg.text  = sprintf("FOV: %d deg / Speed: %.2fx", sl_fov.value.to_i, sl_speed.value)

  if btn_save.clicked?
    lbl_summary_stat.text = "Profile Saved!"
    btn_save.kill_tweens
    btn_save.scale = 0.92
    btn_save.tween.to(0.25, scale: 1.0, ease: :back_out)
  end

  if btn_reset.clicked?
    tb_name.text   = "Player1"
    tb_status.text = "Ready to adventure!"
    sl_fov.value   = 90.0
    sl_speed.value = 1.0
  end

  stage.draw

  frame += 1
  break if test_max > 0 && frame >= test_max
end

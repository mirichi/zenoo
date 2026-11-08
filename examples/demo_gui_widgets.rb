# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo UI (Retained Mode / Sprite-based) Showcase Demo
# - Sprite を継承した保持モード UI ウィジェット群のデモ
# - Flexbox レイアウト (VBox / HBox / flex: 1 / gap / padding)
# - リサイズ・ドラッグ移動・折りたたみ・最前面化に対応した UI::Window
# - ハードウェアシザークリッピングによる UI::ScrollView / UI::ListBox
# - ポーリング (if btn.clicked?) と コールバック (Button.new { ... }) の両対応
# - Sprite ならではの Tween アニメーション連携 (ボタン・ウィンドウのバウンス演出)
# ==============================================================================

# プロシージャルなアイコン画像を生成 (ImageBox & アイコン付きボタン用)
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
stage = UI::Stage.new

# -------------------------------------------------------------------
# ウィンドウ 1: コントロール & タブ切り替え (Resizable: true)
# -------------------------------------------------------------------
win_controls = UI::Window.new(
  "Controls & Tabs [Resizable]",
  35, 85, width: 410, height: 590,
  resizable: true, min_width: 320, min_height: 320,
  parent: stage
)

lbl_win_size = UI::Label.new(
  "Window Size: 410 x 590 (Drag bottom-right corner)",
  size: 12, color: Color.new(130, 195, 255),
  parent: win_controls
)

tabs = UI::Tabs.new(["Settings", "Audio & Sliders", "Tween & Sprite"], 0, height: 34, parent: win_controls)

# タブ 0: チェックボックス・ラジオ・スピナー
page_settings = UI::VBox.new(gap: 8, flex: 1, parent: win_controls) do |box|
  UI::Label.new("=== Checkboxes ===", size: 15, color: Color.new(255, 205, 85), parent: box)
  UI::Checkbox.new("Enable Sound Effects", true, parent: box)
  UI::Checkbox.new("Fullscreen Mode (F11)", false, parent: box)
  UI::Checkbox.new("VSync (60 FPS Lock)", true, parent: box)

  UI::Divider.new(height: 10, parent: box)

  UI::Label.new("=== Radio Buttons (Graphics Quality) ===", size: 15, color: Color.new(255, 205, 85), parent: box)
  UI::RadioButton.new("Low Quality (Fastest)", false, group: :quality, value: :low, parent: box)
  UI::RadioButton.new("Medium Quality (Balanced)", true, group: :quality, value: :medium, parent: box)
  UI::RadioButton.new("High Quality (Ultra)", false, group: :quality, value: :high, parent: box)

  UI::Divider.new(height: 10, parent: box)

  UI::Label.new("=== Spinners / SpinBoxes ===", size: 15, color: Color.new(255, 205, 85), parent: box)
  UI::Spinner.new("Enemy Count", 5, min: 1, max: 50, step: 1, parent: box)
  UI::Spinner.new("Master Vol", 80, min: 0, max: 100, step: 5, parent: box)
  UI::Spinner.new("UI Scale", 1.25, min: 0.5, max: 3.0, step: 0.25, format: "%.2fx", parent: box)
end

# タブ 1: スライダー・プログレスバー・ドロップダウン
page_audio = UI::VBox.new(gap: 10, flex: 1, parent: win_controls)
page_audio.visible = false

UI::Label.new("=== Sliders & ProgressBar ===", size: 15, color: Color.new(255, 205, 85), parent: page_audio)
sl_bgm = UI::Slider.new("BGM Volume", 75.0, 0.0, 100.0, step: 1.0, unit: "%", parent: page_audio)
sl_sfx = UI::Slider.new("SFX Volume", 90.0, 0.0, 100.0, step: 1.0, unit: "%", parent: page_audio)

UI::Label.new("Live Audio Level Meter:", size: 13, color: Color.new(180, 190, 210), parent: page_audio)
prog_bar = UI::ProgressBar.new(75.0, 0.0, 100.0, height: 22, show_percentage: true, parent: page_audio)

sl_bgm.on_change do |val|
  prog_bar.value = val
end

UI::Divider.new(height: 12, parent: page_audio)

UI::Label.new("=== Dropdown (Popup Overlay) ===", size: 15, color: Color.new(255, 205, 85), parent: page_audio)
UI::Label.new("Texture Filter Mode:", size: 13, color: Color.new(180, 190, 210), parent: page_audio)
dropdown_items = ["Linear Filtering", "Nearest Neighbor", "Bicubic Smooth", "CRT Retro Shader"]
UI::Dropdown.new(dropdown_items, 0, parent: page_audio)

# タブ 2: Sprite ならではの Tween 演出 & ImageBox
page_tween = UI::VBox.new(gap: 10, flex: 1, parent: win_controls)
page_tween.visible = false

UI::Label.new("=== Sprite & Tween Integration ===", size: 15, color: Color.new(255, 205, 85), parent: page_tween)
UI::Label.new("Every widget is a Zenoo::Sprite!", size: 13, color: Color.new(150, 220, 180), parent: page_tween)

# アイコンと説明の横並び (HBox)
UI::HBox.new(height: 64, gap: 12, align: :center, parent: page_tween) do |row|
  UI::ImageBox.new(badge_icon, width: 56, height: 56, bg_color: Color.new(20, 26, 38), border_color: Color.new(70, 110, 170), border_width: 1.5, radius: 8, parent: row)
  UI::VBox.new(gap: 4, flex: 1, parent: row) do |col|
    UI::Label.new("UI::ImageBox Widget", size: 15, color: Color::WHITE, parent: col)
    UI::Label.new("Supports :contain, :stretch, :center", size: 12, color: Color.new(160, 175, 200), parent: col)
  end
end

btn_bounce = UI::Button.new("Click to Tween Bounce!", height: 42, icon: badge_icon, parent: page_tween)
btn_bounce.on_click do |btn|
  btn.kill_tweens
  btn.scale = 0.85
  btn.tween.to(0.45, scale: 1.0, ease: :elastic_out)
end

btn_spin = UI::Button.new("Click to Spin 360 deg!", height: 42, parent: page_tween)
btn_spin.on_click do |btn|
  btn.kill_tweens
  btn.angle = 0.0
  btn.tween.to(0.5, angle: 360.0, ease: :cubic_out)
end

# タブ切り替え時の表示制御
tabs.on_change do |idx|
  page_settings.visible = (idx == 0)
  page_audio.visible    = (idx == 1)
  page_tween.visible    = (idx == 2)
  win_controls.mark_layout_dirty!
end

# -------------------------------------------------------------------
# ウィンドウ 2: リストボックス & スクロールビュー (Resizable: true)
# -------------------------------------------------------------------
win_lists = UI::Window.new(
  "Lists & ScrollView [Resizable]",
  470, 85, width: 390, height: 590,
  resizable: true, min_width: 280, min_height: 300,
  parent: stage
)

hero_items = [
  "Warrior (HP: 120, ATK: 15)",
  "Mage (HP: 70, ATK: 28)",
  "Rogue (HP: 85, ATK: 22)",
  "Paladin (HP: 140, ATK: 12)",
  "Archer (HP: 80, ATK: 20)",
  "Berserker (HP: 100, ATK: 25)",
  "Cleric (HP: 90, ATK: 10)",
  "Assassin (HP: 75, ATK: 30)"
]

UI::Label.new("=== ListBox (Scrollable with Wheel) ===", size: 15, color: Color.new(255, 205, 85), parent: win_lists)
lbl_selected_hero = UI::Label.new("Selected: #{hero_items[0]}", size: 13, color: Color.new(100, 220, 255), parent: win_lists)

listbox = UI::ListBox.new(hero_items, 0, height: 150, parent: win_lists)
listbox.on_change do |idx|
  lbl_selected_hero.text = "Selected: #{hero_items[idx]}"
end

UI::Divider.new(height: 12, parent: win_lists)

UI::Label.new("=== ScrollView Container (flex: 1) ===", size: 15, color: Color.new(255, 205, 85), parent: win_lists)
lbl_scroll_log = UI::Label.new("Click any item inside ScrollView:", size: 12, color: Color.new(170, 180, 195), parent: win_lists)

# flex: 1 を指定することで、ウィンドウをリサイズした際に残りの高さを自動で埋める！
scroll_view = UI::ScrollView.new(flex: 1, gap: 6, padding: 8, parent: win_lists)
1.upto(14) do |idx|
  UI::Button.new("Scroll Action Item ##{idx}", height: 34, parent: scroll_view) do
    lbl_scroll_log.text = "Clicked: Scroll Action Item ##{idx}!"
  end
end

# -------------------------------------------------------------------
# ウィンドウ 3: テキスト入力 & フォーム (Fixed Size)
# -------------------------------------------------------------------
win_profile = UI::Window.new(
  "Profile & Text Input [Fixed]",
  885, 85, width: 355, height: 590,
  resizable: false,
  parent: stage
)

UI::Label.new("=== TextBox Input (IME & Clipboard) ===", size: 15, color: Color.new(255, 205, 85), parent: win_profile)
UI::Label.new("Player Name:", size: 13, color: Color.new(180, 190, 205), parent: win_profile)
tb_name = UI::TextBox.new("Player1", placeholder: "Enter name...", parent: win_profile)

UI::Label.new("Status Message:", size: 13, color: Color.new(180, 190, 205), parent: win_profile)
tb_status = UI::TextBox.new("Ready to adventure!", placeholder: "Enter status...", parent: win_profile)

UI::Divider.new(height: 12, parent: win_profile)

UI::Label.new("=== Gameplay Sliders ===", size: 15, color: Color.new(255, 205, 85), parent: win_profile)
sl_fov   = UI::Slider.new("Camera FOV", 90.0, 60.0, 120.0, step: 1.0, unit: " deg", parent: win_profile)
sl_speed = UI::Slider.new("Game Speed", 1.0, 0.25, 3.0, step: 0.05, unit: "x", format: "%.2f", parent: win_profile)

UI::Divider.new(height: 12, parent: win_profile)

UI::Label.new("=== Live Profile Summary ===", size: 14, color: Color.new(120, 225, 180), parent: win_profile)
lbl_summary_name = UI::Label.new("Name: Player1", size: 13, color: Color::WHITE, parent: win_profile)
lbl_summary_stat = UI::Label.new("Status: Ready to adventure!", size: 13, color: Color.new(200, 210, 225), parent: win_profile)
lbl_summary_cfg  = UI::Label.new("FOV: 90 deg / Speed: 1.00x", size: 13, color: Color.new(140, 200, 255), parent: win_profile)

# 余白を埋めるフレキシブルスペーサー
UI::Spacer.new(8, flex: 1, parent: win_profile)

# 下部ボタン行 (HBox + flex: 1 で2等分)
btn_save  = nil
btn_reset = nil
UI::HBox.new(height: 38, gap: 10, parent: win_profile) do |row|
  btn_save  = UI::Button.new("Save Profile", flex: 1, parent: row)
  btn_reset = UI::Button.new("Reset Defaults", flex: 1, parent: row)
end

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame = 0

Window.loop(1280, 720, "Zenoo - Sprite-based Retained Mode UI Showcase", msaa: 4) do
  Window.clear(Color.new(18, 22, 30))

  # 背景グリッド
  grid_w = 40.0
  x = 0.0
  while x < 1280.0
    Window.draw_line(x, 0, x, 720, color: Color.new(26, 30, 40))
    x += grid_w
  end
  y = 0.0
  while y < 720.0
    Window.draw_line(0, y, 1280, y, color: Color.new(26, 30, 40))
    y += grid_w
  end

  Window.draw_text(35.0, 18.0, "Zenoo Retained-Mode UI (Sprite-based Widgets)", size: 24, color: Color::WHITE)
  Window.draw_text(35.0, 48.0, "Drag windows to move/bring-to-front, double-click title bar to collapse, or resize from bottom-right.", size: 14, color: Color.new(160, 170, 190))

  # 1. UI ツリー全体の更新 (レイアウト・ヒットテスト・入力ディスパッチ・Tween更新)
  stage.update

  # ポーリングスタイルでのイベント処理例 (ゲームループ内で直感的に記述可能)
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

  # 2. GUI ツリー全体の描画
  stage.draw

  frame += 1
  break if test_max > 0 && frame >= test_max
end

puts "Retained GUI showcase demo test completed successfully! (#{frame} frames)"

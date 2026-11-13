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
win_controls = stage.window(
  "Controls & Tabs [Resizable]",
  35, 85, width: 410, height: 590,
  resizable: true, min_width: 320, min_height: 320
)

lbl_win_size = win_controls.label(
  "Window Size: 410 x 590 (Drag bottom-right corner)",
  size: 12, color: Color.new(130, 195, 255)
)

tabs = win_controls.tabs(["Settings", "Audio & Sliders", "Custom & Tween"], 0, height: 34)

# タブ 0: チェックボックス・ラジオ・スピナー
page_settings = win_controls.vbox(gap: 8, flex: 1) do |box|
  box.label("=== Checkboxes ===", size: 15, color: Color.new(255, 205, 85))
  box.checkbox("Enable Sound Effects", true)
  box.checkbox("Fullscreen Mode (F11)", false)
  box.checkbox("VSync (60 FPS Lock)", true)

  box.divider(height: 10)

  box.label("=== Radio Buttons (Graphics Quality) ===", size: 15, color: Color.new(255, 205, 85))
  box.radio_button("Low Quality (Fastest)", false, group: :quality, value: :low)
  box.radio_button("Medium Quality (Balanced)", true, group: :quality, value: :medium)
  box.radio_button("High Quality (Ultra)", false, group: :quality, value: :high)

  box.divider(height: 10)

  box.label("=== Spinners / SpinBoxes ===", size: 15, color: Color.new(255, 205, 85))
  box.spinner("Enemy Count", 5, min: 1, max: 50, step: 1)
  box.spinner("Master Vol", 80, min: 0, max: 100, step: 5)
  box.spinner("UI Scale", 1.25, min: 0.5, max: 3.0, step: 0.25, format: "%.2fx")
end

# タブ 1: スライダー・プログレスバー・ドロップダウン
sl_bgm   = nil
prog_bar = nil
page_audio = win_controls.vbox(gap: 10, flex: 1) do |box|
  box.visible = false

  box.label("=== Sliders & ProgressBar ===", size: 15, color: Color.new(255, 205, 85))
  sl_bgm = box.slider("BGM Volume", 75.0, 0.0, 100.0, step: 1.0, unit: "%")
  box.slider("SFX Volume", 90.0, 0.0, 100.0, step: 1.0, unit: "%")

  box.label("Live Audio Level Meter:", size: 13, color: Color.new(180, 190, 210))
  prog_bar = box.progress_bar(75.0, 0.0, 100.0, height: 22, show_percentage: true)

  box.divider(height: 12)

  box.label("=== Dropdown (Popup Overlay) ===", size: 15, color: Color.new(255, 205, 85))
  box.label("Texture Filter Mode:", size: 13, color: Color.new(180, 190, 210))
  dropdown_items = ["Linear Filtering", "Nearest Neighbor", "Bicubic Smooth", "CRT Retro Shader"]
  box.dropdown(dropdown_items, 0)
end

sl_bgm.on_change do |val|
  prog_bar.value = val
end

# タブ 2: on_draw によるカスタム描画 & Tween 演出
btn_bounce = nil
btn_spin   = nil
page_tween = win_controls.vbox(gap: 10, flex: 1) do |box|
  box.visible = false

  box.label("=== Custom on_draw & Tween ===", size: 15, color: Color.new(255, 205, 85))

  # on_draw コールバックを使ったカスタム描画ウィジェットの例
  box.custom(height: 54, interactive: true) do |x, y, w, h, state|
    bg_col = state == :hover ? Color.new(45, 65, 95, 240) : Color.new(30, 40, 58, 220)
    bd_col = state == :hover ? Color.new(120, 200, 255) : Color.new(70, 100, 150)
    Window.draw_rect(x, y, w, h, radius: 8.0, color: bg_col, border_width: 1.5, border_color: bd_col)
    badge_col = state == :hover ? Color.new(255, 220, 80) : Color.new(100, 220, 150)
    Window.draw_circle(x + 24.0, y + h * 0.5, 12.0, color: badge_col)
    Window.draw_text(x + 48.0, y + 10.0, "Custom Widget (via on_draw)", size: 14, color: Color::WHITE)
    Window.draw_text(x + 48.0, y + 28.0, "State: #{state} (Hover me!)", size: 12, color: Color.new(160, 180, 210))
  end

  # アイコンと説明の横並び (HBox)
  box.hbox(height: 60, gap: 12, align: :center) do |row|
    row.image_box(badge_icon, width: 52, height: 52, bg_color: Color.new(20, 26, 38), border_color: Color.new(70, 110, 170), border_width: 1.5, radius: 8)
    row.vbox(gap: 4, flex: 1) do |col|
      col.label("UI::ImageBox Widget", size: 15, color: Color::WHITE)
      col.label("Supports :contain, :stretch, :center", size: 12, color: Color.new(160, 175, 200))
    end
  end

  btn_bounce = box.button("Click to Tween Bounce!", height: 38, icon: badge_icon)
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

# タブ切り替え時の表示制御
tabs.on_change do |idx|
  page_settings.visible = (idx == 0)
  page_audio.visible    = (idx == 1)
  page_tween.visible    = (idx == 2)
end

# -------------------------------------------------------------------
# ウィンドウ 2: リストボックス & スクロールビュー (Resizable: true)
# -------------------------------------------------------------------
win_lists = stage.window(
  "Lists & ScrollView [Resizable]",
  470, 85, width: 390, height: 590,
  resizable: true, min_width: 280, min_height: 300
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

win_lists.label("=== ListBox (Scrollable with Wheel) ===", size: 15, color: Color.new(255, 205, 85))
lbl_selected_hero = win_lists.label("Selected: #{hero_items[0]}", size: 13, color: Color.new(100, 220, 255))

listbox = win_lists.list_box(hero_items, 0, height: 150)
listbox.on_change do |idx|
  lbl_selected_hero.text = "Selected: #{hero_items[idx]}"
end

win_lists.divider(height: 12)

win_lists.label("=== ScrollView Container (flex: 1) ===", size: 15, color: Color.new(255, 205, 85))
lbl_scroll_log = win_lists.label("Click any item inside ScrollView:", size: 12, color: Color.new(170, 180, 195))

# flex: 1 を指定することで、ウィンドウをリサイズした際に残りの高さを自動で埋める！
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
  win.label("=== TextBox Input (IME & Clipboard) ===", size: 15, color: Color.new(255, 205, 85))
  win.label("Player Name:", size: 13, color: Color.new(180, 190, 205))
  tb_name = win.text_box("Player1", placeholder: "Enter name...")

  win.label("Status Message:", size: 13, color: Color.new(180, 190, 205))
  tb_status = win.text_box("Ready to adventure!", placeholder: "Enter status...")

  win.divider(height: 12)

  win.label("=== Gameplay Sliders ===", size: 15, color: Color.new(255, 205, 85))
  sl_fov   = win.slider("Camera FOV", 90.0, 60.0, 120.0, step: 1.0, unit: " deg")
  sl_speed = win.slider("Game Speed", 1.0, 0.25, 3.0, step: 0.05, unit: "x", format: "%.2f")

  win.divider(height: 12)

  win.label("=== Live Profile Summary ===", size: 14, color: Color.new(120, 225, 180))
  lbl_summary_name = win.label("Name: Player1", size: 13, color: Color::WHITE)
  lbl_summary_stat = win.label("Status: Ready to adventure!", size: 13, color: Color.new(200, 210, 225))
  lbl_summary_cfg  = win.label("FOV: 90 deg / Speed: 1.00x", size: 13, color: Color.new(140, 200, 255))

  # 余白を埋めるフレキシブルスペーサー
  win.spacer(8, flex: 1)

  # 下部ボタン行 (HBox + flex: 1 で2等分)
  win.hbox(height: 38, gap: 10) do |row|
    btn_save  = row.button("Save Profile", flex: 1)
    btn_reset = row.button("Reset Defaults", flex: 1)
  end
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

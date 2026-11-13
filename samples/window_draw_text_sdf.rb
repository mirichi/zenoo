# category: Window
# title: テキスト描画 (SDF ON / OFF 比較)
# desc: 文字サイズごとに sdf: true と sdf: false (直接ビットマップ) の描画品質を並べて比較するサンプル

require_relative '../lib/zenoo'

SIZES = [10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 44].freeze
TEXTS = [
  "漢字テスト Abc 0123",
  "永愛 薔薇 鷹 Abc 0123",
  "ABCDEFGHIJK abcdefghijk",
  "0123456789 +-*/=()!?"
].freeze
WEIGHTS = [0.0, -0.4, 0.5].freeze

dark_bg = true
text_idx = 0
weight_idx = 0

Window.loop(1280, 720, "Zenoo - draw_text SDF ON vs OFF") do
  dark_bg = !dark_bg if Input.key_push?(:b) || Input.mouse_push?(:left)
  text_idx = (text_idx + 1) % TEXTS.length if Input.key_push?(:t)
  weight_idx = (weight_idx + 1) % WEIGHTS.length if Input.key_push?(:w)

  bg_col = dark_bg ? [18, 22, 32] : [242, 244, 248]
  fg_col = dark_bg ? :white : [20, 24, 32]
  sub_col = dark_bg ? [150, 175, 210] : [80, 95, 120]
  line_col = dark_bg ? [45, 55, 78] : [205, 212, 224]
  hi_col = dark_bg ? [32, 42, 64] : [224, 232, 246]
  sdf_hdr_col = dark_bg ? [100, 220, 255] : [0, 110, 185]
  bmp_hdr_col = dark_bg ? [255, 200, 110] : [180, 95, 0]

  Window.clear(bg_col)

  cur_text = TEXTS[text_idx]
  cur_weight = WEIGHTS[weight_idx]

  # ヘッダー
  Window.draw_text(95, 20, "sdf: true (SDF)", size: 20, color: sdf_hdr_col)
  Window.draw_text(690, 20, "sdf: false (Bitmap)", size: 20, color: bmp_hdr_col)
  Window.draw_text(1040, 22, "weight: #{cur_weight}", size: 16, color: sub_col)
  Window.draw_line(20, 52, 1260, 52, color: line_col)
  Window.draw_line(665, 16, 665, 650, color: line_col)

  cur_y = 64.0
  i = 0
  while i < SIZES.length
    sz = SIZES[i]
    row_h = sz + 14.0

    # 現行の自動切替閾値 (36px) をハイライト表示
    if sz == 36
      Window.draw_rect(20, cur_y - 3.0, 1240, row_h - 4.0, radius: 4, color: hi_col)
    end

    Window.draw_text(28, cur_y + sz * 0.5, "#{sz}px", size: 13, color: sub_col, valign: :center)
    Window.draw_text(95, cur_y, cur_text, size: sz, color: fg_col, weight: cur_weight, sdf: true)
    Window.draw_text(690, cur_y, cur_text, size: sz, color: fg_col, weight: cur_weight, sdf: false)

    cur_y += row_h
    i += 1
  end

  # 操作ガイド
  Window.draw_line(20, 660, 1260, 660, color: line_col)
  Window.draw_text(28, 678, "[B / Click] Background: #{dark_bg ? 'Dark' : 'Light'}   [T] Change Text   [W] Weight (#{cur_weight})   (Highlight = 36px threshold)", size: 15, color: sub_col)
end

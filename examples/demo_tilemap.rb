# frozen_string_literal: true

require_relative '../lib/zenoo'

include Zenoo

# ==============================================================================
# Zenoo - Tilemap & Image.load_tiles デモ
#
# 特徴:
#   1. Image.load_tiles による画像の格子状一括分割 (DXRuby互換)
#   2. 2次元配列 (Ruby Array) を渡すだけのシンプルな Tilemap クラス
#   3. カメラ表示範囲のみを描画する自動カリング (Frustum Culling)
#   4. クリックによるタイルの動的変更 (tilemap[col, row] = id)
# ==============================================================================

# ----------------------------------------------------
# 1. デモ用タイルセットテクスチャの生成 (32x32 x 4種類 = 64x64)
# ----------------------------------------------------
def create_tileset_image
  tileset = Image.new(64, 64)
  Image.render_to(tileset) do
    Window.clear([0, 0, 0, 0])

    # タイル 0: 草原 (緑 + ドット柄)
    Window.draw_rect(0, 0, 32, 32, color: Color.new(50, 160, 60))
    Window.draw_rect(6, 6, 4, 4, color: Color.new(70, 190, 80))
    Window.draw_rect(20, 18, 4, 4, color: Color.new(70, 190, 80))

    # タイル 1: レンガ壁 (茶 + 目地)
    Window.draw_rect(32, 0, 32, 32, color: Color.new(160, 75, 45))
    Window.draw_rect(32, 15, 32, 2, color: Color.new(100, 40, 20))
    Window.draw_rect(48, 0, 2, 15, color: Color.new(100, 40, 20))
    Window.draw_rect(40, 17, 2, 15, color: Color.new(100, 40, 20))

    # タイル 2: 水辺 (青 + 波紋)
    Window.draw_rect(0, 32, 32, 32, color: Color.new(40, 110, 210))
    Window.draw_rect(6, 40, 16, 2, color: Color.new(80, 160, 255))
    Window.draw_rect(14, 52, 12, 2, color: Color.new(80, 160, 255))

    # タイル 3: 石畳の道 (灰 + パネル)
    Window.draw_rect(32, 32, 32, 32, color: Color.new(130, 135, 145))
    Window.draw_rect(34, 34, 28, 28, color: Color.new(110, 115, 125))
    Window.draw_rect(36, 36, 24, 24, color: Color.new(145, 150, 160))
  end
  tileset
end

# 32x32 ピクセル単位で Image 配列に分割
# (外部ファイルから読み込む場合は Image.load_tiles("tileset.png", 2, 2) または tile_width: 32, tile_height: 32 も可能)
tileset_img = create_tileset_image
tiles = tileset_img.slice_tiles(tile_width: 32, tile_height: 32)

# ----------------------------------------------------
# 2. マップ配列の定義 (20 列 x 14 行)
# ----------------------------------------------------
# 0: 草, 1: レンガ壁, 2: 水, 3: 石畳
map_data = [
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
  [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 3, 3, 3, 0, 1, 0, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 3, 0, 3, 0, 1, 0, 2, 2, 2, 2, 2, 0, 1, 1, 1, 0, 0, 1],
  [1, 0, 3, 0, 3, 0, 0, 0, 2, 2, 2, 2, 2, 0, 1, 0, 1, 0, 0, 1],
  [1, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 1, 0, 1, 0, 0, 1],
  [1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 3, 0, 0, 0, 1, 1, 1, 0, 0, 1],
  [1, 0, 0, 0, 3, 0, 0, 0, 0, 0, 3, 3, 3, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 2, 2, 3, 2, 2, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 2, 2, 3, 2, 2, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 0, 0, 1],
  [1, 0, 2, 2, 3, 2, 2, 0, 1, 1, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1],
  [1, 0, 0, 0, 3, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 3, 0, 0, 1],
  [1, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 1],
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
]

# マップ配置位置
map_x = 40.0
map_y = 50.0

tilemap = Tilemap.new(map_data, tiles, x: map_x, y: map_y)

selected_tile_id = 1
tile_names = ["Grass (0)", "Brick (1)", "Water (2)", "Pavement (3)"]

# 自動テスト用
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(960, 540, "Zenoo - Tilemap & Image.load_tiles Demo") do
  frame_count += 1
  break if test_max > 0 && frame_count >= test_max

  Window.draw_rect(0, 0, 960, 540, color: Color.new(24, 28, 36))

  # ----------------------------------------------------
  # マウス入力によるタイルの編集
  # ----------------------------------------------------
  mx, my = Input.mouse_pos
  hover_coords = tilemap.tile_coords(mx, my)

  if Input.mouse_pressed?(:left) && hover_coords
    col, row = hover_coords
    tilemap[col, row] = selected_tile_id
  elsif Input.mouse_pressed?(:right) && hover_coords
    col, row = hover_coords
    tilemap[col, row] = 0 # 消しゴム (草)
  end

  # ホイールまたはキーで配置タイルを選択
  if Input.mouse_wheel_y != 0
    selected_tile_id = (selected_tile_id + (Input.mouse_wheel_y > 0 ? 1 : -1)) % tiles.size
  end
  (0..3).each do |i|
    selected_tile_id = i if Input.key_push?(:"#{i}")
  end

  # ----------------------------------------------------
  # タイルマップの描画
  # ----------------------------------------------------
  # Window.draw_tilemap(tilemap) または tilemap.draw
  Window.draw_tilemap(tilemap)

  # ホバー枠の表示
  if hover_coords
    col, row = hover_coords
    hx = map_x + col * tilemap.tile_width
    hy = map_y + row * tilemap.tile_height
    Window.draw_rect(hx, hy, tilemap.tile_width, tilemap.tile_height,
                     border_color: Color.new(255, 255, 100), border_width: 2.0)
  end

  # ----------------------------------------------------
  # UI & パレット
  # ----------------------------------------------------
  Window.draw_text(40, 15, "Zenoo Tilemap Demo", size: 22, color: Color.new(240, 245, 255))
  Window.draw_text(300, 18, "Map: #{tilemap.cols}x#{tilemap.rows} (#{tilemap.width.to_i}x#{tilemap.height.to_i}px)", size: 15, color: Color.new(160, 180, 200))

  # パレットカード
  Window.draw_rect(710, 50, 220, 440, color: Color.new(32, 38, 50), radius: 8.0)
  Window.draw_text(730, 65, "■ Tile Palette", size: 18, color: Color.new(100, 200, 255))

  tiles.each_with_index do |t_img, idx|
    px = 730
    py = 110 + idx * 55
    is_sel = (idx == selected_tile_id)

    card_bg = is_sel ? Color.new(50, 70, 95) : Color.new(40, 46, 60)
    Window.draw_rect(px, py, 180, 45, color: card_bg, radius: 4.0,
                     border_color: is_sel ? Color.new(255, 220, 80) : nil, border_width: is_sel ? 2.0 : 0.0)

    # タイルアイコン
    Window.draw_image(px + 8, py + 6, t_img)
    Window.draw_text(px + 48, py + 14, tile_names[idx], size: 14, color: Color.new(240, 240, 240))

    # パレットクリックで選択
    if Input.mouse_push?(:left) && mx >= px && mx <= px + 180 && my >= py && my <= py + 45
      selected_tile_id = idx
    end
  end

  # 操作説明
  Window.draw_text(730, 360, "Controls:", size: 15, color: Color.new(200, 210, 220))
  Window.draw_text(730, 385, "• Left Click: Place Tile", size: 13, color: Color.new(170, 180, 190))
  Window.draw_text(730, 405, "• Right Click: Erase (Grass)", size: 13, color: Color.new(170, 180, 190))
  Window.draw_text(730, 425, "• Wheel / 0..3: Select Tile", size: 13, color: Color.new(170, 180, 190))

  hover_info = hover_coords ? "Hover: [#{hover_coords[0]}, #{hover_coords[1]}] ID: #{tilemap[hover_coords[0], hover_coords[1]]}" : "Hover: Outside"
  Window.draw_text(40, 505, hover_info, size: 15, color: Color.new(180, 200, 220))
end

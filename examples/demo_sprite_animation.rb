# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - 斜め4方向スプライト & 多層 Yソート Tilemap アクションデモ
#
# 特徴:
#   1. 「右下 (手前)」と「右上 (奥)」の【たった2アングル】のみで全方位をカバー！
#   2. 左方向は scale_x = -1.0 の左右反転により完全自動対応（アセット制作コスト半減）
#   3. 縦横2画面分 (1280x768, 40x24タイル) の広大なフィールドとカメラ追従
#   4. 行単位 Mesh + Zオーダーによる Tilemap (3段の石柱・2段の石碑・壁) とキャラの自動Yソート
#   5. 足元コライダーと Tilemap#resolve_collision による滑らかな壁ずり移動 (MTV)
# ==============================================================================

# 画面・仮想解像度・ワールド定数
VIRTUAL_WIDTH  = 640
VIRTUAL_HEIGHT = 360
WINDOW_WIDTH   = 1280
WINDOW_HEIGHT  = 720

TILE_SIZE    = 32
MAP_COLS     = 40
MAP_ROWS     = 24
WORLD_WIDTH  = MAP_COLS * TILE_SIZE # 1280
WORLD_HEIGHT = MAP_ROWS * TILE_SIZE # 768

# タイルID定義 (0..22)
T_GRASS           = 0  # 苔むした地面 (床)
T_PAVE            = 1  # 石畳の回廊 (床)
T_ACCENT          = 2  # 紋章石床 (床)
T_WALL            = 3  # 石レンガ壁 (1マス障害物)
T_CRATE           = 4  # 木箱 (1マス障害物)
T_PILLAR_TOP      = 5  # 3段石柱・上段 (root_offset: 2)
T_PILLAR_MID      = 6  # 3段石柱・中段 (root_offset: 1)
T_PILLAR_BOT      = 7  # 3段石柱・下段 (root_offset: 0, solid: true)
T_STELE_TOP       = 8  # 2段蒼石碑・上段 (root_offset: 1)
T_STELE_BOT       = 9  # 2段蒼石碑・下段 (root_offset: 0, solid: true)
T_WATER           = 10 # 水場・代表タイルID (4コマアニメ 10..13, solid: true)
T_BUSH            = 14 # 背の高い草・代表タイルID (4コマアニメ 14..17, Yソート対象)
T_HIGH_FLOOR      = 18 # 高台の上面石床 (明るい石畳)
T_CLIFF_SOUTH     = 19 # 高台の南側崖面 (正面の垂直段差壁)
T_CLIFF_EDGE      = 20 # 高台の北/東西フチ石 (rotate: 90/270 で東西に対応)
T_CLIFF_CORNER_NW = 21 # 高台の北西角フチ石 (flip_h: true で北東角に対応)
T_CLIFF_CORNER_SW = 22 # 高台の南西角崖面 (flip_h: true で南東角に対応)
TOTAL_TILE_COUNT  = T_CLIFF_CORNER_SW + 1 # 23

# 連結オブジェクトのパーツ定義 (上段から下段へ)
PILLAR_PARTS = [T_PILLAR_TOP, T_PILLAR_MID, T_PILLAR_BOT].freeze
STELE_PARTS  = [T_STELE_TOP,  T_STELE_BOT].freeze

# クォータービューの奥行きパースに合わせて縦移動を 80% に補正
Y_RATIO        = 0.8
PLATEAU_HEIGHT = 18.0 # 高台の標高 (18px)

# 高台範囲 [c_range, r_range] と、Window.clip による上面影クリッピング用矩形 [x, y, w, h]
PLATEAU_RANGES = [
  [24..29, 4..8],  # 北東の高台
  [10..15, 15..19] # 南西の高台
].freeze

PLATEAU_TOP_RECTS = PLATEAU_RANGES.map do |cr, rr|
  top_y = rr.begin * TILE_SIZE - PLATEAU_HEIGHT - 4.0
  bottom_y = (rr.end) * TILE_SIZE + 6.0
  [
    cr.begin * TILE_SIZE + 3.0,
    top_y,
    cr.size * TILE_SIZE - 6.0,
    bottom_y - top_y
  ]
end.freeze

SHADOW_COLOR_RGB = [10, 12, 18].freeze
SHADOW_Z         = -10.0
GROUND_Z         = -100.0
EFFECT_Z         = 2000.0
HP_BAR_Z         = 2100.0

# 描画カラーパレット (同一色の集約)
PAL = {
  curb:         [130, 148, 180, 255],
  curb_hi:      [180, 200, 230, 255],
  curb_rim:     [175, 195, 225, 255],
  curb_shadow:  [14,  18,  26,  165],
  curb_dark:    [52,  62,  82,  255],
  brick_base:   [56,  66,  86,  255],
  brick_line:   [38,  44,  58,  255],
  ground_shade: [12,  15,  22,  165]
}.freeze

# ==============================================================================
# タイルセット生成 (32x32 × 23種類 = 736x32) & マップ構築
# ==============================================================================
def draw_paver_blocks(ox, base_col, p1, p2, p3, p4)
  Zenoo::Window.draw_rect(ox, 0, 32, 32, color: base_col)
  Zenoo::Window.draw_rect(ox + 1,  1,  14, 14, radius: 2, color: p1)
  Zenoo::Window.draw_rect(ox + 17, 1,  14, 14, radius: 2, color: p2)
  Zenoo::Window.draw_rect(ox + 1,  17, 14, 14, radius: 2, color: p3)
  Zenoo::Window.draw_rect(ox + 17, 17, 14, 14, radius: 2, color: p4)
end

def draw_pillar_flutes(ox, y0, y1, outer: false)
  Zenoo::Window.draw_line(ox + 6,  y0, ox + 6,  y1, width: 2, color: [135, 148, 175, 255]) if outer
  Zenoo::Window.draw_line(ox + 10, y0, ox + 10, y1, width: 2, color: [82,  92,  114, 255])
  Zenoo::Window.draw_line(ox + 16, y0, ox + 16, y1, width: 2, color: [135, 148, 175, 255])
  Zenoo::Window.draw_line(ox + 22, y0, ox + 22, y1, width: 2, color: [75,  85,  106, 255])
  Zenoo::Window.draw_line(ox + 26, y0, ox + 26, y1, width: 2, color: [62,  70,  90,  255]) if outer
end

def create_dungeon_tileset
  tileset = Zenoo::Image.new(TILE_SIZE * TOTAL_TILE_COUNT, TILE_SIZE)
  Zenoo::Image.render_to(tileset) do
    Zenoo::Window.clear([0, 0, 0, 0])

    # 0: 苔むしたダーク草原床
    Zenoo::Window.draw_rect(0, 0, 32, 32, color: [30, 42, 46, 255])
    Zenoo::Window.draw_rect(4,  6,  4, 2, color: [40, 58, 58, 255])
    Zenoo::Window.draw_rect(20, 14, 5, 2, color: [36, 52, 54, 255])
    Zenoo::Window.draw_rect(10, 24, 4, 2, color: [42, 62, 60, 255])

    # 1: 石畳の道
    draw_paver_blocks(32, [46, 52, 66, 255], [58, 66, 82, 255], [54, 62, 78, 255], [52, 60, 76, 255], [60, 68, 84, 255])

    # 2: 紋章石床
    ox = 64
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [46, 52, 66, 255])
    Zenoo::Window.draw_rect(ox + 2, 2, 28, 28, radius: 3, color: [56, 64, 82, 255], border_width: 1, border_color: [80, 110, 145, 255])
    Zenoo::Window.draw_circle(ox + 16, 16, 6, color: [45, 85, 120, 255], border_width: 1, border_color: [90, 170, 220, 255])

    # 3: 石レンガ壁 (1マス障害物)
    ox = 96
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [40, 44, 56, 255])
    Zenoo::Window.draw_rect(ox + 1, 1,  30, 16, radius: 2, color: [92, 102, 124, 255], border_width: 1, border_color: [120, 132, 156, 255])
    Zenoo::Window.draw_rect(ox + 1, 17, 30, 14, color: [62, 70, 88, 255])
    Zenoo::Window.draw_line(ox + 1,  24, ox + 31, 24, width: 1, color: [42, 48, 62, 255])
    Zenoo::Window.draw_line(ox + 16, 17, ox + 16, 24, width: 1, color: [42, 48, 62, 255])
    Zenoo::Window.draw_line(ox + 9,  24, ox + 9,  31, width: 1, color: [42, 48, 62, 255])
    Zenoo::Window.draw_line(ox + 23, 24, ox + 23, 31, width: 1, color: [42, 48, 62, 255])

    # 4: 木箱・クレート (1マス障害物)
    ox = 128
    Zenoo::Window.draw_rect(ox + 2, 2, 28, 28, radius: 3, color: [110, 74, 42, 255], border_width: 2, border_color: [68, 44, 24, 255])
    Zenoo::Window.draw_rect(ox + 4, 4, 24, 12, radius: 2, color: [148, 102, 58, 255])
    Zenoo::Window.draw_line(ox + 5,  5, ox + 27, 27, width: 2, color: [88, 58, 32, 255])
    Zenoo::Window.draw_line(ox + 27, 5, ox + 5,  27, width: 2, color: [88, 58, 32, 255])
    Zenoo::Window.draw_rect(ox + 4, 4, 24, 24, radius: 2, color: :clear, border_width: 2, border_color: [165, 118, 70, 255])

    # 5: 3段石柱・上段 (柱頭 + 蒼クリスタル装飾)
    ox = 160
    Zenoo::Window.draw_rect(ox + 3, 6,  26, 10, radius: 2, color: [130, 142, 168, 255], border_width: 1, border_color: [170, 185, 210, 255])
    Zenoo::Window.draw_rect(ox + 5, 16, 22, 16, color: [105, 118, 142, 255])
    draw_pillar_flutes(ox, 16, 32)
    Zenoo::Window.draw_circle(ox + 16, 11, 4, color: [0, 210, 255, 255], border_width: 1, border_color: :white)

    # 6: 3段石柱・中段 (柱身・縦溝)
    ox = 192
    Zenoo::Window.draw_rect(ox + 5, 0, 22, 32, color: [105, 118, 142, 255])
    draw_pillar_flutes(ox, 0, 32, outer: true)

    # 7: 3段石柱・下段 (柱脚・台座)
    ox = 224
    Zenoo::Window.draw_ellipse(ox + 16, 27, 15, 5, color: [10, 12, 18, 140])
    Zenoo::Window.draw_rect(ox + 5, 0,  22, 16, color: [105, 118, 142, 255])
    draw_pillar_flutes(ox, 0, 16)
    Zenoo::Window.draw_rect(ox + 3, 14, 26, 8,  radius: 2, color: [120, 132, 158, 255], border_width: 1, border_color: [70, 80, 100, 255])
    Zenoo::Window.draw_rect(ox + 1, 20, 30, 10, radius: 2, color: [88,  98,  120, 255], border_width: 1, border_color: [55, 62, 80,  255])

    # 8: 2段蒼石碑・上段
    ox = 256
    Zenoo::Window.draw_triangle(ox + 16, 4, ox + 5, 32, ox + 27, 32, color: [[100, 220, 255, 255], [45, 110, 165, 255], [30, 80, 130, 255]])
    Zenoo::Window.draw_line(ox + 16, 6, ox + 16, 32, width: 2, color: [180, 245, 255, 220])

    # 9: 2段蒼石碑・下段 (台座)
    ox = 288
    Zenoo::Window.draw_ellipse(ox + 16, 27, 14, 5, color: [10, 12, 18, 140])
    Zenoo::Window.draw_rect(ox + 5, 0,  22, 18, color: [40, 95, 145, 255])
    Zenoo::Window.draw_line(ox + 16, 0, ox + 16, 16, width: 2, color: [160, 235, 255, 200])
    Zenoo::Window.draw_rect(ox + 2, 16, 28, 12, radius: 3, color: [78, 88, 110, 255], border_width: 1, border_color: [115, 128, 155, 255])

    # 10..13: 水場アニメーションタイル (4コマ)
    4.times do |f|
      ox = (10 + f) * 32
      phase = f * (Math::PI / 2.0)
      shift_x = (Math.sin(phase) * 3.0).round
      shift_y = (Math.cos(phase) * 1.5).round

      Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [18, 52, 86, 255])
      Zenoo::Window.draw_rect(ox + 1, 1, 30, 30, radius: 3, color: [24, 68, 110, 255])
      Zenoo::Window.draw_ellipse(ox + 11 + shift_x, 10 + shift_y, 8, 4, color: [34, 92, 145, 190])
      Zenoo::Window.draw_ellipse(ox + 21 - shift_x, 22 - shift_y, 9, 4, color: [30, 82, 132, 190])

      w1_x = ox + 5  + ((f * 4) % 10)
      w2_x = ox + 13 - ((f * 3) % 8)
      w3_x = ox + 7  + (((f + 2) * 4) % 10)
      Zenoo::Window.draw_line(w1_x, 7  + shift_y, w1_x + 11, 7  + shift_y, width: 2.0, cap: :round, color: [75, 175, 235, 220])
      Zenoo::Window.draw_line(w2_x, 16 - shift_y, w2_x + 12, 16 - shift_y, width: 2.0, cap: :round, color: [95, 195, 250, 230])
      Zenoo::Window.draw_line(w3_x, 25 + shift_y, w3_x + 10, 25 + shift_y, width: 2.0, cap: :round, color: [65, 160, 225, 210])

      glint_x = ox + (f.even? ? 10 + f * 3 : 22 - f * 2)
      glint_y = f < 2 ? 11 + f * 8 : 23 - (f - 2) * 8
      Zenoo::Window.draw_circle(glint_x, glint_y, 1.8, color: [200, 248, 255, 240])
    end

    # 14..17: 風に揺れる背の高い草タイル (4コマ)
    sway_offsets = [0, 3, 1, -2]
    dip_offsets  = [0, 1, 0, 1]
    base_dark = [18, 52, 50, 255]
    base_mid  = [28, 82, 74, 255]
    tip_back  = [52, 145, 118, 255]
    tip_front = [95, 220, 165, 255]
    tip_glow  = [155, 250, 195, 255]

    4.times do |f|
      ox = (14 + f) * 32
      sw = sway_offsets[f]
      dp = dip_offsets[f]

      Zenoo::Window.draw_ellipse(ox + 16, 29, 12, 3, color: [10, 14, 18, 130])
      Zenoo::Window.draw_triangle(ox + 7  + sw, 11 + dp, ox + 6,  29, ox + 12, 29, color: [tip_back, base_dark, base_dark])
      Zenoo::Window.draw_triangle(ox + 16 + sw, 7  + dp, ox + 12, 29, ox + 19, 29, color: [tip_back, base_dark, base_dark])
      Zenoo::Window.draw_triangle(ox + 25 + sw, 12 + dp, ox + 19, 29, ox + 26, 29, color: [tip_back, base_dark, base_dark])

      Zenoo::Window.draw_triangle(ox + 4  + (sw * 0.8).round, 15 + dp, ox + 5,  30, ox + 11, 30, color: [tip_front, base_mid, base_dark])
      Zenoo::Window.draw_triangle(ox + 12 + sw, 8  + dp, ox + 9,  30, ox + 16, 30, color: [tip_glow,  base_mid, base_dark])
      Zenoo::Window.draw_triangle(ox + 20 + sw, 9  + dp, ox + 15, 30, ox + 22, 30, color: [tip_front, base_mid, base_dark])
      Zenoo::Window.draw_triangle(ox + 27 + (sw * 1.1).round, 14 + dp, ox + 20, 30, ox + 27, 30, color: [tip_glow,  base_mid, base_dark])
      Zenoo::Window.draw_circle(ox + 12 + sw, 8 + dp, 1.5, color: [210, 255, 225, 240])
    end

    # 18: 高台の上面石床
    draw_paver_blocks(18 * 32, [72, 84, 108, 255], [92, 106, 134, 255], [86, 100, 128, 255], [84, 98, 126, 255], [96, 110, 138, 255])

    # 19: 高台の南側崖面
    ox = 19 * 32
    Zenoo::Window.draw_rect(ox, 0, 32, 28, color: [30, 36, 48, 255])
    Zenoo::Window.draw_rect(ox, 0, 32, 9,  color: PAL[:curb])
    Zenoo::Window.draw_rect(ox, 0, 32, 2,  color: PAL[:curb_rim])
    Zenoo::Window.draw_rect(ox + 15, 2, 2, 7, color: [90, 105, 132, 255])
    Zenoo::Window.draw_rect(ox, 9, 32, 1, color: [36, 42, 56, 255])
    Zenoo::Window.draw_rect(ox, 10, 32, 18, color: PAL[:brick_base])
    Zenoo::Window.draw_rect(ox, 19, 32, 1,  color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox + 8,  10, 1, 9, color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox + 24, 10, 1, 9, color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox + 16, 20, 1, 8, color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox, 28, 32, 4, color: PAL[:ground_shade])

    # 20: 高台の北・東西フチ石
    ox = 20 * 32
    Zenoo::Window.draw_rect(ox, 3, 32, 29, color: [72, 84, 108, 255])
    Zenoo::Window.draw_rect(ox + 1,  11, 14, 9, radius: 2, color: [90, 104, 132, 255])
    Zenoo::Window.draw_rect(ox + 17, 11, 14, 9, radius: 2, color: [86, 100, 128, 255])
    Zenoo::Window.draw_rect(ox + 1,  22, 30, 9, radius: 2, color: [92, 106, 134, 255])
    Zenoo::Window.draw_rect(ox, 0, 32, 3, color: PAL[:curb_shadow])
    Zenoo::Window.draw_rect(ox, 3, 32, 6, color: PAL[:curb])
    Zenoo::Window.draw_rect(ox, 3, 32, 2, color: PAL[:curb_hi])
    Zenoo::Window.draw_rect(ox, 9, 32, 1, color: PAL[:curb_dark])

    # 21: 高台の北西角フチ石
    ox = 21 * 32
    Zenoo::Window.draw_rect(ox + 3,  3,  29, 29, color: [72, 84, 108, 255])
    Zenoo::Window.draw_rect(ox + 11, 11, 9,  9,  radius: 2, color: [90, 104, 132, 255])
    Zenoo::Window.draw_rect(ox + 22, 11, 9,  9,  radius: 2, color: [86, 100, 128, 255])
    Zenoo::Window.draw_rect(ox + 11, 22, 20, 9,  radius: 2, color: [92, 106, 134, 255])
    Zenoo::Window.draw_rect(ox, 0, 32, 3,  color: PAL[:curb_shadow])
    Zenoo::Window.draw_rect(ox, 3, 3,  29, color: PAL[:curb_shadow])
    Zenoo::Window.draw_rect(ox + 9, 9, 23, 1,  color: PAL[:curb_dark])
    Zenoo::Window.draw_rect(ox + 9, 9, 1,  23, color: PAL[:curb_dark])
    Zenoo::Window.draw_rect(ox + 3, 3, 29, 6,  color: PAL[:curb])
    Zenoo::Window.draw_rect(ox + 3, 3, 6,  29, color: PAL[:curb])
    Zenoo::Window.draw_rect(ox + 3, 3, 29, 2,  color: PAL[:curb_hi])
    Zenoo::Window.draw_rect(ox + 3, 3, 2,  29, color: PAL[:curb_hi])

    # 22: 高台の南西角崖面
    ox = 22 * 32
    Zenoo::Window.draw_rect(ox, 0, 3, 28,  color: PAL[:curb_shadow])
    Zenoo::Window.draw_rect(ox + 3, 28, 29, 4, color: PAL[:ground_shade])
    Zenoo::Window.draw_rect(ox + 3, 10, 29, 18, color: PAL[:brick_base])
    Zenoo::Window.draw_rect(ox + 3, 10, 2,  18, color: [78, 92, 118, 255])
    Zenoo::Window.draw_rect(ox + 3, 19, 29, 1,  color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox + 14, 10, 1, 9,  color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox + 22, 20, 1, 8,  color: PAL[:brick_line])
    Zenoo::Window.draw_rect(ox + 3, 0, 29, 9,  color: PAL[:curb])
    Zenoo::Window.draw_rect(ox + 3, 0, 2,  9,  color: PAL[:curb_hi])
    Zenoo::Window.draw_rect(ox + 9, 0, 23, 2,  color: PAL[:curb_rim])
    Zenoo::Window.draw_rect(ox + 9, 0, 1,  2,  color: PAL[:curb_dark])
    Zenoo::Window.draw_rect(ox + 3, 9, 29, 1,  color: [36, 42, 56, 255])
  end
  tileset.slice_tiles(tile_width: TILE_SIZE, tile_height: TILE_SIZE)
end

def each_cell(c_range, r_range)
  r_range.each { |r| c_range.each { |c| yield c, r } }
end

def place_column_at(objects, c, root_r, parts)
  parts.reverse_each.with_index { |tid, i| objects[root_r - i][c] = tid }
end

def create_world_tilemap
  tiles = create_dungeon_tileset
  map = Zenoo::Tilemap.new(tiles)

  # 1マス障害物タイルの設定 (水場も solid: true)
  map.set_tile(T_WALL,  solid: true)
  map.set_tile(T_CRATE, solid: true)
  map.set_tile(T_WATER, solid: true)

  # 高台上面タイルの高さ (標高) 設定
  [T_HIGH_FLOOR, T_CLIFF_EDGE, T_CLIFF_CORNER_NW].each do |tid|
    map.set_tile(tid, height: PLATEAU_HEIGHT)
  end

  # タイルアニメーション定義 (4コマ)
  map.define_animation(T_WATER, frames: (T_WATER...T_WATER + 4).to_a, wait: 14)
  map.define_animation(T_BUSH,  frames: (T_BUSH...T_BUSH + 4).to_a,   wait: 12)

  # 縦連結オブジェクトの一括定義
  map.define_column(PILLAR_PARTS, solid: true)
  map.define_column(STELE_PARTS,  solid: true)

  # 1. 床レイヤー (40x24)
  ground = Array.new(MAP_ROWS) { Array.new(MAP_COLS, T_GRASS) }
  MAP_ROWS.times do |r|
    MAP_COLS.times do |c|
      if (r >= 10 && r <= 13) || (c >= 18 && c <= 21) ||
         ((r == 4 || r == 19) && c >= 4 && c <= 35) ||
         ((c == 6 || c == 33) && r >= 4 && r <= 19)
        ground[r][c] = ((r + c) % 7 == 0) ? T_ACCENT : T_PAVE
      elsif r >= 8 && r <= 15 && c >= 15 && c <= 24
        ground[r][c] = ((r == 9 || r == 14) && (c == 16 || c == 23)) ? T_ACCENT : T_PAVE
      end
    end
  end

  # 北西・南東の水場 (5x4マス)
  water_flipped = Zenoo::Tilemap.tile(T_WATER, flip_h: true)
  [[10..14, 5..8], [25..29, 15..18]].each do |cr, rr|
    each_cell(cr, rr) { |c, r| ground[r][c] = (r + c).odd? ? water_flipped : T_WATER }
  end

  # 2. 段差 (高台) レイヤー (40x24)
  cliffs       = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }
  cliffs_north = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }
  cliff_north = T_CLIFF_EDGE
  cliff_east  = Zenoo::Tilemap.tile(T_CLIFF_EDGE, rotate: 90)
  cliff_west  = Zenoo::Tilemap.tile(T_CLIFF_EDGE, rotate: 270)
  cliff_nw    = T_CLIFF_CORNER_NW
  cliff_ne    = Zenoo::Tilemap.tile(T_CLIFF_CORNER_NW, flip_h: true)
  cliff_sw    = T_CLIFF_CORNER_SW
  cliff_se    = Zenoo::Tilemap.tile(T_CLIFF_CORNER_SW, flip_h: true)

  PLATEAU_RANGES.each do |c_range, r_range|
    c0, c1 = c_range.begin, c_range.end
    r0, r1 = r_range.begin, r_range.end
    each_cell(c_range, r_range) do |c, r|
      if r == r0 && c == c0
        cliffs_north[r][c] = cliff_nw
      elsif r == r0 && c == c1
        cliffs_north[r][c] = cliff_ne
      elsif r == r0
        cliffs_north[r][c] = cliff_north
      elsif r == r1 && c == c0
        cliffs[r][c] = cliff_sw
      elsif r == r1 && c == c1
        cliffs[r][c] = cliff_se
      elsif r == r1
        cliffs[r][c] = T_CLIFF_SOUTH
      elsif c == c0
        cliffs[r][c] = cliff_west
      elsif c == c1
        cliffs[r][c] = cliff_east
      else
        cliffs[r][c] = T_HIGH_FLOOR
      end
    end
  end

  # 3. 立体オブジェクト・障害物レイヤー (40x24, 行単位 Yソート有効)
  objects = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }

  # 外周の石レンガ壁
  MAP_COLS.times { |c| objects[0][c] = objects[MAP_ROWS - 1][c] = T_WALL }
  MAP_ROWS.times { |r| objects[r][0] = objects[r][MAP_COLS - 1] = T_WALL }

  # 石柱・蒼石碑の配置 (高台の降下経路・フチを塞がないよう1マス余裕を確保)
  [[16, 9], [23, 9], [17, 15], [23, 15], [8, 8], [8, 15], [31, 8], [31, 15]].each do |c, r|
    place_column_at(objects, c, r, PILLAR_PARTS)
  end
  [[5, 5], [34, 5], [5, 19], [34, 19], [19, 4], [20, 20]].each do |c, r|
    place_column_at(objects, c, r, STELE_PARTS)
  end

  # 木箱群
  [[4, 11], [4, 12], [5, 12], [35, 11], [35, 12], [34, 11]].each do |c, r|
    objects[r][c] = T_CRATE
  end

  # 背の高い草の群生配置
  [
    [10..13, 9..9],   [26..29, 14..14],
    [7..8,   6..7],   [7..8,   16..17],
    [31..32, 6..7],   [31..32, 16..17],
    [2..4,   7..9],   [2..4,   15..17],
    [35..37, 6..8],   [35..37, 14..16]
  ].each do |cr, rr|
    each_cell(cr, rr) do |c, r|
      if ground[r][c] == T_GRASS && cliffs[r][c].nil? && cliffs_north[r][c].nil? && objects[r][c].nil?
        objects[r][c] = T_BUSH
      end
    end
  end

  map.add_layer(:ground,       ground,       z: GROUND_Z)
  map.add_layer(:cliffs,       cliffs,       z: 0.0)
  map.add_layer(:cliffs_north, cliffs_north, z: 0.0, y_sort: true)
  map.add_layer(:objects,      objects,      z: 0.0, y_sort: true)
  map
end

# ==============================================================================
# キャラクター浮遊・影描画共通モジュール (案D)
# ==============================================================================
module Airborne
  def shadow_metrics(altitude, max_h = 65.0, base_w = 22.0, base_h = 9.0, base_alpha = 140)
    z_ratio = (1.0 - altitude.clamp(0.0, max_h) / max_h).clamp(0.45, 1.0)
    [base_w * z_ratio, base_h * z_ratio, (base_alpha * z_ratio).to_i]
  end

  def with_lift(lift_y)
    orig_y = y
    self.y = orig_y - lift_y
    res = yield
    self.y = orig_y
    res
  end
end

# ==============================================================================
# 斬撃円弧リボンエフェクト (Mesh.ring による白リボンメッシュ)
# ==============================================================================
class SlashEffect < Zenoo::Sprite
  LIFE     = 12
  CENTER_Y = 32.0 # プレイヤーの手元高さ (足元から 32px)

  def self.create_mesh
    mesh = Zenoo::Mesh.ring(75, inner_radius: 0.6, start_angle: -60.0, end_angle: 60.0, color: :white, blend: :add)
    mesh.deform do |v|
      ratio = v.col.to_f / mesh.cols
      v.alpha = (ratio ** 1.8) * 255.0
    end
    mesh
  end

  def initialize(player, angle, mesh)
    super(player.x, player.y - player.jump_z - CENTER_Y, mesh, anchor: :center, pivot: :center, blend: :add)
    @player = player
    self.angle = angle
    self.scale_y = player.facing_x
    self.z = EFFECT_Z
    @timer = LIFE
  end

  def update
    self.x = @player.x
    self.y = @player.y - @player.jump_z - CENTER_Y

    @timer -= 1
    t = @timer.to_f / LIFE
    self.alpha = (255.0 * t).clamp(0, 255).to_i
    self.scale = 1.0 + (1.0 - t) * 0.18
    vanish if @timer <= 0
  end
end

# ==============================================================================
# ベクターグラフィックスによる潰れたスライム敵 (Mesh.canvas)
# ==============================================================================
def create_slime_mesh
  Zenoo::Mesh.canvas(90, 70) do |c|
    grad = c.create_linear_gradient(45, 15, 45, 68)
    grad.add_color_stop(0.0, [90,  255, 190, 255])
    grad.add_color_stop(1.0, [25,  145, 115, 255])

    c.begin_path
    steps = 32
    steps.times do |i|
      ang = i * (Math::PI * 2.0 / steps)
      ry = Math.sin(ang) > 0 ? 20.0 : 32.0
      px = 45.0 + Math.cos(ang) * 36.0
      py = 47.0 + Math.sin(ang) * ry
      i == 0 ? c.move_to(px, py) : c.line_to(px, py)
    end
    c.close_path
    c.fill(grad)
    c.line_join = :round
    c.stroke([255, 255, 255, 230], 3.0)

    # 瞳 & ハイライト
    c.fill_circle(35, 45, 5, [20, 30, 45, 255])
    c.fill_circle(55, 45, 5, [20, 30, 45, 255])
    c.fill_circle(33, 43, 2, :white)
    c.fill_circle(53, 43, 2, :white)

    # ほっぺ
    c.fill_circle(26, 50, 4, [255, 120, 160, 150])
    c.fill_circle(64, 50, 4, [255, 120, 160, 150])
  end
end

class SlimeEnemy < Zenoo::Sprite
  include Airborne

  BASE_SCALE    = 0.75
  MAX_HP        = 3
  BODY_CENTER_Y = 20.0
  HOP_CYCLE     = 48
  HOP_SPEED     = 2.2
  CHASE_RANGE   = 420.0

  BOUNCES     = [[16, 20.0], [12, 11.0], [8, 5.0]].freeze
  BOUNCE_END  = BOUNCES.sum(&:first) # 36
  HIT_TIME    = BOUNCE_END + 2
  KB_FRICTION = 0.935
  ROUND_SX    = 0.86
  ROUND_SY    = 1.22

  FLASH_COLOR  = [255, 120, 120, 255].freeze
  HP_ON_COLOR  = [80, 240, 140, 230].freeze
  HP_OFF_COLOR = [70, 80, 95, 180].freeze

  attr_reader :hp, :jump_z

  def initialize(x, y, mesh)
    super(x, y, mesh, anchor: :bottom_center, pivot: :bottom_center)
    @hp = MAX_HP
    @hit_timer = 0
    @dying = false
    @vx = 0.0
    @vy = 0.0
    @jump_z = 0.0
    @hop_tick = rand(0...HOP_CYCLE)
    @facing_x = 1.0
    self.z = y

    set_collider(:circle, radius_x: 24.0, radius_y: 12.0, anchor: :bottom_center, offset_y: -8.0)
  end

  def dying?
    @dying
  end

  def update(target_x, target_y, tilemap = nil)
    sx, sy = @hit_timer > 0 ? update_knockback : update_hop(target_x, target_y)
    return if vanished?

    self.scale_x = @facing_x * BASE_SCALE * sx
    self.scale_y = BASE_SCALE * sy
    tilemap&.resolve_collision(self, altitude: 0.0)
    self.z = y
  end

  def hit(kb_x, kb_y)
    return if @dying

    @hp -= 1
    @dying = true if @hp <= 0
    @hit_timer = HIT_TIME

    spd = @dying ? 8.2 : 7.6
    @vx = kb_x * spd
    @vy = kb_y * spd * Y_RATIO
  end

  def draw
    return if vanished? || !visible

    # 1. 接地ドロップシャドウ
    sw, sh, sa = shadow_metrics(@jump_z, 40.0, 30.0 * (scale_x.abs / BASE_SCALE), 11.5, 140)
    a = (sa * alpha / 255.0).to_i
    Zenoo::Window.draw_ellipse(x, y - 3.0, sw, sh, color: [*SHADOW_COLOR_RGB, a], z: SHADOW_Z)

    # 2. スライム本体
    self.z = y
    with_lift(@jump_z) { super }

    # 3. 頭上 HP ドット
    unless @dying
      hp_y = y - @jump_z - 64.0
      MAX_HP.times do |i|
        Zenoo::Window.draw_circle(x.to_i - 12 + i * 12, hp_y, 3.5, color: i < @hp ? HP_ON_COLOR : HP_OFF_COLOR, z: HP_BAR_Z)
      end
    end
  end

  private

  def update_knockback
    @hit_timer -= 1
    elapsed = HIT_TIME - @hit_timer

    self.x += @vx
    self.y += @vy
    @vx *= KB_FRICTION
    @vy *= KB_FRICTION

    @jump_z = bounce_height(elapsed)

    flash = @dying ? 24 : 10
    self.color = elapsed < flash ? (elapsed.even? ? FLASH_COLOR : :white) : nil

    if @dying
      self.alpha = (255.0 * (1.0 - (elapsed - 26) / 12.0)).clamp(0, 255).to_i if elapsed >= 26
      vanish if @hit_timer <= 0
    end

    return [ROUND_SX, ROUND_SY] if elapsed < BOUNCE_END

    t = (elapsed - BOUNCE_END) / 2.0
    [ROUND_SX + (1.0 - ROUND_SX) * t, ROUND_SY + (1.0 - ROUND_SY) * t]
  end

  def bounce_height(elapsed)
    start = 0
    BOUNCES.each do |len, height|
      return Math.sin((elapsed - start).to_f / len * Math::PI) * height if elapsed < start + len
      start += len
    end
    0.0
  end

  def update_hop(target_x, target_y)
    dx = target_x - x
    dy = (target_y - 16.0) - y
    dist = Math.hypot(dx, dy)
    @facing_x = (dx >= 0 ? 1.0 : -1.0) if dist > 10.0 && dist < CHASE_RANGE

    @hop_tick = (@hop_tick + 1) % HOP_CYCLE
    @jump_z = 0.0

    if @hop_tick < 14
      t = @hop_tick / 14.0
      [1.0 + t * 0.22, 1.0 - t * 0.18]
    elsif @hop_tick < 34
      @jump_z = Math.sin((@hop_tick - 14) / 20.0 * Math::PI) * 8.0
      if dist > 32.0 && dist < CHASE_RANGE
        self.x += dx / dist * HOP_SPEED
        self.y += dy / dist * HOP_SPEED * Y_RATIO
      end
      [ROUND_SX, ROUND_SY]
    elsif @hop_tick < 42
      t = (@hop_tick - 34) / 8.0
      [1.18 - t * 0.12, 0.84 + t * 0.12]
    else
      [1.0, 1.0]
    end
  end
end

# ==============================================================================
# 斜め4方向プレイヤー
# ==============================================================================
class IsoPlayer < Zenoo::Sprite
  include Airborne

  SPEED         = 4.2
  ATTACK_DASH   = 6.5
  DASH_FRICTION = 0.85
  HIT_FRAMES    = 12
  JUMP_SPEED    = 6.2
  GRAVITY       = 0.48

  SLASH_REACH   = 115.0
  COS_75        = Math.cos(75.0 * Math::PI / 180.0)
  COS_85        = Math.cos(85.0 * Math::PI / 180.0)
  CLOSE_RANGE   = 40.0

  DIR_DOWN = 0
  DIR_UP   = 1

  WALK_ANIMS   = [:walk_down,   :walk_up].freeze
  IDLE_ANIMS   = [:idle_down,   :idle_up].freeze
  ATTACK_ANIMS = [:attack_down, :attack_up].freeze

  WALK_FRAME_NAMES = ["0 (左足)", "1 (直立)", "2 (右足)", "1 (直立)"].freeze

  attr_reader   :facing_x, :attacking, :altitude, :ground_h
  attr_accessor :effects, :enemies, :tilemap
  alias jump_z altitude

  def initialize(x, y)
    super(x, y, anchor: :bottom_center, pivot: :bottom_center)

    @dir_y = DIR_DOWN
    @facing_x = 1.0
    @attacking = false
    @vx = 0.0
    @vy = 0.0
    @altitude = 0.0
    @ground_h = 0.0
    @vz = 0.0
    @effects = nil
    @enemies = nil
    @tilemap = nil
    @attack_timer = 0
    @hit_targets = {}
    @atk_nx = 1.0
    @atk_ny = 0.0
    @last_move_dx = 1.0
    @last_move_dy = 1.0

    @slash_mesh = SlashEffect.create_mesh

    load_animations
    play(IDLE_ANIMS[@dir_y])

    set_collider(:circle, radius_x: 11.0, radius_y: 8.0, anchor: :bottom_center, offset_y: -8.0)
    self.z = y
  end

  def body_z
    @ground_h >= PLATEAU_HEIGHT ? (y + 32.0) : y
  end

  def trigger_jump
    if @altitude <= @ground_h && @vz <= 0.0
      @vz = JUMP_SPEED
      dx, dy = Zenoo::Input.vector
      if dx != 0.0 || dy != 0.0
        update_direction(dx, dy)
        remember_move_dir(dx, dy)
      end
      # 進行方向への慣性ジャンプ (空中でも前進を維持)
      @jump_dx = @last_move_dx
      @jump_dy = @last_move_dy
    end
  end

  def start_attack
    return if @attacking

    @attacking = true
    @attack_timer = 0
    @hit_targets = {}

    dx, dy = Zenoo::Input.vector
    remember_move_dir(dx, dy) if dx != 0.0 || dy != 0.0
    dir_x = @last_move_dx
    dir_y = @last_move_dy
    update_direction(dir_x, dir_y)

    @vx = dir_x * ATTACK_DASH
    @vy = dir_y * ATTACK_DASH * Y_RATIO

    ay = dir_y * Y_RATIO
    mag = Math.hypot(dir_x, ay)
    mag = 1.0 if mag < 0.0001
    @atk_nx = dir_x / mag
    @atk_ny = ay / mag

    @effects&.push(SlashEffect.new(self, Math.atan2(@atk_ny, @atk_nx) * 180.0 / Math::PI, @slash_mesh))
    check_slash_hit
    play(ATTACK_ANIMS[@dir_y])
  end

  def update
    trigger_jump if Zenoo::Input.action_push?(:jump)

    if @attacking
      update_attack
    elsif Zenoo::Input.action_push?(:attack)
      start_attack
    else
      update_move
    end

    super()

    # エンジン側の高度対応 MTV 衝突解決
    @tilemap&.resolve_collision(self, altitude: @altitude)

    # 足元の床の最高標高を取得
    @ground_h = @tilemap ? @tilemap.support_height(self, altitude: @altitude, offset_y: -PLATEAU_HEIGHT) : 0.0
    update_jump

    self.z = body_z
  end

  def draw
    return if vanished? || !visible

    # 1. 地面に落ちる影
    sw0, sh0, sa0 = shadow_metrics(@altitude)
    Zenoo::Window.draw_ellipse(x, y - 2.0, sw0, sh0, color: [*SHADOW_COLOR_RGB, sa0], z: SHADOW_Z)

    # 2. 高台の上面に落ちる影 (クリッピング付き)
    if @altitude >= PLATEAU_HEIGHT
      sw1, sh1, sa1 = shadow_metrics(@altitude - PLATEAU_HEIGHT)
      top_sy = y - PLATEAU_HEIGHT - 2.0
      shadow_z = body_z - 0.5

      PLATEAU_TOP_RECTS.each do |px, py, pw, ph|
        if x + sw1 > px && x - sw1 < px + pw && top_sy + sh1 > py && top_sy - sh1 < py + ph
          sx, sy = Zenoo::Window.to_screen(px, py)
          Zenoo::Window.clip(sx, sy, pw, ph, z: shadow_z) do
            Zenoo::Window.draw_ellipse(x, top_sy, sw1, sh1, color: [*SHADOW_COLOR_RGB, sa1], z: shadow_z)
          end
        end
      end
    end

    # 3. キャラ本体
    self.z = body_z
    with_lift(@altitude) { super }
  end

  def direction_name
    case [@dir_y, @facing_x > 0 ? :right : :left]
    when [DIR_DOWN, :right] then "右下 (手前)"
    when [DIR_DOWN, :left]  then "左下 (手前・反転)"
    when [DIR_UP,   :right] then "右上 (奥)"
    when [DIR_UP,   :left]  then "左上 (奥・反転)"
    end
  end

  def frame_description
    return "空中 (高度: #{@altitude.to_i}px / 床: #{@ground_h.to_i}px)" if @altitude > @ground_h
    return "攻撃モーション (1コマ/30フレーム/0.5秒)" if @attacking
    WALK_FRAME_NAMES[current_frame_index] || current_frame_index.to_s
  end

  private

  def update_jump
    if @altitude > @ground_h || @vz != 0.0
      @altitude += @vz
      @vz -= GRAVITY
      if @altitude <= @ground_h
        @altitude = @ground_h
        @vz = 0.0
        @jump_dx = nil
        @jump_dy = nil
      end
    end
  end

  def update_move
    dx, dy = Zenoo::Input.vector
    if dx == 0.0 && dy == 0.0
      if @altitude > @ground_h && @jump_dx
        dx, dy = @jump_dx, @jump_dy
      else
        play(IDLE_ANIMS[@dir_y])
        return
      end
    end

    update_direction(dx, dy)
    remember_move_dir(dx, dy)
    play(WALK_ANIMS[@dir_y], keep_frame: true)

    self.x += dx * SPEED
    self.y += dy * SPEED * Y_RATIO
  end

  def update_attack
    self.x += @vx
    self.y += @vy
    @vx *= DASH_FRICTION
    @vy *= DASH_FRICTION

    check_slash_hit if @attack_timer < HIT_FRAMES
    @attack_timer += 1

    if animation_finished?
      @attacking = false
      play(IDLE_ANIMS[@dir_y])
    end
  end

  def check_slash_hit
    return unless @enemies

    cx = x
    cy = y - SlashEffect::CENTER_Y

    @enemies.each do |enemy|
      next if enemy.vanished? || enemy.dying? || @hit_targets[enemy.object_id]
      next if (@altitude - enemy.jump_z).abs > 15.0

      dx = enemy.x - cx
      dy = (enemy.y - SlimeEnemy::BODY_CENTER_Y) - cy
      dist = Math.hypot(dx, dy)
      next if dist > SLASH_REACH

      forward = dx * @atk_nx + dy * @atk_ny
      next if forward <= 5.0
      next if forward / dist <= (dist <= CLOSE_RANGE ? COS_85 : COS_75)

      @hit_targets[enemy.object_id] = true
      kb_x = dx / dist * 0.7 + @atk_nx * 0.3
      kb_y = dy / dist * 0.7 + @atk_ny * 0.3
      kb_mag = Math.hypot(kb_x, kb_y)
      enemy.hit(kb_x / kb_mag, kb_y / kb_mag)
    end
  end

  def remember_move_dir(dx, dy)
    mag = Math.hypot(dx, dy)
    @last_move_dx = dx / mag
    @last_move_dy = dy / mag
  end

  def update_direction(dx, dy)
    if dx.abs > 0.05
      @facing_x = dx > 0.0 ? 1.0 : -1.0
      self.scale_x = @facing_x
    end
    @dir_y = dy > 0.0 ? DIR_DOWN : DIR_UP if dy.abs > 0.05
  end

  def load_animations
    find_sprite = lambda do |file|
      candidates = [
        "assets/sprites/#{file}",
        "/assets/sprites/#{file}",
        "../assets/sprites/#{file}",
        "../../assets/sprites/#{file}"
      ]
      candidates << File.expand_path("../assets/sprites/#{file}", __dir__) if defined?(__dir__) && __dir__
      candidates.each do |p|
        return p if File.exist?(p)
      end
      "assets/sprites/#{file}"
    end

    { down: "player_walk_down_right_3frame_1x.png", up: "player_walk_up_right_3frame_1x.png" }.each do |dir, file|
      t = Zenoo::Image.load_tiles(find_sprite.call(file), 3, 1)
      add_animation(:"walk_#{dir}", [t[0], t[1], t[2], t[1]], wait: 6, loop: true)
      add_animation(:"idle_#{dir}", [t[1]], wait: 1, loop: false)
    end

    { down: "player_attack_down_right_1x.png", up: "player_attack_up_right_1x.png" }.each do |dir, file|
      img = Zenoo::Image.load(find_sprite.call(file))
      add_animation(:"attack_#{dir}", [img], wait: 30, loop: false, offset_x: 4, offset_y: 2)
    end
  end
end

# ==============================================================================
# UI オーバーレイ & メインシーン (案E)
# ==============================================================================
PANEL_COLOR  = [18, 22, 32, 220].freeze
PANEL_BORDER = [60, 80, 110, 200].freeze
TITLE_COLOR  = [0, 220, 255, 255].freeze

GUIDE_LINES = [
  ["マップ   : 1280x768 (40x24) / 行単位Mesh & Zソート & 水場・草IBOアニメ", [160, 220, 255, 255]],
  ["高台     : 標高18px (ジャンプで登り、上からは歩いてそのまま飛び降り可能)", [255, 210, 90, 255]],
  ["移動     : [W][A][S][D] / 矢印 / パッド / マウス・タッチ長押し (MTV 壁ずり)", [220, 225, 235, 255]],
  ["ジャンプ : [K] / [X] / [Shift] / 右クリック / 右下[JUMP]ボタン / 2本指タップ", [120, 255, 180, 255]],
  ["攻撃     : [SPACE] / [J] / [Z] / マウス・タッチクリック (クリック方向へ踏み込み斬撃)", [255, 120, 100, 255]],
  ["表示     : [H] キーで操作ガイド・モニターの表示切替", [200, 200, 220, 255]]
].freeze

SPAWN_POINTS = [
  [240.0,  220.0], [1040.0, 220.0],
  [240.0,  540.0], [1040.0, 540.0],
  [640.0,  210.0], [640.0,  560.0],
  [240.0,  380.0], [1040.0, 380.0]
].freeze

# UI メニューボタン定数 (1280x720 画面座標系)
BTN_MENU_X = 1120.0
BTN_MENU_Y = 24.0
BTN_MENU_W = 136.0
BTN_MENU_H = 34.0

class DemoScene < Zenoo::Scene
  attr_reader :tilemap, :player, :enemies, :camera, :effects

  def initialize
    @tilemap = create_world_tilemap

    @player = IsoPlayer.new(WORLD_WIDTH / 2.0, WORLD_HEIGHT / 2.0)
    @effects = []
    @player.effects = @effects
    @player.tilemap = @tilemap

    @slime_mesh = create_slime_mesh
    @enemies = SPAWN_POINTS.map { |ex, ey| SlimeEnemy.new(ex, ey, @slime_mesh) }
    @player.enemies = @enemies

    @camera = Zenoo::Camera.new(
      x: @player.x,
      y: @player.y - 20.0,
      offset_x: VIRTUAL_WIDTH / 2.0,
      offset_y: VIRTUAL_HEIGHT / 2.0,
      target: @player,
      target_offset_y: -20.0,
      smooth_speed: 1.1,
      bounds: [0, 0, WORLD_WIDTH, WORLD_HEIGHT]
    )

    @screen = Zenoo::Image.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    @screen.texture_filter = :nearest

    @show_ui = true
    @frame_count = 0
    @test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0

    # バーチャルパッドの初期プリセット設定 (デフォルト: ワンハンド、タッチ時のみ自動稼働・描画)
    Zenoo::Input.virtual_pad = Zenoo::VirtualPad.one_hand
    @menu_open = false
    @menu_cooldown = 0
    @mouse_hold_frames = 0
    @mouse_moving = false
  end

  def call
    @frame_count += 1
    exit(0) if @test_max > 0 && @frame_count >= @test_max

    @menu_cooldown -= 1 if @menu_cooldown > 0
    @show_ui = !@show_ui if Zenoo::Input.key_push?(:h)

    # モードに応じた更新 (排他制御)
    if @menu_open
      update_menu
    else
      update_gameplay
    end

    # 2. 仮想解像度バッファへワールドを描画
    Zenoo::Image.render_to(@screen) { draw_world }

    # 3. 画面へ 2 倍拡大描画 & UI 重ね掛け
    Zenoo::Window.clear([0, 0, 0, 255])
    Zenoo::Window.draw(0, 0, @screen, scale_x: 2.0, scale_y: 2.0, anchor: :top_left, pivot: :top_left)
    draw_ui
    draw_menu if @menu_open
  end

  private

  def open_menu
    @menu_open = true
    @menu_cooldown = 15 # 開いた直後の誤爆防止クールダウン (約0.25秒)
    @mouse_hold_frames = 0
    @mouse_moving = false
    Zenoo::Input.virtual_pad.enabled = false if Zenoo::Input.virtual_pad
    Zenoo::Input.cancel_touches
  end

  def close_menu
    @menu_open = false
    @menu_cooldown = 10
    @mouse_hold_frames = -1 # ボタンを一度離すまで左クリック移動・攻撃を抑止
    @mouse_moving = false
    Zenoo::Input.virtual_pad.enabled = true if Zenoo::Input.virtual_pad
    Zenoo::Input.cancel_touches
  end

  # PCマウス専用ダイレクト操作 (左長押し: カーソル方向へ移動 / 左クリック: カーソル方向へ攻撃 / 右クリック: ジャンプ)
  def update_mouse_control
    return if Zenoo::Input.using_touch?

    mx = Zenoo::Input.mouse_x
    my = Zenoo::Input.mouse_y

    if @mouse_hold_frames < 0
      @mouse_hold_frames = 0 unless Zenoo::Input.mouse_pressed?(:left)
      return
    end

    if Zenoo::Input.mouse_pressed?(:left)
      @mouse_hold_frames += 1
      if @mouse_hold_frames > 5 && !@player.attacking
        wx, wy = @camera.screen_to_world(mx / 2.0, my / 2.0)
        pdx = wx - @player.x
        pdy = (wy - (@player.y - 8.0)) / Y_RATIO
        dist = Math.hypot(pdx, pdy)
        thresh = @mouse_moving ? 8.0 : 16.0
        if dist > thresh
          @mouse_moving = true
          spd_ratio = [1.0, dist / 28.0].min
          Zenoo::Input.inject_vector((pdx / dist) * spd_ratio, (pdy / dist) * spd_ratio)
        else
          @mouse_moving = false
        end
      end
    elsif Zenoo::Input.mouse_release?(:left)
      if @mouse_hold_frames > 0 && @mouse_hold_frames <= 20
        wx, wy = @camera.screen_to_world(mx / 2.0, my / 2.0)
        pdx = wx - @player.x
        pdy = (wy - (@player.y - 16.0)) / Y_RATIO
        mag = Math.hypot(pdx, pdy)
        Zenoo::Input.inject_vector(pdx / mag, pdy / mag) if mag > 0.001
        Zenoo::Input.inject_action(:attack, 1.0)
      end
      @mouse_hold_frames = 0
      @mouse_moving = false
    else
      @mouse_hold_frames = 0
      @mouse_moving = false
    end
  end

  def update_gameplay
    touches = Zenoo::Input.touches
    mx = Zenoo::Input.mouse_x
    my = Zenoo::Input.mouse_y

    # 1. [M] キーでメニューを開く
    if Zenoo::Input.key_push?(:m)
      open_menu
      return
    end

    # 2. 右上の MENU ボタンでメニューを開く
    if Zenoo::Input.mouse_push?(:left) && mx >= BTN_MENU_X && mx <= BTN_MENU_X + BTN_MENU_W && my >= BTN_MENU_Y && my <= BTN_MENU_Y + BTN_MENU_H
      Zenoo::Input.consume_mouse!
      open_menu
      return
    end

    # 3. 2本指タップでメニューを開く
    if touches.size >= 2 && touches[0].duration <= 6 && touches[1].duration <= 6
      open_menu
      return
    end

    # 4. PCマウス操作の反映 (タッチ非使用時: 左長押し移動・左クリック攻撃)
    update_mouse_control

    # ゲーム世界の更新 (プレイヤーの移動・ジャンプ・攻撃はすべて Input 経由で自動連携)
    @tilemap.update
    @player.update
    @enemies.each { |e| e.update(@player.x, @player.y, @tilemap) }
    Zenoo::Sprite.clean(@enemies)
    Zenoo::Sprite.update(@effects)
    Zenoo::Sprite.clean(@effects)

    @camera.update

    if @enemies.empty?
      SPAWN_POINTS.sample(4).each do |sx, sy|
        @enemies << SlimeEnemy.new(sx, sy, @slime_mesh)
      end
    end
  end

  def update_menu
    mx = Zenoo::Input.mouse_x
    my = Zenoo::Input.mouse_y
    clicked = Zenoo::Input.mouse_push?(:left)

    # 1. [M] または [ESC] キーで閉じる
    if Zenoo::Input.key_push?(:m) || Zenoo::Input.key_push?(:escape)
      close_menu
      return
    end

    # 2. モード選択ボタン判定 (カード幅一杯 220 <= x <= 1060 を安全にカバー)
    if clicked && mx >= 220 && mx <= 1060
      new_pad = if my >= 215 && my < 305
                  Zenoo::VirtualPad.gamepad
                elsif my >= 305 && my < 390
                  Zenoo::VirtualPad.split_gesture
                elsif my >= 390 && my <= 480
                  Zenoo::VirtualPad.one_hand
                end
      if new_pad
        new_pad.enabled = false # メニュー表示中は無効化状態を維持
        Zenoo::Input.virtual_pad = new_pad
        @menu_cooldown = 6
        return
      end
    end

    # 3. クールダウン中はメニュー終了判定を行わない (メニュー開閉直後の誤爆を100%防止)
    return if @menu_cooldown > 0

    # 4. 右上の MENU ボタンまたは外枠タップ (カードの外側の暗転エリア) で閉じる
    if clicked
      in_menu_btn = mx >= BTN_MENU_X && mx <= BTN_MENU_X + BTN_MENU_W && my >= BTN_MENU_Y && my <= BTN_MENU_Y + BTN_MENU_H
      outside_card = mx < 180 || mx > 1100 || my < 105 || my > 585
      if in_menu_btn || outside_card
        close_menu
        return
      end
    end
  end

  def draw_world
    Zenoo::Window.camera = @camera
    Zenoo::Window.clear([24, 28, 38, 255])

    @tilemap.draw
    @player.draw
    Zenoo::Sprite.draw(@enemies)
    Zenoo::Sprite.draw(@effects)
  end

  def draw_ui
    # 右上: MENUボタン (常時表示)
    btn_hover = !Zenoo::Input.using_touch? && Math.hypot(Zenoo::Input.mouse_x - (BTN_MENU_X + 68), Zenoo::Input.mouse_y - (BTN_MENU_Y + 17)) <= 40
    menu_col = btn_hover ? [40, 56, 80, 240] : [24, 32, 48, 190]
    Zenoo::Window.draw_rect(BTN_MENU_X, BTN_MENU_Y, BTN_MENU_W, BTN_MENU_H, radius: 8, color: menu_col, border_width: 1, border_color: [80, 160, 240, 200])
    Zenoo::Window.draw_text(BTN_MENU_X + 10, BTN_MENU_Y + 8, "⚙️ MENU [2本指]", size: 14, color: [220, 240, 255, 255])

    unless @show_ui
      Zenoo::Window.draw_rect(24, 20, 280, 36, radius: 8, color: [18, 22, 32, 180], border_width: 1, border_color: [60, 80, 110, 160])
      Zenoo::Window.draw_text(36, 29, "[H] キーで操作ガイド・モニターを表示", size: 13, color: [180, 210, 240, 230])
      return
    end

    # 左上: 設計コンセプト & 操作ガイド
    Zenoo::Window.draw_rect(24, 20, 560, 192, radius: 10, color: PANEL_COLOR, border_width: 1, border_color: PANEL_BORDER)
    Zenoo::Window.draw_text(40, 34, "【多層YソートTilemap & 斜め4方向アクション】", size: 18, color: TITLE_COLOR)
    GUIDE_LINES.each_with_index do |(text, color), i|
      Zenoo::Window.draw_text(40, 60 + i * 22, text, size: 13, color: color)
    end

    # 右上: 状態リアルタイムモニター
    col_x = (@player.x / TILE_SIZE).to_i
    row_y = (@player.y / TILE_SIZE).to_i
    preset = Zenoo::Input.virtual_pad ? Zenoo::Input.virtual_pad.preset_name : :none
    mode_name = case preset
                when :gamepad       then "A: VirtualPad.gamepad (スティック+ボタン)"
                when :split_gesture then "B: VirtualPad.split_gesture (フリック)"
                when :one_hand      then "C: VirtualPad.one_hand (指1本操作)"
                else "カスタム / 無効"
                end
    monitor = [
      ["操作モード : #{mode_name}", [255, 220, 80, 255]],
      ["現在座標 : (#{@player.x.to_i}, #{@player.y.to_i}) [Tile: #{col_x}, #{row_y}] / 高度: #{@player.altitude.to_i}px (床:#{@player.ground_h.to_i}px)", :white],
      ["カメラ   : (#{@camera.x.to_i}, #{@camera.y.to_i}) / 残りスライム: #{@enemies.size}体", [100, 255, 180, 255]],
      ["向き・アニメ : #{@player.direction_name} (#{@player.animation})", [180, 200, 255, 255]],
      ["現在のコマ : #{@player.current_frame_index} [#{@player.frame_description}]", [255, 220, 100, 255]]
    ]
    Zenoo::Window.draw_rect(760, 20, 340, 184, radius: 10, color: PANEL_COLOR, border_width: 1, border_color: PANEL_BORDER)
    Zenoo::Window.draw_text(776, 34, "【リアルタイム状態モニター】", size: 18, color: TITLE_COLOR)
    monitor.each_with_index do |(text, color), i|
      Zenoo::Window.draw_text(776, 62 + i * 23, text, size: 13, color: color)
    end
  end

  def draw_menu
    preset = Zenoo::Input.virtual_pad ? Zenoo::Input.virtual_pad.preset_name : :none

    # 暗転オーバーレイ
    Zenoo::Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 180])

    # メニューカード (画面中央・縦横バランス最適化: 幅840, 高さ420)
    Zenoo::Window.draw_rect(220, 135, 840, 420, radius: 16, color: [16, 22, 34, 250], border_width: 2, border_color: [0, 220, 255, 220])
    Zenoo::Window.draw_text(390, 155, "🎮 操作モード設定 (VirtualPad Preset)", size: 26, color: [0, 255, 200, 255])
    Zenoo::Window.draw_text(360, 193, "画面を2本指タップ、または [M] キーでいつでも開閉できます", size: 15, color: [160, 200, 230, 240])

    # 各モードボタンの描画 (幅760, 高さ74)
    draw_menu_item(260, 228, "モード A: VirtualPad.gamepad (おすすめ)", "左: 移動スティック / 右: [ATK][JUMP] ボタン", preset == :gamepad)
    draw_menu_item(260, 312, "モード B: VirtualPad.split_gesture (モダン)", "左: 移動スティック / 右: タップ攻撃・フリックジャンプ", preset == :split_gesture)
    draw_menu_item(260, 396, "モード C: VirtualPad.one_hand (指1本・片手操作)", "全画面スライド移動 / タップ攻撃 / 素早くフリックでジャンプ", preset == :one_hand)

    # 枠外タップ案内 (程よい余白で配置)
    Zenoo::Window.draw_text(485, 494, "※ 枠外（暗転エリア）をタップして閉じる", size: 15, color: [140, 180, 220, 220])
  end

  def draw_menu_item(x, y, title, desc, active)
    bg = active ? [14, 48, 72, 240] : [22, 30, 46, 220]
    border = active ? [0, 255, 220, 255] : [60, 80, 110, 180]
    badge_text = active ? "● 選択中" : "○ 選択"
    badge_col = active ? [0, 255, 200, 255] : [140, 160, 190, 200]

    Zenoo::Window.draw_rect(x, y, 760, 74, radius: 10, color: bg, border_width: active ? 2 : 1, border_color: border)
    Zenoo::Window.draw_text(x + 24, y + 12, title, size: 21, color: active ? :white : [210, 220, 235, 255])
    Zenoo::Window.draw_text(x + 24, y + 42, desc, size: 15, color: active ? [160, 230, 255, 240] : [130, 155, 185, 220])
    Zenoo::Window.draw_text(x + 630, y + 25, badge_text, size: 18, color: badge_col)
  end
end

# ==============================================================================
# メインエントリーポイント
# ==============================================================================
if __FILE__ == $0
  Zenoo::Input.define_action(:attack, keys: [:space, :j, :z], gamepad: [:x, :a, :rb])
  Zenoo::Input.define_action(:jump,   keys: [:k, :x, :left_shift, :right_shift], mouse: :right, gamepad: [:b, :lb])

  scene = DemoScene.new
  Zenoo::Scene.change(scene)
  Zenoo::Window.loop(WINDOW_WIDTH, WINDOW_HEIGHT, "Zenoo - 4-Way Diagonal Animated Sprite & Multi-Layer Tilemap Demo") do
    Zenoo::Scene.call
  end
end

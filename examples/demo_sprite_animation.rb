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
# 縦横半分サイズ (640x360) のバッファに描画し、ウィンドウ (1280x720) に 2 倍拡大描画
VIRTUAL_WIDTH  = 640
VIRTUAL_HEIGHT = 360
WINDOW_WIDTH   = 1280
WINDOW_HEIGHT  = 720

# タイルマップ規模: 32x32 タイル × 40列 × 24行 = 1280x768 (仮想画面の縦横約2画面分)
TILE_SIZE    = 32
MAP_COLS     = 40
MAP_ROWS     = 24
WORLD_WIDTH  = MAP_COLS * TILE_SIZE # 1280
WORLD_HEIGHT = MAP_ROWS * TILE_SIZE # 768

# タイルID定義
T_GRASS      = 0 # 苔むした地面 (床)
T_PAVE       = 1 # 石畳の回廊 (床)
T_ACCENT     = 2 # 紋章石床 (床)
T_WALL       = 3 # 石レンガ壁 (1マス障害物)
T_CRATE      = 4 # 木箱 (1マス障害物)
T_PILLAR_TOP = 5 # 3段石柱・上段 (root_offset: 2)
T_PILLAR_MID = 6 # 3段石柱・中段 (root_offset: 1)
T_PILLAR_BOT = 7 # 3段石柱・下段 (root_offset: 0, solid: true)
T_STELE_TOP  = 8  # 2段蒼石碑・上段 (root_offset: 1)
T_STELE_BOT  = 9  # 2段蒼石碑・下段 (root_offset: 0, solid: true)
T_WATER      = 10 # 水場・アニメコマ0 (代表タイルID, solid: true)
T_WATER_1    = 11 # 水場・アニメコマ1
T_WATER_2    = 12 # 水場・アニメコマ2
T_WATER_3    = 13 # 水場・アニメコマ3
T_BUSH       = 14 # 背の高い草・アニメコマ0 (代表タイルID, solid: false, Yソート対象)
T_BUSH_1     = 15 # 背の高い草・アニメコマ1
T_BUSH_2     = 16 # 背の高い草・アニメコマ2
T_BUSH_3     = 17 # 背の高い草・アニメコマ3
T_HIGH_FLOOR      = 18 # 高台の上面石床 (明るい石畳)
T_CLIFF_SOUTH     = 19 # 高台の南側崖面 (正面の垂直段差壁・ジャンプで飛び越え可能)
T_CLIFF_EDGE      = 20 # 高台の北/東西フチ石 (rotate: 90/270 で東西の縁に対応)
T_CLIFF_CORNER_NW = 21 # 高台の北西角フチ石 (flip_h: true で北東角に対応)
T_CLIFF_CORNER_SW = 22 # 高台の南西角崖面 (flip_h: true で南東角に対応)

# クォータービューの奥行きパースに合わせて縦移動を 80% に補正
Y_RATIO        = 0.8
PLATEAU_HEIGHT = 18.0 # 高台の標高 (18px: 南側崖面の垂直レンガ壁の高さと一致)

# 高台上面のスクリーン/ワールド矩形 [x, y, w, h] (Window.clip による高台上の影クリッピング用)
PLATEAU_TOP_RECTS = [
  [24 * TILE_SIZE + 3,  4 * TILE_SIZE + 3, 6 * TILE_SIZE - 6, 4 * TILE_SIZE + 6], # 北東の高台
  [10 * TILE_SIZE + 3, 15 * TILE_SIZE + 3, 6 * TILE_SIZE - 6, 4 * TILE_SIZE + 6]  # 南西の高台
].freeze

SHADOW_COLOR_RGB = [10, 12, 18].freeze
SHADOW_Z         = -10.0
GROUND_Z         = -100.0
EFFECT_Z         = 2000.0
HP_BAR_Z         = 2100.0

# ==============================================================================
# タイルセット生成 (32x32 × 23種類 = 736x32) & マップ構築
# ==============================================================================
def create_dungeon_tileset
  tileset = Zenoo::Image.new(TILE_SIZE * 23, TILE_SIZE)
  Zenoo::Image.render_to(tileset) do
    Zenoo::Window.clear([0, 0, 0, 0])

    # 0: 苔むしたダーク草原床
    Zenoo::Window.draw_rect(0, 0, 32, 32, color: [30, 42, 46, 255])
    Zenoo::Window.draw_rect(4, 6, 4, 2, color: [40, 58, 58, 255])
    Zenoo::Window.draw_rect(20, 14, 5, 2, color: [36, 52, 54, 255])
    Zenoo::Window.draw_rect(10, 24, 4, 2, color: [42, 62, 60, 255])

    # 1: 石畳の道
    ox = 32
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [46, 52, 66, 255])
    Zenoo::Window.draw_rect(ox + 1, 1, 14, 14, radius: 2, color: [58, 66, 82, 255])
    Zenoo::Window.draw_rect(ox + 17, 1, 14, 14, radius: 2, color: [54, 62, 78, 255])
    Zenoo::Window.draw_rect(ox + 1, 17, 14, 14, radius: 2, color: [52, 60, 76, 255])
    Zenoo::Window.draw_rect(ox + 17, 17, 14, 14, radius: 2, color: [60, 68, 84, 255])

    # 2: 紋章石床
    ox = 64
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [46, 52, 66, 255])
    Zenoo::Window.draw_rect(ox + 2, 2, 28, 28, radius: 3, color: [56, 64, 82, 255], border_width: 1, border_color: [80, 110, 145, 255])
    Zenoo::Window.draw_circle(ox + 16, 16, 6, color: [45, 85, 120, 255], border_width: 1, border_color: [90, 170, 220, 255])

    # 3: 石レンガ壁 (1マス障害物)
    ox = 96
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [40, 44, 56, 255])
    # 上面 (明るい石面)
    Zenoo::Window.draw_rect(ox + 1, 1, 30, 16, radius: 2, color: [92, 102, 124, 255], border_width: 1, border_color: [120, 132, 156, 255])
    # 前面 (陰影のあるレンガ側面)
    Zenoo::Window.draw_rect(ox + 1, 17, 30, 14, color: [62, 70, 88, 255])
    Zenoo::Window.draw_line(ox + 1, 24, ox + 31, 24, width: 1, color: [42, 48, 62, 255])
    Zenoo::Window.draw_line(ox + 16, 17, ox + 16, 24, width: 1, color: [42, 48, 62, 255])
    Zenoo::Window.draw_line(ox + 9, 24, ox + 9, 31, width: 1, color: [42, 48, 62, 255])
    Zenoo::Window.draw_line(ox + 23, 24, ox + 23, 31, width: 1, color: [42, 48, 62, 255])

    # 4: 木箱・クレート (1マス障害物)
    ox = 128
    Zenoo::Window.draw_rect(ox + 2, 2, 28, 28, radius: 3, color: [110, 74, 42, 255], border_width: 2, border_color: [68, 44, 24, 255])
    Zenoo::Window.draw_rect(ox + 4, 4, 24, 12, radius: 2, color: [148, 102, 58, 255])
    Zenoo::Window.draw_line(ox + 5, 5, ox + 27, 27, width: 2, color: [88, 58, 32, 255])
    Zenoo::Window.draw_line(ox + 27, 5, ox + 5, 27, width: 2, color: [88, 58, 32, 255])
    Zenoo::Window.draw_rect(ox + 4, 4, 24, 24, radius: 2, color: :clear, border_width: 2, border_color: [165, 118, 70, 255])

    # 5: 3段石柱・上段 (柱頭 + 蒼クリスタル装飾)
    ox = 160
    Zenoo::Window.draw_rect(ox + 3, 6, 26, 10, radius: 2, color: [130, 142, 168, 255], border_width: 1, border_color: [170, 185, 210, 255])
    Zenoo::Window.draw_rect(ox + 5, 16, 22, 16, color: [105, 118, 142, 255])
    Zenoo::Window.draw_line(ox + 10, 16, ox + 10, 32, width: 2, color: [82, 92, 114, 255])
    Zenoo::Window.draw_line(ox + 16, 16, ox + 16, 32, width: 2, color: [135, 148, 175, 255])
    Zenoo::Window.draw_line(ox + 22, 16, ox + 22, 32, width: 2, color: [75, 85, 106, 255])
    Zenoo::Window.draw_circle(ox + 16, 11, 4, color: [0, 210, 255, 255], border_width: 1, border_color: :white)

    # 6: 3段石柱・中段 (柱身・縦溝)
    ox = 192
    Zenoo::Window.draw_rect(ox + 5, 0, 22, 32, color: [105, 118, 142, 255])
    Zenoo::Window.draw_line(ox + 6, 0, ox + 6, 32, width: 2, color: [135, 148, 175, 255])
    Zenoo::Window.draw_line(ox + 10, 0, ox + 10, 32, width: 2, color: [82, 92, 114, 255])
    Zenoo::Window.draw_line(ox + 16, 0, ox + 16, 32, width: 2, color: [135, 148, 175, 255])
    Zenoo::Window.draw_line(ox + 22, 0, ox + 22, 32, width: 2, color: [75, 85, 106, 255])
    Zenoo::Window.draw_line(ox + 26, 0, ox + 26, 32, width: 2, color: [62, 70, 90, 255])

    # 7: 3段石柱・下段 (柱脚・台座)
    ox = 224
    Zenoo::Window.draw_ellipse(ox + 16, 27, 15, 5, color: [10, 12, 18, 140])
    Zenoo::Window.draw_rect(ox + 5, 0, 22, 16, color: [105, 118, 142, 255])
    Zenoo::Window.draw_line(ox + 10, 0, ox + 10, 16, width: 2, color: [82, 92, 114, 255])
    Zenoo::Window.draw_line(ox + 16, 0, ox + 16, 16, width: 2, color: [135, 148, 175, 255])
    Zenoo::Window.draw_line(ox + 22, 0, ox + 22, 16, width: 2, color: [75, 85, 106, 255])
    Zenoo::Window.draw_rect(ox + 3, 14, 26, 8, radius: 2, color: [120, 132, 158, 255], border_width: 1, border_color: [70, 80, 100, 255])
    Zenoo::Window.draw_rect(ox + 1, 20, 30, 10, radius: 2, color: [88, 98, 120, 255], border_width: 1, border_color: [55, 62, 80, 255])

    # 8: 2段蒼石碑・上段
    ox = 256
    Zenoo::Window.draw_triangle(ox + 16, 4, ox + 5, 32, ox + 27, 32, color: [[100, 220, 255, 255], [45, 110, 165, 255], [30, 80, 130, 255]])
    Zenoo::Window.draw_line(ox + 16, 6, ox + 16, 32, width: 2, color: [180, 245, 255, 220])

    # 9: 2段蒼石碑・下段 (台座)
    ox = 288
    Zenoo::Window.draw_ellipse(ox + 16, 27, 14, 5, color: [10, 12, 18, 140])
    Zenoo::Window.draw_rect(ox + 5, 0, 22, 18, color: [40, 95, 145, 255])
    Zenoo::Window.draw_line(ox + 16, 0, ox + 16, 16, width: 2, color: [160, 235, 255, 200])
    Zenoo::Window.draw_rect(ox + 2, 16, 28, 12, radius: 3, color: [78, 88, 110, 255], border_width: 1, border_color: [115, 128, 155, 255])

    # 10..13: 水場アニメーションタイル (4コマ: 波紋の揺らぎと水面ハイライトの推移)
    4.times do |f|
      ox = (10 + f) * 32
      phase = f * (Math::PI / 2.0)
      shift_x = (Math.sin(phase) * 3.0).round
      shift_y = (Math.cos(phase) * 1.5).round

      # 深い水底ベースと微かな陰影枠
      Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [18, 52, 86, 255])
      Zenoo::Window.draw_rect(ox + 1, 1, 30, 30, radius: 3, color: [24, 68, 110, 255])

      # 水中を漂う柔らかい明暗の楕円
      Zenoo::Window.draw_ellipse(ox + 11 + shift_x, 10 + shift_y, 8, 4, color: [34, 92, 145, 190])
      Zenoo::Window.draw_ellipse(ox + 21 - shift_x, 22 - shift_y, 9, 4, color: [30, 82, 132, 190])

      # 3本の波紋ライン (コマごとに左右・上下へ滑らかに位相シフト)
      w1_x = ox + 5 + ((f * 4) % 10)
      w2_x = ox + 13 - ((f * 3) % 8)
      w3_x = ox + 7 + (((f + 2) * 4) % 10)
      Zenoo::Window.draw_line(w1_x, 7 + shift_y, w1_x + 11, 7 + shift_y, width: 2.0, cap: :round, color: [75, 175, 235, 220])
      Zenoo::Window.draw_line(w2_x, 16 - shift_y, w2_x + 12, 16 - shift_y, width: 2.0, cap: :round, color: [95, 195, 250, 230])
      Zenoo::Window.draw_line(w3_x, 25 + shift_y, w3_x + 10, 25 + shift_y, width: 2.0, cap: :round, color: [65, 160, 225, 210])

      # 水面のきらめき (白〜シアンのハイライト粒)
      glint_x = ox + (f.even? ? 10 + f * 3 : 22 - f * 2)
      glint_y = f < 2 ? 11 + f * 8 : 23 - (f - 2) * 8
      Zenoo::Window.draw_circle(glint_x, glint_y, 1.8, color: [200, 248, 255, 240])
    end

    # 14..17: 風に揺れる背の高い草タイル (4コマ: 根元は固定、葉先だけが左右にしなる背景透過タイル)
    # Coma 0: 中央, Coma 1: 右へなびく, Coma 2: 中央戻り, Coma 3: 左へ少ししなる
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

      # 根元の接地シャドウ (y = 29 付近に固定)
      Zenoo::Window.draw_ellipse(ox + 16, 29, 12, 3, color: [10, 14, 18, 130])

      # 奥側の葉 (3枚: 少し暗めのエメラルド、根元 y=29 から上へ伸びる)
      Zenoo::Window.draw_triangle(ox + 7 + sw, 11 + dp, ox + 6,  29, ox + 12, 29, color: [tip_back, base_dark, base_dark])
      Zenoo::Window.draw_triangle(ox + 16 + sw, 7 + dp, ox + 12, 29, ox + 19, 29, color: [tip_back, base_dark, base_dark])
      Zenoo::Window.draw_triangle(ox + 25 + sw, 12 + dp, ox + 19, 29, ox + 26, 29, color: [tip_back, base_dark, base_dark])

      # 手前側の鮮やかな葉 (4枚: 明るいミント〜ライムグラデーション、根元 y=30)
      Zenoo::Window.draw_triangle(ox + 4 + (sw * 0.8).round, 15 + dp, ox + 5, 30, ox + 11, 30, color: [tip_front, base_mid, base_dark])
      Zenoo::Window.draw_triangle(ox + 12 + sw, 8 + dp,  ox + 9,  30, ox + 16, 30, color: [tip_glow,  base_mid, base_dark])
      Zenoo::Window.draw_triangle(ox + 20 + sw, 9 + dp,  ox + 15, 30, ox + 22, 30, color: [tip_front, base_mid, base_dark])
      Zenoo::Window.draw_triangle(ox + 27 + (sw * 1.1).round, 14 + dp, ox + 20, 30, ox + 27, 30, color: [tip_glow,  base_mid, base_dark])

      # 葉先で揺れる小さな蛍光胞子ドット
      Zenoo::Window.draw_circle(ox + 12 + sw, 8 + dp, 1.5, color: [210, 255, 225, 240])
    end

    # 18: 高台の上面石床 (平地の石畳より明るく、1段高いことを視覚的に示す)
    ox = 18 * 32
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [72, 84, 108, 255])
    Zenoo::Window.draw_rect(ox + 1, 1, 14, 14, radius: 2, color: [92, 106, 134, 255])
    Zenoo::Window.draw_rect(ox + 17, 1, 14, 14, radius: 2, color: [86, 100, 128, 255])
    Zenoo::Window.draw_rect(ox + 1, 17, 14, 14, radius: 2, color: [84, 98, 126, 255])
    Zenoo::Window.draw_rect(ox + 17, 17, 14, 14, radius: 2, color: [96, 110, 138, 255])

    # 19: 高台の南側崖面 (正面に見える垂直な石積みの段差壁 + 地面への落ち影)
    ox = 19 * 32
    Zenoo::Window.draw_rect(ox, 0, 32, 28, color: [30, 36, 48, 255])
    # 上端の明るい縁石リップ (y: 0..8) + 境界線 (y: 9)
    Zenoo::Window.draw_rect(ox, 0, 32, 9, color: [130, 148, 180, 255])
    Zenoo::Window.draw_rect(ox, 0, 32, 2, color: [175, 195, 225, 255])
    Zenoo::Window.draw_rect(ox + 15, 2, 2, 7, color: [90, 105, 132, 255])
    Zenoo::Window.draw_rect(ox, 9, 32, 1, color: [36, 42, 56, 255])
    # 中段の垂直な崖側面レンガ (y: 10..27)
    Zenoo::Window.draw_rect(ox, 10, 32, 18, color: [56, 66, 86, 255])
    Zenoo::Window.draw_rect(ox, 19, 32, 1, color: [38, 44, 58, 255])
    Zenoo::Window.draw_rect(ox + 8, 10, 1, 9, color: [38, 44, 58, 255])
    Zenoo::Window.draw_rect(ox + 24, 10, 1, 9, color: [38, 44, 58, 255])
    Zenoo::Window.draw_rect(ox + 16, 20, 1, 8, color: [38, 44, 58, 255])
    # 下端の半透明接地シャドウ (y: 28..31、下の地面や地面側のキャラ影が透けて見える)
    Zenoo::Window.draw_rect(ox, 28, 32, 4, color: [12, 15, 22, 165])

    # 20: 高台の北・東西フチ石 (上端に段差の縁石と影を持つタイル、rotate: 90/270 で東西に対応)
    ox = 20 * 32
    Zenoo::Window.draw_rect(ox, 3, 32, 29, color: [72, 84, 108, 255])
    Zenoo::Window.draw_rect(ox + 1, 11, 14, 9, radius: 2, color: [90, 104, 132, 255])
    Zenoo::Window.draw_rect(ox + 17, 11, 14, 9, radius: 2, color: [86, 100, 128, 255])
    Zenoo::Window.draw_rect(ox + 1, 22, 30, 9, radius: 2, color: [92, 106, 134, 255])
    # 外周側の半透明落ち影 (y: 0..2)、縁石 (y: 3..8)、ハイライト (y: 3..4)、内側境界 (y: 9)
    Zenoo::Window.draw_rect(ox, 0, 32, 3, color: [14, 18, 26, 165])
    Zenoo::Window.draw_rect(ox, 3, 32, 6, color: [130, 148, 180, 255])
    Zenoo::Window.draw_rect(ox, 3, 32, 2, color: [180, 200, 230, 255])
    Zenoo::Window.draw_rect(ox, 9, 32, 1, color: [52, 62, 82, 255])

    # 21: 高台の北西角フチ石 (上端と左端の縁石がL字に直交、flip_h: true で北東角に対応)
    ox = 21 * 32
    Zenoo::Window.draw_rect(ox + 3, 3, 29, 29, color: [72, 84, 108, 255])
    Zenoo::Window.draw_rect(ox + 11, 11, 9, 9, radius: 2, color: [90, 104, 132, 255])
    Zenoo::Window.draw_rect(ox + 22, 11, 9, 9, radius: 2, color: [86, 100, 128, 255])
    Zenoo::Window.draw_rect(ox + 11, 22, 20, 9, radius: 2, color: [92, 106, 134, 255])
    # 上端・左端のL字半透明落ち影 (幅3px)
    Zenoo::Window.draw_rect(ox, 0, 32, 3, color: [14, 18, 26, 165])
    Zenoo::Window.draw_rect(ox, 3, 3, 29, color: [14, 18, 26, 165])
    # 内側1px境界線 (x=9, y=9)
    Zenoo::Window.draw_rect(ox + 9, 9, 23, 1, color: [52, 62, 82, 255])
    Zenoo::Window.draw_rect(ox + 9, 9, 1, 23, color: [52, 62, 82, 255])
    # L字の縁石本体 (幅6px: 3..8)
    Zenoo::Window.draw_rect(ox + 3, 3, 29, 6, color: [130, 148, 180, 255])
    Zenoo::Window.draw_rect(ox + 3, 3, 6, 29, color: [130, 148, 180, 255])
    # L字の外周ハイライト (幅2px: 3..4)
    Zenoo::Window.draw_rect(ox + 3, 3, 29, 2, color: [180, 200, 230, 255])
    Zenoo::Window.draw_rect(ox + 3, 3, 2, 29, color: [180, 200, 230, 255])

    # 22: 高台の南西角崖面 (左端の縁石と南側の垂直崖面がL字に接続、flip_h: true で南東角に対応)
    ox = 22 * 32
    # 左外周の落ち影 (x: 0..2) と下端の接地シャドウ (y: 28..31)
    Zenoo::Window.draw_rect(ox, 0, 3, 28, color: [14, 18, 26, 165])
    Zenoo::Window.draw_rect(ox + 3, 28, 29, 4, color: [12, 15, 22, 165])
    # 垂直な崖側面レンガ (x: 3..31, y: 10..27) + 左端のエッジハイライト
    Zenoo::Window.draw_rect(ox + 3, 10, 29, 18, color: [56, 66, 86, 255])
    Zenoo::Window.draw_rect(ox + 3, 10, 2, 18, color: [78, 92, 118, 255])
    Zenoo::Window.draw_rect(ox + 3, 19, 29, 1, color: [38, 44, 58, 255])
    Zenoo::Window.draw_rect(ox + 14, 10, 1, 9, color: [38, 44, 58, 255])
    Zenoo::Window.draw_rect(ox + 22, 20, 1, 8, color: [38, 44, 58, 255])
    # 上部のL字縁石リップ (x: 3..31, y: 0..8) と境界線 (y: 9)
    Zenoo::Window.draw_rect(ox + 3, 0, 29, 9, color: [130, 148, 180, 255])
    Zenoo::Window.draw_rect(ox + 3, 0, 2, 9, color: [180, 200, 230, 255])
    Zenoo::Window.draw_rect(ox + 9, 0, 23, 2, color: [175, 195, 225, 255])
    Zenoo::Window.draw_rect(ox + 9, 0, 1, 2, color: [52, 62, 82, 255])
    Zenoo::Window.draw_rect(ox + 3, 9, 29, 1, color: [36, 42, 56, 255])
  end
  tileset.slice_tiles(tile_width: TILE_SIZE, tile_height: TILE_SIZE)
end

def create_world_tilemap
  tiles = create_dungeon_tileset
  map = Zenoo::Tilemap.new(tiles)

  # 1マス障害物タイルの設定 (水場も solid: true で通行不可＆MTV壁ずり対応)
  # ※ T_BUSH (背の高い草) は solid を設定しないため solid: false (すり抜け可能) になる
  map.set_tile(T_WALL,  solid: true)
  map.set_tile(T_CRATE, solid: true)
  map.set_tile(T_WATER, solid: true)

  # 高台上面タイルの高さ (標高) 設定
  # ※ 南端の垂直な崖壁面 (T_CLIFF_SOUTH, T_CLIFF_CORNER_SW) は側面なので除外し、上面タイル (r0..r1-1) のみに高さを設定する
  [T_HIGH_FLOOR, T_CLIFF_EDGE, T_CLIFF_CORNER_NW].each do |tid|
    map.set_tile(tid, height: PLATEAU_HEIGHT)
  end

  # ★ タイルアニメーション定義 (IBO インデックス書き換えによる高速4コマアニメ)
  map.define_animation(T_WATER, frames: [T_WATER, T_WATER_1, T_WATER_2, T_WATER_3], wait: 14)
  map.define_animation(T_BUSH,  frames: [T_BUSH,  T_BUSH_1,  T_BUSH_2,  T_BUSH_3],  wait: 12)

  # ★ 縦連結オブジェクトの一括定義！
  # 上段パーツは自動的に根元(最下段)の行Meshへ帰属し、根元のみが solid: true になる
  map.define_column([T_PILLAR_TOP, T_PILLAR_MID, T_PILLAR_BOT], solid: true)
  map.define_column([T_STELE_TOP,  T_STELE_BOT],                solid: true)

  # 1. 床レイヤー (40x24)
  ground = Array.new(MAP_ROWS) { Array.new(MAP_COLS, T_GRASS) }
  MAP_ROWS.times do |r|
    MAP_COLS.times do |c|
      # 中央の十字大回廊と外周の石畳ルート
      if (r >= 10 && r <= 13) || (c >= 18 && c <= 21) ||
         ((r == 4 || r == 19) && c >= 4 && c <= 35) ||
         ((c == 6 || c == 33) && r >= 4 && r <= 19)
        ground[r][c] = ((r + c) % 7 == 0) ? T_ACCENT : T_PAVE
      elsif r >= 8 && r <= 15 && c >= 15 && c <= 24
        ground[r][c] = ((r == 9 || r == 14) && (c == 16 || c == 23)) ? T_ACCENT : T_PAVE
      end
    end
  end

  # 北西・南東の2箇所に大きめの水場 (5x4マス = 160x128px の池) を配置
  water_flipped = Zenoo::Tilemap.tile(T_WATER, flip_h: true)
  place_pond = lambda do |c_range, r_range|
    r_range.each do |r|
      c_range.each do |c|
        ground[r][c] = (r + c).odd? ? water_flipped : T_WATER
      end
    end
  end

  place_pond.call(10..14, 5..8)   # 北西の池 (5x4マス)
  place_pond.call(25..29, 15..18) # 南東の池 (5x4マス)

  # 2. 段差 (高台) レイヤー (40x24)
  # - 北端行 (r == r0) のみ cliffs_north (y_sort: true) に置いて裏側に回り込んだキャラの足元を隠し、
  # - 残りの行 (r > r0) は cliffs (z: 0.0, y_sort: false) に置くことで、
  #   地面の影 (SHADOW_Z = -10.0) は高台の下に隠しつつ、東西横に並んだスライム等がタイル境目で欠けるのを防ぐ
  cliffs       = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }
  cliffs_north = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }
  cliff_north = T_CLIFF_EDGE
  cliff_east  = Zenoo::Tilemap.tile(T_CLIFF_EDGE, rotate: 90)
  cliff_west  = Zenoo::Tilemap.tile(T_CLIFF_EDGE, rotate: 270)
  cliff_nw    = T_CLIFF_CORNER_NW
  cliff_ne    = Zenoo::Tilemap.tile(T_CLIFF_CORNER_NW, flip_h: true)
  cliff_sw    = T_CLIFF_CORNER_SW
  cliff_se    = Zenoo::Tilemap.tile(T_CLIFF_CORNER_SW, flip_h: true)

  place_plateau = lambda do |c_range, r_range|
    c0, c1 = c_range.begin, c_range.end
    r0, r1 = r_range.begin, r_range.end
    r_range.each do |r|
      c_range.each do |c|
        if r == r0 && c == c0
          # 北西角: L字縁石 (北端レイヤー)
          cliffs_north[r][c] = cliff_nw
        elsif r == r0 && c == c1
          # 北東角: L字縁石・左右反転 (北端レイヤー)
          cliffs_north[r][c] = cliff_ne
        elsif r == r0
          # 北端: 北向きの縁石 (北端レイヤー)
          cliffs_north[r][c] = cliff_north
        elsif r == r1 && c == c0
          # 南西角: 西縁石 + 南崖面
          cliffs[r][c] = cliff_sw
        elsif r == r1 && c == c1
          # 南東角: 東縁石 + 南崖面 (左右反転)
          cliffs[r][c] = cliff_se
        elsif r == r1
          # 南端: 垂直な段差の崖面
          cliffs[r][c] = T_CLIFF_SOUTH
        elsif c == c0
          # 西端: 西向きの縁石
          cliffs[r][c] = cliff_west
        elsif c == c1
          # 東端: 東向きの縁石
          cliffs[r][c] = cliff_east
        else
          # 高台の内側: 明るい高台床 (T_HIGH_FLOOR に設定された height: PLATEAU_HEIGHT が適用される)
          cliffs[r][c] = T_HIGH_FLOOR
        end
      end
    end
  end

  # 北東・南西の2箇所にジャンプで乗り降りできる高台 (6x5マス = 192x160px, 内側4x3マス) を配置
  place_plateau.call(24..29, 4..8)   # 北東の高台
  place_plateau.call(10..15, 15..19) # 南西の高台

  # 3. 立体オブジェクト・障害物レイヤー (40x24, 行単位 Yソート有効)
  objects = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }

  # 外周の石レンガ壁
  MAP_COLS.times do |c|
    objects[0][c] = T_WALL
    objects[MAP_ROWS - 1][c] = T_WALL
  end
  MAP_ROWS.times do |r|
    objects[r][0] = T_WALL
    objects[r][MAP_COLS - 1] = T_WALL
  end

  # 3段の石柱を配置するヘルパー (root_c, root_r が根元の座標)
  place_pillar = lambda do |c, root_r|
    objects[root_r - 2][c] = T_PILLAR_TOP
    objects[root_r - 1][c] = T_PILLAR_MID
    objects[root_r][c]     = T_PILLAR_BOT
  end

  # 2段の蒼石碑を配置するヘルパー
  place_stele = lambda do |c, root_r|
    objects[root_r - 1][c] = T_STELE_TOP
    objects[root_r][c]     = T_STELE_BOT
  end

  # 中央広場の4本の大石柱 (後ろに回り込める＆手前に立つとキャラの頭が手前に出る！)
  place_pillar.call(16, 9)
  place_pillar.call(23, 9)
  place_pillar.call(16, 15)
  place_pillar.call(23, 15)

  # 西エリア・東エリアの並木柱
  place_pillar.call(9,  8)
  place_pillar.call(9,  15)
  place_pillar.call(30, 8)
  place_pillar.call(30, 15)

  # 北西・北東・南西・南東の蒼石碑
  place_stele.call(5,  5)
  place_stele.call(34, 5)
  place_stele.call(5,  19)
  place_stele.call(34, 19)
  place_stele.call(19, 4)
  place_stele.call(20, 20)

  # 西・東エリアの木箱群 (壁ずり移動のテスト用)
  [
    [4, 11, T_CRATE], [4, 12, T_CRATE], [5, 12, T_CRATE],
    [35, 11, T_CRATE], [35, 12, T_CRATE], [34, 11, T_CRATE]
  ].each do |c, r, tid|
    objects[r][c] = tid
  end

  # ★ 草原床の上に「風に揺れる背の高い草 (T_BUSH)」を群生配置
  # objects レイヤー (y_sort: true) に置くことで、衝突判定なし (solid: false) のまま
  # 「草の根元より奥に立つとキャラの足元が草に隠れ、手前に出ると草の前に出る」が自動成立！
  place_bush_patch = lambda do |c_range, r_range|
    r_range.each do |r|
      c_range.each do |c|
        if ground[r][c] == T_GRASS && cliffs[r][c].nil? && cliffs_north[r][c].nil? && objects[r][c].nil?
          objects[r][c] = T_BUSH
        end
      end
    end
  end

  # 池のほとりの水辺草むら (北西の池の南岸・南東の池の北岸)
  place_bush_patch.call(10..13, 9..9)
  place_bush_patch.call(26..29, 14..14)

  # 西・東エリアの草原群生地
  place_bush_patch.call(7..8,   6..7)
  place_bush_patch.call(7..8,   16..17)
  place_bush_patch.call(31..32, 6..7)
  place_bush_patch.call(31..32, 16..17)
  place_bush_patch.call(2..4,   7..9)
  place_bush_patch.call(2..4,   15..17)
  place_bush_patch.call(35..37, 6..8)
  place_bush_patch.call(35..37, 14..16)

  map.add_layer(:ground,       ground,       z: GROUND_Z)
  map.add_layer(:cliffs,       cliffs,       z: 0.0)
  map.add_layer(:cliffs_north, cliffs_north, z: 0.0, y_sort: true)
  map.add_layer(:objects,      objects,      z: 0.0, y_sort: true)
  map
end

# ==============================================================================
# 標高 (height) を考慮した衝突解決 & 足元床標高の取得ヘルパー (方式2)
# ==============================================================================
TEMP_ELEV_WALL_RECT = Zenoo::Collision::Rect.new(0.0, 0.0, TILE_SIZE, TILE_SIZE, anchor: :top_left)
ELEV_CANDIDATES_BUF = []

# スプライトの現在の絶対高度 (altitude) より高いタイル、および solid タイルを壁として MTV 押し出し
def resolve_elevation_collision(sprite, altitude, tilemap)
  return false if sprite.nil? || tilemap.nil? || (sprite.respond_to?(:vanished?) && sprite.vanished?)
  col_shape = sprite.collider
  return false unless col_shape

  tw = tilemap.tile_width * tilemap.scale_x
  th = tilemap.tile_height * tilemap.scale_y
  return false if tw <= 0.0 || th <= 0.0

  cx = col_shape.center_x
  cy = col_shape.center_y
  br = col_shape.bounding_radius

  # 高台タイルは高さ (PLATEAU_HEIGHT) の分だけ接地座標が +Y (下) にずれるため、探索範囲の上端を広げる
  min_c = [((cx - br - tilemap.x) / tw).floor, 0].max
  max_c = [((cx + br - tilemap.x) / tw).floor, tilemap.cols - 1].min
  min_r = [((cy - PLATEAU_HEIGHT - br - tilemap.y) / th).floor, 0].max
  max_r = [((cy + br - tilemap.y) / th).floor, tilemap.rows - 1].min
  return false if min_c > max_c || min_r > max_r

  buf = ELEV_CANDIDATES_BUF
  buf.clear
  r = min_r
  while r <= max_r
    c = min_c
    while c <= max_c
      is_solid = tilemap.solid_cell?(c, r)
      th_elev  = tilemap.height_cell(c, r)
      # 通常の通行不可タイル、または「現在の自分の高度より高い段差タイル」を壁とみなす
      # 段差タイルの接地当たり判定は、見た目の上面描画位置から +th_elev (下) にずらす
      if is_solid || th_elev > altitude + 2.0
        wx = tilemap.x + c * tw
        wy = tilemap.y + r * th + (is_solid ? 0.0 : th_elev)
        dx = (wx + 0.5 * tw) - cx
        dy = (wy + 0.5 * th) - cy
        d2 = dx * dx + dy * dy
        pos = buf.size
        while pos >= 3 && buf[pos - 1] > d2
          pos -= 3
        end
        buf.insert(pos, wx, wy, d2)
      end
      c += 1
    end
    r += 1
  end

  return false if buf.empty?

  wall = TEMP_ELEV_WALL_RECT
  wall.width = tw if wall.width != tw
  wall.height = th if wall.height != th
  resolved_any = false
  pass = 0
  while pass < 2
    hit_in_pass = false
    i = 0
    len = buf.size
    while i < len
      wall.x = buf[i]
      wall.y = buf[i + 1]
      wall.update_cache
      if sprite.push_out_of(wall)
        hit_in_pass = true
        resolved_any = true
      end
      i += 3
    end
    break unless hit_in_pass
    pass += 1
  end
  resolved_any
end

# 足元コライダーが乗っている床の最大標高 (現在の高度以下の床) を取得
# 高台の床タイルは高さ (PLATEAU_HEIGHT) の分だけ画面上で上 (-Y) に描画されているため、
# Y座標を -PLATEAU_HEIGHT ずらして判定することで、高台の上での見た目の足元・影の位置と床の範囲が一致する
def support_floor_height(sprite, altitude, tilemap)
  return 0.0 if sprite.nil? || tilemap.nil?
  col = sprite.collider
  return tilemap.height_at(sprite.x, sprite.y - PLATEAU_HEIGHT) unless col

  cx = col.center_x
  cy = col.center_y
  rx = 6.0
  ry = 4.0
  max_h = 0.0
  # 足元中心と前後左右の接地5点で判定 (フチから完全に足が離れた瞬間に落下開始)
  [
    [cx, cy],
    [cx - rx, cy], [cx + rx, cy],
    [cx, cy - ry], [cx, cy + ry]
  ].each do |px, py|
    h = tilemap.height_at(px, py - PLATEAU_HEIGHT)
    max_h = h if h <= altitude + 2.0 && h > max_h
  end
  max_h
end

# ==============================================================================
# 斬撃円弧リボンエフェクト (Mesh.ring による白リボンメッシュ)
# ==============================================================================
class SlashEffect < Zenoo::Sprite
  LIFE     = 12
  CENTER_Y = 32.0 # プレイヤーの体・手元の高さ (足元から上へ 32px)

  # 120度円弧の白リボンメッシュ (半径 75px, 内径比率 0.6, 加算合成)
  # 左側（根本・振り始め）からアルファ値を下げてグラデーションにする (0: 透明 -> 255: 白)
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
    self.scale_y = player.facing_x # 左右反転時も振り下ろし方向・グラデーション向きを対称にする
    self.z = EFFECT_Z
    @timer = LIFE
  end

  def update
    # ★ 攻撃スライド・ジャンプ中もプレイヤーの移動と高さに完全追従！
    self.x = @player.x
    self.y = @player.y - @player.jump_z - CENTER_Y

    @timer -= 1
    t = @timer.to_f / LIFE
    self.alpha = (255.0 * t).clamp(0, 255).to_i
    self.scale = 1.0 + (1.0 - t) * 0.18 # 斬撃が外側へサッと広がる
    vanish if @timer <= 0
  end
end

# ==============================================================================
# ベクターグラフィックスによる潰れたスライム敵 (Mesh.canvas)
# ==============================================================================
def create_slime_mesh
  Zenoo::Mesh.canvas(90, 70) do |c|
    # 体のグラデーション (上部ミントグリーン → 下部ディープエメラルド)
    grad = c.create_linear_gradient(45, 15, 45, 68)
    grad.add_color_stop(0.0, [90,  255, 190, 255])
    grad.add_color_stop(1.0, [25,  145, 115, 255])

    # 潰れたスライム輪郭 (下端をキャンバス最底面にぴったり合わせて隙間を排除)
    c.begin_path
    steps = 32
    steps.times do |i|
      ang = i * (Math::PI * 2.0 / steps)
      ry = Math.sin(ang) > 0 ? 20.0 : 32.0 # 下側は平らめ、上側はふっくらドーム
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

    # ほっぺ (愛らしいピンク)
    c.fill_circle(26, 50, 4, [255, 120, 160, 150])
    c.fill_circle(64, 50, 4, [255, 120, 160, 150])
  end
end

class SlimeEnemy < Zenoo::Sprite
  BASE_SCALE    = 0.75
  MAX_HP        = 3
  BODY_CENTER_Y = 20.0  # 当たり判定の中心 (足元から上へ 20px)
  HOP_CYCLE     = 48    # ホップ周期 (フレーム)
  HOP_SPEED     = 2.2
  CHASE_RANGE   = 420.0 # プレイヤーを追跡する感知距離

  # 被弾時の 3 回バウンド: [フレーム数, 高さ] (大ホップ -> 中ホップ -> 小ホップ)
  BOUNCES     = [[16, 20.0], [12, 11.0], [8, 5.0]].freeze
  BOUNCE_END  = BOUNCES.sum(&:first) # 36
  HIT_TIME    = BOUNCE_END + 2       # バウンド後 2 フレームで通常形状へ復帰
  KB_FRICTION = 0.935
  ROUND_SX    = 0.86 # ジャンプ中の丸い形状 (縦長水滴型)
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

    # 足元の接地コライダー (楕円: スライムの scale_x=0.85 が乗算されるため radius_x: 24.0 で実効幅約 20px)
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
    # スライムは地上 (標高 0.0) を移動するため、高台 (標高 18.0) の壁とも衝突する
    resolve_elevation_collision(self, 0.0, tilemap)
    self.z = y
  end

  def hit(kb_x, kb_y)
    return if @dying # 撃破中は二重ヒットしない

    @hp -= 1
    @dying = true if @hp <= 0
    @hit_timer = HIT_TIME

    # 3回弾みながら遠くへノックバックする初速 (約 110px 後退、撃破時は少し豪快に)
    spd = @dying ? 8.2 : 7.6
    @vx = kb_x * spd
    @vy = kb_y * spd * Y_RATIO
  end

  # ★ 影 (SHADOW_Z) → 本体 (z = y) → 頭上HPドット (HP_BAR_Z) を draw 内で一括描画
  def draw
    return if vanished? || !visible

    # 1. 足元のドロップシャドウ (浮き上がり中は縮んで薄くなり、消滅時はフェードアウト)
    z_ratio = (1.0 - @jump_z / 40.0).clamp(0.45, 1.0)
    sw = 30.0 * (scale_x.abs / BASE_SCALE) * z_ratio
    sh = 11.5 * z_ratio
    a  = (140 * z_ratio * alpha / 255.0).to_i
    Zenoo::Window.draw_ellipse(x, y - 3.0, sw, sh, color: [*SHADOW_COLOR_RGB, a], z: SHADOW_Z)

    # 2. スライム本体 (ジャンプ高さ分だけ上に浮かせて描画、Z値は地面の y を維持)
    self.z = y
    orig_y = y
    self.y -= @jump_z
    super
    self.y = orig_y

    # 3. 頭上 HP ドット
    unless @dying
      hp_y = y - @jump_z - 64.0
      MAX_HP.times do |i|
        Zenoo::Window.draw_circle(x.to_i - 12 + i * 12, hp_y, 3.5, color: i < @hp ? HP_ON_COLOR : HP_OFF_COLOR, z: HP_BAR_Z)
      end
    end
  end

  private

  # 被弾ノックバック: 丸い形状のまま 3 回弾みながら遠くへ吹き飛ぶ。戻り値は [sx, sy]
  def update_knockback
    @hit_timer -= 1
    elapsed = HIT_TIME - @hit_timer

    self.x += @vx
    self.y += @vy
    @vx *= KB_FRICTION
    @vy *= KB_FRICTION

    @jump_z = bounce_height(elapsed)

    # 被弾点滅 (通常被弾は 10 フレーム、撃破時は第2バウンドまで)
    flash = @dying ? 24 : 10
    self.color = elapsed < flash ? (elapsed.even? ? FLASH_COLOR : :white) : nil

    # 撃破時: 第3バウンド中にフェードアウトし、終了時に消滅
    if @dying
      self.alpha = (255.0 * (1.0 - (elapsed - 26) / 12.0)).clamp(0, 255).to_i if elapsed >= 26
      vanish if @hit_timer <= 0
    end

    return [ROUND_SX, ROUND_SY] if elapsed < BOUNCE_END

    # バウンド終了後、通常形状へ滑らかに復帰
    t = (elapsed - BOUNCE_END) / 2.0
    [ROUND_SX + (1.0 - ROUND_SX) * t, ROUND_SY + (1.0 - ROUND_SY) * t]
  end

  # BOUNCES テーブルから現在の跳ね高さを求める
  def bounce_height(elapsed)
    start = 0
    BOUNCES.each do |len, height|
      return Math.sin((elapsed - start).to_f / len * Math::PI) * height if elapsed < start + len
      start += len
    end
    0.0
  end

  # 通常時: プレイヤーへ向かってぷるぷるホップ。戻り値は [sx, sy]
  def update_hop(target_x, target_y)
    dx = target_x - x
    dy = (target_y - 16.0) - y
    dist = Math.hypot(dx, dy)
    @facing_x = (dx >= 0 ? 1.0 : -1.0) if dist > 10.0 && dist < CHASE_RANGE

    @hop_tick = (@hop_tick + 1) % HOP_CYCLE
    @jump_z = 0.0

    if @hop_tick < 14
      # 1. ジャンプ準備: グッと横に潰れてタメる
      t = @hop_tick / 14.0
      [1.0 + t * 0.22, 1.0 - t * 0.18]
    elsif @hop_tick < 34
      # 2. ホップ空中: 縦長に伸びて少し浮きながら前進！
      @jump_z = Math.sin((@hop_tick - 14) / 20.0 * Math::PI) * 8.0
      if dist > 32.0 && dist < CHASE_RANGE
        self.x += dx / dist * HOP_SPEED
        self.y += dy / dist * HOP_SPEED * Y_RATIO
      end
      [ROUND_SX, ROUND_SY]
    elsif @hop_tick < 42
      # 3. 着地: ボヨンと横に弾む
      t = (@hop_tick - 34) / 8.0
      [1.18 - t * 0.12, 0.84 + t * 0.12]
    else
      # 4. 通常形状
      [1.0, 1.0]
    end
  end
end

# ==============================================================================
# 斜め4方向プレイヤー
# ==============================================================================
class IsoPlayer < Zenoo::Sprite
  SPEED         = 4.2
  ATTACK_DASH   = 6.5  # 踏み込み初速 (入力の強弱に関わらず常にフルパワー)
  DASH_FRICTION = 0.85
  HIT_FRAMES    = 12   # 攻撃判定の持続フレーム (斬撃エフェクトの寿命と同じ)
  JUMP_SPEED    = 6.2  # ジャンプ初速
  GRAVITY       = 0.48 # 重力加速度

  # 斬撃判定: エフェクト半径(約75〜88px) + 敵の当たり半径(約25px)
  SLASH_REACH   = 115.0
  COS_75        = Math.cos(75.0 * Math::PI / 180.0) # 前方 150 度
  COS_85        = Math.cos(85.0 * Math::PI / 180.0) # 至近距離 (40px 以内) は前方 170 度
  CLOSE_RANGE   = 40.0

  DIR_DOWN = 0 # 手前 (右下アングル)
  DIR_UP   = 1 # 奥 (右上アングル)

  # 静的シンボル配列 (動的シンボル生成・ヒープ割り当てゼロ)
  WALK_ANIMS   = [:walk_down,   :walk_up].freeze
  IDLE_ANIMS   = [:idle_down,   :idle_up].freeze
  ATTACK_ANIMS = [:attack_down, :attack_up].freeze

  WALK_FRAME_NAMES = ["0 (左足)", "1 (直立)", "2 (右足)", "1 (直立)"].freeze

  attr_reader   :facing_x, :attacking, :altitude, :ground_h
  attr_accessor :effects, :enemies, :tilemap
  alias jump_z altitude

  def initialize(x, y)
    # ★ 見下ろしアクションの鉄則: 足元・接地点基準 (bottom_center)
    super(x, y, anchor: :bottom_center, pivot: :bottom_center)

    # 向き管理: 手前 (DIR_DOWN) / 奥 (DIR_UP)、左右 (1.0: 右 / -1.0: 左)
    @dir_y = DIR_DOWN
    @facing_x = 1.0
    @attacking = false
    @vx = 0.0
    @vy = 0.0
    @altitude = 0.0 # 絶対高度 (平地: 0.0, 高台の上: 18.0, ジャンプ中はさらに上昇)
    @ground_h = 0.0 # 足元マスの床の標高 (Tilemap#height_at から毎フレーム取得)
    @vz = 0.0
    @effects = nil
    @enemies = nil
    @tilemap = nil
    @attack_timer = 0
    @hit_targets = {}
    @atk_nx = 1.0 # 画面上での攻撃方向 (正規化済み)
    @atk_ny = 0.0
    @last_move_dx = 1.0 # 最後に移動した方向ベクトル (正規化済み)
    @last_move_dy = 1.0

    @slash_mesh = SlashEffect.create_mesh

    load_animations
    play(IDLE_ANIMS[@dir_y])

    # ★ 足元の接地コライダー (横半径11px, 縦半径8px の楕円、anchor: :bottom_center で足元 y - 8px に配置)
    set_collider(:circle, radius_x: 11.0, radius_y: 8.0, anchor: :bottom_center, offset_y: -8.0)
    self.z = y
  end

  def update
    # 1. 現在の床上に接地している時のみジャンプ開始可能
    if @altitude <= @ground_h && @vz <= 0.0 && Zenoo::Input.action_push?(:jump)
      @vz = JUMP_SPEED
    end

    # 2. 水平移動 / 攻撃スライド
    if @attacking
      update_attack
    elsif Zenoo::Input.action_push?(:attack) # 押下の瞬間のみトリガー
      start_attack
    else
      update_move
    end

    super # アニメーション更新 (update_animation)

    # 3. 方式2の衝突解決: 自分の現在の絶対高度 (@altitude) より高いタイル・壁のみと衝突
    #    - 地上 (@altitude = 0) では高台 (height = 18) が壁になる
    #    - ジャンプして @altitude >= 18 になると高台へ入れる
    #    - 高台 (@altitude = 18) から平地 (height = 0) へは壁なしで歩いてそのまま飛び降りられる！
    resolve_elevation_collision(self, @altitude, @tilemap)

    # 4. 移動・衝突解決後の位置から「足元の床の標高 (@ground_h)」を取得し、重力・着地を更新
    @ground_h = support_floor_height(self, @altitude, @tilemap)
    update_jump

    self.z = y + (@altitude >= PLATEAU_HEIGHT ? @altitude + 10.0 : @altitude)
  end

  # ★ 高台と地面の2階層へ影を分割描画 (Window.clip + Zオーダー遮蔽) & 本体描画
  def draw
    return if vanished? || !visible

    # 1. 下の地面 (標高 0.0) に落ちる影 (z: SHADOW_Z)
    #    高台 (:cliffs, z: 160..288) の下に入った部分は自動的に遮蔽され、
    #    高台のフチから外へはみ出した部分だけが 18px 下の地面にそのまま描画される
    air_h0 = @altitude.clamp(0.0, 65.0)
    z_ratio0 = (1.0 - air_h0 / 65.0).clamp(0.45, 1.0)
    sw0 = 22.0 * z_ratio0
    sh0 = 9.0 * z_ratio0
    sa0 = (140 * z_ratio0).to_i
    Zenoo::Window.draw_ellipse(x, y - 2.0, sw0, sh0, color: [*SHADOW_COLOR_RGB, sa0], z: SHADOW_Z)

    # 2. 高台の上面 (標高 PLATEAU_HEIGHT) に落ちる影 (Window.clip で高台上面領域内のみにクリップ)
    #    キャラの高度が高台以上のとき、高台の上に乗っている部分だけが高台床面に描画され、
    #    フチからはみ出した部分はクリップされて消える (1. の地面の影へ自然に繋がる)
    if @altitude >= PLATEAU_HEIGHT
      air_h1 = (@altitude - PLATEAU_HEIGHT).clamp(0.0, 65.0)
      z_ratio1 = (1.0 - air_h1 / 65.0).clamp(0.45, 1.0)
      sw1 = 22.0 * z_ratio1
      sh1 = 9.0 * z_ratio1
      sa1 = (140 * z_ratio1).to_i
      top_sy = y - PLATEAU_HEIGHT - 2.0
      # 影の下端 (top_sy + sh1 = y - 11) がまたがる1つ下のタイル行の row_z (最大 y + 21) より必ず手前にする
      shadow_z = y + PLATEAU_HEIGHT + 8.0

      PLATEAU_TOP_RECTS.each do |px, py, pw, ph|
        if x + sw1 > px && x - sw1 < px + pw && top_sy + sh1 > py && top_sy - sh1 < py + ph
          sx, sy = Zenoo::Window.to_screen(px, py)
          Zenoo::Window.clip(sx, sy, pw, ph, z: shadow_z) do
            Zenoo::Window.draw_ellipse(x, top_sy, sw1, sh1, color: [*SHADOW_COLOR_RGB, sa1], z: shadow_z)
          end
        end
      end
    end

    # 3. キャラ本体は絶対高度 (@altitude) 分だけ上に持ち上げ、Z値も影 (y + 26) より手前にする
    self.z = y + (@altitude >= PLATEAU_HEIGHT ? @altitude + 10.0 : @altitude)
    orig_y = y
    self.y = orig_y - @altitude
    super
    self.y = orig_y
  end

  # 現在向いている斜め方向の名称
  def direction_name
    case [@dir_y, @facing_x > 0 ? :right : :left]
    when [DIR_DOWN, :right] then "右下 (手前)"
    when [DIR_DOWN, :left]  then "左下 (手前・反転)"
    when [DIR_UP,   :right] then "右上 (奥)"
    when [DIR_UP,   :left]  then "左上 (奥・反転)"
    end
  end

  # 現在のコマの説明 (モニター表示用)
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
      end
    end
  end

  def update_move
    dx, dy = Zenoo::Input.vector
    if dx == 0.0 && dy == 0.0
      play(IDLE_ANIMS[@dir_y])
      return
    end

    update_direction(dx, dy)
    remember_move_dir(dx, dy)

    # ★ keep_frame: true により、向きを変えても足運びがリセットされず維持される
    play(WALK_ANIMS[@dir_y], keep_frame: true)

    self.x += dx * SPEED
    self.y += dy * SPEED * Y_RATIO
  end

  def start_attack
    @attacking = true
    @attack_timer = 0
    @hit_targets = {} # 今回の攻撃でヒット済みの敵 (多重ヒット防止)

    # 攻撃方向: 入力があればその方向、静止時は最後に移動した方向
    dx, dy = Zenoo::Input.vector
    remember_move_dir(dx, dy) if dx != 0.0 || dy != 0.0
    dir_x = @last_move_dx
    dir_y = @last_move_dy
    update_direction(dir_x, dir_y) # スプライトの向きも攻撃方向に同期

    # ★ 常にフルパワーで一定距離を踏み込む
    @vx = dir_x * ATTACK_DASH
    @vy = dir_y * ATTACK_DASH * Y_RATIO

    # 画面上の攻撃方向 (縦パース補正後に正規化)
    ay = dir_y * Y_RATIO
    mag = Math.hypot(dir_x, ay)
    @atk_nx = dir_x / mag
    @atk_ny = ay / mag

    # ★ 120度円弧の白リボン斬撃エフェクトをプレイヤー追従で発生！
    @effects&.push(SlashEffect.new(self, Math.atan2(@atk_ny, @atk_nx) * 180.0 / Math::PI, @slash_mesh))

    check_slash_hit
    play(ATTACK_ANIMS[@dir_y])
  end

  def update_attack
    # 前方への滑らかな踏み込みスライド移動 (摩擦減速)
    self.x += @vx
    self.y += @vy
    @vx *= DASH_FRICTION
    @vy *= DASH_FRICTION

    # ★ 斬撃エフェクト発生中は毎フレーム判定 (滑り込み先の敵も確実に捉える)
    check_slash_hit if @attack_timer < HIT_FRAMES
    @attack_timer += 1

    # 攻撃アニメーション終了 (30フレーム = 0.5秒)
    if animation_finished?
      @attacking = false
      play(IDLE_ANIMS[@dir_y])
    end
  end

  # ★ 斬撃命中判定 (前方扇形 + 背後除外)
  def check_slash_hit
    return unless @enemies

    cx = x
    cy = y - SlashEffect::CENTER_Y

    @enemies.each do |enemy|
      next if enemy.vanished? || enemy.dying? || @hit_targets[enemy.object_id]
      # 高低差チェック: 高台の上 (18px) から平地 (0px) の敵は高さが違うため当たらない
      next if (@altitude - enemy.jump_z).abs > 15.0

      dx = enemy.x - cx
      dy = (enemy.y - SlimeEnemy::BODY_CENTER_Y) - cy
      dist = Math.hypot(dx, dy)
      next if dist > SLASH_REACH

      # 前方への射影 (内積): 背後の敵には絶対に当てない
      forward = dx * @atk_nx + dy * @atk_ny
      next if forward <= 5.0

      # 扇形判定 (cos 比較で角度計算を省略)
      next if forward / dist <= (dist <= CLOSE_RANGE ? COS_85 : COS_75)

      @hit_targets[enemy.object_id] = true

      # ノックバック方向: プレイヤーから敵への放射方向 70% + 斬撃の進行方向 30%
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

  # 入力から向きを決定 (左右反転 scale_x と上下手前奥 dir_y)
  # 横・縦それぞれ成分がある場合のみ更新 (真上・真下移動では左右を維持)
  def update_direction(dx, dy)
    if dx != 0.0
      @facing_x = dx > 0.0 ? 1.0 : -1.0
      self.scale_x = @facing_x
    end
    @dir_y = dy > 0.0 ? DIR_DOWN : DIR_UP if dy != 0.0
  end

  def load_animations
    base_dir = File.join(__dir__, "../assets/sprites")

    # ====================================================
    # 1. 歩行アニメーションの登録 (たったの2アングル！)
    # ====================================================
    { down: "player_walk_down_right_3frame_1x.png", up: "player_walk_up_right_3frame_1x.png" }.each do |dir, file|
      t = Zenoo::Image.load_tiles(File.join(base_dir, file), 3, 1)
      add_animation(:"walk_#{dir}", [t[0], t[1], t[2], t[1]], wait: 6, loop: true)
      add_animation(:"idle_#{dir}", [t[1]], wait: 1, loop: false)
    end

    # ====================================================
    # 2. 攻撃アニメーションの登録 (たったの2アングル！)
    # 足元基準 (bottom_center) なので、重心補正オフセットを適用
    # ====================================================
    { down: "player_attack_down_right_1x.png", up: "player_attack_up_right_1x.png" }.each do |dir, file|
      img = Zenoo::Image.load(File.join(base_dir, file))
      add_animation(:"attack_#{dir}", [img], wait: 30, loop: false, offset_x: 4, offset_y: 2)
    end
  end
end

# ==============================================================================
# 描画ヘルパー
# ==============================================================================
PANEL_COLOR  = [18, 22, 32, 220].freeze
PANEL_BORDER = [60, 80, 110, 200].freeze
TITLE_COLOR  = [0, 220, 255, 255].freeze

GUIDE_LINES = [
  ["マップ : 1280x768 (40x24) / 行単位Mesh & Zソート & 水場・草IBOアニメ", [160, 220, 255, 255]],
  ["高台   : 標高18px (ジャンプで登り、上からは歩いてそのまま飛び降り可能)", [255, 210, 90, 255]],
  ["移動   : [W][A][S][D] / 矢印キー / パッド (MTV 壁ずり移動)", [220, 225, 235, 255]],
  ["ジャンプ : [K] / [X] / [Shift] / 右クリック / パッド [B][LB]", [120, 255, 180, 255]],
  ["攻撃   : [SPACE] / [J] / [Z] / 左クリック / パッド [X][A] (踏み込み)", [255, 120, 100, 255]],
  ["表示   : [H] キーで操作ガイド・モニターの表示切替", [200, 200, 220, 255]]
].freeze

SPAWN_POINTS = [
  [240.0,  220.0], [1040.0, 220.0],
  [240.0,  540.0], [1040.0, 540.0],
  [640.0,  210.0], [640.0,  560.0],
  [240.0,  380.0], [1040.0, 380.0]
].freeze

# ゲーム世界 (640x360 仮想解像度、Camera 追従)
# ★ 影・キャラ本体・HPバー・Tilemap各行にそれぞれ Z が設定されているため、
#   draw でまとめて呼ぶだけで Backend が前後関係をすべて自動でソートします！
def draw_world(tilemap, camera, player, enemies, effects)
  Zenoo::Window.camera = camera
  Zenoo::Window.clear([24, 28, 38, 255])

  tilemap.draw
  player.draw
  Zenoo::Sprite.draw(enemies)
  Zenoo::Sprite.draw(effects)
end

# UI オーバーレイ (1280x720 高解像度)
def draw_ui(player, camera, enemies, show_ui)
  unless show_ui
    Zenoo::Window.draw_rect(24, 20, 280, 36, radius: 8, color: [18, 22, 32, 180], border_width: 1, border_color: [60, 80, 110, 160])
    Zenoo::Window.draw_text(36, 29, "[H] キーで操作ガイド・モニターを表示", size: 13, color: [180, 210, 240, 230])
    return
  end

  # 左上: 設計コンセプト & 操作ガイド
  Zenoo::Window.draw_rect(24, 20, 540, 192, radius: 10, color: PANEL_COLOR, border_width: 1, border_color: PANEL_BORDER)
  Zenoo::Window.draw_text(40, 34, "【多層YソートTilemap & 斜め4方向アクション】", size: 18, color: TITLE_COLOR)
  GUIDE_LINES.each_with_index do |(text, color), i|
    Zenoo::Window.draw_text(40, 60 + i * 22, text, size: 13, color: color)
  end

  # 右上: 状態リアルタイムモニター
  col_x = (player.x / TILE_SIZE).to_i
  row_y = (player.y / TILE_SIZE).to_i
  monitor = [
    ["現在座標 : (#{player.x.to_i}, #{player.y.to_i}) [Tile: #{col_x}, #{row_y}] / 高度: #{player.altitude.to_i}px (床:#{player.ground_h.to_i}px)", :white],
    ["カメラ   : (#{camera.x.to_i}, #{camera.y.to_i}) / 残りスライム: #{enemies.size}体", [100, 255, 180, 255]],
    ["向き・アニメ : #{player.direction_name} (#{player.animation})", [180, 200, 255, 255]],
    ["現在のコマ : #{player.current_frame_index} [#{player.frame_description}]", [255, 220, 100, 255]]
  ]
  Zenoo::Window.draw_rect(810, 20, 446, 160, radius: 10, color: PANEL_COLOR, border_width: 1, border_color: PANEL_BORDER)
  Zenoo::Window.draw_text(826, 34, "【リアルタイム状態モニター】", size: 18, color: TITLE_COLOR)
  monitor.each_with_index do |(text, color), i|
    Zenoo::Window.draw_text(826, 64 + i * 24, text, size: 14, color: color)
  end
end

# ==============================================================================
# メインループ
# ==============================================================================
if __FILE__ == $0
  # 1. 広大な多層タイルマップ (1280x768, 40x24) の生成
  tilemap = create_world_tilemap

  # 2. プレイヤー初期化 (ワールド中央 640, 384 に配置)
  player = IsoPlayer.new(WORLD_WIDTH / 2.0, WORLD_HEIGHT / 2.0)
  effects = []
  player.effects = effects
  player.tilemap = tilemap

  # 3. ベクタースライム敵の生成 (メッシュは 1 つを共有し、マップ各地に配置)
  slime_mesh = create_slime_mesh
  enemies = SPAWN_POINTS.map { |ex, ey| SlimeEnemy.new(ex, ey, slime_mesh) }
  player.enemies = enemies

  # 4. カメラ初期化 (プレイヤーを滑らかに追従し、マップ端でクランプ)
  camera = Zenoo::Camera.new(
    x: player.x,
    y: player.y - 24.0,
    offset_x: VIRTUAL_WIDTH / 2.0,
    offset_y: VIRTUAL_HEIGHT / 2.0
  )

  # アクションマップ登録 (キーボード・マウス・ゲームパッド)
  Zenoo::Input.define_action(:attack, keys: [:space, :j, :z], mouse: :left, gamepad: [:x, :a, :rb])
  Zenoo::Input.define_action(:jump,   keys: [:k, :x, :left_shift, :right_shift], mouse: :right, gamepad: [:b, :lb])

  # ★ 縦横半分サイズ (640x360) のオフスクリーン Image
  # nearest フィルタによりピクセルアートやベクターをドット絵調にくっきり 2 倍拡大！
  screen = Zenoo::Image.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
  screen.texture_filter = :nearest

  show_ui = true
  test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
  frame_count = 0

  Zenoo::Window.loop(WINDOW_WIDTH, WINDOW_HEIGHT, "Zenoo - 4-Way Diagonal Animated Sprite & Multi-Layer Tilemap Demo") do
    frame_count += 1
    break if test_max > 0 && frame_count >= test_max

    show_ui = !show_ui if Zenoo::Input.key_push?(:h)

    # 更新
    tilemap.update
    player.update
    enemies.each { |e| e.update(player.x, player.y, tilemap) }
    Zenoo::Sprite.clean(enemies)
    Zenoo::Sprite.update(effects)
    Zenoo::Sprite.clean(effects)

    # カメラをプレイヤーへ滑らかに追従させ、ワールド境界内にクランプ
    target_cx = (player.x).clamp(VIRTUAL_WIDTH / 2.0, WORLD_WIDTH - VIRTUAL_WIDTH / 2.0)
    target_cy = (player.y - 20.0).clamp(VIRTUAL_HEIGHT / 2.0, WORLD_HEIGHT - VIRTUAL_HEIGHT / 2.0)
    camera.x += (target_cx - camera.x) * 0.18
    camera.y += (target_cy - camera.y) * 0.18

    # 全滅時の自動再出現
    if enemies.empty?
      SPAWN_POINTS.sample(4).each do |sx, sy|
        enemies << SlimeEnemy.new(sx, sy, slime_mesh)
      end
    end

    # 1. 640x360 の Image にゲーム世界を描画 → 2. 画面に 2 倍拡大 → 3. UI を重ねる
    Zenoo::Image.render_to(screen) { draw_world(tilemap, camera, player, enemies, effects) }
    Zenoo::Window.clear([0, 0, 0, 255])
    Zenoo::Window.draw(0, 0, screen, scale_x: 2.0, scale_y: 2.0, anchor: :top_left, pivot: :top_left)
    draw_ui(player, camera, enemies, show_ui)
  end
end

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
T_STELE_TOP  = 8 # 2段蒼石碑・上段 (root_offset: 1)
T_STELE_BOT  = 9 # 2段蒼石碑・下段 (root_offset: 0, solid: true)

# クォータービューの奥行きパースに合わせて縦移動を 80% に補正
Y_RATIO = 0.8

SHADOW_COLOR_RGB = [10, 12, 18].freeze
SHADOW_Z         = -10.0
GROUND_Z         = -100.0
EFFECT_Z         = 2000.0
HP_BAR_Z         = 2100.0

# ワールド境界クランプ & マップ衝突解決
module WorldBounds
  def resolve_map_and_bounds(tilemap, margin_x, margin_y)
    self.x = x.clamp(margin_x, WORLD_WIDTH - margin_x)
    self.y = y.clamp(margin_y, WORLD_HEIGHT - margin_y)
    if tilemap
      sync_foot_collider
      tilemap.resolve_collision(self)
      self.x = x.clamp(margin_x, WORLD_WIDTH - margin_x)
      self.y = y.clamp(margin_y, WORLD_HEIGHT - margin_y)
    end
    self.z = y
  end
end

# ==============================================================================
# タイルセット生成 (32x32 × 10種類 = 320x32) & マップ構築
# ==============================================================================
def create_dungeon_tileset
  tileset = Zenoo::Image.new(TILE_SIZE * 10, TILE_SIZE)
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
  end
  tileset.slice_tiles(tile_width: TILE_SIZE, tile_height: TILE_SIZE)
end

def create_world_tilemap
  tiles = create_dungeon_tileset
  map = Zenoo::Tilemap.new(tiles)

  # 1マス障害物タイルの設定
  map.set_tile(T_WALL,  solid: true)
  map.set_tile(T_CRATE, solid: true)

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

  # 2. 立体オブジェクト・障害物レイヤー (40x24, 行単位 Yソート有効)
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

  # 迷路状の石壁ブロックと木箱 (壁ずり移動のテストにも最適)
  [
    # 北西エリアのL字壁
    [11, 4, T_WALL], [12, 4, T_WALL], [13, 4, T_WALL], [13, 5, T_WALL],
    [14, 5, T_CRATE],
    # 北東エリアのL字壁
    [26, 4, T_WALL], [27, 4, T_WALL], [28, 4, T_WALL], [26, 5, T_WALL],
    [25, 5, T_CRATE],
    # 南西エリアの遮蔽壁と木箱群
    [11, 18, T_WALL], [12, 18, T_WALL], [13, 18, T_WALL],
    [11, 19, T_CRATE], [12, 19, T_CRATE],
    [4, 11, T_CRATE], [4, 12, T_CRATE], [5, 12, T_CRATE],
    # 南東エリアの遮蔽壁と木箱群
    [26, 18, T_WALL], [27, 18, T_WALL], [28, 18, T_WALL],
    [27, 19, T_CRATE], [28, 19, T_CRATE],
    [35, 11, T_CRATE], [35, 12, T_CRATE], [34, 11, T_CRATE]
  ].each do |c, r, tid|
    objects[r][c] = tid
  end

  map.add_layer(:ground,  ground,  z: GROUND_Z)
  map.add_layer(:objects, objects, z: 0.0, y_sort: true)
  map
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
    super(player.x, player.y - CENTER_Y, mesh, anchor: :center, pivot: :center, blend: :add)
    @player = player
    self.angle = angle
    self.scale_y = player.facing_x # 左右反転時も振り下ろし方向・グラデーション向きを対称にする
    self.z = EFFECT_Z
    @timer = LIFE
  end

  def update
    # ★ 攻撃スライド中もプレイヤーの移動に完全追従！
    self.x = @player.x
    self.y = @player.y - CENTER_Y

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
  include WorldBounds

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

    # 足元の接地コライダー (楕円)
    set_collider(:circle, radius_x: 16.0, radius_y: 10.0)
  end

  def sync_foot_collider
    # pivot (:bottom_center) 基準で足元 (y - 8px) にコライダー中心を維持
    sy = scale_y.abs > 0.001 ? scale_y.abs : 1.0
    self.collider_offset_y = height * 0.5 - (8.0 / sy)
  end

  def dying?
    @dying
  end

  def update(target_x, target_y, tilemap = nil)
    sx, sy = @hit_timer > 0 ? update_knockback : update_hop(target_x, target_y)
    return if vanished?

    self.scale_x = @facing_x * BASE_SCALE * sx
    self.scale_y = BASE_SCALE * sy
    resolve_map_and_bounds(tilemap, 28.0, 36.0)
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

  # ★ 描画時はジャンプ高さ分だけ上に浮かせて描画！ (地面の y 座標・Z値・影の位置は維持)
  def draw
    self.z = y
    orig_y = y
    self.y -= @jump_z
    super
    self.y = orig_y
  end

  # 足元のドロップシャドウ (浮き上がり中は縮んで薄くなり、消滅時はフェードアウト)
  def draw_shadow
    z_ratio = (1.0 - @jump_z / 40.0).clamp(0.45, 1.0)
    sw = 30.0 * (scale_x.abs / BASE_SCALE) * z_ratio
    sh = 11.5 * z_ratio
    a  = (140 * z_ratio * alpha / 255.0).to_i
    Zenoo::Window.draw_ellipse(x, y - 3.0, sw, sh, color: [*SHADOW_COLOR_RGB, a], z: SHADOW_Z)
  end

  # 頭上 HP ドット (ジャンプ中も重ならないよう頭上高めに配置、浮き上がりに追従)
  def draw_hp
    return if @dying
    hp_y = y - @jump_z - 64.0
    MAX_HP.times do |i|
      Zenoo::Window.draw_circle(x.to_i - 12 + i * 12, hp_y, 3.5, color: i < @hp ? HP_ON_COLOR : HP_OFF_COLOR, z: HP_BAR_Z)
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
  include WorldBounds

  SPEED         = 4.2
  ATTACK_DASH   = 6.5  # 踏み込み初速 (入力の強弱に関わらず常にフルパワー)
  DASH_FRICTION = 0.85
  HIT_FRAMES    = 12   # 攻撃判定の持続フレーム (斬撃エフェクトの寿命と同じ)

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

  attr_reader   :facing_x, :attacking
  attr_accessor :effects, :enemies, :tilemap

  def initialize(x, y)
    # ★ 見下ろしアクションの鉄則: 足元・接地点基準 (bottom_center)
    super(x, y, anchor: :bottom_center, pivot: :bottom_center)

    # 向き管理: 手前 (DIR_DOWN) / 奥 (DIR_UP)、左右 (1.0: 右 / -1.0: 左)
    @dir_y = DIR_DOWN
    @facing_x = 1.0
    @attacking = false
    @vx = 0.0
    @vy = 0.0
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

    # ★ 足元の接地コライダー (横半径11px, 縦半径8px の楕円、下端がちょうど足元 y に一致)
    set_collider(:circle, radius_x: 11.0, radius_y: 8.0)
    sync_foot_collider
    self.z = y
  end

  def sync_foot_collider
    # 歩行(64x80)と攻撃(96x96)で画像高さが変わっても、常に足元(y - 8px)にコライダー中心を固定
    self.collider_offset_y = height * 0.5 - 8.0
  end

  def update
    if @attacking
      update_attack
    elsif Zenoo::Input.action_push?(:attack) # 押下の瞬間のみトリガー
      start_attack
    else
      update_move
    end

    super # アニメーション更新 (update_animation)
    resolve_map_and_bounds(@tilemap, 24.0, 32.0)
  end

  # 足元のドロップシャドウ
  def draw_shadow
    Zenoo::Window.draw_ellipse(x, y - 2.0, 22.0, 9.0, color: [*SHADOW_COLOR_RGB, 140], z: SHADOW_Z)
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
    return "攻撃モーション (1コマ/30フレーム/0.5秒)" if @attacking
    WALK_FRAME_NAMES[current_frame_index] || current_frame_index.to_s
  end

  private

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
  ["マップ : 1280x768 (40x24タイル・2画面分) / 行単位Mesh & Zソート", [160, 220, 255, 255]],
  ["立体柱 : 3段石柱・2段石碑は根元Zで統合 (裏へ回り込み＆手前重なり両立)", [255, 200, 80, 255]],
  ["敵機   : Mesh.canvas による潰れスライム (壁・柱との衝突＆バウンド)", [100, 255, 180, 255]],
  ["移動   : [W][A][S][D] / 矢印キー / パッド (MTV 壁ずり移動)", [220, 225, 235, 255]],
  ["攻撃   : [SPACE] / [J] / 左クリック / パッド [X][A] (踏み込み)", [255, 120, 100, 255]],
  ["表示   : [H] キーで操作ガイド・モニターの表示切替", [200, 200, 220, 255]]
].freeze

SPAWN_POINTS = [
  [360.0,  220.0], [920.0,  220.0],
  [360.0,  540.0], [920.0,  540.0],
  [640.0,  210.0], [640.0,  560.0],
  [240.0,  380.0], [1040.0, 380.0]
].freeze

# ゲーム世界 (640x360 仮想解像度、Camera 追従)
# ★ Backend の Z ソートにより、Tilemap の各行 Mesh とキャラの前後関係が完全自動で解決！
def draw_world(tilemap, camera, player, enemies, effects)
  Zenoo::Window.camera = camera
  Zenoo::Window.clear([24, 28, 38, 255])

  tilemap.draw
  player.draw_shadow
  enemies.each(&:draw_shadow)
  player.draw
  enemies.each(&:draw)
  enemies.each(&:draw_hp)
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
    ["現在座標 : (#{player.x.to_i}, #{player.y.to_i}) [Tile: #{col_x}, #{row_y}] / Z: #{player.z.to_i}", :white],
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

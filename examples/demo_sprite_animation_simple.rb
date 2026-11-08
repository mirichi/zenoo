# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - 斜め4方向スプライト移動 & 最小限Tilemapデモ (石柱・Yソート対応)
#
# 特徴:
#   1. 「右下」と「右上」の2アングル画像を scale_x = -1.0 で反転し全4方向をカバー
#   2. 3段石柱 (define_column) による縦連結オブジェクトと足元衝突判定
#   3. 行単位 Yソートにより、柱の奥へ回り込んだり手前を歩いたりする立体感を自動実現
#   4. 足元サークルコライダーと Tilemap#resolve_collision による滑らかな壁ずり移動 (MTV)
# ==============================================================================

# 画面・仮想解像度
VIRTUAL_WIDTH  = 640
VIRTUAL_HEIGHT = 360
WINDOW_WIDTH   = 1280
WINDOW_HEIGHT  = 720

TILE_SIZE    = 32
MAP_COLS     = 40
MAP_ROWS     = 24
WORLD_WIDTH  = MAP_COLS * TILE_SIZE # 1280
WORLD_HEIGHT = MAP_ROWS * TILE_SIZE # 768
Y_RATIO      = 0.8 # クォータービューの縦移動補正

# タイルID定義 (0..5)
T_FLOOR      = 0
T_WALL       = 1
T_BLOCK      = 2
T_PILLAR_TOP = 3 # 3段石柱・上段 (柱頭)
T_PILLAR_MID = 4 # 3段石柱・中段 (柱身)
T_PILLAR_BOT = 5 # 3段石柱・下段 (柱脚・台座, solid)
PILLAR_PARTS = [T_PILLAR_TOP, T_PILLAR_MID, T_PILLAR_BOT].freeze

# ==============================================================================
# タイルセット生成 (32x32 × 6種類: 床・壁・ブロック・石柱3段)
# ==============================================================================
def draw_pillar_flutes(ox, y0, y1, outer: false)
  Zenoo::Window.draw_line(ox + 6,  y0, ox + 6,  y1, width: 2, color: [135, 148, 175, 255]) if outer
  Zenoo::Window.draw_line(ox + 10, y0, ox + 10, y1, width: 2, color: [82,  92,  114, 255])
  Zenoo::Window.draw_line(ox + 16, y0, ox + 16, y1, width: 2, color: [135, 148, 175, 255])
  Zenoo::Window.draw_line(ox + 22, y0, ox + 22, y1, width: 2, color: [75,  85,  106, 255])
  Zenoo::Window.draw_line(ox + 26, y0, ox + 26, y1, width: 2, color: [62,  70,  90,  255]) if outer
end

def create_tileset
  img = Zenoo::Image.new(TILE_SIZE * 6, TILE_SIZE)
  Zenoo::Image.render_to(img) do
    Zenoo::Window.clear([0, 0, 0, 0])

    # 0: 床 (石畳風)
    Zenoo::Window.draw_rect(0, 0, 32, 32, color: [46, 52, 66, 255])
    Zenoo::Window.draw_rect(1, 1, 14, 14, radius: 2, color: [58, 66, 82, 255])
    Zenoo::Window.draw_rect(17, 1, 14, 14, radius: 2, color: [54, 62, 78, 255])
    Zenoo::Window.draw_rect(1, 17, 14, 14, radius: 2, color: [52, 60, 76, 255])
    Zenoo::Window.draw_rect(17, 17, 14, 14, radius: 2, color: [60, 68, 84, 255])

    # 1: 外周壁 (石レンガ風)
    ox = 32
    Zenoo::Window.draw_rect(ox, 0, 32, 32, color: [40, 44, 56, 255])
    Zenoo::Window.draw_rect(ox + 1, 1, 30, 16, radius: 2, color: [92, 102, 124, 255], border_width: 1, border_color: [120, 132, 156, 255])
    Zenoo::Window.draw_rect(ox + 1, 17, 30, 14, color: [62, 70, 88, 255])
    Zenoo::Window.draw_line(ox + 1, 24, ox + 31, 24, width: 1, color: [42, 48, 62, 255])

    # 2: 障害物ブロック (木箱風)
    ox = 64
    Zenoo::Window.draw_rect(ox + 2, 2, 28, 28, radius: 3, color: [110, 74, 42, 255], border_width: 2, border_color: [68, 44, 24, 255])
    Zenoo::Window.draw_rect(ox + 4, 4, 24, 12, radius: 2, color: [148, 102, 58, 255])
    Zenoo::Window.draw_line(ox + 5, 5, ox + 27, 27, width: 2, color: [88, 58, 32, 255])
    Zenoo::Window.draw_line(ox + 27, 5, ox + 5, 27, width: 2, color: [88, 58, 32, 255])

    # 3: 3段石柱・上段 (柱頭 + 蒼クリスタル装飾)
    ox = 96
    Zenoo::Window.draw_rect(ox + 3, 6, 26, 10, radius: 2, color: [130, 142, 168, 255], border_width: 1, border_color: [170, 185, 210, 255])
    Zenoo::Window.draw_rect(ox + 5, 16, 22, 16, color: [105, 118, 142, 255])
    draw_pillar_flutes(ox, 16, 32)
    Zenoo::Window.draw_circle(ox + 16, 11, 4, color: [0, 210, 255, 255], border_width: 1, border_color: :white)

    # 4: 3段石柱・中段 (柱身・縦溝)
    ox = 128
    Zenoo::Window.draw_rect(ox + 5, 0, 22, 32, color: [105, 118, 142, 255])
    draw_pillar_flutes(ox, 0, 32, outer: true)

    # 5: 3段石柱・下段 (柱脚・台座)
    ox = 160
    Zenoo::Window.draw_ellipse(ox + 16, 27, 15, 5, color: [10, 12, 18, 140])
    Zenoo::Window.draw_rect(ox + 5, 0, 22, 16, color: [105, 118, 142, 255])
    draw_pillar_flutes(ox, 0, 16)
    Zenoo::Window.draw_rect(ox + 3, 14, 26, 8, radius: 2, color: [120, 132, 158, 255], border_width: 1, border_color: [70, 80, 100, 255])
    Zenoo::Window.draw_rect(ox + 1, 20, 30, 10, radius: 2, color: [88, 98, 120, 255], border_width: 1, border_color: [55, 62, 80, 255])
  end
  img.slice_tiles(tile_width: TILE_SIZE, tile_height: TILE_SIZE)
end

# ==============================================================================
# タイルマップ構築 (床レイヤー + Yソート立体オブジェクトレイヤー)
# ==============================================================================
def place_column_at(objects, c, root_r, parts)
  parts.reverse_each.with_index { |tid, i| objects[root_r - i][c] = tid }
end

def create_tilemap
  map = Zenoo::Tilemap.new(create_tileset)
  map.set_tile(T_WALL, solid: true)
  map.set_tile(T_BLOCK, solid: true)

  # 3段石柱の連結定義 (下段のみ solid: true で足元が当たり判定・上中は通過可能)
  map.define_column(PILLAR_PARTS, solid: true)

  ground  = Array.new(MAP_ROWS) { Array.new(MAP_COLS, T_FLOOR) }
  objects = Array.new(MAP_ROWS) { Array.new(MAP_COLS, nil) }

  # 外周の壁
  MAP_COLS.times { |c| objects[0][c] = objects[MAP_ROWS - 1][c] = T_WALL }
  MAP_ROWS.times { |r| objects[r][0] = objects[r][MAP_COLS - 1] = T_WALL }

  # 石柱の配置 (キャラが手前や奥を通れる立体障害物)
  [[14, 8], [25, 8], [14, 16], [25, 16], [8, 12], [31, 12]].each do |c, r|
    place_column_at(objects, c, r, PILLAR_PARTS)
  end

  # 散らばる障害物ブロック
  [[18, 12], [21, 12], [6, 6], [33, 6], [6, 18], [33, 18]].each do |c, r|
    objects[r][c] = T_BLOCK
  end

  map.add_layer(:ground,  ground,  z: -100.0)
  map.add_layer(:objects, objects, z: 0.0, y_sort: true)
  map
end

# ==============================================================================
# 斜め4方向プレイヤー
# ==============================================================================
class IsoPlayer < Zenoo::Sprite
  SPEED = 4.2

  DIR_DOWN = 0
  DIR_UP   = 1

  WALK_ANIMS = [:walk_down, :walk_up].freeze
  IDLE_ANIMS = [:idle_down, :idle_up].freeze

  attr_accessor :tilemap

  def initialize(x, y)
    super(x, y, anchor: :bottom_center, pivot: :bottom_center)
    @dir_y = DIR_DOWN
    load_animations
    play(IDLE_ANIMS[@dir_y])

    # 足元サークルコライダー (MTV壁ずり用)
    set_collider(:circle, radius_x: 11.0, radius_y: 8.0, at: :bottom_center, offset_y: -8.0)
    self.z = y
  end

  def update
    dx, dy = Zenoo::Input.vector
    if dx == 0.0 && dy == 0.0
      play(IDLE_ANIMS[@dir_y])
    else
      self.scale_x = dx > 0.0 ? 1.0 : -1.0 if dx.abs > 0.05
      @dir_y = dy > 0.0 ? DIR_DOWN : DIR_UP if dy.abs > 0.05
      play(WALK_ANIMS[@dir_y], keep_frame: true)

      self.x += dx * SPEED
      self.y += dy * SPEED * Y_RATIO
    end

    super()
    @tilemap.resolve_collision(self)
    self.z = y
  end

  def draw
    # 足元の影
    Zenoo::Window.draw_ellipse(x, y - 2.0, 22.0, 9.0, color: [10, 12, 18, 140], z: -10.0)
    super
  end

  private

  def load_animations
    base_dir = File.expand_path('../assets/sprites', __dir__)
    { down: 'player_walk_down_right_3frame_1x.png', up: 'player_walk_up_right_3frame_1x.png' }.each do |dir, file|
      tiles = Zenoo::Image.load_tiles(File.join(base_dir, file), 3, 1)
      add_animation(:"walk_#{dir}", [tiles[0], tiles[1], tiles[2], tiles[1]], wait: 6, loop: true)
      add_animation(:"idle_#{dir}", [tiles[1]], wait: 1, loop: false)
    end
  end
end

# ==============================================================================
# メインシーン
# ==============================================================================
class DemoScene < Zenoo::Scene
  attr_reader :tilemap, :player, :camera

  def initialize
    @tilemap = create_tilemap
    @player = IsoPlayer.new(WORLD_WIDTH / 2.0, WORLD_HEIGHT / 2.0)
    @player.tilemap = @tilemap

    @camera = Zenoo::Camera.new(
      x: @player.x,
      y: @player.y,
      offset_x: VIRTUAL_WIDTH / 2.0,
      offset_y: VIRTUAL_HEIGHT / 2.0,
      target: @player,
      smooth_speed: 1.1,
      bounds: [0, 0, WORLD_WIDTH, WORLD_HEIGHT]
    )

    @screen = Zenoo::Image.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    @screen.texture_filter = :nearest

    # タッチ操作用バーチャルパッド
    Zenoo::Input.virtual_pad = Zenoo::VirtualPad.one_hand
  end

  def call
    exit(0) if ENV['ZENOO_TEST_FRAMES'] && (@frame_count = (@frame_count || 0) + 1) >= ENV['ZENOO_TEST_FRAMES'].to_i

    @player.update
    @camera.update

    # 仮想解像度バッファに描画
    Zenoo::Image.render_to(@screen) do
      Zenoo::Window.camera = @camera
      Zenoo::Window.clear([24, 28, 38, 255])
      @tilemap.draw
      @player.draw
    end

    # 画面へ 2 倍拡大描画
    Zenoo::Window.clear([0, 0, 0, 255])
    Zenoo::Window.draw(0, 0, @screen, scale_x: 2.0, scale_y: 2.0, anchor: :top_left, pivot: :top_left)
  end
end

# ==============================================================================
# エントリーポイント
# ==============================================================================
if __FILE__ == $0
  scene = DemoScene.new
  Zenoo::Scene.change(scene)
  Zenoo::Window.loop(WINDOW_WIDTH, WINDOW_HEIGHT, 'Zenoo - Simple Sprite Walk & Tilemap Demo') do
    Zenoo::Scene.call
  end
end

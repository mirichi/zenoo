# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - 斜め4方向スプライト・アニメーション デモ
#
# 特徴:
#   1. 「右下 (手前)」と「右上 (奥)」の【たった2アングル】のみで全方位をカバー！
#   2. 左方向は scale_x = -1.0 の左右反転により完全自動対応（アセット制作コスト半減）
#   3. 歩行は 3 コマ画像から 0 -> 1 -> 2 -> 1 のループサイクルを構築
#   4. 攻撃画像 (96x96) は offset_x: 4 により歩行 (64x80) と足元接地点を完全同期
#   5. 方向転換時は keep_frame: true により足運びの位相を滑らかに維持
# ==============================================================================

# 画面・仮想解像度定数
# 縦横半分サイズ (640x360) のバッファに描画し、ウィンドウ (1280x720) に 2 倍拡大描画
VIRTUAL_WIDTH  = 640
VIRTUAL_HEIGHT = 360
WINDOW_WIDTH   = 1280
WINDOW_HEIGHT  = 720

# クォータービューの奥行きパースに合わせて縦移動を 80% に補正
Y_RATIO = 0.8

SHADOW_COLOR_RGB = [10, 12, 18].freeze

# 画面端クランプ (仮想解像度内に収める)
module ScreenBounds
  def clamp_to_screen(margin_x, margin_y)
    self.x = x.clamp(margin_x, VIRTUAL_WIDTH - margin_x)
    self.y = y.clamp(margin_y, VIRTUAL_HEIGHT - margin_y)
  end
end

# ==============================================================================
# 斬撃円弧リボンエフェクト (Mesh.ring による白リボンメッシュ)
# ==============================================================================
class SlashEffect < Zenoo::Sprite
  LIFE      = 12
  CENTER_Y  = 32.0 # プレイヤーの体・手元の高さ (足元から上へ 32px)

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
  include ScreenBounds

  BASE_SCALE    = 0.75
  MAX_HP        = 3
  BODY_CENTER_Y = 20.0 # 当たり判定の中心 (足元から上へ 20px)
  HOP_CYCLE     = 48   # ホップ周期 (フレーム)
  HOP_SPEED     = 2.4

  # 被弾時の 3 回バウンド: [フレーム数, 高さ] (大ホップ -> 中ホップ -> 小ホップ)
  BOUNCES     = [[16, 20.0], [12, 11.0], [8, 5.0]].freeze
  BOUNCE_END  = BOUNCES.sum(&:first) # 36
  HIT_TIME    = BOUNCE_END + 2       # バウンド後 2 フレームで通常形状へ復帰
  KB_FRICTION = 0.935
  ROUND_SX    = 0.86 # ジャンプ中の丸い形状 (縦長水滴型)
  ROUND_SY    = 1.22

  FLASH_COLOR = [255, 120, 120, 255].freeze
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
  end

  def dying?
    @dying
  end

  def update(target_x, target_y)
    sx, sy = @hit_timer > 0 ? update_knockback : update_hop(target_x, target_y)
    return if vanished?

    self.scale_x = @facing_x * BASE_SCALE * sx
    self.scale_y = BASE_SCALE * sy
    clamp_to_screen(28.0, 36.0)
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

  # ★ 描画時はジャンプ高さ分だけ上に浮かせて描画！ (地面の y 座標・影の位置は維持)
  def draw
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
    Zenoo::Window.draw_ellipse(x, y - 3.0, sw, sh, color: [*SHADOW_COLOR_RGB, a])
  end

  # 頭上 HP ドット (ジャンプ中も重ならないよう頭上高めに配置、浮き上がりに追従)
  def draw_hp
    return if @dying
    hp_y = y - @jump_z - 64.0
    MAX_HP.times do |i|
      Zenoo::Window.draw_circle(x.to_i - 12 + i * 12, hp_y, 3.5, color: i < @hp ? HP_ON_COLOR : HP_OFF_COLOR)
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
    @facing_x = (dx >= 0 ? 1.0 : -1.0) if dist > 10.0

    @hop_tick = (@hop_tick + 1) % HOP_CYCLE
    @jump_z = 0.0

    if @hop_tick < 14
      # 1. ジャンプ準備: グッと横に潰れてタメる
      t = @hop_tick / 14.0
      [1.0 + t * 0.22, 1.0 - t * 0.18]
    elsif @hop_tick < 34
      # 2. ホップ空中: 縦長に伸びて少し浮きながら前進！
      @jump_z = Math.sin((@hop_tick - 14) / 20.0 * Math::PI) * 8.0
      if dist > 32.0
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
  include ScreenBounds

  SPEED        = 5.0
  ATTACK_DASH  = 7.0  # 踏み込み初速 (入力の強弱に関わらず常にフルパワー)
  DASH_FRICTION = 0.85
  HIT_FRAMES   = 12   # 攻撃判定の持続フレーム (斬撃エフェクトの寿命と同じ)

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

  attr_reader :facing_x, :attacking
  attr_accessor :effects, :enemies

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
    @attack_timer = 0
    @hit_targets = {}
    @atk_nx = 1.0 # 画面上での攻撃方向 (正規化済み)
    @atk_ny = 0.0
    @last_move_dx = 1.0 # 最後に移動した方向ベクトル (正規化済み)
    @last_move_dy = 1.0

    @slash_mesh = SlashEffect.create_mesh

    load_animations
    play(IDLE_ANIMS[@dir_y])
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
  end

  # 足元のドロップシャドウ
  def draw_shadow
    Zenoo::Window.draw_ellipse(x, y - 2.0, 22.0, 9.0, color: [*SHADOW_COLOR_RGB, 140])
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
    clamp_to_screen(24.0, 32.0)
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
    clamp_to_screen(24.0, 32.0)

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
GRID_COLOR   = [35, 42, 58, 120].freeze

GUIDE_LINES = [
  ["描画 : 640x360 (Image.render_to) → 1280x720 (2倍拡大描画)", [160, 220, 255, 255]],
  ["自機 : 右下・右上の【たった2枚】で全方位歩行＆攻撃", [255, 200, 80, 255]],
  ["敵機 : Mesh.canvas による潰れスライム (ベクター & 伸縮ホップ)", [100, 255, 180, 255]],
  ["移動 : [W][A][S][D] / 矢印キー / パッド (縦80%パース補正)", [220, 225, 235, 255]],
  ["攻撃 : [SPACE] / [J] / 左クリック / パッド [X][A] (踏み込み)", [255, 120, 100, 255]],
  ["表示 : [H] キーで操作ガイド・モニターの表示切替", [200, 200, 220, 255]]
].freeze

# ゲーム世界 (640x360 仮想解像度)
def draw_world(player, enemies, effects)
  Zenoo::Window.clear([24, 28, 38, 255])

  # 背景の装飾グリッド (32px 刻み)
  (0..VIRTUAL_WIDTH).step(32)  { |gx| Zenoo::Window.draw_line(gx, 0, gx, VIRTUAL_HEIGHT, width: 1.0, color: GRID_COLOR) }
  (0..VIRTUAL_HEIGHT).step(32) { |gy| Zenoo::Window.draw_line(0, gy, VIRTUAL_WIDTH, gy, width: 1.0, color: GRID_COLOR) }

  # 見下ろし立体描画: 影 → Yソートキャラ → HP → 斬撃エフェクト
  player.draw_shadow
  enemies.each(&:draw_shadow)
  [player, *enemies].sort_by(&:y).each(&:draw) # 足元 y が手前ほど後に描画
  enemies.each(&:draw_hp)
  Zenoo::Sprite.draw(effects)
end

# UI オーバーレイ (1280x720 高解像度)
def draw_ui(player, show_ui)
  unless show_ui
    Zenoo::Window.draw_rect(24, 20, 280, 36, radius: 8, color: [18, 22, 32, 180], border_width: 1, border_color: [60, 80, 110, 160])
    Zenoo::Window.draw_text(36, 29, "[H] キーで操作ガイド・モニターを表示", size: 13, color: [180, 210, 240, 230])
    return
  end

  # 左上: 設計コンセプト & 操作ガイド
  Zenoo::Window.draw_rect(24, 20, 520, 192, radius: 10, color: PANEL_COLOR, border_width: 1, border_color: PANEL_BORDER)
  Zenoo::Window.draw_text(40, 34, "【斜め4方向スプライト & 拡大描画デモ】", size: 18, color: TITLE_COLOR)
  GUIDE_LINES.each_with_index do |(text, color), i|
    Zenoo::Window.draw_text(40, 60 + i * 22, text, size: 13, color: color)
  end

  # 右上: アニメーション状態リアルタイムモニター
  monitor = [
    ["現在のアニメーション : #{player.animation}", :white],
    ["現在の向き : #{player.direction_name} (scale_x: #{player.scale_x})", [100, 255, 180, 255]],
    ["描画オフセット : [#{player.animation_offset_x}, #{player.animation_offset_y}]", [180, 200, 255, 255]],
    ["現在のコマ : #{player.current_frame_index} [#{player.frame_description}]", [255, 220, 100, 255]]
  ]
  Zenoo::Window.draw_rect(840, 20, 416, 160, radius: 10, color: PANEL_COLOR, border_width: 1, border_color: PANEL_BORDER)
  Zenoo::Window.draw_text(856, 34, "【リアルタイム状態モニター】", size: 18, color: TITLE_COLOR)
  monitor.each_with_index do |(text, color), i|
    Zenoo::Window.draw_text(856, 64 + i * 26, text, size: 15, color: color)
  end
end

# ==============================================================================
# メインループ
# ==============================================================================
if __FILE__ == $0
  # 初期化 (640x360 仮想空間の中央に配置)
  player = IsoPlayer.new(VIRTUAL_WIDTH / 2.0, VIRTUAL_HEIGHT / 2.0)
  effects = []
  player.effects = effects

  # ベクタースライム敵の生成 (メッシュは 1 つを共有)
  slime_mesh = create_slime_mesh
  enemies = [[190.0, 160.0], [460.0, 130.0], [320.0, 270.0]].map { |ex, ey| SlimeEnemy.new(ex, ey, slime_mesh) }
  player.enemies = enemies

  # アクションマップ登録 (キーボード・マウス・ゲームパッド)
  Zenoo::Input.define_action(:attack, keys: [:space, :j, :z], mouse: :left, gamepad: [:x, :a, :rb])

  # ★ 縦横半分サイズ (640x360) のオフスクリーン Image
  # nearest フィルタによりピクセルアートやベクターをドット絵調にくっきり 2 倍拡大！
  screen = Zenoo::Image.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
  screen.texture_filter = :nearest

  show_ui = true

  Zenoo::Window.loop(WINDOW_WIDTH, WINDOW_HEIGHT, "Zenoo - 4-Way Diagonal Animated Sprite & Vector Slime Demo") do
    show_ui = !show_ui if Zenoo::Input.key_push?(:h)

    # 更新
    player.update
    enemies.each { |e| e.update(player.x, player.y) }
    Zenoo::Sprite.clean(enemies)
    Zenoo::Sprite.update(effects)
    Zenoo::Sprite.clean(effects)

    # 全滅時の自動再出現
    if enemies.empty?
      2.times { enemies << SlimeEnemy.new(rand(80.0..560.0), rand(80.0..280.0), slime_mesh) }
    end

    # 1. 640x360 の Image にゲーム世界を描画 → 2. 画面に 2 倍拡大 → 3. UI を重ねる
    Zenoo::Image.render_to(screen) { draw_world(player, enemies, effects) }
    Zenoo::Window.clear([0, 0, 0, 255])
    Zenoo::Window.draw(0, 0, screen, scale_x: 2.0, scale_y: 2.0, anchor: :top_left, pivot: :top_left)
    draw_ui(player, show_ui)
  end
end

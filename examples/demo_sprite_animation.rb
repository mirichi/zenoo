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

# ==============================================================================
# 斬撃円弧リボンエフェクト (Mesh.ring による白リボンメッシュ)
# ==============================================================================
class SlashEffect < Zenoo::Sprite
  def initialize(player, angle, mesh)
    # プレイヤーの体・手元の高さ (足元から上へ 32px) を中心として配置
    super(player.x, player.y - 32.0, mesh, anchor: :center, pivot: :center, blend: :add)
    @player = player
    self.angle = angle
    self.scale_y = player.facing_x # 左右反転時も振り下ろし方向・グラデーション向きを対称にする
    @timer = 12
    @max_timer = 12
  end

  def update
    # ★ 攻撃スライド中もプレイヤーの移動に完全追従！
    self.x = @player.x
    self.y = @player.y - 32.0

    @timer -= 1
    t = @timer.to_f / @max_timer
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
      rx = 36.0
      ry = Math.sin(ang) > 0 ? 20.0 : 32.0

      px = 45.0 + Math.cos(ang) * rx
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
  BASE_SCALE = 0.75
  HOP_CYCLE  = 48 # ホップ周期 (フレーム)
  HIT_TIME   = 38 # 被弾・ノックバックの3回バウンド時間 (フレーム)

  attr_reader :hp, :max_hp, :jump_z

  def initialize(x, y, mesh)
    super(x, y, mesh, anchor: :bottom_center, pivot: :bottom_center)
    @hp = 3
    @max_hp = 3
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
    if @hit_timer > 0
      # ★ 被弾バウンド & ノックバック処理:
      # 3回ポン・ピョン・ピョンと弾みながら、遠くへ (約110px) 吹き飛ぶ！
      @hit_timer -= 1
      elapsed = HIT_TIME - @hit_timer

      # 水平移動 (等比摩擦で滑らかに減衰しながら遠くへ)
      self.x += @vx
      self.y += @vy
      @vx *= 0.935
      @vy *= 0.935

      # 画面外制限 (640x360 仮想解像度)
      self.x = self.x.clamp(28.0, VIRTUAL_WIDTH - 28.0)
      self.y = self.y.clamp(36.0, VIRTUAL_HEIGHT - 36.0)

      # ★ 3回バウンド (大ホップ -> 中ホップ -> 小ホップ) の立体軌道
      # 弾んでいる最中は丸い形状を一貫してキープし、せわしないつぶれを排除！
      jump_z = 0.0
      sx = 0.86
      sy = 1.22

      if elapsed < 16
        # 第1バウンド (0..15): 大ホップ (丸い形状)
        t = elapsed.to_f / 16.0
        jump_z = Math.sin(t * Math::PI) * 20.0
      elsif elapsed < 28
        # 第2バウンド (16..27): 中ホップ (丸い形状)
        t = (elapsed - 16).to_f / 12.0
        jump_z = Math.sin(t * Math::PI) * 11.0
      elsif elapsed < 36
        # 第3バウンド (28..35): 小ホップ (丸い形状)
        t = (elapsed - 28).to_f / 8.0
        jump_z = Math.sin(t * Math::PI) * 5.0
      else
        # 3回バウンド終了後、通常形状へ滑らかに復帰
        jump_z = 0.0
        t = (elapsed - 36).to_f / 2.0
        sx = 0.86 + (1.0 - 0.86) * t
        sy = 1.22 + (1.0 - 1.22) * t
      end

      @jump_z = jump_z

      # 被弾点滅演出 (通常被弾は最初10フレーム、撃破時は第2バウンドまで派手に点滅)
      flash_duration = @dying ? 24 : 10
      if elapsed < flash_duration
        self.color = elapsed.even? ? [255, 120, 120, 255] : :white
      else
        self.color = nil
      end

      # ★ 撃破時のフェードアウト消滅 (第3バウンド中に透明になり、終了時に消滅)
      if @dying
        if elapsed >= 26
          fade_t = (elapsed - 26).to_f / 12.0
          self.alpha = (255.0 * (1.0 - fade_t)).clamp(0, 255).to_i
        end
        if @hit_timer <= 0
          vanish
          return
        end
      end

      self.scale_x = @facing_x * BASE_SCALE * sx
      self.scale_y = BASE_SCALE * sy
      return
    else
      @jump_z = 0.0
      self.color = nil
    end

    # プレイヤーへの追従 & ぷるぷるホップ
    dx = target_x - self.x
    dy = (target_y - 16.0) - self.y
    dist = Math.hypot(dx, dy)

    @facing_x = (dx >= 0 ? 1.0 : -1.0) if dist > 10.0

    @hop_tick = (@hop_tick + 1) % HOP_CYCLE

    sx = 1.0
    sy = 1.0

    if @hop_tick < 14
      # 1. ジャンプ準備: グッと横に潰れてタメる
      t = @hop_tick.to_f / 14.0
      sx = 1.0 + t * 0.22
      sy = 1.0 - t * 0.18
      @jump_z = 0.0
    elsif @hop_tick < 34
      # 2. ホップ空中: 縦長に伸びて前進！
      t = (@hop_tick - 14).to_f / 20.0
      sx = 0.86
      sy = 1.22
      @jump_z = Math.sin(t * Math::PI) * 8.0 # 通常ホップも少しふわりと浮く
      if dist > 32.0
        spd = 2.4
        self.x += (dx / dist) * spd
        self.y += (dy / dist) * (spd * 0.8) # 見下ろしパース補正
      end
    elsif @hop_tick < 42
      # 3. 着地: ボヨンと横に弾む
      t = (@hop_tick - 34).to_f / 8.0
      sx = 1.18 - t * 0.12
      sy = 0.84 + t * 0.12
      @jump_z = 0.0
    else
      # 4. 通常形状へ復元
      sx = 1.0
      sy = 1.0
      @jump_z = 0.0
    end

    self.scale_x = @facing_x * BASE_SCALE * sx
    self.scale_y = BASE_SCALE * sy

    # 画面外制限 (640x360 仮想解像度)
    self.x = self.x.clamp(28.0, VIRTUAL_WIDTH - 28.0)
    self.y = self.y.clamp(36.0, VIRTUAL_HEIGHT - 36.0)
  end

  # ★ 描画時はジャンプ高さ分だけ上に浮かせて描画！ (地面の y 座標・影の位置は維持)
  def draw
    orig_y = self.y
    self.y -= @jump_z
    super
    self.y = orig_y
  end

  def hit(kb_x, kb_y)
    return if @dying # 撃破中は二重ヒットしない

    @hp -= 1
    @dying = true if @hp <= 0
    @hit_timer = HIT_TIME

    # 3回弾みながら遠くへノックバックする初速 (約 110px 後退)
    spd = @dying ? 8.2 : 7.6 # 撃破時は少し豪快に吹き飛ぶ
    @vx = kb_x * spd
    @vy = kb_y * (spd * 0.8) # 見下ろしパース補正
  end
end

class IsoPlayer < Zenoo::Sprite
  SPEED = 5.0
  Y_RATIO = 0.8 # クォータービューの奥行きパースに合わせて縦移動を 80% に補正

  DIR_DOWN = 0 # 手前 (右下アングル)
  DIR_UP   = 1 # 奥 (右上アングル)

  # 静的シンボル配列 (動的シンボル生成・ヒープ割り当てゼロ)
  WALK_ANIMS   = [:walk_down,   :walk_up].freeze
  IDLE_ANIMS   = [:idle_down,   :idle_up].freeze
  ATTACK_ANIMS = [:attack_down, :attack_up].freeze

  attr_reader :dir_y, :facing_x, :moving, :attacking
  attr_accessor :effects, :enemies

  def initialize(x, y)
    # ★ 見下ろしアクションの鉄則: 足元・接地点基準 (bottom_center)
    super(x, y, anchor: :bottom_center, pivot: :bottom_center)

    # 向き管理: 手前 (DIR_DOWN) / 奥 (DIR_UP)、左右 (1.0: 右 / -1.0: 左)
    @dir_y = DIR_DOWN
    @facing_x = 1.0
    @moving = false
    @attacking = false
    @vx = 0.0
    @vy = 0.0
    @effects = nil
    @enemies = nil
    @attack_timer = 0
    @hit_targets = {}
    @atk_dir_x = 1.0
    @atk_dir_y = Y_RATIO
    @last_move_dx = 1.0 # 最後に移動した方向ベクトル (X)
    @last_move_dy = 1.0 # 最後に移動した方向ベクトル (Y)

    # 120度円弧の白リボンメッシュ (半径 75px, 内径比率 0.6, 加算合成)
    @slash_mesh = Zenoo::Mesh.ring(
      75,
      inner_radius: 0.6,
      start_angle: -60.0,
      end_angle: 60.0,
      color: :white,
      blend: :add
    )

    # ★ 左側（根本・振り始め）からアルファ値を下げてグラデーションにする (0: 透明 -> 255: 白)
    @slash_mesh.deform do |v|
      ratio = v.col.to_f / @slash_mesh.cols
      v.alpha = (ratio ** 1.8) * 255.0
    end

    load_animations
    play(IDLE_ANIMS[@dir_y])
  end

  def update
    if @attacking
      # 前方への滑らかな踏み込みスライド移動 (摩擦減速)
      self.x += @vx
      self.y += @vy
      @vx *= 0.85
      @vy *= 0.85

      # ★ 攻撃判定の持続 (踏み込みスライド中の最初の12フレーム、エフェクト発生中は毎フレーム判定！)
      if @attack_timer < 12
        check_slash_hit
      end
      @attack_timer += 1

      # 画面端クランプ (余白 24px)
      self.x = self.x.clamp(24.0, VIRTUAL_WIDTH - 24.0)
      self.y = self.y.clamp(32.0, VIRTUAL_HEIGHT - 32.0)

      # 攻撃アニメーション終了検知 (30フレーム = 0.5秒)
      if animation_finished?
        @attacking = false
        play(IDLE_ANIMS[@dir_y])
      end
    else
      # 攻撃入力判定 (キー押下の瞬間のみトリガー)
      if Zenoo::Input.action_push?(:attack)
        @attacking = true
        @attack_timer = 0
        @hit_targets = {} # 今回の攻撃でヒット済みの敵ID (多重ヒット防止)
        @moving = false

        dx, dy = Zenoo::Input.vector

        # 攻撃方向ベクトルの決定 (入力があればその方向、静止時は最後に進んでいた方向)
        if dx != 0.0 || dy != 0.0
          update_direction(dx, dy)
          mag = Math.hypot(dx, dy)
          dir_x = mag > 0.001 ? (dx / mag) : @facing_x
          dir_y = mag > 0.001 ? (dy / mag) : (@dir_y == DIR_DOWN ? 1.0 : -1.0)
          @last_move_dx = dir_x
          @last_move_dy = dir_y
        else
          # 静止状態から攻撃: 最後に移動した方向ベクトルそのものを採用！
          dir_x = @last_move_dx
          dir_y = @last_move_dy

          # スプライトの向き・上下判定も攻撃方向に同期
          update_direction(dir_x, dir_y)
        end

        # ★ スティック入力が浅くても、静止状態からでも、常にフルパワー (初速 7.0) で一定距離を踏み込む！
        @vx = dir_x * 7.0
        @vy = dir_y * (7.0 * Y_RATIO)
        @atk_dir_x = dir_x
        @atk_dir_y = dir_y * Y_RATIO

        # ★ 120度円弧の白リボン斬撃エフェクトをプレイヤー追従で発生！
        if @effects && @slash_mesh
          slash_angle = Math.atan2(@atk_dir_y, @atk_dir_x) * (180.0 / Math::PI)
          @effects << SlashEffect.new(self, slash_angle, @slash_mesh)
        end

        # 攻撃発生フレームでの判定
        check_slash_hit

        play(ATTACK_ANIMS[@dir_y])
      else
        # 移動入力判定
        dx, dy = Zenoo::Input.vector

        if dx != 0.0 || dy != 0.0
          @moving = true
          update_direction(dx, dy)
          mag = Math.hypot(dx, dy)
          if mag > 0.001
            @last_move_dx = dx / mag
            @last_move_dy = dy / mag
          end

          # ★ keep_frame: true により、向きを変えても足運びがリセットされず維持される
          play(WALK_ANIMS[@dir_y], keep_frame: true)

          # クォータービューのパースに合わせて縦方向を Y_RATIO (80%) にスケーリング
          self.x += dx * SPEED
          self.y += dy * (SPEED * Y_RATIO)

          # 画面端クランプ (余白 24px)
          self.x = self.x.clamp(24.0, VIRTUAL_WIDTH - 24.0)
          self.y = self.y.clamp(32.0, VIRTUAL_HEIGHT - 32.0)
        else
          @moving = false
          play(IDLE_ANIMS[@dir_y])
        end
      end
    end

    super # アニメーション更新 (update_animation)
  end

  # ★ 斬撃命中判定 (白リボンエフェクト発生中、毎フレーム実行して滑り込み先の敵も確実に捉える)
  def check_slash_hit
    return unless @enemies

    cx = self.x
    cy = self.y - 32.0 # 斬撃エフェクトの中心

    atk_mag = Math.hypot(@atk_dir_x, @atk_dir_y)
    nx = atk_mag > 0.001 ? (@atk_dir_x / atk_mag) : @facing_x
    ny = atk_mag > 0.001 ? (@atk_dir_y / atk_mag) : 0.0
    slash_rad = Math.atan2(ny, nx)

    @enemies.each do |enemy|
      next if enemy.vanished? || enemy.dying? || @hit_targets[enemy.object_id]

      # 敵の中心座標 (足元から上へ 20px)
      ex = enemy.x
      ey = enemy.y - 20.0
      dx = ex - cx
      dy = ey - cy
      dist = Math.hypot(dx, dy)

      # 斬撃エフェクト半径(約75〜88px) + 敵の当たり半径(約25px) = 115px
      next if dist > 115.0

      # ★ 前方への射影 (内積): 背後の敵 (forward_dist <= 5.0) には絶対に当てない！
      forward_dist = dx * nx + dy * ny
      next if forward_dist <= 5.0

      # 角度差の計算
      enemy_rad = Math.atan2(dy, dx)
      diff = (slash_rad - enemy_rad) % (Math::PI * 2)
      diff -= Math::PI * 2 if diff > Math::PI

      # 前方 150 度 (片側 75 度) または至近距離の前方 170 度 (片側 85 度) でヒット
      is_hit = if diff.abs < (75.0 * Math::PI / 180.0)
        true
      elsif dist <= 40.0 && diff.abs < (85.0 * Math::PI / 180.0)
        true
      else
        false
      end

      if is_hit
        @hit_targets[enemy.object_id] = true

        # ★ ノックバック方向の計算:
        # プレイヤーから敵への放射ベクトルを主体にし、斬撃の前進力もブレンド
        # これにより、当たった位置から自然に外側・前方へ弾き飛ばされる！
        dir_from_p_x = dist > 0.001 ? (dx / dist) : nx
        dir_from_p_y = dist > 0.001 ? (dy / dist) : ny
        kb_x = dir_from_p_x * 0.7 + nx * 0.3
        kb_y = dir_from_p_y * 0.7 + ny * 0.3
        kb_mag = Math.hypot(kb_x, kb_y)
        if kb_mag > 0.001
          kb_x /= kb_mag
          kb_y /= kb_mag
        end

        enemy.hit(kb_x, kb_y)
      end
    end
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

  private

  # 入力から向きを決定 (左右反転 scale_x と上下手前奥 dir_y)
  def update_direction(dx, dy)
    # 左右の向き更新 (横入力がある場合のみ反転)
    if dx > 0.0
      @facing_x = 1.0
      self.scale_x = 1.0
    elsif dx < 0.0
      @facing_x = -1.0
      self.scale_x = -1.0
    end

    # 上下（手前/奥）の向き更新 (縦入力がある場合のみ切り替え)
    if dy > 0.0
      @dir_y = DIR_DOWN # 手前
    elsif dy < 0.0
      @dir_y = DIR_UP   # 奥
    end
  end

  def load_animations
    base_dir = File.join(__dir__, "../assets/sprites")

    # ====================================================
    # 1. 歩行アニメーションの登録 (たったの2アングル！)
    # ====================================================
    # 手前 (右下)
    down_tiles = Zenoo::Image.load_tiles(File.join(base_dir, "player_walk_down_right_3frame_1x.png"), 3, 1)
    add_animation(:walk_down, [down_tiles[0], down_tiles[1], down_tiles[2], down_tiles[1]], wait: 6, loop: true)
    add_animation(:idle_down, [down_tiles[1]], wait: 1, loop: false)

    # 奥 (右上)
    up_tiles = Zenoo::Image.load_tiles(File.join(base_dir, "player_walk_up_right_3frame_1x.png"), 3, 1)
    add_animation(:walk_up, [up_tiles[0], up_tiles[1], up_tiles[2], up_tiles[1]], wait: 6, loop: true)
    add_animation(:idle_up, [up_tiles[1]], wait: 1, loop: false)

    # ====================================================
    # 2. 攻撃アニメーションの登録 (たったの2アングル！)
    # 足元基準 (bottom_center) なので、横方向の重心補正 offset_x: 4 を適用
    # ====================================================
    atk_down_img = Zenoo::Image.load(File.join(base_dir, "player_attack_down_right_1x.png"))
    add_animation(:attack_down, [atk_down_img], wait: 30, loop: false, offset_x: 4, offset_y: 2)

    atk_up_img = Zenoo::Image.load(File.join(base_dir, "player_attack_up_right_1x.png"))
    add_animation(:attack_up, [atk_up_img], wait: 30, loop: false, offset_x: 4, offset_y: 2)
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

  # ベクタースライム敵の生成 (3体配置、メッシュは 1 つを共有)
  slime_mesh = create_slime_mesh
  enemies = [
    SlimeEnemy.new(190.0, 160.0, slime_mesh),
    SlimeEnemy.new(460.0, 130.0, slime_mesh),
    SlimeEnemy.new(320.0, 270.0, slime_mesh)
  ]
  player.enemies = enemies

  # アクションマップ登録 (キーボード・マウス・ゲームパッド)
  Zenoo::Input.define_action(:attack, keys: [:space, :j, :z], mouse: :left, gamepad: [:x, :a, :rb])

  # ★ 縦横半分サイズ (640x360) のオフスクリーン Image
  # nearest フィルタによりピクセルアートやベクターをドット絵調にくっきり 2 倍拡大！
  screen = Zenoo::Image.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
  screen.texture_filter = :nearest if screen.respond_to?(:texture_filter=)

  show_ui = true

  Zenoo::Window.loop(WINDOW_WIDTH, WINDOW_HEIGHT, "Zenoo - 4-Way Diagonal Animated Sprite & Vector Slime Demo") do
    # [H] キーで UI 表示/非表示の切り替え
    show_ui = !show_ui if Zenoo::Input.key_push?(:h)

    # プレイヤー＆エフェクト＆スライム敵の更新
    player.update
    enemies.each { |e| e.update(player.x, player.y) unless e.vanished? }
    Zenoo::Sprite.clean(enemies)

    # 全滅時の自動再出現
    if enemies.empty?
      enemies << SlimeEnemy.new(rand(80.0..560.0), rand(80.0..280.0), slime_mesh)
      enemies << SlimeEnemy.new(rand(80.0..560.0), rand(80.0..280.0), slime_mesh)
    end

    Zenoo::Sprite.update(effects)
    Zenoo::Sprite.clean(effects)

    # ----------------------------------------------------
    # 1. 縦横半分サイズ (640x360) の Image にゲーム世界を描画
    # ----------------------------------------------------
    Zenoo::Image.render_to(screen) do
      # 画面クリア (落ち着いたダークスレート)
      Zenoo::Window.clear([24, 28, 38, 255])

      # 背景の装飾グリッド (32px 刻み)
      grid_step = 32
      (0..VIRTUAL_WIDTH).step(grid_step) do |gx|
        Zenoo::Window.draw_line(gx, 0, gx, VIRTUAL_HEIGHT, width: 1.0, color: [35, 42, 58, 120])
      end
      (0..VIRTUAL_HEIGHT).step(grid_step) do |gy|
        Zenoo::Window.draw_line(0, gy, VIRTUAL_WIDTH, gy, width: 1.0, color: [35, 42, 58, 120])
      end

      # 見下ろし立体描画 (影 → Yソートキャラ → 斬撃エフェクト)
      # 1. 足元のドロップシャドウ (ジャンプ浮き上がり中は影が縮んで薄くなり、消滅時はフェードアウト)
      Zenoo::Window.draw_ellipse(player.x, player.y - 2.0, 22.0, 9.0, color: [10, 12, 18, 140])
      enemies.each do |e|
        next if e.vanished?
        # スライムの体格 (幅約68px) に合わせた存在感あるドロップシャドウ
        scale_ratio = (e.scale_x.abs / SlimeEnemy::BASE_SCALE)
        z_ratio = (1.0 - (e.jump_z / 40.0)).clamp(0.45, 1.0)
        sw = 30.0 * scale_ratio * z_ratio
        sh = 11.5 * z_ratio
        alpha_ratio = (e.alpha.to_f / 255.0)
        shadow_alpha = (140 * z_ratio * alpha_ratio).to_i
        # スライムのお腹の底面に影がぴったり吸着する位置 (e.y - 3.0) に描画
        Zenoo::Window.draw_ellipse(e.x, e.y - 3.0, sw, sh, color: [10, 12, 18, shadow_alpha])
      end

      # 2. Yソートによる正しい前後描画 (足元 y が手前ほど後に描画)
      render_list = [player, *enemies.reject(&:vanished?)].sort_by(&:y)
      render_list.each(&:draw)

      # 3. 敵の頭上 HP 表示 (グリーンドット / ジャンプ中も重ならないよう頭上高めに配置、浮き上がりに追従)
      enemies.each do |e|
        next if e.vanished? || e.dying?
        hp_y = (e.y - e.jump_z) - 64.0
        e.max_hp.times do |i|
          dot_col = (i < e.hp) ? [80, 240, 140, 230] : [70, 80, 95, 180]
          Zenoo::Window.draw_circle(e.x.to_i - 12 + i * 12, hp_y, 3.5, color: dot_col)
        end
      end

      # 4. 斬撃エフェクト描画 (キャラクターの前面)
      Zenoo::Sprite.draw(effects)
    end

    # ----------------------------------------------------
    # 2. 画面 (1280x720) に 2 倍拡大して描画
    # ----------------------------------------------------
    Zenoo::Window.clear([0, 0, 0, 255])
    Zenoo::Window.draw(0, 0, screen, scale_x: 2.0, scale_y: 2.0, anchor: :top_left, pivot: :top_left)

    # ----------------------------------------------------
    # 3. UI & ステータス表示 (高解像度 1280x720 オーバーレイ)
    # ----------------------------------------------------
    if show_ui
      # 左上: 設計コンセプト & 操作ガイド
      Zenoo::Window.draw_rect(24, 20, 520, 192, radius: 10, color: [18, 22, 32, 220], border_width: 1, border_color: [60, 80, 110, 200])
      Zenoo::Window.draw_text(40, 34, "【斜め4方向スプライト & 拡大描画デモ】", size: 18, color: [0, 220, 255, 255])
      Zenoo::Window.draw_text(40, 60, "描画 : 640x360 (Image.render_to) → 1280x720 (2倍拡大描画)", size: 13, color: [160, 220, 255, 255])
      Zenoo::Window.draw_text(40, 82, "自機 : 右下・右上の【たった2枚】で全方位歩行＆攻撃", size: 13, color: [255, 200, 80, 255])
      Zenoo::Window.draw_text(40, 104, "敵機 : Mesh.canvas による潰れスライム (ベクター & 伸縮ホップ)", size: 13, color: [100, 255, 180, 255])
      Zenoo::Window.draw_text(40, 126, "移動 : [W][A][S][D] / 矢印キー / パッド (縦80%パース補正)", size: 13, color: [220, 225, 235, 255])
      Zenoo::Window.draw_text(40, 148, "攻撃 : [SPACE] / [J] / 左クリック / パッド [X][A] (踏み込み)", size: 13, color: [255, 120, 100, 255])
      Zenoo::Window.draw_text(40, 170, "表示 : [H] キーで操作ガイド・モニターの表示切替", size: 13, color: [200, 200, 220, 255])

      # 右上: アニメーション状態リアルタイムモニター
      Zenoo::Window.draw_rect(840, 20, 416, 160, radius: 10, color: [18, 22, 32, 220], border_width: 1, border_color: [60, 80, 110, 200])
      Zenoo::Window.draw_text(856, 34, "【リアルタイム状態モニター】", size: 18, color: [0, 220, 255, 255])
      Zenoo::Window.draw_text(856, 64, "現在のアニメーション : #{player.animation}", size: 15, color: :white)
      Zenoo::Window.draw_text(856, 90, "現在の向き : #{player.direction_name} (scale_x: #{player.scale_x})", size: 15, color: [100, 255, 180, 255])

      # 描画オフセット
      ox = player.animation_offset_x
      oy = player.animation_offset_y
      Zenoo::Window.draw_text(856, 116, "描画オフセット : [#{ox}, #{oy}]", size: 15, color: [180, 200, 255, 255])

      # コマ進行度
      cycle_frame = player.current_frame_index
      cycle_name = if player.attacking
        "攻撃モーション (1コマ/30フレーム/0.5秒)"
      else
        ["0 (左足)", "1 (直立)", "2 (右足)", "1 (直立)"][cycle_frame] || cycle_frame.to_s
      end
      Zenoo::Window.draw_text(856, 142, "現在のコマ : #{cycle_frame} [#{cycle_name}]", size: 15, color: [255, 220, 100, 255])
    else
      # 最小化インジケーター
      Zenoo::Window.draw_rect(24, 20, 280, 36, radius: 8, color: [18, 22, 32, 180], border_width: 1, border_color: [60, 80, 110, 160])
      Zenoo::Window.draw_text(36, 29, "[H] キーで操作ガイド・モニターを表示", size: 13, color: [180, 210, 240, 230])
    end
  end
end

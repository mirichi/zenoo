# frozen_string_literal: true
# ==============================================================================
# Zenoo: GPU Danmaku Storm (数万発クラスの弾幕 & 円環セクター高速衝突判定デモ)
# ==============================================================================
# 【特徴】
# 1. 頂点シェーダー演算による 60,000〜120,000 発の超高密度弾幕 (Ruby側毎フレーム 0 pack)
# 2. 扇状円弧（円環セクター: Annular Sector）による階層的衝突判定 (Broadphase)
#    - 出現時間による距離範囲 (R_min .. R_max) と扇の角度範囲 (phi) で 99% の弾を一瞬で枝刈り
#    - 自機が円弧内に入った時のみ、インデックスから直近数発の弾だけを O(1) でピンポイント判定
# 3. [C] キーで衝突判定の円環セクター（当たり判定バウンディングボックス）を可視化
#
# 操作方法:
#   - マウス移動 / カーソルキー: 自機移動
#   - [Shift] (キーボード移動時): 低速移動（精密回避モード）
#   - [C]: 衝突判定の円環セクター可視化トグル
#   - [1] [2] [3]: 弾数切り替え (30,000 / 60,000 / 120,000 発)
#   - [SPACE]: ボム（弾消し衝撃波）
# ==============================================================================

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../ext/zenoo", __dir__)
require 'zenoo'

WIDTH  = 1280
HEIGHT = 720

# ------------------------------------------------------------------------------
# 頂点シェーダー: 弾道計算・進行方向への自動姿勢制御・ビルボード展開
# ------------------------------------------------------------------------------
DANMAKU_VERT = <<~'GLSL'
  #version 330 core

  layout (location = 0) in vec4 in_origin_angle; // x0, y0, base_angle, ang_vel
  layout (location = 1) in vec4 in_motion;       // speed, accel, angle_offset, bullet_type (0:米粒, 1:丸弾)
  layout (location = 2) in vec4 in_timing;       // t0, life, size, loop_period
  layout (location = 3) in vec4 in_color;        // r, g, b, a

  uniform vec2  u_resolution;
  uniform float u_flip_y;
  uniform float u_time;
  uniform vec2  u_bomb_pos;
  uniform float u_bomb_radius;

  out vec4 v_color;
  out vec2 v_uv;
  flat out float v_type;

  void main() {
      float t0 = in_timing.x;
      float life = in_timing.y;
      float size = in_timing.z;
      float loop_period = in_timing.w;

      float age = u_time - t0;
      if (loop_period > 0.0) {
          age = mod(age, loop_period);
      }

      // 寿命外または発射前ならクリッピング (画面外へ)
      if (age < 0.0 || age > life) {
          gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
          return;
      }

      // 弾道力学計算
      float base_angle = in_origin_angle.z;
      float ang_vel = in_origin_angle.w;
      float angle_offset = in_motion.z;
      float speed = in_motion.x;
      float accel = in_motion.y;

      // 現在の進行方向角
      float cur_angle = base_angle + angle_offset + ang_vel * age;
      // 進行距離
      float dist = speed * age + 0.5 * accel * age * age;

      vec2 p0 = in_origin_angle.xy;
      vec2 cur_pos = p0 + vec2(cos(cur_angle), sin(cur_angle)) * dist;

      // 発射直後のフェードイン (ボスの中心での密集・白飛びを防止)
      float spawn_fade = clamp((dist - 15.0) / 25.0, 0.0, 1.0);
      if (spawn_fade <= 0.0) {
          gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
          return;
      }

      // ボムによる消滅判定
      if (u_bomb_radius > 0.0) {
          if (distance(cur_pos, u_bomb_pos) < u_bomb_radius) {
              gl_Position = vec4(2.0, 2.0, 0.0, 1.0);
              return;
          }
      }

      // ビルボード展開 (gl_VertexID: 0..3)
      vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1)) - vec2(0.5);

      vec2 local_offset = corner * size;
      if (in_motion.w < 0.5) {
          // 米粒弾: 進行方向にシャープに細長く (x: 2.2倍, y: 0.7倍)
          local_offset.x *= 2.2;
          local_offset.y *= 0.7;
      }

      // 進行方向ベクトルに沿ってクアッドを回転
      vec2 dir = vec2(cos(cur_angle), sin(cur_angle));
      vec2 perp = vec2(-dir.y, dir.x);
      vec2 rotated_offset = dir * local_offset.x + perp * local_offset.y;

      vec2 final_pos = cur_pos + rotated_offset;

      // NDC座標系への変換
      vec2 ndc = (final_pos / u_resolution) * 2.0 - 1.0;
      ndc.y = ndc.y * ((u_flip_y == 0.0) ? -1.0 : u_flip_y);
      gl_Position = vec4(ndc, 0.0, 1.0);

      v_color = vec4(in_color.rgb, in_color.a * spawn_fade);
      v_uv = corner + vec2(0.5);
      v_type = in_motion.w;
  }
GLSL

# ------------------------------------------------------------------------------
# フラグメントシェーダー: 暗い輪郭線 + 鮮やかカラー + 白芯コア (重なっても白飛びしない)
# ------------------------------------------------------------------------------
DANMAKU_FRAG = <<~'GLSL'
  #version 330 core

  in vec4 v_color;
  in vec2 v_uv;
  flat in float v_type;
  out vec4 fragColor;

  void main() {
      vec2 p = (v_uv - vec2(0.5)) * 2.0;
      float d;

      if (v_type < 0.5) {
          // 米粒弾: 進行方向 (x) に長い楕円
          d = length(vec2(p.x * 0.48, p.y * 1.25));
      } else {
          // 丸弾
          d = length(p);
      }

      if (d > 1.0) {
          discard;
      }

      // STG 3層レイヤードレンダリング:
      // 1. 外周 (d > 0.72): 暗色のアウトライン (何重に重なっても輪郭を保ち白飛びしない)
      // 2. 中間 (0.3 < d <= 0.72): ネオンカラー
      // 3. 中心 (d <= 0.3): 白い芯 (コア)
      vec3 col;
      float alpha = v_color.a;

      if (d > 0.72) {
          float t_edge = (1.0 - d) / (1.0 - 0.72);
          col = v_color.rgb * 0.25; // 濃いアウトライン
          alpha *= smoothstep(0.0, 0.3, t_edge);
      } else if (d > 0.3) {
          float t_mid = (d - 0.3) / (0.72 - 0.3);
          col = mix(v_color.rgb, v_color.rgb * 0.8, t_mid);
      } else {
          float t_core = d / 0.3;
          col = mix(vec3(1.0, 1.0, 1.0), v_color.rgb, t_core * t_core);
      }

      fragColor = vec4(col, alpha);
  }
GLSL

# ------------------------------------------------------------------------------
# 補助描画関数: 黒アウトライン付きライン描画 (Spinel AOT 互換)
# ------------------------------------------------------------------------------
def draw_boxed_line(x1, y1, x2, y2, color, width, z = 50.0)
  Window.draw_line(x1, y1, x2, y2, color: :black, width: width + 3.5, z: z - 0.5)
  Window.draw_line(x1, y1, x2, y2, color: color, width: width, z: z)
end
class DanmakuGroup
  attr_accessor :origin_x, :origin_y
  attr_accessor :base_angle, :ang_vel
  attr_accessor :speed, :accel
  attr_accessor :angle_spread
  attr_accessor :t0, :duration, :life, :loop_period
  attr_accessor :ways, :layers
  attr_accessor :size, :bullet_radius, :bullet_type
  attr_accessor :color

  # デバッグ用状態
  attr_accessor :in_distance_range, :in_sector_range, :hit_detected
  attr_reader :tested_bullet_positions

  def initialize(opts = {})
    @origin_x     = opts.fetch(:x, WIDTH * 0.5)
    @origin_y     = opts.fetch(:y, 160.0)
    @base_angle   = opts.fetch(:base_angle, Math::PI * 0.5) # 初期方向（下向き）
    @ang_vel      = opts.fetch(:ang_vel, 0.0)               # 扇自体の回転角速度
    @speed        = opts.fetch(:speed, 180.0)
    @accel        = opts.fetch(:accel, 0.0)
    @angle_spread = opts.fetch(:angle_spread, Math::PI * 0.5) # 扇の開き角 (90度)
    @t0           = opts.fetch(:t0, 0.0)
    @duration     = opts.fetch(:duration, 0.4)              # 発射持続時間
    @life         = opts.fetch(:life, 4.5)                  # 弾の寿命
    @loop_period  = opts.fetch(:loop_period, 5.0)           # 再発射ループ周期
    @ways         = opts.fetch(:ways, 24)                   # 角度方向の弾数
    @layers       = opts.fetch(:layers, 8)                  # 時間方向の層数
    @size         = opts.fetch(:size, 14.0)                 # 描画サイズ
    @bullet_radius = opts.fetch(:bullet_radius, 4.0)        # 判定半径
    @bullet_type  = opts.fetch(:bullet_type, 0)             # 0:米粒, 1:丸
    @color        = opts.fetch(:color, [1.0, 0.3, 0.5, 1.0])

    @in_distance_range = false
    @in_sector_range   = false
    @hit_detected      = false
    @tested_bullet_positions = []
  end

  # フレームごとの衝突判定状態をクリア
  def clear_frame_state
    @in_distance_range = false
    @in_sector_range   = false
    @hit_detected      = false
    @tested_bullet_positions.clear
  end

  def total_bullets
    @ways * @layers
  end

  # VBO用の Float 配列を生成
  def append_vbo_data(out_floats)
    d_angle_step = @ways > 1 ? (@angle_spread / (@ways - 1)) : 0.0
    half_spread  = @angle_spread * 0.5
    d_time_step  = @layers > 1 ? (@duration / (@layers - 1)) : 0.0

    @layers.times do |l|
      spawn_t = @t0 + l * d_time_step
      @ways.times do |w|
        offset_ang = (@ways > 1) ? (-half_spread + w * d_angle_step) : 0.0

        # location 0: x0, y0, base_angle, ang_vel
        out_floats.push(@origin_x, @origin_y, @base_angle, @ang_vel)
        # location 1: speed, accel, angle_offset, bullet_type
        out_floats.push(@speed, @accel, offset_ang, @bullet_type.to_f)
        # location 2: t0, life, size, loop_period
        out_floats.push(spawn_t, @life, @size, @loop_period)
        # location 3: color (r, g, b, a)
        out_floats.push(@color[0], @color[1], @color[2], @color[3])
      end
    end
  end

  # ----------------------------------------------------------------------------
  # 現在の円環セクター幾何パラメータを計算 [r_min, r_max, a_start, a_end, center_angle, age]
  # ----------------------------------------------------------------------------
  def current_geometry(cur_time)
    age = cur_time - @t0
    age = age % @loop_period if @loop_period > 0.0
    return nil if age < 0.0 || age > (@duration + @life)

    t_head = [age, @life].min
    t_tail = [age - @duration, 0.0].max
    return nil if t_tail >= @life

    r_max = @speed * t_head + 0.5 * @accel * (t_head**2) + @bullet_radius
    r_min = [@speed * t_tail + 0.5 * @accel * (t_tail**2) - @bullet_radius, 0.0].max

    t_mid = (t_head + t_tail) * 0.5
    cur_center_angle = @base_angle + @ang_vel * t_mid
    twist_margin = (@ang_vel * (t_head - t_tail) * 0.5).abs
    half_spread = @angle_spread * 0.5 + twist_margin

    [r_min, r_max, cur_center_angle - half_spread, cur_center_angle + half_spread, cur_center_angle, half_spread, age]
  end

  # ----------------------------------------------------------------------------
  # 円環セクター（Annular Sector）衝突判定
  # ----------------------------------------------------------------------------
  def check_collision(px, py, pr, cur_time)
    @in_distance_range = false
    @in_sector_range   = false
    @hit_detected      = false
    @tested_bullet_positions = []

    geom = current_geometry(cur_time)
    return false unless geom

    r_min, r_max, _a_s, _a_e, cur_center_angle, half_spread, age = geom

    # 1. Broadphase (1): 距離チェック (円環の最小半径 R_min 〜 最大半径 R_max)
    dx = px - @origin_x
    dy = py - @origin_y
    dist_sq = dx * dx + dy * dy

    min_bound = [r_min - pr, 0.0].max
    max_bound = r_max + pr

    return false if dist_sq < min_bound * min_bound
    return false if dist_sq > max_bound * max_bound

    @in_distance_range = true

    # 2. Broadphase (2): 角度チェック (扇の角度範囲)
    dist = Math.sqrt(dist_sq)
    return false if dist < 0.001

    player_angle = Math.atan2(dy, dx)

    # 角度差の正規化 (-PI .. PI)
    diff = (player_angle - cur_center_angle + Math::PI) % (Math::PI * 2.0) - Math::PI
    angle_margin = [pr / dist, 1.0].min # 自機半径分の角度マージン

    return false if diff.abs > (half_spread + angle_margin)

    @in_sector_range = true

    # 3. Narrowphase: 扇形円弧内に入った！
    # 自機に最も近い弾のインデックスを数学的に逆算し、ピンポイント判定
    hit = evaluate_narrowphase(px, py, pr, dist, diff, age, half_spread)
    @hit_detected = hit
    hit
  end

  private

  def evaluate_narrowphase(px, py, pr, dist, diff, age, half_spread)
    d_angle_step = @ways > 1 ? (@angle_spread / (@ways - 1)) : 1.0
    approx_w = @ways > 1 ? ((diff + half_spread) / d_angle_step).round : 0
    d_time_step = @layers > 1 ? (@duration / (@layers - 1)) : 0.0

    w_min = [approx_w - 1, 0].max
    w_max = [approx_w + 1, @ways - 1].min

    hit_dist_sq = (pr + @bullet_radius)**2
    hit = false

    (0...@layers).each do |l|
      bullet_age = age - l * d_time_step
      next if bullet_age < 0.0 || bullet_age > @life

      b_dist = @speed * bullet_age + 0.5 * @accel * (bullet_age**2)
      next if (b_dist - dist).abs > (pr + @bullet_radius + 15.0)

      (w_min..w_max).each do |w|
        offset_ang = @ways > 1 ? (-half_spread + w * d_angle_step) : 0.0
        cur_ang = @base_angle + offset_ang + @ang_vel * bullet_age

        bx = @origin_x + Math.cos(cur_ang) * b_dist
        by = @origin_y + Math.sin(cur_ang) * b_dist

        @tested_bullet_positions << [bx, by]

        bx_diff = px - bx
        by_diff = py - by
        if (bx_diff * bx_diff + by_diff * by_diff) <= hit_dist_sq
          hit = true
        end
      end
    end

    hit
  end
end

# ------------------------------------------------------------------------------
# 弾幕ジェネレータ (数万〜10万発のグループ群を構築)
# ------------------------------------------------------------------------------
def build_danmaku_system(total_target_count)
  puts "Building Danmaku System (~#{total_target_count} bullets)..."
  groups = []

  # ボス原点
  boss_x = WIDTH * 0.5
  boss_y = 180.0

  loop_period = 6.0

  # パターン 1: 米粒弾 (まっすぐ飛ぶ扇状スプレッド弾幕 / 回転角速度なし)
  # 進行方向に沿って直線に飛ぶため、米粒弾の間を綺麗にすり抜けられる
  14.times do |i|
    groups << DanmakuGroup.new(
      x: boss_x, y: boss_y,
      base_angle: Math::PI * 0.5, # 真下
      ang_vel: 0.0,               # 直進！回転なし！
      angle_spread: Math::PI * 0.55, # 約100度扇
      speed: 160.0 + (i % 3) * 35.0,
      t0: i * 0.4,
      duration: 0.22,
      life: 5.5,
      loop_period: loop_period,
      ways: 32,
      layers: 8,
      size: 13.0,
      bullet_radius: 3.5,
      bullet_type: 0, # 米粒弾 (直進)
      color: [1.0, 0.25, 0.45, 0.95] # ネオンピンク
    )
  end

  # パターン 2: 回転スパイラル弾幕 (小さい丸弾 / 渦巻き状に回転)
  # 回転させる弾は「小さい丸弾」に限定し、斜めの棒にならないようにする
  4.times do |arm|
    arm_angle = arm * (Math::PI * 0.5)

    # 時計回り (ネオンシアンの小丸弾)
    10.times do |step|
      groups << DanmakuGroup.new(
        x: boss_x, y: boss_y,
        base_angle: arm_angle,
        ang_vel: 0.65, # 回転
        angle_spread: Math::PI * 0.22, # 40度扇
        speed: 130.0 + step * 12.0,
        t0: step * 0.5,
        duration: 0.35,
        life: 5.5,
        loop_period: loop_period,
        ways: 28,
        layers: 10,
        size: 8.0,           # 小さい丸弾
        bullet_radius: 2.2,
        bullet_type: 1,      # 丸弾！
        color: [0.1, 0.85, 1.0, 0.9] # ネオンシアン
      )
    end

    # 反時計回り (ネオンパープルの小丸弾)
    10.times do |step|
      groups << DanmakuGroup.new(
        x: boss_x, y: boss_y,
        base_angle: arm_angle + Math::PI * 0.25,
        ang_vel: -0.65, # 逆回転
        angle_spread: Math::PI * 0.22,
        speed: 140.0 + step * 10.0,
        t0: 0.25 + step * 0.5,
        duration: 0.35,
        life: 5.5,
        loop_period: loop_period,
        ways: 28,
        layers: 10,
        size: 8.0,           # 小さい丸弾
        bullet_radius: 2.2,
        bullet_type: 1,      # 丸弾！
        color: [0.95, 0.2, 0.95, 0.9] # ネオンパープル
      )
    end
  end

  # パターン 3: 曼荼羅・花弁弾幕 (全方位展開・小〜中丸弾・直進)
  # カラーを「ディープ・スカイブルー」に統一し、デバッグの黄色・緑・オレンジと完全分離
  12.times do |pet|
    pet_angle = pet * (Math::PI * 2.0 / 12.0)
    6.times do |step|
      groups << DanmakuGroup.new(
        x: boss_x, y: boss_y,
        base_angle: pet_angle,
        ang_vel: 0.0, # 直進
        angle_spread: Math::PI * 0.16,
        speed: 95.0 + step * 18.0,
        t0: 0.8 + step * 0.7,
        duration: 0.35,
        life: 5.5,
        loop_period: loop_period,
        ways: 20,
        layers: 8,
        size: 9.0,          # 小丸弾
        bullet_radius: 2.6,
        bullet_type: 1,     # 丸弾
        color: [0.15, 0.55, 1.0, 0.95] # エレクトリック・ディープブルー
      )
    end
  end

  # 目標弾数に応じてスケール (複製して時間オフセット)
  scale = (total_target_count.to_f / groups.sum(&:total_bullets)).ceil
  if scale > 1
    base_groups = groups.dup
    (1...scale).each do |s|
      base_groups.each do |g|
        cloned = g.dup
        cloned.t0 = (g.t0 + s * (loop_period / scale)) % loop_period
        groups << cloned
      end
    end
  end

  actual_count = groups.sum(&:total_bullets)
  puts "Constructed #{groups.size} groups, Total: #{actual_count} bullets."
  [groups, actual_count]
end

# ------------------------------------------------------------------------------
# メッシュ生成
# ------------------------------------------------------------------------------
def create_danmaku_mesh(groups, shader, pipeline)
  t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  raw_floats = []
  groups.each { |g| g.append_vbo_data(raw_floats) }

  packed = raw_floats.pack("f*")
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_start) * 1000.0
  puts "VBO Packed: #{groups.sum(&:total_bullets)} bullets, #{packed.bytesize / 1024 / 1024} MB (#{elapsed.round(1)} ms)"

  Mesh.new(
    data: packed,
    count: groups.sum(&:total_bullets),
    pipeline: pipeline,
    shader: shader,
    blend: :add # アルファ合成 (重なっても白飛びしない)
  )
end

# ------------------------------------------------------------------------------
# 初期化
# ------------------------------------------------------------------------------
danmaku_shader = Shader.new(DANMAKU_VERT, DANMAKU_FRAG)

# パイプライン: vec4 x 4 (16 floats per bullet)
danmaku_pipeline = Zenoo::Backend::Pipeline.new(
  Zenoo::Backend::Topology::TRIANGLE_STRIP,
  "\x04\x04\x04\x04",
  "\x01\x01\x01\x01",
  4
)

target_count = 60_000
groups, total_count = build_danmaku_system(target_count)
active_mesh = create_danmaku_mesh(groups, danmaku_shader, danmaku_pipeline)

# 自機ステータス
player_x = WIDTH * 0.5
player_y = HEIGHT * 0.82
player_r = 3.0          # 自機当たり判定半径 (STG定番の小さめコア)
player_graze_r = 20.0   # かすり半径

score = 0
graze_count = 0
hit_flash = 0.0
bomb_radius = 0.0
bomb_pos = [0.0, 0.0]

show_sectors = true # デバッグ: 円環セクター可視化
time = 0.0
collision_time_us = 0.0

fps_timer = 0.0
frame_count = 0
last_fps = 60.0

puts "Starting Zenoo Danmaku Demo..."

# ------------------------------------------------------------------------------
# メインループ
# ------------------------------------------------------------------------------
Window.loop(WIDTH, HEIGHT, "Zenoo - 60,000 GPU Danmaku & Annular Sector Collision", vsync: false) do
  dt = Window.delta_time
  time += dt

  # --- 入力と自機移動 ---
  speed = Input.key_pressed?(:left_shift) || Input.key_pressed?(:right_shift) ? 180.0 : 380.0

  if Input.key_pressed?(:left)  || Input.key_pressed?(:a) then player_x -= speed * dt end
  if Input.key_pressed?(:right) || Input.key_pressed?(:d) then player_x += speed * dt end
  if Input.key_pressed?(:up)    || Input.key_pressed?(:w) then player_y -= speed * dt end
  if Input.key_pressed?(:down)  || Input.key_pressed?(:s) then player_y += speed * dt end

  # マウス操作対応 (左クリックで追従)
  if Input.mouse_pressed?(:left)
    player_x += (Input.mouse_x - player_x) * 0.15
    player_y += (Input.mouse_y - player_y) * 0.15
  end

  player_x = [[player_x, 30.0].max, WIDTH - 30.0].min
  player_y = [[player_y, 40.0].max, HEIGHT - 30.0].min

  # [C] キーで円環セクター可視化切り替え
  show_sectors = !show_sectors if Input.key_push?(:c)

  # [SPACE] キーでボム発動
  if Input.key_push?(:space) && bomb_radius <= 0.0
    bomb_radius = 10.0
    bomb_pos = [player_x, player_y]
  end

  if bomb_radius > 0.0
    bomb_radius += dt * 600.0
    bomb_radius = 0.0 if bomb_radius > 1200.0
  end

  # --- 円環セクター高速衝突判定 (CPU側) ---
  t_col_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # 毎フレーム必ず全グループの状態を完全クリア (前フレームの残骸を防止)
  groups.each { |g| g.clear_frame_state }

  any_hit = false
  tested_groups = 0
  sector_hits = 0

  groups.each do |g|
    tested_groups += 1
    if g.check_collision(player_x, player_y, player_r, time)
      any_hit = true
      # デモのため break せず全グループ更新 (取り残し防止)
    end
    sector_hits += 1 if g.in_sector_range
  end

  collision_time_us = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_col_start) * 1_000_000.0

  if any_hit
    hit_flash = 1.0
    score = [score - 500, 0].max
  end
  hit_flash = [hit_flash - dt * 3.5, 0.0].max

  # --- 画面クリア ---
  clear_color = hit_flash > 0.0 ? [50, 15, 20, 255] : [10, 12, 20, 255]
  Window.clear(clear_color)

  # --- GPU 弾幕描画 (1 ドローコール) ---
  active_mesh.draw(
    z: 10.0,
    uniforms: {
      u_time:        time,
      u_bomb_pos:    bomb_pos,
      u_bomb_radius: bomb_radius
    }
  )

  # --- デバッグ描画: 円環セクター（Annular Sector）バウンディング可視化 ---
  if show_sectors
    groups.each do |g|
      # 距離範囲に入っている、または扇角内に入っているグループを表示
      next unless g.in_distance_range || g.in_sector_range

      geom = g.current_geometry(time)
      next unless geom

      r_min, r_max, a_start, a_end, _cur_center, _half_spread, _age = geom
      next if r_max < 20.0

      ox = g.origin_x
      oy = g.origin_y

      # 加算合成の強い光の中でも埋もれない高コントラスト色 (黒縁付き)
      # 弾幕（青・紫・ピンク）の補色となる「アンバーオレンジ」と「ネオン・ライムグリーン」を採用
      if g.in_sector_range
        # 扇角内に突入！ネオン・ライムグリーン (判定中)
        wire_col = [0, 255, 60, 255]
        line_w = 3.0
      else
        # 距離範囲内！鮮やかなアンバーオレンジ (接近中)
        wire_col = [255, 150, 10, 255]
        line_w = 2.5
      end

      # 外円弧 (8分割)
      steps = 8
      d_ang = (a_end - a_start) / steps.to_f
      prev_x = ox + Math.cos(a_start) * r_max
      prev_y = oy + Math.sin(a_start) * r_max
      steps.times do |s|
        ang = a_start + d_ang * (s + 1)
        cur_x = ox + Math.cos(ang) * r_max
        cur_y = oy + Math.sin(ang) * r_max
        draw_boxed_line(prev_x, prev_y, cur_x, cur_y, wire_col, line_w)
        prev_x = cur_x
        prev_y = cur_y
      end

      # 内円弧
      if r_min > 10.0
        prev_x = ox + Math.cos(a_start) * r_min
        prev_y = oy + Math.sin(a_start) * r_min
        steps.times do |s|
          ang = a_start + d_ang * (s + 1)
          cur_x = ox + Math.cos(ang) * r_min
          cur_y = oy + Math.sin(ang) * r_min
          draw_boxed_line(prev_x, prev_y, cur_x, cur_y, wire_col, line_w)
          prev_x = cur_x
          prev_y = cur_y
        end
      end

      # 左右の境界線
      x_in_s  = ox + Math.cos(a_start) * r_min
      y_in_s  = oy + Math.sin(a_start) * r_min
      x_out_s = ox + Math.cos(a_start) * r_max
      y_out_s = oy + Math.sin(a_start) * r_max
      draw_boxed_line(x_in_s, y_in_s, x_out_s, y_out_s, wire_col, line_w)

      x_in_e  = ox + Math.cos(a_end) * r_min
      y_in_e  = oy + Math.sin(a_end) * r_min
      x_out_e = ox + Math.cos(a_end) * r_max
      y_out_e = oy + Math.sin(a_end) * r_max
      draw_boxed_line(x_in_e, y_in_e, x_out_e, y_out_e, wire_col, line_w)

      # 実際に自機との距離判定を行った直近弾のレティクル (黒フチ + 蛍光グリーン十字)
      g.tested_bullet_positions.each do |bx, by|
        reticle_r = g.bullet_radius + 7.5
        # 黒い下敷き
        Window.draw_circle(bx, by, reticle_r, border_color: :black, border_width: 5.0, z: 69.5)
        Window.draw_line(bx - 10, by, bx + 10, by, color: :black, width: 4.5, z: 69.5)
        Window.draw_line(bx, by - 10, bx, by + 10, color: :black, width: 4.5, z: 69.5)
        # 蛍光ライムグリーンの芯
        target_col = [0, 255, 60, 255]
        Window.draw_circle(bx, by, reticle_r, border_color: target_col, border_width: 2.0, z: 70.0)
        Window.draw_line(bx - 10, by, bx + 10, by, color: target_col, width: 2.0, z: 70.0)
        Window.draw_line(bx, by - 10, bx, by + 10, color: target_col, width: 2.0, z: 70.0)
      end
    end
  end

  # --- ボス描画 ---
  boss_x = WIDTH * 0.5
  boss_y = 180.0
  Window.draw_circle(boss_x, boss_y, 28, color: [220, 50, 70, 255], z: 30.0)
  Window.draw_circle(boss_x, boss_y, 34, border_color: [255, 100, 120, 160], border_width: 2.0, z: 30.0)
  Window.draw_text(boss_x - 30, boss_y - 8, "BOSS", size: 16, color: :white, z: 35.0)

  # --- 自機描画 ---
  p_color = hit_flash > 0.0 ? [255, 60, 60, 255] : [60, 200, 255, 255]
  # 自機機体
  Window.draw_circle(player_x, player_y, 14, border_color: p_color, border_width: 2.0, z: 60.0)
  # 自機コア (極小の当たり判定)
  Window.draw_circle(player_x, player_y, player_r, color: [255, 40, 40, 255], z: 70.0)
  Window.draw_circle(player_x, player_y, player_r + 1.0, border_color: :white, border_width: 1.0, z: 70.0)

  # ボム波面描画
  if bomb_radius > 0.0
    Window.draw_circle(bomb_pos[0], bomb_pos[1], bomb_radius, border_color: [120, 230, 255, 140], border_width: 3.0, z: 45.0)
  end

  # --- UI / テキスト表示 ---
  frame_count += 1
  @total_frames ||= 0
  @total_frames += 1

  fps_timer += dt
  if fps_timer >= 0.5
    last_fps = (frame_count / fps_timer).round(1)
    frame_count = 0
    fps_timer = 0.0
  end

  if ENV["TEST_FRAMES"] && @total_frames >= ENV["TEST_FRAMES"].to_i
    puts "TEST_FRAMES reached (#{ENV['TEST_FRAMES']} frames). Exiting cleanly."
    break
  end

  total_tested_bullets = groups.sum { |g| g.tested_bullet_positions.size }

  Window.draw_rect(10, 10, 500, 140, radius: 8, color: [0.05, 0.08, 0.12, 0.85], border_width: 1, border_color: [0.2, 0.4, 0.6, 0.8], z: 100.0)
  Window.draw_text(24, 20, "Zenoo GPU Danmaku Storm: #{total_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} Bullets", size: 22, color: :white, z: 101.0)
  Window.draw_text(24, 48, "FPS: #{last_fps}  |  DrawCall: 1  |  Ruby pack: 0/frame", size: 16, color: [0.4, 1.0, 0.6, 1.0], z: 101.0)
  Window.draw_text(24, 72, "Collision Time (CPU): #{collision_time_us.round(1)} us (#{tested_groups} groups)", size: 15, color: [1.0, 0.85, 0.3, 1.0], z: 101.0)
  Window.draw_text(24, 96, "In-Sector: #{sector_hits} grp | Evaluated Bullets: #{total_tested_bullets} / #{total_count}", size: 14, color: sector_hits > 0 ? [1.0, 0.9, 0.2, 1.0] : [0.6, 0.8, 1.0, 1.0], z: 101.0)
  Window.draw_text(24, 120, "[WASD/Mouse] Move  [Shift] Slow  [C] Sectors (#{show_sectors ? 'ON' : 'OFF'})  [Space] Bomb", size: 13, color: [0.7, 0.8, 0.9, 0.8], z: 101.0)
end

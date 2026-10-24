# frozen_string_literal: true

# ==============================================================================
# Zenoo: 2D Particle Effect Designer & Editor
# ==============================================================================
# 炎、煙、爆発、魔法、雪などの2Dパーティクルエフェクトを
# GUIスライダーでリアルタイムにパラメータ調整しながらプレビュー・編集できるツールです。
# ==============================================================================

require_relative '../lib/zenoo'

# ------------------------------------------------------------------------------
# 1. 高速パーティクルデータ構造 (オブジェクト再利用プール方式)
# ------------------------------------------------------------------------------
class Particle
  attr_accessor :active, :x, :y, :vx, :vy, :life, :max_life,
                :start_size, :end_size, :size,
                :sr, :sg, :sb, :sa, :er, :eg, :eb, :ea,
                :r, :g, :b, :a,
                :angle, :spin, :wobble_freq, :wobble_amp, :wobble_phase

  def initialize
    @active = false
    @x = 0.0
    @y = 0.0
    @vx = 0.0
    @vy = 0.0
    @life = 0.0
    @max_life = 1.0
    @start_size = 10.0
    @end_size = 0.0
    @size = 10.0
    @sr = 255.0; @sg = 255.0; @sb = 255.0; @sa = 255.0
    @er = 255.0; @eg = 255.0; @eb = 255.0; @ea = 0.0
    @r = 255.0;  @g = 255.0;  @b = 255.0;  @a = 255.0
    @angle = 0.0
    @spin = 0.0
    @wobble_freq = 0.0
    @wobble_amp = 0.0
    @wobble_phase = 0.0
  end
end

# ------------------------------------------------------------------------------
# 2. パーティクルシステムエンジン
# ------------------------------------------------------------------------------
class ParticleSystem
  DEG_TO_RAD = Math::PI / 180.0
  POOL_SIZE = 3000

  attr_accessor :emitter_x, :emitter_y
  attr_accessor :emitting, :emission_rate, :burst_count
  attr_accessor :lifetime, :lifetime_var
  attr_accessor :speed, :speed_var
  attr_accessor :angle_deg, :spread_deg
  attr_accessor :gravity_x, :gravity_y
  attr_accessor :friction
  attr_accessor :wobble_amp, :wobble_freq
  attr_accessor :spin_speed
  attr_accessor :start_size, :end_size
  attr_accessor :start_r, :start_g, :start_b, :start_a
  attr_accessor :end_r,   :end_g,   :end_b,   :end_a
  attr_accessor :blend_mode   # :add or :alpha
  attr_accessor :shape_type   # 0: Circle(Glow), 1: Box, 2: Spark(Line), 3: Ring

  attr_reader :alive_count

  def initialize(x = 640.0, y = 360.0)
    @emitter_x = x.to_f
    @emitter_y = y.to_f
    @pool = Array.new(POOL_SIZE) { Particle.new }
    @emit_accumulator = 0.0
    @alive_count = 0
    @rng = Random.new

    reset_defaults
    preset_fire
  end

  def reset_defaults
    @emitting       = true
    @emission_rate  = 120.0 # 個 / 秒
    @burst_count    = 60
    @lifetime       = 0.7
    @lifetime_var   = 0.2
    @speed          = 150.0
    @speed_var      = 40.0
    @angle_deg      = 270.0 # 上向き
    @spread_deg     = 40.0
    @gravity_x      = 0.0
    @gravity_y      = -30.0 # 軽い上昇浮力
    @friction       = 0.98
    @wobble_amp     = 15.0
    @wobble_freq    = 8.0
    @spin_speed     = 0.0
    @start_size     = 22.0
    @end_size       = 4.0
    @start_r = 255.0; @start_g = 210.0; @start_b = 60.0;  @start_a = 240.0
    @end_r   = 240.0; @end_g   = 40.0;  @end_b   = 10.0;  @end_a   = 0.0
    @blend_mode     = :add
    @shape_type     = 0 # Circle
  end

  # --- プリセット群 ---

  def preset_fire
    reset_defaults
    @emission_rate = 150.0
    @lifetime = 0.65
    @lifetime_var = 0.2
    @speed = 140.0
    @speed_var = 50.0
    @angle_deg = 270.0 # 上
    @spread_deg = 35.0
    @gravity_y = -40.0
    @friction = 0.985
    @wobble_amp = 20.0
    @wobble_freq = 6.0
    @start_size = 24.0
    @end_size = 2.0
    @start_r = 255.0; @start_g = 220.0; @start_b = 60.0;  @start_a = 255.0
    @end_r   = 220.0; @end_g   = 30.0;  @end_b   = 10.0;  @end_a   = 0.0
    @blend_mode = :add
    @shape_type = 0
  end

  def preset_explosion
    reset_defaults
    @emitting = false
    @burst_count = 180
    @lifetime = 0.8
    @lifetime_var = 0.3
    @speed = 360.0
    @speed_var = 160.0
    @angle_deg = 0.0
    @spread_deg = 360.0 # 全方位
    @gravity_y = 60.0
    @friction = 0.92 # 急速ブレーキ
    @start_size = 30.0
    @end_size = 2.0
    @start_r = 255.0; @start_g = 240.0; @start_b = 180.0; @start_a = 255.0
    @end_r   = 210.0; @end_g   = 50.0;  @end_b   = 15.0;  @end_a   = 0.0
    @blend_mode = :add
    @shape_type = 0
    burst(@burst_count)
  end

  def preset_sparks
    reset_defaults
    @emission_rate = 80.0
    @burst_count = 100
    @lifetime = 0.9
    @lifetime_var = 0.3
    @speed = 320.0
    @speed_var = 120.0
    @angle_deg = 270.0
    @spread_deg = 140.0
    @gravity_y = 450.0 # 強い落下重力
    @friction = 0.975
    @start_size = 6.0
    @end_size = 1.5
    @start_r = 255.0; @start_g = 230.0; @start_b = 100.0; @start_a = 255.0
    @end_r   = 255.0; @end_g   = 70.0;  @end_b   = 20.0;  @end_a   = 0.0
    @blend_mode = :add
    @shape_type = 2 # Spark (Lines)
  end

  def preset_smoke
    reset_defaults
    @emission_rate = 45.0
    @lifetime = 1.6
    @lifetime_var = 0.4
    @speed = 50.0
    @speed_var = 25.0
    @angle_deg = 270.0
    @spread_deg = 45.0
    @gravity_y = -15.0 # ゆっくり上昇
    @friction = 0.99
    @wobble_amp = 30.0
    @wobble_freq = 3.0
    @start_size = 10.0
    @end_size = 56.0 # 広がる
    @start_r = 160.0; @start_g = 160.0; @start_b = 175.0; @start_a = 180.0
    @end_r   = 70.0;  @end_g   = 70.0;  @end_b   = 80.0;   @end_a   = 0.0
    @blend_mode = :alpha
    @shape_type = 0
  end

  def preset_magic
    reset_defaults
    @emission_rate = 140.0
    @lifetime = 1.0
    @lifetime_var = 0.3
    @speed = 90.0
    @speed_var = 40.0
    @angle_deg = 0.0
    @spread_deg = 360.0
    @gravity_y = -10.0
    @friction = 0.97
    @wobble_amp = 25.0
    @wobble_freq = 7.0
    @start_size = 18.0
    @end_size = 3.0
    @start_r = 60.0;  @start_g = 230.0; @start_b = 255.0; @start_a = 240.0
    @end_r   = 210.0; @end_g   = 60.0;  @end_b   = 255.0; @end_a   = 0.0
    @blend_mode = :add
    @shape_type = 3 # Ring
  end

  def preset_snow
    reset_defaults
    @emission_rate = 60.0
    @lifetime = 3.5
    @lifetime_var = 1.0
    @speed = 60.0
    @speed_var = 20.0
    @angle_deg = 90.0 # 下向き
    @spread_deg = 30.0
    @gravity_y = 15.0
    @friction = 0.995
    @wobble_amp = 40.0
    @wobble_freq = 2.0
    @start_size = 5.0
    @end_size = 4.0
    @start_r = 230.0; @start_g = 245.0; @start_b = 255.0; @start_a = 220.0
    @end_r   = 180.0; @end_g   = 210.0; @end_b   = 240.0; @end_a   = 60.0
    @blend_mode = :alpha
    @shape_type = 1 # Box
  end

  def preset_stars
    reset_defaults
    @emission_rate = 40.0
    @burst_count = 60
    @lifetime = 1.4
    @lifetime_var = 0.4
    @speed = 340.0
    @speed_var = 100.0
    @angle_deg = 270.0
    @spread_deg = 70.0
    @gravity_y = 520.0 # 放物線
    @friction = 0.99
    @spin_speed = 360.0 # 高速スピン
    @start_size = 14.0
    @end_size = 8.0
    @start_r = 255.0; @start_g = 220.0; @start_b = 40.0;  @start_a = 255.0
    @end_r   = 255.0; @end_g   = 160.0; @end_b   = 20.0;  @end_a   = 0.0
    @blend_mode = :alpha
    @shape_type = 1 # Box
  end

  # 一斉放出 (Burst)
  def burst(count = @burst_count)
    c = 0
    while c < count
      spawn_particle
      c += 1
    end
  end

  # 全消去
  def clear
    i = 0
    len = @pool.length
    while i < len
      @pool[i].active = false
      i += 1
    end
    @alive_count = 0
  end

  # 1フレーム更新
  def update(dt)
    # 1. 放出処理
    if @emitting && @emission_rate > 0.0
      @emit_accumulator += @emission_rate * dt
      while @emit_accumulator >= 1.0
        spawn_particle
        @emit_accumulator -= 1.0
      end
    end

    # 2. パーティクル更新
    alive = 0
    i = 0
    len = @pool.length
    while i < len
      p = @pool[i]
      if p.active
        p.life -= dt
        if p.life <= 0.0
          p.active = false
        else
          progress = 1.0 - (p.life / p.max_life)

          # 速度更新
          p.vx += @gravity_x * dt
          p.vy += @gravity_y * dt
          p.vx *= @friction
          p.vy *= @friction

          # 位置更新
          p.x += p.vx * dt
          p.y += p.vy * dt

          # 乱流・ゆらぎ
          if p.wobble_amp > 0.0
            w_offset = Math.sin(p.wobble_phase + progress * p.wobble_freq * Math::PI * 2.0) * p.wobble_amp * dt
            p.x += w_offset
          end

          # 回転
          p.angle += p.spin * dt if p.spin != 0.0

          # サイズ補間
          p.size = p.start_size + (p.end_size - p.start_size) * progress

          # カラー補間
          p.r = p.sr + (p.er - p.sr) * progress
          p.g = p.sg + (p.eg - p.sg) * progress
          p.b = p.sb + (p.eb - p.sb) * progress
          p.a = p.sa + (p.ea - p.sa) * progress

          alive += 1
        end
      end
      i += 1
    end
    @alive_count = alive
  end

  # 描画
  def draw
    i = 0
    len = @pool.length
    while i < len
      p = @pool[i]
      if p.active && p.size > 0.1 && p.a > 1.0
        col = Color.new(p.r.to_i, p.g.to_i, p.b.to_i, p.a.to_i)
        case @shape_type
        when 0 # Circle (SDF Glow)
          r = p.size * 0.5
          Window.draw_circle(p.x, p.y, r, color: col, blend: @blend_mode)
        when 1 # Box (Rotation support)
          hs = p.size * 0.5
          Window.draw_rect(p.x - hs, p.y - hs, p.size, p.size, angle: p.angle, color: col, blend: @blend_mode)
        when 2 # Spark (Lines based on velocity)
          tail_x = p.x - p.vx * 0.035
          tail_y = p.y - p.vy * 0.035
          lw = [p.size * 0.35, 1.0].max
          Window.draw_line(p.x, p.y, tail_x, tail_y, color: col, width: lw, blend: @blend_mode)
        when 3 # Ring (Shockwave)
          r = p.size * 0.5
          bw = [p.size * 0.12, 1.0].max
          Window.draw_circle(p.x, p.y, r, color: nil, border_color: col, border_width: bw, blend: @blend_mode)
        end
      end
      i += 1
    end
  end

  private

  def spawn_particle
    # 空きパーティクルを探す
    p = nil
    i = 0
    len = @pool.length
    while i < len
      unless @pool[i].active
        p = @pool[i]
        break
      end
      i += 1
    end
    return unless p # プール上限到達時はスキップ

    # 寿命
    l_var = (@rng.rand * 2.0 - 1.0) * @lifetime_var
    p.max_life = [@lifetime + l_var, 0.05].max
    p.life = p.max_life

    # 位置
    p.x = @emitter_x
    p.y = @emitter_y

    # 角度と初速
    spr = (@rng.rand * 2.0 - 1.0) * (@spread_deg * 0.5)
    rad = (@angle_deg + spr) * DEG_TO_RAD
    s_var = (@rng.rand * 2.0 - 1.0) * @speed_var
    cur_spd = [@speed + s_var, 0.0].max

    p.vx = Math.cos(rad) * cur_spd
    p.vy = Math.sin(rad) * cur_spd

    # サイズ
    p.start_size = @start_size
    p.end_size   = @end_size
    p.size       = @start_size

    # カラー
    p.sr = @start_r; p.sg = @start_g; p.sb = @start_b; p.sa = @start_a
    p.er = @end_r;   p.eg = @end_g;   p.eb = @end_b;   p.ea = @end_a
    p.r  = @start_r; p.g  = @start_g; p.b  = @start_b; p.a  = @start_a

    # 回転 & ゆらぎ
    p.angle = @rng.rand * 360.0
    p.spin  = (@rng.rand * 2.0 - 1.0) * @spin_speed
    p.wobble_amp   = @wobble_amp
    p.wobble_freq  = @wobble_freq
    p.wobble_phase = @rng.rand * Math::PI * 2.0

    p.active = true
  end
end

# ------------------------------------------------------------------------------
# 3. エディタ GUI アプリケーション
# ------------------------------------------------------------------------------
system = ParticleSystem.new(500.0, 360.0)

tab_index = 0
bg_mode = 0 # 0: Dark Navy, 1: Pitch Black, 2: Gray Grid
is_dragging_emitter = false

shape_names = ["Circle (Glow)", "Box (Rotate)", "Spark (Line)", "Ring (Shock)"]
blend_names = ["Add (加算合成)", "Alpha (通常合成)"]

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo - 2D Particle Effect Designer & Editor", msaa: 4) do
  dt = Window.delta_time
  mx = Input.mouse_x.to_f
  my = Input.mouse_y.to_f

  # -------------------------------------------------------------------
  # 背景描画
  # -------------------------------------------------------------------
  case bg_mode
  when 0 # Dark Navy
    Window.clear(Color.new(18, 20, 28))
    grid_col = Color.new(28, 30, 40)
  when 1 # Pitch Black
    Window.clear(Color.new(4, 4, 6))
    grid_col = Color.new(16, 16, 20)
  when 2 # Gray
    Window.clear(Color.new(40, 42, 48))
    grid_col = Color.new(55, 58, 66)
  end

  # グリッド
  gx = 0.0
  while gx < 820.0
    Window.draw_line(gx, 0, gx, 720, color: grid_col)
    gx += 40.0
  end
  gy = 0.0
  while gy < 720.0
    Window.draw_line(0, gy, 820, gy, color: grid_col)
    gy += 40.0
  end

  # -------------------------------------------------------------------
  # マウス操作 (キャンバス領域: X < 820)
  # -------------------------------------------------------------------
  if mx < 820.0
    # 左クリックドラッグでエミッター移動
    if Input.mouse_down?(:left)
      system.emitter_x = mx
      system.emitter_y = my
    end
    # 右クリックでワンショットバースト
    if Input.mouse_push?(:right)
      system.burst
    end
  end

  # スペースキーでバースト
  system.burst if Input.key_push?(:space)

  # パーティクル更新 & 描画
  system.update(dt)
  system.draw

  # エミッター中心マーカー描画
  ex = system.emitter_x
  ey = system.emitter_y
  Window.draw_circle(ex, ey, 6.0, color: nil, border_color: Color.new(255, 255, 255, 180), border_width: 1.5)
  Window.draw_line(ex - 10, ey, ex + 10, ey, color: Color.new(255, 255, 255, 120))
  Window.draw_line(ex, ey - 10, ex, ey + 10, color: Color.new(255, 255, 255, 120))

  # ヘッダーガイドテキスト
  Window.draw_text(25.0, 16.0, "Zenoo 2D Particle Designer", size: 22, color: Color::WHITE)
  Window.draw_text(25.0, 44.0, "Left Drag: Move Emitter | Right Click / Space: Burst | Active: #{system.alive_count} / #{ParticleSystem::POOL_SIZE}", size: 13, color: Color.new(160, 200, 240))

  # -------------------------------------------------------------------
  # 右側GUIコントロールパネル (X: 830, 幅: 430)
  # -------------------------------------------------------------------
  GUI.window("Particle Properties", x: 830, y: 15, w: 435, h: 690, resizable: false) do
    tab_index = GUI.tabs(["Presets", "Emitter", "Motion", "Visuals", "Code"], tab_index)
    GUI.spacer(6)

    case tab_index
    when 0 # Presets
      GUI.label("=== Quick Effect Presets ===", size: 15, color: Color.new(255, 200, 80))
      GUI.spacer(4)

      GUI.row(cols: 2, spacing: 6) do
        system.preset_fire if GUI.button("🔥 Fire (炎)")
        system.preset_explosion if GUI.button("💥 Explosion (爆発)")
      end
      GUI.spacer(4)
      GUI.row(cols: 2, spacing: 6) do
        system.preset_sparks if GUI.button("✨ Sparks (火花)")
        system.preset_smoke if GUI.button("💨 Smoke (煙)")
      end
      GUI.spacer(4)
      GUI.row(cols: 2, spacing: 6) do
        system.preset_magic if GUI.button("🌀 Magic (魔法)")
        system.preset_snow if GUI.button("❄️ Snow (雪)")
      end
      GUI.spacer(4)
      GUI.row(cols: 2, spacing: 6) do
        system.preset_stars if GUI.button("🌟 Stars (コイン星)")
        system.reset_defaults if GUI.button("Default Reset")
      end

      GUI.spacer(8)
      GUI.divider
      GUI.label("=== Global Actions ===", size: 15, color: Color.new(100, 220, 255))
      GUI.spacer(4)

      GUI.row(cols: 2, spacing: 6) do
        system.burst if GUI.button("💥 BURST! (Space)")
        system.clear if GUI.button("Clear All")
      end

      GUI.spacer(6)
      system.emitting = GUI.checkbox("Continuous Emission", system.emitting)

      GUI.spacer(8)
      GUI.divider
      GUI.label("=== Background Preview ===", size: 15, color: Color.new(255, 200, 80))
      GUI.row(cols: 3, spacing: 4) do
        bg_mode = 0 if GUI.radio("Dark", bg_mode == 0)
        bg_mode = 1 if GUI.radio("Black", bg_mode == 1)
        bg_mode = 2 if GUI.radio("Gray", bg_mode == 2)
      end

    when 1 # Emitter & Timing
      GUI.label("=== Emitter Timing ===", size: 15, color: Color.new(255, 200, 80))
      system.emission_rate = GUI.slider("Emit Rate (p/s)", system.emission_rate, 5.0, 500.0)
      system.burst_count   = GUI.spinner("Burst Count", system.burst_count, min: 10, max: 500, step: 10)

      GUI.spacer(6)
      GUI.divider
      GUI.label("=== Particle Lifetime ===", size: 15, color: Color.new(255, 200, 80))
      system.lifetime     = GUI.slider("Lifetime (s)", system.lifetime, 0.1, 4.0)
      system.lifetime_var = GUI.slider("Lifetime Var (s)", system.lifetime_var, 0.0, 1.5)

    when 2 # Motion & Physics
      GUI.label("=== Velocity & Direction ===", size: 15, color: Color.new(255, 200, 80))
      system.speed       = GUI.slider("Speed", system.speed, 0.0, 600.0)
      system.speed_var   = GUI.slider("Speed Variance", system.speed_var, 0.0, 250.0)
      system.angle_deg   = GUI.slider("Angle (deg)", system.angle_deg, 0.0, 360.0)
      system.spread_deg  = GUI.slider("Spread (deg)", system.spread_deg, 0.0, 360.0)

      GUI.spacer(6)
      GUI.divider
      GUI.label("=== Forces & Damping ===", size: 15, color: Color.new(255, 200, 80))
      system.gravity_x   = GUI.slider("Gravity X", system.gravity_x, -400.0, 400.0)
      system.gravity_y   = GUI.slider("Gravity Y", system.gravity_y, -600.0, 600.0)
      system.friction    = GUI.slider("Friction", system.friction, 0.90, 1.0)

      GUI.spacer(6)
      GUI.divider
      GUI.label("=== Turbulence & Spin ===", size: 15, color: Color.new(255, 200, 80))
      system.wobble_amp  = GUI.slider("Wobble Amp", system.wobble_amp, 0.0, 60.0)
      system.wobble_freq = GUI.slider("Wobble Freq", system.wobble_freq, 0.5, 20.0)
      system.spin_speed  = GUI.slider("Spin Speed (deg/s)", system.spin_speed, 0.0, 720.0)

    when 3 # Visuals & Color
      GUI.label("=== Particle Shape & Blend ===", size: 15, color: Color.new(255, 200, 80))
      GUI.label("Shape: #{shape_names[system.shape_type]}", size: 13, color: Color.new(120, 220, 255))
      GUI.row(cols: 2, spacing: 4) do
        system.shape_type = 0 if GUI.radio("Circle (Glow)", system.shape_type == 0)
        system.shape_type = 1 if GUI.radio("Box (Rotate)", system.shape_type == 1)
      end
      GUI.row(cols: 2, spacing: 4) do
        system.shape_type = 2 if GUI.radio("Spark (Line)", system.shape_type == 2)
        system.shape_type = 3 if GUI.radio("Ring (Wave)", system.shape_type == 3)
      end

      GUI.spacer(4)
      GUI.row(cols: 2, spacing: 4) do
        system.blend_mode = :add if GUI.radio("Blend: Add", system.blend_mode == :add)
        system.blend_mode = :alpha if GUI.radio("Blend: Alpha", system.blend_mode == :alpha)
      end

      GUI.spacer(6)
      GUI.divider
      GUI.label("=== Size Transition ===", size: 15, color: Color.new(255, 200, 80))
      system.start_size = GUI.slider("Start Size", system.start_size, 1.0, 80.0)
      system.end_size   = GUI.slider("End Size", system.end_size, 0.0, 80.0)

      GUI.spacer(6)
      GUI.divider
      GUI.label("=== Start Color (RGBA) ===", size: 15, color: Color.new(255, 200, 80))
      system.start_r = GUI.slider("Start R", system.start_r, 0.0, 255.0)
      system.start_g = GUI.slider("Start G", system.start_g, 0.0, 255.0)
      system.start_b = GUI.slider("Start B", system.start_b, 0.0, 255.0)
      system.start_a = GUI.slider("Start Alpha", system.start_a, 0.0, 255.0)

      GUI.spacer(4)
      GUI.label("=== End Color (RGBA) ===", size: 15, color: Color.new(255, 200, 80))
      system.end_r = GUI.slider("End R", system.end_r, 0.0, 255.0)
      system.end_g = GUI.slider("End G", system.end_g, 0.0, 255.0)
      system.end_b = GUI.slider("End B", system.end_b, 0.0, 255.0)
      system.end_a = GUI.slider("End Alpha", system.end_a, 0.0, 255.0)

    when 4 # Code Export
      GUI.label("=== Zenoo Particle Integration ===", size: 15, color: Color.new(255, 200, 80))
      GUI.label("Use this snippet in your game code:", size: 12, color: Color.new(160, 160, 180))
      GUI.spacer(6)

      GUI.scroll_view("export_code_scroll", h: 360.0) do
        GUI.label("# --- Particle Emitter Setup ---", size: 12, color: Color.new(120, 220, 255))
        GUI.label("ps = ParticleSystem.new(x, y)", size: 12)
        GUI.label("ps.shape_type    = #{system.shape_type}", size: 12)
        GUI.label("ps.blend_mode    = :#{system.blend_mode}", size: 12)
        GUI.label("ps.emission_rate = #{system.emission_rate.round(1)}", size: 12)
        GUI.label("ps.lifetime      = #{system.lifetime.round(2)}", size: 12)
        GUI.label("ps.speed         = #{system.speed.round(1)}", size: 12)
        GUI.label("ps.angle_deg     = #{system.angle_deg.round(1)}", size: 12)
        GUI.label("ps.spread_deg    = #{system.spread_deg.round(1)}", size: 12)
        GUI.label("ps.gravity_y     = #{system.gravity_y.round(1)}", size: 12)
        GUI.label("ps.friction      = #{system.friction.round(3)}", size: 12)
        GUI.label("ps.start_size    = #{system.start_size.round(1)}", size: 12)
        GUI.label("ps.end_size      = #{system.end_size.round(1)}", size: 12)
        GUI.label("ps.start_r = #{system.start_r.to_i}; ps.start_g = #{system.start_g.to_i}; ps.start_b = #{system.start_b.to_i}; ps.start_a = #{system.start_a.to_i}", size: 12)
        GUI.label("ps.end_r   = #{system.end_r.to_i};   ps.end_g   = #{system.end_g.to_i};   ps.end_b   = #{system.end_b.to_i};   ps.end_a   = #{system.end_a.to_i}", size: 12)
        GUI.spacer(4)
        GUI.label("# In game loop:", size: 12, color: Color.new(140, 240, 180))
        GUI.label("ps.update(Window.delta_time)", size: 12, color: Color.new(255, 220, 100))
        GUI.label("ps.draw", size: 12, color: Color.new(255, 220, 100))
      end
    end
  end

  frame_count += 1
  break if test_max > 0 && frame_count >= test_max
end

puts "Particle Editor test completed (#{frame_count} frames)."

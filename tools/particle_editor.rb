# frozen_string_literal: true

# ==============================================================================
# Zenoo: 2D GPU Particle Effect Designer & Multi-Layer Editor
# ==============================================================================
# Zenoo::ParticleSystem / ParticleEmitter (InstanceBuffer + GPU解析シェーダー) を用い、
# 数千〜数万個のパーティクルをリアルタイムに編集・合成・コード出力できるツールです。
# - スライダーを動かすと Uniform 経由で「今飛んでいる粒子」にも即座に物理・色が反映されます。
# - マルチレイヤー対応（例: 黒煙 + 炎コア + 火花 + 衝撃波リング の重ね合わせ）。
# ==============================================================================

require_relative '../lib/zenoo'

WIDTH  = 1280
HEIGHT = 720
CANVAS_W = 810.0

system = ParticleSystem.preset(:fire, CANVAS_W * 0.5, HEIGHT * 0.55)
selected_layer = 0
tab_index = 0
bg_mode = 0 # 0: Dark Navy, 1: Pitch Black, 2: Slate Grid
show_gizmo = true

SHAPE_LIST       = [:circle, :box, :spark, :ring, :star, :diamond, :soft].freeze
SHAPE_LABELS     = ["Circle (Glow)", "Box (Square)", "Spark (Line)", "Ring (Wave)", "Star (Kirakira)", "Diamond", "Soft Smoke"].freeze
SPAWN_SHAPE_LIST = [:point, :circle, :ring, :box, :line].freeze
SPAWN_LABELS     = ["Point (点)", "Circle (円内)", "Ring (円周)", "Box (矩形)", "Line (線分)"].freeze
CURVE_LIST       = [:linear, :sine, :ease_out, :ease_in].freeze
CURVE_LABELS     = ["Linear (線形)", "Sine (山なり)", "EaseOut (急→緩)", "EaseIn (緩→急)"].freeze
BLEND_LIST       = [:add, :alpha, :multiply].freeze
BLEND_LABELS     = ["Add (加算発光)", "Alpha (通常半透明)", "Multiply (乗算)"].freeze

# 放出範囲ギズモの描画ヘルパー
def draw_emitter_gizmo(em)
  ex = em.x
  ey = em.y
  col_border = Color.new(100, 220, 255, 110)
  case em.spawn_shape
  when :circle
    Window.draw_circle(ex, ey, em.spawn_radius, color: nil, border_color: col_border, border_width: 1.5)
    if em.spawn_inner_radius > 1.0
      Window.draw_circle(ex, ey, em.spawn_inner_radius, color: nil, border_color: Color.new(255, 180, 80, 90), border_width: 1.0)
    end
  when :ring
    Window.draw_circle(ex, ey, em.spawn_radius, color: nil, border_color: col_border, border_width: 1.5)
  when :box
    w = em.spawn_width
    h = em.spawn_height
    Window.draw_rect(ex - w * 0.5, ey - h * 0.5, w, h, color: nil, border_color: col_border, border_width: 1.5)
  when :line
    rad = (em.angle - 90.0) * (Math::PI / 180.0)
    hw = em.spawn_width * 0.5
    dx = Math.cos(rad) * hw
    dy = Math.sin(rad) * hw
    Window.draw_line(ex - dx, ey - dy, ex + dx, ey + dy, color: col_border, width: 2.0)
  end

  # 中心十字マーカー
  Window.draw_circle(ex, ey, 5.0, color: nil, border_color: Color.new(255, 255, 255, 180), border_width: 1.5)
  Window.draw_line(ex - 9.0, ey, ex + 9.0, ey, color: Color.new(255, 255, 255, 130))
  Window.draw_line(ex, ey - 9.0, ex, ey + 9.0, color: Color.new(255, 255, 255, 130))
end

# Ruby コード文字列の生成ヘルパー
def generate_ruby_code(system)
  lines = []
  lines << "# Zenoo GPU ParticleSystem (Multi-Layer)"
  lines << "ps = Zenoo::ParticleSystem.new(x, y)"
  system.emitters.each_with_index do |em, idx|
    h = em.to_h
    lines << ""
    lines << "# --- Layer #{idx + 1} (#{h[:shape]}, #{h[:blend]}) ---"
    lines << "ps.add_emitter("
    lines << "  max_particles: #{em.max_particles},"
    lines << "  shape: :#{h[:shape]}, blend: :#{h[:blend]}, local_space: #{h[:local_space]},"
    lines << "  emitting: #{h[:emitting]}, emission_rate: #{h[:emission_rate]}, burst_count: #{h[:burst_count]},"
    lines << "  spawn_shape: :#{h[:spawn_shape]}, spawn_radius: #{h[:spawn_radius]}, spawn_inner_radius: #{h[:spawn_inner_radius]},"
    lines << "  spawn_width: #{h[:spawn_width]}, spawn_height: #{h[:spawn_height]}, radial_direction: #{h[:radial_direction]},"
    lines << "  lifetime: #{h[:lifetime]}, lifetime_var: #{h[:lifetime_var]},"
    lines << "  speed: #{h[:speed]}, speed_var: #{h[:speed_var]}, angle: #{h[:angle]}, spread: #{h[:spread]},"
    lines << "  gravity_x: #{h[:gravity_x]}, gravity_y: #{h[:gravity_y]}, drag: #{h[:drag]},"
    lines << "  radial_accel: #{h[:radial_accel]}, tangential_accel: #{h[:tangential_accel]},"
    lines << "  wobble_amp: #{h[:wobble_amp]}, wobble_freq: #{h[:wobble_freq]}, spin: #{h[:spin]}, spin_var: #{h[:spin_var]},"
    lines << "  align_to_velocity: #{h[:align_to_velocity]}, stretch: #{h[:stretch]},"
    lines << "  start_size: #{h[:start_size]}, end_size: #{h[:end_size]}, size_var: #{h[:size_var]}, size_curve: :#{h[:size_curve]},"
    lines << "  start_color: #{h[:start_color].inspect},"
    lines << "  mid_color:   #{h[:mid_color].inspect},"
    lines << "  end_color:   #{h[:end_color].inspect},"
    lines << "  color_mid_pos: #{h[:color_mid_pos]}, color_var: #{h[:color_var]}, fade_in: #{h[:fade_in]}, fade_out: #{h[:fade_out]}"
    lines << ")"
  end
  lines.join("\n")
end

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0
copy_feedback_timer = 0.0

Window.loop(WIDTH, HEIGHT, "Zenoo - 2D GPU Particle Designer & Editor") do
  dt = Window.delta_time
  copy_feedback_timer -= dt if copy_feedback_timer > 0.0
  mx = Input.mouse_x.to_f
  my = Input.mouse_y.to_f

  # -------------------------------------------------------------------
  # 1. 背景とグリッドの描画
  # -------------------------------------------------------------------
  case bg_mode
  when 0
    Window.clear(Color.new(14, 16, 24))
    grid_col = Color.new(26, 30, 42)
  when 1
    Window.clear(Color.new(4, 4, 6))
    grid_col = Color.new(15, 15, 20)
  when 2
    Window.clear(Color.new(38, 42, 50))
    grid_col = Color.new(54, 58, 68)
  end

  gx = 0.0
  while gx < CANVAS_W
    Window.draw_line(gx, 0.0, gx, HEIGHT, color: grid_col)
    gx += 40.0
  end
  gy = 0.0
  while gy < HEIGHT
    Window.draw_line(0.0, gy, CANVAS_W, gy, color: grid_col)
    gy += 40.0
  end

  # -------------------------------------------------------------------
  # 2. キャンバス操作 (マウス左ドラッグで移動、右クリック/SpaceでBurst)
  # -------------------------------------------------------------------
  if mx < CANVAS_W && !GUI.mouse_captured?
    if Input.mouse_pressed?(:left)
      system.move_to(mx, my)
    end
    if Input.mouse_push?(:right)
      system.burst(nil, x: mx, y: my)
    end
  end
  system.burst if Input.key_push?(:space)

  # -------------------------------------------------------------------
  # 3. GPU パーティクル更新 & 描画
  # -------------------------------------------------------------------
  system.update(dt)
  system.draw

  selected_layer = [[selected_layer, 0].max, system.emitters.length - 1].min
  active_em = system.emitters[selected_layer]

  draw_emitter_gizmo(active_em) if show_gizmo && active_em

  # -------------------------------------------------------------------
  # 4. キャンバス上部ステータスオーバーレイ
  # -------------------------------------------------------------------
  Window.draw_rect(16.0, 12.0, 780.0, 58.0, radius: 8.0, color: Color.new(12, 16, 26, 210), border_width: 1.0, border_color: Color.new(60, 90, 140, 150), z: 50.0)
  Window.draw_text(28.0, 18.0, "Zenoo GPU Particle Studio (InstanceBuffer Stateless Engine)", size: 19, color: Color::WHITE, z: 51.0)
  info_str = "FPS: #{Window.fps.round(1)}  |  Layers (DrawCalls): #{system.emitters.length}  |  Active Particles: #{system.alive_count} / #{system.max_particles}  |  [Drag] Move  [RightClick / Space] Burst"
  Window.draw_text(28.0, 44.0, info_str, size: 13, color: Color.new(130, 220, 255), z: 51.0)

  # -------------------------------------------------------------------
  # 5. 右側 GUI コントロールパネル
  # -------------------------------------------------------------------
  GUI.window("GPU Particle Inspector", x: 820, y: 10, w: 450, h: 700, resizable: false, collapsible: false) do
    # --- レイヤー管理バー ---
    GUI.row(cols: 4, spacing: 4) do
      system.emitters.each_with_index do |em, idx|
        if GUI.button("L#{idx + 1}:#{em.shape}", h: 28.0, active: (selected_layer == idx), id: "layer_sel_#{idx}")
          selected_layer = idx
        end
      end
    end
    GUI.spacer(2)
    GUI.row(cols: 3, spacing: 6) do
      if GUI.button("+ Add Layer", h: 28.0) && system.emitters.length < 4
        new_em = system.add_emitter(max_particles: 2000)
        new_em.configure(**active_em.to_h) if active_em
        selected_layer = system.emitters.length - 1
      end
      if GUI.button("Duplicate", h: 28.0) && system.emitters.length < 4 && active_em
        new_em = system.add_emitter(max_particles: active_em.max_particles)
        new_em.configure(**active_em.to_h)
        selected_layer = system.emitters.length - 1
      end
      if GUI.button("- Remove", h: 28.0) && system.emitters.length > 1
        system.remove_emitter(selected_layer)
        selected_layer = [selected_layer - 1, 0].max
      end
    end

    selected_layer = [[selected_layer, 0].max, system.emitters.length - 1].min
    em = system.emitters[selected_layer]

    GUI.spacer(4)
    tab_index = GUI.tabs(["Presets", "Spawn", "Physics", "Visuals", "Export"], tab_index, h: 32.0)
    GUI.spacer(4)

    GUI.scroll_view("particle_inspector_scroll", h: 555.0) do
      case tab_index
      when 0 # Presets & Global Controls
        GUI.label("=== Multi-Layer Rich Presets ===", size: 15, color: Color.new(255, 205, 80))
        GUI.spacer(4)

        GUI.row(cols: 2, spacing: 6) do
          if GUI.button("🔥 Campfire (炎+煙+火花)")
            system.apply_preset(:fire)
            selected_layer = 1
          end
          if GUI.button("💥 Explosion (4層大爆発)")
            system.apply_preset(:explosion)
            selected_layer = 1
          end
        end
        GUI.spacer(4)
        GUI.row(cols: 2, spacing: 6) do
          if GUI.button("🌀 Magic Galaxy (銀河渦)")
            system.apply_preset(:magic_galaxy)
            selected_layer = 0
          end
          if GUI.button("⚡ Charge Aura (集束溜め)")
            system.apply_preset(:charge_aura)
            selected_layer = 0
          end
        end
        GUI.spacer(4)
        GUI.row(cols: 2, spacing: 6) do
          if GUI.button("✨ Welding Sparks (火花)")
            system.apply_preset(:sparks)
            selected_layer = 0
          end
          if GUI.button("❄️ Blizzard (吹雪ボックス)")
            system.apply_preset(:blizzard)
            selected_layer = 0
          end
        end
        GUI.spacer(4)
        GUI.row(cols: 2, spacing: 6) do
          if GUI.button("🌟 Star Fountain (星噴水)")
            system.apply_preset(:star_fountain)
            selected_layer = 0
          end
          if GUI.button("💠 Cyber Portal (渦ポータル)")
            system.apply_preset(:cyber_portal)
            selected_layer = 0
          end
        end

        GUI.spacer(8)
        GUI.divider
        GUI.label("=== Playback & Trigger ===", size: 15, color: Color.new(100, 220, 255))
        GUI.row(cols: 2, spacing: 6) do
          system.burst if GUI.button("💥 BURST ALL! (Space)")
          system.clear if GUI.button("Clear All Particles")
        end

        GUI.spacer(4)
        em.emitting    = GUI.checkbox("Layer Emitting (連続放出)", em.emitting, id: "chk_emit")
        em.local_space = GUI.checkbox("Local Space (エミッター移動に全粒子が追従)", em.local_space, id: "chk_local")
        if GUI.checkbox("GPU Infinite Loop Mode (CPU転送完全ゼロ)", em.loop_mode, id: "chk_loop") != em.loop_mode
          em.loop_mode = !em.loop_mode
          em.fill_loop_pool!(em.max_particles) if em.loop_mode
        end
        show_gizmo = GUI.checkbox("Show Emitter Gizmo (放出範囲ガイド表示)", show_gizmo, id: "chk_gizmo")

        GUI.spacer(6)
        GUI.divider
        GUI.label("=== Background Theme ===", size: 15, color: Color.new(255, 205, 80))
        GUI.row(cols: 3, spacing: 4) do
          bg_mode = 0 if GUI.radio("Navy", bg_mode == 0, id: "bg_0")
          bg_mode = 1 if GUI.radio("Black", bg_mode == 1, id: "bg_1")
          bg_mode = 2 if GUI.radio("Slate", bg_mode == 2, id: "bg_2")
        end

      when 1 # Spawn & Timing
        GUI.label("=== Emission Rate & Lifetime ===", size: 15, color: Color.new(255, 205, 80))
        em.emission_rate = GUI.slider("Emit Rate (p/s)", em.emission_rate, 0.0, 2000.0, step: 5.0)
        em.burst_count   = GUI.slider("Burst Count", em.burst_count, 1.0, 1000.0, step: 1.0, format: "%d").to_i
        em.lifetime      = GUI.slider("Lifetime (s)", em.lifetime, 0.1, 6.0, step: 0.05)
        em.lifetime_var  = GUI.slider("Lifetime Var (s)", em.lifetime_var, 0.0, 2.5, step: 0.05)

        GUI.spacer(6)
        GUI.divider
        GUI.label("=== Spawn Shape (放出領域) ===", size: 15, color: Color.new(100, 220, 255))
        SPAWN_LABELS.each_with_index do |lbl, idx|
          sp_sym = SPAWN_SHAPE_LIST[idx]
          if GUI.radio(lbl, em.spawn_shape == sp_sym, id: "sp_shape_#{idx}")
            em.spawn_shape = sp_sym
          end
        end

        case em.spawn_shape
        when :circle, :ring
          em.spawn_radius       = GUI.slider("Outer Radius", em.spawn_radius, 1.0, 350.0, step: 1.0)
          em.spawn_inner_radius = GUI.slider("Inner Radius / Thick", em.spawn_inner_radius, 0.0, 300.0, step: 1.0)
          em.radial_direction   = GUI.checkbox("Radial Direction (中心から放射/集束)", em.radial_direction)
        when :box
          em.spawn_width      = GUI.slider("Box Width", em.spawn_width, 4.0, 800.0, step: 4.0)
          em.spawn_height     = GUI.slider("Box Height", em.spawn_height, 4.0, 600.0, step: 4.0)
          em.radial_direction = GUI.checkbox("Radial Direction (中心から外向き)", em.radial_direction)
        when :line
          em.spawn_width      = GUI.slider("Line Length", em.spawn_width, 10.0, 800.0, step: 5.0)
        end

      when 2 # Motion & Physics (GPU Real-time Uniforms!)
        GUI.label("=== Initial Velocity ===", size: 15, color: Color.new(255, 205, 80))
        em.speed     = GUI.slider("Speed (負で中心へ集束)", em.speed, -500.0, 800.0, step: 5.0)
        em.speed_var = GUI.slider("Speed Variance", em.speed_var, 0.0, 400.0, step: 5.0)
        em.angle     = GUI.slider("Angle (deg)", em.angle, 0.0, 360.0, step: 1.0)
        em.spread    = GUI.slider("Spread (deg)", em.spread, 0.0, 360.0, step: 1.0)

        GUI.spacer(6)
        GUI.divider
        GUI.label("=== GPU Forces (飛翔中の粒子にも即時反映!) ===", size: 15, color: Color.new(100, 220, 255))
        em.gravity_x        = GUI.slider("Gravity X (風)", em.gravity_x, -600.0, 600.0, step: 5.0)
        em.gravity_y        = GUI.slider("Gravity Y (重力/浮力)", em.gravity_y, -800.0, 800.0, step: 5.0)
        em.drag             = GUI.slider("Air Drag (空気抵抗)", em.drag, 0.0, 8.0, step: 0.05)
        em.radial_accel     = GUI.slider("Radial Accel (斥力/引力)", em.radial_accel, -400.0, 400.0, step: 5.0)
        em.tangential_accel = GUI.slider("Vortex Swirl (渦回転)", em.tangential_accel, -400.0, 400.0, step: 5.0)

        GUI.spacer(6)
        GUI.divider
        GUI.label("=== Turbulence & Orientation ===", size: 15, color: Color.new(255, 205, 80))
        em.wobble_amp        = GUI.slider("Wobble Amp (揺らぎ幅)", em.wobble_amp, 0.0, 80.0, step: 1.0)
        em.wobble_freq       = GUI.slider("Wobble Freq (周波数)", em.wobble_freq, 0.5, 15.0, step: 0.2)
        em.spin              = GUI.slider("Spin Speed (deg/s)", em.spin, -720.0, 720.0, step: 10.0)
        em.spin_var          = GUI.slider("Spin Variance", em.spin_var, 0.0, 720.0, step: 10.0)
        em.align_to_velocity = GUI.checkbox("Align to Velocity (進行方向を向く)", em.align_to_velocity)
        em.stretch           = GUI.slider("Velocity Stretch (伸縮)", em.stretch, 1.0, 6.0, step: 0.1)

      when 3 # Visuals, Size Curve & 3-Point Color
        GUI.label("=== Procedural SDF Shape & Blend ===", size: 15, color: Color.new(255, 205, 80))
        GUI.row(cols: 2, spacing: 4) do
          em.shape = :circle  if GUI.radio("Circle (Glow)", em.shape == :circle,  id: "sh_0")
          em.shape = :box     if GUI.radio("Box (Square)",  em.shape == :box,     id: "sh_1")
        end
        GUI.row(cols: 2, spacing: 4) do
          em.shape = :spark   if GUI.radio("Spark (Line)",  em.shape == :spark,   id: "sh_2")
          em.shape = :ring    if GUI.radio("Ring (Wave)",   em.shape == :ring,    id: "sh_3")
        end
        GUI.row(cols: 2, spacing: 4) do
          em.shape = :star    if GUI.radio("Star (Sparkle)", em.shape == :star,    id: "sh_4")
          em.shape = :diamond if GUI.radio("Diamond",        em.shape == :diamond, id: "sh_5")
        end
        em.shape = :soft if GUI.radio("Soft Smoke (Gaussian)", em.shape == :soft, id: "sh_6")

        if em.shape == :ring
          em.ring_thickness = GUI.slider("Ring Thickness", em.ring_thickness, 0.04, 0.6, step: 0.01)
        end

        GUI.spacer(4)
        GUI.row(cols: 3, spacing: 4) do
          em.blend = :add      if GUI.radio("Add",      em.blend == :add,      id: "bl_add")
          em.blend = :alpha    if GUI.radio("Alpha",    em.blend == :alpha,    id: "bl_alp")
          em.blend = :multiply if GUI.radio("Multiply", em.blend == :multiply, id: "bl_mul")
        end

        GUI.spacer(6)
        GUI.divider
        GUI.label("=== Size & Easing Curve ===", size: 15, color: Color.new(100, 220, 255))
        em.start_size = GUI.slider("Start Size", em.start_size, 1.0, 250.0, step: 1.0)
        em.end_size   = GUI.slider("End Size", em.end_size, 0.0, 350.0, step: 1.0)
        em.size_var   = GUI.slider("Size Variance", em.size_var, 0.0, 0.9, step: 0.05)

        GUI.row(cols: 2, spacing: 4) do
          em.size_curve = :linear   if GUI.radio("Linear",        em.size_curve == :linear,   id: "cv_0")
          em.size_curve = :sine     if GUI.radio("Sine (山なり)", em.size_curve == :sine,     id: "cv_1")
        end
        GUI.row(cols: 2, spacing: 4) do
          em.size_curve = :ease_out if GUI.radio("EaseOut",       em.size_curve == :ease_out, id: "cv_2")
          em.size_curve = :ease_in  if GUI.radio("EaseIn",        em.size_curve == :ease_in,  id: "cv_3")
        end

        GUI.spacer(6)
        GUI.divider
        GUI.label("=== 3-Point Color Gradient & Fade ===", size: 15, color: Color.new(255, 205, 80))
        em.fade_in       = GUI.slider("Alpha Fade-In Ratio", em.fade_in, 0.0, 0.5, step: 0.02)
        em.fade_out      = GUI.slider("Alpha Fade-Out Ratio", em.fade_out, 0.0, 0.8, step: 0.02)
        em.color_mid_pos = GUI.slider("Mid Color Timing", em.color_mid_pos, 0.1, 0.9, step: 0.05)
        em.color_var     = GUI.slider("Brightness Variance", em.color_var, 0.0, 0.4, step: 0.02)

        sc = em.to_h[:start_color]
        GUI.label("Start Color (RGBA)", size: 13, color: Color.new(sc[0], sc[1], sc[2], 255))
        sr = GUI.slider("Start R", sc[0], 0, 255, step: 1, format: "%d").to_i
        sg = GUI.slider("Start G", sc[1], 0, 255, step: 1, format: "%d").to_i
        sb = GUI.slider("Start B", sc[2], 0, 255, step: 1, format: "%d").to_i
        sa = GUI.slider("Start A", sc[3], 0, 255, step: 1, format: "%d").to_i
        em.start_color = [sr, sg, sb, sa]

        mc = em.to_h[:mid_color]
        GUI.label("Mid Color (RGBA)", size: 13, color: Color.new(mc[0], mc[1], mc[2], 255))
        mr = GUI.slider("Mid R", mc[0], 0, 255, step: 1, format: "%d").to_i
        mg = GUI.slider("Mid G", mc[1], 0, 255, step: 1, format: "%d").to_i
        mb = GUI.slider("Mid B", mc[2], 0, 255, step: 1, format: "%d").to_i
        ma = GUI.slider("Mid A", mc[3], 0, 255, step: 1, format: "%d").to_i
        em.mid_color = [mr, mg, mb, ma]

        ec = em.to_h[:end_color]
        GUI.label("End Color (RGBA)", size: 13, color: Color.new(ec[0], ec[1], ec[2], 255))
        er = GUI.slider("End R", ec[0], 0, 255, step: 1, format: "%d").to_i
        eg = GUI.slider("End G", ec[1], 0, 255, step: 1, format: "%d").to_i
        eb = GUI.slider("End B", ec[2], 0, 255, step: 1, format: "%d").to_i
        ea = GUI.slider("End A", ec[3], 0, 255, step: 1, format: "%d").to_i
        em.end_color = [er, eg, eb, ea]

      when 4 # Code Export
        GUI.label("=== Ruby Code Export ===", size: 15, color: Color.new(255, 205, 80))
        code_text = generate_ruby_code(system)
        if GUI.button(copy_feedback_timer > 0.0 ? "✅ Copied to Clipboard!" : "📋 Copy Ruby Code to Clipboard")
          Input.clipboard = code_text
          copy_feedback_timer = 2.0
        end
        GUI.spacer(6)
        code_text.each_line do |line|
          col = line.strip.start_with?("#") ? Color.new(120, 210, 255) : Color.new(220, 230, 240)
          GUI.label(line.chomp, size: 12, color: col)
        end
      end
    end
  end

  frame_count += 1
  break if test_max > 0 && frame_count >= test_max
end

puts "GPU Particle Editor test completed (#{frame_count} frames)."

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

WIDTH    = 1280
HEIGHT   = 720
CANVAS_W = 810.0

system = ParticleSystem.preset(:fire, CANVAS_W * 0.5, HEIGHT * 0.55)
selected_layer = 0
bg_mode = 0 # 0: Dark Navy, 1: Pitch Black, 2: Slate Grid
show_gizmo = true

SPAWN_SHAPE_LIST = [:point, :circle, :ring, :box, :line].freeze
SPAWN_LABELS     = ["Point (点)", "Circle (円内)", "Ring (円周)", "Box (矩形)", "Line (線分)"].freeze

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

# -------------------------------------------------------------------
# 右側 UI コントロールパネル (保持モード UI)
# -------------------------------------------------------------------
stage = UI::Stage.new(width: WIDTH, height: HEIGHT, theme: UI::Theme.new(:compact, padding: 8, gap: 4))

current_em = -> {
  selected_layer = selected_layer.clamp(0, [system.emitters.length - 1, 0].max)
  system.emitters[selected_layer]
}

layer_btns       = []
pages            = []
spawn_radios     = []
shape_btns       = {}
blend_btns       = {}
curve_btns       = {}
grp_circle       = nil
grp_box          = nil
grp_line         = nil
sl_ring_thick    = nil
export_lines_box = nil
btn_copy_code    = nil
copy_feedback_frames = 0

# UI 同期用コントロール参照
ctrls = {}

rebuild_export = lambda do
  return unless export_lines_box
  export_lines_box.children.dup.each { |c| c.parent = nil }
  generate_ruby_code(system).each_line do |line|
    s = line.chomp
    col = s.strip.start_with?("#") ? [120, 210, 255] : [220, 230, 240]
    export_lines_box.label(s, size: 12, color: col)
  end
end

sync_ui = lambda do
  em = current_em.call
  4.times do |idx|
    btn = layer_btns[idx]
    if idx < system.emitters.length
      btn.visible = true
      btn.label   = "L#{idx + 1}:#{system.emitters[idx].shape}"
      btn.active  = (idx == selected_layer)
    else
      btn.visible = false
    end
  end
  return unless em

  ctrls[:emitting].checked    = em.emitting
  ctrls[:local_space].checked = em.local_space
  ctrls[:loop_mode].checked   = em.loop_mode
  ctrls[:show_gizmo].checked  = show_gizmo

  ctrls[:emission_rate].value = em.emission_rate
  ctrls[:burst_count].value   = em.burst_count
  ctrls[:lifetime].value      = em.lifetime
  ctrls[:lifetime_var].value  = em.lifetime_var

  SPAWN_SHAPE_LIST.each_with_index { |sp, i| spawn_radios[i].checked = (em.spawn_shape == sp) }
  grp_circle.visible = (em.spawn_shape == :circle || em.spawn_shape == :ring)
  grp_box.visible    = (em.spawn_shape == :box)
  grp_line.visible   = (em.spawn_shape == :line)

  ctrls[:spawn_radius].value       = em.spawn_radius
  ctrls[:spawn_inner_radius].value = em.spawn_inner_radius
  ctrls[:radial_circle].checked    = em.radial_direction
  ctrls[:spawn_width].value        = em.spawn_width
  ctrls[:spawn_height].value       = em.spawn_height
  ctrls[:radial_box].checked       = em.radial_direction
  ctrls[:line_length].value        = em.spawn_width

  ctrls[:speed].value        = em.speed
  ctrls[:speed_var].value    = em.speed_var
  ctrls[:angle].value        = em.angle
  ctrls[:spread].value       = em.spread
  ctrls[:gravity_x].value    = em.gravity_x
  ctrls[:gravity_y].value    = em.gravity_y
  ctrls[:drag].value         = em.drag
  ctrls[:radial_accel].value = em.radial_accel
  ctrls[:tangential].value   = em.tangential_accel
  ctrls[:wobble_amp].value   = em.wobble_amp
  ctrls[:wobble_freq].value  = em.wobble_freq
  ctrls[:spin].value         = em.spin
  ctrls[:spin_var].value     = em.spin_var
  ctrls[:align_vel].checked  = em.align_to_velocity
  ctrls[:stretch].value      = em.stretch

  shape_btns.each { |sym, b| b.active = (em.shape == sym) }
  blend_btns.each { |sym, b| b.active = (em.blend == sym) }
  curve_btns.each { |sym, b| b.active = (em.size_curve == sym) }
  sl_ring_thick.visible = (em.shape == :ring)
  sl_ring_thick.value   = em.ring_thickness

  ctrls[:start_size].value    = em.start_size
  ctrls[:end_size].value      = em.end_size
  ctrls[:size_var].value      = em.size_var
  ctrls[:fade_in].value       = em.fade_in
  ctrls[:fade_out].value      = em.fade_out
  ctrls[:color_mid_pos].value = em.color_mid_pos
  ctrls[:color_var].value     = em.color_var

  h = em.to_h
  [:start_color, :mid_color, :end_color].each do |ck|
    rgba = h[ck]
    ctrls[:"#{ck}_lbl"].color = [rgba[0], rgba[1], rgba[2], 255]
    4.times { |ci| ctrls[:"#{ck}_#{ci}"].value = rgba[ci] }
  end

  rebuild_export.call if pages[4]&.visible
end

stage.panel(820, 10, width: 450, height: 700, title: "GPU Particle Inspector") do |win|
  win.hbox(padding: 0, gap: 4, height: 26) do |row|
    4.times do |idx|
      layer_btns << row.button("L#{idx + 1}", flex: 1) do
        selected_layer = idx
        sync_ui.call
      end
    end
  end

  win.hbox(padding: 0, gap: 6, height: 26) do |row|
    row.button("+ Add Layer", flex: 1) do
      if system.emitters.length < 4
        act = current_em.call
        new_em = system.add_emitter(max_particles: 2000)
        new_em.configure(**act.to_h) if act
        selected_layer = system.emitters.length - 1
        sync_ui.call
      end
    end
    row.button("Duplicate", flex: 1) do
      if system.emitters.length < 4 && (act = current_em.call)
        new_em = system.add_emitter(max_particles: act.max_particles)
        new_em.configure(**act.to_h)
        selected_layer = system.emitters.length - 1
        sync_ui.call
      end
    end
    row.button("- Remove", flex: 1) do
      if system.emitters.length > 1
        system.remove_emitter(selected_layer)
        selected_layer = [selected_layer - 1, 0].max
        sync_ui.call
      end
    end
  end

  scroller = nil
  win.tabs(["Presets", "Spawn", "Physics", "Visuals", "Export"], 0, height: 28) do |idx, _|
    pages.each_with_index { |pg, pi| pg.visible = (pi == idx) }
    scroller.scroll_y = 0.0 if scroller
    rebuild_export.call if idx == 4
  end

  scroller = win.scroll_view(flex: 1, padding: 6, gap: 5) do |sv|
    # Tab 0: Presets & Global Controls
    pages << sv.vbox(padding: 0, gap: 5) do |p0|
      p0.label("=== Multi-Layer Rich Presets ===", size: 15, color: [255, 205, 80])
      preset_rows = [
        [["Campfire (炎+煙+火花)", :fire, 1],        ["Explosion (4層大爆発)", :explosion, 1]],
        [["Magic Galaxy (銀河渦)", :magic_galaxy, 0], ["Charge Aura (集束溜め)", :charge_aura, 0]],
        [["Welding Sparks (火花)", :sparks, 0],       ["Blizzard (吹雪ボックス)", :blizzard, 0]],
        [["Star Fountain (星噴水)", :star_fountain, 0], ["Cyber Portal (渦ポータル)", :cyber_portal, 0]]
      ]
      preset_rows.each do |pair|
        p0.hbox(padding: 0, gap: 6, height: 26) do |row|
          pair.each do |lbl, psym, sel|
            row.button(lbl, flex: 1) do
              system.apply_preset(psym)
              selected_layer = sel
              sync_ui.call
            end
          end
        end
      end

      p0.divider
      p0.label("=== Playback & Trigger ===", size: 15, color: [100, 220, 255])
      p0.hbox(padding: 0, gap: 6, height: 28) do |row|
        row.button("BURST ALL! (Space)", flex: 1) { system.burst }
        row.button("Clear All Particles", flex: 1) { system.clear }
      end

      ctrls[:emitting]    = p0.checkbox("Layer Emitting (連続放出)", true) { |v| current_em.call.emitting = v }
      ctrls[:local_space] = p0.checkbox("Local Space (エミッター移動に追従)", false) { |v| current_em.call.local_space = v }
      ctrls[:loop_mode]   = p0.checkbox("GPU Infinite Loop Mode (CPU転送ゼロ)", false) do |v|
        em = current_em.call
        em.loop_mode = v
        em.fill_loop_pool!(em.max_particles) if v
      end
      ctrls[:show_gizmo] = p0.checkbox("Show Emitter Gizmo (放出範囲表示)", show_gizmo) { |v| show_gizmo = v }

      p0.divider
      p0.label("=== Background Theme ===", size: 15, color: [255, 205, 80])
      p0.hbox(padding: 0, gap: 8, height: 24, align: :center) do |row|
        row.radio_button("Navy",  true,  group: :bg) { bg_mode = 0 }
        row.radio_button("Black", false, group: :bg) { bg_mode = 1 }
        row.radio_button("Slate", false, group: :bg) { bg_mode = 2 }
      end
    end

    # Tab 1: Spawn & Timing
    pages << sv.vbox(padding: 0, gap: 5, visible: false) do |p1|
      p1.label("=== Emission Rate & Lifetime ===", size: 15, color: [255, 205, 80])
      ctrls[:emission_rate] = p1.slider("Emit Rate (p/s)", 0.0, 0.0, 2000.0, format: "%.0f", label_width: 130) { |v| current_em.call.emission_rate = v }
      ctrls[:burst_count]   = p1.slider("Burst Count", 1.0, 1.0, 1000.0, format: "%.0f", label_width: 130) { |v| current_em.call.burst_count = v.round.to_i }
      ctrls[:lifetime]      = p1.slider("Lifetime (s)", 1.0, 0.1, 6.0, format: "%.2f", label_width: 130) { |v| current_em.call.lifetime = v }
      ctrls[:lifetime_var]  = p1.slider("Lifetime Var (s)", 0.0, 0.0, 2.5, format: "%.2f", label_width: 130) { |v| current_em.call.lifetime_var = v }

      p1.divider
      p1.label("=== Spawn Shape (放出領域) ===", size: 15, color: [100, 220, 255])
      p1.vbox(padding: 0, gap: 2) do |rb_box|
        SPAWN_LABELS.each_with_index do |lbl, idx|
          sp_sym = SPAWN_SHAPE_LIST[idx]
          spawn_radios << rb_box.radio_button(lbl, false, group: :spawn_shape) do
            current_em.call.spawn_shape = sp_sym
            sync_ui.call
          end
        end
      end

      grp_circle = p1.vbox(padding: 0, gap: 4, visible: false) do |g|
        ctrls[:spawn_radius]       = g.slider("Outer Radius", 1.0, 1.0, 350.0, format: "%.0f", label_width: 130) { |v| current_em.call.spawn_radius = v }
        ctrls[:spawn_inner_radius] = g.slider("Inner Radius", 0.0, 0.0, 300.0, format: "%.0f", label_width: 130) { |v| current_em.call.spawn_inner_radius = v }
        ctrls[:radial_circle]      = g.checkbox("Radial Direction (中心から放射/集束)", false) { |v| current_em.call.radial_direction = v }
      end
      grp_box = p1.vbox(padding: 0, gap: 4, visible: false) do |g|
        ctrls[:spawn_width]  = g.slider("Box Width", 10.0, 4.0, 800.0, format: "%.0f", label_width: 130) { |v| current_em.call.spawn_width = v }
        ctrls[:spawn_height] = g.slider("Box Height", 10.0, 4.0, 600.0, format: "%.0f", label_width: 130) { |v| current_em.call.spawn_height = v }
        ctrls[:radial_box]   = g.checkbox("Radial Direction (中心から外向き)", false) { |v| current_em.call.radial_direction = v }
      end
      grp_line = p1.vbox(padding: 0, gap: 4, visible: false) do |g|
        ctrls[:line_length] = g.slider("Line Length", 10.0, 10.0, 800.0, format: "%.0f", label_width: 130) { |v| current_em.call.spawn_width = v }
      end
    end

    # Tab 2: Motion & Physics
    pages << sv.vbox(padding: 0, gap: 5, visible: false) do |p2|
      p2.label("=== Initial Velocity ===", size: 15, color: [255, 205, 80])
      ctrls[:speed]     = p2.slider("Speed (負で集束)", 0.0, -500.0, 800.0, format: "%.0f", label_width: 130) { |v| current_em.call.speed = v }
      ctrls[:speed_var] = p2.slider("Speed Variance", 0.0, 0.0, 400.0, format: "%.0f", label_width: 130) { |v| current_em.call.speed_var = v }
      ctrls[:angle]     = p2.slider("Angle (deg)", 0.0, 0.0, 360.0, format: "%.0f", label_width: 130) { |v| current_em.call.angle = v }
      ctrls[:spread]    = p2.slider("Spread (deg)", 0.0, 0.0, 360.0, format: "%.0f", label_width: 130) { |v| current_em.call.spread = v }

      p2.divider
      p2.label("=== GPU Forces (飛翔中の粒子に即反映) ===", size: 15, color: [100, 220, 255])
      ctrls[:gravity_x]    = p2.slider("Gravity X (風)", 0.0, -600.0, 600.0, format: "%.0f", label_width: 130) { |v| current_em.call.gravity_x = v }
      ctrls[:gravity_y]    = p2.slider("Gravity Y (重力)", 0.0, -800.0, 800.0, format: "%.0f", label_width: 130) { |v| current_em.call.gravity_y = v }
      ctrls[:drag]         = p2.slider("Air Drag", 0.0, 0.0, 8.0, format: "%.2f", label_width: 130) { |v| current_em.call.drag = v }
      ctrls[:radial_accel] = p2.slider("Radial Accel", 0.0, -400.0, 400.0, format: "%.0f", label_width: 130) { |v| current_em.call.radial_accel = v }
      ctrls[:tangential]   = p2.slider("Vortex Swirl", 0.0, -400.0, 400.0, format: "%.0f", label_width: 130) { |v| current_em.call.tangential_accel = v }

      p2.divider
      p2.label("=== Turbulence & Orientation ===", size: 15, color: [255, 205, 80])
      ctrls[:wobble_amp]  = p2.slider("Wobble Amp", 0.0, 0.0, 80.0, format: "%.0f", label_width: 130) { |v| current_em.call.wobble_amp = v }
      ctrls[:wobble_freq] = p2.slider("Wobble Freq", 1.0, 0.5, 15.0, format: "%.1f", label_width: 130) { |v| current_em.call.wobble_freq = v }
      ctrls[:spin]        = p2.slider("Spin Speed", 0.0, -720.0, 720.0, format: "%.0f", label_width: 130) { |v| current_em.call.spin = v }
      ctrls[:spin_var]    = p2.slider("Spin Variance", 0.0, 0.0, 720.0, format: "%.0f", label_width: 130) { |v| current_em.call.spin_var = v }
      ctrls[:align_vel]   = p2.checkbox("Align to Velocity (進行方向を向く)", false) { |v| current_em.call.align_to_velocity = v }
      ctrls[:stretch]     = p2.slider("Velocity Stretch", 1.0, 1.0, 6.0, format: "%.1f", label_width: 130) { |v| current_em.call.stretch = v }
    end

    # Tab 3: Visuals, Size Curve & 3-Point Color
    pages << sv.vbox(padding: 0, gap: 5, visible: false) do |p3|
      p3.label("=== Procedural SDF Shape & Blend ===", size: 15, color: [255, 205, 80])
      [[:circle, "Circle"], [:box, "Box"], [:spark, "Spark"], [:ring, "Ring"]].tap do |row_items|
        p3.hbox(padding: 0, gap: 4, height: 24) do |row|
          row_items.each do |sym, lbl|
            shape_btns[sym] = row.button(lbl, flex: 1) { current_em.call.shape = sym; sync_ui.call }
          end
        end
      end
      [[:star, "Star"], [:diamond, "Diamond"], [:soft, "Soft Smoke"]].tap do |row_items|
        p3.hbox(padding: 0, gap: 4, height: 24) do |row|
          row_items.each do |sym, lbl|
            shape_btns[sym] = row.button(lbl, flex: 1) { current_em.call.shape = sym; sync_ui.call }
          end
        end
      end

      sl_ring_thick = p3.slider("Ring Thickness", 0.2, 0.04, 0.6, format: "%.2f", label_width: 130, visible: false) { |v| current_em.call.ring_thickness = v }

      p3.hbox(padding: 0, gap: 4, height: 24) do |row|
        [[:add, "Add"], [:alpha, "Alpha"], [:multiply, "Multiply"]].each do |sym, lbl|
          blend_btns[sym] = row.button(lbl, flex: 1) { current_em.call.blend = sym; sync_ui.call }
        end
      end

      p3.divider
      p3.label("=== Size & Easing Curve ===", size: 15, color: [100, 220, 255])
      ctrls[:start_size] = p3.slider("Start Size", 10.0, 1.0, 250.0, format: "%.0f", label_width: 130) { |v| current_em.call.start_size = v }
      ctrls[:end_size]   = p3.slider("End Size", 0.0, 0.0, 350.0, format: "%.0f", label_width: 130) { |v| current_em.call.end_size = v }
      ctrls[:size_var]   = p3.slider("Size Variance", 0.0, 0.0, 0.9, format: "%.2f", label_width: 130) { |v| current_em.call.size_var = v }

      p3.hbox(padding: 0, gap: 4, height: 24) do |row|
        [[:linear, "Linear"], [:sine, "Sine"], [:ease_out, "EaseOut"], [:ease_in, "EaseIn"]].each do |sym, lbl|
          curve_btns[sym] = row.button(lbl, flex: 1) { current_em.call.size_curve = sym; sync_ui.call }
        end
      end

      p3.divider
      p3.label("=== 3-Point Color Gradient & Fade ===", size: 15, color: [255, 205, 80])
      ctrls[:fade_in]       = p3.slider("Alpha Fade-In", 0.1, 0.0, 0.5, format: "%.2f", label_width: 130) { |v| current_em.call.fade_in = v }
      ctrls[:fade_out]      = p3.slider("Alpha Fade-Out", 0.3, 0.0, 0.8, format: "%.2f", label_width: 130) { |v| current_em.call.fade_out = v }
      ctrls[:color_mid_pos] = p3.slider("Mid Color Timing", 0.5, 0.1, 0.9, format: "%.2f", label_width: 130) { |v| current_em.call.color_mid_pos = v }
      ctrls[:color_var]     = p3.slider("Brightness Var", 0.0, 0.0, 0.4, format: "%.2f", label_width: 130) { |v| current_em.call.color_var = v }

      [[:start_color, "Start Color (RGBA)"], [:mid_color, "Mid Color (RGBA)"], [:end_color, "End Color (RGBA)"]].each do |ck, title|
        ctrls[:"#{ck}_lbl"] = p3.label(title, size: 13, color: [255, 255, 255])
        ch_names = ["R", "G", "B", "A"]
        4.times do |ci|
          ctrls[:"#{ck}_#{ci}"] = p3.slider("#{title.split.first} #{ch_names[ci]}", 255.0, 0.0, 255.0, format: "%.0f", label_width: 100) do |v|
            em = current_em.call
            arr = em.to_h[ck].dup
            arr[ci] = v.round.to_i
            em.public_send(:"#{ck}=", arr)
            ctrls[:"#{ck}_lbl"].color = [arr[0], arr[1], arr[2], 255]
          end
        end
      end
    end

    # Tab 4: Code Export
    pages << sv.vbox(padding: 0, gap: 6, visible: false) do |p4|
      p4.label("=== Ruby Code Export ===", size: 15, color: [255, 205, 80])
      btn_copy_code = p4.button("Copy Ruby Code to Clipboard", height: 28) do
        Input.clipboard = generate_ruby_code(system)
        copy_feedback_frames = 120
        btn_copy_code.label = "Copied to Clipboard!"
      end
      export_lines_box = p4.vbox(padding: 0, gap: 2)
    end
  end
end

sync_ui.call

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(WIDTH, HEIGHT, "Zenoo - 2D GPU Particle Designer & Editor") do
  dt = Window.delta_time
  if copy_feedback_frames > 0
    copy_feedback_frames -= 1
    btn_copy_code.label = "Copy Ruby Code to Clipboard" if copy_feedback_frames == 0
  end

  mx = Input.mouse_x.to_f
  my = Input.mouse_y.to_f

  # 1. 背景とグリッドの描画
  case bg_mode
  when 0
    Window.clear([14, 16, 24])
    grid_col = [26, 30, 42]
  when 1
    Window.clear([4, 4, 6])
    grid_col = [15, 15, 20]
  when 2
    Window.clear([38, 42, 50])
    grid_col = [54, 58, 68]
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

  # 2. キャンバス操作 (マウス左ドラッグで移動、右クリック/SpaceでBurst)
  if mx < CANVAS_W && !UI.mouse_captured?
    system.move_to(mx, my) if Input.mouse_pressed?(:left)
    system.burst(nil, x: mx, y: my) if Input.mouse_push?(:right)
  end
  system.burst if Input.key_push?(:space)

  # 3. GPU パーティクル更新 & 描画
  system.update(dt)
  system.draw

  active_em = current_em.call
  draw_emitter_gizmo(active_em) if show_gizmo && active_em

  # 4. キャンバス上部ステータスオーバーレイ
  Window.draw_rect(16.0, 12.0, 780.0, 58.0, radius: 8.0, color: [12, 16, 26, 210], border_width: 1.0, border_color: [60, 90, 140, 150], z: 50.0)
  Window.draw_text(28.0, 18.0, "Zenoo GPU Particle Studio (InstanceBuffer Stateless Engine)", size: 19, color: :white, z: 51.0)
  info_str = "FPS: #{Window.fps.round(1)}  |  Layers (DrawCalls): #{system.emitters.length}  |  Active Particles: #{system.alive_count} / #{system.max_particles}  |  [Drag] Move  [RightClick / Space] Burst"
  Window.draw_text(28.0, 44.0, info_str, size: 13, color: [130, 220, 255], z: 51.0)

  # 5. 右側 UI パネル
  stage.update
  stage.draw

  frame_count += 1
  break if test_max > 0 && frame_count >= test_max
end

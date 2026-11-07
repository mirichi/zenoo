# frozen_string_literal: true

module Zenoo
  # ====================================================================
  # GPU ステートレス・パーティクルエミッター (Zenoo::ParticleEmitter)
  # ====================================================================
  # - InstanceBuffer (VRAM常駐リングバッファ) と専用GLSLシェーダーを用い、
  #   数千〜数万個のパーティクルを毎フレームの CPU ループ・配列 pack なしで描画します。
  # - 発生(Spawn / Burst)した瞬間にのみ初期値 12 floats (48 bytes) を VRAM へ転送し、
  #   その後の位置・物理(重力/空気抵抗/引力/渦/乱流)・サイズ・3色補間・ビルボード回転は
  #   すべて頂点シェーダーの解析解 f(t) で一括計算します。
  # - 重力や色などのパラメータは Uniform 変数としてシェーダーに渡されるため、
  #   エディタ等で値を変更すると、すでに飛んでいるパーティクルにもリアルタイムに反映されます。
  # ====================================================================
  class ParticleEmitter
    DEG_TO_RAD = Math::PI / 180.0
    FLOATS_PER_PARTICLE = 16
    BYTES_PER_PARTICLE  = FLOATS_PER_PARTICLE * 4

    SHAPES = {
      circle:  0,
      box:     1,
      spark:   2,
      ring:    3,
      star:    4,
      diamond: 5,
      soft:    6
    }.freeze

    SPAWN_SHAPES = {
      point:  0,
      circle: 1,
      ring:   2,
      box:    3,
      line:   4
    }.freeze

    SIZE_CURVES = {
      linear:   0,
      sine:     1,
      ease_out: 2,
      ease_in:  3
    }.freeze

    PARTICLE_VERTEX_SHADER = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec4 in_origin_vel; // x0, y0, vx0, vy0
      layout (location = 1) in vec4 in_timing;     // t0, life, size_mul, spin
      layout (location = 2) in vec4 in_seeds;      // angle0, wobble_phase, color_var, rand_seed
      layout (location = 3) in vec4 in_tint;       // r, g, b, a (0.0=use uniform gradient, >0.0=use per-particle tint)

      uniform vec2  u_resolution;
      uniform float u_flip_y;
      uniform vec4  u_view;        // zoom, ox, oy, local_space (1.0=local, 0.0=world)
      uniform vec4  u_sim;         // time, loop_mode, shape_type, blend_is_add
      uniform vec4  u_emitter;     // emitter_x, emitter_y, align_to_vel, stretch
      uniform vec4  u_forces;      // gravity_x, gravity_y, drag, radial_accel
      uniform vec4  u_turb;        // tangential_accel, wobble_amp, wobble_freq, ring_thickness
      uniform vec4  u_size_fade;   // start_size, end_size, size_curve, fade_in
      uniform vec4  u_fade_uv;     // fade_out, color_mid_pos, has_tex, anim_frames
      uniform vec4  u_uv_rect;     // u0, v0, uw, vh
      uniform vec4  u_start_color; // r, g, b, a
      uniform vec4  u_mid_color;   // r, g, b, a
      uniform vec4  u_end_color;   // r, g, b, a

      out vec4 v_color;
      out vec2 v_uv;
      out vec2 v_local_uv;
      flat out float v_shape;

      vec2 eval_position(float t, vec2 p0, vec2 v0, vec2 g, float drag, float rad_acc, float tan_acc, float wob_amp, float wob_freq, float wob_phase) {
          // 1. 初速と空気抵抗 (指数減衰の解析積分) + 重力
          vec2 pos;
          if (drag > 0.001) {
              float inv_d = 1.0 / drag;
              float decay = (1.0 - exp(-drag * t)) * inv_d;
              vec2 v_term = v0 * decay;
              vec2 g_term = g * (t * inv_d - decay * inv_d);
              pos = p0 + v_term + g_term;
          } else {
              pos = p0 + v0 * t + 0.5 * g * t * t;
          }

          // 2. 放射加速度 (中心からの拡散 / 中心への集束・引力) & 接線加速度 (渦巻き・Vortex)
          vec2 rel = pos - p0;
          float r_len = length(rel);
          vec2 rad_dir = (r_len > 0.001) ? (rel / r_len) : vec2(cos(wob_phase), sin(wob_phase));
          vec2 tan_dir = vec2(-rad_dir.y, rad_dir.x);

          if (abs(rad_acc) > 0.001) {
              pos += rad_dir * (0.5 * rad_acc * t * t);
          }
          if (abs(tan_acc) > 0.001) {
              float swirl_angle = 0.5 * tan_acc * t * t * 0.015;
              float cs = cos(swirl_angle);
              float sn = sin(swirl_angle);
              vec2 d = pos - p0;
              pos = p0 + vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs) + tan_dir * (0.2 * tan_acc * t * t);
          }

          // 3. 乱流・揺らぎ (Wobble / Turbulence)
          if (wob_amp > 0.001) {
              float phase = wob_phase + t * wob_freq * 6.2831853;
              pos += tan_dir * (sin(phase) * wob_amp) + rad_dir * (cos(phase * 0.73) * wob_amp * 0.35);
          }
          return pos;
      }

      void main() {
          float life = in_timing.y;
          if (life <= 0.0) {
              gl_Position = vec4(0.0, 0.0, -2.0, 1.0);
              return;
          }

          float cur_time = u_sim.x;
          float t0 = in_timing.x;
          float age = cur_time - t0;

          if (u_sim.y > 0.5) {
              age = mod(max(age, 0.0), life);
          } else if (age < 0.0 || age > life) {
              gl_Position = vec4(0.0, 0.0, -2.0, 1.0);
              return;
          }

          float progress = clamp(age / life, 0.0, 1.0);

          // 基準原点 (local_space なら現在の u_emitter.xy を加算)
          vec2 p0 = in_origin_vel.xy;
          if (u_view.w > 0.5) {
              p0 += u_emitter.xy;
          }
          vec2 v0 = in_origin_vel.zw;
          vec2 g  = u_forces.xy;
          float drag    = u_forces.z;
          float rad_acc = u_forces.w;
          float tan_acc = u_turb.x;
          float wob_amp = u_turb.y;
          float wob_freq = u_turb.z;
          float wob_phase = in_seeds.y;

          vec2 cur_pos = eval_position(age, p0, v0, g, drag, rad_acc, tan_acc, wob_amp, wob_freq, wob_phase);

          // サイズ補間カーブ
          float s_curve = u_size_fade.z;
          float size_t = progress;
          if (s_curve > 0.5 && s_curve < 1.5) {
              // 1: Sine (山なり: 0 -> 1 -> 0)
              size_t = sin(progress * 3.14159265);
          } else if (s_curve >= 1.5 && s_curve < 2.5) {
              // 2: EaseOut (急変化 -> 緩やか)
              float inv = 1.0 - progress;
              size_t = 1.0 - inv * inv * inv;
          } else if (s_curve >= 2.5) {
              // 3: EaseIn (緩やか -> 急変化)
              size_t = progress * progress * progress;
          }

          float base_size = (s_curve > 0.5 && s_curve < 1.5)
              ? mix(u_size_fade.y, u_size_fade.x, size_t)
              : mix(u_size_fade.x, u_size_fade.y, size_t);
          float cur_size = max(base_size * in_timing.z, 0.0);
          if (cur_size <= 0.05) {
              gl_Position = vec4(0.0, 0.0, -2.0, 1.0);
              return;
          }

          // カラー補間 (in_tint.a > 0.001 なら個別ティントカラーを優先、それ以外は3点グラデーション)
          float mid_pos = clamp(u_fade_uv.y, 0.01, 0.99);
          vec4 grad_col;
          if (progress < mid_pos) {
              grad_col = mix(u_start_color, u_mid_color, progress / mid_pos);
          } else {
              grad_col = mix(u_mid_color, u_end_color, (progress - mid_pos) / (1.0 - mid_pos));
          }

          vec4 col;
          if (in_tint.a > 0.001) {
              vec3 end_rgb = in_tint.rgb * 0.35;
              col = vec4(mix(in_tint.rgb, end_rgb, progress * 0.7), in_tint.a * grad_col.a);
          } else {
              col = grad_col;
          }

          // 個別明度・色相ばらつき (color_var)
          col.rgb = clamp(col.rgb + vec3(in_seeds.z), 0.0, 1.0);

          // フェードイン & フェードアウト
          float fade_in  = u_size_fade.w;
          float fade_out = u_fade_uv.x;
          float alpha_mul = 1.0;
          if (fade_in > 0.001 && progress < fade_in) {
              alpha_mul *= (progress / fade_in);
          }
          if (fade_out > 0.001 && progress > (1.0 - fade_out)) {
              alpha_mul *= ((1.0 - progress) / fade_out);
          }
          col.a *= clamp(alpha_mul, 0.0, 1.0);
          if (col.a <= 0.002) {
              gl_Position = vec4(0.0, 0.0, -2.0, 1.0);
              return;
          }

          // 回転角 & 進行方向整列 (Align to Velocity)
          float rot_rad;
          float stretch_x = 1.0;
          float shape = u_sim.z;
          bool align_vel = (u_emitter.z > 0.5) || (shape > 1.5 && shape < 2.5);
          if (align_vel) {
              float dt_eps = 0.016;
              vec2 next_pos = eval_position(age + dt_eps, p0, v0, g, drag, rad_acc, tan_acc, wob_amp, wob_freq, wob_phase);
              vec2 vel_vec = (next_pos - cur_pos) / dt_eps;
              float spd = length(vel_vec);
              rot_rad = (spd > 0.1) ? atan(vel_vec.y, vel_vec.x) : (in_seeds.x * 0.0174532925);
              stretch_x = max(u_emitter.w, 1.0) + spd * 0.004 * max(u_emitter.w - 1.0, 0.5);
          } else {
              rot_rad = (in_seeds.x + in_timing.w * age) * 0.0174532925;
              stretch_x = max(u_emitter.w, 1.0);
          }

          // gl_VertexID (0..3) によるクアッド展開
          vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          vec2 local = (corner - vec2(0.5)) * cur_size;
          local.x *= stretch_x;

          float cs = cos(rot_rad);
          float sn = sin(rot_rad);
          vec2 rotated_offset = vec2(local.x * cs - local.y * sn, local.x * sn + local.y * cs);

          vec2 world_pos = cur_pos + rotated_offset;

          // カメラ変換 (screen = world * zoom + offset)
          float zoom = (u_view.x == 0.0) ? 1.0 : u_view.x;
          vec2 screen_pos = world_pos * zoom + u_view.yz;

          vec2 ndc = (screen_pos / u_resolution) * 2.0 - 1.0;
          ndc.y = ndc.y * ((u_flip_y == 0.0) ? -1.0 : u_flip_y);
          gl_Position = vec4(ndc, 0.0, 1.0);

          v_color = col;
          v_local_uv = corner;
          v_shape = shape;

          // テクスチャ UV (アニメーションフレーム対応)
          float frames = max(u_fade_uv.w, 1.0);
          float frame_idx = floor(progress * frames * 0.9999);
          float frame_uw = u_uv_rect.z / frames;
          v_uv = vec2(u_uv_rect.x + frame_idx * frame_uw + corner.x * frame_uw,
                      u_uv_rect.y + corner.y * u_uv_rect.w);
      }
    GLSL

    PARTICLE_FRAGMENT_SHADER = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec2 v_uv;
      in vec2 v_local_uv;
      flat in float v_shape;

      uniform sampler2D u_texture;
      uniform vec4 u_fade_uv; // z: has_tex
      uniform vec4 u_turb;    // w: ring_thickness

      out vec4 fragColor;

      void main() {
          if (u_fade_uv.z > 0.5) {
              fragColor = v_color * texture(u_texture, v_uv);
              return;
          }

          vec2 p = (v_local_uv - vec2(0.5)) * 2.0;
          int st = int(v_shape + 0.5);
          float alpha = 1.0;
          float core_glow = 0.0;

          if (st == 0) {
              // 0: Circle (Glow Orb)
              float d2 = dot(p, p);
              if (d2 >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              float d = sqrt(d2);
              alpha = smoothstep(1.0, 0.15, d);
              core_glow = exp(-d2 * 6.0) * 0.65;
          } else if (st == 1) {
              // 1: Box (Sharp/Rounded Square)
              vec2 b = abs(p);
              float d = max(b.x, b.y);
              if (d >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              alpha = smoothstep(1.0, 0.82, d);
              core_glow = (1.0 - d) * 0.25;
          } else if (st == 2) {
              // 2: Spark (Needle / Capsule)
              float d2 = p.x * p.x + (p.y * p.y) * 5.0;
              if (d2 >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              alpha = clamp((1.0 - d2) * 1.8, 0.0, 1.0);
              core_glow = exp(-d2 * 8.0) * 0.9;
          } else if (st == 3) {
              // 3: Ring (Shockwave / Magic Circle)
              float d = length(p);
              if (d >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              float thick = clamp(u_turb.w, 0.04, 0.8);
              float ring_center = 1.0 - thick * 0.6;
              float dist_ring = abs(d - ring_center);
              alpha = smoothstep(thick, thick * 0.15, dist_ring);
              core_glow = alpha * 0.45;
          } else if (st == 4) {
              // 4: Star (4-Point Kirakira Sparkle)
              vec2 ap = abs(p);
              float star_d = pow(ap.x, 0.55) + pow(ap.y, 0.55);
              float d2 = dot(p, p);
              if (star_d >= 1.25 && d2 >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              float star_a = smoothstep(1.15, 0.1, star_d);
              float center_a = exp(-d2 * 10.0);
              alpha = clamp(max(star_a, center_a), 0.0, 1.0);
              core_glow = center_a * 0.95;
          } else if (st == 5) {
              // 5: Diamond (Rhombus Crystal)
              float d = abs(p.x) + abs(p.y);
              if (d >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              alpha = smoothstep(1.0, 0.78, d);
              core_glow = clamp(1.0 - d * 1.5, 0.0, 1.0) * 0.5;
          } else {
              // 6: Soft Smoke / Mist (Gaussian Puff)
              float d2 = dot(p, p);
              if (d2 >= 1.0) {
                  fragColor = vec4(0.0);
                  return;
              }
              alpha = (1.0 - d2) * (1.0 - d2);
              core_glow = 0.0;
          }

          vec3 final_rgb = mix(v_color.rgb, vec3(1.0), core_glow);
          fragColor = vec4(final_rgb, v_color.a * alpha);
      }
    GLSL

    @default_shader = nil
    def self.default_shader
      @default_shader ||= Shader.new(PARTICLE_VERTEX_SHADER, PARTICLE_FRAGMENT_SHADER)
    end

    # --- 座標・空間設定 ---
    attr_accessor :x, :y, :z, :local_space, :camera
    attr_reader   :max_particles, :write_cursor, :used_count, :time

    # --- 放出 (Emission & Spawn Shape) ---
    attr_accessor :emitting, :loop_mode, :emission_rate, :burst_count
    attr_accessor :spawn_shape, :spawn_radius, :spawn_inner_radius, :spawn_width, :spawn_height
    attr_accessor :radial_direction # true の場合、放出位置から外側(または内側)へ向かって飛ぶ

    # --- 寿命・運動 (Lifetime & Motion) ---
    attr_accessor :lifetime, :lifetime_var
    attr_accessor :speed, :speed_var
    attr_accessor :angle, :spread
    attr_accessor :gravity_x, :gravity_y
    attr_accessor :drag
    attr_accessor :radial_accel, :tangential_accel
    attr_accessor :wobble_amp, :wobble_freq
    attr_accessor :spin, :spin_var
    attr_accessor :align_to_velocity, :stretch

    # --- サイズ遷移 (Size) ---
    attr_accessor :start_size, :end_size, :size_var, :size_curve

    # --- カラー3点補間 & フェード (Color & Alpha Fade) ---
    attr_accessor :start_color, :mid_color, :end_color
    attr_accessor :color_mid_pos, :color_var
    attr_accessor :fade_in, :fade_out

    # --- 見た目・ブレンド・テクスチャ (Visuals) ---
    attr_accessor :shape, :ring_thickness
    attr_accessor :blend
    attr_accessor :image, :anim_frames

    def initialize(x = 0.0, y = 0.0, max_particles: 4000, **opts)
      @x = x.to_f
      @y = y.to_f
      @z = 0.0
      @max_particles = [max_particles.to_i, 16].max
      @rng = Random.new

      reset_defaults
      configure(**opts) unless opts.empty?

      init_gpu_buffer
    end

    def reset_defaults
      @local_space        = false
      @camera             = true
      @emitting           = true
      @loop_mode          = false
      @emission_rate      = 150.0
      @burst_count        = 80

      @spawn_shape        = :point
      @spawn_radius       = 40.0
      @spawn_inner_radius = 0.0
      @spawn_width        = 120.0
      @spawn_height       = 40.0
      @radial_direction   = false

      @lifetime           = 0.8
      @lifetime_var       = 0.25
      @speed              = 160.0
      @speed_var          = 50.0
      @angle              = 270.0
      @spread             = 40.0

      @gravity_x          = 0.0
      @gravity_y          = -40.0
      @drag               = 1.2
      @radial_accel       = 0.0
      @tangential_accel   = 0.0
      @wobble_amp         = 15.0
      @wobble_freq        = 3.0
      @spin               = 0.0
      @spin_var           = 90.0
      @align_to_velocity  = false
      @stretch            = 1.0

      @start_size         = 24.0
      @end_size           = 2.0
      @size_var           = 0.25
      @size_curve         = :linear

      @start_color        = [255, 240, 120, 255]
      @mid_color          = [255, 110, 30, 220]
      @end_color          = [200, 20, 10, 0]
      @color_mid_pos      = 0.45
      @color_var          = 0.05
      @fade_in            = 0.08
      @fade_out           = 0.35

      @shape              = :circle
      @ring_thickness     = 0.22
      @blend              = :add
      @image              = nil
      @anim_frames        = 1

      @time               = 0.0
      @emit_accumulator   = 0.0
      @write_cursor       = 0
      @used_count         = 0
      @max_expire_time    = 0.0
      @expire_times       = Array.new(@max_particles, -1.0) if @max_particles
      self
    end

    # ハッシュによる一括設定
    def configure(**opts)
      opts.each do |k, v|
        setter = :"#{k}="
        send(setter, v)
      end
      self
    end

    # 設定を Hash としてエクスポート
    def to_h
      {
        local_space:        @local_space,
        emitting:           @emitting,
        loop_mode:          @loop_mode,
        emission_rate:      @emission_rate.round(2),
        burst_count:        @burst_count.to_i,
        spawn_shape:        @spawn_shape,
        spawn_radius:       @spawn_radius.round(2),
        spawn_inner_radius: @spawn_inner_radius.round(2),
        spawn_width:        @spawn_width.round(2),
        spawn_height:       @spawn_height.round(2),
        radial_direction:   @radial_direction,
        lifetime:           @lifetime.round(3),
        lifetime_var:       @lifetime_var.round(3),
        speed:              @speed.round(2),
        speed_var:          @speed_var.round(2),
        angle:              @angle.round(2),
        spread:             @spread.round(2),
        gravity_x:          @gravity_x.round(2),
        gravity_y:          @gravity_y.round(2),
        drag:               @drag.round(3),
        radial_accel:       @radial_accel.round(2),
        tangential_accel:   @tangential_accel.round(2),
        wobble_amp:         @wobble_amp.round(2),
        wobble_freq:        @wobble_freq.round(2),
        spin:               @spin.round(2),
        spin_var:           @spin_var.round(2),
        align_to_velocity:  @align_to_velocity,
        stretch:            @stretch.round(2),
        start_size:         @start_size.round(2),
        end_size:           @end_size.round(2),
        size_var:           @size_var.round(3),
        size_curve:         @size_curve,
        start_color:        color_to_rgba_array(@start_color),
        mid_color:          color_to_rgba_array(@mid_color),
        end_color:          color_to_rgba_array(@end_color),
        color_mid_pos:      @color_mid_pos.round(3),
        color_var:          @color_var.round(3),
        fade_in:            @fade_in.round(3),
        fade_out:           @fade_out.round(3),
        shape:              @shape,
        ring_thickness:     @ring_thickness.round(3),
        blend:              @blend
      }
    end

    # 現在生存中のパーティクル数 (概算または正確カウント)
    def alive_count
      return @max_particles if @loop_mode
      return 0 if @used_count <= 0 || @time >= @max_expire_time
      c = 0
      i = 0
      t = @time
      len = @used_count
      while i < len
        c += 1 if @expire_times[i] > t
        i += 1
      end
      c
    end

    # 全パーティクルの消去
    def clear
      @time = 0.0
      @emit_accumulator = 0.0
      @write_cursor = 0
      @used_count = 0
      @max_expire_time = 0.0
      i = 0
      while i < @max_particles
        @expire_times[i] = -1.0
        i += 1
      end
      self
    end

    # ワンショット一斉放出 (Burst)
    # x, y, color, speed, size, angle, spread, lifetime を一時オーバーライドして放出可能
    def burst(count = @burst_count, x: nil, y: nil, color: nil, speed: nil, size: nil, angle: nil, spread: nil, lifetime: nil)
      n = count.to_i
      return self if n <= 0
      old_x      = @x
      old_y      = @y
      old_speed  = @speed
      old_angle  = @angle
      old_spread = @spread
      old_life   = @lifetime

      @x        = x.to_f if x
      @y        = y.to_f if y
      @speed    = speed.to_f if speed
      @angle    = angle.to_f if angle
      @spread   = spread.to_f if spread
      @lifetime = lifetime.to_f if lifetime

      size_scale = size ? (size.to_f / [@start_size, 0.1].max) : 1.0
      tint_f4    = color ? Backend.normalize_color(color) : nil

      emit_batch(n, size_scale: size_scale, tint_f4: tint_f4)

      @x        = old_x
      @y        = old_y
      @speed    = old_speed
      @angle    = old_angle
      @spread   = old_spread
      @lifetime = old_life
      self
    end

    # GPU ループモード用に全スロットを一括初期充填 (CPU転送ゼロで無限ループ再生したい場合)
    def fill_loop_pool!(count = @max_particles)
      @loop_mode = true
      n = [[count.to_i, 1].max, @max_particles].min
      @write_cursor = 0
      emit_batch(n, random_time_offset: true)
      self
    end

    # 毎フレーム更新 (新規発生分のみリングバッファへ glBufferSubData 転送)
    def update(dt = Window.delta_time)
      @time += dt.to_f

      if !@loop_mode && @used_count > 0 && @time >= @max_expire_time
        @used_count = 0
        @write_cursor = 0
      end

      if !@loop_mode && @emitting && @emission_rate > 0.0
        @emit_accumulator += @emission_rate * dt.to_f
        spawn_n = @emit_accumulator.to_i
        if spawn_n > 0
          @emit_accumulator -= spawn_n.to_f
          spawn_n = @max_particles if spawn_n > @max_particles
          emit_batch(spawn_n)
        end
      end
      self
    end

    # 描画 (1 ドローコール)
    def draw(x: nil, y: nil, z: nil, camera: nil)
      return self if @used_count <= 0 && !@loop_mode

      draw_x = x ? x.to_f : @x
      draw_y = y ? y.to_f : @y
      draw_z = z ? z.to_f : @z
      use_cam = camera.nil? ? @camera : camera

      cam = Window.active_camera
      if use_cam && cam
        zoom, ox, oy = cam.view
        ox += Window.offset_x
        oy += Window.offset_y
      else
        zoom = 1.0
        ox = Window.offset_x
        oy = Window.offset_y
      end

      shape_id = SHAPES[@shape] || @shape.to_i
      curve_id = SIZE_CURVES[@size_curve] || @size_curve.to_i
      is_add   = (@blend == :add) ? 1.0 : 0.0
      loc_flag = @local_space ? 1.0 : 0.0

      has_tex = @image ? 1.0 : 0.0
      if @image
        u0, v0, uw, vh = @image.uv
      else
        u0 = 0.0; v0 = 0.0; uw = 1.0; vh = 1.0
      end

      sc = Backend.normalize_color(@start_color)
      mc = Backend.normalize_color(@mid_color)
      ec = Backend.normalize_color(@end_color)

      uniforms = {
        u_view:        [zoom, ox, oy, loc_flag],
        u_sim:         [@time, @loop_mode ? 1.0 : 0.0, shape_id.to_f, is_add],
        u_emitter:     [draw_x, draw_y, @align_to_velocity ? 1.0 : 0.0, @stretch.to_f],
        u_forces:      [@gravity_x.to_f, @gravity_y.to_f, @drag.to_f, @radial_accel.to_f],
        u_turb:        [@tangential_accel.to_f, @wobble_amp.to_f, @wobble_freq.to_f, @ring_thickness.to_f],
        u_size_fade:   [@start_size.to_f, @end_size.to_f, curve_id.to_f, @fade_in.to_f],
        u_fade_uv:     [@fade_out.to_f, @color_mid_pos.to_f, has_tex, @anim_frames.to_f],
        u_uv_rect:     [u0, v0, uw, vh],
        u_start_color: sc,
        u_mid_color:   mc,
        u_end_color:   ec
      }

      @instance_buffer.draw(
        z: draw_z,
        image: @image,
        blend: @blend,
        uniforms: uniforms
      )
      self
    end

    private

    def init_gpu_buffer
      @expire_times = Array.new(@max_particles, -1.0)
      @staging_floats = []
      @used_count = 0
      @max_expire_time = 0.0
      zero_bin = "\x00" * (@max_particles * BYTES_PER_PARTICLE)
      @instance_buffer = InstanceBuffer.new(
        data: zero_bin,
        count: @max_particles,
        layout: [4, 4, 4, 4],
        shader: ParticleEmitter.default_shader,
        blend: @blend
      )
    end

    def emit_batch(count, random_time_offset: false, size_scale: 1.0, tint_f4: nil)
      return if count <= 0
      remaining = count
      while remaining > 0
        chunk = [remaining, @max_particles - @write_cursor].min
        write_chunk(@write_cursor, chunk, random_time_offset, size_scale, tint_f4)
        @write_cursor = (@write_cursor + chunk) % @max_particles
        remaining -= chunk
      end
    end

    def write_chunk(start_index, count, random_time_offset, size_scale = 1.0, tint_f4 = nil)
      @staging_floats.clear
      deg_rad = DEG_TO_RAD
      base_x = @local_space ? 0.0 : @x
      base_y = @local_space ? 0.0 : @y
      s_type = SPAWN_SHAPES[@spawn_shape] || @spawn_shape.to_i
      tr = tint_f4 ? tint_f4[0] : 0.0
      tg = tint_f4 ? tint_f4[1] : 0.0
      tb = tint_f4 ? tint_f4[2] : 0.0
      ta = tint_f4 ? tint_f4[3] : 0.0

      i = 0
      while i < count
        # 1. 放出位置 (Spawn Shape) の計算
        ox = 0.0
        oy = 0.0
        spawn_ang = 0.0

        case s_type
        when 1 # :circle (円内ランダム分布)
          ang = @rng.rand * Math::PI * 2.0
          r_min = [@spawn_inner_radius.to_f, 0.0].max
          r_max = [@spawn_radius.to_f, r_min].max
          t_r = Math.sqrt(@rng.rand)
          r = r_min + (r_max - r_min) * t_r
          ox = Math.cos(ang) * r
          oy = Math.sin(ang) * r
          spawn_ang = ang
        when 2 # :ring (円周上)
          ang = @rng.rand * Math::PI * 2.0
          r = @spawn_radius.to_f + (@rng.rand * 2.0 - 1.0) * @spawn_inner_radius.to_f
          ox = Math.cos(ang) * r
          oy = Math.sin(ang) * r
          spawn_ang = ang
        when 3 # :box (矩形領域)
          ox = (@rng.rand - 0.5) * @spawn_width.to_f
          oy = (@rng.rand - 0.5) * @spawn_height.to_f
          spawn_ang = Math.atan2(oy, ox)
        when 4 # :line (線分)
          t_l = @rng.rand - 0.5
          line_rad = (@angle - 90.0) * deg_rad
          ox = Math.cos(line_rad) * (t_l * @spawn_width.to_f)
          oy = Math.sin(line_rad) * (t_l * @spawn_width.to_f)
          spawn_ang = @angle * deg_rad
        end

        px = base_x + ox
        py = base_y + oy

        # 2. 初速ベクトル
        spr = (@rng.rand * 2.0 - 1.0) * (@spread * 0.5) * deg_rad
        dir_rad = @radial_direction ? (spawn_ang + spr) : (@angle * deg_rad + spr)
        spd = @speed + (@rng.rand * 2.0 - 1.0) * @speed_var
        vx = Math.cos(dir_rad) * spd
        vy = Math.sin(dir_rad) * spd

        # 3. 寿命・発生時刻・サイズ倍率・スピン
        life = [@lifetime + (@rng.rand * 2.0 - 1.0) * @lifetime_var, 0.05].max
        t0 = random_time_offset ? (@time - @rng.rand * life) : @time
        size_mul = [1.0 + (@rng.rand * 2.0 - 1.0) * @size_var, 0.1].max * size_scale
        spin_spd = @spin + (@rng.rand * 2.0 - 1.0) * @spin_var

        # 4. 初期角度・揺らぎ位相・明度ばらつき・乱数シード
        ang0 = @rng.rand * 360.0
        wob_phase = @rng.rand * Math::PI * 2.0
        c_var = (@rng.rand * 2.0 - 1.0) * @color_var
        r_seed = @rng.rand

        @staging_floats.push(
          px, py, vx, vy,
          t0, life, size_mul, spin_spd,
          ang0, wob_phase, c_var, r_seed,
          tr, tg, tb, ta
        )

        exp = t0 + life
        @expire_times[start_index + i] = exp
        @max_expire_time = exp if exp > @max_expire_time
        i += 1
      end

      end_idx = start_index + count
      @used_count = end_idx if end_idx > @used_count

      bin = @staging_floats.pack("f*")
      @instance_buffer.update(bin, offset: start_index * BYTES_PER_PARTICLE, count: @used_count)
    end

    def color_to_rgba_array(col)
      f4 = Backend.normalize_color(col)
      [(f4[0] * 255).round, (f4[1] * 255).round, (f4[2] * 255).round, (f4[3] * 255).round]
    end
  end

  # ====================================================================
  # マルチレイヤー・パーティクルシステム (Zenoo::ParticleSystem)
  # ====================================================================
  # - 複数の ParticleEmitter (レイヤー) を束ねて1つのリッチなエフェクトとして管理します。
  #   (例: 「閃光リング + 火花 + 爆炎 + 遅れて立ち昇る黒煙」の4層合成エフェクトなど)
  # - 組み込みプリセット (ParticleSystem.preset(:explosion) 等) も標準搭載しています。
  # ====================================================================
  class ParticleSystem
    attr_reader :emitters
    attr_accessor :x, :y, :z, :camera

    def initialize(x = 0.0, y = 0.0, max_particles: 4000, **opts)
      @x = x.to_f
      @y = y.to_f
      @z = 0.0
      @camera = true
      @emitters = []

      unless opts.empty?
        add_emitter(max_particles: max_particles, **opts)
      end
    end

    def add_emitter(max_particles: 4000, **opts)
      em = ParticleEmitter.new(@x, @y, max_particles: max_particles, **opts)
      @emitters << em
      em
    end

    def remove_emitter(index)
      @emitters.delete_at(index) if @emitters.length > 1
    end

    def [](index)
      @emitters[index]
    end

    def primary
      @emitters[0] ||= ParticleEmitter.new(@x, @y)
    end

    def move_to(nx, ny)
      @x = nx.to_f
      @y = ny.to_f
      i = 0
      len = @emitters.length
      while i < len
        @emitters[i].x = @x
        @emitters[i].y = @y
        i += 1
      end
      self
    end

    def burst(count = nil, x: nil, y: nil)
      bx = x ? x.to_f : @x
      by = y ? y.to_f : @y
      i = 0
      len = @emitters.length
      while i < len
        em = @emitters[i]
        em.burst(count || em.burst_count, x: bx, y: by)
        i += 1
      end
      self
    end

    def clear
      @emitters.each(&:clear)
      self
    end

    def alive_count
      total = 0
      i = 0
      len = @emitters.length
      while i < len
        total += @emitters[i].alive_count
        i += 1
      end
      total
    end

    def max_particles
      total = 0
      i = 0
      len = @emitters.length
      while i < len
        total += @emitters[i].max_particles
        i += 1
      end
      total
    end

    def update(dt = Window.delta_time)
      i = 0
      len = @emitters.length
      while i < len
        em = @emitters[i]
        em.x = @x
        em.y = @y
        em.update(dt)
        i += 1
      end
      self
    end

    def draw(x: nil, y: nil, z: nil, camera: nil)
      dx = x ? x.to_f : @x
      dy = y ? y.to_f : @y
      dz = z ? z.to_f : @z
      cam = camera.nil? ? @camera : camera

      i = 0
      len = @emitters.length
      while i < len
        @emitters[i].draw(x: dx, y: dy, z: dz + i * 0.01, camera: cam)
        i += 1
      end
      self
    end

    # ------------------------------------------------------------------
    # リッチプリセット定義 (マルチレイヤー構成)
    # ------------------------------------------------------------------
    PRESET_NAMES = [
      :fire, :explosion, :sparks, :magic_galaxy, :charge_aura, :blizzard, :star_fountain, :cyber_portal
    ].freeze

    def self.preset(name, x = 640.0, y = 360.0)
      ps = new(x, y)
      ps.apply_preset(name)
      ps
    end

    def apply_preset(name)
      @emitters.clear
      case name.to_sym
      when :fire
        # Layer 1: 立ち昇る黒煙 (Alpha)
        add_emitter(
          max_particles: 1500,
          emitting: true, emission_rate: 70.0,
          spawn_shape: :circle, spawn_radius: 18.0,
          lifetime: 1.5, lifetime_var: 0.4,
          speed: 85.0, speed_var: 30.0, angle: 270.0, spread: 35.0,
          gravity_y: -35.0, drag: 0.8, wobble_amp: 28.0, wobble_freq: 2.2,
          start_size: 18.0, end_size: 64.0, size_curve: :ease_out,
          start_color: [90, 80, 85, 130], mid_color: [55, 55, 65, 90], end_color: [30, 30, 38, 0],
          color_mid_pos: 0.4, fade_in: 0.15, fade_out: 0.5,
          shape: :soft, blend: :alpha
        )
        # Layer 2: 紅蓮の炎コア (Add)
        add_emitter(
          max_particles: 3000,
          emitting: true, emission_rate: 320.0,
          spawn_shape: :circle, spawn_radius: 16.0,
          lifetime: 0.75, lifetime_var: 0.25,
          speed: 150.0, speed_var: 50.0, angle: 270.0, spread: 32.0,
          gravity_y: -60.0, drag: 1.2, radial_accel: -35.0, wobble_amp: 16.0, wobble_freq: 4.5,
          start_size: 32.0, end_size: 4.0, size_curve: :linear,
          start_color: [255, 250, 180, 240], mid_color: [255, 110, 20, 220], end_color: [200, 15, 5, 0],
          color_mid_pos: 0.35, fade_in: 0.08, fade_out: 0.4,
          shape: :circle, blend: :add
        )
        # Layer 3: 舞い上がる火の粉 (Spark Add)
        add_emitter(
          max_particles: 1000,
          emitting: true, emission_rate: 60.0,
          spawn_shape: :circle, spawn_radius: 22.0,
          lifetime: 1.3, lifetime_var: 0.5,
          speed: 220.0, speed_var: 90.0, angle: 270.0, spread: 50.0,
          gravity_y: -80.0, drag: 0.6, wobble_amp: 35.0, wobble_freq: 6.0,
          align_to_velocity: true, stretch: 2.2,
          start_size: 7.0, end_size: 1.5,
          start_color: [255, 255, 200, 255], mid_color: [255, 160, 40, 240], end_color: [255, 50, 10, 0],
          shape: :spark, blend: :add
        )

      when :explosion
        # Layer 1: 爆煙 (Smoke)
        add_emitter(
          max_particles: 1000,
          emitting: false, burst_count: 120,
          spawn_shape: :circle, spawn_radius: 15.0, radial_direction: true,
          lifetime: 1.4, lifetime_var: 0.4,
          speed: 240.0, speed_var: 120.0, spread: 360.0,
          gravity_y: -25.0, drag: 3.2, wobble_amp: 15.0, wobble_freq: 2.0,
          start_size: 24.0, end_size: 85.0, size_curve: :ease_out,
          start_color: [140, 120, 110, 180], mid_color: [70, 65, 75, 130], end_color: [35, 35, 45, 0],
          fade_in: 0.05, fade_out: 0.5, shape: :soft, blend: :alpha
        )
        # Layer 2: 爆炎 (Fireball)
        add_emitter(
          max_particles: 2500,
          emitting: false, burst_count: 350,
          spawn_shape: :circle, spawn_radius: 10.0, radial_direction: true,
          lifetime: 0.75, lifetime_var: 0.3,
          speed: 420.0, speed_var: 220.0, spread: 360.0,
          gravity_y: 40.0, drag: 4.0, wobble_amp: 12.0, wobble_freq: 5.0,
          start_size: 42.0, end_size: 4.0, size_curve: :ease_out,
          start_color: [255, 255, 220, 255], mid_color: [255, 120, 25, 230], end_color: [200, 20, 10, 0],
          color_mid_pos: 0.3, fade_in: 0.02, fade_out: 0.4,
          shape: :circle, blend: :add
        )
        # Layer 3: 高速飛散スパーク (Sparks)
        add_emitter(
          max_particles: 2000,
          emitting: false, burst_count: 250,
          spawn_shape: :point,
          lifetime: 1.1, lifetime_var: 0.4,
          speed: 650.0, speed_var: 280.0, spread: 360.0,
          gravity_y: 380.0, drag: 1.8,
          align_to_velocity: true, stretch: 3.2,
          start_size: 9.0, end_size: 2.0,
          start_color: [255, 255, 240, 255], mid_color: [255, 190, 60, 255], end_color: [255, 60, 10, 0],
          shape: :spark, blend: :add
        )
        # Layer 4: 衝撃波リング (Shockwave Ring)
        add_emitter(
          max_particles: 128,
          emitting: false, burst_count: 3,
          spawn_shape: :point,
          lifetime: 0.45, lifetime_var: 0.05,
          speed: 0.0, speed_var: 0.0,
          start_size: 16.0, end_size: 360.0, size_curve: :ease_out,
          start_color: [255, 240, 200, 255], mid_color: [255, 150, 50, 180], end_color: [255, 80, 20, 0],
          ring_thickness: 0.12, shape: :ring, blend: :add
        )
        burst

      when :sparks
        add_emitter(
          max_particles: 4000,
          emitting: true, emission_rate: 450.0, burst_count: 250,
          spawn_shape: :point,
          lifetime: 1.0, lifetime_var: 0.35,
          speed: 440.0, speed_var: 180.0, angle: 270.0, spread: 110.0,
          gravity_y: 580.0, drag: 0.8,
          align_to_velocity: true, stretch: 2.8,
          start_size: 8.0, end_size: 2.0,
          start_color: [255, 255, 220, 255], mid_color: [255, 180, 50, 240], end_color: [255, 50, 15, 0],
          color_mid_pos: 0.4, fade_out: 0.3,
          shape: :spark, blend: :add
        )

      when :magic_galaxy
        # Layer 1: 銀河渦巻き星屑 (Star Swirl)
        add_emitter(
          max_particles: 5000,
          emitting: true, emission_rate: 600.0, burst_count: 300,
          spawn_shape: :ring, spawn_radius: 28.0, spawn_inner_radius: 8.0, radial_direction: true,
          lifetime: 1.8, lifetime_var: 0.4,
          speed: 110.0, speed_var: 40.0, spread: 40.0,
          drag: 0.6, radial_accel: 20.0, tangential_accel: 180.0,
          wobble_amp: 12.0, wobble_freq: 3.0, spin: 180.0, spin_var: 120.0,
          start_size: 20.0, end_size: 3.0, size_curve: :sine,
          start_color: [120, 255, 255, 255], mid_color: [190, 90, 255, 230], end_color: [255, 40, 160, 0],
          color_mid_pos: 0.5, color_var: 0.12, fade_in: 0.15, fade_out: 0.35,
          shape: :star, blend: :add
        )
        # Layer 2: 中心魔力リング脈動
        add_emitter(
          max_particles: 500,
          emitting: true, emission_rate: 12.0,
          spawn_shape: :point,
          lifetime: 1.1, lifetime_var: 0.1,
          speed: 0.0, speed_var: 0.0,
          start_size: 12.0, end_size: 220.0, size_curve: :ease_out,
          start_color: [80, 220, 255, 200], mid_color: [160, 80, 255, 120], end_color: [220, 40, 255, 0],
          ring_thickness: 0.1, shape: :ring, blend: :add
        )

      when :charge_aura
        # 外周リングから中心へ吸い込まれる「溜め / チャージ」エフェクト
        add_emitter(
          max_particles: 4000,
          local_space: true,
          emitting: true, emission_rate: 500.0, burst_count: 200,
          spawn_shape: :ring, spawn_radius: 170.0, spawn_inner_radius: 25.0, radial_direction: true,
          lifetime: 0.85, lifetime_var: 0.15,
          speed: -180.0, speed_var: 30.0, spread: 15.0,
          drag: 0.2, radial_accel: -120.0, tangential_accel: 110.0,
          align_to_velocity: true, stretch: 2.2,
          start_size: 4.0, end_size: 22.0, size_curve: :ease_in,
          start_color: [40, 180, 255, 0], mid_color: [100, 240, 255, 230], end_color: [255, 255, 255, 255],
          color_mid_pos: 0.65, fade_in: 0.25, fade_out: 0.1,
          shape: :spark, blend: :add
        )
        # 中心コアの輝き
        add_emitter(
          max_particles: 1000,
          local_space: true,
          emitting: true, emission_rate: 90.0,
          spawn_shape: :circle, spawn_radius: 12.0,
          lifetime: 0.4, lifetime_var: 0.1,
          speed: 25.0, speed_var: 15.0, spread: 360.0,
          start_size: 38.0, end_size: 5.0, size_curve: :sine,
          start_color: [255, 255, 255, 255], mid_color: [100, 230, 255, 220], end_color: [40, 120, 255, 0],
          shape: :star, blend: :add
        )

      when :blizzard
        # 広範囲ボックスから吹き荒れる吹雪
        add_emitter(
          max_particles: 5000,
          emitting: true, emission_rate: 450.0,
          spawn_shape: :box, spawn_width: 750.0, spawn_height: 40.0,
          lifetime: 3.2, lifetime_var: 0.8,
          speed: 190.0, speed_var: 60.0, angle: 110.0, spread: 20.0,
          gravity_x: -35.0, gravity_y: 45.0, drag: 0.3,
          wobble_amp: 35.0, wobble_freq: 1.8, spin: 120.0, spin_var: 180.0,
          start_size: 12.0, end_size: 4.0, size_var: 0.45,
          start_color: [240, 250, 255, 230], mid_color: [190, 225, 255, 190], end_color: [140, 190, 245, 0],
          fade_in: 0.1, fade_out: 0.3,
          shape: :diamond, blend: :add
        )

      when :star_fountain
        add_emitter(
          max_particles: 3000,
          emitting: true, emission_rate: 220.0, burst_count: 150,
          spawn_shape: :circle, spawn_radius: 10.0,
          lifetime: 1.5, lifetime_var: 0.3,
          speed: 380.0, speed_var: 110.0, angle: 270.0, spread: 65.0,
          gravity_y: 520.0, drag: 0.4, spin: 240.0, spin_var: 180.0,
          start_size: 22.0, end_size: 6.0, size_var: 0.3,
          start_color: [255, 250, 120, 255], mid_color: [255, 180, 40, 240], end_color: [255, 80, 120, 0],
          color_var: 0.1, fade_in: 0.05, fade_out: 0.25,
          shape: :star, blend: :add
        )

      when :cyber_portal
        add_emitter(
          max_particles: 4000,
          emitting: true, emission_rate: 400.0,
          spawn_shape: :ring, spawn_radius: 110.0, spawn_inner_radius: 4.0, radial_direction: true,
          lifetime: 1.2, lifetime_var: 0.2,
          speed: 20.0, speed_var: 15.0, spread: 20.0,
          radial_accel: -60.0, tangential_accel: 260.0,
          spin: 90.0, spin_var: 90.0,
          start_size: 14.0, end_size: 2.0, size_curve: :sine,
          start_color: [0, 255, 180, 255], mid_color: [0, 160, 255, 220], end_color: [120, 40, 255, 0],
          shape: :box, blend: :add
        )
      end
      self
    end
  end
end

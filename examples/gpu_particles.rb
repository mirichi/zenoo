# frozen_string_literal: true
# ==============================================================================
# Zenoo: GPU Particle Storm (100,000〜200,000 Particles Demo)
# ==============================================================================
# 頂点バッファを一度だけ構築してGPU（VRAM）側に置き、
# 毎フレームの計算はすべて頂点シェーダー内で実行することで、
# Rubyのオーバーヘッドをゼロにして衝撃的な数のパーティクルを60fpsで描画します。
#
# 操作方法:
#   - マウス移動 / ドラッグ : パーティクルを重力・渦巻きで引き寄せる
#   - キー [1] : 50,000 個
#   - キー [2] : 100,000 個 (デフォルト)
#   - キー [3] : 200,000 個
#   - キー [SPACE] : 爆発・拡散パルス
# ==============================================================================

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../ext/zenoo", __dir__)
require 'zenoo'

WIDTH  = 1280
HEIGHT = 720

# ------------------------------------------------------------------------------
# 頂点シェーダー: すべての運動方程式・アニメーション・ビルボード展開をGPU内で完結
# ------------------------------------------------------------------------------
PARTICLE_VERT = <<~'GLSL'
  #version 330 core

  // インスタンス属性 (各パーティクル固有の静的パラメータ)
  layout (location = 0) in vec4 in_pos_vel;   // x0, y0, vx, vy
  layout (location = 1) in vec4 in_params;    // t0 (発生遅延), life (寿命), size, seed
  layout (location = 2) in vec4 in_color;     // base_color (r, g, b, a)

  uniform vec2  u_resolution;
  uniform float u_flip_y;
  uniform float u_time;
  uniform vec2  u_mouse;
  uniform float u_pulse; // スペースキーによる爆発パルス

  out vec4 v_color;
  out vec2 v_uv;

  void main() {
      // 1. パーティクルのローカル時間と進行度 (0.0 .. 1.0)
      float t0 = in_params.x;
      float life = in_params.y;
      float seed = in_params.w;

      // 寿命でループアニメーション
      float age = mod(u_time + t0, life);
      float progress = age / life;

      // 2. 物理演算: 初速 + 乱流 (Turbulence)
      vec2 p0 = in_pos_vel.xy;
      vec2 vel = in_pos_vel.zw;

      // 基本位置
      vec2 cur_pos = p0 + vel * age;

      // 乱流 (三角関数の揺らぎ)
      cur_pos.x += sin(age * 3.0 + seed * 6.28) * 20.0;
      cur_pos.y += cos(age * 2.5 + seed * 6.28) * 20.0;

      // マウス引力 & 渦巻き (Vortex)
      vec2 to_mouse = u_mouse - cur_pos;
      float dist = length(to_mouse);
      if (dist > 5.0 && dist < 500.0) {
          float force = (1.0 - dist / 500.0);
          // 引力
          cur_pos += normalize(to_mouse) * force * 120.0;
          // 接線方向の渦巻き
          vec2 tangent = vec2(-to_mouse.y, to_mouse.x) / dist;
          cur_pos += tangent * force * force * 200.0;
      }

      // 爆発パルス
      if (u_pulse > 0.0) {
          vec2 from_center = cur_pos - u_mouse;
          float p_dist = max(length(from_center), 1.0);
          cur_pos += (from_center / p_dist) * (u_pulse * 300.0 / (1.0 + p_dist * 0.005));
      }

      // 3. サイズとフェードのアニメーション (生まれはじめと消え際に小さく・透明に)
      float size_scale = sin(progress * 3.14159265);
      float cur_size = in_params.z * size_scale;

      // 4. gl_VertexID (0..3) によるクアッド (Billboard) の四隅展開
      // 0: (0, 0), 1: (1, 0), 2: (0, 1), 3: (1, 1)
      vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
      vec2 offset = (corner - vec2(0.5)) * cur_size;

      vec2 final_pos = cur_pos + offset;

      // 5. 画面投影 (NDC)
      vec2 ndc = (final_pos / u_resolution) * 2.0 - 1.0;
      ndc.y = ndc.y * ((u_flip_y == 0.0) ? -1.0 : u_flip_y);
      gl_Position = vec4(ndc, 0.0, 1.0);

      // 色の遷移: 進行に応じて色相がシフトし、端でフェードアウト
      v_color = in_color * size_scale;
      v_uv = corner;
  }
GLSL

# ------------------------------------------------------------------------------
# フラグメントシェーダー: ソフトな光球 (円形グロー) をプロシージャル描画
# ------------------------------------------------------------------------------
PARTICLE_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_uv;
  out vec4 fragColor;

  void main() {
      // 中心 (0.5, 0.5) からの距離でソフトな円形光球を表現
      vec2 d = v_uv - vec2(0.5);
      float dist_sq = dot(d, d);
      if (dist_sq > 0.25) {
          discard;
      }
      // 中心ほど強く光り、外側に向かってなだらかに減衰
      float alpha = clamp((0.25 - dist_sq) * 4.0, 0.0, 1.0);
      float glow = exp(-dist_sq * 16.0);
      fragColor = vec4(v_color.rgb * (1.0 + glow * 2.0), v_color.a * alpha);
  }
GLSL

# ------------------------------------------------------------------------------
# パーティクルバッファの生成関数
# ------------------------------------------------------------------------------
def create_particle_mesh(count, shader, pipeline)
  puts "Generating #{count} particles..."
  t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # 1 パーティクルあたり 12 floats:
  # pos_vel (4): x, y, vx, vy
  # params  (4): t0, life, size, seed
  # color   (4): r, g, b, a
  raw_floats = []

  cx = WIDTH * 0.5
  cy = HEIGHT * 0.5

  count.times do
    # 初期位置: 画面全体に分散、または中心付近に集約
    angle = rand * Math::PI * 2.0
    radius = (rand**0.5) * (WIDTH * 0.45)
    px = cx + Math.cos(angle) * radius
    py = cy + Math.sin(angle) * radius

    # 初速 (放射状または渦巻き)
    speed = rand(10.0..60.0)
    vx = Math.cos(angle + 1.2) * speed
    vy = Math.sin(angle + 1.2) * speed

    # パラメータ: t0(遅延), 寿命(2.0..6.0秒), サイズ(4..14px), シード
    t0 = rand(0.0..10.0)
    life = rand(2.5..6.0)
    size = rand(6.0..18.0)
    seed = rand

    # カラーパレット: 宇宙的なシアン〜パープル〜ネオンオレンジ
    palette_choice = rand
    if palette_choice < 0.4
      # ネオンブルー / シアン
      r, g, b = rand(0.1..0.3), rand(0.6..1.0), rand(0.9..1.0)
    elsif palette_choice < 0.75
      # パープル / マゼンタ
      r, g, b = rand(0.7..1.0), rand(0.1..0.4), rand(0.8..1.0)
    else
      # ゴールド / オレンジ
      r, g, b = rand(1.0..1.0), rand(0.6..0.9), rand(0.1..0.3)
    end
    a = rand(0.4..0.8)

    raw_floats.push(
      px, py, vx, vy,
      t0, life, size, seed,
      r, g, b, a
    )
  end

  packed_binary = raw_floats.pack("f*")
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_start) * 1000.0
  puts "Generated #{count} particles in #{elapsed.round(1)} ms (Buffer size: #{(packed_binary.bytesize / 1024.0 / 1024.0).round(2)} MB)"

  Mesh.new(
    data: packed_binary,
    count: count,
    pipeline: pipeline,
    shader: shader,
    blend: :add
  )
end

# ------------------------------------------------------------------------------
# メインループ
# ------------------------------------------------------------------------------
puts "Starting Zenoo GPU Particle Demo..."

pulse_val = 0.0
time = 0.0
current_count = 100_000

# ------------------------------------------------------------------------------
# 初期化 (Window.loop 前にシェーダーとメッシュを生成)
# ------------------------------------------------------------------------------
particle_shader = Shader.new(PARTICLE_VERT, PARTICLE_FRAG)

# インスタンシングパイプラインの定義:
# トポロジー: TRIANGLE_STRIP
# レイアウト: vec4, vec4, vec4 (合計12 floats)
# Divisors: 1, 1, 1 (各属性が1インスタンスごとに進む)
# base_vertex_count: 4 (1インスタンスあたり4頂点のクアッドを展開)
particle_pipeline = Zenoo::Backend::Pipeline.new(
  Zenoo::Backend::Topology::TRIANGLE_STRIP,
  "\x04\x04\x04",
  "\x01\x01\x01",
  4
)

mesh_cache = {}
mesh_cache[50_000]  = create_particle_mesh(50_000, particle_shader, particle_pipeline)
mesh_cache[100_000] = create_particle_mesh(100_000, particle_shader, particle_pipeline)
active_mesh = mesh_cache[100_000]

fps_timer = 0.0
frame_counter = 0
last_fps = 60.0

# ------------------------------------------------------------------------------
# メインループ
# ------------------------------------------------------------------------------
Window.loop(WIDTH, HEIGHT, "Zenoo GPU Particle Storm", vsync: false) do

  dt = Window.delta_time
  time += dt

  # キー入力によるパーティクル数切り替え
  if Input.key_push?(:"1")
    current_count = 50_000
    active_mesh = mesh_cache[50_000]
  elsif Input.key_push?(:"2")
    current_count = 100_000
    active_mesh = mesh_cache[100_000]
  elsif Input.key_push?(:"3")
    current_count = 200_000
    mesh_cache[200_000] ||= create_particle_mesh(200_000, particle_shader, particle_pipeline)
    active_mesh = mesh_cache[200_000]
  end

  # スペースキーで衝撃波パルス
  if Input.key_push?(:space) || Input.mouse_push?(:left)
    pulse_val = 1.0
  end
  pulse_val = [pulse_val - dt * 2.5, 0.0].max

  # マウス座標
  mx = Input.mouse_x
  my = Input.mouse_y

  # 画面クリア（深みのあるダークネイビー）
  Window.clear(0x0a0c16ff)

  # パーティクルメッシュの描画 (毎フレームのpackはゼロ！)
  active_mesh.draw(
    z: 10.0,
    uniforms: {
      u_time:  time,
      u_mouse: [mx, my],
      u_pulse: pulse_val
    }
  )

  # UI表示
  frame_counter += 1
  fps_timer += dt
  if fps_timer >= 0.5
    last_fps = (frame_counter / fps_timer).round(1)
    frame_counter = 0
    fps_timer = 0.0
  end

  if ENV["TEST_FRAMES"] && frame_counter >= ENV["TEST_FRAMES"].to_i
    puts "TEST_FRAMES reached (#{ENV['TEST_FRAMES']} frames). Exiting cleanly."
    break
  end

  Window.draw_text(20, 20, "Zenoo GPU Particles: #{current_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}", size: 28, color: :white, z: 100.0)
  Window.draw_text(20, 56, "FPS: #{last_fps}  (Ruby Array#pack is 0 calls/frame!)", size: 20, color: [0.4, 1.0, 0.5, 1.0], z: 100.0)
  Window.draw_text(20, 84, "[Mouse] Gravity Vortex   [Space / Click] Shockwave   [1/2/3] Switch Count", size: 16, color: [0.7, 0.8, 1.0, 0.8], z: 100.0)
end

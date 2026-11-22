# frozen_string_literal: true

# ==============================================================================
# NEON ABYSS: Luminous Leviathan & 2D Global Illumination
# ==============================================================================
# Zenoo 2D Game Engine フルスペック・テックデモ & インタラクティブ体験
# (Pure Ruby + Spinel AOT + OpenGL 3.3 / WebGL 2.0)
#
# 【主な搭載技術】
#  1. マルチパス FBO レンダリングパイプライン (DAG 構成):
#     Occluder FBO (640x360) -> 2D Raymarching GI/Shadow FBO (640x360)
#     -> Main Scene FBO (1280x720) -> 2段 Separable Gaussian Bloom (320x180)
#     -> ACES Filmic Tonemap + Chromatic Aberration + Mirror Water Composite
#  2. 2D レイマーチング・ソフトシャドウ & ボリュメトリックゴッドレイ (最大12灯)
#  3. 10,000 GPU フローパーティクル (InstanceBuffer + 頂点シェーダー物理・毎フレーム 0 pack)
#  4. NEON LEVIATHAN: 24節ダイナミック背骨 + 二重 set_ribbon メッシュ変形 +
#     10関節x2 FABRIK IK 触角 (Bone.solve_fabrik) + deform 波打ちエネルギーヒレ
#  5. GPU ParticleEmitter によるスーパーノヴァ＆航跡火花
#  6. プロシージャル SDF タイポグラフィ & CharContext 1文字波打ちアニメーション
#  7. Pure Ruby リアルタイム PCM シンセサイザー (シームレスループBGM & 共鳴音階SE)
#
# 【操作方法】
#  - マウス / WASD / 矢印 : 光のオーブ操作
#  - 左クリック / SPACE (長押し->離す) : チャージ & スーパーノヴァ・ショックウェーブ
#  - 右クリック長押し / V : 重力特異点 (Gravity Vortex)
#  - 右クリック短押し / P : 古代モノリス柱を配置
#  - [1]..[4] / [T] : 4つのネオンテーマ切替
#  - [G] : モード切替 (SANCTUARY / RESONANCE HUNT)
#  - [B] [L] [W] [D] : Bloom / 2D GI影 / 水面反射 / 空間歪み トグル
#  - [M] : サウンドミュート   [H] : HUD表示切替   [R] : リセット
# ==============================================================================

require_relative "../lib/zenoo"

WIDTH   = 1280
HEIGHT  = 720
HALF_W  = 640
HALF_H  = 360
BLOOM_W = 320
BLOOM_H = 180
WATER_Y = 505.0
DT      = 1.0 / 60.0
TWO_PI  = Math::PI * 2.0
DEG_RAD = Math::PI / 180.0
RAD_DEG = 180.0 / Math::PI

# ------------------------------------------------------------------------------
# 補助関数 (Spinel AOT 安全 & 高速)
# ------------------------------------------------------------------------------
def clamp_f(v, lo, hi)
  return lo if v < lo
  return hi if v > hi
  v
end

def clamp_i(v, lo, hi)
  return lo if v < lo
  return hi if v > hi
  v
end

def lerp_f(a, b, t)
  a + (b - a) * t
end

def wrap_angle_rad(a)
  while a > Math::PI
    a -= TWO_PI
  end
  while a < -Math::PI
    a += TWO_PI
  end
  a
end

# ==============================================================================
# 1. GLSL シェーダー群 (#version 330 core / WebGL2 ES 3.00 互換)
# ==============================================================================

# 1A. 背景大気・星雲・オーロラ・遠景古代神殿シルエット
BG_ATMOSPHERE_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_uv;
  uniform sampler2D u_texture;
  uniform float u_time;
  uniform float u_water_y;
  uniform vec4 u_bg_top;
  uniform vec4 u_bg_horizon;
  uniform vec4 u_aurora_a;
  uniform vec4 u_aurora_b;
  uniform vec2 u_cam_offset;
  out vec4 fragColor;

  float hash21(vec2 p) {
      p = fract(p * vec2(123.34, 456.21));
      p += dot(p, p + 45.32);
      return fract(p.x * p.y);
  }

  float noise2d(vec2 p) {
      vec2 i = floor(p);
      vec2 f = fract(p);
      vec2 u = f * f * (3.0 - 2.0 * f);
      float a = hash21(i);
      float b = hash21(i + vec2(1.0, 0.0));
      float c = hash21(i + vec2(0.0, 1.0));
      float d = hash21(i + vec2(1.0, 1.0));
      return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
  }

  float fbm4(vec2 p) {
      float sum = 0.0;
      float amp = 0.5;
      mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
      for (int i = 0; i < 4; i++) {
          sum += amp * noise2d(p);
          p = rot * p * 2.02 + vec2(17.1, 31.7);
          amp *= 0.5;
      }
      return sum;
  }

  void main() {
      vec2 uv = v_uv;
      float sky_t = clamp(uv.y / max(u_water_y, 0.05), 0.0, 1.0);

      // 深いグラデーション空
      vec3 col = mix(u_bg_top.rgb, u_bg_horizon.rgb, pow(sky_t, 1.35));

      // パララックス座標
      vec2 p_uv = uv + u_cam_offset * 0.00018;

      // 多層オーロラ＆星雲リボン
      float n1 = fbm4(vec2(p_uv.x * 2.6 + u_time * 0.035, p_uv.y * 1.9 - u_time * 0.015));
      float n2 = fbm4(vec2(p_uv.x * 4.4 - u_time * 0.025 + 7.3, p_uv.y * 3.1 + n1 * 0.85));
      float curtain = smoothstep(0.36, 0.86, n1) * smoothstep(0.28, 0.80, n2);
      float sky_fade = smoothstep(0.98, 0.15, sky_t) * smoothstep(0.0, 0.18, sky_t);
      col += u_aurora_a.rgb * curtain * sky_fade * 0.36;

      // 縦方向のオーロラカーテン筋
      float wave_y = 0.24 + 0.09 * sin(p_uv.x * 5.2 + u_time * 0.42) + 0.05 * cos(p_uv.x * 11.0 - u_time * 0.28);
      float band = exp(-abs(p_uv.y - wave_y) * 12.0) * (0.45 + 0.55 * n2);
      col += u_aurora_b.rgb * band * 0.32;

      // 星屑レイヤー (控えめで澄んだ星空)
      vec2 star_uv1 = p_uv * vec2(84.0, 48.0);
      vec2 sid1 = floor(star_uv1);
      vec2 sf1 = fract(star_uv1) - 0.5;
      float sr1 = hash21(sid1);
      if (sr1 > 0.968) {
          float tw = 0.45 + 0.55 * sin(u_time * (2.5 + sr1 * 5.0) + sr1 * 40.0);
          float d_star = length(sf1);
          float glow = exp(-d_star * 11.0) * tw * (1.0 - sky_t * 0.78);
          col += mix(vec3(0.85, 0.95, 1.0), u_aurora_b.rgb, 0.4) * glow * 0.72;
      }

      // 遠景の古代神殿ピラミッド＆オベリスク群シルエット
      float horizon = u_water_y;
      float m_x = p_uv.x * 5.5;
      float ridge = 0.085
          + 0.045 * abs(sin(m_x * 1.15 + 0.4))
          + 0.032 * sin(m_x * 2.9 - 1.1)
          + 0.018 * abs(sin(m_x * 6.3 + 2.0));
      float temple_y = horizon - ridge;
      if (uv.y > temple_y && uv.y < horizon + 0.02) {
          float depth_fade = smoothstep(temple_y, temple_y + 0.004, uv.y);
          vec3 sil_col = u_bg_top.rgb * 0.42 + u_bg_horizon.rgb * 0.14;
          col = mix(col, sil_col, depth_fade * 0.88);
          // 遠景遺跡に灯る垂直スリット光
          float cell = floor(p_uv.x * 28.0);
          float cx = fract(p_uv.x * 28.0) - 0.5;
          float h_seed = hash21(vec2(cell, 11.0));
          if (h_seed > 0.74 && uv.y > temple_y + 0.02 && uv.y < horizon - 0.012) {
              float slit = exp(-abs(cx) * 28.0);
              float pulse = 0.4 + 0.6 * sin(u_time * 1.8 + h_seed * 25.0);
              col += u_aurora_a.rgb * slit * pulse * 0.65;
          }
      }

      // 水平線の大気フォグ・ネオンライン
      float h_glow = exp(-abs(uv.y - horizon) * 28.0);
      col += mix(u_aurora_a.rgb, u_aurora_b.rgb, 0.5) * h_glow * 0.34;

      // 微細なサイバー空間座標グリッド (神殿の奥行き演出)
      vec2 grid_p = vec2((p_uv.x - 0.5) * 20.0, (p_uv.y - 0.5) * 11.25);
      vec2 g_line = abs(fract(grid_p - 0.5) - 0.5) / max(fwidth(grid_p), vec2(0.001));
      float g_alpha = 1.0 - min(min(g_line.x, g_line.y), 1.0);
      col += u_aurora_a.rgb * g_alpha * 0.028 * (1.0 - sky_t * 0.5);

      fragColor = vec4(col, 1.0);
  }
GLSL

# 1B. 10,000 GPU フローパーティクル (InstanceBuffer: layout [4, 4, 4], CPU 毎フレーム 0 pack)
PARTICLE_FLOW_VERT = <<~'GLSL'
  #version 330 core
  layout (location = 0) in vec4 in_base;   // x0, y0, phase, flow_speed
  layout (location = 1) in vec4 in_attrib; // size, orbit_r, layer_weight, seed
  layout (location = 2) in vec4 in_color;  // r, g, b, a

  uniform vec2  u_resolution;
  uniform float u_flip_y;
  uniform float u_time;
  uniform vec4  u_view;            // zoom, ox, oy, unused
  uniform vec4  u_orb;             // x, y, charge (0..1), pulse
  uniform vec4  u_leviathan_head;  // x, y, vx, vy
  uniform vec4  u_vortex;          // x, y, radius, strength
  uniform vec4  u_shockwaves[4];   // x, y, radius, strength
  uniform vec4  u_theme_tint;      // r, g, b, theme_mix

  out vec4 v_color;
  out vec2 v_local;

  void main() {
      float t = u_time;
      vec2 base = in_base.xy;
      float phase = in_base.z;
      float spd = in_base.w;
      float sz = in_attrib.x;
      float orbit_r = in_attrib.y;
      float weight = in_attrib.z;
      float seed = in_attrib.w;

      // 多重フローフィールド漂流 (ループで画面内に巡回)
      float drift_x = t * (14.0 + spd * 22.0) + sin(t * 0.55 + phase) * orbit_r;
      float drift_y = cos(t * 0.65 + phase * 1.37) * (orbit_r * 0.65) + sin(base.x * 0.012 + t * 0.4) * 16.0;
      vec2 pos = vec2(
          mod(base.x + drift_x, 1340.0) - 30.0,
          base.y + drift_y
      );

      float energy = 0.0;

      // 1. プレイヤーオーブの磁気吸引＆チャージ渦
      vec2 d_orb = pos - u_orb.xy;
      float dist_orb = length(d_orb);
      float orb_range = 170.0 + u_orb.z * 160.0;
      if (dist_orb < orb_range && dist_orb > 1.0) {
          float k = 1.0 - dist_orb / orb_range;
          float swirl = (0.7 + u_orb.z * 2.4) * k;
          float cs = cos(swirl);
          float sn = sin(swirl);
          vec2 rot_d = vec2(d_orb.x * cs - d_orb.y * sn, d_orb.x * sn + d_orb.y * cs);
          float pull = k * k * (0.35 + u_orb.z * 0.55);
          pos = mix(pos, u_orb.xy + rot_d * (1.0 - pull * 0.72), k);
          energy += k * (0.45 + u_orb.z * 1.1);
      }

      // 2. リヴァイアサン頭部の航跡乱流
      vec2 d_lev = pos - u_leviathan_head.xy;
      float dist_lev = length(d_lev);
      if (dist_lev < 130.0 && dist_lev > 1.0) {
          float k = 1.0 - dist_lev / 130.0;
          vec2 push_dir = normalize(d_lev);
          pos += push_dir * (k * k * 42.0) + u_leviathan_head.zw * (k * 0.08);
          energy += k * 0.75;
      }

      // 3. 重力特異点 (Vortex) による渦巻き吸引
      if (u_vortex.w > 0.01) {
          vec2 d_vor = pos - u_vortex.xy;
          float dist_vor = length(d_vor);
          if (dist_vor < u_vortex.z && dist_vor > 1.0) {
              float k = 1.0 - dist_vor / u_vortex.z;
              float angle = u_vortex.w * k * 4.5 + t * 2.5 * k;
              float cs = cos(angle);
              float sn = sin(angle);
              vec2 r_vec = vec2(d_vor.x * cs - d_vor.y * sn, d_vor.x * sn + d_vor.y * cs);
              pos = u_vortex.xy + r_vec * (1.0 - k * 0.72 * u_vortex.w);
              energy += k * u_vortex.w * 1.2;
          }
      }

      // 4. ショックウェーブ波面による爆発吹き飛ばし
      for (int i = 0; i < 4; i++) {
          vec4 sw = u_shockwaves[i];
          if (sw.w > 0.01) {
              vec2 d_sw = pos - sw.xy;
              float dist_sw = length(d_sw);
              float band = exp(-abs(dist_sw - sw.z) * 0.028) * sw.w;
              if (band > 0.01 && dist_sw > 0.5) {
                  pos += normalize(d_sw) * (band * 58.0);
                  energy += band * 1.4;
              }
          }
      }

      // カメラ変換 (world -> screen)
      vec2 screen_pos = pos * u_view.x + u_view.yz;

      // ビルボード 4 頂点展開 (相互作用時のみサイズと輝きを増幅)
      vec2 corner = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1)) - 0.5;
      float twinkle = 0.72 + 0.28 * sin(t * (2.2 + seed * 3.8) + phase);
      float final_sz = sz * u_view.x * (twinkle + energy * 1.15);
      vec2 v_pos = screen_pos + corner * final_sz;

      vec2 ndc = (v_pos / u_resolution) * 2.0 - 1.0;
      float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
      ndc.y *= flip;
      gl_Position = vec4(ndc, 0.0, 1.0);

      v_local = corner * 2.0;
      vec3 base_rgb = mix(in_color.rgb, u_theme_tint.rgb, u_theme_tint.w * (0.45 + 0.45 * weight));
      vec3 final_rgb = mix(base_rgb, vec3(1.0), clamp(energy * 0.65, 0.0, 0.9));
      float final_a = in_color.a * twinkle * (0.55 + energy * 1.45);
      v_color = vec4(final_rgb, final_a);
  }
GLSL

PARTICLE_FLOW_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_local;
  out vec4 fragColor;

  void main() {
      float d2 = dot(v_local, v_local);
      if (d2 >= 1.0) {
          fragColor = vec4(0.0);
          return;
      }
      float halo = (1.0 - d2);
      halo = halo * halo;
      float core = exp(-d2 * 7.5);
      vec3 rgb = mix(v_color.rgb, vec3(1.0), core * 0.7);
      fragColor = vec4(rgb, v_color.a * (halo * 0.55 + core * 0.75));
  }
GLSL

# 1C. 2D レイマーチング・グローバルイルミネーション (ソフトシャドウ + ゴッドレイ)
#     u_texture = occluder_fbo (r > 0 で遮蔽物)
LIGHTING_2D_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_uv;
  uniform sampler2D u_texture;
  uniform vec4 u_light_pos[12]; // uv_x, uv_y, radius_uv, intensity
  uniform vec4 u_light_col[12]; // r, g, b, volumetric_weight
  uniform float u_water_y;
  out vec4 fragColor;

  void main() {
      vec3 total_light = vec3(0.0);
      vec2 aspect = vec2(1.7777778, 1.0);

      // 水面下 (v_uv.y > u_water_y) は上空の直接ライトを減衰（反射は合成パスで描画）
      float water_atten = (v_uv.y > u_water_y) ? exp(-(v_uv.y - u_water_y) * 9.0) * 0.45 : 1.0;

      for (int i = 0; i < 12; i++) {
          vec4 lp = u_light_pos[i];
          if (lp.w <= 0.001) continue;

          vec4 lc = u_light_col[i];
          vec2 delta_uv = v_uv - lp.xy;
          float dist = length(delta_uv * aspect);
          if (dist >= lp.z) continue;

          float norm_d = dist / max(lp.z, 0.001);
          float falloff = pow(1.0 - norm_d, 2.0);

          // 36ステップ固定レイマーチング (ライト中心 -> 現在ピクセル)
          float occ_sum = 0.0;
          float ray_vis = 0.0;
          const int STEPS = 36;
          for (int s = 1; s <= STEPS; s++) {
              float t = float(s) / float(STEPS);
              vec2 sample_uv = lp.xy + delta_uv * t;
              float occ = texture(u_texture, sample_uv).r;
              // 自身の中心の極近傍は無視し、それ以外の遮蔽を蓄積
              float weight = smoothstep(0.03, 0.14, t);
              occ_sum += occ * weight;
              ray_vis += (1.0 - occ * weight);
          }

          float avg_occ = occ_sum / float(STEPS);
          float shadow = exp(-avg_occ * 11.5);
          float vis_norm = ray_vis / float(STEPS);
          float beam = pow(vis_norm, 2.3) * (0.20 + 0.80 * shadow) * lc.w;

          float direct = falloff * shadow * 0.88;
          float volumetric = pow(1.0 - norm_d, 1.25) * beam * 0.42;
          total_light += lc.rgb * (lp.w * (direct + volumetric));
      }

      fragColor = vec4(total_light * water_atten, 1.0);
  }
GLSL

# 1D. Bloom 高輝度抽出 (Scene + Lighting 合成後の高輝度のみ抽出)
BLOOM_BRIGHT_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_uv;
  uniform sampler2D u_texture;   // scene_fbo
  uniform sampler2D u_light_tex; // light_fbo
  uniform float u_threshold;
  out vec4 fragColor;

  void main() {
      vec3 scene_c = texture(u_texture, v_uv).rgb;
      vec3 light_c = texture(u_light_tex, v_uv).rgb;
      vec3 hdr = scene_c + light_c * 0.58;
      float lum = dot(hdr, vec3(0.2126, 0.7152, 0.0722));
      float soft = clamp((lum - u_threshold) / max(0.35, u_threshold), 0.0, 1.0);
      float contrib = max(lum - u_threshold, 0.0) + soft * soft * 0.25;
      vec3 bright = hdr * (contrib / max(lum, 0.0001));
      fragColor = vec4(bright, 1.0);
  }
GLSL

# 1E. Bloom 9タップ・セパラブルガウスブラー
BLOOM_BLUR_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_uv;
  uniform sampler2D u_texture;
  uniform vec2 u_texel_step;
  out vec4 fragColor;

  void main() {
      vec3 sum = texture(u_texture, v_uv).rgb * 0.227027;
      sum += texture(u_texture, v_uv + u_texel_step * 1.384615).rgb * 0.316216;
      sum += texture(u_texture, v_uv - u_texel_step * 1.384615).rgb * 0.316216;
      sum += texture(u_texture, v_uv + u_texel_step * 3.230769).rgb * 0.070270;
      sum += texture(u_texture, v_uv - u_texel_step * 3.230769).rgb * 0.070270;
      fragColor = vec4(sum, 1.0);
  }
GLSL

# 1F. 最終コンポジット:
#     空間屈折(ショックウェーブ + 重力特異点レンズ) + 色収差 + リアルタイム鏡面水面反射 +
#     水中コースティクス + 2D GI + 多層ブルーム + ACES Filmic トーンマップ
COMPOSITE_FRAG = <<~'GLSL'
  #version 330 core
  in vec4 v_color;
  in vec2 v_uv;
  uniform sampler2D u_texture;   // scene_fbo
  uniform sampler2D u_light_tex; // light_fbo
  uniform sampler2D u_bloom_tex; // bloom_v2
  uniform float u_time;
  uniform float u_water_y;
  uniform vec4 u_vortex;        // uv_x, uv_y, radius_uv, strength
  uniform vec4 u_shockwaves[4]; // uv_x, uv_y, radius_uv, strength
  uniform vec4 u_flags;         // bloom_on, light_on, water_on, distort_on
  uniform vec4 u_water_tint;    // r, g, b, tint_mix
  uniform vec4 u_orb_uv;        // uv_x, uv_y, charge, active
  out vec4 fragColor;

  // ACES Filmic Tonemapping
  vec3 aces_tonemap(vec3 x) {
      const float a = 2.51;
      const float b = 0.03;
      const float c = 2.43;
      const float d = 0.59;
      const float e = 0.14;
      return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
  }

  // 空間歪みベクトル計算 (ショックウェーブ + 重力レンズ)
  vec2 calc_distortion(vec2 uv, out float chroma_amp, out float blackhole_mask) {
      vec2 offset = vec2(0.0);
      chroma_amp = 0.0;
      blackhole_mask = 0.0;
      if (u_flags.w < 0.5) return offset;

      vec2 aspect = vec2(1.7777778, 1.0);

      // ショックウェーブリングの空間屈折
      for (int i = 0; i < 4; i++) {
          vec4 sw = u_shockwaves[i];
          if (sw.w > 0.01) {
              vec2 d = (uv - sw.xy) * aspect;
              float dist = length(d);
              float ring = exp(-pow((dist - sw.z) / 0.055, 2.0)) * sw.w;
              if (dist > 0.001) {
                  vec2 dir = (uv - sw.xy) / dist;
                  offset -= dir * ring * 0.022;
                  chroma_amp += ring * 0.008;
              }
          }
      }

      // 重力特異点ブラックホールレンズ歪み
      if (u_vortex.w > 0.01) {
          vec2 d = (uv - u_vortex.xy) * aspect;
          float dist = length(d);
          float r = max(u_vortex.z, 0.02);
          if (dist < r) {
              float k = 1.0 - dist / r;
              float lens = k * k * u_vortex.w;
              vec2 dir = (dist > 0.001) ? ((uv - u_vortex.xy) / dist) : vec2(0.0);
              vec2 perp = vec2(-dir.y, dir.x);
              offset += (dir * 0.032 + perp * 0.018) * lens;
              chroma_amp += lens * 0.007;
              blackhole_mask = smoothstep(0.038, 0.008, dist) * u_vortex.w;
          }
      }
      return offset;
  }

  vec3 sample_lit_scene(vec2 uv) {
      vec2 suv = clamp(uv, vec2(0.001), vec2(0.999));
      vec3 c = texture(u_texture, suv).rgb;
      if (u_flags.y > 0.5) {
          c += texture(u_light_tex, suv).rgb * 0.85;
      }
      if (u_flags.x > 0.5) {
          c += texture(u_bloom_tex, suv).rgb * 0.72;
      }
      return c;
  }

  void main() {
      vec2 uv = v_uv;
      float chroma_amp = 0.0;
      float bh_mask = 0.0;
      vec2 dist_off = calc_distortion(uv, chroma_amp, bh_mask);

      vec3 color;
      bool in_water = (u_flags.z > 0.5) && (uv.y > u_water_y);

      if (!in_water) {
          // 上空シーン + 色収差サンプリング
          if (chroma_amp > 0.0002) {
              vec2 ca = normalize(dist_off + vec2(0.0001)) * chroma_amp;
              float r = sample_lit_scene(uv + dist_off + ca).r;
              float g = sample_lit_scene(uv + dist_off).g;
              float b = sample_lit_scene(uv + dist_off - ca).b;
              color = vec3(r, g, b);
          } else {
              color = sample_lit_scene(uv + dist_off);
          }
      } else {
          // リアルタイム鏡面反射湖 (リアルな水平さざ波リップル)
          float depth = clamp((uv.y - u_water_y) / max(1.0 - u_water_y, 0.05), 0.0, 1.0);

          // 水平方向の穏やかなさざ波 (縦のジグザグを抑え、水面らしい横長の波紋へ)
          float freq_y = 190.0 + depth * 90.0;
          float w1 = sin(uv.y * freq_y - u_time * 4.2 + sin(uv.x * 14.0 + u_time * 1.1) * 2.2) * (0.0014 + depth * 0.0032);
          float w2 = cos(uv.y * 310.0 + u_time * 5.4 - uv.x * 22.0) * (0.0008 + depth * 0.0016);
          float ry_off = sin(uv.y * 140.0 - u_time * 3.8 + uv.x * 9.0) * (0.0012 + depth * 0.0025);

          // ショックウェーブの水面波紋
          float sw_rip = 0.0;
          for (int i = 0; i < 4; i++) {
              vec4 sw = u_shockwaves[i];
              if (sw.w > 0.01) {
                  float d_sw = length((uv - sw.xy) * vec2(1.7777778, 1.0));
                  sw_rip += sin((d_sw - sw.z) * 95.0) * exp(-abs(d_sw - sw.z) * 18.0) * sw.w * 0.009;
              }
          }

          vec2 ripple = vec2(w1 + w2 + sw_rip, ry_off);
          float ref_y = clamp(u_water_y - (uv.y - u_water_y) * 0.96, 0.002, u_water_y - 0.002);
          vec2 ref_uv = vec2(clamp(uv.x + ripple.x + dist_off.x * 0.7, 0.002, 0.998), ref_y + ripple.y);

          vec3 refl = sample_lit_scene(ref_uv) * mix(0.95, 0.62, depth);
          vec3 bed  = texture(u_texture, clamp(uv + ripple * 0.4, vec2(0.002), vec2(0.998))).rgb;

          // フレネル反射 (水面近くほど鏡面反射が強く、手前ほど深水ティント)
          float fresnel = mix(0.82, 0.42, pow(depth, 0.75));
          vec3 water_base = mix(bed * 0.25 + u_water_tint.rgb * 0.10, refl, fresnel);

          // 水中コースティクス (集光網目模様)
          float c_a = sin(uv.x * 54.0 + u_time * 2.0 + sin(uv.y * 48.0 - u_time * 1.5));
          float c_b = cos(uv.x * 39.0 - u_time * 1.8 + cos(uv.y * 72.0 + u_time * 2.3));
          float caustics = pow(clamp(0.5 + 0.5 * c_a * c_b, 0.0, 1.0), 4.5);
          water_base += u_water_tint.rgb * caustics * (1.0 - depth * 0.55) * 0.22;

          // オーブ位置直下の水面グリッター反射柱
          float dx_orb = abs(uv.x - u_orb_uv.x);
          float glitter = exp(-dx_orb * (28.0 - depth * 12.0)) * (0.45 + 0.55 * sin(uv.y * 190.0 - u_time * 9.0));
          water_base += u_water_tint.rgb * glitter * (0.24 + u_orb_uv.z * 0.45);

          // 水面境界線の輝くリップルエッジ
          float edge = exp(-abs(uv.y - u_water_y) * 280.0);
          water_base += mix(u_water_tint.rgb, vec3(1.0), 0.5) * edge * 0.58;

          color = water_base;
      }

      // 特異点事象の地平面コア (中心のみ暗く引き締める)
      if (bh_mask > 0.01) {
          color = mix(color, vec3(0.02, 0.01, 0.06), bh_mask * 0.92);
      }

      // ACES Filmic トーンマッピング + 露出調整 + 上品なビネット
      color = aces_tonemap(color * 1.12);
      vec2 vig_uv = (uv - 0.5) * vec2(1.15, 1.0);
      float vig = 1.0 - dot(vig_uv, vig_uv) * 0.28;
      color *= clamp(vig, 0.55, 1.0);

      fragColor = vec4(color, 1.0);
  }
GLSL

# ==============================================================================
# 2. テーマ定義 (4つの色彩空間)
# ==============================================================================
THEMES = [
  {
    name: "ABYSS CYAN",
    bg_top: [0.01, 0.02, 0.07, 1.0],
    bg_horizon: [0.02, 0.09, 0.17, 1.0],
    aurora_a: [0.08, 0.80, 1.0, 1.0],
    aurora_b: [0.55, 0.22, 0.95, 1.0],
    water_tint: [0.10, 0.85, 1.0, 1.0],
    orb: [90, 235, 255],
    leviathan_a: [20, 215, 255],
    leviathan_b: [170, 95, 255],
    pillar_edge: [60, 215, 255],
    crystal: [125, 245, 255],
    hud_accent: [90, 235, 255]
  },
  {
    name: "CRIMSON SOLAR",
    bg_top: [0.06, 0.01, 0.04, 1.0],
    bg_horizon: [0.16, 0.04, 0.06, 1.0],
    aurora_a: [1.0, 0.36, 0.14, 1.0],
    aurora_b: [1.0, 0.78, 0.22, 1.0],
    water_tint: [1.0, 0.52, 0.24, 1.0],
    orb: [255, 190, 90],
    leviathan_a: [255, 80, 60],
    leviathan_b: [255, 215, 85],
    pillar_edge: [255, 120, 75],
    crystal: [255, 215, 110],
    hud_accent: [255, 165, 85]
  },
  {
    name: "ETHEREAL VIOLET",
    bg_top: [0.04, 0.01, 0.09, 1.0],
    bg_horizon: [0.12, 0.04, 0.19, 1.0],
    aurora_a: [0.95, 0.28, 0.78, 1.0],
    aurora_b: [0.25, 0.82, 1.0, 1.0],
    water_tint: [0.92, 0.44, 0.98, 1.0],
    orb: [255, 145, 245],
    leviathan_a: [220, 95, 255],
    leviathan_b: [80, 235, 255],
    pillar_edge: [235, 110, 255],
    crystal: [255, 165, 240],
    hud_accent: [240, 140, 255]
  },
  {
    name: "EMERALD AURORA",
    bg_top: [0.01, 0.05, 0.06, 1.0],
    bg_horizon: [0.03, 0.14, 0.11, 1.0],
    aurora_a: [0.15, 0.96, 0.58, 1.0],
    aurora_b: [0.95, 0.85, 0.30, 1.0],
    water_tint: [0.22, 0.95, 0.68, 1.0],
    orb: [125, 255, 195],
    leviathan_a: [45, 245, 165],
    leviathan_b: [255, 225, 95],
    pillar_edge: [70, 245, 175],
    crystal: [160, 255, 200],
    hud_accent: [110, 255, 185]
  }
]

# ==============================================================================
# 3. プロシージャル・オーディオ (Pure Ruby PCM シンセサイザー)
# ==============================================================================
class SoundBank
  attr_reader :muted

  def initialize(silent_boot: false)
    @muted = silent_boot
    @sr = 22050
    @bgm = synthesize_ambient_bgm
    @bgm.looping = true
    @bgm.volume = @muted ? 0.0 : 0.36

    # D マイナーペンタトニックの共鳴クリスタルベル音 (D4, F4, G4, A4, C5, D5)
    notes = [293.66, 349.23, 392.00, 440.00, 523.25, 587.33]
    @bells = []
    i = 0
    while i < notes.length
      s = synthesize_bell(notes[i])
      s.volume = 0.42
      s.max_polyphony = 3
      s.min_interval = 0.05
      @bells << s
      i += 1
    end

    @shock_se = synthesize_shockwave
    @shock_se.volume = 0.55
    @shock_se.max_polyphony = 2

    @charge_se = synthesize_charge
    @charge_se.volume = 0.25
    @charge_se.min_interval = 0.25
  end

  def start_bgm
    @bgm.volume = @muted ? 0.0 : 0.36
    @bgm.play
  end

  def toggle_mute
    @muted = !@muted
    @bgm.volume = @muted ? 0.0 : 0.36
    @muted
  end

  def play_bell(index)
    return if @muted
    b = @bells[index % @bells.length]
    b.play if b
  end

  def play_shockwave
    return if @muted
    @shock_se.play
  end

  def play_charge
    return if @muted
    @charge_se.play
  end

  private

  # 6秒シームレスループのアンビエント・コードパッド & アルペジオ
  def synthesize_ambient_bgm
    dur = 6.0
    total = (@sr * dur).to_i
    samples = Array.new(total, 0.0)
    # 境界で位相が途切れないように基本周波数を 1/6Hz の整数倍へスナップ
    pad_freqs = [
      (73.42 * 6.0).round / 6.0,   # D2
      (110.00 * 6.0).round / 6.0,  # A2
      (146.83 * 6.0).round / 6.0,  # D3
      (174.61 * 6.0).round / 6.0,  # F3
      (220.00 * 6.0).round / 6.0,  # A3
      (261.63 * 6.0).round / 6.0   # C4
    ]
    arp_freqs = [293.66, 349.23, 440.00, 523.25, 587.33, 440.00, 392.00, 349.23]
    step_dur = dur / 12.0 # 0.5秒ごと12ステップ

    i = 0
    while i < total
      t = i.to_f / @sr
      # 温かいパッド和音
      pad = 0.0
      p_idx = 0
      while p_idx < pad_freqs.length
        f = pad_freqs[p_idx]
        lfo = 0.65 + 0.35 * Math.sin(TWO_PI * (1.0 / 6.0) * t + p_idx * 1.1)
        pad += Math.sin(TWO_PI * f * t) * lfo * (p_idx < 2 ? 0.17 : 0.09)
        p_idx += 1
      end

      # ガラスのような淡いアルペジオパルス
      step_pos = t / step_dur
      step_i = step_pos.to_i % arp_freqs.length
      local_t = (step_pos - step_pos.to_i) * step_dur
      af = arp_freqs[step_i]
      env = Math.exp(-local_t * 6.2) * (1.0 - Math.exp(-local_t * 60.0))
      arp = (Math.sin(TWO_PI * af * t) + 0.32 * Math.sin(TWO_PI * af * 2.0 * t)) * env * 0.14

      # 境界ゼロクロス保証の極短フェード (最初と最後 20ms)
      edge_env = 1.0
      if t < 0.02
        edge_env = t / 0.02
      elsif t > dur - 0.02
        edge_env = (dur - t) / 0.02
      end

      samples[i] = clamp_f((pad + arp) * edge_env * 0.85, -0.95, 0.95)
      i += 1
    end
    Sound.from_pcm(samples, channels: 1, sample_rate: @sr, bus: :bgm)
  end

  def synthesize_bell(freq)
    dur = 0.95
    total = (@sr * dur).to_i
    samples = Array.new(total, 0.0)
    i = 0
    while i < total
      t = i.to_f / @sr
      att = t < 0.008 ? (t / 0.008) : 1.0
      env1 = Math.exp(-t * 4.5)
      env2 = Math.exp(-t * 9.5)
      sig = Math.sin(TWO_PI * freq * t) * env1 * 0.55 +
            Math.sin(TWO_PI * freq * 2.0 * t) * env2 * 0.25 +
            Math.sin(TWO_PI * freq * 3.01 * t) * env2 * 0.12
      samples[i] = sig * att * 0.75
      i += 1
    end
    Sound.from_pcm(samples, channels: 1, sample_rate: @sr, bus: :se)
  end

  def synthesize_shockwave
    dur = 0.72
    total = (@sr * dur).to_i
    samples = Array.new(total, 0.0)
    phase = 0.0
    rng = Random.new(42)
    i = 0
    while i < total
      t = i.to_f / @sr
      freq = 32.0 + 135.0 * Math.exp(-t * 10.5)
      phase += TWO_PI * freq / @sr
      sub = Math.sin(phase) * Math.exp(-t * 4.0) * 0.75
      punch = (rng.rand * 2.0 - 1.0) * Math.exp(-t * 16.0) * 0.28
      att = t < 0.005 ? (t / 0.005) : 1.0
      samples[i] = clamp_f((sub + punch) * att, -0.95, 0.95)
      i += 1
    end
    Sound.from_pcm(samples, channels: 1, sample_rate: @sr, bus: :se)
  end

  def synthesize_charge
    dur = 0.35
    total = (@sr * dur).to_i
    samples = Array.new(total, 0.0)
    phase = 0.0
    i = 0
    while i < total
      t = i.to_f / @sr
      freq = 220.0 + t * 520.0
      phase += TWO_PI * freq / @sr
      env = Math.sin(Math::PI * (t / dur))
      samples[i] = (Math.sin(phase) * 0.6 + Math.sin(phase * 1.5) * 0.25) * env * 0.55
      i += 1
    end
    Sound.from_pcm(samples, channels: 1, sample_rate: @sr, bus: :se)
  end
end

# ==============================================================================
# 4. 古代モノリス柱 (2D GI オクルーダー兼ビジュアル描画)
# ==============================================================================
class Pillar
  attr_reader :x, :y, :w, :h, :angle, :user_placed

  def initialize(x, y, w, h, angle: 0.0, rune_seed: 0, user_placed: false)
    @x = x.to_f
    @y = y.to_f
    @w = w.to_f
    @h = h.to_f
    @angle = angle.to_f
    @rune_seed = rune_seed
    @user_placed = user_placed
    @pulse_offset = rune_seed * 0.85
  end

  def draw_occluder
    Window.draw_rect(
      @x - @w * 0.5, @y - @h * 0.5, @w, @h,
      color: [255, 255, 255, 255],
      radius: 4.0,
      angle: @angle,
      pivot: :center,
      z: 10.0
    )
  end

  def draw_visual(time, theme)
    edge = theme[:pillar_edge]
    pulse = 0.5 + 0.5 * Math.sin(time * 2.1 + @pulse_offset)
    border_a = (135 + pulse * 100).to_i

    # 石柱本体 (黒曜石調 + ネオンリムライト)
    Window.draw_rect(
      @x - @w * 0.5, @y - @h * 0.5, @w, @h,
      color: [7, 10, 18, 252],
      radius: 4.0,
      border_width: 2.0,
      border_color: [edge[0], edge[1], edge[2], border_a],
      angle: @angle,
      pivot: :center,
      z: 15.0
    )

    # 内部の古代ルーンライン & 上下装飾ダイヤ (柱の角度に沿ってローカル軸変換)
    rad = @angle * DEG_RAD
    cs = Math.cos(rad)
    sn = Math.sin(rad)

    inner_h = @h * 0.36
    x1 = @x - (-sn) * inner_h
    y1 = @y - cs * inner_h
    x2 = @x + (-sn) * inner_h
    y2 = @y + cs * inner_h
    Window.draw_line(
      x1, y1, x2, y2,
      color: [edge[0], edge[1], edge[2], (110 + pulse * 130).to_i],
      width: 2.4,
      cap: :round,
      z: 15.5
    )

    # 上下端のルーンノード
    cap_h = @h * 0.38
    Window.draw_circle(@x - (-sn) * cap_h, @y - cs * cap_h, 3.2, color: [edge[0], edge[1], edge[2], 190], z: 15.8)
    Window.draw_circle(@x + (-sn) * cap_h, @y + cs * cap_h, 3.2, color: [edge[0], edge[1], edge[2], 190], z: 15.8)

    # 中央に光るクリスタルノード (外周グロー + コア)
    node_r = [@w, @h].min * 0.22
    node_r = 4.5 if node_r < 4.5
    node_r = 10.0 if node_r > 10.0
    Window.draw_circle(
      @x, @y, node_r * 1.9,
      color: [edge[0], edge[1], edge[2], (60 + pulse * 70).to_i],
      blend: :add,
      z: 15.9
    )
    Window.draw_circle(
      @x, @y, node_r,
      color: [edge[0], edge[1], edge[2], (160 + pulse * 95).to_i],
      border_width: 1.4,
      border_color: [255, 255, 255, 210],
      z: 16.0
    )
  end
end

# ==============================================================================
# 5. 共鳴クリスタル & プラズマアーク
# ==============================================================================
class ResonanceCrystal
  attr_accessor :x, :y, :charge, :is_target, :cooldown
  attr_reader :note_index, :base_x, :base_y

  def initialize(x, y, note_index)
    @base_x = x.to_f
    @base_y = y.to_f
    @x = @base_x
    @y = @base_y
    @note_index = note_index
    @charge = 0.25
    @flash = 0.0
    @cooldown = 0.0
    @is_target = false
    @phase = note_index * 1.15
  end

  def trigger(power = 1.0, sound_bank = nil)
    @flash = 1.0
    @charge = clamp_f(@charge + power * 0.75, 0.0, 1.0)
    if @cooldown <= 0.0
      sound_bank.play_bell(@note_index) if sound_bank
      @cooldown = 0.28
    end
  end

  def update(time)
    @x = @base_x + Math.sin(time * 1.1 + @phase) * 8.0
    @y = @base_y + Math.cos(time * 1.45 + @phase * 0.7) * 11.0
    @flash = clamp_f(@flash - DT * 2.2, 0.0, 1.0)
    @charge = clamp_f(@charge - DT * 0.14, 0.18, 1.0)
    @cooldown -= DT if @cooldown > 0.0
  end

  def draw(time, theme)
    c = theme[:crystal]
    pulse = 0.5 + 0.5 * Math.sin(time * 3.6 + @phase)
    glow_r = 26.0 + @flash * 28.0 + (@is_target ? 12.0 * pulse : 0.0)
    glow_a = clamp_i((28 + @flash * 120 + (@is_target ? 48 : 0)).to_i, 0, 255)

    ring_col = @is_target ? [255, 225, 95] : c

    # 控えめな外周オーラ (本体ファセットを白飛びさせない)
    Window.draw_circle(@x, @y, glow_r, color: [ring_col[0], ring_col[1], ring_col[2], glow_a], blend: :add, z: 22.0)

    # ターゲット時の照準回転リング
    if @is_target
      Window.draw_circle(
        @x, @y, 33.0 + pulse * 6.0,
        border_width: 2.2,
        border_color: [255, 235, 110, 235],
        z: 23.0
      )
    end

    # 八面体ダイヤ（4三角形ファセット + クッキリしたエッジ光）
    ang = Math.sin(time * 1.4 + @phase) * 0.16
    r_x = 15.0 + @flash * 4.5
    r_y = 25.0 + @flash * 6.5
    cs = Math.cos(ang)
    sn = Math.sin(ang)

    top_x = @x + sn * r_y
    top_y = @y - cs * r_y
    bot_x = @x - sn * r_y
    bot_y = @y + cs * r_y
    lft_x = @x - cs * r_x
    lft_y = @y - sn * r_x
    rgt_x = @x + cs * r_x
    rgt_y = @y + sn * r_x

    col_lt = [clamp_i(ring_col[0] + 55, 0, 255), clamp_i(ring_col[1] + 55, 0, 255), clamp_i(ring_col[2] + 55, 0, 255), 240]
    col_md = [ring_col[0], ring_col[1], ring_col[2], 235]
    col_dk = [clamp_i((ring_col[0] * 0.35).to_i, 0, 255), clamp_i((ring_col[1] * 0.35).to_i, 0, 255), clamp_i((ring_col[2] * 0.35).to_i, 0, 255), 245]
    Window.draw_triangle(@x, @y, top_x, top_y, lft_x, lft_y, color: col_lt, z: 24.0)
    Window.draw_triangle(@x, @y, top_x, top_y, rgt_x, rgt_y, color: [245, 252, 255, 230], z: 24.0)
    Window.draw_triangle(@x, @y, bot_x, bot_y, lft_x, lft_y, color: col_dk, z: 24.0)
    Window.draw_triangle(@x, @y, bot_x, bot_y, rgt_x, rgt_y, color: col_md, z: 24.0)

    # シャープな輪郭エッジ
    edge_col = [255, 255, 255, 210]
    Window.draw_line(top_x, top_y, lft_x, lft_y, color: edge_col, width: 1.5, cap: :round, z: 24.5)
    Window.draw_line(top_x, top_y, rgt_x, rgt_y, color: edge_col, width: 1.5, cap: :round, z: 24.5)
    Window.draw_line(bot_x, bot_y, lft_x, lft_y, color: [ring_col[0], ring_col[1], ring_col[2], 220], width: 1.5, cap: :round, z: 24.5)
    Window.draw_line(bot_x, bot_y, rgt_x, rgt_y, color: [ring_col[0], ring_col[1], ring_col[2], 220], width: 1.5, cap: :round, z: 24.5)

    # 上下の浮遊衛星シャード
    sat_off = 31.0 + Math.sin(time * 2.8 + @phase) * 3.5
    Window.draw_circle(@x + sn * sat_off, @y - cs * sat_off, 2.8, color: [255, 255, 255, 215], blend: :add, z: 25.0)
    Window.draw_circle(@x - sn * sat_off, @y + cs * sat_off, 2.4, color: [ring_col[0], ring_col[1], ring_col[2], 200], blend: :add, z: 25.0)

    # コアハイライト
    Window.draw_circle(@x, @y, 4.0 + @flash * 3.0, color: [255, 255, 255, 245], blend: :add, z: 25.0)
  end
end

# ==============================================================================
# 6. ショックウェーブ管理 (最大 4 同時)
# ==============================================================================
class Shockwave
  attr_accessor :x, :y, :radius, :max_radius, :strength, :active

  def initialize
    @x = 0.0
    @y = 0.0
    @radius = 0.0
    @max_radius = 480.0
    @strength = 0.0
    @active = false
  end

  def spawn(x, y, power = 1.0)
    @x = x.to_f
    @y = y.to_f
    @radius = 8.0
    @max_radius = 360.0 + power * 240.0
    @strength = 0.65 + power * 0.65
    @speed = 460.0 + power * 220.0
    @active = true
  end

  def update
    return unless @active
    @radius += @speed * DT
    progress = @radius / @max_radius
    if progress >= 1.0
      @active = false
      @strength = 0.0
    else
      @strength = (1.0 - progress) * (1.0 - progress) * 1.15
    end
  end

  def draw(theme)
    return unless @active
    c = theme[:orb]
    alpha = clamp_i((@strength * 190.0).to_i, 0, 255)
    Window.draw_circle(
      @x, @y, @radius,
      border_width: 3.5 + @strength * 4.0,
      border_color: [c[0], c[1], c[2], alpha],
      blend: :add,
      z: 42.0
    )
    if @radius > 24.0
      Window.draw_circle(
        @x, @y, @radius * 0.92,
        border_width: 1.5,
        border_color: [255, 255, 255, (alpha * 0.6).to_i],
        blend: :add,
        z: 42.1
      )
    end
  end
end

# ==============================================================================
# 7. NEON LEVIATHAN (光の龍: 24節 Bone + 二重 set_ribbon Mesh + FABRIK IK 触角 + ヒレ)
# ==============================================================================
class NeonLeviathan
  SEG_COUNT = 26
  SEG_LEN   = 20.0

  attr_reader :head_x, :head_y, :vx, :vy, :points, :surge

  def initialize(skin_tex, fin_tex)
    @head_x = 380.0
    @head_y = 250.0
    @vx = 180.0
    @vy = 20.0
    @heading = 0.0
    @surge = 0.0
    @swim_phase = 0.0

    # 26 節の位置履歴バッファ (堂々たる巨龍プロファイル: 最大幅 58px)
    @points = []
    @widths_outer = []
    @widths_inner = []
    i = 0
    while i < SEG_COUNT
      t = i.to_f / (SEG_COUNT - 1)
      @points << [@head_x - i * SEG_LEN, @head_y]
      w = if i == 0
            34.0
          elsif i <= 4
            lerp_f(38.0, 58.0, i.to_f / 4.0)
          else
            tail_t = (i - 4).to_f / (SEG_COUNT - 5)
            58.0 * ((1.0 - tail_t * 0.88) ** 1.15)
          end
      @widths_outer << w
      @widths_inner << (w * 0.42)
      i += 1
    end

    # 外層メッシュ (濃紺黒曜石+サイバー鱗) + 内層発光コアメッシュ (加算合成)
    @body_mesh = Mesh.grid(skin_tex, cols: SEG_COUNT - 1, rows: 2, blend: :alpha)
    @core_mesh = Mesh.grid(skin_tex, cols: SEG_COUNT - 1, rows: 2, blend: :add)

    # 左右の大型胸ビレ + 中型腹ビレ + 尾ビレ (Mesh.grid + deform 羽ばたき)
    @fin_left_mesh   = Mesh.grid(fin_tex, cols: 8, rows: 4, width: 152, height: 76, blend: :add)
    @fin_right_mesh  = Mesh.grid(fin_tex, cols: 8, rows: 4, width: 152, height: 76, blend: :add)
    @pelvic_l_mesh   = Mesh.grid(fin_tex, cols: 8, rows: 4, width: 98, height: 50, blend: :add)
    @pelvic_r_mesh   = Mesh.grid(fin_tex, cols: 8, rows: 4, width: 98, height: 50, blend: :add)
    @tail_fin_mesh   = Mesh.grid(fin_tex, cols: 8, rows: 4, width: 120, height: 60, blend: :add)

    # 頭部の左右 10 関節 FABRIK IK 触角 (前方外側に広げて優雅にうねる龍髭)
    @feelers_l = Bone.chain(nil, Array.new(10, 15.0), x: @head_x, y: @head_y, angle: -45.0, name_prefix: "FeelerL")
    @feelers_r = Bone.chain(nil, Array.new(10, 15.0), x: @head_x, y: @head_y, angle: 45.0, name_prefix: "FeelerR")
    @feeler_l_tx = @head_x + 30.0
    @feeler_l_ty = @head_y - 105.0
    @feeler_r_tx = @head_x + 30.0
    @feeler_r_ty = @head_y + 105.0

    # AI ステアリング目標
    @orbit_angle = 0.0
    @target_x = 640.0
    @target_y = 250.0
  end

  def trigger_surge(strength = 1.0)
    @surge = clamp_f(@surge + strength * 0.9, 0.0, 1.5)
  end

  def update(time, orb_x, orb_y, vortex_active, vortex_x, vortex_y, crystals, theme)
    @surge = clamp_f(@surge - DT * 0.65, 0.0, 1.5)

    # 1. ステアリングターゲット決定 (上空領域 95..445 を優美に遊泳)
    if vortex_active
      # 特異点に巻き込まれつつ周囲を高速旋回
      @orbit_angle += DT * 2.6
      @target_x = vortex_x + Math.cos(@orbit_angle) * 95.0
      @target_y = clamp_f(vortex_y + Math.sin(@orbit_angle) * 75.0, 80.0, WATER_Y - 55.0)
    else
      # オーブ周辺を大きな8の字 & 周回軌道で優雅に泳ぐ
      @orbit_angle += DT * (0.85 + @surge * 0.5)
      ox = clamp_f(orb_x, 220.0, WIDTH - 220.0)
      oy = clamp_f(orb_y, 130.0, WATER_Y - 80.0)
      @target_x = ox + Math.cos(@orbit_angle) * 260.0 + Math.sin(@orbit_angle * 0.5) * 90.0
      @target_y = clamp_f(oy + Math.sin(@orbit_angle * 1.4) * 115.0, 95.0, WATER_Y - 62.0)
    end

    # 目標方向へ滑らかに操舵
    dx = @target_x - @head_x
    dy = @target_y - @head_y
    desired_ang = Math.atan2(dy, dx)
    diff = wrap_angle_rad(desired_ang - @heading)
    turn_rate = (2.6 + @surge * 1.5) * DT
    @heading = wrap_angle_rad(@heading + clamp_f(diff, -turn_rate, turn_rate))

    # 水面境界ソフト回避
    if @head_y > WATER_Y - 75.0 && Math.sin(@heading) > 0.0
      @heading = wrap_angle_rad(@heading - 3.2 * DT)
    elsif @head_y < 90.0 && Math.sin(@heading) < 0.0
      @heading = wrap_angle_rad(@heading + 3.2 * DT)
    end

    speed = 205.0 + @surge * 175.0 + (vortex_active ? 85.0 : 0.0)
    @vx = Math.cos(@heading) * speed
    @vy = Math.sin(@heading) * speed
    @head_x += @vx * DT
    @head_y += @vy * DT
    @head_x = clamp_f(@head_x, 70.0, WIDTH - 70.0)
    @head_y = clamp_f(@head_y, 70.0, WATER_Y - 45.0)

    @swim_phase += DT * (6.2 + @surge * 4.5)

    # 2. 24 節のスパイン追従 + 泳ぎうねり波動
    @points[0][0] = @head_x
    @points[0][1] = @head_y

    i = 1
    while i < SEG_COUNT
      px = @points[i - 1][0]
      py = @points[i - 1][1]
      cx = @points[i][0]
      cy = @points[i][1]

      vx_seg = cx - px
      vy_seg = cy - py
      dist = Math.sqrt(vx_seg * vx_seg + vy_seg * vy_seg)
      dist = 0.001 if dist < 0.001
      nx = vx_seg / dist
      ny = vy_seg / dist

      # 進行方向に直交する正弦波うねり
      perp_x = -ny
      perp_y = nx
      wave_amp = (1.6 + (i.to_f / SEG_COUNT) * 3.8) * (0.65 + @surge * 0.4)
      wave = Math.sin(@swim_phase - i * 0.42) * wave_amp * DT * 10.0

      tx = px + nx * SEG_LEN + perp_x * wave
      ty = py + ny * SEG_LEN + perp_y * wave

      # 再正規化して節間距離を正確に保つ
      rx = tx - px
      ry = ty - py
      rlen = Math.sqrt(rx * rx + ry * ry)
      rlen = 0.001 if rlen < 0.001
      @points[i][0] = px + (rx / rlen) * SEG_LEN
      @points[i][1] = py + (ry / rlen) * SEG_LEN
      i += 1
    end

    # 3. 2層のボディリボンメッシュを更新 & 生体発光カラーウェーブを焼き込む
    @body_mesh.set_ribbon(@points, width: @widths_outer, fade: false, taper: false)
    @core_mesh.set_ribbon(@points, width: @widths_inner, fade: false, taper: false)

    ca = theme[:leviathan_a]
    cb = theme[:leviathan_b]
    surge_boost = @surge

    @body_mesh.deform do |v|
      u_ratio = v.col.to_f / (SEG_COUNT - 1)
      row_edge = (v.row == 1) ? 1.0 : 0.35
      pulse = 0.5 + 0.5 * Math.sin(time * 5.2 - u_ratio * 9.5)
      mix_t = clamp_f(pulse * 0.75 + u_ratio * 0.25, 0.0, 1.0)
      v.r = clamp_f(lerp_f(ca[0], cb[0], mix_t) * row_edge + surge_boost * 80.0, 0.0, 255.0)
      v.g = clamp_f(lerp_f(ca[1], cb[1], mix_t) * row_edge + surge_boost * 80.0, 0.0, 255.0)
      v.b = clamp_f(lerp_f(ca[2], cb[2], mix_t) * row_edge + surge_boost * 80.0, 0.0, 255.0)
      v.alpha = 235.0
    end

    @core_mesh.deform do |v|
      u_ratio = v.col.to_f / (SEG_COUNT - 1)
      # 頭から尾へ走る高輝度エネルギーパルス
      pulse = 0.5 + 0.5 * Math.sin(time * 7.5 - u_ratio * 12.0)
      center_mask = (v.row == 1) ? 1.0 : 0.15
      v.r = clamp_f(lerp_f(ca[0], 255.0, pulse * 0.65), 0.0, 255.0)
      v.g = clamp_f(lerp_f(ca[1], 255.0, pulse * 0.65), 0.0, 255.0)
      v.b = clamp_f(lerp_f(ca[2], 255.0, pulse * 0.65), 0.0, 255.0)
      v.alpha = (150.0 + pulse * 105.0) * center_mask * (1.0 - u_ratio * 0.35)
    end

    # 4. 左右の翼状エネルギーヒレ & 尾ビレを deform で波打ち変形
    deform_fin(@fin_left_mesh, time, 1.0, ca, cb, 38.0)
    deform_fin(@fin_right_mesh, time, -1.0, ca, cb, 38.0)
    deform_fin(@pelvic_l_mesh, time + 1.2, 1.0, cb, ca, 25.0)
    deform_fin(@pelvic_r_mesh, time + 1.2, -1.0, cb, ca, 25.0)
    deform_fin(@tail_fin_mesh, time * 1.3, 1.0, cb, ca, 30.0)

    # 5. FABRIK IK で左右の 10 関節触角を解決 (前方外側に大きく弧を描く)
    hx_cos = Math.cos(@heading)
    hx_sin = Math.sin(@heading)
    perp_x = -hx_sin
    perp_y = hx_cos

    root_lx = @head_x + hx_cos * 16.0 + perp_x * 11.0
    root_ly = @head_y + hx_sin * 16.0 + perp_y * 11.0
    root_rx = @head_x + hx_cos * 16.0 - perp_x * 11.0
    root_ry = @head_y + hx_sin * 16.0 - perp_y * 11.0

    sway_l = Math.sin(time * 4.2) * 38.0
    sway_r = Math.sin(time * 4.2 + 1.8) * 38.0
    fwd_wave = Math.cos(time * 3.1) * 24.0
    goal_lx = root_lx + hx_cos * (34.0 + fwd_wave) + perp_x * (112.0 + sway_l)
    goal_ly = root_ly + hx_sin * (34.0 + fwd_wave) + perp_y * (112.0 + sway_l)
    goal_rx = root_rx + hx_cos * (34.0 - fwd_wave) - perp_x * (112.0 + sway_r)
    goal_ry = root_ry + hx_sin * (34.0 - fwd_wave) - perp_y * (112.0 + sway_r)

    @feeler_l_tx += (goal_lx - @feeler_l_tx) * 0.16
    @feeler_l_ty += (goal_ly - @feeler_l_ty) * 0.16
    @feeler_r_tx += (goal_rx - @feeler_r_tx) * 0.16
    @feeler_r_ty += (goal_ry - @feeler_r_ty) * 0.16

    @feelers_l[0].x = root_lx
    @feelers_l[0].y = root_ly
    Bone.solve_fabrik(@feelers_l, @feeler_l_tx, @feeler_l_ty, iterations: 4)

    @feelers_r[0].x = root_rx
    @feelers_r[0].y = root_ry
    Bone.solve_fabrik(@feelers_r, @feeler_r_tx, @feeler_r_ty, iterations: 4)

    # 6. 近接クリスタル共鳴反応
    i = 0
    while i < crystals.length
      cr = crystals[i]
      cdx = cr.x - @head_x
      cdy = cr.y - @head_y
      if cdx * cdx + cdy * cdy < 4400.0
        cr.trigger(0.45, nil)
      end
      i += 1
    end
  end

  def draw_occluder
    # 体の主要節を半透明遮蔽物として描画し、自身の発光と外部ライトにソフトなセルフシャドウを落とす
    i = 0
    while i < SEG_COUNT
      p = @points[i]
      r = @widths_outer[i] * 0.36
      Window.draw_circle(p[0], p[1], r, color: [165, 165, 165, 255], z: 10.0)
      i += 2
    end
  end

  def draw_visual(time, orb_x, orb_y, theme)
    ca = theme[:leviathan_a]
    cb = theme[:leviathan_b]

    # 1. 左右の胸ビレ (第4節) & 腹ビレ (第11節) & 尾ビレ
    p3 = @points[4]
    p5 = @points[6]
    fin_ang = Math.atan2(p3[1] - p5[1], p3[0] - p5[0]) * RAD_DEG
    flap = Math.sin(@swim_phase * 1.1) * 14.0
    @fin_left_mesh.draw(p3[0], p3[1], anchor: :center_left, pivot: :center_left, angle: fin_ang - 128.0 + flap, z: 27.0)
    @fin_right_mesh.draw(p3[0], p3[1], anchor: :center_left, pivot: :center_left, angle: fin_ang + 128.0 - flap, scale_y: -1.0, z: 27.0)

    p10 = @points[11]
    p12 = @points[13]
    p_ang = Math.atan2(p10[1] - p12[1], p10[0] - p12[0]) * RAD_DEG
    @pelvic_l_mesh.draw(p10[0], p10[1], anchor: :center_left, pivot: :center_left, angle: p_ang - 135.0 - flap * 0.7, z: 27.2)
    @pelvic_r_mesh.draw(p10[0], p10[1], anchor: :center_left, pivot: :center_left, angle: p_ang + 135.0 + flap * 0.7, scale_y: -1.0, z: 27.2)

    pt_prev = @points[SEG_COUNT - 3]
    pt_end  = @points[SEG_COUNT - 1]
    tail_ang = Math.atan2(pt_end[1] - pt_prev[1], pt_end[0] - pt_prev[0]) * RAD_DEG
    @tail_fin_mesh.draw(pt_end[0], pt_end[1], anchor: :center_left, pivot: :center_left, angle: tail_ang, z: 27.5)

    # 2. FABRIK IK 10関節触角 (Bone.draw_chain)
    Bone.draw_chain(
      @feelers_l,
      start_width: 9.5, end_width: 2.2,
      color: [ca[0], ca[1], ca[2], 220],
      core_ratio: 0.45,
      core_color: [255, 255, 255, 245],
      joint_color: [cb[0], cb[1], cb[2], 235],
      z: 28.0
    )
    Bone.draw_chain(
      @feelers_r,
      start_width: 9.5, end_width: 2.2,
      color: [ca[0], ca[1], ca[2], 220],
      core_ratio: 0.45,
      core_color: [255, 255, 255, 245],
      joint_color: [cb[0], cb[1], cb[2], 235],
      z: 28.0
    )

    # 3. 2層ボディメッシュ (外皮 + 加算発光コア)
    @body_mesh.draw(z: 29.0)
    @core_mesh.draw(z: 30.0)

    # 背骨に沿った繊細な発光エネルギー節ノード
    i = 1
    while i < SEG_COUNT - 1
      p = @points[i]
      pulse = 0.5 + 0.5 * Math.sin(time * 6.5 - i * 0.5)
      r = (1.0 - i.to_f / SEG_COUNT) * 4.2 + 1.2
      Window.draw_circle(p[0], p[1], r * 1.5, color: [cb[0], cb[1], cb[2], (70 + pulse * 80).to_i], blend: :add, z: 30.5)
      Window.draw_circle(p[0], p[1], r * 0.6, color: [255, 255, 255, (125 + pulse * 75).to_i], blend: :add, z: 30.6)
      i += 2
    end

    # 4. 龍の頭部造形 (装甲・二重角・視線追従する双眼)
    hx_cos = Math.cos(@heading)
    hx_sin = Math.sin(@heading)
    px = -hx_sin
    py = hx_cos

    nose_x = @head_x + hx_cos * 34.0
    nose_y = @head_y + hx_sin * 34.0
    cheek_lx = @head_x - hx_cos * 10.0 + px * 22.0
    cheek_ly = @head_y - hx_sin * 10.0 + py * 22.0
    cheek_rx = @head_x - hx_cos * 10.0 - px * 22.0
    cheek_ry = @head_y - hx_sin * 10.0 - py * 22.0
    horn_lx = @head_x - hx_cos * 34.0 + px * 32.0
    horn_ly = @head_y - hx_sin * 34.0 + py * 32.0
    horn_rx = @head_x - hx_cos * 34.0 - px * 32.0
    horn_ry = @head_y - hx_sin * 34.0 - py * 32.0

    # ヘッド装甲 & 二重ドラゴンホーン
    Window.draw_triangle(nose_x, nose_y, cheek_lx, cheek_ly, cheek_rx, cheek_ry, color: [10, 16, 34, 250], z: 31.0)
    Window.draw_line(nose_x, nose_y, cheek_lx, cheek_ly, color: [ca[0], ca[1], ca[2], 255], width: 3.2, cap: :round, z: 31.5)
    Window.draw_line(nose_x, nose_y, cheek_rx, cheek_ry, color: [ca[0], ca[1], ca[2], 255], width: 3.2, cap: :round, z: 31.5)
    Window.draw_line(cheek_lx, cheek_ly, horn_lx, horn_ly, color: [cb[0], cb[1], cb[2], 245], width: 4.0, cap: :round, z: 31.5)
    Window.draw_line(cheek_rx, cheek_ry, horn_rx, horn_ry, color: [cb[0], cb[1], cb[2], 245], width: 4.0, cap: :round, z: 31.5)
    Window.draw_line(cheek_lx, cheek_ly, horn_lx, horn_ly, color: [255, 255, 255, 210], width: 1.4, cap: :round, z: 31.6)
    Window.draw_line(cheek_rx, cheek_ry, horn_rx, horn_ry, color: [255, 255, 255, 210], width: 1.4, cap: :round, z: 31.6)

    # 額のコアクリスタル
    Window.draw_circle(@head_x + hx_cos * 8.0, @head_y + hx_sin * 8.0, 13.0, color: [cb[0], cb[1], cb[2], 155], blend: :add, z: 32.0)
    Window.draw_circle(@head_x + hx_cos * 8.0, @head_y + hx_sin * 8.0, 5.5, color: [255, 255, 255, 255], blend: :add, z: 32.1)

    # オーブを見つめる発光アイ
    eye_dx = orb_x - @head_x
    eye_dy = orb_y - @head_y
    ed = Math.sqrt(eye_dx * eye_dx + eye_dy * eye_dy)
    ex_off = ed > 1.0 ? (eye_dx / ed * 2.0) : 0.0
    ey_off = ed > 1.0 ? (eye_dy / ed * 2.0) : 0.0

    el_x = @head_x + hx_cos * 6.0 + px * 10.5
    el_y = @head_y + hx_sin * 6.0 + py * 10.5
    er_x = @head_x + hx_cos * 6.0 - px * 10.5
    er_y = @head_y + hx_sin * 6.0 - py * 10.5
    Window.draw_circle(el_x + ex_off, el_y + ey_off, 4.2, color: [255, 255, 210, 255], blend: :add, z: 32.5)
    Window.draw_circle(er_x + ex_off, er_y + ey_off, 4.2, color: [255, 255, 210, 255], blend: :add, z: 32.5)
  end

  def mid_pos
    @points[12]
  end

  def tail_pos
    @points[SEG_COUNT - 1]
  end

  private

  def deform_fin(mesh, time, sign, ca, cb, half_h)
    mesh.deform do |v|
      u_r = v.col.to_f / 8.0
      v_r = (v.row.to_f / 4.0) - 0.5
      wave = Math.sin(time * 5.8 * sign - u_r * 4.2) * (13.0 * u_r)
      taper = (1.0 - u_r * 0.40)
      v.x = v.base_x + u_r * 14.0
      v.y = (v.base_y - half_h) * taper + half_h + wave + v_r * u_r * 18.0
      glow = 0.5 + 0.5 * Math.cos(u_r * 3.14 - time * 3.5)
      v.r = lerp_f(ca[0], cb[0], u_r)
      v.g = lerp_f(ca[1], cb[1], u_r)
      v.b = lerp_f(ca[2], cb[2], u_r)
      v.alpha = (230.0 * (1.0 - u_r * 0.65)) * (0.72 + 0.28 * glow)
    end
  end
end

# ==============================================================================
# 8. プレイヤー・光のオーブ (魔法陣チャージ + 軌跡リボン)
# ==============================================================================
class PlayerOrb
  TRAIL_LEN = 21

  attr_accessor :x, :y, :vx, :vy, :charge, :charging, :pulse

  def initialize(ribbon_tex)
    @x = 640.0
    @y = 320.0
    @vx = 0.0
    @vy = 0.0
    @charge = 0.0
    @charging = false
    @pulse = 0.0

    @trail = []
    @trail_widths = []
    i = 0
    while i < TRAIL_LEN
      @trail << [@x, @y]
      @trail_widths << (20.0 * (1.0 - i.to_f / (TRAIL_LEN - 1)))
      i += 1
    end
    @trail_mesh = Mesh.grid(ribbon_tex, cols: TRAIL_LEN - 1, rows: 2, blend: :add)
  end

  def update(target_x, target_y, key_dx, key_dy, charging, time, theme)
    prev_x = @x
    prev_y = @y

    if key_dx.abs > 0.01 || key_dy.abs > 0.01
      @x += key_dx * 420.0 * DT
      @y += key_dy * 420.0 * DT
    else
      @x += (target_x - @x) * 0.19
      @y += (target_y - @y) * 0.19
    end

    @x = clamp_f(@x, 32.0, WIDTH - 32.0)
    @y = clamp_f(@y, 32.0, WATER_Y - 18.0)

    @vx = (@x - prev_x) / DT
    @vy = (@y - prev_y) / DT

    @charging = charging
    if @charging
      @charge = clamp_f(@charge + DT * 0.85, 0.0, 1.0)
    end
    @pulse = clamp_f(@pulse - DT * 2.5, 0.0, 1.0)

    # 軌跡シフト (GCゼロの配列座標上書き)
    i = TRAIL_LEN - 1
    while i > 0
      @trail[i][0] = @trail[i - 1][0]
      @trail[i][1] = @trail[i - 1][1]
      i -= 1
    end
    @trail[0][0] = @x
    @trail[0][1] = @y

    @trail_mesh.set_ribbon(@trail, width: @trail_widths, fade: true, start_alpha: 210.0, end_alpha: 0.0)
    oc = theme[:orb]
    @trail_mesh.deform do |v|
      v.r = oc[0]
      v.g = oc[1]
      v.b = oc[2]
    end
  end

  def release_charge!
    power = clamp_f(0.35 + @charge * 0.85, 0.35, 1.2)
    @charge = 0.0
    @charging = false
    @pulse = 1.0
    power
  end

  def draw(time, theme)
    oc = theme[:orb]
    @trail_mesh.draw(z: 34.0)

    core_r = 9.0 + @charge * 6.5 + @pulse * 8.0
    aura_r = 26.0 + @charge * 28.0 + @pulse * 22.0 + Math.sin(time * 6.0) * 3.0

    # 外層オーラ
    Window.draw_circle(@x, @y, aura_r, color: [oc[0], oc[1], oc[2], 95], blend: :add, z: 35.0)

    # チャージ中の回転ルーン魔法陣
    if @charge > 0.02
      ring_r = 26.0 + (1.0 - @charge) * 36.0
      ring_a = clamp_i((90 + @charge * 165).to_i, 0, 255)
      Window.draw_circle(@x, @y, ring_r, border_width: 2.0, border_color: [oc[0], oc[1], oc[2], ring_a], blend: :add, z: 35.5)

      # 回転する魔法陣の4点星紋
      base_a = time * (3.5 + @charge * 7.0)
      k = 0
      while k < 4
        a1 = base_a + k * (Math::PI * 0.5)
        a2 = a1 + Math::PI * 0.5
        Window.draw_line(
          @x + Math.cos(a1) * ring_r, @y + Math.sin(a1) * ring_r,
          @x + Math.cos(a2) * ring_r, @y + Math.sin(a2) * ring_r,
          color: [255, 255, 255, ring_a], width: 1.6, blend: :add, z: 35.6
        )
        k += 1
      end
    end

    # オーブ本体 & 白芯コア
    Window.draw_circle(@x, @y, core_r * 1.4, color: [oc[0], oc[1], oc[2], 220], blend: :add, z: 36.0)
    Window.draw_circle(@x, @y, core_r * 0.68, color: [255, 255, 255, 255], blend: :add, z: 36.1)
  end
end

# ==============================================================================
# 9. プロシージャル・テクスチャ生成 & リソース初期化 (Window.loop の外側)
# ==============================================================================
def build_procedural_textures
  # 1. 白 4x4 ベーステクスチャ (フルスクリーンシェーダー描画用)
  white_tex = Image.new(4, 4)
  Image.render_to(white_tex) do
    Window.clear([255, 255, 255, 255])
  end

  # 2. リヴァイアサン・サイバー鱗スキンテクスチャ (256 x 64)
  # 濃い黒曜石外縁により、光とブルームの中でも龍の輪郭と鱗模様が鮮烈に浮き立つ
  leviathan_skin = Image.new(256, 64)
  Image.render_to(leviathan_skin) do
    Window.clear([0, 0, 0, 0])
    Window.draw_rect(0, 4, 256, 56, radius: 14, color: [24, 38, 64, 238])
    Window.draw_rect(0, 12, 256, 40, radius: 10, color: [110, 165, 225, 245])
    Window.draw_rect(0, 24, 256, 16, radius: 6, color: [255, 255, 255, 255])
    ix = 0
    while ix < 256
      Window.draw_line(ix, 8, ix + 15, 32, color: [255, 255, 255, 175], width: 2.4, cap: :round)
      Window.draw_line(ix, 56, ix + 15, 32, color: [255, 255, 255, 175], width: 2.4, cap: :round)
      Window.draw_circle(ix + 8, 32, 3.6, color: [255, 255, 255, 230])
      ix += 16
    end
  end

  # 3. 放射状エネルギー翼・ヒレテクスチャ (128 x 64)
  fin_tex = Image.new(128, 64)
  Image.render_to(fin_tex) do
    Window.clear([0, 0, 0, 0])
    rays = [-27.0, -20.0, -12.0, -4.0, 4.0, 12.0, 20.0, 27.0]
    i = 0
    while i < rays.length
      y_end = 32.0 + rays[i]
      w = 3.6 - (rays[i].abs / 30.0) * 1.6
      Window.draw_line(2, 32, 122, y_end, color: [235, 250, 255, 235], width: w, cap: :round)
      i += 1
    end
    Window.draw_circle(14, 32, 13, color: [255, 255, 255, 220])
  end

  # 4. オーブ軌跡用ソフトグローリボンテクスチャ (128 x 32)
  ribbon_tex = Image.new(128, 32)
  Image.render_to(ribbon_tex) do
    Window.clear([0, 0, 0, 0])
    Window.draw_rect(0, 4, 128, 24, radius: 12, color: [180, 235, 255, 145])
    Window.draw_rect(0, 11, 128, 10, radius: 5, color: [255, 255, 255, 245])
  end

  [white_tex, leviathan_skin, fin_tex, ribbon_tex]
end

# 10,000 個 GPU フローパーティクル用の InstanceBuffer を構築 (起動時 1 回のみ pack)
def build_flow_particles(shader)
  count = 10_000
  rng = Random.new(202611)
  floats = Array.new(count * 12, 0.0)
  i = 0
  base_idx = 0
  while i < count
    x0 = rng.rand * 1340.0 - 30.0
    # 90% を空中〜地平線付近に配置して水面反射で映えるようにする、10% は水中プランクトン
    if (i % 10) == 0
      y0 = WATER_Y + 12.0 + rng.rand * (HEIGHT - WATER_Y - 24.0)
    else
      y0 = 18.0 + rng.rand * (WATER_Y - 28.0)
    end
    phase = rng.rand * TWO_PI
    spd = 0.25 + rng.rand * 1.15

    sz = (i % 18 == 0) ? (5.5 + rng.rand * 4.5) : (1.7 + rng.rand * 2.2)
    orbit_r = 8.0 + rng.rand * 26.0
    weight = rng.rand
    seed = rng.rand

    # 色彩バリエーション (白銀・シアン・バイオレット基調、シェーダーでテーマ色とブレンド)
    c_pick = i % 3
    if c_pick == 0
      r = 0.55 + rng.rand * 0.45
      g = 0.85 + rng.rand * 0.15
      b = 1.0
    elsif c_pick == 1
      r = 0.78 + rng.rand * 0.22
      g = 0.45 + rng.rand * 0.35
      b = 1.0
    else
      r = 1.0
      g = 0.88 + rng.rand * 0.12
      b = 0.75 + rng.rand * 0.25
    end
    a = (i % 18 == 0) ? 0.38 : (0.10 + rng.rand * 0.18)

    floats[base_idx]      = x0
    floats[base_idx + 1]  = y0
    floats[base_idx + 2]  = phase
    floats[base_idx + 3]  = spd
    floats[base_idx + 4]  = sz
    floats[base_idx + 5]  = orbit_r
    floats[base_idx + 6]  = weight
    floats[base_idx + 7]  = seed
    floats[base_idx + 8]  = r
    floats[base_idx + 9]  = g
    floats[base_idx + 10] = b
    floats[base_idx + 11] = a

    base_idx += 12
    i += 1
  end

  packed = floats.pack("f*")
  InstanceBuffer.new(
    data: packed,
    count: count,
    layout: [4, 4, 4],
    shader: shader,
    blend: :add,
    retain_data: false
  )
end

def create_default_pillars
  [
    Pillar.new(175.0, 225.0, 42.0, 255.0, angle: -8.0, rune_seed: 1),
    Pillar.new(355.0, 125.0, 26.0, 150.0, angle: 26.0, rune_seed: 2),
    Pillar.new(485.0, 358.0, 34.0, 185.0, angle: 0.0, rune_seed: 3),
    Pillar.new(795.0, 125.0, 28.0, 155.0, angle: -24.0, rune_seed: 4),
    Pillar.new(895.0, 360.0, 38.0, 190.0, angle: 0.0, rune_seed: 5),
    Pillar.new(1095.0, 235.0, 44.0, 260.0, angle: 8.0, rune_seed: 6),
    Pillar.new(640.0, 68.0, 108.0, 22.0, angle: 0.0, rune_seed: 7)
  ]
end

def create_crystals
  coords = [
    [255.0, 145.0],
    [415.0, 250.0],
    [575.0, 185.0],
    [715.0, 210.0],
    [875.0, 165.0],
    [1010.0, 290.0]
  ]
  arr = []
  i = 0
  while i < coords.length
    arr << ResonanceCrystal.new(coords[i][0], coords[i][1], i)
    i += 1
  end
  arr
end

# ギザギザの稲妻プラズマアーク描画 (2点間)
def draw_plasma_arc(x1, y1, x2, y2, seed, color, width = 2.2)
  dx = x2 - x1
  dy = y2 - y1
  len = Math.sqrt(dx * dx + dy * dy)
  return if len < 1.0
  nx = -dy / len
  ny = dx / len
  segs = 7
  px = x1
  py = y1
  i = 1
  while i <= segs
    t = i.to_f / segs
    jitter = (i == segs) ? 0.0 : (Math.sin(seed * 13.7 + i * 7.3) * 16.0)
    cx = lerp_f(x1, x2, t) + nx * jitter
    cy = lerp_f(y1, y2, t) + ny * jitter
    Window.draw_line(px, py, cx, cy, color: color, width: width, cap: :round, blend: :add, z: 26.0)
    Window.draw_line(px, py, cx, cy, color: [255, 255, 255, 190], width: width * 0.4, cap: :round, blend: :add, z: 26.1)
    px = cx
    py = cy
    i += 1
  end
end

# 最終コンポジット + SDF タイトル + ミニマル HUD 描画 (ウィンドウ / キャプチャ共通)
def draw_final_composite_and_hud(scene_fbo, composite_shader, comp_uniforms, time, theme, orb,
                                 show_hud, show_bloom, show_light, show_water, show_distort,
                                 game_mode, score, combo, sound_bank)
  Window.clear([0, 0, 0, 255])
  Window.draw(
    0, 0, scene_fbo,
    width: WIDTH, height: HEIGHT,
    shader: composite_shader,
    blend: :none,
    z: 0.0,
    uniforms: comp_uniforms
  )

  # SDF タイトル演出 (起動後 4.8 秒間)
  if time < 4.8
    t_alpha = if time < 0.7
                (time / 0.7 * 255.0).to_i
              elsif time > 3.6
                ((4.8 - time) / 1.2 * 255.0).to_i
              else
                255
              end
    t_alpha = clamp_i(t_alpha, 0, 255)
    if t_alpha > 4
      acc = theme[:hud_accent]
      Window.draw_text(
        WIDTH * 0.5, 112.0, "NEON ABYSS",
        font: Font::MPLUS, size: 56, align: :center,
        color: [255, 255, 255, t_alpha],
        outline_width: 3.0, outline_color: [6, 10, 24, t_alpha],
        shadow_blur: 8.0, shadow_color: [acc[0], acc[1], acc[2], (t_alpha * 0.9).to_i],
        z: 90.0
      ) do |ch|
        ch.y += Math.sin(time * 4.5 + ch.index * 0.55) * 5.0
        glow_mix = 0.5 + 0.5 * Math.sin(time * 5.0 - ch.index * 0.4)
        ch.color = [
          lerp_f(acc[0], 255.0, 0.35 + glow_mix * 0.65).to_i,
          lerp_f(acc[1], 255.0, 0.35 + glow_mix * 0.65).to_i,
          lerp_f(acc[2], 255.0, 0.35 + glow_mix * 0.65).to_i,
          t_alpha
        ]
      end

      Window.draw_text(
        WIDTH * 0.5, 182.0, "Luminous Leviathan & 2D Global Illumination",
        font: Font::MPLUS, size: 17, align: :center,
        color: [225, 238, 255, (t_alpha * 0.95).to_i],
        outline_width: 1.4, outline_color: [6, 10, 24, t_alpha],
        shadow_blur: 3.0, shadow_color: [0, 0, 0, t_alpha],
        z: 90.0
      )
    end
  end

  # ミニマル・グラス HUD ([H] で非表示可)
  if show_hud
    acc = theme[:hud_accent]
    hud_h = (game_mode == :hunt) ? 142.0 : 114.0
    Window.draw_rect(
      18, 16, 372, hud_h,
      radius: 10.0,
      color: [8, 12, 24, 175],
      border_width: 1.2,
      border_color: [acc[0], acc[1], acc[2], 145],
      shadow_blur: 10.0,
      shadow_color: [0, 0, 0, 120],
      z: 95.0
    )

    Window.draw_text(32, 26, "NEON ABYSS  //  #{theme[:name]}", size: 16, color: [acc[0], acc[1], acc[2], 255], weight: 0.4, z: 96.0)
    fps_val = Window.fps.round(1)
    Window.draw_text(32, 50, "FPS: #{fps_val}   |   10,000 GPU Particles   |   12-Light 2D GI", size: 12, color: [205, 220, 240, 230], z: 96.0)

    flags_str = "Bloom:#{show_bloom ? 'ON' : 'OFF'}  GI:#{show_light ? 'ON' : 'OFF'}  Water:#{show_water ? 'ON' : 'OFF'}  Lens:#{show_distort ? 'ON' : 'OFF'}"
    Window.draw_text(32, 70, flags_str, size: 12, color: [155, 185, 215, 220], z: 96.0)

    Window.draw_text(32, 92, "PULSE CHARGE", size: 11, color: [175, 195, 220, 210], z: 96.0)
    Window.draw_rect(128, 95, 140, 8, radius: 4.0, color: [22, 30, 48, 220], z: 96.0)
    fill_w = 8.0 + orb.charge * 132.0
    Window.draw_rect(128, 95, fill_w, 8, radius: 4.0, color: [acc[0], acc[1], acc[2], 245], z: 96.5)
    Window.draw_text(282, 92, sound_bank.muted ? "AUDIO: MUTE" : "AUDIO: ON", size: 11, color: sound_bank.muted ? [150, 140, 160, 200] : [130, 245, 185, 235], z: 96.0)

    if game_mode == :hunt
      Window.draw_text(32, 114, "HUNT SCORE: #{score}    COMBO: x#{combo}", size: 14, color: [255, 230, 115, 255], weight: 0.4, z: 96.0)
    end

    Window.draw_rect(
      18, HEIGHT - 40, WIDTH - 36, 28,
      radius: 7.0,
      color: [8, 12, 24, 155],
      border_width: 1.0,
      border_color: [acc[0], acc[1], acc[2], 90],
      z: 95.0
    )
    guide = "[Move/WASD] Orb   [L-Hold/Space] Shockwave   [R-Hold/V] Vortex   [R-Click/P] Pillar   [1-4/T] Theme   [G] Mode   [B/L/W/D] FX   [H] HUD"
    Window.draw_text(WIDTH * 0.5, HEIGHT - 33, guide, size: 12, align: :center, color: [195, 212, 235, 225], z: 96.0)
  end
end

# ==============================================================================
# 10. 事前初期化 (すべての FBO / Shader / Mesh / Sound を Window.loop 外で生成)
# ==============================================================================
test_max_frames = ENV["ZENOO_TEST_FRAMES"] ? ENV["ZENOO_TEST_FRAMES"].to_i : 0
capture_png_path = ENV["ZENOO_CAPTURE_PNG"]
capture_frame    = ENV["ZENOO_CAPTURE_FRAME"] ? ENV["ZENOO_CAPTURE_FRAME"].to_i : 75
capture_theme    = ENV["ZENOO_CAPTURE_THEME"] ? ENV["ZENOO_CAPTURE_THEME"].to_i : 0
capture_shock    = ENV["ZENOO_CAPTURE_SHOCK"] == "1"

# FBO 群 (DAG: occluder -> light -> scene -> bloom_bright -> h1 -> v1 -> h2 -> v2 -> final)
occluder_fbo = Image.new(HALF_W, HALF_H)
light_fbo    = Image.new(HALF_W, HALF_H)
scene_fbo    = Image.new(WIDTH, HEIGHT)
bloom_bright = Image.new(BLOOM_W, BLOOM_H)
bloom_h1     = Image.new(BLOOM_W, BLOOM_H)
bloom_v1     = Image.new(BLOOM_W, BLOOM_H)
bloom_h2     = Image.new(BLOOM_W, BLOOM_H)
bloom_v2     = Image.new(BLOOM_W, BLOOM_H)
capture_fbo  = capture_png_path ? Image.new(WIDTH, HEIGHT) : nil

[occluder_fbo, light_fbo, scene_fbo, bloom_bright, bloom_h1, bloom_v1, bloom_h2, bloom_v2].each do |img|
  img.texture_filter = :linear
end

# シェーダーコンパイル
bg_shader           = Shader.new(BG_ATMOSPHERE_FRAG)
particle_flow_sh    = Shader.new(PARTICLE_FLOW_VERT, PARTICLE_FLOW_FRAG)
lighting_shader     = Shader.new(LIGHTING_2D_FRAG)
bloom_bright_shader = Shader.new(BLOOM_BRIGHT_FRAG)
bloom_blur_shader   = Shader.new(BLOOM_BLUR_FRAG)
composite_shader    = Shader.new(COMPOSITE_FRAG)

# プロシージャルテクスチャ & GPU オブジェクト
white_tex, leviathan_skin, fin_tex, ribbon_tex = build_procedural_textures
flow_particles = build_flow_particles(particle_flow_sh)

# 汎用 GPU バーストパーティクル (ショックウェーブ炸裂時)
burst_emitter = ParticleEmitter.new(
  640.0, 320.0,
  max_particles: 1600,
  emitting: false,
  spawn_shape: :ring,
  spawn_radius: 16.0,
  radial_direction: true,
  lifetime: 0.95,
  lifetime_var: 0.35,
  speed: 320.0,
  speed_var: 140.0,
  drag: 2.4,
  gravity_y: 40.0,
  start_size: 16.0,
  end_size: 1.5,
  shape: :star,
  blend: :add,
  start_color: [255, 255, 255, 255],
  mid_color: [90, 235, 255, 220],
  end_color: [140, 80, 255, 0]
)

# ゲーム・デモ状態
theme_idx = clamp_i(capture_theme, 0, THEMES.length - 1)
game_mode = :sanctuary # :sanctuary | :hunt
show_bloom   = true
show_light   = true
show_water   = true
show_distort = true
show_hud     = true

pillars       = create_default_pillars
base_pillars  = pillars.length
user_p_cursor = 0
max_user_p    = 6

crystals = create_crystals
target_crystal_idx = 0
crystals[0].is_target = false

shockwaves = [Shockwave.new, Shockwave.new, Shockwave.new, Shockwave.new]
sw_cursor  = 0

leviathan = NeonLeviathan.new(leviathan_skin, fin_tex)
orb       = PlayerOrb.new(ribbon_tex)

# カメラ (ワールド中心付近を緩やかに追従 + 半解像度同期カメラ)
cam      = Camera.new(x: WIDTH * 0.5, y: HEIGHT * 0.5, zoom: 1.0, width: WIDTH, height: HEIGHT)
cam_half = Camera.new(x: WIDTH * 0.5, y: HEIGHT * 0.5, zoom: 0.5, width: HALF_W, height: HALF_H)

# サウンドバンク (自動テスト/キャプチャ時はミュート起動)
sound_bank = SoundBank.new(silent_boot: (test_max_frames > 0 || !capture_png_path.nil?))
sound_bank.start_bgm unless test_max_frames > 0

# Uniform 用事前確保配列 (毎フレーム新規アロケーション最小化)
light_pos_arr = Array.new(48, 0.0)
light_col_arr = Array.new(48, 0.0)
sw_arr        = Array.new(16, 0.0)
sw_world_arr  = Array.new(16, 0.0)
arc_links     = []

score         = 0
combo         = 0
combo_timer   = 0.0
right_hold_t  = 0.0
right_down    = false
vortex_str    = 0.0
vortex_x      = 640.0
vortex_y      = 320.0
prev_mouse_x  = nil
prev_mouse_y  = nil
use_mouse     = false
frame         = 0

# ==============================================================================
# 11. メインループ (固定 1/60 秒フレームベース進行)
# ==============================================================================
Window.loop(WIDTH, HEIGHT, "NEON ABYSS — Luminous Leviathan & 2D GI", vsync: false) do
  frame += 1
  time = frame * DT
  theme = THEMES[theme_idx]

  # --- A. 入力処理 ---
  if Input.key_push?(:"1") || Input.key_push?(:kp_1) then theme_idx = 0 end
  if Input.key_push?(:"2") || Input.key_push?(:kp_2) then theme_idx = 1 end
  if Input.key_push?(:"3") || Input.key_push?(:kp_3) then theme_idx = 2 end
  if Input.key_push?(:"4") || Input.key_push?(:kp_4) then theme_idx = 3 end
  if Input.key_push?(:t)
    theme_idx = (theme_idx + 1) % THEMES.length
  end
  theme = THEMES[theme_idx]

  if Input.key_push?(:g)
    game_mode = (game_mode == :sanctuary) ? :hunt : :sanctuary
    if game_mode == :hunt
      i = 0
      while i < crystals.length
        crystals[i].is_target = (i == target_crystal_idx)
        i += 1
      end
      score = 0
      combo = 0
      combo_timer = 0.0
    else
      i = 0
      while i < crystals.length
        crystals[i].is_target = false
        i += 1
      end
    end
  end

  show_bloom   = !show_bloom   if Input.key_push?(:b)
  show_light   = !show_light   if Input.key_push?(:l)
  show_water   = !show_water   if Input.key_push?(:w)
  show_distort = !show_distort if Input.key_push?(:d)
  show_hud     = !show_hud     if Input.key_push?(:h)
  sound_bank.toggle_mute       if Input.key_push?(:m)

  if Input.key_push?(:r)
    pillars = create_default_pillars
    user_p_cursor = 0
    score = 0
    combo = 0
    combo_timer = 0.0
  end

  # マウス位置検知 (起動直後の(0,0)誤検知を防ぎ、実際に動かした時だけ追従)
  mx = Input.mouse_x.to_f
  my = Input.mouse_y.to_f
  if prev_mouse_x.nil?
    prev_mouse_x = mx
    prev_mouse_y = my
  elsif (mx - prev_mouse_x).abs > 2.5 || (my - prev_mouse_y).abs > 2.5
    use_mouse = true
  end
  prev_mouse_x = mx
  prev_mouse_y = my

  key_dx = 0.0
  key_dy = 0.0
  key_dx -= 1.0 if Input.key_pressed?(:a) || Input.key_pressed?(:left)
  key_dx += 1.0 if Input.key_pressed?(:d) || Input.key_pressed?(:right)
  key_dy -= 1.0 if Input.key_pressed?(:w) || Input.key_pressed?(:up)
  key_dy += 1.0 if Input.key_pressed?(:s) || Input.key_pressed?(:down)
  if key_dx != 0.0 && key_dy != 0.0
    inv_sqrt2 = 0.70710678
    key_dx *= inv_sqrt2
    key_dy *= inv_sqrt2
  end

  if use_mouse
    world_mx, world_my = cam.screen_to_world(mx, my)
    target_orb_x = world_mx
    target_orb_y = world_my
  else
    # 未操作時は優雅な自動周回デモ軌道
    target_orb_x = 640.0 + Math.cos(time * 0.75) * 280.0
    target_orb_y = 280.0 + Math.sin(time * 1.15) * 110.0
  end

  # 左ホールド / SPACE でチャージ、離すとショックウェーブ炸裂
  charging_now = Input.mouse_pressed?(:left) || Input.key_pressed?(:space)
  if (Input.mouse_push?(:left) || Input.key_push?(:space)) && !orb.charging
    sound_bank.play_charge
  end

  release_sw = false
  if orb.charging && !charging_now
    release_sw = true
  end
  # キャプチャ用ショックウェーブ自動トリガー (48フレーム目で発動し 75フレーム目で美しく広がる)
  if capture_shock && frame == 48
    release_sw = true
    orb.charge = 0.9
  end

  orb.update(target_orb_x, target_orb_y, key_dx, key_dy, charging_now, time, theme)

  if release_sw
    pw = orb.release_charge!
    shockwaves[sw_cursor].spawn(orb.x, orb.y, pw)
    sw_cursor = (sw_cursor + 1) % 4
    cam.shake(8.0 + pw * 6.0, 0.32)
    cam_half.shake((8.0 + pw * 6.0) * 0.5, 0.32)
    sound_bank.play_shockwave
    leviathan.trigger_surge(pw)

    # ParticleEmitter 一斉バースト
    oc = theme[:orb]
    burst_emitter.mid_color = [oc[0], oc[1], oc[2], 230]
    burst_emitter.burst((160 + pw * 180).to_i, x: orb.x, y: orb.y, speed: 240.0 + pw * 210.0)
  end

  # 右クリック (長押し: 重力特異点 / 短押し: 柱配置) または [V] / [P]
  if Input.mouse_push?(:right)
    right_down = true
    right_hold_t = 0.0
  end
  if right_down
    if Input.mouse_pressed?(:right)
      right_hold_t += DT
    else
      if right_hold_t < 0.22
        px, py = cam.screen_to_world(mx, my)
        py = clamp_f(py, 70.0, WATER_Y - 50.0)
        new_p = Pillar.new(px, py, 34.0, 140.0, angle: (frame % 3 - 1) * 14.0, rune_seed: frame, user_placed: true)
        if pillars.length < base_pillars + max_user_p
          pillars << new_p
        else
          pillars[base_pillars + user_p_cursor] = new_p
          user_p_cursor = (user_p_cursor + 1) % max_user_p
        end
      end
      right_down = false
    end
  end

  if Input.key_push?(:p)
    new_p = Pillar.new(orb.x, clamp_f(orb.y, 70.0, WATER_Y - 50.0), 34.0, 140.0, angle: (frame % 3 - 1) * 14.0, rune_seed: frame, user_placed: true)
    if pillars.length < base_pillars + max_user_p
      pillars << new_p
    else
      pillars[base_pillars + user_p_cursor] = new_p
      user_p_cursor = (user_p_cursor + 1) % max_user_p
    end
  end

  vortex_active = (right_down && right_hold_t >= 0.22) || Input.key_pressed?(:v)
  if vortex_active
    vortex_x = (right_down && use_mouse) ? target_orb_x : orb.x
    vortex_y = (right_down && use_mouse) ? clamp_f(target_orb_y, 60.0, WATER_Y - 25.0) : orb.y
    vortex_str = clamp_f(vortex_str + DT * 3.5, 0.0, 1.0)
  else
    vortex_str = clamp_f(vortex_str - DT * 3.5, 0.0, 1.0)
  end

  # --- B. カメラ更新 (視差パン + シェイク同期) ---
  desired_cam_x = WIDTH * 0.5 + (orb.x - WIDTH * 0.5) * 0.055
  desired_cam_y = HEIGHT * 0.5 + (orb.y - WATER_Y * 0.5) * 0.035
  cam.x = lerp_f(cam.x, desired_cam_x, 0.08)
  cam.y = lerp_f(cam.y, desired_cam_y, 0.08)
  cam.update(DT)

  cam_half.x = cam.x
  cam_half.y = cam.y
  cam_half.update(DT)

  # --- C. エンティティ & 物理更新 ---
  i = 0
  while i < crystals.length
    crystals[i].update(time)
    i += 1
  end

  leviathan.update(time, orb.x, orb.y, vortex_str > 0.2, vortex_x, vortex_y, crystals, theme)

  # オーブ近接 & ショックウェーブによるクリスタル共鳴判定
  arc_links.clear
  i = 0
  while i < crystals.length
    cr = crystals[i]
    dx = cr.x - orb.x
    dy = cr.y - orb.y
    d2 = dx * dx + dy * dy
    hit_by_orb = d2 < 2300.0
    hit_by_sw = false
    s_i = 0
    while s_i < 4
      sw = shockwaves[s_i]
      if sw.active
        sdx = cr.x - sw.x
        sdy = cr.y - sw.y
        sdist = Math.sqrt(sdx * sdx + sdy * sdy)
        if (sdist - sw.radius).abs < 28.0
          hit_by_sw = true
        end
      end
      s_i += 1
    end

    if hit_by_orb || hit_by_sw
      if cr.cooldown <= 0.0
        cr.trigger(hit_by_sw ? 1.0 : 0.7, sound_bank)
        if game_mode == :hunt && cr.is_target
          combo += 1
          combo_timer = 4.5
          score += 100 * combo
          cr.is_target = false
          target_crystal_idx = (target_crystal_idx + 1 + (frame % 3)) % crystals.length
          crystals[target_crystal_idx].is_target = true
          burst_emitter.burst(90, x: cr.x, y: cr.y, speed: 220.0)
        end
      end
    end

    # 共鳴中のクリスタル同士をプラズマアークで結ぶ
    if cr.charge > 0.55
      j = i + 1
      while j < crystals.length
        cr2 = crystals[j]
        if cr2.charge > 0.55
          adx = cr2.x - cr.x
          ady = cr2.y - cr.y
          if adx * adx + ady * ady < 95_000.0
            arc_links << [cr.x, cr.y, cr2.x, cr2.y]
          end
        end
        j += 1
      end
    end
    i += 1
  end

  if combo_timer > 0.0
    combo_timer -= DT
    if combo_timer <= 0.0
      combo = 0
    end
  end

  i = 0
  while i < 4
    shockwaves[i].update
    i += 1
  end

  burst_emitter.update(DT)

  # --- D. 共通カメラパラメータ & ライト配列の組み立て (0..11, 12灯) ---
  cz, cam_ox, cam_oy = cam.view
  water_y_uv = clamp_f((WATER_Y * cz + cam_oy) / HEIGHT.to_f, 0.35, 0.90)

  # ヘルパーラムダは使わず直線代入でライト 12 灯を UV 空間に変換
  l_idx = 0
  # Light 0: プレイヤーオーブ
  ox_uv = (orb.x * cz + cam_ox) / WIDTH.to_f
  oy_uv = (orb.y * cz + cam_oy) / HEIGHT.to_f
  oc = theme[:orb]
  light_pos_arr[0] = ox_uv; light_pos_arr[1] = oy_uv
  light_pos_arr[2] = 0.38 + orb.charge * 0.22 + orb.pulse * 0.16
  light_pos_arr[3] = 0.85 + orb.charge * 0.75 + orb.pulse * 0.65
  light_col_arr[0] = oc[0] / 255.0; light_col_arr[1] = oc[1] / 255.0; light_col_arr[2] = oc[2] / 255.0; light_col_arr[3] = 1.15

  # Light 1: リヴァイアサン頭部
  ca = theme[:leviathan_a]
  cb = theme[:leviathan_b]
  light_pos_arr[4] = (leviathan.head_x * cz + cam_ox) / WIDTH.to_f
  light_pos_arr[5] = (leviathan.head_y * cz + cam_oy) / HEIGHT.to_f
  light_pos_arr[6] = 0.36 + leviathan.surge * 0.12
  light_pos_arr[7] = 0.95 + leviathan.surge * 0.50
  light_col_arr[4] = ca[0] / 255.0; light_col_arr[5] = ca[1] / 255.0; light_col_arr[6] = ca[2] / 255.0; light_col_arr[7] = 1.25

  # Light 2: リヴァイアサン胴体中央
  mp = leviathan.mid_pos
  light_pos_arr[8]  = (mp[0] * cz + cam_ox) / WIDTH.to_f
  light_pos_arr[9]  = (mp[1] * cz + cam_oy) / HEIGHT.to_f
  light_pos_arr[10] = 0.22
  light_pos_arr[11] = 0.52
  light_col_arr[8] = cb[0] / 255.0; light_col_arr[9] = cb[1] / 255.0; light_col_arr[10] = cb[2] / 255.0; light_col_arr[11] = 0.7

  # Light 3: リヴァイアサン尾先
  tp = leviathan.tail_pos
  light_pos_arr[12] = (tp[0] * cz + cam_ox) / WIDTH.to_f
  light_pos_arr[13] = (tp[1] * cz + cam_oy) / HEIGHT.to_f
  light_pos_arr[14] = 0.18
  light_pos_arr[15] = 0.45
  light_col_arr[12] = ca[0] / 255.0; light_col_arr[13] = ca[1] / 255.0; light_col_arr[14] = ca[2] / 255.0; light_col_arr[15] = 0.65

  # Light 4..9: 6個の共鳴クリスタル
  cc = theme[:crystal]
  ci = 0
  while ci < 6
    cr = crystals[ci]
    base = (4 + ci) * 4
    light_pos_arr[base]     = (cr.x * cz + cam_ox) / WIDTH.to_f
    light_pos_arr[base + 1] = (cr.y * cz + cam_oy) / HEIGHT.to_f
    light_pos_arr[base + 2] = 0.16 + cr.charge * 0.14
    light_pos_arr[base + 3] = 0.25 + cr.charge * 0.65 + (cr.is_target ? 0.40 : 0.0)
    light_col_arr[base]     = cr.is_target ? 1.0 : (cc[0] / 255.0)
    light_col_arr[base + 1] = cr.is_target ? 0.88 : (cc[1] / 255.0)
    light_col_arr[base + 2] = cr.is_target ? 0.35 : (cc[2] / 255.0)
    light_col_arr[base + 3] = 0.85
    ci += 1
  end

  # Light 10: 上空神殿の天蓋アンビエント・スポットライト (斜めゴッドレイ演出の要)
  sky_lx = 0.5 + Math.sin(time * 0.22) * 0.18
  light_pos_arr[40] = sky_lx
  light_pos_arr[41] = 0.03
  light_pos_arr[42] = 0.85
  light_pos_arr[43] = 0.92
  au = theme[:aurora_a]
  light_col_arr[40] = au[0]; light_col_arr[41] = au[1]; light_col_arr[42] = au[2]; light_col_arr[43] = 1.85

  # Light 11: ショックウェーブまたは特異点フラッシュ
  sw_active_ref = nil
  s_i = 0
  while s_i < 4
    sw = shockwaves[s_i]
    base = s_i * 4
    if sw.active
      sw_arr[base]           = (sw.x * cz + cam_ox) / WIDTH.to_f
      sw_arr[base + 1]       = (sw.y * cz + cam_oy) / HEIGHT.to_f
      sw_arr[base + 2]       = (sw.radius * cz) / WIDTH.to_f
      sw_arr[base + 3]       = sw.strength
      sw_world_arr[base]     = sw.x
      sw_world_arr[base + 1] = sw.y
      sw_world_arr[base + 2] = sw.radius
      sw_world_arr[base + 3] = sw.strength
      sw_active_ref = sw
    else
      sw_arr[base]           = 0.0
      sw_arr[base + 1]       = 0.0
      sw_arr[base + 2]       = 0.0
      sw_arr[base + 3]       = 0.0
      sw_world_arr[base]     = 0.0
      sw_world_arr[base + 1] = 0.0
      sw_world_arr[base + 2] = 0.0
      sw_world_arr[base + 3] = 0.0
    end
    s_i += 1
  end

  if sw_active_ref
    light_pos_arr[44] = (sw_active_ref.x * cz + cam_ox) / WIDTH.to_f
    light_pos_arr[45] = (sw_active_ref.y * cz + cam_oy) / HEIGHT.to_f
    light_pos_arr[46] = 0.55
    light_pos_arr[47] = sw_active_ref.strength * 1.1
    light_col_arr[44] = 1.0; light_col_arr[45] = 0.92; light_col_arr[46] = 1.0; light_col_arr[47] = 1.1
  elsif vortex_str > 0.02
    light_pos_arr[44] = (vortex_x * cz + cam_ox) / WIDTH.to_f
    light_pos_arr[45] = (vortex_y * cz + cam_oy) / HEIGHT.to_f
    light_pos_arr[46] = 0.36
    light_pos_arr[47] = vortex_str * 0.95
    light_col_arr[44] = cb[0] / 255.0; light_col_arr[45] = cb[1] / 255.0; light_col_arr[46] = cb[2] / 255.0; light_col_arr[47] = 1.1
  else
    light_pos_arr[47] = 0.0
  end

  # ============================================================================
  # E. DAG レンダリングパイプライン実行
  # ============================================================================

  # [Pass 1] Occluder Map (640x360)
  if show_light
    Image.render_to(occluder_fbo) do
      Window.clear([0, 0, 0, 255])
      Window.camera(cam_half) do
        pi = 0
        while pi < pillars.length
          pillars[pi].draw_occluder
          pi += 1
        end
        leviathan.draw_occluder
      end
    end

    # [Pass 2] 2D レイマーチング GI & ソフトシャドウ & ゴッドレイ (640x360)
    Image.render_to(light_fbo) do
      Window.clear([0, 0, 0, 255])
      Window.draw(
        0, 0, occluder_fbo,
        width: HALF_W, height: HALF_H,
        shader: lighting_shader,
        blend: :none,
        uniforms: {
          u_light_pos: light_pos_arr,
          u_light_col: light_col_arr,
          u_water_y:   water_y_uv
        }
      )
    end
  end

  # [Pass 3] メインカラーシーン (1280x720)
  Image.render_to(scene_fbo) do
    Window.clear([4, 8, 18, 255])

    # 3-1. プロシージャル背景大気 & 遠景神殿
    Window.draw(
      0, 0, white_tex,
      width: WIDTH, height: HEIGHT,
      shader: bg_shader,
      blend: :none,
      z: 0.0,
      uniforms: {
        u_time:       time,
        u_water_y:    water_y_uv,
        u_bg_top:     theme[:bg_top],
        u_bg_horizon: theme[:bg_horizon],
        u_aurora_a:   theme[:aurora_a],
        u_aurora_b:   theme[:aurora_b],
        u_cam_offset: [cam.x - WIDTH * 0.5, cam.y - HEIGHT * 0.5]
      }
    )

    # 3-2. ワールド空間オブジェクト (Camera 適用)
    Window.camera(cam) do
      # 10,000 GPU フローパーティクル (1 DrawCall / CPU pack 0)
      flow_particles.draw(
        z: 10.0,
        uniforms: {
          u_time:           time,
          u_view:           [cz, cam_ox, cam_oy, 0.0],
          u_orb:            [orb.x, orb.y, orb.charge, orb.pulse],
          u_leviathan_head: [leviathan.head_x, leviathan.head_y, leviathan.vx, leviathan.vy],
          u_vortex:         [vortex_x, vortex_y, 260.0, vortex_str],
          u_shockwaves:     sw_world_arr.pack("f*"),
          u_theme_tint:     [theme[:aurora_a][0], theme[:aurora_a][1], theme[:aurora_a][2], 0.72]
        }
      )

      # 古代モノリス柱
      pi = 0
      while pi < pillars.length
        pillars[pi].draw_visual(time, theme)
        pi += 1
      end

      # 共鳴クリスタル & プラズマ放電アーク
      ci = 0
      while ci < crystals.length
        crystals[ci].draw(time, theme)
        ci += 1
      end
      ai = 0
      while ai < arc_links.length
        lnk = arc_links[ai]
        draw_plasma_arc(lnk[0], lnk[1], lnk[2], lnk[3], time * 6.0 + ai * 2.1, [cc[0], cc[1], cc[2], 235])
        ai += 1
      end

      # NEON LEVIATHAN (FABRIK 触角 + 二重リボン体躯 + 波打ちヒレ)
      leviathan.draw_visual(time, orb.x, orb.y, theme)

      # プレイヤーオーブ & 軌跡リボン
      orb.draw(time, theme)

      # 重力特異点の事象の地平面リング
      if vortex_str > 0.02
        vr = 34.0 * vortex_str + Math.sin(time * 9.0) * 3.0
        Window.draw_circle(
          vortex_x, vortex_y, vr * 1.9,
          border_width: 2.0,
          border_color: [cb[0], cb[1], cb[2], (vortex_str * 190).to_i],
          blend: :add,
          z: 38.0
        )
        Window.draw_circle(vortex_x, vortex_y, vr * 0.55, color: [5, 2, 14, (vortex_str * 245).to_i], z: 38.5)
      end

      # ショックウェーブリング & ParticleEmitter バースト
      s_i = 0
      while s_i < 4
        shockwaves[s_i].draw(theme)
        s_i += 1
      end
      burst_emitter.draw(z: 44.0)
    end
  end

  # [Pass 4..8] 2ラウンド・セパラブルガウスブルーム (320x180, 完全 DAG)
  if show_bloom
    Image.render_to(bloom_bright) do
      Window.clear([0, 0, 0, 255])
      Window.draw(
        0, 0, scene_fbo,
        width: BLOOM_W, height: BLOOM_H,
        shader: bloom_bright_shader,
        blend: :none,
        uniforms: {
          u_light_tex: show_light ? light_fbo : white_tex,
          u_threshold: show_light ? 0.62 : 0.48
        }
      )
    end

    Image.render_to(bloom_h1) do
      Window.clear([0, 0, 0, 255])
      Window.draw(0, 0, bloom_bright, width: BLOOM_W, height: BLOOM_H, shader: bloom_blur_shader, blend: :none,
                  uniforms: { u_texel_step: [1.0 / BLOOM_W, 0.0] })
    end
    Image.render_to(bloom_v1) do
      Window.clear([0, 0, 0, 255])
      Window.draw(0, 0, bloom_h1, width: BLOOM_W, height: BLOOM_H, shader: bloom_blur_shader, blend: :none,
                  uniforms: { u_texel_step: [0.0, 1.0 / BLOOM_H] })
    end
    Image.render_to(bloom_h2) do
      Window.clear([0, 0, 0, 255])
      Window.draw(0, 0, bloom_v1, width: BLOOM_W, height: BLOOM_H, shader: bloom_blur_shader, blend: :none,
                  uniforms: { u_texel_step: [2.2 / BLOOM_W, 0.0] })
    end
    Image.render_to(bloom_v2) do
      Window.clear([0, 0, 0, 255])
      Window.draw(0, 0, bloom_h2, width: BLOOM_W, height: BLOOM_H, shader: bloom_blur_shader, blend: :none,
                  uniforms: { u_texel_step: [0.0, 2.2 / BLOOM_H] })
    end
  end

  # 最終コンポジット & HUD 描画用 uniform を組み立て
  comp_uniforms = {
    u_light_tex:  light_fbo,
    u_bloom_tex:  bloom_v2,
    u_time:       time,
    u_water_y:    water_y_uv,
    u_vortex:     [(vortex_x * cz + cam_ox) / WIDTH.to_f, (vortex_y * cz + cam_oy) / HEIGHT.to_f, 0.22, vortex_str],
    u_shockwaves: sw_arr.pack("f*"),
    u_flags:      [show_bloom ? 1.0 : 0.0, show_light ? 1.0 : 0.0, show_water ? 1.0 : 0.0, show_distort ? 1.0 : 0.0],
    u_water_tint: theme[:water_tint],
    u_orb_uv:     [ox_uv, oy_uv, orb.charge, 1.0]
  }

  if capture_fbo && frame == capture_frame
    Image.render_to(capture_fbo) do
      draw_final_composite_and_hud(
        scene_fbo, composite_shader, comp_uniforms, time, theme, orb,
        show_hud, show_bloom, show_light, show_water, show_distort,
        game_mode, score, combo, sound_bank
      )
    end
    Zenoo::Backend.flush_image(capture_fbo)
    capture_fbo.save(capture_png_path)
  end

  draw_final_composite_and_hud(
    scene_fbo, composite_shader, comp_uniforms, time, theme, orb,
    show_hud, show_bloom, show_light, show_water, show_distort,
    game_mode, score, combo, sound_bank
  )

  break if test_max_frames > 0 && frame >= test_max_frames
end

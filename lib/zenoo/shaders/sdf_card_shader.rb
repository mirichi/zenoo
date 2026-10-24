module Zenoo
  module Shaders
    CARD_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec4 in_bounds;
      layout (location = 1) in vec4 in_color;
      layout (location = 2) in vec4 in_param0;       // corner_radius, border_width, shadow_blur, mode
      layout (location = 3) in vec4 in_param1;       // border_color (r, g, b, a)
      layout (location = 4) in vec4 in_param2;       // shadow_color (r, g, b, a)
      layout (location = 5) in vec4 in_uv;          // uv or tri_p01
      layout (location = 6) in vec4 in_transform;   // rot_rad, pivot_x, pivot_y, unused (or tri_p2.xy)
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      out vec2 v_local_pos;
      out vec2 v_half_size;
      out vec4 v_color;
      out vec4 v_border_color;
      out vec4 v_shadow_color;
      out float v_corner_radius;
      out float v_border_width;
      out float v_shadow_blur;
      flat out int v_mode;
      out vec2 v_uv;
      out vec4 v_tri_p01;
      out vec2 v_tri_p2;

      void main() {
          vec2 in_unit_pos = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          float x = in_bounds.x; float y = in_bounds.y; float w = in_bounds.z; float h = in_bounds.w;
          int mode = int(in_param0.w);
          float shadow_blur = in_param0.z;
          // 三角形(mode == 4)の角丸膨らみ、および太いボーダーの描画領域をパディングに加算
          float extra_pad = in_param0.y + ((mode == 4) ? in_param0.x : 0.0);
          float pad = max(shadow_blur * 2.0, 2.0) + extra_pad;

          // パディング込みのローカル頂点
          vec2 local_corner = vec2(-pad, -pad) + in_unit_pos * vec2(w + pad * 2.0, h + pad * 2.0);

          // 三角形モード (mode == 4) は回転計算をスキップし中心固定
          vec2 pivot = (mode == 4) ? vec2(0.5, 0.5) : in_transform.yz;
          vec2 pivot_pos = pivot * vec2(w, h);

          // ピボットからの相対位置
          vec2 rel = local_corner - pivot_pos;

          // 回転
          float rad = (mode == 4) ? 0.0 : in_transform.x;
          float c = cos(rad);
          float s = sin(rad);
          vec2 rot = vec2(rel.x * c - rel.y * s, rel.x * s + rel.y * c);

          // ワールド位置
          vec2 world_pivot = vec2(x, y) + pivot_pos;
          vec2 pos = world_pivot + rot;

          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);

          v_half_size = vec2(w * 0.5, h * 0.5);
          v_local_pos = local_corner - v_half_size;
          v_color = in_color;
          v_border_color = in_param1;
          v_shadow_color = in_param2;
          v_corner_radius = (mode == 4) ? in_param0.x : min(in_param0.x, min(v_half_size.x, v_half_size.y));
          v_border_width = in_param0.y;
          v_shadow_blur = shadow_blur;
          v_mode = mode;
          v_uv = in_uv.xy + in_unit_pos * in_uv.zw;
          v_tri_p01 = in_uv;
          v_tri_p2 = in_transform.xy;
      }
    GLSL

    CARD_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec2 v_local_pos;
      in vec2 v_half_size;
      in vec4 v_color;
      in vec4 v_border_color;
      in vec4 v_shadow_color;
      in float v_corner_radius;
      out vec4 fragColor;
      in float v_border_width;
      in float v_shadow_blur;
      flat in int v_mode;
      in vec2 v_uv;
      in vec4 v_tri_p01;
      in vec2 v_tri_p2;
      uniform sampler2D u_texture;

      // SDF 角丸ボックス距離関数
      float sd_rounded_box(vec2 p, vec2 b, float r) {
          vec2 q = abs(p) - b + r;
          return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
      }

      // SDF 楕円距離関数 (勾配補正による高品質・高速近似)
      float sd_ellipse(vec2 p, vec2 ab) {
          vec2 k = p / ab;
          float k0 = length(k);
          float k1 = length(k / ab);
          return (k0 < 0.0001) ? -min(ab.x, ab.y) : (k0 * (k0 - 1.0) / k1);
      }

      // SDF 三角形距離関数 (Inigo Quilez)
      float sd_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
          vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
          vec2 v0 = p - p0,  v1 = p - p1,  v2 = p - p2;

          vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / max(dot(e0, e0), 0.00001), 0.0, 1.0);
          vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / max(dot(e1, e1), 0.00001), 0.0, 1.0);
          vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / max(dot(e2, e2), 0.00001), 0.0, 1.0);

          float s = sign(e0.x * e2.y - e0.y * e2.x);
          vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                           vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                           vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));

          return -sqrt(d.x) * sign(d.y);
      }

      void main() {
          // モード判定:
          // 0: 角丸矩形 (単色)
          // 1: 角丸矩形 (テクスチャ)
          // 2: 楕円 (単色)
          // 3: 楕円 (テクスチャ)
          // 4: 三角形 (単色)
          float dist = 0.0;
          if (v_mode == 2 || v_mode == 3) {
              dist = sd_ellipse(v_local_pos, v_half_size);
          } else if (v_mode == 4) {
              dist = sd_triangle(v_local_pos, v_tri_p01.xy, v_tri_p01.zw, v_tri_p2) - v_corner_radius;
          } else {
              dist = sd_rounded_box(v_local_pos, v_half_size, v_corner_radius);
          }

          // 1. ドロップシャドウ計算
          float shadow_alpha = 0.0;
          if (v_shadow_blur > 0.0 && dist > 0.0) {
              shadow_alpha = 1.0 - smoothstep(0.0, v_shadow_blur * 1.5, dist);
              shadow_alpha *= v_shadow_color.a;
          }

          // 2. 本体アンチエイリアシング
          float fw = fwidth(dist) * 0.5;
          if (fw < 0.001) fw = 0.7;
          float body_alpha = 1.0 - smoothstep(-fw, fw, dist);

          vec4 base_color = (v_mode == 1 || v_mode == 3) ? texture(u_texture, v_uv) * v_color : v_color;

          // 3. ボーダー合成
          vec4 shape_col = base_color;
          if (v_border_width > 0.0) {
              float border_dist = dist + v_border_width;
              float border_alpha = 1.0 - smoothstep(-fw, fw, border_dist);
              shape_col = mix(v_border_color, base_color, border_alpha);
          }

          vec4 final_shape = vec4(shape_col.rgb, shape_col.a * body_alpha);

          // 4. シャドウと本体をブレンド
          if (dist > 0.0) {
              fragColor = vec4(v_shadow_color.rgb, shadow_alpha);
          } else {
              fragColor = final_shape;
          }
      }
    GLSL
  end
end

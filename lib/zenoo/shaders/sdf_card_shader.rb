module Zenoo
  class SDFCardShader
    VERTEX_SOURCE = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2 in_unit_pos;
      layout (location = 1) in vec4 in_bounds;
      layout (location = 2) in vec4 in_color;
      layout (location = 3) in vec4 in_param0;       // corner_radius, border_width, shadow_blur, mode
      layout (location = 4) in vec4 in_param1;       // border_color (r, g, b, a)
      layout (location = 5) in vec4 in_param2;       // shadow_color (r, g, b, a)
      layout (location = 6) in vec4 in_uv;
      uniform vec2 u_resolution;
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
      void main() {
          float x = in_bounds.x; float y = in_bounds.y; float w = in_bounds.z; float h = in_bounds.w;
          float shadow_blur = in_param0.z;
          float pad = shadow_blur * 2.0;
          vec2 pos = vec2(x - pad, y - pad) + in_unit_pos * vec2(w + pad * 2.0, h + pad * 2.0);
          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          ndc.y = -ndc.y;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_half_size = vec2(w * 0.5, h * 0.5);
          vec2 center = vec2(x + w * 0.5, y + h * 0.5);
          v_local_pos = pos - center;
          v_color = in_color;
          v_border_color = in_param1;
          v_shadow_color = in_param2;
          v_corner_radius = min(in_param0.x, min(v_half_size.x, v_half_size.y));
          v_border_width = in_param0.y;
          v_shadow_blur = shadow_blur;
          v_mode = int(in_param0.w);
          v_uv = in_uv.xy + in_unit_pos * in_uv.zw;
      }
    GLSL

    FRAGMENT_SOURCE = <<~'GLSL'
      #version 330 core
      in vec2 v_local_pos;
      in vec2 v_half_size;
      in vec4 v_color;
      in vec4 v_border_color;
      in vec4 v_shadow_color;
      in float v_corner_radius;
      in float v_border_width;
      in float v_shadow_blur;
      flat in int v_mode;
      in vec2 v_uv;
      uniform sampler2D u_texture;
      out vec4 fragColor;

      // ★Ruby側で定義された SDF 角丸ボックス距離関数！★
      float sd_rounded_box(vec2 p, vec2 b, float r) {
          vec2 q = abs(p) - b + r;
          return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
      }

      void main() {
          float dist = sd_rounded_box(v_local_pos, v_half_size, v_corner_radius);

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

          vec4 base_color = (v_mode == 1) ? texture(u_texture, v_uv) * v_color : v_color;

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

    # シングルトンインスタンス
    def self.instance
      @instance ||= Shader.new(VERTEX_SOURCE, FRAGMENT_SOURCE)
    end
  end
end

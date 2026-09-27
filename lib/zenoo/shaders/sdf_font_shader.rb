# frozen_string_literal: true

module Zenoo
  module Shaders
    FONT_SDF_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec4 in_bounds;
      layout (location = 1) in vec4 in_color;
      layout (location = 2) in vec4 in_param0;       // outline_width, shadow_blur, shadow_dx, shadow_dy
      layout (location = 3) in vec4 in_param1;       // outline_color (r, g, b, a)
      layout (location = 4) in vec4 in_param2;       // shadow_color (r, g, b, a)
      layout (location = 5) in vec4 in_uv;
      uniform vec2 u_resolution;

      out vec4 v_color;
      out vec4 v_param0;
      out vec4 v_param1;
      out vec4 v_param2;
      out vec2 v_uv;

      void main() {
          vec2 in_unit_pos = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          vec2 pos = in_bounds.xy + in_unit_pos * in_bounds.zw;
          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          ndc.y = -ndc.y;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
          v_param0 = in_param0;
          v_param1 = in_param1;
          v_param2 = in_param2;
          v_uv = in_uv.xy + in_unit_pos * in_uv.zw;
      }
    GLSL

    FONT_SDF_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec4 v_param0;
      in vec4 v_param1;
      in vec4 v_param2;
      in vec2 v_uv;
      uniform sampler2D u_texture;
      out vec4 fragColor;

      void main() {
          float outline_width = v_param0.x;
          float shadow_blur    = v_param0.y;
          vec2 shadow_offset  = v_param0.zw;
          vec4 outline_color  = v_param1;
          vec4 shadow_color   = v_param2;

          // 1チャンネル GL_RED アトラスからサンプリング
          float dist = texture(u_texture, v_uv).r;

          // スクリーンスペース変化率に基づくアンチエイリアス幅 (画面解像度・スケール追従)
          float fw = fwidth(dist);
          if (fw < 0.0001) fw = 0.02;

          // 1. 本体のアルファ (0.5 がエッジ閾値)
          float body_alpha = smoothstep(0.5 - fw, 0.5 + fw, dist);

          // 2. アウトライン (袋文字)
          float border_alpha = 0.0;
          if (outline_width > 0.0) {
              float border_dist = dist + outline_width * 0.04183;
              float b_alpha = smoothstep(0.5 - fw, 0.5 + fw, border_dist);
              // Quad 端部 (dist = 0) で四角形が露出しないよう滑らかにフェード
              float edge_fade = smoothstep(0.01, 0.06, dist);
              border_alpha = b_alpha * edge_fade;
          }

          // 3. ドロップシャドウ
          float shadow_alpha = 0.0;
          if (shadow_color.a > 0.0 && (shadow_offset.x != 0.0 || shadow_offset.y != 0.0 || shadow_blur > 0.0)) {
              vec2 s_uv = v_uv - shadow_offset * (1.0 / 1024.0);
              float s_dist = texture(u_texture, s_uv).r;
              float s_fw = fw + shadow_blur * 0.04183;
              float s_alpha = smoothstep(0.5 - s_fw, 0.5 + s_fw, s_dist) * shadow_color.a;
              float s_edge_fade = smoothstep(0.01, 0.06, s_dist);
              shadow_alpha = s_alpha * s_edge_fade;
          }

          // 4. 文字本体とアウトラインのブレンド
          vec3 shape_rgb;
          float shape_alpha;
          if (outline_width > 0.0) {
              shape_rgb = mix(outline_color.rgb, v_color.rgb, body_alpha);
              shape_alpha = max(body_alpha * v_color.a, border_alpha * outline_color.a);
          } else {
              shape_rgb = v_color.rgb;
              shape_alpha = body_alpha * v_color.a;
          }

          // 5. シャドウとの合成 (Straight Alpha Porter-Duff Over)
          float final_a = shape_alpha + shadow_alpha * (1.0 - shape_alpha);
          if (final_a < 0.001) {
              discard;
          }

          vec3 final_rgb = (shape_rgb * shape_alpha + shadow_color.rgb * shadow_alpha * (1.0 - shape_alpha)) / final_a;
          fragColor = vec4(final_rgb, final_a);
      }
    GLSL
  end
end

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
      layout (location = 5) in vec4 in_param3;       // weight, is_bitmap, raw_weight, unused
      layout (location = 6) in vec4 in_uv;
      uniform vec2 u_resolution;
      uniform float u_flip_y;

      out vec4 v_color;
      out vec4 v_param0;
      out vec4 v_param1;
      out vec4 v_param2;
      out vec4 v_param3;
      out vec2 v_uv;

      void main() {
          vec2 in_unit_pos = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          vec2 pos = in_bounds.xy + in_unit_pos * in_bounds.zw;
          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
          v_param0 = in_param0;
          v_param1 = in_param1;
          v_param2 = in_param2;
          v_param3 = in_param3;
          v_uv = in_uv.xy + in_unit_pos * in_uv.zw;
      }
    GLSL

    FONT_SDF_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec4 v_param0;
      in vec4 v_param1;
      in vec4 v_param2;
      in vec4 v_param3;
      in vec2 v_uv;
      uniform sampler2D u_texture;
      out vec4 fragColor;

      void main() {
          float outline_width = v_param0.x;
          float shadow_blur    = v_param0.y;
          vec2 shadow_offset  = v_param0.zw;
          vec4 outline_color  = v_param1;
          vec4 shadow_color   = v_param2;
          float atlas_weight  = v_param3.x; // スケール補正済みウェイト値
          float is_bitmap     = v_param3.y; // 1.0: 直接ラスタライズビットマップ, 0.0: SDF
          float raw_weight    = v_param3.z; // ビットマップ用の生ウェイト値

          // 文字色の輝度に応じた知覚ガンマ補正値 (暗い背景上の明るい文字でエッジが細く沈むのを防ぐ)
          float lum = dot(v_color.rgb, vec3(0.299, 0.587, 0.114));
          float gamma = mix(1.12, 1.56, clamp(lum, 0.0, 1.0));

          // 直接ラスタライズビットマップモード (36px未満の通常文字用)
          if (is_bitmap > 0.5) {
              float a = texture(u_texture, v_uv).r;
              if (a < 0.004) discard;

              // weight 指定時の太さ補正
              if (abs(raw_weight) > 0.001) {
                  float w_bias = clamp(raw_weight * 0.25, -0.35, 0.45);
                  a = clamp((a - 0.5 * (1.0 - w_bias)) / max(1.0 - abs(w_bias) * 0.5, 0.2) + 0.5, 0.0, 1.0);
              }

              // sRGB 知覚ガンマ補正によってアンチエイリアス境界のかすれ・輝度低下を解消
              float a_corrected = pow(clamp(a, 0.0, 1.0), 1.0 / gamma);
              vec4 col = vec4(v_color.rgb, v_color.a * a_corrected);
              if (col.a < 0.001) discard;
              fragColor = col;
              return;
          }

          // 1チャンネル GL_RED アトラスからサンプリング (SDFモード)
          float dist = texture(u_texture, v_uv).r;

          // 等方的なユークリッド勾配 (fwidth のマンハッタン距離による斜め線のボヤけを防止)
          vec2 grad = vec2(dFdx(dist), dFdy(dist));
          float raw_fw = length(grad);
          float fw = max(raw_fw * 0.65, 0.001);

          // エッジ閾値 (weight による手動調整: SDF_PADDING=10, ONEDGE=128 => 1pxあたり 12.8/255 = 0.0502)
          float edge_threshold = 0.5 - atlas_weight * 0.0502;

          // 1. 本体のアルファ + 知覚ガンマ補正
          float body_alpha;
          if (outline_width > 0.0) {
              float b_fw = max(fw * 0.75, 0.002);
              body_alpha = smoothstep(edge_threshold - b_fw, edge_threshold + b_fw, dist);
          } else {
              body_alpha = smoothstep(edge_threshold - fw, edge_threshold + fw, dist);
              body_alpha = pow(body_alpha, 1.0 / gamma);
          }

          // 2. アウトライン (袋文字)
          float border_alpha = 0.0;
          if (outline_width > 0.0) {
              float outline_offset = max(outline_width * 0.0502, fw * 1.5);
              float border_dist = dist + outline_offset;
              float b_alpha = smoothstep(edge_threshold - fw, edge_threshold + fw, border_dist);
              float edge_fade = smoothstep(0.001, 0.02, dist);
              border_alpha = b_alpha * edge_fade;
          }

          // 3. ドロップシャドウ
          float shadow_alpha = 0.0;
          if (shadow_color.a > 0.0 && (shadow_offset.x != 0.0 || shadow_offset.y != 0.0 || shadow_blur > 0.0)) {
              vec2 tex_size = vec2(textureSize(u_texture, 0));
              vec2 s_uv = v_uv - shadow_offset / tex_size;
              float s_dist = texture(u_texture, s_uv).r;
              float s_fw = fw + shadow_blur * 0.0502;
              float s_alpha = smoothstep(0.5 - s_fw, 0.5 + s_fw, s_dist) * shadow_color.a;
              float s_edge_fade = smoothstep(0.001, 0.02, s_dist);
              shadow_alpha = s_alpha * s_edge_fade;
          }

          // 4. 文字本体とアウトラインの合成 (正確な Porter-Duff Over)
          vec4 body = vec4(v_color.rgb, v_color.a * body_alpha);
          vec4 border = vec4(outline_color.rgb, outline_color.a * border_alpha);

          vec4 shape;
          if (outline_width > 0.0) {
              float a_out = body.a + border.a * (1.0 - body.a);
              if (a_out > 0.0001) {
                  vec3 rgb_out = (body.rgb * body.a + border.rgb * border.a * (1.0 - body.a)) / a_out;
                  shape = vec4(rgb_out, a_out);
              } else {
                  shape = vec4(0.0);
              }
          } else {
              shape = body;
          }

          // 5. シャドウとの合成 (Straight Alpha Porter-Duff Over)
          float final_a = shape.a + shadow_alpha * (1.0 - shape.a);
          if (final_a < 0.001) {
              discard;
          }

          vec3 final_rgb = (shape.rgb * shape.a + shadow_color.rgb * shadow_alpha * (1.0 - shape.a)) / final_a;
          fragColor = vec4(final_rgb, final_a);
      }
    GLSL
  end
end

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
      layout (location = 5) in vec4 in_param3;       // weight, unused, unused, unused
      layout (location = 6) in vec4 in_uv;
      uniform vec2 u_resolution;

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
          ndc.y = -ndc.y;
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

          // 直接ラスタライズビットマップモード (14px以下の極小文字用)
          // 距離場計算を通さず、TrueType直接ラスタライズされたアルファ値をそのまま出力 (1ドット単位で超高精細)
          if (is_bitmap > 0.5) {
              float a = texture(u_texture, v_uv).r;
              vec4 col = vec4(v_color.rgb, v_color.a * a);
              if (col.a < 0.001) discard;
              fragColor = col;
              return;
          }

          // 1チャンネル GL_RED アトラスからサンプリング
          float dist = texture(u_texture, v_uv).r;

          // 画面1ピクセルあたりのSDFテクセル変化量
          float raw_fw = fwidth(dist);

          // アンチエイリアス幅: 画面上 ちょうど1ピクセル幅
          float fw = max(raw_fw * 0.5, 0.002);

          // エッジ閾値 (weight による手動調整)
          float edge_threshold = 0.5 - atlas_weight * 0.04183;

          // 1. 本体のアルファ
          // 小サイズ文字 (raw_fw > 0.02) では、画面1ピクセルに対してアトラスが激しく縮小されるため、
          // 4-Tap サブピクセル・スーパーサンプリング (Box Filter) でサンプリング漏れ・線の途切れ・潰れを防止
          float body_alpha;
          if (raw_fw > 0.02) {
              vec2 d_uv_x = dFdx(v_uv) * 0.35;
              vec2 d_uv_y = dFdy(v_uv) * 0.35;
              float d0 = texture(u_texture, v_uv + d_uv_x + d_uv_y).r;
              float d1 = texture(u_texture, v_uv - d_uv_x + d_uv_y).r;
              float d2 = texture(u_texture, v_uv + d_uv_x - d_uv_y).r;
              float d3 = texture(u_texture, v_uv - d_uv_x - d_uv_y).r;
              float a0 = clamp((d0 - edge_threshold) / (fw * 2.0) + 0.5, 0.0, 1.0);
              float a1 = clamp((d1 - edge_threshold) / (fw * 2.0) + 0.5, 0.0, 1.0);
              float a2 = clamp((d2 - edge_threshold) / (fw * 2.0) + 0.5, 0.0, 1.0);
              float a3 = clamp((d3 - edge_threshold) / (fw * 2.0) + 0.5, 0.0, 1.0);
              body_alpha = (a0 + a1 + a2 + a3) * 0.25;
          } else {
              body_alpha = clamp((dist - edge_threshold) / (fw * 2.0) + 0.5, 0.0, 1.0);
          }

          // 2. アウトライン (袋文字)
          float border_alpha = 0.0;
          if (outline_width > 0.0) {
              // fw に対して十分なオフセットを確保し、縮小時の潰れ・滲みを防止
              float outline_offset = max(outline_width * 0.04183, fw * 1.5);
              float border_dist = dist + outline_offset;
              float b_alpha = clamp((border_dist - edge_threshold) / (fw * 2.0) + 0.5, 0.0, 1.0);
              // Quad 端部でのクリッピングフェード
              float edge_fade = smoothstep(0.001, 0.02, dist);
              border_alpha = b_alpha * edge_fade;
          }

          // 3. ドロップシャドウ
          float shadow_alpha = 0.0;
          if (shadow_color.a > 0.0 && (shadow_offset.x != 0.0 || shadow_offset.y != 0.0 || shadow_blur > 0.0)) {
              vec2 tex_size = vec2(textureSize(u_texture, 0));
              vec2 s_uv = v_uv - shadow_offset / tex_size;
              float s_dist = texture(u_texture, s_uv).r;
              float s_fw = fw + shadow_blur * 0.04183;
              float s_alpha = smoothstep(0.5 - s_fw, 0.5 + s_fw, s_dist) * shadow_color.a;
              float s_edge_fade = smoothstep(0.001, 0.02, s_dist);
              shadow_alpha = s_alpha * s_edge_fade;
          }

          // 4. 文字本体とアウトラインの合成 (正確な Porter-Duff Over)
          // 従来の mix() による濁り・中間色の滲みを完全に排除
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

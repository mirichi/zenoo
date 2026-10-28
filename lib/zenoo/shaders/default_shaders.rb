# frozen_string_literal: true

module Zenoo
  module Shaders
    # Sprite / Mesh 統合インスタンシング描画用デフォルト頂点シェーダー
    # Stream 0 (divisor = 0, 8 floats): in_pos(2), in_uv(2), in_color(4)
    # Stream 1 (divisor = 1, 16 floats): in_inst_mat(4), in_inst_trans(4), in_inst_color(4), in_inst_uv(4)
    DEFAULT_SPRITE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2  in_pos;
      layout (location = 1) in vec2  in_uv;
      layout (location = 2) in vec4  in_color;
      layout (location = 3) in vec4  in_inst_mat;   // m00, m01, m10, m11 (2x2 アフィン変換行列)
      layout (location = 4) in vec4  in_inst_trans; // tx, ty, unused, unused (平行移動)
      layout (location = 5) in vec4  in_inst_color; // r, g, b, a (インスタンス乗算カラー)
      layout (location = 6) in vec4  in_inst_uv;    // u0, v0, uw, vh (SubImage UV領域)
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      out vec4 v_color;
      out vec2 v_uv;
      void main() {
          vec2 pos = vec2(
              in_inst_mat.x * in_pos.x + in_inst_mat.y * in_pos.y + in_inst_trans.x,
              in_inst_mat.z * in_pos.x + in_inst_mat.w * in_pos.y + in_inst_trans.y
          );

          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_inst_color * in_color;
          v_uv = in_inst_uv.xy + in_uv * in_inst_uv.zw;
      }
    GLSL

    # Sprite 用デフォルトフラグメントシェーダー
    DEFAULT_SPRITE_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec2 v_uv;
      uniform sampler2D u_texture;
      out vec4 fragColor;
      void main() {
          fragColor = v_color * texture(u_texture, v_uv);
      }
    GLSL

    # 互換用エイリアス
    DEFAULT_QUAD_VERTEX = DEFAULT_SPRITE_VERTEX
    DEFAULT_QUAD_FRAGMENT = DEFAULT_SPRITE_FRAGMENT

    # 単色・頂点カラー描画（三角形・ライン・単色パス）用頂点シェーダー（Uniform不要・最軽量）
    FLAT_PRIMITIVE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2 in_pos;
      layout (location = 1) in vec4 in_color;
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      out vec4 v_color;
      void main() {
          vec2 ndc = (in_pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
      }
    GLSL

    # 単色・頂点カラー描画用フラグメントシェーダー
    FLAT_PRIMITIVE_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      out vec4 fragColor;
      void main() {
          fragColor = v_color;
      }
    GLSL

    # ピクセルグラデーション描画用頂点シェーダー
    GRADIENT_PRIMITIVE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2 in_pos;
      layout (location = 1) in vec4 in_color;
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      out vec4 v_color;
      out vec2 v_pos;
      void main() {
          vec2 ndc = (in_pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
          v_pos = in_pos;
      }
    GLSL

    # ピクセルグラデーション描画用フラグメントシェーダー
    GRADIENT_PRIMITIVE_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec2 v_pos;
      uniform int u_grad_type; // 1: 線形グラデーション, 2: 放射グラデーション
      uniform vec4 u_grad_p0;
      uniform vec4 u_grad_p1;
      uniform vec4 u_grad_color0;
      uniform vec4 u_grad_color1;
      out vec4 fragColor;
      void main() {
          if (u_grad_type == 1) {
              vec2 dir = u_grad_p1.xy - u_grad_p0.xy;
              float len_sq = dot(dir, dir);
              vec2 dpos = v_pos - u_grad_p0.xy;
              float t = (len_sq > 0.0001) ? clamp(dot(dpos, dir) / len_sq, 0.0, 1.0) : 0.0;
              fragColor = mix(u_grad_color0, u_grad_color1, t);
          } else if (u_grad_type == 2) {
              vec2 center = u_grad_p0.xy;
              float r0 = u_grad_p0.z;
              float r1 = u_grad_p1.z;
              float d = length(v_pos - center);
              float dr = r1 - r0;
              float t = (abs(dr) > 0.0001) ? clamp((d - r0) / dr, 0.0, 1.0) : 0.0;
              fragColor = mix(u_grad_color0, u_grad_color1, t);
          } else {
              fragColor = v_color;
          }
      }
    GLSL

    # テクスチャ付きプリミティブ描画用頂点シェーダー (pos2, uv2, color4)
    TEXTURED_PRIMITIVE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2 in_pos;
      layout (location = 1) in vec2 in_uv;
      layout (location = 2) in vec4 in_color;
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      out vec4 v_color;
      out vec2 v_uv;
      void main() {
          vec2 ndc = (in_pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
          v_uv = in_uv;
      }
    GLSL

    # テクスチャ付きプリミティブ描画用フラグメントシェーダー
    TEXTURED_PRIMITIVE_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec2 v_uv;
      uniform sampler2D u_texture;
      out vec4 fragColor;
      void main() {
          fragColor = v_color * texture(u_texture, v_uv);
      }
    GLSL

    # 互換用エイリアス
    PRIMITIVE_VERTEX = FLAT_PRIMITIVE_VERTEX
    PRIMITIVE_FRAGMENT = FLAT_PRIMITIVE_FRAGMENT

    # ====================================================================
    # Tilemap Instancing 用シェーダー (8 floats/tile: pos_size4, uv4)
    # - in_pos_size: x, y, w, h (w < 0.0 の場合は対角反転＝UVのXY軸入れ替え)
    # - in_uv: u, v, uw, vh (反転時は負の uw, vh で表現)
    # - u_view: tx, ty, scale_x, scale_y (カメラ・オフセット・スケール変換)
    # - u_color: レイヤー乗算カラー & 不透明度 (r, g, b, a)
    # ====================================================================
    TILEMAP_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec4 in_pos_size;
      layout (location = 1) in vec4 in_uv;
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      uniform vec4 u_view;
      uniform vec4 u_color;
      out vec4 v_color;
      out vec2 v_uv;
      void main() {
          vec2 unit = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          float raw_w = in_pos_size.z;
          vec2 size = vec2(abs(raw_w), in_pos_size.w);
          vec2 local_pos = in_pos_size.xy + unit * size;

          vec2 view_scale = (u_view.z == 0.0 && u_view.w == 0.0) ? vec2(1.0, 1.0) : u_view.zw;
          vec2 pos = local_pos * view_scale + u_view.xy;

          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);

          vec4 tint = (u_color.a == 0.0 && u_color.r == 0.0 && u_color.g == 0.0 && u_color.b == 0.0) ? vec4(1.0) : u_color;
          v_color = tint;

          vec2 uv_unit = (raw_w < 0.0) ? unit.yx : unit;
          v_uv = in_uv.xy + uv_unit * in_uv.zw;
      }
    GLSL

    TILEMAP_FRAGMENT = DEFAULT_SPRITE_FRAGMENT
  end
end

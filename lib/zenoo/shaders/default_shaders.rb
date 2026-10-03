# frozen_string_literal: true

module Zenoo
  module Shaders
    # Sprite インスタンシング（画像描画）用デフォルト頂点シェーダー
    # bounds(4), color(4), uv(4), transform(4), pivot(4) の頂点レイアウト (20 floats)
    DEFAULT_SPRITE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec4 in_bounds;
      layout (location = 1) in vec4 in_color;
      layout (location = 2) in vec4 in_uv;
      layout (location = 3) in vec4 in_transform; // rot_rad, scale_x, scale_y, offset_mode (0: top_left, 1: center)
      layout (location = 4) in vec4 in_pivot;     // pivot_x, pivot_y, unused, unused
      uniform vec2 u_resolution;
      uniform float u_flip_y;
      out vec4 v_color;
      out vec2 v_uv;
      void main() {
          vec2 in_unit_pos = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          vec2 size = in_bounds.zw;
          vec2 pivot = in_pivot.xy;

          // ピボットからの相対位置とスケーリング
          vec2 rel = (in_unit_pos - pivot) * size * in_transform.yz;

          // 回転
          float rad = in_transform.x;
          float c = cos(rad);
          float s = sin(rad);
          vec2 rot = vec2(rel.x * c - rel.y * s, rel.x * s + rel.y * c);

          // 基準位置計算
          // in_transform.w == 0.0 (top_left): in_bounds.xy + pivot * size + rot
          // in_transform.w == 1.0 (center)  : in_bounds.xy + rot
          vec2 base_pos = in_bounds.xy + mix(pivot * size, vec2(0.0), in_transform.w);
          vec2 pos = base_pos + rot;

          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          float flip = (u_flip_y == 0.0) ? -1.0 : u_flip_y;
          ndc.y = ndc.y * flip;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
          v_uv = in_uv.xy + in_unit_pos * in_uv.zw;
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

    # 互換用エイリアス
    PRIMITIVE_VERTEX = FLAT_PRIMITIVE_VERTEX
    PRIMITIVE_FRAGMENT = FLAT_PRIMITIVE_FRAGMENT
  end
end

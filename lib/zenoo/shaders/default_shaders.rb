# frozen_string_literal: true

module Zenoo
  module Shaders
    # Sprite インスタンシング（画像描画）用デフォルト頂点シェーダー
    # bounds(4), color(4), uv(4) の最小限の頂点レイアウト (12 floats)
    DEFAULT_SPRITE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec4 in_bounds;
      layout (location = 1) in vec4 in_color;
      layout (location = 2) in vec4 in_uv;
      uniform vec2 u_resolution;
      out vec4 v_color;
      out vec2 v_uv;
      void main() {
          vec2 in_unit_pos = vec2(float(gl_VertexID & 1), float((gl_VertexID >> 1) & 1));
          vec2 pos = in_bounds.xy + in_unit_pos * in_bounds.zw;
          vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;
          ndc.y = -ndc.y;
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

    # 単色・グラデーション描画（三角形・ライン・ベクタパス）用頂点シェーダー
    PRIMITIVE_VERTEX = <<~'GLSL'
      #version 330 core
      layout (location = 0) in vec2 in_pos;
      layout (location = 1) in vec4 in_color;
      uniform vec2 u_resolution;
      out vec4 v_color;
      out vec2 v_pos;
      void main() {
          vec2 ndc = (in_pos / u_resolution) * 2.0 - 1.0;
          ndc.y = -ndc.y;
          gl_Position = vec4(ndc, 0.0, 1.0);
          v_color = in_color;
          v_pos = in_pos;
      }
    GLSL

    # 単色・グラデーション描画用フラグメントシェーダー
    PRIMITIVE_FRAGMENT = <<~'GLSL'
      #version 330 core
      in vec4 v_color;
      in vec2 v_pos;
      uniform int u_grad_type; // 0: 単色, 1: 線形グラデーション, 2: 放射グラデーション
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
  end
end

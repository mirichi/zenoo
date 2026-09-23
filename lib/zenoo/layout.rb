# frozen_string_literal: true

module Zenoo
  # 描画プリミティブトポロジー (OpenGL GLenum準拠)
  module Topology
    POINTS         = 0
    LINES          = 1
    LINE_LOOP      = 2
    LINE_STRIP     = 3
    TRIANGLES      = 4
    TRIANGLE_STRIP = 5
    TRIANGLE_FAN   = 6
  end

  # 動的頂点レイアウト (1バイト属性要素数列: 各バイトが float の要素数 1〜4 を表す)
  module Layout
    POS2_COLOR4         = "\x02\x04"                 # pos(2), color(4) -> 6 floats
    POS2_UV2_COLOR4     = "\x02\x02\x04"             # pos(2), uv(2), color(4) -> 8 floats
    LINE                = "\x02\x04"                 # pos(2), color(4) -> 6 floats
    CARD_INSTANCED      = "\x04\x04\x04\x04\x04\x04" # bounds(4), color(4), p0(4), p1(4), p2(4), uv(4) -> 24 floats
    SPRITE_INSTANCED    = "\x04\x04\x04"             # bounds(4), color(4), uv(4) -> 12 floats
  end
end

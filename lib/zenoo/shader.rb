# frozen_string_literal: true

module Zenoo
  # カスタム GLSL シェーダー管理クラス
  class Shader
    # ユーザー向け Shader コンストラクタ
    # - 1引数: Fragment Shader 単体指定（DEFAULT_SPRITE_VERTEX を自動補完）
    # - 2引数: Vertex Shader, Fragment Shader を両方指定
    #
    # - `vert_or_frag` (`String`): Vertex Shader ソース（第2引数省略時は Fragment Shader ソース）
    # - `frag` (`String`, `nil`): Fragment Shader ソース
    def self.new(vert_or_frag, frag = nil)
      if frag.nil?
        Native::NativeShader.new(Shaders::DEFAULT_SPRITE_VERTEX, vert_or_frag)
      else
        Native::NativeShader.new(vert_or_frag, frag)
      end
    end
  end
end

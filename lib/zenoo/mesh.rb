# frozen_string_literal: true

module Zenoo
  # 頂点バッファ・メッシュ管理クラス
  # 事前にパックされた頂点バイナリデータをキャッシュし、
  # 単一のZ値やUniformパラメータとともに描画キューへ投入して高速に再利用します。
  class Mesh
    attr_accessor :data, :count, :pipeline, :image, :shader, :uniforms, :blend

    # 初期化
    # - data: pack("f*") された頂点バイナリ文字列 (String)
    # - count: 描画する頂点数 (またはインスタンス数)
    # - pipeline: 描画パイプライン (:triangles, :lines, :triangle_strip, :textured_triangles,
    #             :textured_triangle_strip, :sprite, :card, または Backend::Pipeline)
    # - image: 描画に使用するテクスチャ (Zenoo::Image, 省略時は nil)
    # - shader: 描画に使用するシェーダー (Zenoo::Shader, 省略時はパイプライン既定または自動選択)
    # - uniforms: シェーダーに渡す Uniform ハッシュ (例: { u_time: 1.0, ... })
    # - blend: ブレンドモード (:alpha, :add, :multiply, :none)
    def initialize(data: nil,
                   count: 0,
                   pipeline: :triangles,
                   image: nil,
                   shader: nil,
                   uniforms: nil,
                   blend: :alpha)
      @data = data
      @count = count.to_i
      @pipeline = resolve_pipeline(pipeline)
      @image = image
      @shader = shader
      @uniforms = uniforms
      @blend = blend
    end

    # 描画キューに登録
    # 各オプション引数により、メッシュ保持値を一時的に上書き可能です。
    def draw(z: 0.0, uniforms: nil, shader: nil, image: nil, blend: nil)
      Window.draw_mesh(
        self,
        z: z,
        uniforms: uniforms,
        shader: shader,
        image: image,
        blend: blend
      )
    end

    private

    def resolve_pipeline(p)
      case p
      when Backend::Pipeline
        p
      when :triangles
        Backend::Pipelines::TRIANGLES
      when :lines
        Backend::Pipelines::LINES
      when :points
        Backend::Pipelines::POINTS
      when :triangle_strip
        Backend::Pipelines::TRIANGLE_STRIP
      when :textured_triangles
        Backend::Pipelines::TEXTURED_TRIANGLES
      when :textured_triangle_strip
        Backend::Pipelines::TEXTURED_TRIANGLE_STRIP
      when :sprite
        Backend::Pipelines::SPRITE
      when :card
        Backend::Pipelines::CARD
      else
        Backend::Pipelines::TRIANGLES
      end
    end
  end
end

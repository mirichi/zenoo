# frozen_string_literal: true

module Zenoo
  # 低レベル頂点バッファ・パイプライン管理クラス
  # パックされた頂点バイナリデータを保持し、指定パイプライン・シェーダーで描画キューへ投入します。
  # 座標変換や色は頂点データ自身に持たせるか、uniforms を介してシェーダーに伝達します。
  class Mesh
    attr_accessor :data, :count, :pipeline, :image, :shader, :uniforms, :blend

    # 初期化
    # - data: pack("f*") された頂点バイナリ文字列 (String)
    # - count: 描画する頂点数 (またはインスタンス数)
    # - pipeline: 描画パイプライン (:triangles, :lines, :points, :triangle_strip,
    #             :textured_triangles, :textured_triangle_strip, :sprite, :card, :tilemap, または Backend::Pipeline)
    # - image: 描画に使用するテクスチャ (Zenoo::Image, 省略時は nil)
    # - shader: 描画に使用するシェーダー (Zenoo::Shader, 省略時はパイプライン既定)
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

    # 頂点バッファの部分更新 (将来の VRAM バッファ直接転送への布石)
    def update(binary_data, offset: 0)
      return unless @data && binary_data
      @data[offset, binary_data.bytesize] = binary_data
    end

    # 描画キューに登録
    def draw(z: 0.0,
             uniforms: nil,
             shader: nil,
             image: nil,
             blend: nil)
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
      when :tilemap
        Backend::Pipelines::TILEMAP
      else
        Backend::Pipelines::TRIANGLES
      end
    end
  end
end

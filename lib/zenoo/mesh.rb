# frozen_string_literal: true

module Zenoo
  # 頂点バッファ・メッシュ管理クラス
  # 事前にパックされた頂点バイナリデータをキャッシュし、
  # 単一のZ値やUniformパラメータとともに描画キューへ投入して高速に再利用します。
  class Mesh
    attr_accessor :data, :count, :pipeline, :image, :shader, :uniforms, :blend
    attr_accessor :x, :y, :scale_x, :scale_y, :color, :alpha, :camera, :parallax_x, :parallax_y

    # 初期化
    # - data: pack("f*") された頂点バイナリ文字列 (String)
    # - count: 描画する頂点数 (またはインスタンス数)
    # - pipeline: 描画パイプライン (:triangles, :lines, :triangle_strip, :textured_triangles,
    #             :textured_triangle_strip, :sprite, :card, :tilemap, または Backend::Pipeline)
    # - image: 描画に使用するテクスチャ (Zenoo::Image, 省略時は nil)
    # - shader: 描画に使用するシェーダー (Zenoo::Shader, 省略時はパイプライン既定または自動選択)
    # - uniforms: シェーダーに渡す Uniform ハッシュ (例: { u_time: 1.0, ... })
    # - blend: ブレンドモード (:alpha, :add, :multiply, :none)
    # - x, y: メッシュ基準位置オフセット (デフォルト: 0.0)
    # - scale_x, scale_y: スケール倍率 (デフォルト: 1.0)
    # - color, alpha: 乗算カラーおよび不透明度 (0..255 または 0.0..1.0)
    # - camera: カメラ追従の有効/無効 (デフォルト: true)
    # - parallax_x, parallax_y: カメラスクロールに対する視差係数 (デフォルト: 1.0)
    def initialize(data: nil,
                   count: 0,
                   pipeline: :triangles,
                   image: nil,
                   shader: nil,
                   uniforms: nil,
                   blend: :alpha,
                   x: 0.0,
                   y: 0.0,
                   scale_x: 1.0,
                   scale_y: 1.0,
                   color: nil,
                   alpha: 255,
                   camera: true,
                   parallax_x: 1.0,
                   parallax_y: 1.0)
      @data = data
      @count = count.to_i
      @pipeline = resolve_pipeline(pipeline)
      @image = image
      @shader = shader
      @uniforms = uniforms
      @blend = blend
      @x = x.to_f
      @y = y.to_f
      @scale_x = scale_x.to_f
      @scale_y = scale_y.to_f
      @color = color
      @alpha = alpha
      @camera = camera
      @parallax_x = parallax_x.to_f
      @parallax_y = parallax_y.to_f
    end

    def scale=(val)
      s = val.to_f
      @scale_x = s
      @scale_y = s
    end

    # 描画キューに登録
    # 各オプション引数により、メッシュ保持値を一時的に上書き可能です。
    def draw(x: nil,
             y: nil,
             scale_x: nil,
             scale_y: nil,
             color: nil,
             alpha: nil,
             camera: nil,
             parallax_x: nil,
             parallax_y: nil,
             z: 0.0,
             uniforms: nil,
             shader: nil,
             image: nil,
             blend: nil)
      Window.draw_mesh(
        self,
        x: x,
        y: y,
        scale_x: scale_x,
        scale_y: scale_y,
        color: color,
        alpha: alpha,
        camera: camera,
        parallax_x: parallax_x,
        parallax_y: parallax_y,
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

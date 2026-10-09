class Zenoo::Image
  # 内部描画キュー（Backend が使用）
  attr_accessor :__draw_queue

  # サブ画像かどうか判定
  def sub_image?
    x != 0 || y != 0 || width != texture_width || height != texture_height
  end

  # テクスチャ全体における正規化 UV 座標 [u, v, uw, vh]
  def uv
    tw = texture_width.to_f
    th = texture_height.to_f
    return [0.0, 0.0, 1.0, 1.0] if tw <= 0.0 || th <= 0.0

    [x.to_f / tw, y.to_f / th, width.to_f / tw, height.to_f / th]
  end


  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_rect(...)
  # end
  # ※ sub_image に対して呼び出された場合は、自動的に該当領域へクリッピングされます。
  def self.render_to(target)
    is_sub = target.respond_to?(:sub_image?) && target.sub_image?
    old_target = Zenoo::Backend.current_target
    Zenoo::Backend.current_target = target

    # オフスクリーン描画中はワールドカメラの影響を遮断 (ローカル座標系にリセット)
    old_camera = Zenoo::Window.respond_to?(:camera) ? Zenoo::Window.camera : nil
    Zenoo::Window.camera = nil if Zenoo::Window.respond_to?(:camera=)

    if is_sub
      prev_ox = Zenoo::Window.offset_x
      prev_oy = Zenoo::Window.offset_y
      Zenoo::Window.offset_x = target.x.to_f
      Zenoo::Window.offset_y = target.y.to_f
      Zenoo::Backend.push_clip([target.x.to_f, target.y.to_f, target.width.to_f, target.height.to_f], 0.0)
    end

    yield
  ensure
    if is_sub
      Zenoo::Backend.pop_clip
      Zenoo::Window.offset_x = prev_ox
      Zenoo::Window.offset_y = prev_oy
    end
    Zenoo::Window.camera = old_camera if Zenoo::Window.respond_to?(:camera=)
    Zenoo::Backend.current_target = old_target
  end

  # シェーダーフィルターの適用 (画像加工・ポストプロセス)
  # 非破壊版: 加工済みの新しい Image を生成して返します
  def apply_filter(shader, uniforms: nil)
    result = Zenoo::Image.new(width, height)
    Zenoo::Image.render_to(result) do
      Zenoo::Window.clear([0, 0, 0, 0])
      Zenoo::Window.draw_image(0, 0, self, shader: shader, uniforms: uniforms)
    end
    Zenoo::Backend.flush_image(result)
    result
  end

  # 破壊版: 自身のテクスチャをシェーダー処理で上書き加工します
  def apply_filter!(shader, uniforms: nil)
    filtered = apply_filter(shader, uniforms: uniforms)
    if respond_to?(:replace_texture!)
      replace_texture!(filtered)
    else
      Zenoo::Image.render_to(self) do
        Zenoo::Window.clear([0, 0, 0, 0])
        Zenoo::Window.draw_image(0, 0, filtered)
      end
      Zenoo::Backend.flush_image(self)
    end
    self
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == "spinel"
    def texture_filter
      raw_texture_filter == 0 ? :nearest : :linear
    end

    def texture_filter=(val)
      self.raw_texture_filter = (val == :nearest || val == 0) ? 0 : 1
    end

    def self.default_texture_filter
      raw_default_texture_filter == 0 ? :nearest : :linear
    end

    def self.default_texture_filter=(val)
      self.raw_default_texture_filter = (val == :nearest || val == 0) ? 0 : 1
    end
  end
end

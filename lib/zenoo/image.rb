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
    Zenoo::Backend.current_target = old_target
  end

  if defined?(RUBY_ENGINE) && RUBY_ENGINE == "spinel"
    def filter
      raw_filter == 0 ? :nearest : :linear
    end

    def filter=(val)
      self.raw_filter = (val == :nearest || val == 0) ? 0 : 1
    end

    def self.default_filter
      raw_default_filter == 0 ? :nearest : :linear
    end

    def self.default_filter=(val)
      self.raw_default_filter = (val == :nearest || val == 0) ? 0 : 1
    end
  end
end

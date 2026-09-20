class Zenoo::Image
  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_card(...)
  # end
  def self.render_to(target)
    target.set_as_render_target
    yield
  ensure
    reset_render_target
  end
end

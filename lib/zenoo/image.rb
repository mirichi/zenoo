class Zenoo::Image
  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_card(...)
  # end
  def self.render_to(target, &block)
    Zenoo::Window.with_target(target, &block)
  end
end

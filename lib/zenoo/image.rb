class Zenoo::Image
  # 内部描画キュー（Backend が使用）
  attr_accessor :__draw_queue

  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_card(...)
  # end
  def self.render_to(target, &block)
    Zenoo::Window.with_target(target, &block)
  end
end

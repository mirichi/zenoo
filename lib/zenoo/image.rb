class Zenoo::Image
  # 内部描画キュー（Backend が使用）
  attr_accessor :__draw_queue

  # サブ画像かどうか判定
  def sub_image?
    x != 0 || y != 0 || width != texture_width || height != texture_height
  end


  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_card(...)
  # end
  # ※ sub_image に対して呼び出された場合は、自動的に該当領域へクリッピングされます。
  def self.render_to(target, &block)
    if target.respond_to?(:sub_image?) && target.sub_image?
      Zenoo::Window.with_target(target) do
        Zenoo::Window.clip(target.x, target.y, target.width, target.height, local: true) do
          yield
        end
      end
    else
      Zenoo::Window.with_target(target, &block)
    end
  end
end

module Zenoo
  class Image
    attr_reader :native

    def initialize(width, height)
      @native = Native::Image.new(width, height)
    end

    def self.load(path)
      img = allocate
      img.instance_variable_set(:@native, Native::Image.load(path))
      img
    end

    def width
      @native.width
    end

    def height
      @native.height
    end

    # オフスクリーンFBO描画ブロック
    # Image.render_to(canvas) do
    #   Window.draw_card(...)
    # end
    def self.render_to(target)
      target.native.set_as_render_target
      yield
    ensure
      Native::Image.reset_render_target
    end
  end
end

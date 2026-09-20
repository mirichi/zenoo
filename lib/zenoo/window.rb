module Zenoo
  module Window
    COLOR_MAP = {
      white:   [1.0, 1.0, 1.0, 1.0],
      black:   [0.0, 0.0, 0.0, 1.0],
      red:     [1.0, 0.2, 0.2, 1.0],
      green:   [0.2, 1.0, 0.3, 1.0],
      blue:    [0.1, 0.5, 1.0, 1.0],
      cyan:    [0.0, 0.9, 1.0, 1.0],
      magenta: [1.0, 0.2, 0.8, 1.0],
      yellow:  [1.0, 0.9, 0.1, 1.0],
      clear:   [0.0, 0.0, 0.0, 0.0]
    }

    def self.normalize_color(col)
      return [1.0, 1.0, 1.0, 1.0] if col.nil?
      return COLOR_MAP[col] if COLOR_MAP.key?(col)

      if col.is_a?(Array)
        r = (col[0] || 0) / 255.0
        g = (col[1] || 0) / 255.0
        b = (col[2] || 0) / 255.0
        a = (col[3] || 255) / 255.0
        [r.to_f, g.to_f, b.to_f, a.to_f]
      elsif col.is_a?(Integer)
        r = ((col >> 24) & 0xFF) / 255.0
        g = ((col >> 16) & 0xFF) / 255.0
        b = ((col >> 8) & 0xFF) / 255.0
        a = (col & 0xFF) / 255.0
        [r, g, b, a]
      else
        [1.0, 1.0, 1.0, 1.0]
      end
    end

    def self.color_to_uint32(col)
      floats = normalize_color(col)
      r = (floats[0] * 255).to_i & 0xFF
      g = (floats[1] * 255).to_i & 0xFF
      b = (floats[2] * 255).to_i & 0xFF
      a = (floats[3] * 255).to_i & 0xFF
      (r << 24) | (g << 16) | (b << 8) | a
    end

    # DXRuby風メインループ
    def self.loop(width = 1280, height = 720, title = "Zenoo", fullscreen: false, vsync: false, &block)
      Native::Window.init(width, height, title, fullscreen)
      Native::Window.vsync = vsync
      Native::Window.target_fps = 60

      while Native::Window.update
        Native::Window.clear(color_to_uint32([18, 20, 30, 255]))
        yield
      end
    ensure
      Native::Window.shutdown
    end

    def self.clear(color)
      Native::Window.clear(color_to_uint32(color))
    end

    def self.width
      Native::Window.size[0]
    end

    def self.height
      Native::Window.size[1]
    end

    def self.delta_time
      Native::Window.delta_time
    end

    def self.fps
      dt = delta_time
      dt > 0.0001 ? (1.0 / dt) : 60.0
    end

    def self.vsync=(val)
      Native::Window.vsync = val
    end

    @current_shader = nil

    # ブロック内でのシェーダー適用スコープ (RAII / ensure で確実に元の状態に戻る)
    def self.with_shader(shader)
      old_shader = @current_shader
      @current_shader = shader
      yield
    ensure
      @current_shader = old_shader
    end

    # ----------------------------------------------------
    # 描画 API (シェーダーは引数またはブロックで自動制御！)
    # ----------------------------------------------------
    def self.draw_card(x, y, w, h, radius: 0.0, color: :white, border: nil, shadow: nil, image: nil, shader: nil)
      effective_shader = shader || SDFCardShader.instance
      c_color = normalize_color(color)

      b_width = 0.0
      b_color = [0.0, 0.0, 0.0, 0.0]
      if border
        b_width = border[:width] || border[0] || 1.0
        b_color = normalize_color(border[:color] || border[1] || :cyan)
      end

      s_blur = 0.0
      s_color = [0.0, 0.0, 0.0, 0.0]
      if shadow
        s_blur = shadow[:blur] || shadow[0] || 8.0
        s_color = normalize_color(shadow[:color] || shadow[1] || [0, 0, 0, 180])
      end

      mode = image ? 1.0 : 0.0
      p0 = [radius.to_f, b_width.to_f, s_blur.to_f, mode]
      uv = [0.0, 0.0, 1.0, 1.0]

      native_img = image ? image.native : nil
      native_shader = effective_shader ? effective_shader.native : nil
      Native::Renderer.draw_quad(x, y, w, h, uv, c_color, p0, b_color, s_color, native_img, native_shader)
    end

    def self.draw_rect(x, y, w, h, color = :white, shader: nil)
      effective_shader = shader || @current_shader
      native_shader = effective_shader ? effective_shader.native : nil
      c_color = normalize_color(color)
      Native::Renderer.draw_quad(x, y, w, h, [0.0, 0.0, 1.0, 1.0], c_color, nil, nil, nil, nil, native_shader)
    end

    def self.draw_rounded_rect(x, y, w, h, radius, color = :white, shader: nil)
      draw_card(x, y, w, h, radius: radius, color: color, shader: shader)
    end

    def self.draw_image(x, y, image, color = :white, shader: nil)
      return unless image
      effective_shader = shader || @current_shader
      native_shader = effective_shader ? effective_shader.native : nil
      c_color = normalize_color(color)
      Native::Renderer.draw_quad(x, y, image.width, image.height, [0.0, 0.0, 1.0, 1.0], c_color, nil, nil, nil, image.native, native_shader)
    end
  end
end

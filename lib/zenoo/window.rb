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

      if col.is_a?(Color)
        col.to_f4
      elsif col.is_a?(Array)
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
      return col.to_i if col.is_a?(Color)

      floats = normalize_color(col)
      r = (floats[0] * 255).to_i & 0xFF
      g = (floats[1] * 255).to_i & 0xFF
      b = (floats[2] * 255).to_i & 0xFF
      a = (floats[3] * 255).to_i & 0xFF
      r_part = r >= 128 ? ((r - 256) * 16777216) : (r << 24)
      r_part | (g << 16) | (b << 8) | a
    end

    # DXRuby風メインループ
    def self.loop(width = 1280, height = 720, title = "Zenoo", fullscreen: false, vsync: false, &block)
      Native::Window.init(width, height, title, fullscreen)
      Native::Window.vsync = (vsync ? 1 : 0)
      Native::Window.target_fps = 60

      while Native::Window.update
        Native::Window.clear(color_to_uint32([18, 20, 30, 255]))
        Zenoo::GUI.begin_frame if defined?(Zenoo::GUI)
        yield
        Zenoo::GUI.end_frame if defined?(Zenoo::GUI)
      end
    ensure
      Native::Window.shutdown
    end

    def self.time
      Native::Window.time
    end

    def self.clear(color)
      Native::Window.clear(color_to_uint32(color))
    end

    def self.width
      Native::Window.size_w
    end

    def self.height
      Native::Window.size_h
    end

    def self.size
      [Native::Window.size_w, Native::Window.size_h]
    end

    def self.delta_time
      Native::Window.delta_time
    end

    def self.fps
      dt = delta_time
      if dt > 0.001 && dt < 1.0
        1.0 / dt
      else
        60.0
      end
    end

    def self.vsync=(val)
      Native::Window.vsync = (val ? 1 : 0)
    end

    @current_shader = nil
    @card_shader = nil

    def self.card_shader
      @card_shader ||= Shader.new(Shaders::CARD_VERTEX, Shaders::CARD_FRAGMENT)
    end

    # ブロック内でのシェーダー適用スコープ (RAII / ensure で確実に元の状態に戻る)
    def self.with_shader(shader)
      old_shader = @current_shader
      @current_shader = shader
      yield
    ensure
      @current_shader = old_shader
    end

    # ----------------------------------------------------
    # 描画 API 
    # ----------------------------------------------------
    def self.draw_card(x, y, w, h, radius: 0.0, color: :white, border: nil, shadow: nil, image: nil)
      c_color = normalize_color(color)

      b_width = 0.0
      b_color = [0.0, 0.0, 0.0, 0.0]
      if border
        if border.is_a?(Hash)
          b_width = (border[:width] || 1.0).to_f
          b_color = normalize_color(border[:color] || :cyan)
        elsif border.is_a?(Array)
          b_width = (border[0] || 1.0).to_f
          b_color = normalize_color(border[1] || :cyan)
        end
      end

      s_blur = 0.0
      s_color = [0.0, 0.0, 0.0, 0.0]
      if shadow
        if shadow.is_a?(Hash)
          s_blur = (shadow[:blur] || 8.0).to_f
          s_color = normalize_color(shadow[:color] || [0, 0, 0, 180])
        elsif shadow.is_a?(Array)
          s_blur = (shadow[0] || 8.0).to_f
          s_color = normalize_color(shadow[1] || [0, 0, 0, 180])
        end
      end

      mode = image ? 1.0 : 0.0
      p0 = [radius.to_f, b_width.to_f, s_blur.to_f, mode]
      uv = [0.0, 0.0, 1.0, 1.0]

      Native::Renderer.draw_quad(x, y, w, h, uv, c_color, p0, b_color, s_color, image, card_shader)
    end

    def self.draw_rect(x, y, w, h, color = :white, shader: nil)
      effective_shader = shader || @current_shader
      c_color = normalize_color(color)
      Native::Renderer.draw_quad(x, y, w, h, [0.0, 0.0, 1.0, 1.0], c_color, nil, nil, nil, nil, effective_shader)
    end

    def self.draw_rounded_rect(x, y, w, h, radius, color = :white)
      draw_card(x, y, w, h, radius: radius, color: color)
    end

    def self.draw_image(x, y, image, color = :white, shader: nil)
      return unless image
      effective_shader = shader || @current_shader
      c_color = normalize_color(color)
      Native::Renderer.draw_quad(x, y, image.width, image.height, [0.0, 0.0, 1.0, 1.0], c_color, nil, nil, nil, image, effective_shader)
    end

    def self.draw_triangle(x1, y1, x2, y2, x3, y3, color = :white)
      c = normalize_color(color)
      Native::Renderer.draw_triangle(
        x1.to_f, y1.to_f, x2.to_f, y2.to_f, x3.to_f, y3.to_f,
        c[0].to_f, c[1].to_f, c[2].to_f, c[3].to_f
      )
    end

    def self.draw_line(x1, y1, x2, y2, color = :white)
      c = normalize_color(color)
      Native::Renderer.draw_line(
        x1.to_f, y1.to_f, x2.to_f, y2.to_f,
        c[0].to_f, c[1].to_f, c[2].to_f, c[3].to_f
      )
    end

    def self.draw_text(x, y, text, size: 16, color: :white)
      Font.draw_text(x, y, text, size: size, color: color)
    end
  end
end

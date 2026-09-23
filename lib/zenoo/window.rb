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
        r = 0.0
        g = 0.0
        b = 0.0
        a = 1.0
        count = 0
        col.each_with_index do |v, i|
          vf = v.to_f
          r = vf if i == 0
          g = vf if i == 1
          b = vf if i == 2
          a = vf if i == 3
          count += 1
        end
        if r <= 1.0 && g <= 1.0 && b <= 1.0 && (count < 4 || a <= 1.0)
          [r, g, b, a]
        else
          a = (count >= 4) ? (a / 255.0) : 1.0
          [r / 255.0, g / 255.0, b / 255.0, a]
        end
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
      rf = 0.0
      gf = 0.0
      bf = 0.0
      af = 1.0
      floats.each_with_index do |v, i|
        vf = v.to_f
        rf = vf if i == 0
        gf = vf if i == 1
        bf = vf if i == 2
        af = vf if i == 3
      end
      r = (rf * 255).to_i & 0xFF
      g = (gf * 255).to_i & 0xFF
      b = (bf * 255).to_i & 0xFF
      a = (af * 255).to_i & 0xFF
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
    def self.draw_card(x, y, w, h,
                       radius: 0.0,
                       color: :white,
                       border_width: 0.0,
                       border_color: :cyan,
                       shadow_blur: 0.0,
                       shadow_color: [0, 0, 0, 180],
                       image: nil)
      c_color = normalize_color(color)
      b_width = border_width.to_f
      b_color = (b_width > 0.0) ? normalize_color(border_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_color = (s_blur > 0.0) ? normalize_color(shadow_color) : [0.0, 0.0, 0.0, 0.0]

      mode = image ? 1.0 : 0.0
      p0 = [radius.to_f, b_width, s_blur, mode]
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
      cr = 1.0; cg = 1.0; cb = 1.0; ca = 1.0
      c.each_with_index do |v, i|
        vf = v.to_f
        cr = vf if i == 0
        cg = vf if i == 1
        cb = vf if i == 2
        ca = vf if i == 3
      end
      Native::Renderer.draw_triangle(
        x1.to_f, y1.to_f, x2.to_f, y2.to_f, x3.to_f, y3.to_f,
        cr, cg, cb, ca
      )
    end

    def self.draw_line(x1, y1, x2, y2, color = :white)
      c = normalize_color(color)
      cr = 1.0; cg = 1.0; cb = 1.0; ca = 1.0
      c.each_with_index do |v, i|
        vf = v.to_f
        cr = vf if i == 0
        cg = vf if i == 1
        cb = vf if i == 2
        ca = vf if i == 3
      end
      Native::Renderer.draw_line(
        x1.to_f, y1.to_f, x2.to_f, y2.to_f,
        cr, cg, cb, ca
      )
    end

    @sdf_font_shader = nil

    def self.sdf_font_shader
      @sdf_font_shader ||= Shader.new(Shaders::FONT_SDF_VERTEX, Shaders::FONT_SDF_FRAGMENT)
    end

    class CharContext
      attr_accessor :char, :index, :line_index, :x, :y, :w, :h, :color, :scale, :visible
      attr_accessor :outline_width, :outline_color

      def reset(char, index, gx, gy, gw, gh, default_color, def_out_w, def_out_c)
        @char = char
        @index = index
        @line_index = 0
        @x = gx
        @y = gy
        @w = gw
        @h = gh
        @color = default_color
        @scale = 1.0
        @visible = true
        @outline_width = def_out_w
        @outline_color = def_out_c
      end
    end

    @char_ctx = CharContext.new

    # ----------------------------------------------------
    # 高品質 SDF テキスト描画 API (改行なし・文字列直接描画)
    # ----------------------------------------------------
    def self.draw_text(x, y, text,
                       font: nil,
                       size: 24,
                       color: :white,
                       outline_width: 0.0,
                       outline_color: :black,
                       shadow_blur: 0.0,
                       shadow_color: [0, 0, 0, 180],
                       shadow_dx: 0.0,
                       shadow_dy: 0.0,
                       &block)
      return if text.nil?

      target_font = font || Font.default
      return unless target_font

      atlas = Font.atlas_image
      return unless atlas

      f_size = size.to_f
      f_size = 24.0 if f_size <= 0.0

      c_color = normalize_color(color)

      outline_w = outline_width.to_f
      outline_c = (outline_w > 0.0) ? normalize_color(outline_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_dx = shadow_dx.to_f
      s_dy = shadow_dy.to_f
      s_c = (s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? normalize_color(shadow_color) : [0.0, 0.0, 0.0, 0.0]

      # 画面上ピクセルとアトラスピクセルのスケール比補正 (アトラス基準サイズは48px)
      scale_ratio = 48.0 / f_size
      s_atlas_dx = s_dx * scale_ratio
      s_atlas_dy = s_dy * scale_ratio
      s_atlas_blur = s_blur * scale_ratio
      s_atlas_outline_w = outline_w * scale_ratio

      p0 = [s_atlas_outline_w, s_atlas_blur, s_atlas_dx, s_atlas_dy]
      p1 = outline_c
      p2 = s_c
      shader = sdf_font_shader

      metrics = target_font.metrics(f_size)
      ascent = metrics[:ascent]

      pen_x = x.to_f
      pen_y = y.to_f + ascent

      str = text.to_s
      chars = str.chars
      len = chars.length
      return if len == 0

      if block_given?
        ctx = @char_ctx
        i = 0
        while i < len
          ch = chars[i]
          glyph_data = target_font.get_glyph(ch, f_size)
          adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

          if glyph_data && glyph_data[0] # visible == true
            _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv = glyph_data
            gx = pen_x + x0
            gy = pen_y + y0
            gw = x1 - x0
            gh = y1 - y0
            uv = [u0, v0, u1 - u0, v1 - v0]

            ctx.reset(ch, i, gx, gy, gw, gh, c_color, outline_w, outline_c)
            yield(ctx)

            if ctx.visible
              cgx = ctx.x
              cgy = ctx.y
              cgw = ctx.w
              cgh = ctx.h

              if ctx.scale != 1.0
                sc = ctx.scale
                # 中心を基準にスケーリング
                cx = cgx + cgw * 0.5
                cy = cgy + cgh * 0.5
                cgw *= sc
                cgh *= sc
                cgx = cx - cgw * 0.5
                cgy = cy - cgh * 0.5
              end

              cur_color = (ctx.color.equal?(c_color)) ? c_color : normalize_color(ctx.color)
              cur_p0 = (ctx.outline_width == outline_w) ? p0 : [ctx.outline_width * scale_ratio, s_atlas_blur, s_atlas_dx, s_atlas_dy]
              cur_p1 = (ctx.outline_color.equal?(outline_c)) ? outline_c : normalize_color(ctx.outline_color)

              Native::Renderer.draw_quad(
                cgx, cgy, cgw, cgh,
                uv, cur_color, cur_p0, cur_p1, p2, atlas, shader
              )
            end
          end

          pen_x += adv
          i += 1
        end
      else
        i = 0
        while i < len
          ch = chars[i]
          glyph_data = target_font.get_glyph(ch, f_size)
          adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

          if glyph_data && glyph_data[0] # visible == true
            _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv = glyph_data
            gx = pen_x + x0
            gy = pen_y + y0
            gw = x1 - x0
            gh = y1 - y0
            uv = [u0, v0, u1 - u0, v1 - v0]

            Native::Renderer.draw_quad(
              gx, gy, gw, gh,
              uv, c_color, p0, p1, p2, atlas, shader
            )
          end

          pen_x += adv
          i += 1
        end
      end
    end

    def self.canvas
      @canvas ||= Canvas.new
    end

    def self.draw_path
      c = canvas
      c.begin_path
      yield c
    end
  end
end

# frozen_string_literal: true

module Zenoo
  class TextLayout
    Glyph = Struct.new(:char, :index, :line_index, :x, :y, :w, :h, :uv, :advance_x)

    attr_reader :text, :font, :size, :font_size, :line_spacing, :max_width, :align
    attr_reader :width, :height, :glyphs, :lines

    def initialize(text, opt_or_size = 24, line_spacing = 1.0, max_width = nil, align = :left, font: nil, size: nil)
      @text = text.to_s
      @font = font || Font.default
      raise "Font not found or specified!" unless @font


      if opt_or_size.is_a?(Hash)
        @size = (opt_or_size[:size] || 24).to_f
        @line_spacing = (opt_or_size[:line_spacing] || 1.0).to_f
        @max_width = opt_or_size[:max_width] ? opt_or_size[:max_width].to_f : nil
        @align = opt_or_size[:align] || :left
      else
        @size = (size || opt_or_size || 24).to_f
        @line_spacing = line_spacing.to_f
        @max_width = max_width ? max_width.to_f : nil
        @align = align || :left
      end
      @font_size = @size

      @glyphs = []
      @lines = []

      compute_layout
      freeze
    end

    private

    def compute_layout
      metrics = @font.metrics(@size)
      ascent = metrics[:ascent]
      descent = metrics[:descent]
      line_gap = metrics[:line_gap]
      line_height = (ascent - descent + line_gap) * @line_spacing

      current_line_glyphs = []
      pen_x = 0.0
      pen_y = 0.0
      line_index = 0
      char_index = 0
      max_line_w = 0.0

      chars = @text.chars
      i = 0
      len = chars.length

      while i < len
        ch = chars[i]

        if ch == "\n"
          # 改行
          max_line_w = pen_x if pen_x > max_line_w
          @lines << { glyphs: current_line_glyphs, width: pen_x, y: pen_y }
          current_line_glyphs = []
          pen_x = 0.0
          pen_y += line_height
          line_index += 1
          i += 1
          next
        end

        glyph_data = @font.get_glyph(ch, @size)
        adv = glyph_data ? glyph_data[9].to_f : (@size * 0.5)

        # 自動折り返し判定 (行頭でなく、max_width を超過する場合)
        if @max_width && pen_x > 0.0 && (pen_x + adv > @max_width)
          max_line_w = pen_x if pen_x > max_line_w
          @lines << { glyphs: current_line_glyphs, width: pen_x, y: pen_y }
          current_line_glyphs = []
          pen_x = 0.0
          pen_y += line_height
          line_index += 1
        end

        if glyph_data && glyph_data[0] # visible == true
          _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv = glyph_data

          # ベースライン位置: pen_y + ascent
          gx = pen_x + x0
          gy = pen_y + ascent + y0
          gw = x1 - x0
          gh = y1 - y0
          uv = [u0, v0, u1 - u0, v1 - v0]

          item = Glyph.new(ch, char_index, line_index, gx, gy, gw, gh, uv, adv)
          current_line_glyphs << item
          @glyphs << item
        end

        pen_x += adv
        char_index += 1
        i += 1
      end

      # 最後の行の登録
      max_line_w = pen_x if pen_x > max_line_w
      @lines << { glyphs: current_line_glyphs, width: pen_x, y: pen_y }

      @width = @max_width ? [@max_width, max_line_w].max : max_line_w
      @height = pen_y + (ascent - descent)

      # 水平アライメント調整 (:center, :right)
      if @align == :center || @align == :right
        target_w = @max_width || max_line_w
        @lines.each do |line|
          shift_x = if @align == :center
                      (target_w - line[:width]) / 2.0
                    else
                      target_w - line[:width]
                    end
          next if shift_x <= 0.0

          line[:glyphs].each do |g|
            g.x = g.x + shift_x
          end
        end
      end

      @glyphs.freeze
      @lines.freeze
    end
  end
end

# frozen_string_literal: true

module Zenoo
  class Font
    attr_reader :path, :native

    # ----------------------------------------------------
    # 8x8 ASCII ビットマップフォント (後方互換・フォールバック用)
    # ----------------------------------------------------
    FONT_HEX = "0000000000000000181818181800180066662400000000006c6cfe6cfe6c6c00187e183c187e180000c6cc183066c600386c3876dccc760018183000000000000c18303030180c0030180c0c0c18300000663cff3c6600000018187e1818000000000000001818300000007e000000000000000000181800060c183060c080007cc6ced6e6c67c001838181818187e007cc6061c3066fe007cc6063c06c67c001c3c6cccfe0c1e00fec0fc0606c67c007cc6c0fcc6c67c00fec60c18303030007cc6c67cc6c67c007cc6c67e060c7800001818001818000000181800181830000c18306030180c0000007e007e00000030180c060c1830007cc60c18180018007cc6dededcc07c00386cc6c6fec6c600fc66667c6666fc003c66c0c0c0663c00f86c6666666cf800fe6268786862fe00fe6268786860f0003c66c0c0ce663e00c6c6c6fec6c6c6007e18181818187e001e0c0c0ccccc7800e6666c786c66e600f06060606266fe00c6eefefed6c6c600c6e6f6fedecec6007cc6c6c6c6c67c00fc66667c6060f0007cc6c6c6d6de7c0efc66667c6c66e6007cc660380cc67c007e7e5a1818183c00c6c6c6c6c6c67c00c6c6c6c6c66c3800c6c6d6fefeeec600c6c66c386cc6c6006666663c18183c00fec60c183063fe003c30303030303c00c06030180c0602003c0c0c0c0c0c3c0010386cc60000000000000000000000ff30180c00000000000000780c7ccc7600e0607c666666dc00000078ccc0cc78001c0c7ccccccc7600000078ccfcc07800386c60f06060f000000076cccc7c0cf8e0606c766666e6001800381818183c0006000e060666663ce060666c786ce6003818181818183c000000e6ffdbc9c9000000dc666666660000007cc6c6c67c000000dc66667c60f0000076cccc7c0c1e0000dc766060f00000007cc07c06fc0010307c30303418000000cccccccc76000000c6c6c66c38000000c6c6d6fe6c000000c66c386cc6000000c6c6ce76067c0000fc983064fc000e18187018180e0018181818181818007018180e1818700076dc000000000000".freeze

    def self.hex_val(byte)
      if byte >= 48 && byte <= 57
        byte - 48
      elsif byte >= 97 && byte <= 102
        byte - 87
      elsif byte >= 65 && byte <= 70
        byte - 55
      else
        0
      end
    end

    def self.get_font_byte(offset)
      h_idx = offset * 2
      (hex_val(FONT_HEX.getbyte(h_idx)) << 4) | hex_val(FONT_HEX.getbyte(h_idx + 1))
    end

    def self.draw_bitmap_text(x, y, text, size: 16, color: :white)
      return unless text
      text_str = text.to_s
      len = text_str.length
      return if len == 0

      scale = size.to_f / 8.0
      char_w = 8.0 * scale
      pixel_w = scale

      cur_x = x.to_f
      cur_y = y.to_f

      i = 0
      while i < len
        ch_code = text_str.getbyte(i)
        if ch_code == 10 # '\n'
          cur_x = x.to_f
          cur_y += 10.0 * scale
          i += 1
          next
        end

        if ch_code >= 32 && ch_code <= 126
          font_offset = (ch_code - 32) * 8
          row = 0
          while row < 8
            byte = get_font_byte(font_offset + row)
            if byte != 0
              py = cur_y + row * pixel_w
              col = 0
              while col < 8
                if ((byte >> (7 - col)) & 1) == 1
                  run_start = col
                  while col < 8 && ((byte >> (7 - col)) & 1) == 1
                    col += 1
                  end
                  run_len = col - run_start
                  Window.draw_rect(cur_x + run_start * pixel_w, py, run_len * pixel_w, pixel_w, color)
                else
                  col += 1
                end
              end
            end
            row += 1
          end
        end

        cur_x += char_w
        i += 1
      end
    end

    # 従来の Font.draw_text 呼び出し（ビットマップ描画との後方互換）
    def self.draw_text(x, y, text, size: 16, color: :white)
      draw_bitmap_text(x, y, text, size: size, color: color)
    end

    # TTF / OTF / TTC ファイルパスから初期化
    def initialize(path)
      @path = path
      @native = Native::Font.load(path)
      @metrics_cache = {}
    end

    # フォントメトリクスの取得 (ascent, descent, line_gap, line_height)
    def metrics(size = 24.0)
      s = size.to_f
      @metrics_cache[s] ||= begin
        ascent, descent, line_gap = @native.metrics(s)
        {
          ascent: ascent,
          descent: descent,
          line_gap: line_gap,
          line_height: (ascent - descent + line_gap)
        }
      end
    end

    # グリフの取得
    # 返り値: [visible, u0, v0, u1, v1, x0, y0, x1, y1, advance_x] または nil
    def get_glyph(char_or_cp, size = 24.0)
      cp = if char_or_cp.is_a?(String)
             char_or_cp.ord
           else
             char_or_cp.to_i
           end
      res = @native.get_glyph(cp, size.to_f)
      res
    end

    # テキスト組版（Immutable な TextLayout）を生成
    def layout(text, size: 24, line_spacing: 1.0, max_width: nil, align: :left)
      TextLayout.new(text, font: self, size: size, line_spacing: line_spacing, max_width: max_width, align: align)
    end

    # ----------------------------------------------------
    # SDF / TTF ベクターフォント基盤 (定数・デフォルトフォント)
    # ----------------------------------------------------
    @default_font = nil

    def self.load_default_font
      path = "/assets/fonts/MPLUS1p-Regular.ttf"
      rel1 = "assets/fonts/MPLUS1p-Regular.ttf"
      rel2 = File.expand_path("../../assets/fonts/MPLUS1p-Regular.ttf", __dir__)
      if File.exist?(rel1)
        path = rel1
      elsif File.exist?(rel2)
        path = rel2
      elsif File.exist?("/assets/fonts/MPLUS1p-Regular.ttf")
        path = "/assets/fonts/MPLUS1p-Regular.ttf"
      elsif File.exist?("C:/Windows/Fonts/msgothic.ttc")
        path = "C:/Windows/Fonts/msgothic.ttc"
      end
      new(path)
    end

    def self.load_sinclair_font
      path = "/assets/fonts/zx_spectrum.ttf"
      rel1 = "assets/fonts/zx_spectrum.ttf"
      rel2 = File.expand_path("../../assets/fonts/zx_spectrum.ttf", __dir__)
      if File.exist?(rel1)
        path = rel1
      elsif File.exist?(rel2)
        path = rel2
      elsif File.exist?("/assets/fonts/zx_spectrum.ttf")
        path = "/assets/fonts/zx_spectrum.ttf"
      end
      new(path)
    end

    SINCLAIR = load_sinclair_font
    MPLUS = load_default_font
    DEFAULT = MPLUS

    def self.default
      @default_font || DEFAULT
    end

    def self.default=(font)
      @default_font = font
    end

    def self.sinclair
      SINCLAIR
    end

    def self.mplus
      MPLUS
    end

    def self.layout(text, opt_or_size = 24, line_spacing = 1.0, max_width = nil, align = :left)
      TextLayout.new(text, opt_or_size, line_spacing, max_width, align)
    end

    def self.atlas_image
      Native::Font.atlas_image
    end
  end
end

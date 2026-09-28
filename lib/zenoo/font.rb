# frozen_string_literal: true

module Zenoo
  class Font
    SDF_BASE_SIZE = 72.0

    attr_reader :path, :native


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
    def get_glyph(char_or_cp, size = 24.0, sdf = nil)
      cp = if char_or_cp.is_a?(String)
             char_or_cp.ord
           else
             char_or_cp.to_i
           end
      s = size.to_f
      if sdf == true
        s = -s
      elsif sdf == false
        s = s + 10000.0
      end
      res = @native.get_glyph(cp, s)
      res
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


    def self.atlas_image
      Native::Font.atlas_image
    end
  end
end

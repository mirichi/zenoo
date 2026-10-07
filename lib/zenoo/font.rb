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

    # 文字列の描画幅 (ピクセル単位) を計算
    def text_width(text, size = 24.0)
      return 0.0 unless text
      s = size.to_f
      w = 0.0
      text.to_s.each_char do |ch|
        g = get_glyph(ch, s)
        w += g ? g[9] : s * 0.6
      end
      w
    end

    def self.text_width(text, size = 24.0)
      default.text_width(text, size)
    end


    # ----------------------------------------------------
    # SDF / TTF ベクターフォント基盤 (定数・デフォルトフォント)
    # ----------------------------------------------------
    @default_font = nil

    def self.find_font_file(filename)
      candidates = [
        "assets/fonts/#{filename}",
        "../assets/fonts/#{filename}",
        "../../assets/fonts/#{filename}",
        "/assets/fonts/#{filename}"
      ]
      candidates << File.expand_path("../../assets/fonts/#{filename}", __dir__) if defined?(__dir__) && __dir__
      candidates.each do |p|
        return p if File.exist?(p)
      end
      "/assets/fonts/#{filename}"
    end

    def self.load_default_font
      path = find_font_file("MPLUS1p-Regular.ttf")
      if !File.exist?(path) && File.exist?("C:/Windows/Fonts/msgothic.ttc")
        path = "C:/Windows/Fonts/msgothic.ttc"
      end
      new(path)
    end

    def self.load_sinclair_font
      path = find_font_file("zx_spectrum.ttf")
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
      @atlas_image ||= begin
        # Native 内部メソッドで R8 アトラス画像を生成 (ユーザーからは見えない)
        img = Native::Image.create_r8(2048, 2048)
        # C 側にフォントアトラスの描画先テクスチャとして登録
        Native::FontHelper.set_atlas_image(img)
        img
      end
    end
  end
end

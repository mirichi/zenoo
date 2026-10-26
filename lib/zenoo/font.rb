# frozen_string_literal: true

module Zenoo
  class Font
    SDF_BASE_SIZE = 64.0

    attr_reader :path, :native


    # TTF / OTF / TTC ファイルパスから初期化
    def initialize(path)
      @path = path
      @native = Native::Font.load(path)
      @metrics_cache = {}
      @advance_cache = {}
      @glyph_cache = {}
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

    # グリフの取得 (Ruby側でキャッシュして C拡張呼び出しと配列生成を最小化)
    # 返り値: [visible, u0, v0, u1, v1, x0, y0, x1, y1, advance_x] または nil
    def get_glyph(char_or_cp, size = 24.0, sdf = nil, r_scale = 1.0)
      cp = char_or_cp.is_a?(String) ? char_or_cp.ord : char_or_cp.to_i
      sdf_flag = (sdf == true ? 1 : (sdf.nil? ? 0 : 2))
      # 31bit正のFixnum内に収まるビットパック (Wasm 32bit環境でオーバーフローゼロ)
      # [cp: 16bit] [size: 10bit] [sdf: 2bit] [r_scale: 3bit] = 31bit
      cp_16 = (cp ^ (cp >> 16)) & 0xFFFF
      sz_10 = (size.to_f * 2.0).to_i & 0x3FF
      r_3   = (r_scale.to_f * 2.0).to_i & 0x7
      key   = (cp_16 << 15) | (sz_10 << 5) | (sdf_flag << 3) | r_3

      @glyph_cache[key] ||= begin
        s = size.to_f
        actual_s = s
        if sdf == true
          actual_s = -s
        elsif sdf == false
          actual_s = s + 10000.0
        end
        @native.get_glyph(cp, actual_s)
      end
    end

    # 1文字の送り幅 (advance_x) の取得 (キャッシュ対応)
    def advance_x(char_or_cp, size = 24.0)
      s = size.to_f
      cp = char_or_cp.is_a?(String) ? char_or_cp.ord : char_or_cp.to_i
      # [cp: 18bit] [size: 13bit] = 31bit (オーバーフローゼロ)
      cp_18 = (cp ^ (cp >> 18)) & 0x3FFFF
      sz_13 = (s * 2.0).to_i & 0x1FFF
      key   = (cp_18 << 13) | sz_13
      @advance_cache[key] ||= begin
        g = get_glyph(char_or_cp, s)
        g ? g[9].to_f : (s * 0.6)
      end
    end

    # 文字列の描画幅 (ピクセル単位) を計算 (キャッシュ対応で高速)
    def text_width(text, size = 24.0)
      return 0.0 unless text
      s = size.to_f
      w = 0.0
      sz_13 = (s * 2.0).to_i & 0x1FFF
      text.to_s.each_char do |ch|
        cp = ch.ord
        cp_18 = (cp ^ (cp >> 18)) & 0x3FFFF
        key   = (cp_18 << 13) | sz_13
        w += (@advance_cache[key] ||= begin
          g = get_glyph(ch, s)
          g ? g[9].to_f : (s * 0.6)
        end)
      end
      w
    end

    def self.text_width(text, size = 24.0)
      default.text_width(text, size)
    end

    # 文字列の描画サイズ [width, height] を計算 (複数行対応)
    def text_size(text, size = 24.0, line_spacing: nil)
      return [0.0, 0.0] unless text
      str = text.to_s
      return [0.0, 0.0] if str.empty?

      s = size.to_f
      s = 24.0 if s <= 0.0

      if str.include?("\n")
        lines = str.split("\n", -1)
        max_w = 0.0
        lines.each do |line|
          w = text_width(line, s)
          max_w = w if w > max_w
        end
        m = metrics(s)
        line_h = line_spacing ? (s * line_spacing.to_f) : (m[:line_height] || (s * 1.2))
        total_h = s + (lines.length - 1) * line_h
        [max_w, total_h]
      else
        [text_width(str, s), s]
      end
    end

    def self.text_size(text, size = 24.0, line_spacing: nil)
      default.text_size(text, size, line_spacing: line_spacing)
    end

    # 文字列の描画高さを計算 (複数行対応)
    def text_height(text, size = 24.0, line_spacing: nil)
      text_size(text, size, line_spacing: line_spacing)[1]
    end

    def self.text_height(text, size = 24.0, line_spacing: nil)
      default.text_height(text, size, line_spacing: line_spacing)
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

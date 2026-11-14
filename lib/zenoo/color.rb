module Zenoo
  # RGBA 各色成分を 0〜255 の整数で保持する不変色クラス。
  # 描画 API の color: 引数では Color インスタンスのほか、[r, g, b, a] 配列や :red などのシンボルも利用できます。
  class Color
    attr_reader :r, :g, :b, :a

    # 新しい Color インスタンスを生成します。
    #
    # - `r` (`Integer`): 赤成分 (`0..255` にクランプ)
    # - `g` (`Integer`): 緑成分 (`0..255` にクランプ)
    # - `b` (`Integer`): 青成分 (`0..255` にクランプ)
    # - `a` (`Integer`): 不透明度 (`0..255` にクランプ、デフォルト: `255`)
    def initialize(r, g, b, a = 255)
      @r = clamp(r, 0, 255)
      @g = clamp(g, 0, 255)
      @b = clamp(b, 0, 255)
      @a = clamp(a, 0, 255)
      @f4 = [@r / 255.0, @g / 255.0, @b / 255.0, @a / 255.0].freeze
    end

    # 浮動小数点 (0.0..1.0) ゲッター (シェーダー連携用)

    # 赤成分を `0.0..1.0` の浮動小数点数で返します。
    def rf
      @r / 255.0
    end

    # 緑成分を `0.0..1.0` の浮動小数点数で返します。
    def gf
      @g / 255.0
    end

    # 青成分を `0.0..1.0` の浮動小数点数で返します。
    def bf
      @b / 255.0
    end

    # 不透明度を `0.0..1.0` の浮動小数点数で返します。
    def af
      @a / 255.0
    end

    # ----------------------------------------------------
    # ファクトリメソッド
    # ----------------------------------------------------

    # 不透明 (アルファ 255) の Color を生成します。
    #
    # - `r` (`Integer`): 赤成分 (`0..255`)
    # - `g` (`Integer`): 緑成分 (`0..255`)
    # - `b` (`Integer`): 青成分 (`0..255`)
    def self.rgb(r, g, b)
      new(r, g, b, 255)
    end

    # アルファ指定付きの Color を生成します。
    #
    # - `r` (`Integer`): 赤成分 (`0..255`)
    # - `g` (`Integer`): 緑成分 (`0..255`)
    # - `b` (`Integer`): 青成分 (`0..255`)
    # - `a` (`Integer`): 不透明度 (`0..255`)
    def self.rgba(r, g, b, a)
      new(r, g, b, a)
    end

    # `0.0..1.0` の浮動小数点値から Color を生成します (内部で `0..255` へ変換)。
    #
    # - `r` (`Numeric`): 赤成分 (`0.0..1.0`)
    # - `g` (`Numeric`): 緑成分 (`0.0..1.0`)
    # - `b` (`Numeric`): 青成分 (`0.0..1.0`)
    # - `a` (`Numeric`): 不透明度 (`0.0..1.0`、デフォルト: `1.0`)
    def self.from_floats(r, g, b, a = 1.0)
      new((r.to_f * 255.0).round, (g.to_f * 255.0).round, (b.to_f * 255.0).round, (a.to_f * 255.0).round)
    end

    # HSV (色相: 0..360, 彩度: 0.0..1.0, 明度: 0.0..1.0) から Color を生成します。
    #
    # - `h` (`Numeric`): 色相 (`0..360` 度、範囲外は周回補正)
    # - `s` (`Numeric`): 彩度 (`0.0..1.0` にクランプ)
    # - `v` (`Numeric`): 明度 (`0.0..1.0` にクランプ)
    # - `a` (`Integer`): 不透明度 (`0..255`、デフォルト: `255`)
    def self.hsv(h, s, v, a = 255)
      h_deg = h.to_f % 360.0
      h_deg += 360.0 if h_deg < 0.0
      sat = s.to_f < 0.0 ? 0.0 : (s.to_f > 1.0 ? 1.0 : s.to_f)
      val = v.to_f < 0.0 ? 0.0 : (v.to_f > 1.0 ? 1.0 : v.to_f)

      c = val * sat
      h_sector = h_deg / 60.0
      # (h_sector % 2.0 - 1.0).abs
      mod2 = h_sector - (h_sector.to_i / 2 * 2)
      x = c * (1.0 - (mod2 - 1.0).abs)
      m = val - c

      r1 = 0.0
      g1 = 0.0
      b1 = 0.0

      if h_sector < 1.0
        r1 = c; g1 = x; b1 = 0.0
      elsif h_sector < 2.0
        r1 = x; g1 = c; b1 = 0.0
      elsif h_sector < 3.0
        r1 = 0.0; g1 = c; b1 = x
      elsif h_sector < 4.0
        r1 = 0.0; g1 = x; b1 = c
      elsif h_sector < 5.0
        r1 = x; g1 = 0.0; b1 = c
      else
        r1 = c; g1 = 0.0; b1 = x
      end

      new(((r1 + m) * 255.0).round, ((g1 + m) * 255.0).round, ((b1 + m) * 255.0).round, a)
    end

    # HEXコード (0xFF5500 または "#FF5500" / "FF5500") から Color を生成します。
    #
    # - `val` (`Integer, String`): 16進数カラー値 (7文字以上の文字列で `#RRGGBBAA` を指定した場合は末尾2桁をアルファ値として使用)
    # - `a` (`Integer`): 不透明度 (`0..255`、デフォルト: `255`)
    def self.hex(val, a = 255)
      if val.is_a?(String)
        str = val.to_s
        clean = (str[0] == "#") ? str[1..-1] : str
        v = clean.to_i(16)
        if clean.length > 6
          new((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
        else
          new((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, a)
        end
      else
        v = val.to_i
        new((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, a)
      end
    end

    # ----------------------------------------------------
    # 操作・演出メソッド
    # ----------------------------------------------------

    # アルファ値のみ変更した新しい Color を生成します。
    #
    # - `new_a` (`Integer`): 新しい不透明度 (`0..255`)
    def with_alpha(new_a)
      Color.new(@r, @g, @b, new_a)
    end

    # 別の色との線形補間 (Lerp) を行った新しい Color を返します。
    #
    # - `target` (`Color`): 補間先の色
    # - `t` (`Numeric`): 補間係数 (`0.0..1.0` にクランプ。`0.0` で自身、`1.0` で `target`)
    def lerp(target, t)
      tf = t.to_f < 0.0 ? 0.0 : (t.to_f > 1.0 ? 1.0 : t.to_f)
      nr = (@r + (target.r - @r) * tf).round.to_i
      ng = (@g + (target.g - @g) * tf).round.to_i
      nb = (@b + (target.b - @b) * tf).round.to_i
      na = (@a + (target.a - @a) * tf).round.to_i
      Color.new(nr, ng, nb, na)
    end

    # 明度スケーリング (color * 0.8) を行った新しい Color を返します (アルファ値は維持)。
    #
    # - `factor` (`Numeric`): RGB 各成分に掛ける倍率
    def *(factor)
      f = factor.to_f
      Color.new((@r * f).round.to_i, (@g * f).round.to_i, (@b * f).round.to_i, @a)
    end

    # 加算合成した新しい Color を返します (アルファ値は維持)。
    #
    # - `other` (`Color`): 加算する色
    def +(other)
      Color.new(@r + other.r, @g + other.g, @b + other.b, @a)
    end

    # 減算合成した新しい Color を返します (アルファ値は維持)。
    #
    # - `other` (`Color`): 減算する色
    def -(other)
      Color.new(@r - other.r, @g - other.g, @b - other.b, @a)
    end

    # ----------------------------------------------------
    # 変換メソッド
    # ----------------------------------------------------

    # 0〜255 の整数配列 [r, g, b, a] を返します。
    def to_a
      [@r, @g, @b, @a]
    end

    # 0.0〜1.0 の浮動小数点配列 [r, g, b, a] を返します (シェーダー直接送出用)。
    def to_f4
      @f4
    end

    # 0xRRGGBBAA 形式の uint32 (32bit signed環境で r >= 128 のオーバーフローを防止) を返します。
    def to_i
      val = ((@r & 0x7F) << 24) | (@g << 16) | (@b << 8) | @a
      (@r >= 128) ? (val | -2147483648) : val
    end

    # 別のオブジェクトと各 RGBA 成分が一致するか判定します。
    #
    # - `other` (`Object`): 比較対象のオブジェクト
    def ==(other)
      other.is_a?(Color) && @r == other.r && @g == other.g && @b == other.b && @a == other.a
    end

    private

    def clamp(v, min, max)
      vi = v.to_i
      if vi < min
        min
      elsif vi > max
        max
      else
        vi
      end
    end

    # ----------------------------------------------------
    # プリセット定数
    # ----------------------------------------------------
    WHITE   = new(255, 255, 255, 255)
    BLACK   = new(0, 0, 0, 255)
    RED     = new(255, 50, 50, 255)
    GREEN   = new(50, 255, 75, 255)
    BLUE    = new(25, 130, 255, 255)
    CYAN    = new(0, 230, 255, 255)
    MAGENTA = new(255, 50, 200, 255)
    YELLOW  = new(255, 230, 25, 255)
    CLEAR   = new(0, 0, 0, 0)
  end
end

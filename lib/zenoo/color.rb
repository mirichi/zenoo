module Zenoo
  class Color
    attr_reader :r, :g, :b, :a

    def initialize(r, g, b, a = 255)
      @r = clamp(r, 0, 255)
      @g = clamp(g, 0, 255)
      @b = clamp(b, 0, 255)
      @a = clamp(a, 0, 255)
    end

    # 浮動小数点 (0.0..1.0) ゲッター (シェーダー連携用)
    def rf
      @r / 255.0
    end

    def gf
      @g / 255.0
    end

    def bf
      @b / 255.0
    end

    def af
      @a / 255.0
    end

    # ----------------------------------------------------
    # ファクトリメソッド
    # ----------------------------------------------------
    def self.rgb(r, g, b)
      new(r, g, b, 255)
    end

    def self.rgba(r, g, b, a)
      new(r, g, b, a)
    end

    def self.from_floats(r, g, b, a = 1.0)
      new((r.to_f * 255.0).round, (g.to_f * 255.0).round, (b.to_f * 255.0).round, (a.to_f * 255.0).round)
    end

    # HSV (色相: 0..360, 彩度: 0.0..1.0, 明度: 0.0..1.0)
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

    # HEXコード (0xFF5500 または "#FF5500" / "FF5500")
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
    # アルファ値のみ変更した新しいColorを生成
    def with_alpha(new_a)
      Color.new(@r, @g, @b, new_a)
    end

    # 線形補間 (Lerp)
    def lerp(target, t)
      tf = t.to_f < 0.0 ? 0.0 : (t.to_f > 1.0 ? 1.0 : t.to_f)
      nr = (@r + (target.r - @r) * tf).round.to_i
      ng = (@g + (target.g - @g) * tf).round.to_i
      nb = (@b + (target.b - @b) * tf).round.to_i
      na = (@a + (target.a - @a) * tf).round.to_i
      Color.new(nr, ng, nb, na)
    end

    # 明度スケーリング (color * 0.8)
    def *(factor)
      f = factor.to_f
      Color.new((@r * f).round.to_i, (@g * f).round.to_i, (@b * f).round.to_i, @a)
    end

    # 加算合成
    def +(other)
      Color.new(@r + other.r, @g + other.g, @b + other.b, @a)
    end

    # 減算合成
    def -(other)
      Color.new(@r - other.r, @g - other.g, @b - other.b, @a)
    end

    # ----------------------------------------------------
    # 変換メソッド
    # ----------------------------------------------------
    # 0〜255 の整数配列 [r, g, b, a]
    def to_a
      [@r, @g, @b, @a]
    end

    # 0.0〜1.0 の浮動小数点配列 [r, g, b, a] (シェーダー直接送出用)
    def to_f4
      [rf, gf, bf, af]
    end

    # 0xRRGGBBAA 形式の uint32
    def to_i
      (@r << 24) | (@g << 16) | (@b << 8) | @a
    end
    alias to_uint32 to_i

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

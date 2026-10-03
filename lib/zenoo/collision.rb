# frozen_string_literal: true

module Zenoo
  module Collision
    # 形状種別定数 (高速整数ディスパッチ用)
    TYPE_POINT   = 0
    TYPE_CIRCLE  = 1
    TYPE_RECT    = 2
    TYPE_POLYGON = 3

    # ====================================================
    # 幾何形状定義 (凸形状)
    # ※ 各形状は内部に再利用バッファ @_support を持ち、
    #    判定ループ中の一時オブジェクト生成 (アロケーション) をゼロにします。
    # ====================================================

    # 円
    class Circle
      attr_accessor :x, :y, :radius

      def initialize(x = 0.0, y = 0.0, radius = 0.0)
        @x = x.to_f
        @y = y.to_f
        @radius = radius.to_f
        @_support = [0.0, 0.0]
      end

      def shape_type; TYPE_CIRCLE; end
      def center_x; @x; end
      def center_y; @y; end
      def bounding_radius; @radius; end

      def set(x, y, radius = @radius)
        @x = x.to_f
        @y = y.to_f
        @radius = radius.to_f
      end

      # サポート写像: 方向 (dx, dy) で最も遠い点
      def support(dx, dy)
        len_sq = dx * dx + dy * dy
        if len_sq > 0.000001
          inv_len = @radius / Math.sqrt(len_sq)
          @_support[0] = @x + dx * inv_len
          @_support[1] = @y + dy * inv_len
        else
          @_support[0] = @x
          @_support[1] = @y
        end
        @_support
      end
    end

    # 点
    class Point
      attr_accessor :x, :y

      def initialize(x = 0.0, y = 0.0)
        @x = x.to_f
        @y = y.to_f
        @_support = [0.0, 0.0]
      end

      def shape_type; TYPE_POINT; end
      def center_x; @x; end
      def center_y; @y; end
      def bounding_radius; 0.0; end

      def set(x, y)
        @x = x.to_f
        @y = y.to_f
      end

      def support(_dx, _dy)
        @_support[0] = @x
        @_support[1] = @y
        @_support
      end
    end

    # 回転矩形 (OBB) / 軸平行矩形 (AABB) / 角丸矩形 (Rounded Rect)
    class Rect
      attr_accessor :x, :y, :width, :height, :angle, :radius, :pivot_x, :pivot_y
      attr_reader :half_w, :half_h, :core_half_w, :core_half_h, :is_aabb, :is_rounded, :bounding_radius, :cos, :sin

      def initialize(x, y, width, height, angle: 0.0, radius: 0.0, pivot: :center)
        @x = x.to_f
        @y = y.to_f
        @width = width.to_f
        @height = height.to_f
        @angle = angle.to_f
        @radius = radius.to_f
        @_support = [0.0, 0.0]

        set_pivot(pivot)
        update_cache
      end

      def shape_type; TYPE_RECT; end

      def set_pivot(pivot)
        if pivot == :center
          @pivot_x = 0.5
          @pivot_y = 0.5
        elsif pivot == :top_left
          @pivot_x = 0.0
          @pivot_y = 0.0
        elsif pivot.is_a?(Array) && pivot.length >= 2
          @pivot_x = pivot[0].to_f
          @pivot_y = pivot[1].to_f
        else
          @pivot_x = 0.5
          @pivot_y = 0.5
        end
      end

      def update_cache
        @half_w = @width * 0.5
        @half_h = @height * 0.5
        # 中心座標
        @center_x = @x + @width * (0.5 - @pivot_x)
        @center_y = @y + @height * (0.5 - @pivot_y)

        # 外接円半径
        @bounding_radius = Math.sqrt(@half_w * @half_w + @half_h * @half_h)

        # 角丸半径のクランプ (短辺の半分まで)
        max_r = @half_w < @half_h ? @half_w : @half_h
        @radius = 0.0 if @radius < 0.0
        @radius = max_r if @radius > max_r
        @is_rounded = (@radius > 0.0001)

        # 角丸の内側の芯となる矩形 (Core Box) の半サイズ
        @core_half_w = @half_w - @radius
        @core_half_h = @half_h - @radius

        # AABB (回転なし) かどうかの判定
        norm_ang = (@angle % 360.0).abs
        @is_aabb = (norm_ang < 0.0001 || (norm_ang - 360.0).abs < 0.0001)

        rad = @angle * (Math::PI / 180.0)
        @cos = Math.cos(rad)
        @sin = Math.sin(rad)
      end

      def center_x; @center_x; end
      def center_y; @center_y; end

      def set(x, y, width = @width, height = @height, angle = @angle, radius = @radius)
        @x = x.to_f
        @y = y.to_f
        @width = width.to_f
        @height = height.to_f
        @angle = angle.to_f
        @radius = radius.to_f
        update_cache
      end

      # OBB / 角丸矩形の高速サポート写像
      def support(dx, dy)
        ldx = dx * @cos + dy * @sin
        ldy = -dx * @sin + dy * @cos

        # 芯となる矩形でのサポート点
        lpx = (ldx >= 0.0) ? @core_half_w : -@core_half_w
        lpy = (ldy >= 0.0) ? @core_half_h : -@core_half_h

        wx = @center_x + (lpx * @cos - lpy * @sin)
        wy = @center_y + (lpx * @sin + lpy * @cos)

        if @is_rounded
          len_sq = dx * dx + dy * dy
          if len_sq > 0.000001
            inv_len = @radius / Math.sqrt(len_sq)
            @_support[0] = wx + dx * inv_len
            @_support[1] = wy + dy * inv_len
          else
            @_support[0] = wx
            @_support[1] = wy
          end
        else
          @_support[0] = wx
          @_support[1] = wy
        end
        @_support
      end
    end

    # 凸多角形 (Convex Polygon)
    class Polygon
      attr_reader :vertices, :bounding_radius

      def initialize(vertices)
        @vertices = vertices.map { |v| [v[0].to_f, v[1].to_f] }
        @_support = [0.0, 0.0]
        update_cache
      end

      def shape_type; TYPE_POLYGON; end

      def update_cache
        sum_x = 0.0
        sum_y = 0.0
        count = @vertices.length
        return if count == 0

        @vertices.each do |v|
          sum_x += v[0]
          sum_y += v[1]
        end
        @center_x = sum_x / count
        @center_y = sum_y / count

        # 外接半径
        max_r_sq = 0.0
        @vertices.each do |v|
          dx = v[0] - @center_x
          dy = v[1] - @center_y
          r_sq = dx * dx + dy * dy
          max_r_sq = r_sq if r_sq > max_r_sq
        end
        @bounding_radius = Math.sqrt(max_r_sq)
      end

      def center_x; @center_x; end
      def center_y; @center_y; end

      def support(dx, dy)
        max_dot = -1.0e30
        best_x = 0.0
        best_y = 0.0

        i = 0
        len = @vertices.length
        while i < len
          v = @vertices[i]
          dot = v[0] * dx + v[1] * dy
          if dot > max_dot
            max_dot = dot
            best_x = v[0]
            best_y = v[1]
          end
          i += 1
        end

        @_support[0] = best_x
        @_support[1] = best_y
        @_support
      end
    end

    # ====================================================
    # 衝突判定メインエントリ
    # 1. ブロードフェーズ (外接円チェックで離れたペアを即除外)
    # 2. 高速パス (円vs円, AABBvsAABB, 点vs円 などを超軽量計算で即決)
    # 3. ナローフェーズ (OBB/カプセル/多角形の近接時のみ GJK を起動)
    # ====================================================
    def self.check(shape_a, shape_b)
      dx = shape_b.center_x - shape_a.center_x
      dy = shape_b.center_y - shape_a.center_y
      dist_sq = dx * dx + dy * dy
      r_sum = shape_a.bounding_radius + shape_b.bounding_radius

      # 1. ブロードフェーズ: 外接円が離れていれば絶対に当たっていない
      return false if dist_sq > r_sum * r_sum

      type_a = shape_a.shape_type
      type_b = shape_b.shape_type

      # 2. 高速パス (Fast Path)

      # 円 vs 円: 外接円 == 本体の円なので、ブロードフェーズ通過時点で衝突確定！
      if type_a == TYPE_CIRCLE && type_b == TYPE_CIRCLE
        return true
      end

      # 点 vs 円
      if type_a == TYPE_POINT && type_b == TYPE_CIRCLE
        return true
      elsif type_a == TYPE_CIRCLE && type_b == TYPE_POINT
        return true
      end

      # 円 vs 矩形 (AABB, OBB, 角丸矩形すべてに完全対応の SDF 高速パス)
      if type_a == TYPE_CIRCLE && type_b == TYPE_RECT
        return check_circle_rect(shape_a, shape_b, dx, dy)
      elsif type_a == TYPE_RECT && type_b == TYPE_CIRCLE
        return check_circle_rect(shape_b, shape_a, -dx, -dy)
      end

      # 点 vs 矩形 (AABB, OBB, 角丸矩形すべてに完全対応の SDF 高速パス)
      if type_a == TYPE_POINT && type_b == TYPE_RECT
        return check_point_rect(shape_a, shape_b, dx, dy)
      elsif type_a == TYPE_RECT && type_b == TYPE_POINT
        return check_point_rect(shape_b, shape_a, -dx, -dy)
      end

      # 矩形 vs 矩形
      if type_a == TYPE_RECT && type_b == TYPE_RECT
        if !shape_a.is_rounded && !shape_b.is_rounded
          if shape_a.is_aabb && shape_b.is_aabb
            return false if (dx > 0 ? dx : -dx) > (shape_a.half_w + shape_b.half_w)
            return false if (dy > 0 ? dy : -dy) > (shape_a.half_h + shape_b.half_h)
            return true
          else
            return check_obb_obb(shape_a, shape_b, dx, dy)
          end
        end
        # 角丸同士、または角丸 vs OBB は GJK に委ねる (サポート写像で完全対応)
      end

      # 3. ナローフェーズ (GJK: カプセル, 多角形, 角丸矩形ペアなど)
      gjk(shape_a, shape_b, dx, dy, dist_sq)
    end

    # 円 vs 矩形 (回転・角丸対応 SDF 判定)
    def self.check_circle_rect(circle, rect, dx, dy)
      # 矩形のローカル座標系への相対中心ベクトル
      ldx = dx * rect.cos + dy * rect.sin
      ldy = -dx * rect.sin + dy * rect.cos
      ldx = -ldx if ldx < 0.0
      ldy = -ldy if ldy < 0.0

      total_r = rect.radius + circle.radius
      diff_x = ldx - rect.core_half_w
      diff_x = 0.0 if diff_x < 0.0
      diff_y = ldy - rect.core_half_h
      diff_y = 0.0 if diff_y < 0.0

      (diff_x * diff_x + diff_y * diff_y) <= (total_r * total_r)
    end

    # 点 vs 矩形 (回転・角丸対応 SDF 判定)
    def self.check_point_rect(pt, rect, dx, dy)
      ldx = dx * rect.cos + dy * rect.sin
      ldy = -dx * rect.sin + dy * rect.cos
      ldx = -ldx if ldx < 0.0
      ldy = -ldy if ldy < 0.0

      if rect.is_rounded
        diff_x = ldx - rect.core_half_w
        diff_x = 0.0 if diff_x < 0.0
        diff_y = ldy - rect.core_half_h
        diff_y = 0.0 if diff_y < 0.0

        (diff_x * diff_x + diff_y * diff_y) <= (rect.radius * rect.radius)
      else
        ldx <= rect.half_w && ldy <= rect.half_h
      end
    end

    # 2D OBB vs OBB の分離軸テスト (SAT: 4軸射影・三角関数積和最適化)
    # ループなし・反復なし。各軸の射影幅比較で即時判定。
    def self.check_obb_obb(a, b, dx, dy)
      # 相対角度の三角関数 (加法定理により cos, sin の積和で直接計算)
      # cos(θB - θA) = cosB * cosA + sinB * sinA
      # sin(θB - θA) = sinB * cosA - cosB * sinA
      cos_rel = b.cos * a.cos + b.sin * a.sin
      sin_rel = b.sin * a.cos - b.cos * a.sin
      c = cos_rel >= 0.0 ? cos_rel : -cos_rel
      s = sin_rel >= 0.0 ? sin_rel : -sin_rel

      # 1. 形状 A のローカル座標系への投影テスト (A の 2 本の主軸)
      dx_a = dx * a.cos + dy * a.sin
      dx_a = -dx_a if dx_a < 0.0
      return false if dx_a > (a.half_w + b.half_w * c + b.half_h * s)

      dy_a = -dx * a.sin + dy * a.cos
      dy_a = -dy_a if dy_a < 0.0
      return false if dy_a > (a.half_h + b.half_w * s + b.half_h * c)

      # 2. 形状 B のローカル座標系への投影テスト (B の 2 本の主軸)
      dx_b = dx * b.cos + dy * b.sin
      dx_b = -dx_b if dx_b < 0.0
      return false if dx_b > (b.half_w + a.half_w * c + a.half_h * s)

      dy_b = -dx * b.sin + dy * b.cos
      dy_b = -dy_b if dy_b < 0.0
      return false if dy_b > (b.half_h + a.half_w * s + a.half_h * c)

      # 4軸すべてで重なっている -> 衝突確定
      true
    end

    # GJK コア
    def self.gjk(shape_a, shape_b, init_dx, init_dy, dist_sq)
      dx = init_dx
      dy = init_dy
      if dist_sq < 0.000001
        dx = 1.0
        dy = 0.0
      end

      pa = shape_a.support(dx, dy)
      pb = shape_b.support(-dx, -dy)
      p0_x = pa[0] - pb[0]
      p0_y = pa[1] - pb[1]

      return true if p0_x == 0.0 && p0_y == 0.0

      dx = -p0_x
      dy = -p0_y

      p1_x = 0.0; p1_y = 0.0
      simplex_count = 1

      iterations = 0
      max_iterations = 32

      while iterations < max_iterations
        iterations += 1

        pa = shape_a.support(dx, dy)
        pb = shape_b.support(-dx, -dy)
        a_x = pa[0] - pb[0]
        a_y = pa[1] - pb[1]

        dot = a_x * dx + a_y * dy
        return false if dot <= 0.0

        if simplex_count == 1
          b_x = p0_x
          b_y = p0_y

          ab_x = b_x - a_x
          ab_y = b_y - a_y
          ao_x = -a_x
          ao_y = -a_y

          n_x = -ab_y
          n_y = ab_x
          if n_x * ao_x + n_y * ao_y < 0.0
            n_x = ab_y
            n_y = -ab_x
          end

          dx = n_x
          dy = n_y

          p1_x = b_x
          p1_y = b_y
          p0_x = a_x
          p0_y = a_y
          simplex_count = 2

        elsif simplex_count == 2
          b_x = p0_x
          b_y = p0_y
          c_x = p1_x
          c_y = p1_y

          ab_x = b_x - a_x
          ab_y = b_y - a_y
          ac_x = c_x - a_x
          ac_y = c_y - a_y
          ao_x = -a_x
          ao_y = -a_y

          cross = ab_x * ac_y - ab_y * ac_x

          if cross > 0.0
            ab_perp_x = ab_y
            ab_perp_y = -ab_x

            ac_perp_x = -ac_y
            ac_perp_y = ac_x
          else
            ab_perp_x = -ab_y
            ab_perp_y = ab_x

            ac_perp_x = ac_y
            ac_perp_y = -ac_x
          end

          if ab_perp_x * ao_x + ab_perp_y * ao_y > 0.0
            dx = ab_perp_x
            dy = ab_perp_y
            p1_x = b_x
            p1_y = b_y
            p0_x = a_x
            p0_y = a_y
            simplex_count = 2
          elsif ac_perp_x * ao_x + ac_perp_y * ao_y > 0.0
            dx = ac_perp_x
            dy = ac_perp_y
            p1_x = c_x
            p1_y = c_y
            p0_x = a_x
            p0_y = a_y
            simplex_count = 2
          else
            return true
          end
        end
      end

      false
    end

    # 配列同士の判定
    def self.check_all(group_a, group_b)
      len_a = group_a.length
      len_b = group_b.length
      i = 0
      while i < len_a
        item_a = group_a[i]
        shape_a = (item_a.is_a?(Circle) || item_a.is_a?(Rect) || item_a.is_a?(Polygon) || item_a.is_a?(Point)) ? item_a : (item_a.respond_to?(:collider) ? item_a.collider : nil)
        if shape_a
          j = 0
          while j < len_b
            item_b = group_b[j]
            shape_b = (item_b.is_a?(Circle) || item_b.is_a?(Rect) || item_b.is_a?(Polygon) || item_b.is_a?(Point)) ? item_b : (item_b.respond_to?(:collider) ? item_b.collider : nil)
            if shape_b && check(shape_a, shape_b)
              yield(item_a, item_b) if block_given?
            end
            j += 1
          end
        end
        i += 1
      end
    end

    # ファクトリメソッド
    def self.circle(x, y, r); Circle.new(x, y, r); end
    def self.rect(x, y, w, h, angle: 0.0, radius: 0.0, pivot: :center); Rect.new(x, y, w, h, angle: angle, radius: radius, pivot: pivot); end
    def self.point(x, y); Point.new(x, y); end

    # カプセル (角丸矩形 Rect に統合: 長さ len + 直径 2r, 幅 2r, 角丸半径 r)
    def self.capsule(x1, y1, x2, y2, r)
      dx = x2.to_f - x1.to_f
      dy = y2.to_f - y1.to_f
      len = Math.sqrt(dx * dx + dy * dy)
      ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
      cx = (x1.to_f + x2.to_f) * 0.5
      cy = (y1.to_f + y2.to_f) * 0.5
      rad = r.to_f
      Rect.new(cx, cy, len + rad * 2.0, rad * 2.0, angle: ang, radius: rad, pivot: :center)
    end

    def self.polygon(vertices); Polygon.new(vertices); end
  end
end

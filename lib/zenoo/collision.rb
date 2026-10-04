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
    # 幾何クラスは Point, Circle (楕円を包含), Rect (カプセルを包含), Polygon の 4 つ。
    # すべての形状が回転 (angle) および 不等スケール (scale_x, scale_y) に完全対応。
    # サポート定理 P' = M * S(M^T * D) + T により厳密判定。
    # ====================================================

    # 円 / 楕円 (楕円は不等半径・不等スケールの Circle として包含)
    class Circle
      attr_reader :x, :y, :radius_x, :radius_y, :angle, :scale_x, :scale_y, :pivot_x, :pivot_y
      attr_reader :center_x, :center_y, :bounding_radius, :is_true_circle, :effective_radius

      def initialize(x, y, radius_x, radius_y = radius_x, angle: 0.0, scale_x: 1.0, scale_y: 1.0, pivot: :center)
        @x = x.to_f
        @y = y.to_f
        @radius_x = radius_x.to_f
        @radius_y = (radius_y || radius_x).to_f
        @angle = angle.to_f
        @scale_x = scale_x.to_f
        @scale_y = scale_y.to_f
        @_support = [0.0, 0.0]

        set_pivot(pivot)
        @dirty_pos = true
        @dirty_geom = true
        update_cache
      end

      def shape_type; TYPE_CIRCLE; end

      def x=(v); @x = v.to_f; @dirty_pos = true; end
      def y=(v); @y = v.to_f; @dirty_pos = true; end

      def radius; @radius_x; end
      def radius=(val); @radius_x = val.to_f; @radius_y = val.to_f; @dirty_geom = true; end
      def radius_x=(val); @radius_x = val.to_f; @dirty_geom = true; end
      def radius_y=(val); @radius_y = val.to_f; @dirty_geom = true; end
      def angle=(val); @angle = val.to_f; @dirty_geom = true; end
      def scale_x=(val); @scale_x = val.to_f; @dirty_geom = true; end
      def scale_y=(val); @scale_y = val.to_f; @dirty_geom = true; end

      def set_pivot(pivot)
        if pivot == :center
          @pivot_x = 0.5; @pivot_y = 0.5
        elsif pivot == :top_left
          @pivot_x = 0.0; @pivot_y = 0.0
        elsif pivot.is_a?(Array) && pivot.length >= 2
          @pivot_x = pivot[0].to_f; @pivot_y = pivot[1].to_f
        else
          @pivot_x = 0.5; @pivot_y = 0.5
        end
        @dirty_geom = true
      end

      def dirty?
        @dirty_pos || @dirty_geom
      end

      def update_cache
        if @dirty_geom
          @dirty_geom = false
          w = @radius_x * 2.0
          h = @radius_y * 2.0
          @_offset_x = w * (0.5 - @pivot_x)
          @_offset_y = h * (0.5 - @pivot_y)

          sx = @scale_x.abs
          sy = @scale_y.abs
          eff_rx = @radius_x * sx
          eff_ry = @radius_y * sy

          # 真円判定: 実効半径が等しい場合 (回転不変のため三角関数・行列計算をスキップ)
          if (eff_rx - eff_ry).abs < 0.0001
            @is_true_circle = true
            @effective_radius = eff_rx
            @bounding_radius = eff_rx
          else
            @is_true_circle = false
            max_r = @radius_x > @radius_y ? @radius_x : @radius_y
            max_s = sx > sy ? sx : sy
            @bounding_radius = max_r * max_s

            rad = @angle * (Math::PI / 180.0)
            @cos = Math.cos(rad)
            @sin = Math.sin(rad)

            @m00 = @cos * @scale_x
            @m01 = -@sin * @scale_y
            @m10 = @sin * @scale_x
            @m11 = @cos * @scale_y

            @rx2 = @radius_x * @radius_x
            @ry2 = @radius_y * @radius_y
          end
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          @center_x = @x + @_offset_x
          @center_y = @y + @_offset_y
        end
      end

      # 円・楕円の閉形式サポート写像: M * S(M^T * D) + T
      def support(dx, dy)
        # 真円なら回転・歪み逆変換不要で直接正規化
        if @is_true_circle
          len_sq = dx * dx + dy * dy
          if len_sq > 0.000001
            inv_len = @effective_radius / Math.sqrt(len_sq)
            @_support[0] = @center_x + dx * inv_len
            @_support[1] = @center_y + dy * inv_len
          else
            @_support[0] = @center_x
            @_support[1] = @center_y
          end
          return @_support
        end

        ldx = @m00 * dx + @m10 * dy
        ldy = @m01 * dx + @m11 * dy

        k_sq = @rx2 * ldx * ldx + @ry2 * ldy * ldy
        if k_sq > 0.000001
          inv_k = 1.0 / Math.sqrt(k_sq)
          lpx = @rx2 * ldx * inv_k
          lpy = @ry2 * ldy * inv_k
        else
          lpx = 0.0
          lpy = 0.0
        end

        @_support[0] = @center_x + (@m00 * lpx + @m01 * lpy)
        @_support[1] = @center_y + (@m10 * lpx + @m11 * lpy)
        @_support
      end
    end

    # 点
    class Point
      attr_reader :x, :y

      def initialize(x = 0.0, y = 0.0)
        @x = x.to_f
        @y = y.to_f
        @_support = [0.0, 0.0]
      end

      def x=(v); @x = v.to_f; end
      def y=(v); @y = v.to_f; end

      def shape_type; TYPE_POINT; end
      def center_x; @x; end
      def center_y; @y; end
      def bounding_radius; 0.0; end
      def dirty?; false; end
      def update_cache; end

      def support(_dx, _dy)
        @_support[0] = @x
        @_support[1] = @y
        @_support
      end
    end

    # 矩形 / OBB / 角丸矩形 (カプセルを包含)
    class Rect
      attr_reader :x, :y, :width, :height, :angle, :radius, :scale_x, :scale_y, :pivot_x, :pivot_y
      attr_reader :center_x, :center_y, :half_w, :half_h, :core_half_w, :core_half_h
      attr_reader :is_aabb, :is_rounded, :is_uniform, :bounding_radius, :cos, :sin

      def initialize(x, y, width, height, angle: 0.0, radius: 0.0, scale_x: 1.0, scale_y: 1.0, pivot: :center)
        @x = x.to_f
        @y = y.to_f
        @width = width.to_f
        @height = height.to_f
        @angle = angle.to_f
        @radius = radius.to_f
        @scale_x = scale_x.to_f
        @scale_y = scale_y.to_f
        @_support = [0.0, 0.0]

        set_pivot(pivot)
        @dirty_pos = true
        @dirty_geom = true
        update_cache
      end

      def shape_type; TYPE_RECT; end

      def x=(v); @x = v.to_f; @dirty_pos = true; end
      def y=(v); @y = v.to_f; @dirty_pos = true; end

      def width=(v);   @width = v.to_f;   @dirty_geom = true; end
      def height=(v);  @height = v.to_f;  @dirty_geom = true; end
      def radius=(v);  @radius = v.to_f;  @dirty_geom = true; end
      def angle=(v);   @angle = v.to_f;   @dirty_geom = true; end
      def scale_x=(v); @scale_x = v.to_f; @dirty_geom = true; end
      def scale_y=(v); @scale_y = v.to_f; @dirty_geom = true; end

      def set_pivot(pivot)
        if pivot == :center
          @pivot_x = 0.5; @pivot_y = 0.5
        elsif pivot == :top_left
          @pivot_x = 0.0; @pivot_y = 0.0
        elsif pivot.is_a?(Array) && pivot.length >= 2
          @pivot_x = pivot[0].to_f; @pivot_y = pivot[1].to_f
        else
          @pivot_x = 0.5; @pivot_y = 0.5
        end
        @dirty_geom = true
      end

      def dirty?
        @dirty_pos || @dirty_geom
      end

      def update_cache
        if @dirty_geom
          @dirty_geom = false
          @half_w = @width * 0.5
          @half_h = @height * 0.5
          @_offset_x = @width * (0.5 - @pivot_x)
          @_offset_y = @height * (0.5 - @pivot_y)

          # 角丸半径のクランプ
          max_r = @half_w < @half_h ? @half_w : @half_h
          @radius = 0.0 if @radius < 0.0
          @radius = max_r if @radius > max_r
          @is_rounded = (@radius > 0.0001)

          @core_half_w = @half_w - @radius
          @core_half_h = @half_h - @radius

          # 等倍スケール判定
          @is_uniform = ((@scale_x - 1.0).abs < 0.0001 && (@scale_y - 1.0).abs < 0.0001)

          # AABB 判定 (非回転かつ等倍)
          norm_ang = (@angle % 360.0).abs
          is_axis_aligned = (norm_ang < 0.0001 || (norm_ang - 360.0).abs < 0.0001)
          @is_aabb = (is_axis_aligned && @is_uniform)

          # 外接円半径
          base_r = Math.sqrt(@half_w * @half_w + @half_h * @half_h)
          sx = @scale_x.abs
          sy = @scale_y.abs
          max_s = sx > sy ? sx : sy
          @bounding_radius = base_r * max_s

          if is_axis_aligned
            @cos = 1.0
            @sin = 0.0
            @m00 = @scale_x
            @m01 = 0.0
            @m10 = 0.0
            @m11 = @scale_y
          else
            rad = @angle * (Math::PI / 180.0)
            @cos = Math.cos(rad)
            @sin = Math.sin(rad)
            @m00 = @cos * @scale_x
            @m01 = -@sin * @scale_y
            @m10 = @sin * @scale_x
            @m11 = @cos * @scale_y
          end
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          @center_x = @x + @_offset_x
          @center_y = @y + @_offset_y
        end
      end

      # OBB / 角丸矩形 / 不等スケール角丸矩形の完全サポート写像
      def support(dx, dy)
        ldx = @m00 * dx + @m10 * dy
        ldy = @m01 * dx + @m11 * dy

        # 芯となる矩形でのローカル最遠点
        lpx = (ldx >= 0.0) ? @core_half_w : -@core_half_w
        lpy = (ldy >= 0.0) ? @core_half_h : -@core_half_h

        # 角丸部分 (不等スケーリング時は自動的に楕円弧に歪む)
        if @is_rounded
          len_sq = ldx * ldx + ldy * ldy
          if len_sq > 0.000001
            inv_len = @radius / Math.sqrt(len_sq)
            lpx += ldx * inv_len
            lpy += ldy * inv_len
          end
        end

        @_support[0] = @center_x + (@m00 * lpx + @m01 * lpy)
        @_support[1] = @center_y + (@m10 * lpx + @m11 * lpy)
        @_support
      end
    end

    # 凸多角形 (Convex Polygon: 回転・不等スケーリング対応)
    class Polygon
      attr_reader :x, :y, :angle, :scale_x, :scale_y, :pivot_x, :pivot_y
      attr_reader :vertices, :local_vertices, :center_x, :center_y, :bounding_radius

      def initialize(vertices, x: 0.0, y: 0.0, angle: 0.0, scale_x: 1.0, scale_y: 1.0, pivot: :center)
        @vertices = vertices.map { |v| [v[0].to_f, v[1].to_f] }
        @x = x.to_f
        @y = y.to_f
        @angle = angle.to_f
        @scale_x = scale_x.to_f
        @scale_y = scale_y.to_f
        @_support = [0.0, 0.0]

        set_pivot(pivot)
        @dirty_pos = true
        @dirty_geom = true
        update_cache
      end

      def shape_type; TYPE_POLYGON; end

      def x=(v); @x = v.to_f; @dirty_pos = true; end
      def y=(v); @y = v.to_f; @dirty_pos = true; end
      def angle=(v);   @angle = v.to_f;   @dirty_geom = true; end
      def scale_x=(v); @scale_x = v.to_f; @dirty_geom = true; end
      def scale_y=(v); @scale_y = v.to_f; @dirty_geom = true; end
      def vertices=(v); @vertices = v.map { |pt| [pt[0].to_f, pt[1].to_f] }; @dirty_geom = true; end

      def set_pivot(pivot)
        if pivot == :center
          @pivot_x = 0.5; @pivot_y = 0.5
        elsif pivot == :top_left
          @pivot_x = 0.0; @pivot_y = 0.0
        elsif pivot.is_a?(Array) && pivot.length >= 2
          @pivot_x = pivot[0].to_f; @pivot_y = pivot[1].to_f
        else
          @pivot_x = 0.5; @pivot_y = 0.5
        end
        @dirty_geom = true
      end

      def dirty?
        @dirty_pos || @dirty_geom
      end

      def update_cache
        if @dirty_geom
          @dirty_geom = false
          sum_x = 0.0
          sum_y = 0.0
          count = @vertices.length
          return if count == 0

          @vertices.each do |v|
            sum_x += v[0]
            sum_y += v[1]
          end
          @_local_cx = sum_x / count
          @_local_cy = sum_y / count

          @local_vertices = []
          @vertices.each do |v|
            @local_vertices << [v[0] - @_local_cx, v[1] - @_local_cy]
          end

          max_r_sq = 0.0
          @local_vertices.each do |v|
            r_sq = v[0] * v[0] + v[1] * v[1]
            max_r_sq = r_sq if r_sq > max_r_sq
          end
          sx = @scale_x.abs
          sy = @scale_y.abs
          max_s = sx > sy ? sx : sy
          @bounding_radius = Math.sqrt(max_r_sq) * max_s

          rad = @angle * (Math::PI / 180.0)
          @cos = Math.cos(rad)
          @sin = Math.sin(rad)

          @m00 = @cos * @scale_x
          @m01 = -@sin * @scale_y
          @m10 = @sin * @scale_x
          @m11 = @cos * @scale_y
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          @center_x = @x + (@_local_cx || 0.0)
          @center_y = @y + (@_local_cy || 0.0)
        end
      end

      def support(dx, dy)
        ldx = @m00 * dx + @m10 * dy
        ldy = @m01 * dx + @m11 * dy

        max_dot = -1.0e30
        best_x = 0.0
        best_y = 0.0

        i = 0
        len = @local_vertices.length
        while i < len
          v = @local_vertices[i]
          dot = v[0] * ldx + v[1] * ldy
          if dot > max_dot
            max_dot = dot
            best_x = v[0]
            best_y = v[1]
          end
          i += 1
        end

        @_support[0] = @center_x + (@m00 * best_x + @m01 * best_y)
        @_support[1] = @center_y + (@m10 * best_x + @m11 * best_y)
        @_support
      end
    end

    # ====================================================
    # 衝突判定メインエントリ
    # ====================================================
    def self.check(shape_a, shape_b)
      shape_a.update_cache if shape_a.dirty?
      shape_b.update_cache if shape_b.dirty?

      dx = shape_b.center_x - shape_a.center_x
      dy = shape_b.center_y - shape_a.center_y
      dist_sq = dx * dx + dy * dy
      r_sum = shape_a.bounding_radius + shape_b.bounding_radius

      # 1. ブロードフェーズ: 外接円が離れていれば絶対に当たっていない
      return false if dist_sq > r_sum * r_sum

      type_a = shape_a.shape_type
      type_b = shape_b.shape_type

      # 2. 高速パス (Fast Path)

      # 真円 vs 真円 (どちらも is_true_circle な Circle)
      if type_a == TYPE_CIRCLE && type_b == TYPE_CIRCLE
        if shape_a.is_true_circle && shape_b.is_true_circle
          r = shape_a.effective_radius + shape_b.effective_radius
          return dist_sq <= r * r
        end
      end

      # 点 vs 真円
      if type_a == TYPE_POINT && type_b == TYPE_CIRCLE && shape_b.is_true_circle
        r = shape_b.effective_radius
        return dist_sq <= r * r
      elsif type_a == TYPE_CIRCLE && type_b == TYPE_POINT && shape_a.is_true_circle
        r = shape_a.effective_radius
        return dist_sq <= r * r
      end

      # 真円 vs 等倍矩形 (角丸含む)
      if type_a == TYPE_CIRCLE && type_b == TYPE_RECT && shape_a.is_true_circle && shape_b.is_uniform
        return check_circle_rect(shape_a, shape_b, dx, dy)
      elsif type_a == TYPE_RECT && type_b == TYPE_CIRCLE && shape_b.is_true_circle && shape_a.is_uniform
        return check_circle_rect(shape_b, shape_a, -dx, -dy)
      end

      # 点 vs 等倍矩形 (角丸含む)
      if type_a == TYPE_POINT && type_b == TYPE_RECT && shape_b.is_uniform
        return check_point_rect(shape_a, shape_b, dx, dy)
      elsif type_a == TYPE_RECT && type_b == TYPE_POINT && shape_a.is_uniform
        return check_point_rect(shape_b, shape_a, -dx, -dy)
      end

      # 等倍・非角丸 矩形 vs 矩形
      if type_a == TYPE_RECT && type_b == TYPE_RECT && shape_a.is_uniform && shape_b.is_uniform
        if !shape_a.is_rounded && !shape_b.is_rounded
          if shape_a.is_aabb && shape_b.is_aabb
            return false if (dx > 0 ? dx : -dx) > (shape_a.half_w + shape_b.half_w)
            return false if (dy > 0 ? dy : -dy) > (shape_a.half_h + shape_b.half_h)
            return true
          else
            return check_obb_obb(shape_a, shape_b, dx, dy)
          end
        end
      end

      # 3. ナローフェーズ (GJK: 回転楕円, 不等スケール角丸矩形, 多角形などを完全厳密判定)
      gjk(shape_a, shape_b, dx, dy, dist_sq)
    end

    # 真円 vs 等倍矩形 (回転・角丸対応 SDF 判定)
    def self.check_circle_rect(circle, rect, dx, dy)
      ldx = dx * rect.cos + dy * rect.sin
      ldy = -dx * rect.sin + dy * rect.cos
      ldx = -ldx if ldx < 0.0
      ldy = -ldy if ldy < 0.0

      total_r = rect.radius + circle.effective_radius
      diff_x = ldx - rect.core_half_w
      diff_x = 0.0 if diff_x < 0.0
      diff_y = ldy - rect.core_half_h
      diff_y = 0.0 if diff_y < 0.0

      (diff_x * diff_x + diff_y * diff_y) <= (total_r * total_r)
    end

    # 点 vs 等倍矩形 (回転・角丸対応 SDF 判定)
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

    # 2D OBB vs OBB の分離軸テスト (SAT: 4軸射影・等倍矩形特化)
    def self.check_obb_obb(a, b, dx, dy)
      cos_rel = b.cos * a.cos + b.sin * a.sin
      sin_rel = b.sin * a.cos - b.cos * a.sin
      c = cos_rel >= 0.0 ? cos_rel : -cos_rel
      s = sin_rel >= 0.0 ? sin_rel : -sin_rel

      dx_a = dx * a.cos + dy * a.sin
      dx_a = -dx_a if dx_a < 0.0
      return false if dx_a > (a.half_w + b.half_w * c + b.half_h * s)

      dy_a = -dx * a.sin + dy * a.cos
      dy_a = -dy_a if dy_a < 0.0
      return false if dy_a > (a.half_h + b.half_w * s + b.half_h * c)

      dx_b = dx * b.cos + dy * b.sin
      dx_b = -dx_b if dx_b < 0.0
      return false if dx_b > (b.half_w + a.half_w * c + a.half_h * s)

      dy_b = -dx * b.sin + dy * b.cos
      dy_b = -dy_b if dy_b < 0.0
      return false if dy_b > (b.half_h + a.half_w * s + a.half_h * c)

      true
    end

    # GJK コアアルゴリズム (任意凸形状・回転・不等スケーリングに完全対応)
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
        shape_a = (item_a.is_a?(Rect) || item_a.is_a?(Circle) || item_a.is_a?(Polygon) || item_a.is_a?(Point)) ? item_a : (item_a.respond_to?(:collider) ? item_a.collider : nil)
        if shape_a
          j = 0
          while j < len_b
            item_b = group_b[j]
            shape_b = (item_b.is_a?(Rect) || item_b.is_a?(Circle) || item_b.is_a?(Polygon) || item_b.is_a?(Point)) ? item_b : (item_b.respond_to?(:collider) ? item_b.collider : nil)
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
    # 円 / 楕円 (ry を省略した場合は真円)
    def self.circle(x, y, rx, ry = rx, angle: 0.0, scale_x: 1.0, scale_y: 1.0, pivot: :center)
      Circle.new(x, y, rx, ry, angle: angle, scale_x: scale_x, scale_y: scale_y, pivot: pivot)
    end

    # 矩形 / 角丸矩形
    def self.rect(x, y, w, h, angle: 0.0, radius: 0.0, scale_x: 1.0, scale_y: 1.0, pivot: :center)
      Rect.new(x, y, w, h, angle: angle, radius: radius, scale_x: scale_x, scale_y: scale_y, pivot: pivot)
    end

    # 点
    def self.point(x, y)
      Point.new(x, y)
    end

    # 太さを持つ直線 / 線分 (角丸なしの OBB: 端面は直角)
    def self.line(x1, y1, x2, y2, width = 1.0)
      dx = x2.to_f - x1.to_f
      dy = y2.to_f - y1.to_f
      len = Math.sqrt(dx * dx + dy * dy)
      ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
      cx = (x1.to_f + x2.to_f) * 0.5
      cy = (y1.to_f + y2.to_f) * 0.5
      Rect.new(cx, cy, len, width.to_f, angle: ang, radius: 0.0, pivot: :center)
    end

    # セグメント (両端が半円のカプセル形状: 角丸矩形 Rect に統合)
    def self.segment(x1, y1, x2, y2, r)
      dx = x2.to_f - x1.to_f
      dy = y2.to_f - y1.to_f
      len = Math.sqrt(dx * dx + dy * dy)
      ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
      cx = (x1.to_f + x2.to_f) * 0.5
      cy = (y1.to_f + y2.to_f) * 0.5
      rad = r.to_f
      Rect.new(cx, cy, len + rad * 2.0, rad * 2.0, angle: ang, radius: rad, pivot: :center)
    end

    # 多角形
    def self.polygon(vertices, x: 0.0, y: 0.0, angle: 0.0, scale_x: 1.0, scale_y: 1.0, pivot: :center)
      Polygon.new(vertices, x: x, y: y, angle: angle, scale_x: scale_x, scale_y: scale_y, pivot: pivot)
    end
  end
end

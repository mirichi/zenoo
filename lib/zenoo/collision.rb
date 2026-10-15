# frozen_string_literal: true

module Zenoo
  module Collision
    # 形状種別定数 (高速整数ディスパッチ用)
    TYPE_POINT   = 0
    TYPE_CIRCLE  = 1
    TYPE_RECT    = 2
    TYPE_POLYGON = 3

    # ====================================================
    # 衝突めり込み・押し出し結果 (MTV: Minimum Translation Vector)
    # ====================================================
    class Hit
      attr_accessor :depth, :normal_x, :normal_y, :overlap_x, :overlap_y, :impact, :contact_x, :contact_y

      def initialize(depth = 0.0, normal_x = 0.0, normal_y = 0.0, overlap_x = 0.0, overlap_y = 0.0, impact = 0.0, contact_x = 0.0, contact_y = 0.0)
        @depth = depth.to_f
        @normal_x = normal_x.to_f
        @normal_y = normal_y.to_f
        @overlap_x = overlap_x.to_f
        @overlap_y = overlap_y.to_f
        @impact = impact.to_f
        @contact_x = contact_x.to_f
        @contact_y = contact_y.to_f
      end

      # a を押し戻す移動量 (overlap_x, overlap_y)
      def push_x; @overlap_x; end
      def push_y; @overlap_y; end

      # b を押し戻す移動量 (-overlap_x, -overlap_y)
      def push_b_x; -@overlap_x; end
      def push_b_y; -@overlap_y; end

      # 向き反転 (a と b を入れ替えた結果)
      def flipped
        Hit.new(@depth, -@normal_x, -@normal_y, -@overlap_x, -@overlap_y, @impact, @contact_x, @contact_y)
      end

      def inspect
        "#<Zenoo::Collision::Hit depth=#{@depth.round(3)} normal=[#{@normal_x.round(3)}, #{@normal_y.round(3)}] contact=[#{@contact_x.round(2)}, #{@contact_y.round(2)}] overlap=[#{@overlap_x.round(3)}, #{@overlap_y.round(3)}]>"
      end
    end

    # ====================================================
    # 幾何形状定義 (凸形状)
    # 幾何クラスは Point, Circle (楕円を包含), Rect (カプセルを包含), Polygon の 4 つ。
    # すべての形状が回転 (angle) および 不等スケール (scale_x, scale_y) に完全対応。
    # サポート定理 P' = M * S(M^T * D) + T により厳密判定。
    # ====================================================

    # 幾何アライメント定義定数
    ALIGN_MAP = {
      top_left: [0.0, 0.0],      north_west: [0.0, 0.0],
      top_center: [0.5, 0.0],    north: [0.5, 0.0],
      top_right: [1.0, 0.0],     north_east: [1.0, 0.0],
      center_left: [0.0, 0.5],   west: [0.0, 0.5],
      center: [0.5, 0.5],
      center_right: [1.0, 0.5],  east: [1.0, 0.5],
      bottom_left: [0.0, 1.0],   south_west: [0.0, 1.0],
      bottom_center: [0.5, 1.0], south: [0.5, 1.0],
      bottom_right: [1.0, 1.0],  south_east: [1.0, 1.0]
    }.freeze

    # アンカー解釈共通ヘルパー
    def self.parse_anchor(val)
      return [val[0].to_f, (val[1] || val[0]).to_f] if val.is_a?(Array)
      ALIGN_MAP[val] || [0.0, 0.0]
    end

    # ピボット解釈共通ヘルパー
    def self.parse_pivot(val)
      return [val[0].to_f, (val[1] || val[0]).to_f] if val.is_a?(Array)
      ALIGN_MAP[val] || [0.5, 0.5]
    end

    # 幾何形状の基底クラス (ポリモーフィック静的型解決用共通インターフェース)
    class Shape
      attr_reader :anchor_x, :anchor_y, :pivot_x, :pivot_y, :offset_x, :offset_y
      attr_accessor :parent

      def initialize(x = 0.0, y = 0.0, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :center, pivot: :center, parent: nil)
        @parent = parent
        @x = x.to_f
        @y = y.to_f
        @angle = angle.to_f
        @scale_x = scale_x.to_f
        @scale_y = scale_y.to_f
        @offset_x = offset_x.to_f
        @offset_y = offset_y.to_f
        @_support = [0.0, 0.0]

        @anchor_x = 0.0
        @anchor_y = 0.0
        @pivot_x = 0.5
        @pivot_y = 0.5

        set_anchor(anchor)
        set_pivot(pivot)
        dirty_pos!
        dirty_geom!
      end

      def is_rounded; false; end
      def is_aabb; false; end
      def is_uniform; false; end
      def half_w; 0.0; end
      def half_h; 0.0; end
      def core_half_w; 0.0; end
      def core_half_h; 0.0; end
      def radius; 0.0; end
      def cos; 1.0; end
      def sin; 0.0; end
      def bounding_radius; 0.0; end
      def dirty?; false; end
      def update_cache; end

      def dirty_pos!; @dirty_pos = true; end
      def dirty_geom!; @dirty_geom = true; @dirty_pos = true; end

      def x
        @parent ? @parent.x : @x
      end

      def x=(v)
        vf = v.to_f
        return if @x == vf
        @x = vf
        dirty_pos!
      end

      def y
        @parent ? @parent.y : @y
      end

      def y=(v)
        vf = v.to_f
        return if @y == vf
        @y = vf
        dirty_pos!
      end

      def angle
        @parent ? @parent.angle : @angle
      end

      def angle=(v)
        vf = v.to_f
        return if @angle == vf
        @angle = vf
        dirty_geom!
      end

      def scale_x
        @parent ? @parent.scale_x : @scale_x
      end

      def scale_x=(v)
        vf = v.to_f
        return if @scale_x == vf
        @scale_x = vf
        dirty_geom!
      end

      def scale_y
        @parent ? @parent.scale_y : @scale_y
      end

      def scale_y=(v)
        vf = v.to_f
        return if @scale_y == vf
        @scale_y = vf
        dirty_geom!
      end

      def scale=(v)
        vf = v.to_f
        return if @scale_x == vf && @scale_y == vf
        @scale_x = vf
        @scale_y = vf
        dirty_geom!
      end

      # 親 Sprite が存在する場合のワールド重心座標を1パスで算出
      def compute_parent_center(offset_x, offset_y, cos_v, sin_v, sx, sy)
        p = @parent
        pw = p.width
        ph = p.height
        pv_x = p.pivot_x
        pv_y = p.pivot_y

        tl_x = p.x - p.anchor_x * pw
        tl_y = p.y - p.anchor_y * ph
        wpv_x = tl_x + pv_x * pw
        wpv_y = tl_y + pv_y * ph

        rel_cx = (0.5 - pv_x) * pw + offset_x
        rel_cy = (0.5 - pv_y) * ph + offset_y

        if rel_cx.abs < 0.0001 && rel_cy.abs < 0.0001
          [wpv_x, wpv_y]
        else
          s_rel_cx = rel_cx * sx
          s_rel_cy = rel_cy * sy
          rot_cx = s_rel_cx * cos_v - s_rel_cy * sin_v
          rot_cy = s_rel_cx * sin_v + s_rel_cy * cos_v
          [wpv_x + rot_cx, wpv_y + rot_cy]
        end
      end

      def center_x
        update_cache if dirty?
        @center_x
      end

      def center_y
        update_cache if dirty?
        @center_y
      end

      # アンカー (取得)
      def anchor
        if (@anchor_x - 0.0).abs < 0.0001 && (@anchor_y - 0.0).abs < 0.0001
          :top_left
        elsif (@anchor_x - 0.5).abs < 0.0001 && (@anchor_y - 0.5).abs < 0.0001
          :center
        else
          [@anchor_x, @anchor_y]
        end
      end

      def anchor=(val)
        ax, ay = Collision.parse_anchor(val)
        return if @anchor_x == ax && @anchor_y == ay
        @anchor_x = ax
        @anchor_y = ay
        dirty_pos!
      end

      def anchor_x=(val)
        vf = val.to_f
        return if @anchor_x == vf
        @anchor_x = vf
        dirty_pos!
      end

      def anchor_y=(val)
        vf = val.to_f
        return if @anchor_y == vf
        @anchor_y = vf
        dirty_pos!
      end

      # ピボット (取得)
      def pivot
        if (@pivot_x - 0.5).abs < 0.0001 && (@pivot_y - 0.5).abs < 0.0001
          :center
        elsif (@pivot_x - 0.0).abs < 0.0001 && (@pivot_y - 0.0).abs < 0.0001
          :top_left
        else
          [@pivot_x, @pivot_y]
        end
      end

      def pivot=(val)
        px, py = Collision.parse_pivot(val)
        return if @pivot_x == px && @pivot_y == py
        @pivot_x = px
        @pivot_y = py
        dirty_geom!
      end

      def offset_x=(val)
        vf = val.to_f
        return if @offset_x == vf
        @offset_x = vf
        dirty_pos!
      end

      def offset_y=(val)
        vf = val.to_f
        return if @offset_y == vf
        @offset_y = vf
        dirty_pos!
      end

      # 重心 (設定: アンカー位置に関わらず重心が指定座標になるよう x, y を平行移動)
      def center_x=(val)
        vf = val.to_f
        diff = vf - center_x
        @x += diff
        dirty_pos!
      end

      def center_y=(val)
        vf = val.to_f
        diff = vf - center_y
        @y += diff
        dirty_pos!
      end

      def set_center(cx, cy)
        self.center_x = cx
        self.center_y = cy
      end

      # 内部初期化用エイリアス
      alias set_anchor anchor=
      alias set_pivot pivot=
    end

    # 円 / 楕円 (楕円は不等半径・不等スケールの Circle として包含)
    class Circle < Shape
      attr_reader :radius_x, :radius_y
      attr_reader :bounding_radius, :is_true_circle, :effective_radius

      def initialize(x = 0.0, y = 0.0, radius_x = 0.0, radius_y = radius_x, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :center, pivot: :center, parent: nil)
        super(x, y, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot, parent: parent)
        @radius_x = radius_x.to_f
        @radius_y = (radius_y || radius_x).to_f
        update_cache
      end

      def shape_type; TYPE_CIRCLE; end

      def radius; @radius_x; end
      def radius=(val)
        vf = val.to_f
        return if @radius_x == vf && @radius_y == vf
        @radius_x = vf
        @radius_y = vf
        dirty_geom!
      end

      def radius_x=(val)
        vf = val.to_f
        return if @radius_x == vf
        @radius_x = vf
        dirty_geom!
      end

      def radius_y=(val)
        vf = val.to_f
        return if @radius_y == vf
        @radius_y = vf
        dirty_geom!
      end

      def dirty_pos!; @dirty_pos = true; end
      def dirty_geom!; @dirty_geom = true; @dirty_pos = true; end

      def dirty?
        @dirty_pos || @dirty_geom
      end

      def update_cache
        cur_sx = scale_x
        cur_sy = scale_y
        cur_ang = angle

        if @dirty_geom
          @dirty_geom = false
          w = @radius_x * 2.0
          h = @radius_y * 2.0

          sx = cur_sx.abs
          sy = cur_sy.abs
          eff_rx = @radius_x * sx
          eff_ry = @radius_y * sy

          rad = cur_ang * (Math::PI / 180.0)
          @cos = Math.cos(rad)
          @sin = Math.sin(rad)

          # 真円判定: 実効半径が等しい場合 (回転不変のため三角関数・行列計算をスキップ)
          if (eff_rx - eff_ry).abs < 0.0001
            @is_true_circle = true
            @effective_radius = eff_rx
            @bounding_radius = eff_rx
          else
            @is_true_circle = false
            @bounding_radius = eff_rx > eff_ry ? eff_rx : eff_ry

            @m00 = @cos * cur_sx
            @m01 = -@sin * cur_sy
            @m10 = @sin * cur_sx
            @m11 = @cos * cur_sy

            @rx2 = @radius_x * @radius_x
            @ry2 = @radius_y * @radius_y
          end
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          if @parent
            cx, cy = compute_parent_center(@offset_x, @offset_y, @cos, @sin, cur_sx, cur_sy)
            @center_x = cx
            @center_y = cy
          else
            w = @radius_x * 2.0
            h = @radius_y * 2.0
            tl_x = @x - @anchor_x * w
            tl_y = @y - @anchor_y * h
            wpv_x = tl_x + @pivot_x * w
            wpv_y = tl_y + @pivot_y * h

            rel_cx = (0.5 - @pivot_x) * w + @offset_x
            rel_cy = (0.5 - @pivot_y) * h + @offset_y

            if rel_cx.abs < 0.0001 && rel_cy.abs < 0.0001
              @center_x = wpv_x
              @center_y = wpv_y
            else
              s_rel_cx = rel_cx * cur_sx
              s_rel_cy = rel_cy * cur_sy
              rot_cx = s_rel_cx * @cos - s_rel_cy * @sin
              rot_cy = s_rel_cx * @sin + s_rel_cy * @cos
              @center_x = wpv_x + rot_cx
              @center_y = wpv_y + rot_cy
            end
          end
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
    class Point < Shape
      def initialize(x = 0.0, y = 0.0, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :top_left, pivot: :center, parent: nil)
        super(x, y, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot, parent: parent)
        update_cache
      end

      def shape_type; TYPE_POINT; end

      def dirty_pos!; @dirty_pos = true; end
      def dirty_geom!; @dirty_angle = true; @dirty_pos = true; end

      def dirty?; @dirty_pos || @dirty_angle; end

      def update_cache
        cur_ang = angle
        cur_sx = scale_x
        cur_sy = scale_y

        if @dirty_angle
          @dirty_angle = false
          rad = cur_ang * (Math::PI / 180.0)
          @cos = Math.cos(rad)
          @sin = Math.sin(rad)
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          if @parent
            cx, cy = compute_parent_center(@offset_x, @offset_y, @cos || 1.0, @sin || 0.0, cur_sx, cur_sy)
            @center_x = cx
            @center_y = cy
          else
            if @offset_x == 0.0 && @offset_y == 0.0
              @center_x = @x
              @center_y = @y
            else
              s_ox = @offset_x * cur_sx
              s_oy = @offset_y * cur_sy
              cos_v = @cos || 1.0
              sin_v = @sin || 0.0
              rot_x = s_ox * cos_v - s_oy * sin_v
              rot_y = s_ox * sin_v + s_oy * cos_v
              @center_x = @x + rot_x
              @center_y = @y + rot_y
            end
          end
        end
      end

      def support(_dx, _dy)
        @_support[0] = center_x
        @_support[1] = center_y
        @_support
      end
    end

    # 矩形 / OBB / 角丸矩形 (カプセルを包含)
    class Rect < Shape
      attr_reader :radius
      attr_reader :half_w, :half_h, :core_half_w, :core_half_h
      attr_reader :is_aabb, :is_rounded, :is_uniform, :bounding_radius, :cos, :sin

      def initialize(x = 0.0, y = 0.0, width = 0.0, height = 0.0, angle: 0.0, radius: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :top_left, pivot: :center, parent: nil)
        super(x, y, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot, parent: parent)
        @width = width.to_f
        @height = height.to_f
        @radius = radius.to_f
        @is_aabb = false
        @is_rounded = false
        @is_uniform = true
        dirty_size!
        update_cache
      end

      def shape_type; TYPE_RECT; end

      def width
        if @parent && (@width == 0.0 || @width.nil?)
          @parent.width
        else
          @width
        end
      end

      def width=(v)
        vf = v.to_f
        return if @width == vf
        @width = vf
        @dirty_size = true
      end

      def height
        if @parent && (@height == 0.0 || @height.nil?)
          @parent.height
        else
          @height
        end
      end

      def height=(v)
        vf = v.to_f
        return if @height == vf
        @height = vf
        @dirty_size = true
      end

      def radius=(v)
        vf = v.to_f
        return if @radius == vf
        @radius = vf
        @dirty_size = true
      end

      def dirty_pos!; @dirty_pos = true; @_dirty_world_verts = true; end
      def dirty_geom!; @dirty_angle = true; @dirty_scale = true; @dirty_pos = true; @_dirty_world_verts = true; end
      def dirty_size!; @dirty_size = true; dirty_geom!; end

      def dirty?
        @dirty_pos || @dirty_angle || @dirty_scale || @dirty_size
      end

      def update_cache
        cur_w = width
        cur_h = height
        cur_sx = scale_x
        cur_sy = scale_y
        cur_ang = angle

        if @dirty_size
          @dirty_size = false
          @half_w = cur_w * 0.5
          @half_h = cur_h * 0.5

          # 角丸半径のクランプ
          max_r = @half_w < @half_h ? @half_w : @half_h
          @radius = 0.0 if @radius < 0.0
          @radius = max_r if @radius > max_r
          @is_rounded = (@radius > 0.0001)

          @core_half_w = @half_w - @radius
          @core_half_h = @half_h - @radius

          @dirty_scale = true
          @dirty_angle = true
          @dirty_pos = true
        end

        if @dirty_scale
          @dirty_scale = false
          # 等倍スケール判定
          @is_uniform = ((cur_sx - 1.0).abs < 0.0001 && (cur_sy - 1.0).abs < 0.0001)

          # 外接円半径 (スケール後の半幅・半高さから厳密に計算)
          scaled_hw = @half_w * cur_sx.abs
          scaled_hh = @half_h * cur_sy.abs
          @bounding_radius = Math.sqrt(scaled_hw * scaled_hw + scaled_hh * scaled_hh)
          @dirty_angle = true
        end

        if @dirty_angle
          @dirty_angle = false
          # AABB 判定 (非回転かつ等倍)
          norm_ang = (cur_ang % 360.0).abs
          is_axis_aligned = (norm_ang < 0.0001 || (norm_ang - 360.0).abs < 0.0001)
          @is_aabb = (is_axis_aligned && @is_uniform)

          if is_axis_aligned
            @cos = 1.0
            @sin = 0.0
            @m00 = cur_sx
            @m01 = 0.0
            @m10 = 0.0
            @m11 = cur_sy
          else
            rad = cur_ang * (Math::PI / 180.0)
            @cos = Math.cos(rad)
            @sin = Math.sin(rad)
            @m00 = @cos * cur_sx
            @m01 = -@sin * cur_sy
            @m10 = @sin * cur_sx
            @m11 = @cos * cur_sy
          end
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          if @parent
            cx, cy = compute_parent_center(@offset_x, @offset_y, @cos, @sin, cur_sx, cur_sy)
            @center_x = cx
            @center_y = cy
          else
            tl_x = @x - @anchor_x * cur_w
            tl_y = @y - @anchor_y * cur_h
            wpv_x = tl_x + @pivot_x * cur_w
            wpv_y = tl_y + @pivot_y * cur_h

            rel_cx = (0.5 - @pivot_x) * cur_w + @offset_x
            rel_cy = (0.5 - @pivot_y) * cur_h + @offset_y

            if rel_cx.abs < 0.0001 && rel_cy.abs < 0.0001
              @center_x = wpv_x
              @center_y = wpv_y
            else
              s_rel_cx = rel_cx * cur_sx
              s_rel_cy = rel_cy * cur_sy
              rot_cx = s_rel_cx * @cos - s_rel_cy * @sin
              rot_cy = s_rel_cx * @sin + s_rel_cy * @cos
              @center_x = wpv_x + rot_cx
              @center_y = wpv_y + rot_cy
            end
          end
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

      # ワールド座標系での4頂点 (SAT射影用: 配列再利用キャッシュ)
      def world_vertices
        update_cache if dirty?
        return @_world_vertices if @_world_vertices && !@_dirty_world_verts

        cur_sx = scale_x
        cur_sy = scale_y
        hw = @half_w * cur_sx
        hh = @half_h * cur_sy
        dx1 = hw * @cos - hh * @sin
        dy1 = hw * @sin + hh * @cos
        dx2 = -hw * @cos - hh * @sin
        dy2 = -hw * @sin + hh * @cos

        @_world_vertices ||= [ [0.0, 0.0], [0.0, 0.0], [0.0, 0.0], [0.0, 0.0] ]
        @_world_vertices[0][0] = @center_x + dx1; @_world_vertices[0][1] = @center_y + dy1
        @_world_vertices[1][0] = @center_x - dx2; @_world_vertices[1][1] = @center_y - dy2
        @_world_vertices[2][0] = @center_x - dx1; @_world_vertices[2][1] = @center_y - dy1
        @_world_vertices[3][0] = @center_x + dx2; @_world_vertices[3][1] = @center_y + dy2
        @_dirty_world_verts = false
        @_world_vertices
      end
    end

    # 凸多角形 (Convex Polygon: 回転・不等スケーリング対応)
    class Polygon < Shape
      attr_reader :vertices, :local_vertices, :bounding_radius

      def initialize(vertices, x: 0.0, y: 0.0, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :center, pivot: :center, parent: nil)
        super(x, y, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot, parent: parent)
        @vertices = vertices.map { |v| [v[0].to_f, v[1].to_f] }
        dirty_verts!
        update_cache
      end

      def shape_type; TYPE_POLYGON; end

      def vertices=(v); @vertices = v.map { |pt| [pt[0].to_f, pt[1].to_f] }; @dirty_verts = true; end

      def dirty_pos!; @dirty_pos = true; @_dirty_world_verts = true; end
      def dirty_geom!; @dirty_angle = true; @dirty_scale = true; @dirty_pos = true; @_dirty_world_verts = true; end
      def dirty_verts!; @dirty_verts = true; dirty_geom!; end

      def dirty?
        @dirty_pos || @dirty_angle || @dirty_scale || @dirty_verts
      end

      def update_cache
        cur_ang = angle
        cur_sx = scale_x
        cur_sy = scale_y

        if @dirty_verts
          @dirty_verts = false
          sum_x = 0.0
          sum_y = 0.0
          count = @vertices.length
          return if count == 0

          min_x = @vertices[0][0]
          max_x = @vertices[0][0]
          min_y = @vertices[0][1]
          max_y = @vertices[0][1]

          @vertices.each do |v|
            sum_x += v[0]
            sum_y += v[1]
            min_x = v[0] if v[0] < min_x
            max_x = v[0] if v[0] > max_x
            min_y = v[1] if v[1] < min_y
            max_y = v[1] if v[1] > max_y
          end
          @_local_cx = sum_x / count
          @_local_cy = sum_y / count
          @_bbox_w = max_x - min_x
          @_bbox_h = max_y - min_y
          @_bbox_min_x = min_x
          @_bbox_min_y = min_y

          @local_vertices = []
          @local_vx = []
          @local_vy = []
          @vertices.each do |v|
            lx = v[0] - @_local_cx
            ly = v[1] - @_local_cy
            @local_vertices << [lx, ly]
            @local_vx << lx
            @local_vy << ly
          end

          @dirty_scale = true
          @dirty_angle = true
          @dirty_pos = true
        end

        if @dirty_scale
          @dirty_scale = false
          sx = cur_sx.abs
          sy = cur_sy.abs
          max_r_sq = 0.0
          i = 0
          len = @local_vx ? @local_vx.length : 0
          while i < len
            slx = @local_vx[i] * sx
            sly = @local_vy[i] * sy
            r_sq = slx * slx + sly * sly
            max_r_sq = r_sq if r_sq > max_r_sq
            i += 1
          end
          @bounding_radius = Math.sqrt(max_r_sq)
          @dirty_angle = true
        end

        if @dirty_angle
          @dirty_angle = false
          rad = cur_ang * (Math::PI / 180.0)
          @cos = Math.cos(rad)
          @sin = Math.sin(rad)

          @m00 = @cos * cur_sx
          @m01 = -@sin * cur_sy
          @m10 = @sin * cur_sx
          @m11 = @cos * cur_sy
          @dirty_pos = true
        end

        if @dirty_pos
          @dirty_pos = false
          if @parent
            cx, cy = compute_parent_center(@offset_x, @offset_y, @cos, @sin, cur_sx, cur_sy)
            @center_x = cx
            @center_y = cy
          else
            if (@anchor_x - 0.5).abs < 0.0001 && (@anchor_y - 0.5).abs < 0.0001 &&
               (@pivot_x - 0.5).abs < 0.0001 && (@pivot_y - 0.5).abs < 0.0001
              # :center の場合は重心そのものをアンカー・ピボットとする
              if @offset_x == 0.0 && @offset_y == 0.0
                @center_x = @x
                @center_y = @y
              else
                s_rel_cx = @offset_x * cur_sx
                s_rel_cy = @offset_y * cur_sy
                rot_cx = s_rel_cx * @cos - s_rel_cy * @sin
                rot_cy = s_rel_cx * @sin + s_rel_cy * @cos
                @center_x = @x + rot_cx
                @center_y = @y + rot_cy
              end
            else
              bw = @_bbox_w || 0.0
              bh = @_bbox_h || 0.0
              tl_x = @x - @anchor_x * bw
              tl_y = @y - @anchor_y * bh
              wpv_x = tl_x + @pivot_x * bw
              wpv_y = tl_y + @pivot_y * bh

              # 重心のピボットからの相対座標
              rel_cx = ((@_local_cx || 0.0) - (@_bbox_min_x || 0.0)) - @pivot_x * bw + @offset_x
              rel_cy = ((@_local_cy || 0.0) - (@_bbox_min_y || 0.0)) - @pivot_y * bh + @offset_y

              s_rel_cx = rel_cx * cur_sx
              s_rel_cy = rel_cy * cur_sy
              rot_cx = s_rel_cx * @cos - s_rel_cy * @sin
              rot_cy = s_rel_cx * @sin + s_rel_cy * @cos
              @center_x = wpv_x + rot_cx
              @center_y = wpv_y + rot_cy
            end
          end
        end
      end

      def support(dx, dy)
        ldx = @m00 * dx + @m10 * dy
        ldy = @m01 * dx + @m11 * dy

        max_dot = -1.0e30
        best_x = 0.0
        best_y = 0.0

        i = 0
        len = @local_vx.length
        while i < len
          vx = @local_vx[i]
          vy = @local_vy[i]
          dot = vx * ldx + vy * ldy
          if dot > max_dot
            max_dot = dot
            best_x = vx
            best_y = vy
          end
          i += 1
        end

        @_support[0] = @center_x + (@m00 * best_x + @m01 * best_y)
        @_support[1] = @center_y + (@m10 * best_x + @m11 * best_y)
        @_support
      end

      # ワールド座標系での頂点配列 (SAT射影用: 配列再利用キャッシュ)
      def world_vertices
        update_cache if dirty?
        return @_world_vertices if @_world_vertices && !@_dirty_world_verts

        @_world_vertices ||= []
        cur_sx = scale_x
        cur_sy = scale_y
        len = @local_vx ? @local_vx.length : 0
        i = 0
        while i < len
          lx = @local_vx[i] * cur_sx
          ly = @local_vy[i] * cur_sy
          wx = @center_x + lx * @cos - ly * @sin
          wy = @center_y + lx * @sin + ly * @cos
          if @_world_vertices[i]
            @_world_vertices[i][0] = wx
            @_world_vertices[i][1] = wy
          else
            @_world_vertices[i] = [wx, wy]
          end
          i += 1
        end
        @_world_vertices.pop while @_world_vertices.length > len
        @_dirty_world_verts = false
        @_world_vertices
      end
    end

    # ====================================================
    # 衝突判定メインエントリ
    # ====================================================
    def self.check(shape_a, shape_b)
      shape_a = shape_a.collider if shape_a.respond_to?(:collider)
      shape_b = shape_b.collider if shape_b.respond_to?(:collider)
      return false unless shape_a && shape_b

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

    # Sweep and Prune 用ヘルパー: アイテムから Shape と AABB (min_x, max_x) を抽出
    def self.__extract_sap_entry(item, group_id = nil)
      shape = item.is_a?(Shape) ? item : (item.respond_to?(:collider) ? item.collider : nil)
      return nil unless shape

      shape.update_cache if shape.respond_to?(:dirty?) && shape.dirty?
      r = shape.bounding_radius.to_f
      cx = shape.center_x.to_f
      min_x = cx - r
      max_x = cx + r
      if group_id
        [min_x, max_x, item, shape, group_id]
      else
        [min_x, max_x, item, shape]
      end
    end

    # 小規模配列用の直接総当たり判定
    def self.__check_all_direct(arr_a, arr_b, same_group)
      len_a = arr_a.length
      len_b = arr_b.length
      hits = block_given? ? nil : []

      i = 0
      while i < len_a
        item_a = arr_a[i]
        shape_a = item_a.is_a?(Shape) ? item_a : (item_a.respond_to?(:collider) ? item_a.collider : nil)
        if shape_a
          j = same_group ? (i + 1) : 0
          while j < len_b
            item_b = arr_b[j]
            shape_b = item_b.is_a?(Shape) ? item_b : (item_b.respond_to?(:collider) ? item_b.collider : nil)
            if shape_b && check(shape_a, shape_b)
              if block_given?
                yield(item_a, item_b)
              else
                hits << [item_a, item_b]
              end
            end
            j += 1
          end
        end
        i += 1
      end
      hits
    end

    # 配列・オブジェクト同士の一括衝突判定 (DXRuby 互換: ブロック省略時は衝突ペア配列を返す)
    # Sweep and Prune (X軸ソート＆スイープ) による O(N log N) 高速ブロードフェーズ
    def self.check_all(group_a, group_b = nil, &block)
      arr_a = group_a.is_a?(Array) ? group_a : [group_a]
      same_group = group_b.nil? || group_a.equal?(group_b) || arr_a.equal?(group_b)
      arr_b = same_group ? arr_a : (group_b.is_a?(Array) ? group_b : [group_b])
      len_a = arr_a.length
      len_b = arr_b.length

      # 要素数が極小 (積が64未満) の場合はオーバーヘッドを避けるため直接判定
      if len_a * len_b < 64
        return __check_all_direct(arr_a, arr_b, same_group, &block)
      end

      hits = block_given? ? nil : []

      if same_group
        entries = []
        i = 0
        while i < len_a
          entry = __extract_sap_entry(arr_a[i])
          entries << entry if entry
          i += 1
        end

        entries.sort_by! { |e| e[0] }
        total = entries.length

        i = 0
        while i < total
          e_a = entries[i]
          max_a = e_a[1]
          item_a = e_a[2]
          shape_a = e_a[3]

          j = i + 1
          while j < total
            e_b = entries[j]
            break if e_b[0] > max_a

            item_b = e_b[2]
            shape_b = e_b[3]
            if check(shape_a, shape_b)
              if block_given?
                yield(item_a, item_b)
              else
                hits << [item_a, item_b]
              end
            end
            j += 1
          end
          i += 1
        end
      else
        entries_a = []
        i = 0
        while i < len_a
          entry = __extract_sap_entry(arr_a[i])
          entries_a << entry if entry
          i += 1
        end

        entries_b = []
        max_w_b = 0.0
        i = 0
        while i < len_b
          entry = __extract_sap_entry(arr_b[i])
          if entry
            w_b = entry[1] - entry[0]
            max_w_b = w_b if w_b > max_w_b
            entries_b << entry
          end
          i += 1
        end

        entries_a.sort_by! { |e| e[0] }
        entries_b.sort_by! { |e| e[0] }
        total_a = entries_a.length
        total_b = entries_b.length

        start_j = 0
        i = 0
        while i < total_a
          e_a = entries_a[i]
          min_a = e_a[0]
          max_a = e_a[1]
          item_a = e_a[2]
          shape_a = e_a[3]

          # 左側の切り捨て (Two Pointers): B の先頭要素が完全に A より左側にある間 start_j を進める
          safe_cutoff = min_a - max_w_b
          while start_j < total_b
            e_b_start = entries_b[start_j]
            if e_b_start[1] < min_a || e_b_start[0] < safe_cutoff
              start_j += 1
            else
              break
            end
          end

          j = start_j
          while j < total_b
            e_b = entries_b[j]
            # 右側の打ち切り (Early Out)
            break if e_b[0] > max_a

            # X軸の重なり確認 (先頭に巨大キャラがいて start_j が進んでいなくても、左に外れたキャラはここで即スキップ)
            if e_b[1] >= min_a
              item_b = e_b[2]
              shape_b = e_b[3]
              if check(shape_a, shape_b)
                if block_given?
                  yield(item_a, item_b)
                else
                  hits << [item_a, item_b]
                end
              end
            end
            j += 1
          end
          i += 1
        end
      end
      hits
    end

    # ====================================================
    # 衝突めり込み量・押し出しベクトル (MTV) 算出エントリ
    # ====================================================
    def self.penetration(shape_a, shape_b)
      shape_a = shape_a.collider if shape_a.respond_to?(:collider)
      shape_b = shape_b.collider if shape_b.respond_to?(:collider)
      return nil unless shape_a && shape_b
      return nil if shape_a.is_a?(Array) || shape_b.is_a?(Array)

      shape_a.update_cache if shape_a.respond_to?(:dirty?) && shape_a.dirty?
      shape_b.update_cache if shape_b.respond_to?(:dirty?) && shape_b.dirty?

      dx = shape_b.center_x - shape_a.center_x
      dy = shape_b.center_y - shape_a.center_y
      dist_sq = dx * dx + dy * dy
      r_sum = shape_a.bounding_radius + shape_b.bounding_radius

      # 1. ブロードフェーズ
      return nil if dist_sq > r_sum * r_sum

      type_a = shape_a.shape_type
      type_b = shape_b.shape_type

      # 2. 高速パス (Fast Path)

      # 真円 vs 真円
      if type_a == TYPE_CIRCLE && type_b == TYPE_CIRCLE
        if shape_a.is_true_circle && shape_b.is_true_circle
          return penetration_circle_circle(shape_a, shape_b, dx, dy, dist_sq)
        end
      end

      # 真円 vs 等倍矩形 (角丸含む)
      if type_a == TYPE_CIRCLE && type_b == TYPE_RECT && shape_a.is_true_circle && shape_b.is_uniform
        return penetration_circle_rect(shape_a, shape_b, dx, dy)
      elsif type_a == TYPE_RECT && type_b == TYPE_CIRCLE && shape_b.is_true_circle && shape_a.is_uniform
        hit = penetration_circle_rect(shape_b, shape_a, -dx, -dy)
        return hit ? hit.flipped : nil
      end

      # 等倍・非角丸 矩形 vs 矩形
      if type_a == TYPE_RECT && type_b == TYPE_RECT && shape_a.is_uniform && shape_b.is_uniform
        if !shape_a.is_rounded && !shape_b.is_rounded
          if shape_a.is_aabb && shape_b.is_aabb
            return penetration_aabb_aabb(shape_a, shape_b, dx, dy)
          else
            return penetration_obb_obb(shape_a, shape_b, dx, dy)
          end
        end
      end

      # 3. 汎用 SAT (多角形, 傾いた楕円, 角丸矩形同士など)
      penetration_generic_sat(shape_a, shape_b, dx, dy)
    end

    # 小規模配列用の直接めり込み量判定
    def self.__penetration_all_direct(arr_a, arr_b, same_group)
      len_a = arr_a.length
      len_b = arr_b.length
      hits = block_given? ? nil : []

      i = 0
      while i < len_a
        item_a = arr_a[i]
        shape_a = item_a.is_a?(Shape) ? item_a : (item_a.respond_to?(:collider) ? item_a.collider : nil)
        if shape_a
          j = same_group ? (i + 1) : 0
          while j < len_b
            item_b = arr_b[j]
            shape_b = item_b.is_a?(Shape) ? item_b : (item_b.respond_to?(:collider) ? item_b.collider : nil)
            if shape_b
              hit = penetration(shape_a, shape_b)
              if hit
                if block_given?
                  yield(item_a, item_b, hit)
                else
                  hits << [item_a, item_b, hit]
                end
              end
            end
            j += 1
          end
        end
        i += 1
      end
      hits
    end

    # 配列・オブジェクト同士の一括めり込み量・押し出し (MTV) 判定
    # ブロック省略時は [[item_a, item_b, hit], ...] の配列を返す
    # Sweep and Prune (X軸ソート＆スイープ) による高速ブロードフェーズ
    def self.penetration_all(group_a, group_b = nil, &block)
      arr_a = group_a.is_a?(Array) ? group_a : [group_a]
      same_group = group_b.nil? || group_a.equal?(group_b) || arr_a.equal?(group_b)
      arr_b = same_group ? arr_a : (group_b.is_a?(Array) ? group_b : [group_b])
      len_a = arr_a.length
      len_b = arr_b.length

      if len_a * len_b < 64
        return __penetration_all_direct(arr_a, arr_b, same_group, &block)
      end

      hits = block_given? ? nil : []

      if same_group
        entries = []
        i = 0
        while i < len_a
          entry = __extract_sap_entry(arr_a[i])
          entries << entry if entry
          i += 1
        end

        entries.sort_by! { |e| e[0] }
        total = entries.length

        i = 0
        while i < total
          e_a = entries[i]
          max_a = e_a[1]
          item_a = e_a[2]
          shape_a = e_a[3]

          j = i + 1
          while j < total
            e_b = entries[j]
            break if e_b[0] > max_a

            item_b = e_b[2]
            shape_b = e_b[3]
            hit = penetration(shape_a, shape_b)
            if hit
              if block_given?
                yield(item_a, item_b, hit)
              else
                hits << [item_a, item_b, hit]
              end
            end
            j += 1
          end
          i += 1
        end
      else
        entries_a = []
        i = 0
        while i < len_a
          entry = __extract_sap_entry(arr_a[i])
          entries_a << entry if entry
          i += 1
        end

        entries_b = []
        max_w_b = 0.0
        i = 0
        while i < len_b
          entry = __extract_sap_entry(arr_b[i])
          if entry
            w_b = entry[1] - entry[0]
            max_w_b = w_b if w_b > max_w_b
            entries_b << entry
          end
          i += 1
        end

        entries_a.sort_by! { |e| e[0] }
        entries_b.sort_by! { |e| e[0] }
        total_a = entries_a.length
        total_b = entries_b.length

        start_j = 0
        i = 0
        while i < total_a
          e_a = entries_a[i]
          min_a = e_a[0]
          max_a = e_a[1]
          item_a = e_a[2]
          shape_a = e_a[3]

          # 左側の切り捨て (Two Pointers): B の先頭要素が完全に A より左側にある間 start_j を進める
          safe_cutoff = min_a - max_w_b
          while start_j < total_b
            e_b_start = entries_b[start_j]
            if e_b_start[1] < min_a || e_b_start[0] < safe_cutoff
              start_j += 1
            else
              break
            end
          end

          j = start_j
          while j < total_b
            e_b = entries_b[j]
            # 右側の打ち切り (Early Out)
            break if e_b[0] > max_a

            if e_b[1] >= min_a
              item_b = e_b[2]
              shape_b = e_b[3]
              hit = penetration(shape_a, shape_b)
              if hit
                if block_given?
                  yield(item_a, item_b, hit)
                else
                  hits << [item_a, item_b, hit]
                end
              end
            end
            j += 1
          end
          i += 1
        end
      end
      hits
    end

    class << self
      alias overlap penetration
      alias intersect penetration
      alias overlap_all penetration_all
      alias intersect_all penetration_all
    end

    # 真円 vs 真円の押し出し
    def self.penetration_circle_circle(a, b, dx, dy, dist_sq)
      r_sum = a.effective_radius + b.effective_radius
      return nil if dist_sq >= r_sum * r_sum

      dist = Math.sqrt(dist_sq)
      depth = r_sum - dist
      if dist > 0.000001
        nx = -dx / dist
        ny = -dy / dist
      else
        nx = -1.0
        ny = 0.0
      end

      # 接触点 (2つの円の境界・重なりの中間点)
      cx = a.center_x - nx * (a.effective_radius - depth * 0.5)
      cy = a.center_y - ny * (a.effective_radius - depth * 0.5)

      Hit.new(depth, nx, ny, nx * depth, ny * depth, 0.0, cx, cy)
    end

    # AABB vs AABB の押し出し
    def self.penetration_aabb_aabb(a, b, dx, dy)
      ox = (a.half_w + b.half_w) - (dx >= 0.0 ? dx : -dx)
      oy = (a.half_h + b.half_h) - (dy >= 0.0 ? dy : -dy)
      return nil if ox <= 0.0 || oy <= 0.0

      if ox < oy
        depth = ox
        nx = dx >= 0.0 ? -1.0 : 1.0
        ny = 0.0
        cx = a.center_x - nx * (a.half_w - depth * 0.5)
        y_min = (a.center_y - a.half_h) > (b.center_y - b.half_h) ? (a.center_y - a.half_h) : (b.center_y - b.half_h)
        y_max = (a.center_y + a.half_h) < (b.center_y + b.half_h) ? (a.center_y + a.half_h) : (b.center_y + b.half_h)
        cy = (y_min + y_max) * 0.5
      else
        depth = oy
        nx = 0.0
        ny = dy >= 0.0 ? -1.0 : 1.0
        x_min = (a.center_x - a.half_w) > (b.center_x - b.half_w) ? (a.center_x - a.half_w) : (b.center_x - b.half_w)
        x_max = (a.center_x + a.half_w) < (b.center_x + b.half_w) ? (a.center_x + a.half_w) : (b.center_x + b.half_w)
        cx = (x_min + x_max) * 0.5
        cy = a.center_y - ny * (a.half_h - depth * 0.5)
      end
      Hit.new(depth, nx, ny, nx * depth, ny * depth, 0.0, cx, cy)
    end

    # 真円 vs 矩形 (回転・角丸対応 SDF 方式)
    def self.penetration_circle_rect(circle, rect, dx, dy)
      ldx = dx * rect.cos + dy * rect.sin
      ldy = -dx * rect.sin + dy * rect.cos

      sign_x = ldx >= 0.0 ? 1.0 : -1.0
      sign_y = ldy >= 0.0 ? 1.0 : -1.0
      abs_x = ldx >= 0.0 ? ldx : -ldx
      abs_y = ldy >= 0.0 ? ldy : -ldy

      cw = rect.core_half_w
      ch = rect.core_half_h
      total_r = rect.radius + circle.effective_radius

      qx = abs_x - cw
      qy = abs_y - ch

      if qx > 0.0 && qy > 0.0
        d_sq = qx * qx + qy * qy
        return nil if d_sq >= total_r * total_r
        d = Math.sqrt(d_sq)
        depth = total_r - d
        lnx = -sign_x * (qx / d)
        lny = -sign_y * (qy / d)
      elsif qx > 0.0
        return nil if qx >= total_r
        depth = total_r - qx
        lnx = -sign_x
        lny = 0.0
      elsif qy > 0.0
        return nil if qy >= total_r
        depth = total_r - qy
        lnx = 0.0
        lny = -sign_y
      else
        # 内部に埋まっている場合: 最も浅い辺の外側へ
        if qx > qy
          depth = -qx + total_r
          lnx = -sign_x
          lny = 0.0
        else
          depth = -qy + total_r
          lnx = 0.0
          lny = -sign_y
        end
      end

      nx = lnx * rect.cos - lny * rect.sin
      ny = lnx * rect.sin + lny * rect.cos

      # 接触点: 円の中心から法線の逆向き (矩形側) へ (円と矩形の重なり境界)
      cx = circle.center_x - nx * (circle.effective_radius - depth * 0.5)
      cy = circle.center_y - ny * (circle.effective_radius - depth * 0.5)

      Hit.new(depth, nx, ny, nx * depth, ny * depth, 0.0, cx, cy)
    end

    # OBB vs OBB の 4軸 SAT 押し出し
    def self.penetration_obb_obb(a, b, dx, dy)
      cos_rel = b.cos * a.cos + b.sin * a.sin
      sin_rel = b.sin * a.cos - b.cos * a.sin
      c = cos_rel >= 0.0 ? cos_rel : -cos_rel
      s = sin_rel >= 0.0 ? sin_rel : -sin_rel

      min_overlap = 1.0e30
      best_nx = 0.0
      best_ny = 0.0

      # 軸 1: a.X (法線: [a.cos, a.sin])
      p1 = dx * a.cos + dy * a.sin
      r1 = a.half_w + b.half_w * c + b.half_h * s
      p1_abs = p1 >= 0.0 ? p1 : -p1
      o1 = r1 - p1_abs
      return nil if o1 <= 0.0
      if o1 < min_overlap
        min_overlap = o1
        sign = p1 >= 0.0 ? -1.0 : 1.0
        best_nx = a.cos * sign
        best_ny = a.sin * sign
      end

      # 軸 2: a.Y (法線: [-a.sin, a.cos])
      p2 = -dx * a.sin + dy * a.cos
      r2 = a.half_h + b.half_w * s + b.half_h * c
      p2_abs = p2 >= 0.0 ? p2 : -p2
      o2 = r2 - p2_abs
      return nil if o2 <= 0.0
      if o2 < min_overlap
        min_overlap = o2
        sign = p2 >= 0.0 ? -1.0 : 1.0
        best_nx = -a.sin * sign
        best_ny = a.cos * sign
      end

      # 軸 3: b.X (法線: [b.cos, b.sin])
      p3 = dx * b.cos + dy * b.sin
      r3 = b.half_w + a.half_w * c + a.half_h * s
      p3_abs = p3 >= 0.0 ? p3 : -p3
      o3 = r3 - p3_abs
      return nil if o3 <= 0.0
      if o3 < min_overlap
        min_overlap = o3
        sign = p3 >= 0.0 ? -1.0 : 1.0
        best_nx = b.cos * sign
        best_ny = b.sin * sign
      end

      # 軸 4: b.Y (法線: [-b.sin, b.cos])
      p4 = -dx * b.sin + dy * b.cos
      r4 = b.half_h + a.half_w * s + a.half_h * c
      p4_abs = p4 >= 0.0 ? p4 : -p4
      o4 = r4 - p4_abs
      return nil if o4 <= 0.0
      if o4 < min_overlap
        min_overlap = o4
        sign = p4 >= 0.0 ? -1.0 : 1.0
        best_nx = -b.sin * sign
        best_ny = b.cos * sign
      end

      # 接触点 (面 vs 頂点を正確に判定して真の接触点を導出)
      cx, cy = calculate_contact_point(a, b, best_nx, best_ny, min_overlap)

      Hit.new(min_overlap, best_nx, best_ny, best_nx * min_overlap, best_ny * min_overlap, 0.0, cx, cy)
    end

    # 多角形・楕円等を含む汎用 2D SAT 押し出し
    def self.penetration_generic_sat(shape_a, shape_b, dx, dy)
      axes = collect_sat_axes(shape_a, shape_b)
      return nil if axes.empty?

      min_overlap = 1.0e30
      best_nx = 0.0
      best_ny = 0.0

      ab_dx = shape_a.center_x - shape_b.center_x
      ab_dy = shape_a.center_y - shape_b.center_y

      axes.each do |axis|
        ax = axis[0]
        ay = axis[1]

        min_a, max_a = project_shape(ax, ay, shape_a)
        min_b, max_b = project_shape(ax, ay, shape_b)

        overlap = (max_a < max_b ? max_a : max_b) - (min_a > min_b ? min_a : min_b)
        return nil if overlap <= 0.0

        if overlap < min_overlap
          min_overlap = overlap
          ab_dot = ab_dx * ax + ab_dy * ay
          if ab_dot < 0.0
            best_nx = -ax
            best_ny = -ay
          else
            best_nx = ax
            best_ny = ay
          end
        end
      end

      # 接触点 (面 vs 頂点を正確に判定して真の接触点を導出)
      cx, cy = calculate_contact_point(shape_a, shape_b, best_nx, best_ny, min_overlap)

      Hit.new(min_overlap, best_nx, best_ny, best_nx * min_overlap, best_ny * min_overlap, 0.0, cx, cy)
    end

    # 接触点導出 (法線コーン摂動により、どちらが「面 (Reference)」でどちらが「角 (Incident)」かを幾何学的に判定)
    def self.calculate_contact_point(shape_a, shape_b, nx, ny, depth)
      # 微小回転 (約 2.5度: cos=0.999048, sin=0.043619)
      cw_nx = nx * 0.999048 + ny * 0.043619
      cw_ny = -nx * 0.043619 + ny * 0.999048
      ccw_nx = nx * 0.999048 - ny * 0.043619
      ccw_ny = nx * 0.043619 + ny * 0.999048

      # 物体 A (法線 -n 方向) の接触面の幅 (面なら幅が大きく、角なら 0 に近い)
      p_a_cw = shape_a.support(-cw_nx, -cw_ny)
      p_a_cw_x = p_a_cw[0]
      p_a_cw_y = p_a_cw[1]
      p_a_ccw = shape_a.support(-ccw_nx, -ccw_ny)
      dx_a = p_a_cw_x - p_a_ccw[0]
      dy_a = p_a_cw_y - p_a_ccw[1]
      span_a = dx_a * dx_a + dy_a * dy_a

      # 物体 B (法線 +n 方向) の接触面の幅
      p_b_cw = shape_b.support(cw_nx, cw_ny)
      p_b_cw_x = p_b_cw[0]
      p_b_cw_y = p_b_cw[1]
      p_b_ccw = shape_b.support(ccw_nx, ccw_ny)
      dx_b = p_b_cw_x - p_b_ccw[0]
      dy_b = p_b_cw_y - p_b_ccw[1]
      span_b = dx_b * dx_b + dy_b * dy_b

      half_d = depth * 0.5

      if span_b < span_a - 4.0
        # 物体 B の方がより鋭い角 (Incident Vertex: 物体 B の角が物体 A の面に刺さっている)
        pb = shape_b.support(nx, ny)
        [pb[0] - nx * half_d, pb[1] - ny * half_d]
      elsif span_a < span_b - 4.0
        # 物体 A の方がより鋭い角 (Incident Vertex: 物体 A の角が物体 B の面に刺さっている)
        pa = shape_a.support(-nx, -ny)
        [pa[0] + nx * half_d, pa[1] + ny * half_d]
      else
        # ほぼ同等 (面同士または点同士)
        pa = shape_a.support(-nx, -ny)
        pa_x = pa[0]
        pa_y = pa[1]
        pb = shape_b.support(nx, ny)
        [(pa_x + pb[0]) * 0.5, (pa_y + pb[1]) * 0.5]
      end
    end

    def self.project_shape(axis_x, axis_y, shape)
      if shape.shape_type == TYPE_CIRCLE && shape.is_true_circle
        project_circle(axis_x, axis_y, shape)
      elsif shape.respond_to?(:world_vertices) && shape.world_vertices
        project_polygon(axis_x, axis_y, shape.world_vertices)
      else
        # 楕円などの一般的な凸形状 (サポート写像による厳密射影)
        p_max = shape.support(axis_x, axis_y)
        p_max_x = p_max[0]
        p_max_y = p_max[1]
        p_min = shape.support(-axis_x, -axis_y)
        d_max = axis_x * p_max_x + axis_y * p_max_y
        d_min = axis_x * p_min[0] + axis_y * p_min[1]
        d_min > d_max ? [d_max, d_min] : [d_min, d_max]
      end
    end

    def self.collect_sat_axes(shape_a, shape_b)
      axes = []
      verts_a = shape_a.respond_to?(:world_vertices) ? shape_a.world_vertices : nil
      verts_b = shape_b.respond_to?(:world_vertices) ? shape_b.world_vertices : nil

      # エッジ法線
      if verts_a
        len = verts_a.length
        len.times do |i|
          p1 = verts_a[i]
          p2 = verts_a[(i + 1) % len]
          nx = -(p2[1] - p1[1])
          ny = p2[0] - p1[0]
          l = Math.sqrt(nx * nx + ny * ny)
          axes << [nx / l, ny / l] if l > 0.000001
        end
      end

      if verts_b
        len = verts_b.length
        len.times do |i|
          p1 = verts_b[i]
          p2 = verts_b[(i + 1) % len]
          nx = -(p2[1] - p1[1])
          ny = p2[0] - p1[0]
          l = Math.sqrt(nx * nx + ny * ny)
          axes << [nx / l, ny / l] if l > 0.000001
        end
      end

      # 頂点から中心への軸 (円・楕円とポリゴン)
      if shape_a.shape_type == TYPE_CIRCLE && verts_b
        verts_b.each do |v|
          vx = v[0] - shape_a.center_x
          vy = v[1] - shape_a.center_y
          l = Math.sqrt(vx * vx + vy * vy)
          axes << [vx / l, vy / l] if l > 0.000001
        end
      end
      if shape_b.shape_type == TYPE_CIRCLE && verts_a
        verts_a.each do |v|
          vx = v[0] - shape_b.center_x
          vy = v[1] - shape_b.center_y
          l = Math.sqrt(vx * vx + vy * vy)
          axes << [vx / l, vy / l] if l > 0.000001
        end
      end

      # 楕円の主軸 (長軸・短軸)
      [shape_a, shape_b].each do |s|
        if s.shape_type == TYPE_CIRCLE && !s.is_true_circle
          rad = s.angle * (Math::PI / 180.0)
          c = Math.cos(rad)
          sn = Math.sin(rad)
          axes << [c, sn]
          axes << [-sn, c]
        end
      end

      # 中心間軸
      dx = shape_b.center_x - shape_a.center_x
      dy = shape_b.center_y - shape_a.center_y
      dist = Math.sqrt(dx * dx + dy * dy)
      axes << [dx / dist, dy / dist] if dist > 0.000001

      axes
    end

    def self.project_polygon(axis_x, axis_y, verts)
      min = axis_x * verts[0][0] + axis_y * verts[0][1]
      max = min
      i = 1
      len = verts.length
      while i < len
        dot = axis_x * verts[i][0] + axis_y * verts[i][1]
        min = dot if dot < min
        max = dot if dot > max
        i += 1
      end
      [min, max]
    end

    def self.project_circle(axis_x, axis_y, circle)
      center_dot = axis_x * circle.center_x + axis_y * circle.center_y
      r = circle.effective_radius
      [center_dot - r, center_dot + r]
    end

    # ファクトリメソッド
    # 円 / 楕円 (ry を省略した場合は真円)
    def self.circle(x, y, rx, ry = rx, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :center, pivot: :center)
      Circle.new(x, y, rx, ry, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot)
    end

    # 矩形 / 角丸矩形
    def self.rect(x, y, w, h, angle: 0.0, radius: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :top_left, pivot: :center)
      Rect.new(x, y, w, h, angle: angle, radius: radius, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot)
    end

    # 点
    def self.point(x, y, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :top_left, pivot: :center)
      Point.new(x, y, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot)
    end

    # 太さを持つ直線 / 線分 (角丸なしの OBB: 端面は直角)
    def self.line(x1, y1, x2, y2, width = 1.0)
      dx = x2.to_f - x1.to_f
      dy = y2.to_f - y1.to_f
      len = Math.sqrt(dx * dx + dy * dy)
      ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
      cx = (x1.to_f + x2.to_f) * 0.5
      cy = (y1.to_f + y2.to_f) * 0.5
      Rect.new(cx, cy, len, width.to_f, angle: ang, radius: 0.0, anchor: :center, pivot: :center)
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
      Rect.new(cx, cy, len + rad * 2.0, rad * 2.0, angle: ang, radius: rad, anchor: :center, pivot: :center)
    end

    # 多角形
    def self.polygon(vertices, x: 0.0, y: 0.0, angle: 0.0, scale_x: 1.0, scale_y: 1.0, offset_x: 0.0, offset_y: 0.0, anchor: :center, pivot: :center)
      Polygon.new(vertices, x: x, y: y, angle: angle, scale_x: scale_x, scale_y: scale_y, offset_x: offset_x, offset_y: offset_y, anchor: anchor, pivot: pivot)
    end
  end
end

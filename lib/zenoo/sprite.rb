# frozen_string_literal: true

module Zenoo
  class Sprite
    attr_reader :x, :y, :z, :angle, :scale_x, :scale_y, :pivot, :anchor_x, :anchor_y, :alpha, :color, :visible, :image

    def initialize(x = 0.0, y = 0.0, image = nil, anchor: :top_left, pivot: :center)
      @x = x.to_f
      @y = y.to_f
      @z = 0.0
      @image = image
      @angle = 0.0
      @scale_x = 1.0
      @scale_y = 1.0
      @anchor_x = 0.0
      @anchor_y = 0.0
      self.anchor = anchor
      self.pivot = pivot
      @alpha = 255
      @color = nil
      @visible = true

      # コライダー管理
      @collider_type = :default
      @collider_shape = nil
      @col_offset_x = 0.0
      @col_offset_y = 0.0
      @col_param1 = 0.0
      @col_param2 = 0.0
      @col_param3 = 0.0
      @col_vertices = nil
      @dirty_collider = true
    end

    def x=(v)
      vf = v.to_f
      return if @x == vf
      @x = vf
      @dirty_collider = true
    end

    def y=(v)
      vf = v.to_f
      return if @y == vf
      @y = vf
      @dirty_collider = true
    end

    def z=(v)
      @z = v.to_f
    end

    def angle=(v)
      vf = v.to_f
      return if @angle == vf
      @angle = vf
      @dirty_collider = true
    end

    def scale_x=(v)
      vf = v.to_f
      return if @scale_x == vf
      @scale_x = vf
      @dirty_collider = true
    end

    def scale_y=(v)
      vf = v.to_f
      return if @scale_y == vf
      @scale_y = vf
      @dirty_collider = true
    end

    def scale=(v)
      s = v.to_f
      return if @scale_x == s && @scale_y == s
      @scale_x = s
      @scale_y = s
      @dirty_collider = true
    end

    def pivot=(v)
      return if @pivot == v
      @pivot = v
      @dirty_collider = true
    end

    def pivot_x
      Collision.parse_pivot(@pivot)[0]
    end

    def pivot_y
      Collision.parse_pivot(@pivot)[1]
    end

    def pivot_x=(v)
      py = pivot_y
      self.pivot = [v.to_f, py]
    end

    def pivot_y=(v)
      px = pivot_x
      self.pivot = [px, v.to_f]
    end

    def anchor
      if (@anchor_x - 0.0).abs < 0.0001 && (@anchor_y - 0.0).abs < 0.0001
        :top_left
      elsif (@anchor_x - 0.5).abs < 0.0001 && (@anchor_y - 0.5).abs < 0.0001
        :center
      else
        [@anchor_x, @anchor_y]
      end
    end

    def anchor=(v)
      ax, ay = Collision.parse_anchor(v)
      return if @anchor_x == ax && @anchor_y == ay
      @anchor_x = ax
      @anchor_y = ay
      @dirty_collider = true
    end

    def anchor_x=(v)
      vf = v.to_f
      return if @anchor_x == vf
      @anchor_x = vf
      @dirty_collider = true
    end

    def anchor_y=(v)
      vf = v.to_f
      return if @anchor_y == vf
      @anchor_y = vf
      @dirty_collider = true
    end

    def alpha=(v); @alpha = v; end
    def color=(v); @color = v; end
    def visible=(v); @visible = !!v; end

    def image=(v)
      return if @image == v
      @image = v
      @dirty_collider = true
    end

    def width
      @image ? @image.width.to_f : 0.0
    end

    def height
      @image ? @image.height.to_f : 0.0
    end

    # コライダーの設定
    # - :default: 画像サイズ全体の Rect
    # - :rect: 矩形 (width, height, offset_x, offset_y, radius)
    # - :circle: 円/楕円 (radius, radius_x, radius_y, offset_x, offset_y)
    # - :point: 点 (offset_x, offset_y)
    # - :polygon: 多角形 (vertices: [[x1, y1], [x2, y2], ...])
    def set_collider(type = :default,
                     width: nil, height: nil,
                     radius: nil, radius_x: nil, radius_y: nil,
                     offset_x: nil, offset_y: nil,
                     vertices: nil)
      @collider_type = type
      @collider_shape = nil
      @col_offset_x = offset_x.to_f if offset_x
      @col_offset_y = offset_y.to_f if offset_y

      case type
      when :circle
        rx = (radius_x || radius || (width ? width.to_f * 0.5 : [self.width, self.height].min * 0.5)).to_f
        ry = (radius_y || radius || (height ? height.to_f * 0.5 : rx)).to_f
        @col_param1 = rx
        @col_param2 = ry
      when :rect
        w = (width || self.width).to_f
        h = (height || self.height).to_f
        @col_param1 = w
        @col_param2 = h
        @col_param3 = (radius || 0.0).to_f
      when :point
        # offset_x, offset_y のみ使用
      when :polygon
        @col_vertices = vertices
      when :default
        # 画像サイズから自動解決
      end

      @dirty_collider = true
      self
    end

    def collider=(shape)
      @collider_type = :custom
      @collider_shape = shape
      @dirty_collider = true
    end

    def collider_offset_x
      @col_offset_x
    end

    def collider_offset_x=(v)
      vf = v.to_f
      return if @col_offset_x == vf
      @col_offset_x = vf
      @dirty_collider = true
    end

    def collider_offset_y
      @col_offset_y
    end

    def collider_offset_y=(v)
      vf = v.to_f
      return if @col_offset_y == vf
      @col_offset_y = vf
      @dirty_collider = true
    end

    def collider_offset
      [@col_offset_x, @col_offset_y]
    end

    def collider_offset=(val)
      if val.is_a?(Array)
        self.collider_offset_x = val[0]
        self.collider_offset_y = val[1]
      else
        self.collider_offset_x = val
        self.collider_offset_y = val
      end
    end

    # 変形（位置・回転・拡大・ピボット）と同期した Collision::Shape を取得
    def collider
      sync_collider if @dirty_collider || @collider_shape.nil?
      @collider_shape
    end

    # 衝突判定
    def collide?(other)
      col_a = self.collider
      return false unless col_a
      col_b = other.respond_to?(:collider) ? other.collider : other
      return false unless col_b
      Collision.check(col_a, col_b)
    end
    alias collides_with? collide?

    def ===(other)
      collide?(other)
    end

    # 衝突めり込み量・押し出しベクトルを取得 (MTV: 衝突していない場合は nil)
    def penetration(other)
      col_a = self.collider
      return nil unless col_a
      col_b = other.respond_to?(:collider) ? other.collider : other
      return nil unless col_b
      Collision.penetration(col_a, col_b)
    end
    alias overlap_with penetration

    # other から自動的にめり込み解消 (位置を直接更新)
    def push_out_of(other)
      hit = penetration(other)
      if hit
        self.x += hit.overlap_x
        self.y += hit.overlap_y
        hit
      else
        nil
      end
    end

    private

    def sync_collider
      @dirty_collider = false
      w = width
      h = height

      # ピボット比率
      pv = Collision.parse_pivot(@pivot)
      pv_x = pv[0]
      pv_y = pv[1]

      # スプライトのワールド回転中心 (ピボット)
      tl_x = @x - @anchor_x * w
      tl_y = @y - @anchor_y * h
      wpv_x = tl_x + pv_x * w
      wpv_y = tl_y + pv_y * h

      # スプライトの回転中心から見た、コライダー中心のローカル相対オフセット
      rel_cx = (0.5 - pv_x) * w + @col_offset_x
      rel_cy = (0.5 - pv_y) * h + @col_offset_y

      case @collider_type
      when :default
        if @collider_shape.is_a?(Collision::Rect)
          shape = @collider_shape
          shape.x = wpv_x
          shape.y = wpv_y
          shape.width = w
          shape.height = h
          shape.offset_x = rel_cx
          shape.offset_y = rel_cy
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
          shape.anchor = :center
          shape.pivot = :center
        else
          @collider_shape = Collision::Rect.new(
            wpv_x, wpv_y, w, h,
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y,
            offset_x: rel_cx, offset_y: rel_cy, anchor: :center, pivot: :center
          )
        end

      when :rect
        cw = @col_param1 > 0 ? @col_param1 : w
        ch = @col_param2 > 0 ? @col_param2 : h
        cr = @col_param3

        if @collider_shape.is_a?(Collision::Rect)
          shape = @collider_shape
          shape.x = wpv_x
          shape.y = wpv_y
          shape.width = cw
          shape.height = ch
          shape.radius = cr
          shape.offset_x = rel_cx
          shape.offset_y = rel_cy
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
          shape.anchor = :center
          shape.pivot = :center
        else
          @collider_shape = Collision::Rect.new(
            wpv_x, wpv_y, cw, ch,
            angle: @angle, radius: cr, scale_x: @scale_x, scale_y: @scale_y,
            offset_x: rel_cx, offset_y: rel_cy, anchor: :center, pivot: :center
          )
        end

      when :circle
        rx = @col_param1 > 0 ? @col_param1 : w * 0.5
        ry = @col_param2 > 0 ? @col_param2 : rx

        if @collider_shape.is_a?(Collision::Circle)
          shape = @collider_shape
          shape.x = wpv_x
          shape.y = wpv_y
          shape.radius_x = rx
          shape.radius_y = ry
          shape.offset_x = rel_cx
          shape.offset_y = rel_cy
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
          shape.anchor = :center
          shape.pivot = :center
        else
          @collider_shape = Collision::Circle.new(
            wpv_x, wpv_y, rx, ry,
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y,
            offset_x: rel_cx, offset_y: rel_cy, anchor: :center, pivot: :center
          )
        end

      when :point
        if @collider_shape.is_a?(Collision::Point)
          shape = @collider_shape
          shape.x = wpv_x
          shape.y = wpv_y
          shape.offset_x = rel_cx
          shape.offset_y = rel_cy
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
          shape.anchor = :center
          shape.pivot = :center
        else
          @collider_shape = Collision::Point.new(
            wpv_x, wpv_y,
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y,
            offset_x: rel_cx, offset_y: rel_cy, anchor: :center, pivot: :center
          )
        end

      when :polygon
        return unless @col_vertices && @col_vertices.length >= 3
        if @collider_shape.is_a?(Collision::Polygon)
          shape = @collider_shape
          shape.x = wpv_x
          shape.y = wpv_y
          shape.offset_x = rel_cx
          shape.offset_y = rel_cy
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
          shape.anchor = :center
          shape.pivot = :center
        else
          @collider_shape = Collision::Polygon.new(
            @col_vertices,
            x: wpv_x, y: wpv_y,
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y,
            offset_x: rel_cx, offset_y: rel_cy, anchor: :center, pivot: :center
          )
        end

      when :custom
        if @collider_shape.respond_to?(:x=) && @collider_shape.respond_to?(:y=)
          shape = @collider_shape
          shape.x = wpv_x
          shape.y = wpv_y
          shape.offset_x = rel_cx if shape.respond_to?(:offset_x=)
          shape.offset_y = rel_cy if shape.respond_to?(:offset_y=)
          shape.angle = @angle if shape.respond_to?(:angle=)
          shape.scale_x = @scale_x if shape.respond_to?(:scale_x=)
          shape.scale_y = @scale_y if shape.respond_to?(:scale_y=)
          shape.anchor = :center if shape.respond_to?(:anchor=)
          shape.pivot = :center if shape.respond_to?(:pivot=)
        end
      end

      if @collider_shape.respond_to?(:update_cache) && @collider_shape.dirty?
        @collider_shape.update_cache
      end
    end
  end
end

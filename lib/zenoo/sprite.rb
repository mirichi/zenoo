# frozen_string_literal: true

module Zenoo
  class Sprite
    attr_reader :x, :y, :z, :angle, :scale_x, :scale_y, :pivot, :alpha, :color, :visible, :image

    def initialize(x = 0.0, y = 0.0, image = nil)
      @x = x.to_f
      @y = y.to_f
      @z = 0.0
      @image = image
      @angle = 0.0
      @scale_x = 1.0
      @scale_y = 1.0
      @pivot = :center
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
                     offset_x: 0.0, offset_y: 0.0,
                     vertices: nil)
      @collider_type = type
      @collider_shape = nil
      @col_offset_x = offset_x.to_f
      @col_offset_y = offset_y.to_f

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

    def ===(other)
      collide?(other)
    end

    private

    # ローカル座標 (画像左上原点) をスプライトの変形に基づいてワールド座標へ変換
    def transform_local_point(lx, ly)
      w = width
      h = height

      is_no_rot = (@angle % 360.0).abs < 0.0001
      is_unit_scale = (@scale_x - 1.0).abs < 0.0001 && (@scale_y - 1.0).abs < 0.0001

      # 非回転・等倍かつ中央ピボットの場合の最速パス (O(1) 加算のみ)
      if is_no_rot && is_unit_scale && (@pivot == :center || @pivot.nil?)
        return [@x + lx, @y + ly]
      end

      if @pivot == :center || @pivot.nil?
        pv_x = 0.5
        pv_y = 0.5
      elsif @pivot == :top_left
        pv_x = 0.0
        pv_y = 0.0
      elsif @pivot.is_a?(Array) && @pivot.length >= 2
        pv_x = @pivot[0].to_f
        pv_y = @pivot[1].to_f
      else
        pv_x = 0.5
        pv_y = 0.5
      end

      wpv_x = @x + pv_x * w
      wpv_y = @y + pv_y * h

      rel_x = lx - pv_x * w
      rel_y = ly - pv_y * h

      slx = rel_x * @scale_x
      sly = rel_y * @scale_y

      if is_no_rot
        rot_x = slx
        rot_y = sly
      else
        rad = @angle * (Math::PI / 180.0)
        c = Math.cos(rad)
        s = Math.sin(rad)
        rot_x = slx * c - sly * s
        rot_y = slx * s + sly * c
      end

      [wpv_x + rot_x, wpv_y + rot_y]
    end

    def sync_collider
      @dirty_collider = false
      w = width
      h = height

      case @collider_type
      when :default
        wc = transform_local_point(w * 0.5, h * 0.5)
        if @collider_shape.is_a?(Collision::Rect)
          shape = @collider_shape
          shape.x = wc[0]
          shape.y = wc[1]
          shape.width = w
          shape.height = h
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
        else
          @collider_shape = Collision::Rect.new(
            wc[0], wc[1], w, h,
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y, pivot: :center
          )
        end

      when :rect
        lcx = (w * 0.5) + @col_offset_x
        lcy = (h * 0.5) + @col_offset_y
        wc = transform_local_point(lcx, lcy)
        cw = @col_param1 > 0 ? @col_param1 : w
        ch = @col_param2 > 0 ? @col_param2 : h
        cr = @col_param3

        if @collider_shape.is_a?(Collision::Rect)
          shape = @collider_shape
          shape.x = wc[0]
          shape.y = wc[1]
          shape.width = cw
          shape.height = ch
          shape.radius = cr
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
        else
          @collider_shape = Collision::Rect.new(
            wc[0], wc[1], cw, ch,
            angle: @angle, radius: cr, scale_x: @scale_x, scale_y: @scale_y, pivot: :center
          )
        end

      when :circle
        lcx = (w * 0.5) + @col_offset_x
        lcy = (h * 0.5) + @col_offset_y
        wc = transform_local_point(lcx, lcy)
        rx = @col_param1 > 0 ? @col_param1 : w * 0.5
        ry = @col_param2 > 0 ? @col_param2 : rx

        if @collider_shape.is_a?(Collision::Circle)
          shape = @collider_shape
          shape.x = wc[0]
          shape.y = wc[1]
          shape.radius_x = rx
          shape.radius_y = ry
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
        else
          @collider_shape = Collision::Circle.new(
            wc[0], wc[1], rx, ry,
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y, pivot: :center
          )
        end

      when :point
        lcx = (w * 0.5) + @col_offset_x
        lcy = (h * 0.5) + @col_offset_y
        wc = transform_local_point(lcx, lcy)
        if @collider_shape.is_a?(Collision::Point)
          shape = @collider_shape
          shape.x = wc[0]
          shape.y = wc[1]
        else
          @collider_shape = Collision::Point.new(wc[0], wc[1])
        end

      when :polygon
        return unless @col_vertices && @col_vertices.length >= 3
        sum_x = 0.0
        sum_y = 0.0
        @col_vertices.each { |v| sum_x += v[0].to_f; sum_y += v[1].to_f }
        lcx = sum_x / @col_vertices.length
        lcy = sum_y / @col_vertices.length
        wc = transform_local_point(lcx, lcy)
        rel_verts = @col_vertices.map { |v| [v[0].to_f - lcx, v[1].to_f - lcy] }

        if @collider_shape.is_a?(Collision::Polygon)
          shape = @collider_shape
          shape.x = wc[0]
          shape.y = wc[1]
          shape.angle = @angle
          shape.scale_x = @scale_x
          shape.scale_y = @scale_y
        else
          @collider_shape = Collision::Polygon.new(
            rel_verts,
            x: wc[0], y: wc[1],
            angle: @angle, scale_x: @scale_x, scale_y: @scale_y, pivot: :center
          )
        end

      when :custom
        if @collider_shape.respond_to?(:x=) && @collider_shape.respond_to?(:y=)
          wc = transform_local_point(w * 0.5 + @col_offset_x, h * 0.5 + @col_offset_y)
          shape = @collider_shape
          shape.x = wc[0]
          shape.y = wc[1]
          shape.angle = @angle if shape.respond_to?(:angle=)
          shape.scale_x = @scale_x if shape.respond_to?(:scale_x=)
          shape.scale_y = @scale_y if shape.respond_to?(:scale_y=)
        end
      end

      if @collider_shape.respond_to?(:update_cache) && @collider_shape.dirty?
        @collider_shape.update_cache
      end
    end
  end
end

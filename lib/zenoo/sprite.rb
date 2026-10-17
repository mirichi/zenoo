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
      @collider_shape = nil
    end

    def x=(v)
      vf = v.to_f
      return if @x == vf
      @x = vf
      @collider_shape&.dirty_pos!
    end

    def y=(v)
      vf = v.to_f
      return if @y == vf
      @y = vf
      @collider_shape&.dirty_pos!
    end

    def z=(v)
      @z = v.to_f
    end

    def angle=(v)
      vf = v.to_f
      return if @angle == vf
      @angle = vf
      @collider_shape&.dirty_geom!
    end

    def scale_x=(v)
      vf = v.to_f
      return if @scale_x == vf
      @scale_x = vf
      @collider_shape&.dirty_geom!
    end

    def scale_y=(v)
      vf = v.to_f
      return if @scale_y == vf
      @scale_y = vf
      @collider_shape&.dirty_geom!
    end

    def scale=(v)
      s = v.to_f
      return if @scale_x == s && @scale_y == s
      @scale_x = s
      @scale_y = s
      @collider_shape&.dirty_geom!
    end

    def pivot=(v)
      return if @pivot == v
      @pivot = v
      @collider_shape&.dirty_pos!
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
      @collider_shape&.dirty_pos!
    end

    def anchor_x=(v)
      vf = v.to_f
      return if @anchor_x == vf
      @anchor_x = vf
      @collider_shape&.dirty_pos!
    end

    def anchor_y=(v)
      vf = v.to_f
      return if @anchor_y == vf
      @anchor_y = vf
      @collider_shape&.dirty_pos!
    end

    def alpha=(v); @alpha = v; end
    def color=(v); @color = v; end
    def visible=(v); @visible = !!v; end

    def image=(v)
      return if @image == v
      @image = v
      if @collider_shape.is_a?(Collision::Rect) && @collider_shape.parent
        @collider_shape.dirty_size!
      else
        @collider_shape&.dirty_pos!
      end
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
      ox = offset_x ? offset_x.to_f : 0.0
      oy = offset_y ? offset_y.to_f : 0.0

      case type
      when :circle
        rx = (radius_x || radius || (width ? width.to_f * 0.5 : [self.width, self.height].min * 0.5)).to_f
        ry = (radius_y || radius || (height ? height.to_f * 0.5 : rx)).to_f
        @collider_shape = Collision::Circle.new(0.0, 0.0, rx, ry, offset_x: ox, offset_y: oy, parent: self)
      when :rect
        w = (width || self.width).to_f
        h = (height || self.height).to_f
        r = (radius || 0.0).to_f
        @collider_shape = Collision::Rect.new(0.0, 0.0, w, h, radius: r, offset_x: ox, offset_y: oy, parent: self)
      when :point
        @collider_shape = Collision::Point.new(offset_x: ox, offset_y: oy, parent: self)
      when :polygon
        @collider_shape = Collision::Polygon.new(vertices || [], offset_x: ox, offset_y: oy, parent: self)
      when :default
        @collider_shape = Collision::Rect.new(offset_x: ox, offset_y: oy, parent: self)
      end
      self
    end

    def collider=(shape)
      @collider_shape = shape
      if shape.respond_to?(:parent=)
        shape.parent = self
        shape.dirty_pos! if shape.respond_to?(:dirty_pos!)
      end
    end

    def collider_offset_x
      collider.offset_x
    end

    def collider_offset_x=(v)
      collider.offset_x = v.to_f
    end

    def collider_offset_y
      collider.offset_y
    end

    def collider_offset_y=(v)
      collider.offset_y = v.to_f
    end

    def collider_offset
      [collider_offset_x, collider_offset_y]
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
      unless @collider_shape
        @collider_shape = Collision::Rect.new(parent: self)
      end
      @collider_shape.update_cache if @collider_shape.dirty?
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
    # other が配列の場合は各オブジェクトに対して順次押し出しを行う
    def push_out_of(other)
      if other.is_a?(Array)
        resolved_hits = []
        other.each do |item|
          hit = push_out_of(item)
          resolved_hits << hit if hit
        end
        resolved_hits.empty? ? nil : resolved_hits
      else
        hit = penetration(other)
        if hit
          self.x += hit.overlap_x
          self.y += hit.overlap_y
          hit
        else
          nil
        end
      end
    end

    # 描画
    def draw(camera: true, z: nil)
      Window.draw_sprite(self, camera: camera, z: z)
    end

    # 単一または配列スプライトの一括描画 (DXRuby互換)
    def self.draw(sprites, camera: true, z: nil)
      Window.draw_sprite(sprites, camera: camera, z: z)
    end

    # スプライト同士・配列同士の一括衝突判定 (DXRuby互換)
    def self.check(group_a, group_b = nil, &block)
      Collision.check_all(group_a, group_b, &block)
    end

    # スプライト同士・配列同士の一括めり込み量 (MTV) 判定
    def self.penetration(group_a, group_b = nil, &block)
      Collision.penetration_all(group_a, group_b, &block)
    end

    # 空間ハッシュによる近傍ペア列挙 (ブロードフェーズ / 大量オブジェクト総当たり用)
    def self.each_pair_spatial(sprites, cell_size: 64.0, bounds: nil, &block)
      Collision.each_pair_spatial(sprites, cell_size: cell_size, bounds: bounds, &block)
    end

    # 空間ハッシュによる一括衝突判定
    def self.check_spatial(sprites, cell_size: 64.0, bounds: nil, &block)
      Collision.check_spatial(sprites, cell_size: cell_size, bounds: bounds, &block)
    end

    # 空間ハッシュによる一括めり込み量 (MTV) 判定
    def self.penetration_spatial(sprites, cell_size: 64.0, bounds: nil, &block)
      Collision.penetration_spatial(sprites, cell_size: cell_size, bounds: bounds, &block)
    end
  end
end

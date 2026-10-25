# frozen_string_literal: true

module Zenoo
  class Sprite
    attr_reader :x, :y, :z, :angle, :scale_x, :scale_y, :anchor, :pivot, :anchor_x, :anchor_y, :alpha, :color, :visible, :image, :parent
    attr_accessor :blend, :shader, :uniforms, :camera

    def initialize(x = 0.0, y = 0.0, image = nil, anchor: :top_left, pivot: :center, blend: :alpha, shader: nil, uniforms: nil, camera: true, parent: nil)
      @x = x.to_f
      @y = y.to_f
      @z = 0.0
      @image = image
      @angle = 0.0
      @scale_x = 1.0
      @scale_y = 1.0
      @anchor_x = 0.0
      @anchor_y = 0.0
      @pivot_x = 0.5
      @pivot_y = 0.5
      self.anchor = anchor
      self.pivot = pivot
      @alpha = 255
      @color = nil
      @blend = blend || :alpha
      @shader = shader
      @uniforms = uniforms
      @camera = camera.nil? ? true : camera
      @visible = true
      @vanished = false

      # 親子階層・ワールド変換キャッシュ (単体利用時は遅延評価によりオーバーヘッドゼロ)
      @parent = nil
      @children = nil
      @world_dirty = true
      @world_x = @x
      @world_y = @y
      @world_pivot_x = 0.0
      @world_pivot_y = 0.0
      @world_angle = 0.0
      @world_scale_x = 1.0
      @world_scale_y = 1.0
      @world_cos = 1.0
      @world_sin = 0.0

      # コライダー管理
      @collider_shape = nil

      self.parent = parent if parent
    end

    # ライフサイクル管理 (消滅)
    def vanish
      @vanished = true
    end

    def vanished?
      @vanished
    end

    # フレーム更新 (継承先でオーバーライド)
    def update
    end

    def x=(v)
      vf = v.to_f
      return if @x == vf
      @x = vf
      @world_dirty = true
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def y=(v)
      vf = v.to_f
      return if @y == vf
      @y = vf
      @world_dirty = true
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def z=(v)
      @z = v.to_f
    end

    def angle=(v)
      vf = v.to_f
      return if @angle == vf
      @angle = vf
      @world_dirty = true
      @collider_shape&.dirty_angle!
      dirty_children_geom! if @children
    end

    def scale_x=(v)
      vf = v.to_f
      return if @scale_x == vf
      @scale_x = vf
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def scale_y=(v)
      vf = v.to_f
      return if @scale_y == vf
      @scale_y = vf
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def scale=(v)
      s = v.to_f
      return if @scale_x == s && @scale_y == s
      @scale_x = s
      @scale_y = s
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def pivot=(v)
      return if @pivot == v
      @pivot = v
      pv = Collision.parse_pivot(v)
      @pivot_x = pv[0]
      @pivot_y = pv[1]
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_pos! if @children
    end

    def pivot_x
      @pivot_x || 0.5
    end

    def pivot_y
      @pivot_y || 0.5
    end

    def pivot_x=(v)
      vf = v.to_f
      return if @pivot_x == vf
      @pivot_x = vf
      @pivot = [@pivot_x, pivot_y]
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_pos! if @children
    end

    def pivot_y=(v)
      vf = v.to_f
      return if @pivot_y == vf
      @pivot_y = vf
      @pivot = [pivot_x, @pivot_y]
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_pos! if @children
    end

    def anchor
      @anchor || if (@anchor_x - 0.0).abs < 0.0001 && (@anchor_y - 0.0).abs < 0.0001
        :top_left
      elsif (@anchor_x - 0.5).abs < 0.0001 && (@anchor_y - 0.5).abs < 0.0001
        :center
      else
        [@anchor_x, @anchor_y]
      end
    end

    def anchor=(v)
      return if @anchor == v
      @anchor = v
      ax, ay = Collision.parse_anchor(v)
      @anchor_x = ax
      @anchor_y = ay
      @world_dirty = true
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def anchor_x=(v)
      vf = v.to_f
      return if @anchor_x == vf
      @anchor_x = vf
      @anchor = [@anchor_x, anchor_y]
      @world_dirty = true
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def anchor_y=(v)
      vf = v.to_f
      return if @anchor_y == vf
      @anchor_y = vf
      @anchor = [anchor_x, @anchor_y]
      @world_dirty = true
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def alpha=(v); @alpha = v; end
    def color=(v); @color = v; end
    def visible=(v); @visible = !!v; end

    def image=(v)
      return if @image.equal?(v)
      old_img = @image
      @image = v

      # 画像サイズが変わっていないならコライダーは影響を受けない (アニメーションやフラッシュ切り替え時の再計算を排除)
      old_w = old_img ? old_img.width : 0
      old_h = old_img ? old_img.height : 0
      new_w = v ? v.width : 0
      new_h = v ? v.height : 0
      return if old_w == new_w && old_h == new_h

      @world_dirty = true
      if @collider_shape.is_a?(Collision::Rect) && @collider_shape.parent
        @collider_shape.dirty_size!
      else
        @collider_shape&.dirty_pos!
      end
      dirty_children_pos! if @children
    end

    # ====================================================
    # 親子階層・ワールド変換 (単体時はファストパスでゼロオーバーヘッド)
    # ====================================================
    def parent=(new_parent)
      return if @parent.equal?(new_parent)
      return if new_parent.equal?(self)

      # 循環参照の防止
      if new_parent
        cur = new_parent.parent
        while cur
          return if cur.equal?(self)
          cur = cur.parent
        end
      end

      @parent&.__remove_child_internal(self)
      @parent = new_parent
      new_parent&.__add_child_internal(self)
      dirty_world_geom!
    end

    def children
      @children ||= []
    end

    def add_child(child)
      child.parent = self if child
      self
    end

    def remove_child(child)
      child.parent = nil if child && child.parent.equal?(self)
      self
    end

    def __add_child_internal(child)
      ch = (@children ||= [])
      ch << child unless ch.include?(child)
    end

    def __remove_child_internal(child)
      return unless (ch = @children)
      ch.delete(child)
      @children = nil if ch.empty?
    end

    def world_dirty?
      @world_dirty
    end

    def dirty_world_pos!
      @world_dirty = true
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def dirty_world_geom!
      @world_dirty = true
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def dirty_children_pos!
      return unless (ch = @children)
      i = 0
      len = ch.length
      while i < len
        ch[i].dirty_world_pos!
        i += 1
      end
    end

    def dirty_children_geom!
      return unless (ch = @children)
      i = 0
      len = ch.length
      while i < len
        ch[i].dirty_world_geom!
        i += 1
      end
    end

    def update_world_transform
      @world_dirty = false
      w = width
      h = height
      if (p = @parent)
        p.update_world_transform if p.world_dirty?
        p_wpv_x = p.world_pivot_x
        p_wpv_y = p.world_pivot_y
        p_sx = p.world_scale_x
        p_sy = p.world_scale_y
        p_cos = p.world_cos
        p_sin = p.world_sin

        pw = p.width
        ph = p.height
        lx = (p.anchor_x - p.pivot_x) * pw + @x
        ly = (p.anchor_y - p.pivot_y) * ph + @y

        slx = lx * p_sx
        sly = ly * p_sy
        @world_x = p_wpv_x + slx * p_cos - sly * p_sin
        @world_y = p_wpv_y + slx * p_sin + sly * p_cos

        pv_off_x = (@pivot_x - @anchor_x) * w
        pv_off_y = (@pivot_y - @anchor_y) * h
        if pv_off_x.abs < 0.0001 && pv_off_y.abs < 0.0001
          @world_pivot_x = @world_x
          @world_pivot_y = @world_y
        else
          spv_x = (lx + pv_off_x) * p_sx
          spv_y = (ly + pv_off_y) * p_sy
          @world_pivot_x = p_wpv_x + spv_x * p_cos - spv_y * p_sin
          @world_pivot_y = p_wpv_y + spv_x * p_sin + spv_y * p_cos
        end

        @world_scale_x = p_sx * @scale_x
        @world_scale_y = p_sy * @scale_y
        @world_angle = p.world_angle + @angle
      else
        @world_x = @x
        @world_y = @y
        @world_pivot_x = @x + (@pivot_x - @anchor_x) * w
        @world_pivot_y = @y + (@pivot_y - @anchor_y) * h
        @world_scale_x = @scale_x
        @world_scale_y = @scale_y
        @world_angle = @angle
      end

      if @world_angle == 0.0
        @world_cos = 1.0
        @world_sin = 0.0
      else
        rad = @world_angle * (Math::PI / 180.0)
        @world_cos = Math.cos(rad)
        @world_sin = Math.sin(rad)
      end
    end

    def world_x
      if @parent
        update_world_transform if @world_dirty
        @world_x
      else
        @x
      end
    end

    def world_y
      if @parent
        update_world_transform if @world_dirty
        @world_y
      else
        @y
      end
    end

    def world_pivot_x
      if @parent
        update_world_transform if @world_dirty
        @world_pivot_x
      else
        @x + (@pivot_x - @anchor_x) * width
      end
    end

    def world_pivot_y
      if @parent
        update_world_transform if @world_dirty
        @world_pivot_y
      else
        @y + (@pivot_y - @anchor_y) * height
      end
    end

    def world_angle
      if @parent
        update_world_transform if @world_dirty
        @world_angle
      else
        @angle
      end
    end

    def world_scale_x
      if @parent
        update_world_transform if @world_dirty
        @world_scale_x
      else
        @scale_x
      end
    end

    def world_scale_y
      if @parent
        update_world_transform if @world_dirty
        @world_scale_y
      else
        @scale_y
      end
    end

    def world_cos
      update_world_transform if @world_dirty
      @world_cos
    end

    def world_sin
      update_world_transform if @world_dirty
      @world_sin
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
      col = collider
      col.offset_x = v.to_f if col
      nil
    end

    def collider_offset_y
      collider.offset_y
    end

    def collider_offset_y=(v)
      col = collider
      col.offset_y = v.to_f if col
      nil
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
      return false if @vanished || other.vanished?
      col_a = self.collider
      return false unless col_a
      col_b = other.is_a?(Collision::Shape) ? other : (other.respond_to?(:collider) ? other.collider : nil)
      return false unless col_b
      Collision.check(col_a, col_b)
    end

    def ===(other)
      collide?(other)
    end

    # 衝突めり込み量・押し出しベクトルを取得 (MTV: 衝突していない場合は nil)
    def penetration(other)
      return nil if @vanished || other.vanished?
      col_a = self.collider
      return nil unless col_a
      col_b = other.is_a?(Collision::Shape) ? other : (other.respond_to?(:collider) ? other.collider : nil)
      return nil unless col_b
      Collision.penetration(col_a, col_b)
    end

    # 階層ツリーの最上位ルートスプライトを取得 (親がいない場合は self)
    def root
      cur = self
      while (p = cur.parent)
        cur = p
      end
      cur
    end

    # other から自動的にめり込み解消 (位置を直接更新)
    # other が配列の場合は各オブジェクトに対して順次押し出しを行う
    # target_root: true の場合、子パーツが衝突しても関節が外れないようルート親（キャラクター全体）を押し出します
    def push_out_of(other, target_root: true)
      return nil if @vanished
      if other.is_a?(Array)
        resolved_hits = []
        other.each do |item|
          hit = push_out_of(item, target_root: target_root)
          resolved_hits << hit if hit
        end
        resolved_hits.empty? ? nil : resolved_hits
      else
        hit = penetration(other)
        if hit
          if target_root && @parent
            r = root
            r.x += hit.overlap_x
            r.y += hit.overlap_y
          elsif (p = @parent)
            ox = hit.overlap_x
            oy = hit.overlap_y
            p_cos = p.world_cos
            p_sin = p.world_sin
            p_sx = p.world_scale_x
            p_sy = p.world_scale_y
            rx = ox * p_cos + oy * p_sin
            ry = -ox * p_sin + oy * p_cos
            self.x += (p_sx.abs > 0.0001 ? rx / p_sx : rx)
            self.y += (p_sy.abs > 0.0001 ? ry / p_sy : ry)
          else
            self.x += hit.overlap_x
            self.y += hit.overlap_y
          end
          hit
        else
          nil
        end
      end
    end

    # 描画
    def draw
      return if @vanished
      Window.draw_sprite(self)
    end

    # 単一または配列スプライトの一括描画 (DXRuby互換)
    def self.draw(sprites)
      return unless sprites
      if sprites.is_a?(Array)
        i = 0
        len = sprites.length
        while i < len
          sp = sprites[i]
          if sp
            is_vanished = sp.respond_to?(:vanished?) && sp.vanished?
            sp.draw unless is_vanished
          end
          i += 1
        end
      else
        is_vanished = sprites.respond_to?(:vanished?) && sprites.vanished?
        sprites.draw unless is_vanished
      end
    end

    # 単一または配列スプライトの一括フレーム更新 (DXRuby互換)
    def self.update(sprites)
      return unless sprites
      if sprites.is_a?(Array)
        i = 0
        len = sprites.length
        while i < len
          sp = sprites[i]
          if sp
            is_vanished = sp.respond_to?(:vanished?) && sp.vanished?
            sp.update unless is_vanished
          end
          i += 1
        end
      else
        is_vanished = sprites.respond_to?(:vanished?) && sprites.vanished?
        sprites.update unless is_vanished
      end
    end

    # 配列から消滅済み (vanished?) スプライトを一括除去 (インプレース・ゼロアロケーション)
    def self.clean(sprites)
      return sprites unless sprites.is_a?(Array)

      write_idx = 0
      i = 0
      len = sprites.length
      while i < len
        sp = sprites[i]
        if sp
          is_vanished = sp.respond_to?(:vanished?) && sp.vanished?
          unless is_vanished
            sprites[write_idx] = sp if write_idx != i
            write_idx += 1
          end
        end
        i += 1
      end

      # 末尾を切り詰める
      while sprites.length > write_idx
        sprites.pop
      end

      sprites
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

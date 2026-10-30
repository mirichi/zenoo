# frozen_string_literal: true

module Zenoo
  class Sprite
    # ワールド変換キャッシュ構造体 (親子関係がある場合のみ遅延生成)
    WorldTransform = Struct.new(
      :dirty,
      :x, :y,
      :pivot_x, :pivot_y,
      :angle,
      :scale_x, :scale_y,
      :cos, :sin
    )

    # アニメーション管理コンポーネント (アニメーション使用時のみ遅延生成)
    class Animator
      attr_reader :current_name, :frame_index, :finished, :tick

      def initialize
        @animations = {}
        @current_name = nil
        @current_data = nil
        @frame_index = 0
        @tick = 0
        @finished = false
      end

      def add(name, images, wait: 4, loop: true, offset: nil, offset_x: nil, offset_y: nil)
        imgs = images.is_a?(Array) ? images : [images]
        ox = (offset_x || (offset ? offset[0] : 0.0) || 0.0).to_f
        oy = (offset_y || (offset ? offset[1] : 0.0) || 0.0).to_f
        @animations[name.to_sym] = {
          images: imgs,
          wait: wait,
          loop: loop,
          offset_x: ox,
          offset_y: oy
        }
      end

      def offset_x
        @current_data ? @current_data[:offset_x] : 0.0
      end

      def offset_y
        @current_data ? @current_data[:offset_y] : 0.0
      end

      def play(sprite, name, reset: false, keep_frame: false)
        sym = name&.to_sym
        return unless @animations.key?(sym)

        if !reset && @current_name == sym && !@finished
          return
        end

        data = @animations[sym]
        @current_name = sym
        @current_data = data
        @finished = false

        images = data[:images]
        new_len = images ? images.length : 0

        if keep_frame && new_len > 0
          @frame_index = @frame_index % new_len
        else
          @frame_index = 0
          @tick = 0
        end

        if new_len > 0
          sprite.image = images[@frame_index]
        end
      end

      def stop
        @current_name = nil
        @current_data = nil
        @frame_index = 0
        @tick = 0
        @finished = false
      end

      def update(sprite)
        return unless @current_data

        images = @current_data[:images]
        return if !images || images.empty?
        return if @finished

        len = images.length
        wait_spec = @current_data[:wait]
        cur_wait = if wait_spec.is_a?(Array)
          wait_spec[@frame_index] || wait_spec[-1] || 1
        else
          wait_spec || 4
        end
        cur_wait = 1 if cur_wait < 1

        @tick += 1
        if @tick >= cur_wait
          @tick = 0
          next_idx = @frame_index + 1

          if next_idx >= len
            if @current_data[:loop]
              @frame_index = 0
              sprite.image = images[0]
            else
              @frame_index = len - 1
              @finished = true
              sprite.image = images[@frame_index]
            end
          else
            @frame_index = next_idx
            sprite.image = images[next_idx]
          end
        end
      end
    end

    attr_reader :x, :y, :z, :angle, :scale_x, :scale_y, :anchor, :pivot, :anchor_x, :anchor_y, :alpha, :color, :visible, :image, :parent
    attr_accessor :blend, :shader, :uniforms, :camera

    def initialize(x = 0.0, y = 0.0, image = nil, width: nil, height: nil, anchor: :top_left, pivot: :center, blend: :alpha, shader: nil, uniforms: nil, camera: true, parent: nil)
      @x = x.to_f
      @y = y.to_f
      @z = 0.0
      @image = image
      @width = width ? width.to_f : nil
      @height = height ? height.to_f : nil
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

      # 親子階層 & ワールド変換キャッシュ (遅延化: 親子関係がある場合のみ生成)
      @parent = nil
      @children = nil
      @world_transform = nil

      # コライダー管理 (遅延化)
      @collider_shape = nil

      # アニメーション管理 (遅延化: アニメーション使用時のみ生成)
      @animator = nil

      self.parent = parent if parent
    end

    # ライフサイクル管理 (消滅)
    def vanish
      @vanished = true
    end

    def vanished?
      @vanished
    end

    # フレーム更新 (継承先でオーバーライド。super でアニメーションが自動更新されます)
    def update
      update_animation
    end

    # ====================================================
    # アニメーション制御 (Animator コンポーネントへ委譲)
    # ====================================================

    # アニメーションを登録
    # @param name [Symbol, String] アニメーション名
    # @param images [Array<Image>, Image] 画像配列
    # @param wait [Integer, Array<Integer>] 1コマあたりの表示フレーム数 (配列でコマごと可変指定可能)
    # @param loop [Boolean] ループ再生するかどうか (デフォルト: true)
    # @param offset [Array<Numeric>] 描画位置オフセット [x, y] (画像サイズが異なる攻撃モーション等の位置合わせ用)
    # @param offset_x [Numeric] 描画位置オフセット X
    # @param offset_y [Numeric] 描画位置オフセット Y
    def add_animation(name, images, wait: 4, loop: true, offset: nil, offset_x: nil, offset_y: nil)
      animator.add(name, images, wait: wait, loop: loop, offset: offset, offset_x: offset_x, offset_y: offset_y)
      self
    end

    # 現在のアニメーションの描画オフセット X
    def animation_offset_x
      @animator ? @animator.offset_x : 0.0
    end

    # 現在のアニメーションの描画オフセット Y
    def animation_offset_y
      @animator ? @animator.offset_y : 0.0
    end

    # アニメーションを再生
    # 同一アニメーション再生中の場合は巻き戻さず継続します。
    # 異なるアニメーションに切り替わった場合、または reset: true の場合は先頭から再生します。
    # @param name [Symbol, String] 再生するアニメーション名
    # @param reset [Boolean] 同名アニメーションであっても強制的に先頭から巻き戻すか (デフォルト: false)
    # @param keep_frame [Boolean] 切り替え時に現在のコマ番号と経過フレーム数を引き継ぐか (4方向歩行の向き変更等用、デフォルト: false)
    def play(name, reset: false, keep_frame: false)
      animator.play(self, name, reset: reset, keep_frame: keep_frame)
      self
    end

    # アニメーションを停止し、アニメーション状態を解除
    def stop_animation
      @animator&.stop
      self
    end

    # 現在再生中のアニメーション名 (再生されていない場合は nil)
    def animation
      @animator&.current_name
    end

    # アニメーションが再生中かどうか判定 (name を指定した場合はそのアニメーションか判定)
    def playing?(name = nil)
      return false unless @animator
      if name
        @animator.current_name == name.to_sym
      else
        !@animator.current_name.nil?
      end
    end

    # loop: false のアニメーションが最後のコマまで再生完了したかどうか
    def animation_finished?
      @animator ? @animator.finished : false
    end

    # 現在のコマ番号 (0 オリジン)
    def animation_frame_index
      @animator ? @animator.frame_index : 0
    end
    alias current_frame_index animation_frame_index

    # 1フレーム分のアニメーション更新処理
    # (update 内から自動で呼ばれますが、手動呼び出しも可能)
    def update_animation
      @animator&.update(self)
    end

    private

    def animator
      @animator ||= Animator.new
    end

    public

    def x=(v)
      vf = v.to_f
      return if @x == vf
      @x = vf
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def y=(v)
      vf = v.to_f
      return if @y == vf
      @y = vf
      @world_transform.dirty = true if @world_transform
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
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_angle!
      dirty_children_geom! if @children
    end

    def scale_x=(v)
      vf = v.to_f
      return if @scale_x == vf
      @scale_x = vf
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def scale_y=(v)
      vf = v.to_f
      return if @scale_y == vf
      @scale_y = vf
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def scale=(v)
      s = v.to_f
      return if @scale_x == s && @scale_y == s
      @scale_x = s
      @scale_y = s
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_geom!
      dirty_children_geom! if @children
    end

    def pivot=(v)
      return if @pivot == v
      @pivot = v
      pv = Collision.parse_pivot(v)
      @pivot_x = pv[0]
      @pivot_y = pv[1]
      @world_transform.dirty = true if @world_transform
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
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_geom!
      dirty_children_pos! if @children
    end

    def pivot_y=(v)
      vf = v.to_f
      return if @pivot_y == vf
      @pivot_y = vf
      @pivot = [pivot_x, @pivot_y]
      @world_transform.dirty = true if @world_transform
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
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def anchor_x=(v)
      vf = v.to_f
      return if @anchor_x == vf
      @anchor_x = vf
      @anchor = [@anchor_x, anchor_y]
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def anchor_y=(v)
      vf = v.to_f
      return if @anchor_y == vf
      @anchor_y = vf
      @anchor = [anchor_x, @anchor_y]
      @world_transform.dirty = true if @world_transform
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

      # 明示的に width / height が両方設定されている場合、または画像サイズが変わっていないならコライダーや子座標は影響を受けない
      return if @width && @height
      old_w = @width || (old_img ? old_img.width : 0)
      old_h = @height || (old_img ? old_img.height : 0)
      new_w = @width || (v ? v.width : 0)
      new_h = @height || (v ? v.height : 0)
      return if old_w == new_w && old_h == new_h

      @world_transform.dirty = true if @world_transform
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
      @world_transform ? @world_transform.dirty : true
    end

    def dirty_world_pos!
      @world_transform.dirty = true if @world_transform
      @collider_shape&.dirty_pos!
      dirty_children_pos! if @children
    end

    def dirty_world_geom!
      @world_transform.dirty = true if @world_transform
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

    def world_transform
      @world_transform ||= WorldTransform.new(true, @x, @y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0)
    end

    def update_world_transform
      wt = world_transform
      wt.dirty = false
      w = width
      h = height
      if (p = @parent)
        p.update_world_transform if p.world_dirty?
        p_wt = p.world_transform
        p_wpv_x = p_wt.pivot_x
        p_wpv_y = p_wt.pivot_y
        p_sx = p_wt.scale_x
        p_sy = p_wt.scale_y
        p_cos = p_wt.cos
        p_sin = p_wt.sin

        pw = p.width
        ph = p.height
        lx = (p.anchor_x - p.pivot_x) * pw + @x
        ly = (p.anchor_y - p.pivot_y) * ph + @y

        slx = lx * p_sx
        sly = ly * p_sy
        wt.x = p_wpv_x + slx * p_cos - sly * p_sin
        wt.y = p_wpv_y + slx * p_sin + sly * p_cos

        pv_off_x = (@pivot_x - @anchor_x) * w
        pv_off_y = (@pivot_y - @anchor_y) * h
        if pv_off_x.abs < 0.0001 && pv_off_y.abs < 0.0001
          wt.pivot_x = wt.x
          wt.pivot_y = wt.y
        else
          spv_x = (lx + pv_off_x) * p_sx
          spv_y = (ly + pv_off_y) * p_sy
          wt.pivot_x = p_wpv_x + spv_x * p_cos - spv_y * p_sin
          wt.pivot_y = p_wpv_y + spv_x * p_sin + spv_y * p_cos
        end

        wt.scale_x = p_sx * @scale_x
        wt.scale_y = p_sy * @scale_y
        wt.angle = p_wt.angle + @angle
      else
        wt.x = @x
        wt.y = @y
        wt.pivot_x = @x + (@pivot_x - @anchor_x) * w
        wt.pivot_y = @y + (@pivot_y - @anchor_y) * h
        wt.scale_x = @scale_x
        wt.scale_y = @scale_y
        wt.angle = @angle
      end

      if wt.angle == 0.0
        wt.cos = 1.0
        wt.sin = 0.0
      else
        rad = wt.angle * (Math::PI / 180.0)
        wt.cos = Math.cos(rad)
        wt.sin = Math.sin(rad)
      end
    end

    def world_x
      if @parent
        update_world_transform if world_dirty?
        @world_transform.x
      else
        @x
      end
    end

    def world_y
      if @parent
        update_world_transform if world_dirty?
        @world_transform.y
      else
        @y
      end
    end

    def world_pivot_x
      if @parent
        update_world_transform if world_dirty?
        @world_transform.pivot_x
      else
        @x + (@pivot_x - @anchor_x) * width
      end
    end

    def world_pivot_y
      if @parent
        update_world_transform if world_dirty?
        @world_transform.pivot_y
      else
        @y + (@pivot_y - @anchor_y) * height
      end
    end

    def world_angle
      if @parent
        update_world_transform if world_dirty?
        @world_transform.angle
      else
        @angle
      end
    end

    def world_scale_x
      if @parent
        update_world_transform if world_dirty?
        @world_transform.scale_x
      else
        @scale_x
      end
    end

    def world_scale_y
      if @parent
        update_world_transform if world_dirty?
        @world_transform.scale_y
      else
        @scale_y
      end
    end

    def world_cos
      if @parent || @children
        update_world_transform if world_dirty?
        @world_transform ? @world_transform.cos : 1.0
      else
        @angle == 0.0 ? 1.0 : Math.cos(@angle * (Math::PI / 180.0))
      end
    end

    def world_sin
      if @parent || @children
        update_world_transform if world_dirty?
        @world_transform ? @world_transform.sin : 0.0
      else
        @angle == 0.0 ? 0.0 : Math.sin(@angle * (Math::PI / 180.0))
      end
    end

    def width
      @width || (@image ? @image.width.to_f : 0.0)
    end

    def width=(v)
      vf = v ? v.to_f : nil
      return if @width == vf
      old_w = width
      @width = vf
      return if old_w == width

      @world_transform.dirty = true if @world_transform
      if @collider_shape.is_a?(Collision::Rect) && @collider_shape.parent
        @collider_shape.dirty_size!
      else
        @collider_shape&.dirty_pos!
      end
      dirty_children_pos! if @children
    end

    def height
      @height || (@image ? @image.height.to_f : 0.0)
    end

    def height=(v)
      vf = v ? v.to_f : nil
      return if @height == vf
      old_h = height
      @height = vf
      return if old_h == height

      @world_transform.dirty = true if @world_transform
      if @collider_shape.is_a?(Collision::Rect) && @collider_shape.parent
        @collider_shape.dirty_size!
      else
        @collider_shape&.dirty_pos!
      end
      dirty_children_pos! if @children
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

    # 描画 (Window.draw へ委譲)
    def draw
      return if @vanished || !@visible || !@image

      anim_ox = animation_offset_x
      anim_oy = animation_offset_y

      if @parent
        pv = [@pivot_x, @pivot_y]
        wpv_x = world_pivot_x
        wpv_y = world_pivot_y

        if anim_ox != 0.0 || anim_oy != 0.0
          sox = anim_ox * world_scale_x
          soy = anim_oy * world_scale_y
          w_ang = world_angle
          if w_ang == 0.0
            dx = wpv_x + sox
            dy = wpv_y + soy
          else
            cos = world_cos
            sin = world_sin
            dx = wpv_x + sox * cos - soy * sin
            dy = wpv_y + sox * sin + soy * cos
          end
        else
          dx = wpv_x
          dy = wpv_y
        end

        Window.draw(
          dx, dy, @image,
          width: @width, height: @height,
          anchor: pv, pivot: pv,
          scale_x: world_scale_x, scale_y: world_scale_y,
          angle: world_angle,
          color: @color, alpha: @alpha,
          blend: @blend, shader: @shader, uniforms: @uniforms,
          camera: @camera, z: @z
        )
      else
        if anim_ox != 0.0 || anim_oy != 0.0
          sox = anim_ox * @scale_x
          soy = anim_oy * @scale_y
          if @angle == 0.0
            dx = @x + sox
            dy = @y + soy
          else
            rad = @angle * (Math::PI / 180.0)
            cos = Math.cos(rad)
            sin = Math.sin(rad)
            dx = @x + sox * cos - soy * sin
            dy = @y + sox * sin + soy * cos
          end
        else
          dx = @x
          dy = @y
        end

        Window.draw(
          dx, dy, @image,
          width: @width, height: @height,
          anchor: [@anchor_x, @anchor_y], pivot: [@pivot_x, @pivot_y],
          scale_x: @scale_x, scale_y: @scale_y,
          angle: @angle,
          color: @color, alpha: @alpha,
          blend: @blend, shader: @shader, uniforms: @uniforms,
          camera: @camera, z: @z
        )
      end
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

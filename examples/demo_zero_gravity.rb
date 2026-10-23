# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Zero-Gravity Immediate-Mode Physics Playground
# - 無重力空間で、多彩な幾何図形と即時モード物理拘束 (Constraints) を体験できる剛体物理デモ
# - [左ドラッグ]: 掴んだ点をマウスへ引っ張る (Mouse Joint / Fling 投擲)
# - [右ドラッグ]: 図形を中心軸で直感的にスピン回転させる
# - 拘束オブジェクト:
#     1. ⚲ Pinned Spinner     : 空間の固定点に留められた回転バー
#     2. ⚙ Welded Cross       : 2本のバーが直交固定された均整剛体クロス
#     3. ⛓ Pinned Double Bar  : 関節でピン結合された2連バー
#     4. 〰 Bolas Rope         : 最大距離ロープで繋がれた2連ボール
# - [SPACE]: 全図形にランダム拡散衝撃  |  [S]: 全停止  |  [R]: リセット
# - [N]: マウス位置に新しいランダム図形をスポーン  |  [C]: 全消去
# ==============================================================================

# 衝突スパーク (火花パーティクル)
class Spark
  attr_accessor :x, :y, :vx, :vy, :life, :max_life, :color, :size

  def initialize(x, y, vx, vy, life, color, size = 3.0)
    @x = x.to_f
    @y = y.to_f
    @vx = vx.to_f
    @vy = vy.to_f
    @life = life
    @max_life = life
    @color = color
    @size = size
  end

  def update
    @x += @vx
    @y += @vy
    @vx *= 0.94
    @vy *= 0.94
    @life -= 1
    vanish if @life <= 0
  end

  def vanish
    @vanished = true
  end

  def vanished?
    @vanished
  end

  def draw
    alpha = (@life.to_f / @max_life * 255).to_i
    c = [@color[0], @color[1], @color[2], alpha]
    sz = @size * (@life.to_f / @max_life)
    Window.draw_circle(@x, @y, sz, color: c)
  end
end

# 剛体物理オブジェクト
class PhysicsBody < PhysicsSprite
  attr_accessor :name, :shape, :type, :color, :border_color
  attr_accessor :init_x, :init_y, :init_vx, :init_vy, :init_angle, :init_omega
  attr_accessor :hit

  def initialize(name, shape, type, mass: 1.0, restitution: 0.88, friction: 0.35, color: nil, vx: 0.0, vy: 0.0, omega: 0.0)
    super(shape.center_x, shape.center_y,
          vx: vx, vy: vy, omega: omega,
          mass: mass, restitution: restitution, friction: friction,
          anchor: :center, pivot: :center)
    @name = name
    @shape = shape
    self.collider = shape
    self.angle = shape.angle.to_f
    @type = type
    @color = color || default_color_for(type)
    @border_color = [255, 255, 255, 220]
    @hit = false

    @init_x = self.x
    @init_y = self.y
    @init_vx = @vx
    @init_vy = @vy
    @init_angle = self.angle
    @init_omega = @omega
  end

  def reset!
    self.x = @init_x
    self.y = @init_y
    self.vx = @init_vx
    self.vy = @init_vy
    self.angle = @init_angle
    self.omega = @init_omega
    sync_shape!
    @hit = false
  end

  def sync_shape!
    @shape.center_x = self.x
    @shape.center_y = self.y
    @shape.angle = self.angle
  end

  def default_color_for(type)
    case type
    when :rect         then [55, 125, 215, 220] # ブルー
    when :rounded_rect then [65, 180, 160, 220] # ターコイズ
    when :circle       then [225, 150, 60, 220] # オレンジ
    when :ellipse      then [185, 95, 220, 220] # パープル
    when :polygon      then [220, 85, 105, 220] # コーラルピンク
    else                    [120, 140, 170, 220]
    end
  end

  def update
    # 無重力空間の運動方程式 (ごくわずかな慣性抵抗のみ)
    @vx *= 0.9992
    @vy *= 0.9992
    @omega *= 0.9985

    self.x += @vx
    self.y += @vy
    self.angle += @omega

    sync_shape!
  end

  def draw(is_active, is_hover)
    body_col = if @hit
                 [255, 80, 100, 240]
               elsif is_active
                 [100, 210, 255, 240]
               elsif is_hover
                 [@color[0] + 30, @color[1] + 30, @color[2] + 30, 240]
               else
                 @color
               end

    border_col = is_active ? [255, 240, 90, 255] : (is_hover ? [255, 255, 255, 255] : @border_color)
    border_w = (is_active || @hit) ? 2.5 : 1.5

    case @type
    when :circle
      c = @shape
      Window.draw_circle(c.center_x, c.center_y, c.effective_radius, color: body_col, border_color: border_col, border_width: border_w)
      # スピン可視化マーク
      rad = @angle * (Math::PI / 180.0)
      mx = c.center_x + Math.cos(rad) * (c.effective_radius * 0.7)
      my = c.center_y + Math.sin(rad) * (c.effective_radius * 0.7)
      Window.draw_line(c.center_x, c.center_y, mx, my, color: [255, 255, 255, 180], width: 2)

    when :ellipse
      el = @shape
      rx = el.radius_x * el.scale_x
      ry = el.radius_y * el.scale_y
      Window.draw_path do |c|
        c.save
        c.translate(el.center_x, el.center_y)
        c.rotate(el.angle * Math::PI / 180.0)
        c.begin_path
        c.ellipse(0, 0, rx, ry, 0.0)
        c.close_path
        c.fill(body_col)
        c.stroke(border_col, border_w)
        # 長軸に沿ったスピン可視化マーク線
        c.begin_path
        c.move_to(0, 0)
        c.line_to(rx * 0.7, 0)
        c.stroke([255, 255, 255, 180], 2)
        c.restore
      end

    when :rect
      r = @shape
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.scale(r.scale_x, r.scale_y)
        c.begin_path
        c.rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height)
        c.fill(body_col)
        c.stroke(border_col, border_w)
        # 対角スピンガイド線
        c.move_to(-r.width * 0.25, 0)
        c.line_to(r.width * 0.25, 0)
        c.stroke([255, 255, 255, 120], 1.5)
        c.restore
      end

    when :rounded_rect
      r = @shape
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.scale(r.scale_x, r.scale_y)
        c.begin_path
        c.round_rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height, r.radius)
        c.fill(body_col)
        c.stroke(border_col, border_w)
        c.restore
      end

    when :polygon
      poly = @shape
      verts = poly.local_vertices
      v_len = verts.length
      Window.draw_path do |c|
        c.save
        c.translate(poly.center_x, poly.center_y)
        c.rotate(poly.angle * Math::PI / 180.0)
        c.scale(poly.scale_x, poly.scale_y)
        c.begin_path
        vi = 0
        while vi < v_len
          v = verts[vi]
          if vi == 0
            c.move_to(v[0], v[1])
          else
            c.line_to(v[0], v[1])
          end
          vi += 1
        end
        c.close_path
        c.fill(body_col)
        c.stroke(border_col, border_w)
        c.restore
      end
    end
  end
end

class ZeroGravityDemo
  attr_accessor :items, :walls, :constraints, :sparks, :active_item, :drag_mode
  attr_accessor :drag_anchor, :prev_mx, :prev_my, :mouse_vx, :mouse_vy
  attr_accessor :rotate_base_angle, :mouse_pt, :hit_count

  def initialize
    @mouse_pt = Collision.point(0.0, 0.0)
    @active_item = nil
    @drag_mode = nil
    @drag_anchor = nil
    @prev_mx = 0.0
    @prev_my = 0.0
    @mouse_vx = 0.0
    @mouse_vy = 0.0
    @rotate_base_angle = 0.0
    @sparks = []
    @hit_count = 0
    @items = []
    @constraints = []

    create_walls
    create_items
  end

  def create_walls
    # 画面外周のクッション壁 (上下左右)
    @walls = [
      Collision.rect(640, -10, 1360, 40, anchor: :center),
      Collision.rect(640, 730, 1360, 40, anchor: :center),
      Collision.rect(-10, 360, 40, 800, anchor: :center),
      Collision.rect(1290, 360, 40, 800, anchor: :center)
    ]
  end

  def create_items
    @items.clear
    @constraints.clear

    # --- 1. 単体図形 (プリミティブ＆ポリゴン) ---
    # 回転矩形 (OBB) - 左上
    @items << PhysicsBody.new("Box A", Collision.rect(180, 160, 95, 60, angle: 25, anchor: :center), :rect, mass: 1.2, vx: 1.2, vy: 0.6, omega: 1.0)
    # 三角形 - 中央やや左
    @items << PhysicsBody.new("Triangle", Collision.polygon([[0.0, -45.0], [40.0, 35.0], [-40.0, 35.0]], x: 460, y: 340, angle: 30, anchor: :center), :polygon, mass: 0.9, vx: -0.8, vy: 0.7, omega: -1.5)
    # 楕円 - 右下
    @items << PhysicsBody.new("Ellipse", Collision.circle(1100, 520, 70, 38, angle: -20, anchor: :center), :ellipse, mass: 1.1, vx: -1.2, vy: 0.5, omega: 1.2)
    # カプセル - 左下
    @items << PhysicsBody.new("Capsule", Collision.rect(200, 560, 120, 55, radius: 22, angle: 35, anchor: :center), :rounded_rect, mass: 1.3, vx: 0.8, vy: -1.0, omega: -0.8)
    # 凸五角形 - 右上
    @items << PhysicsBody.new("Pentagon", Collision.polygon([[0.0, -42.0], [40.0, -12.0], [25.0, 35.0], [-25.0, 35.0], [-40.0, -12.0]], x: 1080, y: 160, angle: 10, anchor: :center), :polygon, mass: 1.4, vx: -0.5, vy: -0.6, omega: 0.8)

    # --- 2. 拘束オブジェクト群 (Constraints) ---

    # ① 固定ピン留めスピナー (Pinned Spinner) - 画面上部中央
    # 空間の固定点 [640, 150] を軸として自由に回転するバー
    spinner = PhysicsBody.new("Spinner", Collision.rect(640, 150, 230, 24, angle: 0, anchor: :center), :rect, mass: 2.0, vx: 0.0, vy: 0.0, omega: 2.2)
    spinner.color = [240, 190, 50, 230] # メタリックゴールド
    @items << spinner
    @constraints << {
      type: :pin,
      name: "Pinned Spinner",
      a: spinner,
      b: nil,
      pivot: [640.0, 150.0],
      anchor_a: [0.0, 0.0]
    }

    # ② 完全固定溶接 (Welded Cross) - 画面中央
    # 2本の直交するバー (Rect) が中心で完全溶接された均整クロス剛体
    cross_h = PhysicsBody.new("Cross Horizontal", Collision.rect(640, 360, 130, 24, angle: -20, anchor: :center), :rect, mass: 1.2, vx: 1.0, vy: -0.5, omega: 1.2)
    cross_h.color = [60, 150, 240, 230] # ブルー
    cross_v = PhysicsBody.new("Cross Vertical", Collision.rect(640, 360, 24, 130, angle: -20, anchor: :center), :rect, mass: 1.2, vx: 1.0, vy: -0.5, omega: 1.2)
    cross_v.color = [235, 70, 95, 230] # ルビーレッド
    @items << cross_h
    @items << cross_v
    rel_offset, rel_ang = cross_h.relative_offset(cross_v)
    @constraints << {
      type: :weld,
      name: "Welded Cross",
      a: cross_h,
      b: cross_v,
      offset: rel_offset,
      angle: rel_ang
    }

    # ③ ピン結合ヌンチャク (Pinned Double Bar) - 画面右側
    # 2つのバーが関節で接続され、自由に折れ曲がりながら運動
    bar_a = PhysicsBody.new("Bar A", Collision.rect(860, 360, 95, 20, angle: 15, anchor: :center), :rect, mass: 1.0, vx: -0.8, vy: 1.2, omega: 2.0)
    bar_a.color = [45, 205, 155, 230] # エメラルド
    bar_b = PhysicsBody.new("Bar B", Collision.rect(948, 385, 95, 20, angle: 60, anchor: :center), :rect, mass: 1.0, vx: -0.8, vy: 1.2, omega: -1.5)
    bar_b.color = [140, 225, 65, 230] # ライム
    @items << bar_a
    @items << bar_b
    @constraints << {
      type: :pin,
      name: "Pinned Double Bar",
      a: bar_a,
      b: bar_b,
      anchor_a: [47.5, 0.0],
      anchor_b: [-47.5, 0.0]
    }

    # ④ ロープ拘束ボーラ (Distance Rope Balls) - 画面下部
    # 2つの球が最大長ロープで繋がれ公転
    bola_a = PhysicsBody.new("Bola A", Collision.circle(580, 560, 24, anchor: :center), :circle, mass: 1.1, vx: 0.0, vy: 2.4, omega: 1.0)
    bola_a.color = [245, 130, 45, 230] # オレンジ
    bola_b = PhysicsBody.new("Bola B", Collision.circle(700, 560, 24, anchor: :center), :circle, mass: 1.1, vx: 0.0, vy: -2.4, omega: -1.0)
    bola_b.color = [50, 195, 235, 230] # スカイブルー
    @items << bola_a
    @items << bola_b
    @constraints << {
      type: :distance,
      name: "Bolas Rope",
      a: bola_a,
      b: bola_b,
      max: 130.0
    }
  end

  # 直接結合された物体同士は相互衝突をスキップ
  def connected?(a, b)
    @constraints.any? do |c|
      (c[:type] == :weld || c[:type] == :pin) &&
        ((c[:a] == a && c[:b] == b) || (c[:a] == b && c[:b] == a))
    end
  end

  # 溶接（weld）された相棒オブジェクトへ押し戻し（平行移動）を連動伝搬
  def push_connected(item, px, py)
    @constraints.each do |c|
      next unless c[:type] == :weld
      if c[:a] == item
        c[:b].x += px
        c[:b].y += py
        c[:b].sync_shape!
      elsif c[:b] == item
        c[:a].x += px
        c[:a].y += py
        c[:a].sync_shape!
      end
    end
  end

  def spawn_random_item(x, y)
    type = [:rect, :circle, :ellipse, :polygon, :rounded_rect].sample
    name = "Obj_#{@items.length + 1}"
    vx = rand(-4.0..4.0)
    vy = rand(-4.0..4.0)
    omega = rand(-5.0..5.0)

    shape = case type
            when :circle
              Collision.circle(x, y, rand(30..50), anchor: :center)
            when :ellipse
              Collision.circle(x, y, rand(45..75), rand(25..40), angle: rand(0..360), anchor: :center)
            when :rect
              Collision.rect(x, y, rand(50..100), rand(50..90), angle: rand(0..360), anchor: :center)
            when :rounded_rect
              Collision.rect(x, y, rand(70..120), rand(50..70), radius: rand(15..25), angle: rand(0..360), anchor: :center)
            when :polygon
              sides = rand(3..6)
              r = rand(35..55)
              pts = (0...sides).map do |si|
                a = (si.to_f / sides) * Math::PI * 2.0
                [Math.cos(a) * r, Math.sin(a) * r]
              end
              Collision.polygon(pts, x: x, y: y, angle: rand(0..360), anchor: :center)
            end

    @items << PhysicsBody.new(name, shape, type, mass: rand(0.8..1.5), vx: vx, vy: vy, omega: omega)
  end

  def spawn_sparks(x, y, count, color = [255, 230, 120])
    count.times do
      ang = rand(0.0..(Math::PI * 2.0))
      spd = rand(1.5..7.0)
      svx = Math.cos(ang) * spd
      svy = Math.sin(ang) * spd
      @sparks << Spark.new(x, y, svx, svy, rand(10..22), color, rand(2.0..4.5))
    end
  end

  def find_item_at(mx, my)
    @mouse_pt.x = mx
    @mouse_pt.y = my
    i = @items.length - 1
    while i >= 0
      item = @items[i]
      return item if Collision.check(@mouse_pt, item.shape)
      i -= 1
    end
    nil
  end

  def update(mx, my)
    # マウス移動速度の計測 (投擲用)
    @mouse_vx = (mx - @prev_mx) * 0.7 + @mouse_vx * 0.3
    @mouse_vy = (my - @prev_my) * 0.7 + @mouse_vy * 0.3
    @prev_mx = mx
    @prev_my = my

    # キー操作
    create_items if Input.key_push?(:r) # [R] リセット
    if Input.key_push?(:c)              # [C] 全消去
      @items.clear
      @constraints.clear
    end

    # [SPACE] 全オブジェクト拡散インパルス
    if Input.key_push?(:space)
      @items.each do |it|
        it.vx += rand(-6.0..6.0)
        it.vy += rand(-6.0..6.0)
        it.omega += rand(-8.0..8.0)
      end
      spawn_sparks(640, 360, 40, [255, 180, 80])
    end

    # [S] 全停止
    if Input.key_push?(:s)
      @items.each do |it|
        it.vx = 0.0
        it.vy = 0.0
        it.omega = 0.0
      end
    end

    # [N] 新規スポーン
    spawn_random_item(mx, my) if Input.key_push?(:n)

    # マウスドラッグ操作 (掴んで動かす / 投げる / 回転させる)
    if Input.mouse_push?(:left)
      found = find_item_at(mx, my)
      if found
        @active_item = found
        @drag_mode = :move
        # クリックした位置のローカル座標をアンカーとして記憶
        @drag_anchor = @active_item.world_to_local(mx, my)
      end
    end

    if Input.mouse_push?(:right)
      found = find_item_at(mx, my)
      if found
        @active_item = found
        @drag_mode = :rotate
        dx = mx - @active_item.x
        dy = my - @active_item.y
        init_angle = Math.atan2(dy, dx) * (180.0 / Math::PI)
        @rotate_base_angle = init_angle - @active_item.angle
      end
    end

    # 移動ドラッグ中
    if @drag_mode == :move && @active_item
      if Input.mouse_pressed?(:left)
        # 物理ドラッグ拘束は update_physics 内で毎フレーム適用される
      else
        # マウスを離した瞬間：掴んでいた速度・角速度 + マウス振りの勢いで投げ飛ばす！ (Fling)
        @active_item.vx = (@active_item.vx * 0.4 + @mouse_vx * 0.6).clamp(-22.0, 22.0)
        @active_item.vy = (@active_item.vy * 0.4 + @mouse_vy * 0.6).clamp(-22.0, 22.0)
        @drag_mode = nil
        @active_item = nil
        @drag_anchor = nil
      end
    end

    # 回転ドラッグ中
    if @drag_mode == :rotate && @active_item
      if Input.mouse_pressed?(:right)
        dx = mx - @active_item.x
        dy = my - @active_item.y
        if dx * dx + dy * dy > 16.0
          mouse_ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
          new_ang = mouse_ang - @rotate_base_angle
          @active_item.omega = (new_ang - @active_item.angle) * 0.4
          @active_item.angle = new_ang
          @active_item.sync_shape!
        end
      else
        @drag_mode = nil
        @active_item = nil
      end
    end

    # 全アイテムの自由運動
    @items.each(&:update)

    # 物理シミュレーション (拘束解決 ＆ 衝突解決)
    update_physics(mx, my)

    # パーティクル更新 (Sprite.update / Sprite.clean)
    Sprite.update(@sparks)
    Sprite.clean(@sparks)
  end

  # 即時モード 拘束の適用
  def apply_constraints(mx, my)
    # 1. マウスドラッグ拘束 (掴んだ点をマウスカーソルへ追従・トルク回転)
    if @drag_mode == :move && @active_item && @drag_anchor
      @active_item.constrain_point(mx, my, anchor: @drag_anchor, stiffness: 0.55, damping: 0.88)
    end

    # 2. 定常拘束群
    @constraints.each do |c|
      case c[:type]
      when :pin
        c[:a].constrain_pin(c[:b], pivot: c[:pivot], anchor: c[:anchor_a], other_anchor: c[:anchor_b])
      when :weld
        c[:a].constrain_weld(c[:b], offset: c[:offset], angle: c[:angle], stiffness: 1.0)
      when :distance
        c[:a].constrain_distance(c[:b], length: c[:length], min: c[:min], max: c[:max], anchor: c[:anchor_a], other_anchor: c[:anchor_b])
      end
    end
  end

  def update_physics(mx, my)
    len = @items.length
    i = 0
    while i < len
      @items[i].hit = false
      i += 1
    end
    @hit_count = 0

    # 2回反復ソルバー (拘束・衝突の多重解決でめり込み・ズレを完全解消)
    2.times do |iter|
      # 拘束事前適用
      apply_constraints(mx, my)
      @items.each(&:sync_shape!)

      # 1. アイテム vs アイテム の相互衝突 (Physics.resolve)
      i = 0
      while i < len
        it_a = @items[i]
        j = i + 1
        while j < len
          it_b = @items[j]

          # 結合されたペアの自己衝突はスキップ
          if connected?(it_a, it_b)
            j += 1
            next
          end

          # 高速ブロードフェーズ (外接円チェック)
          r_sum = it_a.shape.bounding_radius + it_b.shape.bounding_radius
          dx = it_b.x - it_a.x
          dy = it_b.y - it_a.y
          if dx * dx + dy * dy < r_sum * r_sum
            hit = Collision.penetration(it_a.shape, it_b.shape)
            if hit
              it_a.hit = true
              it_b.hit = true
              @hit_count += 1 if iter == 0

              # 即時モード 2体剛体衝突解決！
              res = Physics.resolve(hit, it_a, it_b, restitution: 0.88, friction: 0.35)

              it_a.x += res.a.push_x
              it_a.y += res.a.push_y
              it_a.vx = res.a.vx
              it_a.vy = res.a.vy
              it_a.omega = res.a.omega
              it_a.sync_shape!
              push_connected(it_a, res.a.push_x, res.a.push_y)

              it_b.x += res.b.push_x
              it_b.y += res.b.push_y
              it_b.vx = res.b.vx
              it_b.vy = res.b.vy
              it_b.omega = res.b.omega
              it_b.sync_shape!
              push_connected(it_b, res.b.push_x, res.b.push_y)

              # 激しい衝突時は火花エフェクト
              if iter == 0 && res.impact > 1.2
                spawn_sparks(hit.contact_x, hit.contact_y, [(res.impact * 2).to_i, 12].min, [255, 220, 140])
              end
            end
          end
          j += 1
        end
        i += 1
      end

      # 2. アイテム vs 外周壁 の衝突解決 (Physics.resolve_static)
      @items.each do |it|
        @walls.each do |wall|
          hit = Collision.penetration(it.shape, wall)
          next unless hit

          res = Physics.resolve_static(hit, it, wall, restitution: 0.92, friction: 0.25)
          it.x += res.push_x
          it.y += res.push_y
          it.vx = res.vx
          it.vy = res.vy
          it.omega = res.omega
          it.sync_shape!
          push_connected(it, res.push_x, res.push_y)

          if iter == 0 && res.impact > 1.5
            sx = hit.contact_x.clamp(2.0, 1278.0)
            sy = hit.contact_y.clamp(2.0, 718.0)
            spawn_sparks(sx, sy, [(res.impact * 2).to_i, 8].min, [140, 210, 255])
          end
        end
      end

      # 拘束事後適用 (衝突によるズレを最終補正)
      apply_constraints(mx, my)
      @items.each(&:sync_shape!)
    end
  end

  # 拘束・ジョイントのビジュアル描画
  def draw_constraints(mx, my)
    @constraints.each do |c|
      case c[:type]
      when :pin
        px, py = if c[:b]
                   c[:a].local_to_world(c[:anchor_a][0], c[:anchor_a][1])
                 else
                   c[:pivot]
                 end

        unless c[:b]
          # 固定ピンの壁留めベース十字
          Window.draw_line(px - 10, py, px + 10, py, color: [160, 180, 210, 180], width: 2)
          Window.draw_line(px, py - 10, px, py + 10, color: [160, 180, 210, 180], width: 2)
        end

        # ベアリングピン金具
        Window.draw_circle(px, py, 7, color: [40, 50, 65, 255])
        Window.draw_circle(px, py, 5, color: [220, 230, 245, 255])
        Window.draw_circle(px, py, 2, color: [70, 80, 95, 255])

      when :distance
        pax, pay = c[:a].local_to_world(0.0, 0.0)
        pbx, pby = c[:b].local_to_world(0.0, 0.0)
        dist = Math.hypot(pbx - pax, pby - pay)
        max_d = c[:max] || c[:length] || 100.0
        tension = (dist / max_d).clamp(0.0, 1.0)
        rope_alpha = (140 + tension * 115).to_i
        rope_color = tension > 0.95 ? [255, 240, 120, rope_alpha] : [210, 205, 175, rope_alpha]

        Window.draw_line(pax, pay, pbx, pby, color: rope_color, width: 2.5)
        Window.draw_circle(pax, pay, 4, color: [240, 220, 160, 255])
        Window.draw_circle(pbx, pby, 4, color: [240, 220, 160, 255])

      when :weld
        mid_x = (c[:a].x + c[:b].x) * 0.5
        mid_y = (c[:a].y + c[:b].y) * 0.5
        Window.draw_circle(mid_x, mid_y, 4, color: [255, 220, 80, 220])
      end
    end

    # マウスドラッグ拘束 (Mouse Joint) の弾性ライン描画
    if @drag_mode == :move && @active_item && @drag_anchor
      ax, ay = @active_item.local_to_world(@drag_anchor[0], @drag_anchor[1])
      Window.draw_line(ax, ay, mx, my, color: [100, 240, 255, 200], width: 2.5)
      Window.draw_circle(ax, ay, 6, color: [40, 180, 240, 240], border_color: [255, 255, 255, 255], border_width: 1.5)
      Window.draw_circle(mx, my, 7, color: [255, 240, 90, 255], border_color: [30, 30, 30, 200], border_width: 1.5)
    elsif @drag_mode == :rotate && @active_item
      Window.draw_line(@active_item.x, @active_item.y, mx, my, color: [255, 120, 180, 180], width: 2)
      Window.draw_circle(mx, my, 6, color: [255, 90, 140, 255])
    end
  end

  def draw(mx, my)
    Window.clear([15, 20, 30, 255])

    # 外周壁のボーダーライン
    Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 0], border_width: 3, border_color: [60, 90, 130, 200])

    hover_item = find_item_at(mx, my)

    # 拘束のビジュアル描画
    draw_constraints(mx, my)

    # オブジェクト描画
    @items.each do |it|
      it.draw(it == @active_item, it == hover_item)
    end

    # パーティクル描画
    @sparks.each(&:draw)

    # UI 情報テキスト
    Window.draw_text(30, 20, "Zenoo Zero-Gravity Physics Playground with Constraints", size: 22, color: [255, 255, 255, 255])
    Window.draw_text(30, 48, "Pure Ruby Immediate-Mode Rigid Body Physics & Stateless Constraints", size: 14, color: [140, 180, 220, 255])
    Window.draw_text(30, 72, "[左ドラッグ]: 掴んで動かす・投げる (Mouse Joint)   |   [右ドラッグ]: スピン回転   |   [SPACE]: 拡散   |   [S]: 停止", size: 13, color: [255, 225, 100, 255])
    Window.draw_text(30, 94, "Constraints: ⚲ Pinned Spinner  |  ⚙ Welded Cross  |  ⛓ Pinned Double Bar  |  〰 Bolas Rope", size: 13, color: [130, 230, 210, 255])
    Window.draw_text(30, 116, "[N]: ランダム図形生成   |   [R]: リセット   |   [C]: 全消去", size: 13, color: [180, 210, 235, 255])

    status_col = @hit_count > 0 ? [255, 110, 110, 255] : [120, 230, 160, 255]
    Window.draw_text(30, 680, "Objects: #{@items.length}   |   Constraints: #{@constraints.length}   |   Collisions: #{@hit_count} pairs   |   FPS: #{Window.fps.round(1)}", size: 14, color: status_col)
  end

  def step_frame
    mx, my = Input.mouse_pos
    mx = 640.0 if mx < 0 || mx > 1280
    my = 360.0 if my < 0 || my > 720

    update(mx, my)
    draw(mx, my)
  end
end

if __FILE__ == $0
  demo = ZeroGravityDemo.new
  test_frames = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
  frame_counter = 0

  Window.loop(1280, 720, "Zenoo Zero-Gravity Physics Playground") do
    demo.step_frame
    if test_frames > 0
      frame_counter += 1
      if frame_counter >= test_frames
        puts "Zero-gravity physics demo completed successfully! (#{frame_counter} frames)"
        exit
      end
    end
  end
end

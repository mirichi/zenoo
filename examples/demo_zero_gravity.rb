# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Zero-Gravity Immediate-Mode Physics Playground
# - 無重力空間で、多彩な幾何図形（矩形・多角形・楕円・円・カプセル）が飛び交う剛体物理デモ
# - [左ドラッグ]: 図形を掴んで動かす / 離すとマウスの勢いで投げ飛ばす！
# - [右ドラッグ]: 図形を中心軸で直感的にスピン回転させる
# - [SPACE]: 全図形にランダムな衝撃（拡散）  |  [S]: 全停止  |  [R]: リセット
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
  end

  def dead?
    @life <= 0
  end

  def draw
    alpha = (@life.to_f / @max_life * 255).to_i
    c = [@color[0], @color[1], @color[2], alpha]
    sz = @size * (@life.to_f / @max_life)
    Window.draw_circle(@x, @y, sz, color: c)
  end
end

# 剛体物理オブジェクト
class PhysicsBody
  attr_accessor :name, :shape, :type, :x, :y, :vx, :vy, :angle, :omega
  attr_accessor :mass, :restitution, :friction, :color, :border_color
  attr_accessor :init_x, :init_y, :init_vx, :init_vy, :init_angle, :init_omega
  attr_accessor :hit

  def initialize(name, shape, type, mass: 1.0, restitution: 0.88, friction: 0.35, color: nil, vx: 0.0, vy: 0.0, omega: 0.0)
    @name = name
    @shape = shape
    @type = type
    @x = shape.center_x
    @y = shape.center_y
    @vx = vx.to_f
    @vy = vy.to_f
    @angle = shape.angle.to_f
    @omega = omega.to_f
    @mass = mass.to_f
    @restitution = restitution.to_f
    @friction = friction.to_f
    @color = color || default_color_for(type)
    @border_color = [255, 255, 255, 220]
    @hit = false

    @init_x = @x
    @init_y = @y
    @init_vx = @vx
    @init_vy = @vy
    @init_angle = @angle
    @init_omega = @omega
  end

  def reset!
    @x = @init_x
    @y = @init_y
    @vx = @init_vx
    @vy = @init_vy
    @angle = @init_angle
    @omega = @init_omega
    @shape.center_x = @x
    @shape.center_y = @y
    @shape.angle = @angle
    @hit = false
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

  def update(is_grabbed)
    return if is_grabbed

    # 無重力空間の運動方程式 (ごくわずかな慣性抵抗のみ)
    @vx *= 0.9992
    @vy *= 0.9992
    @omega *= 0.9985

    @x += @vx
    @y += @vy
    @angle += @omega

    # Shape を同期 (常に重心位置に同期)
    @shape.center_x = @x
    @shape.center_y = @y
    @shape.angle = @angle
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
        # 長軸に沿ったスピン可視化マーク線 (中心から長軸方向へ)
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
  attr_accessor :items, :walls, :sparks, :active_item, :drag_mode
  attr_accessor :drag_offset_x, :drag_offset_y, :prev_mx, :prev_my, :mouse_vx, :mouse_vy
  attr_accessor :rotate_base_angle, :mouse_pt, :hit_count

  def initialize
    @mouse_pt = Collision.point(0.0, 0.0)
    @active_item = nil
    @drag_mode = nil
    @drag_offset_x = 0.0
    @drag_offset_y = 0.0
    @prev_mx = 0.0
    @prev_my = 0.0
    @mouse_vx = 0.0
    @mouse_vy = 0.0
    @rotate_base_angle = 0.0
    @sparks = []
    @hit_count = 0

    create_walls
    create_items
  end

  def create_walls
    # 画面外周のクッション壁 (上下左右)
    @walls = [
      # 上壁
      Collision.rect(640, -10, 1360, 40, anchor: :center),
      # 下壁
      Collision.rect(640, 730, 1360, 40, anchor: :center),
      # 左壁
      Collision.rect(-10, 360, 40, 800, anchor: :center),
      # 右壁
      Collision.rect(1290, 360, 40, 800, anchor: :center)
    ]
  end

  def create_items
    @items = [
      # 1. 回転矩形 (OBB) - 左上
      PhysicsBody.new("Box A", Collision.rect(260, 200, 110, 70, angle: 25, anchor: :center), :rect, mass: 1.2, vx: 1.5, vy: 0.8, omega: 1.2),

      # 2. 三角形 (Triangle Polygon) - 中央上
      PhysicsBody.new("Triangle", Collision.polygon([[0.0, -50.0], [45.0, 38.0], [-45.0, 38.0]], x: 540, y: 190, angle: 30, anchor: :center), :polygon, mass: 0.9, vx: -1.2, vy: 1.0, omega: -2.0),

      # 3. 楕円 (Ellipse) - 右上
      PhysicsBody.new("Ellipse", Collision.circle(840, 210, 75, 40, angle: -20, anchor: :center), :ellipse, mass: 1.1, vx: -1.8, vy: 0.6, omega: 1.5),

      # 4. カプセル (Rounded Rect) - 左下
      PhysicsBody.new("Capsule", Collision.rect(320, 500, 130, 60, radius: 24, angle: 45, anchor: :center), :rounded_rect, mass: 1.3, vx: 1.0, vy: -1.4, omega: -1.0),

      # 5. 凸五角形 (Pentagon Polygon) - 中央
      PhysicsBody.new("Pentagon", Collision.polygon([[0.0, -48.0], [46.0, -15.0], [28.0, 40.0], [-28.0, 40.0], [-46.0, -15.0]], x: 640, y: 380, angle: 10, anchor: :center), :polygon, mass: 1.4, vx: 0.5, vy: -0.8, omega: 0.8),

      # 6. 真円 (Circle) - 右下
      PhysicsBody.new("Ball", Collision.circle(960, 480, 48, anchor: :center), :circle, mass: 1.0, vx: -2.0, vy: -1.2, omega: 2.2),

      # 7. 小型スピードボックス - 中央下
      PhysicsBody.new("Mini Box", Collision.rect(640, 560, 50, 50, angle: 15, anchor: :center), :rect, mass: 0.7, vx: 2.4, vy: -1.8, omega: 3.5)
    ]
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
              # ランダム凸多角形 (3角形〜6角形)
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
    @items.clear if Input.key_push?(:c) # [C] 全消去

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
        @drag_offset_x = mx - @active_item.x
        @drag_offset_y = my - @active_item.y
        @active_item.vx = 0.0
        @active_item.vy = 0.0
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
        target_x = mx - @drag_offset_x
        target_y = my - @drag_offset_y
        @active_item.x = target_x
        @active_item.y = target_y
        @active_item.shape.center_x = target_x
        @active_item.shape.center_y = target_y
      else
        # マウスを離した瞬間：勢いよく投げ飛ばす！ (Fling)
        @active_item.vx = @mouse_vx.clamp(-18.0, 18.0)
        @active_item.vy = @mouse_vy.clamp(-18.0, 18.0)
        @drag_mode = nil
        @active_item = nil
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
          @active_item.shape.angle = new_ang
        end
      else
        @drag_mode = nil
        @active_item = nil
      end
    end

    # 全アイテムの自由運動
    @items.each { |it| it.update(it == @active_item) }

    # 物理シミュレーション (衝突判定＆即時剛体解決)
    update_physics

    # パーティクル更新
    @sparks.each(&:update)
    @sparks.reject!(&:dead?)
  end

  def update_physics
    len = @items.length

    # 1. アイテム vs アイテム の相互衝突 (Physics.resolve)
    i = 0
    while i < len
      it_a = @items[i]
      it_a.hit = false
      i += 1
    end

    @hit_count = 0
    i = 0
    while i < len
      it_a = @items[i]
      j = i + 1
      while j < len
        it_b = @items[j]

        # 高速ブロードフェーズ (外接円チェック)
        r_sum = it_a.shape.bounding_radius + it_b.shape.bounding_radius
        dx = it_b.x - it_a.x
        dy = it_b.y - it_a.y
        if dx * dx + dy * dy < r_sum * r_sum
          hit = Collision.penetration(it_a.shape, it_b.shape)
          if hit
            it_a.hit = true
            it_b.hit = true
            @hit_count += 1

            # ★ 即時モード 2体剛体衝突解決！
            res = Physics.resolve(
              hit,
              a: { x: it_a.x, y: it_a.y, vx: it_a.vx, vy: it_a.vy, omega: it_a.omega, shape: it_a.shape, mass: it_a.mass },
              b: { x: it_b.x, y: it_b.y, vx: it_b.vx, vy: it_b.vy, omega: it_b.omega, shape: it_b.shape, mass: it_b.mass },
              restitution: 0.88, # 高弾性で軽快に跳ね返る
              friction: 0.35     # 摩擦によるスピン交換
            )

            # 物体Aへの反映 (ドラッグ中でない場合のみ位置押し戻し)
            unless it_a == @active_item && @drag_mode == :move
              it_a.x += res.a.push_x
              it_a.y += res.a.push_y
            end
            it_a.vx = res.a.vx
            it_a.vy = res.a.vy
            it_a.omega = res.a.omega
            it_a.shape.center_x = it_a.x
            it_a.shape.center_y = it_a.y

            # 物体Bへの反映
            unless it_b == @active_item && @drag_mode == :move
              it_b.x += res.b.push_x
              it_b.y += res.b.push_y
            end
            it_b.vx = res.b.vx
            it_b.vy = res.b.vy
            it_b.omega = res.b.omega
            it_b.shape.center_x = it_b.x
            it_b.shape.center_y = it_b.y

            # 激しい衝突時は火花エフェクト
            if res.impact > 1.2
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

        res = Physics.resolve_static(
          hit,
          x: it.x, y: it.y,
          vx: it.vx, vy: it.vy,
          omega: it.omega,
          shape: it.shape,
          mass: it.mass,
          restitution: 0.92, # 壁からの高反発
          friction: 0.25
        )

        unless it == @active_item && @drag_mode == :move
          it.x += res.push_x
          it.y += res.push_y
        end
        it.vx = res.vx
        it.vy = res.vy
        it.omega = res.omega
        it.shape.center_x = it.x
        it.shape.center_y = it.y

        if res.impact > 1.5
          # 画面枠線 (0..1280, 0..720) 上に美しく散るよう微小クランプ
          sx = hit.contact_x.clamp(2.0, 1278.0)
          sy = hit.contact_y.clamp(2.0, 718.0)
          spawn_sparks(sx, sy, [(res.impact * 2).to_i, 8].min, [140, 210, 255])
        end
      end
    end
  end

  def draw(mx, my)
    Window.clear([15, 20, 30, 255])

    # 外周壁のボーダーライン
    Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 0], border_width: 3, border_color: [60, 90, 130, 200])

    hover_item = find_item_at(mx, my)

    # オブジェクト描画
    @items.each do |it|
      it.draw(it == @active_item, it == hover_item)
    end

    # パーティクル描画
    @sparks.each(&:draw)

    # ドラッグ中のガイド線
    if @drag_mode == :move && @active_item
      Window.draw_line(@active_item.x, @active_item.y, mx, my, color: [100, 220, 255, 180], width: 2)
      Window.draw_circle(mx, my, 6, color: [255, 240, 100, 255])
    elsif @drag_mode == :rotate && @active_item
      Window.draw_line(@active_item.x, @active_item.y, mx, my, color: [255, 120, 180, 180], width: 2)
      Window.draw_circle(mx, my, 6, color: [255, 90, 140, 255])
    end

    # UI 情報テキスト
    Window.draw_text(30, 20, "Zenoo Zero-Gravity 2D Physics Playground", size: 22, color: [255, 255, 255, 255])
    Window.draw_text(30, 48, "Pure Ruby Immediate-Mode Rigid Body Physics (Rect, Polygon, Ellipse, Circle)", size: 14, color: [140, 180, 220, 255])
    Window.draw_text(30, 72, "[左ドラッグ]: 掴んで投げる (Fling)   |   [右ドラッグ]: スピン回転   |   [SPACE]: 拡散   |   [S]: 停止", size: 13, color: [255, 225, 100, 255])
    Window.draw_text(30, 94, "[N]: ランダム図形生成   |   [R]: リセット   |   [C]: 全消去", size: 13, color: [180, 210, 235, 255])

    status_col = @hit_count > 0 ? [255, 110, 110, 255] : [120, 230, 160, 255]
    Window.draw_text(30, 680, "Objects: #{@items.length}   |   Collisions: #{@hit_count} pairs   |   FPS: #{Window.fps.round(1)}", size: 14, color: status_col)
  end

  def step_frame
    mx, my = Input.mouse_pos
    mx = 640.0 if mx < 0 || mx > 1280
    my = 360.0 if my < 0 || my > 720

    update(mx, my)
    draw(mx, my)
  end
end

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

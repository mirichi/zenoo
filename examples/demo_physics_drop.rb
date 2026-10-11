# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Immediate-Mode Physics Demo: Item Drop & Roll
# - クリックした場所からアイテム（小箱、コインなど）を生成・放り投げる
# - 水平地面や斜面（坂道）と衝突し、反発・摩擦・トルクによって自然に回転＆転がる！
# - [SPACE]: アイテムを連続スポーン  |  [C]: アイテム全消去  |  [R]: リセット
# ==============================================================================

class DroppedItem
  attr_accessor :x, :y, :vx, :vy, :angle, :omega, :width, :height, :radius
  attr_accessor :type, :color, :shape, :mass, :restitution, :friction, :sleeping

  def initialize(x, y, vx: 0.0, vy: 0.0, type: :rect)
    @x = x.to_f
    @y = y.to_f
    @vx = vx.to_f
    @vy = vy.to_f
    @angle = rand(0..360).to_f
    @omega = rand(-10.0..10.0)
    @type = type
    @mass = 1.0
    @restitution = 0.35 # 反発
    @friction = 0.55    # 摩擦
    @sleeping = false

    case @type
    when :rect
      @width = rand(24..36).to_f
      @height = rand(24..36).to_f
      @color = [rand(180..255), rand(120..220), rand(70..160), 255]
      @shape = Collision.rect(@x, @y, @width, @height, angle: @angle, anchor: :center)
    when :circle
      @radius = rand(14..20).to_f
      @width = @radius * 2.0
      @height = @radius * 2.0
      @color = [rand(80..180), rand(180..255), rand(180..255), 255]
      @shape = Collision.circle(@x, @y, @radius, anchor: :center)
    end
  end

  def update(obstacles)
    return if @sleeping

    # 1. 自由落下と運動
    @vy += 0.45       # 重力
    @vx *= 0.992      # 空気抵抗
    @omega *= 0.985   # 転がり・回転減速
    @x += @vx
    @y += @vy
    @angle += @omega

    # Shape を更新 (アンカー中心)
    @shape.x = @x
    @shape.y = @y
    @shape.angle = @angle

    # 2. 地面・障害物との衝突解決
    obstacles.each do |obs|
      hit = Collision.penetration(@shape, obs.shape)
      next unless hit

      # 3. 即時モード物理応答の計算！
      res = Physics.resolve_static(
        hit,
        x: @x, y: @y,
        vx: @vx, vy: @vy,
        omega: @omega,
        mass: @mass,
        shape: @shape,
        static_shape: obs.shape,
        restitution: @restitution,
        friction: @friction
      )

      # 4. 反映！
      @x += res.push_x
      @y += res.push_y
      @angle += res.d_angle if res.d_angle != 0.0
      @vx = res.vx
      @vy = res.vy
      @omega = res.omega

      # Shape にも位置と角度を即座に再同期 (連鎖衝突用)
      @shape.x = @x
      @shape.y = @y
      @shape.angle = @angle
    end

    # 速度と角速度が静止に達したらスリープ
    if @vx == 0.0 && @vy == 0.0 && @omega == 0.0
      @sleep_counter = (@sleep_counter || 0) + 1
      @sleeping = true if @sleep_counter >= 10
    else
      @sleep_counter = 0
    end
  end

  def draw
    case @type
    when :rect
      # Window.draw_rect は左上基準のため、中心からオフセットして描画
      Window.draw_rect(
        @x - @width * 0.5, @y - @height * 0.5,
        @width, @height,
        angle: @angle,
        pivot: :center,
        color: @color,
        border_width: 2,
        border_color: [255, 255, 255, 180],
        shadow_blur: 6,
        shadow_color: [0, 0, 0, 80]
      )
    when :circle
      Window.draw_circle(
        @x, @y, @radius,
        color: @color,
        border_width: 2,
        border_color: [255, 255, 255, 180]
      )
      # 回転が視認できるようにマーク線を描画
      rad = @angle * (Math::PI / 180.0)
      mx = @x + Math.cos(rad) * (@radius * 0.75)
      my = @y + Math.sin(rad) * (@radius * 0.75)
      Window.draw_line(@x, @y, mx, my, color: [20, 20, 30, 220], width: 2)
    end
  end
end

class Obstacle
  attr_accessor :x, :y, :width, :height, :angle, :radius, :color, :shape

  def initialize(x, y, w, h, angle: 0.0, radius: 4.0, color: [45, 65, 80, 255])
    @x = x.to_f
    @y = y.to_f
    @width = w.to_f
    @height = h.to_f
    @angle = angle.to_f
    @radius = radius.to_f
    @color = color
    @shape = Collision.rect(@x, @y, @width, @height, angle: @angle, radius: @radius, anchor: :center)
  end

  def draw
    Window.draw_rect(
      @x - @width * 0.5, @y - @height * 0.5,
      @width, @height,
      angle: @angle,
      radius: @radius,
      pivot: :center,
      color: @color,
      border_width: 2,
      border_color: [100, 140, 180, 255],
      shadow_blur: 10,
      shadow_color: [0, 0, 0, 100]
    )
  end
end

class PhysicsDropDemo
  def initialize
    @items = []
    @obstacles = [
      # 1. 最下部のメインフロア
      Obstacle.new(640, 680, 1200, 40, color: [35, 45, 60, 255]),
      # 2. 左上の傾斜スロープ (右下へ転がり落ちる)
      Obstacle.new(340, 240, 420, 24, angle: 18.0, color: [45, 70, 90, 255]),
      # 3. 右中段の逆向きスロープ (左下へ転がり落ちる)
      Obstacle.new(880, 420, 480, 24, angle: -16.0, color: [45, 70, 90, 255]),
      # 4. 中央の小さな踏み台
      Obstacle.new(460, 530, 220, 24, angle: 10.0, color: [50, 75, 95, 255])
    ]
    # 初期アイテムを数個降らせる
    spawn_item(220, 100, vx: 2.0, vy: -1.0)
    spawn_item(260, 80, vx: 3.0, vy: 0.0, type: :circle)
    spawn_item(300, 110, vx: 1.0, vy: -2.0)
  end

  def spawn_item(x, y, vx: rand(-4.0..4.0), vy: rand(-3.0..1.0), type: nil)
    t = type || (rand > 0.4 ? :rect : :circle)
    @items << DroppedItem.new(x, y, vx: vx, vy: vy, type: t)
  end

  def update
    mx, my = Input.mouse_pos

    # マウスクリックでアイテムを投げる
    if Input.mouse_push?(:left)
      spawn_item(mx, my, vx: rand(-5.0..5.0), vy: rand(-6.0..-1.0))
    end

    # [SPACE] で連続スポーン
    if Input.key_pressed?(:space)
      spawn_item(200 + rand(-40..40), 80, vx: rand(1.0..4.0), vy: rand(-2.0..1.0)) if rand > 0.6
    end

    # [C] で消去
    if Input.key_push?(:c)
      @items.clear
    end

    # [R] でリセット
    if Input.key_push?(:r)
      @items.clear
      spawn_item(220, 100, vx: 2.0, vy: -1.0)
      spawn_item(260, 80, vx: 3.0, vy: 0.0, type: :circle)
    end

    # アイテム更新
    @items.each { |it| it.update(@obstacles) }

    # 画面外へ落ちたアイテムを削除
    @items.reject! { |it| it.y > 800 }
  end

  def draw
    Window.clear([16, 22, 34, 255])

    # 障害物・スロープ描画
    @obstacles.each(&:draw)

    # アイテム描画
    @items.each(&:draw)

    # UI 説明テキスト
    Window.draw_text(30, 20, "Zenoo Immediate-Mode Physics: Drop & Roll Demo", size: 22, color: [255, 255, 255, 255])
    Window.draw_text(30, 50, "Pure Ruby 2D Rigid Body Physics (Impulse + Friction + Torque)", size: 14, color: [140, 170, 210, 255])
    Window.draw_text(30, 74, "[左クリック]: アイテム生成   |   [SPACE]: 連続降下   |   [C]: 全消去   |   [R]: リセット", size: 13, color: [255, 220, 100, 255])
    Window.draw_text(30, 100, "Items: #{@items.length}   |   FPS: #{Window.fps.round(1)}", size: 13, color: [180, 200, 220, 255])
  end

  def step_frame
    update
    draw
  end
end

demo = PhysicsDropDemo.new
test_frames = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_counter = 0

Window.loop(1280, 720, "Zenoo Immediate-Mode Physics Demo") do
  demo.step_frame
  if test_frames > 0
    frame_counter += 1
    if frame_counter >= test_frames
      puts "Physics drop demo completed successfully! (#{frame_counter} frames)"
      exit
    end
  end
end

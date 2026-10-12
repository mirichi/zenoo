# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Immediate-Mode Physics Demo: Item Drop & Roll
# - クリックした場所からアイテム（小箱、コインなど）を生成・放り投げる
# - 水平地面や斜面（坂道）と衝突し、反発・摩擦・トルクによって自然に回転＆転がる！
# - [SPACE]: アイテムを連続スポーン  |  [C]: アイテム全消去  |  [R]: リセット
# ==============================================================================

class DroppedItem < PhysicsSprite
  attr_accessor :width, :height, :radius, :type, :color, :sleeping

  def initialize(x, y, vx: 0.0, vy: 0.0, type: :rect)
    angle = rand(0..360).to_f
    omega = rand(-10.0..10.0)
    super(x, y, vx: vx, vy: vy, omega: omega, mass: 1.0, restitution: 0.35, friction: 0.55, anchor: :center, pivot: :center)
    self.angle = angle
    @type = type
    @sleeping = false

    case @type
    when :rect
      @width = rand(24..36).to_f
      @height = rand(24..36).to_f
      @color = [rand(180..255), rand(120..220), rand(70..160), 255]
      set_collider(:rect, width: @width, height: @height)
    when :circle
      @radius = rand(14..20).to_f
      @width = @radius * 2.0
      @height = @radius * 2.0
      @color = [rand(80..180), rand(180..255), rand(180..255), 255]
      set_collider(:circle, radius: @radius)
    end
  end

  def update(obstacles)
    return if @sleeping

    # 1. 自由落下と運動
    @vy += 0.45       # 重力
    @vx *= 0.992      # 空気抵抗
    @omega *= 0.985   # 転がり・回転減速
    self.x += @vx
    self.y += @vy
    self.angle += @omega

    # 2. 地面・障害物との衝突解決
    obstacles.each do |obs|
      hit = Collision.penetration(self, obs)
      next unless hit

      # 3. 即時モード物理応答の計算 & 自身への反映
      res = Physics.resolve_static(hit, self, obs)
      res.apply_to(self)
    end

    # 速度と角速度が静止に達したらスリープ
    if @vx.abs < 0.08 && @vy.abs < 0.08 && @omega.abs < 0.15
      @sleep_counter = (@sleep_counter || 0) + 1
      if @sleep_counter >= 8
        @vx = 0.0
        @vy = 0.0
        @omega = 0.0
        @sleeping = true
      end
    else
      @sleep_counter = 0
    end
  end

  def draw
    case @type
    when :rect
      # Window.draw_rect は左上基準のため、中心からオフセットして描画
      Window.draw_rect(
        self.x - @width * 0.5, self.y - @height * 0.5,
        @width, @height,
        angle: self.angle,
        pivot: :center,
        color: @color,
        border_width: 2,
        border_color: [255, 255, 255, 180],
        shadow_blur: 6,
        shadow_color: [0, 0, 0, 80]
      )
    when :circle
      Window.draw_circle(
        self.x, self.y, @radius,
        color: @color,
        border_width: 2,
        border_color: [255, 255, 255, 180]
      )
      # 回転が視認できるようにマーク線を描画
      rad = self.angle * (Math::PI / 180.0)
      mx = self.x + Math.cos(rad) * (@radius * 0.75)
      my = self.y + Math.sin(rad) * (@radius * 0.75)
      Window.draw_line(self.x, self.y, mx, my, color: [20, 20, 30, 220], width: 2)
    end
  end
end

class Obstacle < Sprite
  attr_accessor :radius, :color

  def initialize(x, y, w, h, angle: 0.0, radius: 4.0, color: [45, 65, 80, 255])
    super(x, y, anchor: :center, pivot: :center)
    self.angle = angle
    @width_val = w.to_f
    @height_val = h.to_f
    @radius = radius.to_f
    @color = color
    set_collider(:rect, width: @width_val, height: @height_val, radius: @radius)
  end

  def width; @width_val; end
  def height; @height_val; end

  def draw
    Window.draw_rect(
      self.x - width * 0.5, self.y - height * 0.5,
      width, height,
      angle: self.angle,
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

    # アイテム同士の相互衝突解決 (動的 vs 動的)
    len = @items.length
    i = 0
    while i < len
      item_a = @items[i]
      j = i + 1
      while j < len
        item_b = @items[j]

        # 高速ブロードフェーズ (外接円チェック)
        r_sum = item_a.collider.bounding_radius + item_b.collider.bounding_radius
        dx = item_b.x - item_a.x
        dy = item_b.y - item_a.y
        if dx * dx + dy * dy < r_sum * r_sum
          hit = Collision.penetration(item_a, item_b)
          if hit
            # 衝突したらスリープ解除
            item_a.sleeping = false
            item_b.sleeping = false

            # ★ Physics.resolve で 2 体の物理応答を取得＆一括反映！
            res = Physics.resolve(hit, item_a, item_b, restitution: 0.45, friction: 0.4)
            res&.apply_to(item_a, item_b)
          end
        end
        j += 1
      end
      i += 1
    end

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

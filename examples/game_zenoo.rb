require_relative '../lib/zenoo'

# 事前定義カラー定数
COLOR_ORANGE       = Color.new(255, 161, 0)
COLOR_HP_GRAY      = Color.new(130, 130, 130)
COLOR_GRID_DARK    = Color.new(50, 50, 60)
COLOR_MENU_BG      = Color.new(0, 0, 0, (255 * 0.58).to_i)
COLOR_BUTTON_HOVER = Color.new(70, 70, 80)
COLOR_TEXT_GRAY    = Color.new(140, 140, 140)

class Bullet
  attr_accessor :x, :y, :vx, :vy, :active, :speed

  def initialize
    @x = 0.0
    @y = 0.0
    @speed = 15.0
    @vx = 0.0
    @vy = 0.0
    @active = false
  end

  def update(px, py)
    @x += @vx
    @y += @vy
    dx = @x - px
    dy = @y - py
    if dx * dx + dy * dy > 1500.0 * 1500.0
      @active = false
    end
  end

  def draw(cx, cy)
    if @active
      sx = @x - cx
      sy = @y - cy
      Window.draw_rect(sx.to_f - 2.0, sy.to_f - 2.0, 4.0, 4.0, color: Color::RED)
    end
  end
end

class BulletManager
  attr_accessor :bullets

  def initialize(max_bullets)
    @bullets = []
    max_bullets.times do
      @bullets.push(Bullet.new)
    end
  end

  def add(x, y, angle)
    @bullets.each do |b|
      if !b.active
        b.x = x
        b.y = y
        b.vx = b.speed * Math.cos(angle)
        b.vy = b.speed * Math.sin(angle)
        b.active = true
        return
      end
    end
  end

  def update(px, py)
    @bullets.each do |b|
      b.update(px, py) if b.active
    end
  end

  def draw(cx, cy)
    @bullets.each do |b|
      b.draw(cx, cy) if b.active
    end
  end
end

class Item
  attr_accessor :x, :y, :active, :life

  def initialize
    @x = 0.0
    @y = 0.0
    @active = false
    @life = 600
  end

  def spawn(x, y)
    @x = x
    @y = y
    @active = true
    @life = 600
  end

  def update(px, py, magnet_radius)
    @life = @life - 1
    if @life <= 0
      @active = false
      return
    end

    dx = px - @x
    dy = py - @y
    dist_sq = dx * dx + dy * dy
    if dist_sq < magnet_radius * magnet_radius
      dist = Math.sqrt(dist_sq)
      if dist > 0.1
        speed = 12.0
        @x = @x + (dx / dist) * speed
        @y = @y + (dy / dist) * speed
      end
    end
  end

  def draw(cx, cy)
    if @active
      if @life < 120 && (@life % 20) < 10
        return
      end

      sx = @x - cx
      sy = @y - cy
      Window.draw_rect(sx.to_f - 5.0, sy.to_f - 5.0, 10.0, 10.0, color: Color::YELLOW)
    end
  end
end

class ItemManager
  attr_accessor :items

  def initialize(max_items)
    @items = []
    max_items.times do
      @items.push(Item.new)
    end
  end

  def add(x, y)
    @items.each do |i|
      if !i.active
        i.spawn(x, y)
        break
      end
    end
  end

  def update(px, py, magnet_radius)
    @items.each do |i|
      i.update(px, py, magnet_radius) if i.active
    end
  end

  def draw(cx, cy)
    @items.each do |i|
      i.draw(cx, cy) if i.active
    end
  end
end

class Particle
  attr_accessor :x, :y, :vx, :vy, :active, :life, :max_life

  def initialize
    @x = 0.0
    @y = 0.0
    @vx = 0.0
    @vy = 0.0
    @active = false
    @life = 0
    @max_life = 30
  end

  def spawn(x, y, vx, vy, life)
    @x = x
    @y = y
    @vx = vx
    @vy = vy
    @life = life
    @max_life = life
    @active = true
  end

  def update
    @x = @x + @vx
    @y = @y + @vy
    @life = @life - 1
    if @life <= 0
      @active = false
    end
  end

  def draw(cx, cy)
    if @active
      sx = @x - cx
      sy = @y - cy
      size = (@life.to_f / @max_life) * 10.0
      Window.draw_rect(sx.to_f - size / 2.0, sy.to_f - size / 2.0, size, size, color: COLOR_ORANGE)
    end
  end
end

class ParticleManager
  attr_accessor :particles

  def initialize(max_particles)
    @particles = []
    max_particles.times do
      @particles.push(Particle.new)
    end
  end

  def add_explosion(x, y)
    10.times do
      angle = rand(360) * Math::PI / 180.0
      speed = rand(5).to_f + 2.0
      vx = speed * Math.cos(angle)
      vy = speed * Math.sin(angle)
      life = rand(15) + 15

      @particles.each do |p|
        if !p.active
          p.spawn(x, y, vx, vy, life)
          break
        end
      end
    end
  end

  def update
    @particles.each do |p|
      p.update if p.active
    end
  end

  def draw(cx, cy)
    @particles.each do |p|
      p.draw(cx, cy) if p.active
    end
  end
end

class Enemy
  attr_accessor :x, :y, :vx, :vy, :active, :speed, :radius, :hp, :max_hp

  def initialize
    @x = 0.0
    @y = 0.0
    @vx = 0.0
    @vy = 0.0
    @active = false
    @speed = 2.0
    @radius = 15.0
    @hp = 1
    @max_hp = 1
  end

  def spawn(px, py)
    edge = rand(4)
    if edge == 0
      @x = px + (rand(1400) - 700).to_f
      @y = py - 400.0
    elsif edge == 1
      @x = px + (rand(1400) - 700).to_f
      @y = py + 400.0
    elsif edge == 2
      @x = px - 700.0
      @y = py + (rand(800) - 400).to_f
    else
      @x = px + 700.0
      @y = py + (rand(800) - 400).to_f
    end
    @active = true

    if rand(10) == 0
      @hp = 10
      @max_hp = 10
      @speed = 1.0
      @radius = 25.0
    else
      @hp = 1
      @max_hp = 1
      @speed = 2.0
      @radius = 15.0
    end
  end

  def update(px, py)
    angle = Math.atan2(py - @y, px - @x)
    @x += @speed * Math.cos(angle)
    @y += @speed * Math.sin(angle)
  end

  def draw(cx, cy)
    if @active
      sx = @x - cx
      sy = @y - cy
      size = @radius * 2.0
      
      if @max_hp > 1
        Window.draw_rect(sx - size / 2.0, sy - size / 2.0, size, size, color: Color::RED)
        
        bar_width = size
        hp_ratio = @hp.to_f / @max_hp
        Window.draw_rect(sx - size / 2.0, sy - size / 2.0 - 10.0, bar_width, 5.0, color: COLOR_HP_GRAY)
        Window.draw_rect(sx - size / 2.0, sy - size / 2.0 - 10.0, bar_width * hp_ratio, 5.0, color: Color::GREEN)
      else
        Window.draw_rect(sx - size / 2.0, sy - size / 2.0, size, size, color: Color::BLUE)
      end
    end
  end
end

class EnemyManager
  attr_accessor :enemies, :spawn_timer, :spawn_interval

  def initialize(max_enemies)
    @enemies = []
    max_enemies.times do
      @enemies.push(Enemy.new)
    end
    @spawn_timer = 0
    @spawn_interval = 60.0
  end

  def update(px, py)
    if @spawn_interval > 5.0
      @spawn_interval -= 0.01
    end

    @spawn_timer -= 1
    if @spawn_timer <= 0
      @spawn_timer = @spawn_interval.to_i
      @enemies.each do |e|
        if !e.active
          e.spawn(px, py)
          break
        end
      end
    end

    @enemies.each do |e|
      e.update(px, py) if e.active
    end
  end

  def draw(cx, cy)
    @enemies.each do |e|
      e.draw(cx, cy) if e.active
    end
  end
end

class Player
  attr_accessor :x, :y, :radius, :sides, :rotation, :speed, :fire_timer, :fire_rate, :score, :magnet_radius

  def initialize(x, y)
    @x = x.to_f
    @y = y.to_f
    @radius = 30.0
    @sides = 3
    @rotation = 0.0
    @speed = 5.0
    @fire_timer = 0
    @fire_rate = 10
    @score = 0
    @magnet_radius = 150.0
  end

  def update(bullet_manager)
    # 移動 (Input.x / Input.y: キーボードWASD/矢印、パッド十字キー、左スティックを自動統合)
    @x += Input.x * @speed
    @y += Input.y * @speed

    cx = @x - 1280.0 / 2.0
    cy = @y - 720.0 / 2.0

    mx = Input.mouse_x + cx
    my = Input.mouse_y + cy

    # マウス左クリック長押しでの追従移動 (グリッド1.5個分=150pxで最高速になるアナログ追従)
    if Input.mouse_pressed?(:left)
      dx = mx - @x
      dy = my - @y
      dist = Math.sqrt(dx * dx + dy * dy)
      if dist > 0.001
        ratio = dist / 150.0
        ratio = 1.0 if ratio > 1.0
        move_speed = @speed * ratio
        if dist > move_speed
          @x += (dx / dist) * move_speed
          @y += (dy / dist) * move_speed
        else
          @x = mx
          @y = my
        end
      end
    end

    # 照準: 右スティック(Input.rx / Input.ry)優先、スティック未入力時はマウス照準
    rx = Input.rx
    ry = Input.ry

    if rx != 0.0 || ry != 0.0
      @rotation = Math.atan2(ry, rx)
    else
      @rotation = Math.atan2(my - @y, mx - @x)
    end

    if @fire_timer > 0
      @fire_timer -= 1
    else
      @fire_timer = @fire_rate
      @sides.times do |i|
        angle = @rotation + i * (2.0 * Math::PI / @sides)
        vx = @x + @radius * Math.cos(angle)
        vy = @y + @radius * Math.sin(angle)
        bullet_manager.add(vx, vy, angle)
      end
    end
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy

    @sides.times do |i|
      angle1 = @rotation + i * (2.0 * Math::PI / @sides)
      vx1 = sx + @radius * Math.cos(angle1)
      vy1 = sy + @radius * Math.sin(angle1)

      angle2 = @rotation + ((i + 1) % @sides) * (2.0 * Math::PI / @sides)
      vx2 = sx + @radius * Math.cos(angle2)
      vy2 = sy + @radius * Math.sin(angle2)

      Window.draw_triangle(sx, sy, vx2, vy2, vx1, vy1, Color::GREEN)
      Window.draw_line(vx1, vy1, vx2, vy2, Color::WHITE)
      Window.draw_rect(vx1 - 2.0, vy1 - 2.0, 4.0, 4.0, color: Color::WHITE)
    end
  end
end

def check_collisions(bullet_manager, enemy_manager, item_manager, particle_manager, player)
  enemy_manager.enemies.each do |e|
    if e.active
      bullet_manager.bullets.each do |b|
        if b.active
          dx = e.x - b.x
          dy = e.y - b.y
          dist_sq = dx * dx + dy * dy
          hit_dist = e.radius + 2.0
          if dist_sq < hit_dist * hit_dist
            b.active = false
            e.hp = e.hp - 1
            
            if e.hp <= 0
              e.active = false
              particle_manager.add_explosion(e.x, e.y)
              
              if e.max_hp > 1
                5.times do
                  drop_x = e.x + (rand(40) - 20).to_f
                  drop_y = e.y + (rand(40) - 20).to_f
                  item_manager.add(drop_x, drop_y)
                end
              else
                item_manager.add(e.x, e.y)
              end
            end
            break
          end
        end
      end
    end
  end

  item_manager.items.each do |i|
    if i.active
      dx = player.x - i.x
      dy = player.y - i.y
      if dx * dx + dy * dy < 45.0 * 45.0
        i.active = false
        player.score = player.score + 10
      end
    end
  end
end

class Game
  attr_accessor :player, :bullet_manager, :enemy_manager, :item_manager, :particle_manager, :game_state

  def initialize
    @player = Player.new(1280.0 / 2.0, 720.0 / 2.0)
    @bullet_manager = BulletManager.new(1000)
    @enemy_manager = EnemyManager.new(300)
    @item_manager = ItemManager.new(500)
    @particle_manager = ParticleManager.new(1000)
    @game_state = 0
  end

  def update_draw_frame
    esc_pressed = Input.key_push?(:escape)
    right_clicked = Input.mouse_push?(:right)
    start_pressed = Input.gamepad_button_push?(:start) || Input.gamepad_button_push?(:back)
    b_pressed = (@game_state == 1) && Input.gamepad_button_push?(:b)

    if esc_pressed || right_clicked || start_pressed || b_pressed
      if @game_state == 0
        @game_state = 1
      else
        @game_state = 0
      end
    end

    if @game_state == 0
      @player.update(@bullet_manager)
      @bullet_manager.update(@player.x, @player.y)
      @enemy_manager.update(@player.x, @player.y)
      @item_manager.update(@player.x, @player.y, @player.magnet_radius)
      @particle_manager.update
      check_collisions(@bullet_manager, @enemy_manager, @item_manager, @particle_manager, @player)
    elsif @game_state == 1
      shape_cost = (@player.sides - 2) * 100
      
      mx = Input.mouse_x
      my = Input.mouse_y
      left_click = Input.mouse_push?(:left)

      pad_btn1 = Input.gamepad_button_push?(:a)
      pad_btn2 = Input.gamepad_button_push?(:x)
      pad_btn3 = Input.gamepad_button_push?(:y)
      pad_btn4 = Input.gamepad_button_push?(:rb) || Input.gamepad_button_push?(:lb)

      hover1 = mx >= 140.0 && mx <= 1140.0 && my >= 245.0 && my <= 290.0
      hover2 = mx >= 140.0 && mx <= 1140.0 && my >= 295.0 && my <= 340.0
      hover3 = mx >= 140.0 && mx <= 1140.0 && my >= 345.0 && my <= 390.0
      hover4 = mx >= 140.0 && mx <= 1140.0 && my >= 395.0 && my <= 440.0

      if (Input.key_push?(:"1") || pad_btn1 || (hover1 && left_click)) && @player.score >= shape_cost
        @player.score = @player.score - shape_cost
        @player.sides = @player.sides + 1
      end
      if (Input.key_push?(:"2") || pad_btn2 || (hover2 && left_click)) && @player.score >= 50
        @player.score = @player.score - 50
        @player.speed = @player.speed + 1.0
      end
      if (Input.key_push?(:"3") || pad_btn3 || (hover3 && left_click)) && @player.score >= 50 && @player.fire_rate > 2
        @player.score = @player.score - 50
        @player.fire_rate = @player.fire_rate - 2
      end
      if (Input.key_push?(:"4") || pad_btn4 || (hover4 && left_click)) && @player.score >= 50
        @player.score = @player.score - 50
        @player.magnet_radius = @player.magnet_radius + 50.0
      end
    end

    Window.clear(Color::BLACK)

    cx = @player.x - 1280.0 / 2.0
    cy = @player.y - 720.0 / 2.0

    grid_size = 100.0
    offset_x = -(cx.to_i % 100).to_f
    offset_y = -(cy.to_i % 100).to_f

    x = offset_x
    while x < 1280.0
      Window.draw_line(x, 0.0, x, 720.0, COLOR_GRID_DARK)
      x += grid_size
    end

    y = offset_y
    while y < 720.0
      Window.draw_line(0.0, y, 1280.0, y, COLOR_GRID_DARK)
      y += grid_size
    end

    @particle_manager.draw(cx, cy)
    @item_manager.draw(cx, cy)
    @enemy_manager.draw(cx, cy)
    @bullet_manager.draw(cx, cy)
    @player.draw(cx, cy)

    if Input.gamepad_connected?(0)
      score_str = "SCORE: #{@player.score}  FPS: #{Window.fps.to_i}  [PAD: CONNECTED]"
    else
      score_str = "SCORE: #{@player.score}  FPS: #{Window.fps.to_i}"
    end
    Window.draw_text(20.0, 20.0, score_str, font: Font::SINCLAIR, size: 24, color: Color::WHITE)

    if @game_state == 1
      # 半透明暗幕 (58% 黒)
      Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG)
      
      # タイトル (18文字 * 32px = 576px -> (1280 - 576) / 2 = 352)
      Window.draw_text(352.0, 150.0, "--- SKILL MENU ---", font: Font::SINCLAIR, size: 32, color: Color::WHITE)
      
      mx = Input.mouse_x
      my = Input.mouse_y
      hover1 = mx >= 140.0 && mx <= 1140.0 && my >= 245.0 && my <= 290.0
      hover2 = mx >= 140.0 && mx <= 1140.0 && my >= 295.0 && my <= 340.0
      hover3 = mx >= 140.0 && mx <= 1140.0 && my >= 345.0 && my <= 390.0
      hover4 = mx >= 140.0 && mx <= 1140.0 && my >= 395.0 && my <= 440.0

      Window.draw_rect(140.0, 245.0, 1000.0, 45.0, color: COLOR_BUTTON_HOVER) if hover1
      Window.draw_rect(140.0, 295.0, 1000.0, 45.0, color: COLOR_BUTTON_HOVER) if hover2
      Window.draw_rect(140.0, 345.0, 1000.0, 45.0, color: COLOR_BUTTON_HOVER) if hover3
      Window.draw_rect(140.0, 395.0, 1000.0, 45.0, color: COLOR_BUTTON_HOVER) if hover4

      shape_cost = (@player.sides - 2) * 100
      t1 = "[1/A]  Upgrade Shape (Cost: #{shape_cost}) -> Sides: #{@player.sides + 1}"
      t2 = "[2/X]  Speed Up      (Cost: 50) -> Speed: #{(@player.speed + 1.0).to_i}"
      t3 = "[3/Y]  Fire Rate Up  (Cost: 50)"
      t4 = "[4/RB] Magnet Radius (Cost: 50) -> Range: #{(@player.magnet_radius + 50.0).to_i}"

      # リストテキスト (最長48文字 * 20px = 960px -> 開始x=160, 終了x=1120, 中心=640)
      Window.draw_text(160.0, 255.0, t1, font: Font::SINCLAIR, size: 20, color: @player.score >= shape_cost ? Color::WHITE : COLOR_TEXT_GRAY)
      Window.draw_text(160.0, 305.0, t2, font: Font::SINCLAIR, size: 20, color: @player.score >= 50 ? Color::WHITE : COLOR_TEXT_GRAY)
      Window.draw_text(160.0, 355.0, t3, font: Font::SINCLAIR, size: 20, color: (@player.score >= 50 && @player.fire_rate > 2) ? Color::WHITE : COLOR_TEXT_GRAY)
      Window.draw_text(160.0, 405.0, t4, font: Font::SINCLAIR, size: 20, color: @player.score >= 50 ? Color::WHITE : COLOR_TEXT_GRAY)
      
      # フッター (42文字 * 16px = 672px -> (1280 - 672) / 2 = 304)
      Window.draw_text(304.0, 500.0, "Right Click / ESC / START / (B) to Resume", font: Font::SINCLAIR, size: 16, color: COLOR_TEXT_GRAY)
    end
  end
end

game = Game.new
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo Survival Shooting Game") do
  game.update_draw_frame
  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "Game test completed successfully! (#{frame_count} frames)"
      exit
    end
  end
end

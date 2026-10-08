# frozen_string_literal: true

require_relative '../lib/zenoo'

# 事前定義カラー定数
COLOR_ORANGE       = Color.new(255, 161, 0)
COLOR_HP_GRAY      = Color.new(130, 130, 130)
COLOR_GRID_DARK    = Color.new(50, 50, 60)
COLOR_MENU_BG      = Color.new(0, 0, 0, 180)
COLOR_BUTTON_HOVER = Color.new(70, 70, 80)
COLOR_TEXT_GRAY    = Color.new(140, 140, 140)
COLOR_PURPLE       = Color.new(210, 60, 255)
COLOR_EXP_GREEN    = Color.new(50, 255, 130)

# ==========================================
# 1. パーティクル & エフェクト (短命GCオブジェクト)
# ==========================================
class Particle
  attr_reader :dead

  def initialize(x, y, vx, vy, life, color, size = 6.0)
    @x = x.to_f
    @y = y.to_f
    @vx = vx.to_f
    @vy = vy.to_f
    @life = life
    @max_life = life
    @color = color
    @size = size.to_f
    @dead = false
  end

  def update
    @x += @vx
    @y += @vy
    @vx *= 0.94
    @vy *= 0.94
    @life -= 1
    @dead = true if @life <= 0
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy
    s = (@life.to_f / @max_life) * @size
    Window.draw_rect(sx - s * 0.5, sy - s * 0.5, s, s, color: @color)
  end
end

# 敵頭上に飛び出すダメージ数値ポップアップ
class DamageText
  attr_reader :dead

  def initialize(x, y, text, color = Color::WHITE)
    @x = x.to_f + (rand(16) - 8).to_f
    @y = y.to_f
    @text = text.to_s
    @color = color
    @life = 25
    @dead = false
  end

  def update
    @y -= 1.2
    @life -= 1
    @dead = true if @life <= 0
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy
    Window.draw_text(sx, sy, @text, font: Font::SINCLAIR, size: 18, color: @color)
  end
end

# ==========================================
# 2. 弾 & 近接武器 (Bullet, Missile, Orbiter)
# ==========================================
class Bullet
  attr_accessor :x, :y, :vx, :vy, :dead, :damage

  def initialize(x, y, angle, speed = 16.0, damage = 1)
    @x = x.to_f
    @y = y.to_f
    @vx = speed * Math.cos(angle)
    @vy = speed * Math.sin(angle)
    @damage = damage
    @traveled = 0.0
    @dead = false
  end

  def update
    @x += @vx
    @y += @vy
    @traveled += 16.0
    @dead = true if @traveled > 1400.0
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy
    Window.draw_rect(sx - 2.5, sy - 2.5, 5.0, 5.0, color: Color::CYAN)
  end
end

# 追尾＆着弾範囲爆発ミサイル
class Missile
  attr_accessor :x, :y, :vx, :vy, :dead, :damage, :exploded

  def initialize(x, y, target_x, target_y)
    @x = x.to_f
    @y = y.to_f
    dx = target_x - x
    dy = target_y - y
    angle = Math.atan2(dy, dx)
    @speed = 10.0
    @vx = @speed * Math.cos(angle)
    @vy = @speed * Math.sin(angle)
    @damage = 12
    @life = 90
    @dead = false
    @exploded = false
  end

  def update(enemies)
    @life -= 1
    if @life <= 0
      @dead = true
      @exploded = true
      return
    end

    nearest = nil
    min_d2 = 600.0 * 600.0
    enemies.each do |e|
      next if e.dead
      dx = e.x - @x
      dy = e.y - @y
      d2 = dx * dx + dy * dy
      if d2 < min_d2
        min_d2 = d2
        nearest = e
      end
    end

    if nearest
      angle = Math.atan2(nearest.y - @y, nearest.x - @x)
      @vx += Math.cos(angle) * 0.7
      @vy += Math.sin(angle) * 0.7
      speed = Math.sqrt(@vx * @vx + @vy * @vy)
      if speed > 11.0
        @vx = (@vx / speed) * 11.0
        @vy = (@vy / speed) * 11.0
      end
    end

    @x += @vx
    @y += @vy
  end

  def explode
    @dead = true
    @exploded = true
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy
    Window.draw_rect(sx - 4.0, sy - 4.0, 8.0, 8.0, color: Color::RED)
  end
end

# 自機周囲を旋回する近接シールド刃
class Orbiter
  attr_accessor :x, :y, :damage

  def initialize(index, total)
    @index = index
    @total = total
    @radius = 85.0
    @angle = index * (2.0 * Math::PI / total)
    @speed = 0.08
    @damage = 2
    @x = 0.0
    @y = 0.0
  end

  def update(px, py)
    @angle += @speed
    @x = px + @radius * Math.cos(@angle)
    @y = py + @radius * Math.sin(@angle)
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy
    Window.draw_rect(sx - 6.0, sy - 6.0, 12.0, 12.0, color: Color::CYAN)
    Window.draw_rect(sx - 3.0, sy - 3.0, 6.0, 6.0, color: Color::WHITE)
  end
end

# ==========================================
# 3. ドロップアイテム (EXPジェム)
# ==========================================
class Item
  attr_accessor :x, :y, :dead, :value

  def initialize(x, y, value = 10)
    @x = x.to_f
    @y = y.to_f
    @value = value
    @life = 600
    @dead = false
  end

  def update(px, py, magnet_radius)
    @life -= 1
    if @life <= 0
      @dead = true
      return
    end

    dx = px - @x
    dy = py - @y
    dist_sq = dx * dx + dy * dy
    if dist_sq < magnet_radius * magnet_radius
      dist = Math.sqrt(dist_sq)
      if dist > 0.1
        speed = 14.0
        @x += (dx / dist) * speed
        @y += (dy / dist) * speed
      end
    end
  end

  def draw(cx, cy)
    return if @life < 100 && (@life % 10) < 5
    sx = @x - cx
    sy = @y - cy
    c = @value > 10 ? COLOR_EXP_GREEN : Color::YELLOW
    s = @value > 10 ? 12.0 : 8.0
    Window.draw_rect(sx - s * 0.5, sy - s * 0.5, s, s, color: c)
  end
end

# ==========================================
# 4. 敵キャラクター (Enemy)
# ==========================================
class Enemy
  attr_accessor :x, :y, :radius, :hp, :max_hp, :speed, :sides, :color, :score_value, :dead, :is_boss

  def initialize(px, py, type = :normal)
    edge = rand(4)
    if edge == 0
      @x = px + (rand(1400) - 700).to_f
      @y = py - 420.0
    elsif edge == 1
      @x = px + (rand(1400) - 700).to_f
      @y = py + 420.0
    elsif edge == 2
      @x = px - 720.0
      @y = py + (rand(900) - 450).to_f
    else
      @x = px + 720.0
      @y = py + (rand(900) - 450).to_f
    end

    @dead = false
    @rotation = 0.0
    @is_boss = false

    case type
    when :fast
      @sides = 3
      @radius = 12.0
      @hp = 1
      @max_hp = 1
      @speed = 3.4
      @color = Color::YELLOW
      @score_value = 10
    when :elite
      @sides = 5
      @radius = 32.0
      @hp = 20
      @max_hp = 20
      @speed = 1.4
      @color = Color::RED
      @score_value = 50
    when :boss
      @sides = 8
      @radius = 70.0
      @hp = 160
      @max_hp = 160
      @speed = 0.85
      @color = COLOR_PURPLE
      @score_value = 300
      @is_boss = true
    else
      @sides = 4
      @radius = 18.0
      @hp = 3
      @max_hp = 3
      @speed = 2.0
      @color = Color::BLUE
      @score_value = 20
    end
  end

  def update(px, py)
    angle = Math.atan2(py - @y, px - @x)
    @x += @speed * Math.cos(angle)
    @y += @speed * Math.sin(angle)
    @rotation += 0.03
  end

  def draw(cx, cy)
    sx = @x - cx
    sy = @y - cy

    @sides.times do |i|
      a1 = @rotation + i * (2.0 * Math::PI / @sides)
      a2 = @rotation + ((i + 1) % @sides) * (2.0 * Math::PI / @sides)
      vx1 = sx + @radius * Math.cos(a1)
      vy1 = sy + @radius * Math.sin(a1)
      vx2 = sx + @radius * Math.cos(a2)
      vy2 = sy + @radius * Math.sin(a2)
      Window.draw_triangle(sx, sy, vx2, vy2, vx1, vy1, color: @color)
      Window.draw_line(vx1, vy1, vx2, vy2, color: Color::WHITE, width: @is_boss ? 2.0 : 1.0)
    end

    if @max_hp > 1
      bar_w = @radius * 2.0
      bar_h = @is_boss ? 8.0 : 5.0
      bar_y = sy - @radius - (@is_boss ? 18.0 : 12.0)
      hp_ratio = @hp.to_f / @max_hp
      hp_ratio = 0.0 if hp_ratio < 0.0
      Window.draw_rect(sx - bar_w * 0.5, bar_y, bar_w, bar_h, color: COLOR_HP_GRAY)
      hp_color = @is_boss ? Color.new(255, 60, 100) : Color::GREEN
      Window.draw_rect(sx - bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h, color: hp_color)
    end
  end
end

# ==========================================
# 5. プレイヤー (Player)
# ==========================================
class Player
  attr_accessor :x, :y, :radius, :sides, :rotation, :speed, :fire_timer, :fire_rate,
                :score, :magnet_radius, :shot_level, :orbiter_count, :missile_level,
                :missile_timer, :orbiters

  def initialize(x, y)
    @x = x.to_f
    @y = y.to_f
    @radius = 28.0
    @sides = 3
    @rotation = 0.0
    @speed = 5.0
    @fire_timer = 0
    @fire_rate = 10
    @score = 0
    @magnet_radius = 160.0
    @shot_level = 1
    @orbiter_count = 0
    @missile_level = 0
    @missile_timer = 0
    @orbiters = []
  end

  def rebuild_orbiters
    @orbiters = []
    @orbiter_count.times do |i|
      @orbiters << Orbiter.new(i, @orbiter_count)
    end
  end

  def update(bullets, missiles, enemies, particles)
    # 移動
    @x += Input.x * @speed
    @y += Input.y * @speed

    cx = @x - 1280.0 / 2.0
    cy = @y - 720.0 / 2.0
    mx = Input.mouse_x + cx
    my = Input.mouse_y + cy

    # マウス追従
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

    # 照準
    rx = Input.rx
    ry = Input.ry
    if rx != 0.0 || ry != 0.0
      @rotation = Math.atan2(ry, rx)
    else
      @rotation = Math.atan2(my - @y, mx - @x)
    end

    # メインショット発射
    if @fire_timer > 0
      @fire_timer -= 1
    else
      @fire_timer = @fire_rate
      fire_shots(bullets, particles)
    end

    # ミサイル自動発射
    if @missile_level > 0
      @missile_timer -= 1
      if @missile_timer <= 0
        @missile_timer = 45 - (@missile_level * 5)
        nearest_enemy = nil
        min_dist_sq = 1_000_000_000.0
        enemies.each do |e|
          next if e.dead
          dx = e.x - @x
          dy = e.y - @y
          d2 = dx * dx + dy * dy
          if d2 < min_dist_sq
            min_dist_sq = d2
            nearest_enemy = e
          end
        end
        if nearest_enemy
          missiles << Missile.new(@x, @y, nearest_enemy.x, nearest_enemy.y)
        end
      end
    end

    # オービター更新
    @orbiters.each { |orb| orb.update(@x, @y) }
  end

  def fire_shots(bullets, particles)
    # 1. 正面頂点からのショット (shot_level に応じた WAY 拡散)
    front_ang = @rotation
    front_vx = @x + @radius * Math.cos(front_ang)
    front_vy = @y + @radius * Math.sin(front_ang)

    front_angles = []
    case @shot_level
    when 1
      front_angles << front_ang
    when 2
      front_angles << (front_ang - 0.15)
      front_angles << (front_ang + 0.15)
    when 3
      front_angles << (front_ang - 0.25)
      front_angles << front_ang
      front_angles << (front_ang + 0.25)
    when 4
      front_angles << (front_ang - 0.35)
      front_angles << (front_ang - 0.15)
      front_angles << (front_ang + 0.15)
      front_angles << (front_ang + 0.35)
    else # 5以上
      front_angles << (front_ang - 0.4)
      front_angles << (front_ang - 0.2)
      front_angles << front_ang
      front_angles << (front_ang + 0.2)
      front_angles << (front_ang + 0.4)
    end

    front_angles.each do |ang|
      bullets << Bullet.new(front_vx, front_vy, ang)
      particles << Particle.new(front_vx, front_vy, Math.cos(ang) * 4.0, Math.sin(ang) * 4.0, 8, Color::YELLOW, 3.0)
    end

    # 2. 正面以外の各頂点からも発射 (三角形なら残り2頂点、四角形なら残り3頂点...)
    if @sides > 1
      (@sides - 1).times do |t|
        i = t + 1
        ang = @rotation + i.to_f * (2.0 * Math::PI / @sides.to_f)
        vx = @x + @radius * Math.cos(ang)
        vy = @y + @radius * Math.sin(ang)
        bullets << Bullet.new(vx, vy, ang)
        particles << Particle.new(vx, vy, Math.cos(ang) * 4.0, Math.sin(ang) * 4.0, 8, Color::YELLOW, 3.0)
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

      Window.draw_triangle(sx, sy, vx2, vy2, vx1, vy1, color: Color::GREEN)
      Window.draw_line(vx1, vy1, vx2, vy2, color: Color::WHITE)
      Window.draw_rect(vx1 - 2.0, vy1 - 2.0, 4.0, 4.0, color: Color::WHITE)
    end

    @orbiters.each { |orb| orb.draw(cx, cy) }
  end
end

# ==========================================
# 6. メインゲーム (Game)
# ==========================================
class Game
  attr_accessor :player, :bullets, :missiles, :enemies, :items, :particles, :damage_texts, :game_state

  def initialize
    @player = Player.new(1280.0 / 2.0, 720.0 / 2.0)
    @bullets = []
    @missiles = []
    @enemies = []
    @items = []
    @particles = []
    @damage_texts = []
    @game_state = 0 # 0: プレイ中, 1: スキルメニュー
    @menu_cursor = 0
    @stick_prev_up = false
    @stick_prev_down = false
    @spawn_timer = 0
    @spawn_interval = 50.0
    @boss_spawn_timer = 1200 # 20秒ごとに出現
  end

  def spawn_enemies
    if @spawn_interval > 8.0
      @spawn_interval -= 0.015
    end

    @spawn_timer -= 1
    if @spawn_timer <= 0
      @spawn_timer = @spawn_interval.to_i
      r = rand(100)
      if r < 40
        @enemies << Enemy.new(@player.x, @player.y, :fast)
      elsif r < 80
        @enemies << Enemy.new(@player.x, @player.y, :normal)
      else
        @enemies << Enemy.new(@player.x, @player.y, :elite)
      end
    end

    @boss_spawn_timer -= 1
    if @boss_spawn_timer <= 0
      @boss_spawn_timer = 1500 # 25秒ごと
      @enemies << Enemy.new(@player.x, @player.y, :boss)
    end
  end

  def check_collisions
    player_hit = false
    boss_hit = false

    # 1. 弾 vs 敵
    @enemies.each do |e|
      next if e.dead

      # 自機との接触判定
      p_dx = @player.x - e.x
      p_dy = @player.y - e.y
      p_dist_sq = p_dx * p_dx + p_dy * p_dy
      p_hit_dist = @player.radius + e.radius
      if p_dist_sq < p_hit_dist * p_hit_dist
        player_hit = true
        boss_hit = true if e.is_boss
      end

      # オービター刃 vs 敵
      @player.orbiters.each do |orb|
        o_dx = orb.x - e.x
        o_dy = orb.y - e.y
        if o_dx * o_dx + o_dy * o_dy < (e.radius + 12.0)**2
          damage_enemy(e, orb.damage, Color::CYAN)
        end
      end

      # 通常弾 vs 敵
      @bullets.each do |b|
        next if b.dead
        dx = e.x - b.x
        dy = e.y - b.y
        if dx * dx + dy * dy < (e.radius + 3.0)**2
          b.dead = true
          damage_enemy(e, b.damage, Color::YELLOW)
          break if e.dead
        end
      end

      # ミサイル直撃 vs 敵
      @missiles.each do |m|
        next if m.dead
        dx = e.x - m.x
        dy = e.y - m.y
        if dx * dx + dy * dy < (e.radius + 8.0)**2
          m.explode
        end
      end
    end

    # 2. ミサイルの範囲爆発処理
    @missiles.each do |m|
      if m.exploded
        m.exploded = false
        create_explosion(m.x, m.y, 65.0, m.damage)
      end
    end

    # 3. 振動フィードバック
    if player_hit
      if boss_hit
        Input.vibrate_gamepad(0, 1.0, 1.0, 0.15) # ボス接触は特大振動
      else
        Input.vibrate_gamepad(0, 0.7, 0.7, 0.1)  # 通常接触
      end
      Input.vibrate(0.1)
    end

    # 4. アイテム取得判定
    @items.each do |item|
      next if item.dead
      dx = @player.x - item.x
      dy = @player.y - item.y
      if dx * dx + dy * dy < 40.0 * 40.0
        item.dead = true
        @player.score += item.value
        # 取得キラキラパーティクル
        @particles << Particle.new(item.x, item.y, (rand(4) - 2).to_f, (rand(4) - 2).to_f, 12, COLOR_EXP_GREEN, 4.0)
      end
    end
  end

  def damage_enemy(e, dmg, text_color)
    e.hp -= dmg
    @damage_texts << DamageText.new(e.x, e.y - e.radius, dmg, text_color)
    # 被弾スパーク
    3.times do
      @particles << Particle.new(e.x, e.y, (rand(6) - 3).to_f, (rand(6) - 3).to_f, 10, Color::WHITE, 3.0)
    end

    if e.hp <= 0
      e.dead = true
      kill_enemy(e)
    end
  end

  def kill_enemy(e)
    if e.is_boss
      # ボス撃破：大爆発＆大量ジェム
      60.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(10).to_f + 2.0
        @particles << Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(30) + 20, COLOR_PURPLE, 10.0)
      end
      12.times do
        @items << Item.new(e.x + (rand(80) - 40).to_f, e.y + (rand(80) - 40).to_f, 30)
      end
    elsif e.max_hp > 5
      # エリート撃破
      25.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(7).to_f + 2.0
        @particles << Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(20) + 15, Color::RED, 7.0)
      end
      4.times do
        @items << Item.new(e.x + (rand(40) - 20).to_f, e.y + (rand(40) - 20).to_f, 20)
      end
    else
      # 通常・チビ撃破
      12.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(5).to_f + 2.0
        @particles << Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(15) + 10, COLOR_ORANGE, 5.0)
      end
      @items << Item.new(e.x, e.y, 10)
    end
  end

  def create_explosion(x, y, radius, damage)
    # 爆発パーティクル
    25.times do
      ang = rand(360) * Math::PI / 180.0
      spd = rand(8).to_f + 2.0
      @particles << Particle.new(x, y, spd * Math.cos(ang), spd * Math.sin(ang), rand(20) + 10, Color::RED, 8.0)
    end
    # 範囲内の敵全員にダメージ
    @enemies.each do |e|
      next if e.dead
      dx = e.x - x
      dy = e.y - y
      if dx * dx + dy * dy < radius * radius
        damage_enemy(e, damage, COLOR_ORANGE)
      end
    end
  end

  def update_draw_frame
    esc_pressed = Input.key_push?(:escape)
    right_clicked = Input.mouse_push?(:right)
    start_pressed = Input.gamepad_button_push?(:start) || Input.gamepad_button_push?(:back)
    b_pressed = (@game_state == 1) && Input.gamepad_button_push?(:b)

    if esc_pressed || right_clicked || start_pressed || b_pressed
      @game_state = (@game_state == 0 ? 1 : 0)
    end

    if @game_state == 0
      # 1. 敵スポーン
      spawn_enemies

      # 2. オブジェクト更新
      @player.update(@bullets, @missiles, @enemies, @particles)
      @bullets.each { |b| b.update }
      @missiles.each { |m| m.update(@enemies) }
      @enemies.each { |e| e.update(@player.x, @player.y) }
      @items.each { |i| i.update(@player.x, @player.y, @player.magnet_radius) }
      @particles.each { |p| p.update }
      @damage_texts.each { |t| t.update }

      # 3. 当たり判定
      check_collisions

      # 4. オブジェクトの自然なGC回収 (delete_if)
      @bullets.delete_if { |b| b.dead }
      @missiles.delete_if { |m| m.dead }
      @enemies.delete_if { |e| e.dead }
      @items.delete_if { |i| i.dead }
      @particles.delete_if { |p| p.dead }
      @damage_texts.delete_if { |t| t.dead }
    elsif @game_state == 1
      handle_skill_menu
    end

    draw_game
  end

  def handle_skill_menu
    # 上下選択入力 (十字キー / WSキー / 上下矢印 / 左スティック)
    up_pressed = Input.key_push?(:up) || Input.key_push?(:w) || Input.gamepad_button_push?(:dpad_up)
    down_pressed = Input.key_push?(:down) || Input.key_push?(:s) || Input.gamepad_button_push?(:dpad_down)

    stick_y = Input.y
    if stick_y < -0.4
      up_pressed = true unless @stick_prev_up
      @stick_prev_up = true
    else
      @stick_prev_up = false
    end
    if stick_y > 0.4
      down_pressed = true unless @stick_prev_down
      @stick_prev_down = true
    else
      @stick_prev_down = false
    end

    if up_pressed
      @menu_cursor = (@menu_cursor - 1) % 7
    elsif down_pressed
      @menu_cursor = (@menu_cursor + 1) % 7
    end

    # マウスによる選択（ホバー）
    mx = Input.mouse_x
    my = Input.mouse_y
    mouse_hover_idx = -1
    7.times do |i|
      top = 205.0 + (i.to_f * 45.0)
      if mx >= 140.0 && mx <= 1140.0 && my >= top && my <= top + 40.0
        mouse_hover_idx = i
        @menu_cursor = i
        break
      end
    end

    # 決定（購入）操作: ゲームパッド A, キーボード Enter/Space/Z, またはマウス左クリック
    buy_pressed = Input.gamepad_button_push?(:a) || Input.key_push?(:enter) || Input.key_push?(:space) || Input.key_push?(:z)
    if mouse_hover_idx >= 0 && Input.mouse_push?(:left)
      buy_pressed = true
    end

    return unless buy_pressed

    execute_skill_upgrade(@menu_cursor)
  end

  def execute_skill_upgrade(idx)
    shape_cost = (@player.sides - 2) * 100
    shot_cost = @player.shot_level * 80
    orbiter_cost = (@player.orbiter_count + 1) * 70
    missile_cost = (@player.missile_level + 1) * 90

    case idx
    when 0 # 形状強化
      if @player.score >= shape_cost
        @player.score -= shape_cost
        @player.sides += 1
      end
    when 1 # 拡散ショット
      if @player.score >= shot_cost && @player.shot_level < 5
        @player.score -= shot_cost
        @player.shot_level += 1
      end
    when 2 # 近接回転刃 (オービター)
      if @player.score >= orbiter_cost && @player.orbiter_count < 4
        @player.score -= orbiter_cost
        @player.orbiter_count += 1
        @player.rebuild_orbiters
      end
    when 3 # 追尾爆発ミサイル
      if @player.score >= missile_cost && @player.missile_level < 3
        @player.score -= missile_cost
        @player.missile_level += 1
      end
    when 4 # 移動速度
      if @player.score >= 50
        @player.score -= 50
        @player.speed += 1.0
      end
    when 5 # 連射速度 (下限 3 を限度とする)
      if @player.score >= 50 && @player.fire_rate > 3
        @player.score -= 50
        @player.fire_rate -= 2
        @player.fire_rate = 3 if @player.fire_rate < 3
      end
    when 6 # 磁石範囲
      if @player.score >= 50
        @player.score -= 50
        @player.magnet_radius += 50.0
      end
    end
  end

  def draw_game
    Window.clear(Color::BLACK)

    cx = @player.x - 1280.0 / 2.0
    cy = @player.y - 720.0 / 2.0

    # 背景グリッド
    grid_size = 100.0
    offset_x = -(cx.to_i % 100).to_f
    offset_y = -(cy.to_i % 100).to_f

    x = offset_x
    while x < 1280.0
      Window.draw_line(x, 0.0, x, 720.0, color: COLOR_GRID_DARK)
      x += grid_size
    end

    y = offset_y
    while y < 720.0
      Window.draw_line(0.0, y, 1280.0, y, color: COLOR_GRID_DARK)
      y += grid_size
    end

    # オブジェクト描画
    @items.each { |i| i.draw(cx, cy) }
    @particles.each { |p| p.draw(cx, cy) }
    @enemies.each { |e| e.draw(cx, cy) }
    @bullets.each { |b| b.draw(cx, cy) }
    @missiles.each { |m| m.draw(cx, cy) }
    @player.draw(cx, cy)
    @damage_texts.each { |d| d.draw(cx, cy) }

    # HUD (UI)
    entities_count = @bullets.size + @missiles.size + @enemies.size + @items.size + @particles.size + @damage_texts.size
    pad_str = Input.gamepad_connected?(0) ? "[PAD: ON]" : "[PAD: OFF]"
    hud_str = "SCORE: #{@player.score}  FPS: #{Window.fps.to_i}  OBJECTS: #{entities_count}  #{pad_str}"
    Window.draw_text(20.0, 20.0, hud_str, font: Font::SINCLAIR, size: 24, color: Color::WHITE)

    # スキルメニュー画面
    if @game_state == 1
      draw_skill_menu
    end
  end

  def draw_skill_menu
    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG)
    Window.draw_text(420.0, 130.0, "=== UPGRADE SKILLS ===", font: Font::SINCLAIR, size: 32, color: Color::WHITE)

    shape_cost = (@player.sides - 2) * 100
    shot_cost = @player.shot_level * 80
    orbiter_cost = (@player.orbiter_count + 1) * 70
    missile_cost = (@player.missile_level + 1) * 90

    next_rate = @player.fire_rate - 2
    next_rate = 3 if next_rate < 3
    fire_rate_str = @player.fire_rate <= 3 ? "MAX" : "#{next_rate}"

    labels = [
      "Upgrade Shape  (Cost: #{shape_cost}) -> Sides: #{@player.sides + 1}",
      "Spread Shot    (Cost: #{shot_cost}) -> Way: #{@player.shot_level >= 5 ? 'MAX' : @player.shot_level + 1}",
      "Energy Orbiter (Cost: #{orbiter_cost}) -> Blades: #{@player.orbiter_count >= 4 ? 'MAX' : @player.orbiter_count + 1}",
      "Homing Missile (Cost: #{missile_cost}) -> Level: #{@player.missile_level >= 3 ? 'MAX' : @player.missile_level + 1}",
      "Speed Up       (Cost: 50) -> Speed: #{@player.speed.to_i + 1}",
      "Fire Rate Up   (Cost: 50) -> Rate: #{fire_rate_str}",
      "Magnet Radius  (Cost: 50) -> Range: #{@player.magnet_radius.to_i + 50}"
    ]

    can_buys = [
      @player.score >= shape_cost,
      @player.score >= shot_cost && @player.shot_level < 5,
      @player.score >= orbiter_cost && @player.orbiter_count < 4,
      @player.score >= missile_cost && @player.missile_level < 3,
      @player.score >= 50,
      @player.score >= 50 && @player.fire_rate > 3,
      @player.score >= 50
    ]

    7.times do |i|
      top = 205.0 + (i.to_f * 45.0)
      is_selected = (@menu_cursor == i)

      if is_selected
        Window.draw_rect(140.0, top, 1000.0, 40.0, color: COLOR_BUTTON_HOVER)
        Window.draw_rect(136.0, top, 4.0, 40.0, color: Color::CYAN)
      end

      prefix = is_selected ? "> " : "  "
      text = "#{prefix}#{labels[i]}"

      c = if can_buys[i]
            is_selected ? Color::CYAN : Color::WHITE
          else
            COLOR_TEXT_GRAY
          end

      Window.draw_text(160.0, top + 10.0, text, font: Font::SINCLAIR, size: 20, color: c)
    end

    Window.draw_text(290.0, 545.0, "[UP/DOWN/Stick] Select   [A / ENTER / Click] Purchase", font: Font::SINCLAIR, size: 20, color: Color::WHITE)
    Window.draw_text(330.0, 585.0, "Right Click / ESC / START / (B) to Resume Game", font: Font::SINCLAIR, size: 18, color: COLOR_TEXT_GRAY)
  end
end

# ==========================================
# 7. メインループ
# ==========================================
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

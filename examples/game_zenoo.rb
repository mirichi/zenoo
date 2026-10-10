# frozen_string_literal: true

require_relative '../lib/zenoo'

# レトロCRTブラウン管シェーダー (スキャンライン・樽型歪み・色収差・ビネット)
CRT_FRAGMENT_SHADER = <<~'GLSL'
#version 330 core
in vec4 v_color;
in vec2 v_uv;
uniform sampler2D u_texture;
out vec4 fragColor;

// 樽型歪み (CRTブラウン管の曲面ガラス)
vec2 crt_curve(vec2 uv) {
    vec2 cc = uv - 0.5;
    float dist = dot(cc, cc);
    return 0.5 + cc * (1.0 + 0.12 * dist + 0.06 * dist * dist);
}

void main() {
    vec2 uv = crt_curve(v_uv);

    // 画面外は黒 (ベゼル枠)
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // 色収差 (RGBチャンネル微小ズレ)
    float r = texture(u_texture, crt_curve(v_uv - vec2(0.0012, 0.0))).r;
    float g = texture(u_texture, uv).g;
    float b = texture(u_texture, crt_curve(v_uv + vec2(0.0012, 0.0))).b;
    vec3 col = vec3(r, g, b);

    // スキャンライン (黒い横走査線)
    // 240本の走査線 (レトロアーケード/CRTスタイル)
    float scan = sin(uv.y * 240.0 * 6.2831853);
    float scan_weight = clamp(0.5 + 0.5 * scan, 0.0, 1.0);
    // 黒い隙間をしっかり暗く (0.20)
    col *= mix(0.20, 1.15, pow(scan_weight, 0.75));

    // ブラウン管の微小発光 (黒い背景でも走査線の存在感が微かにわかる)
    col += vec3(0.010) * scan_weight;

    // ビネット (四隅の周辺減光)
    vec2 vig_uv = uv * (1.0 - uv.yx);
    float vig = vig_uv.x * vig_uv.y * 15.0;
    vig = clamp(pow(vig, 0.22), 0.0, 1.0);
    col *= vig;

    fragColor = vec4(col, 1.0);
}
GLSL

# 事前定義カラー定数
COLOR_ORANGE       = Color.new(255, 161, 0)
COLOR_HP_GRAY      = Color.new(130, 130, 130)
COLOR_GRID_DARK    = Color.new(50, 50, 60)
COLOR_MENU_BG      = Color.new(0, 0, 0, 180)
COLOR_BUTTON_HOVER = Color.new(70, 70, 80)
COLOR_TEXT_GRAY    = Color.new(140, 140, 140)
COLOR_PURPLE       = Color.new(210, 60, 255)
COLOR_EXP_GREEN    = Color.new(50, 255, 130)
COLOR_HEART_RED    = Color.new(255, 70, 90)
COLOR_EXP_BAR_BG   = Color.new(30, 40, 35)

# ゲーム状態
STATE_PLAY     = 0 # プレイ中
STATE_PAUSE    = 1 # ポーズ (ステータス確認)
STATE_TITLE    = 2 # タイトル画面
STATE_LEVELUP  = 3 # レベルアップ 3 択
STATE_GAMEOVER = 4 # リザルト画面

# アップグレード種別数 (0..7)
UPGRADE_COUNT = 8

# オブジェクト上限 (描画キュー・メモリ保護)
MAX_PARTICLES    = 250
MAX_DAMAGE_TEXTS = 60

# ==========================================
# 0. 効果音 (SoundEffect で起動時に波形生成)
# ==========================================
class Sfx
  SHOT      = 0
  HIT       = 1
  KILL      = 2
  EXPLODE   = 3
  GEM       = 4
  LEVELUP   = 5
  DAMAGE    = 6
  BOSS_KILL = 7
  HEAL      = 8
  SELECT    = 9

  def initialize
    @sounds = [
      SoundEffect.sweep(1500, 700, 0.04, type: :square, volume: 0.10),
      SoundEffect.tone(180, 0.03, type: :square, volume: 0.12),
      SoundEffect.sweep(600, 120, 0.12, type: :square, volume: 0.22),
      SoundEffect.noise(0.30, volume: 0.40, release: 0.25),
      SoundEffect.tone(1320, 0.05, type: :triangle, volume: 0.22),
      SoundEffect.sweep(400, 1300, 0.35, type: :square, volume: 0.25),
      SoundEffect.sweep(320, 50, 0.30, type: :sawtooth, volume: 0.50),
      SoundEffect.noise(0.90, volume: 0.70, release: 0.70),
      SoundEffect.sweep(600, 1000, 0.20, type: :triangle, volume: 0.35),
      SoundEffect.tone(880, 0.04, type: :square, volume: 0.15)
    ]
    # 同一フレームでの多重再生を防ぐクールダウン (フレーム数)
    @cooldowns = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  end

  def tick
    i = 0
    while i < @cooldowns.size
      @cooldowns[i] -= 1 if @cooldowns[i] > 0
      i += 1
    end
  end

  def play(id, cooldown = 2)
    return if @cooldowns[id] > 0
    @cooldowns[id] = cooldown
    @sounds[id].play
  end
end

# ==========================================
# 1. パーティクル & エフェクト (短命GCオブジェクト)
# ==========================================
class Particle
  attr_reader :dead, :x, :y

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

  def draw
    s = (@life.to_f / @max_life) * @size
    Window.draw_rect(@x - s * 0.5, @y - s * 0.5, s, s, color: @color)
  end
end

# 敵頭上に飛び出すダメージ数値ポップアップ
class DamageText
  attr_reader :dead, :x, :y

  def initialize(x, y, text, color = Color::WHITE, size = 18)
    @x = x.to_f + (rand(16) - 8).to_f
    @y = y.to_f
    @text = text.to_s
    @color = color
    @size = size
    @life = 25
    @dead = false
  end

  def update
    @y -= 1.2
    @life -= 1
    @dead = true if @life <= 0
  end

  def draw
    Window.draw_text(@x, @y, @text, font: Font::SINCLAIR, size: @size, color: @color)
  end
end

# ==========================================
# 2. 弾 & 近接武器 (Bullet, Missile, Orbiter)
# ==========================================
class Bullet
  attr_accessor :x, :y, :vx, :vy, :dead, :damage, :shape

  def initialize(x, y, angle, speed = 16.0, damage = 1)
    @x = x.to_f
    @y = y.to_f
    @vx = speed * Math.cos(angle)
    @vy = speed * Math.sin(angle)
    @damage = damage
    @traveled = 0.0
    @dead = false
    @shape = Collision.circle(@x, @y, 2.5)
  end

  def update
    @x += @vx
    @y += @vy
    @shape.x = @x
    @shape.y = @y
    @traveled += 16.0
    @dead = true if @traveled > 1400.0
  end

  def draw
    Window.draw_rect(@x - 2.5, @y - 2.5, 5.0, 5.0, color: Color::CYAN)
  end
end

# 追尾＆着弾範囲爆発ミサイル
class Missile
  attr_accessor :x, :y, :vx, :vy, :dead, :damage, :exploded, :shape

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
    @shape = Collision.circle(@x, @y, 4.0)
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
    @shape.x = @x
    @shape.y = @y
  end

  def explode
    @dead = true
    @exploded = true
  end

  def draw
    Window.draw_rect(@x - 4.0, @y - 4.0, 8.0, 8.0, color: Color::RED)
  end
end

# 自機周囲を旋回する近接シールド刃
class Orbiter
  attr_accessor :x, :y, :damage, :shape

  def initialize(index, total)
    @index = index
    @total = total
    @radius = 85.0
    @angle = index * (2.0 * Math::PI / total)
    @speed = 0.08
    @damage = 2
    @x = 0.0
    @y = 0.0
    @shape = Collision.circle(@x, @y, 6.0)
  end

  def update(px, py)
    @angle += @speed
    @x = px + @radius * Math.cos(@angle)
    @y = py + @radius * Math.sin(@angle)
    @shape.x = @x
    @shape.y = @y
  end

  def draw
    Window.draw_rect(@x - 6.0, @y - 6.0, 12.0, 12.0, color: Color::CYAN)
    Window.draw_rect(@x - 3.0, @y - 3.0, 6.0, 6.0, color: Color::WHITE)
  end
end

# ==========================================
# 3. ドロップアイテム (EXPジェム / 回復ハート)
# ==========================================
class Item
  attr_accessor :x, :y, :dead, :value, :kind

  # kind: 0 = EXPジェム, 1 = 回復ハート
  def initialize(x, y, value = 10, kind = 0)
    @x = x.to_f
    @y = y.to_f
    @value = value
    @kind = kind
    @life = kind == 1 ? 900 : 600
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

  def draw
    return if @life < 100 && (@life % 10) < 5
    if @kind == 1
      # 十字型のハート (回復)
      Window.draw_rect(@x - 9.0, @y - 3.0, 18.0, 6.0, color: COLOR_HEART_RED)
      Window.draw_rect(@x - 3.0, @y - 9.0, 6.0, 18.0, color: COLOR_HEART_RED)
      return
    end
    c = @value > 10 ? COLOR_EXP_GREEN : Color::YELLOW
    s = @value > 10 ? 12.0 : 8.0
    Window.draw_rect(@x - s * 0.5, @y - s * 0.5, s, s, color: c)
  end
end

# ==========================================
# 4. 敵キャラクター (Enemy)
# ==========================================
class Enemy
  attr_accessor :x, :y, :radius, :hp, :max_hp, :speed, :sides, :color, :score_value, :dead, :is_boss, :flash, :type, :shape, :hit_radius

  @atlas = nil
  @sprites = nil

  def self.atlas
    @atlas
  end

  def self.sprites
    @sprites
  end

  def self.init_atlas
    return if @atlas

    @atlas = Image.new(512, 256)
    @sprites = {}

    configs = {
      fast:   { sides: 3, radius: 12.0, color: Color::YELLOW, is_boss: false, size: 48,  x0: 0,   y: 0 },
      normal: { sides: 4, radius: 18.0, color: Color::BLUE,   is_boss: false, size: 48,  x0: 96,  y: 0 },
      elite:  { sides: 5, radius: 32.0, color: Color::RED,    is_boss: false, size: 80,  x0: 192, y: 0 },
      boss:   { sides: 8, radius: 70.0, color: COLOR_PURPLE,  is_boss: true,  size: 160, x0: 0,   y: 80 }
    }

    configs.each do |type, cfg|
      sz = cfg[:size]
      y = cfg[:y]
      line_w = cfg[:is_boss] ? 2.0 : 1.0

      # 通常スロット
      s_normal = @atlas.sub_image(cfg[:x0], y, sz, sz)
      bake_enemy_poly(s_normal, cfg[:sides], cfg[:radius], cfg[:color], line_w)

      # 白フラッシュスロット
      s_flash = @atlas.sub_image(cfg[:x0] + sz, y, sz, sz)
      bake_enemy_poly(s_flash, cfg[:sides], cfg[:radius], Color::WHITE, line_w)

      @sprites[type] = { false => s_normal, true => s_flash }
    end
  end

  def self.bake_enemy_poly(slot, sides, radius, fill_color, line_w)
    Image.render_to(slot) do
      Window.clear(Color.new(0, 0, 0, 0))
      cx = slot.width * 0.5
      cy = slot.height * 0.5
      step = 2.0 * Math::PI / sides
      verts = []
      sides.times do |i|
        a = i * step
        verts << [cx + radius * Math.cos(a), cy + radius * Math.sin(a)]
      end

      # 1. 三角形描画 (塗りつぶし)
      sides.times do |i|
        v1 = verts[i]
        v2 = verts[(i + 1) % sides]
        Window.draw_triangle(cx, cy, v2[0], v2[1], v1[0], v1[1], color: fill_color)
      end

      # 2. 外周線描画 (白枠)
      sides.times do |i|
        v1 = verts[i]
        v2 = verts[(i + 1) % sides]
        Window.draw_line(v1[0], v1[1], v2[0], v2[1], color: Color::WHITE, width: line_w)
      end
    end
  end

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
    @flash = 0 # 被弾時の白フラッシュ残りフレーム
    @type = type

    case type
    when :fast
      @sides = 3
      @radius = 12.0
      @hp = 1
      @max_hp = 1
      @speed = 3.4
      @color = Color::YELLOW
      @score_value = 10
      # 三角形の内接円 (6.0) は極小ですり抜けの原因となるため、見た目と当たりのバランスが良い 10.0 を採用
      @hit_radius = 10.0
    when :elite
      @sides = 5
      @radius = 32.0
      @hp = 20
      @max_hp = 20
      @speed = 1.4
      @color = Color::RED
      @score_value = 50
      @hit_radius = @radius * Math.cos(Math::PI / @sides)
    when :boss
      @sides = 8
      @radius = 70.0
      @hp = 160
      @max_hp = 160
      @speed = 0.85
      @color = COLOR_PURPLE
      @score_value = 300
      @is_boss = true
      @hit_radius = @radius * Math.cos(Math::PI / @sides)
    else
      @sides = 4
      @radius = 18.0
      @hp = 3
      @max_hp = 3
      @speed = 2.0
      @color = Color::BLUE
      @score_value = 20
      @hit_radius = @radius * Math.cos(Math::PI / @sides)
    end

    @shape = Collision.circle(@x, @y, @hit_radius)
  end

  def update(px, py)
    angle = Math.atan2(py - @y, px - @x)
    @x += @speed * Math.cos(angle)
    @y += @speed * Math.sin(angle)
    @rotation += 0.03
    @shape.x = @x
    @shape.y = @y
    @flash -= 1 if @flash > 0
  end

  def draw
    sprite = Enemy.sprites[@type][@flash > 0]
    Window.draw_image(@x, @y, sprite, angle: @rotation * (180.0 / Math::PI), pivot: :center, offset_mode: :center)

    if @max_hp > 1
      bar_w = @radius * 2.0
      bar_h = @is_boss ? 8.0 : 5.0
      bar_y = @y - @radius - (@is_boss ? 18.0 : 12.0)
      hp_ratio = @hp.to_f / @max_hp
      hp_ratio = 0.0 if hp_ratio < 0.0
      Window.draw_rect(@x - bar_w * 0.5, bar_y, bar_w, bar_h, color: COLOR_HP_GRAY, z: 1.0)
      hp_color = @is_boss ? Color.new(255, 60, 100) : Color::GREEN
      Window.draw_rect(@x - bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h, color: hp_color, z: 1.0)
    end
  end
end

# ==========================================
# 5. プレイヤー (Player)
# ==========================================
class Player
  attr_accessor :x, :y, :radius, :sides, :rotation, :speed, :fire_timer, :fire_rate,
                :score, :magnet_radius, :shot_level, :orbiter_count, :missile_level,
                :missile_timer, :orbiters,
                :hp, :max_hp, :invincible, :exp, :level, :fired, :shape, :hit_radius

  def rebuild_shape
    # 正三角形 (外接半径 28.0) の内接円 (14.0) 程度のコンパクトな当たり判定
    @hit_radius = 12.0
    @shape = Collision.circle(@x, @y, @hit_radius)
  end

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
    @hp = 5
    @max_hp = 5
    @invincible = 0 # 被弾後の無敵残りフレーム
    @exp = 0
    @level = 1
    @fired = false  # このフレームにメインショットを撃ったか (効果音用)
    rebuild_shape
  end

  # 次のレベルに必要な経験値 (レベルが上がるにつれて段階的に増加)
  def exp_to_next
    # 初期は50、レベルが上がるにつれて増加幅も大きくなる
    lv = @level - 1
    50 + lv * 40 + (lv * lv * 4)
  end

  # ダメージを受けたら true を返す (無敵中は false)
  def take_damage(amount)
    return false if @invincible > 0
    @hp -= amount
    @hp = 0 if @hp < 0
    @invincible = 90
    true
  end

  def rebuild_orbiters
    @orbiters = []
    @orbiter_count.times do |i|
      @orbiters << Orbiter.new(i, @orbiter_count)
    end
  end

  def update(bullets, missiles, enemies, particles, camera = nil)
    @fired = false
    @invincible -= 1 if @invincible > 0

    # 移動
    dx, dy = Input.vector
    @x += dx * @speed
    @y += dy * @speed

    if camera
      mx, my = camera.screen_to_world(Input.mouse_x, Input.mouse_y)
    else
      cx = @x - 1280.0 / 2.0
      cy = @y - 720.0 / 2.0
      mx = Input.mouse_x + cx
      my = Input.mouse_y + cy
    end

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
      @fired = true
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

    @shape.x = @x
    @shape.y = @y
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

  def draw
    # 無敵中は点滅 (本体のみ。オービターは常に描画)
    visible = @invincible <= 0 || ((@invincible / 4) % 2) == 0
    if visible
      body_color = @hp <= 1 ? COLOR_HEART_RED : Color::GREEN
      @sides.times do |i|
        angle1 = @rotation + i * (2.0 * Math::PI / @sides)
        vx1 = @x + @radius * Math.cos(angle1)
        vy1 = @y + @radius * Math.sin(angle1)

        angle2 = @rotation + ((i + 1) % @sides) * (2.0 * Math::PI / @sides)
        vx2 = @x + @radius * Math.cos(angle2)
        vy2 = @y + @radius * Math.sin(angle2)

        Window.draw_triangle(@x, @y, vx2, vy2, vx1, vy1, color: body_color)
        Window.draw_line(vx1, vy1, vx2, vy2, color: Color::WHITE)
        Window.draw_rect(vx1 - 2.0, vy1 - 2.0, 4.0, 4.0, color: Color::WHITE)
      end
    end

    @orbiters.each(&:draw)
  end
end

# ==========================================
# 6. メインゲーム (Game)
# ==========================================
class Game
  attr_accessor :player, :camera, :bullets, :missiles, :enemies, :items, :particles, :damage_texts, :game_state, :crt_enabled, :collision_mode, :collision_time_ms

  def spawn_particle(p)
    @particles.shift if @particles.size >= MAX_PARTICLES
    @particles << p
  end

  def spawn_damage_text(t)
    @damage_texts.shift if @damage_texts.size >= MAX_DAMAGE_TEXTS
    @damage_texts << t
  end

  def initialize
    # ゲーム固有のアクションマッピング (ポーズ操作)
    Input.define_action(:pause, keys: [:escape, :p], gamepad: [:start, :back], mouse: [:right])

    @sfx = Sfx.new
    @best_score = 0
    @title_timer = 0
    @crt_enabled = true
    @crt_shader = nil
    @collision_mode = :exact # :exact (Collision GJK) または :simple (円判定)
    @collision_time_ms = 0.0
    reset_world
    @game_state = STATE_TITLE
  end

  # ワールド全体を初期状態に戻す (リトライ時にも使用)
  def reset_world
    @player = Player.new(1280.0 / 2.0, 720.0 / 2.0)
    @camera = Camera2D.new(target: @player, smooth_speed: 0.8)
    @bullets = []
    @missiles = []
    @enemies = []
    @items = []
    @particles = []
    @damage_texts = []
    @game_state = STATE_PLAY
    @menu_cursor = 0
    @prev_mouse_x = -1.0
    @prev_mouse_y = -1.0
    @spawn_timer = 0
    @spawn_interval = 50.0
    @boss_spawn_timer = 1200 # 20秒ごとに出現

    # 演出
    @hitstop = 0         # ヒットストップ残りフレーム
    @damage_flash = 0    # 被弾時の赤フラッシュ残りフレーム
    @levelup_flash = 0   # レベルアップ時の白フラッシュ

    # 戦績
    @frames_alive = 0
    @kills = 0
    @combo = 0
    @combo_timer = 0
    @max_combo = 0
    @new_record = false

    # 死亡演出 / 画面遷移
    @player_dead = false
    @death_timer = 0
    @state_timer = 0 # 画面遷移直後の誤入力防止用

    # レベルアップ選択肢 (アップグレード種別の index)
    @choices = []
  end

  def add_shake(amount)
    @camera.shake([amount * 1.5, 20.0].min, 0.25)
  end

  def add_hitstop(frames)
    @hitstop = frames if frames > @hitstop
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
    t0 = Window.time
    contact_damage = 0
    boss_hit = false
    is_exact = (@collision_mode == :exact)

    # 1. 弾 vs 敵
    @enemies.each do |e|
      next if e.dead

      # 自機との接触判定
      unless @player_dead
        hit = if is_exact
          Collision.check(@player.shape, e.shape)
        else
          p_dx = @player.x - e.x
          p_dy = @player.y - e.y
          p_hit_dist = @player.hit_radius + e.hit_radius
          (p_dx * p_dx + p_dy * p_dy) < (p_hit_dist * p_hit_dist)
        end

        if hit
          if e.is_boss
            boss_hit = true
            contact_damage = 2
          elsif contact_damage < 1
            contact_damage = 1
          end
        end
      end

      # オービター刃 vs 敵
      @player.orbiters.each do |orb|
        hit = if is_exact
          Collision.check(orb.shape, e.shape)
        else
          o_dx = orb.x - e.x
          o_dy = orb.y - e.y
          o_r = e.hit_radius + 6.0
          (o_dx * o_dx + o_dy * o_dy) < (o_r * o_r)
        end

        if hit
          damage_enemy(e, orb.damage, Color::CYAN)
        end
      end

      # 通常弾 vs 敵
      hit_r = e.hit_radius + 2.5
      hit_r_sq = hit_r * hit_r
      max_reach = hit_r + 18.0
      @bullets.each do |b|
        next if b.dead
        dx = e.x - b.x
        next if dx.abs > max_reach
        dy = e.y - b.y
        next if dy.abs > max_reach

        hit = false
        if is_exact
          hit = Collision.check(b.shape, e.shape)
          # トンネリング対策: 高速弾が1フレームで敵を飛び越えた場合、1フレーム手前の中間点でも判定
          unless hit
            b.shape.x = b.x - b.vx * 0.5
            b.shape.y = b.y - b.vy * 0.5
            hit = Collision.check(b.shape, e.shape)
            b.shape.x = b.x
            b.shape.y = b.y
          end
        else
          # Continuous Collision Detection (CCD):
          # 弾の移動線分と敵中心の最短アプローチ距離の2乗を計算 (sqrt不要・O(1))
          # 弾の速さは 16.0 なので vx^2 + vy^2 = 256.0
          u = (dx * b.vx + dy * b.vy) / 256.0
          u = 0.0 if u > 0.0
          u = -1.0 if u < -1.0
          cx = dx - u * b.vx
          cy = dy - u * b.vy
          hit = (cx * cx + cy * cy) < hit_r_sq
        end

        if hit
          b.dead = true
          damage_enemy(e, b.damage, Color::YELLOW)
          break if e.dead
        end
      end

      # ミサイル直撃 vs 敵
      m_hit_r_sq = (e.hit_radius + 4.0) * (e.hit_radius + 4.0) unless is_exact
      @missiles.each do |m|
        next if m.dead
        hit = if is_exact
          Collision.check(m.shape, e.shape)
        else
          dx = e.x - m.x
          dy = e.y - m.y
          (dx * dx + dy * dy) < m_hit_r_sq
        end

        if hit
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

    # 3. 自機の被弾処理 (無敵時間中は無効)
    if contact_damage > 0 && @player.take_damage(contact_damage)
      on_player_damaged(boss_hit)
    end

    dt_ms = (Window.time - t0) * 1000.0
    @collision_time_ms = @collision_time_ms * 0.9 + dt_ms * 0.1

    # 4. アイテム取得判定
    return if @player_dead
    @items.each do |item|
      next if item.dead
      dx = @player.x - item.x
      dy = @player.y - item.y
      if dx * dx + dy * dy < 40.0 * 40.0
        item.dead = true
        if item.kind == 1
          pick_heart(item)
        else
          @player.exp += item.value
          @sfx.play(Sfx::GEM, 3)
          # 取得キラキラパーティクル
          spawn_particle(Particle.new(item.x, item.y, (rand(4) - 2).to_f, (rand(4) - 2).to_f, 12, COLOR_EXP_GREEN, 4.0))
        end
      end
    end
  end

  def pick_heart(item)
    if @player.hp < @player.max_hp
      @player.hp += 1
      spawn_damage_text(DamageText.new(@player.x - 30.0, @player.y - 50.0, "+1 HP", COLOR_HEART_RED, 22))
    else
      # HP満タン時はスコアボーナス
      @player.score += 100
      spawn_damage_text(DamageText.new(@player.x - 30.0, @player.y - 50.0, "+100", COLOR_HEART_RED, 22))
    end
    @sfx.play(Sfx::HEAL, 4)
    8.times do
      ang = rand(360) * Math::PI / 180.0
      spawn_particle(Particle.new(item.x, item.y, 3.0 * Math.cos(ang), 3.0 * Math.sin(ang), 18, COLOR_HEART_RED, 5.0))
    end
  end

  # 自機被弾時の演出・振動・ノックバック
  def on_player_damaged(boss_hit)
    @combo = 0
    @combo_timer = 0
    @damage_flash = 14
    add_shake(boss_hit ? 8.0 : 5.0)
    add_hitstop(5)
    @sfx.play(Sfx::DAMAGE, 10)

    # 3. 振動フィードバック
    if boss_hit
      Input.vibrate_gamepad(0, 1.0, 1.0, 0.25) # ボス接触は特大振動
    else
      Input.vibrate_gamepad(0, 0.7, 0.7, 0.15) # 通常接触
    end
    Input.vibrate(0.1)

    # 周囲の雑魚を押し返して立て直す余地を作る
    @enemies.each do |e|
      next if e.dead || e.is_boss
      dx = e.x - @player.x
      dy = e.y - @player.y
      dist = Math.sqrt(dx * dx + dy * dy)
      if dist < 180.0 && dist > 0.1
        push = 180.0 - dist
        e.x += (dx / dist) * push
        e.y += (dy / dist) * push
      end
    end

    12.times do
      ang = rand(360) * Math::PI / 180.0
      spd = rand(6).to_f + 2.0
      spawn_particle(Particle.new(@player.x, @player.y, spd * Math.cos(ang), spd * Math.sin(ang), 20, COLOR_HEART_RED, 6.0))
    end

    on_player_death if @player.hp <= 0
  end

  def on_player_death
    @player_dead = true
    @death_timer = 100
    add_shake(10.0)
    add_hitstop(12)
    @sfx.play(Sfx::BOSS_KILL, 30)
    Input.vibrate_gamepad(0, 1.0, 1.0, 0.6)
    80.times do
      ang = rand(360) * Math::PI / 180.0
      spd = rand(12).to_f + 2.0
      spawn_particle(Particle.new(@player.x, @player.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(40) + 30, Color::GREEN, 9.0))
    end
  end

  def damage_enemy(e, dmg, text_color)
    e.hp -= dmg
    e.flash = 3
    @sfx.play(Sfx::HIT, 3)
    spawn_damage_text(DamageText.new(e.x, e.y - e.radius, dmg, text_color))
    # 被弾スパーク
    3.times do
      spawn_particle(Particle.new(e.x, e.y, (rand(6) - 3).to_f, (rand(6) - 3).to_f, 10, Color::WHITE, 3.0))
    end

    if e.hp <= 0
      e.dead = true
      kill_enemy(e)
    end
  end

  def combo_multiplier
    1 + @combo / 10
  end

  def kill_enemy(e)
    # コンボ & スコア加算
    @kills += 1
    @combo += 1
    @combo_timer = 120
    @max_combo = @combo if @combo > @max_combo
    @player.score += e.score_value * combo_multiplier

    if e.is_boss
      # ボス撃破：大爆発＆大量ジェム
      60.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(10).to_f + 2.0
        spawn_particle(Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(30) + 20, COLOR_PURPLE, 10.0))
      end
      12.times do
        @items << Item.new(e.x + (rand(80) - 40).to_f, e.y + (rand(80) - 40).to_f, 30)
      end
      @items << Item.new(e.x, e.y, 0, 1)
      add_shake(9.0)
      add_hitstop(8)
      @sfx.play(Sfx::BOSS_KILL, 20)
      Input.vibrate_gamepad(0, 1.0, 0.6, 0.3)
    elsif e.max_hp > 5
      # エリート撃破
      25.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(7).to_f + 2.0
        spawn_particle(Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(20) + 15, Color::RED, 7.0))
      end
      4.times do
        @items << Item.new(e.x + (rand(40) - 20).to_f, e.y + (rand(40) - 20).to_f, 20)
      end
      # 20% の確率で回復ハートをドロップ
      @items << Item.new(e.x, e.y, 0, 1) if rand(100) < 20
      add_shake(3.0)
      add_hitstop(3)
      @sfx.play(Sfx::EXPLODE, 4)
    else
      # 通常・チビ撃破
      12.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(5).to_f + 2.0
        spawn_particle(Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(15) + 10, COLOR_ORANGE, 5.0))
      end
      @items << Item.new(e.x, e.y, 10)
      add_shake(0.6)
      @sfx.play(Sfx::KILL, 3)
    end
  end

  def create_explosion(x, y, radius, damage)
    add_shake(2.5)
    @sfx.play(Sfx::EXPLODE, 4)
    # 爆発パーティクル
    25.times do
      ang = rand(360) * Math::PI / 180.0
      spd = rand(8).to_f + 2.0
      spawn_particle(Particle.new(x, y, spd * Math.cos(ang), spd * Math.sin(ang), rand(20) + 10, Color::RED, 8.0))
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

  # ==========================================
  # 入力ヘルパー
  # ==========================================
  def confirm_pressed?
    Input.action_push?(:ui_accept)
  end

  def update_draw_frame
    @sfx.tick
    @state_timer += 1

    case @game_state
    when STATE_TITLE
      update_title
    when STATE_PLAY
      update_play
    when STATE_PAUSE
      update_pause
    when STATE_LEVELUP
      update_levelup
    when STATE_GAMEOVER
      update_gameover
    end

    # カメラ更新 (ターゲット追従 & 画面シェイク減衰)
    @camera.update

    @damage_flash -= 1 if @damage_flash > 0
    @levelup_flash -= 1 if @levelup_flash > 0

    # CRT エフェクトの初期化とトグル切り替え ([C] キー)
    if @crt_shader.nil?
      @crt_shader = Shader.new(CRT_FRAGMENT_SHADER)
      Window.filter = @crt_shader if @crt_enabled
    end

    if Input.key_push?(:c)
      @crt_enabled = !@crt_enabled
      Window.filter = @crt_enabled ? @crt_shader : nil
    end

    if Input.key_push?(:m)
      @collision_mode = (@collision_mode == :exact ? :simple : :exact)
    end

    draw_game
  end

  def change_state(state)
    @game_state = state
    @state_timer = 0
  end

  def update_title
    @title_timer += 1
    return unless @state_timer > 10 && confirm_pressed?
    reset_world
    @sfx.play(Sfx::LEVELUP, 10)
    change_state(STATE_PLAY)
  end

  def update_play
    if Input.action_push?(:pause) && !@player_dead
      change_state(STATE_PAUSE)
      return
    end

    # ヒットストップ中はワールドを止める (描画のみ継続)
    if @hitstop > 0
      @hitstop -= 1
      return
    end

    # コンボ時間切れ
    if @combo_timer > 0
      @combo_timer -= 1
      @combo = 0 if @combo_timer <= 0
    end

    # 1. 敵スポーン
    spawn_enemies unless @player_dead

    # 2. オブジェクト更新
    unless @player_dead
      @frames_alive += 1
      @player.update(@bullets, @missiles, @enemies, @particles, @camera)
      @sfx.play(Sfx::SHOT, 4) if @player.fired
    end
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

    # 5. 死亡演出 → リザルトへ
    if @player_dead
      @death_timer -= 1
      if @death_timer <= 0
        if @player.score > @best_score
          @best_score = @player.score
          @new_record = true
        end
        change_state(STATE_GAMEOVER)
      end
      return
    end

    # 6. レベルアップ判定
    if @player.exp >= @player.exp_to_next
      start_levelup
    end
  end

  def update_pause
    if Input.action_push?(:pause) || Input.action_push?(:ui_cancel)
      change_state(STATE_PLAY)
      return
    end

    # Q / Y ボタンでタイトルへ戻る
    if Input.key_push?(:q) || Input.gamepad_button_push?(:y)
      change_state(STATE_TITLE)
    end
  end

  def update_gameover
    return unless @state_timer > 45 && confirm_pressed?
    reset_world
    @sfx.play(Sfx::LEVELUP, 10)
    change_state(STATE_PLAY)
  end

  # ==========================================
  # レベルアップ (ランダム 3 択)
  # ==========================================
  def upgrade_available?(idx)
    case idx
    when 0 then @player.sides < 10
    when 1 then @player.shot_level < 5
    when 2 then @player.orbiter_count < 4
    when 3 then @player.missile_level < 3
    when 4 then @player.speed < 9.0
    when 5 then @player.fire_rate > 3
    when 6 then @player.magnet_radius < 460.0
    else true # 最大HPアップは常に選択可能
    end
  end

  def start_levelup
    @player.exp -= @player.exp_to_next
    @player.level += 1

    # 選択可能なアップグレードから重複なしで最大 3 つ抽選
    candidates = []
    UPGRADE_COUNT.times do |i|
      candidates << i if upgrade_available?(i)
    end
    @choices = []
    while @choices.size < 3 && candidates.size > 0
      pick = rand(candidates.size)
      @choices << candidates[pick]
      candidates.delete_at(pick)
    end

    @menu_cursor = 0
    @levelup_flash = 10
    @sfx.play(Sfx::LEVELUP, 10)
    change_state(STATE_LEVELUP)
  end

  def update_levelup
    # 上下選択入力 (十字キー / WSキー / 上下矢印 / 左スティックを自動統合)
    up_pressed = Input.action_push?(:ui_up)
    down_pressed = Input.action_push?(:ui_down)

    count = @choices.size
    if up_pressed
      @menu_cursor = (@menu_cursor - 1) % count
      @sfx.play(Sfx::SELECT, 2)
    elsif down_pressed
      @menu_cursor = (@menu_cursor + 1) % count
      @sfx.play(Sfx::SELECT, 2)
    end

    # マウスによる選択（ホバー）: マウスが動いたときだけカーソルを奪う
    mx = Input.mouse_x
    my = Input.mouse_y
    mouse_moved = (mx != @prev_mouse_x || my != @prev_mouse_y)
    @prev_mouse_x = mx
    @prev_mouse_y = my
    mouse_hover_idx = -1
    count.times do |i|
      top = levelup_row_top(i)
      if mx >= 240.0 && mx <= 1040.0 && my >= top && my <= top + 80.0
        mouse_hover_idx = i
        @menu_cursor = i if mouse_moved
        break
      end
    end

    # 遷移直後の誤爆防止
    return if @state_timer < 20

    # 決定操作 (Action: :ui_accept またはマウスホバークリック)
    buy_pressed = Input.action_push?(:ui_accept)
    if mouse_hover_idx >= 0 && Input.mouse_push?(:left)
      @menu_cursor = mouse_hover_idx
      buy_pressed = true
    end

    return unless buy_pressed

    execute_skill_upgrade(@choices[@menu_cursor])
    @sfx.play(Sfx::HEAL, 4)
    change_state(STATE_PLAY)
    # 経験値が余っていれば連続レベルアップ
    start_levelup if @player.exp >= @player.exp_to_next
  end

  def levelup_row_top(i)
    250.0 + i.to_f * 100.0
  end

  def execute_skill_upgrade(idx)
    case idx
    when 0 # 形状強化
      @player.sides += 1
      @player.rebuild_shape
    when 1 # 拡散ショット
      @player.shot_level += 1
    when 2 # 近接回転刃 (オービター)
      @player.orbiter_count += 1
      @player.rebuild_orbiters
    when 3 # 追尾爆発ミサイル
      @player.missile_level += 1
    when 4 # 移動速度
      @player.speed += 1.0
    when 5 # 連射速度 (下限 3 を限度とする)
      @player.fire_rate -= 2
      @player.fire_rate = 3 if @player.fire_rate < 3
    when 6 # 磁石範囲
      @player.magnet_radius += 60.0
    when 7 # 最大HPアップ & 全回復
      @player.max_hp += 1
      @player.hp = @player.max_hp
    end
  end

  def upgrade_title(idx)
    case idx
    when 0 then "UPGRADE SHAPE"
    when 1 then "SPREAD SHOT"
    when 2 then "ENERGY ORBITER"
    when 3 then "HOMING MISSILE"
    when 4 then "SPEED UP"
    when 5 then "FIRE RATE UP"
    when 6 then "MAGNET RADIUS"
    else "VITALITY"
    end
  end

  def upgrade_desc(idx)
    case idx
    when 0 then "Sides #{@player.sides} -> #{@player.sides + 1}  (more shots from every vertex)"
    when 1 then "Way #{@player.shot_level} -> #{@player.shot_level + 1}"
    when 2 then "Blades #{@player.orbiter_count} -> #{@player.orbiter_count + 1}"
    when 3 then "Missile Lv #{@player.missile_level} -> #{@player.missile_level + 1}"
    when 4 then "Speed #{@player.speed.to_i} -> #{@player.speed.to_i + 1}"
    when 5
      next_rate = @player.fire_rate - 2
      next_rate = 3 if next_rate < 3
      "Interval #{@player.fire_rate} -> #{next_rate} frames"
    when 6 then "Range #{@player.magnet_radius.to_i} -> #{@player.magnet_radius.to_i + 60}"
    else "Max HP #{@player.max_hp} -> #{@player.max_hp + 1}  & full heal"
    end
  end

  # ==========================================
  # 描画
  # ==========================================
  def time_str(frames)
    sec = frames / 60
    m = sec / 60
    s = sec % 60
    s_str = s < 10 ? "0#{s}" : "#{s}"
    "#{m}:#{s_str}"
  end

  def draw_centered(y, text, size, color, font = Font::SINCLAIR)
    Window.draw_text(640.0, y, text, font: font, size: size, color: color, align: :center)
  end

  def draw_game
    Window.clear(Color::BLACK)

    if @game_state == STATE_TITLE
      draw_title
      return
    end

    # 画面外カリング用の可視矩形 (1280x720 + マージン)
    cam_x = @camera.x
    cam_y = @camera.y
    cull_l = cam_x - 720.0
    cull_r = cam_x + 720.0
    cull_t = cam_y - 440.0
    cull_b = cam_y + 440.0

    # ワールド空間描画 (Window.camera ブロック構文)
    Window.camera(@camera) do
      draw_grid
      @items.each { |i| i.draw if i.x >= cull_l && i.x <= cull_r && i.y >= cull_t && i.y <= cull_b }
      @particles.each { |p| p.draw if p.x >= cull_l && p.x <= cull_r && p.y >= cull_t && p.y <= cull_b }
      @enemies.each { |e| e.draw if e.x >= cull_l && e.x <= cull_r && e.y >= cull_t && e.y <= cull_b }
      @bullets.each { |b| b.draw if b.x >= cull_l && b.x <= cull_r && b.y >= cull_t && b.y <= cull_b }
      @missiles.each(&:draw)
      @player.draw unless @player_dead
      @damage_texts.each { |d| d.draw if d.x >= cull_l && d.x <= cull_r && d.y >= cull_t && d.y <= cull_b }
    end

    # 画面空間描画 (被弾の赤フラッシュ / レベルアップの白フラッシュ / HUD)
    if @damage_flash > 0
      Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: Color.new(255, 0, 0, @damage_flash * 8))
    end
    if @levelup_flash > 0
      Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: Color.new(255, 255, 255, @levelup_flash * 10))
    end

    draw_hud

    case @game_state
    when STATE_PAUSE
      draw_pause_menu
    when STATE_LEVELUP
      draw_levelup_menu
    when STATE_GAMEOVER
      draw_gameover
    end
  end

  # ワールド座標系での背景グリッド描画 (カメラの可視範囲のみ描画)
  def draw_grid
    grid_size = 100.0
    half_w = 1280.0 * 0.5
    half_h = 720.0 * 0.5
    left = ((@camera.x - half_w - grid_size) / grid_size).floor * grid_size
    right = ((@camera.x + half_w + grid_size) / grid_size).ceil * grid_size
    top = ((@camera.y - half_h - grid_size) / grid_size).floor * grid_size
    bottom = ((@camera.y + half_h + grid_size) / grid_size).ceil * grid_size

    x = left
    while x <= right
      Window.draw_line(x, top, x, bottom, color: COLOR_GRID_DARK)
      x += grid_size
    end

    y = top
    while y <= bottom
      Window.draw_line(left, y, right, y, color: COLOR_GRID_DARK)
      y += grid_size
    end
  end

  # スクリーン座標系でのグリッド描画 (タイトル画面用)
  def draw_screen_grid(ox, oy)
    grid_size = 100.0
    x = -(ox.to_i % 100).to_f
    while x < 1280.0
      Window.draw_line(x, 0.0, x, 720.0, color: COLOR_GRID_DARK)
      x += grid_size
    end

    y = -(oy.to_i % 100).to_f
    while y < 720.0
      Window.draw_line(0.0, y, 1280.0, y, color: COLOR_GRID_DARK)
      y += grid_size
    end
  end

  def draw_hud
    # HUD (UI)
    hud_str = "SCORE: #{@player.score}   TIME: #{time_str(@frames_alive)}   LV: #{@player.level}"
    Window.draw_text(20.0, 20.0, hud_str, font: Font::SINCLAIR, size: 24, color: Color::WHITE)

    # HP (ハートブロック)
    @player.max_hp.times do |i|
      hx = 20.0 + i.to_f * 30.0
      c = i < @player.hp ? COLOR_HEART_RED : COLOR_HP_GRAY
      Window.draw_rect(hx, 56.0, 24.0, 18.0, color: c)
    end

    # コンボ表示 (右揃え align: :right)
    if @combo >= 3
      combo_size = 28 + (@combo > 40 ? 20 : @combo / 2)
      combo_str = "#{@combo} COMBO  x#{combo_multiplier}"
      w = Window.text_width(combo_str, font: Font::SINCLAIR, size: combo_size)
      ratio = @combo_timer.to_f / 120.0
      Window.draw_text(1260.0, 20.0, combo_str, font: Font::SINCLAIR, size: combo_size, color: COLOR_ORANGE, align: :right)
      Window.draw_rect(1260.0 - w, 24.0 + combo_size.to_f, w * ratio, 4.0, color: COLOR_ORANGE)
    end

    # EXPバー (画面下端)
    exp_ratio = @player.exp.to_f / @player.exp_to_next
    exp_ratio = 1.0 if exp_ratio > 1.0
    Window.draw_rect(0.0, 710.0, 1280.0, 10.0, color: COLOR_EXP_BAR_BG)
    Window.draw_rect(0.0, 710.0, 1280.0 * exp_ratio, 10.0, color: COLOR_EXP_GREEN)

    # デバッグ情報
    entities_count = @bullets.size + @missiles.size + @enemies.size + @items.size + @particles.size + @damage_texts.size
    pad_str = Input.gamepad_connected?(0) ? "[PAD: ON]" : "[PAD: OFF]"
    mode_str = @collision_mode == :exact ? "EXACT(API)" : "SIMPLE(MATH)"
    val_100 = (@collision_time_ms * 100).to_i
    val_dec = val_100 % 100
    col_str = "#{val_100 / 100}.#{val_dec < 10 ? '0' : ''}#{val_dec}ms"
    dbg_str = "FPS: #{Window.fps.to_i}  OBJ: #{entities_count}  COL: #{col_str} [M: #{mode_str}]  #{pad_str}  [C: CRT #{@crt_enabled ? 'ON' : 'OFF'}]"
    Window.draw_text(20.0, 684.0, dbg_str, font: Font::SINCLAIR, size: 14, color: COLOR_TEXT_GRAY)
  end

  def draw_title
    t = @title_timer
    # 背景グリッドをゆっくりスクロール
    draw_screen_grid(t.to_f * 0.6, t.to_f * 0.3)

    # 中央で回転する多角形 (頂点数が徐々に増える)
    sides = 3 + (t / 90) % 6
    rot = t.to_f * 0.02
    radius = 90.0
    sides.times do |i|
      a1 = rot + i * (2.0 * Math::PI / sides)
      a2 = rot + ((i + 1) % sides) * (2.0 * Math::PI / sides)
      x1 = 640.0 + radius * Math.cos(a1)
      y1 = 330.0 + radius * Math.sin(a1)
      x2 = 640.0 + radius * Math.cos(a2)
      y2 = 330.0 + radius * Math.sin(a2)
      Window.draw_triangle(640.0, 330.0, x2, y2, x1, y1, color: Color::GREEN)
      Window.draw_line(x1, y1, x2, y2, color: Color::WHITE, width: 2.0)
    end

    draw_centered(100.0, "ZENOO SURVIVOR", 56, Color::WHITE, Font::MPLUS)
    draw_centered(180.0, "Grow your shape. Survive the swarm.", 20, COLOR_TEXT_GRAY)

    if (t / 30) % 2 == 0
      draw_centered(470.0, "PRESS ENTER / A / CLICK TO START", 24, Color::CYAN)
    end

    draw_centered(540.0, "MOVE: WASD / Stick / Hold Left Click    AIM: Mouse / Right Stick", 18, Color::WHITE)
    draw_centered(570.0, "PAUSE: ESC / START / Right Click    CRT: [C]    COLLISION: [M]", 18, Color::WHITE)
    draw_centered(630.0, "BEST SCORE: #{@best_score}", 22, COLOR_ORANGE) if @best_score > 0
  end

  def draw_pause_menu
    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG)
    draw_centered(130.0, "=== PAUSED ===", 40, Color::WHITE)

    lines = [
      "LEVEL      : #{@player.level}",
      "HP         : #{@player.hp} / #{@player.max_hp}",
      "SHAPE      : #{@player.sides} sides",
      "SPREAD     : #{@player.shot_level} way",
      "ORBITER    : #{@player.orbiter_count} blades",
      "MISSILE    : Lv #{@player.missile_level}",
      "SPEED      : #{@player.speed.to_i}",
      "FIRE RATE  : #{@player.fire_rate} frames",
      "MAGNET     : #{@player.magnet_radius.to_i}"
    ]
    lines.each_with_index do |line, i|
      Window.draw_text(460.0, 210.0 + i.to_f * 34.0, line, font: Font::SINCLAIR, size: 22, color: Color::WHITE)
    end

    mode_str = @collision_mode == :exact ? "EXACT(API)" : "SIMPLE(MATH)"
    draw_centered(560.0, "ESC / START / Right Click / (B) to Resume", 20, Color::WHITE)
    draw_centered(595.0, "Q / (Y) to Title    [C] CRT: #{@crt_enabled ? 'ON' : 'OFF'}    [M] Collision: #{mode_str}", 18, COLOR_TEXT_GRAY)
  end

  def draw_levelup_menu
    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG)
    draw_centered(130.0, "LEVEL UP!", 56, COLOR_EXP_GREEN)
    draw_centered(200.0, "Choose one upgrade", 20, COLOR_TEXT_GRAY)

    @choices.each_with_index do |idx, i|
      top = levelup_row_top(i)
      is_selected = (@menu_cursor == i)

      if is_selected
        Window.draw_rect(240.0, top, 800.0, 80.0, color: COLOR_BUTTON_HOVER)
        Window.draw_rect(236.0, top, 4.0, 80.0, color: Color::CYAN)
      else
        Window.draw_rect(240.0, top, 800.0, 80.0, color: Color.new(30, 30, 38, 220))
      end

      title_color = is_selected ? Color::CYAN : Color::WHITE
      prefix = is_selected ? "> " : "  "
      Window.draw_text(260.0, top + 14.0, "#{prefix}#{upgrade_title(idx)}", font: Font::SINCLAIR, size: 26, color: title_color)
      Window.draw_text(300.0, top + 48.0, upgrade_desc(idx), font: Font::SINCLAIR, size: 18, color: COLOR_TEXT_GRAY)
    end

    draw_centered(570.0, "[UP/DOWN/Stick] Select   [A / ENTER / Click] Choose", 20, Color::WHITE)
  end

  def draw_gameover
    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG)
    draw_centered(110.0, "GAME OVER", 64, COLOR_HEART_RED)

    lines = [
      "TIME       : #{time_str(@frames_alive)}",
      "LEVEL      : #{@player.level}",
      "KILLS      : #{@kills}",
      "MAX COMBO  : #{@max_combo}",
      "SCORE      : #{@player.score}",
      "BEST       : #{@best_score}"
    ]
    lines.each_with_index do |line, i|
      Window.draw_text(470.0, 220.0 + i.to_f * 40.0, line, font: Font::SINCLAIR, size: 26, color: Color::WHITE)
    end

    if @new_record && (@state_timer / 15) % 2 == 0
      draw_centered(480.0, "NEW RECORD!", 32, COLOR_ORANGE)
    end

    if @state_timer > 45 && (@state_timer / 30) % 2 == 0
      draw_centered(570.0, "PRESS ENTER / A / CLICK TO RETRY", 26, Color::CYAN)
    end
  end
end

# ==========================================
# 7. メインループ
# ==========================================
game = Game.new
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0
# 自動テスト時はタイトルを飛ばしてプレイ状態から開始 (ZENOO_TEST_TITLE 指定時はタイトルをテスト)
game.game_state = STATE_PLAY if test_max > 0 && ENV['ZENOO_TEST_TITLE'] != '1'

Window.loop(1280, 720, "Zenoo Survival Shooting Game") do
  Enemy.init_atlas
  game.update_draw_frame
  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "Game test completed successfully! (#{frame_count} frames)"
      exit
    end
  end
end

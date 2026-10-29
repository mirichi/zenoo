# frozen_string_literal: true

require_relative '../lib/zenoo'

# 衝撃波 (Shockwave / Ripple Distortion) シェーダー
# ボス撃破地点から同心円状に空間が歪み、RGB分散と波面ハイライトが発生
SHOCKWAVE_FRAGMENT_SHADER = <<~'GLSL'
#version 330 core
in vec4 v_color;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform vec2 u_center;  // 衝撃波の中心座標 (0.0〜1.0)
uniform float u_radius; // 波面の現在半径 (0.0〜1.5)
uniform float u_force;  // 歪みの強さ (0.0〜0.1)
out vec4 fragColor;

void main() {
    if (u_force <= 0.0001 || u_radius <= 0.0) {
        fragColor = texture(u_texture, v_uv);
        return;
    }

    vec2 aspect = vec2(1280.0 / 720.0, 1.0);
    vec2 diff = (v_uv - u_center) * aspect;
    float dist = length(diff);

    // 波面の幅
    float thickness = 0.12;

    if (dist >= u_radius - thickness && dist <= u_radius + thickness) {
        // -1.0 〜 +1.0
        float edge = (dist - u_radius) / thickness;
        // コサイン波による滑らかな山型
        float diff_factor = cos(edge * 1.5707963);
        diff_factor = diff_factor * diff_factor;

        vec2 dir = normalize(diff) / aspect;
        vec2 offset = dir * diff_factor * u_force;

        // 色収差 (RGB波長ごとの屈折率分散)
        float r = texture(u_texture, v_uv - offset * 1.15).r;
        float g = texture(u_texture, v_uv - offset).g;
        float b = texture(u_texture, v_uv - offset * 0.85).b;
        vec3 col = vec3(r, g, b);

        // 波面リングのハイライト発光
        col += vec3(0.12, 0.15, 0.20) * diff_factor;

        fragColor = vec4(col, 1.0);
    } else {
        fragColor = texture(u_texture, v_uv);
    }
}
GLSL

# レトロCRTブラウン管シェーダー (スキャンライン・樽型歪み・色収差・ビネット・受信障害グリッチ)
CRT_FRAGMENT_SHADER = <<~'GLSL'
#version 330 core
in vec4 v_color;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_time;
uniform float u_glitch; // 0.0 (通常) 〜 1.0 (最大グリッチ)
out vec4 fragColor;

// 樽型歪み (CRTブラウン管の曲面ガラス)
vec2 crt_curve(vec2 uv) {
    vec2 cc = uv - 0.5;
    float dist = dot(cc, cc);
    return 0.5 + cc * (1.0 + 0.12 * dist + 0.06 * dist * dist);
}

// 疑似乱数 (砂嵐ノイズ用)
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = crt_curve(v_uv);

    // 画面外は黒 (ベゼル枠)
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // --- 受信障害グリッチ演出 ---
    vec2 glitch_uv = uv;
    float chroma_offset = 0.0012;

    if (u_glitch > 0.001) {
        // 1. 水平テアリング (スキャンラインのブロック横ズレ)
        float tear_line = sin(uv.y * 35.0 + u_time * 18.0) * sin(uv.y * 80.0 - u_time * 25.0);
        float tear_trigger = step(0.60, abs(tear_line));
        float tear_shift = sin(u_time * 40.0 + uv.y * 100.0) * 0.035 * u_glitch;
        glitch_uv.x += tear_trigger * tear_shift;

        // 2. 水平ジッター (同期の乱れ)
        glitch_uv.x += (sin(u_time * 50.0 + uv.y * 200.0) * 0.004) * u_glitch;

        // 3. 垂直同期の乱れ (上下の微小揺れ)
        float v_jump = step(0.85, sin(u_time * 12.0)) * (sin(u_time * 30.0) * 0.02 * u_glitch);
        glitch_uv.y += v_jump;

        // 4. 色収差 (RGB分離) の大幅増大
        chroma_offset += u_glitch * 0.015;
    }

    // 色収差 (RGBチャンネル微小ズレ)
    float r = texture(u_texture, glitch_uv - vec2(chroma_offset, 0.0)).r;
    float g = texture(u_texture, glitch_uv).g;
    float b = texture(u_texture, glitch_uv + vec2(chroma_offset, 0.0)).b;
    vec3 col = vec3(r, g, b);

    // 砂嵐ノイズ (Static snow)
    if (u_glitch > 0.001) {
        float snow = hash(uv * 3.0 + vec2(u_time * 15.0, u_time * 37.0));
        col = mix(col, vec3(snow), u_glitch * 0.22);
    }

    // スキャンライン (黒い横走査線)
    // 240本の走査線 (レトロアーケード/CRTスタイル)
    float scan = sin(uv.y * 240.0 * 6.2831853);
    float scan_weight = clamp(0.5 + 0.5 * scan, 0.0, 1.0);
    float scan_dark = 0.20;
    if (u_glitch > 0.001) {
        scan_dark = mix(0.20, 0.05, u_glitch * abs(sin(u_time * 30.0)));
    }
    col *= mix(scan_dark, 1.15, pow(scan_weight, 0.75));

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

# ゲームデモ固有のプロファイラ表示色パレット
Zenoo::Profiler.set_colors(
  player:     Color.new(100, 220, 180), # ターコイズ (自機処理)
  missile:    Color.new(230, 110, 190), # ピンク/マゼンタ (ミサイル追尾)
  enemy_move: Color.new(255, 190, 60),  # ウォーム・イエロー (敵移動)
  separate:   Color.new(255, 95, 95),   # コーラル・レッド (敵押し出し)
  gc:         Color.new(160, 165, 175), # シルバーグレー (GC/クリーンアップ)
  hud:        Color.new(120, 220, 240), # スカイシアン (HUD描画)
  gui_text:   Color.new(235, 150, 255)  # 明るいパープル (GUIテキスト描画)
)
COLOR_TEXT_GRAY    = Color.new(140, 140, 140)
COLOR_PURPLE       = Color.new(210, 60, 255)
COLOR_EXP_GREEN    = Color.new(50, 255, 130)
COLOR_HEART_RED    = Color.new(255, 70, 90)
COLOR_EXP_BAR_BG   = Color.new(30, 40, 35)
COLOR_BOSS_HP      = Color.new(255, 60, 100)

# 画面 (タイトル / プレイ / ポーズ / レベルアップ / リザルト) は Zenoo::Scene で管理
# → 末尾の「7. シーン」を参照

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
  attr_reader :x, :y

  def initialize(x, y, vx, vy, life, color, size = 6.0)
    @x = x.to_f
    @y = y.to_f
    @vx = vx.to_f
    @vy = vy.to_f
    @life = life
    @max_life = life
    @color = color
    @size = size.to_f
    @vanished = false
  end

  def vanish
    @vanished = true
  end

  def vanished?
    @vanished
  end

  def update
    @x += @vx
    @y += @vy
    @vx *= 0.94
    @vy *= 0.94
    @life -= 1
    vanish if @life <= 0
  end

  def draw
    s = (@life.to_f / @max_life) * @size
    Window.draw_rect(@x - s * 0.5, @y - s * 0.5, s, s, color: @color)
  end
end

# 敵頭上に飛び出すダメージ数値ポップアップ
class DamageText
  attr_reader :x, :y

  def initialize(x, y, text, color = Color::WHITE, size = 18)
    @x = x.to_f + (rand(16) - 8).to_f
    @y = y.to_f
    @text = text.to_s
    @color = color
    @size = size
    @life = 25
    @vanished = false
  end

  def vanish
    @vanished = true
  end

  def vanished?
    @vanished
  end

  def update
    @y -= 1.2
    @life -= 1
    vanish if @life <= 0
  end

  def draw
    Window.draw_text(@x, @y, @text, font: Font::SINCLAIR, size: @size, color: @color)
  end
end

# ==========================================
# 2. 弾 & 近接武器 (Bullet, Missile, Orbiter)
# ==========================================
class Bullet < Sprite
  attr_accessor :vx, :vy, :damage

  def initialize(x, y, angle, speed = 16.0, damage = 1)
    super(x, y, anchor: :center, pivot: :center)
    @vx = speed * Math.cos(angle)
    @vy = speed * Math.sin(angle)
    @damage = damage
    @traveled = 0.0
    set_collider(:circle, radius: 2.5)
  end

  def update
    self.x += @vx
    self.y += @vy
    @traveled += 16.0
    vanish if @traveled > 1400.0
  end

  def draw
    Window.draw_rect(self.x - 2.5, self.y - 2.5, 5.0, 5.0, color: Color::CYAN)
  end
end

# 追尾＆着弾範囲爆発ミサイル
class Missile < Sprite
  attr_accessor :vx, :vy, :damage, :exploded

  def initialize(x, y, target_x, target_y)
    super(x, y, anchor: :center, pivot: :center)
    dx = target_x - x
    dy = target_y - y
    angle = Math.atan2(dy, dx)
    @speed = 10.0
    @vx = @speed * Math.cos(angle)
    @vy = @speed * Math.sin(angle)
    @damage = 12
    @life = 90
    @exploded = false
    set_collider(:circle, radius: 4.0)
  end

  def update(enemies)
    @life -= 1
    if @life <= 0
      vanish
      @exploded = true
      return
    end

    nearest = nil
    min_d2 = 600.0 * 600.0
    enemies.each do |e|
      next if e.vanished?
      dx = e.x - self.x
      dy = e.y - self.y
      d2 = dx * dx + dy * dy
      if d2 < min_d2
        min_d2 = d2
        nearest = e
      end
    end

    if nearest
      angle = Math.atan2(nearest.y - self.y, nearest.x - self.x)
      @vx += Math.cos(angle) * 0.7
      @vy += Math.sin(angle) * 0.7
      speed = Math.sqrt(@vx * @vx + @vy * @vy)
      if speed > 11.0
        @vx = (@vx / speed) * 11.0
        @vy = (@vy / speed) * 11.0
      end
    end

    self.x += @vx
    self.y += @vy
  end

  def explode
    vanish
    @exploded = true
  end

  def draw
    Window.draw_rect(self.x - 4.0, self.y - 4.0, 8.0, 8.0, color: Color::RED)
  end
end

# 自機周囲を旋回する近接シールド刃
class Orbiter < Sprite
  attr_accessor :damage

  def initialize(index, total)
    super(0.0, 0.0, anchor: :center, pivot: :center)
    @index = index
    @total = total
    @radius = 125.0
    @angle_rad = index * (2.0 * Math::PI / total)
    @speed = 0.08
    @damage = 2
    set_collider(:circle, radius: 6.0)
  end

  def update(px, py)
    @angle_rad += @speed
    self.x = px + @radius * Math.cos(@angle_rad)
    self.y = py + @radius * Math.sin(@angle_rad)
  end

  def draw
    Window.draw_rect(self.x - 6.0, self.y - 6.0, 12.0, 12.0, color: Color::CYAN)
    Window.draw_rect(self.x - 3.0, self.y - 3.0, 6.0, 6.0, color: Color::WHITE)
  end
end

# ==========================================
# 3. ドロップアイテム (EXPジェム / 回復ハート)
# ==========================================
class Item < Sprite
  attr_accessor :value, :kind

  # kind: 0 = EXPジェム, 1 = 回復ハート
  def initialize(x, y, value = 10, kind = 0)
    super(x, y, anchor: :center, pivot: :center)
    @value = value
    @kind = kind
    @life = kind == 1 ? 900 : 600
    set_collider(:circle, radius: 28.0) # 自機(12.0) + アイテム(28.0) = 40.0 で取得
  end

  def update(px, py, magnet_radius)
    @life -= 1
    if @life <= 0
      vanish
      return
    end

    dx = px - self.x
    dy = py - self.y
    dist_sq = dx * dx + dy * dy
    if dist_sq < magnet_radius * magnet_radius
      dist = Math.sqrt(dist_sq)
      if dist > 0.1
        speed = 14.0
        self.x += (dx / dist) * speed
        self.y += (dy / dist) * speed
      end
    end
  end

  def draw
    return if @life < 100 && (@life % 10) < 5
    if @kind == 1
      # 十字型のハート (回復)
      Window.draw_rect(self.x - 9.0, self.y - 3.0, 18.0, 6.0, color: COLOR_HEART_RED)
      Window.draw_rect(self.x - 3.0, self.y - 9.0, 6.0, 18.0, color: COLOR_HEART_RED)
      return
    end
    c = @value > 10 ? COLOR_EXP_GREEN : Color::YELLOW
    s = @value > 10 ? 12.0 : 8.0
    Window.draw_rect(self.x - s * 0.5, self.y - s * 0.5, s, s, color: c)
  end
end

# ==========================================
# 4. 敵キャラクター (Enemy)
# ==========================================
class Enemy < Sprite
  attr_accessor :radius, :hp, :max_hp, :speed, :sides, :color, :score_value, :is_boss, :flash, :type, :hit_radius

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

    @atlas = Image.new(512, 512)
    @sprites = {}

    configs = {
      fast:   { sides: 3, radius: 18.0,  color: Color::YELLOW, is_boss: false, size: 72,  x0: 0,   y: 0 },
      normal: { sides: 4, radius: 27.0,  color: Color::BLUE,   is_boss: false, size: 72,  x0: 144, y: 0 },
      elite:  { sides: 5, radius: 48.0,  color: Color::RED,    is_boss: false, size: 120, x0: 0,   y: 72 },
      boss:   { sides: 8, radius: 105.0, color: COLOR_PURPLE,  is_boss: true,  size: 240, x0: 0,   y: 192 }
    }

    configs.each do |type, cfg|
      sz = cfg[:size]
      y = cfg[:y]
      line_w = cfg[:is_boss] ? 3.0 : 1.5

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

  def initialize(px, py, type = :normal, hp_mult = 1.0, spawn_ang = nil)
    # 全方位楕円リングスポーン (カメラ外周 360 度から包囲進軍)
    spawn_ang ||= rand(360) * (Math::PI / 180.0)
    rx = 750.0 + rand(120).to_f
    ry = 480.0 + rand(90).to_f
    ix = px + rx * Math.cos(spawn_ang)
    iy = py + ry * Math.sin(spawn_ang)

    super(ix, iy, Enemy.sprites[type][false], anchor: :center, pivot: :center)

    @rotation = 0.0
    @is_boss = false
    @flash = 0 # 被弾時の白フラッシュ残りフレーム
    @type = type

    case type
    when :fast
      @sides = 3
      @radius = 18.0
      base_hp = 1
      @hp = [1, (base_hp * hp_mult).round, hp_mult.to_i].max
      @max_hp = @hp
      @base_speed = 3.4
      @color = Color::YELLOW
      @score_value = 10
      @hit_radius = 15.0
    when :elite
      @sides = 5
      @radius = 48.0
      base_hp = 20
      @hp = [(base_hp * hp_mult).round, 20].max
      @max_hp = @hp
      @base_speed = 1.4
      @color = Color::RED
      @score_value = 50
      @hit_radius = @radius * Math.cos(Math::PI / @sides)
    when :boss
      @sides = 8
      @radius = 105.0
      base_hp = 160
      @hp = [(base_hp * hp_mult).round, 160].max
      @max_hp = @hp
      @base_speed = 0.85
      @color = COLOR_PURPLE
      @score_value = 300
      @is_boss = true
      @hit_radius = @radius * Math.cos(Math::PI / @sides)
    else
      @sides = 4
      @radius = 27.0
      base_hp = 3
      @hp = [(base_hp * hp_mult).round, 3].max
      @max_hp = @hp
      @base_speed = 2.0
      @color = Color::BLUE
      @score_value = 20
      @hit_radius = @radius * Math.cos(Math::PI / @sides)
    end

    # 速度の個体差 (±15% のゆらぎ: 前後の重なり分散)
    @speed = @is_boss ? @base_speed : (@base_speed * (0.85 + rand(31) * 0.01))

    set_collider(:circle, radius: @hit_radius)
  end

  def flash=(v)
    @flash = v
    self.image = Enemy.sprites[@type][@flash > 0]
  end

  # 画面外遠方に置き去りにされた敵を、回収位置と自機から計算して逆方向（逃げ先の前方）に即座に再配置
  def relocate_opposite(px, py, hp_mult = 1.0)
    # 敵から自機へ向かうベクトル（自機から見て敵の真逆方向）
    opposite_ang = Math.atan2(py - self.y, px - self.x)
    ang = opposite_ang + (rand(91) - 45) * (Math::PI / 180.0)
    rx = 760.0 + rand(120).to_f
    ry = 480.0 + rand(90).to_f
    self.x = px + rx * Math.cos(ang)
    self.y = py + ry * Math.sin(ang)

    base_hp = case @type
              when :fast  then 1
              when :elite then 20
              else 3
              end
    @hp = [base_hp, (base_hp * hp_mult).round, hp_mult.to_i].max
    @max_hp = @hp
    @flash = 0
    self.image = Enemy.sprites[@type][false]
  end

  def update(px, py)
    angle_rad = Math.atan2(py - self.y, px - self.x)
    self.x += @speed * Math.cos(angle_rad)
    self.y += @speed * Math.sin(angle_rad)
    @rotation += 0.03
    self.angle = @rotation * (180.0 / Math::PI)
    if @flash > 0
      @flash -= 1
      self.image = Enemy.sprites[@type][false] if @flash == 0
    end
  end

  def draw
    super

    if (@max_hp > 1 && @hp < @max_hp) || @is_boss
      bar_w = @radius * 2.0
      bar_h = @is_boss ? 10.0 : 6.0
      bar_y = self.y - @radius - (@is_boss ? 24.0 : 16.0)
      hp_ratio = @hp.to_f / @max_hp
      hp_ratio = 0.0 if hp_ratio < 0.0
      Window.draw_rect(self.x - bar_w * 0.5, bar_y, bar_w, bar_h, color: COLOR_HP_GRAY, z: 1.0)
      hp_color = @is_boss ? COLOR_BOSS_HP : Color::GREEN
      Window.draw_rect(self.x - bar_w * 0.5, bar_y, bar_w * hp_ratio, bar_h, color: hp_color, z: 1.0)
    end
  end
end

# ==========================================
# 5. プレイヤー (Player)
# ==========================================
class Player < Sprite
  attr_accessor :radius, :sides, :rotation, :speed, :fire_timer, :fire_rate,
                :score, :magnet_radius, :shot_level, :orbiter_count, :missile_level,
                :missile_timer, :orbiters,
                :hp, :max_hp, :invincible, :exp, :level, :fired, :hit_radius

  def rebuild_shape
    # 正三角形 (外接半径 42.0) の内接円 (21.0) 程度のコンパクトな当たり判定
    @hit_radius = 18.0
    set_collider(:circle, radius: @hit_radius)
  end

  def initialize(x, y)
    super(x, y, nil, anchor: :center, pivot: :center)
    @radius = 42.0
    @sides = 3
    @rotation = 0.0
    @speed = 5.0
    @fire_timer = 0
    @fire_rate = 10
    @score = 0
    @magnet_radius = 200.0
    @shot_level = 1
    @orbiter_count = 0
    @missile_level = 0
    @missile_timer = 0
    @orbiters = []
    @hp = 3
    @max_hp = 3
    @invincible = 0 # 被弾後の無敵残りフレーム
    @exp = 0
    @level = 1
    @fired = false  # このフレームにメインショットを撃ったか (効果音用)
    rebuild_shape
  end

  # 次のレベルに必要な経験値 (レベルが上がるにつれて段階的に増加)
  def exp_to_next
    # 初期は50、序盤はテンポよく上がり、敵大群が押し寄せるLv10以降は必要量を増やして連続停止を緩和
    lv = @level - 1
    req = 50 + lv * 40 + (lv * lv * 4)
    if @level > 10
      extra = @level - 10
      req += extra * 100 + (extra * extra * 12)
    end
    req
  end

  # ダメージを受けたら true を返す (無敵中は false)
  def take_damage(amount)
    return false if @invincible > 0
    @hp -= amount
    @hp = 0 if @hp < 0
    @invincible = 45
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
    self.x += dx * @speed
    self.y += dy * @speed

    if camera
      mx, my = camera.screen_to_world(Input.mouse_x, Input.mouse_y)
    else
      cx = self.x - 1280.0 / 2.0
      cy = self.y - 720.0 / 2.0
      mx = Input.mouse_x + cx
      my = Input.mouse_y + cy
    end

    # マウス追従
    if Input.mouse_pressed?(:left)
      dx = mx - self.x
      dy = my - self.y
      dist = Math.sqrt(dx * dx + dy * dy)
      if dist > 0.001
        ratio = dist / 150.0
        ratio = 1.0 if ratio > 1.0
        move_speed = @speed * ratio
        if dist > move_speed
          self.x += (dx / dist) * move_speed
          self.y += (dy / dist) * move_speed
        else
          self.x = mx
          self.y = my
        end
      end
    end

    # 照準
    rx = Input.rx
    ry = Input.ry
    if rx != 0.0 || ry != 0.0
      @rotation = Math.atan2(ry, rx)
    else
      @rotation = Math.atan2(my - self.y, mx - self.x)
    end
    self.angle = @rotation * (180.0 / Math::PI)

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
          next if e.vanished?
          dx = e.x - self.x
          dy = e.y - self.y
          d2 = dx * dx + dy * dy
          if d2 < min_dist_sq
            min_dist_sq = d2
            nearest_enemy = e
          end
        end
        if nearest_enemy
          missiles << Missile.new(self.x, self.y, nearest_enemy.x, nearest_enemy.y)
        end
      end
    end

    # オービター更新
    @orbiters.each { |orb| orb.update(self.x, self.y) }
  end

  def fire_shots(bullets, particles)
    # 1. 正面頂点からのショット (shot_level に応じた WAY 拡散)
    front_ang = @rotation
    front_vx = self.x + @radius * Math.cos(front_ang)
    front_vy = self.y + @radius * Math.sin(front_ang)

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
        vx = self.x + @radius * Math.cos(ang)
        vy = self.y + @radius * Math.sin(ang)
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
        vx1 = self.x + @radius * Math.cos(angle1)
        vy1 = self.y + @radius * Math.sin(angle1)

        angle2 = @rotation + ((i + 1) % @sides) * (2.0 * Math::PI / @sides)
        vx2 = self.x + @radius * Math.cos(angle2)
        vy2 = self.y + @radius * Math.sin(angle2)

        Window.draw_triangle(self.x, self.y, vx2, vy2, vx1, vy1, color: body_color)
        Window.draw_line(vx1, vy1, vx2, vy2, color: Color::WHITE, width: 1.5)
        Window.draw_rect(vx1 - 3.0, vy1 - 3.0, 6.0, 6.0, color: Color::WHITE)
      end
    end

    @orbiters.each(&:draw)
  end
end

# ==========================================
# 6. ゲームワールド (Game)
#    自機・敵・弾などの「ステージを跨いで共有されるもの」を一括保持する。
#    どの画面 (シーン) からも同じ Game インスタンスを参照して使う。
# ==========================================
class Game
  attr_accessor :player, :camera, :bullets, :missiles, :enemies, :items, :particles, :damage_texts, :crt_enabled, :collision_mode
  attr_reader :sfx, :best_score, :new_record, :kills, :max_combo, :frames_alive

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
    @crt_enabled = true
    @crt_shader = nil
    @shockwave_shader = nil
    @collision_mode = :exact # :exact (Collision GJK) または :simple (円判定)
    @show_profiler = false
    @crt_time = 0.0
    reset_world
  end

  # 新しいゲームを開始 (ワールドを初期化して開始音を鳴らす)
  def new_game
    reset_world
    @sfx.play(Sfx::LEVELUP, 10)
    self
  end

  # ワールド全体を初期状態に戻す (リトライ時にも使用)
  def reset_world
    @player = Player.new(1280.0 / 2.0, 720.0 / 2.0)
    @camera = Camera.new(target: @player, smooth_speed: 0.8)
    @bullets = []
    @missiles = []
    @enemies = []
    @items = []
    @particles = []
    @damage_texts = []
    @spawn_timer = 0
    @spawn_interval = 50.0
    @enemy_stock = 0
    @wave_minute = 0
    @boss_spawn_timer = 1200 # 20秒ごとに出現

    # 演出
    @hitstop = 0         # ヒットストップ残りフレーム
    @damage_flash = 0    # 被弾時の赤フラッシュ残りフレーム

    # ポストエフェクト演出 (衝撃波 & グリッチ)
    @shockwave_timer = 0
    @shockwave_max_timer = 50
    @shockwave_cx = 0.5
    @shockwave_cy = 0.5
    @shockwave_radius = 0.0
    @shockwave_force = 0.0
    @glitch_timer = 0

    # 戦績
    @frames_alive = 0
    @kills = 0
    @combo = 0
    @combo_timer = 0
    @max_combo = 0
    @new_record = false

    # 死亡演出
    @player_dead = false
    @death_timer = 0
  end

  def add_shake(amount)
    @camera.shake([amount * 1.5, 20.0].min, 0.25)
  end

  def add_hitstop(frames)
    @hitstop = frames if frames > @hitstop
  end

  # 経過時間に応じた敵HP倍率 (60秒 = 3600フレームごとに約50%増加)
  def enemy_hp_multiplier
    1.0 + (@frames_alive / 3600.0) * 0.5
  end

  # 経過時間に応じた敵同時上限数 (初期100体、1分=3600フレームごとに+100)
  def max_enemies
    100 + (@frames_alive / 3600) * 100
  end

  def spawn_one_enemy(hp_mult)
    px = @player.x
    py = @player.y
    r = rand(100)
    if r < 40
      @enemies << Enemy.new(px, py, :fast, hp_mult)
    elsif r < 80
      @enemies << Enemy.new(px, py, :normal, hp_mult)
    else
      @enemies << Enemy.new(px, py, :elite, hp_mult)
    end
  end

  def spawn_enemies
    # スポーン間隔の最短下限を 1.0 (毎フレーム=毎秒60体) まで加速
    if @spawn_interval > 1.0
      @spawn_interval -= 0.02
    end

    px = @player.x
    py = @player.y
    cull_sq = 1200.0 * 1200.0
    hp_mult = enemy_hp_multiplier
    limit = max_enemies

    # 1分ごとの上限増加ウェーブ (1分: 黄色100体, 2分: 青100体, 3分: 赤100体, 4分: ボス)
    current_min = @frames_alive / 3600
    if current_min > @wave_minute
      @wave_minute = current_min
      wave_type = case current_min
                  when 1 then :fast
                  when 2 then :normal
                  when 3 then :elite
                  when 4 then :boss
                  else
                    cycle = ((current_min - 1) % 4) + 1
                    [:fast, :normal, :elite, :boss][cycle - 1]
                  end

      count = (wave_type == :boss ? 30 : 100)
      count.times do |i|
        ang = (i.to_f / count.to_f) * (2.0 * Math::PI) + (rand(11) - 5) * (Math::PI / 180.0)
        @enemies << Enemy.new(px, py, wave_type, hp_mult, ang)
      end
    end

    # 画面外遠方 (半径1200px超) に置き去りにされた敵を回収し、逆方向 (逃げ先の前方) に即座に再配置 (ボスは維持)
    @enemies.each do |e|
      next if e.is_boss
      dx = e.x - px
      dy = e.y - py
      if dx * dx + dy * dy > cull_sq
        e.relocate_opposite(px, py, hp_mult)
      end
    end

    # 上限枠に空きがあり、ストックがあるなら即座に補充
    if @enemy_stock > 0 && @enemies.size < limit
      slots = [limit - @enemies.size, @enemy_stock].min
      slots.times { spawn_one_enemy(hp_mult) }
      @enemy_stock -= slots
    end

    @spawn_timer -= 1
    if @spawn_timer <= 0
      @spawn_timer = @spawn_interval.to_i
      if @enemies.size < limit
        spawn_one_enemy(hp_mult)
      else
        @enemy_stock += 1
      end
    end

    @boss_spawn_timer -= 1
    if @boss_spawn_timer <= 0
      @boss_spawn_timer = 1500 # 25秒ごと
      @enemies << Enemy.new(px, py, :boss, hp_mult)
    end
  end

  # 敵同士の重なり防止
  def separate_enemies
    return if @enemies.size < 2

    Sprite.each_pair_spatial(@enemies, cell_size: 96.0) do |e1, e2|
      resolve_enemy_overlap(e1, e2)
    end
  end

  # 敵同士のめり込み解消ヘルパー
  def resolve_enemy_overlap(e1, e2)
    dx = e2.x - e1.x
    r_sum = e1.hit_radius + e2.hit_radius
    return if dx.abs > r_sum
    dy = e2.y - e1.y
    return if dy.abs > r_sum

    d2 = dx * dx + dy * dy
    if d2 < r_sum * r_sum && d2 > 0.0001
      d = Math.sqrt(d2)
      overlap = r_sum - d
      return if overlap <= 0.0
      push = overlap * 0.4
      inv_d = 1.0 / d
      nx = dx * inv_d * push
      ny = dy * inv_d * push

      if e1.is_boss && e2.is_boss
        e1.x -= nx
        e1.y -= ny
        e2.x += nx
        e2.y += ny
      elsif e1.is_boss
        e2.x += nx * 2.0
        e2.y += ny * 2.0
      elsif e2.is_boss
        e1.x -= nx * 2.0
        e1.y -= ny * 2.0
      elsif e1.max_hp > 5 && e2.max_hp <= 5
        e2.x += nx * 2.0
        e2.y += ny * 2.0
      elsif e2.max_hp > 5 && e1.max_hp <= 5
        e1.x -= nx * 2.0
        e1.y -= ny * 2.0
      else
        e1.x -= nx
        e1.y -= ny
        e2.x += nx
        e2.y += ny
      end
    end
  end

  def check_collisions
    contact_damage = 0
    boss_hit = false

    # 1. 通常弾 vs 敵 (Sprite.check: Sweep and Prune による一括高速判定)
    Sprite.check(@bullets, @enemies) do |b, e|
      b.vanish
      damage_enemy(e, b.damage, Color::YELLOW)
    end

    # 2. ミサイル直撃 vs 敵 (Sprite.check)
    Sprite.check(@missiles, @enemies) do |m, e|
      m.explode
    end

    # 3. オービター刃 vs 敵 (Sprite.check)
    Sprite.check(@player.orbiters, @enemies) do |orb, e|
      damage_enemy(e, orb.damage, Color::CYAN)
    end

    # 4. 自機 vs 敵 (Sprite.check)
    unless @player_dead
      Sprite.check(@player, @enemies) do |p, e|
        if e.is_boss
          boss_hit = true
          contact_damage = 2
        elsif contact_damage < 1
          contact_damage = 1
        end
      end
    end

    # 5. ミサイルの範囲爆発処理
    @missiles.each do |m|
      if m.exploded
        m.exploded = false
        create_explosion(m.x, m.y, 65.0, m.damage)
      end
    end

    # 6. 自機の被弾処理 (無敵時間中は無効)
    if contact_damage > 0 && @player.take_damage(contact_damage)
      on_player_damaged(boss_hit)
    end

    # 7. アイテム取得判定 (自機 vs アイテム: Sprite.check)
    unless @player_dead
      Sprite.check(@player, @items) do |p, item|
        item.vanish
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
      next if e.vanished? || e.is_boss
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
      e.vanish
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
      # 回復ハートドロップ (10% の確率)
      @items << Item.new(e.x, e.y, 0, 1) if rand(100) < 10
      add_shake(9.0)
      add_hitstop(8)
      @sfx.play(Sfx::BOSS_KILL, 20)
      Input.vibrate_gamepad(0, 1.0, 0.6, 0.3)

      # 画面ポストエフェクト (衝撃波歪み & CRT受信障害グリッチ)
      # ボスのワールド座標をスクリーンUV座標 (0.0〜1.0) に変換
      sx = (e.x - (@camera.x - 640.0)) / 1280.0
      sy = (e.y - (@camera.y - 360.0)) / 720.0
      sx = 0.05 if sx < 0.05
      sx = 0.95 if sx > 0.95
      sy = 0.05 if sy < 0.05
      sy = 0.95 if sy > 0.95
      @shockwave_cx = sx.to_f
      @shockwave_cy = sy.to_f
      @shockwave_max_timer = 50
      @shockwave_timer = @shockwave_max_timer
      @shockwave_radius = 0.0
      @shockwave_force = 0.08
      @glitch_timer = 70
    elsif e.type == :elite
      # エリート撃破
      25.times do
        ang = rand(360) * Math::PI / 180.0
        spd = rand(7).to_f + 2.0
        spawn_particle(Particle.new(e.x, e.y, spd * Math.cos(ang), spd * Math.sin(ang), rand(20) + 15, Color::RED, 7.0))
      end
      4.times do
        @items << Item.new(e.x + (rand(40) - 20).to_f, e.y + (rand(40) - 20).to_f, 20)
      end
      # 2% の確率で回復ハートをドロップ
      @items << Item.new(e.x, e.y, 0, 1) if rand(100) < 2
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
      next if e.vanished?
      dx = e.x - x
      dy = e.y - y
      if dx * dx + dy * dy < radius * radius
        damage_enemy(e, damage, COLOR_ORANGE)
      end
    end
  end

  # ==========================================
  # フレーム共通更新 & ポストエフェクト描画
  # ==========================================
  def update_frame_common
    # プロファイラ表示トグル ([F3] または [TAB] キー)
    if Input.key_push?(:f3) || Input.key_push?(:tab)
      @show_profiler = !@show_profiler
    end

    @sfx.tick

    # ポストエフェクトタイマー更新 (衝撃波 & CRTグリッチ)
    if @shockwave_timer > 0
      @shockwave_timer -= 1
      progress = 1.0 - (@shockwave_timer.to_f / @shockwave_max_timer.to_f)
      @shockwave_radius = progress * 1.5
      @shockwave_force = (1.0 - progress) * 0.08
    end
    @glitch_timer -= 1 if @glitch_timer > 0
    @crt_time += 0.05

    # CRT エフェクトの初期化とトグル切り替え ([C] キー)
    @crt_shader ||= Shader.new(CRT_FRAGMENT_SHADER)
    if Input.key_push?(:c)
      @crt_enabled = !@crt_enabled
    end

    if Input.key_push?(:m)
      @collision_mode = (@collision_mode == :exact ? :simple : :exact)
    end
  end

  # ポストエフェクト (衝撃波 / CRT) を適用してブロック内の描画を実行 (Profiler.measure(:render) で計測)
  def render_with_post_effects
    Profiler.measure(:render) do
      if @crt_enabled || @shockwave_timer > 0
        @game_screen ||= Image.create_msaa(1280, 720)
        Image.render_to(@game_screen) do
          Window.clear(Color::BLACK)
          yield
        end

        current_source = @game_screen

        # 第1段: 衝撃波エフェクト (ボス撃破時の歪み波面)
        if @shockwave_timer > 0
          @shockwave_shader ||= Shader.new(SHOCKWAVE_FRAGMENT_SHADER)
          @shockwave_shader.set_vec2("u_center", @shockwave_cx.to_f, @shockwave_cy.to_f)
          @shockwave_shader.set_float("u_radius", @shockwave_radius.to_f)
          @shockwave_shader.set_float("u_force", @shockwave_force.to_f)

          if @crt_enabled
            @post_screen ||= Image.new(1280, 720)
            Image.render_to(@post_screen) do
              Window.clear(Color::BLACK)
              Window.draw(0, 0, current_source, shader: @shockwave_shader)
            end
            current_source = @post_screen
          else
            Window.clear(Color::BLACK)
            Window.draw(0, 0, current_source, shader: @shockwave_shader)
            current_source = nil
          end
        end

        # 第2段: レトロCRTシェーダー + 受信障害グリッチ
        if @crt_enabled && current_source
          @crt_shader.set_float("u_time", @crt_time.to_f)
          glitch_val = @glitch_timer > 0 ? (@glitch_timer.to_f / 70.0) : 0.0
          @crt_shader.set_float("u_glitch", glitch_val.to_f)

          Window.clear(Color::BLACK)
          Window.draw(0, 0, current_source, shader: @crt_shader)
        end
      else
        Window.clear(Color::BLACK)
        yield
      end
    end
  end

  # プロファイラGUIの描画 (ポストエフェクトの歪みを受けないよう最前面に描画)
  def draw_profiler_gui
    if @show_profiler
      Profiler.measure(:gui) do
        GUI.window("Profiler [F3 / TAB]", x: 20, y: 50, w: 320, h: 270) do
          GUI.profile_graph(w: 290, h: 80, max_ms: 33.33)
        end
      end
    end
  end

  # ==========================================
  # プレイ本編の更新と描画
  # ==========================================
  def update_play
    if Input.action_push?(:pause) && !@player_dead
      Scene.push(PauseScene.new(self))
      return
    end

    # デバッグ操作: [B] キーでボスを即座に召喚
    if Input.key_push?(:b)
      @enemies << Enemy.new(@player.x + 200.0, @player.y, :boss, enemy_hp_multiplier)
    end

    @damage_flash -= 1 if @damage_flash > 0

    # ヒットストップ中はワールドを止める (カメラ減衰と描画のみ継続)
    if @hitstop > 0
      @hitstop -= 1
      @camera.update
      return
    end

    # コンボ時間切れ
    if @combo_timer > 0
      @combo_timer -= 1
      @combo = 0 if @combo_timer <= 0
    end

    # 1. 敵スポーン
    spawn_enemies unless @player_dead

    # 2. オブジェクト更新 (カテゴリ別にプロファイル計測)
    unless @player_dead
      @frames_alive += 1
      Profiler.measure(:player) do
        @player.update(@bullets, @missiles, @enemies, @particles, @camera)
        @sfx.play(Sfx::SHOT, 4) if @player.fired
      end
    end

    @bullets.each { |b| b.update }

    Profiler.measure(:missile) do
      @missiles.each { |m| m.update(@enemies) }
    end

    Profiler.measure(:enemy_move) do
      @enemies.each { |e| e.update(@player.x, @player.y) }
    end

    Profiler.measure(:separate) do
      separate_enemies
    end

    @items.each { |i| i.update(@player.x, @player.y, @player.magnet_radius) }
    @particles.each { |p| p.update }
    @damage_texts.each { |t| t.update }

    # 3. 当たり判定 (物理・衝突)
    Profiler.measure(:physics) do
      check_collisions
    end

    # 4. オブジェクトの自然な回収 (Sprite.clean)
    Profiler.measure(:gc) do
      Sprite.clean(@bullets)
      Sprite.clean(@missiles)
      Sprite.clean(@enemies)
      Sprite.clean(@items)
      Sprite.clean(@particles)
      Sprite.clean(@damage_texts)

      # 敵を倒して空いた枠へ、ストックから即座にスポーン補充
      limit = max_enemies
      if @enemy_stock > 0 && @enemies.size < limit
        slots = [limit - @enemies.size, @enemy_stock].min
        hp_mult = enemy_hp_multiplier
        slots.times { spawn_one_enemy(hp_mult) }
        @enemy_stock -= slots
      end
    end

    # カメラ更新 (ターゲット追従 & 画面シェイク減衰)
    @camera.update

    # 5. 死亡演出 → リザルト画面を上に重ねる (背景の戦場はそのまま静止表示)
    if @player_dead
      @death_timer -= 1
      if @death_timer <= 0
        if @player.score > @best_score
          @best_score = @player.score
          @new_record = true
        end
        Scene.push(GameOverScene.new(self))
      end
      return
    end

    # 6. レベルアップ判定 → レベルアップ画面を上に重ねる
    if @player.exp >= @player.exp_to_next
      Scene.push(LevelUpScene.new(self))
    end
  end

  def draw_play
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

    # 被弾の赤フラッシュ
    if @damage_flash > 0
      Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: Color.new(255, 0, 0, @damage_flash * 8), z: 10.0)
    end

    Profiler.measure(:hud) do
      draw_hud
    end
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
    else true # HP全回復は常に選択可能
    end
  end

  # レベルを 1 上げ、選択可能なアップグレードから最大 3 つ抽選して返す
  def prepare_levelup_choices
    @player.exp -= @player.exp_to_next
    @player.level += 1
    @sfx.play(Sfx::LEVELUP, 10)

    candidates = []
    UPGRADE_COUNT.times do |i|
      candidates << i if upgrade_available?(i)
    end
    choices = []
    while choices.size < 3 && candidates.size > 0
      pick = rand(candidates.size)
      choices << candidates[pick]
      candidates.delete_at(pick)
    end
    choices
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
    when 7 # HP全回復
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
    else "REPAIR"
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
    else "Recover HP to full (#{@player.hp} -> #{@player.max_hp})"
    end
  end

  # ==========================================
  # 描画ヘルパー
  # ==========================================
  def time_str(frames)
    sec = frames / 60
    m = sec / 60
    s = sec % 60
    s_str = s < 10 ? "0#{s}" : "#{s}"
    "#{m}:#{s_str}"
  end

  def draw_centered(y, text, size, color, font = Font::SINCLAIR, z: 0.0)
    Window.draw_text(640.0, y, text, font: font, size: size, color: color, align: :center, z: z)
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
    # HUD (UI: z: 5.0 でワールドやHPバー(z: 1.0)より手前、メニュー(z: 10.0)より奥に配置)
    hud_str = "SCORE: #{@player.score}   TIME: #{time_str(@frames_alive)}   LV: #{@player.level}"
    Window.draw_text(20.0, 20.0, hud_str, font: Font::SINCLAIR, size: 24, color: Color::WHITE, z: 5.0)

    # HP (ハートブロック)
    @player.max_hp.times do |i|
      hx = 20.0 + i.to_f * 30.0
      c = i < @player.hp ? COLOR_HEART_RED : COLOR_HP_GRAY
      Window.draw_rect(hx, 56.0, 24.0, 18.0, color: c, z: 5.0)
    end

    # コンボ表示 (右揃え align: :right)
    if @combo >= 3
      combo_size = 28 + (@combo > 40 ? 20 : @combo / 2)
      combo_str = "#{@combo} COMBO  x#{combo_multiplier}"
      w = Window.text_width(combo_str, font: Font::SINCLAIR, size: combo_size)
      ratio = @combo_timer.to_f / 120.0
      Window.draw_text(1260.0, 20.0, combo_str, font: Font::SINCLAIR, size: combo_size, color: COLOR_ORANGE, align: :right, z: 5.0)
      Window.draw_rect(1260.0 - w, 24.0 + combo_size.to_f, w * ratio, 4.0, color: COLOR_ORANGE, z: 5.0)
    end

    # EXPバー (画面下端)
    exp_ratio = @player.exp.to_f / @player.exp_to_next
    exp_ratio = 1.0 if exp_ratio > 1.0
    Window.draw_rect(0.0, 710.0, 1280.0, 10.0, color: COLOR_EXP_BAR_BG, z: 5.0)
    Window.draw_rect(0.0, 710.0, 1280.0 * exp_ratio, 10.0, color: COLOR_EXP_GREEN, z: 5.0)

    # デバッグ情報
    pad_str = Input.gamepad_connected?(0) ? "[PAD: ON]" : "[PAD: OFF]"
    stock_str = @enemy_stock > 0 ? " (+#{@enemy_stock})" : ""
    dbg_str = "FPS: #{Window.fps.to_i}  ENEMY: #{@enemies.size}#{stock_str}  [F3/TAB: Profiler]  #{pad_str}  [C: CRT #{@crt_enabled ? 'ON' : 'OFF'}]  [B: Boss]"
    Window.draw_text(20.0, 684.0, dbg_str, font: Font::SINCLAIR, size: 14, color: COLOR_TEXT_GRAY, z: 5.0)
  end
end

# ==========================================
# 7. シーン定義 (Zenoo::Scene)
#    - 各シーンは `call` メソッド 1 個だけ (更新と描画を分けない)
#    - ポーズ / レベルアップ / ゲームオーバーは PlayScene の上に `Scene.push` で重ねる
#      → 下の PlayScene は自動的に停止し、直前の描画キューがそのまま背景として再描画される
#    - 各シーンで更新と描画を Profiler.measure で計測するため、処理負荷の内訳を正確に追跡可能
# ==========================================

# タイトル画面
class TitleScene < Scene
  def initialize(game)
    @game = game
  end

  def call
    t = frames
    @game.draw_screen_grid(t.to_f * 0.6, t.to_f * 0.3)

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

    @game.draw_centered(100.0, "ZENOO SURVIVOR", 56, Color::WHITE, Font::MPLUS)
    @game.draw_centered(180.0, "Grow your shape. Survive the swarm.", 20, COLOR_TEXT_GRAY)

    if (t / 30) % 2 == 0
      @game.draw_centered(470.0, "PRESS ENTER / A / CLICK TO START", 24, Color::CYAN)
    end

    @game.draw_centered(540.0, "MOVE: WASD / Stick / Hold Left Click    AIM: Mouse / Right Stick", 18, Color::WHITE)
    @game.draw_centered(570.0, "PAUSE: ESC / START / Right Click    CRT: [C]", 18, Color::WHITE)
    @game.draw_centered(630.0, "BEST SCORE: #{@game.best_score}", 22, COLOR_ORANGE) if @game.best_score > 0

    Profiler.measure(:update) do
      if frames > 10 && Input.action_push?(:ui_accept)
        Scene.change(PlayScene.new(@game.new_game))
      end
    end
  end
end

# プレイ本編画面
class PlayScene < Scene
  def initialize(game)
    @game = game
  end

  def call
    Profiler.measure(:update) do
      @game.update_play
    end
    @game.draw_play
  end
end

# ポーズ画面 (PlayScene の上に push して重ねる)
class PauseScene < Scene
  def initialize(game)
    @game = game
  end

  def call
    p = @game.player
    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG, z: 10.0)
    @game.draw_centered(130.0, "=== PAUSED ===", 40, Color::WHITE, Font::SINCLAIR, z: 10.0)

    lines = [
      "LEVEL      : #{p.level}",
      "HP         : #{p.hp} / #{p.max_hp}",
      "SHAPE      : #{p.sides} sides",
      "SPREAD     : #{p.shot_level} way",
      "ORBITER    : #{p.orbiter_count} blades",
      "MISSILE    : Lv #{p.missile_level}",
      "SPEED      : #{p.speed.to_i}",
      "FIRE RATE  : #{p.fire_rate} frames",
      "MAGNET     : #{p.magnet_radius.to_i}"
    ]
    lines.each_with_index do |line, i|
      Window.draw_text(460.0, 210.0 + i.to_f * 34.0, line, font: Font::SINCLAIR, size: 22, color: Color::WHITE, z: 10.0)
    end

    @game.draw_centered(560.0, "ESC / START / Right Click / (B) to Resume", 20, Color::WHITE, Font::SINCLAIR, z: 10.0)
    @game.draw_centered(595.0, "Q / (Y) to Title    [C] CRT: #{@game.crt_enabled ? 'ON' : 'OFF'}    Collision: [Sprite.check / SAP]", 18, COLOR_TEXT_GRAY, Font::SINCLAIR, z: 10.0)

    Profiler.measure(:update) do
      if Input.action_push?(:pause) || Input.action_push?(:ui_cancel)
        Scene.pop
      elsif Input.key_push?(:q) || Input.gamepad_button_push?(:y)
        Scene.change(TitleScene.new(@game))
      end
    end
  end
end

# レベルアップ 3 択画面 (PlayScene の上に push して重ねる)
class LevelUpScene < Scene
  def initialize(game)
    @game = game
    @choices = @game.prepare_levelup_choices
    @cursor = 0
    @prev_mx = Input.mouse_x
    @prev_my = Input.mouse_y
    @flash = 10
  end

  def row_top(i)
    250.0 + i.to_f * 100.0
  end

  def call
    # レベルアップ瞬間の白フラッシュ
    if @flash > 0
      Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: Color.new(255, 255, 255, @flash * 10), z: 10.0)
      @flash -= 1
    end

    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG, z: 10.0)
    @game.draw_centered(130.0, "LEVEL UP!", 56, COLOR_EXP_GREEN, Font::SINCLAIR, z: 10.0)
    @game.draw_centered(200.0, "Choose one upgrade", 20, COLOR_TEXT_GRAY, Font::SINCLAIR, z: 10.0)

    @choices.each_with_index do |idx, i|
      top = row_top(i)
      is_selected = (@cursor == i)

      if is_selected
        Window.draw_rect(240.0, top, 800.0, 80.0, color: COLOR_BUTTON_HOVER, z: 10.0)
        Window.draw_rect(236.0, top, 4.0, 80.0, color: Color::CYAN, z: 10.0)
      else
        Window.draw_rect(240.0, top, 800.0, 80.0, color: Color.new(30, 30, 38, 220), z: 10.0)
      end

      title_color = is_selected ? Color::CYAN : Color::WHITE
      prefix = is_selected ? "> " : "  "
      Window.draw_text(260.0, top + 14.0, "#{prefix}#{@game.upgrade_title(idx)}", font: Font::SINCLAIR, size: 26, color: title_color, z: 10.0)
      Window.draw_text(300.0, top + 48.0, @game.upgrade_desc(idx), font: Font::SINCLAIR, size: 18, color: COLOR_TEXT_GRAY, z: 10.0)
    end

    @game.draw_centered(570.0, "[UP/DOWN/Stick] Select   [A / ENTER / Click] Choose", 20, Color::WHITE, Font::SINCLAIR, z: 10.0)

    Profiler.measure(:update) do
      # 上下選択入力
      count = @choices.size
      if Input.action_push?(:ui_up)
        @cursor = (@cursor - 1) % count
        @game.sfx.play(Sfx::SELECT, 2)
      elsif Input.action_push?(:ui_down)
        @cursor = (@cursor + 1) % count
        @game.sfx.play(Sfx::SELECT, 2)
      end

      # マウスホバー選択 (マウスが動いたときだけカーソルを合わせる)
      mx = Input.mouse_x
      my = Input.mouse_y
      mouse_moved = (mx != @prev_mx || my != @prev_my)
      @prev_mx = mx
      @prev_my = my
      mouse_hover_idx = -1
      count.times do |i|
        top = row_top(i)
        if mx >= 240.0 && mx <= 1040.0 && my >= top && my <= top + 80.0
          mouse_hover_idx = i
          @cursor = i if mouse_moved
          break
        end
      end

      # 画面が開いた直後の誤入力防止も frames で 1 行
      return if frames < 20

      buy_pressed = Input.action_push?(:ui_accept)
      if mouse_hover_idx >= 0 && Input.mouse_push?(:left)
        @cursor = mouse_hover_idx
        buy_pressed = true
      end
      return unless buy_pressed

      @game.execute_skill_upgrade(@choices[@cursor])
      @game.sfx.play(Sfx::HEAL, 4)
      Scene.pop
    end
  end
end

# ゲームオーバー画面 (PlayScene の上に push して重ねる)
class GameOverScene < Scene
  def initialize(game)
    @game = game
  end

  def call
    p = @game.player
    Window.draw_rect(0.0, 0.0, 1280.0, 720.0, color: COLOR_MENU_BG, z: 10.0)
    @game.draw_centered(110.0, "GAME OVER", 64, COLOR_HEART_RED, Font::SINCLAIR, z: 10.0)

    lines = [
      "TIME       : #{@game.time_str(@game.frames_alive)}",
      "LEVEL      : #{p.level}",
      "KILLS      : #{@game.kills}",
      "MAX COMBO  : #{@game.max_combo}",
      "SCORE      : #{p.score}",
      "BEST       : #{@game.best_score}"
    ]
    lines.each_with_index do |line, i|
      Window.draw_text(470.0, 220.0 + i.to_f * 40.0, line, font: Font::SINCLAIR, size: 26, color: Color::WHITE, z: 10.0)
    end

    if @game.new_record && (frames / 15) % 2 == 0
      @game.draw_centered(480.0, "NEW RECORD!", 32, COLOR_ORANGE, Font::SINCLAIR, z: 10.0)
    end

    if frames > 45 && (frames / 30) % 2 == 0
      @game.draw_centered(570.0, "PRESS ENTER / A / CLICK TO RETRY", 26, Color::CYAN, Font::SINCLAIR, z: 10.0)
    end

    Profiler.measure(:update) do
      if frames > 45 && Input.action_push?(:ui_accept)
        Scene.change(PlayScene.new(@game.new_game))
      end
    end
  end
end

# ==========================================
# 8. 初期化 & メインループ
# ==========================================
Enemy.init_atlas
game = Game.new
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

# 自動テスト時はタイトルを飛ばしてプレイ画面から開始 (ZENOO_TEST_TITLE 指定時はタイトルをテスト)
if test_max > 0 && ENV['ZENOO_TEST_TITLE'] != '1'
  Scene.change(PlayScene.new(game))
else
  Scene.change(TitleScene.new(game))
end

if ENV['ZENOO_TEST_ENEMIES']
  ENV['ZENOO_TEST_ENEMIES'].to_i.times do
    game.enemies << Enemy.new(game.player.x, game.player.y, :normal)
  end
end

Window.loop(1280, 720, "Zenoo Survival Shooting Game") do
  game.update_frame_common

  game.render_with_post_effects do
    Scene.call
  end

  game.draw_profiler_gui

  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "Game test completed successfully! (#{frame_count} frames, enemies=#{game.enemies.size})"
      puts "=== Profiler Average Times (ms) over last 60 frames ==="
      times = Zenoo::Profiler.average_times(60)
      times.each do |cat, ms|
        printf("  %-15s: %6.2f ms\n", cat, ms)
      end
      printf("  %-15s: %6.2f ms\n", "TOTAL", times.values.sum)
      exit
    end
  end
end

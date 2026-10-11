# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Billiards & MTV (Minimum Translation Vector) Physics Demo
# - 画面外周のクッション壁と点在する障害物 (OBB/角丸矩形)
# - Collision.penetration を用いた完全めり込み解消＆高精度弾性衝突物理
# - 左ドラッグで狙いとパワーを決めてショット！
# - [R]: リセット  |  [SPACE]: 全ボール拡散  |  [S]: 全ボール停止
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. 衝突スパーク・パーティクル
# ------------------------------------------------------------------------------
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
    @vx *= 0.92
    @vy *= 0.92
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

# ------------------------------------------------------------------------------
# 2. 壁・障害物 (Rect / OBB / 角丸矩形)
# ------------------------------------------------------------------------------
class Wall
  attr_accessor :x, :y, :width, :height, :angle, :radius, :color, :border_color, :shape

  def initialize(x, y, w, h, angle: 0.0, radius: 0.0, color: [35, 55, 48, 255], border_color: [80, 160, 120, 255])
    @x = x.to_f
    @y = y.to_f
    @width = w.to_f
    @height = h.to_f
    @angle = angle.to_f
    @radius = radius.to_f
    @color = color
    @border_color = border_color
    @shape = Collision.rect(@x, @y, @width, @height, angle: @angle, radius: @radius, anchor: :center)
  end

  def draw
    # Window.draw_rect は左上基準なので中心からオフセット
    Window.draw_rect(
      @x - @width * 0.5, @y - @height * 0.5,
      @width, @height,
      radius: @radius,
      color: @color,
      border_width: 2,
      border_color: @border_color,
      shadow_blur: 12,
      shadow_color: [0, 0, 0, 120],
      angle: @angle,
      pivot: :center
    )
  end
end

# ------------------------------------------------------------------------------
# 3. ボール (Ball)
# ------------------------------------------------------------------------------
class Ball
  attr_accessor :x, :y, :vx, :vy, :radius, :color, :number, :is_cue, :shape, :highlight

  BALL_COLORS = [
    [255, 215, 0, 255],   # 1: 黄
    [30, 120, 240, 255],  # 2: 青
    [230, 45, 45, 255],   # 3: 赤
    [155, 60, 200, 255],  # 4: 紫
    [255, 125, 30, 255],  # 5: オレンジ
    [35, 175, 80, 255],   # 6: 緑
    [150, 40, 40, 255],   # 7: えんじ
    [20, 20, 25, 255],    # 8: 黒
    [255, 215, 0, 255],   # 9: 黄ストライプ
    [30, 120, 240, 255],  # 10: 青ストライプ
    [230, 45, 45, 255],   # 11: 赤ストライプ
    [155, 60, 200, 255],  # 12: 紫ストライプ
    [255, 125, 30, 255],  # 13: オレンジストライプ
    [35, 175, 80, 255],   # 14: 緑ストライプ
    [150, 40, 40, 255]    # 15: えんじストライプ
  ].freeze

  def initialize(x, y, number = 0, radius = 17.0)
    @x = x.to_f
    @y = y.to_f
    @vx = 0.0
    @vy = 0.0
    @radius = radius.to_f
    @number = number
    @is_cue = (number == 0)
    @color = @is_cue ? [250, 250, 252, 255] : BALL_COLORS[(number - 1) % BALL_COLORS.length]
    @shape = Collision.circle(@x, @y, @radius, anchor: :center)
    @highlight = false
  end

  def speed
    Math.sqrt(@vx * @vx + @vy * @vy)
  end

  def moving?
    @vx.abs > 0.04 || @vy.abs > 0.04
  end

  def update(substep_factor = 1.0)
    @x += @vx * substep_factor
    @y += @vy * substep_factor
    @shape.x = @x
    @shape.y = @y

    # 転がり摩擦 (徐々に減速)
    friction = 0.992**substep_factor
    @vx *= friction
    @vy *= friction

    if @vx.abs < 0.03 && @vy.abs < 0.03
      @vx = 0.0
      @vy = 0.0
    end
  end

  def draw
    sp = speed

    # 移動時のシャドウ
    Window.draw_circle(@x + 3, @y + 4, @radius, color: [0, 0, 0, 75])

    # 選択/ホバー時の発光グロー
    if @highlight
      Window.draw_circle(@x, @y, @radius + 5, color: [255, 240, 100, 100])
      Window.draw_circle(@x, @y, @radius + 2, color: [255, 255, 255, 180])
    end

    # ボール本体
    border_col = @is_cue ? [200, 200, 210, 255] : [40, 40, 45, 200]
    Window.draw_circle(@x, @y, @radius, color: @color, border_width: 1.5, border_color: border_col)

    # 9〜15番ボールは中央に白帯 (ストライプ球の表現)
    if @number >= 9
      Window.draw_rect(@x - @radius * 0.9, @y - 6, @radius * 1.8, 12, color: [250, 250, 250, 220])
    end

    # 中央の番号サークル (手球以外)
    unless @is_cue
      num_bg_r = 7.0
      Window.draw_circle(@x, @y, num_bg_r, color: [255, 255, 255, 240])
      num_str = @number.to_s
      num_x = num_str.length > 1 ? @x - 5 : @x - 3
      Window.draw_text(num_x, @y - 6, num_str, size: 10, color: [20, 20, 20, 255])
    end

    # 球体の立体感: 左上のスペキュラ光沢ハイライト
    hl_ox = @x - @radius * 0.35
    hl_oy = @y - @radius * 0.35
    Window.draw_circle(hl_ox, hl_oy, @radius * 0.32, color: [255, 255, 255, 110])
    Window.draw_circle(hl_ox - 1, hl_oy - 1, @radius * 0.16, color: [255, 255, 255, 190])
  end
end

# ------------------------------------------------------------------------------
# 4. ビリヤード・シミュレーター (BilliardsPlayground)
# ------------------------------------------------------------------------------
class BilliardsPlayground
  attr_accessor :balls, :walls, :sparks, :selected_ball, :dragging
  attr_accessor :drag_start_x, :drag_start_y, :current_mouse_x, :current_mouse_y

  SUBSTEPS = 4 # 高速ショットでのめり込み・すり抜けを完全防止するサブステップ数

  def initialize
    @walls = create_walls
    @balls = []
    @sparks = []
    @selected_ball = nil
    @dragging = false
    @drag_start_x = 0.0
    @drag_start_y = 0.0
    @current_mouse_x = 0.0
    @current_mouse_y = 0.0

    # サウンド効果音の生成 (SoundEffect)
    init_sounds

    reset_balls!
  end

  def init_sounds
    @snd_ball_hit = SoundEffect.tone(920, 0.03, type: :triangle, volume: 0.6)
    @snd_wall_hit = SoundEffect.tone(360, 0.05, type: :sine, volume: 0.5)
    @snd_shoot    = SoundEffect.sweep(320, 780, 0.09, type: :sine, volume: 0.7)
  rescue StandardError => e
    puts "Sound init note: #{e.message}"
    @snd_ball_hit = nil
    @snd_wall_hit = nil
    @snd_shoot = nil
  end

  def play_sfx(type, intensity = 1.0)
    case type
    when :ball
      return unless @snd_ball_hit
      @snd_ball_hit.volume = [0.1 + intensity * 0.5, 0.8].min
      @snd_ball_hit.pitch = 0.8 + rand * 0.4
      @snd_ball_hit.play
    when :wall
      return unless @snd_wall_hit
      @snd_wall_hit.volume = [0.1 + intensity * 0.4, 0.7].min
      @snd_wall_hit.pitch = 0.9 + rand * 0.2
      @snd_wall_hit.play
    when :shoot
      return unless @snd_shoot
      @snd_shoot.volume = [0.3 + intensity * 0.5, 0.9].min
      @snd_shoot.play
    end
  rescue StandardError
    # サウンド再生例外を安全に吸収
  end

  # 外周壁と点在する障害物の配置
  def create_walls
    w_list = []

    # 1. 外周のクッション壁 (4辺)
    w_list << Wall.new(640, 20, 1220, 24, radius: 4, color: [48, 28, 16, 255], border_color: [180, 130, 80, 255])   # 上
    w_list << Wall.new(640, 700, 1220, 24, radius: 4, color: [48, 28, 16, 255], border_color: [180, 130, 80, 255])  # 下
    w_list << Wall.new(20, 360, 24, 660, radius: 4, color: [48, 28, 16, 255], border_color: [180, 130, 80, 255])    # 左
    w_list << Wall.new(1260, 360, 24, 660, radius: 4, color: [48, 28, 16, 255], border_color: [180, 130, 80, 255])  # 右

    # 2. 内部に点在する障害物 (角丸矩形・傾いたOBBブロック)
    # 中央の回転プロペラ風バー (OBB)
    w_list << Wall.new(640, 360, 170, 34, angle: 35, radius: 10, color: [25, 45, 55, 255], border_color: [80, 200, 220, 255])

    # 左上の角丸ブロック
    w_list << Wall.new(340, 220, 84, 84, radius: 20, color: [30, 50, 45, 255], border_color: [100, 210, 150, 255])

    # 右下の角丸ブロック
    w_list << Wall.new(940, 500, 84, 84, radius: 20, color: [30, 50, 45, 255], border_color: [100, 210, 150, 255])

    # 左下の傾いた斜めブロック (OBB)
    w_list << Wall.new(340, 500, 42, 130, angle: -28, radius: 10, color: [45, 30, 55, 255], border_color: [200, 110, 220, 255])

    # 右上の傾いた斜めブロック (OBB)
    w_list << Wall.new(940, 220, 42, 130, angle: 28, radius: 10, color: [45, 30, 55, 255], border_color: [200, 110, 220, 255])

    w_list
  end

  # ボールをテーブル全体に散らばった状態で再配置
  def reset_balls!
    @balls.clear
    @sparks.clear
    @selected_ball = nil
    @dragging = false

    # 手球 (Cue Ball: 0番)
    @balls << Ball.new(220, 360, 0)

    # 1〜15番の的球を散らして配置
    spawn_points = [
      [480, 280], [520, 440], [580, 200], [580, 520],
      [700, 200], [700, 520], [760, 280], [800, 440],
      [860, 360], [1060, 260], [1060, 460], [1120, 360],
      [450, 360], [780, 360], [1020, 360]
    ]

    spawn_points.each_with_index do |pos, i|
      # 少しランダムに散らす
      rx = pos[0] + (rand(40) - 20)
      ry = pos[1] + (rand(40) - 20)
      @balls << Ball.new(rx, ry, i + 1)
    end
  end

  # 全ボールにランダムなインパルスを与えて拡散
  def scatter_balls!
    @balls.each do |b|
      ang = rand * Math::PI * 2.0
      pwr = 8.0 + rand * 14.0
      b.vx += Math.cos(ang) * pwr
      b.vy += Math.sin(ang) * pwr
    end
    play_sfx(:shoot, 1.0)
  end

  # 全ボールを即座に停止
  def stop_balls!
    @balls.each do |b|
      b.vx = 0.0
      b.vy = 0.0
    end
  end

  # スパーク発生
  def spawn_sparks(x, y, count = 4, color = [255, 240, 180])
    count.times do
      ang = rand * Math::PI * 2.0
      spd = 1.0 + rand * 4.0
      life = 8 + rand(10)
      @sparks << Spark.new(x, y, Math.cos(ang) * spd, Math.sin(ang) * spd, life, color)
    end
  end

  # マウス下のボールを検出
  def find_ball_under_mouse(mx, my)
    @balls.reverse_each do |b|
      dx = mx - b.x
      dy = my - b.y
      return b if (dx * dx + dy * dy) <= (b.radius + 6.0)**2
    end
    nil
  end

  # 入力とショット更新
  def handle_input(mx, my)
    @current_mouse_x = mx
    @current_mouse_y = my

    # ホバー球の判定
    hovered = find_ball_under_mouse(mx, my)
    @balls.each { |b| b.highlight = false }

    if @dragging && @selected_ball
      @selected_ball.highlight = true
    elsif hovered
      hovered.highlight = true
    end

    # 左クリック押下: ドラッグ開始
    if Input.mouse_push?(:left)
      target = hovered || @balls.find(&:is_cue) || @balls.first
      if target
        @selected_ball = target
        @dragging = true
        @drag_start_x = target.x
        @drag_start_y = target.y
      end
    end

    # 左クリック解放: ショット発射
    if Input.mouse_release?(:left) && @dragging && @selected_ball
      # 引っ張ったベクトル (ボールからマウスへのベクトル)
      dx = @selected_ball.x - mx
      dy = @selected_ball.y - my
      drag_dist = Math.sqrt(dx * dx + dy * dy)

      if drag_dist > 6.0
        # 最大ショット力にクランプ
        max_dist = 220.0
        dist_clamped = [drag_dist, max_dist].min
        power = (dist_clamped / max_dist) * 28.0 # 最大初速 28.0 px/frame

        nx = dx / drag_dist
        ny = dy / drag_dist

        @selected_ball.vx = nx * power
        @selected_ball.vy = ny * power

        spawn_sparks(@selected_ball.x, @selected_ball.y, 8, [255, 255, 200])
        play_sfx(:shoot, power / 28.0)
      end

      @dragging = false
      @selected_ball = nil
    end

    # キーボード操作
    reset_balls! if Input.key_push?(:r)
    scatter_balls! if Input.key_push?(:space)
    stop_balls! if Input.key_push?(:s)
  end

  # 物理更新 (サブステップで実行)
  def update_physics
    dt_factor = 1.0 / SUBSTEPS

    SUBSTEPS.times do
      # 1. 位置更新と摩擦
      @balls.each { |b| b.update(dt_factor) }

      # 2. ボール vs ボール のめり込み解消＆弾性衝突
      len = @balls.length
      i = 0
      while i < len
        b1 = @balls[i]
        j = i + 1
        while j < len
          b2 = @balls[j]

          # 高速ブロードフェーズ (外接円チェック)
          dx = b2.x - b1.x
          dy = b2.y - b1.y
          r_sum = b1.radius + b2.radius
          if dx.abs < r_sum && dy.abs < r_sum
            # ★ Collision.penetration を呼び出し！
            hit = Collision.penetration(b1.shape, b2.shape)
            if hit
              # A. めり込み解消 (各自半分ずつ押し戻す)
              b1.x += hit.push_x * 0.5
              b1.y += hit.push_y * 0.5
              b2.x += hit.push_b_x * 0.5
              b2.y += hit.push_b_y * 0.5
              b1.shape.x = b1.x
              b1.shape.y = b1.y
              b2.shape.x = b2.x
              b2.shape.y = b2.y

              # B. 弾性衝突インパルス (速度交換)
              rel_vx = b1.vx - b2.vx
              rel_vy = b1.vy - b2.vy
              vel_along_norm = rel_vx * hit.normal_x + rel_vy * hit.normal_y

              # 互いに近づいている場合のみ力積を適用
              if vel_along_norm < 0.0
                restitution = 0.94 # 反発係数
                impulse = -(1.0 + restitution) * vel_along_norm * 0.5

                b1.vx += impulse * hit.normal_x
                b1.vy += impulse * hit.normal_y
                b2.vx -= impulse * hit.normal_x
                b2.vy -= impulse * hit.normal_y

                # 衝突スパーク＆効果音 (一定以上の衝撃のみ)
                impact = -vel_along_norm
                if impact > 1.2
                  mid_x = (b1.x + b2.x) * 0.5
                  mid_y = (b1.y + b2.y) * 0.5
                  spawn_sparks(mid_x, mid_y, 3, [255, 240, 160])
                  play_sfx(:ball, impact / 15.0)
                end
              end
            end
          end
          j += 1
        end
        i += 1
      end

      # 3. ボール vs 壁/障害物 のめり込み解消＆反射
      @balls.each do |ball|
        @walls.each do |wall|
          # ★ Collision.penetration を呼び出し！
          hit = Collision.penetration(ball.shape, wall.shape)
          if hit
            # A. めり込み解消 (ボールを壁の外側へ押し戻す)
            ball.x += hit.push_x
            ball.y += hit.push_y
            ball.shape.x = ball.x
            ball.shape.y = ball.y

            # B. 壁への弾性反射
            dot = ball.vx * hit.normal_x + ball.vy * hit.normal_y
            if dot < 0.0
              restitution = 0.86
              ball.vx -= (1.0 + restitution) * dot * hit.normal_x
              ball.vy -= (1.0 + restitution) * dot * hit.normal_y

              impact = -dot
              if impact > 1.2
                spawn_sparks(ball.x, ball.y, 4, [160, 240, 200])
                play_sfx(:wall, impact / 12.0)
              end
            end
          end
        end
      end
    end

    # パーティクル更新
    @sparks.each(&:update)
    @sparks.reject!(&:dead?)
  end

  # エイムガイドライン・パワーインジケータ描画
  def draw_aim_guide
    return unless @dragging && @selected_ball

    bx = @selected_ball.x
    by = @selected_ball.y
    mx = @current_mouse_x
    my = @current_mouse_y

    dx = bx - mx
    dy = by - my
    dist = Math.sqrt(dx * dx + dy * dy)
    return if dist < 3.0

    max_dist = 220.0
    clamped_dist = [dist, max_dist].min
    ratio = clamped_dist / max_dist

    dir_x = dx / dist
    dir_y = dy / dist

    # 1. 引っ張り線 (マウスからボールへ)
    Window.draw_line(bx, by, mx, my, color: [255, 255, 255, 120], width: 1.5)
    Window.draw_circle(mx, my, 4, color: [255, 200, 80, 200])

    # 2. ショット発射予測線 (ボールから前方へ)
    shoot_len = clamped_dist * 1.5
    target_x = bx + dir_x * shoot_len
    target_y = by + dir_y * shoot_len

    # パワーに応じた色 (青 -> 黄 -> 赤)
    guide_color = if ratio < 0.5
                    r_val = (ratio * 2.0 * 255).to_i
                    [r_val, 220, 255, 220]
                  else
                    g_val = ((1.0 - (ratio - 0.5) * 2.0) * 220).to_i
                    [255, g_val, 50, 220]
                  end

    # 矢印ライン
    Window.draw_line(bx, by, target_x, target_y, color: guide_color, width: 3.0)

    # 予測着弾位置のゴーストボール
    Window.draw_circle(target_x, target_y, @selected_ball.radius, color: [guide_color[0], guide_color[1], guide_color[2], 50], border_width: 1.5, border_color: guide_color)

    # パワーパーセント文字
    power_pct = (ratio * 100).to_i
    Window.draw_text(target_x + 18, target_y - 8, "#{power_pct}%", size: 14, color: guide_color)
  end

  # 全体描画
  def draw
    # 1. ビリヤードテーブルのフェルト背景
    Window.clear([16, 48, 34, 255])

    # テーブルの外枠ウッドフレーム
    Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 0], border_width: 12, border_color: [42, 24, 14, 255])

    # 2. 壁と障害物
    @walls.each(&:draw)

    # 3. エイムガイドライン
    draw_aim_guide

    # 4. ボール
    @balls.each(&:draw)

    # 5. スパーク
    @sparks.each(&:draw)

    # 6. UI HUD パネル
    draw_hud
  end

  def draw_hud
    # 左上コントロールパネル (モダンSDFカード)
    Window.draw_rect(28, 28, 380, 105, radius: 10, color: [15, 25, 22, 225], border_width: 1, border_color: [50, 90, 70, 255], shadow_blur: 16)

    Window.draw_text(42, 38, "Zenoo Billiards & MTV Physics", size: 18, color: [100, 255, 180, 255])
    Window.draw_text(42, 64, "Drag Ball: Aim & Shoot    [R]: Reset Table", size: 13, color: [210, 230, 220, 255])
    Window.draw_text(42, 84, "[SPACE]: Scatter Balls    [S]: Stop All", size: 13, color: [210, 230, 220, 255])

    moving_count = @balls.count(&:moving?)
    status_str = moving_count > 0 ? "Moving: #{moving_count} balls" : "Table at rest"
    status_col = moving_count > 0 ? [255, 215, 80, 255] : [140, 180, 160, 255]
    Window.draw_text(42, 104, "FPS: #{Window.fps.round(1)}  |  #{status_str}", size: 13, color: status_col)

    # 右上ミニ情報
    Window.draw_rect(1060, 28, 192, 42, radius: 8, color: [15, 25, 22, 200], border_width: 1, border_color: [50, 90, 70, 255])
    Window.draw_text(1074, 40, "MTV: Penetration 2D", size: 14, color: [80, 220, 240, 255])
  end

  def step_frame
    mx, my = Input.mouse_pos
    mx = 640.0 if mx < 0 || mx > 1280
    my = 360.0 if my < 0 || my > 720

    handle_input(mx, my)
    update_physics
    draw
  end
end

# ------------------------------------------------------------------------------
# メインループ
# ------------------------------------------------------------------------------
playground = BilliardsPlayground.new
test_frames = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_counter = 0

Window.loop(1280, 720, "Zenoo Billiards & MTV Physics Demo") do
  playground.step_frame
  if test_frames > 0
    frame_counter += 1
    if frame_counter >= test_frames
      puts "Billiards demo test completed successfully! (#{frame_counter} frames)"
      exit
    end
  end
end

# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo GJK Collision Demo
# GJK アルゴリズムによる任意凸形状 (円, 回転矩形, カプセル, 凸多角形) のリアルタイム衝突判定
# ==============================================================================

player_type = 0 # 0: 回転矩形, 1: 円, 2: カプセル, 3: 三角形
player_angle = 0.0

# ターゲット形状一覧
class Target
  attr_accessor :name, :shape, :type, :color_idle, :color_hit, :hit

  def initialize(name, shape, type, color_idle = [70, 160, 240, 220])
    @name = name
    @shape = shape
    @type = type
    @color_idle = color_idle
    @color_hit = [240, 70, 90, 240]
    @hit = false
  end

  def current_color
    @hit ? @color_hit : @color_idle
  end
end

targets = [
  # 1. 回転矩形 (OBB)
  Target.new("OBB (Rotated Rect)", Collision.rect(300, 360, 140, 90, angle: 25), :rect),
  # 2. 円
  Target.new("Circle", Collision.circle(580, 200, 60), :circle),
  # 3. 角丸矩形 (Rounded Rect)
  Target.new("Rounded Rect", Collision.rect(580, 420, 150, 95, angle: 15, radius: 24), :rounded_rect),
  # 4. カプセル
  Target.new("Capsule", Collision.capsule(820, 480, 960, 560, 32), :capsule),
  # 5. 凸多角形 (五角形)
  Target.new(
    "Polygon (Pentagon)",
    Collision.polygon([
      [1040.0, 240.0],
      [1120.0, 290.0],
      [1090.0, 380.0],
      [990.0, 380.0],
      [960.0, 290.0]
    ]),
    :polygon
  )
]

Window.loop(1280, 720, "Zenoo GJK Collision System Demo") do
  test_frames = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
  if test_frames > 0
    @test_frame_counter ||= 0
    @test_frame_counter += 1
    break if @test_frame_counter >= test_frames
  end

  t = Window.time
  dt = Window.delta_time

  # 画面クリア
  Window.clear([18, 22, 32, 255])

  # タイトルと操作説明
  Window.draw_text(40, 25, "Zenoo GJK Collision System", size: 26, color: :white)
  Window.draw_text(40, 58, "Pure Ruby GJK Algorithm - Zero Allocations - OBB / Circle / Capsule / Convex Polygon", size: 15, color: [160, 180, 210, 255])
  Window.draw_text(40, 85, "[Space]: プレイヤー形状切替  |  [Q / E]: 回転  |  マウスで移動", size: 14, color: [255, 215, 80, 255])

  # 入力処理
  if Input.key_push?(:space)
    player_type = (player_type + 1) % 4
  end

  if Input.key_pressed?(:q)
    player_angle -= 120.0 * dt
  elsif Input.key_pressed?(:e)
    player_angle += 120.0 * dt
  else
    player_angle += 20.0 * dt # 自動微回転
  end

  mx, my = Input.mouse_pos
  # 画面外なら中央
  mx = 640.0 if mx < 0 || mx > 1280
  my = 360.0 if my < 0 || my > 720

  # ターゲット 1 (矩形) をゆっくり回転
  targets[0].shape.angle = t * 30.0
  targets[0].shape.update_cache

  # プレイヤー形状の構築
  player_shape = case player_type
                 when 0
                   Collision.rect(mx, my, 100, 60, angle: player_angle, pivot: :center)
                 when 1
                   Collision.circle(mx, my, 40)
                 when 2
                   rad = player_angle * (Math::PI / 180.0)
                   dx = Math.cos(rad) * 45.0
                   dy = Math.sin(rad) * 45.0
                   Collision.capsule(mx - dx, my - dy, mx + dx, my + dy, 25)
                 when 3
                   rad = player_angle * (Math::PI / 180.0)
                   cos_a = Math.cos(rad)
                   sin_a = Math.sin(rad)
                   # 正三角形
                   p1 = [mx + (0.0 * cos_a - (-50.0) * sin_a), my + (0.0 * sin_a + (-50.0) * cos_a)]
                   p2 = [mx + (45.0 * cos_a - 35.0 * sin_a),   my + (45.0 * sin_a + 35.0 * cos_a)]
                   p3 = [mx + (-45.0 * cos_a - 35.0 * sin_a),  my + (-45.0 * sin_a + 35.0 * cos_a)]
                   Collision.polygon([p1, p2, p3])
                 end

  # 衝突判定実行
  total_hits = 0
  targets.each do |target|
    target.hit = Collision.check(player_shape, target.shape)
    total_hits += 1 if target.hit
  end

  # ----------------------------------------------------
  # ターゲットの描画
  # ----------------------------------------------------
  targets.each do |target|
    col = target.current_color
    case target.type
    when :rect
      r = target.shape
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.begin_path
        c.rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height)
        c.fill(col)
        c.stroke(:white, 2)
        c.restore
      end
      Window.draw_text(r.center_x - 60, r.center_y + 65, target.name, size: 14, color: [200, 215, 230, 255])

    when :circle
      c = target.shape
      Window.draw_circle(c.x, c.y, c.radius, color: col, border_color: :white, border_width: 2)
      Window.draw_text(c.x - 20, c.y + c.radius + 15, target.name, size: 14, color: [200, 215, 230, 255])

    when :rounded_rect
      r = target.shape
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.begin_path
        c.round_rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height, r.radius)
        c.fill(col)
        c.stroke(:white, 2)
        c.restore
      end
      Window.draw_text(r.center_x - 50, r.center_y + 65, target.name, size: 14, color: [200, 215, 230, 255])

    when :capsule
      cap = target.shape
      Window.draw_path do |c|
        c.save
        c.translate(cap.center_x, cap.center_y)
        c.rotate(cap.angle * Math::PI / 180.0)
        c.begin_path
        c.round_rect(-cap.width * 0.5, -cap.height * 0.5, cap.width, cap.height, cap.radius)
        c.fill(col)
        c.stroke(:white, 2)
        c.restore
      end
      Window.draw_text(cap.center_x - 30, cap.center_y + 55, target.name, size: 14, color: [200, 215, 230, 255])

    when :polygon
      poly = target.shape
      Window.draw_path do |c|
        c.begin_path
        poly.vertices.each_with_index do |v, idx|
          idx == 0 ? c.move_to(v[0], v[1]) : c.line_to(v[0], v[1])
        end
        c.close_path
        c.fill(col)
        c.stroke(:white, 2)
      end
      Window.draw_text(poly.center_x - 65, poly.center_y + 80, target.name, size: 14, color: [200, 215, 230, 255])
    end
  end

  # ----------------------------------------------------
  # プレイヤー形状の描画
  # ----------------------------------------------------
  p_col = (total_hits > 0) ? [255, 100, 100, 230] : [100, 255, 140, 230]
  case player_type
  when 0 # 矩形
    r = player_shape
    Window.draw_path do |c|
      c.save
      c.translate(r.center_x, r.center_y)
      c.rotate(r.angle * Math::PI / 180.0)
      c.begin_path
      c.rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height)
      c.fill(p_col)
      c.stroke(:white, 3)
      c.restore
    end
  when 1 # 円
    c = player_shape
    Window.draw_circle(c.x, c.y, c.radius, color: p_col, border_color: :white, border_width: 3)
  when 2 # カプセル
    cap = player_shape
    Window.draw_path do |c|
      c.save
      c.translate(cap.center_x, cap.center_y)
      c.rotate(cap.angle * Math::PI / 180.0)
      c.begin_path
      c.round_rect(-cap.width * 0.5, -cap.height * 0.5, cap.width, cap.height, cap.radius)
      c.fill(p_col)
      c.stroke(:white, 3)
      c.restore
    end
  when 3 # 三角形
    poly = player_shape
    Window.draw_path do |c|
      c.begin_path
      poly.vertices.each_with_index do |v, idx|
        idx == 0 ? c.move_to(v[0], v[1]) : c.line_to(v[0], v[1])
      end
      c.close_path
      c.fill(p_col)
      c.stroke(:white, 3)
    end
  end

  # 情報 HUD
  Window.draw_rect(30, 640, 360, 55, radius: 8, color: [20, 28, 42, 220], border_width: 1, border_color: [60, 80, 110, 255])
  Window.draw_text(45, 650, "Status: #{total_hits > 0 ? 'COLLISION DETECTED!' : 'No Collision'}", size: 16, color: total_hits > 0 ? [255, 90, 90, 255] : [100, 255, 150, 255])
  Window.draw_text(45, 672, "FPS: #{Window.fps.round(1)}  |  Hits: #{total_hits}", size: 14, color: [180, 200, 220, 255])
end

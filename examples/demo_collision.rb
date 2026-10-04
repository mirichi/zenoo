# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo GJK Collision Demo
# GJK アルゴリズムによる任意凸形状 (円, 回転矩形, 角丸矩形, 回転楕円, 凸多角形) のリアルタイム衝突判定
# すべての形状が【回転 (angle)】および【不等スケーリング (scale_x, scale_y)】に完全対応！
# ==============================================================================

player_type = 0 # 0: 回転矩形, 1: 円, 2: 回転楕円, 3: 不等スケール角丸矩形, 4: 三角形
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
  Target.new("OBB (Rotated Rect)", Collision.rect(260, 360, 140, 90, angle: 25), :rect),
  # 2. 円
  Target.new("Circle", Collision.circle(520, 180, 55), :circle),
  # 3. 楕円状の円 (Rotated Circle: rx != ry)
  Target.new("Circle (Rotated rx != ry)", Collision.circle(800, 180, 75, 35, angle: 30), :ellipse),
  # 4. 不等スケール角丸矩形 (Scaled Rounded Rect)
  Target.new("Scaled Rounded Rect", Collision.rect(520, 420, 120, 80, radius: 20, angle: 15, scale_x: 1.4, scale_y: 0.8), :rounded_rect),
  # 5. カプセル (Capsule)
  Target.new("Capsule", Collision.capsule(780, 440, 920, 520, 30), :capsule),
  # 6. 凸多角形 (五角形)
  Target.new(
    "Polygon (Pentagon)",
    Collision.polygon([
      [1080.0, 220.0],
      [1160.0, 270.0],
      [1130.0, 360.0],
      [1030.0, 360.0],
      [1000.0, 270.0]
    ]),
    :polygon
  )
]

# プレイヤー形状の事前生成 (ループ内アロケーション完全ゼロ化)
player_shapes = [
  Collision.rect(0, 0, 100, 60, pivot: :center),                                          # 0: 回転矩形
  Collision.circle(0, 0, 40),                                                             # 1: 円
  Collision.circle(0, 0, 65, 28, pivot: :center),                                         # 2: 楕円状の円 (rx != ry)
  Collision.rect(0, 0, 90, 50, radius: 15, scale_x: 1.5, scale_y: 0.8, pivot: :center),      # 3: 不等スケール角丸矩形
  Collision.polygon([[0.0, -50.0], [45.0, 35.0], [-45.0, 35.0]])                        # 4: 三角形
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
  Window.draw_text(40, 58, "Pure Ruby GJK - Zero Allocations - Rotated Ellipse, Scaled Rounded Rect & Polygon", size: 15, color: [160, 180, 210, 255])
  Window.draw_text(40, 85, "[Space]: プレイヤー形状切替 (#{player_type}/4)  |  [Q / E]: 回転  |  マウスで移動", size: 14, color: [255, 215, 80, 255])

  # 入力処理
  if Input.key_push?(:space)
    player_type = (player_type + 1) % 5
  end

  if Input.key_pressed?(:q)
    player_angle -= 120.0 * dt
  elsif Input.key_pressed?(:e)
    player_angle += 120.0 * dt
  else
    player_angle += 20.0 * dt # 自動微回転
  end

  mx, my = Input.mouse_pos
  mx = 640.0 if mx < 0 || mx > 1280
  my = 360.0 if my < 0 || my > 720

  # ターゲット 1 (矩形) と ターゲット 3 (楕円状の円) をゆっくり回転
  targets[0].shape.angle = t * 30.0
  targets[2].shape.angle = -t * 25.0

  # プレイヤー形状の更新 (セッター代入のみ。update_cache は Collision.check 時に自動遅延評価)
  player_shape = player_shapes[player_type]
  player_shape.x = mx
  player_shape.y = my
  player_shape.angle = player_angle

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
        c.scale(r.scale_x, r.scale_y)
        c.begin_path
        c.rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height)
        c.fill(col)
        c.stroke(:white, 2)
        c.restore
      end
      Window.draw_text(r.center_x - 60, r.center_y + 65, target.name, size: 14, color: [200, 215, 230, 255])

    when :circle
      c_shape = target.shape
      Window.draw_circle(c_shape.x, c_shape.y, c_shape.bounding_radius, color: col, border_color: :white, border_width: 2)
      Window.draw_text(c_shape.x - 20, c_shape.y + c_shape.bounding_radius + 15, target.name, size: 14, color: [200, 215, 230, 255])

    when :ellipse
      el = target.shape
      Window.draw_path do |c|
        c.begin_path
        c.ellipse(el.center_x, el.center_y, el.radius_x * el.scale_x, el.radius_y * el.scale_y, el.angle * Math::PI / 180.0)
        c.close_path
        c.fill(col)
        c.stroke(:white, 2)
      end
      Window.draw_text(el.center_x - 55, el.center_y + 55, target.name, size: 14, color: [200, 215, 230, 255])

    when :rounded_rect, :capsule
      r = target.shape
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.scale(r.scale_x, r.scale_y)
        c.begin_path
        c.round_rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height, r.radius)
        c.fill(col)
        c.stroke(:white, 2.0 / [r.scale_x, r.scale_y].max)
        c.restore
      end
      Window.draw_text(r.center_x - 50, r.center_y + 55, target.name, size: 14, color: [200, 215, 230, 255])

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
    c_shape = player_shape
    Window.draw_circle(c_shape.x, c_shape.y, c_shape.radius, color: p_col, border_color: :white, border_width: 3)

  when 2 # 楕円
    el = player_shape
    Window.draw_path do |c|
      c.begin_path
      c.ellipse(el.center_x, el.center_y, el.radius_x * el.scale_x, el.radius_y * el.scale_y, el.angle * Math::PI / 180.0)
      c.close_path
      c.fill(p_col)
      c.stroke(:white, 3)
    end

  when 3 # 不等スケール角丸矩形
    r = player_shape
    Window.draw_path do |c|
      c.save
      c.translate(r.center_x, r.center_y)
      c.rotate(r.angle * Math::PI / 180.0)
      c.scale(r.scale_x, r.scale_y)
      c.begin_path
      c.round_rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height, r.radius)
      c.fill(p_col)
      c.stroke(:white, 3.0 / [r.scale_x, r.scale_y].max)
      c.restore
    end

  when 4 # 三角形
    poly = player_shape
    Window.draw_path do |c|
      c.save
      c.translate(poly.center_x, poly.center_y)
      c.rotate(poly.angle * Math::PI / 180.0)
      c.scale(poly.scale_x, poly.scale_y)
      c.begin_path
      poly.local_vertices.each_with_index do |v, idx|
        idx == 0 ? c.move_to(v[0], v[1]) : c.line_to(v[0], v[1])
      end
      c.close_path
      c.fill(p_col)
      c.stroke(:white, 3)
      c.restore
    end
  end

  # 情報 HUD
  Window.draw_rect(30, 640, 380, 55, radius: 8, color: [20, 28, 42, 220], border_width: 1, border_color: [60, 80, 110, 255])
  Window.draw_text(45, 650, "Status: #{total_hits > 0 ? 'COLLISION DETECTED!' : 'No Collision'}", size: 16, color: total_hits > 0 ? [255, 90, 90, 255] : [100, 255, 150, 255])
  Window.draw_text(45, 672, "FPS: #{Window.fps.round(1)}  |  Hits: #{total_hits}", size: 14, color: [180, 200, 220, 255])
end

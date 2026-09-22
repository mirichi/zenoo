# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Vector Graphics (NanoGL / HTML5 Canvas 2D 互換) デモ
# ==============================================================================
Window.loop(1280, 720, "Zenoo - Vector Graphics Demo (HTML5 Canvas Style)") do
  t = Window.time

  # 1. 背景クリア
  Window.clear([20, 24, 34, 255])

  # タイトルと説明
  Window.draw_text(40, 25, "Zenoo Vector Graphics (HTML5 Canvas 2D Compatible API)", size: 26, color: :white)
  Window.draw_text(40, 58, "Shader Gradients (Linear / Radial) & Ear-Clipping Tessellation", size: 15, color: [160, 175, 200, 255])

  # ----------------------------------------------------
  # 2. 星型の線形グラデーション塗りつぶし (LinearGradient + Ear Clipping)
  # ----------------------------------------------------
  Window.draw_path do |c|
    c.save
    c.translate(180, 220)
    c.rotate(t * 0.6)

    # 10角の星型パスを構築
    c.begin_path
    10.times do |i|
      r = i.even? ? 95 : 42
      ang = i * Math::PI / 5.0 - Math::PI / 2.0
      x = Math.cos(ang) * r
      y = Math.sin(ang) * r
      i == 0 ? c.move_to(x, y) : c.line_to(x, y)
    end
    c.close_path

    # 線形グラデーション (ゴールド -> マゼンタ)
    grad = c.create_linear_gradient(-80, -80, 80, 80)
    grad.add_color_stop(0.0, [1.0, 0.85, 0.2, 0.95])
    grad.add_color_stop(1.0, [1.0, 0.2, 0.5, 0.95])
    c.fill(grad)
    c.stroke([1.0, 1.0, 1.0, 0.9], 4)
    c.restore
  end
  Window.draw_text(110, 340, "Linear Gradient Star", size: 15, color: :white)

  # ----------------------------------------------------
  # 3. 3次ベジエ曲線 & 2次ベジエ曲線 (Bézier Curves)
  # ----------------------------------------------------
  Window.draw_path do |c|
    c.begin_path
    start_x, start_y = 350, 220
    c.move_to(start_x, start_y)

    cp1x = start_x + 70
    cp1y = start_y - 100 + Math.sin(t * 3) * 40
    cp2x = start_x + 140
    cp2y = start_y + 100 + Math.cos(t * 3) * 40
    end_x = start_x + 210
    end_y = start_y

    c.bezier_curve_to(cp1x, cp1y, cp2x, cp2y, end_x, end_y, 32)
    c.stroke([0.2, 0.8, 1.0, 1.0], 7)

    # 制御点
    c.fill_circle(start_x, start_y, 5, :white)
    c.fill_circle(cp1x, cp1y, 4, [1.0, 0.3, 0.3, 1.0])
    c.fill_circle(cp2x, cp2y, 4, [1.0, 0.3, 0.3, 1.0])
    c.fill_circle(end_x, end_y, 5, :white)

    # 制御線
    c.begin_path
    c.move_to(start_x, start_y)
    c.line_to(cp1x, cp1y)
    c.move_to(end_x, end_y)
    c.line_to(cp2x, cp2y)
    c.stroke([1.0, 1.0, 1.0, 0.25], 1.5)
  end
  Window.draw_text(390, 340, "Cubic Bézier Curve", size: 15, color: :white)

  # ----------------------------------------------------
  # 4. 放射グラデーション (RadialGradient: 光るオーブ & 球体)
  # ----------------------------------------------------
  Window.draw_path do |c|
    orb_cx, orb_cy = 690, 220
    orb_r = 75

    # 球体ハイライト風の放射グラデーション (中心を少し左上にシフト)
    light_x = orb_cx - 25 + Math.cos(t * 1.5) * 15
    light_y = orb_cy - 25 + Math.sin(t * 1.5) * 15
    rad_sphere = c.create_radial_gradient(light_x, light_y, 5, orb_cx, orb_cy, orb_r)
    rad_sphere.add_color_stop(0.0, [1.0, 1.0, 1.0, 1.0])      # ハイライト白
    rad_sphere.add_color_stop(1.0, [0.05, 0.2, 0.75, 0.95])   # ディープブルー

    c.begin_path
    c.circle(orb_cx, orb_cy, orb_r)
    c.fill(rad_sphere)
    c.stroke([0.3, 0.7, 1.0, 0.8], 3)

    # 外側のパルス発光グロー (外径アニメーション)
    glow_r = orb_r + 20 + Math.sin(t * 4) * 8
    rad_glow = c.create_radial_gradient(orb_cx, orb_cy, orb_r * 0.8, orb_cx, orb_cy, glow_r)
    rad_glow.add_color_stop(0.0, [0.2, 0.8, 1.0, 0.4])
    rad_glow.add_color_stop(1.0, [0.0, 0.5, 1.0, 0.0])
    c.begin_path
    c.circle(orb_cx, orb_cy, glow_r)
    c.fill(rad_glow)
  end
  Window.draw_text(630, 340, "Radial Gradient Orb", size: 15, color: :white)

  # ----------------------------------------------------
  # 5. 角丸矩形 (Round Rect) とグラデーションカード
  # ----------------------------------------------------
  Window.draw_path do |c|
    c.save
    c.translate(920, 140)

    # 角丸矩形カード（垂直線形グラデーション）
    card_grad = c.create_linear_gradient(0, 0, 0, 160)
    card_grad.add_color_stop(0.0, [0.25, 0.35, 0.55, 0.95])
    card_grad.add_color_stop(1.0, [0.10, 0.15, 0.30, 0.95])

    c.begin_path
    c.round_rect(0, 0, 240, 160, 20)
    c.fill(card_grad)
    c.stroke([0.4, 0.6, 0.9, 0.8], 2.5)

    # カード内部のミニ図形
    c.fill_rect(20, 20, 70, 50, [1.0, 0.6, 0.2, 0.9])
    c.stroke_rect(20, 20, 70, 50, :white, 2)
    c.stroke_circle(160, 45, 22, [0.3, 1.0, 0.7, 1.0], 3)
    c.restore
  end
  Window.draw_text(960, 340, "Round Rect & Card", size: 15, color: :white)

  # ----------------------------------------------------
  # 6. アフィン変形・幾何学模様 (Flower / Mandala)
  # ----------------------------------------------------
  Window.draw_path do |c|
    c.save
    c.translate(220, 520)
    c.scale(0.8, 0.8)

    num_petals = 12
    num_petals.times do |i|
      c.save
      c.rotate(i * (Math::PI * 2 / num_petals) + t * 0.5)

      c.begin_path
      c.move_to(0, 0)
      c.quadratic_curve_to(35, -28, 80, 0)
      c.quadratic_curve_to(35, 28, 0, 0)
      c.close_path

      alpha = 0.5 + 0.3 * Math.sin(t * 2 + i)
      c.fill([0.4 + 0.5 * (i.to_f / num_petals), 0.3, 0.8 - 0.4 * (i.to_f / num_petals), alpha])
      c.stroke([1.0, 1.0, 1.0, 0.8], 2)
      c.restore
    end

    c.fill_circle(0, 0, 12, [1.0, 0.9, 0.3, 1.0])
    c.restore
  end
  Window.draw_text(130, 640, "Mandala (Transforms)", size: 15, color: :white)

  # ----------------------------------------------------
  # 7. 円弧 (arc) と扇形 (Pies & Arcs)
  # ----------------------------------------------------
  Window.draw_path do |c|
    cx, cy = 520, 520
    r = 75

    # 扇形 1
    c.begin_path
    c.move_to(cx, cy)
    c.arc(cx, cy, r, 0, Math::PI * 0.7)
    c.close_path
    c.fill([0.3, 0.9, 0.5, 0.85])
    c.stroke([0.1, 0.4, 0.2, 1.0], 3)

    # 扇形 2 (アニメーション)
    anim_end = Math::PI * 0.8 + (Math.sin(t * 2) + 1.0) * 0.5 * Math::PI * 0.8
    c.begin_path
    c.move_to(cx, cy)
    c.arc(cx, cy, r + 4, Math::PI * 0.8, anim_end)
    c.close_path
    c.fill([0.9, 0.3, 0.6, 0.85])
    c.stroke([0.5, 0.1, 0.3, 1.0], 3)

    # 外枠円弧ストローク
    c.begin_path
    c.arc(cx, cy, r + 16, 0, Math::PI * 2)
    c.stroke([1.0, 1.0, 1.0, 0.3], 2)
  end
  Window.draw_text(460, 640, "Arcs & Pie Slices", size: 15, color: :white)

  # ----------------------------------------------------
  # 8. マウス追従インタラクティブパス
  # ----------------------------------------------------
  mx, my = Input.mouse_x, Input.mouse_y
  Window.draw_path do |c|
    c.line_join = :round
    c.line_cap = :round
    c.begin_path
    c.move_to(800, 520)
    c.bezier_curve_to(900, 440, mx - 40, my - 40, mx, my)
    c.stroke([1.0, 0.85, 0.2, 0.9], 5)

    c.fill_circle(mx, my, 7, [1.0, 0.2, 0.2, 1.0])
    c.stroke_circle(mx, my, 12, :white, 2)
  end
  Window.draw_text(800, 640, "Interactive Ribbon (Mouse: #{mx.to_i}, #{my.to_i})", size: 15, color: :white)

  # 終了案内
  exit if Input.key_push?(:escape)
end

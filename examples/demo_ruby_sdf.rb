$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../ext/zenoo", __dir__)

require 'zenoo'

puts "Starting Zenoo Pure Ruby SDF Demo..."

ball_x = 100.0
ball_dir = 1.0

frame = 0
Window.loop(1280, 720, "Zenoo on Ruby - Pure Ruby SDF Engine") do
  # ESCキーまたは60フレームで終了
  frame += 1
  break if Input.key_push?(:escape) || frame >= 60

  # 1. 往復アニメーション
  dt = Window.delta_time
  ball_x += ball_dir * 500.0 * dt
  if ball_x > Window.width - 240
    ball_x = Window.width - 240
    ball_dir = -1.0
  elsif ball_x < 40
    ball_x = 40
    ball_dir = 1.0
  end

  # 2. 背景グリッド装飾
  Window.draw_card(40, 20, Window.width - 80, 60,
    radius: 12,
    color: [24, 28, 42],
    border_width: 1, border_color: [60, 70, 100],
    shadow_blur: 10, shadow_color: [0, 0, 0, 150]
  )

  # 3. マウス追従カード
  mx, my = Input.mouse_pos
  Window.draw_card(mx - 80, my - 50, 160, 100,
    radius: 20,
    color: [35, 45, 75, 200],
    border_width: 2, border_color: :cyan,
    shadow_blur: 18, shadow_color: [0, 200, 255, 120]
  )

  # 4. 往復するネオンカード
  card_color = Input.mouse_pressed?(:left) ? :magenta : :yellow
  Window.draw_card(ball_x, 140, 200, 120,
    radius: 16,
    color: [30, 32, 45],
    border_width: 3, border_color: card_color,
    shadow_blur: 24, shadow_color: [255, 215, 0, 160]
  )

  # 5. ガラスモーフィズム風カード (半透明 + 影)
  Window.draw_card(40, 320, 380, 340,
    radius: 24,
    color: [25, 30, 48, 220],
    border_width: 1.5, border_color: [255, 255, 255, 80],
    shadow_blur: 20, shadow_color: [0, 0, 0, 180]
  )

  # 6. 右側カード
  Window.draw_card(460, 320, Window.width - 500, 340,
    radius: 16,
    color: [20, 24, 36],
    border_width: 1, border_color: [50, 60, 85],
    shadow_blur: 12, shadow_color: [0, 0, 0, 140]
  )
end

puts "Demo finished successfully."

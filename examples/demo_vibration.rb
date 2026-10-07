# frozen_string_literal: true

require_relative '../lib/zenoo'

status = "Press Gamepad buttons (A/B/X) or Keys (Z/X/C/V) to Vibrate"

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(960, 540, "Zenoo Vibration Demo") do
  frame_count += 1
  break if test_max > 0 && frame_count >= test_max

  Window.draw_rect(0, 0, 960, 540, color: Color.new(24, 28, 36))

  # ゲームパッド接続確認
  connected = Input.gamepad_connected?(0)

  if connected
    Window.draw_text(40, 40, "Gamepad 0: Connected", size: 28, color: Color.new(80, 220, 120))
  else
    Window.draw_text(40, 40, "Gamepad 0: Not Connected (Using Keyboard/Mouse)", size: 28, color: Color.new(220, 100, 100))
  end

  # 入力と振動トリガー
  if Input.gamepad_button_push?(:a, 0) || Input.key_push?(:z)
    Input.vibrate_gamepad(0, 0.0, 1.0, 0.2) # 弱モーター (高周波)
    status = "Weak Vibration (High-freq motor) triggered!"
  elsif Input.gamepad_button_push?(:b, 0) || Input.key_push?(:x)
    Input.vibrate_gamepad(0, 1.0, 0.0, 0.2) # 強モーター (低周波)
    status = "Strong Vibration (Low-freq motor) triggered!"
  elsif Input.gamepad_button_push?(:x, 0) || Input.key_push?(:c)
    Input.vibrate_gamepad(0, 0.8, 0.8, 0.5) # 両方
    status = "Dual Rumble (Both motors 0.8 for 0.5s) triggered!"
  elsif Input.gamepad_button_push?(:y, 0) || Input.key_push?(:v) || Input.mouse_push?(:left)
    Input.vibrate(0.2) # スマホ端末本体用 (Web/Android等)
    status = "Device Vibration (navigator.vibrate) triggered!"
  end

  # 説明テキスト
  Window.draw_text(40, 120, "Controls:", size: 24, color: Color.new(200, 200, 200))
  Window.draw_text(60, 160, "[A] or [Z] : Weak motor (0.2s)", size: 20, color: Color.new(180, 180, 180))
  Window.draw_text(60, 200, "[B] or [X] : Strong motor (0.2s)", size: 20, color: Color.new(180, 180, 180))
  Window.draw_text(60, 240, "[X] or [C] : Both motors (0.5s)", size: 20, color: Color.new(180, 180, 180))
  Window.draw_text(60, 280, "[Y] or [V] or Click : Device vibrate (Web/Mobile)", size: 20, color: Color.new(180, 180, 180))

  Window.draw_text(40, 360, "Status: #{status}", size: 22, color: Color.new(240, 220, 100))
end

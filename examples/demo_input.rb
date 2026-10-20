# frozen_string_literal: true

require_relative '../lib/zenoo'

include Zenoo

# アクションマッピングの登録テスト
Input.define_action(:jump, keys: [:space, :w, :up], gamepad: :a)
Input.define_action(:attack, keys: [:z, :j], mouse: :left, gamepad: :x)

# テスト用変数
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

# 入力履歴・状態保持用
text_input_log = ""
wheel_acc_x = 0.0
wheel_acc_y = 0.0
preview_radius = 24.0

# プレイヤー（操作テスト用オブジェクト）
player_x = 840.0
player_y = 440.0
player_speed = 3.0

Window.loop(960, 540, "Zenoo - Input Module All-in-One Showcase") do
  frame_count += 1
  break if test_max > 0 && frame_count >= test_max

  # 背景描画
  Window.draw_rect(0, 0, 960, 540, color: Color.new(20, 24, 32))

  # ----------------------------------------------------
  # 1. マウス & ホイール入力 (Mouse & Wheel)
  # ----------------------------------------------------
  mx, my = Input.mouse_pos
  wx = Input.mouse_wheel_x
  wy = Input.mouse_wheel_y
  wheel_acc_x += wx
  wheel_acc_y += wy

  # ホイールによる半径変更
  preview_radius = (preview_radius + wy * 3.0).clamp(10.0, 60.0)

  # マウスエリアカード
  Window.draw_rect(20, 20, 450, 150, color: Color.new(30, 36, 48), radius: 8.0)
  Window.draw_text(35, 30, "■ Mouse & Wheel", size: 18, color: Color.new(100, 200, 255))
  Window.draw_text(35, 55, "Pos: (#{mx.round(1)}, #{my.round(1)})", size: 15, color: Color.new(200, 210, 220))
  Window.draw_text(35, 75, "Wheel Delta: X=#{wx.round(2)}, Y=#{wy.round(2)} (acc: #{wheel_acc_y.round(1)})", size: 15, color: Color.new(200, 210, 220))

  # マウスボタン状態表示 (左・中・右)
  [:left, :middle, :right].each_with_index do |btn, idx|
    bx = 35 + idx * 75
    by = 100
    is_down = Input.mouse_pressed?(btn)
    is_push = Input.mouse_push?(btn)
    btn_color = is_push ? Color.new(255, 120, 120) : (is_down ? Color.new(100, 220, 120) : Color.new(50, 60, 80))
    Window.draw_rect(bx, by, 65, 30, color: btn_color, radius: 4.0)
    Window.draw_text(bx + 8, by + 7, btn.to_s.capitalize, size: 14, color: Color.new(255, 255, 255))
  end

  # ホイール感度テスト円
  Window.draw_circle(410, 95, preview_radius, color: Color.new(80, 160, 240, 160), border_color: Color.new(140, 200, 255), border_width: 2.0)
  Window.draw_text(380, 135, "Wheel Zoom", size: 11, color: Color.new(160, 170, 180))

  # ----------------------------------------------------
  # 2. キーボード & 文字入力 (Keyboard & Text Input)
  # ----------------------------------------------------
  Window.draw_rect(490, 20, 450, 150, color: Color.new(30, 36, 48), radius: 8.0)
  Window.draw_text(505, 30, "■ Keyboard & Input Chars", size: 18, color: Color.new(120, 230, 150))

  # 代表キーの可視化
  keys = [
    [:w, 560, 55], [:a, 520, 85], [:s, 560, 85], [:d, 600, 85],
    [:space, 650, 85, 80], [:enter, 740, 85, 60], [:escape, 810, 85, 65]
  ]
  keys.each do |k, kx, ky, kw|
    kw ||= 32
    pressed = Input.key_pressed?(k)
    k_color = pressed ? Color.new(255, 200, 80) : Color.new(50, 60, 80)
    Window.draw_rect(kx, ky, kw, 26, color: k_color, radius: 4.0)
    Window.draw_text(kx + 6, ky + 5, k.to_s.upcase, size: 12, color: Color.new(255, 255, 255))
  end

  # テキスト入力バッファ (Input.input_chars)
  new_chars = Input.input_chars
  new_chars.each { |ch| text_input_log += ch }
  text_input_log = text_input_log[-24..] if text_input_log.length > 24
  Window.draw_text(505, 122, "Typed Chars: [ #{text_input_log} ]", size: 14, color: Color.new(240, 240, 200))

  # ----------------------------------------------------
  # 3. ゲームパッド (Gamepad & Sticks & Rumble)
  # ----------------------------------------------------
  Window.draw_rect(20, 190, 450, 210, color: Color.new(30, 36, 48), radius: 8.0)
  pad_connected = Input.gamepad_connected?(0)
  pad_title_color = pad_connected ? Color.new(100, 230, 120) : Color.new(220, 100, 100)
  Window.draw_text(35, 200, "■ Gamepad 0 : #{pad_connected ? 'Connected' : 'Disconnected'}", size: 18, color: pad_title_color)

  # スティック表示 (左・右)
  lx, ly = Input.left_stick(0)
  rx, ry = Input.right_stick(0)

  # 左スティックゲージ
  Window.draw_circle(90, 275, 35, color: Color.new(45, 55, 75))
  Window.draw_circle(90 + lx * 25, 275 + ly * 25, 10, color: Color.new(100, 200, 255))
  Window.draw_text(65, 318, "L Stick", size: 12, color: Color.new(180, 190, 200))

  # 右スティックゲージ
  Window.draw_circle(190, 275, 35, color: Color.new(45, 55, 75))
  Window.draw_circle(190 + rx * 25, 275 + ry * 25, 10, color: Color.new(255, 150, 100))
  Window.draw_text(165, 318, "R Stick", size: 12, color: Color.new(180, 190, 200))

  # トリガー (LT / RT)
  lt = (Input.gamepad_axis(:lt, 0) + 1.0) * 0.5 # 0.0..1.0
  rt = (Input.gamepad_axis(:rt, 0) + 1.0) * 0.5
  Window.draw_rect(250, 245, 80, 14, color: Color.new(50, 60, 80), radius: 3.0)
  Window.draw_rect(250, 245, 80 * lt, 14, color: Color.new(120, 200, 255), radius: 3.0)
  Window.draw_text(250, 227, "LT: #{(lt * 100).to_i}%", size: 12, color: Color.new(180, 190, 200))

  Window.draw_rect(250, 285, 80, 14, color: Color.new(50, 60, 80), radius: 3.0)
  Window.draw_rect(250, 285, 80 * rt, 14, color: Color.new(255, 150, 100), radius: 3.0)
  Window.draw_text(250, 267, "RT: #{(rt * 100).to_i}%", size: 12, color: Color.new(180, 190, 200))

  # 主要ボタン (A/B/X/Y)
  pad_btns = [[:y, 385, 235], [:x, 355, 260], [:b, 415, 260], [:a, 385, 285]]
  pad_btns.each do |btn, bx, by|
    b_down = Input.gamepad_button_pressed?(btn, 0)
    Window.draw_circle(bx, by, 12, color: b_down ? Color.new(255, 220, 80) : Color.new(50, 60, 80))
    Window.draw_text(bx - 4, by - 6, btn.to_s.upcase, size: 12, color: Color.new(255, 255, 255))
  end

  # 振動テスト操作
  if Input.key_push?(:v) || Input.gamepad_button_push?(:a, 0)
    Input.vibrate_gamepad(0, 0.7, 0.7, 0.2)
    Input.vibrate(0.2)
  end
  Window.draw_text(35, 370, "Press [V] key or Pad [A] to trigger Rumble", size: 13, color: Color.new(255, 220, 140))

  # ----------------------------------------------------
  # 4. 高レベル入力 & アクションマッピング (High-level Direction & Action)
  # ----------------------------------------------------
  Window.draw_rect(490, 190, 450, 210, color: Color.new(30, 36, 48), radius: 8.0)
  Window.draw_text(505, 200, "■ High-Level Direction & Action Map", size: 18, color: Color.new(255, 180, 100))

  # Input.x / Input.y (DXRuby互換の合成方向)
  dx = Input.x
  dy = Input.y
  Window.draw_text(505, 235, "Input.x: #{dx.round(2)}, Input.y: #{dy.round(2)}", size: 15, color: Color.new(220, 220, 220))

  # プレイヤーの移動
  player_x = (player_x + dx * player_speed).clamp(520.0, 910.0)
  player_y = (player_y + dy * player_speed).clamp(280.0, 370.0)

  # アクション状態
  jump_strength = Input.action_strength(:jump)
  atk_down = Input.action_pressed?(:attack)

  Window.draw_text(505, 260, "Action :jump   (Space/W/Up/Pad A) : #{(jump_strength * 100).to_i}%", size: 13, color: Color.new(180, 240, 180))
  Window.draw_text(505, 280, "Action :attack (Z/J/Mouse L/Pad X): #{atk_down ? 'ACTIVE' : 'OFF'}", size: 13, color: Color.new(255, 180, 180))

  # 操作可能なプレイヤースクエア
  p_color = atk_down ? Color.new(255, 80, 80) : Color.new(100, 200, 255)
  Window.draw_rect(player_x - 15, player_y - 15, 30, 30, color: p_color, radius: 4.0)
  Window.draw_text(505, 370, "Use Arrow keys / WASD / Stick to move square", size: 13, color: Color.new(160, 170, 180))

  # ----------------------------------------------------
  # 5. マウスカーソル追従フィードバック
  # ----------------------------------------------------
  Window.draw_circle(mx, my, 6, color: Color.new(255, 255, 255, 180))
end

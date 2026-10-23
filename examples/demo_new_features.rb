# frozen_string_literal: true

require_relative '../lib/zenoo'

include Zenoo

# テスト用画像（グラデーション円スプライト）
img = Image.new(96, 96)
Image.render_to(img) do
  Window.clear([0, 0, 0, 0])
  # 綺麗な発色の円を描画
  Window.draw_circle(48, 48, 44, color: Color.new(255, 100, 150))
  Window.draw_circle(48, 48, 30, color: Color.new(255, 220, 100))
  Window.draw_circle(48, 48, 15, color: :white)
end

# スプライト用カスタムシェーダー (時間連動ホログラム色相シフト)
HOLO_FRAG = <<~'GLSL'
#version 330 core
in vec4 v_color;
in vec2 v_uv;
uniform sampler2D u_texture;
uniform float u_time;
out vec4 fragColor;

void main() {
    vec4 tex = texture(u_texture, v_uv);
    if (tex.a < 0.01) discard;

    // 時間変化によるレインボー色相シフト
    vec3 rainbow = 0.5 + 0.5 * cos(u_time * 3.5 + v_uv.xyx * 6.28318 + vec3(0.0, 2.0, 4.0));
    vec4 tinted = vec4(mix(tex.rgb, rainbow, 0.7), tex.a) * v_color;
    fragColor = tinted;
}
GLSL

custom_shader = Shader.new(HOLO_FRAG)

# 1. Sprite の描画パラメータ対称性テスト用スプライト (blend, shader, uniforms)
sprite_alpha  = Sprite.new(105, 560, img, anchor: :center, pivot: :center, blend: :alpha)
sprite_add    = Sprite.new(215, 560, img, anchor: :center, pivot: :center, blend: :add)
sprite_mul    = Sprite.new(325, 560, img, anchor: :center, pivot: :center, blend: :multiply)
sprite_shader = Sprite.new(435, 560, img, anchor: :center, pivot: :center, blend: :alpha, shader: custom_shader)

# テキスト計測用サンプルテキスト配列
sample_texts = [
  "Single line text",
  "Zenoo 2D Game Engine\nMulti-line text measurement test!",
  "Line 1: High-precision SDF Font\nLine 2: Automatic line height\nLine 3: Window.text_size bounding box!",
  "日本語テキスト\n2行目の日本語\n3行目：高精度な枠線フィッティング"
]
text_idx = 1

# タイトル変更用プリセット
title_presets = [
  "Zenoo - New Features Interactive Showcase",
  "★ Dynamic Title Changed! ★",
  "FPS: %0.1f | Window: [%d, %d]",
  "Ready for Game Production!"
]
title_idx = 0

# テスト実行制御
test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1200, 700, title_presets[0]) do
  frame_count += 1
  break if test_max > 0 && frame_count >= test_max

  t = Window.time
  dt = Window.delta_time

  # 背景描画
  Window.draw_rect(0, 0, 1200, 700, color: Color.new(18, 22, 30))

  # ヘッダー
  Window.draw_text(30, 20, "Zenoo New Features Showcase", size: 28, color: :white)
  Window.draw_text(30, 55, "Demonstrating Window control, Input modifiers, Sprite properties & Text measurement", size: 14, color: Color.new(150, 160, 180))

  # ====================================================================
  # パネル 1: Window System & States (タイトル・位置・状態検知)
  # ====================================================================
  Window.draw_rect(30, 90, 540, 270, color: Color.new(28, 34, 46), radius: 8.0)
  Window.draw_text(45, 105, "■ 1. Window Control & States", size: 18, color: Color.new(100, 200, 255))

  # タイトル動的変更
  cur_title = Window.title
  Window.draw_text(45, 135, "Title: #{cur_title[0..36]}#{cur_title.length > 36 ? '...' : ''}", size: 15, color: :white)
  
  # タイトル切り替えボタン
  btn_hover1 = (Input.mouse_x.between?(45, 230) && Input.mouse_y.between?(160, 190))
  Window.draw_rect(45, 160, 185, 30, color: btn_hover1 ? Color.new(70, 130, 200) : Color.new(50, 80, 130), radius: 4.0)
  Window.draw_text(55, 167, "Change Title (Click)", size: 14, color: :white)
  if btn_hover1 && Input.mouse_push?(:left)
    title_idx = (title_idx + 1) % title_presets.length
    if title_idx == 2
      Window.title = "FPS: #{Window.fps.round(1)} | Pos: [#{Window.window_position[0]}, #{Window.window_position[1]}]"
    else
      Window.title = title_presets[title_idx]
    end
  end

  # ウィンドウ位置 (Window Position)
  pos = Window.window_position
  Window.draw_text(45, 205, "Window Position: [X: #{pos[0]}, Y: #{pos[1]}]", size: 15, color: :white)

  # 位置微調整ボタン (矢印キーまたはボタン)
  Window.draw_text(45, 230, "Move Window with keys: [I/J/K/L] or click buttons:", size: 13, color: Color.new(180, 190, 205))
  move_dx, move_dy = 0, 0
  move_dx -= 10 if Input.key_push?(:j)
  move_dx += 10 if Input.key_push?(:l)
  move_dy -= 10 if Input.key_push?(:i)
  move_dy += 10 if Input.key_push?(:k)

  # 画面上ボタン
  [
    ["Left",  45,  255, -15,   0],
    ["Right", 115, 255,  15,   0],
    ["Up",    185, 255,   0, -15],
    ["Down",  255, 255,   0,  15]
  ].each do |label, bx, by, dx, dy|
    btn_h = (Input.mouse_x.between?(bx, bx + 60) && Input.mouse_y.between?(by, by + 26))
    Window.draw_rect(bx, by, 60, 26, color: btn_h ? Color.new(80, 100, 130) : Color.new(45, 55, 75), radius: 3.0)
    Window.draw_text(bx + 12, by + 5, label, size: 13, color: :white)
    if btn_h && Input.mouse_push?(:left)
      move_dx += dx
      move_dy += dy
    end
  end

  if move_dx != 0 || move_dy != 0
    Window.window_position = [pos[0] + move_dx, pos[1] + move_dy]
  end

  # 状態検知インジケーター (focused?, minimized?, maximized?, hovered?)
  states = [
    ["Focused",   Window.focused?],
    ["Minimized", Window.minimized?],
    ["Maximized", Window.maximized?],
    ["Hovered",   Window.hovered?]
  ]
  states.each_with_index do |(st_name, st_val), idx|
    sx = 330 + (idx % 2) * 95
    sy = 145 + (idx / 2) * 45
    led_color = st_val ? Color.new(50, 220, 120) : Color.new(80, 40, 50)
    text_color = st_val ? :white : Color.new(140, 150, 160)
    Window.draw_circle(sx + 10, sy + 10, 7, color: led_color)
    Window.draw_text(sx + 24, sy + 2, st_name, size: 14, color: text_color)
    Window.draw_text(sx + 24, sy + 18, st_val ? "TRUE" : "FALSE", size: 11, color: led_color)
  end

  # ====================================================================
  # パネル 2: Input: Modifiers & Special Keys (修飾キー・特殊キー)
  # ====================================================================
  Window.draw_rect(600, 90, 570, 270, color: Color.new(28, 34, 46), radius: 8.0)
  Window.draw_text(615, 105, "■ 2. Modifiers & Special Keys Detection", size: 18, color: Color.new(100, 200, 255))
  Window.draw_text(615, 130, "Press Shift, Ctrl, Alt, CapsLock, Numpad, Symbols on your keyboard:", size: 13, color: Color.new(180, 190, 205))

  # 主要修飾キーのリアルタイム表示
  modifiers = [
    ["Shift (Any)",  :shift],
    ["L-Shift",      :left_shift],
    ["R-Shift",      :right_shift],
    ["Ctrl (Any)",   :ctrl],
    ["L-Ctrl",       :left_control],
    ["R-Ctrl",       :right_control],
    ["Alt (Any)",    :alt],
    ["L-Alt",        :left_alt],
    ["R-Alt",        :right_alt],
    ["Super/Win",    :super],
    ["Caps Lock",    :caps_lock],
    ["Space",        :space]
  ]

  modifiers.each_with_index do |(m_name, m_key), idx|
    col = idx % 3
    row = idx / 3
    kx = 615 + col * 180
    ky = 155 + row * 26
    is_down = Input.key_pressed?(m_key)
    bg_col = is_down ? Color.new(40, 180, 100) : Color.new(40, 48, 64)
    txt_col = is_down ? :white : Color.new(160, 170, 190)
    Window.draw_rect(kx, ky, 170, 22, color: bg_col, radius: 3.0)
    Window.draw_text(kx + 8, ky + 3, "#{m_name}: #{is_down ? 'DOWN' : 'UP'}", size: 12, color: txt_col)
  end

  # テンキー & 記号キーのリアルタイム検知
  extra_keys = [
    [:kp_0, "KP 0"], [:kp_enter, "KP Enter"], [:kp_add, "KP +"],
    [:comma, ","], [:period, "."], [:slash, "/"], [:semicolon, ";"]
  ]
  active_extras = extra_keys.select { |k, _| Input.key_pressed?(k) }.map(&:last)
  active_str = active_extras.empty? ? "None" : active_extras.join(", ")
  Window.draw_text(615, 270, "Other active special keys: #{active_str}", size: 13, color: Color.new(220, 230, 245))

  # ====================================================================
  # パネル 3: Sprite Render Attributes (Spriteのblend/shader)
  # ====================================================================
  Window.draw_rect(30, 380, 540, 290, color: Color.new(28, 34, 46), radius: 8.0)
  Window.draw_text(45, 395, "■ 3. Sprite Render Properties (Blend Modes)", size: 18, color: Color.new(100, 200, 255))
  Window.draw_text(45, 420, "Each sprite independently retains its .blend property (:alpha, :add, :multiply)", size: 13, color: Color.new(180, 190, 205))

  # 背景にグラデーション矩形を敷いてブレンド効果を分かりやすくする
  Window.draw_rect(70, 455, 450, 120, color: Color.new(60, 70, 90), radius: 6.0)
  Window.draw_rect(100, 470, 390, 90, color: Color.new(30, 90, 160), radius: 4.0)

  # スプライトのアニメーション回転と拡縮
  sprite_alpha.angle  = (t * 60.0) % 360.0
  sprite_add.angle    = (t * 60.0) % 360.0
  sprite_mul.angle    = (t * 60.0) % 360.0
  sprite_shader.angle = (t * 60.0) % 360.0

  scale_pulse = 1.0 + Math.sin(t * 3.0) * 0.15
  sprite_alpha.scale  = scale_pulse
  sprite_add.scale    = scale_pulse
  sprite_mul.scale    = scale_pulse
  sprite_shader.scale = scale_pulse

  # シェーダーへの Uniform リアルタイム転送
  sprite_shader.uniforms = { u_time: t.to_f }

  # Window.draw_sprite による一括描画 (内部で blend / shader / uniforms が忠実に反映される)
  Sprite.draw([sprite_alpha, sprite_add, sprite_mul, sprite_shader])

  Window.draw_text(80,  590, ":alpha", size: 13, color: :white)
  Window.draw_text(180, 590, ":add", size: 13, color: Color.new(255, 230, 150))
  Window.draw_text(290, 590, ":multiply", size: 13, color: Color.new(150, 200, 255))
  Window.draw_text(395, 590, ":shader (Holo)", size: 13, color: Color.new(255, 170, 220))

  # ====================================================================
  # パネル 4: Window.text_size / text_height (バウンディングボックス検証)
  # ====================================================================
  Window.draw_rect(600, 380, 570, 290, color: Color.new(28, 34, 46), radius: 8.0)
  Window.draw_text(615, 395, "■ 4. Window.text_size & Bounding Box", size: 18, color: Color.new(100, 200, 255))
  Window.draw_text(615, 420, "Measures multi-line text dimensions. Box fits text precisely:", size: 13, color: Color.new(180, 190, 205))

  # テキスト切り替えボタン
  btn_hover_t = (Input.mouse_x.between?(615, 785) && Input.mouse_y.between?(445, 475))
  Window.draw_rect(615, 445, 170, 30, color: btn_hover_t ? Color.new(70, 130, 200) : Color.new(50, 80, 130), radius: 4.0)
  Window.draw_text(628, 452, "Next Sample Text", size: 14, color: :white)
  if btn_hover_t && Input.mouse_push?(:left)
    text_idx = (text_idx + 1) % sample_texts.length
  end

  cur_sample = sample_texts[text_idx]
  target_size = 20.0
  # Window.text_size で幅と高さを事前計算！
  tw, th = Window.text_size(cur_sample, size: target_size)

  # テキスト描画位置
  tx = 625.0
  ty = 495.0

  # 計測されたサイズに基づくバウンディングボックスの描画
  # (外枠と半透明の背景を敷き、テキストがぴったり収まることを可視化)
  pad = 6.0
  Window.draw_rect(tx - pad, ty - pad, tw + pad * 2.0, th + pad * 2.0,
                   color: Color.new(40, 55, 75, 180),
                   border_color: Color.new(255, 200, 80),
                   border_width: 2.0,
                   radius: 4.0)

  # テキスト本体の描画
  Window.draw_text(tx, ty, cur_sample, size: target_size, color: :white)

  # サイズ情報表示
  Window.draw_text(615, 640, "Calculated Box: #{tw.round(1)} x #{th.round(1)} px  (Lines: #{cur_sample.count("\n") + 1})", size: 13, color: Color.new(255, 220, 120))
end

module Zenoo
  module Input
    # キーシンボルからGLFWキーコードへのマッピング
    KEY_MAP = {
      space: 32,
      escape: 256,
      enter: 257,
      tab: 258,
      backspace: 259,
      insert: 260,
      delete: 261,
      right: 262,
      left: 263,
      down: 264,
      up: 265,
      page_up: 266,
      page_down: 267,
      home: 268,
      end: 269,
      f11: 290,
    }

    # アルファベットキー (a..z)
    (?a..?z).each do |ch|
      KEY_MAP[ch.to_sym] = ch.upcase.ord
    end

    # 数字キー (0..9)
    (?0..?9).each do |ch|
      KEY_MAP[ch.to_sym] = ch.ord
    end

    MOUSE_MAP = {
      left: 0,
      right: 1,
      middle: 2
    }

    def self.resolve_key(key)
      KEY_MAP[key] || key.to_i
    end

    def self.resolve_mouse(button)
      MOUSE_MAP[button] || button.to_i
    end

    # 押されている状態 (持続)
    def self.key_pressed?(key)
      Native::Input.key_pressed?(resolve_key(key))
    end

    # 押した瞬間 (トリガー)
    def self.key_push?(key)
      Native::Input.key_push?(resolve_key(key))
    end

    # 離した瞬間 (リリース)
    def self.key_release?(key)
      Native::Input.key_release?(resolve_key(key))
    end

    # 押した瞬間、または長押しによるキーリピート
    def self.key_repeat?(key)
      Native::Input.key_repeat?(resolve_key(key))
    end

    # フレーム内で入力された文字（UTF-8文字列）の配列
    def self.input_chars
      Native::Input.input_chars
    end

    # IME変換候補ウィンドウの位置設定
    def self.set_ime_position(x, y)
      Native::Input.set_ime_position(x.to_i, y.to_i) if Native::Input.respond_to?(:set_ime_position)
    end

    # マウス座標
    def self.mouse_x
      Native::Input.mouse_x
    end

    def self.mouse_y
      Native::Input.mouse_y
    end

    def self.mouse_pos
      [Native::Input.mouse_x, Native::Input.mouse_y]
    end

    def self.mouse_pressed?(button = :left)
      Native::Input.mouse_pressed?(resolve_mouse(button))
    end

    def self.mouse_push?(button = :left)
      Native::Input.mouse_push?(resolve_mouse(button))
    end

    def self.mouse_release?(button = :left)
      Native::Input.mouse_release?(resolve_mouse(button))
    end

    # ==========================================
    # ゲームパッド API
    # ==========================================
    def self.resolve_gamepad_button(btn)
      return btn.to_i if btn.is_a?(Integer)
      case btn
      when :a, :cross then 0
      when :b, :circle then 1
      when :x, :square then 2
      when :y, :triangle then 3
      when :lb, :left_bumper, :l1 then 4
      when :rb, :right_bumper, :r1 then 5
      when :back, :select, :share then 6
      when :start, :options, :menu then 7
      when :guide, :home then 8
      when :left_thumb, :lthumb, :l3 then 9
      when :right_thumb, :rthumb, :r3 then 10
      when :dpad_up, :up then 11
      when :dpad_right, :right then 12
      when :dpad_down, :down then 13
      when :dpad_left, :left then 14
      else btn.to_i
      end
    end

    def self.resolve_gamepad_axis(axis)
      return axis.to_i if axis.is_a?(Integer)
      case axis
      when :lx, :left_x then 0
      when :ly, :left_y then 1
      when :rx, :right_x then 2
      when :ry, :right_y then 3
      when :lt, :left_trigger, :l2 then 4
      when :rt, :right_trigger, :r2 then 5
      else axis.to_i
      end
    end

    def self.gamepad_connected?(id = 0)
      Native::Input.gamepad_connected?(id.to_i)
    end

    def self.gamepad_axis(axis, id = 0)
      Native::Input.gamepad_axis(id.to_i, resolve_gamepad_axis(axis))
    end

    def self.gamepad_button_pressed?(button, id = 0)
      Native::Input.gamepad_button_pressed?(id.to_i, resolve_gamepad_button(button))
    end

    def self.gamepad_button_push?(button, id = 0)
      Native::Input.gamepad_button_push?(id.to_i, resolve_gamepad_button(button))
    end

    def self.gamepad_button_release?(button, id = 0)
      Native::Input.gamepad_button_release?(id.to_i, resolve_gamepad_button(button))
    end

    # ゲームパッドの振動 (デュアルランブル)
    def self.vibrate_gamepad(id = 0, strong = 1.0, weak = 1.0, duration = 0.2)
      Native::Input.vibrate_gamepad(id.to_i, strong.to_f, weak.to_f, duration.to_f)
    end

    # スマホ/デバイス本体の振動 (Web/Android等)
    def self.vibrate(duration = 0.2)
      Native::Input.vibrate(duration.to_f)
    end

    # アナログスティックの円形デッドゾーン処理 (Radial Deadzone)
    def self.apply_deadzone(vx, vy, deadzone = 0.2)
      len = Math.sqrt(vx * vx + vy * vy)
      if len <= deadzone
        return [0.0, 0.0]
      end
      scale = (len - deadzone) / (1.0 - deadzone)
      scale = 1.0 if scale > 1.0
      [(vx / len) * scale, (vy / len) * scale]
    end

    # 左スティックの正規化ベクトル [x, y] (-1.0 .. 1.0)
    def self.left_stick(id = 0, deadzone = 0.2)
      vx = gamepad_axis(0, id)
      vy = gamepad_axis(1, id)
      apply_deadzone(vx, vy, deadzone)
    end

    # 右スティックの正規化ベクトル [x, y] (-1.0 .. 1.0)
    def self.right_stick(id = 0, deadzone = 0.2)
      vx = gamepad_axis(2, id)
      vy = gamepad_axis(3, id)
      apply_deadzone(vx, vy, deadzone)
    end

    # ==========================================
    # DXRuby 風 入力 API (方向・移動)
    # ==========================================
    # 水平方向の入力値 (-1.0 .. 1.0)
    # キーボード (A/D, 矢印左右)、十字キー、左アナログスティックを自動統合
    def self.x(id = 0)
      dx = 0.0
      dx -= 1.0 if key_pressed?(:a) || key_pressed?(:left) || gamepad_button_pressed?(:dpad_left, id)
      dx += 1.0 if key_pressed?(:d) || key_pressed?(:right) || gamepad_button_pressed?(:dpad_right, id)
      return dx if dx != 0.0

      stick = left_stick(id, 0.2)
      stick[0].to_f
    end

    # 垂直方向の入力値 (-1.0 .. 1.0)
    # キーボード (W/S, 矢印上下)、十字キー、左アナログスティックを自動統合
    def self.y(id = 0)
      dy = 0.0
      dy -= 1.0 if key_pressed?(:w) || key_pressed?(:up) || gamepad_button_pressed?(:dpad_up, id)
      dy += 1.0 if key_pressed?(:s) || key_pressed?(:down) || gamepad_button_pressed?(:dpad_down, id)
      return dy if dy != 0.0

      stick = left_stick(id, 0.2)
      stick[1].to_f
    end

    # 右スティック水平方向 (-1.0 .. 1.0)
    def self.rx(id = 0)
      stick = right_stick(id, 0.2)
      stick[0].to_f
    end

    # 右スティック垂直方向 (-1.0 .. 1.0)
    def self.ry(id = 0)
      stick = right_stick(id, 0.2)
      stick[1].to_f
    end
  end
end

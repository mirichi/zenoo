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
    # 方向・移動 API (DXRuby 互換 & 簡易アクセス)
    # ==========================================
    # 水平方向の入力値 (-1.0 .. 1.0)
    # デフォルトでアクション :left と :right を合成
    def self.x(id = 0)
      axis(:left, :right, id)
    end

    # 垂直方向の入力値 (-1.0 .. 1.0)
    # デフォルトでアクション :up と :down を合成
    def self.y(id = 0)
      axis(:up, :down, id)
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

    # ==========================================
    # アクションマッピング API (Input Action Map)
    # ==========================================
    @actions = {}
    @axis_state_prev = {} # { [axis, id, dir] => boolean }

    def self.actions
      @actions
    end

    # アクションの定義・追加登録
    # @param name [Symbol] アクション名 (例: :jump, :ui_accept)
    # @param keys [Symbol, Array<Symbol>] キーボードのキー
    # @param gamepad [Symbol, Integer, Array] ゲームパッドのボタン
    # @param mouse [Symbol, Integer, Array] マウスのボタン (:left, :right, :middle)
    # @param stick [Symbol] スティック方向ショートカット (:up, :down, :left, :right)
    # @param axes [Array<Array>] アナログ軸バインド [axis_sym, direction, threshold]
    def self.define_action(name, keys: nil, gamepad: nil, mouse: nil, stick: nil, axes: nil)
      act = (@actions[name.to_sym] ||= { keys: [], gamepad: [], mouse: [], axes: [] })
      if keys
        Array(keys).each do |k|
          rk = resolve_key(k)
          act[:keys] << rk unless act[:keys].include?(rk)
        end
      end
      if gamepad
        Array(gamepad).each do |b|
          rb = resolve_gamepad_button(b)
          act[:gamepad] << rb unless act[:gamepad].include?(rb)
        end
      end
      if mouse
        Array(mouse).each do |m|
          rm = resolve_mouse(m)
          act[:mouse] << rm unless act[:mouse].include?(rm)
        end
      end
      if stick
        case stick
        when :up    then (act[:axes] << [:ly, :negative, 0.5, 0.2]) unless act[:axes].any? { |a| a[0] == :ly && a[1] == :negative }
        when :down  then (act[:axes] << [:ly, :positive, 0.5, 0.2]) unless act[:axes].any? { |a| a[0] == :ly && a[1] == :positive }
        when :left  then (act[:axes] << [:lx, :negative, 0.5, 0.2]) unless act[:axes].any? { |a| a[0] == :lx && a[1] == :negative }
        when :right then (act[:axes] << [:lx, :positive, 0.5, 0.2]) unless act[:axes].any? { |a| a[0] == :lx && a[1] == :positive }
        end
      end
      if axes
        Array(axes).each do |ax|
          act[:axes] << ax unless act[:axes].include?(ax)
        end
      end
      act
    end

    # 指定したアクション、または全アクションをクリア
    def self.clear_action(name = nil)
      if name
        @actions.delete(name.to_sym)
      else
        @actions.clear
      end
    end

    # アクションの強度 (0.0 .. 1.0)
    def self.action_strength(name, id = 0)
      act = @actions[name.to_sym]
      return 0.0 unless act

      max_val = 0.0

      # 1. キーボード
      act[:keys].each do |k|
        return 1.0 if Native::Input.key_pressed?(k)
      end

      # 2. ゲームパッドボタン
      act[:gamepad].each do |b|
        return 1.0 if Native::Input.gamepad_button_pressed?(id.to_i, b)
      end

      # 3. マウスボタン
      act[:mouse].each do |m|
        return 1.0 if Native::Input.mouse_pressed?(m)
      end

      # 4. アナログ軸 (トリガーやスティック)
      act[:axes].each do |ax_def|
        axis_name, dir, _thresh, deadzone = ax_def
        deadzone ||= 0.2
        val = gamepad_axis(axis_name, id)
        raw = case dir
              when :positive then val > 0.0 ? val : 0.0
              when :negative then val < 0.0 ? -val : 0.0
              else val > 0.0 ? val : 0.0
              end

        strength = if raw <= deadzone
                     0.0
                   else
                     ((raw - deadzone) / (1.0 - deadzone)).clamp(0.0, 1.0)
                   end

        max_val = strength if strength > max_val
      end

      max_val
    end

    # アクションが押されているか (持続)
    def self.action_pressed?(name, id = 0)
      act = @actions[name.to_sym]
      return false unless act

      # キーボード
      act[:keys].each do |k|
        return true if Native::Input.key_pressed?(k)
      end

      # ゲームパッドボタン
      act[:gamepad].each do |b|
        return true if Native::Input.gamepad_button_pressed?(id.to_i, b)
      end

      # マウスボタン
      act[:mouse].each do |m|
        return true if Native::Input.mouse_pressed?(m)
      end

      # アナログ軸
      act[:axes].each do |ax_def|
        axis_name, dir, thresh, _deadzone = ax_def
        thresh ||= 0.5
        val = gamepad_axis(axis_name, id)
        case dir
        when :positive
          return true if val >= thresh
        when :negative
          return true if val <= -thresh
        else
          return true if val >= thresh
        end
      end

      false
    end

    # アクションが押された瞬間か (トリガー)
    def self.action_push?(name, id = 0)
      act = @actions[name.to_sym]
      return false unless act

      # キーボード
      act[:keys].each do |k|
        return true if Native::Input.key_push?(k)
      end

      # ゲームパッドボタン
      act[:gamepad].each do |b|
        return true if Native::Input.gamepad_button_push?(id.to_i, b)
      end

      # マウスボタン
      act[:mouse].each do |m|
        return true if Native::Input.mouse_push?(m)
      end

      # アナログ軸の閾値クロス判定 (今フレームで閾値を超え、前フレームでは未超過)
      act[:axes].each do |ax_def|
        axis_name, dir, thresh, _deadzone = ax_def
        thresh ||= 0.5
        val = gamepad_axis(axis_name, id)
        cur_active = case dir
                     when :positive then val >= thresh
                     when :negative then val <= -thresh
                     else val >= thresh
                     end
        key = [axis_name, id.to_i, dir]
        prev_active = @axis_state_prev[key] || false
        return true if cur_active && !prev_active
      end

      false
    end

    # アクションが離された瞬間か (リリース)
    def self.action_release?(name, id = 0)
      act = @actions[name.to_sym]
      return false unless act

      act[:keys].each do |k|
        return true if Native::Input.key_release?(k)
      end

      act[:gamepad].each do |b|
        return true if Native::Input.gamepad_button_release?(id.to_i, b)
      end

      act[:mouse].each do |m|
        return true if Native::Input.mouse_release?(m)
      end

      # アナログ軸のリリース判定
      act[:axes].each do |ax_def|
        axis_name, dir, thresh, _deadzone = ax_def
        thresh ||= 0.5
        val = gamepad_axis(axis_name, id)
        cur_active = case dir
                     when :positive then val >= thresh
                     when :negative then val <= -thresh
                     else val >= thresh
                     end
        key = [axis_name, id.to_i, dir]
        prev_active = @axis_state_prev[key] || false
        return true if !cur_active && prev_active
      end

      false
    end

    # 軸の入力値 (-1.0 .. 1.0)
    # positive_action の強さ - negative_action の強さ
    def self.axis(negative_action, positive_action, id = 0)
      pos = action_strength(positive_action, id)
      neg = action_strength(negative_action, id)
      pos - neg
    end

    # 2次元移動ベクトル [dx, dy]
    # 4方向のアクションからベクトルを算出し、長さを 1.0 にクランプ (斜め移動速度超過を防止)
    # 引数省略時はデフォルトで (:left, :right, :up, :down) を使用
    def self.vector(negative_x = :left, positive_x = :right, negative_y = :up, positive_y = :down, id: 0)
      dx = axis(negative_x, positive_x, id)
      dy = axis(negative_y, positive_y, id)

      len = Math.sqrt(dx * dx + dy * dy)
      if len > 1.0
        dx /= len
        dy /= len
      end
      [dx, dy]
    end

    # 毎フレーム末尾で軸状態を更新 (Window.__update_step から自動呼出し)
    def self.__update_step
      @actions.each_value do |act|
        act[:axes].each do |ax_def|
          axis_name, dir, thresh, _deadzone = ax_def
          thresh ||= 0.5
          val = gamepad_axis(axis_name, 0)
          cur_active = case dir
                       when :positive then val >= thresh
                       when :negative then val <= -thresh
                       else val >= thresh
                       end
          @axis_state_prev[[axis_name, 0, dir]] = cur_active
        end
      end
    end

    # デフォルトの組み込みアクション初期化
    def self.__init_default_actions
      # --- UI ナビゲーション用アクション ---
      define_action(:ui_accept, keys: [:enter, :space, :z], gamepad: [:a], mouse: [:left])
      define_action(:ui_cancel, keys: [:escape, :x], gamepad: [:b], mouse: [:right])
      define_action(:ui_up,     keys: [:up, :w], gamepad: [:dpad_up], stick: :up)
      define_action(:ui_down,   keys: [:down, :s], gamepad: [:dpad_down], stick: :down)
      define_action(:ui_left,   keys: [:left, :a], gamepad: [:dpad_left], stick: :left)
      define_action(:ui_right,  keys: [:right, :d], gamepad: [:dpad_right], stick: :right)

      # --- ゲームプレイ・自機移動用アクション (プレフィックスなし) ---
      define_action(:up,        keys: [:up, :w], gamepad: [:dpad_up], stick: :up)
      define_action(:down,      keys: [:down, :s], gamepad: [:dpad_down], stick: :down)
      define_action(:left,      keys: [:left, :a], gamepad: [:dpad_left], stick: :left)
      define_action(:right,     keys: [:right, :d], gamepad: [:dpad_right], stick: :right)
    end

    __init_default_actions
  end
end

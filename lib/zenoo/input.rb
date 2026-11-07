module Zenoo
  # ==============================================================================
  # Zenoo::Touch
  # 画面に指が触れてから離れるまでの 1 回のタッチセッションを具現化するクラス。
  # 指が離された後は値がフリーズし、以後は情報が更新されません。
  # ==============================================================================
  class Touch
    attr_reader :id, :start_x, :start_y, :x, :y, :prev_x, :prev_y, :duration

    def initialize(id, x, y)
      @id = id
      @start_x = x
      @start_y = y
      @x = x
      @y = y
      @prev_x = x
      @prev_y = y
      @active = true
      @released = false
      @cancelled = false
      @consumed = false
      @duration = 0
    end

    def active?
      @active
    end

    def released?
      @released
    end

    def cancelled?
      @cancelled
    end

    # UI・GUI等で処理済みとしてマークされているか (バーチャルパッド等への貫通防止)
    def consumed?
      @consumed
    end

    def consume!
      @consumed = true
    end

    # 前フレームからの移動量 (Delta)
    def dx
      @x - @prev_x
    end

    def dy
      @y - @prev_y
    end

    # 触れた起点からの総移動量
    def total_dx
      @x - @start_x
    end

    def total_dy
      @y - @start_y
    end

    # 触れた起点からの直線距離
    def distance
      Math.hypot(@x - @start_x, @y - @start_y)
    end

    # 内部更新用: 指が動いた時 (アクティブ時のみ)
    # ※ @prev_x / @prev_y はフレーム開始時 (__step) のみ更新するため、ここでは @x / @y のみ更新
    def __update(new_x, new_y)
      return unless @active
      @x = new_x
      @y = new_y
    end

    # 内部更新用: 指が離された/キャンセルされた時 (値フリーズ)
    # ※ @prev_x / @prev_y はフレーム開始時 (__step) のみ更新するため、ここでは @x / @y のみ更新
    def __finish(released, final_x = nil, final_y = nil)
      return unless @active
      if final_x && final_y
        @x = final_x
        @y = final_y
      end
      @active = false
      if released
        @released = true
      else
        @cancelled = true
      end
    end

    # 内部更新用: フレーム進行
    def __step
      @duration += 1 if @active
      @prev_x = @x
      @prev_y = @y
    end
  end

  module Input
    # キーシンボルからGLFWキーコードへのマッピング
    KEY_MAP = {
      # 記号キー
      apostrophe: 39,
      comma: 44,
      minus: 45,
      period: 46,
      slash: 47,
      semicolon: 59,
      equal: 61,
      left_bracket: 91,
      backslash: 92,
      right_bracket: 93,
      grave_accent: 96,

      # 制御・移動キー
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

      # 特殊・ロック
      caps_lock: 280,
      scroll_lock: 281,
      num_lock: 282,
      print_screen: 283,
      pause: 284,

      # テンキー
      kp_0: 320,
      kp_1: 321,
      kp_2: 322,
      kp_3: 323,
      kp_4: 324,
      kp_5: 325,
      kp_6: 326,
      kp_7: 327,
      kp_8: 328,
      kp_9: 329,
      kp_decimal: 330,
      kp_divide: 331,
      kp_multiply: 332,
      kp_subtract: 333,
      kp_add: 334,
      kp_enter: 335,
      kp_equal: 336,

      # 修飾キー (左右別)
      left_shift: 340,
      left_control: 341,
      left_ctrl: 341,
      left_alt: 342,
      left_super: 343,
      left_win: 343,
      left_command: 343,
      right_shift: 344,
      right_control: 345,
      right_ctrl: 345,
      right_alt: 346,
      right_super: 347,
      right_win: 347,
      right_command: 347,
      menu: 348,

      # 修飾キー (左右統合エイリアス)
      shift: 340,
      control: 341,
      ctrl: 341,
      alt: 342,
      super: 343,
      win: 343,
      command: 343
    }

    # ファンクションキー (f1..f12)
    (1..12).each do |i|
      KEY_MAP[:"f#{i}"] = 289 + i
    end

    # アルファベットキー (a..z)
    (?a..?z).each do |ch|
      KEY_MAP[ch.to_sym] = ch.upcase.ord
    end

    # 数字キー (0..9, num0..num9)
    (?0..?9).each do |ch|
      KEY_MAP[ch.to_sym] = ch.ord
      KEY_MAP[:"num#{ch}"] = ch.ord
    end

    MOUSE_MAP = {
      left: 0,
      right: 1,
      middle: 2
    }

    def self.resolve_key(key)
      KEY_MAP[key] || (key.respond_to?(:to_i) ? key.to_i : 0)
    end

    def self.resolve_mouse(button)
      MOUSE_MAP[button] || (button.respond_to?(:to_i) ? button.to_i : 0)
    end

    # 押されている状態 (持続)
    def self.key_pressed?(key)
      if key == :shift
        Native::Input.key_pressed?(340) || Native::Input.key_pressed?(344)
      elsif key == :ctrl || key == :control
        Native::Input.key_pressed?(341) || Native::Input.key_pressed?(345)
      elsif key == :alt
        Native::Input.key_pressed?(342) || Native::Input.key_pressed?(346)
      elsif key == :super || key == :win || key == :command
        Native::Input.key_pressed?(343) || Native::Input.key_pressed?(347)
      else
        Native::Input.key_pressed?(resolve_key(key))
      end
    end

    def self.key_down?(key)
      key_pressed?(key)
    end

    # 押した瞬間 (トリガー)
    def self.key_push?(key)
      if key == :shift
        Native::Input.key_push?(340) || Native::Input.key_push?(344)
      elsif key == :ctrl || key == :control
        Native::Input.key_push?(341) || Native::Input.key_push?(345)
      elsif key == :alt
        Native::Input.key_push?(342) || Native::Input.key_push?(346)
      elsif key == :super || key == :win || key == :command
        Native::Input.key_push?(343) || Native::Input.key_push?(347)
      else
        Native::Input.key_push?(resolve_key(key))
      end
    end

    # 離した瞬間 (リリース)
    def self.key_release?(key)
      if key == :shift
        Native::Input.key_release?(340) || Native::Input.key_release?(344)
      elsif key == :ctrl || key == :control
        Native::Input.key_release?(341) || Native::Input.key_release?(345)
      elsif key == :alt
        Native::Input.key_release?(342) || Native::Input.key_release?(346)
      elsif key == :super || key == :win || key == :command
        Native::Input.key_release?(343) || Native::Input.key_release?(347)
      else
        Native::Input.key_release?(resolve_key(key))
      end
    end

    # 押した瞬間、または長押しによるキーリピート
    def self.key_repeat?(key)
      if key == :shift
        Native::Input.key_repeat?(340) || Native::Input.key_repeat?(344)
      elsif key == :ctrl || key == :control
        Native::Input.key_repeat?(341) || Native::Input.key_repeat?(345)
      elsif key == :alt
        Native::Input.key_repeat?(342) || Native::Input.key_repeat?(346)
      elsif key == :super || key == :win || key == :command
        Native::Input.key_repeat?(343) || Native::Input.key_repeat?(347)
      else
        Native::Input.key_repeat?(resolve_key(key))
      end
    end

    # フレーム内で入力された文字（UTF-8文字列）の配列
    def self.input_chars
      Native::Input.input_chars
    end

    # IME変換候補ウィンドウの位置設定
    def self.set_ime_position(x, y)
      Native::Input.set_ime_position(x.to_i, y.to_i)
    end

    # マウス座標 (タッチ操作時は未消費のアクティブタッチ座標を透過的に反映)
    def self.mouse_x
      if @using_touch
        t = __mouse_emulation_touch
        t ? t.x : (@last_emulated_mx || Native::Input.mouse_x)
      else
        Native::Input.mouse_x
      end
    end

    def self.mouse_y
      if @using_touch
        t = __mouse_emulation_touch
        t ? t.y : (@last_emulated_my || Native::Input.mouse_y)
      else
        Native::Input.mouse_y
      end
    end

    def self.mouse_pos
      [mouse_x, mouse_y]
    end

    # タッチ操作をマウス左ボタンとしてエミュレートする対象の Touch を取得
    # (同一タッチのドラッグ中は consume! されていても継続して追跡)
    def self.__mouse_emulation_touch
      return nil unless @using_touch

      # 1. 既にマウス操作として追跡中のタッチがあれば、消費済みであっても離されるまで継続追跡
      if @mouse_touch_id
        t = @active_touches[@mouse_touch_id]
        if t.nil?
          i = 0
          len = @touches.length
          while i < len
            cand = @touches[i]
            if cand && cand.id == @mouse_touch_id
              t = cand
              break
            end
            i += 1
          end
        end

        if t && (t.active? || t.released?)
          return t
        else
          @mouse_touch_id = nil
        end
      end

      # 2. 追跡対象がなければ、未消費のアクティブタッチから新たに選定
      i = 0
      len = @touches.length
      while i < len
        t = @touches[i]
        if t && !t.consumed? && t.active?
          @mouse_touch_id = t.id
          return t
        end
        i += 1
      end
      nil
    end

    def self.mouse_pressed?(button = :left)
      b = resolve_mouse(button)
      if @using_touch
        if b == 0 # 左クリックのみタッチでエミュレート
          t = __mouse_emulation_touch
          t ? t.active? : false
        else
          false
        end
      else
        Native::Input.mouse_pressed?(b)
      end
    end

    def self.mouse_down?(button = :left)
      mouse_pressed?(button)
    end

    def self.mouse_push?(button = :left)
      b = resolve_mouse(button)
      if @using_touch
        if b == 0
          t = __mouse_emulation_touch
          t ? (t.duration == 0 && !t.cancelled?) : false
        else
          false
        end
      else
        Native::Input.mouse_push?(b)
      end
    end

    def self.mouse_release?(button = :left)
      b = resolve_mouse(button)
      if @using_touch
        if b == 0
          t = __mouse_emulation_touch
          t ? t.released? : false
        else
          false
        end
      else
        Native::Input.mouse_release?(b)
      end
    end

    # 現在のマウス操作（またはタッチ）を消費し、以降のUIやゲーム側のクリック反応を抑止
    def self.consume_mouse!
      if @using_touch
        t = __mouse_emulation_touch
        t.consume! if t
      else
        @virtual_pad.consume_mouse_touch! if @virtual_pad
      end
    end

    # マウスホイール (スクロール量)
    def self.mouse_wheel_x
      Native::Input.mouse_wheel_x
    end

    def self.mouse_wheel_y
      Native::Input.mouse_wheel_y
    end

    def self.mouse_wheel
      Native::Input.mouse_wheel
    end

    # クリップボード
    def self.clipboard
      Native::Input.clipboard
    end

    def self.clipboard=(str)
      Native::Input.clipboard = str.to_s
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
      else
        btn.respond_to?(:to_i) ? btn.to_i : 0
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
      else
        axis.respond_to?(:to_i) ? axis.to_i : 0
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

    def self.gamepad_button_down?(button, id = 0)
      gamepad_button_pressed?(button, id)
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
      return @vpad_rx if @vpad_rx && @vpad_rx != 0.0
      stick = right_stick(id, 0.2)
      stick[0].to_f
    end

    # 右スティック垂直方向 (-1.0 .. 1.0)
    def self.ry(id = 0)
      return @vpad_ry if @vpad_ry && @vpad_ry != 0.0
      stick = right_stick(id, 0.2)
      stick[1].to_f
    end

    # ==========================================
    # アクションマッピング API (Input Action Map)
    # ==========================================
    @actions = {}
    @axis_state_prev = {} # { [axis, id, dir] => boolean }
    @virtual_pad = nil
    @vpad_actions_cur = {}
    @vpad_actions_prev = {}
    @vpad_rx = 0.0
    @vpad_ry = 0.0

    def self.actions
      @actions
    end

    def self.virtual_pad
      @virtual_pad
    end

    def self.virtual_pad=(pad)
      @virtual_pad.reset if @virtual_pad
      @virtual_pad = pad
      @vpad_actions_cur.clear
      @vpad_actions_prev.clear
      @vpad_rx = 0.0
      @vpad_ry = 0.0
    end

    # 仮想アクション注入 (VirtualPad 等から今フレームのアクション強度を注入)
    def self.inject_action(name, strength = 1.0)
      sym = name.to_sym
      val = strength.to_f.clamp(0.0, 1.0)
      cur = @vpad_actions_cur[sym] || 0.0
      @vpad_actions_cur[sym] = val if val > cur
    end

    # 仮想2次元ベクトル注入 (VirtualPad のスティックやフリック方向を移動アクションへ注入)
    def self.inject_vector(dx, dy)
      vx = dx.to_f
      vy = dy.to_f
      len = Math.hypot(vx, vy)
      if len > 1.0
        vx /= len
        vy /= len
      end
      if vx < 0.0
        inject_action(:left, -vx)
      elsif vx > 0.0
        inject_action(:right, vx)
      end
      if vy < 0.0
        inject_action(:up, -vy)
      elsif vy > 0.0
        inject_action(:down, vy)
      end
    end

    # 仮想右スティックベクトル注入 (VirtualPad の照準スティック等を Input.rx / Input.ry へ注入)
    def self.inject_right_vector(dx, dy)
      rx = dx.to_f
      ry = dy.to_f
      len = Math.hypot(rx, ry)
      if len > 1.0
        rx /= len
        ry /= len
      end
      @vpad_rx = rx
      @vpad_ry = ry
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
      sym = name.to_sym
      vpad_val = @vpad_actions_cur[sym] || 0.0
      act = @actions[sym]
      return vpad_val unless act

      max_val = vpad_val

      # 1. キーボード
      act[:keys].each do |k|
        return 1.0 if Native::Input.key_pressed?(k)
      end

      # 2. ゲームパッドボタン
      act[:gamepad].each do |b|
        return 1.0 if Native::Input.gamepad_button_pressed?(id.to_i, b)
      end

      # 3. マウスボタン (タッチ時はエミュレーション経由で判定)
      act[:mouse].each do |m|
        return 1.0 if mouse_pressed?(m)
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
      sym = name.to_sym
      vpad_val = @vpad_actions_cur[sym] || 0.0
      return true if vpad_val >= 0.5

      act = @actions[sym]
      return false unless act

      # キーボード
      act[:keys].each do |k|
        return true if Native::Input.key_pressed?(k)
      end

      # ゲームパッドボタン
      act[:gamepad].each do |b|
        return true if Native::Input.gamepad_button_pressed?(id.to_i, b)
      end

      # マウスボタン (タッチ時はエミュレーション経由で判定)
      act[:mouse].each do |m|
        return true if mouse_pressed?(m)
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

    def self.action_down?(name, id = 0)
      action_pressed?(name, id)
    end

    # アクションが押された瞬間か (トリガー)
    def self.action_push?(name, id = 0)
      sym = name.to_sym
      cur_vpad = (@vpad_actions_cur[sym] || 0.0) >= 0.5
      prev_vpad = @vpad_actions_prev[sym] || false
      return true if cur_vpad && !prev_vpad

      act = @actions[sym]
      return false unless act

      # キーボード
      act[:keys].each do |k|
        return true if Native::Input.key_push?(k)
      end

      # ゲームパッドボタン
      act[:gamepad].each do |b|
        return true if Native::Input.gamepad_button_push?(id.to_i, b)
      end

      # マウスボタン (タッチ時はエミュレーション経由で判定)
      act[:mouse].each do |m|
        return true if mouse_push?(m)
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
      sym = name.to_sym
      cur_vpad = (@vpad_actions_cur[sym] || 0.0) >= 0.5
      prev_vpad = @vpad_actions_prev[sym] || false
      return true if !cur_vpad && prev_vpad

      act = @actions[sym]
      return false unless act

      act[:keys].each do |k|
        return true if Native::Input.key_release?(k)
      end

      act[:gamepad].each do |b|
        return true if Native::Input.gamepad_button_release?(id.to_i, b)
      end

      # マウスボタン (タッチ時はエミュレーション経由で判定)
      act[:mouse].each do |m|
        return true if mouse_release?(m)
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

    # ==========================================================================
    # マルチタッチ API (Touch Session Lifecycle)
    # ==========================================================================
    @active_touches = {}
    @touches = []
    @using_touch = false
    @mouse_touch_id = nil
    @touch_guard_frames = 0
    @last_raw_mx = 0.0
    @last_raw_my = 0.0

    # 現在タッチ操作モード中か (ブラウザのタッチ由来マウスエミュレーションを自動排除し、物理マウス移動時にfalseへ復帰)
    def self.using_touch?
      @using_touch
    end

    # 現在アクティブ、またはこのフレームで離された Touch オブジェクトの配列
    def self.touches
      @touches
    end

    # タッチIDから該当する Touch オブジェクトを取得 (無効/終了時は nil)
    def self.touch(id)
      @active_touches[id]
    end

    # タッチ入力が利用可能・発生しているか
    def self.touch_available?
      !@active_touches.empty? || !@touches.empty?
    end

    # 現在追跡中の全タッチセッションを強制キャンセルします (シーン・モーダル遷移時の誤タッチ防止)
    def self.cancel_touches
      i = 0
      len = @touches.length
      while i < len
        t = @touches[i]
        t.__finish(false) if t
        i += 1
      end
      @active_touches.clear
      @touches.clear
      @mouse_touch_id = nil
      @vpad_actions_cur.clear
      @vpad_actions_prev.clear
      @vpad_rx = 0.0
      @vpad_ry = 0.0
      @virtual_pad.reset if @virtual_pad
      Native::Input.touch_clear_events
    end

    # フレーム開始時: 終了済みTouchの除去 & Cカーネルからの生イベント反映
    def self.__begin_frame
      @vpad_actions_cur.clear
      @vpad_rx = 0.0
      @vpad_ry = 0.0

      # 1. 前フレームで終了（離脱/キャンセル）していた Touch を一覧から除外
      i = 0
      while i < @touches.length
        t = @touches[i]
        if t.released? || t.cancelled?
          @touches.delete_at(i)
        else
          t.__step
          i += 1
        end
      end

      # 2. Cカーネルのキューから生イベントを読み出す
      count = Native::Input.touch_event_count
      if count > 0
        idx = 0
        while idx < count
          tid  = Native::Input.touch_event_id(idx)
          type = Native::Input.touch_event_type(idx)
          tx   = Native::Input.touch_event_x(idx)
          ty   = Native::Input.touch_event_y(idx)

          case type
          when 0 # DOWN
            t = Touch.new(tid, tx, ty)
            @active_touches[tid] = t
            @touches << t
          when 1 # MOVE
            t = @active_touches[tid]
            t.__update(tx, ty) if t
          when 2 # UP
            t = @active_touches.delete(tid)
            t.__finish(true, tx, ty) if t
          when 3 # CANCEL
            t = @active_touches.delete(tid)
            t.__finish(false, tx, ty) if t
          end

          idx += 1
        end
        Native::Input.touch_clear_events
      end

      # 3. タッチ操作モードと物理マウス復帰の自動判定
      raw_mx = Native::Input.mouse_x
      raw_my = Native::Input.mouse_y
      if !@touches.empty?
        @using_touch = true
        @touch_guard_frames = 10
        t = __mouse_emulation_touch
        if t
          @last_emulated_mx = t.x
          @last_emulated_my = t.y
        end
      elsif @touch_guard_frames > 0
        @touch_guard_frames -= 1
      elsif @using_touch
        if (raw_mx - @last_raw_mx).abs > 0.5 || (raw_my - @last_raw_my).abs > 0.5 ||
           Native::Input.mouse_wheel_y != 0.0 || Native::Input.mouse_wheel_x != 0.0
          @using_touch = false
          @last_emulated_mx = nil
          @last_emulated_my = nil
        end
      end
      @last_raw_mx = raw_mx
      @last_raw_my = raw_my
    end

    # GUI.begin_frame の直後に呼ばれ、VirtualPad の状態を今フレームの Input へ反映
    def self.__update_virtual_pad
      @virtual_pad.update if @virtual_pad && @virtual_pad.enabled
    end

    # メインループブロック終了後に呼ばれ、VirtualPad を自動描画
    def self.__draw_virtual_pad
      @virtual_pad.draw if @virtual_pad && @virtual_pad.enabled && @virtual_pad.visible && @virtual_pad.auto_draw
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

      @vpad_actions_prev.clear
      @vpad_actions_cur.each do |sym, val|
        @vpad_actions_prev[sym] = (val >= 0.5)
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

# frozen_string_literal: true

module Zenoo
  # ==============================================================================
  # Zenoo::VirtualPad
  # マルチタッチ＆マウス対応のバーチャルパッド制御クラス。
  # Input.virtual_pad にセットすることで、毎フレーム自動的に更新・描画され、
  # スティック移動 (Input.vector) やボタン/ジェスチャー (Input.action_push? 等) を
  # アクションマップへ透過的に注入します。
  # ==============================================================================
  class VirtualPad
    # 領域判定ヘルパー (:left_half, :right_half, :full, または [x, y, w, h])
    def self.in_zone?(zone, px, py, win_w, win_h)
      case zone
      when :left_half
        px < win_w * 0.5
      when :right_half
        px >= win_w * 0.5
      when :full
        true
      else
        if zone.is_a?(Array) && zone.length >= 4
          rx = zone[0].to_f
          ry = zone[1].to_f
          rw = zone[2].to_f
          rh = zone[3].to_f
          px >= rx && px <= rx + rw && py >= ry && py <= ry + rh
        else
          true
        end
      end
    end

    # ==========================================================================
    # Stick: フローティング / 固定バーチャルスティック
    # ==========================================================================
    class Stick
      attr_accessor :zone, :target, :radius, :knob_radius, :deadzone, :follow
      attr_accessor :fixed_x, :fixed_y, :color, :border_color, :knob_color
      attr_reader   :touch, :ox, :oy, :cx, :cy, :vx, :vy, :last_ox, :last_oy

      def initialize(zone: :left_half, target: :move, radius: 90.0, knob_radius: 40.0, deadzone: 12.0,
                     follow: true, fixed_x: nil, fixed_y: nil,
                     color: [0, 0, 0, 70], border_color: [100, 200, 255, 160], knob_color: [0, 220, 255, 180])
        @zone         = zone
        @target       = target.to_sym
        @radius       = radius.to_f
        @knob_radius  = knob_radius.to_f
        @deadzone     = deadzone.to_f
        @follow       = follow
        @fixed_x      = fixed_x ? fixed_x.to_f : nil
        @fixed_y      = fixed_y ? fixed_y.to_f : nil
        @color        = color
        @border_color = border_color
        @knob_color   = knob_color
        reset
      end

      def reset
        @touch      = nil
        @ox         = @fixed_x || 0.0
        @oy         = @fixed_y || 0.0
        @cx         = @ox
        @cy         = @oy
        @last_ox    = @ox
        @last_oy    = @oy
        @vx         = 0.0
        @vy         = 0.0
        @moved      = false
      end

      def active?
        !@touch.nil? && @touch.active? && !@touch.consumed?
      end

      def moving?
        @vx != 0.0 || @vy != 0.0
      end

      def update(touches, win_w, win_h)
        @vx = 0.0
        @vy = 0.0

        if @touch && (@touch.released? || @touch.cancelled? || @touch.consumed?)
          @last_ox = @ox
          @last_oy = @oy
          @touch = nil
          @moved = false
        end

        if @touch.nil?
          i = 0
          len = touches.length
          while i < len
            t = touches[i]
            if t.active? && !t.consumed? && VirtualPad.in_zone?(@zone, t.start_x, t.start_y, win_w, win_h)
              @touch = t
              @ox = @fixed_x ? @fixed_x : t.x
              @oy = @fixed_y ? @fixed_y : t.y
              @cx = @ox
              @cy = @oy
              @last_ox = @ox
              @last_oy = @oy
              @moved = false
              break
            end
            i += 1
          end
        end

        if @touch && @touch.active?
          tdx = @touch.x - @ox
          tdy = @touch.y - @oy
          dist = Math.hypot(tdx, tdy)
          max_r = @radius

          if dist > max_r
            dir_x = tdx / dist
            dir_y = tdy / dist
            if @follow && @fixed_x.nil?
              @ox = @touch.x - dir_x * max_r
              @oy = @touch.y - dir_y * max_r
              @cx = @touch.x
              @cy = @touch.y
            else
              @cx = @ox + dir_x * max_r
              @cy = @oy + dir_y * max_r
            end
            tdx_c = dir_x * max_r
            tdy_c = dir_y * max_r
          else
            @cx = @ox + tdx
            @cy = @oy + tdy
            tdx_c = tdx
            tdy_c = tdy
          end

          @last_ox = @ox
          @last_oy = @oy

          if dist > @deadzone
            @moved = true
            @vx = tdx_c / max_r
            @vy = tdy_c / max_r
          end
        end
      end

      def draw(z)
        if @fixed_x && @fixed_y
          Window.draw_circle(@ox, @oy, @radius, color: @color, border_width: 3, border_color: @border_color, z: z)
          Window.draw_circle(@cx, @cy, @knob_radius, color: @knob_color, border_width: 2, border_color: [255, 255, 255, 220], z: z)
        elsif active? && (@moved || @touch.duration > 4)
          Window.draw_circle(@ox, @oy, @radius, color: @color, border_width: 3, border_color: @border_color, z: z)
          Window.draw_circle(@cx, @cy, @knob_radius, color: @knob_color, border_width: 2, border_color: [255, 255, 255, 220], z: z)
        end
      end
    end

    # ==========================================================================
    # Button: アクションボタン (ワイド判定 & 最寄り吸着対応)
    # ==========================================================================
    class Button
      attr_accessor :action, :x, :y, :radius, :hit_radius, :label, :font_size
      attr_accessor :color, :active_color, :border_color, :active_border_color
      attr_accessor :pressed

      def initialize(action, x:, y:, radius: 56.0, hit_radius: 140.0, label: "", font_size: 20,
                     color: [0, 180, 140, 95], active_color: [0, 255, 190, 200],
                     border_color: [255, 255, 255, 140], active_border_color: [255, 255, 255, 255])
        @action              = action.to_sym
        @x                   = x.to_f
        @y                   = y.to_f
        @radius              = radius.to_f
        @hit_radius          = hit_radius.to_f
        @label               = label.to_s
        @font_size           = font_size.to_i
        @color               = color
        @active_color        = active_color
        @border_color        = border_color
        @active_border_color = active_border_color
        @pressed             = false
      end

      def screen_x(win_w)
        @x < 0.0 ? (win_w + @x) : @x
      end

      def screen_y(win_h)
        @y < 0.0 ? (win_h + @y) : @y
      end

      def reset
        @pressed = false
      end

      def draw(win_w, win_h, z)
        bx = screen_x(win_w)
        by = screen_y(win_h)
        bg = @pressed ? @active_color : @color
        bd = @pressed ? @active_border_color : @border_color
        Window.draw_circle(bx, by, @radius, color: bg, border_width: 2, border_color: bd, z: z)

        unless @label.empty?
          tw = Font.default.text_width(@label, @font_size)
          tx = bx - tw * 0.5
          ty = by - @font_size * 0.52
          Window.draw_text(tx, ty, @label, size: @font_size, color: :white, z: z)
        end
      end
    end

    # ==========================================================================
    # GestureZone: タップ & フリック領域
    # ==========================================================================
    class GestureZone
      attr_accessor :zone, :tap_action, :flick_action, :flick_direction
      attr_accessor :flick_distance, :flick_speed, :tap_max_duration, :shared_with_stick
      attr_accessor :guide_text, :guide_x, :guide_y, :guide_color

      def initialize(zone: :right_half, tap_action: :attack, flick_action: :jump,
                     flick_direction: true, flick_distance: 24.0, flick_speed: 6.0,
                     tap_max_duration: 16, shared_with_stick: false,
                     guide_text: nil, guide_x: nil, guide_y: nil, guide_color: [140, 200, 255, 180])
        @zone              = zone
        @tap_action        = tap_action ? tap_action.to_sym : nil
        @flick_action      = flick_action ? flick_action.to_sym : nil
        @flick_direction   = flick_direction
        @flick_distance    = flick_distance.to_f
        @flick_speed       = flick_speed.to_f
        @tap_max_duration  = tap_max_duration.to_i
        @shared_with_stick = shared_with_stick
        @guide_text        = guide_text
        @guide_x           = guide_x ? guide_x.to_f : nil
        @guide_y           = guide_y ? guide_y.to_f : nil
        @guide_color       = guide_color
      end

      def update(touches, sticks, stick_moving, win_w, win_h)
        i = 0
        len = touches.length
        while i < len
          t = touches[i]
          if t.released? && !t.consumed? && VirtualPad.in_zone?(@zone, t.start_x, t.start_y, win_w, win_h)
            if @shared_with_stick
              evaluate_shared_gesture(t, sticks, stick_moving)
            else
              evaluate_dedicated_gesture(t, stick_moving)
            end
          end
          i += 1
        end
      end

      def draw(win_w, win_h, z)
        return unless @guide_text && !@guide_text.empty?
        gx = @guide_x ? (@guide_x < 0.0 ? win_w + @guide_x : @guide_x) : (win_w * 0.5)
        gy = @guide_y ? (@guide_y < 0.0 ? win_h + @guide_y : @guide_y) : (win_h - 45.0)
        Window.draw_text(gx, gy, @guide_text, size: 13, color: @guide_color, z: z)
      end

      private

      # 専用ジェスチャー領域 (スプリット・ジェスチャーの右画面など)
      # 離した瞬間に移動距離または終端速度が閾値以上ならフリック、それ以外はすべてタップとして扱う (不感帯なし)
      def evaluate_dedicated_gesture(t, stick_moving)
        spd = Math.hypot(t.dx, t.dy)
        if @flick_action && (t.distance >= @flick_distance || spd >= @flick_speed)
          Input.inject_action(@flick_action, 1.0)
          if @flick_direction && !stick_moving
            inject_flick_dir(t.total_dx, t.total_dy)
          end
        elsif @tap_action
          Input.inject_action(@tap_action, 1.0)
        end
      end

      # スティック共有ジェスチャー領域 (ワンハンドモードの全画面など)
      # 長押し移動後の通常リリースでは何も発火せず停止し、素早いタップまたはフリック離しのみ発火する
      def evaluate_shared_gesture(t, sticks, stick_moving)
        spd = Math.hypot(t.dx, t.dy)
        is_flick = spd >= @flick_speed || (t.duration <= 14 && t.distance >= @flick_distance)

        if @flick_action && is_flick
          Input.inject_action(@flick_action, 1.0)
          if @flick_direction && !stick_moving
            if t.duration <= 14
              inject_flick_dir(t.total_dx, t.total_dy)
            else
              # スティック移動からのフリック離し: 追従後のスティック中心からの変位または終端速度ベクトルを使用
              st = sticks[0]
              if st
                sdx = t.x - st.last_ox
                sdy = t.y - st.last_oy
                if Math.hypot(sdx, sdy) > 8.0
                  inject_flick_dir(sdx, sdy)
                else
                  inject_flick_dir(t.dx, t.dy)
                end
              else
                inject_flick_dir(t.dx, t.dy)
              end
            end
          end
        elsif @tap_action && t.distance < @flick_distance && t.duration <= @tap_max_duration
          Input.inject_action(@tap_action, 1.0)
        end
      end

      def inject_flick_dir(fdx, fdy)
        mag = Math.hypot(fdx, fdy)
        if mag > 0.001
          Input.inject_vector(fdx / mag, fdy / mag)
        end
      end
    end

    # ==========================================================================
    # VirtualPad 本体
    # ==========================================================================
    attr_accessor :enabled, :visible, :auto_draw, :mouse_input, :z, :preset_name
    attr_reader   :sticks, :buttons, :gestures

    def initialize(preset_name: :custom)
      @preset_name = preset_name
      @enabled     = true
      @visible     = true
      @auto_draw   = true
      @mouse_input = false
      @z           = 5000.0
      @sticks      = []
      @buttons     = []
      @gestures    = []
      @mouse_touch = nil
      @work_touches = []
    end

    # --------------------------------------------------------------------------
    # プリセット生成ファクトリメソッド
    # --------------------------------------------------------------------------

    # プリセット1: 王道ゲームパッド型 (左: フローティングスティック / 右: 2ボタン)
    def self.gamepad(primary: :attack, secondary: :jump, primary_label: "ATK", secondary_label: "JUMP")
      pad = new(preset_name: :gamepad)
      pad.add_stick(zone: :left_half, radius: 90.0, knob_radius: 40.0, follow: true)
      pad.add_button(
        primary,
        x: -200.0, y: -180.0, radius: 64.0, hit_radius: 140.0,
        label: primary_label, font_size: 22,
        color: [220, 50, 50, 95], active_color: [255, 70, 70, 200]
      )
      pad.add_button(
        secondary,
        x: -400.0, y: -120.0, radius: 56.0, hit_radius: 140.0,
        label: secondary_label, font_size: 18,
        color: [0, 180, 140, 95], active_color: [0, 255, 190, 200]
      )
      pad
    end

    # プリセット2: 画面分割ジェスチャー型 (左: フローティングスティック / 右: タップ＆フリック)
    def self.split_gesture(tap: :attack, flick: :jump, flick_direction: true, show_guide: true)
      pad = new(preset_name: :split_gesture)
      pad.add_stick(zone: :left_half, radius: 90.0, knob_radius: 40.0, follow: true)
      pad.add_gesture(
        zone: :right_half,
        tap_action: tap,
        flick_action: flick,
        flick_direction: flick_direction,
        shared_with_stick: false,
        guide_text: show_guide ? "右画面: タップで#{tap} / フリックで#{flick}" : nil,
        guide_x: -340.0,
        guide_y: -50.0,
        guide_color: [140, 200, 255, 180]
      )
      pad
    end

    # プリセット3: 指1本・ワンハンド型 (全画面: スライドでスティック移動 / タップ＆フリック)
    def self.one_hand(tap: :attack, flick: :jump, flick_direction: true, show_guide: true)
      pad = new(preset_name: :one_hand)
      pad.add_stick(zone: :full, radius: 90.0, knob_radius: 40.0, follow: true)
      pad.add_gesture(
        zone: :full,
        tap_action: tap,
        flick_action: flick,
        flick_direction: flick_direction,
        shared_with_stick: true,
        guide_text: show_guide ? "ワンハンド操作: スライド移動 / タップで#{tap} / フリックで#{flick}" : nil,
        guide_x: 420.0,
        guide_y: -40.0,
        guide_color: [140, 220, 200, 190]
      )
      pad
    end

    # プリセット4: ツインスティック型 (左: 移動スティック / 右: 照準スティック)
    def self.twin_stick
      pad = new(preset_name: :twin_stick)
      pad.add_stick(zone: :left_half, target: :move, radius: 90.0, knob_radius: 40.0, follow: true)
      pad.add_stick(
        zone: :right_half, target: :aim, radius: 90.0, knob_radius: 40.0, follow: true,
        border_color: [255, 170, 90, 160], knob_color: [255, 180, 50, 180]
      )
      pad
    end

    # --------------------------------------------------------------------------
    # パーツ追加 API
    # --------------------------------------------------------------------------
    def add_stick(**opts)
      st = Stick.new(**opts)
      @sticks << st
      st
    end

    def add_button(action, **opts)
      btn = Button.new(action, **opts)
      @buttons << btn
      btn
    end

    def add_gesture(**opts)
      gz = GestureZone.new(**opts)
      @gestures << gz
      gz
    end

    # 状態リセット (シーン遷移・メニュー開閉時など)
    def reset
      @mouse_touch = nil
      @work_touches.clear
      i = 0
      while i < @sticks.length
        @sticks[i].reset
        i += 1
      end
      i = 0
      while i < @buttons.length
        @buttons[i].reset
        i += 1
      end
    end

    def consume_mouse_touch!
      @mouse_touch.consume! if @mouse_touch
    end

    # 毎フレーム更新 (Input.__update_virtual_pad から自動呼び出し)
    def update
      return unless @enabled
      return unless Input.using_touch? || @mouse_input

      win_w = Window.width.to_f
      win_h = Window.height.to_f

      touches = collect_active_touches

      # 1. スティックの更新と移動・照準ベクトル合成
      move_vx = 0.0
      move_vy = 0.0
      move_moving = false

      aim_vx = 0.0
      aim_vy = 0.0
      aim_moving = false

      i = 0
      while i < @sticks.length
        st = @sticks[i]
        st.update(touches, win_w, win_h)
        if st.moving?
          if st.target == :aim || st.target == :right
            aim_vx += st.vx
            aim_vy += st.vy
            aim_moving = true
          else
            move_vx += st.vx
            move_vy += st.vy
            move_moving = true
          end
        end
        i += 1
      end

      if move_moving
        mag = Math.hypot(move_vx, move_vy)
        if mag > 1.0
          move_vx /= mag
          move_vy /= mag
        end
        Input.inject_vector(move_vx, move_vy)
      end

      if aim_moving
        mag = Math.hypot(aim_vx, aim_vy)
        if mag > 1.0
          aim_vx /= mag
          aim_vy /= mag
        end
        Input.inject_right_vector(aim_vx, aim_vy)
      end

      # 2. ボタングループの更新 (ワイド判定 & 最寄りボタン吸着)
      update_buttons(touches, win_w, win_h)

      # 3. ジェスチャー領域の更新 (リリース時のタップ・フリック判定)
      i = 0
      while i < @gestures.length
        @gestures[i].update(touches, @sticks, (move_moving || aim_moving), win_w, win_h)
        i += 1
      end
    end

    # 描画 (Window.without_camera でスクリーン空間へ描画)
    def draw
      return unless @enabled && @visible
      return unless Input.using_touch? || @mouse_input
      Window.without_camera { draw_elements }
    end

    private

    def draw_elements
      win_w = Window.width.to_f
      win_h = Window.height.to_f

      i = 0
      while i < @sticks.length
        @sticks[i].draw(@z)
        i += 1
      end

      i = 0
      while i < @buttons.length
        @buttons[i].draw(win_w, win_h, @z)
        i += 1
      end

      i = 0
      while i < @gestures.length
        @gestures[i].draw(win_w, win_h, @z)
        i += 1
      end
    end

    def collect_active_touches
      if Input.using_touch?
        @mouse_touch = nil
        return Input.touches
      end

      @work_touches.clear
      if @mouse_input && !ImGui.mouse_captured? && !UI.mouse_captured?
        if @mouse_touch && (@mouse_touch.released? || @mouse_touch.cancelled?)
          @mouse_touch = nil
        end

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f

        if Input.mouse_push?(:left)
          @mouse_touch = Touch.new(-1, mx, my)
        elsif @mouse_touch
          @mouse_touch.__step
          if Input.mouse_pressed?(:left)
            @mouse_touch.__update(mx, my)
          else
            @mouse_touch.__finish(true, mx, my)
          end
        end

        @work_touches << @mouse_touch if @mouse_touch
      else
        @mouse_touch = nil
      end

      @work_touches
    end

    def stick_claimed?(t)
      i = 0
      while i < @sticks.length
        return true if @sticks[i].touch == t
        i += 1
      end
      false
    end

    def update_buttons(touches, win_w, win_h)
      btn_len = @buttons.length
      return if btn_len == 0

      i = 0
      while i < btn_len
        @buttons[i].pressed = false
        i += 1
      end

      ti = 0
      t_len = touches.length
      while ti < t_len
        t = touches[ti]
        if t.active? && !t.consumed? && !stick_claimed?(t)
          best_btn = nil
          best_dist = 999999.0

          bi = 0
          while bi < btn_len
            btn = @buttons[bi]
            bx = btn.screen_x(win_w)
            by = btn.screen_y(win_h)
            dist = Math.hypot(t.x - bx, t.y - by)
            if dist <= btn.hit_radius && dist < best_dist
              best_dist = dist
              best_btn = btn
            end
            bi += 1
          end

          best_btn.pressed = true if best_btn
        end
        ti += 1
      end

      i = 0
      while i < btn_len
        btn = @buttons[i]
        Input.inject_action(btn.action, 1.0) if btn.pressed
        i += 1
      end
    end
  end
end

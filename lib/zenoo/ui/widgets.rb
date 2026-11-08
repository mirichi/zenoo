# frozen_string_literal: true

module Zenoo
  module UI
    # ==========================================================================
    # Label (テキストラベルウィジェット)
    # ==========================================================================
    class Label < Widget
      attr_reader :text, :size
      attr_accessor :text_color, :align, :valign, :font, :outline_width, :outline_color

      def initialize(text = "", x = 0.0, y = 0.0, width: nil, height: nil,
                     size: nil, color: nil, align: :left, valign: :middle,
                     font: nil, outline_width: 0.0, outline_color: :black,
                     interactive: false, **opts)
        @text          = text.to_s
        @size          = size ? size.to_i : nil
        @text_color    = color
        @align         = align
        @valign        = valign
        @font          = font
        @outline_width = outline_width.to_f
        @outline_color = outline_color
        @auto_w        = width.nil?
        @auto_h        = height.nil?

        f_size = @size || 15
        f_font = @font || Font.default
        w = width ? width.to_f : (f_font ? f_font.text_width(@text, f_size) : 100.0)
        h = height ? height.to_f : (f_size.to_f + 4.0)

        super(x, y, width: w, height: h, interactive: interactive, **opts)
      end

      def text=(val)
        s = val.to_s
        return if @text == s
        @text = s
        if @auto_w
          f_font = @font || theme.font || Font.default
          f_size = @size || theme.font_size || 15
          self.width = f_font.text_width(@text, f_size) if f_font
        end
      end

      def size=(val)
        @size = val ? val.to_i : nil
        if @auto_h
          f_size = @size || theme.font_size || 15
          self.height = f_size.to_f + 4.0
        end
      end

      def draw_self
        return if @text.empty?
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height

        f_font = @font || th.font || Font.default
        f_size = ((@size || th.font_size || 15).to_f * world_scale_y).to_i
        f_size = 8 if f_size < 8
        col = @text_color || (@enabled ? th.text_color : th.text_disabled)

        tx = case @align
             when :center then rx + rw * 0.5
             when :right  then rx + rw
             else rx
             end

        ty = case @valign
             when :middle, :center then ry + rh * 0.5
             when :bottom          then ry + rh
             else ry
             end

        Zenoo::Window.draw_text(
          tx, ty, @text,
          font: f_font, size: f_size, color: col,
          align: @align, valign: @valign,
          outline_width: @outline_width, outline_color: @outline_color,
          camera: @camera, z: @z
        )
      end
    end

    # ==========================================================================
    # Divider (水平区切り線ウィジェット)
    # ==========================================================================
    class Divider < Widget
      attr_accessor :line_color

      def initialize(x = 0.0, y = 0.0, width: 200.0, height: 10.0, color: nil, **opts)
        @line_color = color
        super(x, y, width: width, height: height, interactive: false, **opts)
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top + screen_height * 0.5
        rw = screen_width
        b_cfg = th.border_normal
        col = @line_color || (b_cfg ? b_cfg[1] : Color.new(75, 85, 105, 180))
        Zenoo::Window.draw_line(rx, ry, rx + rw, ry, color: col, width: 1.0, camera: @camera, z: @z)
      end
    end

    # ==========================================================================
    # Spacer (空白調整用ウィジェット)
    # ==========================================================================
    class Spacer < Widget
      def initialize(size = 8.0, flex: nil, **opts)
        s = size.to_f
        super(0.0, 0.0, width: s, height: s, flex: flex, interactive: false, **opts)
      end

      def draw_self
      end
    end

    # ==========================================================================
    # ImageBox (画像・アイコン・サブ画像・レンダーターゲット表示ウィジェット)
    # - fit: :contain (アスペクト比維持), :stretch (枠いっぱい), :center (等倍中央)
    # ==========================================================================
    class ImageBox < Widget
      attr_accessor :fit, :bg_color, :border_color, :border_width, :radius

      def initialize(image = nil, x = 0.0, y = 0.0, width: nil, height: nil,
                     fit: :contain, bg_color: nil, border_color: nil, border_width: 0.0, radius: 4.0,
                     interactive: false, **opts)
        w = width ? width.to_f : (image ? image.width.to_f : 64.0)
        h = height ? height.to_f : (image ? image.height.to_f : 64.0)
        @fit          = fit
        @bg_color     = bg_color
        @border_color = border_color
        @border_width = border_width.to_f
        @radius       = radius.to_f

        super(x, y, width: w, height: h, interactive: interactive, **opts)
        @image = image
      end

      def draw_self
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height

        if @bg_color || (@border_color && @border_width > 0.0)
          Zenoo::Window.draw_rect(
            rx, ry, rw, rh,
            radius: @radius,
            color: @bg_color,
            border_color: @border_color,
            border_width: @border_width,
            camera: @camera,
            z: @z
          )
        end

        return unless (img = @image)
        iw = img.width.to_f
        ih = img.height.to_f
        return if iw <= 0.0 || ih <= 0.0

        case @fit
        when :stretch
          dw = rw
          dh = rh
          dx = rx
          dy = ry
        when :center
          dw = iw * world_scale_x
          dh = ih * world_scale_y
          dx = rx + (rw - dw) * 0.5
          dy = ry + (rh - dh) * 0.5
        else # :contain
          scale = [rw / iw, rh / ih].min
          dw = iw * scale
          dh = ih * scale
          dx = rx + (rw - dw) * 0.5
          dy = ry + (rh - dh) * 0.5
        end

        Zenoo::Window.draw(
          dx, dy, img,
          width: dw, height: dh,
          anchor: :top_left,
          color: @color || :white,
          alpha: @alpha,
          blend: @blend,
          shader: @shader,
          uniforms: @uniforms,
          camera: @camera,
          z: @z
        )
      end
    end

    # ==========================================================================
    # Button (プッシュボタン / トグル対応ボタン / アイコン付きボタン)
    # ==========================================================================
    class Button < Widget
      attr_accessor :label, :icon, :active, :bg_color, :hover_color, :active_color, :text_color, :radius, :font_size

      def initialize(label = "Button", x = 0.0, y = 0.0, width: 140.0, height: 38.0,
                     icon: nil, active: false,
                     bg_color: nil, hover_color: nil, active_color: nil, text_color: nil,
                     radius: nil, font_size: nil, **opts, &block)
        @label        = label.to_s
        @icon         = icon
        @active       = active
        @bg_color     = bg_color
        @hover_color  = hover_color
        @active_color = active_color
        @text_color   = text_color
        @radius       = radius
        @font_size    = font_size

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_click_proc = block if block
      end

      def hover_cursor_shape
        :hand
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height

        st = (@active || @clicked) ? :active : visual_state
        bg = case st
             when :active   then @active_color || th.bg_active
             when :hover    then @hover_color  || th.bg_hover
             when :disabled then Color.new(35, 38, 45, 180)
             else                @bg_color     || th.bg_normal
             end

        b_cfg = case st
                when :active then th.border_active
                when :hover  then th.border_hover
                else              th.border_normal
                end
        bw = b_cfg ? b_cfg[0].to_f : 1.0
        bc = b_cfg ? b_cfg[1] : th.accent_color
        rad = (@radius ? @radius.to_f : (th.corner_radius || 6.0).to_f) * world_scale_y

        s_cfg = (st == :hover) ? th.shadow_hover : th.shadow_normal
        sblur = s_cfg ? s_cfg[0].to_f : 0.0
        scol  = s_cfg ? s_cfg[1] : nil

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: rad,
          color: bg,
          border_width: bw,
          border_color: bc,
          shadow_blur: sblur,
          shadow_color: scol,
          angle: world_angle,
          camera: @camera,
          z: @z
        )

        # アイコン + テキストの描画
        f_font = th.font || Font.default
        f_size = ((@font_size || th.font_size || 15).to_f * world_scale_y).to_i
        f_size = 8 if f_size < 8

        press_offset = (@pressed && @enabled) ? 1.0 : 0.0
        tcol = @enabled ? (@text_color || th.text_color) : th.text_disabled

        if @icon && @label.empty?
          isz = [rw, rh].min * 0.65
          ix = rx + (rw - isz) * 0.5
          iy = ry + (rh - isz) * 0.5 + press_offset
          Zenoo::Window.draw(ix, iy, @icon, width: isz, height: isz, anchor: :top_left, camera: @camera, z: @z)
        elsif @icon && !@label.empty?
          isz = [rh * 0.6, 24.0 * world_scale_y].min
          tw = f_font.text_width(@label, f_size)
          tot_w = isz + 6.0 + tw
          start_x = rx + (rw - tot_w) * 0.5
          iy = ry + (rh - isz) * 0.5 + press_offset
          Zenoo::Window.draw(start_x, iy, @icon, width: isz, height: isz, anchor: :top_left, camera: @camera, z: @z)
          Zenoo::Window.draw_text(
            start_x + isz + 6.0, ry + rh * 0.5 + press_offset,
            @label,
            font: f_font, size: f_size, color: tcol,
            align: :left, valign: :middle,
            camera: @camera, z: @z
          )
        elsif !@label.empty?
          tw = f_font.text_width(@label, f_size)
          avail_w = rw - 16.0
          if avail_w > 8.0 && tw > avail_w
            f_size = [(f_size.to_f * (avail_w / tw)).to_i, 8].max
          end
          Zenoo::Window.draw_text(
            rx + rw * 0.5, ry + rh * 0.5 + press_offset,
            @label,
            font: f_font, size: f_size, color: tcol,
            align: :center, valign: :middle,
            camera: @camera, z: @z
          )
        end
      end
    end

    # ==========================================================================
    # Checkbox (トグルチェックボックス)
    # ==========================================================================
    class Checkbox < Widget
      attr_accessor :label, :checked

      def initialize(label = "", checked = false, x = 0.0, y = 0.0, width: nil, height: 28.0, **opts, &block)
        @label   = label.to_s
        @checked = !!checked
        f_font   = Font.default
        w = width ? width.to_f : (28.0 + (f_font ? f_font.text_width(@label, 15) : 100.0) + 10.0)

        super(x, y, width: w, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def checked?
        @checked
      end

      def hover_cursor_shape
        :hand
      end

      def trigger_click!
        @checked = !@checked
        super
        trigger_change!(@checked)
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rh = screen_height
        box_size = 20.0 * world_scale_y
        box_y = ry + (rh - box_size) * 0.5

        b_cfg = @hovered ? th.border_hover : th.border_normal
        bw = b_cfg ? b_cfg[0].to_f : 1.0
        bc = b_cfg ? b_cfg[1] : th.accent_color
        bg = @hovered ? th.bg_hover : th.bg_normal

        Zenoo::Window.draw_rect(
          rx, box_y, box_size, box_size,
          radius: (th.corner_radius || 4.0) * 0.8,
          color: bg,
          border_width: bw,
          border_color: bc,
          camera: @camera,
          z: @z
        )

        if @checked
          pad = 4.0 * world_scale_y
          Zenoo::Window.draw_rect(
            rx + pad, box_y + pad,
            box_size - pad * 2.0, box_size - pad * 2.0,
            radius: 2.0,
            color: th.accent_color,
            camera: @camera,
            z: @z
          )
        end

        unless @label.empty?
          f_font = th.font || Font.default
          f_size = ((th.font_size || 15).to_f * world_scale_y).to_i
          tcol = @hovered ? Color::WHITE : (@enabled ? th.text_color : th.text_disabled)
          Zenoo::Window.draw_text(
            rx + box_size + 10.0, ry + rh * 0.5,
            @label,
            font: f_font, size: f_size, color: tcol,
            align: :left, valign: :middle,
            camera: @camera, z: @z
          )
        end
      end
    end

    # ==========================================================================
    # RadioButton (ラジオボタン)
    # ==========================================================================
    class RadioButton < Widget
      attr_accessor :label, :checked, :group, :value

      def initialize(label = "", checked = false, x = 0.0, y = 0.0, width: nil, height: 28.0,
                     group: nil, value: nil, **opts, &block)
        @label   = label.to_s
        @checked = !!checked
        @group   = group
        @value   = value
        f_font   = Font.default
        w = width ? width.to_f : (28.0 + (f_font ? f_font.text_width(@label, 15) : 100.0) + 10.0)

        super(x, y, width: w, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def checked?
        @checked
      end

      def hover_cursor_shape
        :hand
      end

      def trigger_click!
        if !@checked
          # 同じ親またはグループの RadioButton を OFF にする
          if @parent && (ch = @parent.children)
            i = 0
            len = ch.length
            while i < len
              sib = ch[i]
              if sib.is_a?(RadioButton) && !sib.equal?(self) && sib.group == @group
                sib.checked = false
              end
              i += 1
            end
          end
          @checked = true
          trigger_change!(@value.nil? ? true : @value)
        end
        super
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rh = screen_height
        r  = 9.0 * world_scale_y
        cx = rx + r + 2.0
        cy = ry + rh * 0.5

        b_cfg = @hovered ? th.border_hover : th.border_normal
        bw = b_cfg ? b_cfg[0].to_f : 1.0
        bc = b_cfg ? b_cfg[1] : th.accent_color
        bg = @hovered ? th.bg_hover : th.bg_normal

        Zenoo::Window.draw_circle(
          cx, cy, r,
          color: bg,
          border_width: bw,
          border_color: bc,
          camera: @camera,
          z: @z
        )

        if @checked
          Zenoo::Window.draw_circle(cx, cy, r * 0.5, color: th.accent_color, camera: @camera, z: @z)
        end

        unless @label.empty?
          f_font = th.font || Font.default
          f_size = ((th.font_size || 15).to_f * world_scale_y).to_i
          tcol = @hovered ? Color::WHITE : (@enabled ? th.text_color : th.text_disabled)
          Zenoo::Window.draw_text(
            rx + r * 2.0 + 10.0, cy,
            @label,
            font: f_font, size: f_size, color: tcol,
            align: :left, valign: :middle,
            camera: @camera, z: @z
          )
        end
      end
    end

    # ==========================================================================
    # ProgressBar (HPバー・EXPゲージ・ローディングバー)
    # ==========================================================================
    class ProgressBar < Widget
      attr_accessor :value, :min, :max, :label, :fill_color, :bg_color, :show_percentage

      def initialize(value = 0.5, min = 0.0, max = 1.0, x = 0.0, y = 0.0, width: 200.0, height: 22.0,
                     label: nil, fill_color: nil, bg_color: nil, show_percentage: false, **opts)
        @value           = value.to_f
        @min             = min.to_f
        @max             = max.to_f
        @label           = label
        @fill_color      = fill_color
        @bg_color        = bg_color
        @show_percentage = show_percentage

        super(x, y, width: width, height: height, interactive: false, **opts)
      end

      def ratio
        range = @max - @min
        return 0.0 if range <= 0.00001
        ((@value - @min) / range).clamp(0.0, 1.0)
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        rad = [rh * 0.35, (th.corner_radius || 6.0)].min

        tb = th.track_border || th.border_normal
        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: rad,
          color: @bg_color || th.track_bg || th.bg_normal,
          border_width: tb ? tb[0].to_f : 1.0,
          border_color: tb ? tb[1] : nil,
          camera: @camera,
          z: @z
        )

        r = ratio
        fw = (rw - 2.0) * r
        if fw > 1.0
          Zenoo::Window.draw_rect(
            rx + 1.0, ry + 1.0, fw, rh - 2.0,
            radius: [rad - 1.0, 1.0].max,
            color: @fill_color || th.accent_color,
            camera: @camera,
            z: @z
          )
        end

        txt = if @label
                @label.to_s
              elsif @show_percentage
                "#{(r * 100.0).round}%"
              else
                nil
              end

        if txt && !txt.empty?
          f_font = th.font || Font.default
          f_size = [((rh * 0.62)).to_i, 10].max
          Zenoo::Window.draw_text(
            rx + rw * 0.5, ry + rh * 0.5,
            txt,
            font: f_font, size: f_size, color: th.text_color,
            align: :center, valign: :middle,
            outline_width: 1.0, outline_color: Color.new(0, 0, 0, 180),
            camera: @camera, z: @z
          )
        end
      end
    end

    # ==========================================================================
    # Slider (ドラッグ・ホイール操作対応スライダー)
    # ==========================================================================
    class Slider < Widget
      attr_accessor :label, :min, :max, :step, :unit, :format
      attr_reader :value

      def initialize(label = "", value = 0.0, min = 0.0, max = 100.0,
                     x = 0.0, y = 0.0, width: 220.0, height: 42.0,
                     step: nil, unit: "", format: nil, **opts, &block)
        @label  = label.to_s
        @min    = min.to_f
        @max    = max.to_f
        @step   = step ? step.to_f : nil
        @unit   = unit.to_s
        @format = format
        @value  = clamp_and_step(value.to_f)

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def value=(val)
        nv = clamp_and_step(val.to_f)
        return if (@value - nv).abs < 0.00001
        @value = nv
      end

      def hover_cursor_shape
        :hand
      end

      def on_pointer_down(mx, _my)
        super
        update_value_from_mouse(mx)
      end

      def on_pointer_drag(mx, _my)
        UI.set_mouse_cursor(:hand)
        update_value_from_mouse(mx)
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height

        range = @max - @min
        range = 1.0 if range <= 0.00001
        ratio = ((@value - @min) / range).clamp(0.0, 1.0)

        f_font = th.font || Font.default
        f_size = ((th.font_size || 15).to_f * world_scale_y).to_i
        f_size = 8 if f_size < 8

        has_label = !@label.empty?
        is_dis = !@enabled
        lbl_col = is_dis ? th.text_disabled : th.text_color
        num_col = is_dis ? th.text_disabled : th.accent_color

        if has_label
          Zenoo::Window.draw_text(rx, ry, @label, font: f_font, size: f_size, color: lbl_col, camera: @camera, z: @z)

          val_str = format_value(@value)
          val_w = f_font.text_width(val_str, f_size)
          Zenoo::Window.draw_text(rx + rw - val_w, ry, val_str, font: f_font, size: f_size, color: num_col, camera: @camera, z: @z)

          track_y = ry + f_size.to_f + 8.0 * world_scale_y
          track_h = 8.0 * world_scale_y
        else
          track_h = 8.0 * world_scale_y
          track_y = ry + (rh - track_h) * 0.5
        end

        knob_size = 18.0 * world_scale_y
        knob_r    = knob_size * 0.5
        usable_w  = [rw - knob_size, 0.0].max
        track_x   = rx + knob_r
        track_w   = usable_w

        tb = th.track_border
        Zenoo::Window.draw_rect(
          track_x, track_y, track_w, track_h,
          radius: track_h * 0.5,
          color: th.track_bg,
          border_width: tb ? tb[0].to_f : 0.0,
          border_color: tb ? tb[1] : nil,
          camera: @camera,
          z: @z
        )

        fill_w = track_w * ratio
        if fill_w > 0.0
          fill_col = if is_dis
                       Color.new(70, 75, 85, 140)
                     elsif @hovered || @pressed
                       th.accent_hover
                     else
                       th.accent_color
                     end
          Zenoo::Window.draw_rect(
            track_x, track_y, fill_w, track_h,
            radius: track_h * 0.5,
            color: fill_col,
            camera: @camera,
            z: @z
          )
        end

        knob_x = rx + usable_w * ratio
        knob_y = track_y + (track_h - knob_size) * 0.5
        k_col  = is_dis ? Color.new(80, 85, 95) : (th.text_color || Color::WHITE)
        kb_col = is_dis ? Color.new(65, 70, 80) : (@pressed ? th.accent_hover : th.accent_color)

        Zenoo::Window.draw_rect(
          knob_x, knob_y, knob_size, knob_size,
          radius: knob_r,
          color: k_col,
          border_width: 2.0,
          border_color: kb_col,
          camera: @camera,
          z: @z
        )
      end

      private

      def clamp_and_step(val)
        v = val
        if @step && @step > 0.0
          v = ((v - @min) / @step).round * @step + @min
        end
        [[v, @min].max, @max].min
      end

      def update_value_from_mouse(mx)
        rx = screen_left
        rw = screen_width
        knob_r = 9.0 * world_scale_x
        usable_w = [rw - knob_r * 2.0, 1.0].max
        ratio = ((mx - (rx + knob_r)) / usable_w).clamp(0.0, 1.0)
        new_val = clamp_and_step(@min + ratio * (@max - @min))
        if (new_val - @value).abs > 0.00001
          @value = new_val
          trigger_change!(@value)
        end
      end

      def format_value(v)
        s = if @format
              sprintf(@format, v)
            elsif (v % 1.0).abs < 0.0001 && (@min % 1.0).abs < 0.0001 && (@max % 1.0).abs < 0.0001 && (@step.nil? || (@step % 1.0).abs < 0.0001)
              v.round.to_s
            else
              sprintf("%.2f", v).sub(/\.?0+$/, '')
            end
        @unit.empty? ? s : "#{s}#{@unit}"
      end
    end

    # ==========================================================================
    # Spinner ([-] [数値] [+] ステップ増減ウィジェット)
    # ==========================================================================
    class Spinner < Widget
      attr_accessor :label, :min, :max, :step, :format
      attr_reader :value

      def initialize(label = "", value = 0, x = 0.0, y = 0.0,
                     min: nil, max: nil, step: 1,
                     width: 220.0, height: 34.0,
                     format: nil, **opts, &block)
        @label      = label.to_s
        @min        = min
        @max        = max
        @step       = step
        @format     = format
        @value      = clamp_val(value)
        @hover_part = nil # :minus, :plus

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def value=(val)
        @value = clamp_val(val)
      end

      def set_hovered_state(val)
        @hovered = val
        @hover_part = nil
        return unless val && @enabled && @interactive

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        @hover_part = hit_part(mx, my)
        UI.set_mouse_cursor(@hover_part ? :hand : :arrow)
      end

      def on_pointer_down(mx, my)
        super
        part = hit_part(mx, my)
        if part == :minus
          change_by(-@step)
        elsif part == :plus
          change_by(@step)
        end
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        btn_w = 32.0 * world_scale_x
        f_font = th.font || Font.default
        f_size = ((th.font_size || 14).to_f * world_scale_y).to_i

        has_label = !@label.empty?
        label_w = has_label ? (f_font.text_width(@label, f_size) + 12.0) : 0.0

        if has_label
          Zenoo::Window.draw_text(
            rx, ry + rh * 0.5, @label,
            font: f_font, size: f_size, color: th.text_color,
            align: :left, valign: :middle, camera: @camera, z: @z
          )
        end

        ctrl_x = rx + label_w
        ctrl_w = [rw - label_w, btn_w * 2.0 + 30.0].max
        minus_x = ctrl_x
        plus_x  = ctrl_x + ctrl_w - btn_w
        val_x   = ctrl_x + btn_w + 2.0
        val_w   = ctrl_w - btn_w * 2.0 - 4.0
        rad     = [(th.corner_radius || 4.0) - 1.0, 2.0].max

        # 中央値ボックス
        tb = th.track_border || th.border_normal
        Zenoo::Window.draw_rect(
          val_x, ry, val_w, rh,
          radius: rad,
          color: th.track_bg || th.bg_normal,
          border_width: tb ? tb[0].to_f : 1.0,
          border_color: tb ? tb[1] : nil,
          camera: @camera, z: @z
        )

        fmt = @format || (@value.is_a?(Float) ? "%.2f" : "%d")
        val_str = sprintf(fmt, @value)
        Zenoo::Window.draw_text(
          val_x + val_w * 0.5, ry + rh * 0.5, val_str,
          font: f_font, size: f_size, color: th.text_color,
          align: :center, valign: :middle, camera: @camera, z: @z
        )

        # [-] ボタン
        m_hov = (@hovered && @hover_part == :minus)
        mb = m_hov ? th.border_hover : th.border_normal
        Zenoo::Window.draw_rect(
          minus_x, ry, btn_w, rh,
          radius: rad,
          color: m_hov ? th.bg_hover : th.bg_normal,
          border_width: mb ? mb[0].to_f : 1.0,
          border_color: mb ? mb[1] : nil,
          camera: @camera, z: @z
        )
        m_col = m_hov ? Color::WHITE : th.text_color
        Zenoo::Window.draw_rect(minus_x + 10.0, ry + rh * 0.5 - 1.0, btn_w - 20.0, 2.0, color: m_col, camera: @camera, z: @z)

        # [+] ボタン
        p_hov = (@hovered && @hover_part == :plus)
        pb = p_hov ? th.border_hover : th.border_normal
        Zenoo::Window.draw_rect(
          plus_x, ry, btn_w, rh,
          radius: rad,
          color: p_hov ? th.bg_hover : th.bg_normal,
          border_width: pb ? pb[0].to_f : 1.0,
          border_color: pb ? pb[1] : nil,
          camera: @camera, z: @z
        )
        p_col = p_hov ? Color::WHITE : th.text_color
        Zenoo::Window.draw_rect(plus_x + 10.0, ry + rh * 0.5 - 1.0, btn_w - 20.0, 2.0, color: p_col, camera: @camera, z: @z)
        Zenoo::Window.draw_rect(plus_x + btn_w * 0.5 - 1.0, ry + 10.0, 2.0, rh - 20.0, color: p_col, camera: @camera, z: @z)
      end

      private

      def clamp_val(v)
        res = (@step.is_a?(Float) || v.is_a?(Float)) ? v.to_f : v.to_i
        res = [res, @min].max if @min
        res = [res, @max].min if @max
        res
      end

      def change_by(delta)
        old = @value
        @value = clamp_val(@value + delta)
        if @value != old
          trigger_change!(@value)
        end
      end

      def hit_part(px, py)
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        return nil if py < ry || py > (ry + rh)

        th = theme
        f_font = th.font || Font.default
        f_size = ((th.font_size || 14).to_f * world_scale_y).to_i
        label_w = @label.empty? ? 0.0 : (f_font.text_width(@label, f_size) + 12.0)
        btn_w = 32.0 * world_scale_x
        ctrl_x = rx + label_w
        ctrl_w = [rw - label_w, btn_w * 2.0 + 30.0].max
        minus_x = ctrl_x
        plus_x  = ctrl_x + ctrl_w - btn_w

        if px >= minus_x && px <= (minus_x + btn_w)
          :minus
        elsif px >= plus_x && px <= (plus_x + btn_w)
          :plus
        else
          nil
        end
      end
    end

    # ==========================================================================
    # Tabs (タブバー切り替えウィジェット)
    # ==========================================================================
    class Tabs < Widget
      attr_accessor :items
      attr_reader :selected_index

      def initialize(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 300.0, height: 36.0, **opts, &block)
        @items          = items.map(&:to_s)
        @selected_index = selected_index.to_i
        @hover_index    = nil

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def selected_index=(idx)
        @selected_index = idx.to_i.clamp(0, [@items.length - 1, 0].max)
      end

      def selected_item
        @items[@selected_index]
      end

      def set_hovered_state(val)
        @hovered = val
        @hover_index = nil
        return unless val && @enabled && @interactive && !@items.empty?

        mx = Input.mouse_x.to_f
        tab_w = screen_width / @items.length.to_f
        idx = ((mx - screen_left) / tab_w).to_i
        if idx >= 0 && idx < @items.length
          @hover_index = idx
          UI.set_mouse_cursor(:hand)
        end
      end

      def on_pointer_down(mx, _my)
        super
        return if @items.empty?
        tab_w = screen_width / @items.length.to_f
        idx = ((mx - screen_left) / tab_w).to_i
        if idx >= 0 && idx < @items.length && idx != @selected_index
          @selected_index = idx
          trigger_change!(@selected_index)
        end
      end

      def draw_self
        return if @items.empty?
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        count = @items.length
        tab_w = rw / count.to_f
        f_font = th.font || Font.default
        f_size = ((th.font_size || 15).to_f * world_scale_y).to_i - 1
        f_size = 10 if f_size < 10
        rad = th.corner_radius || 6.0
        tb  = th.track_border || th.border_normal

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: rad,
          color: th.track_bg || th.bg_normal,
          border_width: tb ? tb[0].to_f : 1.0,
          border_color: tb ? tb[1] : nil,
          camera: @camera, z: @z
        )

        i = 0
        while i < count
          lbl = @items[i]
          tx = rx + i.to_f * tab_w
          is_cur = (i == @selected_index)
          is_hov = (@hovered && i == @hover_index)
          in_rad = [rad - 1.0, 2.0].max

          if is_cur
            Zenoo::Window.draw_rect(tx + 2.0, ry + 2.0, tab_w - 4.0, rh - 4.0, radius: in_rad, color: th.bg_active, camera: @camera, z: @z)
            Zenoo::Window.draw_rect(tx + 8.0, ry + rh - 3.5, tab_w - 16.0, 2.5, radius: 1.0, color: th.accent_color, camera: @camera, z: @z)
          elsif is_hov
            Zenoo::Window.draw_rect(tx + 2.0, ry + 2.0, tab_w - 4.0, rh - 4.0, radius: in_rad, color: th.bg_hover, camera: @camera, z: @z)
          end

          tcol = is_cur ? Color::WHITE : (is_hov ? th.text_color : Color.new(190, 198, 212))
          Zenoo::Window.draw_text(
            tx + tab_w * 0.5, ry + rh * 0.5 - 1.0,
            lbl,
            font: f_font, size: f_size, color: tcol,
            align: :center, valign: :middle,
            camera: @camera, z: @z
          )
          i += 1
        end
      end
    end

    # ==========================================================================
    # TextBox (キャレット移動・IME位置同期・クリップボード対応テキスト入力)
    # ==========================================================================
    class TextBox < Widget
      attr_accessor :placeholder
      attr_reader :text, :cursor_pos

      def initialize(text = "", x = 0.0, y = 0.0, width: 220.0, height: 38.0,
                     placeholder: "", **opts, &block)
        @text        = text.to_s.dup
        @placeholder = placeholder.to_s
        @cursor_pos  = @text.length

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def text=(val)
        @text = val.to_s.dup
        @cursor_pos = @text.length if @cursor_pos > @text.length
      end

      def hover_cursor_shape
        :ibeam
      end

      def on_pointer_down(mx, _my)
        super
        focus!
        click_x = mx - (screen_left + 10.0)
        @cursor_pos = caret_index_from_click(@text, click_x)
        UI.blink_time = 0.0
      end

      def update_self
        return unless focused? && @enabled

        old_text = @text.dup
        th = theme
        rx = screen_left
        ry = screen_top
        rh = screen_height

        f_font = th.font || Font.default
        f_size = ((th.font_size || 15).to_f * world_scale_y).to_i
        sub_str = @text[0...@cursor_pos] || ""
        caret_offset = f_font.text_width(sub_str, f_size)
        Input.set_ime_position(rx + 10.0 + caret_offset, ry + rh + 2.0)

        ctrl_down = Input.key_pressed?(:left_control) || Input.key_pressed?(:right_control) ||
                    Input.key_pressed?(:left_super) || Input.key_pressed?(:right_super)

        reset_blink = false
        if ctrl_down && Input.key_push?(:v)
          clip = Input.clipboard
          if clip && !clip.empty?
            @text.insert(@cursor_pos, clip)
            @cursor_pos += clip.length
            reset_blink = true
          end
        elsif ctrl_down && Input.key_push?(:c)
          Input.clipboard = @text
        elsif ctrl_down && Input.key_push?(:x)
          Input.clipboard = @text
          @text = String.new
          @cursor_pos = 0
          reset_blink = true
        elsif ctrl_down && Input.key_push?(:a)
          @cursor_pos = @text.length
          reset_blink = true
        elsif Input.key_repeat?(:backspace)
          if @cursor_pos > 0
            @text.slice!(@cursor_pos - 1)
            @cursor_pos -= 1
            reset_blink = true
          end
        elsif Input.key_repeat?(:delete)
          if @cursor_pos < @text.length
            @text.slice!(@cursor_pos)
            reset_blink = true
          end
        elsif Input.key_repeat?(:left)
          if @cursor_pos > 0
            @cursor_pos -= 1
            reset_blink = true
          end
        elsif Input.key_repeat?(:right)
          if @cursor_pos < @text.length
            @cursor_pos += 1
            reset_blink = true
          end
        elsif Input.key_push?(:home)
          @cursor_pos = 0
          reset_blink = true
        elsif Input.key_push?(:end)
          @cursor_pos = @text.length
          reset_blink = true
        elsif Input.key_push?(:enter) || Input.key_push?(:escape)
          blur!
        end

        unless ctrl_down
          chars = Input.input_chars
          i = 0
          len = chars.length
          while i < len
            ch = chars[i]
            if ch.ord >= 32 || ch == "\t"
              @text.insert(@cursor_pos, ch)
              @cursor_pos += ch.length
              reset_blink = true
            end
            i += 1
          end
        end

        UI.blink_time = 0.0 if reset_blink
        if @text != old_text
          trigger_change!(@text)
        end
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        is_foc = focused?

        bg = th.track_bg || th.bg_normal
        b_cfg = is_foc ? (th.border_active || [1.5, th.accent_color]) : (@hovered ? th.border_hover : th.border_normal)
        bw = b_cfg ? b_cfg[0].to_f : 1.0
        bc = b_cfg ? b_cfg[1] : th.accent_color

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: th.corner_radius || 6.0,
          color: bg,
          border_width: bw,
          border_color: bc,
          camera: @camera, z: @z
        )

        f_font = th.font || Font.default
        f_size = ((th.font_size || 15).to_f * world_scale_y).to_i
        pad_x  = 10.0
        text_y = ry + (rh - f_size.to_f) * 0.5

        sub_str = @text[0...@cursor_pos] || ""
        caret_ox = f_font.text_width(sub_str, f_size)
        avail_w  = [rw - pad_x * 2.0 - 4.0, 10.0].max
        scroll_x = caret_ox > avail_w ? (caret_ox - avail_w) : 0.0
        text_x   = rx + pad_x - scroll_x

        prev_ox, prev_oy = Zenoo::Window.push_clip_scope(rx + 4.0, ry + 2.0, [rw - 8.0, 0.0].max, [rh - 4.0, 0.0].max, local: false, z: @z)
        if @text.empty? && !is_foc && !@placeholder.empty?
          Zenoo::Window.draw_text(text_x, text_y, @placeholder, font: f_font, size: f_size, color: th.text_disabled, camera: @camera, z: @z)
        elsif !@text.empty?
          Zenoo::Window.draw_text(text_x, text_y, @text, font: f_font, size: f_size, color: th.text_color, camera: @camera, z: @z)
        end

        if is_foc && ((UI.blink_time % 1.0) < 0.5)
          caret_x = text_x + caret_ox
          Zenoo::Window.draw_rect(caret_x, text_y - 1.0, 2.0, f_size.to_f + 2.0, color: th.accent_color, camera: @camera, z: @z)
        end
        Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)
      end

      private

      def caret_index_from_click(str, click_x)
        th = theme
        f_font = th.font || Font.default
        f_size = ((th.font_size || 15).to_f * world_scale_y).to_i
        best_idx = str.length
        accum_w = 0.0
        idx = 0
        len = str.length
        while idx < len
          ch = str[idx]
          char_w = f_font.text_width(ch, f_size)
          if click_x < accum_w + char_w * 0.5
            best_idx = idx
            break
          end
          accum_w += char_w
          idx += 1
        end
        best_idx
      end
    end

    # ==========================================================================
    # Dropdown (ポップアップオーバーレイ対応コンボボックス)
    # ==========================================================================
    class Dropdown < Widget
      attr_accessor :label, :items
      attr_reader :selected_index, :open

      def initialize(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 200.0, height: 36.0,
                     label: "", **opts, &block)
        @items          = items.map(&:to_s)
        @selected_index = selected_index.to_i
        @label          = label.to_s
        @open           = false
        @hover_item_idx = nil

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def selected_index=(idx)
        @selected_index = idx.to_i.clamp(0, [@items.length - 1, 0].max)
      end

      def selected_item
        @items[@selected_index]
      end

      def hover_cursor_shape
        :hand
      end

      def on_pointer_down(_mx, _my)
        super
        if @open
          close_popup!
        else
          open_popup!
        end
      end

      def open_popup!
        @open = true
        UI.open_popup_widget = self
      end

      def close_popup!
        @open = false
        @hover_item_idx = nil
        UI.open_popup_widget = nil if UI.open_popup_widget.equal?(self)
      end

      # UI.end_frame および process_root_input から呼ばれる最前面ポップアップ入力処理
      def handle_popup_input(mx, my, m_push, _m_down, _m_rel, _wheel_y)
        px, py, pw, ph = popup_rect
        in_pop = mx >= px && mx <= (px + pw) && my >= py && my <= (py + ph)
        in_btn = hit_test_self?(mx, my)

        if in_pop
          UI.set_mouse_cursor(:hand)
          item_h = 28.0
          idx = ((my - (py + 3.0)) / item_h).to_i
          @hover_item_idx = (idx >= 0 && idx < @items.length) ? idx : nil
          if m_push && @hover_item_idx
            old = @selected_index
            @selected_index = @hover_item_idx
            close_popup!
            trigger_change!(@selected_index) if @selected_index != old
          end
          return true
        else
          @hover_item_idx = nil
          if m_push
            close_popup!
            # ボタン自身をクリックした場合はそのまま閉じて入力消費
            return true if in_btn
          end
          return false
        end
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        f_font = th.font || Font.default
        f_size = ((th.font_size || 14).to_f * world_scale_y).to_i

        b_cfg = (@hovered || @open) ? th.border_hover : th.border_normal
        bw = b_cfg ? b_cfg[0].to_f : 1.0
        bc = b_cfg ? b_cfg[1] : th.accent_color
        bg = (@hovered || @open) ? th.bg_hover : th.bg_normal

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: th.corner_radius || 6.0,
          color: bg,
          border_width: bw,
          border_color: bc,
          camera: @camera, z: @z
        )

        sel_str = (@items[@selected_index] || "").to_s
        Zenoo::Window.draw_text(
          rx + 12.0, ry + rh * 0.5,
          sel_str,
          font: f_font, size: f_size, color: th.text_color,
          align: :left, valign: :middle,
          camera: @camera, z: @z
        )

        # 下向き矢印 (▼)
        ax = rx + rw - 20.0
        ay = ry + rh * 0.5 - 2.0
        acol = (@hovered || @open) ? th.accent_color : Color.new(180, 185, 195)
        Zenoo::Window.draw_triangle(ax, ay, ax + 8.0, ay, ax + 4.0, ay + 5.0, color: acol, camera: @camera, z: @z)
      end

      def draw_popup_overlay
        return unless @open && !@items.empty?
        th = theme
        px, py, pw, ph = popup_rect
        pop_z = 900.0
        f_font = th.font || Font.default
        f_size = ((th.font_size || 14).to_f * world_scale_y).to_i
        rad = th.corner_radius || 6.0
        s_cfg = th.shadow_normal

        Zenoo::Window.draw_rect(
          px, py, pw, ph,
          radius: rad,
          color: th.win_bg || th.bg_normal,
          border_width: 1.5,
          border_color: th.accent_color,
          shadow_blur: s_cfg ? s_cfg[0].to_f : 8.0,
          shadow_color: s_cfg ? s_cfg[1] : nil,
          camera: @camera, z: pop_z
        )

        item_h = 28.0
        i = 0
        len = @items.length
        while i < len
          iy = py + 3.0 + i.to_f * item_h
          is_sel = (i == @selected_index)
          is_hov = (i == @hover_item_idx)
          if is_sel || is_hov
            Zenoo::Window.draw_rect(
              px + 3.0, iy, pw - 6.0, item_h,
              radius: [rad - 2.0, 2.0].max,
              color: is_sel ? th.bg_active : th.bg_hover,
              camera: @camera, z: pop_z + 1.0
            )
          end
          tcol = (is_sel || is_hov) ? Color::WHITE : th.text_color
          Zenoo::Window.draw_text(
            px + 12.0, iy + item_h * 0.5,
            @items[i],
            font: f_font, size: f_size, color: tcol,
            align: :left, valign: :middle,
            camera: @camera, z: pop_z + 2.0
          )
          i += 1
        end
      end

      private

      def popup_rect
        item_h = 28.0
        pop_h  = @items.length.to_f * item_h + 6.0
        [screen_left, screen_top + screen_height + 2.0, screen_width, pop_h]
      end
    end

    # ==========================================================================
    # ListBox (スクロール対応アイテム選択リストウィジェット)
    # ==========================================================================
    class ListBox < Widget
      attr_accessor :items, :item_height
      attr_reader :selected_index, :scroll_y

      def initialize(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 240.0, height: 150.0,
                     item_height: 28.0, **opts, &block)
        @items          = items.map(&:to_s)
        @selected_index = selected_index.to_i
        @item_height    = item_height.to_f
        @scroll_y       = 0.0
        @hover_index    = nil
        @dragging_sb    = false

        super(x, y, width: width, height: height, interactive: true, **opts)
        @on_change_proc = block if block
      end

      def selected_index=(idx)
        @selected_index = idx.to_i.clamp(0, [@items.length - 1, 0].max)
      end

      def selected_item
        @items[@selected_index]
      end

      def total_content_height
        @items.length.to_f * @item_height + 8.0
      end

      def inner_height
        [height - 4.0, 1.0].max
      end

      def max_scroll
        [total_content_height - inner_height, 0.0].max
      end

      def needs_scroll?
        max_scroll > 0.5
      end

      def set_hovered_state(val)
        @hovered = val
        @hover_index = nil
        return unless val && @enabled && @interactive

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        if needs_scroll? && mx >= (screen_left + screen_width - 14.0)
          UI.set_mouse_cursor(:hand)
          return
        end

        idx = item_index_at(my)
        if idx
          @hover_index = idx
          UI.set_mouse_cursor(:hand)
        end
      end

      def on_mouse_wheel(wheel_y)
        return false unless needs_scroll?
        @scroll_y = (@scroll_y - wheel_y * @item_height).clamp(0.0, max_scroll)
        true
      end

      def on_pointer_down(mx, my)
        super
        if needs_scroll? && mx >= (screen_left + screen_width - 14.0)
          @dragging_sb = true
          update_sb_from_mouse(my)
          return
        end

        @dragging_sb = false
        idx = item_index_at(my)
        if idx && idx != @selected_index
          @selected_index = idx
          trigger_change!(@selected_index)
        end
      end

      def on_pointer_drag(_mx, my)
        if @dragging_sb
          UI.set_mouse_cursor(:hand)
          update_sb_from_mouse(my)
        end
      end

      def on_pointer_up(mx, my, inside)
        @dragging_sb = false
        super
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        rad = th.corner_radius || 6.0
        tb  = th.track_border || th.border_normal

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: rad,
          color: th.track_bg || th.bg_normal,
          border_width: tb ? tb[0].to_f : 1.0,
          border_color: tb ? tb[1] : nil,
          camera: @camera, z: @z
        )

        sb_w = needs_scroll? ? 12.0 : 0.0
        content_w = [rw - sb_w - 4.0, 10.0].max
        in_h = [rh - 4.0, 1.0].max
        f_font = th.font || Font.default
        f_size = ((th.font_size || 14).to_f * world_scale_y).to_i

        prev_ox, prev_oy = Zenoo::Window.push_clip_scope(rx + 2.0, ry + 2.0, content_w, in_h, local: false, z: @z)
        i = 0
        len = @items.length
        while i < len
          iy = ry + 4.0 + i.to_f * @item_height - @scroll_y
          if (iy + @item_height) >= (ry + 2.0) && iy <= (ry + rh - 2.0)
            is_sel = (i == @selected_index)
            is_hov = (@hovered && i == @hover_index)
            if is_sel || is_hov
              Zenoo::Window.draw_rect(
                rx + 4.0, iy + 1.0, content_w - 4.0, @item_height - 2.0,
                radius: [rad - 2.0, 2.0].max,
                color: is_sel ? th.bg_active : th.bg_hover,
                camera: @camera, z: @z
              )
            end
            tcol = (is_sel || is_hov) ? Color::WHITE : th.text_color
            Zenoo::Window.draw_text(
              rx + 12.0, iy + @item_height * 0.5,
              @items[i],
              font: f_font, size: f_size, color: tcol,
              align: :left, valign: :middle,
              camera: @camera, z: @z
            )
          end
          i += 1
        end
        Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)

        if needs_scroll?
          sb_x = rx + rw - sb_w - 2.0
          sb_y = ry + 3.0
          sb_h = [rh - 6.0, 10.0].max
          Zenoo::Window.draw_rect(sb_x, sb_y, sb_w, sb_h, radius: sb_w * 0.5, color: Color.new(15, 18, 25, 180), camera: @camera, z: @z)

          tot = total_content_height
          thumb_h = [[(in_h / tot) * sb_h, 20.0].max, sb_h].min
          ratio = max_scroll > 0.0 ? (@scroll_y / max_scroll) : 0.0
          thumb_y = sb_y + ratio * (sb_h - thumb_h)
          t_col = @dragging_sb ? (th.accent_hover || th.accent_color) : th.accent_color
          Zenoo::Window.draw_rect(sb_x + 2.0, thumb_y, sb_w - 4.0, thumb_h, radius: (sb_w - 4.0) * 0.5, color: t_col, camera: @camera, z: @z)
        end
      end

      private

      def item_index_at(my)
        rel_y = my - (screen_top + 4.0) + @scroll_y
        return nil if rel_y < 0.0
        idx = (rel_y / @item_height).to_i
        (idx >= 0 && idx < @items.length) ? idx : nil
      end

      def update_sb_from_mouse(my)
        sb_y = screen_top + 3.0
        sb_h = [screen_height - 6.0, 10.0].max
        thumb_h = [[(inner_height / total_content_height) * sb_h, 20.0].max, sb_h].min
        avail = [sb_h - thumb_h, 1.0].max
        ratio = ((my - (sb_y + thumb_h * 0.5)) / avail).clamp(0.0, 1.0)
        @scroll_y = ratio * max_scroll
      end
    end
  end
end

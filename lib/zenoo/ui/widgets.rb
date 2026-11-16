# frozen_string_literal: true

module Zenoo
  module UI
    # 水平区切り線
    class Divider < Widget
      attr_accessor :color

      def initialize(x = 0.0, y = 0.0, width: 200.0, height: 8.0, color: nil, **opts)
        @color = color
        super(x, y, width: width, height: height, interactive: false, **opts)
      end

      def draw_self
        th = theme
        ry = (screen_top + screen_height * 0.5).floor
        Zenoo::Window.draw_rect(screen_left, ry, screen_width, 1.0, color: @color || th.border_normal, camera: false, z: @z)
      end
    end

    # レイアウト余白調整用スペーサ
    class Spacer < Widget
      def initialize(size = 8.0, flex: nil, **opts)
        s = size.to_f
        super(0.0, 0.0, width: s, height: s, flex: flex, interactive: false, **opts)
      end
    end

    # 画像表示ウィジェット
    class ImageBox < Widget
      attr_accessor :fit, :bg_color, :border_color, :border_width, :radius, :tint

      def initialize(image = nil, x = 0.0, y = 0.0, width: nil, height: nil,
                     fit: :contain, bg_color: nil, border_color: nil, border_width: 0.0, radius: 4.0,
                     tint: nil, interactive: false, **opts)
        @source_image = image
        @fit          = fit
        @bg_color     = bg_color
        @border_color = border_color
        @border_width = border_width.to_f
        @radius       = radius.to_f
        @tint         = tint
        w = width ? width.to_f : (image ? image.width.to_f : 64.0)
        h = height ? height.to_f : (image ? image.height.to_f : 64.0)
        super(x, y, width: w, height: h, interactive: interactive, **opts)
      end

      def image = @source_image
      def image=(val)
        @source_image = val
      end
      def collider_radius = @radius

      def draw_self
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        has_border = !@border_color.nil? && @border_width > 0.0
        bw = has_border ? @border_width : 0.0

        if @bg_color
          Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: @radius, color: @bg_color, camera: false, z: @z)
        end

        if (img = @source_image)
          iw = img.width.to_f
          ih = img.height.to_f
          ix = rx + bw
          iy = ry + bw
          ax_w = [rw - bw * 2.0, 0.0].max
          ax_h = [rh - bw * 2.0, 0.0].max
          if iw > 0.0 && ih > 0.0 && ax_w > 0.0 && ax_h > 0.0
            case @fit
            when :stretch
              dw = ax_w; dh = ax_h; dx = ix; dy = iy
            when :center
              dw = iw * world_scale_x
              dh = ih * world_scale_y
              dx = ix + (ax_w - dw) * 0.5
              dy = iy + (ax_h - dh) * 0.5
            else # :contain
              sc = [ax_w / iw, ax_h / ih].min
              dw = iw * sc
              dh = ih * sc
              dx = ix + (ax_w - dw) * 0.5
              dy = iy + (ax_h - dh) * 0.5
            end

            inner_rad = [@radius - bw, 0.0].max
            img_rad = (@fit == :stretch) ? inner_rad : [inner_rad, dw * 0.5, dh * 0.5].min
            if @fit == :center && (dw > ax_w || dh > ax_h)
              prev_ox, prev_oy = Zenoo::Window.push_clip_scope(ix, iy, ax_w, ax_h, local: false, z: @z)
              Zenoo::Window.draw_rect(dx, dy, dw, dh, radius: img_rad, color: @tint || :white, image: img, camera: false, z: @z)
              Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)
            else
              Zenoo::Window.draw_rect(dx, dy, dw, dh, radius: img_rad, color: @tint || :white, image: img, camera: false, z: @z)
            end
          end
        end

        if has_border
          Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: @radius, color: nil,
                                  border_width: @border_width, border_color: @border_color, camera: false, z: @z)
        end
      end
    end

    # 単一行テキストラベル
    class Label < Widget
      attr_accessor :text, :color

      def initialize(text = "", x = 0.0, y = 0.0, width: nil, height: nil, size: nil, color: nil, **opts)
        @text  = text.to_s
        @size  = size ? size.to_i : nil
        @color = color
        super(x, y, width: width, height: height, interactive: false, **opts)
      end

      def font_size = @size || theme.font_size
      def width     = @width || Font.default.text_width(@text, font_size)
      def height    = @height || (font_size + 4.0)

      def draw_self
        return if @text.empty?
        th = theme
        Zenoo::Window.draw_text(screen_left, screen_top + screen_height * 0.5, @text,
                                size: font_size, color: @color || th.text_color, valign: :center, camera: false, z: @z)
      end
    end

    # プッシュボタン
    class Button < Widget
      include Clickable
      attr_accessor :label, :active

      def initialize(label = "Button", x = 0.0, y = 0.0, width: 120.0, height: nil, active: false, **opts, &block)
        @label  = label.to_s
        @active = !!active
        super(x, y, width: width, height: height, **opts)
        on_click(&block) if block
      end

      def active? = !!@active
      def collider_radius = theme.radius

      def draw_self
        th = theme
        bg = if pressed?
               th.bg_active
             elsif active?
               hovered? ? th.accent_hover : th.accent_color
             elsif hovered?
               th.bg_hover
             else
               th.bg_normal
             end
        bd = (hovered? || active?) ? th.border_hover : th.border_normal
        py = pressed? ? 1.0 : 0.0
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: th.radius, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)
        Zenoo::Window.draw_text(screen_left + screen_width * 0.5, screen_top + screen_height * 0.5 + py,
                                @label, size: th.font_size, color: th.text_color, align: :center, valign: :center, camera: false, z: @z)
      end
    end

    # トグル系ウィジェットの共通基底
    class ToggleBase < Widget
      include Clickable
      attr_accessor :label
      attr_reader :checked

      def initialize(label = "", checked = false, x = 0.0, y = 0.0, width: 200.0, height: nil, **opts, &block)
        @label   = label.to_s
        @checked = !!checked
        @on_change_proc = block
        super(x, y, width: width, height: height, **opts)
      end

      def checked? = @checked
      def checked=(val)
        @checked = !!val
      end
      def on_change(&block) = (@on_change_proc = block; self)

      def trigger_click!
        self.checked = !@checked
        @on_change_proc&.call(@checked)
        super
      end
    end

    # 四角チェックボックス
    class Checkbox < ToggleBase
      def draw_self
        th = theme
        lx = screen_left
        sy = world_scale_y
        box_sz = (th.font_size + 3).to_f * sy
        ty = screen_top + (screen_height - box_sz) * 0.5
        rad = [th.radius, 4.0].min
        bd = hovered? ? th.border_hover : (@checked ? th.accent_color : th.border_normal)
        bg = hovered? ? th.bg_hover : th.track_bg
        Zenoo::Window.draw_rect(lx, ty, box_sz, box_sz, radius: rad, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)
        if @checked
          pad = 3.5 * sy
          inner_sz = [box_sz - pad * 2.0, 2.0].max
          Zenoo::Window.draw_rect(lx + pad, ty + pad, inner_sz, inner_sz, radius: [rad - 1.5, 1.5].max, color: th.accent_color, camera: false, z: @z)
        end
        unless @label.empty?
          Zenoo::Window.draw_text(lx + box_sz + 7.0, screen_top + screen_height * 0.5, @label, size: th.font_size, color: th.text_color, valign: :center, camera: false, z: @z)
        end
      end
    end

    # 丸ツマミが左右にスライドするトグルスイッチ
    class Switch < ToggleBase
      def initialize(label = "", checked = false, x = 0.0, y = 0.0, width: 200.0, height: nil, **opts, &block)
        super
        @knob_t = @checked ? 1.0 : 0.0
      end

      def update
        target = @checked ? 1.0 : 0.0
        diff = target - @knob_t
        if diff.abs <= 0.01
          @knob_t = target
        else
          @knob_t += diff * 0.28
        end
        super
      end

      def draw_self
        th = theme
        lx = screen_left
        sx = world_scale_x
        sy = world_scale_y
        sw_h = (th.font_size + 5).to_f * sy
        sw_w = (sw_h * 1.85).round.to_f
        ty = screen_top + (screen_height - sw_h) * 0.5
        rad = sw_h * 0.5

        off_c = th.track_bg
        on_c  = hovered? ? th.accent_hover : th.accent_color
        bg = [
          (off_c[0] + (on_c[0] - off_c[0]) * @knob_t).round,
          (off_c[1] + (on_c[1] - off_c[1]) * @knob_t).round,
          (off_c[2] + (on_c[2] - off_c[2]) * @knob_t).round
        ]
        bd = hovered? ? th.border_hover : (@checked ? th.accent_color : th.border_normal)
        Zenoo::Window.draw_rect(lx, ty, sw_w, sw_h, radius: rad, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)

        knob_r = [rad - 3.0 * sy, 3.0].max
        knob_x = lx + rad + @knob_t * (sw_w - sw_h)
        knob_col = @checked ? [255, 255, 255] : (hovered? ? th.text_color : th.text_muted)
        Zenoo::Window.draw_circle(knob_x, ty + rad, knob_r, color: knob_col, camera: false, z: @z)

        unless @label.empty?
          Zenoo::Window.draw_text(lx + sw_w + 8.0 * sx, screen_top + screen_height * 0.5, @label,
                                  size: th.font_size, color: th.text_color, valign: :center, camera: false, z: @z)
        end
      end
    end

    # 同一親内のグループ排他選択ラジオボタン
    class RadioButton < Widget
      include Clickable
      attr_accessor :label, :checked, :group, :value

      def initialize(label = "", checked = false, x = 0.0, y = 0.0, width: nil, height: nil,
                     group: nil, value: nil, **opts, &block)
        @label   = label.to_s
        @checked = !!checked
        @group   = group
        @value   = value
        @on_change_proc = block
        super(x, y, width: width || 120.0, height: height, **opts)
        if width.nil?
          tw = @label.empty? ? 0.0 : Font.default.text_width(@label, theme.font_size)
          self.width = 24.0 + tw + 8.0
        end
      end

      def checked? = @checked
      def on_change(&block) = (@on_change_proc = block; self)

      def trigger_click!
        unless @checked
          if @parent && (ch = @parent.children)
            i = 0
            len = ch.length
            while i < len
              sib = ch[i]
              sib.checked = false if sib.is_a?(RadioButton) && !sib.equal?(self) && sib.group == @group
              i += 1
            end
          end
          @checked = true
          @on_change_proc&.call(@value.nil? ? true : @value)
        end
        super
      end

      def draw_self
        th = theme
        sy = world_scale_y
        r = [((th.font_size + 2) * 0.5).round.to_f, 7.0].max * sy
        cx = screen_left + r + 1.0
        cy = screen_top + screen_height * 0.5

        bd = hovered? ? th.border_hover : (@checked ? th.accent_color : th.border_normal)
        bg = hovered? ? th.bg_hover : th.track_bg
        Zenoo::Window.draw_circle(cx, cy, r, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)
        Zenoo::Window.draw_circle(cx, cy, r * 0.5, color: th.accent_color, camera: false, z: @z) if @checked

        unless @label.empty?
          Zenoo::Window.draw_text(screen_left + r * 2.0 + 7.0, cy, @label,
                                  size: th.font_size, color: th.text_color, valign: :center, camera: false, z: @z)
        end
      end
    end

    # 進行状況バー
    class ProgressBar < Widget
      attr_accessor :min, :max, :label, :fill_color, :bg_color, :show_percentage
      attr_reader :value

      def initialize(value = 0.0, min = 0.0, max = 1.0, x = 0.0, y = 0.0, width: 220.0, height: nil,
                     label: nil, show_percentage: true, fill_color: nil, bg_color: nil, **opts)
        @value           = value.to_f
        @min             = min.to_f
        @max             = max.to_f
        @label           = label
        @show_percentage = show_percentage
        @fill_color      = fill_color
        @bg_color        = bg_color
        super(x, y, width: width, height: height, interactive: false, **opts)
      end

      def value=(v)
        @value = v.to_f
      end

      def ratio
        span = @max - @min
        return 0.0 if span <= 0.00001
        ((@value - @min) / span).clamp(0.0, 1.0)
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        rad = th.radius

        Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: rad, color: @bg_color || th.track_bg,
                                border_width: 1.0, border_color: th.track_border, camera: false, z: @z)

        r = ratio
        fw = (rw - 2.0) * r
        if fw > 1.0
          Zenoo::Window.draw_rect(rx + 1.0, ry + 1.0, fw, [rh - 2.0, 1.0].max,
                                  radius: [rad - 1.0, 1.0].max, color: @fill_color || th.accent_color, camera: false, z: @z)
        end

        txt = if @label
                @label.to_s
              elsif @show_percentage
                "#{(r * 100.0).round}%"
              else
                nil
              end
        if txt && !txt.empty?
          Zenoo::Window.draw_text(rx + rw * 0.5, ry + rh * 0.5, txt,
                                  size: [th.font_size - 1, 10].max, color: th.text_color, align: :center, valign: :center, camera: false, z: @z)
        end
      end
    end

    # スライダー共通基底
    class SliderBase < Widget
      include Draggable
      attr_reader :value, :min, :max

      def initialize(label = "", value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0,
                     width: 220.0, height: nil, format: nil, unit: "", **opts, &block)
        @label          = label.to_s
        @min            = min.to_f
        @max            = max.to_f
        @value          = value.to_f.clamp(@min, @max)
        @format         = format
        @unit           = unit.to_s
        @on_change_proc = block
        super(x, y, width: width, height: height, **opts)
        self.drag_target = nil
      end

      def set_default_collider
        ox, oy, tw, th_b, rad = track_local_bounds
        set_collider(:rect, width: tw, height: th_b,
                     offset_x: ox + tw * 0.5, offset_y: oy + th_b * 0.5,
                     at: :top_left, radius: rad)
      end

      def sync_collider_shape
        col = @collider_shape
        return unless col && col.shape_type == Collision::TYPE_RECT
        ox, oy, tw, th_b, rad = track_local_bounds
        col.width = tw
        col.height = th_b
        col.offset_x = ox + tw * 0.5
        col.offset_y = oy + th_b * 0.5
        col.radius = rad
      end

      def cursor_shape = :hand
      def on_change(&block) = (@on_change_proc = block; self)

      def value=(v)
        nv = v.to_f.clamp(@min, @max)
        if nv != @value
          @value = nv
          @on_change_proc&.call(@value)
        end
      end

      def on_pointer_down(mx, my)
        super
        update_value_from_x(mx)
      end

      def on_pointer_drag(mx, my)
        super
        update_value_from_x(mx) if dragging?
      end

      private

      def value_ratio
        (@max > @min) ? (@value - @min) / (@max - @min) : 0.0
      end

      def format_value
        s = @format ? sprintf(@format, @value) : sprintf("%.2f", @value).sub(/\.?0+$/, "")
        s = "0" if s == "-0"
        @unit.empty? ? s : "#{s}#{@unit}"
      end

      def track_rect_bounds
        ox, _oy, tw, _bh, _rad = track_local_bounds
        sx = world_scale_x
        [screen_left + ox * sx, tw * sx]
      end

      def update_value_from_x(mx)
        tx, tw = track_rect_bounds
        ratio = ((mx - tx) / [tw, 1.0].max).clamp(0.0, 1.0)
        self.value = @min + (@max - @min) * ratio
      end
    end

    # 1段インライン型スライダー
    class Slider < SliderBase
      def initialize(label = "", value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0,
                     width: 220.0, height: nil, label_width: nil, format: nil, unit: "", **opts, &block)
        @label_width = label_width ? label_width.to_f : nil
        super(label, value, min, max, x, y, width: width, height: height, format: format, unit: unit, **opts, &block)
      end

      def track_local_bounds
        th = theme
        rw = width
        rh = height
        ox = @label.empty? ? 0.0 : [(@label_width || 110.0), rw * 0.48].min
        tw = [rw - ox, 1.0].max
        bar_y = 2.0
        bar_h = [rh - 4.0, 12.0].max
        [ox, bar_y, tw, bar_h, th.radius]
      end

      def draw_self
        th = theme
        lx = screen_left
        ty = screen_top
        rh = screen_height
        ox, bar_y_off, tw, bar_h, rad = track_local_bounds
        sx = world_scale_x
        sy = world_scale_y
        tx = lx + ox * sx
        tw_s = tw * sx
        bar_y = ty + bar_y_off * sy
        bar_h_s = bar_h * sy
        ratio = value_ratio
        val_str = format_value

        unless @label.empty?
          Zenoo::Window.draw_text(lx, ty + rh * 0.5, @label, size: th.font_size, color: th.text_muted, valign: :center, camera: false, z: @z)
        end

        bd = (hovered? || dragging?) ? th.border_hover : th.track_border
        Zenoo::Window.draw_rect(tx, bar_y, tw_s, bar_h_s, radius: rad, color: th.track_bg, border_width: 1.0, border_color: bd, camera: false, z: @z)

        fill_w = tw_s * ratio
        if fill_w > 1.0
          fill_col = (hovered? || dragging?) ? th.accent_hover : th.accent_color
          Zenoo::Window.draw_rect(tx, bar_y, fill_w, bar_h_s, radius: rad, color: fill_col, camera: false, z: @z)
        end

        if tw_s > 8.0
          kx = (tx + fill_w).clamp(tx + 2.0, tx + tw_s - 2.0)
          Zenoo::Window.draw_line(kx, bar_y + 2.0, kx, bar_y + bar_h_s - 2.0, color: [245, 250, 255, 220], width: 2.0, camera: false, z: @z)
        end

        Zenoo::Window.draw_text(tx + tw_s - 6.0, ty + rh * 0.5, val_str,
                                size: [th.font_size - 1, 10].max, color: th.text_color, align: :right, valign: :center, camera: false, z: @z)
      end
    end

    # 2段スタック型スライダー
    class StackedSlider < SliderBase
      def height
        @height || (theme.control_height + 6.0)
      end

      def track_local_bounds
        th = theme
        bar_y = th.font_size + 2.0
        [0.0, bar_y, [width, 1.0].max, 17.0, 4.0]
      end

      def draw_self
        th = theme
        lx = screen_left
        ty = screen_top
        rw = screen_width
        sy = world_scale_y
        ratio = value_ratio
        val_str = format_value

        Zenoo::Window.draw_text(lx, ty, @label, size: th.font_size - 1, color: th.text_color, camera: false, z: @z)
        Zenoo::Window.draw_text(lx + rw, ty, val_str, size: th.font_size - 1, color: th.accent_hover, align: :right, camera: false, z: @z)

        track_y = ty + (th.font_size + 7.0) * sy
        bar_h = 7.0 * sy
        Zenoo::Window.draw_rect(lx, track_y, rw, bar_h, radius: 3.5, color: th.track_bg, border_width: 1, border_color: th.track_border, camera: false, z: @z)
        Zenoo::Window.draw_rect(lx, track_y, rw * ratio, bar_h, radius: 3.5, color: th.accent_color, camera: false, z: @z)
        knob_col = (hovered? || dragging?) ? th.accent_hover : th.text_color
        Zenoo::Window.draw_circle(lx + rw * ratio, track_y + bar_h * 0.5, 6.5 * sy, color: knob_col, camera: false, z: @z)
      end
    end

    # [-] / [+] ボタン付き数値ステッパー
    class Spinner < Widget
      attr_accessor :label, :min, :max, :step, :format
      attr_reader :value

      def initialize(label = "", value = 0, x = 0.0, y = 0.0, min: nil, max: nil, step: 1,
                     width: 220.0, height: nil, label_width: nil, format: nil, **opts, &block)
        @label          = label.to_s
        @min            = min
        @max            = max
        @step           = step
        @label_width    = label_width ? label_width.to_f : nil
        @format         = format
        @value          = clamp_val(value)
        @hover_part     = nil
        @on_change_proc = block
        super(x, y, width: width, height: height, **opts)
      end

      def cursor_shape = @hover_part ? :hand : :arrow
      def on_change(&block) = (@on_change_proc = block; self)

      def value=(val)
        nv = clamp_val(val)
        if nv != @value
          @value = nv
          @on_change_proc&.call(@value)
        end
      end

      def set_default_collider
        ox, oy, cw, ch, rad = ctrl_local_bounds
        set_collider(:rect, width: cw, height: ch,
                     offset_x: ox + cw * 0.5, offset_y: oy + ch * 0.5,
                     at: :top_left, radius: rad)
      end

      def sync_collider_shape
        col = @collider_shape
        return unless col && col.shape_type == Collision::TYPE_RECT
        ox, oy, cw, ch, rad = ctrl_local_bounds
        col.width = cw
        col.height = ch
        col.offset_x = ox + cw * 0.5
        col.offset_y = oy + ch * 0.5
        col.radius = rad
      end

      def on_pointer_move(mx, _my)
        @hover_part = hit_part(mx)
      end

      def on_pointer_leave
        @hover_part = nil
      end

      def on_pointer_down(mx, _my)
        super
        part = hit_part(mx)
        if part == :minus
          self.value = @value - @step
        elsif part == :plus
          self.value = @value + @step
        end
      end

      def draw_self
        th = theme
        lx = screen_left
        ty = screen_top
        rh = screen_height

        unless @label.empty?
          Zenoo::Window.draw_text(lx, ty + rh * 0.5, @label, size: th.font_size, color: th.text_muted, valign: :center, camera: false, z: @z)
        end

        _cx, _cw, btn_w, minus_x, plus_x, val_x, val_w = ctrl_screen_layout
        rad = th.radius

        Zenoo::Window.draw_rect(val_x, ty, val_w, rh, radius: [rad - 1.0, 2.0].max,
                                color: th.track_bg, border_width: 1.0, border_color: th.track_border, camera: false, z: @z)
        fmt = @format || (@value.is_a?(Float) ? "%.2f" : "%d")
        val_str = sprintf(fmt, @value)
        Zenoo::Window.draw_text(val_x + val_w * 0.5, ty + rh * 0.5, val_str,
                                size: th.font_size, color: th.text_color, align: :center, valign: :center, camera: false, z: @z)

        draw_step_button(th, minus_x, ty, btn_w, rh, rad, "-", @hover_part == :minus)
        draw_step_button(th, plus_x,  ty, btn_w, rh, rad, "+", @hover_part == :plus)
      end

      private

      def clamp_val(val)
        v = val
        v = @min if @min && v < @min
        v = @max if @max && v > @max
        v
      end

      def ctrl_local_bounds
        th = theme
        rw = width
        ox = @label.empty? ? 0.0 : [(@label_width || 110.0), rw * 0.48].min
        [ox, 0.0, [rw - ox, 1.0].max, height, th.radius]
      end

      def ctrl_screen_layout
        ox, _oy, cw, _ch, = ctrl_local_bounds
        sx = world_scale_x
        cx = screen_left + ox * sx
        cw_s = cw * sx
        rh_s = screen_height
        btn_w = [rh_s, cw_s * 0.28, 26.0 * sx].min
        minus_x = cx
        plus_x  = cx + cw_s - btn_w
        val_x   = cx + btn_w + 2.0
        val_w   = [cw_s - btn_w * 2.0 - 4.0, 4.0].max
        [cx, cw_s, btn_w, minus_x, plus_x, val_x, val_w]
      end

      def hit_part(mx)
        _cx, _cw, btn_w, minus_x, plus_x, = ctrl_screen_layout
        if mx >= minus_x && mx <= minus_x + btn_w
          :minus
        elsif mx >= plus_x && mx <= plus_x + btn_w
          :plus
        else
          nil
        end
      end

      def draw_step_button(th, bx, by, bw, bh, rad, glyph, hov)
        Zenoo::Window.draw_rect(bx, by, bw, bh, radius: rad,
                                color: hov ? th.bg_hover : th.bg_normal,
                                border_width: 1.0, border_color: hov ? th.border_hover : th.border_normal,
                                camera: false, z: @z)
        Zenoo::Window.draw_text(bx + bw * 0.5, by + bh * 0.5, glyph,
                                size: th.font_size, color: hov ? [255, 255, 255] : th.text_color,
                                align: :center, valign: :center, camera: false, z: @z)
      end
    end

    # ポップアップ選択リスト付きドロップダウン
    class Dropdown < Widget
      attr_accessor :label
      attr_reader :items, :selected_index, :popup_collider

      def initialize(items = [], selected_index = 0, x = 0.0, y = 0.0,
                     width: 200.0, height: nil, label: "", max_items: 8, **opts, &block)
        @items          = items.map(&:to_s)
        @selected_index = (@items.empty? || selected_index.nil? || selected_index.to_i < 0) ? -1 : selected_index.to_i.clamp(0, @items.length - 1)
        @label          = label.to_s
        @max_items      = [max_items.to_i, 1].max
        @hover_item_idx = nil
        @scroll_index   = 0
        @on_change_proc = block
        @popup_collider = Collision::Rect.new(0.0, 0.0, 100.0, 20.0, anchor: :top_left, pivot: :center)
        super(x, y, width: width, height: height, **opts)
      end

      def cursor_shape       = :hand
      def popup_cursor_shape = :hand
      def collider_radius    = theme.radius
      def on_change(&block)  = (@on_change_proc = block; self)
      def selected_item      = (@selected_index >= 0) ? @items[@selected_index] : nil

      def items=(val)
        @items = val.map(&:to_s)
        if @items.empty?
          @selected_index = -1
        elsif @selected_index >= @items.length
          @selected_index = @items.length - 1
        end
        clamp_scroll!
      end

      def selected_index=(idx)
        if idx.nil? || idx.to_i < 0 || @items.empty?
          @selected_index = -1
        else
          @selected_index = idx.to_i.clamp(0, @items.length - 1)
        end
      end

      def on_pointer_down(_mx, _my)
        super
        popup_open? ? close_popup! : open_popup! unless @items.empty?
      end

      def on_popup_open
        @hover_item_idx = nil
        ensure_selected_visible
        compute_popup_layout
      end

      def on_popup_close
        @hover_item_idx = nil
      end

      def hit_test_popup?(mx, my)
        return false if @items.empty?
        compute_popup_layout
        Collision.check(UI.point_collider(mx, my), @popup_collider)
      end

      def on_popup_move(mx, my)
        unless hit_test_popup?(mx, my)
          @hover_item_idx = nil
          return
        end
        _px, py, _pw, _ph, item_h, pad, vis_count = compute_popup_layout
        row = ((my - (py + pad)) / item_h).floor
        if row >= 0 && row < vis_count
          idx = @scroll_index + row
          @hover_item_idx = (idx < @items.length) ? idx : nil
        else
          @hover_item_idx = nil
        end
      end

      def on_popup_wheel(dy)
        max_scroll = [@items.length - @max_items, 0].max
        return false if max_scroll <= 0
        @scroll_index = (@scroll_index + (dy > 0.0 ? -1 : 1)).clamp(0, max_scroll)
        true
      end

      def on_popup_down(mx, my)
        on_popup_move(mx, my)
        return unless @hover_item_idx
        old = @selected_index
        @selected_index = @hover_item_idx
        close_popup!
        @on_change_proc&.call(@selected_index, selected_item) if @selected_index != old
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        is_open = popup_open?

        bg = (hovered? || is_open) ? th.bg_hover : th.bg_normal
        bd = is_open ? th.accent_color : (hovered? ? th.border_hover : th.border_normal)
        Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: th.radius, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)

        tx = rx + 8.0
        ty = ry + rh * 0.5
        sel_str = (selected_item || "").to_s
        if @label.empty?
          Zenoo::Window.draw_text(tx, ty, sel_str, size: th.font_size, color: th.text_color, valign: :center, camera: false, z: @z) unless sel_str.empty?
        else
          prefix = "#{@label}: "
          Zenoo::Window.draw_text(tx, ty, prefix, size: th.font_size, color: th.text_muted, valign: :center, camera: false, z: @z)
          pw = Font.default.text_width(prefix, th.font_size)
          Zenoo::Window.draw_text(tx + pw, ty, sel_str, size: th.font_size, color: th.text_color, valign: :center, camera: false, z: @z) unless sel_str.empty?
        end

        ax = rx + rw - 14.0
        ay = ty
        acol = (hovered? || is_open) ? th.accent_hover : th.text_muted
        if is_open
          Zenoo::Window.draw_triangle(ax, ay + 2.5, ax + 8.0, ay + 2.5, ax + 4.0, ay - 2.5, color: acol, camera: false, z: @z)
        else
          Zenoo::Window.draw_triangle(ax, ay - 2.5, ax + 8.0, ay - 2.5, ax + 4.0, ay + 2.5, color: acol, camera: false, z: @z)
        end
      end

      def draw_popup
        return if @items.empty?
        th = theme
        px, py, pw, ph, item_h, pad, vis_count = compute_popup_layout
        pop_z = 9000.0

        Zenoo::Window.draw_rect(px, py, pw, ph,
                                radius: th.radius + 1.0, color: th.win_bg,
                                border_width: 1.5, border_color: th.accent_color,
                                shadow_blur: 10.0, shadow_color: [0, 0, 0, 160], camera: false, z: pop_z)

        has_scroll = @items.length > @max_items
        item_w = pw - pad * 2.0 - (has_scroll ? 7.0 : 0.0)
        row = 0
        while row < vis_count
          idx = @scroll_index + row
          break if idx >= @items.length
          iy = py + pad + row * item_h
          is_sel = (idx == @selected_index)
          is_hov = (idx == @hover_item_idx)

          if is_sel || is_hov
            col = is_hov ? th.bg_hover : th.bg_active
            Zenoo::Window.draw_rect(px + pad, iy, item_w, item_h, radius: [th.radius - 1.0, 2.0].max, color: col, camera: false, z: pop_z + 1.0)
          end
          if is_sel
            Zenoo::Window.draw_rect(px + pad + 2.0, iy + 3.0, 3.0, item_h - 6.0, radius: 1.5, color: th.accent_color, camera: false, z: pop_z + 2.0)
          end

          tcol = (is_sel || is_hov) ? [255, 255, 255] : th.text_color
          Zenoo::Window.draw_text(px + pad + 9.0, iy + item_h * 0.5, @items[idx],
                                  size: th.font_size, color: tcol, valign: :center, camera: false, z: pop_z + 2.0)
          row += 1
        end

        if has_scroll
          track_x = px + pw - pad - 4.0
          track_y = py + pad
          track_h = ph - pad * 2.0
          thumb_h = [track_h * (vis_count.to_f / @items.length), 14.0].max
          max_s = @items.length - @max_items
          ratio = max_s > 0 ? (@scroll_index.to_f / max_s) : 0.0
          thumb_y = track_y + (track_h - thumb_h) * ratio
          Zenoo::Window.draw_rect(track_x, thumb_y, 3.0, thumb_h, radius: 1.5, color: th.accent_color, camera: false, z: pop_z + 2.0)
        end
      end

      private

      def clamp_scroll!
        max_s = [@items.length - @max_items, 0].max
        @scroll_index = @scroll_index.clamp(0, max_s)
      end

      def ensure_selected_visible
        return if @selected_index < 0
        if @selected_index < @scroll_index
          @scroll_index = @selected_index
        elsif @selected_index >= @scroll_index + @max_items
          @scroll_index = @selected_index - @max_items + 1
        end
        clamp_scroll!
      end

      def compute_popup_layout
        th = theme
        item_h = [th.control_height - 2.0, 20.0].max
        pad = 3.0
        vis_count = [@items.length, @max_items].min
        ph = vis_count * item_h + pad * 2.0
        pw = [screen_width, 110.0].max

        win_w = Zenoo::Window.width.to_f
        win_h = Zenoo::Window.height.to_f
        px = screen_left
        px = [px, win_w - pw - 4.0].min if win_w > 0.0
        px = 4.0 if px < 4.0

        below_y = screen_top + screen_height + 2.0
        above_y = screen_top - ph - 2.0
        py = (win_h > 0.0 && below_y + ph > win_h - 4.0 && above_y >= 4.0) ? above_y : below_y

        @popup_collider.x = px
        @popup_collider.y = py
        @popup_collider.width = pw
        @popup_collider.height = ph
        @popup_collider.radius = th.radius + 1.0
        @popup_collider.update_cache if @popup_collider.dirty?

        [px, py, pw, ph, item_h, pad, vis_count]
      end
    end

    # キャレット操作・範囲選択・クリップボード・IME座標同期対応テキストボックス
    class TextBox < Widget
      include Focusable
      attr_accessor :label, :placeholder
      attr_reader :text, :cursor_pos

      def initialize(text = "", x = 0.0, y = 0.0, width: 220.0, height: nil,
                     label: "", label_width: nil, placeholder: "", **opts, &block)
        @text              = text.to_s.dup
        @label             = label.to_s
        @label_width       = label_width ? label_width.to_f : nil
        @placeholder       = placeholder.to_s
        @cursor_pos        = @text.length
        @sel_anchor        = nil
        @dragging_sel      = false
        @scroll_x          = 0.0
        @blink_start_frame = UI.frame
        @on_change_proc    = block
        @on_submit_proc    = nil
        super(x, y, width: width, height: height, **opts)
      end

      def cursor_shape = :ibeam
      def on_change(&block) = (@on_change_proc = block; self)
      def on_submit(&block) = (@on_submit_proc = block; self)

      def text=(val)
        @text = val.to_s.dup
        @cursor_pos = @cursor_pos.clamp(0, @text.length)
        @sel_anchor = nil
        @scroll_x = 0.0 if @text.empty?
      end

      def set_default_collider
        ox, oy, bw, bh, rad = box_local_bounds
        set_collider(:rect, width: bw, height: bh,
                     offset_x: ox + bw * 0.5, offset_y: oy + bh * 0.5,
                     at: :top_left, radius: rad)
      end

      def sync_collider_shape
        col = @collider_shape
        return unless col && col.shape_type == Collision::TYPE_RECT
        ox, oy, bw, bh, rad = box_local_bounds
        col.width = bw
        col.height = bh
        col.offset_x = ox + bw * 0.5
        col.offset_y = oy + bh * 0.5
        col.radius = rad
      end

      def on_pointer_down(mx, _my)
        super
        idx = index_at_mouse_x(mx)
        shift_down = Input.key_pressed?(:left_shift) || Input.key_pressed?(:right_shift)
        if shift_down
          @sel_anchor ||= @cursor_pos
        else
          @sel_anchor = idx
        end
        @cursor_pos = idx
        @dragging_sel = true
        ensure_caret_visible
        @blink_start_frame = UI.frame
      end

      def on_pointer_drag(mx, _my)
        super
        return unless @dragging_sel
        @cursor_pos = index_at_mouse_x(mx)
        ensure_caret_visible
        @blink_start_frame = UI.frame
      end

      def on_pointer_up(_mx, _my, _inside)
        @dragging_sel = false
        @sel_anchor = nil if @sel_anchor == @cursor_pos
        super
      end

      def on_focus
        @blink_start_frame = UI.frame
      end

      def on_blur
        @sel_anchor = nil
        @dragging_sel = false
        Input.set_ime_position(-1, -1)
      end

      def on_focused_update
        return unless @enabled

        bx, by, bw, bh, = box_screen_rect
        f_font, f_size = text_font_and_size
        caret_ox = f_font.text_width(@text[0...@cursor_pos] || "", f_size)
        ensure_caret_visible_with(caret_ox, bw)
        pad_x = 8.0 * world_scale_x
        abs_ime_x = bx + pad_x + caret_ox - @scroll_x + Zenoo::Window.__offset_x
        abs_ime_y = by + bh + 2.0 + Zenoo::Window.__offset_y
        Input.set_ime_position(abs_ime_x, abs_ime_y)

        ctrl_down = Input.key_pressed?(:left_control) || Input.key_pressed?(:right_control) ||
                    Input.key_pressed?(:left_super) || Input.key_pressed?(:right_super)
        shift_down = Input.key_pressed?(:left_shift) || Input.key_pressed?(:right_shift)

        reset_blink = false
        text_changed = false

        if ctrl_down && Input.key_push?(:v)
          clip = Input.clipboard
          if clip && !clip.empty?
            clip = clip.gsub(/[\r\n\t]+/, " ")
            replace_selection(clip)
            reset_blink = true
            text_changed = true
          end
        elsif ctrl_down && Input.key_push?(:c)
          Input.clipboard = has_selection? ? selected_text : @text
        elsif ctrl_down && Input.key_push?(:x)
          if has_selection?
            Input.clipboard = selected_text
            delete_selection!
            text_changed = true
          else
            Input.clipboard = @text
            unless @text.empty?
              @text = String.new
              @cursor_pos = 0
              text_changed = true
            end
          end
          reset_blink = true
        elsif ctrl_down && Input.key_push?(:a)
          @sel_anchor = 0
          @cursor_pos = @text.length
          reset_blink = true
        elsif Input.key_repeat?(:backspace)
          if delete_selection!
            reset_blink = true
            text_changed = true
          elsif @cursor_pos > 0
            @text.slice!(@cursor_pos - 1)
            @cursor_pos -= 1
            reset_blink = true
            text_changed = true
          end
        elsif Input.key_repeat?(:delete)
          if delete_selection!
            reset_blink = true
            text_changed = true
          elsif @cursor_pos < @text.length
            @text.slice!(@cursor_pos)
            reset_blink = true
            text_changed = true
          end
        elsif Input.key_repeat?(:left)
          move_caret_left(shift_down)
          reset_blink = true
        elsif Input.key_repeat?(:right)
          move_caret_right(shift_down)
          reset_blink = true
        elsif Input.key_push?(:home)
          shift_down ? (@sel_anchor ||= @cursor_pos) : (@sel_anchor = nil)
          @cursor_pos = 0
          reset_blink = true
        elsif Input.key_push?(:end)
          shift_down ? (@sel_anchor ||= @cursor_pos) : (@sel_anchor = nil)
          @cursor_pos = @text.length
          reset_blink = true
        elsif Input.key_push?(:enter)
          @on_submit_proc&.call(@text)
          blur!
          return
        elsif Input.key_push?(:escape)
          blur!
          return
        end

        unless ctrl_down
          chars = Input.input_chars
          i = 0
          len = chars.length
          while i < len
            ch = chars[i]
            if ch.ord >= 32
              replace_selection(ch)
              reset_blink = true
              text_changed = true
            end
            i += 1
          end
        end

        @blink_start_frame = UI.frame if reset_blink
        if text_changed
          ensure_caret_visible
          @on_change_proc&.call(@text)
        elsif reset_blink
          ensure_caret_visible
        end
      end

      def draw_self
        th = theme
        unless @label.empty?
          Zenoo::Window.draw_text(screen_left, screen_top + screen_height * 0.5, @label,
                                  size: th.font_size, color: th.text_muted, valign: :center, camera: false, z: @z)
        end

        bx, by, bw, bh, rad = box_screen_rect
        is_foc = focused?
        bd = is_foc ? th.accent_color : (hovered? ? th.border_hover : th.track_border)
        bd_w = is_foc ? 1.5 : 1.0
        Zenoo::Window.draw_rect(bx, by, bw, bh, radius: rad, color: th.track_bg,
                                border_width: bd_w, border_color: bd, camera: false, z: @z)

        f_font, f_size = text_font_and_size
        caret_ox = f_font.text_width(@text[0...@cursor_pos] || "", f_size)
        ensure_caret_visible_with(caret_ox, bw)
        pad_x = 8.0 * world_scale_x
        text_x = bx + pad_x - @scroll_x
        text_cy = by + bh * 0.5

        prev_ox, prev_oy = Zenoo::Window.push_clip_scope(bx + 2.0, by + 1.0, [bw - 4.0, 0.0].max, [bh - 2.0, 0.0].max, local: false, z: @z)
        if is_foc && (rng = selection_range)
          s_x0 = f_font.text_width(@text[0...rng[0]] || "", f_size)
          s_x1 = f_font.text_width(@text[0...rng[1]] || "", f_size)
          sel_h = [f_size.to_f + 4.0, bh - 4.0].min
          Zenoo::Window.draw_rect(text_x + s_x0, by + (bh - sel_h) * 0.5, [s_x1 - s_x0, 1.0].max, sel_h,
                                  color: [72, 152, 242, 110], camera: false, z: @z)
        end

        if @text.empty? && !@placeholder.empty?
          Zenoo::Window.draw_text(text_x, text_cy, @placeholder, size: f_size, color: [120, 132, 155],
                                  valign: :center, camera: false, z: @z)
        elsif !@text.empty?
          Zenoo::Window.draw_text(text_x, text_cy, @text, size: f_size, color: th.text_color,
                                  valign: :center, camera: false, z: @z)
        end

        if is_foc && (((UI.frame - @blink_start_frame) % 60) < 30)
          caret_h = [f_size.to_f + 4.0, bh - 4.0].min
          Zenoo::Window.draw_rect(text_x + caret_ox, by + (bh - caret_h) * 0.5, 1.5, caret_h,
                                  color: th.accent_hover, camera: false, z: @z)
        end
        Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)
      end

      private

      def box_local_bounds
        th = theme
        rw = width
        rh = height
        ox = @label.empty? ? 0.0 : [(@label_width || 110.0), rw * 0.48].min
        bw = [rw - ox, 1.0].max
        [ox, 0.0, bw, rh, th.radius]
      end

      def box_screen_rect
        ox, oy, bw, bh, rad = box_local_bounds
        sx = world_scale_x
        sy = world_scale_y
        [screen_left + ox * sx, screen_top + oy * sy, bw * sx, bh * sy, rad]
      end

      def text_font_and_size
        f_size = (theme.font_size.to_f * world_scale_y).round
        f_size = 8 if f_size < 8
        [Font.default, f_size]
      end

      def has_selection?
        !@sel_anchor.nil? && @sel_anchor != @cursor_pos
      end

      def selection_range
        return nil unless has_selection?
        @sel_anchor < @cursor_pos ? [@sel_anchor, @cursor_pos] : [@cursor_pos, @sel_anchor]
      end

      def selected_text
        rng = selection_range
        rng ? (@text[rng[0]...rng[1]] || "") : ""
      end

      def delete_selection!
        rng = selection_range
        return false unless rng
        @text.slice!(rng[0]...rng[1])
        @cursor_pos = rng[0]
        @sel_anchor = nil
        true
      end

      def replace_selection(str)
        delete_selection!
        @text.insert(@cursor_pos, str)
        @cursor_pos += str.length
      end

      def move_caret_left(shift_down)
        if shift_down
          @sel_anchor ||= @cursor_pos
          @cursor_pos -= 1 if @cursor_pos > 0
        elsif has_selection?
          @cursor_pos = selection_range[0]
          @sel_anchor = nil
        elsif @cursor_pos > 0
          @cursor_pos -= 1
        end
      end

      def move_caret_right(shift_down)
        if shift_down
          @sel_anchor ||= @cursor_pos
          @cursor_pos += 1 if @cursor_pos < @text.length
        elsif has_selection?
          @cursor_pos = selection_range[1]
          @sel_anchor = nil
        elsif @cursor_pos < @text.length
          @cursor_pos += 1
        end
      end

      def ensure_caret_visible
        _bx, _by, bw, _bh, = box_screen_rect
        f_font, f_size = text_font_and_size
        caret_ox = f_font.text_width(@text[0...@cursor_pos] || "", f_size)
        ensure_caret_visible_with(caret_ox, bw)
      end

      def ensure_caret_visible_with(caret_ox, bw)
        pad_x = 8.0 * world_scale_x
        avail_w = [bw - pad_x * 2.0 - 2.0, 10.0].max
        f_font, f_size = text_font_and_size
        total_w = f_font.text_width(@text, f_size)
        max_scroll = [total_w - avail_w, 0.0].max
        if caret_ox < @scroll_x
          @scroll_x = caret_ox
        elsif caret_ox > @scroll_x + avail_w
          @scroll_x = caret_ox - avail_w
        end
        @scroll_x = @scroll_x.clamp(0.0, max_scroll)
      end

      def index_at_mouse_x(mx)
        bx, _by, _bw, _bh, = box_screen_rect
        pad_x = 8.0 * world_scale_x
        click_x = mx - (bx + pad_x - @scroll_x)
        f_font, f_size = text_font_and_size

        best_idx = @text.length
        accum_w = 0.0
        idx = 0
        len = @text.length
        while idx < len
          char_w = f_font.text_width(@text[idx], f_size)
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

    # タブ切り替えバー
    class Tabs < Widget
      attr_reader :items, :selected_index

      def initialize(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 260.0, height: nil, **opts, &block)
        @items          = items.map(&:to_s)
        @selected_index = @items.empty? ? 0 : selected_index.to_i.clamp(0, @items.length - 1)
        @hover_index    = nil
        @on_change_proc = block
        super(x, y, width: width, height: height, **opts)
      end

      def cursor_shape = :hand
      def collider_radius = theme.radius
      def on_change(&block) = (@on_change_proc = block; self)
      def selected_item = @items[@selected_index]

      def items=(val)
        @items = val.map(&:to_s)
        @selected_index = @items.empty? ? 0 : @selected_index.clamp(0, @items.length - 1)
        @hover_index = nil
      end

      def selected_index=(idx)
        @selected_index = @items.empty? ? 0 : idx.to_i.clamp(0, @items.length - 1)
      end

      def on_pointer_move(mx, _my)
        @hover_index = tab_index_at(mx)
      end

      def on_pointer_leave
        @hover_index = nil
      end

      def on_pointer_down(mx, _my)
        super
        idx = tab_index_at(mx)
        if idx && idx != @selected_index
          @selected_index = idx
          @on_change_proc&.call(@selected_index, selected_item)
        end
      end

      def draw_self
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        th = theme
        rad = th.radius

        Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: rad, color: th.track_bg,
                                border_width: 1.0, border_color: th.track_border, camera: false, z: @z)
        return if @items.empty? || rw <= 0.0

        count = @items.length
        tab_w = rw / count.to_f
        i = 0
        while i < count
          tx = rx + i * tab_w
          is_sel = (i == @selected_index)
          is_hov = (i == @hover_index)

          if is_sel || is_hov
            bg = is_sel ? th.bg_active : th.bg_hover
            Zenoo::Window.draw_rect(tx + 2.0, ry + 2.0, [tab_w - 4.0, 2.0].max, [rh - 4.0, 2.0].max,
                                    radius: [rad - 1.0, 2.0].max, color: bg, camera: false, z: @z)
          end
          if is_sel
            Zenoo::Window.draw_rect(tx + 5.0, ry + rh - 3.5, [tab_w - 10.0, 2.0].max, 2.0,
                                    radius: 1.0, color: th.accent_color, camera: false, z: @z)
          end

          tcol = is_sel ? [255, 255, 255] : (is_hov ? th.text_color : th.text_muted)
          Zenoo::Window.draw_text(tx + tab_w * 0.5, ry + rh * 0.5, @items[i],
                                  size: [th.font_size - 1, 10].max, color: tcol, align: :center, valign: :center, camera: false, z: @z)
          i += 1
        end
      end

      private

      def tab_index_at(mx)
        rw = screen_width
        return nil if @items.empty? || rw <= 0.0
        idx = ((mx - screen_left) / (rw / @items.length.to_f)).floor
        (idx >= 0 && idx < @items.length) ? idx : nil
      end
    end

    # 行選択・スクロール対応テーブル
    class Table < Widget
      COL_HDR_BG   = [32, 38, 52].freeze
      COL_HDR_TXT  = [178, 194, 222].freeze
      COL_ROW_EVEN = [255, 255, 255, 9].freeze
      COL_SEP      = [255, 255, 255, 22].freeze
      COL_VAL_NUM  = [130, 210, 255].freeze
      COL_VAL_BOOL = [245, 195, 110].freeze
      COL_VAL_SYM  = [210, 160, 255].freeze
      COL_VAL_NIL  = [130, 140, 160].freeze

      attr_accessor :selectable, :label
      attr_reader :columns, :rows, :selected_index, :scroll_y

      def initialize(columns = [], rows = [], selected_index = nil, x = 0.0, y = 0.0,
                     width: 320.0, height: 180.0, item_height: 20.0, selectable: true, label: "", **opts, &block)
        @columns        = columns.dup
        @rows           = rows.dup
        @item_height    = [item_height.to_f, 14.0].max
        @selectable     = !!selectable
        @label          = label.to_s
        @scroll_y       = 0.0
        @hover_index    = nil
        @on_change_proc = block
        @selected_index = normalize_selected_index(selected_index)
        super(x, y, width: width, height: height, **opts)
      end

      def cursor_shape = (@selectable && !@hover_index.nil?) ? :hand : :arrow
      def on_change(&block) = (@on_change_proc = block; self)
      def selected_row = (@selected_index && @selected_index >= 0) ? @rows[@selected_index] : nil

      def columns=(val)
        @columns = val.dup
      end

      def rows=(val)
        @rows = val.dup
        @selected_index = normalize_selected_index(@selected_index)
        @scroll_y = @scroll_y.clamp(0.0, max_scroll_y)
        @hover_index = nil if @hover_index && @hover_index >= @rows.length
      end

      def selected_index=(idx)
        @selected_index = normalize_selected_index(idx)
      end

      def set_default_collider
        ox, oy, tw, th_b, rad = table_local_bounds
        set_collider(:rect, width: tw, height: th_b,
                     offset_x: ox + tw * 0.5, offset_y: oy + th_b * 0.5,
                     at: :top_left, radius: rad)
      end

      def sync_collider_shape
        col = @collider_shape
        return unless col && col.shape_type == Collision::TYPE_RECT
        ox, oy, tw, th_b, rad = table_local_bounds
        col.width = tw
        col.height = th_b
        col.offset_x = ox + tw * 0.5
        col.offset_y = oy + th_b * 0.5
        col.radius = rad
      end

      def on_pointer_move(mx, my)
        @hover_index = @selectable ? row_index_at(mx, my) : nil
      end

      def on_pointer_leave
        @hover_index = nil
      end

      def on_wheel(dy)
        max_s = max_scroll_y
        return false if max_s <= 0.0
        @scroll_y = (@scroll_y - dy * @item_height * 1.5).clamp(0.0, max_s)
        true
      end

      def on_pointer_down(mx, my)
        super
        return unless @selectable
        idx = row_index_at(mx, my)
        if idx && idx != @selected_index
          @selected_index = idx
          @on_change_proc&.call(@selected_index, @rows[@selected_index])
        end
      end

      def draw_self
        th = theme
        sx = world_scale_x
        sy = world_scale_y
        tx, ty, tw, th_b, rad, header_h, body_x, body_y, body_w, body_h, scroll_w = table_metrics

        unless @label.empty?
          Zenoo::Window.draw_text(screen_left, screen_top + 10.0 * sy, @label,
                                  size: [th.font_size - 1, 10].max, color: th.text_muted, valign: :center, camera: false, z: @z)
        end

        Zenoo::Window.draw_rect(tx, ty, tw, th_b, radius: rad, color: th.track_bg,
                                border_width: 1.0, border_color: th.track_border, camera: false, z: @z)

        col_names, col_widths = resolve_columns(body_w)
        draw_header(tx + 2.0 * sx, ty + 2.0 * sy, tw - 4.0 * sx, header_h, col_names, col_widths, sy)

        @scroll_y = @scroll_y.clamp(0.0, max_scroll_y)
        row_h = @item_height * sy
        f_size = [(th.font_size - 2) * sy, 10].max.round

        prev_ox, prev_oy = Zenoo::Window.push_clip_scope(body_x, body_y, body_w, body_h, local: false, z: @z)
        if !@rows.empty? && body_h > 0.0
          first_idx = [(@scroll_y / row_h).floor, 0].max
          last_idx  = [((@scroll_y + body_h) / row_h).ceil, @rows.length - 1].min
          i = first_idx
          while i <= last_idx
            iy = body_y + i * row_h - @scroll_y
            draw_row(th, body_x, iy, body_w, row_h, @rows[i], col_widths,
                     i == @selected_index, i == @hover_index, i.even?, f_size)
            i += 1
          end
        end
        Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)

        if scroll_w > 0.0
          max_s = max_scroll_y
          total_h = @rows.length * row_h
          track_x = tx + tw - scroll_w + 1.0
          thumb_h = [body_h * (body_h / [total_h, 1.0].max), 16.0].max
          ratio = max_s > 0.0 ? (@scroll_y / max_s) : 0.0
          thumb_y = body_y + (body_h - thumb_h) * ratio
          Zenoo::Window.draw_rect(track_x, thumb_y, [scroll_w - 4.0, 3.0].max, thumb_h,
                                  radius: 2.0, color: th.accent_color, camera: false, z: @z)
        end
      end

      private

      def normalize_selected_index(idx)
        return nil if idx.nil? || @rows.empty?
        i = idx.to_i
        (i >= 0 && i < @rows.length) ? i : nil
      end

      def table_local_bounds
        th = theme
        label_h = @label.empty? ? 0.0 : 20.0
        th_b = [height - label_h, 24.0].max
        [0.0, label_h, [width, 1.0].max, th_b, th.radius]
      end

      def table_metrics
        ox, oy, tw_l, th_l, rad = table_local_bounds
        sx = world_scale_x
        sy = world_scale_y
        tx = screen_left + ox * sx
        ty = screen_top + oy * sy
        tw = tw_l * sx
        th_b = th_l * sy
        header_h = [22.0 * sy, th_b * 0.45].min
        body_y = ty + header_h + 3.0 * sy
        body_h = [th_b - header_h - 5.0 * sy, 1.0].max
        total_h = @rows.length * (@item_height * sy)
        scroll_w = (total_h > body_h) ? (8.0 * sx) : 0.0
        body_x = tx + 2.0 * sx
        body_w = [tw - scroll_w - 4.0 * sx, 1.0].max
        [tx, ty, tw, th_b, rad, header_h, body_x, body_y, body_w, body_h, scroll_w]
      end

      def max_scroll_y
        _tx, _ty, _tw, _th_b, _rad, _hh, _bx, _by, _bw, body_h, = table_metrics
        total_h = @rows.length * (@item_height * world_scale_y)
        [total_h - body_h, 0.0].max
      end

      def row_index_at(mx, my)
        _tx, _ty, _tw, _th_b, _rad, _hh, body_x, body_y, body_w, body_h, = table_metrics
        return nil if @rows.empty? || mx < body_x || mx > body_x + body_w || my < body_y || my > body_y + body_h
        row_h = @item_height * world_scale_y
        idx = ((my - body_y + @scroll_y) / row_h).floor
        (idx >= 0 && idx < @rows.length) ? idx : nil
      end

      def resolve_columns(content_w)
        names = []
        widths = []
        fixed_total = 0.0
        flex_count = 0
        len = @columns.length
        i = 0
        while i < len
          col = @columns[i]
          if col.is_a?(Array)
            cname = col[0].to_s
            cw = col[1] ? col[1].to_f : nil
          elsif col.is_a?(Hash)
            cname = (col[:name] || col["name"]).to_s
            cw = (col[:width] || col["width"]) ? (col[:width] || col["width"]).to_f : nil
          else
            cname = col.to_s
            cw = nil
          end
          names << cname
          if cw && cw > 0.0
            widths << cw
            fixed_total += cw
          else
            widths << nil
            flex_count += 1
          end
          i += 1
        end
        flex_w = flex_count > 0 ? [((content_w - fixed_total) / flex_count.to_f), 20.0].max : 0.0
        i = 0
        while i < len
          widths[i] ||= flex_w
          i += 1
        end
        [names, widths]
      end

      def draw_header(hx, hy, hw, hh, col_names, col_widths, sy)
        Zenoo::Window.draw_rect(hx, hy, hw, hh, radius: 2.0, color: COL_HDR_BG, camera: false, z: @z)
        Zenoo::Window.draw_rect(hx, hy + hh - 1.0, hw, 1.0, color: COL_SEP, camera: false, z: @z)

        f_size = [11 * sy, 9].max.round
        cx = hx
        len = col_names.length
        i = 0
        while i < len
          cw = col_widths[i]
          txt = truncate_to_width(col_names[i], cw - 10.0, f_size)
          Zenoo::Window.draw_text(cx + 5.0, hy + hh * 0.5, txt, size: f_size, color: COL_HDR_TXT, valign: :center, camera: false, z: @z)
          Zenoo::Window.draw_rect(cx + cw - 1.0, hy + 2.0, 1.0, [hh - 4.0, 1.0].max, color: COL_SEP, camera: false, z: @z) if i < len - 1
          cx += cw
          i += 1
        end
      end

      def draw_row(th, rx, ry, rw, rh, row_data, col_widths, is_sel, is_hov, is_even, f_size)
        if is_sel
          Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: 2.0, color: th.bg_active, camera: false, z: @z)
          Zenoo::Window.draw_rect(rx + 1.0, ry + 2.0, 2.5, [rh - 4.0, 2.0].max, radius: 1.0, color: th.accent_color, camera: false, z: @z)
        elsif is_hov
          Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: 2.0, color: th.bg_hover, camera: false, z: @z)
        elsif is_even
          Zenoo::Window.draw_rect(rx, ry, rw, rh, radius: 2.0, color: COL_ROW_EVEN, camera: false, z: @z)
        end

        cx = rx
        len = col_widths.length
        i = 0
        while i < len
          cw = col_widths[i]
          val = row_data.is_a?(Array) ? row_data[i] : nil
          val_col = value_color(th, val, is_sel || is_hov)
          val_str = val.is_a?(String) ? val : (val.nil? ? "nil" : val.to_s)
          txt = truncate_to_width(val_str, cw - 10.0, f_size)
          Zenoo::Window.draw_text(cx + 6.0, ry + rh * 0.5, txt, size: f_size, color: val_col, valign: :center, camera: false, z: @z)
          Zenoo::Window.draw_rect(cx + cw - 1.0, ry + 1.0, 1.0, [rh - 2.0, 1.0].max, color: COL_SEP, camera: false, z: @z) if i < len - 1
          cx += cw
          i += 1
        end
      end

      def value_color(th, val, highlighted)
        return [255, 255, 255] if highlighted
        if val.is_a?(Numeric)
          COL_VAL_NUM
        elsif val == true || val == false
          COL_VAL_BOOL
        elsif val.is_a?(Symbol)
          COL_VAL_SYM
        elsif val.nil?
          COL_VAL_NIL
        else
          th.text_color
        end
      end

      def truncate_to_width(str, max_w, f_size)
        return "" if str.empty? || max_w <= 4.0
        f = Font.default
        return str if f.text_width(str, f_size) <= max_w
        ell = "..."
        ew = f.text_width(ell, f_size)
        return "" if ew > max_w
        limit = max_w - ew
        acc = 0.0
        cut = 0
        len = str.length
        while cut < len
          cw = f.text_width(str[cut], f_size)
          break if acc + cw > limit
          acc += cw
          cut += 1
        end
        "#{str[0...cut]}#{ell}"
      end
    end

    # フレーム実行時間の積み上げヒストグラム表示ウィジェット
    class ProfileGraph < Widget
      attr_accessor :max_ms, :show_legend

      def initialize(x = 0.0, y = 0.0, width: 290.0, height: 80.0, max_ms: 33.33, show_legend: true, **opts)
        @max_ms      = max_ms.to_f > 0.0 ? max_ms.to_f : 33.33
        @show_legend = show_legend
        @hover_bar   = nil
        @bar_color_cache = {}
        super(x, y, width: width, height: height, **opts)
      end

      def on_pointer_move(mx, my)
        rx = screen_left
        ry = screen_top
        rw = screen_width
        gh = graph_height
        if mx >= rx && mx <= rx + rw && my >= ry && my <= ry + gh
          bar_w = 3.0
          max_bars = ((rw - 4.0) / bar_w).to_i
          hist = Profiler.history
          vis_len = [hist.length, max_bars].min
          dist = (rx + rw - 2.0) - mx
          if dist >= 0.0 && vis_len > 0
            idx_end = (dist / bar_w).to_i
            @hover_bar = idx_end < vis_len ? (vis_len - 1 - idx_end) : nil
          else
            @hover_bar = nil
          end
        else
          @hover_bar = nil
        end
      end

      def on_pointer_leave
        @hover_bar = nil
      end

      def draw_self
        rx = screen_left
        ry = screen_top
        rw = screen_width
        gh = graph_height
        th = theme

        Zenoo::Window.draw_rect(rx, ry, rw, gh, radius: th.radius, color: [24, 24, 26, 230],
                                border_width: 1.0, border_color: [55, 55, 60, 200], camera: false, z: @z)

        draw_guideline(rx, ry, rw, gh, 16.666, "16.6ms (60fps)", [80, 160, 180, 140])
        draw_guideline(rx, ry, rw, gh, 33.333, "33.3ms (30fps)", [180, 80, 80, 140]) if @max_ms > 33.33

        bar_w = 3.0
        max_bars = ((rw - 4.0) / bar_w).to_i
        hist = Profiler.history
        vis_start = [hist.length - max_bars, 0].max
        vis_len = max_bars > 0 ? (hist.length - vis_start) : 0

        if @hover_bar && @hover_bar >= 0 && @hover_bar < vis_len
          hbx = rx + rw - 2.0 - (vis_len - @hover_bar) * bar_w
          Zenoo::Window.draw_rect(hbx, ry + 1.0, bar_w, [gh - 2.0, 1.0].max, color: [255, 255, 255, 60], camera: false, z: @z)
        end

        draw_bars(rx, ry, rw, gh, bar_w, hist, vis_start, vis_len)
        draw_header(rx, ry, rw, hist, vis_start, vis_len)
        draw_legend(rx, ry, rw, gh) if @show_legend
      end

      private

      def graph_height
        @show_legend ? [screen_height * 0.45, 70.0].max.clamp(40.0, screen_height) : screen_height
      end

      def draw_guideline(rx, ry, rw, gh, ms, label_text, col)
        gy = ry + gh - (ms / @max_ms) * gh
        return unless gy >= ry && gy <= ry + gh
        Zenoo::Window.draw_line(rx + 1.0, gy, rx + rw - 1.0, gy, color: col, width: 1.0, camera: false, z: @z)
        Zenoo::Window.draw_text(rx + 4.0, gy - 12.0, label_text, size: 10, color: col, camera: false, z: @z)
      end

      def draw_bars(rx, ry, rw, gh, bar_w, hist, vis_start, vis_len)
        return if vis_len <= 0
        ox = Zenoo::Window.__offset_x
        oy = Zenoo::Window.__offset_y
        bw = [bar_w - 0.5, 1.0].max
        cats = Profiler.categories
        bars_batch = []
        rect_count = 0

        vi = 0
        while vi < vis_len
          frame = hist[vis_start + vi]
          bx = rx + rw - 2.0 - (vis_len - vi) * bar_w
          if bx >= rx + 1.0
            abx  = bx + ox
            abx2 = abx + bw
            cur_y = ry + gh - 1.0
            ci = 0
            while ci < cats.length
              cat = cats[ci]
              ms = frame[cat]
              if ms && ms > 0.0001
                h_cat = (ms.to_f / @max_ms) * gh
                if h_cat >= 0.5
                  avail_h = cur_y - (ry + 1.0)
                  break if avail_h <= 0.0
                  h_cat = avail_h if h_cat > avail_h
                  top_y = cur_y - h_cat
                  col = (@bar_color_cache[cat] ||= begin
                    nc = Backend.normalize_color(Profiler.color_for(cat))
                    [nc[0].to_f, nc[1].to_f, nc[2].to_f, nc[3].to_f]
                  end)
                  cr, cg, cb, ca = col
                  atop_y = top_y + oy
                  acur_y = cur_y + oy
                  bars_batch.push(
                    abx, atop_y, cr, cg, cb, ca,
                    abx, acur_y, cr, cg, cb, ca,
                    abx2, atop_y, cr, cg, cb, ca,
                    abx2, atop_y, cr, cg, cb, ca,
                    abx, acur_y, cr, cg, cb, ca,
                    abx2, acur_y, cr, cg, cb, ca
                  )
                  rect_count += 1
                  cur_y = top_y
                end
              end
              ci += 1
            end
          end
          vi += 1
        end

        if rect_count > 0
          Backend.enqueue_draw(
            Backend::Pipelines::TRIANGLES,
            bars_batch.pack("f*"),
            rect_count * 6,
            shader: Zenoo::Window.flat_primitive_shader
          )
        end
      end

      def draw_header(rx, ry, rw, hist, vis_start, vis_len)
        total_last = Profiler.last_total_ms
        n = [vis_len, 30].min
        avg_sum = 0.0
        if n > 0
          i = vis_len - n
          while i < vis_len
            hist[vis_start + i].each_value { |v| avg_sum += v }
            i += 1
          end
        end
        avg_last = n > 0 ? (avg_sum / n.to_f) : 0.0
        status = "Avg: #{avg_last.round(1)}ms | Last: #{total_last.round(1)}ms | #{Zenoo::Window.fps.round(0)} FPS"
        Zenoo::Window.draw_text(rx + rw - 6.0, ry + 4.0, status, size: 11, color: [200, 200, 200], align: :right, camera: false, z: @z)

        if @hover_bar && @hover_bar >= 0 && @hover_bar < vis_len
          tf = hist[vis_start + @hover_bar]
          tot = 0.0
          parts = []
          tf.each do |k, v|
            tot += v
            parts << "#{k}:#{v.round(1)}"
          end
          Zenoo::Window.draw_text(rx + 6.0, ry + 4.0, "Frame: #{tot.round(2)}ms (#{parts.join(', ')})",
                                  size: 11, color: [255, 240, 100], camera: false, z: @z)
        end
      end

      def draw_legend(rx, ry, rw, gh)
        avg_map = Profiler.average_times(30)
        total_avg = 0.0001
        avg_map.each_value { |v| total_avg += v }
        cats = Profiler.categories.sort_by { |c| -(avg_map[c] || 0.0) }
        legend_y = ry + gh + 8.0
        max_y = screen_top + screen_height - 14.0

        i = 0
        while i < cats.length
          break if legend_y > max_y
          cat = cats[i]
          avg_ms = avg_map[cat] || 0.0
          last_ms = Profiler.last_times[cat] || 0.0
          if avg_ms >= 0.005 || last_ms >= 0.005
            pct = ((avg_ms / total_avg) * 100.0).round(0)
            cat_col = Profiler.color_for(cat)
            Zenoo::Window.draw_rect(rx + 4.0, legend_y + 2.0, 8.0, 8.0, color: cat_col, camera: false, z: @z)
            Zenoo::Window.draw_text(rx + 16.0, legend_y, cat.to_s, size: 11, color: [200, 205, 210], camera: false, z: @z)

            val_100 = (avg_ms * 100).to_i
            val_dec = val_100 % 100
            val_str = "#{val_100 / 100}.#{val_dec < 10 ? '0' : ''}#{val_dec}ms"
            Zenoo::Window.draw_text(rx + rw - 4.0, legend_y, "#{val_str} (#{pct}%)",
                                    size: 11, color: [160, 210, 240], align: :right, camera: false, z: @z)
            legend_y += 15.0
          end
          i += 1
        end
      end
    end
  end
end

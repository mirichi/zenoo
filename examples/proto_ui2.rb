# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo 新 GUI プロトタイプ (UI2)
# ------------------------------------------------------------------------------
# コンセプト:
#   - Sprite ベースの保持モード一本化（Stage が入力・フォーカス・ホバーを統括）
#   - 薄い Widget 基底クラス + include による機能合成 (Clickable / Draggable / Focusable / Scrollable)
#   - Theme が「配色」と「密度・寸法（高さ/余白/フォントサイズ/スライダー形式）」の両方を管理
#   - ツール標準は適度にコンパクトな 1 段コントロール、Theme 差し替えでゆったり UI にも対応
#   - Builder DSL (win.vbox { |b| b.button(...) }) の書き味を維持
# ==============================================================================

module Zenoo
  module UI2
    # --------------------------------------------------------------------------
    # 0. テーマ (配色 + 密度・寸法)
    # --------------------------------------------------------------------------
    class Theme
      attr_accessor :bg_normal, :bg_hover, :bg_active,
                    :border_normal, :border_hover,
                    :win_bg, :win_border, :win_border_active,
                    :text_color, :text_muted, :accent_color, :accent_hover,
                    :track_bg, :track_border,
                    :font_size, :control_height, :header_height,
                    :padding, :gap, :radius, :slider_style

      def initialize(preset = :compact, **overrides)
        if preset == :relaxed
          apply_relaxed
        else
          apply_compact
        end
        overrides.each { |k, v| public_send(:"#{k}=", v) }
      end

      # ツール向けの引き締まった標準テーマ（過度な詰め込みではなく見やすいコンパクトさ）
      def apply_compact
        @bg_normal         = [40, 46, 60]
        @bg_hover          = [54, 64, 84]
        @bg_active         = [68, 84, 114]
        @border_normal     = [74, 86, 110]
        @border_hover      = [110, 175, 245]
        @win_bg            = [24, 28, 38, 242]
        @win_border        = [68, 80, 106]
        @win_border_active = [105, 165, 245]
        @text_color        = [236, 240, 248]
        @text_muted        = [180, 192, 212]
        @accent_color      = [72, 152, 242]
        @accent_hover      = [105, 180, 255]
        @track_bg          = [18, 22, 30]
        @track_border      = [58, 68, 88]

        @font_size      = 14
        @control_height = 24.0
        @header_height  = 26.0
        @padding        = 5.0
        @gap            = 3.0
        @radius         = 4.0
        @slider_style   = :inline
      end

      # ゲーム設定画面など向けのゆったりテーマ
      def apply_relaxed
        apply_compact
        @font_size      = 15
        @control_height = 34.0
        @header_height  = 34.0
        @padding        = 14.0
        @gap            = 10.0
        @radius         = 7.0
        @slider_style   = :stacked
      end
    end

    @frame = 0
    @theme = Theme.new(:compact)
    class << self
      attr_accessor :frame

      def theme(preset = nil, **overrides)
        if preset.is_a?(Theme)
          @theme = preset
        elsif preset.is_a?(Symbol)
          @theme = Theme.new(preset, **overrides)
        elsif !overrides.empty?
          overrides.each { |k, v| @theme.public_send(:"#{k}=", v) }
        end
        @theme
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
      end
    end

    # --------------------------------------------------------------------------
    # 1. 最小基底クラス: Widget < Sprite
    # --------------------------------------------------------------------------
    class Widget < Sprite
      attr_accessor :enabled, :interactive, :clip_children, :flex

      def initialize(x = 0.0, y = 0.0, width: 100.0, height: nil,
                     anchor: :top_left, pivot: :center, z: 0.0, camera: false,
                     enabled: true, interactive: true, clip_children: false,
                     flex: nil, theme: nil, **opts)
        super(x, y, nil, width: width, height: height, anchor: anchor, pivot: pivot, z: z, camera: camera, **opts)
        @enabled       = enabled
        @interactive   = interactive
        @clip_children = clip_children
        @flex          = flex ? flex.to_f : nil
        @theme         = theme.is_a?(Symbol) ? Theme.new(theme) : theme
        @on_draw_proc  = nil
      end

      def theme
        @theme || (@parent.is_a?(Widget) ? @parent.theme : UI2.theme)
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
        mark_layout_dirty!
      end

      def stage
        cur = self
        while cur
          return cur if cur.is_a?(Stage)
          cur = cur.parent
        end
        nil
      end

      def hovered?
        st = stage
        st ? st.hovered?(self) : false
      end

      def focused?
        st = stage
        st ? st.focused?(self) : false
      end

      def on_draw(&block)
        @on_draw_proc = block
        self
      end

      # 明示 height 未指定時はテーマ基準の標準高さを返す
      def height
        @height || theme.control_height
      end

      # 画面上の描画矩形 (Pivot・Scale 反映)
      def screen_left   = world_pivot_x - @pivot_x * width * world_scale_x
      def screen_top    = world_pivot_y - @pivot_y * height * world_scale_y
      def screen_width  = width * world_scale_x
      def screen_height = height * world_scale_y

      def clip_bounds
        [screen_left, screen_top, screen_width, screen_height]
      end

      def add(child)
        return nil unless child
        child.parent = self
        child
      end

      def <<(child)
        add(child)
        self
      end

      def draw
        return if @vanished || !@visible

        ensure_layout
        if @on_draw_proc
          @on_draw_proc.call(self)
        else
          draw_self
        end

        return unless @children
        if @clip_children
          cx, cy, cw, ch = clip_bounds
          if cw > 0.0 && ch > 0.0
            prev_ox, prev_oy = Zenoo::Window.push_clip_scope(cx, cy, cw, ch, local: false, z: @z)
            draw_children
            Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)
          end
        else
          draw_children
        end
      end

      def draw_self
        super if @image
      end

      # 自身への当たり判定 (回転なしなら高速 AABB、回転ありなら逆変換)
      def hit_test_self?(px, py)
        return false if @vanished || !@visible || !@enabled || !@interactive

        if world_angle == 0.0
          l = screen_left
          t = screen_top
          px >= l && px <= (l + screen_width) && py >= t && py <= (t + screen_height)
        else
          dx = px - world_pivot_x
          dy = py - world_pivot_y
          cos = world_cos
          sin = world_sin
          rx = dx * cos + dy * sin
          ry = -dx * sin + dy * cos
          sx = world_scale_x
          sy = world_scale_y
          lx = (sx.abs > 0.0001 ? rx / sx : rx) + @pivot_x * width
          ly = (sy.abs > 0.0001 ? ry / sy : ry) + @pivot_y * height
          lx >= 0.0 && lx <= width && ly >= 0.0 && ly <= height
        end
      end

      # 手前(配列末尾)から奥(配列先頭)へ最前面のヒット対象を探索
      def find_hit(px, py)
        return nil if @vanished || !@visible || !@enabled

        if (ch_list = @children)
          can_enter_children = true
          if @clip_children
            cx, cy, cw, ch = clip_bounds
            can_enter_children = px >= cx && px <= (cx + cw) && py >= cy && py <= (cy + ch)
          end

          if can_enter_children
            i = ch_list.length - 1
            while i >= 0
              c = ch_list[i]
              if c.is_a?(Widget) && !c.vanished?
                hit = c.find_hit(px, py)
                return hit if hit
              end
              i -= 1
            end
          end
        end

        hit_test_self?(px, py) ? self : nil
      end

      # 親レイアウトへの変更通知
      def width=(v)
        old_w = width
        super(v)
        @parent.mark_layout_dirty! if width != old_w && @parent.is_a?(Widget)
      end

      def height=(v)
        old_h = height
        super(v)
        @parent.mark_layout_dirty! if height != old_h && @parent.is_a?(Widget)
      end

      def visible=(v)
        old_v = @visible
        super(v)
        if @visible != old_v
          mark_layout_dirty!
          @parent.mark_layout_dirty! if @parent.is_a?(Widget)
        end
      end

      def __add_child_internal(child)
        super(child)
        mark_layout_dirty!
      end

      def __remove_child_internal(child)
        super(child)
        mark_layout_dirty!
      end

      def bring_child_to_front!(child)
        return false unless @children && @children.include?(child)
        return true if @children.last.equal?(child)
        @children.delete(child)
        @children << child
        true
      end

      # --- イベント受け口 (Module / サブクラス向けフック) ---
      def ensure_layout;                end
      def mark_layout_dirty!;           end
      def cursor_shape                 = :arrow
      def can_focus?                   = false
      def bring_to_front_on_click?     = false
      def on_pointer_enter;            end
      def on_pointer_leave;            end
      def on_pointer_down(_mx, _my);   end
      def on_pointer_drag(_mx, _my);   end
      def on_pointer_up(_mx, _my, _in); end
      def on_wheel(_dy)                = false
      def on_focus;                    end
      def on_blur;                     end
    end

    # --------------------------------------------------------------------------
    # 2. 機能 Module 群 (include で組み合わせ可能)
    # --------------------------------------------------------------------------
    module Clickable
      def pressed? = !!@pressed
      def clicked? = @clicked_frame == UI2.frame
      def cursor_shape = :hand

      def on_click(&block)
        @on_click_proc = block
        self
      end

      def on_pointer_down(mx, my)
        @pressed = true
        super
      end

      def on_pointer_up(mx, my, inside)
        was_pressed = @pressed
        @pressed = false
        trigger_click! if was_pressed && inside && @enabled
        super
      end

      def trigger_click!
        @clicked_frame = UI2.frame
        @on_click_proc&.call(self)
      end
    end

    module Draggable
      attr_accessor :drag_target
      attr_reader :drag_offset_x, :drag_offset_y
      def dragging? = !!@dragging

      def on_drag_start(_mx, _my); end
      def on_drag(_dx, _dy);       end
      def on_drag_end;             end

      def on_pointer_down(mx, my)
        @dragging = true
        @drag_start_mx = mx
        @drag_start_my = my
        @prev_drag_x = mx
        @prev_drag_y = my
        @drag_offset_x = 0.0
        @drag_offset_y = 0.0
        on_drag_start(mx, my)
        super
      end

      def on_pointer_drag(mx, my)
        if @dragging
          dx = mx - @prev_drag_x
          dy = my - @prev_drag_y
          @prev_drag_x = mx
          @prev_drag_y = my
          @drag_offset_x = mx - @drag_start_mx
          @drag_offset_y = my - @drag_start_my
          if (target = @drag_target)
            target.x += dx
            target.y += dy
          elsif @drag_target.nil? && !instance_variable_defined?(:@drag_target)
            self.x += dx
            self.y += dy
          end
          on_drag(dx, dy)
        end
        super
      end

      def on_pointer_up(mx, my, inside)
        if @dragging
          @dragging = false
          on_drag_end
        end
        super
      end
    end

    module Focusable
      def can_focus? = @enabled
      def focus!     = (stage&.set_focus(self); self)
      def blur!      = (stage&.set_focus(nil) if focused?; self)
    end

    module Scrollable
      attr_reader :scroll_y

      def init_scrollable
        @scroll_y = 0.0
        @clip_children = true
      end

      def scroll_y=(val)
        max_s = max_scroll_y
        v = val.to_f
        v = 0.0 if v < 0.0
        v = max_s if v > max_s
        if @scroll_y != v
          @scroll_y = v
          mark_layout_dirty!
        end
      end

      def max_scroll_y
        [content_height - height, 0.0].max
      end

      def scroll_offset_y
        @scroll_y || 0.0
      end

      def on_wheel(dy)
        return false if max_scroll_y <= 0.0
        self.scroll_y = (@scroll_y || 0.0) - dy * 28.0
        true
      end
    end

    # --------------------------------------------------------------------------
    # 3. 司令塔: Stage (UI ツリーのルート)
    # --------------------------------------------------------------------------
    class Stage < Widget
      attr_reader :hovered_widget, :active_widget, :focused_widget

      def initialize(width: nil, height: nil, theme: nil)
        @auto_w = width.nil?
        @auto_h = height.nil?
        super(0.0, 0.0, width: width || Zenoo::Window.width, height: height || Zenoo::Window.height, interactive: false, theme: theme)
        @hovered_widget = nil
        @active_widget  = nil
        @focused_widget = nil
      end

      def hovered?(w) = @hovered_widget.equal?(w)
      def focused?(w) = @focused_widget.equal?(w)

      def set_focus(w)
        return if @focused_widget.equal?(w)
        @focused_widget&.on_blur
        @focused_widget = w
        @focused_widget&.on_focus
      end

      def update
        return if @vanished || !@visible
        UI2.frame += 1

        self.width  = Zenoo::Window.width.to_f  if @auto_w && Zenoo::Window.width > 0
        self.height = Zenoo::Window.height.to_f if @auto_h && Zenoo::Window.height > 0

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        down = Input.mouse_pressed?(:left)
        push = Input.mouse_push?(:left)
        rel  = Input.mouse_release?(:left)

        if @active_widget
          Input.consume_mouse!
          inside = @active_widget.hit_test_self?(mx, my)
          update_hover(inside ? @active_widget : nil)
          if rel || !down
            act = @active_widget
            @active_widget = nil
            act.on_pointer_up(mx, my, inside)
          else
            @active_widget.on_pointer_drag(mx, my)
          end
        else
          hit = find_hit(mx, my)
          update_hover(hit)

          if hit
            wheel = Input.mouse_wheel_y.to_f
            if wheel != 0.0
              cur = hit
              while cur && cur.is_a?(Widget)
                break if cur.on_wheel(wheel)
                cur = cur.parent
              end
            end

            if push
              Input.consume_mouse!
              bring_ancestor_to_front(hit)
              set_focus(hit.can_focus? ? hit : nil)
              @active_widget = hit
              hit.on_pointer_down(mx, my)
              if rel
                @active_widget = nil
                hit.on_pointer_up(mx, my, true)
              end
            end
          elsif push
            set_focus(nil)
          end
        end

        cur_shape = @hovered_widget ? @hovered_widget.cursor_shape : :arrow
        Zenoo::UI.set_mouse_cursor(cur_shape)

        super
      end

      private

      def update_hover(new_hit)
        return if @hovered_widget.equal?(new_hit)
        @hovered_widget&.on_pointer_leave
        @hovered_widget = new_hit
        @hovered_widget&.on_pointer_enter
      end

      def bring_ancestor_to_front(w)
        cur = w
        while cur && cur.is_a?(Widget)
          if cur.bring_to_front_on_click? && cur.parent.is_a?(Widget)
            cur.parent.bring_child_to_front!(cur)
          end
          cur = cur.parent
        end
      end
    end

    # --------------------------------------------------------------------------
    # 4. シンプルなレイアウトコンテナ: Box / VBox / HBox / ScrollView
    # --------------------------------------------------------------------------
    class Box < Widget
      attr_reader :direction, :align

      def initialize(x = 0.0, y = 0.0, width: 200.0, height: 200.0,
                     direction: :column, padding: nil, gap: nil, align: :stretch,
                     clip_children: false, interactive: false, **opts, &block)
        @direction    = direction
        @explicit_gap = gap ? gap.to_f : nil
        @explicit_pad = padding ? padding.to_f : nil
        @align        = align
        @layout_dirty = true
        super(x, y, width: width, height: height, clip_children: clip_children, interactive: interactive, **opts)
        yield(self) if block
      end

      def gap     = @explicit_gap || theme.gap
      def padding = @explicit_pad || theme.padding

      def mark_layout_dirty!
        @layout_dirty = true
      end

      def width=(v)
        old_w = width
        super(v)
        @layout_dirty = true if width != old_w
      end

      def height=(v)
        old_h = height
        super(v)
        @layout_dirty = true if height != old_h
      end

      def scroll_offset_y
        0.0
      end

      def ensure_layout
        perform_layout if @layout_dirty
      end

      def update
        ensure_layout
        super
      end

      def content_height
        pad = padding
        g   = gap
        return pad * 2.0 unless @children
        sum = 0.0
        count = 0
        i = 0
        while i < @children.length
          c = @children[i]
          if c.is_a?(Widget) && c.visible && !c.vanished?
            count += 1
            sum = (@direction == :column) ? (sum + c.height) : [sum, c.height].max
          end
          i += 1
        end
        pad * 2.0 + sum + ((@direction == :column && count > 1) ? g * (count - 1) : 0.0)
      end

      def perform_layout
        @layout_dirty = false
        ch = @children
        return unless ch && !ch.empty?

        pad = padding
        g   = gap
        inner_w = [width - pad * 2.0, 0.0].max
        inner_h = [height - pad * 2.0, 0.0].max
        is_row = (@direction == :row)
        main_avail  = is_row ? inner_w : inner_h
        cross_avail = is_row ? inner_h : inner_w

        vis_count = 0
        fixed_main = 0.0
        total_flex = 0.0
        i = 0
        while i < ch.length
          c = ch[i]
          if c.is_a?(Widget) && c.visible && !c.vanished?
            vis_count += 1
            if @align == :stretch
              is_row ? (c.height = cross_avail) : (c.width = cross_avail)
            end
            if c.flex && c.flex > 0.0
              total_flex += c.flex
            else
              fixed_main += is_row ? c.width : c.height
            end
          end
          i += 1
        end
        return if vis_count == 0

        gaps = vis_count > 1 ? g * (vis_count - 1) : 0.0
        rem = [main_avail - fixed_main - gaps, 0.0].max

        cursor = pad - (is_row ? 0.0 : scroll_offset_y)
        pax = @anchor_x * width
        pay = @anchor_y * height

        i = 0
        while i < ch.length
          c = ch[i]
          if c.is_a?(Widget) && c.visible && !c.vanished?
            if c.flex && c.flex > 0.0 && total_flex > 0.0
              alloc = rem * (c.flex / total_flex)
              is_row ? (c.width = alloc) : (c.height = alloc)
            end

            c_cross = is_row ? c.height : c.width
            cross_pos = pad
            if @align == :center
              cross_pos += (cross_avail - c_cross) * 0.5
            elsif @align == :end
              cross_pos += (cross_avail - c_cross)
            end

            ox = is_row ? cursor : cross_pos
            oy = is_row ? cross_pos : cursor
            c.x = ox - pax + c.anchor_x * c.width
            c.y = oy - pay + c.anchor_y * c.height

            cursor += (is_row ? c.width : c.height) + g
          end
          i += 1
        end

        @layout_dirty = false
      end
    end

    class VBox < Box
      def initialize(x = 0.0, y = 0.0, **opts, &block)
        super(x, y, direction: :column, **opts, &block)
      end
    end

    class HBox < Box
      def initialize(x = 0.0, y = 0.0, **opts, &block)
        super(x, y, direction: :row, **opts, &block)
      end
    end

    class ScrollView < VBox
      include Scrollable

      def initialize(x = 0.0, y = 0.0, padding: nil, gap: nil, **opts, &block)
        init_scrollable
        super(x, y, padding: padding, gap: gap, clip_children: true, interactive: true, **opts, &block)
      end

      def draw_self
        th = theme
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: th.radius, color: th.track_bg, border_width: 1, border_color: th.track_border, camera: false, z: @z)
      end
    end

    # --------------------------------------------------------------------------
    # 5. 標準ウィジェット (ツール / 汎用)
    # --------------------------------------------------------------------------
    class Label < Widget
      attr_accessor :text, :color

      def initialize(text = "", x = 0.0, y = 0.0, width: nil, height: nil, size: nil, color: nil, **opts)
        @text  = text.to_s
        @size  = size ? size.to_i : nil
        @color = color
        super(x, y, width: width, height: height, interactive: false, **opts)
      end

      def font_size = @size || theme.font_size
      def width     = @width || (Font.default ? Font.default.text_width(@text, font_size) : 100.0)
      def height    = @height || (font_size + 4.0)

      def draw_self
        return if @text.empty?
        th = theme
        Zenoo::Window.draw_text(screen_left, screen_top + screen_height * 0.5, @text,
                                size: font_size, color: @color || th.text_color, valign: :center, camera: false, z: @z)
      end
    end

    class Button < Widget
      include Clickable
      attr_accessor :label

      def initialize(label = "Button", x = 0.0, y = 0.0, width: 120.0, height: nil, **opts, &block)
        @label = label.to_s
        super(x, y, width: width, height: height, **opts)
        on_click(&block) if block
      end

      def draw_self
        th = theme
        bg = pressed? ? th.bg_active : (hovered? ? th.bg_hover : th.bg_normal)
        bd = hovered? ? th.border_hover : th.border_normal
        py = pressed? ? 1.0 : 0.0
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: th.radius, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)
        Zenoo::Window.draw_text(screen_left + screen_width * 0.5, screen_top + screen_height * 0.5 + py,
                                @label, size: th.font_size, color: th.text_color, align: :center, valign: :center, camera: false, z: @z)
      end
    end

    class Checkbox < Widget
      include Clickable
      attr_accessor :label, :checked

      def initialize(label = "", checked = false, x = 0.0, y = 0.0, width: 200.0, height: nil, **opts, &block)
        @label   = label.to_s
        @checked = !!checked
        @on_change_proc = block
        super(x, y, width: width, height: height, **opts)
      end

      def on_change(&block) = (@on_change_proc = block; self)

      def trigger_click!
        @checked = !@checked
        @on_change_proc&.call(@checked)
        super
      end

      def draw_self
        th = theme
        lx = screen_left
        box_sz = (th.font_size + 3).to_f
        ty = screen_top + (screen_height - box_sz) * 0.5
        bd = hovered? ? th.border_hover : th.border_normal
        bg = @checked ? th.accent_color : th.track_bg
        Zenoo::Window.draw_rect(lx, ty, box_sz, box_sz, radius: [th.radius, 4.0].min, color: bg, border_width: 1.0, border_color: bd, camera: false, z: @z)
        Zenoo::Window.draw_text(lx + box_sz * 0.5, ty + box_sz * 0.5, "v", size: [th.font_size - 2, 10].max, color: :white, align: :center, valign: :center, camera: false, z: @z) if @checked
        Zenoo::Window.draw_text(lx + box_sz + 7.0, screen_top + screen_height * 0.5, @label, size: th.font_size, color: th.text_color, valign: :center, camera: false, z: @z)
      end
    end

    class Slider < Widget
      include Draggable
      attr_reader :value, :min, :max

      def initialize(label = "", value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0,
                     width: 220.0, height: nil, style: nil, format: nil, unit: "", **opts, &block)
        @label  = label.to_s
        @min    = min.to_f
        @max    = max.to_f
        @value  = value.to_f.clamp(@min, @max)
        @style  = style
        @format = format
        @unit   = unit.to_s
        @on_change_proc = block
        super(x, y, width: width, height: height, **opts)
        @drag_target = false # 自分自身は動かさず値だけ変える
      end

      def slider_style = @style || theme.slider_style
      def cursor_shape = :hand
      def on_change(&block) = (@on_change_proc = block; self)

      def height
        return @height if @height
        slider_style == :stacked ? (theme.control_height + 6.0) : theme.control_height
      end

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

      def draw_self
        th = theme
        lx = screen_left
        ty = screen_top
        rw = screen_width
        rh = screen_height
        ratio = (@max > @min) ? (@value - @min) / (@max - @min) : 0.0
        val_str = format_value

        if slider_style == :stacked
          draw_stacked(th, lx, ty, rw, rh, ratio, val_str)
        else
          draw_inline(th, lx, ty, rw, rh, ratio, val_str)
        end
      end

      private

      def format_value
        s = @format ? sprintf(@format, @value) : sprintf("%.2f", @value).sub(/\.?0+$/, "")
        s = "0" if s == "-0"
        @unit.empty? ? s : "#{s}#{@unit}"
      end

      def track_rect_bounds
        lx = screen_left
        rw = screen_width
        if slider_style == :inline && !@label.empty?
          lbl_w = [rw * 0.42, 72.0].max
          lbl_w = rw * 0.55 if lbl_w > rw * 0.55
          [lx + lbl_w, rw - lbl_w]
        else
          [lx, rw]
        end
      end

      # 1段インライン型: 左ラベル + 右ゲージバー(中に現在値表示)
      def draw_inline(th, lx, ty, rw, rh, ratio, val_str)
        tx, tw = track_rect_bounds
        unless @label.empty?
          Zenoo::Window.draw_text(lx, ty + rh * 0.5, @label, size: th.font_size, color: th.text_muted, valign: :center, camera: false, z: @z)
        end

        bar_y = ty + 2.0
        bar_h = [rh - 4.0, 12.0].max
        bd = (hovered? || dragging?) ? th.border_hover : th.track_border
        Zenoo::Window.draw_rect(tx, bar_y, tw, bar_h, radius: th.radius, color: th.track_bg, border_width: 1.0, border_color: bd, camera: false, z: @z)

        fill_w = tw * ratio
        if fill_w > 1.0
          fill_col = (hovered? || dragging?) ? th.accent_hover : th.accent_color
          Zenoo::Window.draw_rect(tx, bar_y, fill_w, bar_h, radius: th.radius, color: fill_col, camera: false, z: @z)
        end

        # つまみの目印ライン
        if tw > 8.0
          kx = (tx + fill_w).clamp(tx + 2.0, tx + tw - 2.0)
          Zenoo::Window.draw_line(kx, bar_y + 2.0, kx, bar_y + bar_h - 2.0, color: [245, 250, 255, 220], width: 2.0, camera: false, z: @z)
        end

        Zenoo::Window.draw_text(tx + tw - 6.0, ty + rh * 0.5, val_str,
                                size: [th.font_size - 1, 10].max, color: th.text_color, align: :right, valign: :center, camera: false, z: @z)
      end

      # 2段スタック型: 上にラベル&数値、下にトラック&丸ツマミ
      def draw_stacked(th, lx, ty, rw, _rh, ratio, val_str)
        Zenoo::Window.draw_text(lx, ty, @label, size: th.font_size - 1, color: th.text_color, camera: false, z: @z)
        Zenoo::Window.draw_text(lx + rw, ty, val_str, size: th.font_size - 1, color: th.accent_hover, align: :right, camera: false, z: @z)

        track_y = ty + th.font_size + 7.0
        Zenoo::Window.draw_rect(lx, track_y, rw, 7, radius: 3.5, color: th.track_bg, border_width: 1, border_color: th.track_border, camera: false, z: @z)
        Zenoo::Window.draw_rect(lx, track_y, rw * ratio, 7, radius: 3.5, color: th.accent_color, camera: false, z: @z)
        knob_col = (hovered? || dragging?) ? th.accent_hover : th.text_color
        Zenoo::Window.draw_circle(lx + rw * ratio, track_y + 3.5, 6.5, color: knob_col, camera: false, z: @z)
      end

      def update_value_from_x(mx)
        tx, tw = track_rect_bounds
        ratio = ((mx - tx) / [tw, 1.0].max).clamp(0.0, 1.0)
        self.value = @min + (@max - @min) * ratio
      end
    end

    # --------------------------------------------------------------------------
    # 6. 部品合成による Window (Window自体がDraggable + Body + ResizeGrip)
    # --------------------------------------------------------------------------
    class Window < Widget
      include Draggable

      class ResizeGrip < Widget
        include Draggable

        def initialize(owner_win)
          super(owner_win.width - 16.0, owner_win.height - 16.0, width: 16.0, height: 16.0)
          @owner = owner_win
          @drag_target = false
        end

        def cursor_shape = :resize_nwse

        def on_drag_start(_mx, _my)
          @start_w = @owner.width
          @start_h = @owner.height
        end

        def on_drag(_dx, _dy)
          @owner.resize_to(@start_w + @drag_offset_x, @start_h + @drag_offset_y)
        end

        def draw_self
          th = theme
          col = (hovered? || dragging?) ? th.accent_hover : th.border_normal
          Zenoo::Window.draw_line(screen_left + 4, screen_top + 12, screen_left + 12, screen_top + 4, color: col, width: 1.5, camera: false, z: @z)
          Zenoo::Window.draw_line(screen_left + 8, screen_top + 12, screen_left + 12, screen_top + 8, color: col, width: 1.5, camera: false, z: @z)
        end
      end

      attr_accessor :title
      attr_reader :body

      def initialize(title = "Window", x = 60.0, y = 60.0, width: 320.0, height: 260.0,
                     resizable: true, min_width: 180.0, min_height: 120.0, padding: nil, gap: nil, theme: nil, &block)
        super(x, y, width: width, height: height, interactive: true, theme: theme)
        @title    = title.to_s
        @min_w    = min_width.to_f
        @min_h    = min_height.to_f
        @header_h = @title.empty? ? 0.0 : self.theme.header_height

        @body = VBox.new(0.0, @header_h, width: width, height: height - @header_h,
                         padding: padding, gap: gap, clip_children: true)
        @body.parent = self

        if resizable
          @grip = ResizeGrip.new(self)
          @grip.parent = self
        end

        yield(self) if block
      end

      def add(child)
        @body.add(child)
      end

      def cursor_shape = :arrow
      def bring_to_front_on_click? = true

      def resize_to(new_w, new_h)
        nw = [new_w.to_f, @min_w].max
        nh = [new_h.to_f, @min_h].max
        self.width  = nw
        self.height = nh
        @body.width  = nw
        @body.height = nh - @header_h
        if @grip
          @grip.x = nw - @grip.width
          @grip.y = nh - @grip.height
        end
      end

      def resize_by(dx, dy)
        resize_to(width + dx, height + dy)
      end

      def draw_self
        th = theme
        bd = dragging? ? th.win_border_active : th.win_border
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: th.radius + 2.0, color: th.win_bg,
                                border_width: 1.5, border_color: bd,
                                shadow_blur: 10.0, shadow_color: [0, 0, 0, 140], camera: false, z: @z)
        unless @title.empty?
          Zenoo::Window.draw_text(screen_left + th.padding, screen_top + @header_h * 0.5 + 2.0, @title,
                                  size: th.font_size + 1, color: th.text_color, valign: :center, camera: false, z: @z)
        end
      end
    end

    # --------------------------------------------------------------------------
    # 7. Builder DSL
    # --------------------------------------------------------------------------
    module Builder
      def vbox(x = 0.0, y = 0.0, **opts, &block)
        w = add(VBox.new(x, y, **opts))
        yield(w) if block
        w
      end

      def hbox(x = 0.0, y = 0.0, **opts, &block)
        w = add(HBox.new(x, y, **opts))
        yield(w) if block
        w
      end

      def scroll_view(x = 0.0, y = 0.0, **opts, &block)
        w = add(ScrollView.new(x, y, **opts))
        yield(w) if block
        w
      end

      def window(title = "Window", x = 60.0, y = 60.0, **opts, &block)
        w = add(Window.new(title, x, y, **opts))
        yield(w) if block
        w
      end

      def label(text = "", **opts)                      = add(Label.new(text, **opts))
      def button(label = "Button", **opts, &block)      = add(Button.new(label, **opts, &block))
      def checkbox(label = "", checked = false, **opts, &block) = add(Checkbox.new(label, checked, **opts, &block))
      def slider(label = "", value = 0.0, min = 0.0, max = 100.0, **opts, &block) = add(Slider.new(label, value, min, max, **opts, &block))
      def custom(width: 100.0, height: 32.0, **opts, &block) = add(Widget.new(0.0, 0.0, width: width, height: height, **opts)).on_draw(&block)
    end

    Widget.include(Builder)
  end
end

# ==============================================================================
# 動作確認 & 密度・テーマ比較デモ
# ==============================================================================

class ColorTileButton < Zenoo::UI2::Widget
  include Zenoo::UI2::Clickable

  attr_reader :tile_color

  def initialize(col, size: 28.0)
    super(0.0, 0.0, width: size, height: size)
    @tile_color = col
  end

  def draw_self
    bd = hovered? ? [255, 255, 255] : [80, 95, 120]
    dy = pressed? ? 1.5 : 0.0
    Zenoo::Window.draw_rect(screen_left, screen_top + dy, screen_width, screen_height,
                            radius: 5, color: @tile_color, border_width: 1.5, border_color: bd, camera: false)
  end
end

class DraggableCard < Zenoo::UI2::Widget
  include Zenoo::UI2::Clickable
  include Zenoo::UI2::Draggable

  def initialize(title, x, y, color:)
    super(x, y, width: 105, height: 130, pivot: :center)
    @title = title
    @card_color = color
  end

  def bring_to_front_on_click? = true

  def draw_self
    bd = dragging? ? [255, 220, 90] : (hovered? ? [140, 210, 255] : [80, 95, 125])
    Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                            radius: 8, color: @card_color, border_width: 2, border_color: bd,
                            shadow_blur: dragging? ? 14.0 : 5.0, shadow_color: [0, 0, 0, 150], camera: false)
    Zenoo::Window.draw_text(screen_left + screen_width * 0.5, screen_top + 18, @title,
                            size: 13, color: :white, align: :center, camera: false)
    Zenoo::Window.draw_text(screen_left + screen_width * 0.5, screen_top + 70, dragging? ? "DRAG" : (hovered? ? "HOVER" : "IDLE"),
                            size: 11, color: [200, 220, 245], align: :center, camera: false)
  end
end

# --- UI ツリー構築 ---
stage = Zenoo::UI2::Stage.new
selected_color = [230, 90, 90]
preview_speed  = 1.2
wave_amp       = 16.0
wave_freq      = 0.40
animate_wave   = true

lbl_status = nil

# 左ウィンドウ: デフォルトの :compact テーマ (1段スライダーでスッキリ高密度)
stage.window("Tool Window (:compact default)", 40, 56, width: 340, height: 470, resizable: true) do |win|
  lbl_status = win.label("Status: Ready", color: [130, 210, 255])

  win.checkbox("Animate Preview", animate_wave) { |v| animate_wave = v }
  win.slider("Wave Speed", preview_speed, 0.2, 4.0, unit: "x") { |v| preview_speed = v }
  win.slider("Amplitude", wave_amp, 4.0, 28.0, unit: "px") { |v| wave_amp = v }
  win.slider("Frequency", wave_freq, 0.1, 1.0) { |v| wave_freq = v }

  win.label("Custom Class Widget (Palette):")
  win.hbox(gap: 6, height: 28, align: :center) do |row|
    [[230, 90, 90], [90, 200, 120], [80, 150, 240], [240, 200, 70]].each do |col|
      tile = ColorTileButton.new(col)
      tile.on_click do |btn|
        selected_color = btn.tile_color
        lbl_status.text = "Selected: #{selected_color.inspect}"
        btn.kill_tweens
        btn.scale = 0.85
        btn.tween.to(0.25, scale: 1.0, ease: :back_out)
      end
      row << tile
    end
  end

  win.label("Custom Block (Builder#custom):")
  wave_phase = 0.0
  win.custom(height: 64) do |w|
    wave_phase += 0.05 * preview_speed if animate_wave
    Zenoo::Window.draw_rect(w.screen_left, w.screen_top, w.screen_width, w.screen_height,
                            radius: 4, color: [16, 20, 28], border_width: 1, border_color: [60, 70, 95], camera: false)
    steps = 24
    step_w = w.screen_width / steps
    i = 0
    while i < steps
      px = w.screen_left + i * step_w + 6.0
      py = w.screen_top + w.screen_height * 0.5 + Math.sin(wave_phase + i * wave_freq) * wave_amp
      Zenoo::Window.draw_circle(px, py, 3.0, color: selected_color, camera: false)
      i += 1
    end
  end

  win.label("ScrollView (flex: 1):")
  win.scroll_view(flex: 1) do |sv|
    1.upto(10) do |idx|
      sv.button("Action ##{idx}") do
        lbl_status.text = "Clicked Action ##{idx}"
      end
    end
  end
end

# 右上ウィンドウ: :relaxed テーマを指定した例（同じ Builder / 同じクラスで自動的にゆったり表示）
win2 = stage.window("Game Settings (:relaxed theme)", 410, 56, width: 310, height: 245, resizable: true, theme: :relaxed)
win2.label("Same widgets, :relaxed theme!")
win2.checkbox("Fullscreen", false) { |v| lbl_status.text = "Fullscreen: #{v}" }
win2.slider("BGM Volume", 75.0, 0.0, 100.0, unit: "%") { |v| lbl_status.text = "BGM: #{v.round}%" }
win2.add(Zenoo::UI2::Button.new("Apply Settings") { lbl_status.text = "Applied!" })

card1 = DraggableCard.new("Card A", 450, 390, color: [48, 64, 96])
card1.on_click { lbl_status.text = "Card A clicked!" }
card2 = DraggableCard.new("Card B", 580, 410, color: [86, 52, 86])
card2.on_click { lbl_status.text = "Card B clicked!" }
stage << card1 << card2

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame = 0

Window.loop(1024, 640, "Zenoo UI2 Compact & Theme Prototype") do
  Window.clear([18, 22, 30])
  Window.draw_text(40, 18, "UI2 Prototype: :compact (1-row Slider) vs :relaxed Theme", size: 16, color: :white)

  stage.update
  stage.draw

  frame += 1
  break if test_max > 0 && frame >= test_max
end

puts "UI2 prototype completed (#{frame} frames)"

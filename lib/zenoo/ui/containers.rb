# frozen_string_literal: true

module Zenoo
  module UI
    # UI ツリーのルートとなる管理ステージ（入力・ホバー・フォーカス・ポップアップを統括）
    class Stage < Widget
      attr_reader :hovered_widget, :active_widget, :focused_widget, :popup_widget

      def initialize(width: nil, height: nil, theme: nil)
        @auto_w = width.nil?
        @auto_h = height.nil?
        super(0.0, 0.0, width: width || Zenoo::Window.width, height: height || Zenoo::Window.height, interactive: false, theme: theme)
        @hovered_widget = nil
        @active_widget  = nil
        @focused_widget = nil
        @popup_widget   = nil
      end

      def hovered?(w)    = @hovered_widget.equal?(w)
      def focused?(w)    = @focused_widget.equal?(w)
      def popup_open?(w) = @popup_widget.equal?(w)

      # このステージがいずれかのポインタ状態（ドラッグ/ホバー/ポップアップ）を保持しているか
      def capturing_pointer?
        !@active_widget.nil? || !@hovered_widget.nil? || !@popup_widget.nil?
      end

      def set_focus(w)
        return if @focused_widget.equal?(w)
        @focused_widget&.on_blur
        @focused_widget = w
        UI.notify_focus(self, @focused_widget)
        @focused_widget&.on_focus
      end

      def open_popup(w)
        return if @popup_widget.equal?(w)
        if @popup_widget
          old = @popup_widget
          @popup_widget = nil
          old.on_popup_close
        end
        @popup_widget = w
        w&.on_popup_open
      end

      def close_popup(w = nil)
        return unless @popup_widget
        return if w && !@popup_widget.equal?(w)
        old = @popup_widget
        @popup_widget = nil
        old.on_popup_close
      end

      def update
        return if @vanished || !@visible

        self.width  = Zenoo::Window.width.to_f  if @auto_w && Zenoo::Window.width > 0
        self.height = Zenoo::Window.height.to_f if @auto_h && Zenoo::Window.height > 0

        if @popup_widget && (!@popup_widget.tree_active? || !@popup_widget.stage.equal?(self) || Input.key_push?(:escape))
          close_popup
        end

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        down  = Input.mouse_pressed?(:left)
        push  = Input.mouse_push?(:left)
        rel   = Input.mouse_release?(:left)
        wheel = Input.mouse_wheel_y.to_f

        if UI.pointer_claimed?
          if @active_widget
            act = @active_widget
            @active_widget = nil
            act.on_pointer_up(mx, my, false)
          end
          update_hover(nil)
          close_popup if push
        else
          process_pointer(mx, my, down, push, rel, wheel)
        end

        if @focused_widget && (!@focused_widget.tree_active? || !@focused_widget.stage.equal?(self))
          set_focus(nil)
        end
        @focused_widget&.on_focused_update

        super
      end

      def draw
        return if @vanished || !@visible
        super
        if (pop = @popup_widget) && pop.tree_active?
          pop.draw_popup
        end
      end

      private

      def process_pointer(mx, my, down, push, rel, wheel)
        pop_over = false
        claimed  = false

        if @active_widget
          claimed = true
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
          pop = @popup_widget
          pop_consumed = false
          if pop
            if pop.hit_test_popup?(mx, my)
              pop_over = true
              pop_consumed = true
              claimed = true
              update_hover(nil)
              pop.on_popup_move(mx, my)
              pop.on_popup_wheel(wheel) if wheel != 0.0
              if push
                Input.consume_mouse!
                pop.on_popup_down(mx, my)
              end
            else
              pop.on_popup_move(mx, my)
              if push
                clicked_owner = pop.hit_test_self?(mx, my)
                close_popup
                if clicked_owner
                  Input.consume_mouse!
                  pop_consumed = true
                  claimed = true
                end
              end
            end
          end

          unless pop_consumed
            hit = find_hit(mx, my)
            update_hover(hit)

            if hit
              claimed = true
              hit.on_pointer_move(mx, my)
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
        end

        return unless claimed
        UI.claim_pointer!
        cur_shape = if pop_over && @popup_widget
                      @popup_widget.popup_cursor_shape
                    elsif @hovered_widget
                      @hovered_widget.cursor_shape
                    else
                      :arrow
                    end
        UI.set_mouse_cursor(cur_shape)
      end

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

    # 縦/横の自動レイアウトコンテナ
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

      def top_padding    = padding
      def right_padding  = padding
      def bottom_padding = padding

      def ensure_layout
        perform_layout if @layout_dirty
      end

      def update
        ensure_layout
        super
      end

      def content_height
        tp = top_padding
        bp = bottom_padding
        g  = gap
        return tp + bp unless @children
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
        tp + bp + sum + ((@direction == :column && count > 1) ? g * (count - 1) : 0.0)
      end

      def perform_layout
        @layout_dirty = false
        ch = @children
        return unless ch && !ch.empty?

        lp  = padding
        rp  = right_padding
        tp  = top_padding
        bp  = bottom_padding
        g   = gap
        inner_w = [width - lp - rp, 0.0].max
        inner_h = [height - tp - bp, 0.0].max
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

        cursor = (is_row ? lp : tp) - (is_row ? 0.0 : scroll_offset_y)
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
            cross_pos = is_row ? tp : lp
            if @align == :center
              cross_pos += (cross_avail - c_cross) * 0.5
            elsif @align == :end
              cross_pos += (cross_avail - c_cross)
            end

            ox = is_row ? cursor : cross_pos
            oy = is_row ? cross_pos : cursor
            c.x = ox - pax + c.anchor_x * c.width
            c.y = oy - pay + c.anchor_y * c.height
            c.ensure_layout

            cursor += (is_row ? c.width : c.height) + g
          end
          i += 1
        end

        @layout_dirty = false
      end
    end

    # 縦積みレイアウトコンテナ
    class VBox < Box
      def initialize(x = 0.0, y = 0.0, **opts, &block)
        super(x, y, direction: :column, **opts, &block)
      end
    end

    # 横並びレイアウトコンテナ
    class HBox < Box
      def initialize(x = 0.0, y = 0.0, **opts, &block)
        super(x, y, direction: :row, **opts, &block)
      end
    end

    # スクロール可能な縦積みコンテナ
    class ScrollView < VBox
      include Scrollable
      SB_WIDTH = 10.0

      def initialize(x = 0.0, y = 0.0, padding: nil, gap: nil, **opts, &block)
        init_scrollable
        @dragging_sb   = false
        @hover_sb      = false
        @sb_drag_off_y = 0.0
        super(x, y, padding: padding, gap: gap, clip_children: true, interactive: true, **opts, &block)
      end

      def collider_radius = theme.radius
      def cursor_shape    = (@hover_sb || @dragging_sb) ? :hand : :arrow
      def right_padding   = padding + (max_scroll_y > 0.0 ? SB_WIDTH : 0.0)

      def perform_layout
        max_s = max_scroll_y
        @scroll_y = max_s if @scroll_y > max_s
        @scroll_y = 0.0 if @scroll_y < 0.0
        super
      end

      def find_hit(px, py)
        return nil if @vanished || !@visible || !@enabled
        ensure_layout
        if max_scroll_y > 0.0 && in_scrollbar_track?(px, py)
          return self
        end
        super
      end

      def on_pointer_move(mx, my)
        @hover_sb = max_scroll_y > 0.0 && in_scrollbar_track?(mx, my)
      end

      def on_pointer_leave
        @hover_sb = false
      end

      def on_pointer_down(mx, my)
        super
        return unless max_scroll_y > 0.0 && in_scrollbar_track?(mx, my)
        _tx, ty, _tw, th, thumb_y, thumb_h = scrollbar_metrics
        @dragging_sb = true
        if my >= thumb_y && my <= thumb_y + thumb_h
          @sb_drag_off_y = my - thumb_y
        else
          @sb_drag_off_y = thumb_h * 0.5
          update_scroll_from_pointer(my, ty, th, thumb_h)
        end
      end

      def on_pointer_drag(_mx, my)
        super
        return unless @dragging_sb
        _tx, ty, _tw, th, _thumb_y, thumb_h = scrollbar_metrics
        update_scroll_from_pointer(my, ty, th, thumb_h)
      end

      def on_pointer_up(mx, my, inside)
        @dragging_sb = false
        super
      end

      def draw
        return if @vanished || !@visible
        super
        draw_scrollbar if max_scroll_y > 0.0
      end

      def draw_self
        th = theme
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: th.radius, color: th.track_bg, border_width: 1, border_color: th.track_border, camera: false, z: @z)
      end

      private

      def scrollbar_metrics
        sx = world_scale_x
        sy = world_scale_y
        pad = 3.0 * sy
        sb_w = 6.0 * sx
        tx = screen_left + screen_width - sb_w - 3.0 * sx
        ty = screen_top + pad
        th = [screen_height - pad * 2.0, 1.0].max
        tot_h = [content_height * sy, 1.0].max
        thumb_h = [th * (screen_height / tot_h), 18.0 * sy].max
        thumb_h = th if thumb_h > th
        max_s = max_scroll_y
        ratio = max_s > 0.0 ? (@scroll_y / max_s) : 0.0
        thumb_y = ty + (th - thumb_h) * ratio
        [tx, ty, sb_w, th, thumb_y, thumb_h]
      end

      def in_scrollbar_track?(mx, my)
        sx = world_scale_x
        left_x = screen_left + screen_width - (SB_WIDTH + 2.0) * sx
        mx >= left_x && mx <= screen_left + screen_width && my >= screen_top && my <= screen_top + screen_height
      end

      def update_scroll_from_pointer(my, ty, th, thumb_h)
        movable = th - thumb_h
        return if movable <= 0.0
        ratio = ((my - @sb_drag_off_y - ty) / movable).clamp(0.0, 1.0)
        self.scroll_y = max_scroll_y * ratio
      end

      def draw_scrollbar
        th = theme
        tx, ty, tw, track_h, thumb_y, thumb_h = scrollbar_metrics
        Zenoo::Window.draw_rect(tx, ty, tw, track_h, radius: tw * 0.5, color: [255, 255, 255, 16], camera: false, z: @z)
        thumb_col = (@hover_sb || @dragging_sb) ? th.accent_hover : [130, 150, 185, 200]
        Zenoo::Window.draw_rect(tx, thumb_y, tw, thumb_h, radius: tw * 0.5, color: thumb_col, camera: false, z: @z)
      end
    end

    # 背景色・枠線・任意タイトル付きの固定コンテナ（ドラッグ移動なし）
    class Panel < VBox
      attr_accessor :title, :bg_color, :border_color, :border_width, :radius

      def initialize(x = 0.0, y = 0.0, width: 200.0, height: 200.0, title: "",
                     bg_color: nil, border_color: nil, border_width: 1.0, radius: nil, interactive: true, **opts, &block)
        @title        = title.to_s
        @bg_color     = bg_color
        @border_color = border_color
        @border_width = border_width.to_f
        @radius       = radius ? radius.to_f : nil
        super(x, y, width: width, height: height, clip_children: true, interactive: interactive, **opts, &block)
      end

      def collider_radius = @radius || (theme.radius + 2.0)

      def top_padding
        @title.empty? ? padding : (padding + theme.header_height)
      end

      def draw_self
        th = theme
        rad = @radius || (th.radius + 2.0)
        bd = @border_color || th.win_border
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: rad, color: @bg_color || th.win_bg,
                                border_width: @border_width, border_color: bd,
                                camera: false, z: @z)
        unless @title.empty?
          hh = th.header_height * world_scale_y
          Zenoo::Window.draw_text(screen_left + padding * world_scale_x, screen_top + hh * 0.5 + 1.0, @title,
                                  size: th.font_size + 1, color: th.text_color, valign: :center, camera: false, z: @z)
          Zenoo::Window.draw_line(screen_left + 1.0, screen_top + hh, screen_left + screen_width - 1.0, screen_top + hh,
                                  color: bd, width: 1.0, camera: false, z: @z)
        end
      end
    end

    # ドラッグ移動・リサイズ・最前面化に対応したウィンドウ
    class Window < Widget
      include Draggable

      # ウィンドウ右下のリサイズハンドル
      class ResizeGrip < Widget
        include Draggable

        def initialize(owner_win)
          super(owner_win.width - 16.0, owner_win.height - 16.0, width: 16.0, height: 16.0)
          @owner = owner_win
          self.drag_target = nil
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
                     resizable: false, padding: nil, gap: nil, min_width: 180.0, min_height: 120.0, **opts, &block)
        @title      = title.to_s
        @min_w      = min_width.to_f
        @min_h      = min_height.to_f
        super(x, y, width: width, height: height, **opts)
        @header_h   = @title.empty? ? 0.0 : theme.header_height
        @body       = VBox.new(0.0, @header_h, width: self.width, height: [self.height - @header_h, 0.0].max,
                               padding: padding, gap: gap, clip_children: true)
        add(@body)
        if resizable
          @grip = ResizeGrip.new(self)
          add(@grip)
        end
        yield(@body) if block
      end

      def add(child)
        return super(child) if child.equal?(@body) || (@grip && child.equal?(@grip))
        @body.add(child)
      end

      def bring_to_front_on_click? = true
      def cursor_shape             = :arrow
      def collider_radius          = theme.radius + 2.0

      def resize_to(nw, nh)
        self.width  = [nw.to_f, @min_w].max
        self.height = [nh.to_f, @min_h].max
        @body.width  = width
        @body.height = [height - @header_h, 0.0].max
        @body.ensure_layout
        if @grip
          @grip.x = width - 16.0
          @grip.y = height - 16.0
        end
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
  end
end

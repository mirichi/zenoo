# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo 新 GUI プロトタイプ (UI2)
# ------------------------------------------------------------------------------
# コンセプト:
#   - Sprite ベースの保持モード一本化（Stage が入力・フォーカス・ホバーを統括）
#   - 薄い Widget 基底クラス + include による機能合成 (Clickable / Draggable / Focusable / Scrollable)
#   - Theme が「配色」と「密度・寸法（高さ/余白/フォントサイズ）」の両方を管理
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
                    :padding, :gap, :radius

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
        @padding        = 8.0
        @gap            = 3.0
        @radius         = 4.0
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
      end
    end

    @frame = 0
    @theme = Theme.new(:compact)
    @point_collider = Collision::Point.new(anchor: :center, pivot: :center)
    class << self
      attr_accessor :frame

      def point_collider(px, py)
        @point_collider.x = px.to_f
        @point_collider.y = py.to_f
        @point_collider
      end

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
      attr_reader :interactive
      attr_accessor :enabled, :clip_children, :flex

      def initialize(x = 0.0, y = 0.0, width: 100.0, height: nil,
                     anchor: :top_left, pivot: :center, z: 0.0, camera: false,
                     enabled: true, visible: true, interactive: true, clip_children: false,
                     flex: nil, theme: nil, **opts)
        super(x, y, nil, width: width, height: height, anchor: anchor, pivot: pivot, z: z, camera: camera, **opts)
        @enabled       = enabled
        @visible       = !!visible
        @interactive   = !!interactive
        @clip_children = clip_children
        @flex          = flex ? flex.to_f : nil
        @theme         = theme.is_a?(Symbol) ? Theme.new(theme) : theme
        @on_draw_proc  = nil
        set_default_collider if @interactive
      end

      def interactive=(v)
        @interactive = !!v
        set_default_collider if @interactive && !@collider_shape
      end

      def collider_radius = nil
      def sync_collider_shape
        col = @collider_shape
        return unless col && col.shape_type == Collision::TYPE_RECT
        if (rad = collider_radius)
          col.radius = rad
        end
      end

      def set_default_collider
        rad = collider_radius
        if rad && rad > 0.0
          set_collider(:rect, radius: rad)
        else
          set_collider(:default)
        end
      end

      def theme
        @theme || (@parent.is_a?(Widget) ? @parent.theme : UI2.theme)
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
        dirty_world_geom!
        mark_layout_dirty!
      end

      def dirty_world_geom!
        super
        if (col = @collider_shape)
          col.dirty_size!
          sync_collider_shape
        end
      end

      def tree_active?
        cur = self
        while cur
          return false if cur.vanished? || !cur.visible
          return false if cur.is_a?(Widget) && !cur.enabled
          cur = cur.parent
        end
        true
      end

      def popup_open?  = (st = stage) ? st.popup_open?(self) : false
      def open_popup!  = (stage&.open_popup(self); self)
      def close_popup! = (stage&.close_popup(self); self)

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

      # 自身への当たり判定 (Sprite の Collider による統合判定: 矩形/角丸/円/多角形/回転/拡大縮小対応)
      def hit_test_self?(px, py)
        return false if @vanished || !@visible || !@enabled || !@interactive
        col = self.collider
        return false unless col
        Collision.check(UI2.point_collider(px, py), col)
      end

      # 手前(配列末尾)から奥(配列先頭)へ最前面のヒット対象を探索
      def find_hit(px, py)
        return nil if @vanished || !@visible || !@enabled

        ensure_layout
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
        if width != old_w
          sync_collider_shape
          @parent.mark_layout_dirty! if @parent.is_a?(Widget)
        end
      end

      def height=(v)
        old_h = height
        super(v)
        if height != old_h
          sync_collider_shape
          @parent.mark_layout_dirty! if @parent.is_a?(Widget)
        end
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
      def on_pointer_move(_mx, _my);   end
      def on_pointer_leave;            end
      def on_pointer_down(_mx, _my);   end
      def on_pointer_drag(_mx, _my);   end
      def on_pointer_up(_mx, _my, _in); end
      def on_wheel(_dy)                = false
      def on_focus;                    end
      def on_blur;                     end
      def on_focused_update;           end
      def hit_test_popup?(_mx, _my)    = false
      def popup_cursor_shape           = :arrow
      def on_popup_open;               end
      def on_popup_close;              end
      def on_popup_move(_mx, _my);     end
      def on_popup_down(_mx, _my);     end
      def on_popup_wheel(_dy)          = false
      def draw_popup;                  end
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
      attr_reader :drag_offset_x, :drag_offset_y
      def dragging? = !!@dragging

      def drag_target
        @has_drag_target ? @drag_target : self
      end

      def drag_target=(val)
        @has_drag_target = true
        @drag_target = val
      end

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
          if (target = drag_target)
            target.x += dx
            target.y += dy
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

      def set_focus(w)
        return if @focused_widget.equal?(w)
        @focused_widget&.on_blur
        @focused_widget = w
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
        UI2.frame += 1

        self.width  = Zenoo::Window.width.to_f  if @auto_w && Zenoo::Window.width > 0
        self.height = Zenoo::Window.height.to_f if @auto_h && Zenoo::Window.height > 0

        if @popup_widget && (!@popup_widget.tree_active? || !@popup_widget.stage.equal?(self) || Input.key_push?(:escape))
          close_popup
        end

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        down = Input.mouse_pressed?(:left)
        push = Input.mouse_push?(:left)
        rel  = Input.mouse_release?(:left)
        wheel = Input.mouse_wheel_y.to_f

        pop_over = false

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
          pop = @popup_widget
          pop_consumed = false
          if pop
            if pop.hit_test_popup?(mx, my)
              pop_over = true
              pop_consumed = true
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
                end
              end
            end
          end

          unless pop_consumed
            hit = find_hit(mx, my)
            update_hover(hit)

            if hit
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

        cur_shape = if pop_over && @popup_widget
                      @popup_widget.popup_cursor_shape
                    elsif @hovered_widget
                      @hovered_widget.cursor_shape
                    else
                      :arrow
                    end
        Zenoo::UI.set_mouse_cursor(cur_shape)

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
            c.ensure_layout

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

      def collider_radius = theme.radius

      def perform_layout
        max_s = max_scroll_y
        @scroll_y = max_s if @scroll_y > max_s
        @scroll_y = 0.0 if @scroll_y < 0.0
        super
      end

      def draw_self
        th = theme
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: th.radius, color: th.track_bg, border_width: 1, border_color: th.track_border, camera: false, z: @z)
      end
    end

    class Panel < VBox
      attr_accessor :bg_color, :border_color, :border_width, :radius

      def initialize(x = 0.0, y = 0.0, width: 200.0, height: 200.0,
                     bg_color: nil, border_color: nil, border_width: 1.0, radius: nil, **opts, &block)
        @bg_color     = bg_color
        @border_color = border_color
        @border_width = border_width.to_f
        @radius       = radius ? radius.to_f : nil
        super(x, y, width: width, height: height, **opts, &block)
      end

      def draw_self
        th = theme
        Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                                radius: @radius || th.radius, color: @bg_color || [28, 33, 45],
                                border_width: @border_width, border_color: @border_color || th.border_normal,
                                camera: false, z: @z)
      end
    end

    # --------------------------------------------------------------------------
    # 5. 標準ウィジェット (ツール / 汎用)
    # --------------------------------------------------------------------------
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

    class Spacer < Widget
      def initialize(size = 8.0, flex: nil, **opts)
        s = size.to_f
        super(0.0, 0.0, width: s, height: s, flex: flex, interactive: false, **opts)
      end
    end

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

      def collider_radius = theme.radius

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

    # 丸ツマミが左右にスライドする今風のトグルスイッチ
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

        cx, cw, btn_w, minus_x, plus_x, val_x, val_w = ctrl_screen_layout
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
        self.drag_target = nil # 自分自身は動かさず値だけ変える
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

    # 1段インライン型スライダー: 左ラベル + 右ゲージバー(中に現在値表示)
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

    # 2段スタック型スライダー: 上にラベル&数値、下にトラック&丸ツマミ
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
          @scroll_index = 0
          close_popup! if popup_open?
        else
          @selected_index = @selected_index.clamp(0, @items.length - 1) if @selected_index >= 0
          clamp_scroll!
        end
        @items
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
        Collision.check(UI2.point_collider(mx, my), @popup_collider)
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
          pw = Font.default ? Font.default.text_width(prefix, th.font_size) : prefix.length * th.font_size * 0.55
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
        @blink_start_frame = UI2.frame
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
        @blink_start_frame = UI2.frame
      end

      def on_pointer_drag(mx, _my)
        super
        return unless @dragging_sel
        @cursor_pos = index_at_mouse_x(mx)
        ensure_caret_visible
        @blink_start_frame = UI2.frame
      end

      def on_pointer_up(_mx, _my, _inside)
        @dragging_sel = false
        @sel_anchor = nil if @sel_anchor == @cursor_pos
        super
      end

      def on_focus
        @blink_start_frame = UI2.frame
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

        @blink_start_frame = UI2.frame if reset_blink
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

        if is_foc && (((UI2.frame - @blink_start_frame) % 60) < 30)
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
        bx, _by, bw, _bh, = box_screen_rect
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

    class Table < Widget
      COL_HDR_BG   = [32, 38, 52]
      COL_HDR_TXT  = [178, 194, 222]
      COL_ROW_EVEN = [255, 255, 255, 9]
      COL_SEP      = [255, 255, 255, 22]
      COL_VAL_NUM  = [130, 210, 255]
      COL_VAL_BOOL = [245, 195, 110]
      COL_VAL_SYM  = [210, 160, 255]
      COL_VAL_NIL  = [130, 140, 160]

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
      def collider_radius = theme.radius + 2.0

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
        @body.ensure_layout
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

      def panel(x = 0.0, y = 0.0, **opts, &block)
        w = add(Panel.new(x, y, **opts))
        yield(w) if block
        w
      end

      def divider(**opts)                               = add(Divider.new(**opts))
      def spacer(size = 8.0, **opts)                    = add(Spacer.new(size, **opts))
      def image_box(image = nil, **opts)                = add(ImageBox.new(image, **opts))
      def label(text = "", **opts)                      = add(Label.new(text, **opts))
      def button(label = "Button", **opts, &block)      = add(Button.new(label, **opts, &block))
      def checkbox(label = "", checked = false, **opts, &block) = add(Checkbox.new(label, checked, **opts, &block))
      def switch(label = "", checked = false, **opts, &block)   = add(Switch.new(label, checked, **opts, &block))
      def radio_button(label = "", checked = false, **opts, &block) = add(RadioButton.new(label, checked, **opts, &block))
      def progress_bar(value = 0.0, min = 0.0, max = 1.0, **opts)   = add(ProgressBar.new(value, min, max, **opts))
      def spinner(label = "", value = 0, **opts, &block)            = add(Spinner.new(label, value, **opts, &block))
      def slider(label = "", value = 0.0, min = 0.0, max = 100.0, **opts, &block) = add(Slider.new(label, value, min, max, **opts, &block))
      def stacked_slider(label = "", value = 0.0, min = 0.0, max = 100.0, **opts, &block) = add(StackedSlider.new(label, value, min, max, **opts, &block))
      def dropdown(items = [], selected_index = 0, **opts, &block) = add(Dropdown.new(items, selected_index, **opts, &block))
      def text_box(text = "", **opts, &block)        = add(TextBox.new(text, **opts, &block))
      def tabs(items = [], selected_index = 0, **opts, &block) = add(Tabs.new(items, selected_index, **opts, &block))
      def table(columns = [], rows = [], selected_index = nil, **opts, &block) = add(Table.new(columns, rows, selected_index, **opts, &block))
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

  def collider_radius = 5.0

  def draw_self
    bd = hovered? ? [255, 255, 255] : [80, 95, 120]
    dy = pressed? ? 1.5 : 0.0
    Zenoo::Window.draw_rect(screen_left, screen_top + dy, screen_width, screen_height,
                            radius: 5, color: @tile_color, border_width: 1.5, border_color: bd, camera: false)
  end
end

class CirclePadButton < Zenoo::UI2::Widget
  include Zenoo::UI2::Clickable

  def initialize(label, x, y, size: 72.0, color: [64, 128, 190])
    @label = label
    @btn_color = color
    super(x, y, width: size, height: size, pivot: :center)
    set_collider(:circle)
  end

  def draw_self
    cx = screen_left + screen_width * 0.5
    cy = screen_top + screen_height * 0.5 + (pressed? ? 1.5 : 0.0)
    r  = [screen_width, screen_height].min * 0.5
    bd = hovered? ? [255, 255, 255] : [110, 175, 245]
    Zenoo::Window.draw_circle(cx, cy, r, color: @btn_color, border_width: 2.0, border_color: bd, camera: false)
    Zenoo::Window.draw_text(cx, cy, hovered? ? "HOVER" : @label, size: 12, color: :white, align: :center, valign: :center, camera: false)
  end
end

class DiamondButton < Zenoo::UI2::Widget
  include Zenoo::UI2::Clickable

  def initialize(label, x, y, size: 76.0, color: [165, 92, 130])
    @label = label
    @btn_color = color
    @half = size * 0.5
    super(x, y, width: size, height: size, pivot: :center)
    set_collider(:polygon, vertices: [[0.0, -@half], [@half, 0.0], [0.0, @half], [-@half, 0.0]])
  end

  def draw_self
    cx = screen_left + screen_width * 0.5
    cy = screen_top + screen_height * 0.5 + (pressed? ? 1.5 : 0.0)
    h  = @half
    bd = hovered? ? [255, 255, 255] : [220, 160, 190]
    Zenoo::Window.draw_triangle(cx, cy - h, cx + h, cy, cx - h, cy, color: @btn_color, camera: false)
    Zenoo::Window.draw_triangle(cx - h, cy, cx + h, cy, cx, cy + h, color: @btn_color, camera: false)
    Zenoo::Window.draw_line(cx, cy - h, cx + h, cy, color: bd, width: 2.0, camera: false)
    Zenoo::Window.draw_line(cx + h, cy, cx, cy + h, color: bd, width: 2.0, camera: false)
    Zenoo::Window.draw_line(cx, cy + h, cx - h, cy, color: bd, width: 2.0, camera: false)
    Zenoo::Window.draw_line(cx - h, cy, cx, cy - h, color: bd, width: 2.0, camera: false)
    Zenoo::Window.draw_text(cx, cy, hovered? ? "HOVER" : @label, size: 12, color: :white, align: :center, valign: :center, camera: false)
  end
end

class DraggableCard < Zenoo::UI2::Widget
  include Zenoo::UI2::Clickable
  include Zenoo::UI2::Draggable

  def initialize(title, x, y, color:, angle: 0.0)
    super(x, y, width: 105, height: 130, pivot: :center)
    self.angle = angle
    @title = title
    @card_color = color
  end

  def bring_to_front_on_click? = true
  def collider_radius = 8.0

  def draw_self
    bd = dragging? ? [255, 220, 90] : (hovered? ? [140, 210, 255] : [80, 95, 125])
    Zenoo::Window.draw_rect(screen_left, screen_top, screen_width, screen_height,
                            radius: 8, color: @card_color, border_width: 2, border_color: bd,
                            angle: world_angle, pivot: :center,
                            shadow_blur: dragging? ? 14.0 : 5.0, shadow_color: [0, 0, 0, 150], camera: false)
    cx = screen_left + screen_width * 0.5
    cy = screen_top + screen_height * 0.5
    Zenoo::Window.draw_text(cx, cy - 24, @title, size: 13, color: :white, align: :center, camera: false)
    Zenoo::Window.draw_text(cx, cy + 8, dragging? ? "DRAG" : (hovered? ? "HOVER" : "IDLE"),
                            size: 11, color: [200, 220, 245], align: :center, camera: false)
  end
end

def draw_debug_shape(col, hovered)
  return unless col
  fill   = hovered ? [255, 210, 60, 48] : [60, 230, 140, 26]
  border = hovered ? [255, 220, 90, 220] : [70, 240, 155, 190]
  case col.shape_type
  when Zenoo::Collision::TYPE_CIRCLE
    rx = col.is_true_circle ? col.effective_radius : col.radius_x * col.scale_x.abs
    ry = col.is_true_circle ? col.effective_radius : col.radius_y * col.scale_y.abs
    Zenoo::Window.draw_circle(col.center_x, col.center_y, rx, ry, angle: col.angle,
                              color: fill, border_width: 1.5, border_color: border, camera: false, z: 9500.0)
  when Zenoo::Collision::TYPE_RECT
    if col.is_rounded
      cx = col.center_x
      cy = col.center_y
      w = col.width * col.scale_x.abs
      h = col.height * col.scale_y.abs
      Zenoo::Window.draw_rect(cx - w * 0.5, cy - h * 0.5, w, h,
                              angle: col.angle, pivot: :center,
                              color: fill, border_width: 1.5, border_color: border,
                              radius: col.radius, camera: false, z: 9500.0)
      return
    end
  end

  if (col.shape_type == Zenoo::Collision::TYPE_RECT || col.shape_type == Zenoo::Collision::TYPE_POLYGON) &&
     (verts = col.world_vertices) && verts.length >= 3
    i = 0
    len = verts.length
    while i < len
      a = verts[i]
      b = verts[(i + 1) % len]
      Zenoo::Window.draw_line(a[0], a[1], b[0], b[1], color: border, width: 1.5, camera: false, z: 9500.0)
      i += 1
    end
  end
end

def draw_debug_colliders(node, stage)
  return if node.vanished? || !node.visible
  if node.is_a?(Zenoo::UI2::Widget) && node.collider
    draw_debug_shape(node.collider, stage.hovered?(node))
  end
  ch = node.children
  i = 0
  while i < ch.length
    draw_debug_colliders(ch[i], stage)
    i += 1
  end
end

# --- UI ツリー構築 ---
stage = Zenoo::UI2::Stage.new
selected_color = [230, 90, 90]
wave_type      = "Sine"
preview_speed  = 1.2
wave_amp       = 16.0
wave_freq      = 0.40
animate_wave   = true
show_colliders = true

lbl_status = nil

# 左ウィンドウ: デフォルトの :compact テーマ (1段コントロールで高密度)
stage.window("Tool Window (:compact default)", 36, 52, width: 344, height: 540, resizable: true) do |win|
  lbl_status = win.label("Status: Ready", color: [130, 210, 255])

  win.dropdown(["Sine", "Triangle", "Square", "Sawtooth", "Pulse", "Noise", "Abs Sine", "Cosine", "Step", "Ripple"],
               0, label: "Wave", max_items: 6) do |_idx, item|
    wave_type = item
    lbl_status.text = "Wave: #{item}"
  end

  win.text_box("Wave A", label: "Preset Name", placeholder: "Enter preset...") do |txt|
    lbl_status.text = "Preset: #{txt}"
  end.on_submit do |txt|
    lbl_status.text = "Submitted: #{txt}"
  end

  win.checkbox("Animate Preview", animate_wave) { |v| animate_wave = v }
  win.slider("Wave Speed", preview_speed, 0.2, 4.0, unit: "x") { |v| preview_speed = v }
  win.slider("Amplitude", wave_amp, 4.0, 28.0, unit: "px") { |v| wave_amp = v }
  win.slider("Frequency", wave_freq, 0.1, 1.0) { |v| wave_freq = v }

  win.label("Custom Class Widget (Palette):")
  win.hbox(padding: 0, gap: 6, height: 28, align: :center) do |row|
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
    steps = 28
    step_w = w.screen_width / steps
    i = 0
    while i < steps
      ph = wave_phase + i * wave_freq
      val = case wave_type
            when "Triangle"
              (2.0 / Math::PI) * Math.asin(Math.sin(ph))
            when "Square"
              Math.sin(ph) >= 0.0 ? 1.0 : -1.0
            when "Sawtooth"
              t = (ph / (Math::PI * 2.0)) % 1.0
              2.0 * t - 1.0
            when "Pulse"
              Math.sin(ph) >= 0.6 ? 1.0 : -0.6
            when "Noise"
              Math.sin(ph * 7.3) * Math.cos(ph * 13.7)
            when "Abs Sine"
              Math.sin(ph).abs * 2.0 - 1.0
            when "Cosine"
              Math.cos(ph)
            when "Step"
              (Math.sin(ph) * 3.0).round / 3.0
            when "Ripple"
              Math.sin(ph * 1.5) * Math.cos(ph * 0.35)
            else
              Math.sin(ph)
            end
      px = w.screen_left + i * step_w + 6.0
      py = w.screen_top + w.screen_height * 0.5 + val * wave_amp
      Zenoo::Window.draw_circle(px, py, 2.8, color: selected_color, camera: false)
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

# 右上ウィンドウ: :relaxed テーマを指定した例（同じ Widget / Dropdown も自動でゆったり高さ）
win2 = stage.window("Game Settings (:relaxed theme)", 410, 52, width: 320, height: 376, resizable: true, theme: :relaxed)
win2.checkbox("Show Colliders", show_colliders) { |v| show_colliders = v }
win2.switch("V-Sync (Switch)", true) { |v| lbl_status.text = "V-Sync: #{v}" }
win2.text_box("", placeholder: "Search or type player name...") do |txt|
  lbl_status.text = "Filter: #{txt}"
end
win2.dropdown(["60 FPS", "120 FPS", "240 FPS", "Unlimited"], 0, label: "FPS Cap") { |_i, item| lbl_status.text = "FPS Cap: #{item}" }
win2.stacked_slider("BGM Volume", 75.0, 0.0, 100.0, unit: "%") { |v| lbl_status.text = "BGM: #{v.round}%" }
win2.add(Zenoo::UI2::Button.new("Apply Settings") { lbl_status.text = "Applied!" })

# 右側ウィンドウ: 追加コントロール一覧 (Tabs / Panel / Switch / RadioButton / Spinner / ProgressBar / ImageBox)
preview_img_box = nil
pbar = nil
tab_panels = []
win3 = stage.window("Controls Showcase", 748, 185, width: 256, height: 382, resizable: true)
win3.tabs(["Controls", "Visual", "Table"], 0) do |idx, item|
  lbl_status.text = "Tab: #{item}"
  ti = 0
  while ti < tab_panels.length
    tab_panels[ti].visible = (ti == idx)
    ti += 1
  end
end

tab_panels << win3.panel(flex: 1) do |p0|
  p0.checkbox("Checkbox (Square)", true) { |v| lbl_status.text = "Checkbox: #{v}" }
  p0.switch("Switch (Toggle)", true) { |v| lbl_status.text = "Switch: #{v}" }
  p0.divider
  p0.label("Radio Group:")
  p0.hbox(padding: 0, gap: 6, height: 24, align: :center) do |rrow|
    rrow.radio_button("Low",  false, group: :qual, value: :low)  { |v| lbl_status.text = "Quality: #{v}" }
    rrow.radio_button("Mid",  true,  group: :qual, value: :mid)  { |v| lbl_status.text = "Quality: #{v}" }
    rrow.radio_button("High", false, group: :qual, value: :high) { |v| lbl_status.text = "Quality: #{v}" }
  end
  p0.divider
  p0.spinner("Count", 12, min: 0, max: 20, step: 2, label_width: 72) do |v|
    lbl_status.text = "Spinner: #{v}"
    pbar.value = v / 20.0 if pbar
  end
  pbar = p0.progress_bar(0.6, 0.0, 1.0, show_percentage: true)
  p0.spacer(4, flex: 1)
  p0.label("Try clicking [-] / [+] & Tabs!", color: [160, 175, 200])
end

tab_panels << win3.panel(flex: 1, visible: false) do |p1|
  p1.label("ImageBox Preview:")
  preview_img_box = p1.image_box(nil, width: 96, height: 96, fit: :contain,
                                 bg_color: [16, 20, 28], border_color: [68, 80, 106], border_width: 1.0, radius: 6.0)
  p1.divider
  p1.label("Progress Bar Control:")
  p1.hbox(padding: 0, gap: 6, height: 26, align: :center) do |brow|
    brow.button("-15%", width: 64) { pbar.value = (pbar.value - 0.15).clamp(0.0, 1.0) }
    brow.button("+15%", width: 64) { pbar.value = (pbar.value + 0.15).clamp(0.0, 1.0) }
    brow.spacer(4, flex: 1)
  end
end

tab_panels << win3.panel(flex: 1, visible: false) do |p2|
  sample_rows = [
    ["Player",  120.5, true,  :idle],
    ["Enemy_1", 340.0, true,  :patrol],
    ["Enemy_2", 512.8, false, :dead],
    ["Boss",    880.0, true,  :phase2],
    ["Bullet",  210.2, true,  :fly],
    ["Item",    96.0,  false, nil],
    ["Trigger", 400.0, true,  :active],
    ["Effect",  64.0,  false, :fade],
    ["Camera",  0.0,   true,  :follow],
    ["Shadow",  120.5, true,  :cast]
  ]
  p2.table([["Name", 78], ["X", 50], ["Live", 44], "State"], sample_rows, 0,
           flex: 1, item_height: 20, label: "Objects (Wheel Scroll)") do |idx, row|
    lbl_status.text = "Row #{idx}: #{row[0]} (#{row[3].inspect})"
  end
end

# 下辺反転テスト用の配置ドロップダウン (画面下端近くで開くと自動で上向きに展開)
bottom_dd = Zenoo::UI2::Dropdown.new(["Bottom Flip A", "Bottom Flip B", "Bottom Flip C", "Bottom Flip D"], 0, 760, 588, width: 220, label: "Bottom")
bottom_dd.on_change { |_i, item| lbl_status.text = "Bottom: #{item}" }
stage << bottom_dd

# コライダー形状デモ: 円形 / 多角形 / 回転矩形 (OBB)
circle_btn = CirclePadButton.new("CIRCLE", 790, 120)
circle_btn.on_click { lbl_status.text = "Circle Collider clicked!" }
diamond_btn = DiamondButton.new("POLYGON", 890, 120)
diamond_btn.on_click { lbl_status.text = "Polygon Collider clicked!" }
stage << circle_btn << diamond_btn

card1 = DraggableCard.new("Card A", 435, 460, color: [48, 64, 96])
card1.on_click { lbl_status.text = "Card A clicked!" }
card2 = DraggableCard.new("Card B (14deg)", 585, 475, color: [86, 52, 86], angle: 14.0)
card2.on_click { lbl_status.text = "Card B (rotated OBB) clicked!" }
stage << card1 << card2

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame = 0

img = Zenoo::Image.new(64, 64)
Zenoo::Image.render_to(img) do
  Zenoo::Window.clear([24, 30, 44, 255])
  Zenoo::Window.draw_circle(32, 32, 22, color: [72, 152, 242, 255])
  Zenoo::Window.draw_triangle(32, 14, 16, 46, 48, 46, color: [240, 210, 80, 255])
end
preview_img_box.image = img

Window.loop(1024, 640, "Zenoo UI2 Collider HitTest & Dropdown Prototype") do

  Window.clear([18, 22, 30])
  Window.draw_text(36, 18, "UI2 Prototype: Sprite Collider HitTest & Dropdown Popup", size: 16, color: :white)

  stage.update
  stage.draw

  if show_colliders
    draw_debug_colliders(stage, stage)
    if (pop = stage.popup_widget).is_a?(Zenoo::UI2::Dropdown)
      draw_debug_shape(pop.popup_collider, true)
    end
  end

  frame += 1
  break if test_max > 0 && frame >= test_max
end

puts "UI2 prototype completed (#{frame} frames)"

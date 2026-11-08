# frozen_string_literal: true

module Zenoo
  module UI
    # ==========================================================================
    # Stage (ルートキャンバス: 画面全体を覆う透明な親コンテナ)
    # ==========================================================================
    class Stage < Widget
      def initialize(width: nil, height: nil, theme: nil)
        w = width ? width.to_f : 1280.0
        h = height ? height.to_f : 720.0
        super(0.0, 0.0, width: w, height: h, anchor: :top_left, interactive: false, theme: theme)
      end

      def update_self
        # 画面サイズに自動追従
        win_w = Zenoo::Window.width.to_f
        win_h = Zenoo::Window.height.to_f
        @width  = win_w if win_w > 0.0 && @width != win_w
        @height = win_h if win_h > 0.0 && @height != win_h
      end

      def draw_self
        # ステージ自身は背景を描画しない
      end
    end

    # ==========================================================================
    # Box (軽量 Flexbox レイアウトコンテナ)
    # - direction: :column (縦並び) / :row (横並び)
    # - padding: 内側余白 (Float または [x, y] または [left, top, right, bottom])
    # - gap: 子要素間のスペース
    # - align: 交差軸の揃え (:start, :center, :end, :stretch)
    # - justify: 主軸の揃え (:start, :center, :end, :space_between)
    # ==========================================================================
    class Box < Widget
      attr_reader :direction, :gap, :align, :justify, :pad_left, :pad_top, :pad_right, :pad_bottom, :header_height
      attr_accessor :auto_layout

      def initialize(x = 0.0, y = 0.0, width: 200.0, height: 200.0,
                     direction: :column, padding: 0.0, gap: 8.0,
                     align: :stretch, justify: :start,
                     auto_layout: true, clip: false,
                     interactive: false, parent: nil, **opts, &block)
        @direction     = direction
        @gap           = gap.to_f
        @align         = align
        @justify       = justify
        @auto_layout   = auto_layout
        @header_height = 0.0
        @layout_dirty  = true
        parse_padding(padding)

        super(x, y, width: width, height: height, interactive: interactive, parent: parent, **opts)
        @clip_children = clip

        yield(self) if block
      end

      def padding=(val)
        parse_padding(val)
        mark_layout_dirty!
      end

      def direction=(val)
        return if @direction == val
        @direction = val
        mark_layout_dirty!
      end

      def gap=(val)
        vf = val.to_f
        return if @gap == vf
        @gap = vf
        mark_layout_dirty!
      end

      def align=(val)
        return if @align == val
        @align = val
        mark_layout_dirty!
      end

      def justify=(val)
        return if @justify == val
        @justify = val
        mark_layout_dirty!
      end

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

      def update_layout_tree
        perform_layout if @auto_layout && @layout_dirty
        super
      end

      def perform_layout
        @layout_dirty = false
        ch_list = @children
        return unless ch_list && !ch_list.empty?

        # レイアウト対象の可視・非消滅ウィジェットを収集
        vis_count = 0
        i = 0
        len = ch_list.length
        while i < len
          c = ch_list[i]
          if c.is_a?(Widget) && c.visible && !c.vanished? && !c.respond_to?(:floating_ignore_layout?)
            vis_count += 1
          end
          i += 1
        end
        return if vis_count == 0

        inner_x = @pad_left
        inner_y = @pad_top + @header_height
        inner_w = [width - @pad_left - @pad_right, 0.0].max
        inner_h = [height - @pad_top - @pad_bottom - @header_height, 0.0].max

        is_row = (@direction == :row)
        main_avail  = is_row ? inner_w : inner_h
        cross_avail = is_row ? inner_h : inner_w
        total_gaps  = (vis_count > 1) ? (@gap * (vis_count - 1).to_f) : 0.0

        # 1. 固定サイズ合計と flex 合計を算出 + 交差軸の :stretch 適用
        fixed_main = 0.0
        total_flex = 0.0
        i = 0
        while i < len
          c = ch_list[i]
          if c.is_a?(Widget) && c.visible && !c.vanished?
            c_align = c.align_self || @align
            if c_align == :stretch
              if is_row
                c.height = cross_avail if c.height != cross_avail
              else
                c.width = cross_avail if c.width != cross_avail
              end
            end

            if c.flex && c.flex > 0.0
              total_flex += c.flex
            else
              fixed_main += (is_row ? c.width : c.height)
            end
          end
          i += 1
        end

        rem_main = [main_avail - fixed_main - total_gaps, 0.0].max

        # 2. flex 子要素の主軸サイズを確定
        if total_flex > 0.0
          i = 0
          while i < len
            c = ch_list[i]
            if c.is_a?(Widget) && c.visible && !c.vanished? && c.flex && c.flex > 0.0
              alloc = rem_main * (c.flex / total_flex)
              if is_row
                c.width = alloc
              else
                c.height = alloc
              end
            end
            i += 1
          end
          rem_main = 0.0
        end

        # 3. justify (主軸の開始位置とギャップ)
        cursor_main = is_row ? inner_x : inner_y
        step_gap = @gap
        if total_flex <= 0.0 && rem_main > 0.0
          case @justify
          when :center
            cursor_main += rem_main * 0.5
          when :end
            cursor_main += rem_main
          when :space_between
            if vis_count > 1
              step_gap = @gap + (rem_main / (vis_count - 1).to_f)
            end
          end
        end

        # 4. 各子要素のローカル座標 (x, y) を設定
        # Sprite の親子変換式: lx = (p.anchor_x - p.pivot_x)*pw + child.x
        # 親の左上からのオフセット ox, oy に対し、子の左上を合わせるには:
        # child.x = ox - p.anchor_x * pw + child.anchor_x * cw
        pw = width
        ph = height
        pax = @anchor_x * pw
        pay = @anchor_y * ph

        i = 0
        while i < len
          c = ch_list[i]
          if c.is_a?(Widget) && c.visible && !c.vanished?
            cw = c.width
            ch = c.height
            c_align = c.align_self || @align

            cross_pos = is_row ? inner_y : inner_x
            c_cross_size = is_row ? ch : cw
            case c_align
            when :center
              cross_pos += (cross_avail - c_cross_size) * 0.5
            when :end
              cross_pos += (cross_avail - c_cross_size)
            end

            ox = is_row ? cursor_main : cross_pos
            oy = is_row ? cross_pos : cursor_main

            c.x = ox - pax + c.anchor_x * cw
            c.y = oy - pay + c.anchor_y * ch

            cursor_main += (is_row ? cw : ch) + step_gap
          end
          i += 1
        end

        # @layout_dirty が子のサイズ変更で再度立った場合はクリア
        @layout_dirty = false
      end

      private

      def parse_padding(pad)
        if pad.is_a?(Array)
          if pad.length == 2
            @pad_left = @pad_right = pad[0].to_f
            @pad_top = @pad_bottom = pad[1].to_f
          elsif pad.length >= 4
            @pad_left   = pad[0].to_f
            @pad_top    = pad[1].to_f
            @pad_right  = pad[2].to_f
            @pad_bottom = pad[3].to_f
          else
            @pad_left = @pad_top = @pad_right = @pad_bottom = (pad[0] || 0.0).to_f
          end
        else
          v = pad ? pad.to_f : 0.0
          @pad_left = @pad_top = @pad_right = @pad_bottom = v
        end
      end
    end

    # VBox (縦並び Flexbox ショートカット)
    class VBox < Box
      def initialize(x = 0.0, y = 0.0, **opts, &block)
        super(x, y, direction: :column, **opts, &block)
      end
    end

    # HBox (横並び Flexbox ショートカット)
    class HBox < Box
      def initialize(x = 0.0, y = 0.0, **opts, &block)
        super(x, y, direction: :row, **opts, &block)
      end
    end

    # ==========================================================================
    # Panel (SDF カード背景 + タイトル + Flexbox レイアウトを持つコンテナ)
    # ==========================================================================
    class Panel < Box
      attr_accessor :title, :bg_color, :border_color, :border_width, :radius, :shadow_blur, :shadow_color, :title_size, :title_color

      def initialize(x = 0.0, y = 0.0, width: 320.0, height: 240.0,
                     title: "", padding: 14.0, gap: 8.0,
                     direction: :column, align: :stretch, justify: :start,
                     auto_layout: true, clip: false,
                     bg_color: nil, border_color: nil, border_width: nil,
                     radius: nil, shadow_blur: nil, shadow_color: nil,
                     title_size: 16, title_color: nil,
                     interactive: true, **opts, &block)
        @title        = title.to_s
        @bg_color     = bg_color
        @border_color = border_color
        @border_width = border_width
        @radius       = radius
        @shadow_blur  = shadow_blur
        @shadow_color = shadow_color
        @title_size   = title_size.to_i
        @title_color  = title_color

        super(x, y, width: width, height: height,
              direction: direction, padding: padding, gap: gap,
              align: align, justify: justify,
              auto_layout: auto_layout, clip: clip,
              interactive: interactive, **opts, &block)

        update_header_height
      end

      def title=(val)
        @title = val.to_s
        update_header_height
        mark_layout_dirty!
      end

      def update_header_height
        @header_height = @title.empty? ? 0.0 : (@title_size.to_f + 10.0)
      end

      def clip_bounds
        l = screen_left
        t = screen_top
        w = screen_width
        h = screen_height
        [l + 2.0, t + @header_height + 2.0, [w - 4.0, 0.0].max, [h - @header_height - 4.0, 0.0].max]
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height

        b_cfg = th.win_border_normal || th.border_normal
        s_cfg = th.shadow_normal

        rad   = @radius ? @radius.to_f : (th.corner_radius || 6.0).to_f
        bg    = @bg_color || th.win_bg || th.bg_normal
        bw    = @border_width ? @border_width.to_f : (b_cfg ? b_cfg[0].to_f : 1.0)
        bc    = @border_color || (b_cfg ? b_cfg[1] : nil)
        sblur = @shadow_blur ? @shadow_blur.to_f : (s_cfg ? s_cfg[0].to_f : 0.0)
        scol  = @shadow_color || (s_cfg ? s_cfg[1] : nil)

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: rad,
          color: bg,
          border_width: bw,
          border_color: bc,
          shadow_blur: sblur,
          shadow_color: scol,
          image: @image,
          angle: world_angle,
          camera: @camera,
          z: @z
        )

        unless @title.empty?
          f_font = th.font || Font.default
          tcol = @title_color || th.text_color
          Zenoo::Window.draw_text(
            rx + @pad_left, ry + @pad_top * 0.75,
            @title,
            font: f_font, size: @title_size, color: tcol,
            camera: @camera, z: @z
          )
        end
      end
    end

    # ==========================================================================
    # Window (ドラッグ移動・リサイズ・折りたたみ・最前面化に対応したフローティングウィンドウ)
    # ==========================================================================
    class Window < Panel
      attr_accessor :resizable, :collapsible, :draggable, :min_width, :min_height, :title_bar_height
      attr_reader :collapsed

      def initialize(title = "Window", x = 60.0, y = 60.0, width: 340.0, height: 260.0,
                     padding: 12.0, gap: 8.0,
                     direction: :column, align: :stretch, justify: :start,
                     auto_layout: true, clip: true,
                     resizable: false, collapsible: true, draggable: true,
                     min_width: 140.0, min_height: 90.0,
                     **opts, &block)
        @title_bar_height = 34.0
        @resizable        = resizable
        @collapsible      = collapsible
        @draggable        = draggable
        @min_width        = min_width.to_f
        @min_height       = min_height.to_f
        @collapsed        = false
        @expanded_height  = height.to_f

        @drag_mode        = nil # :move, :resize, :collapse_btn
        @drag_start_mx    = 0.0
        @drag_start_my    = 0.0
        @drag_orig_x      = 0.0
        @drag_orig_y      = 0.0
        @drag_orig_w      = 0.0
        @drag_orig_h      = 0.0
        @last_click_time  = -10.0
        @btn_hover        = false

        super(x, y, width: width, height: height,
              title: title, padding: padding, gap: gap,
              direction: direction, align: align, justify: justify,
              auto_layout: auto_layout, clip: clip,
              interactive: true, **opts, &block)
      end

      def update_header_height
        @header_height = @title_bar_height || 34.0
      end

      def collapsed=(val)
        v = !!val
        return if @collapsed == v
        @collapsed = v
        if @collapsed
          @expanded_height = [height, @min_height].max
          self.height = @title_bar_height
        else
          self.height = [@expanded_height, @min_height].max
        end
      end

      def toggle_collapse!
        self.collapsed = !@collapsed
      end

      def active_window?
        return true unless @parent
        ch = @parent.children
        return true unless ch
        ch.last.equal?(self)
      end

      # 親の children 配列の末尾に移動させ、描画順とヒットテストを最前面にする
      def bring_to_front!
        return unless (p = @parent)
        ch = p.children
        return unless ch && ch.length > 1
        if !ch.last.equal?(self)
          ch.delete(self)
          ch << self
        end
      end

      def clip_bounds
        return [0.0, 0.0, 0.0, 0.0] if @collapsed
        l = screen_left
        t = screen_top
        w = screen_width
        h = screen_height
        [l + 2.0, t + @title_bar_height + 2.0, [w - 4.0, 0.0].max, [h - @title_bar_height - 4.0, 0.0].max]
      end

      def find_hit_widget(px, py)
        return nil if @vanished || !@visible || !@enabled

        # リサイズハンドルまたはタイトルバー上のボタンは子要素より優先してウィンドウ自身が受け取る
        if !@collapsed && @resizable && in_resize_grip?(px, py)
          return self
        end

        unless @collapsed
          if (ch_list = @children)
            cx, cy, cw, ch = clip_bounds
            if !@clip_children || (px >= cx && px <= (cx + cw) && py >= cy && py <= (cy + ch))
              i = ch_list.length - 1
              while i >= 0
                c = ch_list[i]
                if c.is_a?(Widget) && !c.vanished?
                  hit = c.find_hit_widget(px, py)
                  return hit if hit
                end
                i -= 1
              end
            end
          end
        end

        return self if hit_test_self?(px, py)
        nil
      end

      def set_hovered_state(val)
        @hovered = val
        @btn_hover = false
        return unless val && @enabled && @interactive

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        if @collapsible && in_collapse_button?(mx, my)
          @btn_hover = true
          UI.set_mouse_cursor(:hand)
        elsif !@collapsed && @resizable && in_resize_grip?(mx, my)
          UI.set_mouse_cursor(:resize_nwse)
        elsif @draggable && in_title_bar?(mx, my)
          UI.set_mouse_cursor(:hand)
        else
          UI.set_mouse_cursor(:arrow)
        end
      end

      def on_pointer_down(mx, my)
        super
        bring_to_front!

        if @collapsible && in_collapse_button?(mx, my)
          @drag_mode = :collapse_btn
          return
        end

        if !@collapsed && @resizable && in_resize_grip?(mx, my)
          @drag_mode = :resize
          @drag_start_mx = mx
          @drag_start_my = my
          @drag_orig_w = width
          @drag_orig_h = height
          return
        end

        if in_title_bar?(mx, my)
          now = Zenoo::Window.real_time
          if @collapsible && (now - @last_click_time) < 0.32
            toggle_collapse!
            @last_click_time = -10.0
            @drag_mode = nil
            return
          end
          @last_click_time = now

          if @draggable
            @drag_mode = :move
            @drag_start_mx = mx
            @drag_start_my = my
            @drag_orig_x = @x
            @drag_orig_y = @y
          end
        else
          @drag_mode = nil
        end
      end

      def on_pointer_drag(mx, my)
        case @drag_mode
        when :move
          UI.set_mouse_cursor(:hand)
          psx = @parent ? @parent.world_scale_x : 1.0
          psy = @parent ? @parent.world_scale_y : 1.0
          dx = (mx - @drag_start_mx) / (psx.abs > 0.0001 ? psx : 1.0)
          dy = (my - @drag_start_my) / (psy.abs > 0.0001 ? psy : 1.0)
          self.x = @drag_orig_x + dx
          self.y = @drag_orig_y + dy
        when :resize
          UI.set_mouse_cursor(:resize_nwse)
          psx = world_scale_x
          psy = world_scale_y
          dw = (mx - @drag_start_mx) / (psx.abs > 0.0001 ? psx : 1.0)
          dh = (my - @drag_start_my) / (psy.abs > 0.0001 ? psy : 1.0)
          self.width  = [@drag_orig_w + dw, @min_width].max
          self.height = [@drag_orig_h + dh, @min_height].max
          @expanded_height = height
        end
      end

      def on_pointer_up(mx, my, inside)
        if @drag_mode == :collapse_btn && in_collapse_button?(mx, my)
          toggle_collapse!
        end
        @drag_mode = nil
        super
      end

      def draw
        return if @vanished || !@visible

        draw_self
        if !@collapsed && @children
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
      end

      def draw_self
        th = theme
        wx = screen_left
        wy = screen_top
        ww = screen_width
        wh = screen_height
        th_bar = @title_bar_height * world_scale_y
        is_act = active_window?

        border_cfg = is_act ? (th.win_border_active || th.border_active) : (th.win_border_normal || th.border_normal)
        bw = border_cfg ? border_cfg[0].to_f : 1.5
        bc = border_cfg ? border_cfg[1] : th.accent_color

        shadow_cfg = is_act ? th.shadow_active : th.shadow_normal
        sblur = shadow_cfg ? shadow_cfg[0].to_f : 0.0
        scol  = shadow_cfg ? shadow_cfg[1] : nil
        win_bg = @bg_color || th.win_bg || th.bg_normal
        rad    = @radius ? @radius.to_f : (th.corner_radius || 6.0).to_f

        # ウィンドウ背景カード
        Zenoo::Window.draw_rect(
          wx, wy, ww, wh,
          radius: rad,
          color: win_bg,
          border_width: bw,
          border_color: bc,
          shadow_blur: sblur,
          shadow_color: scol,
          camera: @camera,
          z: @z
        )

        # タイトルバー帯
        title_bg = is_act ? (th.win_title_bg_active || th.bg_active) : (th.win_title_bg || th.bg_hover)
        t_rad = [rad - 1.0, 0.0].max
        Zenoo::Window.draw_rect(
          wx + 1.0, wy + 1.0, ww - 2.0, th_bar,
          radius: t_rad,
          color: title_bg,
          camera: @camera,
          z: @z
        )

        # タイトルバー境界線
        unless @collapsed
          Zenoo::Window.draw_line(
            wx + 1.0, wy + th_bar + 1.0,
            wx + ww - 1.0, wy + th_bar + 1.0,
            color: bc,
            camera: @camera,
            z: @z
          )
        end

        # タイトルテキスト
        unless @title.empty?
          f_font = th.font || Font.default
          f_size = 14
          tcol = is_act ? th.text_color : (th.text_disabled || th.text_color)
          Zenoo::Window.draw_text(
            wx + 12.0, wy + (th_bar - f_size.to_f) * 0.5 + 1.0,
            @title,
            font: f_font, size: f_size, color: tcol,
            camera: @camera, z: @z
          )
        end

        # 折りたたみボタン
        if @collapsible
          btn_size = 22.0
          bx = wx + ww - btn_size - 7.0
          by = wy + (th_bar - btn_size) * 0.5
          icon_col = is_act ? (th.text_color || Color::WHITE) : (th.text_disabled || Color.new(160, 160, 165))

          if @btn_hover
            Zenoo::Window.draw_rect(bx, by, btn_size, btn_size, radius: 4.0, color: Color.new(255, 255, 255, 45), camera: @camera, z: @z)
          end

          if @collapsed
            Zenoo::Window.draw_rect(bx + 5.0, by + 5.0, 12.0, 12.0, radius: 2.0, color: nil, border_width: 1.5, border_color: icon_col, camera: @camera, z: @z)
          else
            Zenoo::Window.draw_line(bx + 5.0, by + 11.0, bx + 17.0, by + 11.0, color: icon_col, width: 2.0, camera: @camera, z: @z)
          end
        end

        # リサイズグリップ
        if @resizable && !@collapsed
          rx = wx + ww - 15.0
          ry = wy + wh - 15.0
          Zenoo::Window.draw_line(rx + 8.0, ry + 12.0, rx + 12.0, ry + 8.0, color: bc, width: 1.5, camera: @camera, z: @z)
          Zenoo::Window.draw_line(rx + 4.0, ry + 12.0, rx + 12.0, ry + 4.0, color: bc, width: 1.5, camera: @camera, z: @z)
          Zenoo::Window.draw_line(rx + 0.0, ry + 12.0, rx + 12.0, ry + 0.0, color: bc, width: 1.5, camera: @camera, z: @z)
        end
      end

      private

      def in_title_bar?(px, py)
        l = screen_left
        t = screen_top
        w = screen_width
        th_bar = @title_bar_height * world_scale_y
        px >= l && px <= (l + w) && py >= t && py <= (t + th_bar)
      end

      def in_collapse_button?(px, py)
        l = screen_left
        t = screen_top
        w = screen_width
        th_bar = @title_bar_height * world_scale_y
        btn_size = 22.0
        bx = l + w - btn_size - 7.0
        by = t + (th_bar - btn_size) * 0.5
        px >= bx && px <= (bx + btn_size) && py >= by && py <= (by + btn_size)
      end

      def in_resize_grip?(px, py)
        l = screen_left
        t = screen_top
        w = screen_width
        h = screen_height
        g = 18.0
        px >= (l + w - g) && px <= (l + w) && py >= (t + h - g) && py <= (t + h)
      end
    end

    # ==========================================================================
    # ScrollView (ハードウェアクリッピング + スクロールバー + ホイール対応コンテナ)
    # ==========================================================================
    class ScrollView < Box
      attr_reader :scroll_y, :content_height
      attr_accessor :scrollbar_width, :wheel_step

      def initialize(x = 0.0, y = 0.0, width: 300.0, height: 220.0,
                     padding: 10.0, gap: 8.0,
                     direction: :column, align: :stretch, justify: :start,
                     content_height: nil, wheel_step: 32.0,
                     **opts, &block)
        @scroll_y             = 0.0
        @fixed_content_height = content_height ? content_height.to_f : nil
        @content_height       = @fixed_content_height || 0.0
        @scrollbar_width      = 12.0
        @wheel_step           = wheel_step.to_f
        @dragging_scrollbar   = false
        @sb_hover             = false

        super(x, y, width: width, height: height,
              direction: direction, padding: padding, gap: gap,
              align: align, justify: justify,
              auto_layout: true, clip: true,
              interactive: true, **opts, &block)
      end

      def scroll_y=(val)
        max_s = max_scroll
        new_y = [[val.to_f, 0.0].max, max_s].min
        return if (@scroll_y - new_y).abs < 0.001
        @scroll_y = new_y
        mark_layout_dirty!
      end

      def view_height
        [height - 4.0, 1.0].max
      end

      def max_scroll
        [@content_height - view_height, 0.0].max
      end

      def needs_scrollbar?
        max_scroll > 0.5
      end

      def clip_bounds
        l = screen_left
        t = screen_top
        w = screen_width
        h = screen_height
        sb_w = needs_scrollbar? ? (@scrollbar_width + 4.0) * world_scale_x : 0.0
        [l + 2.0, t + 2.0, [w - sb_w - 4.0, 0.0].max, [h - 4.0, 0.0].max]
      end

      def find_hit_widget(px, py)
        return nil if @vanished || !@visible || !@enabled

        # スクロールバー領域上なら ScrollView 自身が受け取る
        if needs_scrollbar? && in_scrollbar_track?(px, py)
          return self
        end

        super(px, py)
      end

      def set_hovered_state(val)
        @hovered = val
        @sb_hover = false
        return unless val && @enabled && @interactive

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        if needs_scrollbar? && in_scrollbar_track?(mx, my)
          @sb_hover = true
          UI.set_mouse_cursor(:hand)
        else
          UI.set_mouse_cursor(:arrow)
        end
      end

      def on_mouse_wheel(wheel_y)
        return false unless needs_scrollbar?
        old_s = @scroll_y
        self.scroll_y = @scroll_y - wheel_y * @wheel_step
        (@scroll_y - old_s).abs > 0.001 || true
      end

      def on_pointer_down(mx, my)
        super
        if needs_scrollbar? && in_scrollbar_track?(mx, my)
          @dragging_scrollbar = true
          update_scroll_from_mouse(my)
        else
          @dragging_scrollbar = false
        end
      end

      def on_pointer_drag(_mx, my)
        if @dragging_scrollbar
          UI.set_mouse_cursor(:hand)
          update_scroll_from_mouse(my)
        end
      end

      def on_pointer_up(mx, my, inside)
        @dragging_scrollbar = false
        super
      end

      def perform_layout
        @layout_dirty = false
        ch_list = @children
        return unless ch_list && !ch_list.empty?

        # まずスクロールバーの有無を考慮した内側幅で子要素を配置し、コンテンツ総高さを計測
        sb_reserve = (@scrollbar_width + 4.0)
        inner_x = @pad_left
        inner_w = [width - @pad_left - @pad_right - sb_reserve, 10.0].max

        pw = width
        ph = height
        pax = @anchor_x * pw
        pay = @anchor_y * ph

        cur_y = @pad_top
        vis_count = 0
        i = 0
        len = ch_list.length
        while i < len
          c = ch_list[i]
          if c.is_a?(Widget) && c.visible && !c.vanished?
            vis_count += 1
            c_align = c.align_self || @align
            if c_align == :stretch
              c.width = inner_w if c.width != inner_w
            end
            cw = c.width
            ch = c.height

            ox = inner_x
            if c_align == :center
              ox += (inner_w - cw) * 0.5
            elsif c_align == :end
              ox += (inner_w - cw)
            end

            oy = cur_y - @scroll_y
            c.x = ox - pax + c.anchor_x * cw
            c.y = oy - pay + c.anchor_y * ch

            cur_y += ch + @gap
          end
          i += 1
        end

        measured_h = vis_count > 0 ? (cur_y - @gap + @pad_bottom) : 0.0
        @content_height = @fixed_content_height ? [@fixed_content_height, measured_h].max : measured_h

        # 最大スクロール量を超えている場合はクランプして再配置
        max_s = max_scroll
        if @scroll_y > max_s
          @scroll_y = max_s
          cur_y = @pad_top
          i = 0
          while i < len
            c = ch_list[i]
            if c.is_a?(Widget) && c.visible && !c.vanished?
              ch = c.height
              oy = cur_y - @scroll_y
              c.y = oy - pay + c.anchor_y * ch
              cur_y += ch + @gap
            end
            i += 1
          end
        end

        @layout_dirty = false
      end

      def draw
        return if @vanished || !@visible

        draw_self
        if @children
          cx, cy, cw, ch = clip_bounds
          if cw > 0.0 && ch > 0.0
            prev_ox, prev_oy = Zenoo::Window.push_clip_scope(cx, cy, cw, ch, local: false, z: @z)
            draw_children
            Zenoo::Window.pop_clip_scope(prev_ox, prev_oy)
          end
        end
        draw_scrollbar_self if needs_scrollbar?
      end

      def draw_self
        th = theme
        rx = screen_left
        ry = screen_top
        rw = screen_width
        rh = screen_height
        track_b = th.track_border || th.border_normal

        Zenoo::Window.draw_rect(
          rx, ry, rw, rh,
          radius: th.corner_radius || 6.0,
          color: th.track_bg || th.bg_normal,
          border_width: track_b ? track_b[0].to_f : 1.0,
          border_color: track_b ? track_b[1] : nil,
          camera: @camera,
          z: @z
        )
      end

      def draw_scrollbar_self
        th = theme
        l = screen_left
        t = screen_top
        w = screen_width
        h = screen_height
        sb_w = @scrollbar_width * world_scale_x
        sb_x = l + w - sb_w - 3.0
        sb_y = t + 3.0
        sb_h = [h - 6.0, 10.0].max

        # トラック
        Zenoo::Window.draw_rect(sb_x, sb_y, sb_w, sb_h, radius: sb_w * 0.5, color: Color.new(15, 18, 25, 180), camera: @camera, z: @z)

        tot = [@content_height, 1.0].max
        vw  = view_height
        thumb_h = [[(vw / tot) * sb_h, 22.0].max, sb_h].min
        max_s = max_scroll
        ratio = max_s > 0.0 ? (@scroll_y / max_s) : 0.0
        thumb_y = sb_y + ratio * (sb_h - thumb_h)

        thumb_col = if @dragging_scrollbar
                      th.accent_hover || th.accent_color
                    elsif @sb_hover
                      th.accent_color
                    else
                      th.border_hover ? th.border_hover[1] : th.bg_active
                    end

        Zenoo::Window.draw_rect(
          sb_x + 2.0, thumb_y, sb_w - 4.0, thumb_h,
          radius: (sb_w - 4.0) * 0.5,
          color: thumb_col,
          camera: @camera,
          z: @z
        )
      end

      private

      def in_scrollbar_track?(px, py)
        l = screen_left
        t = screen_top
        w = screen_width
        h = screen_height
        sb_w = (@scrollbar_width + 6.0) * world_scale_x
        px >= (l + w - sb_w) && px <= (l + w) && py >= t && py <= (t + h)
      end

      def update_scroll_from_mouse(my)
        t = screen_top + 3.0
        sb_h = [screen_height - 6.0, 10.0].max
        tot = [@content_height, 1.0].max
        vw  = view_height
        thumb_h = [[(vw / tot) * sb_h, 22.0].max, sb_h].min
        avail = [sb_h - thumb_h, 1.0].max
        ratio = (my - (t + thumb_h * 0.5)) / avail
        ratio = 0.0 if ratio < 0.0
        ratio = 1.0 if ratio > 1.0
        self.scroll_y = ratio * max_scroll
      end
    end
  end
end

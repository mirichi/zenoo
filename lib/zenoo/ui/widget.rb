# frozen_string_literal: true

module Zenoo
  module UI
    # Sprite ベースの軽量 UI 基底クラス
    class Widget < Sprite
      attr_reader :interactive
      attr_accessor :enabled, :clip_children, :flex

      # ウィジェットを初期化する
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

      # 当たり判定の有効・無効を設定する
      def interactive=(v)
        @interactive = !!v
        set_default_collider if @interactive && !@collider_shape
      end

      def collider_radius = nil

      # 自身のサイズやテーマに合わせてコライダー形状を同期する
      def sync_collider_shape
        col = @collider_shape
        return unless col && col.shape_type == Collision::TYPE_RECT
        if (rad = collider_radius)
          col.radius = rad
        end
      end

      # 既定コライダーを設定する
      def set_default_collider
        rad = collider_radius
        if rad && rad > 0.0
          set_collider(:rect, radius: rad)
        else
          set_collider(:default)
        end
      end

      # 適用されるテーマを取得する（親からの継承または UI グローバルテーマ）
      def theme
        @theme || (@parent.is_a?(Widget) ? @parent.theme : UI.theme)
      end

      # このウィジェット用の個別テーマを設定する
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

      # 祖先を含めてツリーが有効（表示・enabled・未消滅）かを返す
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

      # 所属している最寄りの Stage を辿る
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

      # カスタム描画ブロックを設定する
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

      # 子ウィジェットを追加する
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

      # 自身への当たり判定 (Sprite の Collider による統合判定)
      def hit_test_self?(px, py)
        return false if @vanished || !@visible || !@enabled || !@interactive
        col = self.collider
        return false unless col
        Collision.check(UI.point_collider(px, py), col)
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

      # 指定の子を最前面（描画配列の末尾）へ移動する
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

    # クリック操作を提供するミックスイン
    module Clickable
      def pressed? = !!@pressed
      def clicked? = @clicked_frame == UI.frame
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
        @clicked_frame = UI.frame
        @on_click_proc&.call(self)
      end
    end

    # ドラッグ操作を提供するミックスイン
    module Draggable
      def drag_target
        @drag_target_initialized ? @drag_target : self
      end

      def drag_target=(target)
        @drag_target_initialized = true
        @drag_target = target
      end

      def dragging?    = !!@dragging
      def on_drag_start(_mx, _my); end
      def on_drag(_dx, _dy);       end
      def on_drag_end;             end

      def on_pointer_down(mx, my)
        @dragging = true
        @drag_start_mx = mx
        @drag_start_my = my
        @drag_offset_x = 0.0
        @drag_offset_y = 0.0
        if (tgt = drag_target)
          @drag_origin_x = tgt.x
          @drag_origin_y = tgt.y
        end
        on_drag_start(mx, my)
        super
      end

      def on_pointer_drag(mx, my)
        if @dragging
          dx = mx - @drag_start_mx
          dy = my - @drag_start_my
          @drag_offset_x = dx
          @drag_offset_y = dy
          if (tgt = drag_target)
            tgt.x = @drag_origin_x + dx
            tgt.y = @drag_origin_y + dy
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

    # キーボードフォーカス対象を表すミックスイン
    module Focusable
      def can_focus? = @enabled
      def focus!     = (stage&.set_focus(self); self)
      def blur!      = (stage&.set_focus(nil) if focused?; self)
    end

    # 縦スクロール操作を提供するミックスイン
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
  end
end

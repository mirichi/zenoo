# frozen_string_literal: true

module Zenoo
  module UI
    # Sprite ベースの保持モード (Retained Mode) UI ウィジェット基底クラス
    class Widget < Sprite
      attr_accessor :enabled, :interactive, :clip_children, :flex, :align_self, :id, :tooltip
      attr_reader :hovered, :pressed, :clicked, :changed

      def initialize(x = 0.0, y = 0.0, width: 100.0, height: 32.0,
                     anchor: :top_left, pivot: :center, z: 0.0,
                     camera: false, parent: nil,
                     enabled: true, interactive: true,
                     flex: nil, align_self: nil, id: nil, theme: nil)
        super(x, y, nil, width: width, height: height, anchor: anchor, pivot: pivot, z: z, camera: camera, parent: nil)
        @enabled       = enabled
        @interactive   = interactive
        @clip_children = false
        @flex          = flex ? flex.to_f : nil
        @align_self    = align_self
        @id            = id
        @theme         = theme

        @hovered = false
        @pressed = false
        @clicked = false
        @changed = false

        @on_click_proc  = nil
        @on_change_proc = nil
        @on_draw_proc   = nil

        self.parent = parent if parent
      end

      def theme
        @theme || (@parent.is_a?(Widget) ? @parent.theme : UI.theme)
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
      end

      def hovered?
        @hovered
      end

      def pressed?
        @pressed
      end

      def clicked?
        @clicked
      end

      def changed?
        @changed
      end

      def focused?
        UI.focused_widget.equal?(self)
      end

      def focus!
        UI.focused_widget = self
        self
      end

      def blur!
        UI.clear_focus if focused?
        self
      end

      def on_click(&block)
        @on_click_proc = block
        self
      end

      def on_change(&block)
        @on_change_proc = block
        self
      end

      def on_draw(&block)
        @on_draw_proc = block
        self
      end

      # 子ウィジェットの追加 (add / <<)
      # @param child [Widget] 追加するウィジェット
      # @return [Widget] 追加した child 自身
      def add(child, &block)
        return nil unless child
        child.parent = self
        block.call(child) if block
        child
      end

      def <<(child, &block)
        add(child, &block)
      end

      def on_focus
      end

      def on_blur
      end

      # 状態を応じた視覚ステート (:normal, :hover, :active, :disabled)
      def visual_state
        return :disabled unless @enabled
        return :active if @pressed
        return :hover if @hovered
        :normal
      end

      # ワールド空間での描画左上座標 (Pivot 中心スケーリング考慮)
      def screen_left
        world_pivot_x - @pivot_x * width * world_scale_x
      end

      def screen_top
        world_pivot_y - @pivot_y * height * world_scale_y
      end

      def screen_width
        width * world_scale_x
      end

      def screen_height
        height * world_scale_y
      end

      # 自身のクリッピング矩形 [x, y, w, h] (clip_children が有効なコンテナでオーバーライド可)
      def clip_bounds
        [screen_left, screen_top, screen_width, screen_height]
      end

      # 親を辿り、すべての clip_children スコープ内に (px, py) が収まっているか判定
      def point_in_ancestor_clips?(px, py)
        cur = @parent
        while cur
          if cur.is_a?(Widget) && cur.clip_children
            cx, cy, cw, ch = cur.clip_bounds
            return false if px < cx || px > (cx + cw) || py < cy || py > (cy + ch)
          end
          cur = cur.parent
        end
        true
      end

      # ワールド座標 (px, py) がこのウィジェット自身の領域内か判定
      def hit_test_self?(px, py)
        return false if @vanished || !@visible || !@enabled || !@interactive
        return false unless point_in_ancestor_clips?(px, py)

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

      # 子孫を含めた最前面のヒットウィジェットを逆順（手前から奥へ）探索
      def find_hit_widget(px, py)
        return nil if @vanished || !@visible || !@enabled

        if @clip_children
          cx, cy, cw, ch = clip_bounds
          if px >= cx && px <= (cx + cw) && py >= cy && py <= (cy + ch)
            if (ch_list = @children)
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
        elsif (ch_list = @children)
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

        return self if hit_test_self?(px, py)
        nil
      end

      # フレーム毎の状態リセット (ルートから再帰呼び出し)
      def reset_frame_flags
        @clicked = false
        @changed = false
        set_hovered_state(false) if @hovered
        if (ch_list = @children)
          i = 0
          len = ch_list.length
          while i < len
            c = ch_list[i]
            c.reset_frame_flags if c.is_a?(Widget)
            i += 1
          end
        end
      end

      # 親子のレイアウト計算フック
      def update_layout_tree
        if (ch_list = @children)
          i = 0
          len = ch_list.length
          while i < len
            c = ch_list[i]
            c.update_layout_tree if c.is_a?(Widget) && !c.vanished?
            i += 1
          end
        end
      end

      # フレーム更新 (ルートウィジェットに対して update を呼ぶとツリー全体が更新されます)
      def update
        return if @vanished || !@visible

        unless @parent.is_a?(Widget)
          reset_frame_flags
          update_layout_tree
          process_root_input
          update_layout_tree
        end

        update_self
        super
      end

      # 各ウィジェット固有の毎フレーム更新フック
      def update_self
      end

      # ルートウィジェットによるポインタ・ホイール・フォーカス入力の一括ディスパッチ
      def process_root_input
        # ImGui (デバッグUI) がマウスを掴んでいる場合は保持モードGUIへの入力を遮断
        return if defined?(ImGui) && ImGui.mouse_captured?

        mx = Input.mouse_x.to_f
        my = Input.mouse_y.to_f
        m_down = Input.mouse_pressed?(:left)
        m_push = Input.mouse_push?(:left)
        m_rel  = Input.mouse_release?(:left)
        wheel_y = Input.mouse_wheel_y.to_f

        # 0. 開いているポップアップ (Dropdown等) の優先処理
        if (pop = UI.open_popup_widget) && !pop.vanished? && pop.visible
          if pop.handle_popup_input(mx, my, m_push, m_down, m_rel, wheel_y)
            UI.mark_mouse_captured!
            Input.consume_mouse!
            return
          end
        end

        # 1. ドラッグ中 (active_widget) のウィジェットが自身のツリー内にある場合
        act = UI.active_widget
        if act && act.root.equal?(self)
          UI.mark_mouse_captured!
          Input.consume_mouse!
          in_self = act.hit_test_self?(mx, my)
          act.set_hovered_state(in_self)
          if m_rel || !m_down
            UI.active_widget = nil
            act.on_pointer_up(mx, my, in_self)
          else
            act.on_pointer_drag(mx, my)
          end
          return
        elsif act
          # 別のルートツリーがドラッグ中なら何もしない
          return
        end

        # 2. マウス直下の最前面ウィジェットを探索
        hit = find_hit_widget(mx, my)
        if hit
          UI.hovered_widget = hit
          UI.mark_mouse_captured!
          hit.set_hovered_state(true)

          # マウスホイールイベントをヒット箇所から親へバブリング
          if wheel_y != 0.0
            cur = hit
            while cur
              break if cur.is_a?(Widget) && cur.on_mouse_wheel(wheel_y)
              cur = cur.parent
            end
          end

          if m_push
            Input.consume_mouse!
            # ウィンドウのクリック時最前面化 (Bring to Front)
            hit.bring_ancestor_window_to_front!
            # フォーカス遷移
            if UI.focused_widget && !UI.focused_widget.equal?(hit)
              UI.clear_focus
            end
            UI.active_widget = hit
            hit.on_pointer_down(mx, my)
            if m_rel
              UI.active_widget = nil
              hit.on_pointer_up(mx, my, true)
            end
          end
        else
          if m_push && UI.focused_widget && UI.focused_widget.root.equal?(self)
            UI.clear_focus
          end
        end
      end

      def set_hovered_state(val)
        @hovered = val
        if val && @enabled && @interactive
          UI.set_mouse_cursor(hover_cursor_shape)
        end
      end

      def hover_cursor_shape
        :arrow
      end

      def bring_ancestor_window_to_front!
        cur = self
        while cur
          if cur.respond_to?(:bring_to_front!)
            cur.bring_to_front!
            break
          end
          cur = cur.parent
        end
      end

      # ポインタイベントハンドラ (サブクラスでオーバーライド)
      def on_pointer_down(_mx, _my)
        @pressed = true
      end

      def on_pointer_drag(_mx, _my)
      end

      def on_pointer_up(_mx, _my, inside)
        was_pressed = @pressed
        @pressed = false
        if was_pressed && inside && @enabled
          trigger_click!
        end
      end

      def on_mouse_wheel(_wheel_y)
        false
      end

      def trigger_click!
        @clicked = true
        @on_click_proc.call(self) if @on_click_proc
      end

      def trigger_change!(val = nil)
        @changed = true
        if @on_change_proc
          if @on_change_proc.arity == 0
            @on_change_proc.call
          else
            @on_change_proc.call(val)
          end
        end
      end

      # 描画
      def draw
        return if @vanished || !@visible

        update_layout_tree unless @parent.is_a?(Widget)

        if @on_draw_proc
          @on_draw_proc.call(screen_left, screen_top, screen_width, screen_height, visual_state)
        else
          draw_self
        end

        if @children
          perform_layout if respond_to?(:perform_layout) && @auto_layout && @layout_dirty
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
        super if @image
      end

      # width / height 変更時に親コンテナのレイアウトを再計算させる
      def width=(v)
        old_w = width
        super(v)
        if width != old_w && @parent.is_a?(Widget) && @parent.respond_to?(:mark_layout_dirty!)
          @parent.mark_layout_dirty!
        end
      end

      def height=(v)
        old_h = height
        super(v)
        if height != old_h && @parent.is_a?(Widget) && @parent.respond_to?(:mark_layout_dirty!)
          @parent.mark_layout_dirty!
        end
      end

      def visible=(v)
        old_v = @visible
        super(v)
        if @visible != old_v
          mark_layout_dirty! if respond_to?(:mark_layout_dirty!)
          if @parent.is_a?(Widget) && @parent.respond_to?(:mark_layout_dirty!)
            @parent.mark_layout_dirty!
          end
        end
      end

      def __add_child_internal(child)
        super(child)
        mark_layout_dirty! if respond_to?(:mark_layout_dirty!)
      end

      def __remove_child_internal(child)
        super(child)
        mark_layout_dirty! if respond_to?(:mark_layout_dirty!)
      end
    end
  end
end

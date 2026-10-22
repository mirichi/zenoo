# frozen_string_literal: true

module Zenoo
  module GUI
    # ウィンドウ状態オブジェクト (位置・サイズ・フォーカス・開閉状態)
    class WindowState
      attr_accessor :id, :title, :x, :y, :w, :h, :z, :open

      def initialize(id, title, x, y, w, h)
        @id    = id.to_s
        @title = title.to_s
        @x     = x.to_f
        @y     = y.to_f
        @w     = w.to_f
        @h     = h.to_f
        @z     = 0.0
        @open  = true
      end
    end

    # マルチウィンドウのZオーダー・ドラッグ移動・入力遮断を管理するクラス
    class WindowManager
      attr_reader :windows, :window_order, :hovered_window_id, :active_window_id, :current_window_id

      def initialize
        @windows            = {} # id => WindowState
        @window_order       = [] # [win_id, ...] (手前が末尾)
        @hovered_window_id  = nil
        @active_window_id   = nil
        @dragging_window_id = nil
        @drag_offset_x      = 0.0
        @drag_offset_y      = 0.0
        @current_window_id  = nil
      end

      def begin_frame(mouse_x, mouse_y, mouse_down, mouse_push)
        # 1. ウィンドウのドラッグ継続処理
        if @dragging_window_id
          if mouse_down && (win = @windows[@dragging_window_id])
            win.x = mouse_x - @drag_offset_x
            win.y = mouse_y - @drag_offset_y
          else
            @dragging_window_id = nil
          end
        end

        # 2. 前フレーム確定ウィンドウ情報に基づくマウス直下の最前面ウィンドウ特定
        if @dragging_window_id
          @hovered_window_id = @dragging_window_id
        else
          @hovered_window_id = nil
          @window_order.reverse_each do |wid|
            w = @windows[wid]
            next unless w && w.open
            if in_rect?(mouse_x, mouse_y, w.x, w.y, w.w, w.h)
              @hovered_window_id = wid
              break
            end
          end
        end

        # 3. ウィンドウクリック時の最前面化 (Bring to Front)
        if mouse_push
          if @hovered_window_id
            @active_window_id = @hovered_window_id
            @window_order.delete(@hovered_window_id)
            @window_order.push(@hovered_window_id)
          else
            @active_window_id = nil
          end
        end

        # 4. ウィンドウごとのベース Z 割り当て (奥から順に 100.0, 200.0, 300.0, ...)
        @window_order.each_with_index do |wid, idx|
          if (w = @windows[wid])
            w.z = 100.0 + idx * 100.0
          end
        end

        @current_window_id = nil
      end

      def find_or_create(win_id, title, x, y, w, h)
        win = @windows[win_id]
        unless win
          def_x = x ? x.to_f : (60.0 + (@windows.size * 30.0) % 400.0)
          def_y = y ? y.to_f : (60.0 + (@windows.size * 30.0) % 300.0)
          win = WindowState.new(win_id, title.to_s, def_x, def_y, w.to_f, h.to_f)
          @windows[win_id] = win
          @window_order.push(win_id)
          win.z = 100.0 + (@window_order.size - 1) * 100.0
        end
        win
      end

      def active?(win_id)
        @window_order.last == win_id
      end

      def check_drag_start(win, title_bar_h, mouse_x, mouse_y, mouse_push)
        return unless mouse_push && @hovered_window_id == win.id
        if in_rect?(mouse_x, mouse_y, win.x, win.y, win.w, title_bar_h)
          @dragging_window_id = win.id
          @drag_offset_x = mouse_x - win.x
          @drag_offset_y = mouse_y - win.y
        end
      end

      def with_window_context(win_id)
        prev_win_id = @current_window_id
        @current_window_id = win_id
        yield
        @current_window_id = prev_win_id
      end

      private

      def in_rect?(px, py, rx, ry, rw, rh)
        px >= rx && px <= (rx + rw) && py >= ry && py <= (ry + rh)
      end
    end
  end
end

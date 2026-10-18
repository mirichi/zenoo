# frozen_string_literal: true

require_relative 'gui/theme'
require_relative 'gui/renderer'
require_relative 'gui/card_renderer'
require_relative 'gui/layout'
require_relative 'gui/window_manager'
require_relative 'gui/text_edit'
require_relative 'gui/profile_graph'

module Zenoo
  # 即時モード (Immediate Mode) GUI システム
  module GUI
    @theme      = Theme.new
    @renderer   = CardRenderer.new
    @layout     = Layout.new
    @win_mgr    = WindowManager.new

    @mouse_x    = 0.0
    @mouse_y    = 0.0
    @mouse_down = false
    @mouse_push = false
    @mouse_rel  = false
    @hot_id     = nil
    @active_id  = nil
    @focus_id   = nil
    @cursor_pos = 0
    @blink_time = 0.0

    class << self
      attr_accessor :theme, :renderer
      attr_reader :layout, :focus_id

      def focus_id=(val)
        @focus_id = val ? val.to_s : nil
        @blink_time = 0.0
        Input.set_ime_position(-1, -1) unless @focus_id
      end

      def has_focus?(id)
        @focus_id == id.to_s
      end

      def clear_focus
        self.focus_id = nil
      end

      # --------------------------------------------------
      # ウィンドウ管理状態へのアクセサ (WindowManager へ委譲)
      # --------------------------------------------------
      def windows
        @win_mgr.windows
      end

      def window_order
        @win_mgr.window_order
      end

      def hovered_window_id
        @win_mgr.hovered_window_id
      end

      def active_window_id
        @win_mgr.active_window_id
      end

      # --------------------------------------------------
      # フレーム開始・終了処理 (Window.loop で毎フレーム自動呼び出し)
      # --------------------------------------------------
      def begin_frame
        @mouse_x    = Input.mouse_x.to_f
        @mouse_y    = Input.mouse_y.to_f
        @mouse_down = Input.mouse_pressed?(:left)
        @mouse_push = Input.mouse_push?(:left)
        @mouse_rel  = Input.mouse_release?(:left)
        @hot_id     = nil
        @blink_time = (@blink_time || 0.0) + Window.delta_time

        @win_mgr.begin_frame(@mouse_x, @mouse_y, @mouse_down, @mouse_push)
        @layout.reset
      end

      def end_frame
      end

      # --------------------------------------------------
      # レイアウト & カーソル操作 (Layout へ委譲)
      # --------------------------------------------------
      def cursor(x = nil, y = nil)
        @layout.cursor(x, y)
      end

      def set_cursor(x, y)
        @layout.cursor(x, y)
      end

      def cursor_x
        @layout.cursor_x
      end

      def cursor_x=(val)
        @layout.cursor_x = val
        val
      end

      def cursor_y
        @layout.cursor_y
      end

      def cursor_y=(val)
        @layout.cursor_y = val
        val
      end

      def spacing(x = nil, y = nil)
        @layout.spacing(x, y)
      end

      def spacing_x
        @layout.spacing_x
      end

      def spacing_x=(val)
        @layout.spacing_x = val
        val
      end

      def spacing_y
        @layout.spacing_y
      end

      def spacing_y=(val)
        @layout.spacing_y = val
        val
      end

      def advance_cursor(w, h)
        @layout.advance(w, h)
      end

      def spacer(size = 8.0)
        @layout.spacer(size)
      end

      # 横並びブロック (cols: N を指定するとコンテナ幅を N 等分した幅を自動割り当て)
      def row(spacing: -1.0, cols: nil, &block)
        @layout.row(spacing: spacing, cols: cols, &block)
      end

      # --------------------------------------------------
      # 座標・入力遮断ヘルパー
      # --------------------------------------------------
      def in_rect?(px, py, rx, ry, rw, rh)
        px >= rx && px <= (rx + rw) && py >= ry && py <= (ry + rh)
      end

      # コントロールの操作可否判定 (前面ウィンドウによる入力遮断 & クリップ範囲外遮断)
      def can_interact?
        # 1. ハードウェアクリッピング矩形外なら不可 (スクロールではみ出たコントロール等の遮断)
        clip = Backend.current_clip
        if clip
          return false unless in_rect?(@mouse_x, @mouse_y, clip[0], clip[1], clip[2], clip[3])
        end

        # 2. マウス直下の最前面ウィンドウと現在のウィジェット所属コンテキストが一致しているか
        @win_mgr.hovered_window_id == @win_mgr.current_window_id
      end

      # ローカル座標系対応のマウス座標
      def gui_mouse_x
        @mouse_x - Window.offset_x
      end

      def gui_mouse_y
        @mouse_y - Window.offset_y
      end

      # --------------------------------------------------
      # コンテナ (Panel / Window)
      # --------------------------------------------------
      # パネル (コンテナ枠)
      def panel(title = "", w: nil, h: 400.0, padding: 16.0,
                radius: -1.0, color: nil,
                border_width: nil, border_color: nil,
                shadow_blur: 8.0, shadow_color: Color.new(0, 0, 0, 120),
                z: 0.0, title_size: 18, title_color: nil, clip: false)
        px  = @layout.cursor_x
        py  = @layout.cursor_y
        pw  = @layout.resolve_width(w, 360.0)
        ph  = h.to_f
        pad = padding.to_f
        rad = (radius < 0.0) ? (@theme.corner_radius || 4.0).to_f : radius.to_f

        border_cfg = @theme.win_border_normal || @theme.border_normal
        b_width = border_width ? border_width.to_f : (border_cfg ? border_cfg[0].to_f : 1.0)
        b_color = border_color || (border_cfg ? border_cfg[1] : Color.new(70, 70, 75, 200))

        opts = {
          w: pw,
          h: ph,
          padding: pad,
          radius: rad,
          color: color || @theme.win_bg || Color.new(30, 30, 32, 245),
          border_width: b_width,
          border_color: b_color,
          shadow_blur: shadow_blur.to_f,
          shadow_color: shadow_color,
          z: z.to_f,
          title_size: title_size.to_i,
          title_color: title_color || @theme.text_color
        }

        @renderer.draw_panel(px, py, pw, ph, title, @theme, opts)

        if block_given?
          header_h  = title.to_s.empty? ? 0.0 : (title_size.to_i + @layout.spacing_y + 4.0)
          content_x = px + pad
          content_y = py + pad + header_h
          content_w = [pw - pad * 2.0, 0.0].max
          content_h = [ph - pad * 2.0 - header_h, 0.0].max

          @layout.container(content_x, content_y, content_w, content_h, clip: clip, z: z.to_f) do
            yield
          end
        end

        @layout.advance(pw, ph)
      end

      # フローティングウィンドウ (Window)
      # - ドラッグ移動、タイトルバー、最前面フォーカス切り替え
      # - Window.clip(local: true) によるコンテンツのビューポートクリッピング
      def window(title, x: nil, y: nil, w: 320.0, h: 240.0, id: "", padding: 12.0)
        win_id = id.to_s.empty? ? title.to_s : id.to_s
        win = @win_mgr.find_or_create(win_id, title, x, y, w, h)
        return unless win.open

        wx = win.x
        wy = win.y
        ww = win.w
        wh = win.h
        title_bar_h = 36.0
        pad = padding.to_f
        is_active = @win_mgr.active?(win_id)
        win_z = win.z

        # タイトルバーのドラッグ開始判定
        @win_mgr.check_drag_start(win, title_bar_h, @mouse_x, @mouse_y, @mouse_push)

        # 1. ウィンドウ全体の装飾描画 (Renderer へ委譲)
        @renderer.draw_window(wx, wy, ww, wh, win.title, is_active, @theme, z: win_z, title_bar_h: title_bar_h)

        # 2. コンテンツ領域のクリッピング & レイアウトスコープ
        return unless block_given?

        content_x = wx + pad
        content_y = wy + title_bar_h + 8.0
        content_w = [ww - pad * 2.0, 0.0].max
        content_h = [wh - title_bar_h - pad - 8.0, 0.0].max

        @win_mgr.with_window_context(win_id) do
          @layout.container(content_x, content_y, content_w, content_h, clip: true, z: win_z + 10.0) do
            yield win
          end
        end
      end

      # --------------------------------------------------
      # ウィジェット (Button / Slider / Label / TextBox / Divider / ProfileGraph)
      # --------------------------------------------------
      # ボタン (クリックされた瞬間のみ true を返却)
      def button(label, w: nil, h: 40.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = @layout.cursor_x
        ry = @layout.cursor_y
        rw = @layout.resolve_width(w, 140.0)
        rh = h.to_f

        hover = can_interact? && @renderer.hit_test_button(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)
        clicked = false

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            clicked = true if hover
            @active_id = nil
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            if @mouse_rel
              clicked = true
            else
              @active_id = widget_id
            end
          end
        end

        state = widget_visual_state(widget_id, hover, active_requires_hover: true)
        @renderer.draw_button(rx, ry, rw, rh, label, state, @theme)
        @layout.advance(rw, rh)
        clicked
      end

      # スライダー (マウスドラッグで値を変更し、更新された Float 値を返却)
      def slider(label, value, min, max, w: nil, h: 32.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = @layout.cursor_x
        ry = @layout.cursor_y
        rw = @layout.resolve_width(w, 200.0)
        rh = h.to_f
        v_val = value.to_f
        v_min = min.to_f
        v_max = max.to_f

        hover = can_interact? && @renderer.hit_test_slider(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            @active_id = nil
          else
            v_val = calc_slider_value(rx, rw, v_min, v_max)
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            v_val = calc_slider_value(rx, rw, v_min, v_max)
            @active_id = widget_id unless @mouse_rel
          end
        end

        state = widget_visual_state(widget_id, hover, active_requires_hover: false)
        @renderer.draw_slider(rx, ry, rw, rh, label, v_val, v_min, v_max, state, @theme)
        @layout.advance(rw, rh)
        v_val
      end

      # ラベル (テキストを描画)
      def label(text, size: 18, color: Color::WHITE)
        rx = @layout.cursor_x
        ry = @layout.cursor_y
        f_size = size.to_i

        @renderer.draw_label(rx, ry, text, f_size, color, @theme)

        f_font = @theme.font || Font.default
        w = f_font.text_width(text.to_s, f_size)
        h = f_size.to_f
        @layout.advance(w, h)
        nil
      end

      # 水平区切り線 (Divider)
      def divider(w: nil, color: nil, spacing: 6.0)
        rx = @layout.cursor_x
        ry = @layout.cursor_y + spacing.to_f
        rw = @layout.resolve_width(w, 200.0)
        border_cfg = @theme.border_normal
        line_col = color || (border_cfg ? border_cfg[1] : Color.new(70, 70, 75, 180))

        Window.draw_line(rx, ry, rx + rw, ry, color: line_col, width: 1.0)
        @layout.advance(rw, spacing.to_f * 2.0 + 1.0)
        nil
      end

      # テキストボックス (フォーカス中に文字入力・キー操作を受け付け、更新された文字列を返却)
      def text_box(label, text, w: nil, h: 42.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = @layout.cursor_x
        ry = @layout.cursor_y
        rw = @layout.resolve_width(w, 200.0)
        rh = h.to_f
        cur_text = text.to_s

        hover = can_interact? && @renderer.hit_test_text_box(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)

        if @mouse_push
          if hover
            @focus_id = widget_id
            @blink_time = 0.0
            click_x = gui_mouse_x - (rx + 10.0)
            @cursor_pos = TextEdit.caret_index_from_click(cur_text, click_x, @theme)
          elsif @focus_id == widget_id
            clear_focus
          end
        end

        cur_text = cur_text.dup
        is_focused = (@focus_id == widget_id)

        if is_focused
          cur_text, @cursor_pos, reset_blink, unfocus =
            TextEdit.process_focused_input(cur_text, @cursor_pos, rx, ry, rh, @theme)
          @blink_time = 0.0 if reset_blink
          clear_focus if unfocus
          is_focused = (@focus_id == widget_id)
        end

        bt = @blink_time || 0.0
        blink_on = (bt % 1.0) < 0.5
        @renderer.draw_text_box(rx, ry, rw, rh, cur_text, is_focused, @cursor_pos || 0, blink_on, @theme)
        @layout.advance(rw, rh)
        cur_text
      end

      # プロファイルグラフ (Profile Graph / Frame Time Histogram)
      def profile_graph(w: nil, h: 80.0, max_ms: 33.33, show_legend: true, id: "")
        rx = @layout.cursor_x
        ry = @layout.cursor_y
        rw = @layout.resolve_width(w, 280.0)
        rh = h.to_f

        total_h = ProfileGraph.draw(
          rx, ry, rw, rh, max_ms.to_f, show_legend,
          can_interact?, gui_mouse_x, gui_mouse_y, @theme
        )
        @layout.advance(rw, total_h)
        nil
      end

      private

      def widget_visual_state(widget_id, hover, active_requires_hover: true)
        if @active_id == widget_id
          return :active if !active_requires_hover || hover
          :normal
        elsif @active_id.nil? && hover
          :hover
        else
          :normal
        end
      end

      def calc_slider_value(rx, rw, v_min, v_max)
        ratio = (gui_mouse_x - rx) / rw
        ratio = 0.0 if ratio < 0.0
        ratio = 1.0 if ratio > 1.0
        v_min + ratio * (v_max - v_min)
      end
    end
  end
end

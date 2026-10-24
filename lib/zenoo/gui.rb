# frozen_string_literal: true

require_relative 'gui/theme'
require_relative 'gui/renderer'
require_relative 'gui/card_renderer'
require_relative 'gui/layout'
require_relative 'gui/window_manager'
require_relative 'gui/text_edit'
require_relative 'gui/profile_graph'
require_relative 'gui/widgets'

module Zenoo
  # 即時モード (Immediate Mode) GUI システム
  module GUI
    extend Widgets

    @theme      = Theme.new
    @renderer   = CardRenderer.new
    @layout     = Layout.new
    @win_mgr    = WindowManager.new

    @mouse_x    = 0.0
    @mouse_y    = 0.0
    @mouse_down = false
    @mouse_push = false
    @mouse_rel  = false
    @hot_id        = nil
    @active_id     = nil
    @focus_id      = nil
    @prev_captured = false
    @evaluated     = false
    @cursor_pos    = 0
    @blink_time    = 0.0

    class << self
      attr_accessor :renderer
      attr_reader :layout, :focus_id, :hot_id, :active_id

      # テーマの設定または取得
      # - 引数なし: 現在の Theme オブジェクトを返却
      # - 引数あり: プリセット適用 or プロパティ上書き
      #   例: GUI.theme(:navy)
      #   例: GUI.theme(bg_normal: [30, 40, 60, 200])
      def theme(preset = nil, **overrides)
        if preset.nil? && overrides.empty?
          @theme
        elsif preset.is_a?(Symbol)
          @theme = Theme.new(preset, **overrides)
        elsif preset.is_a?(Theme)
          @theme = preset
          @theme.update(**overrides) unless overrides.empty?
          @theme
        else
          @theme.update(**overrides)
        end
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
      end

      # 一時的にテーマを切り替えてブロックを実行
      def with_theme(target_theme, **overrides)
        old_theme = @theme
        @theme = if target_theme.is_a?(Symbol)
                   Theme.new(target_theme, **overrides)
                 elsif target_theme.is_a?(Theme)
                   target_theme
                 else
                   @theme.dup.update(**overrides)
                 end
        yield
        @theme = old_theme
      end

      # マウスカーソルが GUI コントロール上にあるか、操作中かどうか (Dear ImGui の WantCaptureMouse 相当)
      # update -> draw の実行順序でも正しく判定できるよう、描画前は前フレーム状態を参照
      def mouse_captured?
        if @evaluated
          !@hot_id.nil? || !@active_id.nil? || !@focus_id.nil? || !@win_mgr.hovered_window_id.nil?
        else
          @prev_captured || !@active_id.nil? || !@focus_id.nil?
        end
      end

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
        @prev_captured = !@hot_id.nil? || !@active_id.nil? || !@focus_id.nil? || !@win_mgr.hovered_window_id.nil?
        @hot_id     = nil
        @evaluated  = false
        @blink_time = (@blink_time || 0.0) + Window.delta_time
        @requested_cursor = :arrow

        @win_mgr.begin_frame(@mouse_x, @mouse_y, @mouse_down, @mouse_push)
        @layout.reset
      end

      def set_mouse_cursor(shape)
        @requested_cursor = shape
      end

      def end_frame
        Window.cursor = @requested_cursor
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
        @evaluated = true
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
      # パネルの開始 (描画とコンテナ設定を別関数に切り出し、yieldのインライン展開肥大化を防止)
      def begin_panel(title = "", x: nil, y: nil, w: nil, h: 400.0, padding: 16.0,
                      radius: -1.0, color: nil,
                      border_width: nil, border_color: nil,
                      shadow_blur: 8.0, shadow_color: Color.new(0, 0, 0, 120),
                      z: 0.0, title_size: 18, title_color: nil, clip: false,
                      spacing_x: nil, spacing_y: nil)
        px  = x ? x.to_f : @layout.cursor_x
        py  = y ? y.to_f : @layout.cursor_y
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

        @renderer.draw_panel(px, py, pw, ph, title, @theme, **opts)

        header_h  = title.to_s.empty? ? 0.0 : (title_size.to_i + (spacing_y || @layout.spacing_y) + 4.0)
        content_x = px + pad
        content_y = py + pad + header_h
        content_w = [pw - pad * 2.0, 0.0].max
        content_h = [ph - pad * 2.0 - header_h, 0.0].max

        container_state = @layout.begin_container(content_x, content_y, content_w, content_h, clip: clip, z: z.to_f, spacing_x: spacing_x, spacing_y: spacing_y)
        [pw, ph, !x.nil? || !y.nil?, container_state]
      end

      # パネルの終了
      def end_panel(state)
        pw, ph, is_manual_pos, container_state = state
        @layout.end_container(container_state)
        @layout.advance(pw, ph) unless is_manual_pos
      end

      # パネル (コンテナ枠)
      def panel(title = "", x: nil, y: nil, w: nil, h: 400.0, padding: 16.0,
                radius: -1.0, color: nil,
                border_width: nil, border_color: nil,
                shadow_blur: 8.0, shadow_color: Color.new(0, 0, 0, 120),
                z: 0.0, title_size: 18, title_color: nil, clip: false,
                spacing_x: nil, spacing_y: nil)
        state = begin_panel(
          title, x: x, y: y, w: w, h: h, padding: padding,
          radius: radius, color: color,
          border_width: border_width, border_color: border_color,
          shadow_blur: shadow_blur, shadow_color: shadow_color,
          z: z, title_size: title_size, title_color: title_color, clip: clip,
          spacing_x: spacing_x, spacing_y: spacing_y
        )
        if block_given?
          yield
          end_panel(state)
        else
          end_panel(state)
        end
      end

      # ウィンドウの開始
      def begin_window(title, x: nil, y: nil, w: 320.0, h: 240.0, id: "", padding: 12.0, resizable: false, min_w: 120.0, min_h: 80.0)
        win_id = id.to_s.empty? ? title.to_s : id.to_s
        win = @win_mgr.find_or_create(win_id, title, x, y, w, h, resizable: resizable, min_w: min_w, min_h: min_h)
        return nil unless win.open

        wx = win.x
        wy = win.y
        ww = win.w
        wh = win.h
        title_bar_h = 36.0
        pad = padding.to_f
        is_active = @win_mgr.active?(win_id)
        win_z = win.z

        unless @win_mgr.check_resize_start(win, @mouse_x, @mouse_y, @mouse_push)
          @win_mgr.check_drag_start(win, title_bar_h, @mouse_x, @mouse_y, @mouse_push)
        end
        @renderer.draw_window(wx, wy, ww, wh, win.title, is_active, @theme, z: win_z, title_bar_h: title_bar_h, resizable: win.resizable)

        content_x = wx + pad
        content_y = wy + title_bar_h + 8.0
        content_w = [ww - pad * 2.0, 0.0].max
        content_h = [wh - title_bar_h - pad - 8.0, 0.0].max

        container_state = @layout.begin_container(content_x, content_y, content_w, content_h, clip: true, z: win_z + 10.0)
        [win, win_id, container_state]
      end

      # ウィンドウの終了
      def end_window(state)
        return unless state
        _win, _win_id, container_state = state
        @layout.end_container(container_state)
      end

      # フローティングウィンドウ (Window)
      # - ドラッグ移動、タイトルバー、最前面フォーカス切り替え
      # - Window.clip(local: true) によるコンテンツのビューポートクリッピング
      # - resizable: true で右下ドラッグによるサイズ変更を許可 (オプション)
      def window(title, x: nil, y: nil, w: 320.0, h: 240.0, id: "", padding: 12.0, resizable: false, min_w: 120.0, min_h: 80.0)
        state = begin_window(title, x: x, y: y, w: w, h: h, id: id, padding: padding, resizable: resizable, min_w: min_w, min_h: min_h)
        return unless state
        return unless block_given?

        win, win_id, _cs = state
        @win_mgr.with_window_context(win_id) do
          yield win
          end_window(state)
        end
      end

      # --------------------------------------------------
      # ウィジェット (Button / Slider / Label / TextBox / Divider / ProfileGraph)
      # --------------------------------------------------
      # ボタン (クリックされた瞬間のみ true を返却)
      # - x, y: 省略時はレイアウトカーソル位置を使用。指定時はその座標に直接配置
      # - active: true の場合、選択中 (ハイライト) 状態で描画 (ラジオ/トグルボタン対応)
      def button(label, x: nil, y: nil, w: nil, h: 40.0, active: false, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
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

        # クリックが成立した瞬間、トグル/ラジオボタン等でアクティブ化されるケースを考慮し、
        # 1フレームだけホバー色に戻ってチラつくのを防止する
        is_active_visual = active || clicked
        state = is_active_visual ? :active : widget_visual_state(widget_id, hover, active_requires_hover: true)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        @renderer.draw_button(rx, ry, rw, rh, label, state, @theme)
        @layout.advance(rw, rh) if x.nil? && y.nil?
        clicked
      end

      # スライダー (マウスドラッグで値を変更し、更新された Float 値を返却)
      # - x, y: 省略時はレイアウトカーソル位置を使用
      # - step: 刻み幅 (例: 0.1, 1.0)
      # - unit: 単位サフィックス (例: "px", "x", "%")
      # - format: 数値書式 (例: "%.2f", "%d")
      def slider(label, value, min, max, x: nil, y: nil, w: nil, h: 44.0, step: nil, unit: "", format: nil, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
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
            v_val = calc_slider_value(rx, rw, v_min, v_max, step)
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            v_val = calc_slider_value(rx, rw, v_min, v_max, step)
            @active_id = widget_id unless @mouse_rel
          end
        end

        state = widget_visual_state(widget_id, hover, active_requires_hover: false)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        @renderer.draw_slider(rx, ry, rw, rh, label, v_val, v_min, v_max, state, @theme, unit: unit, format: format)
        @layout.advance(rw, rh) if x.nil? && y.nil?
        v_val
      end

      # ラベル (テキストを描画)
      def label(text, x: nil, y: nil, size: 18, color: nil)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        f_size = size.to_i
        col = color || @theme.text_color

        @renderer.draw_label(rx, ry, text, f_size, col, @theme)

        f_font = @theme.font || Font.default
        w = f_font.text_width(text.to_s, f_size)
        h = f_size.to_f
        @layout.advance(w, h) if x.nil? && y.nil?
        nil
      end

      # 水平区切り線 (Divider)
      def divider(x: nil, y: nil, w: nil, color: nil, spacing: 6.0)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : (@layout.cursor_y + spacing.to_f)
        rw = @layout.resolve_width(w, 200.0)
        border_cfg = @theme.border_normal
        line_col = color || (border_cfg ? border_cfg[1] : Color.new(70, 70, 75, 180))

        Window.draw_line(rx, ry, rx + rw, ry, color: line_col, width: 1.0)
        @layout.advance(rw, spacing.to_f * 2.0 + 1.0) if x.nil? && y.nil?
        nil
      end

      # テキストボックス (フォーカス中に文字入力・キー操作を受け付け、更新された文字列を返却)
      def text_box(label, text, x: nil, y: nil, w: nil, h: 42.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
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
        set_mouse_cursor(:ibeam) if hover || is_focused
        @renderer.draw_text_box(rx, ry, rw, rh, cur_text, is_focused, @cursor_pos || 0, blink_on, @theme)
        @layout.advance(rw, rh) if x.nil? && y.nil?
        cur_text
      end

      # プロファイルグラフ (Profile Graph / Frame Time Histogram)
      def profile_graph(x: nil, y: nil, w: nil, h: 80.0, max_ms: 33.33, show_legend: true, id: "")
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 280.0)
        rh = h.to_f

        total_h = ProfileGraph.draw(
          rx, ry, rw, rh, max_ms.to_f, show_legend,
          can_interact?, gui_mouse_x, gui_mouse_y, @theme
        )
        @layout.advance(rw, total_h) if x.nil? && y.nil?
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

      def calc_slider_value(rx, rw, v_min, v_max, step = nil)
        knob_radius = 9.0
        usable_w = [rw - knob_radius * 2.0, 1.0].max
        ratio = (gui_mouse_x - (rx + knob_radius)) / usable_w
        ratio = 0.0 if ratio < 0.0
        ratio = 1.0 if ratio > 1.0
        val = v_min + ratio * (v_max - v_min)
        if step && step.to_f > 0.0
          st = step.to_f
          val = ((val - v_min) / st).round * st + v_min
        end
        [[val, v_min].max, v_max].min
      end
    end
  end
end

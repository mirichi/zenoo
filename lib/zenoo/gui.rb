# frozen_string_literal: true

require_relative 'gui/theme'
require_relative 'gui/renderer'
require_relative 'gui/card_renderer'

module Zenoo
  # 即時モード (Immediate Mode) GUI システム
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

    @theme       = Theme.new
    @renderer    = CardRenderer.new
    @mouse_x     = 0.0
    @mouse_y     = 0.0
    @mouse_down  = false
    @mouse_push  = false
    @mouse_rel   = false
    @hot_id      = nil
    @active_id   = nil
    @focus_id    = nil
    @cursor_pos  = 0
    @blink_time  = 0.0

    # ウィンドウ管理状態
    @windows            = {} # id => WindowState
    @window_order       = [] # [win_id, ...] (手前が末尾)
    @hovered_window_id  = nil
    @active_window_id   = nil
    @dragging_window_id = nil
    @drag_offset_x      = 0.0
    @drag_offset_y      = 0.0
    @current_window_id  = nil

    # レイアウト状態
    @cursor_x     = 0.0
    @cursor_y     = 0.0
    @line_start_x = 0.0
    @line_max_h   = 0.0
    @spacing_x    = 8.0
    @spacing_y    = 8.0
    @in_row       = false
    @panel_stack  = []
    class << self
      def theme
        @theme
      end

      def theme=(val)
        @theme = val
      end

      def renderer
        @renderer
      end

      def renderer=(val)
        @renderer = val
      end

      def focus_id
        @focus_id
      end

      def focus_id=(val)
        @focus_id = val ? val.to_s : nil
        @blink_time = 0.0
        Input.set_ime_position(-1, -1) unless @focus_id
      end

      def windows
        @windows
      end

      def window_order
        @window_order
      end

      def hovered_window_id
        @hovered_window_id
      end

      def active_window_id
        @active_window_id
      end

      # --------------------------------------------------
      # フレーム開始処理 (Window.loop の先頭で毎フレーム自動呼び出し)
      # --------------------------------------------------
      def begin_frame
        @mouse_x    = Input.mouse_x.to_f
        @mouse_y    = Input.mouse_y.to_f
        @mouse_down = Input.mouse_pressed?(:left)
        @mouse_push = Input.mouse_push?(:left)
        @mouse_rel  = Input.mouse_release?(:left)
        @hot_id     = nil
        @blink_time += Window.delta_time

        # 1. ウィンドウのドラッグ継続処理
        if @dragging_window_id
          if @mouse_down && (win = @windows[@dragging_window_id])
            win.x = @mouse_x - @drag_offset_x
            win.y = @mouse_y - @drag_offset_y
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
            if in_rect?(@mouse_x, @mouse_y, w.x, w.y, w.w, w.h)
              @hovered_window_id = wid
              break
            end
          end
        end

        # 3. ウィンドウクリック時の最前面化 (Bring to Front)
        if @mouse_push
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

        # レイアウト状態の初期化
        @cursor_x     = 0.0
        @cursor_y     = 0.0
        @line_start_x = 0.0
        @line_max_h   = 0.0
        @in_row       = false
        @panel_stack.clear
        @current_window_id = nil
      end

      # --------------------------------------------------
      # レイアウト & カーソル操作
      # --------------------------------------------------
      def cursor(x = nil, y = nil)
        panel = @panel_stack.last
        base_x = panel ? panel[:x] : 0.0
        base_y = panel ? panel[:y] : 0.0

        if x && y
          @cursor_x = base_x + x.to_f
          @cursor_y = base_y + y.to_f
          @line_start_x = @cursor_x unless @in_row
          @line_max_h = 0.0 unless @in_row
        end
        [@cursor_x - base_x, @cursor_y - base_y]
      end

      def set_cursor(x, y)
        cursor(x, y)
      end

      def cursor_x
        base_x = @panel_stack.last ? @panel_stack.last[:x] : 0.0
        @cursor_x - base_x
      end

      def cursor_x=(val)
        base_x = @panel_stack.last ? @panel_stack.last[:x] : 0.0
        @cursor_x = base_x + val.to_f
        @line_start_x = @cursor_x unless @in_row
      end

      def cursor_y
        base_y = @panel_stack.last ? @panel_stack.last[:y] : 0.0
        @cursor_y - base_y
      end

      def cursor_y=(val)
        base_y = @panel_stack.last ? @panel_stack.last[:y] : 0.0
        @cursor_y = base_y + val.to_f
      end

      def spacing(x = nil, y = nil)
        if x
          @spacing_x = x.to_f
          @spacing_y = (y || x).to_f
        end
        [@spacing_x, @spacing_y]
      end

      def spacing_x
        @spacing_x
      end

      def spacing_x=(val)
        @spacing_x = val.to_f
      end

      def spacing_y
        @spacing_y
      end

      def spacing_y=(val)
        @spacing_y = val.to_f
      end

      # ウィジェット配置後のカーソル移動
      def advance_cursor(w, h)
        w = w.to_f
        h = h.to_f
        if @in_row
          @cursor_x += w + @spacing_x
          @line_max_h = h if h > @line_max_h
        else
          @cursor_y += h + @spacing_y
          @cursor_x = @line_start_x
          @line_max_h = 0.0
        end
      end

      # 横並びブロック
      def row(spacing: -1.0)
        prev_in_row       = @in_row
        prev_line_start_x = @line_start_x
        prev_line_max_h   = @line_max_h
        old_spacing_x     = @spacing_x

        @spacing_x = spacing.to_f if spacing >= 0.0
        @in_row = true
        @line_start_x = @cursor_x
        @line_max_h   = 0.0

        yield

        row_h = @line_max_h
        @in_row       = prev_in_row
        @line_start_x = prev_line_start_x
        @cursor_x     = prev_line_start_x
        @spacing_x    = old_spacing_x

        if @in_row
          @line_max_h = [prev_line_max_h, row_h].max
        else
          @cursor_y += row_h + @spacing_y
          @line_max_h = 0.0
        end
      end

      # --------------------------------------------------
      # パネル (コンテナ / ウィンドウ枠)
      # --------------------------------------------------
      def panel(title = "", w: 360.0, h: 400.0, padding: 16.0,
                radius: -1.0, color: nil,
                border_width: nil, border_color: nil,
                shadow_blur: 8.0, shadow_color: Color.new(0, 0, 0, 120),
                z: 0.0, title_size: 18, title_color: nil, &block)
        px  = @cursor_x
        py  = @cursor_y
        pw  = w.to_f
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

        prev_cx      = @cursor_x
        prev_cy      = @cursor_y
        prev_lsx     = @line_start_x
        prev_in_row  = @in_row
        @panel_stack.push({ x: px, y: py, w: pw, h: ph })

        content_x = px + pad
        content_y = py + pad

        if !title.empty?
          content_y += title_size.to_i + @spacing_y + 4.0
        end

        @cursor_x     = content_x
        @cursor_y     = content_y
        @line_start_x = content_x
        @in_row       = false

        yield if block_given?

        @panel_stack.pop
        @cursor_x     = prev_cx
        @cursor_y     = prev_cy
        @line_start_x = prev_lsx
        @in_row       = prev_in_row

        advance_cursor(pw, ph)
      end

      # --------------------------------------------------
      # フレーム終了処理 (Window.loop の末尾で毎フレーム自動呼び出し)
      # --------------------------------------------------
      def end_frame
      end

      # 矩形内当たり判定
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
        @hovered_window_id == @current_window_id
      end

      # ローカル座標系対応のマウス X 座標
      def gui_mouse_x
        @mouse_x - Window.offset_x
      end

      # ローカル座標系対応のマウス Y 座標
      def gui_mouse_y
        @mouse_y - Window.offset_y
      end

      # --------------------------------------------------
      # フローティングウィンドウ (Window)
      # - ドラッグ移動、タイトルバー、最前面フォーカス切り替え
      # - Window.clip(local: true) によるコンテンツのビューポートクリッピング
      # --------------------------------------------------
      def window(title, x: nil, y: nil, w: 320.0, h: 240.0, id: "", padding: 12.0, &block)
        win_id = id.to_s.empty? ? title.to_s : id.to_s
        win = @windows[win_id]
        unless win
          def_x = x ? x.to_f : (60.0 + (@windows.size * 30.0) % 400.0)
          def_y = y ? y.to_f : (60.0 + (@windows.size * 30.0) % 300.0)
          win = WindowState.new(win_id, title.to_s, def_x, def_y, w.to_f, h.to_f)
          @windows[win_id] = win
          @window_order.push(win_id)
          win.z = 100.0 + (@window_order.size - 1) * 100.0
        end

        return unless win.open

        wx = win.x
        wy = win.y
        ww = win.w
        wh = win.h
        title_bar_h = 36.0
        pad = padding.to_f

        is_active = (@window_order.last == win_id)
        win_z = win.z

        # タイトルバーのドラッグ開始判定
        # (最前面ウィンドウかつタイトルバー内で押下された場合)
        if @mouse_push && @hovered_window_id == win_id
          if in_rect?(@mouse_x, @mouse_y, wx, wy, ww, title_bar_h)
            @dragging_window_id = win_id
            @drag_offset_x = @mouse_x - wx
            @drag_offset_y = @mouse_y - wy
          end
        end

        # 1. ウィンドウ全体の装飾描画 (外枠・タイトルバー)
        border_cfg = is_active ? (@theme.win_border_active || @theme.border_active) : (@theme.win_border_normal || @theme.border_normal)
        border_w = border_cfg ? border_cfg[0].to_f : 1.0
        border_color = border_cfg ? border_cfg[1] : Color.new(80, 80, 80)

        shadow_blur = is_active ? 8.0 : 4.0
        shadow_color = Color.new(0, 0, 0, is_active ? 140 : 100)
        win_bg_col = @theme.win_bg || Color.new(30, 30, 32, 245)
        win_radius = (@theme.corner_radius || 4.0).to_f

        # 背景カード
        Window.draw_rect(
          wx, wy, ww, wh,
          radius: win_radius,
          color: win_bg_col,
          border_width: border_w,
          border_color: border_color,
          shadow_blur: shadow_blur,
          shadow_color: shadow_color,
          z: win_z
        )

        # タイトルバー帯
        title_bg = is_active ? (@theme.win_title_bg_active || Color.new(52, 52, 58)) : (@theme.win_title_bg || Color.new(42, 42, 45))
        title_bar_radius = [win_radius - 1.0, 0.0].max
        Window.draw_rect(
          wx + 1.0, wy + 1.0, ww - 2.0, title_bar_h,
          radius: title_bar_radius,
          color: title_bg,
          z: win_z + 1.0
        )

        # タイトルバー境界線
        Window.draw_line(
          wx + 1.0, wy + title_bar_h + 1.0,
          wx + ww - 1.0, wy + title_bar_h + 1.0,
          color: border_color,
          z: win_z + 1.5
        )

        # タイトル文字列
        f_font = @theme.font || Font.default
        f_size = 14
        title_col = is_active ? (@theme.text_color || Color::WHITE) : (@theme.text_disabled || Color.new(160, 160, 165))
        Profiler.measure(:gui_text) do
          Window.draw_text(
            wx + 10.0, wy + (title_bar_h - f_size.to_f) / 2.0 + 1.0,
            win.title,
            font: f_font,
            size: f_size,
            color: title_col,
            z: win_z + 2.0
          )
        end

        # 2. コンテンツ領域のクリッピング & レイアウト
        content_x = wx + pad
        content_y = wy + title_bar_h + 8.0
        content_w = ww - pad * 2.0
        content_h = wh - title_bar_h - pad - 8.0

        prev_win_id = @current_window_id
        @current_window_id = win_id

        prev_cx  = @cursor_x
        prev_cy  = @cursor_y
        prev_lsx = @line_start_x
        prev_in_row = @in_row

        @cursor_x = 0.0
        @cursor_y = 0.0
        @line_start_x = 0.0
        @in_row = false

        begin
          Window.clip(content_x, content_y, content_w, content_h, local: true, z: win_z + 10.0) do
            yield win if block_given?
          end
        ensure
          @current_window_id = prev_win_id
          @cursor_x     = prev_cx
          @cursor_y     = prev_cy
          @line_start_x = prev_lsx
          @in_row       = prev_in_row
        end
      end

      # --------------------------------------------------
      # ボタン (Button)
      # クリックされた瞬間のみ true を返却
      # --------------------------------------------------
      def button(label, w: 140.0, h: 40.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = @cursor_x
        ry = @cursor_y
        rw = w.to_f
        rh = h.to_f

        hover = can_interact? && @renderer.hit_test_button(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)
        clicked = false

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            clicked = true if hover
            @active_id = nil
          end
        elsif @active_id == nil && hover
          @hot_id = widget_id
          if @mouse_push
            if @mouse_rel
              clicked = true
            else
              @active_id = widget_id
            end
          end
        end

        # 見た目の状態決定:
        # - 押下中(@active_id)でカーソルがボタン内にあるときは :active
        # - 押下中でもカーソルがボタン外にあるときは :normal (見た目は元に戻る)
        # - 他にアクティブなウィジェットがなくカーソルが乗っているときは :hover
        state = :normal
        if @active_id == widget_id
          state = :active if hover
        elsif @active_id == nil && hover
          state = :hover
        end

        @renderer.draw_button(rx, ry, rw, rh, label, state, @theme)
        advance_cursor(rw, rh)
        clicked
      end

      # --------------------------------------------------
      # スライダー (Slider)
      # マウスドラッグで値を変更し、更新された Float 値を返却
      # --------------------------------------------------
      def slider(label, value, min, max, w: 200.0, h: 32.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = @cursor_x
        ry = @cursor_y
        rw = w.to_f
        rh = h.to_f
        v_val = value.to_f
        v_min = min.to_f
        v_max = max.to_f

        hover = can_interact? && @renderer.hit_test_slider(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            @active_id = nil
          else
            # ドラッグ中: ローカルマウスX座標から値を算出
            ratio = (gui_mouse_x - rx) / rw
            ratio = 0.0 if ratio < 0.0
            ratio = 1.0 if ratio > 1.0
            v_val = v_min + ratio * (v_max - v_min)
          end
        elsif @active_id == nil && hover
          @hot_id = widget_id
          if @mouse_push
            ratio = (gui_mouse_x - rx) / rw
            ratio = 0.0 if ratio < 0.0
            ratio = 1.0 if ratio > 1.0
            v_val = v_min + ratio * (v_max - v_min)
            @active_id = widget_id unless @mouse_rel
          end
        end

        state = :normal
        if @active_id == widget_id
          state = :active
        elsif @active_id == nil && hover
          state = :hover
        end

        @renderer.draw_slider(rx, ry, rw, rh, label, v_val, v_min, v_max, state, @theme)
        advance_cursor(rw, rh)
        v_val
      end

      # --------------------------------------------------
      # ラベル (Label)
      # テキストを描画
      # --------------------------------------------------
      def label(text, size: 18, color: Color::WHITE)
        rx = @cursor_x
        ry = @cursor_y
        f_size = size.to_i

        @renderer.draw_label(rx, ry, text, f_size, color, @theme)

        f_font = @theme.font || Font.default
        w = f_font.text_width(text.to_s, f_size)
        h = f_size.to_f
        advance_cursor(w, h)
        nil
      end

      # --------------------------------------------------
      # テキストボックス (Text Box)
      # フォーカス中に文字入力・キー操作を受け付け、更新された文字列を返却
      # --------------------------------------------------
      def text_box(label, text, w: 200.0, h: 42.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = @cursor_x
        ry = @cursor_y
        rw = w.to_f
        rh = h.to_f
        cur_text = text.to_s

        hover = can_interact? && @renderer.hit_test_text_box(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)

        # クリックによるフォーカス獲得 / キャレット移動 / フォーカス解除
        if @mouse_push
          if hover
            @focus_id = widget_id
            @blink_time = 0.0

            # クリック位置からキャレット位置を算出
            str = cur_text
            pad_x = 10.0
            click_x = gui_mouse_x - (rx + pad_x)
            f_font = @theme.font || Font.default
            f_size = @theme.font_size.to_i
            f_size = 14 if f_size <= 0

            best_idx = str.length
            accum_w = 0.0
            str.each_char.with_index do |ch, idx|
              char_w = f_font.text_width(ch, f_size)
              if click_x < accum_w + char_w * 0.5
                best_idx = idx
                break
              end
              accum_w += char_w
            end
            @cursor_pos = best_idx
          elsif @focus_id == widget_id
            # ボックス外をクリックしたらフォーカス解除
            @focus_id = nil
            Input.set_ime_position(-1, -1)
          end
        end

        cur_text = cur_text.dup
        is_focused = (@focus_id == widget_id)

        # フォーカス中の入力処理
        if is_focused
          @cursor_pos = cur_text.length if @cursor_pos > cur_text.length
          @cursor_pos = 0 if @cursor_pos < 0

          # 1. IME変換候補位置の更新 (キャレットの直下 - 画面絶対座標に変換)
          f_font = @theme.font || Font.default
          f_size = @theme.font_size.to_i
          f_size = 14 if f_size <= 0
          sub_str = cur_text[0...@cursor_pos] || ""
          caret_offset = f_font.text_width(sub_str, f_size)
          pad_x = 10.0
          abs_ime_x = rx + pad_x + caret_offset + Window.offset_x
          abs_ime_y = ry + rh + 2.0 + Window.offset_y
          Input.set_ime_position(abs_ime_x, abs_ime_y)

          # 2. 特殊キー処理 (キーリピート対応)
          if Input.key_repeat?(:backspace)
            if @cursor_pos > 0
              cur_text.slice!(@cursor_pos - 1)
              @cursor_pos -= 1
              @blink_time = 0.0
            end
          elsif Input.key_repeat?(:delete)
            if @cursor_pos < cur_text.length
              cur_text.slice!(@cursor_pos)
              @blink_time = 0.0
            end
          elsif Input.key_repeat?(:left)
            if @cursor_pos > 0
              @cursor_pos -= 1
              @blink_time = 0.0
            end
          elsif Input.key_repeat?(:right)
            if @cursor_pos < cur_text.length
              @cursor_pos += 1
              @blink_time = 0.0
            end
          elsif Input.key_push?(:home)
            @cursor_pos = 0
            @blink_time = 0.0
          elsif Input.key_push?(:end)
            @cursor_pos = cur_text.length
            @blink_time = 0.0
          elsif Input.key_push?(:enter) || Input.key_push?(:escape)
            @focus_id = nil
            Input.set_ime_position(-1, -1)
          end

          # 3. 通常文字・日本語確定文字の入力
          Input.input_chars.each do |ch|
            next if ch == "\r" || ch == "\n"
            cur_text.insert(@cursor_pos, ch)
            @cursor_pos += ch.length
            @blink_time = 0.0
          end
        end

        # キャレット点滅 (0.5秒表示、0.5秒非表示)
        blink_on = (@blink_time % 1.0) < 0.5

        @renderer.draw_text_box(rx, ry, rw, rh, cur_text, is_focused, @cursor_pos, blink_on, @theme)
        advance_cursor(rw, rh)
        cur_text
      end

      def has_focus?(id)
        @focus_id == id.to_s
      end

      def clear_focus
        @focus_id = nil
        Input.set_ime_position(-1, -1)
      end

      # --------------------------------------------------
      # プロファイルグラフ (Profile Graph / Frame Time Histogram)
      # 各処理の実行時間 (ms) をカテゴリ別に積み上げ棒グラフとして描画
      # --------------------------------------------------
      # @param w [Float] グラフ横幅 (デフォルト 280.0)
      # @param h [Float] グラフ高さ (デフォルト 80.0)
      # @param max_ms [Float] グラフの縦軸上限ミリ秒 (デフォルト 33.33ms = 30FPS相当)
      # @param show_legend [Boolean] 凡例の表示有無
      # @param id [String] ウィジェットID
      def profile_graph(w: 280.0, h: 80.0, max_ms: 33.33, show_legend: true, id: "")
        rx = @cursor_x
        ry = @cursor_y
        rw = w.to_f
        rh = h.to_f
        f_font = @theme.font || Font.default

        # 1. グラフ枠・背景の描画
        graph_bg = Color.new(24, 24, 26, 230)
        graph_border = Color.new(55, 55, 60, 200)
        Window.draw_rect(rx, ry, rw, rh, color: graph_bg, border_color: graph_border, border_width: 1.0)

        # 2. ガイドライン描画 (16.6ms / 60FPS 目標線)
        target_60_y = ry + rh - (16.666 / max_ms) * rh
        if target_60_y >= ry && target_60_y <= ry + rh
          line_color = Color.new(80, 160, 180, 140)
          Window.draw_line(rx + 1.0, target_60_y, rx + rw - 1.0, target_60_y, color: line_color, width: 1.0)
          Profiler.measure(:gui_text) do
            Window.draw_text(rx + 4.0, target_60_y - 12.0, "16.6ms (60fps)", font: f_font, size: 10, color: line_color)
          end
        end

        # 3. ガイドライン描画 (33.3ms / 30FPS 目標線)
        if max_ms > 33.33
          target_30_y = ry + rh - (33.333 / max_ms) * rh
          if target_30_y >= ry && target_30_y <= ry + rh
            line_color_30 = Color.new(180, 80, 80, 140)
            Window.draw_line(rx + 1.0, target_30_y, rx + rw - 1.0, target_30_y, color: line_color_30, width: 1.0)
            Profiler.measure(:gui_text) do
              Window.draw_text(rx + 4.0, target_30_y - 12.0, "33.3ms (30fps)", font: f_font, size: 10, color: line_color_30)
            end
          end
        end

        # 4. フレーム履歴の積み上げ棒グラフ描画 (全バーを一括バッチ化して1回のenqueueで高速描画)
        history = Profiler.history
        bar_w = 3.0
        max_bars = ((rw - 4.0) / bar_w).to_i
        visible_frames = history.last(max_bars)

        # マウスホバー判定
        mx = gui_mouse_x
        my = gui_mouse_y
        is_hovered = can_interact? && in_rect?(mx, my, rx, ry, rw, rh)
        hovered_idx = nil

        if is_hovered && !visible_frames.empty?
          # 右端からのインデックス
          dist_from_right = (rx + rw - 2.0) - mx
          if dist_from_right >= 0
            idx_from_end = (dist_from_right / bar_w).to_i
            hovered_idx = visible_frames.size - 1 - idx_from_end if idx_from_end < visible_frames.size
          end
        end

        # ホバーされているフレームは背景ハイライト
        if hovered_idx && hovered_idx >= 0 && hovered_idx < visible_frames.size
          hbx = rx + rw - 2.0 - (visible_frames.size - hovered_idx) * bar_w
          Window.draw_rect(hbx, ry + 1.0, bar_w, rh - 2.0, color: Color.new(255, 255, 255, 60))
        end

        ox = Window.offset_x
        oy = Window.offset_y

        bars_batch = []
        rect_count = 0
        bw = [bar_w - 0.5, 1.0].max
        bar_col_cache = @bar_color_cache ||= {}

        # 右端から左へ描画データをバッチ構築
        visible_frames.each_with_index do |frame, i|
          bx = rx + rw - 2.0 - (visible_frames.size - i) * bar_w
          next if bx < rx + 1.0

          bx2 = bx + bw
          current_y = ry + rh - 1.0

          abx = bx + ox
          abx2 = bx2 + ox

          frame.each do |category, ms|
            h_cat = (ms.to_f / max_ms) * rh
            h_cat = 0.0 if h_cat < 0.0
            h_cat = current_y - ry - 1.0 if current_y - h_cat < ry + 1.0
            break if h_cat <= 0.0

            top_y = current_y - h_cat
            col = bar_col_cache[category] ||= begin
              cat_color = Profiler.color_for(category)
              nc = Backend.normalize_color(cat_color)
              [nc[0].to_f, nc[1].to_f, nc[2].to_f, nc[3].to_f]
            end
            cr, cg, cb, ca = col

            atop_y = top_y + oy
            acur_y = current_y + oy

            bars_batch.push(
              abx, atop_y, cr, cg, cb, ca,
              abx, acur_y, cr, cg, cb, ca,
              abx2, atop_y, cr, cg, cb, ca,
              abx2, atop_y, cr, cg, cb, ca,
              abx, acur_y, cr, cg, cb, ca,
              abx2, acur_y, cr, cg, cb, ca
            )
            rect_count += 1
            current_y = top_y
            break if current_y <= ry + 1.0
          end
        end

        if rect_count > 0
          Backend.enqueue_draw(
            Backend::Pipelines::TRIANGLES,
            bars_batch.pack("f*"),
            rect_count * 6,
            shader: Window.flat_primitive_shader
          )
        end

        # 5. 上部ステータステキスト (FPS / 最新合計ms)
        total_last = Profiler.last_total_ms
        avg_last = Profiler.history.empty? ? 0.0 : (Profiler.history.last(30).map { |f| f.values.sum }.sum / [Profiler.history.size, 30].min)
        status_text = "Avg: #{avg_last.round(1)}ms | Last: #{total_last.round(1)}ms | #{Window.fps.round(0)} FPS"
        Profiler.measure(:gui_text) do
          Window.draw_text(rx + rw - 6.0, ry + 4.0, status_text, font: f_font, size: 11, color: Color.new(200, 200, 200), align: :right)
        end

        # 6. ホバー中の詳細情報ポップアップ / ラベル
        if hovered_idx && visible_frames[hovered_idx]
          target_frame = visible_frames[hovered_idx]
          frame_tot = target_frame.values.sum.round(2)
          hover_str = "Frame: #{frame_tot}ms (" + target_frame.map { |k, v| "#{k}:#{v.round(1)}" }.join(", ") + ")"
          Profiler.measure(:gui_text) do
            Window.draw_text(rx + 6.0, ry + 4.0, hover_str, font: f_font, size: 11, color: Color.new(255, 240, 100))
          end
        end

        total_h = rh

        # 7. 詳細内訳リスト (Legend) の描画 (直近30フレーム平均で重い順にソート)
        if show_legend
          avg_map = Profiler.average_times(30)
          total_avg = [avg_map.values.sum, 0.0001].max
          sorted_cats = Profiler.categories.sort_by { |cat| -(avg_map[cat] || 0.0) }

          legend_y = ry + rh + 8.0
          chip_size = 8.0

          sorted_cats.each do |cat|
            avg_ms = avg_map[cat] || 0.0
            last_ms = (Profiler.last_times[cat] || 0.0)
            next if avg_ms < 0.005 && last_ms < 0.005 # ほぼゼロのセクションは非表示

            pct = ((avg_ms / total_avg) * 100.0).round(0)
            cat_col = Profiler.color_for(cat)

            # 左側: カラーチップ
            Window.draw_rect(rx + 4.0, legend_y + 2.0, chip_size, chip_size, color: cat_col)

            # テキスト描画 (カテゴリ名 + ms・割合)
            Profiler.measure(:gui_text) do
              Window.draw_text(rx + 16.0, legend_y, cat.to_s, font: f_font, size: 11, color: Color.new(200, 205, 210))

              val_100 = (avg_ms * 100).to_i
              val_dec = val_100 % 100
              val_str = "#{val_100 / 100}.#{val_dec < 10 ? '0' : ''}#{val_dec}ms"
              ms_str = "#{val_str} (#{pct}%)"
              Window.draw_text(rx + rw - 4.0, legend_y, ms_str, font: f_font, size: 11, color: Color.new(160, 210, 240), align: :right)
            end

            legend_y += 15.0
          end

          total_h = (legend_y + 4.0) - ry
        end

        advance_cursor(rw, total_h)
        nil
      end
    end
  end
end

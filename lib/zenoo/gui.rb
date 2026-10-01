# frozen_string_literal: true

require_relative 'gui/theme'
require_relative 'gui/renderer'
require_relative 'gui/card_renderer'

module Zenoo
  # 即時モード (Immediate Mode) GUI システム
  module GUI
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

        # レイアウト状態の初期化
        @cursor_x     = 0.0
        @cursor_y     = 0.0
        @line_start_x = 0.0
        @line_max_h   = 0.0
        @in_row       = false
        @panel_stack.clear
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
                radius: -1.0, color: Color.new(24, 28, 38, 240),
                border_width: 1.5, border_color: Color.new(60, 70, 90, 200),
                shadow_blur: 16.0, shadow_color: Color.new(0, 0, 0, 150),
                z: 0.0, title_size: 20, title_color: Color::WHITE, &block)
        px  = @cursor_x
        py  = @cursor_y
        pw  = w.to_f
        ph  = h.to_f
        pad = padding.to_f
        rad = (radius < 0.0) ? (@theme.corner_radius || 12.0).to_f : radius.to_f

        opts = {
          w: pw,
          h: ph,
          padding: pad,
          radius: rad,
          color: color,
          border_width: border_width.to_f,
          border_color: border_color,
          shadow_blur: shadow_blur.to_f,
          shadow_color: shadow_color,
          z: z.to_f,
          title_size: title_size.to_i,
          title_color: title_color
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

        hover = @renderer.hit_test_button(rx, ry, rw, rh, @mouse_x, @mouse_y, @theme)
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

        hover = @renderer.hit_test_slider(rx, ry, rw, rh, @mouse_x, @mouse_y, @theme)

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            @active_id = nil
          else
            # ドラッグ中: マウスX座標から値を算出
            ratio = (@mouse_x - rx) / rw
            ratio = 0.0 if ratio < 0.0
            ratio = 1.0 if ratio > 1.0
            v_val = v_min + ratio * (v_max - v_min)
          end
        elsif @active_id == nil && hover
          @hot_id = widget_id
          if @mouse_push
            ratio = (@mouse_x - rx) / rw
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

        hover = @renderer.hit_test_text_box(rx, ry, rw, rh, @mouse_x, @mouse_y, @theme)

        # クリックによるフォーカス獲得 / キャレット移動 / フォーカス解除
        if @mouse_push
          if hover
            @focus_id = widget_id
            @blink_time = 0.0

            # クリック位置からキャレット位置を算出
            str = cur_text
            pad_x = 10.0
            click_x = @mouse_x - (rx + pad_x)
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

          # 1. IME変換候補位置の更新 (キャレットの直下)
          f_font = @theme.font || Font.default
          f_size = @theme.font_size.to_i
          f_size = 14 if f_size <= 0
          sub_str = cur_text[0...@cursor_pos] || ""
          caret_offset = f_font.text_width(sub_str, f_size)
          pad_x = 10.0
          Input.set_ime_position(rx + pad_x + caret_offset, ry + rh + 2.0)

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
    end
  end
end

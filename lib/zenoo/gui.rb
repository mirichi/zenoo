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
      def button(label, x, y, w = 140.0, h = 40.0, id = nil)
        widget_id = id ? id.to_s : label.to_s
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        hover = @renderer.hit_test_button(rx, ry, rw, rh, @mouse_x, @mouse_y, @theme)
        clicked = false

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            clicked = true if hover && @mouse_rel
            @active_id = nil
          end
        elsif @active_id == nil && hover
          @hot_id = widget_id
          if @mouse_push
            @active_id = widget_id
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
        clicked
      end

      # --------------------------------------------------
      # スライダー (Slider)
      # マウスドラッグで値を変更し、更新された Float 値を返却
      # --------------------------------------------------
      def slider(label, x, y, w = 200.0, h = 32.0, value = 0.0, min = 0.0, max = 1.0, id = nil)
        widget_id = id ? id.to_s : label.to_s
        rx = x.to_f
        ry = y.to_f
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
            @active_id = widget_id
            ratio = (@mouse_x - rx) / rw
            ratio = 0.0 if ratio < 0.0
            ratio = 1.0 if ratio > 1.0
            v_val = v_min + ratio * (v_max - v_min)
          end
        end

        state = :normal
        if @active_id == widget_id
          state = :active
        elsif @active_id == nil && hover
          state = :hover
        end

        @renderer.draw_slider(rx, ry, rw, rh, label, v_val, v_min, v_max, state, @theme)
        v_val
      end

      # --------------------------------------------------
      # ラベル (Label)
      # テキストを描画
      # --------------------------------------------------
      def label(text, x, y, size = 18, color = nil)
        @renderer.draw_label(x.to_f, y.to_f, text, size, color, @theme)
        nil
      end

      # --------------------------------------------------
      # テキストボックス (Text Box)
      # フォーカス中に文字入力・キー操作を受け付け、更新された文字列を返却
      # --------------------------------------------------
      def text_box(label, x, y, w = 200.0, h = 42.0, text = "", id: nil)
        widget_id = id ? id.to_s : label.to_s
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        hover = @renderer.hit_test_text_box(rx, ry, rw, rh, @mouse_x, @mouse_y, @theme)

        # クリックによるフォーカス獲得 / キャレット移動 / フォーカス解除
        if @mouse_push
          if hover
            @focus_id = widget_id
            @blink_time = 0.0

            # クリック位置からキャレット位置を算出
            str = text.to_s
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

        cur_text = text.to_s.dup
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

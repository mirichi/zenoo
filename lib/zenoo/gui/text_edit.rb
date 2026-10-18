# frozen_string_literal: true

module Zenoo
  module GUI
    # テキストボックスのキャレット位置算出・IME座標同期・キー入力編集ロジック
    module TextEdit
      class << self
        # クリック位置から最適なキャレット文字インデックスを算出
        def caret_index_from_click(str, click_x, theme)
          f_font = theme.font || Font.default
          f_size = theme.font_size.to_i
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
          best_idx
        end

        # フォーカス中のテキスト編集・IME位置更新処理
        # @return [Array(String, Integer, Boolean, Boolean)] [updated_text, updated_cursor_pos, reset_blink, unfocus]
        def process_focused_input(cur_text, cursor_pos, rx, ry, rh, theme)
          cursor_pos = cur_text.length if cursor_pos > cur_text.length
          cursor_pos = 0 if cursor_pos < 0
          reset_blink = false
          unfocus = false

          # 1. IME変換候補位置の更新 (キャレットの直下 - 画面絶対座標に変換)
          f_font = theme.font || Font.default
          f_size = theme.font_size.to_i
          f_size = 14 if f_size <= 0
          sub_str = cur_text[0...cursor_pos] || ""
          caret_offset = f_font.text_width(sub_str, f_size)
          pad_x = 10.0
          abs_ime_x = rx + pad_x + caret_offset + Window.offset_x
          abs_ime_y = ry + rh + 2.0 + Window.offset_y
          Input.set_ime_position(abs_ime_x, abs_ime_y)

          # 2. 特殊キー処理 (キーリピート対応)
          if Input.key_repeat?(:backspace)
            if cursor_pos > 0
              cur_text.slice!(cursor_pos - 1)
              cursor_pos -= 1
              reset_blink = true
            end
          elsif Input.key_repeat?(:delete)
            if cursor_pos < cur_text.length
              cur_text.slice!(cursor_pos)
              reset_blink = true
            end
          elsif Input.key_repeat?(:left)
            if cursor_pos > 0
              cursor_pos -= 1
              reset_blink = true
            end
          elsif Input.key_repeat?(:right)
            if cursor_pos < cur_text.length
              cursor_pos += 1
              reset_blink = true
            end
          elsif Input.key_push?(:home)
            cursor_pos = 0
            reset_blink = true
          elsif Input.key_push?(:end)
            cursor_pos = cur_text.length
            reset_blink = true
          elsif Input.key_push?(:enter) || Input.key_push?(:escape)
            unfocus = true
          end

          # 3. 通常文字・日本語確定文字の入力
          Input.input_chars.each do |ch|
            next if ch == "\r" || ch == "\n"
            cur_text.insert(cursor_pos, ch)
            cursor_pos += ch.length
            reset_blink = true
          end

          [cur_text, cursor_pos, reset_blink, unfocus]
        end
      end
    end
  end
end

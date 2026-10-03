# frozen_string_literal: true

module Zenoo
  module GUI
    # 描画レンダラー基底クラス (Pluggable Renderer)
    # ユーザーはこのクラスを継承して独自の描画ロジックに差し替えることができます。
    class Renderer
      # ボタン描画
      # state: :normal, :hover, :active
      def draw_button(x, y, w, h, label, state, theme)
        raise NotImplementedError, "#{self.class}#draw_button must be implemented"
      end

      # スライダー描画
      # state: :normal, :hover, :active
      def draw_slider(x, y, w, h, label, value, min, max, state, theme)
        raise NotImplementedError, "#{self.class}#draw_slider must be implemented"
      end

      # ラベル描画
      def draw_label(x, y, text, size, color, theme)
        raise NotImplementedError, "#{self.class}#draw_label must be implemented"
      end

      # テキストボックス描画
      def draw_text_box(x, y, w, h, text, focused, cursor_pos, blink_on, theme)
        raise NotImplementedError, "#{self.class}#draw_text_box must be implemented"
      end

      # パネル (コンテナ枠) 描画
      def draw_panel(x, y, w, h, title, theme, opts = {})
        # デフォルトはシンプルな矩形描画
        bg_col = opts[:color] || Color.new(24, 28, 38, 240)
        border_col = opts[:border_color] || Color.new(60, 70, 90, 200)
        border_w = (opts[:border_width] || 1.5).to_f

        Window.draw_rect(x, y, w, h, color: bg_col, border_color: (border_w > 0.0 ? border_col : nil), border_width: border_w)

        if title && !title.to_s.empty?
          f_font = opts[:font] || theme.font || Font.default
          title_size = (opts[:title_size] || 20).to_i
          title_col = opts[:title_color] || Color::WHITE
          pad = (opts[:padding] || 16.0).to_f
          Window.draw_text(x + pad, y + pad, title.to_s, font: f_font, size: title_size, color: title_col)
        end
      end

      # ----------------------------------------------------
      # 当たり判定 (Hit-Test)
      # レンダラーの描画形状に合わせてオーバーライド可能
      # ----------------------------------------------------
      def hit_test_button(x, y, w, h, px, py, theme)
        px >= x && px <= (x + w) && py >= y && py <= (y + h)
      end

      def hit_test_slider(x, y, w, h, px, py, theme)
        px >= x && px <= (x + w) && py >= y && py <= (y + h)
      end

      def hit_test_text_box(x, y, w, h, px, py, theme)
        px >= x && px <= (x + w) && py >= y && py <= (y + h)
      end
    end
  end
end

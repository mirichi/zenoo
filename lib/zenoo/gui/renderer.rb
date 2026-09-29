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

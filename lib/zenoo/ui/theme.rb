# frozen_string_literal: true

module Zenoo
  module UI
    # UI 全体の配色と密度（フォントサイズ・標準高さ・余白・角丸）を保持するテーマ設定
    class Theme
      attr_accessor :bg_normal, :bg_hover, :bg_active,
                    :border_normal, :border_hover,
                    :win_bg, :win_border, :win_border_active,
                    :text_color, :text_muted, :accent_color, :accent_hover,
                    :track_bg, :track_border,
                    :font_size, :control_height, :header_height,
                    :padding, :gap, :radius

      # テーマを初期化する
      #
      # - `preset` (`Symbol`): 密度プリセット（`:compact` または `:relaxed`）
      # - `overrides` (`Hash`): 上書きする属性名と値
      def initialize(preset = :compact, **overrides)
        if preset == :relaxed
          apply_relaxed
        else
          apply_compact
        end
        overrides.each { |k, v| public_send(:"#{k}=", v) }
      end

      # ツール向けの引き締まった標準テーマを適用する
      def apply_compact
        @bg_normal         = [40, 46, 60]
        @bg_hover          = [54, 64, 84]
        @bg_active         = [68, 84, 114]
        @border_normal     = [74, 86, 110]
        @border_hover      = [110, 175, 245]
        @win_bg            = [24, 28, 38, 242]
        @win_border        = [68, 80, 106]
        @win_border_active = [105, 165, 245]
        @text_color        = [236, 240, 248]
        @text_muted        = [180, 192, 212]
        @accent_color      = [72, 152, 242]
        @accent_hover      = [105, 180, 255]
        @track_bg          = [18, 22, 30]
        @track_border      = [58, 68, 88]

        @font_size      = 14
        @control_height = 24.0
        @header_height  = 26.0
        @padding        = 8.0
        @gap            = 3.0
        @radius         = 4.0
      end

      # ゲーム設定画面など向けのゆったりテーマを適用する
      def apply_relaxed
        apply_compact
        @font_size      = 15
        @control_height = 34.0
        @header_height  = 34.0
        @padding        = 14.0
        @gap            = 10.0
        @radius         = 7.0
      end
    end
  end
end

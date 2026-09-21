# frozen_string_literal: true

module Zenoo
  module GUI
    class Theme
      attr_accessor :bg_normal, :bg_hover, :bg_active,
                    :border_normal, :border_hover, :border_active,
                    :shadow_normal, :shadow_hover, :shadow_active,
                    :text_color, :text_disabled,
                    :accent_color, :accent_hover, :track_bg, :track_border,
                    :corner_radius, :font_size, :font

      def initialize
        @font           = nil
        # ボタン・カード背景色
        @bg_normal      = Color.new(40, 44, 52, 230)
        @bg_hover       = Color.new(55, 60, 72, 245)
        @bg_active      = Color.new(70, 80, 100, 255)

        # ボーダー設定 [幅, Color]
        @border_normal  = [1.0, Color.new(80, 88, 104, 180)]
        @border_hover   = [1.5, Color.new(0, 210, 255, 230)]
        @border_active  = [2.0, Color.new(0, 255, 200, 255)]

        # シャドウ設定 [ブラー, Color]
        @shadow_normal  = [6.0, Color.new(0, 0, 0, 120)]
        @shadow_hover   = [12.0, Color.new(0, 180, 255, 100)]
        @shadow_active  = [4.0, Color.new(0, 0, 0, 180)]

        # テキストカラー
        @text_color     = Color::WHITE
        @text_disabled  = Color.new(120, 120, 130)

        # スライダー・アクセントカラー
        @accent_color   = Color.new(0, 195, 255)
        @accent_hover   = Color.new(50, 220, 255)
        @track_bg       = Color.new(25, 28, 35, 220)
        @track_border   = [1.0, Color.new(60, 65, 80, 150)]

        # スタイル設定
        @corner_radius  = 8.0
        @font_size      = 14
      end
    end
  end
end

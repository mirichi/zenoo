# frozen_string_literal: true

module Zenoo
  module GUI
    class Theme
      attr_accessor :bg_normal, :bg_hover, :bg_active,
                    :border_normal, :border_hover, :border_active,
                    :shadow_normal, :shadow_hover, :shadow_active,
                    :win_bg, :win_title_bg, :win_title_bg_active,
                    :win_border_normal, :win_border_active,
                    :text_color, :text_disabled,
                    :accent_color, :accent_hover, :track_bg, :track_border,
                    :corner_radius, :font_size, :font

      def initialize(preset = :tool_dark)
        apply_preset(preset)
      end

      def apply_preset(preset)
        case preset
        when :cyber
          apply_cyber
        else
          apply_tool_dark
        end
      end

      # ツール・デバッグ向けのシンプル＆フラットなグレースケールテーマ (デフォルト)
      def apply_tool_dark
        @font           = nil
        # 背景色 (ダークグレー)
        @bg_normal      = Color.new(42, 42, 44, 235)
        @bg_hover       = Color.new(58, 58, 62, 245)
        @bg_active      = Color.new(75, 75, 80, 255)

        # ウィンドウ装飾 (フラットなモノトーン・ダークグレー)
        @win_bg              = Color.new(30, 30, 32, 245)
        @win_title_bg        = Color.new(42, 42, 45, 240)
        @win_title_bg_active = Color.new(52, 52, 58, 255)
        @win_border_normal   = [1.0, Color.new(65, 65, 70, 200)]
        @win_border_active   = [1.0, Color.new(120, 120, 130, 240)]

        # ボーダー設定 [幅, Color] (端正な1pxグレー)
        @border_normal  = [1.0, Color.new(70, 70, 75, 180)]
        @border_hover   = [1.0, Color.new(120, 120, 130, 220)]
        @border_active  = [1.5, Color.new(180, 180, 190, 255)]

        # シャドウ設定 (控えめなドロップシャドウ)
        @shadow_normal  = [4.0, Color.new(0, 0, 0, 100)]
        @shadow_hover   = [6.0, Color.new(0, 0, 0, 140)]
        @shadow_active  = [2.0, Color.new(0, 0, 0, 160)]

        # テキストカラー
        @text_color     = Color.new(235, 235, 235)
        @text_disabled  = Color.new(110, 110, 115)

        # スライダー・アクセントカラー (落ち着いたライトグレー・シルバー)
        @accent_color   = Color.new(160, 165, 175)
        @accent_hover   = Color.new(200, 205, 215)
        @track_bg       = Color.new(28, 28, 30, 220)
        @track_border   = [1.0, Color.new(55, 55, 60, 160)]

        # スタイル設定 (ツール向けにコンパクト＆シャープ)
        @corner_radius  = 4.0
        @font_size      = 15
      end

      # サイバー・ゲーム風テーマ
      def apply_cyber
        @font           = nil
        # ウィンドウ装飾
        @win_bg              = Color.new(22, 26, 36, 245)
        @win_title_bg        = Color.new(28, 32, 44, 230)
        @win_title_bg_active = Color.new(35, 45, 65, 230)
        @win_border_normal   = [1.5, Color.new(60, 70, 90, 180)]
        @win_border_active   = [2.0, Color.new(0, 200, 255, 220)]
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
        @font_size      = 18
      end
    end
  end
end

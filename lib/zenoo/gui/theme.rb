# frozen_string_literal: true

module Zenoo
  module GUI
    class Theme
      @custom_presets = {}

      class << self
        attr_reader :custom_presets

        # カスタムテーマ（プリセット）の動的登録
        # 例:
        #   Theme.register(:coords_blue, bg_normal: [30, 40, 60, 200], ...)
        #   Theme.register(:my_theme, base: :cyber, accent_color: [255, 100, 100])
        def register(name, base: :tool_dark, **attrs)
          @custom_presets[name.to_sym] = { base: base, attrs: attrs }
        end
      end

      attr_accessor :bg_normal, :bg_hover, :bg_active,
                    :border_normal, :border_hover, :border_active,
                    :shadow_normal, :shadow_hover, :shadow_active,
                    :win_bg, :win_title_bg, :win_title_bg_active,
                    :win_border_normal, :win_border_active,
                    :text_color, :text_disabled,
                    :accent_color, :accent_hover, :track_bg, :track_border,
                    :corner_radius, :font_size, :font

      def initialize(preset = :tool_dark, **overrides)
        apply_preset(preset)
        update(**overrides) unless overrides.empty?
      end

      # プロパティの一括更新 (配列形式の色指定 [r, g, b, a] にも対応)
      def update(
        bg_normal: nil, bg_hover: nil, bg_active: nil,
        border_normal: nil, border_hover: nil, border_active: nil,
        shadow_normal: nil, shadow_hover: nil, shadow_active: nil,
        win_bg: nil, win_title_bg: nil, win_title_bg_active: nil,
        win_border_normal: nil, win_border_active: nil,
        text_color: nil, text_disabled: nil,
        accent_color: nil, accent_hover: nil, track_bg: nil, track_border: nil,
        corner_radius: nil, font_size: nil, font: nil
      )
        self.bg_normal     = normalize_color(bg_normal) unless bg_normal.nil?
        self.bg_hover      = normalize_color(bg_hover) unless bg_hover.nil?
        self.bg_active     = normalize_color(bg_active) unless bg_active.nil?
        self.border_normal = normalize_pair(border_normal) unless border_normal.nil?
        self.border_hover  = normalize_pair(border_hover) unless border_hover.nil?
        self.border_active = normalize_pair(border_active) unless border_active.nil?
        self.shadow_normal = normalize_pair(shadow_normal) unless shadow_normal.nil?
        self.shadow_hover  = normalize_pair(shadow_hover) unless shadow_hover.nil?
        self.shadow_active = normalize_pair(shadow_active) unless shadow_active.nil?
        self.win_bg        = normalize_color(win_bg) unless win_bg.nil?
        self.win_title_bg  = normalize_color(win_title_bg) unless win_title_bg.nil?
        self.win_title_bg_active = normalize_color(win_title_bg_active) unless win_title_bg_active.nil?
        self.win_border_normal   = normalize_pair(win_border_normal) unless win_border_normal.nil?
        self.win_border_active   = normalize_pair(win_border_active) unless win_border_active.nil?
        self.text_color    = normalize_color(text_color) unless text_color.nil?
        self.text_disabled = normalize_color(text_disabled) unless text_disabled.nil?
        self.accent_color  = normalize_color(accent_color) unless accent_color.nil?
        self.accent_hover  = normalize_color(accent_hover) unless accent_hover.nil?
        self.track_bg      = normalize_color(track_bg) unless track_bg.nil?
        self.track_border  = normalize_pair(track_border) unless track_border.nil?
        self.corner_radius = corner_radius.to_f unless corner_radius.nil?
        self.font_size     = font_size.to_i unless font_size.nil?
        self.font          = font unless font.nil?
        self
      end

      def apply_preset(preset)
        sym = preset.to_sym
        custom = Theme.custom_presets[sym]
        if !custom.nil?
          apply_preset(custom[:base])
          update(**custom[:attrs])
        elsif sym == :cyber
          apply_cyber
        else
          apply_tool_dark
        end
      end

      # ツール・デバッグ向けのシンプル＆フラットなグレースケールテーマ (デフォルト)
      def apply_tool_dark
        @font           = nil
        # 背景色 (ダークグレー)
        @bg_normal      = Color.new(46, 46, 50, 240)
        @bg_hover       = Color.new(62, 62, 68, 245)
        @bg_active      = Color.new(78, 78, 86, 255)

        # ウィンドウ装飾 (フラットなモノトーン・ダークグレー)
        @win_bg              = Color.new(30, 30, 32, 245)
        @win_title_bg        = Color.new(42, 42, 45, 240)
        @win_title_bg_active = Color.new(52, 52, 58, 255)
        @win_border_normal   = [1.0, Color.new(65, 65, 70, 200)]
        @win_border_active   = [1.0, Color.new(120, 120, 130, 240)]

        # ボーダー設定 [幅, Color] (端正な1pxグレー)
        @border_normal  = [1.0, Color.new(90, 95, 105, 220)]
        @border_hover   = [1.0, Color.new(145, 150, 165, 240)]
        @border_active  = [1.5, Color.new(190, 195, 210, 255)]

        # シャドウ設定 (控えめなドロップシャドウ)
        @shadow_normal  = [4.0, Color.new(0, 0, 0, 100)]
        @shadow_hover   = [6.0, Color.new(0, 0, 0, 140)]
        @shadow_active  = [2.0, Color.new(0, 0, 0, 160)]

        # テキストカラー
        @text_color     = Color.new(235, 235, 235)
        @text_disabled  = Color.new(110, 110, 115)

        # スライダー・アクセントカラー (落ち着いたライトグレー・シルバー)
        @accent_color   = Color.new(175, 180, 195)
        @accent_hover   = Color.new(215, 220, 235)
        @track_bg       = Color.new(32, 32, 36, 230)
        @track_border   = [1.0, Color.new(70, 75, 85, 180)]

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

      private

      def normalize_attr(key, val)
        case key.to_sym
        when :bg_normal, :bg_hover, :bg_active,
             :win_bg, :win_title_bg, :win_title_bg_active,
             :text_color, :text_disabled,
             :accent_color, :accent_hover, :track_bg
          normalize_color(val)
        when :border_normal, :border_hover, :border_active,
             :win_border_normal, :win_border_active,
             :shadow_normal, :shadow_hover, :shadow_active,
             :track_border
          normalize_pair(val)
        else
          val
        end
      end

      def normalize_color(val)
        return val if val.is_a?(Color)
        return Color.new(*val) if val.is_a?(Array)
        val
      end

      def normalize_pair(val)
        return val unless val.is_a?(Array)
        width_or_blur = val[0]
        color = normalize_color(val[1])
        [width_or_blur, color]
      end
    end
  end
end

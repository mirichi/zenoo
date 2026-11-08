# frozen_string_literal: true

require_relative 'ui/theme'
require_relative 'ui/widget'
require_relative 'ui/widgets'
require_relative 'ui/containers'
require_relative 'ui/builder'

module Zenoo
  # Sprite ベースの保持モード (Retained Mode) UI システム
  module UI
    Widget.include(Builder)
    @theme             = Theme.new
    @active_widget     = nil
    @focused_widget    = nil
    @hovered_widget    = nil
    @open_popup_widget = nil
    @mouse_captured    = false
    @prev_captured     = false
    @requested_cursor  = nil
    @blink_time        = 0.0
    @hit_test_point    = nil

    class << self
      attr_accessor :active_widget, :hovered_widget, :open_popup_widget, :blink_time
      attr_reader :focused_widget, :requested_cursor

      # 点判定用の再利用 Point コライダー (GC 圧迫防止)
      def hit_test_point
        @hit_test_point ||= Collision::Point.new(0.0, 0.0)
      end

      # テーマの設定または取得
      # - 引数なし: 現在の Theme オブジェクトを返却
      # - 引数あり: プリセット適用 or プロパティ上書き
      def theme(preset = nil, **overrides)
        if preset.nil? && overrides.empty?
          @theme
        elsif preset.is_a?(Symbol)
          @theme = Theme.new(preset, **overrides)
        elsif preset.is_a?(Theme)
          @theme = preset
          @theme.configure(**overrides) unless overrides.empty?
          @theme
        else
          @theme.configure(**overrides)
        end
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
      end

      def focused_widget=(w)
        return if @focused_widget.equal?(w)
        old = @focused_widget
        @focused_widget = w
        @blink_time = 0.0
        old.on_blur if old
        if w
          w.on_focus
        else
          Input.set_ime_position(-1, -1)
        end
      end

      def clear_focus
        self.focused_widget = nil
      end

      def set_mouse_cursor(shape)
        @requested_cursor = shape
      end

      def mark_mouse_captured!
        @mouse_captured = true
      end

      def mouse_captured?
        @mouse_captured || @prev_captured || !@active_widget.nil? || !@hovered_widget.nil?
      end

      def has_keyboard_focus?
        !@focused_widget.nil?
      end

      # フレーム開始処理 (Window.loop で毎フレーム自動呼び出し)
      def begin_frame
        @prev_captured = @mouse_captured || !@active_widget.nil? || !@hovered_widget.nil?
        @mouse_captured = false
        @hovered_widget = nil
        @requested_cursor = nil
        @blink_time = (@blink_time || 0.0) + Zenoo::Window.delta_time

        if @active_widget && (@active_widget.vanished? || !@active_widget.visible || !@active_widget.enabled)
          @active_widget = nil
        end

        if @focused_widget && (@focused_widget.vanished? || !@focused_widget.visible || !@focused_widget.enabled)
          self.focused_widget = nil
        end

        if @open_popup_widget && (@open_popup_widget.vanished? || !@open_popup_widget.visible || !@open_popup_widget.enabled)
          @open_popup_widget = nil
        end
      end

      # フレーム終了処理 (Window.loop で毎フレーム自動呼び出し)
      def end_frame
        # 開いているポップアップの最前面オーバーレイ描画
        if (pop = @open_popup_widget) && !pop.vanished? && pop.visible
          pop.draw_popup_overlay
        end

        # マウスボタンが離されたらドラッグ状態を解除
        if @active_widget && !Input.mouse_pressed?(:left)
          w = @active_widget
          @active_widget = nil
          w.on_pointer_up(Input.mouse_x.to_f, Input.mouse_y.to_f, false)
        end
      end

      # ウィジェットツリーまたは配列の一括更新
      def update(widgets = nil)
        Sprite.update(widgets)
      end

      # ウィジェットツリーまたは配列の一括描画
      def draw(widgets = nil)
        Sprite.draw(widgets)
      end
    end
  end
end

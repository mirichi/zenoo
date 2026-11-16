# frozen_string_literal: true

require_relative 'ui/theme'
require_relative 'ui/widget'
require_relative 'ui/containers'
require_relative 'ui/widgets'
require_relative 'ui/builder'

module Zenoo
  # Sprite ベースの保持モード UI システム
  module UI
    Widget.include(Builder)

    @theme            = Theme.new(:compact)
    @frame            = 0
    @point_collider   = Collision::Point.new(anchor: :center, pivot: :center)
    @mouse_captured   = false
    @prev_captured    = false
    @pointer_claimed  = false
    @requested_cursor = nil
    @cursor_dirty     = false
    @focused_stage    = nil

    class << self
      attr_accessor :frame

      # 当たり判定用の再利用 Point コライダーを返す
      def point_collider(px, py)
        @point_collider.x = px.to_f
        @point_collider.y = py.to_f
        @point_collider
      end

      # グローバルテーマを取得・設定する
      def theme(preset = nil, **overrides)
        if preset.is_a?(Theme)
          @theme = preset
          overrides.each { |k, v| @theme.public_send(:"#{k}=", v) } unless overrides.empty?
        elsif preset.is_a?(Symbol)
          @theme = Theme.new(preset, **overrides)
        elsif !overrides.empty?
          overrides.each { |k, v| @theme.public_send(:"#{k}=", v) }
        end
        @theme
      end

      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
      end

      # 複数 Stage 間でポインタ消費状態をマーク・参照する
      def claim_pointer!
        @pointer_claimed = true
        @mouse_captured  = true
      end

      def pointer_claimed?
        @pointer_claimed
      end

      # UI が現在ポインタ入力を捕捉しているかを返す
      def mouse_captured?
        @mouse_captured || @prev_captured
      end

      # 複数 Stage 間でキーボードフォーカスを排他管理する
      def notify_focus(stage, widget)
        if widget
          if @focused_stage && !@focused_stage.equal?(stage)
            @focused_stage.set_focus(nil)
          end
          @focused_stage = stage
        elsif @focused_stage.equal?(stage)
          @focused_stage = nil
        end
      end

      def has_keyboard_focus?
        !@focused_stage.nil? && !@focused_stage.focused_widget.nil?
      end

      # このフレームで希望するマウスカーソル形状を設定する
      def set_mouse_cursor(shape)
        @requested_cursor = shape
      end

      # フレーム開始時の状態リセット（Window.loop 内から自動呼び出し）
      def begin_frame
        @frame += 1
        @prev_captured    = @mouse_captured
        @mouse_captured   = false
        @pointer_claimed  = false
        @requested_cursor = nil
      end

      # フレーム終了時のカーソル反映（Window.loop 内から自動呼び出し）
      def end_frame
        if @requested_cursor
          Zenoo::Window.cursor = @requested_cursor
          @cursor_dirty = (@requested_cursor != :arrow)
        elsif @cursor_dirty
          Zenoo::Window.cursor = :arrow
          @cursor_dirty = false
        end
      end
    end
  end
end

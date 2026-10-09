# frozen_string_literal: true

module Zenoo
  # 2D ゲーム用カメラクラス
  # スクロール追従、画面シェイク、スクリーン/ワールド座標相互変換を管理します。
  class Camera2D
    attr_accessor :x, :y, :zoom
    attr_accessor :offset_x, :offset_y
    attr_accessor :smooth_speed
    attr_reader :shake_x, :shake_y, :shake_intensity

    def initialize(x: 0.0, y: 0.0, zoom: 1.0, offset_x: nil, offset_y: nil, target: nil, smooth_speed: 0.0)
      @x = x.to_f
      @y = y.to_f
      @zoom = zoom.to_f
      @offset_x = offset_x ? offset_x.to_f : nil
      @offset_y = offset_y ? offset_y.to_f : nil
      @target = target
      @smooth_speed = smooth_speed.to_f # 0.0 で即時追従、>0 で補間追従 (Lerp)

      # 画面シェイク
      @shake_intensity = 0.0
      @shake_duration = 0.0
      @shake_timer = 0.0
      @shake_x = 0.0
      @shake_y = 0.0
    end

    # 注視対象 (x, y メソッドを持つオブジェクト、または [x, y] 配列)
    def target
      @target
    end

    def target=(obj)
      @target = obj
    end

    # 画面シェイクの発動
    # - intensity: 揺れの強さ (ピクセル)
    # - duration: 揺れる時間 (秒数またはフレーム数)
    def shake(intensity = 12.0, duration = 0.3)
      @shake_intensity = intensity.to_f
      @shake_duration = duration.to_f
      @shake_timer = duration.to_f
    end

    # 毎フレームの更新 (ターゲット追従とシェイク減衰)
    def update(dt = 1.0 / 60.0)
      # 1. ターゲット自動追従
      if @target
        tx = 0.0
        ty = 0.0
        if @target.is_a?(Array)
          tx = @target[0].to_f
          ty = @target[1].to_f
        elsif @target.respond_to?(:x) && @target.respond_to?(:y)
          tx = @target.x.to_f
          ty = @target.y.to_f
        end

        if @smooth_speed > 0.0
          # 滑らかな補間 (Lerp)
          rate = [dt * @smooth_speed * 10.0, 1.0].min
          @x += (tx - @x) * rate
          @y += (ty - @y) * rate
        else
          # 即時追従
          @x = tx
          @y = ty
        end
      end

      # 2. 画面シェイクの計算
      if @shake_timer > 0.0
        @shake_timer -= dt
        decay = @shake_duration > 0.0 ? (@shake_timer / @shake_duration) : 0.0
        decay = 0.0 if decay < 0.0
        cur_intensity = @shake_intensity * decay
        @shake_x = (rand(2001) - 1000).to_f / 1000.0 * cur_intensity
        @shake_y = (rand(2001) - 1000).to_f / 1000.0 * cur_intensity
        if @shake_timer <= 0.0
          @shake_intensity = 0.0
          @shake_x = 0.0
          @shake_y = 0.0
        end
      else
        @shake_x = 0.0
        @shake_y = 0.0
      end
    end

    # カメラのスクリーン中心座標
    def screen_center_x
      @offset_x || (Window.width.to_f * 0.5)
    end

    def screen_center_y
      @offset_y || (Window.height.to_f * 0.5)
    end

    # 描画用トータルオフセット
    def calc_offset_x
      screen_center_x - (@x + @shake_x) * @zoom
    end

    def calc_offset_y
      screen_center_y - (@y + @shake_y) * @zoom
    end

    # 画面座標 -> ワールド座標への逆変換 (マウス入力やクリック判定用)
    def screen_to_world(sx, sy)
      wx = (sx.to_f - screen_center_x) / @zoom + (@x + @shake_x)
      wy = (sy.to_f - screen_center_y) / @zoom + (@y + @shake_y)
      [wx, wy]
    end

    # ワールド座標 -> 画面座標への変換
    def world_to_screen(wx, wy)
      sx = (wx.to_f - (@x + @shake_x)) * @zoom + screen_center_x
      sy = (wy.to_f - (@y + @shake_y)) * @zoom + screen_center_y
      [sx, sy]
    end
  end
end

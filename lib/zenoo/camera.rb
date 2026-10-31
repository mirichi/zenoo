# frozen_string_literal: true

module Zenoo
  # 2D ゲーム用カメラクラス
  # スクロール追従、画面シェイク、スクリーン/ワールド座標相互変換を管理します。
  #
  # 変換は「screen = world * zoom + (ox, oy)」の形に正規化され、
  # #view が [zoom, ox, oy] を返します。値はパラメータ変更時 (dirty) または
  # 画面サイズ変化時のみ再計算され、それ以外はキャッシュを返します。
  # Window 側はこの #view を描画時に参照するだけで、Camera から Window への依存はありません。
  class Camera
    attr_reader :x, :y, :zoom
    attr_reader :offset_x, :offset_y
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

      # 変換キャッシュ ([zoom, ox, oy])
      @view = nil
      @view_w = nil
      @view_h = nil
    end

    def x=(v)
      @x = v.to_f
      @view = nil
    end

    def y=(v)
      @y = v.to_f
      @view = nil
    end

    def zoom=(v)
      @zoom = v.to_f
      @view = nil
    end

    def offset_x=(v)
      @offset_x = v ? v.to_f : nil
      @view = nil
    end

    def offset_y=(v)
      @offset_y = v ? v.to_f : nil
      @view = nil
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
        @view = nil
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
        @view = nil
      elsif @shake_x != 0.0 || @shake_y != 0.0
        @shake_x = 0.0
        @shake_y = 0.0
        @view = nil
      end
    end

    # カメラのスクリーン中心座標
    def screen_center_x
      return @offset_x if @offset_x
      t = Backend.current_target
      (t ? t.width.to_f : Window.width.to_f) * 0.5
    end

    def screen_center_y
      return @offset_y if @offset_y
      t = Backend.current_target
      (t ? t.height.to_f : Window.height.to_f) * 0.5
    end

    # 描画用変換 [zoom, ox, oy] (screen = world * zoom + o)
    # パラメータ・画面サイズが変わらない限りキャッシュ済みの配列を返す
    def view
      # offset 未指定時は画面中心に依存するため、画面サイズ変化も検知する
      if @offset_x.nil? || @offset_y.nil?
        t = Backend.current_target
        w = t ? t.width : Window.width
        h = t ? t.height : Window.height
        if w != @view_w || h != @view_h
          @view_w = w
          @view_h = h
          @view = nil
        end
      end
      @view ||= [
        @zoom,
        screen_center_x - (@x + @shake_x) * @zoom,
        screen_center_y - (@y + @shake_y) * @zoom
      ].freeze
    end

    # パララックス係数付きの描画用変換 [zoom, ox, oy]
    # (px, py) = (1, 1) のときは #view と同じ
    def parallax_view(px, py)
      return view if px == 1.0 && py == 1.0
      [
        @zoom,
        screen_center_x - (@x + @shake_x) * px * @zoom,
        screen_center_y - (@y + @shake_y) * py * @zoom
      ]
    end

    # 描画用トータルオフセット
    def calc_offset_x
      view[1]
    end

    def calc_offset_y
      view[2]
    end

    # 画面座標 -> ワールド座標への逆変換 (マウス入力やクリック判定用)
    def screen_to_world(sx, sy)
      z, ox, oy = view
      [(sx.to_f - ox) / z, (sy.to_f - oy) / z]
    end

    # ワールド座標 -> 画面座標への変換
    def world_to_screen(wx, wy)
      z, ox, oy = view
      [wx.to_f * z + ox, wy.to_f * z + oy]
    end

    # 画面矩形 (0, 0)-(w, h) に映るワールド範囲 [left, top, right, bottom]
    # カリング用。負のズームによる反転も正規化する
    def visible_rect(w = Window.width, h = Window.height)
      z, ox, oy = view
      x1 = -ox / z
      y1 = -oy / z
      x2 = (w.to_f - ox) / z
      y2 = (h.to_f - oy) / z
      x1, x2 = x2, x1 if x1 > x2
      y1, y2 = y2, y1 if y1 > y2
      [x1, y1, x2, y2]
    end
  end
end

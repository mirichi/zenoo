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
    attr_reader :width, :height
    attr_accessor :smooth_speed
    attr_reader :shake_x, :shake_y, :shake_intensity
    attr_reader :bounds
    attr_accessor :target_offset_x, :target_offset_y

    # カメラを生成します。
    #
    # - `x:` (`Numeric`): カメラ中心のワールドX座標 (デフォルト: `0.0`)
    # - `y:` (`Numeric`): カメラ中心のワールドY座標 (デフォルト: `0.0`)
    # - `zoom:` (`Numeric`): 拡大率 (`1.0` で等倍、デフォルト: `1.0`)
    # - `offset_x:` (`Numeric, nil`): スクリーン基準点のX座標 (省略時は画面中央)
    # - `offset_y:` (`Numeric, nil`): スクリーン基準点のY座標 (省略時は画面中央)
    # - `width:` (`Numeric, nil`): ビューポート幅 (省略時は現在のレンダーターゲット/ウィンドウ幅)
    # - `height:` (`Numeric, nil`): ビューポート高さ (省略時は現在のレンダーターゲット/ウィンドウ高さ)
    # - `target:` (`Object, Array, nil`): 自動追従する対象 (`#x`/`#y` を持つオブジェクトまたは `[x, y]` 配列)
    # - `smooth_speed:` (`Numeric`): 追従の滑らかさ (`0.0` で即時追従、`> 0` で補間追従、デフォルト: `0.0`)
    # - `bounds:` (`Array<Numeric>, nil`): カメラ移動範囲の制限 `[min_x, min_y, max_x, max_y]`
    # - `target_offset_x:` (`Numeric`): 追従対象からのX方向オフセット (デフォルト: `0.0`)
    # - `target_offset_y:` (`Numeric`): 追従対象からのY方向オフセット (デフォルト: `0.0`)
    def initialize(x: 0.0, y: 0.0, zoom: 1.0, offset_x: nil, offset_y: nil, width: nil, height: nil, target: nil, smooth_speed: 0.0, bounds: nil, target_offset_x: 0.0, target_offset_y: 0.0)
      @x = x.to_f
      @y = y.to_f
      @zoom = zoom.to_f
      @offset_x = offset_x ? offset_x.to_f : nil
      @offset_y = offset_y ? offset_y.to_f : nil
      @width = width ? width.to_f : nil
      @height = height ? height.to_f : nil
      @target = target
      @smooth_speed = smooth_speed.to_f # 0.0 で即時追従、>0 で補間追従 (Lerp)
      @bounds = bounds ? bounds.map(&:to_f) : nil # [min_x, min_y, max_x, max_y]
      @target_offset_x = target_offset_x.to_f
      @target_offset_y = target_offset_y.to_f

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
      clamp_to_bounds! if @bounds
    end

    # カメラ中心のワールドX座標を設定します (`bounds` 指定時は範囲内にクランプ)。
    #
    # - `v` (`Numeric`): ワールドX座標
    def x=(v)
      @x = v.to_f
      clamp_to_bounds!
      @view = nil
    end

    # カメラ中心のワールドY座標を設定します (`bounds` 指定時は範囲内にクランプ)。
    #
    # - `v` (`Numeric`): ワールドY座標
    def y=(v)
      @y = v.to_f
      clamp_to_bounds!
      @view = nil
    end

    # カメラの拡大率を設定します。
    #
    # - `v` (`Numeric`): 拡大率 (`1.0` で等倍)
    def zoom=(v)
      @zoom = v.to_f
      clamp_to_bounds!
      @view = nil
    end

    # スクリーン基準点のX座標を設定します (`nil` で画面中央)。
    #
    # - `v` (`Numeric, nil`): スクリーンX座標
    def offset_x=(v)
      @offset_x = v ? v.to_f : nil
      clamp_to_bounds!
      @view = nil
    end

    # スクリーン基準点のY座標を設定します (`nil` で画面中央)。
    #
    # - `v` (`Numeric, nil`): スクリーンY座標
    def offset_y=(v)
      @offset_y = v ? v.to_f : nil
      clamp_to_bounds!
      @view = nil
    end

    # ビューポート幅を設定します (`nil` で現在の描画先幅を自動参照)。
    #
    # - `v` (`Numeric, nil`): ビューポート幅
    def width=(v)
      @width = v ? v.to_f : nil
      clamp_to_bounds!
      @view = nil
    end

    # ビューポート高さを設定します (`nil` で現在の描画先高さを自動参照)。
    #
    # - `v` (`Numeric, nil`): ビューポート高さ
    def height=(v)
      @height = v ? v.to_f : nil
      clamp_to_bounds!
      @view = nil
    end

    # カメラの移動可能範囲を設定します (`nil` で制限解除)。
    #
    # - `b` (`Array<Numeric>, nil`): `[min_x, min_y, max_x, max_y]` のワールド座標配列
    def bounds=(b)
      @bounds = b ? b.map(&:to_f) : nil
      clamp_to_bounds!
      @view = nil
    end

    # 注視対象 (x, y メソッドを持つオブジェクト、または [x, y] 配列) を返します。
    def target
      @target
    end

    # 自動追従する注視対象を設定します。
    #
    # - `obj` (`Object, Array, nil`): `#x`/`#y` を持つオブジェクトまたは `[x, y]` 配列
    def target=(obj)
      @target = obj
    end

    # 画面シェイクの発動
    #
    # - `intensity` (`Numeric`): 揺れの強さ (ピクセル単位、デフォルト: `12.0`)
    # - `duration` (`Numeric`): 揺れる時間 (`update` の `dt` と同じ単位、デフォルト: `0.3`)
    def shake(intensity = 12.0, duration = 0.3)
      @shake_intensity = intensity.to_f
      @shake_duration = duration.to_f
      @shake_timer = duration.to_f
    end

    # 毎フレームの更新 (ターゲット追従とシェイク減衰)
    #
    # - `dt` (`Numeric`): 経過時間 (秒単位、デフォルト: `1.0 / 60.0`)
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
          @x += (tx + @target_offset_x - @x) * rate
          @y += (ty + @target_offset_y - @y) * rate
        else
          # 即時追従
          @x = tx + @target_offset_x
          @y = ty + @target_offset_y
        end
        clamp_to_bounds!
        @view = nil
      elsif @bounds
        clamp_to_bounds!
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

    # カメラのスクリーン中心X座標を返します (`offset_x` 未設定時はビューポート幅の半分)。
    def screen_center_x
      return @offset_x if @offset_x
      target_width * 0.5
    end

    # カメラのスクリーン中心Y座標を返します (`offset_y` 未設定時はビューポート高さの半分)。
    def screen_center_y
      return @offset_y if @offset_y
      target_height * 0.5
    end

    # 描画用変換 [zoom, ox, oy] (screen = world * zoom + o)
    # パラメータ・画面サイズが変わらない限りキャッシュ済みの配列を返す
    def view
      w = target_width
      h = target_height
      if w != @view_w || h != @view_h
        @view_w = w
        @view_h = h
        clamp_to_bounds!
        @view = nil
      end
      @view ||= [
        @zoom,
        screen_center_x - (@x + @shake_x) * @zoom,
        screen_center_y - (@y + @shake_y) * @zoom
      ].freeze
    end

    # パララックス係数付きの描画用変換 [zoom, ox, oy]
    # (px, py) = (1, 1) のときは #view と同じ
    #
    # - `px` (`Numeric`): X方向のスクロール倍率 (`0.0` で固定、`1.0` で通常追従)
    # - `py` (`Numeric`): Y方向のスクロール倍率 (`0.0` で固定、`1.0` で通常追従)
    def parallax_view(px, py)
      return view if px == 1.0 && py == 1.0
      [
        @zoom,
        screen_center_x - (@x + @shake_x) * px * @zoom,
        screen_center_y - (@y + @shake_y) * py * @zoom
      ]
    end

    # 画面座標 -> ワールド座標への逆変換 (マウス入力やクリック判定用)
    #
    # - `sx` (`Numeric`): スクリーンX座標
    # - `sy` (`Numeric`): スクリーンY座標
    # - 戻り値: `Array<Float>` `[world_x, world_y]`
    def screen_to_world(sx, sy)
      z, ox, oy = view
      [(sx.to_f - ox) / z, (sy.to_f - oy) / z]
    end

    # ワールド座標 -> 画面座標への変換
    #
    # - `wx` (`Numeric`): ワールドX座標
    # - `wy` (`Numeric`): ワールドY座標
    # - 戻り値: `Array<Float>` `[screen_x, screen_y]`
    def world_to_screen(wx, wy)
      z, ox, oy = view
      [wx.to_f * z + ox, wy.to_f * z + oy]
    end

    # 画面矩形 (0, 0)-(w, h) に映るワールド範囲 [left, top, right, bottom]
    # カリング用。負のズームによる反転も正規化する
    #
    # - `w` (`Numeric`): ビューポート幅 (デフォルト: 現在の描画先幅)
    # - `h` (`Numeric`): ビューポート高さ (デフォルト: 現在の描画先高さ)
    # - 戻り値: `Array<Float>` `[left, top, right, bottom]`
    def visible_rect(w = target_width, h = target_height)
      z, ox, oy = view
      x1 = -ox / z
      y1 = -oy / z
      x2 = (w.to_f - ox) / z
      y2 = (h.to_f - oy) / z
      x1, x2 = x2, x1 if x1 > x2
      y1, y2 = y2, y1 if y1 > y2
      [x1, y1, x2, y2]
    end

    private

    def target_width
      return @width if @width
      t = Backend.current_target
      t ? t.width.to_f : Window.width.to_f
    end

    def target_height
      return @height if @height
      t = Backend.current_target
      t ? t.height.to_f : Window.height.to_f
    end

    def clamp_to_bounds!
      return unless @bounds
      w = target_width
      h = target_height
      return if w <= 0.0 || h <= 0.0

      min_x, min_y, max_x, max_y = @bounds
      z = @zoom > 0.0 ? @zoom : 1.0
      cx = @offset_x || (w * 0.5)
      cy = @offset_y || (h * 0.5)

      low_x  = min_x + cx / z
      high_x = max_x - (w - cx) / z
      low_y  = min_y + cy / z
      high_y = max_y - (h - cy) / z

      @x = low_x <= high_x ? @x.clamp(low_x, high_x) : ((min_x + max_x) * 0.5 + (cx - w * 0.5) / z)
      @y = low_y <= high_y ? @y.clamp(low_y, high_y) : ((min_y + max_y) * 0.5 + (cy - h * 0.5) / z)
    end
  end
end

# frozen_string_literal: true

module Zenoo
  # ====================================================================
  # Zenoo::Easing - 2D アニメーション用イージング関数コレクション
  # ====================================================================
  # Robert Penner の Easing Equations に基づく補間関数群。
  # 引数 t (0.0 .. 1.0) を受け取り、加減速された進捗率 (0.0 .. 1.0) を返します。
  # ====================================================================
  module Easing
    module_function

    # ------------------------------------------------------------------
    # イージング関数のディスパッチ
    # ------------------------------------------------------------------
    # :linear, :quad_in, :out_quad, :bounce_out, :elastic_in_out などを柔軟に解釈
    def calc(type, t)
      return 1.0 if t >= 1.0
      return 0.0 if t <= 0.0

      case type
      # Linear
      when :linear, nil
        t

      # Step (補間なし・整数フレーム/コマ送り用)
      when :step
        t < 1.0 ? 0.0 : 1.0

      # Quadratic
      when :quad_in, :in_quad
        t * t
      when :quad_out, :out_quad
        t * (2.0 - t)
      when :quad_in_out, :in_out_quad
        t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t

      # Cubic
      when :cubic_in, :in_cubic
        t * t * t
      when :cubic_out, :out_cubic
        t -= 1.0
        t * t * t + 1.0
      when :cubic_in_out, :in_out_cubic
        t < 0.5 ? 4.0 * t * t * t : (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0

      # Quartic
      when :quart_in, :in_quart
        t * t * t * t
      when :quart_out, :out_quart
        t -= 1.0
        1.0 - t * t * t * t
      when :quart_in_out, :in_out_quart
        if t < 0.5
          8.0 * t * t * t * t
        else
          t -= 1.0
          1.0 - 8.0 * t * t * t * t
        end

      # Quintic
      when :quint_in, :in_quint
        t * t * t * t * t
      when :quint_out, :out_quint
        t -= 1.0
        t * t * t * t * t + 1.0
      when :quint_in_out, :in_out_quint
        if t < 0.5
          16.0 * t * t * t * t * t
        else
          t -= 1.0
          16.0 * t * t * t * t * t + 1.0
        end

      # Sine
      when :sine_in, :in_sine
        1.0 - Math.cos(t * (Math::PI / 2.0))
      when :sine_out, :out_sine
        Math.sin(t * (Math::PI / 2.0))
      when :sine_in_out, :in_out_sine
        0.5 * (1.0 - Math.cos(Math::PI * t))

      # Exponential
      when :expo_in, :in_expo
        (2.0 ** (10.0 * (t - 1.0)))
      when :expo_out, :out_expo
        1.0 - (2.0 ** (-10.0 * t))
      when :expo_in_out, :in_out_expo
        if t < 0.5
          0.5 * (2.0 ** (20.0 * t - 10.0))
        else
          1.0 - 0.5 * (2.0 ** (-20.0 * t + 10.0))
        end

      # Circular
      when :circ_in, :in_circ
        1.0 - Math.sqrt(1.0 - t * t)
      when :circ_out, :out_circ
        t -= 1.0
        Math.sqrt(1.0 - t * t)
      when :circ_in_out, :in_out_circ
        if t < 0.5
          0.5 * (1.0 - Math.sqrt(1.0 - 4.0 * t * t))
        else
          t = 2.0 * t - 2.0
          0.5 * (Math.sqrt(1.0 - t * t) + 1.0)
        end

      # Back (少し行き過ぎて戻る)
      when :back_in, :in_back
        s = 1.70158
        t * t * ((s + 1.0) * t - s)
      when :back_out, :out_back
        s = 1.70158
        t -= 1.0
        t * t * ((s + 1.0) * t + s) + 1.0
      when :back_in_out, :in_out_back
        s = 1.70158 * 1.525
        t *= 2.0
        if t < 1.0
          0.5 * (t * t * ((s + 1.0) * t - s))
        else
          t -= 2.0
          0.5 * (t * t * ((s + 1.0) * t + s) + 2.0)
        end

      # Elastic (ゴムのように振動して収束する)
      when :elastic_in, :in_elastic
        return 0.0 if t == 0.0
        return 1.0 if t == 1.0
        p = 0.3
        s = p / 4.0
        t -= 1.0
        -(2.0 ** (10.0 * t)) * Math.sin((t - s) * (2.0 * Math::PI) / p)
      when :elastic_out, :out_elastic
        return 0.0 if t == 0.0
        return 1.0 if t == 1.0
        p = 0.3
        s = p / 4.0
        (2.0 ** (-10.0 * t)) * Math.sin((t - s) * (2.0 * Math::PI) / p) + 1.0
      when :elastic_in_out, :in_out_elastic
        return 0.0 if t == 0.0
        return 1.0 if t == 1.0
        p = 0.3 * 1.5
        s = p / 4.0
        t = t * 2.0 - 1.0
        if t < 0.0
          -0.5 * (2.0 ** (10.0 * t)) * Math.sin((t - s) * (2.0 * Math::PI) / p)
        else
          0.5 * (2.0 ** (-10.0 * t)) * Math.sin((t - s) * (2.0 * Math::PI) / p) + 1.0
        end

      # Bounce (ボールが跳ねるような挙動)
      when :bounce_out, :out_bounce
        calc_bounce_out(t)
      when :bounce_in, :in_bounce
        1.0 - calc_bounce_out(1.0 - t)
      when :bounce_in_out, :in_out_bounce
        if t < 0.5
          0.5 * (1.0 - calc_bounce_out(1.0 - t * 2.0))
        else
          0.5 * calc_bounce_out(t * 2.0 - 1.0) + 0.5
        end

      else
        # 未知のシンボルの場合はデフォルトで線形補間
        t
      end
    end

    def calc_bounce_out(t)
      if t < (1.0 / 2.75)
        7.5625 * t * t
      elsif t < (2.0 / 2.75)
        t -= (1.5 / 2.75)
        7.5625 * t * t + 0.75
      elsif t < (2.5 / 2.75)
        t -= (2.25 / 2.75)
        7.5625 * t * t + 0.9375
      else
        t -= (2.625 / 2.75)
        7.5625 * t * t + 0.984375
      end
    end
  end
end

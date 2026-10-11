# frozen_string_literal: true

module Zenoo
  # ====================================================
  # Zenoo::Physics - 即時モード 2D 剛体物理エンジン
  # ====================================================
  # ワールドや剛体クラスを保持せず、毎フレームの衝突情報 (Hit) と
  # 物性パラメータから、反映すべき移動・速度・回転の差分/新値を
  # ステートレスに計算する即時モード物理モジュール。
  module Physics
    DEG_TO_RAD = Math::PI / 180.0
    RAD_TO_DEG = 180.0 / Math::PI

    # ====================================================
    # 物理応答結果オブジェクト
    # ====================================================
    class Response
      attr_accessor :push_x, :push_y, :vx, :vy, :omega, :d_angle, :impact, :normal_impulse, :tangent_impulse, :hit

      def initialize(push_x: 0.0, push_y: 0.0, vx: 0.0, vy: 0.0, omega: 0.0, d_angle: 0.0, impact: 0.0, normal_impulse: 0.0, tangent_impulse: 0.0, hit: nil)
        @push_x = push_x.to_f
        @push_y = push_y.to_f
        @vx = vx.to_f
        @vy = vy.to_f
        @omega = omega.to_f
        @d_angle = d_angle.to_f
        @impact = impact.to_f
        @normal_impulse = normal_impulse.to_f
        @tangent_impulse = tangent_impulse.to_f
        @hit = hit
      end

      # 位置と速度・角速度・角度への反映ショートカット
      def apply_to(target)
        target.x += @push_x if target.respond_to?(:x=)
        target.y += @push_y if target.respond_to?(:y=)
        target.angle += @d_angle if @d_angle != 0.0 && target.respond_to?(:angle=)
        target.vx = @vx if target.respond_to?(:vx=)
        target.vy = @vy if target.respond_to?(:vy=)
        target.omega = @omega if target.respond_to?(:omega=)
        self
      end

      def inspect
        "#<Zenoo::Physics::Response push=[#{@push_x.round(3)}, #{@push_y.round(3)}] v=[#{@vx.round(2)}, #{@vy.round(2)}] omega=#{@omega.round(2)} d_angle=#{@d_angle.round(2)} impact=#{@impact.round(2)}>"
      end
    end

    # ====================================================
    # 慣性モーメント (Moment of Inertia) 計算ヘルパー
    # ====================================================

    # 矩形の慣性モーメント (質量中心まわり)
    # I = (1/12) * m * (w^2 + h^2)
    def self.inertia_rect(width, height, mass: 1.0)
      m = mass.to_f
      w = width.to_f
      h = height.to_f
      (1.0 / 12.0) * m * (w * w + h * h)
    end

    # 円の慣性モーメント
    # I = (1/2) * m * r^2
    def self.inertia_circle(radius, mass: 1.0)
      m = mass.to_f
      r = radius.to_f
      0.5 * m * (r * r)
    end

    # Shape または Sprite から慣性モーメントを自動推定
    def self.inertia_of(shape_or_sprite, mass: 1.0)
      target = shape_or_sprite
      target = target.collider if target.respond_to?(:collider) && target.collider

      case target
      when Collision::Rect
        w = target.width * target.scale_x.abs
        h = target.height * target.scale_y.abs
        inertia_rect(w, h, mass: mass)
      when Collision::Circle
        r = target.bounding_radius
        inertia_circle(r, mass: mass)
      when Collision::Polygon
        r = target.bounding_radius
        0.5 * mass.to_f * (r * r)
      else
        # デフォルトは 32x32 矩形近似
        inertia_rect(32.0, 32.0, mass: mass)
      end
    end

    # ====================================================
    # 即時物理応答計算 (動的オブジェクト vs 静的地形/壁)
    # ====================================================
    # @param hit [Zenoo::Collision::Hit] 衝突判定結果
    # @param x [Float] 動的オブジェクトの重心X座標
    # @param y [Float] 動的オブジェクトの重心Y座標
    # @param vx [Float] 現在のX速度 (px/frame)
    # @param vy [Float] 現在のY速度 (px/frame)
    # @param omega [Float] 現在の角速度 (deg/frame)
    # @param angle [Float, nil] 現在の角度 (deg, 省略時は shape から取得)
    # @param mass [Float] 質量 (kg)
    # @param inertia [Float, nil] 慣性モーメント (省略時は shape または 32x32矩形から自動推定)
    # @param shape [Object, nil] 形状 (Sprite や Collision::Shape)
    # @param static_shape [Object, nil] 静的障害物の形状 (オーバーハング・崖っぷち判定の高精度化)
    # @param restitution [Float] 反発係数 (0.0〜1.0)
    # @param friction [Float] 摩擦係数 (0.0〜1.0)
    # @param bounce_threshold [Float] 微小衝突時の反発カット閾値 (ジッター防止)
    # @return [Zenoo::Physics::Response] 反映すべき新値
    def self.resolve_static(
      hit,
      x:, y:,
      vx:, vy:,
      omega: 0.0,
      angle: nil,
      mass: 1.0,
      inertia: nil,
      shape: nil,
      static_shape: nil,
      restitution: 0.3,
      friction: 0.5,
      bounce_threshold: 0.5
    )
      return nil unless hit

      m = mass.to_f
      inv_m = m > 0.00001 ? 1.0 / m : 0.0

      # 慣性モーメントの決定
      inert = if inertia
                inertia.to_f
              elsif shape
                inertia_of(shape, mass: m)
              else
                inertia_rect(32.0, 32.0, mass: m)
              end
      inv_i = inert > 0.00001 ? 1.0 / inert : 0.0

      # 静的オブジェクトとの衝突なので、動的側が 100% 押し戻される
      push_x = hit.push_x
      push_y = hit.push_y

      # 法線 n (静的オブジェクト -> 動的オブジェクト の押し戻し方向)
      nx = hit.normal_x
      ny = hit.normal_y

      # 接線 t (法線を反時計回りに90度回転)
      tx = -ny
      ty = nx

      # 接触点 P の高精度決定:
      # 面接触 (エッジ接地) と オーバーハング (崖っぷち・角支点) の精密計算
      is_edge_contact = false
      is_overhang = false
      col_shape = shape.respond_to?(:collider) ? shape.collider : shape
      col_static = static_shape.respond_to?(:collider) ? static_shape.collider : static_shape

      # 1. 静的物体 (足場) のローカル座標系によるオーバーハング (はみ出し) 判定
      b_hw = 0.0
      b_hh = 0.0
      local_x = 0.0
      local_y = 0.0
      bcx = 0.0
      bcy = 0.0
      b_cos = 1.0
      b_sin = 0.0

      if col_static && col_static.respond_to?(:center_x) && col_static.respond_to?(:half_w)
        bcx = col_static.center_x
        bcy = col_static.center_y
        b_cos = col_static.respond_to?(:cos) ? col_static.cos : 1.0
        b_sin = col_static.respond_to?(:sin) ? col_static.sin : 0.0
        b_hw = col_static.respond_to?(:half_w) ? col_static.half_w : col_static.bounding_radius
        b_hh = col_static.respond_to?(:half_h) ? col_static.half_h : col_static.bounding_radius

        dx = x.to_f - bcx
        dy = y.to_f - bcy
        local_x = dx * b_cos + dy * b_sin
        local_y = -dx * b_sin + dy * b_cos

        # 足場の主軸横方向からのはみ出し
        is_overhang = local_x.abs > (b_hw + 0.5)
      end

      if col_shape && col_shape.respond_to?(:world_vertices) && col_shape.world_vertices
        verts_a = col_shape.world_vertices
        dir_x = -nx
        dir_y = -ny
        d_best1 = -1.0e30
        d_best2 = -1.0e30
        v_best1 = nil
        v_best2 = nil

        verts_a.each do |v|
          d = v[0] * dir_x + v[1] * dir_y
          if d > d_best1
            d_best2 = d_best1
            v_best2 = v_best1
            d_best1 = d
            v_best1 = v
          elsif d > d_best2
            d_best2 = d
            v_best2 = v
          end
        end

        is_parallel_face = v_best1 && v_best2 && (d_best1 - d_best2) < 2.5

        if is_overhang
          # オーバーハング (崖っぷち): 足場の境界の角が支点になり、自然に回転落下する！
          clamped_lx = local_x.clamp(-b_hw, b_hw)
          clamped_ly = local_y.clamp(-b_hh, b_hh)
          cx = bcx + clamped_lx * b_cos - clamped_ly * b_sin
          cy = bcy + clamped_lx * b_sin + clamped_ly * b_cos
          is_edge_contact = false
        elsif is_parallel_face
          # 足場の上に乗っていて面が平行: 底面の中点が接触点
          cx = (v_best1[0] + v_best2[0]) * 0.5
          cy = (v_best1[1] + v_best2[1]) * 0.5
          is_edge_contact = true
        elsif v_best1
          cx = v_best1[0]
          cy = v_best1[1]
        else
          cx = hit.contact_x
          cy = hit.contact_y
        end
      elsif col_shape && col_shape.respond_to?(:support)
        sp = col_shape.support(-nx, -ny)
        cx = sp[0]
        cy = sp[1]
      else
        cx = hit.contact_x
        cy = hit.contact_y
      end

      # 重心から接触点への相対ベクトル r
      rx = cx - x.to_f
      ry = cy - y.to_f

      # 角速度を rad/frame に変換
      w_rad = omega.to_f * DEG_TO_RAD

      # 接触点における動的物体の全速度 (並進 + 回転)
      # vp = v + omega x r = (vx - omega * ry, vy + omega * rx)
      vp_x = vx.to_f - w_rad * ry
      vp_y = vy.to_f + w_rad * rx

      # 法線方向の相対速度 vn (接近時は vn < 0)
      vn = vp_x * nx + vp_y * ny

      # 接線方向の相対速度 vt
      vt = vp_x * tx + vp_y * ty

      # 2D 外積 r x n, r x t (スカラー)
      rxn = rx * ny - ry * nx
      rxt = rx * ty - ry * tx

      # 有効質量の逆数 Kn, Kt
      kn = inv_m + (rxn * rxn) * inv_i
      kt = inv_m + (rxt * rxt) * inv_i

      jn = 0.0
      jt = 0.0

      # 静止接触 (Resting Contact) 判定
      is_resting = -vn < bounce_threshold

      # 法線インパルス計算 (接触点において地面へ向かって近づいている場合のみ)
      if vn < 0.0 && kn > 0.000001
        e = is_resting ? 0.0 : restitution.to_f
        jn = -(1.0 + e) * vn / kn
        jn = 0.0 if jn < 0.0
      end

      # 接線インパルス計算 (クーロン摩擦)
      if kt > 0.000001 && jn > 0.0
        # 接触点の接線速度をゼロにしようとする力積
        jt_ideal = -vt / kt
        max_jt = friction.to_f * jn
        if jt_ideal > max_jt
          jt = max_jt
        elsif jt_ideal < -max_jt
          jt = -max_jt
        else
          jt = jt_ideal
        end
      end

      # 合計インパルス J = jn * n + jt * t
      total_jx = jn * nx + jt * tx
      total_jy = jn * ny + jt * ty

      # 並進速度の更新
      new_vx = vx.to_f + inv_m * total_jx
      new_vy = vy.to_f + inv_m * total_jy

      # トルクインパルス tau = r x J
      tau = rx * total_jy - ry * total_jx

      # 面接触 (エッジ接地) の場合は左右シーソー振動を防ぐためトルクを抑制し角速度を減衰
      # ※オーバーハング (はみ出し) 中は 100% のトルクを活かしてダイナミックに回転させる！
      if is_edge_contact && !is_overhang
        tau *= 0.1
        omega_damped = omega.to_f * 0.4
      else
        omega_damped = omega.to_f
      end

      # 角速度の更新 (rad/frame -> deg/frame)
      delta_w_rad = inv_i * tau
      new_omega = omega_damped + delta_w_rad * RAD_TO_DEG
      d_angle = 0.0

      # 静止接触時の安定化 (ジッター・ブルブル振動の防止 ＆ 地面平行アライメント)
      # ※安定した面接地中 (オーバーハングしていない時) のみ適用
      if is_resting && is_edge_contact && !is_overhang
        # 法線方向の微小跳ね上がりをカット (床への密着)
        v_norm = new_vx * nx + new_vy * ny
        if v_norm > 0.0
          new_vx -= v_norm * nx
          new_vy -= v_norm * ny
        end

        # 面を地面と完全に平行にするアライメント
        ground_angle = Math.atan2(nx, -ny) * RAD_TO_DEG
        cur_ang = angle ? angle.to_f : (col_shape && col_shape.respond_to?(:angle) ? col_shape.angle.to_f : 0.0)

        diff = (cur_ang - ground_angle) % 90.0
        diff -= 90.0 if diff > 45.0
        diff += 90.0 if diff < -45.0

        if diff.abs < 15.0
          align_omega = -diff * 0.4
          new_omega = align_omega

          # わずかな傾き (1.2度未満) は完全に平行へスナップ
          if diff.abs < 1.2
            d_angle = -diff
            new_omega = 0.0
          end
        end

        # 微小速度・角速度のデッドゾーン
        if new_vx.abs < 0.15 && new_vy.abs < 0.15
          new_vx = 0.0
          new_vy = 0.0
        end
        if new_omega.abs < 0.5
          new_omega = 0.0
        end
      end

      # 衝撃の大きさ (効果音・パーティクル用)
      impact = -vn > 0.0 ? -vn : 0.0

      Response.new(
        push_x: push_x,
        push_y: push_y,
        vx: new_vx,
        vy: new_vy,
        omega: new_omega,
        d_angle: d_angle,
        impact: impact,
        normal_impulse: jn,
        tangent_impulse: jt,
        hit: hit
      )
    end
  end
end

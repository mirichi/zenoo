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
    # 2体衝突物理応答結果オブジェクト
    # ====================================================
    class PairResponse
      attr_accessor :a, :b, :impact, :hit

      def initialize(a, b, impact: 0.0, hit: nil)
        @a = a
        @b = b
        @impact = impact.to_f
        @hit = hit
      end

      # 2つのターゲットに一括反映
      def apply_to(target_a, target_b)
        @a.apply_to(target_a)
        @b.apply_to(target_b)
        self
      end

      def inspect
        "#<Zenoo::Physics::PairResponse impact=#{@impact.round(2)}\n  a: #{@a.inspect}\n  b: #{@b.inspect}>"
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

      res = case target
            when Collision::Rect
              w = target.width * target.scale_x.abs
              h = target.height * target.scale_y.abs
              (w > 0.001 && h > 0.001) ? inertia_rect(w, h, mass: mass) : inertia_rect(32.0, 32.0, mass: mass)
            when Collision::Circle
              r = target.bounding_radius
              r > 0.001 ? inertia_circle(r, mass: mass) : inertia_circle(16.0, mass: mass)
            when Collision::Polygon
              r = target.bounding_radius
              r > 0.001 ? 0.5 * mass.to_f * (r * r) : inertia_rect(32.0, 32.0, mass: mass)
            else
              # デフォルトは 32x32 矩形近似
              inertia_rect(32.0, 32.0, mass: mass)
            end
      res > 0.0001 ? res : inertia_rect(32.0, 32.0, mass: mass)
    end

    # ====================================================
    # 即時物理応答計算 (動的オブジェクト vs 静的地形/壁)
    # ====================================================
    # @param hit [Zenoo::Collision::Hit] 衝突判定結果
    # @param a [PhysicsSprite, Sprite, Hash, Object] 動的オブジェクト
    # @param b [Sprite, Collision::Shape, Hash, Object, nil] 静的障害物オブジェクト
    # @param restitution [Float, nil] 反発係数 (省略時は a のプロパティまたは 0.3)
    # @param friction [Float, nil] 摩擦係数 (省略時は a のプロパティまたは 0.5)
    # @param bounce_threshold [Float] 微小衝突時の反発カット閾値 (ジッター防止)
    # @return [Zenoo::Physics::Response] 反映すべき新値
    def self.resolve_static(
      hit,
      a = nil,
      b = nil,
      restitution: nil,
      friction: nil,
      bounce_threshold: 0.5,
      **kwargs
    )
      return nil unless hit

      target_a = a || kwargs[:a] || kwargs[:body]
      target_a ||= kwargs if kwargs[:x] || kwargs[:vx]
      target_b = b || kwargs[:b] || kwargs[:static_body] || kwargs[:static_shape]
      return nil unless target_a

      x, y, vx, vy, omega, angle, mass, shape, inertia = extract_body_params(target_a)
      restitution = restitution ? restitution.to_f : (target_a.respond_to?(:restitution) ? target_a.restitution.to_f : 0.3)
      friction = friction ? friction.to_f : (target_a.respond_to?(:friction) ? target_a.friction.to_f : 0.5)

      static_shape = target_b ? (target_b.respond_to?(:collider) ? target_b.collider : target_b) : nil

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

    # ====================================================
    # 2体衝突即時物理応答計算 (動的オブジェクト vs 動的オブジェクト)
    # ====================================================
    # @param hit [Zenoo::Collision::Hit] 衝突判定結果
    # @param a [Hash, Object] 物体Aのパラメータまたはオブジェクト ({ x:, y:, vx:, vy:, omega:, mass:, shape:, ... })
    # @param b [Hash, Object] 物体Bのパラメータまたはオブジェクト
    # @param restitution [Float] 反発係数 (0.0〜1.0)
    # @param friction [Float] 摩擦係数 (0.0〜1.0)
    # @param bounce_threshold [Float] 微小衝突時の反発カット閾値
    # @return [Zenoo::Physics::PairResponse] 物体Aと物体Bそれぞれの反映新値を含む結果
    def self.resolve(
      hit,
      a = nil,
      b = nil,
      restitution: nil,
      friction: nil,
      bounce_threshold: 0.5,
      **kwargs
    )
      return nil unless hit

      target_a = a || kwargs[:a]
      target_b = b || kwargs[:b]
      return nil unless target_a && target_b

      xa, ya, vax, vay, wa, anga, ma, shape_a, ia = extract_body_params(target_a)
      xb, yb, vbx, vby, wb, angb, mb, shape_b, ib = extract_body_params(target_b)

      rest_a = target_a.respond_to?(:restitution) ? target_a.restitution.to_f : nil
      rest_b = target_b.respond_to?(:restitution) ? target_b.restitution.to_f : nil
      restitution = restitution ? restitution.to_f : ((rest_a && rest_b) ? [rest_a, rest_b].max : (rest_a || rest_b || 0.5))

      fric_a = target_a.respond_to?(:friction) ? target_a.friction.to_f : nil
      fric_b = target_b.respond_to?(:friction) ? target_b.friction.to_f : nil
      friction = friction ? friction.to_f : ((fric_a && fric_b) ? Math.sqrt(fric_a * fric_b) : (fric_a || fric_b || 0.4))

      inv_ma = ma > 0.00001 ? 1.0 / ma : 0.0
      inv_mb = mb > 0.00001 ? 1.0 / mb : 0.0
      inv_m_total = inv_ma + inv_mb
      return nil if inv_m_total <= 0.000001

      inert_a = ia ? ia.to_f : (shape_a ? inertia_of(shape_a, mass: ma) : inertia_rect(32.0, 32.0, mass: ma))
      inert_b = ib ? ib.to_f : (shape_b ? inertia_of(shape_b, mass: mb) : inertia_rect(32.0, 32.0, mass: mb))
      inv_ia = inert_a > 0.00001 ? 1.0 / inert_a : 0.0
      inv_ib = inert_b > 0.00001 ? 1.0 / inert_b : 0.0

      # めり込み押し戻し (逆質量比で配分)
      ratio_a = inv_ma / inv_m_total
      ratio_b = inv_mb / inv_m_total

      push_ax = hit.push_x * ratio_a
      push_ay = hit.push_y * ratio_a
      push_bx = -hit.push_x * ratio_b
      push_by = -hit.push_y * ratio_b

      # 法線 n (B -> A 向き), 接線 t
      nx = hit.normal_x
      ny = hit.normal_y
      tx = -ny
      ty = nx

      # 接触点 P
      col_a = shape_a.respond_to?(:collider) ? shape_a.collider : shape_a
      col_b = shape_b.respond_to?(:collider) ? shape_b.collider : shape_b

      if col_a && col_a.respond_to?(:support) && col_b && col_b.respond_to?(:support)
        sp_a = col_a.support(-nx, -ny)
        sp_b = col_b.support(nx, ny)
        cx = (sp_a[0] + sp_b[0]) * 0.5
        cy = (sp_a[1] + sp_b[1]) * 0.5
      else
        cx = hit.contact_x
        cy = hit.contact_y
      end

      # トルクアーム rA, rB
      rax = cx - xa
      ray = cy - ya
      rbx = cx - xb
      rby = cy - yb

      w_rad_a = wa * DEG_TO_RAD
      w_rad_b = wb * DEG_TO_RAD

      vpa_x = vax - w_rad_a * ray
      vpa_y = vay + w_rad_a * rax

      vpb_x = vbx - w_rad_b * rby
      vpb_y = vby + w_rad_b * rbx

      v_rel_x = vpa_x - vpb_x
      v_rel_y = vpa_y - vpb_y

      vn = v_rel_x * nx + v_rel_y * ny
      vt = v_rel_x * tx + v_rel_y * ty

      ran = rax * ny - ray * nx
      rat = rax * ty - ray * tx
      rbn = rbx * ny - rby * nx
      rbt = rbx * ty - rby * tx

      kn = inv_m_total + (ran * ran) * inv_ia + (rbn * rbn) * inv_ib
      kt = inv_m_total + (rat * rat) * inv_ia + (rbt * rbt) * inv_ib

      jn = 0.0
      jt = 0.0

      if vn < 0.0 && kn > 0.000001
        e = (-vn < bounce_threshold) ? 0.0 : restitution.to_f
        jn = -(1.0 + e) * vn / kn
        jn = 0.0 if jn < 0.0
      end

      if kt > 0.000001 && jn > 0.0
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

      total_jx = jn * nx + jt * tx
      total_jy = jn * ny + jt * ty

      # 物体Aの更新 (+J)
      new_vax = vax + inv_ma * total_jx
      new_vay = vay + inv_ma * total_jy
      tau_a = rax * total_jy - ray * total_jx
      delta_wa_rad = inv_ia * tau_a
      new_wa = wa + delta_wa_rad * RAD_TO_DEG

      # 物体Bの更新 (-J)
      new_vbx = vbx - inv_mb * total_jx
      new_vby = vby - inv_mb * total_jy
      tau_b = -(rbx * total_jy - rby * total_jx)
      delta_wb_rad = inv_ib * tau_b
      new_wb = wb + delta_wb_rad * RAD_TO_DEG

      # 静止接触 (Resting contact) 安定化 ＆ 転がり抵抗ダンピング
      if -vn < bounce_threshold
        # 相対速度の法線成分 (跳ね離脱) をカット
        v_rel_n = (new_vax - new_vbx) * nx + (new_vay - new_vby) * ny
        if v_rel_n > 0.0
          new_vax -= v_rel_n * nx * ratio_a
          new_vay -= v_rel_n * ny * ratio_a
          new_vbx += v_rel_n * nx * ratio_b
          new_vby += v_rel_n * ny * ratio_b
        end

        # 転がり抵抗ダンピング (円やディスクが接地・乗っかり中に永久回転するのを防止)
        new_wa *= 0.85
        new_wb *= 0.85

        # 微小角速度のデッドゾーン
        new_wa = 0.0 if new_wa.abs < 0.4
        new_wb = 0.0 if new_wb.abs < 0.4

        # 微小相対速度のデッドゾーン
        rel_vx = new_vax - new_vbx
        rel_vy = new_vay - new_vby
        if rel_vx.abs < 0.12 && rel_vy.abs < 0.12
          common_vx = (new_vax + new_vbx) * 0.5
          common_vy = (new_vay + new_vby) * 0.5
          new_vax = common_vx
          new_vay = common_vy
          new_vbx = common_vx
          new_vby = common_vy
        end
      end

      impact = -vn > 0.0 ? -vn : 0.0

      res_a = Response.new(
        push_x: push_ax,
        push_y: push_ay,
        vx: new_vax,
        vy: new_vay,
        omega: new_wa,
        impact: impact,
        normal_impulse: jn,
        tangent_impulse: jt,
        hit: hit
      )

      res_b = Response.new(
        push_x: push_bx,
        push_y: push_by,
        vx: new_vbx,
        vy: new_vby,
        omega: new_wb,
        impact: impact,
        normal_impulse: jn,
        tangent_impulse: jt,
        hit: hit
      )

      PairResponse.new(res_a, res_b, impact: impact, hit: hit)
    end

    # 物体パラメータの共通抽出ヘルパー (Hash または Object)
    def self.extract_body_params(body)
      if body.is_a?(Hash)
        x = body[:x].to_f
        y = body[:y].to_f
        vx = body[:vx].to_f
        vy = body[:vy].to_f
        omega = (body[:omega] || 0.0).to_f
        angle = (body[:angle] || 0.0).to_f
        mass = (body[:mass] || 1.0).to_f
        shape = body[:shape]
        inertia = body[:inertia]
      else
        x = body.respond_to?(:x) ? body.x.to_f : 0.0
        y = body.respond_to?(:y) ? body.y.to_f : 0.0
        vx = body.respond_to?(:vx) ? body.vx.to_f : 0.0
        vy = body.respond_to?(:vy) ? body.vy.to_f : 0.0
        omega = body.respond_to?(:omega) ? body.omega.to_f : 0.0
        angle = body.respond_to?(:angle) ? body.angle.to_f : 0.0
        mass = body.respond_to?(:mass) ? body.mass.to_f : 1.0
        shape = body.respond_to?(:shape) ? body.shape : (body.respond_to?(:collider) ? body.collider : nil)
        inertia = body.respond_to?(:inertia) ? body.inertia : nil
      end
      [x, y, vx, vy, omega, angle, mass, shape, inertia]
    end

    # ====================================================
    # 座標変換ヘルパー
    # ====================================================

    # 物体のローカル座標 [lx, ly] を現在のワールド座標 [wx, wy] に変換
    def self.local_to_world(body, lx, ly)
      x, y, _vx, _vy, _w, angle = extract_body_params(body)
      rad = angle * DEG_TO_RAD
      c = Math.cos(rad)
      s = Math.sin(rad)
      [x + lx.to_f * c - ly.to_f * s, y + lx.to_f * s + ly.to_f * c]
    end

    # ワールド座標 [wx, wy] を物体の現在のローカル座標 [lx, ly] に変換
    def self.world_to_local(body, wx, wy)
      x, y, _vx, _vy, _w, angle = extract_body_params(body)
      rad = angle * DEG_TO_RAD
      c = Math.cos(rad)
      s = Math.sin(rad)
      dx = wx.to_f - x
      dy = wy.to_f - y
      [dx * c + dy * s, -dx * s + dy * c]
    end

    # 物体 A から見た物体 B の相対オフセット [ox, oy] と相対角度 rel_angle (deg) を計算
    def self.relative_offset(body_a, body_b)
      bx = body_b.respond_to?(:x) ? body_b.x.to_f : 0.0
      by = body_b.respond_to?(:y) ? body_b.y.to_f : 0.0
      ba = body_b.respond_to?(:angle) ? body_b.angle.to_f : 0.0
      aa = body_a.respond_to?(:angle) ? body_a.angle.to_f : 0.0
      lx, ly = world_to_local(body_a, bx, by)
      diff_ang = (ba - aa) % 360.0
      diff_ang -= 360.0 if diff_ang > 180.0
      diff_ang += 360.0 if diff_ang < -180.0
      [[lx, ly], diff_ang]
    end

    # ====================================================
    # 即時モード 拘束 (Constraints / Joints)
    # ====================================================

    # 1. 目標点 / マウスへの引っ張り拘束 (スプリング・トルクドラッグ)
    # @param body [PhysicsSprite, Object] 対象物体
    # @param tx [Float] 目標ワールドX座標 (マウスXなど)
    # @param ty [Float] 目標ワールドY座標 (マウスYなど)
    # @param anchor [Array<Float>, nil] 物体上のローカル接続点 [lx, ly] (省略時は重心 [0, 0])
    # @param stiffness [Float] 引っ張りの強さ (0.0〜1.0, デフォルト 0.3)
    # @param damping [Float] 速度減衰 (0.0〜1.0, デフォルト 0.85)
    def self.constrain_point(body, tx, ty, anchor: nil, stiffness: 0.3, damping: 0.85)
      return nil unless body

      x, y, vx, vy, omega, angle, mass, shape, inertia = extract_body_params(body)
      m = mass.to_f
      return nil if m <= 0.00001

      inert = inertia ? inertia.to_f : (shape ? inertia_of(shape, mass: m) : inertia_rect(32.0, 32.0, mass: m))
      inv_m = 1.0 / m
      inv_i = inert > 0.00001 ? 1.0 / inert : 0.0

      # アンカー点の現在ワールド座標
      rad = angle * DEG_TO_RAD
      c = Math.cos(rad)
      s = Math.sin(rad)
      lx = anchor ? anchor[0].to_f : 0.0
      ly = anchor ? anchor[1].to_f : 0.0

      rx = lx * c - ly * s
      ry = lx * s + ly * c
      px = x + rx
      py = y + ry

      # 目標点とのズレ
      dx = tx.to_f - px
      dy = ty.to_f - py

      k_stiff = stiffness.to_f.clamp(0.01, 1.0)
      k_damp = damping.to_f.clamp(0.0, 1.0)

      # 位置の直接引き寄せ (PBD)
      push_x = dx * k_stiff
      push_y = dy * k_stiff

      # トルクによる回転
      tau_pos = rx * push_y - ry * push_x
      d_angle = (tau_pos * inv_i * RAD_TO_DEG) * 0.5

      body.x += push_x if body.respond_to?(:x=)
      body.y += push_y if body.respond_to?(:y=)
      body.angle += d_angle if body.respond_to?(:angle=)

      # 速度の更新 (追従インパルス + 減衰)
      body.vx = (vx * k_damp) + (push_x * 0.5) if body.respond_to?(:vx=)
      body.vy = (vy * k_damp) + (push_y * 0.5) if body.respond_to?(:vy=)
      body.omega = (omega * k_damp) + (d_angle * 0.5) if body.respond_to?(:omega=)

      true
    end

    def self.constrain_mouse(body, mx, my, **kwargs)
      constrain_point(body, mx, my, **kwargs)
    end

    # 2. ピン結合・回転ジョイント (Revolute / Pin Joint)
    # @param a [PhysicsSprite, Object] 物体A
    # @param b [PhysicsSprite, Object, Array, nil] 物体B (nilまたは座標[x, y]の場合は空間の固定点)
    # @param pivot [Array<Float>, nil] ワールド結合点座標 [px, py]
    # @param anchor_a [Array<Float>, nil] 物体Aのローカル結合点 [lx, ly]
    # @param anchor_b [Array<Float>, nil] 物体Bのローカル結合点 [lx, ly]
    def self.constrain_pin(a, b = nil, pivot: nil, anchor_a: nil, anchor_b: nil)
      return nil unless a

      xa, ya, vax, vay, wa, anga, ma, shape_a, ia = extract_body_params(a)
      rad_a = anga * DEG_TO_RAD
      ca = Math.cos(rad_a)
      sa = Math.sin(rad_a)

      # anchor_a の決定: 指定があればそれ、無ければ重心 [0, 0]
      lax = anchor_a ? anchor_a[0].to_f : 0.0
      lay = anchor_a ? anchor_a[1].to_f : 0.0

      rax = lax * ca - lay * sa
      ray = lax * sa + lay * ca
      pax = xa + rax
      pay = ya + ray

      is_fixed = b.nil? || b.is_a?(Array)
      if is_fixed
        pbx = b.is_a?(Array) ? b[0].to_f : (pivot ? pivot[0].to_f : pax)
        pby = b.is_a?(Array) ? b[1].to_f : (pivot ? pivot[1].to_f : pay)
        vbx = 0.0
        vby = 0.0
        wb = 0.0
        rbx = 0.0
        rby = 0.0
        inv_mb = 0.0
        inv_ib = 0.0
      else
        xb, yb, vbx, vby, wb, angb, mb, shape_b, ib = extract_body_params(b)
        rad_b = angb * DEG_TO_RAD
        cb = Math.cos(rad_b)
        sb = Math.sin(rad_b)

        lbx = anchor_b ? anchor_b[0].to_f : 0.0
        lby = anchor_b ? anchor_b[1].to_f : 0.0

        rbx = lbx * cb - lby * sb
        rby = lbx * sb + lby * cb
        pbx = xb + rbx
        pby = yb + rby

        mb_f = mb.to_f
        inv_mb = mb_f > 0.00001 ? 1.0 / mb_f : 0.0
        inert_b = ib ? ib.to_f : (shape_b ? inertia_of(shape_b, mass: mb_f) : inertia_rect(32.0, 32.0, mass: mb_f))
        inv_ib = inert_b > 0.00001 ? 1.0 / inert_b : 0.0
      end

      ma_f = ma.to_f
      inv_ma = ma_f > 0.00001 ? 1.0 / ma_f : 0.0
      inert_a = ia ? ia.to_f : (shape_a ? inertia_of(shape_a, mass: ma_f) : inertia_rect(32.0, 32.0, mass: ma_f))
      inv_ia = inert_a > 0.00001 ? 1.0 / inert_a : 0.0

      inv_m_total = inv_ma + inv_mb
      return nil if inv_m_total <= 0.000001

      # 1. 位置ズレ (Position Drift) の直接補正
      # ピン結合は角度を拘束しないため、アンカー点同士が一致するように平行移動するだけで厳密に一致する
      dpx = pbx - pax
      dpy = pby - pay

      if is_fixed
        a.x += dpx if a.respond_to?(:x=)
        a.y += dpy if a.respond_to?(:y=)
      else
        ratio_a = inv_ma / inv_m_total
        ratio_b = inv_mb / inv_m_total
        a.x += dpx * ratio_a if a.respond_to?(:x=)
        a.y += dpy * ratio_a if a.respond_to?(:y=)
        b.x -= dpx * ratio_b if b.respond_to?(:x=)
        b.y -= dpy * ratio_b if b.respond_to?(:y=)
      end

      # 2. 速度ズレ (Velocity Constraint) の力積解決
      if is_fixed && lax.abs < 0.0001 && lay.abs < 0.0001
        # 中心固定ピン: 線速度は完全にゼロ、角速度のみ自由
        a.vx = 0.0 if a.respond_to?(:vx=)
        a.vy = 0.0 if a.respond_to?(:vy=)
      else
        cur_anga = a.respond_to?(:angle) ? a.angle.to_f : anga
        rad_a = cur_anga * DEG_TO_RAD
        ca = Math.cos(rad_a)
        sa = Math.sin(rad_a)
        rax = lax * ca - lay * sa
        ray = lax * sa + lay * ca

        vax = a.respond_to?(:vx) ? a.vx.to_f : 0.0
        vay = a.respond_to?(:vy) ? a.vy.to_f : 0.0
        wa = a.respond_to?(:omega) ? a.omega.to_f : 0.0

        if is_fixed
          vbx = 0.0
          vby = 0.0
          wb = 0.0
          rbx = 0.0
          rby = 0.0
        else
          cur_angb = b.respond_to?(:angle) ? b.angle.to_f : angb
          rad_b = cur_angb * DEG_TO_RAD
          cb = Math.cos(rad_b)
          sb = Math.sin(rad_b)
          rbx = lbx * cb - lby * sb
          rby = lbx * sb + lby * cb
          vbx = b.respond_to?(:vx) ? b.vx.to_f : 0.0
          vby = b.respond_to?(:vy) ? b.vy.to_f : 0.0
          wb = b.respond_to?(:omega) ? b.omega.to_f : 0.0
        end

        w_rad_a = wa * DEG_TO_RAD
        w_rad_b = wb * DEG_TO_RAD
        vpa_x = vax - w_rad_a * ray
        vpa_y = vay + w_rad_a * rax
        vpb_x = vbx - w_rad_b * rby
        vpb_y = vby + w_rad_b * rbx

        rel_vx = vpa_x - vpb_x
        rel_vy = vpa_y - vpb_y

        k11 = inv_m_total + (ray * ray) * inv_ia + (rby * rby) * inv_ib
        k22 = inv_m_total + (rax * rax) * inv_ia + (rbx * rbx) * inv_ib
        k12 = -(rax * ray) * inv_ia - (rbx * rby) * inv_ib
        det = k11 * k22 - k12 * k12

        if det.abs > 0.000001
          inv_det = 1.0 / det
          jx_vel = -(k22 * rel_vx - k12 * rel_vy) * inv_det
          jy_vel = -(-k12 * rel_vx + k11 * rel_vy) * inv_det

          a.vx = vax + inv_ma * jx_vel if a.respond_to?(:vx=)
          a.vy = vay + inv_ma * jy_vel if a.respond_to?(:vy=)
          tau_a_vel = rax * jy_vel - ray * jx_vel
          a.omega = wa + (tau_a_vel * inv_ia * RAD_TO_DEG) if a.respond_to?(:omega=)

          unless is_fixed
            b.vx = vbx - inv_mb * jx_vel if b.respond_to?(:vx=)
            b.vy = vby - inv_mb * jy_vel if b.respond_to?(:vy=)
            tau_b_vel = -(rbx * jy_vel - rby * jx_vel)
            b.omega = wb + (tau_b_vel * inv_ib * RAD_TO_DEG) if b.respond_to?(:omega=)
          end
        end
      end

      true
    end

    # 3. 完全固定・溶接ジョイント (Weld / Fixed Constraint)
    # 物体 A から見た物体 B の目標相対位置 (offset) と相対角度 (angle) を維持して一体化
    # @param a [PhysicsSprite, Object] 基準物体A
    # @param b [PhysicsSprite, Object] 結合物体B
    # @param offset [Array<Float>] Aから見たBの目標ローカル位置 [ox, oy] (省略時は現在の相対位置)
    # @param angle [Float, nil] Aから見たBの目標相対角度 (deg, 省略時は現在の角度差または0.0)
    # @param stiffness [Float] 結合の硬さ (0.0〜1.0, デフォルト 1.0 = 完全固定)
    def self.constrain_weld(a, b, offset: nil, angle: nil, stiffness: 1.0)
      return nil unless a && b

      if offset.nil?
        offset, auto_ang = relative_offset(a, b)
        angle ||= auto_ang
      elsif offset.is_a?(Array) && offset.length >= 3 && angle.nil?
        angle = offset[2].to_f
      end

      xa, ya, vax, vay, wa, anga, ma, shape_a, ia = extract_body_params(a)
      xb, yb, vbx, vby, wb, angb, mb, shape_b, ib = extract_body_params(b)

      ma_f = ma.to_f
      mb_f = mb.to_f
      inv_ma = ma_f > 0.00001 ? 1.0 / ma_f : 0.0
      inv_mb = mb_f > 0.00001 ? 1.0 / mb_f : 0.0
      inv_m_total = inv_ma + inv_mb
      return nil if inv_m_total <= 0.000001

      inert_a = ia ? ia.to_f : (shape_a ? inertia_of(shape_a, mass: ma_f) : inertia_rect(32.0, 32.0, mass: ma_f))
      inert_b = ib ? ib.to_f : (shape_b ? inertia_of(shape_b, mass: mb_f) : inertia_rect(32.0, 32.0, mass: mb_f))
      inv_ia = inert_a > 0.00001 ? 1.0 / inert_a : 0.0
      inv_ib = inert_b > 0.00001 ? 1.0 / inert_b : 0.0
      inv_i_total = inv_ia + inv_ib

      k_stiff = stiffness.to_f.clamp(0.01, 1.0)

      # 1. 角度の固定
      target_rel_ang = angle ? angle.to_f : 0.0
      target_ang_b = anga + target_rel_ang
      diff_ang = (target_ang_b - angb) % 360.0
      diff_ang -= 360.0 if diff_ang > 180.0
      diff_ang += 360.0 if diff_ang < -180.0

      if diff_ang.abs > 0.001 && inv_i_total > 0.000001
        ratio_ang_a = (inv_ia / inv_i_total) * k_stiff
        ratio_ang_b = (inv_ib / inv_i_total) * k_stiff
        a.angle -= diff_ang * ratio_ang_a if a.respond_to?(:angle=)
        b.angle += diff_ang * ratio_ang_b if b.respond_to?(:angle=)
      end

      # 2. 相対位置の固定
      cur_anga = a.respond_to?(:angle) ? a.angle.to_f : anga
      rad_a = cur_anga * DEG_TO_RAD
      ca = Math.cos(rad_a)
      sa = Math.sin(rad_a)

      ox = offset ? offset[0].to_f : 0.0
      oy = offset ? offset[1].to_f : 0.0
      target_xb = a.x + (ox * ca - oy * sa)
      target_yb = a.y + (ox * sa + oy * ca)

      dx = target_xb - b.x
      dy = target_yb - b.y

      ratio_pos_a = (inv_ma / inv_m_total) * k_stiff
      ratio_pos_b = (inv_mb / inv_m_total) * k_stiff

      b.x += dx * ratio_pos_b if b.respond_to?(:x=)
      b.y += dy * ratio_pos_b if b.respond_to?(:y=)
      a.x -= dx * ratio_pos_a if a.respond_to?(:x=)
      a.y -= dy * ratio_pos_a if a.respond_to?(:y=)

      # 3. 速度・角速度の同期 (一体剛体運動)
      total_mass = ma_f + mb_f
      com_x = (ma_f * a.x + mb_f * b.x) / total_mass
      com_y = (ma_f * a.y + mb_f * b.y) / total_mass

      com_vx = (ma_f * vax + mb_f * vbx) / total_mass
      com_vy = (ma_f * vay + mb_f * vby) / total_mass

      ra_cx = a.x - com_x
      ra_cy = a.y - com_y
      rb_cx = b.x - com_x
      rb_cy = b.y - com_y

      total_inertia = inert_a + inert_b + ma_f * (ra_cx * ra_cx + ra_cy * ra_cy) + mb_f * (rb_cx * rb_cx + rb_cy * rb_cy)
      if total_inertia > 0.00001
        l_ang = (inert_a * wa + inert_b * wb) * DEG_TO_RAD
        l_linear = (ra_cx * (ma_f * (vay - com_vy)) - ra_cy * (ma_f * (vax - com_vx))) +
                   (rb_cx * (mb_f * (vby - com_vy)) - rb_cy * (mb_f * (vbx - com_vx)))
        common_w_rad = (l_ang + l_linear) / total_inertia
        common_w = common_w_rad * RAD_TO_DEG

        a.omega = wa + (common_w - wa) * k_stiff if a.respond_to?(:omega=)
        b.omega = wb + (common_w - wb) * k_stiff if b.respond_to?(:omega=)

        a.vx = com_vx - (common_w_rad * ra_cy) if a.respond_to?(:vx=)
        a.vy = com_vy + (common_w_rad * ra_cx) if a.respond_to?(:vy=)
        b.vx = com_vx - (common_w_rad * rb_cy) if b.respond_to?(:vx=)
        b.vy = com_vy + (common_w_rad * rb_cx) if b.respond_to?(:vy=)
      end

      true
    end

    # 4. 距離拘束・ロッド・ロープ (Distance / Rod / Rope Joint)
    # @param a [PhysicsSprite, Object] 物体A
    # @param b [PhysicsSprite, Object] 物体B
    # @param length [Float, nil] 目標距離 (nil の場合は min/max、または現在の距離)
    # @param min [Float, nil] 最小距離 (伸縮ロッド)
    # @param max [Float, nil] 最大距離 (ロープ・糸)
    # @param anchor_a [Array<Float>, nil] 物体Aのローカル接続点
    # @param anchor_b [Array<Float>, nil] 物体Bのローカル接続点
    def self.constrain_distance(a, b, length: nil, min: nil, max: nil, anchor_a: nil, anchor_b: nil)
      return nil unless a && b

      xa, ya, vax, vay, wa, anga, ma, shape_a, ia = extract_body_params(a)
      xb, yb, vbx, vby, wb, angb, mb, shape_b, ib = extract_body_params(b)

      pax, pay = local_to_world(a, anchor_a ? anchor_a[0].to_f : 0.0, anchor_a ? anchor_a[1].to_f : 0.0)
      pbx, pby = local_to_world(b, anchor_b ? anchor_b[0].to_f : 0.0, anchor_b ? anchor_b[1].to_f : 0.0)

      dx = pbx - pax
      dy = pby - pay
      dist = Math.sqrt(dx * dx + dy * dy)
      return nil if dist <= 0.000001

      nx = dx / dist
      ny = dy / dist

      target_len = length ? length.to_f : dist
      target_min = min ? min.to_f : target_len
      target_max = max ? max.to_f : target_len

      diff = 0.0
      if dist < target_min
        diff = dist - target_min
      elsif dist > target_max
        diff = dist - target_max
      else
        return true
      end

      ma_f = ma.to_f
      mb_f = mb.to_f
      inv_ma = ma_f > 0.00001 ? 1.0 / ma_f : 0.0
      inv_mb = mb_f > 0.00001 ? 1.0 / mb_f : 0.0
      inv_m_total = inv_ma + inv_mb
      return nil if inv_m_total <= 0.000001

      inert_a = ia ? ia.to_f : (shape_a ? inertia_of(shape_a, mass: ma_f) : inertia_rect(32.0, 32.0, mass: ma_f))
      inert_b = ib ? ib.to_f : (shape_b ? inertia_of(shape_b, mass: mb_f) : inertia_rect(32.0, 32.0, mass: mb_f))
      inv_ia = inert_a > 0.00001 ? 1.0 / inert_a : 0.0
      inv_ib = inert_b > 0.00001 ? 1.0 / inert_b : 0.0

      rax = pax - xa
      ray = pay - ya
      rbx = pbx - xb
      rby = pby - yb

      ran = rax * ny - ray * nx
      rbn = rbx * ny - rby * nx
      k = inv_m_total + (ran * ran) * inv_ia + (rbn * rbn) * inv_ib
      return nil if k <= 0.000001

      # 位置補正
      j_pos = diff / k
      px_imp = j_pos * nx
      py_imp = j_pos * ny

      a.x += inv_ma * px_imp if a.respond_to?(:x=)
      a.y += inv_ma * py_imp if a.respond_to?(:y=)
      a.angle += ((rax * py_imp - ray * px_imp) * inv_ia * RAD_TO_DEG) if a.respond_to?(:angle=)

      b.x -= inv_mb * px_imp if b.respond_to?(:x=)
      b.y -= inv_mb * py_imp if b.respond_to?(:y=)
      b.angle -= ((rbx * py_imp - rby * px_imp) * inv_ib * RAD_TO_DEG) if b.respond_to?(:angle=)

      # 速度補正
      w_rad_a = wa * DEG_TO_RAD
      w_rad_b = wb * DEG_TO_RAD
      vpa_x = vax - w_rad_a * ray
      vpa_y = vay + w_rad_a * rax
      vpb_x = vbx - w_rad_b * rby
      vpb_y = vby + w_rad_b * rbx

      rel_vn = (vpb_x - vpa_x) * nx + (vpb_y - vpa_y) * ny
      if (diff > 0.0 && rel_vn > 0.0) || (diff < 0.0 && rel_vn < 0.0)
        j_vel = rel_vn / k
        vx_imp = j_vel * nx
        vy_imp = j_vel * ny

        a.vx = vax + inv_ma * vx_imp if a.respond_to?(:vx=)
        a.vy = vay + inv_ma * vy_imp if a.respond_to?(:vy=)
        a.omega = wa + ((rax * vy_imp - ray * px_imp) * inv_ia * RAD_TO_DEG) if a.respond_to?(:omega=)

        b.vx = vbx - inv_mb * vx_imp if b.respond_to?(:vx=)
        b.vy = vby - inv_mb * vy_imp if b.respond_to?(:vy=)
        b.omega = wb - ((rbx * vy_imp - rby * px_imp) * inv_ib * RAD_TO_DEG) if b.respond_to?(:omega=)
      end

      true
    end
  end
end

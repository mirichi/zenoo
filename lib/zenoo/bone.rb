# frozen_string_literal: true

module Zenoo
  # ====================================================================
  # 2D ボーン（関節ノード）& インバースキネマティクス (IK) クラス
  # Sprite を継承し、画像を持たない関節階層ノードとして機能します。
  # デフォルトでは width = 0, height = 0, anchor = :top_left, pivot = :top_left となり、
  # (x, y) がそのまま親ボーンからの相対オフセットおよび自身の回転中心（関節点）になります。
  # ====================================================================
  class Bone < Sprite
    attr_accessor :name, :length

    def initialize(x = 0.0, y = 0.0, angle: 0.0, length: 0.0, name: nil, parent: nil,
                   scale_x: 1.0, scale_y: 1.0, width: nil, height: nil,
                   anchor: :top_left, pivot: :top_left)
      super(x, y, nil, width: width, height: height, anchor: anchor, pivot: pivot, parent: parent)
      @name = name
      @length = length.to_f
      self.angle = angle if angle != 0.0
      self.scale_x = scale_x if scale_x != 1.0
      self.scale_y = scale_y if scale_y != 1.0
    end

    # 親ボーンの回転分を自動相殺してワールド角度（度数法）を直接設定します
    def world_angle=(deg)
      if @parent
        self.angle = deg.to_f - @parent.world_angle
      else
        self.angle = deg.to_f
      end
    end

    # ボーン先端のワールド座標 (length が設定されている場合、または子ボーンがある場合)
    def tip_world_pos
      wx = world_pivot_x
      wy = world_pivot_y
      if @length > 0.0001
        len = @length * world_scale_x
        [wx + len * world_cos, wy + len * world_sin]
      elsif @children && !@children.empty?
        ch = @children[0]
        [ch.world_pivot_x, ch.world_pivot_y]
      else
        [wx, wy]
      end
    end

    def tip_world_x
      wx = world_pivot_x
      if @length > 0.0001
        wx + (@length * world_scale_x) * world_cos
      elsif @children && !@children.empty?
        @children[0].world_pivot_x
      else
        wx
      end
    end

    def tip_world_y
      wy = world_pivot_y
      if @length > 0.0001
        wy + (@length * world_scale_x) * world_sin
      elsif @children && !@children.empty?
        @children[0].world_pivot_y
      else
        wy
      end
    end

    # ====================================================================
    # 階層・チェーン構築ヘルパー
    # ====================================================================

    # 親ノードから直列につながるボーン配列を一括生成します
    # - parent: 起点となる親 Bone / Sprite (または nil)
    # - lengths: 各ボーンの長さの配列 (例: [85.0, 85.0, 30.0])
    # - x, y: 先頭ボーンの初期オフセット座標
    # - angle: 先頭ボーンの初期角度
    def self.chain(parent, lengths, x: 0.0, y: 0.0, angle: 0.0, name_prefix: nil)
      bones = []
      cur_parent = parent
      prev_len = 0.0
      i = 0
      n = lengths.length
      while i < n
        len = lengths[i].to_f
        bx = (i == 0) ? x.to_f : prev_len
        by = (i == 0) ? y.to_f : 0.0
        b_ang = (i == 0) ? angle.to_f : 0.0
        b_name = name_prefix ? "#{name_prefix}_#{i}" : nil
        b = Bone.new(bx, by, angle: b_ang, length: len, parent: cur_parent, name: b_name)
        bones << b
        cur_parent = b
        prev_len = len
        i += 1
      end
      bones
    end

    # ====================================================================
    # インバースキネマティクス (IK) ソルバー
    # ====================================================================

    # 2ボーンIKの角度（度数法）を余弦定理で算出します
    # 戻り値: [upper_world_deg, lower_local_deg]
    # - x0, y0: 根元（肩・股関節）のワールド座標
    # - tx, ty: 目標（手首・足首）のワールド座標
    # - len1, len2: 第1ボーン（上腕・太もも）と第2ボーン（前腕・すね）の長さ
    # - bend: 関節の曲がる向き (+1.0 または -1.0)
    def self.calc_two_bone(x0, y0, tx, ty, len1, len2, bend: 1.0)
      dx = tx.to_f - x0.to_f
      dy = ty.to_f - y0.to_f
      dist = Math.sqrt(dx * dx + dy * dy)

      l1 = len1.to_f
      l2 = len2.to_f
      max_dist = l1 + l2 - 0.001
      min_dist = (l1 - l2).abs + 0.001
      dist = dist.clamp(min_dist, max_dist)

      base_angle = Math.atan2(dy, dx)

      cos_alpha = ((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)).clamp(-1.0, 1.0)
      alpha = Math.acos(cos_alpha)

      cos_beta = ((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2)).clamp(-1.0, 1.0)
      beta = Math.acos(cos_beta)

      b_dir = bend.to_f
      upper_rad = base_angle - b_dir * alpha
      lower_rad = b_dir * (Math::PI - beta)

      [upper_rad * (180.0 / Math::PI), lower_rad * (180.0 / Math::PI)]
    end

    # 2つのボーン (upper, lower) に対して2ボーンIKを計算し、回転角を直接適用します
    # - upper: 第1ボーン（太もも・上腕）
    # - lower: 第2ボーン（すね・前腕）
    # - tx, ty: 目標ワールド座標
    # - bend: 関節の曲がる向き (+1.0: 膝・前曲がり, -1.0: 肘・後ろ曲がり)
    # - tip_bone: 先端の第3ボーン（足首・手首など、省略可）
    # - tip_angle: tip_bone を維持したいワールド角度（地面やボードの傾斜角など、省略可）
    def self.solve_two_bone(upper, lower, tx, ty, bend: 1.0, tip_bone: nil, tip_angle: nil)
      x0 = upper.world_pivot_x
      y0 = upper.world_pivot_y
      len1 = upper.length * upper.world_scale_x
      len2 = lower.length * lower.world_scale_x

      u_deg, l_deg = calc_two_bone(x0, y0, tx, ty, len1, len2, bend: bend)
      upper.world_angle = u_deg
      lower.angle = l_deg

      if tip_bone && tip_angle
        tip_bone.world_angle = tip_angle.to_f
      end
      [u_deg, l_deg]
    end

    # 自身を第1ボーン、lower を第2ボーンとして2ボーンIKを解決します
    def solve_two_bone(lower, tx, ty, bend: 1.0, tip_bone: nil, tip_angle: nil)
      Bone.solve_two_bone(self, lower, tx, ty, bend: bend, tip_bone: tip_bone, tip_angle: tip_angle)
    end

    # 多関節ボーン配列に対して FABRIK (Forward And Backward Reaching IK) を実行し、
    # 各ボーンの回転角度を一括更新します（触手・尻尾・多関節アーム等）
    # - bones: 直列に並んだ Bone の配列
    # - tx, ty: 先端が目指す目標ワールド座標
    # - iterations: 反復計算回数（デフォルト: 4）
    def self.solve_fabrik(bones, tx, ty, iterations: 4)
      n = bones.length
      return if n == 0

      root = bones[0]
      root_x = root.world_pivot_x
      root_y = root.world_pivot_y

      # 各関節の現在ワールド座標 (n + 1 個) と各セグメント長を収集
      px = Array.new(n + 1, 0.0)
      py = Array.new(n + 1, 0.0)
      lens = Array.new(n, 0.0)
      total_len = 0.0

      i = 0
      while i < n
        b = bones[i]
        px[i] = b.world_pivot_x
        py[i] = b.world_pivot_y
        seg_l = b.length * b.world_scale_x
        seg_l = 1.0 if seg_l <= 0.0001
        lens[i] = seg_l
        total_len += seg_l
        i += 1
      end
      last_b = bones[n - 1]
      px[n] = last_b.tip_world_x
      py[n] = last_b.tip_world_y

      # 目標が最大リーチより遠い場合は、ポッピング（急激な直線化）を防ぐため最大リーチ円周上へクランプ
      dx = tx.to_f - root_x
      dy = ty.to_f - root_y
      dist_sq = dx * dx + dy * dy
      max_reach = total_len - 0.001
      eff_tx = tx.to_f
      eff_ty = ty.to_f
      if dist_sq > max_reach * max_reach && dist_sq > 0.000001
        scale = max_reach / Math.sqrt(dist_sq)
        eff_tx = root_x + dx * scale
        eff_ty = root_y + dy * scale
      end

      # FABRIK 反復計算
      iter = 0
      while iter < iterations
        # 1. Backward Reaching (先端から根元へ)
        px[n] = eff_tx
        py[n] = eff_ty
        j = n - 1
        while j >= 0
          vx = px[j] - px[j + 1]
          vy = py[j] - py[j + 1]
          d = Math.sqrt(vx * vx + vy * vy)
          d = 0.0001 if d < 0.0001
          inv = lens[j] / d
          px[j] = px[j + 1] + vx * inv
          py[j] = py[j + 1] + vy * inv
          j -= 1
        end

        # 2. Forward Reaching (根元から先端へ)
        px[0] = root_x
        py[0] = root_y
        j = 0
        while j < n
          vx = px[j + 1] - px[j]
          vy = py[j + 1] - py[j]
          d = Math.sqrt(vx * vx + vy * vy)
          d = 0.0001 if d < 0.0001
          inv = lens[j] / d
          px[j + 1] = px[j] + vx * inv
          py[j + 1] = py[j] + vy * inv
          j += 1
        end

        iter += 1
      end

      # 算出された関節点座標から各ボーンの回転角を更新
      parent_w_ang = root.parent ? root.parent.world_angle : 0.0
      i = 0
      while i < n
        vx = px[i + 1] - px[i]
        vy = py[i + 1] - py[i]
        w_deg = Math.atan2(vy, vx) * (180.0 / Math::PI)
        bones[i].angle = w_deg - parent_w_ang
        parent_w_ang = w_deg
        i += 1
      end

      bones
    end

    # ====================================================================
    # 接地調停・プロシージャル歩行アシスト（応用ヘルパー）
    # ====================================================================

    # 2足キャラクターの左右の足先ターゲット (tx1, ty1), (tx2, ty2) に対して、
    # 膝が伸びきらない (max_reach) かつ潰れすぎない (min_reach) ための
    # 理想の腰座標と骨盤の傾き [hip_x, hip_y, hip_angle] を算出します
    def self.calc_pelvis(base_x, base_y, tx1, ty1, tx2, ty2,
                         hip_spacing: 16.0, max_reach: 145.0, min_reach: 50.0, tilt_ratio: 0.65)
      mid_foot_x = (tx1 + tx2) * 0.5
      foot_dx = tx2 - tx1
      foot_dy = ty2 - ty1
      ground_slope_deg = Math.atan2(foot_dy, foot_dx.abs > 0.001 ? foot_dx : 1.0) * (180.0 / Math::PI)
      hip_angle = ground_slope_deg * tilt_ratio

      max_x_offset = max_reach * 0.65
      hip_x = base_x.to_f.clamp(mid_foot_x - max_x_offset, mid_foot_x + max_x_offset)
      hip_y = base_y.to_f

      hl_x = hip_x - hip_spacing
      hr_x = hip_x + hip_spacing

      # 1. 足の突っ張り（突き上げ）: 足元が高すぎて膝が潰れそうなとき腰を持ち上げる
      if min_reach > 0.0
        dist_1 = Math.hypot(tx1 - hl_x, ty1 - hip_y)
        if dist_1 < min_reach
          dx = (hl_x - tx1).abs
          dy_needed = Math.sqrt([min_reach * min_reach - dx * dx, 4.0].max)
          hip_y = [hip_y, ty1 - dy_needed].min
        end

        dist_2 = Math.hypot(tx2 - hr_x, ty2 - hip_y)
        if dist_2 < min_reach
          dx = (hr_x - tx2).abs
          dy_needed = Math.sqrt([min_reach * min_reach - dx * dx, 4.0].max)
          hip_y = [hip_y, ty2 - dy_needed].min
        end
      end

      # 2. 足の引っ張り（引き下げ）: 足元が遠すぎて届かないとき腰を引き下げる
      dist_1 = Math.hypot(tx1 - hl_x, ty1 - hip_y)
      if dist_1 > max_reach
        dx = [(hl_x - tx1).abs, max_reach - 1.0].min
        dy_max = Math.sqrt(max_reach * max_reach - dx * dx)
        hip_y = [hip_y, ty1 - dy_max].max
      end

      dist_2 = Math.hypot(tx2 - hr_x, ty2 - hip_y)
      if dist_2 > max_reach
        dx = [(hr_x - tx2).abs, max_reach - 1.0].min
        dy_max = Math.sqrt(max_reach * max_reach - dx * dx)
        hip_y = [hip_y, ty2 - dy_max].max
      end

      [hip_x, hip_y, hip_angle]
    end

    # フットスライド（足滑り）を起こさないプロシージャル歩行の1歩分の足先オフセットを算出します
    # サイクル前半 (0..π) は地面と完全一致する等速直線移動、後半 (π..2π) は上空へ弧を描いて前方へ復帰します
    # - phase: 歩行フェーズ角（ラジアン）
    # - stride: 振り幅（片道ストライド半径 px）
    # - lift: 足を上げる高さ (px)
    # 戻り値: [offset_x, offset_y, grounded] (grounded は接地中なら true)
    def self.step_offset(phase, stride: 50.0, lift: 25.0)
      u = (phase.to_f / (2.0 * Math::PI)) % 1.0
      u += 1.0 if u < 0.0

      if u < 0.5
        # 接地フェーズ (Stance: 0.0 -> 0.5): 前方(+stride)から後方(-stride)へ等速直線移動
        t = u * 2.0
        ox = stride * (1.0 - 2.0 * t)
        [ox, 0.0, true]
      else
        # 空中フェーズ (Swing: 0.5 -> 1.0): 後方(-stride)から前方(+stride)へ弧を描いて移動
        s = (u - 0.5) * 2.0
        ox = -stride * Math.cos(s * Math::PI)
        oy = -Math.sin(s * Math::PI) * lift
        [ox, oy, false]
      end
    end

    # ====================================================================
    # ボーン描画ヘルパー (SDF カプセル・テーパーチェーン・デバッグ骨格)
    # ====================================================================

    # 単体ボーンをSDF丸端カプセル（＋オプションのコア発光ライン＆関節サークル）として描画します
    def draw_capsule(width: 12.0, color: :white, core_width: 0.0, core_color: nil,
                     joint_radius: 0.0, joint_color: nil, joint_border_width: 2.0, joint_border_color: nil,
                     camera: true, z: 0.0)
      wx = world_pivot_x
      wy = world_pivot_y
      tx = tip_world_x
      ty = tip_world_y

      Window.draw_line(wx, wy, tx, ty, color: color, width: width, cap: :round, camera: camera, z: z)
      if core_color && core_width > 0.0
        Window.draw_line(wx, wy, tx, ty, color: core_color, width: core_width, cap: :round, camera: camera, z: z)
      end
      if joint_radius > 0.0
        j_col = joint_color || color
        b_col = joint_border_color || core_color
        b_w = b_col ? joint_border_width : 0.0
        Window.draw_circle(wx, wy, joint_radius, color: j_col, border_width: b_w, border_color: b_col, camera: camera, z: z)
      end
    end

    # ボーン配列（チェーン）を根元から先端へ向けて太さが変化するカプセル列として一括描画します
    # メカの腕・脚から、有機的な触手・尻尾まで幅広く表現できます
    def self.draw_chain(bones, width: nil, start_width: 16.0, end_width: 8.0,
                        color: :white, core_ratio: 0.0, core_color: nil,
                        joint_radius: nil, joint_color: nil, joint_border_color: nil,
                        camera: true, z: 0.0)
      n = bones.length
      return if n == 0

      w0 = (width || start_width).to_f
      w1 = (width || end_width).to_f

      i = 0
      while i < n
        b = bones[i]
        t = n > 1 ? (i.to_f / (n - 1).to_f) : 0.0
        cur_w = w0 + (w1 - w0) * t
        c_w = (core_color && core_ratio > 0.0) ? [cur_w * core_ratio, 1.5].max : 0.0
        j_r = if joint_radius
                joint_radius.to_f
              elsif joint_color
                cur_w * 0.45
              else
                0.0
              end

        b.draw_capsule(
          width: cur_w,
          color: color,
          core_width: c_w,
          core_color: core_color,
          joint_radius: j_r,
          joint_color: joint_color,
          joint_border_color: joint_border_color,
          camera: camera,
          z: z
        )
        i += 1
      end
    end

    # ボーンおよび子ボーン階層のデバッグ可視化描画
    def draw_debug(color: :cyan, joint_color: :yellow, width: 3.0, joint_radius: 5.0, recursive: true, camera: true, z: 1000.0)
      wx = world_pivot_x
      wy = world_pivot_y

      if @children && !@children.empty?
        if @length > 0.0001
          tx, ty = tip_world_pos
          Window.draw_line(wx, wy, tx, ty, color: color, width: width, cap: :round, camera: camera, z: z)
          Window.draw_circle(tx, ty, joint_radius * 0.7, color: color, camera: camera, z: z + 0.01)
        end
        @children.each do |ch|
          next unless ch.is_a?(Sprite)
          cwx = ch.world_pivot_x
          cwy = ch.world_pivot_y
          if @length <= 0.0001
            Window.draw_line(wx, wy, cwx, cwy, color: color, width: width, cap: :round, camera: camera, z: z)
          else
            Window.draw_line(wx, wy, cwx, cwy, color: [180, 180, 220, 120], width: width * 0.6, cap: :round, camera: camera, z: z - 0.01)
          end
          if recursive && ch.is_a?(Bone)
            ch.draw_debug(color: color, joint_color: joint_color, width: width, joint_radius: joint_radius, recursive: true, camera: camera, z: z)
          end
        end
      elsif @length > 0.0001
        tx, ty = tip_world_pos
        Window.draw_line(wx, wy, tx, ty, color: color, width: width, cap: :round, camera: camera, z: z)
        Window.draw_circle(tx, ty, joint_radius * 0.7, color: color, camera: camera, z: z + 0.01)
      end

      Window.draw_circle(wx, wy, joint_radius, color: joint_color, border_color: :black, border_width: 1.5, camera: camera, z: z + 0.02)
    end

    def self.draw_debug(bones, **kwargs)
      if bones.is_a?(Array)
        i = 0
        len = bones.length
        while i < len
          b = bones[i]
          b.draw_debug(**kwargs, recursive: false) if b.is_a?(Bone)
          i += 1
        end
      elsif bones.is_a?(Bone)
        bones.draw_debug(**kwargs)
      end
    end
  end
end

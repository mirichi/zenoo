# frozen_string_literal: true
require_relative "../lib/zenoo"

# ====================================================================
# Zenoo 2D プロシージャル・ランナー & 剣振り下ろし IK デモ
#
# ・左右180度位相差の楕円軌道 ＋ 地面Yクリップによる足の走行サイクル
# ・上下バウンド(倍周期)、速度連動の前傾ピッチ、左右ロール、着地クッションを備えた「生きた腰」
# ・肩を親とするターゲットSpriteの回転による「剣の振り下ろし腕IK」
#
# 操作方法:
#   [A][D] または [←][→] : 移動速度の変更（停止〜歩き〜猛ダッシュ〜後退）
#   [SPACE] または 左クリック : 剣を豪快に振り下ろす（腕IKアタック）
#   [W][S] または [↑][↓] : 腰の基準高さ（スクワット・体勢の調整）
#   [TAB]                 : デバッグ表示（ボーン・軌道・ターゲット）の切り替え
# ====================================================================

SCREEN_WIDTH = 960
SCREEN_HEIGHT = 640
BASE_GROUND_Y = 490.0

# ----------------------------------------------------
# 不整地・凸凹地面のプロシージャル標高 & 傾斜角関数
# screen_x と累積スクロール量 scroll_x から地形の高さを算出
# ----------------------------------------------------
def get_ground_y(screen_x, scroll_x, roughness = 1.0)
  return BASE_GROUND_Y if roughness <= 0.001
  wx = screen_x + scroll_x
  y = BASE_GROUND_Y
  y += Math.sin(wx * 0.0035) * (45.0 * roughness)
  y += Math.sin(wx * 0.011 + 1.4) * (22.0 * roughness)
  y += Math.cos(wx * 0.032 + 2.7) * (10.0 * roughness)
  y
end

# screen_x における地面の接線傾斜角 (度数法)
def get_ground_slope_deg(screen_x, scroll_x, roughness = 1.0)
  return 0.0 if roughness <= 0.001
  y_prev = get_ground_y(screen_x - 6.0, scroll_x, roughness)
  y_next = get_ground_y(screen_x + 6.0, scroll_x, roughness)
  Math.atan2(y_next - y_prev, 12.0) * (180.0 / Math::PI)
end

# ----------------------------------------------------
# キャラクターのセットアップ (Bone.chain で腕・脚を直列生成)
# ----------------------------------------------------
CHARA_BASE_X = SCREEN_WIDTH * 0.42
base_hip_y = 350.0

LEG_UPPER = 75.0
LEG_LOWER = 75.0
MAX_COMFORTABLE_REACH = 144.0 # 足の最大長(150px)に対して膝にゆとりを残す上限
ARM_UPPER = 45.0
ARM_LOWER = 50.0

# 腰（骨盤）
pelvis = Bone.new(CHARA_BASE_X, base_hip_y, name: "Pelvis")

# 胴体・背骨・頭
spine = Bone.new(0.0, -15.0, length: 70.0, parent: pelvis, name: "Spine")
spine.angle = -90.0 # 上向き
head = Bone.new(70.0, 0.0, length: 25.0, parent: spine, name: "Head")

# 肩（右肩・左肩）と腕ボーンチェーン
shoulder_l = Bone.new(55.0, -12.0, parent: spine, name: "Shoulder_L") # 奥の肩
upper_arm_l, forearm_l = Bone.chain(shoulder_l, [ARM_UPPER, ARM_LOWER], name_prefix: "ArmL")

shoulder_r = Bone.new(55.0, 12.0, parent: spine, name: "Shoulder_R")  # 手前の肩
upper_arm_r, forearm_r = Bone.chain(shoulder_r, [ARM_UPPER, ARM_LOWER], name_prefix: "ArmR")

# 股関節と脚ボーンチェーン
hip_l = Bone.new(-12.0, 0.0, parent: pelvis, name: "Hip_L") # 奥脚の股関節
thigh_l, calf_l = Bone.chain(hip_l, [LEG_UPPER, LEG_LOWER], name_prefix: "LegL")

hip_r = Bone.new(12.0, 0.0, parent: pelvis, name: "Hip_R")  # 手前脚の股関節
thigh_r, calf_r = Bone.chain(hip_r, [LEG_UPPER, LEG_LOWER], name_prefix: "LegR")

# ----------------------------------------------------
# 剣と腕IK用のターゲットSprite階層（両手持ち）
# 肩（Shoulder）を中心とする回転アーム shoulder_sword_pivot を配置し、
# その先端に手元（sword_pivot）を配置することで「肩主導の豪快な振り」を実現。
# ----------------------------------------------------
SWORD_READY_ANGLE  =   0.0 # ユーザー調整済みの構え角度
SWORD_WINDUP_ANGLE = -115.0 # 肩中心の振りかぶり (背後・上段へ腕ごと引き絞る)
SWORD_SLASH_ANGLE  =   85.0 # 肩中心の振り下ろし (前下方へ腕ごと豪快に振り抜く)

# 1. 肩の回転ピボット (手前肩の位置 X=55, Y=12 に配置)
shoulder_sword_pivot = Sprite.new(55.0, 12.0, parent: spine)
shoulder_sword_pivot.angle = 0.0

# 2. 手元（グリップ中心）: 肩の子としてユーザー調整の構え位置 (10, 70) に配置
# これにより shoulder_sword_pivot.angle = 0 のとき、spineから見て (65, 82) に完全一致
sword_pivot = Sprite.new(10.0, 70.0, parent: shoulder_sword_pivot)
sword_pivot.angle = SWORD_READY_ANGLE

# 3. グリップ上の両手: 右手が上（刀身寄り +10px）、左手が下（柄尻寄り -10px）
sword_target_r = Sprite.new(10.0, 0.0, parent: sword_pivot) # 右手ターゲット（上・鍔寄り）
sword_target_l = Sprite.new(-10.0, 0.0, parent: sword_pivot) # 左手ターゲット（下・柄尻寄り）

# 走行・アニメーション状態変数
speed = 260.0               # 移動速度 (px/s)
target_speed = 260.0
walk_cycle = 0.0            # 歩行フェーズ角 (ラジアン)
ground_scroll_x = 0.0       # 地面スクロールオフセット
show_debug = false

# 剣振り下ろし状態
is_slashing = false
slash_trail = [] # 剣の軌跡ポイント

# 地形起伏プリセット (キー [T] で切替)
TERRAIN_PRESETS = [
  { name: "凸凹の丘 (Rolling Hills)", roughness: 1.0 },
  { name: "険しい不整地 (Rugged Uneven)", roughness: 1.8 },
  { name: "平坦な直線 (Flat Ground)", roughness: 0.0 },
  { name: "軽微な起伏 (Gentle Uneven)", roughness: 0.5 }
]
current_terrain_idx = 0

# 地形追従サスペンション状態変数
terrain_hip_offset = 0.0
terrain_slope_angle = 0.0
world_scroll_x = 0.0

# ----------------------------------------------------
# 足の接地・軌道 & 足首角度計算ヘルパー（Bone.step_offset で滑り完全ゼロ化）
# ----------------------------------------------------
def calc_foot_trajectory(cycle, phase, hip_world_x, scroll_x, stride_half, swing_height, roughness)
  ox, oy, is_grounded = Bone.step_offset(cycle + phase, stride: stride_half, lift: swing_height)
  foot_x = hip_world_x + ox
  local_gy = get_ground_y(foot_x, scroll_x, roughness)
  ground_slope = get_ground_slope_deg(foot_x, scroll_x, roughness)
  foot_y = local_gy + oy

  if is_grounded
    foot_angle = ground_slope
  else
    u = ((cycle + phase) / (2.0 * Math::PI)) % 1.0
    u += 1.0 if u < 0.0
    s = (u - 0.5) * 2.0
    air_angle = (1.0 - s) * 16.0 - 6.0
    if s > 0.65
      approach_t = (s - 0.65) / 0.35
      foot_angle = air_angle * (1.0 - approach_t) + ground_slope * approach_t
    else
      foot_angle = air_angle
    end
  end

  [foot_x, foot_y, is_grounded, local_gy, foot_angle, ground_slope]
end

# ----------------------------------------------------
# メインループ
# ----------------------------------------------------
Window.loop(SCREEN_WIDTH, SCREEN_HEIGHT, "Zenoo - Procedural Runner & Sword IK") do
  dt = Window.delta_time

  # --------------------------------------------------
  # 1. ユーザー入力
  # --------------------------------------------------
  if Input.key_push?(:tab)
    show_debug = !show_debug
  end

  # 速度操作
  if Input.key_down?(:d) || Input.key_down?(:right)
    target_speed = [target_speed + 350.0 * dt, 550.0].min
  elsif Input.key_down?(:a) || Input.key_down?(:left)
    target_speed = [target_speed - 350.0 * dt, -180.0].max
  else
    # キーを離したときの自然減速 / 通常速度維持
    # 完全に停止させたい場合は 0 に近づける
  end

  # プリセット速度キー
  target_speed = 0.0 if Input.key_push?(:num0) || Input.key_push?(:k0)
  target_speed = 120.0 if Input.key_push?(:num1) || Input.key_push?(:k1)
  target_speed = 280.0 if Input.key_push?(:num2) || Input.key_push?(:k2)
  target_speed = 520.0 if Input.key_push?(:num3) || Input.key_push?(:k3)

  # 地形起伏プリセットの切り替え ([T] キー)
  if Input.key_push?(:t)
    current_terrain_idx = (current_terrain_idx + 1) % TERRAIN_PRESETS.length
  end
  roughness = TERRAIN_PRESETS[current_terrain_idx][:roughness]

  # 腰の高さ調整（スクワット・姿勢変更）
  if Input.key_down?(:w) || Input.key_down?(:up)
    base_hip_y -= 80.0 * dt
  end
  if Input.key_down?(:s) || Input.key_down?(:down)
    base_hip_y += 80.0 * dt
  end
  base_hip_y = base_hip_y.clamp(280.0, 410.0)

  # 剣の振り下ろしトリガー（肩中心の Expo In 居合一閃 Tween）
  if (Input.key_push?(:space) || Input.mouse_push?(:left)) && !is_slashing
    is_slashing = true
    slash_trail.clear

    shoulder_sword_pivot.kill_tweens
    # Sprite#tween による肩中心の回転（Expo In で瞬間超加速）:
    # 1. 振りかぶり (背後・上段へ引き絞る: SWORD_WINDUP_ANGLE)
    # 2. 一閃 (前下方へ超加速で振り抜く: SWORD_SLASH_ANGLE, :expo_in)
    # 3. 残心・構え復帰 (元の構え位置 0.0 へスムーズに戻る)
    shoulder_sword_pivot.tween
      .to(0.13, angle: SWORD_WINDUP_ANGLE, ease: :back_out)
      .to(0.08, angle: SWORD_SLASH_ANGLE,  ease: :expo_in)
      .to(0.20, angle: 0.0,                ease: :quad_out)
      .call { is_slashing = false }
  end

  # Sprite の Tweenable 更新
  shoulder_sword_pivot.update
  sword_pivot.update

  # 速度のスムーズ補間
  speed += (target_speed - speed) * (6.0 * dt)
  abs_speed = speed.abs

  # 地面ワールドスクロール累積
  world_scroll_x += speed * dt

  # --------------------------------------------------
  # 2. 走行サイクル進行 & 腰（骨盤）の凝った挙動計算
  # --------------------------------------------------
  # 地面スクロール速度と100%完全同期するダイナミックな大股ストライド
  stride_x = 52.0 + abs_speed * 0.12
  freq = stride_x > 0.001 ? (speed * Math::PI) / (2.0 * stride_x) : 0.0
  walk_cycle += freq * dt

  # スピード比率と足の持ち上げ高さ
  speed_ratio = (speed / 500.0).clamp(-0.5, 1.0)
  swing_height = 24.0 + (abs_speed / 500.0) * 16.0

  # --------------------------------------------------
  # 3. 両足の接地・軌道 & 足首角度計算（不整地・凸凹地面対応）
  # --------------------------------------------------
  # 左足（奥: phase = Math::PI）
  foot_lx, foot_ly, ground_l, gy_l, foot_angle_l = calc_foot_trajectory(walk_cycle, Math::PI, pelvis.x - 8.0, world_scroll_x, stride_x, swing_height, roughness)
  # 右足（手前: phase = 0.0）
  foot_rx, foot_ry, ground_r, gy_r, foot_angle_r = calc_foot_trajectory(walk_cycle, 0.0, pelvis.x + 8.0, world_scroll_x, stride_x, swing_height, roughness)

  # === 腰の4大挙動 ＋ 斬撃連動 ＋ 地形適応サスペンション ===
  # (A) 上下バウンド (倍周期 2θ): 1歩ごとに着地で沈み、蹴り出しで跳ねる
  bounce_amount = (abs_speed / 500.0) * 12.0
  pelvis_bounce = Math.sin(walk_cycle * 2.0) * bounce_amount

  # 斬撃時の踏み込み沈み込み & 全身前傾（Tween の肩回転角に完全連動）
  slash_impact_drop = 0.0
  slash_impact_lean = 0.0
  if is_slashing && shoulder_sword_pivot.angle > -50.0 && shoulder_sword_pivot.angle < (SWORD_SLASH_ANGLE + 10.0)
    ang_ratio = ((shoulder_sword_pivot.angle - (-50.0)) / (SWORD_SLASH_ANGLE + 60.0)).clamp(0.0, 1.0)
    impact_curve = Math.sin(ang_ratio * Math::PI)
    slash_impact_drop = impact_curve * 14.0
    slash_impact_lean = impact_curve * 18.0
  end

  # (B) 走行速度連動の前傾チルト（ピッチ）: 高速時は最大約22度前傾
  forward_lean = speed_ratio * 18.0
  pitch_bobbing = Math.cos(walk_cycle * 2.0) * (speed_ratio * 3.5)
  pelvis_pitch = forward_lean + pitch_bobbing + slash_impact_lean

  # (C) 骨盤の左右ロール（手前・奥の足の入れ替わりによるシーソー傾き）
  pelvis_roll = Math.sin(walk_cycle) * 4.0

  # (E) 地形適応（サスペンション & 窪地での腰落とし & 坂道チルト）
  # 左右の足元の平均高さを基準としつつ、窪地（より低い地面）がある時は適度に腰を引き下げる
  avg_gy = (gy_l + gy_r) * 0.5
  lowest_gy = [gy_l, gy_r].max
  dip_depth = lowest_gy - avg_gy # 片足が深く落ち込んでいる深さ
  target_ground_y = avg_gy + dip_depth * 0.5

  target_terrain_hip_y = target_ground_y - BASE_GROUND_Y
  slope_rad = Math.atan2(gy_r - gy_l, (foot_rx - foot_lx).abs + 1.0)
  target_slope_deg = slope_rad * (180.0 / Math::PI)

  # サスペンションのスムーズ補間
  terrain_hip_offset += (target_terrain_hip_y - terrain_hip_offset) * (14.0 * dt)
  terrain_slope_angle += (target_slope_deg - terrain_slope_angle) * (12.0 * dt)

  # (D) 腰の最終座標と角度の適用
  pelvis.x = CHARA_BASE_X
  temp_hip_y = base_hip_y + pelvis_bounce + slash_impact_drop + terrain_hip_offset

  # ★ 膝の伸びきり防止・腰引き下げ調停 (Knee Extension Limiter)
  # 足の合計長(150px)に対して、144px を超えて足がピンと突っ張りそうになった時だけ腰を真下に落とす
  reach_l = Math.hypot(foot_lx - (CHARA_BASE_X - 12.0), foot_ly - temp_hip_y)
  reach_r = Math.hypot(foot_rx - (CHARA_BASE_X + 12.0), foot_ry - temp_hip_y)
  knee_stretch = [reach_l - MAX_COMFORTABLE_REACH, reach_r - MAX_COMFORTABLE_REACH, 0.0].max

  pelvis.y = temp_hip_y + knee_stretch * 1.05 # 足が届かなくなる分だけ腰を真下に落とす
  pelvis.angle = pelvis_pitch + pelvis_roll + terrain_slope_angle * 0.65

  # 胴体・背骨のカウンターバランス（前傾を保ちつつわずかにしなる）
  spine.angle = -90.0 - (forward_lean * 0.3) - (slash_impact_lean * 0.5) + Math.sin(walk_cycle) * 3.0
  head.angle = -pelvis.angle * 0.5 # 頭部は水平を保とうとする前庭反射

  # --------------------------------------------------
  # 4. 2ボーンIKの計算と適用 (Bone.solve_two_bone)
  # --------------------------------------------------
  # 左脚 IK（奥脚: bend: 1.0）
  Bone.solve_two_bone(thigh_l, calf_l, foot_lx, foot_ly, bend: 1.0)

  # 右脚 IK（手前脚: bend: 1.0）
  Bone.solve_two_bone(thigh_r, calf_r, foot_rx, foot_ry, bend: 1.0)

  # --------------------------------------------------
  # 5. 両手持ちの剣振り下ろし & 両腕IK
  # --------------------------------------------------
  unless is_slashing
    # 待機・走行中の両手構え（走りのリズムで肩アームが自然に揺れる）
    arm_bob = Math.sin(walk_cycle) * (3.5 + speed_ratio * 5.0)
    shoulder_sword_pivot.angle = arm_bob
    sword_pivot.angle = SWORD_READY_ANGLE
  end

  # --- 両腕IKの解決 (bend: -1.0 肘後ろ曲がり) ---
  # 右手（手前手: 鍔寄り）
  target_hand_rx = sword_target_r.world_pivot_x
  target_hand_ry = sword_target_r.world_pivot_y
  Bone.solve_two_bone(upper_arm_r, forearm_r, target_hand_rx, target_hand_ry, bend: -1.0)

  # 左手（奥手: 柄尻寄り）
  target_hand_lx = sword_target_l.world_pivot_x
  target_hand_ly = sword_target_l.world_pivot_y
  Bone.solve_two_bone(upper_arm_l, forearm_l, target_hand_lx, target_hand_ly, bend: -1.0)

  # 剣の切っ先位置の計算 & 斬撃軌跡トレイルの記録
  sword_angle_rad = (sword_pivot.world_angle) * Math::PI / 180.0
  sword_len = 90.0
  sword_tip_x = target_hand_rx + Math.cos(sword_angle_rad) * sword_len
  sword_tip_y = target_hand_ry + Math.sin(sword_angle_rad) * sword_len

  if is_slashing
    slash_trail << [sword_tip_x, sword_tip_y, 1.0] # [x, y, alpha]
  end

  # トレイルのフェードアウト
  i = slash_trail.length - 1
  while i >= 0
    slash_trail[i][2] -= dt * 3.5
    slash_trail.delete_at(i) if slash_trail[i][2] <= 0.0
    i -= 1
  end

  # --------------------------------------------------
  # 6. 描画処理
  # --------------------------------------------------
  # 背景
  Window.draw_rect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, color: [16, 20, 32])

  # 不整地・凸凹地面のスクロール描画 (16pxステップ)
  step_w = 16.0
  gx = 0.0
  while gx < SCREEN_WIDTH + step_w
    gy1 = get_ground_y(gx, world_scroll_x, roughness)
    gy2 = get_ground_y(gx + step_w, world_scroll_x, roughness)

    # 地中岩盤の塗りつぶし
    top_y = [gy1, gy2].min
    Window.draw_rect(gx, top_y, step_w + 1.0, SCREEN_HEIGHT - top_y, color: [22, 28, 42])

    # 地表面ネオンライン（稜線）
    Window.draw_line(gx, gy1, gx + step_w, gy2, color: [60, 100, 160], width: 3.5)
    Window.draw_line(gx, gy1 - 1.0, gx + step_w, gy2 - 1.0, color: [100, 180, 255], width: 1.5)

    gx += step_w
  end

  # 地表面を流れる小石・マーカー（疾走感の演出）
  marker_spacing = 60.0
  mx = -(world_scroll_x % marker_spacing)
  while mx < SCREEN_WIDTH + marker_spacing
    m_gy = get_ground_y(mx, world_scroll_x, roughness)
    Window.draw_circle(mx, m_gy + 8.0, 3.0, color: [60, 90, 140])
    mx += marker_spacing
  end

  # 斬撃トレイル（光の残像）
  if slash_trail.length >= 2
    for t_idx in 0...(slash_trail.length - 1)
      p1 = slash_trail[t_idx]
      p2 = slash_trail[t_idx + 1]
      a = (p1[2] * 220).to_i
      Window.draw_line(p1[0], p1[1], p2[0], p2[1], color: [0, 240, 255, a], width: 6.0, cap: :round)
      Window.draw_line(p1[0], p1[1], p2[0], p2[1], color: [255, 255, 255, a], width: 2.0, cap: :round)
    end
  end

  if show_debug
    # --- デバッグ表示モード ---
    # 足元地面ハイトライン
    Window.draw_line(foot_lx - 20.0, gy_l, foot_lx + 20.0, gy_l, color: [100, 100, 255], width: 1.5)
    Window.draw_line(foot_rx - 20.0, gy_r, foot_rx + 20.0, gy_r, color: [255, 100, 100], width: 1.5)

    # 足裏の傾斜角度ガイド (接地適応 & 補間角度)
    rad_deb_l = foot_angle_l * Math::PI / 180.0
    Window.draw_line(foot_lx - 12.0 * Math.cos(rad_deb_l), foot_ly - 12.0 * Math.sin(rad_deb_l),
                     foot_lx + 22.0 * Math.cos(rad_deb_l), foot_ly + 22.0 * Math.sin(rad_deb_l),
                     color: [140, 160, 255], width: 4.0, cap: :round)

    rad_deb_r = foot_angle_r * Math::PI / 180.0
    Window.draw_line(foot_rx - 14.0 * Math.cos(rad_deb_r), foot_ry - 14.0 * Math.sin(rad_deb_r),
                     foot_rx + 24.0 * Math.cos(rad_deb_r), foot_ry + 24.0 * Math.sin(rad_deb_r),
                     color: [255, 140, 140], width: 4.0, cap: :round)

    # IKターゲット
    Window.draw_circle(foot_lx, foot_ly, 7.0, color: [100, 100, 255], border_color: :white, border_width: 2.0)
    Window.draw_circle(foot_rx, foot_ry, 7.0, color: [255, 100, 100], border_color: :white, border_width: 2.0)
    Window.draw_circle(target_hand_rx, target_hand_ry, 6.0, color: :yellow, border_color: :black, border_width: 1.5)
    Window.draw_circle(target_hand_lx, target_hand_ly, 5.0, color: [255, 180, 50], border_color: :black, border_width: 1.5)

    # ボーン階層の可視化
    pelvis.draw_debug(color: [140, 200, 255], joint_color: [255, 220, 80], width: 4.0)
    # 肩から手元へのピボットアーム（肩中心回転の可視化）
    Window.draw_line(shoulder_sword_pivot.world_pivot_x, shoulder_sword_pivot.world_pivot_y,
                     sword_pivot.world_pivot_x, sword_pivot.world_pivot_y, color: [0, 255, 200, 140], width: 2.0)
    Window.draw_circle(shoulder_sword_pivot.world_pivot_x, shoulder_sword_pivot.world_pivot_y, 4.0, color: [0, 255, 200])
    # 剣
    Window.draw_line(target_hand_lx, target_hand_ly, target_hand_rx, target_hand_ry, color: [180, 140, 60], width: 4.0, cap: :round)
    Window.draw_line(target_hand_rx, target_hand_ry, sword_tip_x, sword_tip_y, color: [255, 80, 80], width: 5.0, cap: :round)
  else
    # --- スタイリッシュ・メカキャラクター描画（両手持ち） ---
    col_back_leg  = [55, 75, 105]
    col_back_sub  = [80, 110, 150]
    col_front_leg = [110, 160, 230]
    col_front_sub = [180, 220, 255]
    col_body      = [80, 115, 170]
    col_armor     = [160, 205, 255]

    # 1. 奥脚（左脚: Bone.draw_chain で一括描画）
    Bone.draw_chain([thigh_l, calf_l], start_width: 14.0, end_width: 11.0, color: col_back_leg)
    Window.draw_circle(calf_l.world_pivot_x, calf_l.world_pivot_y, 7.0, color: col_back_sub)
    # 靴（地面傾斜 ＆ 接地アプローチ補間角度で回転）
    rad_l = foot_angle_l * Math::PI / 180.0
    cos_l = Math.cos(rad_l)
    sin_l = Math.sin(rad_l)
    Window.draw_line(foot_lx - 12.0 * cos_l, foot_ly - 12.0 * sin_l, foot_lx + 22.0 * cos_l, foot_ly + 22.0 * sin_l, color: col_back_sub, width: 8.0, cap: :round)

    # 2. 奥腕（左腕: 柄尻を両手持ちで握る）
    Bone.draw_chain([upper_arm_l, forearm_l], start_width: 10.0, end_width: 8.0, color: col_back_leg)
    Window.draw_circle(forearm_l.world_pivot_x, forearm_l.world_pivot_y, 6.0, color: col_back_sub)
    Window.draw_circle(target_hand_lx, target_hand_ly, 5.0, color: [200, 160, 50])

    # 3. 胴体・骨盤・頭部
    hx, hy = head.world_pivot_x, head.world_pivot_y
    # 骨盤アーマー
    Window.draw_circle(pelvis.x, pelvis.y, 16.0, color: col_body, border_color: col_armor, border_width: 3.0)
    # 背骨・胸部
    spine.draw_capsule(width: 22.0, color: col_body, core_width: 6.0, core_color: col_armor)
    # 頭部ヘルメット & バイザー
    Window.draw_circle(hx, hy, 14.0, color: col_armor)
    Window.draw_line(hx - 2.0, hy + 2.0, hx + 12.0, hy + 2.0, color: [0, 255, 230], width: 5.0, cap: :round)

    # 4. 手前脚（右脚: コアライン付き Bone.draw_chain）
    Bone.draw_chain([thigh_r, calf_r], start_width: 16.0, end_width: 12.0, color: col_front_leg, core_ratio: 0.32, core_color: col_front_sub)
    Window.draw_circle(calf_r.world_pivot_x, calf_r.world_pivot_y, 9.0, color: [30, 45, 70], border_color: col_front_sub, border_width: 2.5)
    # 足裏（ブーツ: 地面傾斜 ＆ 接地アプローチ補間角度で回転）
    rad_r = foot_angle_r * Math::PI / 180.0
    cos_r = Math.cos(rad_r)
    sin_r = Math.sin(rad_r)
    Window.draw_line(foot_rx - 14.0 * cos_r, foot_ry - 14.0 * sin_r, foot_rx + 24.0 * cos_r, foot_ry + 24.0 * sin_r, color: col_front_sub, width: 9.0, cap: :round)
    Window.draw_circle(foot_rx, foot_ry, 6.0, color: [30, 45, 70])

    # 5. 剣（柄 ＋ 鍔 ＋ 刀身）
    # 柄（両手で挟むグリップ部分）
    Window.draw_line(target_hand_lx, target_hand_ly, target_hand_rx, target_hand_ry, color: [60, 40, 30], width: 6.0, cap: :round)
    Window.draw_circle(target_hand_lx, target_hand_ly, 4.0, color: [220, 180, 50]) # 柄頭（ポンメル）

    # 鍔（ガード）
    guard_rad = sword_angle_rad + Math::PI * 0.5
    gx1 = target_hand_rx + Math.cos(guard_rad) * 14.0
    gy1 = target_hand_ry + Math.sin(guard_rad) * 14.0
    gx2 = target_hand_rx - Math.cos(guard_rad) * 14.0
    gy2 = target_hand_ry - Math.sin(guard_rad) * 14.0
    Window.draw_line(gx1, gy1, gx2, gy2, color: [255, 200, 50], width: 4.5, cap: :round)

    # 刀身（ブレード）
    blade_w = is_slashing ? 8.5 : 6.5
    Window.draw_line(target_hand_rx, target_hand_ry, sword_tip_x, sword_tip_y, color: [230, 245, 255], width: blade_w, cap: :round)
    Window.draw_line(target_hand_rx, target_hand_ry, sword_tip_x, sword_tip_y, color: [0, 220, 255], width: blade_w * 0.45, cap: :round)

    # 6. 手前腕（右腕: 鍔寄りを握る）
    upper_arm_r.draw_capsule(width: 13.0, color: col_front_leg, core_width: 4.5, core_color: col_front_sub)
    forearm_r.draw_capsule(width: 11.0, color: col_front_leg, joint_radius: 7.5, joint_color: [30, 45, 70], joint_border_color: col_front_sub, joint_border_width: 2.0)
    Window.draw_circle(target_hand_rx, target_hand_ry, 6.5, color: [255, 200, 50])
  end

  # --------------------------------------------------
  # 7. UI / ステータスHUD表示
  # --------------------------------------------------
  Window.draw_rect(16, 16, 420, 222, color: [10, 15, 25, 215], border_color: [60, 100, 160], border_width: 1.5)
  Window.draw_text(28, 24, "PRO PROCEDURAL RUNNER & UNEVEN TERRAIN IK", size: 16, color: [0, 240, 255])
  Window.draw_line(28, 48, 424, 48, color: [40, 70, 110], width: 1.0)

  spd_label = case
              when abs_speed < 10.0  then "STOPPED"
              when abs_speed < 180.0 then "WALKING"
              when abs_speed < 380.0 then "JOGGING / RUNNING"
              else                        "FULL SPRINT (DASH)"
              end

  cur_terrain = TERRAIN_PRESETS[current_terrain_idx]
  Window.draw_text(28, 56,  "Speed: #{speed.round(1)} px/s  [#{spd_label}]", size: 13, color: :white)
  Window.draw_text(28, 74,  "Pelvis Bounce (2θ) : #{pelvis_bounce.round(1)} px", size: 13, color: [200, 220, 255])
  Window.draw_text(28, 92,  "Terrain Slope Lean : #{terrain_slope_angle.round(1)} deg", size: 13, color: [200, 220, 255])
  Window.draw_text(28, 110, "Terrain ([T])      : #{cur_terrain[:name]}", size: 13, color: [120, 240, 180])
  Window.draw_text(28, 128, "Slash Ease         : Expo In (居合超加速)", size: 13, color: [255, 220, 100])
  Window.draw_text(28, 146, "Sword Angle        : #{sword_pivot.angle.round(1)} deg  (#{is_slashing ? 'SLASHING!' : 'Ready'})", size: 13, color: is_slashing ? [255, 100, 100] : [100, 255, 150])
  Window.draw_text(28, 172, "[SPACE/Click] Slash | [T] Terrain | [TAB] Debug", size: 12, color: [140, 170, 210])
  Window.draw_text(28, 192, "[A][D] Speed | [0..3] Preset | [W][S] Pelvis Height", size: 12, color: [110, 140, 180])
end

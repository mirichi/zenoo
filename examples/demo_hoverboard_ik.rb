# frozen_string_literal: true
require_relative "../lib/zenoo"

# ====================================================================
# Zenoo 2D Inverse Kinematics (IK) デモ: ホバーボード & 下半身
#
# ・Bone.solve_two_bone（余弦定理による幾何解）により、膝の屈伸を高速かつピタッと計算
# ・Bone.calc_pelvis により、足の突っ張り・引き下げ・骨盤チルトを自動調停
# ・浮遊・傾くホバーボードの上に、左右の足がリアルタイムに吸着・接地
# ・Zenoo::Bone の階層構造 (Bone.chain) とカプセル/デバッグ描画を活用
#
# 操作方法:
#   マウス移動 / ドラッグ : ホバーボードの移動
#   マウスホイール / [W][S] : 腰の高さ（スクワット・屈伸）
#   [A][D] または [←][→]   : ボードの手動チルト（傾き）
#   [SPACE]               : 自動浮遊モード ON / OFF
#   [TAB]                 : デバッグボーン表示 / メカ装甲表示の切り替え
# ====================================================================

SCREEN_WIDTH = 960
SCREEN_HEIGHT = 640

# ----------------------------------------------------
# ボーン階層のセットアップ (Bone.chain で直列一括生成)
# ----------------------------------------------------
LEG_UPPER_LEN = 85.0
LEG_LOWER_LEN = 85.0
FOOT_LEN = 30.0

# 腰（骨盤）
hip = Bone.new(SCREEN_WIDTH * 0.5, 230.0, name: "Hip")

# 左脚（奥側: 後ろ足スタンス）
hip_l = Bone.new(-24.0, 0.0, parent: hip, name: "Hip_L")
thigh_l, calf_l, foot_l = Bone.chain(hip_l, [LEG_UPPER_LEN, LEG_LOWER_LEN, FOOT_LEN], name_prefix: "LegL")

# 右脚（手前側: 前足スタンス）
hip_r = Bone.new(24.0, 0.0, parent: hip, name: "Hip_R")
thigh_r, calf_r, foot_r = Bone.chain(hip_r, [LEG_UPPER_LEN, LEG_LOWER_LEN, FOOT_LEN], name_prefix: "LegR")

# ホバーボード
board_x = SCREEN_WIDTH * 0.5
board_y = 430.0
board_angle = 0.0
board_width = 240.0
board_height = 20.0

# ボード上のフットステップ相対オフセット（前後）
STEP_BACK_X = -65.0
STEP_FRONT_X = 65.0
STEP_OFFSET_Y = -12.0 # ボード表面の高さ

# 状態管理
auto_hover = true
show_mesh = true
hover_time = 0.0
hip_target_y = 230.0
tilt_manual = 0.0

# メカ脚パーツの簡易描画ヘルパー (Bone.draw_chain / draw_capsule を活用)
def draw_mech_leg(thigh, calf, foot, col_main, col_accent)
  Bone.draw_chain([thigh, calf], start_width: 14.0, end_width: 11.0, color: col_main, core_ratio: 0.28, core_color: col_accent)
  calf.draw_capsule(width: 0.0, joint_radius: 9.0, joint_color: [30, 40, 60], joint_border_color: col_accent, joint_border_width: 2.5)
  foot.draw_capsule(width: 8.0, color: col_accent, joint_radius: 6.0, joint_color: [20, 30, 45], joint_border_color: col_accent, joint_border_width: 2.0)
end

Window.loop(SCREEN_WIDTH, SCREEN_HEIGHT, "Zenoo - Hoverboard IK Demo") do
  dt = 1.0 / 60.0
  hover_time += dt

  # ----------------------------------------------------
  # 入力処理
  # ----------------------------------------------------
  if Input.key_push?(:space)
    auto_hover = !auto_hover
  end
  if Input.key_push?(:tab)
    show_mesh = !show_mesh
  end

  # 腰の高さ変更（スクワット）
  if Input.key_down?(:w) || Input.key_down?(:up)
    hip_target_y -= 120.0 * dt
  end
  if Input.key_down?(:s) || Input.key_down?(:down)
    hip_target_y += 120.0 * dt
  end
  hip_target_y = hip_target_y.clamp(140.0, 310.0)

  # ボードの手動チルト
  if Input.key_down?(:a) || Input.key_down?(:left)
    tilt_manual -= 60.0 * dt
  elsif Input.key_down?(:d) || Input.key_down?(:right)
    tilt_manual += 60.0 * dt
  else
    tilt_manual *= (1.0 - 5.0 * dt).clamp(0.0, 1.0)
  end
  tilt_manual = tilt_manual.clamp(-40.0, 40.0)

  # ホバーボードの位置計算
  if auto_hover
    # ふわふわ浮遊（サイン波合成）
    target_bx = SCREEN_WIDTH * 0.5 + Math.sin(hover_time * 1.2) * 50.0
    target_by = 430.0 + Math.sin(hover_time * 2.5) * 25.0 + Math.cos(hover_time * 1.1) * 10.0
    target_b_ang = Math.sin(hover_time * 1.8) * 12.0 + tilt_manual

    # マウスドラッグで引っ張り操作も可能
    if Input.mouse_down?(:left)
      target_bx = Input.mouse_x.to_f
      target_by = Input.mouse_y.to_f
    end
  else
    # マウス追従モード
    target_bx = Input.mouse_x.to_f
    target_by = Input.mouse_y.to_f
    target_b_ang = tilt_manual
  end

  # スムーズな補間
  board_x += (target_bx - board_x) * (8.0 * dt)
  board_y += (target_by - board_y) * (8.0 * dt)
  board_angle += (target_b_ang - board_angle) * (10.0 * dt)

  # ----------------------------------------------------
  # ホバーボード上の足置き（ステップ）のワールド座標を計算
  # ----------------------------------------------------
  b_rad = board_angle * Math::PI / 180.0
  b_cos = Math.cos(b_rad)
  b_sin = Math.sin(b_rad)

  # 左足（奥 / 後ろ足）の接地目標
  target_lx = board_x + (STEP_BACK_X * b_cos - STEP_OFFSET_Y * b_sin)
  target_ly = board_y + (STEP_BACK_X * b_sin + STEP_OFFSET_Y * b_cos)

  # 右足（手前 / 前足）の接地目標
  target_rx = board_x + (STEP_FRONT_X * b_cos - STEP_OFFSET_Y * b_sin)
  target_ry = board_y + (STEP_FRONT_X * b_sin + STEP_OFFSET_Y * b_cos)

  # ----------------------------------------------------
  # 足元接地調停（Bone.calc_pelvis）の実行
  # 足の突き上げ・届かない限界・骨盤チルトを全自動調停
  # ----------------------------------------------------
  base_hip_x = board_x
  base_hip_y = hip_target_y

  res_hx, res_hy, res_hang = Bone.calc_pelvis(
    base_hip_x, base_hip_y,
    target_lx, target_ly,
    target_rx, target_ry,
    hip_spacing: 24.0,
    max_reach: LEG_UPPER_LEN + LEG_LOWER_LEN - 3.0,
    min_reach: 55.0
  )

  # 調停された腰座標へ滑らかに追従
  # 突き上げや引っ張りの限界時はより機敏に反応
  hip.x += (res_hx - hip.x) * (12.0 * dt)
  hip.y += (res_hy - hip.y) * (14.0 * dt)
  hip.angle += (res_hang - hip.angle) * (12.0 * dt)

  # ----------------------------------------------------
  # 2ボーンIKの計算とボーンへの適用 (Bone.solve_two_bone)
  # ----------------------------------------------------
  # 1. 左脚（奥足: 足首はボードの傾き角度 board_angle と自動で揃える）
  Bone.solve_two_bone(thigh_l, calf_l, target_lx, target_ly, bend: 1.0, tip_bone: foot_l, tip_angle: board_angle)

  # 2. 右脚（手前足）
  Bone.solve_two_bone(thigh_r, calf_r, target_rx, target_ry, bend: 1.0, tip_bone: foot_r, tip_angle: board_angle)

  # ----------------------------------------------------
  # 描画処理
  # ----------------------------------------------------
  Window.clear([16, 20, 32])

  # 背景グリッド
  (0..SCREEN_WIDTH).step(40) { |gx| Window.draw_line(gx, 0, gx, SCREEN_HEIGHT, color: [24, 32, 50, 255], width: 1.0) }
  (0..SCREEN_HEIGHT).step(40) { |gy| Window.draw_line(0, gy, SCREEN_WIDTH, gy, color: [24, 32, 50, 255], width: 1.0) }

  # ホバーボードのスラスターエフェクト（噴射プラズマ）
  thrust_len = 35.0 + Math.sin(hover_time * 25.0) * 12.0
  thrust_x = board_x - b_sin * 12.0
  thrust_y = board_y + b_cos * 12.0
  jet_end_x = thrust_x - b_sin * thrust_len
  jet_end_y = thrust_y + b_cos * thrust_len
  Window.draw_line(thrust_x, thrust_y, jet_end_x, jet_end_y, color: [0, 200, 255, 180], width: 14.0, cap: :round)
  Window.draw_line(thrust_x, thrust_y, jet_end_x * 0.7 + thrust_x * 0.3, jet_end_y * 0.7 + thrust_y * 0.3, color: :white, width: 6.0, cap: :round)

  # ホバーボード本体
  Window.draw_rect(
    board_x - board_width * 0.5, board_y - board_height * 0.5,
    board_width, board_height,
    angle: board_angle,
    pivot: :center,
    radius: 10.0,
    color: [30, 38, 55],
    border_width: 3.0,
    border_color: [0, 230, 255]
  )
  # ボード上のステップマーカー
  Window.draw_circle(target_lx, target_ly, 7.0, color: [100, 140, 180])
  Window.draw_circle(target_rx, target_ry, 7.0, color: [0, 230, 255])

  # --- 脚・体の描画 ---
  if show_mesh
    # 【外装（メカパーツ）描画モード】
    # 奥の脚（暗めのトーン）
    draw_mech_leg(thigh_l, calf_l, foot_l, [60, 80, 110], [90, 120, 160])

    # 腰アーマー
    Window.draw_rect(
      hip.x - 35.0, hip.y - 25.0,
      70.0, 30.0,
      angle: hip.angle,
      pivot: :center,
      radius: 8.0,
      color: [45, 55, 75],
      border_width: 2.5,
      border_color: [0, 230, 255]
    )
    Window.draw_circle(hip.x, hip.y, 8.0, color: [0, 230, 255])

    # 手前の脚（明るいネオントーン）
    draw_mech_leg(thigh_r, calf_r, foot_r, [0, 170, 220], [0, 240, 255])
  else
    # 【Bone デバッグ線描画モード】
    # 奥の脚
    Bone.draw_debug([thigh_l, calf_l, foot_l], color: [80, 100, 130], joint_color: [130, 160, 200], width: 4.0, joint_radius: 6.0)
    # 腰
    Window.draw_circle(hip.x, hip.y, 8.0, color: :yellow, border_color: :black, border_width: 1.5)
    # 手前の脚
    Bone.draw_debug([thigh_r, calf_r, foot_r], color: [0, 220, 255], joint_color: :yellow, width: 5.0, joint_radius: 7.0)
  end

  # 接地ポイントのインジケータ
  Window.draw_circle(target_lx, target_ly, 4.0, color: :white)
  Window.draw_circle(target_rx, target_ry, 4.0, color: :white)

  # UIガイダンス表示
  Window.draw_text(20, 20, "Zenoo 2D Inverse Kinematics & Pelvis Grounding Resolver", color: :white, size: 20)
  Window.draw_text(20, 50, "[Mouse Drag] ボード移動 (上下に激しく動かすと足が腰を突き上げ/引き下げます)", color: [180, 210, 240], size: 14)
  Window.draw_text(20, 72, "[W / S] 基本の腰高さ  |  [A / D] ボード傾き  |  [SPACE] 自動ホバリング: #{auto_hover ? 'ON' : 'OFF'}", color: [140, 180, 220], size: 14)
  Window.draw_text(20, 94, "骨盤調停: チルト #{hip.angle.round(1)}° / 腰高さ #{hip.y.round(1)}px  |  [TAB] 表示: #{show_mesh ? 'メカ外装' : 'ボーン線'}", color: [120, 160, 200], size: 13)
end

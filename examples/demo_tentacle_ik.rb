# frozen_string_literal: true
require_relative "../lib/zenoo"

# ====================================================================
# Zenoo 2D Inverse Kinematics (FABRIK) デモ: 多関節 触手クリーチャー
#
# ・FABRIK (Forward And Backward Reaching Inverse Kinematics) 法を採用
# ・角度計算・三角関数・特異点なしで、10〜20関節以上の多関節が破綻せず高速追従
# ・根元固定＋吸盤・節・脈動エフェクトによる有機的なエイリアン触手を表現
#
# 操作方法:
#   マウス移動          : 触手が獲物（カーソル）を追従・捕食
#   マウス左クリック    : エサ（ターゲット球）を設置・ロックオン
#   [W] / [S]           : 関節数（セグメント数）の増減 (6 〜 24関節)
#   [1] / [2] / [3]     : 触手の本数切り替え (1本 / 2本 / 4本)
#   [SPACE]             : 自律うねり（Wiggle）アニメーションの ON / OFF
#   [TAB]               : 生体レンダリング / Bone骨格デバッグ線の切り替え
# ====================================================================

SCREEN_WIDTH = 960
SCREEN_HEIGHT = 640

# ----------------------------------------------------
# FABRIK 触手クラス (Zenoo::Bone.chain & Bone.solve_fabrik を活用)
# ----------------------------------------------------
class FabrikTentacle
  attr_accessor :root_x, :root_y, :segments, :segment_len, :color_skin, :color_glow, :bones

  def initialize(root_x, root_y, count = 14, len = 24.0, skin: [40, 160, 200], glow: [0, 240, 255])
    @root_x = root_x.to_f
    @root_y = root_y.to_f
    @segment_len = len.to_f
    @color_skin = skin
    @color_glow = glow
    @cur_target_x = root_x + count * len * 0.8
    @cur_target_y = root_y + count * len * 0.5
    build_bones(count)
  end

  def build_bones(count)
    @segments = count
    # Bone.chain で直列の多関節ボーンを一括生成 (初期角度 32度方向へ展開)
    @bones = Bone.chain(nil, Array.new(count, @segment_len), x: @root_x, y: @root_y, angle: 32.0, name_prefix: "Tentacle")
  end

  # セグメント数の動的変更
  def set_segment_count(count)
    return if count == @segments
    build_bones(count.clamp(4, 30))
  end

  # FABRIKソルバーの反復実行 (Bone.solve_fabrik)
  def solve(target_x, target_y, iterations: 4, speed: 10.0, dt: 0.016)
    # 先端目標を滑らかに追従させ、急激な直線化（ポッピング）を防止して物理的な「しなり」を生成
    lerp = (speed * dt).clamp(0.0, 1.0)
    @cur_target_x += (target_x - @cur_target_x) * lerp
    @cur_target_y += (target_y - @cur_target_y) * lerp

    @bones[0].x = @root_x
    @bones[0].y = @root_y
    Bone.solve_fabrik(@bones, @cur_target_x, @cur_target_y, iterations: iterations)
  end

  # 生体風レンダリング（Bone.draw_chain によるテーパー付きカプセル ＋ 吸盤・発光体）
  def draw_organic(time_sec)
    n = @segments
    tip_pulse = (Math.sin(time_sec * 8.0) * 0.5 + 0.5)

    # 1. Bone.draw_chain で根元(太)から先端(細)へのテーパー外皮・発光コア・関節球を一括描画
    Bone.draw_chain(
      @bones,
      start_width: 28.0,
      end_width: 8.0,
      color: @color_skin,
      core_ratio: 0.35,
      core_color: @color_glow,
      joint_color: @color_skin
    )

    # 2. 吸盤の描画（各ボーンの法線方向に小丸を配置）
    i = 1
    while i < n - 1
      b = @bones[i]
      p0x = b.world_pivot_x
      p0y = b.world_pivot_y
      p1x = b.tip_world_x
      p1y = b.tip_world_y
      t0 = 1.0 - (i.to_f / n)
      avg_w = 6.0 + t0 * 22.0

      # ボーンの向き (world_cos, world_sin) から法線ベクトル (-sin, cos) を取得
      nx = -b.world_sin
      ny = b.world_cos
      sucker_dist = avg_w * 0.52
      sx = (p0x + p1x) * 0.5 + nx * sucker_dist
      sy = (p0y + p1y) * 0.5 + ny * sucker_dist
      sucker_r = [3.0 + t0 * 5.0, 2.0].max
      Window.draw_circle(sx, sy, sucker_r, color: [220, 240, 255, 220], border_width: 1.5, border_color: @color_skin)
      Window.draw_circle(sx, sy, sucker_r * 0.4, color: [20, 60, 90])
      i += 1
    end

    # 3. 先端の触角・発光センサー
    last_b = @bones[n - 1]
    tip_x = last_b.tip_world_x
    tip_y = last_b.tip_world_y
    Window.draw_circle(tip_x, tip_y, 8.0 + tip_pulse * 4.0, color: [255, 255, 255, 220])
    Window.draw_circle(tip_x, tip_y, 14.0 + tip_pulse * 8.0, color: [@color_glow[0], @color_glow[1], @color_glow[2], 120])
  end

  # デバッグ骨格表示（Bone.draw_debug）
  def draw_debug
    @bones[0].draw_debug(color: @color_glow, joint_color: :yellow, width: 3.0, joint_radius: 5.0)
    last_b = @bones[@segments - 1]
    Window.draw_circle(last_b.tip_world_x, last_b.tip_world_y, 7.0, color: [255, 80, 80], border_width: 1.5, border_color: :white)
  end
end

# ----------------------------------------------------
# シーン初期化
# ----------------------------------------------------
# モンスターの母体コア（画面左側中央）
CORE_X = 140.0
CORE_Y = SCREEN_HEIGHT * 0.5

# 触手リスト
tentacles = [
  FabrikTentacle.new(CORE_X, CORE_Y - 40.0, 14, 25.0, skin: [30, 140, 180], glow: [0, 230, 255]),
  FabrikTentacle.new(CORE_X, CORE_Y,       16, 26.0, skin: [35, 160, 150], glow: [50, 255, 200]),
  FabrikTentacle.new(CORE_X, CORE_Y + 40.0, 14, 25.0, skin: [120, 70, 180], glow: [210, 120, 255]),
  FabrikTentacle.new(CORE_X, CORE_Y + 70.0, 12, 23.0, skin: [180, 80, 120], glow: [255, 130, 180])
]

active_count = 3
show_organic = true
enable_wiggle = true
locked_target = nil
sim_time = 0.0

Window.loop(SCREEN_WIDTH, SCREEN_HEIGHT, "Zenoo - Multi-Joint Tentacle FABRIK IK Demo") do
  dt = 1.0 / 60.0
  sim_time += dt

  # ----------------------------------------------------
  # 入力処理
  # ----------------------------------------------------
  if Input.key_push?(:tab)
    show_organic = !show_organic
  end
  if Input.key_push?(:space)
    enable_wiggle = !enable_wiggle
  end

  # 触手本数の切り替え
  if Input.key_push?(:num1) || Input.key_push?(:one)
    active_count = 1
  elsif Input.key_push?(:num2) || Input.key_push?(:two)
    active_count = 2
  elsif Input.key_push?(:num3) || Input.key_push?(:three)
    active_count = 3
  elsif Input.key_push?(:num4) || Input.key_push?(:four)
    active_count = 4
  end

  # 関節数の増減
  if Input.key_push?(:w)
    tentacles.each { |t| t.set_segment_count(t.segments + 1) }
  elsif Input.key_push?(:s)
    tentacles.each { |t| t.set_segment_count(t.segments - 1) }
  end

  # クリックでエサ（固定ターゲット）の配置 / 解除
  if Input.mouse_push?(:left)
    if locked_target
      # 近くをクリックしたら解除、遠くなら移動
      ldx = Input.mouse_x - locked_target[0]
      ldy = Input.mouse_y - locked_target[1]
      if ldx * ldx + ldy * ldy < 900.0
        locked_target = nil
      else
        locked_target = [Input.mouse_x.to_f, Input.mouse_y.to_f]
      end
    else
      locked_target = [Input.mouse_x.to_f, Input.mouse_y.to_f]
    end
  end

  # マウス右クリックでも解除
  locked_target = nil if Input.mouse_push?(:right)

  # 基準ターゲット位置（エサがあるならそこ、なければマウスカーソル）
  base_target_x = locked_target ? locked_target[0] : Input.mouse_x.to_f
  base_target_y = locked_target ? locked_target[1] : Input.mouse_y.to_f

  # 画面外クランプ
  base_target_x = base_target_x.clamp(0.0, SCREEN_WIDTH.to_f)
  base_target_y = base_target_y.clamp(0.0, SCREEN_HEIGHT.to_f)

  # ----------------------------------------------------
  # FABRIK IK による各触手の計算
  # ----------------------------------------------------
  0.upto(active_count - 1) do |idx|
    t = tentacles[idx]

    # 各触手に少しずつ異なる目標点と自律うねり（うごめき感）を付与
    offset_angle = sim_time * 2.0 + idx * (Math::PI * 0.6)
    wiggle_radius = enable_wiggle ? (16.0 + idx * 8.0) : 0.0

    tx = base_target_x + Math.cos(offset_angle) * wiggle_radius
    ty = base_target_y + Math.sin(offset_angle) * wiggle_radius

    # 触手が複数ある場合、目標の周りを少し囲むようにオフセット
    if active_count > 1
      spread_angle = (idx.to_f / active_count) * Math::PI * 1.4 - 0.7
      tx += Math.sin(spread_angle) * 35.0
      ty += Math.cos(spread_angle) * 35.0
    end

    # FABRIK法を一発実行（3〜4回の反復で滑らかに収束）
    t.solve(tx, ty, iterations: 4, dt: dt)
  end

  # ----------------------------------------------------
  # 描画処理
  # ----------------------------------------------------
  Window.clear([12, 16, 26])

  # 深海・サイバー空間の背景グリッド
  (0..SCREEN_WIDTH).step(40) { |gx| Window.draw_line(gx, 0, gx, SCREEN_HEIGHT, color: [20, 26, 42, 255], width: 1.0) }
  (0..SCREEN_HEIGHT).step(40) { |gy| Window.draw_line(0, gy, SCREEN_WIDTH, gy, color: [20, 26, 42, 255], width: 1.0) }

  # 母体コア（生物の本体・眼球）の描画
  pulse = Math.sin(sim_time * 3.0) * 4.0
  core_r = 55.0 + pulse
  Window.draw_circle(CORE_X - 20.0, CORE_Y, core_r + 8.0, color: [20, 40, 60, 180])
  Window.draw_circle(CORE_X - 20.0, CORE_Y, core_r, color: [30, 45, 70], border_width: 3.5, border_color: [0, 230, 255])
  # 巨大なコアアイ（瞳孔がマウスをじっと見つめる）
  eye_dx = base_target_x - (CORE_X - 20.0)
  eye_dy = base_target_y - CORE_Y
  eye_dist = Math.sqrt(eye_dx * eye_dx + eye_dy * eye_dy)
  eye_len = [eye_dist, 14.0].min
  pupil_x = (CORE_X - 20.0) + (eye_dist > 0.001 ? (eye_dx / eye_dist) * eye_len : 0.0)
  pupil_y = CORE_Y + (eye_dist > 0.001 ? (eye_dy / eye_dist) * eye_len : 0.0)
  Window.draw_circle(pupil_x, pupil_y, 16.0, color: [0, 240, 255])
  Window.draw_circle(pupil_x, pupil_y, 8.0, color: [10, 20, 35])
  Window.draw_circle(pupil_x + 4.0, pupil_y - 4.0, 3.5, color: :white)

  # 触手本体の描画
  (active_count - 1).downto(0) do |idx|
    t = tentacles[idx]
    if show_organic
      t.draw_organic(sim_time + idx * 1.5)
    else
      t.draw_debug
    end
  end

  # エサ（ロックオンターゲット）の描画
  if locked_target
    Window.draw_circle(locked_target[0], locked_target[1], 12.0 + Math.sin(sim_time * 10.0) * 3.0, color: [255, 100, 120, 160])
    Window.draw_circle(locked_target[0], locked_target[1], 6.0, color: [255, 230, 120])
    Window.draw_text(locked_target[0] - 28, locked_target[1] - 30, "[BAIT]", color: [255, 180, 180], size: 12)
  else
    # カーソルターゲットリング
    Window.draw_circle(Input.mouse_x, Input.mouse_y, 9.0 + Math.sin(sim_time * 6.0) * 2.0, color: [0, 240, 255, 100], border_width: 1.5, border_color: :white)
  end

  # UIガイダンス表示
  Window.draw_text(20, 20, "Zenoo Multi-Joint Tentacle (FABRIK IK)", color: :white, size: 20)
  Window.draw_text(20, 48, "[Mouse] 獲物を追従  |  [Left Click] エサを設置/解除", color: [180, 210, 240], size: 14)
  Window.draw_text(20, 70, "[1..4] 触手の本数: #{active_count}本  |  [W / S] 関節数: #{tentacles[0].segments}関節", color: [140, 180, 220], size: 14)
  Window.draw_text(20, 92, "[SPACE] 自律うねり: #{enable_wiggle ? 'ON' : 'OFF'}  |  [TAB] 表示: #{show_organic ? '生体レンダリング' : 'Bone骨格線'}", color: [120, 160, 200], size: 14)
end

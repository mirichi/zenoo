# frozen_string_literal: true
require_relative "../lib/zenoo"

# ====================================================================
# Zenoo 2D SkinnedMesh & Bone デモ
# 1. 多関節チェーン (自動ウェイト生成・触手/尻尾)
# 2. 2ボーン + 白黒グラデーション Image による関節スキニング (腕)
# 3. 4ボーン + RGBA 4色ウェイトマップ Image による分岐スキニング (星型クリーチャー)
# ====================================================================

# ----------------------------------------------------
# 1. 触手・リボン用のテクスチャ生成 (320 x 48)
# ----------------------------------------------------
tentacle_img = Image.new(320, 48)
Image.render_to(tentacle_img) do
  Window.clear(:clear)
  # 本体カプセル
  Window.draw_rect(4, 6, 312, 36, radius: 18, color: [40, 180, 220, 255], border_width: 3, border_color: [180, 245, 255, 255])
  # 模様の吸盤・節
  10.times do |i|
    cx = 24 + i * 30
    Window.draw_circle(cx, 24, 9, color: [20, 110, 160, 255], border_width: 2, border_color: [120, 220, 250, 255])
  end
end

# 5関節のボーンチェーンを作成 (80px 間隔 × 4区間 = 320px)
t_b0 = Bone.new(80, 200, length: 80)
t_b1 = Bone.new(80, 0, length: 80, parent: t_b0)
t_b2 = Bone.new(80, 0, length: 80, parent: t_b1)
t_b3 = Bone.new(80, 0, length: 80, parent: t_b2)
t_b4 = Bone.new(80, 0, length: 0,  parent: t_b3)
tentacle_bones = [t_b0, t_b1, t_b2, t_b3, t_b4]

# weight_map 省略で自動生成！
tentacle_skin = SkinnedMesh.new(
  tentacle_img,
  bones: tentacle_bones,
  div_x: 32,
  div_y: 4,
  anchor: :center_left
)

# ----------------------------------------------------
# 2. 2ボーン + 白黒グラデーション Image による腕スキニング (240 x 56)
# ----------------------------------------------------
arm_img = Image.new(240, 56)
Image.render_to(arm_img) do
  Window.clear(:clear)
  # 上腕〜前腕のイラスト
  Window.draw_rect(4, 8, 232, 40, radius: 20, color: [235, 130, 70, 255], border_width: 3, border_color: [255, 210, 170, 255])
  Window.draw_line(20, 28, 220, 28, width: 6, cap: :round, color: [255, 180, 120, 180])
  Window.draw_circle(120, 28, 10, color: [200, 90, 40, 255])
end

# 白黒グラデーションの重みマップを Image で作成 (黒=上腕100%, 白=前腕100%)
arm_weight_img = Image.new(240, 16)
240.times do |x|
  # 肘 (x=120) 周辺 (80..160) で黒(0)から白(255)へ滑らかに変化するグラデーション
  t = ((x - 80.0) / 80.0).clamp(0.0, 1.0)
  # smoothstep
  s = t * t * (3.0 - 2.0 * t)
  c = (s * 255).round
  16.times do |y|
    arm_weight_img[x, y] = [c, c, c, 255]
  end
end
arm_weight_img.sync

upper_arm = Bone.new(80, 440, length: 120)
lower_arm = Bone.new(120, 0, length: 120, parent: upper_arm)
# 手のひらに持たせる通常 Sprite (剣) - 同じボーン階層に混在可能！
sword_img = Image.new(90, 24)
Image.render_to(sword_img) do
  Window.clear(:clear)
  Window.draw_rect(0, 8, 20, 8, radius: 3, color: [160, 110, 50, 255])
  Window.draw_rect(16, 2, 8, 20, radius: 2, color: :yellow)
  Window.draw_triangle(24, 4, 24, 20, 88, 12, color: [:white, :cyan, :white])
end
hand_bone = Bone.new(110, 0, parent: lower_arm)
sword_sprite = Sprite.new(0, 0, sword_img, anchor: :center_left, pivot: :center_left, parent: hand_bone)

arm_skin = SkinnedMesh.new(
  arm_img,
  bones: [upper_arm, lower_arm],
  weight_map: arm_weight_img,
  weight_mode: :gradient,
  div_x: 24,
  div_y: 4,
  anchor: :center_left
)

# ----------------------------------------------------
# 3. 4ボーン + RGBA 4色塗り分けによる分岐スキニング (220 x 220)
# ----------------------------------------------------
star_img = Image.new(220, 220)
Image.render_to(star_img) do
  Window.clear(:clear)
  # 十字型の軟体キャラクター
  Window.draw_rect(75, 10, 70, 200, radius: 32, color: [170, 90, 240, 255], border_width: 3, border_color: :white)
  Window.draw_rect(10, 75, 200, 70, radius: 32, color: [170, 90, 240, 255], border_width: 3, border_color: :white)
  Window.draw_circle(110, 110, 42, color: [190, 110, 250, 255])
  # 目
  Window.draw_circle(95, 105, 8, color: :white)
  Window.draw_circle(125, 105, 8, color: :white)
  Window.draw_circle(95, 105, 4, color: :black)
  Window.draw_circle(125, 105, 4, color: :black)
end

# 中心(胴体)を親として、上・左・右の3本の枝ボーンを分岐配置
# 各ボーンの先端が枝の先を向くように angle を設定
b_center = Bone.new(820, 360, angle: 90, length: 60)   # 中心〜下方向 (R=赤)
b_top    = Bone.new(-45, 0, angle: -180, length: 50, parent: b_center) # 上方向: (820, 315) から上へ (G=緑)
b_left   = Bone.new(0, 45,  angle: 90,   length: 50, parent: b_center) # 左方向: (775, 360) から左へ (B=青)
b_right  = Bone.new(0, -45, angle: -90,  length: 50, parent: b_center) # 右方向: (865, 360) から右へ (A=透明)
star_bones = [b_center, b_top, b_left, b_right]

# 自動生成された RGBA 4チャンネルのウェイトマップを使用
star_skin = SkinnedMesh.new(
  star_img,
  bones: star_bones,
  weight_mode: :rgba,
  div_x: 20,
  div_y: 20,
  anchor: :center
)

show_bones = true
show_weights = true

Window.loop(1100, 650, "Zenoo 2D SkinnedMesh & Bone Demo") do
  Window.clear([20, 24, 34, 255])
  t = Window.time

  if Input.key_push?(:space)
    show_bones = !show_bones
  end
  if Input.key_push?(:w)
    show_weights = !show_weights
  end

  # 1. 多関節触手のアニメーション
  t_b0.angle = Math.sin(t * 2.2) * 20.0
  t_b1.angle = Math.sin(t * 2.2 - 0.7) * 28.0
  t_b2.angle = Math.sin(t * 2.2 - 1.4) * 35.0
  t_b3.angle = Math.sin(t * 2.2 - 2.1) * 42.0

  # 2. 腕 + 剣のアニメーション
  upper_arm.angle = Math.sin(t * 1.8) * 25.0 - 10.0
  lower_arm.angle = (Math.sin(t * 3.6) * 0.5 + 0.5) * -85.0 + 10.0
  hand_bone.angle = Math.sin(t * 5.4) * 25.0

  # 3. 4ボーン分岐キャラクターのアニメーション
  b_center.y = 360.0 + Math.sin(t * 2.5) * 12.0
  b_center.angle = 90.0 + Math.sin(t * 1.5) * 12.0
  b_top.angle    = -180.0 + Math.sin(t * 3.5) * 35.0
  b_left.angle   = 90.0 + Math.sin(t * 4.0) * 35.0
  b_right.angle  = -90.0 - Math.sin(t * 4.0) * 35.0

  # 描画
  tentacle_skin.draw
  arm_skin.draw
  sword_sprite.draw
  star_skin.draw

  # ボーン構造のデバッグ可視化
  if show_bones
    t_b0.draw_debug(color: :cyan, joint_color: :yellow)
    upper_arm.draw_debug(color: :green, joint_color: :yellow)
    b_center.draw_debug(color: :magenta, joint_color: :yellow)
  end

  # ウェイトマップのプレビュー表示
  if show_weights
    Window.draw_text(480, 150, "自動生成ウェイト(Chain)", size: 15, color: [180, 200, 220, 255])
    Window.draw_image(480, 175, tentacle_skin.weight_map, scale_x: 2.0, scale_y: 0.5)

    Window.draw_text(480, 390, "白黒グラデーションImage", size: 15, color: [180, 200, 220, 255])
    Window.draw_image(480, 415, arm_weight_img, scale_x: 0.6, scale_y: 2.0)

    Window.draw_text(760, 500, "RGBA 4色ウェイトマップ (R/G/B/A)", size: 15, color: [180, 200, 220, 255])
    Window.draw_image(820, 525, star_skin.weight_map, scale: 1.2)
  end

  # UI ガイド
  Window.draw_text(30, 25, "Zenoo 2D SkinnedMesh & Bone (頂点シェーダースキニング)", size: 24, color: :white)
  Window.draw_text(30, 60, "[SPACE] ボーン表示 ON/OFF   [W] ウェイトマップ表示 ON/OFF", size: 16, color: :cyan)

  Window.draw_text(60, 105, "① 5ボーン多関節チェーン (重み省略・自動生成)", size: 18, color: :yellow)
  Window.draw_text(60, 340, "② 2ボーン + 白黒グラデーションImage + 通常Sprite(剣)混在", size: 18, color: :yellow)
  Window.draw_text(680, 180, "③ 4ボーン親子分岐 + RGBA 4チャンネル重み", size: 18, color: :yellow)
end

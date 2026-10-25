# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - 多関節スプライト (2Dボーン & 親子階層コライダー同期) デモ
#
# 特徴:
#   1. 階層化されたSprite構造:
#      Body (胴体)
#      ├── Head (頭部)
#      ├── Left Arm (肩 -> 肘 -> シールド[Circleコライダー])
#      ├── Right Arm (肩 -> 肘 -> 大剣[Rectコライダー])
#      └── Legs (左右の太もも -> 膝)
#   2. 親の移動・回転・拡縮がすべての関節と武器・防具のコライダーへ完全同期
#   3. 各関節はアンカー・ピボット基準で自然に回転 (肘を曲げる、剣を振るなど)
#
# 操作方法:
#   - マウス移動: 胴体 (Body) の移動
#   - [Q] / [E] キー または [A] / [D]: 胴体の全体回転
#   - [W] / [S] キー: 全体の拡大 / 縮小
#   - マウスクリック / [SPACE]: 剣を素早くスイング攻撃！
#   - [C] キー: コライダー枠線の表示 / 非表示
# ==============================================================================

# ----------------------------------------------------
# 各関節パーツ画像の自立生成 (Image.render_to)
# ----------------------------------------------------
def create_body_image
  img = Image.new(64, 80)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # 胴体アーマー (サイバーネイビー & ゴールドフレーム)
    Window.draw_rect(6, 6, 52, 68, radius: 12, color: [38, 52, 85, 255], border_width: 2, border_color: [0, 220, 255, 255])
    # コアクリスタル
    Window.draw_circle(32, 40, 10, color: [0, 240, 255, 255], shadow_blur: 8, shadow_color: [0, 200, 255, 180])
    Window.draw_circle(32, 40, 5, color: :white)
  end
  img
end

def create_head_image
  img = Image.new(40, 40)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # ヘルメット
    Window.draw_circle(20, 20, 16, color: [48, 64, 105, 255], border_width: 2, border_color: [0, 220, 255, 255])
    # バイザー
    Window.draw_rect(10, 16, 20, 7, radius: 3, color: [0, 255, 200, 255], shadow_blur: 5, shadow_color: [0, 255, 200, 150])
  end
  img
end

def create_limb_image(w, h, color)
  img = Image.new(w, h)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # 関節カプセル
    Window.draw_rect(2, 2, w - 4, h - 4, radius: [w, h].min * 0.45, color: color, border_width: 1.5, border_color: [180, 210, 240, 200])
    # 回転軸マーカー (関節ピボット位置の目印)
    Window.draw_circle(w * 0.5, [w, h].min * 0.5, 3, color: [0, 220, 255, 255])
  end
  img
end

def create_sword_image
  img = Image.new(24, 110)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # 刀身 (光るビームブレード)
    Window.draw_rect(7, 4, 10, 84, radius: 4, color: [255, 70, 130, 255], border_width: 1.5, border_color: :white, shadow_blur: 10, shadow_color: [255, 50, 120, 200])
    # 鍔 (ツバ)
    Window.draw_rect(2, 86, 20, 6, radius: 2, color: [240, 200, 70, 255])
    # 柄 (グリップ)
    Window.draw_rect(9, 92, 6, 16, radius: 2, color: [70, 75, 90, 255])
  end
  img
end

def create_shield_image
  img = Image.new(56, 56)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # エナジーシールド
    Window.draw_circle(28, 28, 24, color: [0, 180, 255, 120], border_width: 2.5, border_color: [100, 240, 255, 255], shadow_blur: 8, shadow_color: [0, 180, 255, 180])
    Window.draw_circle(28, 28, 12, color: [0, 240, 255, 180])
  end
  img
end

def create_target_image
  img = Image.new(48, 48)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # 浮遊ターゲット (オーブ)
    Window.draw_circle(24, 24, 20, color: [255, 160, 40, 230], border_width: 2, border_color: :white, shadow_blur: 6, shadow_color: [255, 140, 20, 180])
    Window.draw_circle(18, 18, 5, color: :white)
  end
  img
end

# ----------------------------------------------------
# 多関節キャラクターの構築
# ----------------------------------------------------
@body_img      = create_body_image
@head_img      = create_head_image
@upper_arm_img = create_limb_image(16, 46, [60, 80, 120, 255])
@forearm_img   = create_limb_image(14, 42, [80, 105, 150, 255])
@thigh_img     = create_limb_image(18, 50, [50, 65, 100, 255])
@shin_img      = create_limb_image(16, 48, [70, 90, 135, 255])
@sword_img     = create_sword_image
@shield_img    = create_shield_image
@target_img    = create_target_image

# 1. 胴体 (ルート)
@body = Sprite.new(640, 380, @body_img, anchor: :center, pivot: :center)

# 2. 頭部 (胴体の上端に接続)
@head = Sprite.new(0, -38, @head_img, anchor: :bottom_center, pivot: :bottom_center, parent: @body)

# 3. 左腕 (シールド装備腕)
# 肩関節: 胴体左肩(-22, -18) に top_center で接続
@arm_l1 = Sprite.new(-22, -18, @upper_arm_img, anchor: :top_center, pivot: :top_center, parent: @body)
# 肘関節: 上腕先端(0, 38) に接続
@arm_l2 = Sprite.new(0, 38, @forearm_img, anchor: :top_center, pivot: :top_center, parent: @arm_l1)
# シールド: 前腕下部(0, 36) に中心アンカーで接続
@shield = Sprite.new(0, 36, @shield_img, anchor: :center, pivot: :center, parent: @arm_l2)
@shield.set_collider(:circle, radius: 24)

# 4. 右腕 (大剣装備腕)
# 肩関節: 胴体右肩(22, -18) に top_center で接続
@arm_r1 = Sprite.new(22, -18, @upper_arm_img, anchor: :top_center, pivot: :top_center, parent: @body)
# 肘関節: 上腕先端(0, 38) に接続
@arm_r2 = Sprite.new(0, 38, @forearm_img, anchor: :top_center, pivot: :top_center, parent: @arm_r1)
# 刀剣: 前腕手首(0, 36) に柄の部分(anchor: [0.5, 0.9])で接続
@sword = Sprite.new(0, 36, @sword_img, anchor: [0.5, 0.9], pivot: [0.5, 0.9], parent: @arm_r2)
# 刀身部分に矩形コライダーを設定 (オフセットで刀身の重心に配置)
@sword.set_collider(:rect, width: 14, height: 86, offset_y: -42)

# 5. 脚部 (左右)
@leg_l1 = Sprite.new(-16, 32, @thigh_img, anchor: :top_center, pivot: :top_center, parent: @body)
@leg_l2 = Sprite.new(0, 42, @shin_img, anchor: :top_center, pivot: :top_center, parent: @leg_l1)

@leg_r1 = Sprite.new(16, 32, @thigh_img, anchor: :top_center, pivot: :top_center, parent: @body)
@leg_r2 = Sprite.new(0, 42, @shin_img, anchor: :top_center, pivot: :top_center, parent: @leg_r1)

# キャラクター構成パーツの描画順 (脚/胴体奥 -> 胴体 -> 腕/武器手前)
@character_parts = [
  @leg_l1, @leg_l2, @leg_r1, @leg_r2,
  @body, @head,
  @arm_l1, @arm_l2, @shield,
  @arm_r1, @arm_r2, @sword
]

# 浮遊ターゲット群
@targets = []
reset_targets = lambda do
  @targets.clear
  8.times do |i|
    ang = i * (Math::PI * 2.0 / 8.0)
    dist = rand(220..320)
    tx = 640 + Math.cos(ang) * dist
    ty = 360 + Math.sin(ang) * dist
    t = Sprite.new(tx, ty, @target_img, anchor: :center, pivot: :center)
    t.set_collider(:circle, radius: 20)
    @targets << t
  end
end
reset_targets.call

@show_colliders = true
@sword_swing = 0.0
@time = 0.0

# ==============================================================================
# メインゲームループ
# ==============================================================================
Window.loop(1280, 720, "Zenoo - Articulated Sprite & Hierarchical Collision Demo") do
  @time += 0.035

  # 入力処理
  mx = Input.mouse_x
  my = Input.mouse_y

  # 胴体位置をマウスへスムーズに追従
  @body.x += (mx - @body.x) * 0.08
  @body.y += (my - @body.y) * 0.08

  # [Q] / [E] または [A] / [D] でキャラクター全体の自転
  @body.angle += 2.5 if Input.key_pressed?(:e) || Input.key_pressed?(:d)
  @body.angle -= 2.5 if Input.key_pressed?(:q) || Input.key_pressed?(:a)

  # [W] / [S] でキャラクター全体のスケール変更 (すべての関節が正しく拡大縮小)
  @body.scale_x = [@body.scale_x + 0.02, 2.5].min if Input.key_pressed?(:w)
  @body.scale_x = [@body.scale_x - 0.02, 0.5].max if Input.key_pressed?(:s)
  @body.scale_y = @body.scale_x

  # 剣のスイング攻撃 (クリック / SPACE)
  if Input.mouse_push?(:left) || Input.key_push?(:space)
    @sword_swing = 1.0
  end

  if @sword_swing > 0.0
    @sword_swing = [@sword_swing - 0.06, 0.0].max
    swing_ratio = Math.sin(@sword_swing * Math::PI)
    # 斬撃モーション: 肩と肘と手首が連動して大きく前方に一閃！
    @arm_r1.angle = -40.0 + swing_ratio * 110.0
    @arm_r2.angle = 20.0 + swing_ratio * 50.0
    @sword.angle  = -20.0 + swing_ratio * 70.0
  else
    # 通常のアイドルモーション (呼吸・構えの揺れ)
    idle_wave = Math.sin(@time * 2.0)
    @arm_r1.angle = -25.0 + idle_wave * 8.0
    @arm_r2.angle = 45.0  + idle_wave * 12.0
    @sword.angle  = 15.0  + idle_wave * 5.0
  end

  # 左腕 (シールド側): ゆらゆらと防御姿勢を維持
  shield_wave = Math.cos(@time * 2.0)
  @arm_l1.angle = 30.0 + shield_wave * 6.0
  @arm_l2.angle = -35.0 - shield_wave * 8.0
  @shield.angle = -shield_wave * 15.0

  # 頭部: わずかに上下に頷く
  @head.angle = Math.sin(@time * 1.5) * 4.0

  # 脚部: 待機歩行ステップ (左右交互)
  walk_l = Math.sin(@time * 3.0)
  walk_r = Math.sin(@time * 3.0 + Math::PI)
  @leg_l1.angle = walk_l * 12.0
  @leg_l2.angle = [walk_l * 15.0, 0.0].max # 膝は後ろ向きにのみ曲がる
  @leg_r1.angle = walk_r * 12.0
  @leg_r2.angle = [walk_r * 15.0, 0.0].max

  # コライダー表示切り替え & ターゲット再配置
  @show_colliders = !@show_colliders if Input.key_push?(:c)
  reset_targets.call if Input.key_push?(:r)

  # ターゲットの浮遊アニメーション
  @targets.each_with_index do |t, i|
    t.y += Math.sin(@time * 2.5 + i) * 0.4
    t.angle += 0.5
  end

  # 衝突判定 (大剣 & シールド vs ターゲット群)
  # 親がどんなに回転・拡大縮小・スイングしていても、自動でワールド同期されます！
  sword_hit_count = 0
  shield_hit_count = 0

  @targets.each do |target|
    hit_by_sword  = @sword.collide?(target)
    hit_by_shield = @shield.collide?(target)

    if hit_by_sword
      # 剣で斬撃中: 赤く激しく発光 & 弾き飛ばし
      target.color = [255, 60, 80, 255]
      sword_hit_count += 1
      target.x += Math.cos(@sword.world_angle * Math::PI / 180.0) * 3.0
      target.y += Math.sin(@sword.world_angle * Math::PI / 180.0) * 3.0
    elsif hit_by_shield
      # シールドで防御中: シアンに発光
      target.color = [0, 240, 255, 255]
      shield_hit_count += 1
      target.push_out_of(@shield)
    else
      target.color = :white
    end
  end

  # 描画処理
  Window.clear([16, 20, 32, 255])

  # 背景グリッド
  (0..1280).step(80) { |gx| Window.draw_line(gx, 0, gx, 720, color: [24, 32, 50, 255], width: 1.0) }
  (0..720).step(80)  { |gy| Window.draw_line(0, gy, 1280, gy, color: [24, 32, 50, 255], width: 1.0) }

  # ターゲットスプライト描画
  Sprite.draw(@targets)

  # 多関節キャラの一括描画
  Sprite.draw(@character_parts)

  # コライダー幾何形状の可視化デバッグ描画 (トグル [C])
  if @show_colliders
    # ターゲットコライダー
    @targets.each do |t|
      col = t.collider
      Window.draw_circle(col.center_x, col.center_y, col.radius * t.world_scale_x,
                        color: [255, 160, 40, 30], border_color: [255, 180, 50, 200], border_width: 1.5)
    end

    # 剣のコライダー (矩形)
    s_col = @sword.collider
    Window.draw_rect(s_col.center_x - s_col.half_w * @sword.world_scale_x,
                     s_col.center_y - s_col.half_h * @sword.world_scale_y,
                     s_col.width * @sword.world_scale_x, s_col.height * @sword.world_scale_y,
                     angle: s_col.angle,
                     color: [255, 50, 100, 40], border_color: [255, 80, 140, 240], border_width: 1.5)

    # シールドのコライダー (円)
    sh_col = @shield.collider
    Window.draw_circle(sh_col.center_x, sh_col.center_y, sh_col.radius * @shield.world_scale_x,
                      color: [0, 200, 255, 40], border_color: [0, 240, 255, 240], border_width: 1.5)
  end

  # UI / ガイド表示
  Window.draw_text(24, 20, "Zenoo 2D Articulated Sprite & Hierarchical Collision", font: Font::MPLUS, size: 26, color: :white)
  Window.draw_text(24, 56, "Sword Hits: #{sword_hit_count}  |  Shield Blocks: #{shield_hit_count}", font: Font::SINCLAIR, size: 16, color: (sword_hit_count > 0 ? [255, 90, 120, 255] : [100, 240, 180, 255]))
  Window.draw_text(24, 80, "Body Scale: #{@body.scale_x.round(2)}x  |  Body Angle: #{@body.angle.round(1)} deg  |  Colliders [C]: #{@show_colliders ? 'ON' : 'OFF'}", font: Font::SINCLAIR, size: 14, color: [170, 185, 210, 255])
  Window.draw_text(24, 680, "Controls: Mouse Move | Click / [SPACE]: Sword Slash | [Q][E] / [A][D]: Rotate Body | [W][S]: Scale Body | [R]: Reset Targets", font: Font::SINCLAIR, size: 14, color: [130, 145, 170, 255])
end

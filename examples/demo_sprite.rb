# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - Sprite & Collision 同期ショーケース
#
# 実装された機能:
#   1. Zenoo::Sprite クラス (x, y, angle, scale, pivot, collider)
#   2. Window.draw_sprite による一括・個別描画
#   3. 回転・不等スケール・ピボット変形と完全に同期した衝突判定 (Collision 連携)
#   4. 各種コライダー (Rect, Circle) の切り替え
#
# 操作方法:
#   - マウス移動 / ドラッグ: プレイヤースプライトの移動
#   - マウスホイール / [Q][E] キー: スプライトの回転
#   - [W][S] キー: スプライトの拡大・縮小
#   - [C] キー: コライダー境界線の表示 / 非表示
#   - [SPACE]: ターゲットのランダム再配置
# ==============================================================================

# ----------------------------------------------------
# 自立生成スプライト画像
# ----------------------------------------------------
def create_ship_image
  img = Image.new(80, 80)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # 船体 (シアン)
    Window.draw_triangle(70, 40, 15, 20, 15, 60, color: [0, 220, 255, 255])
    # コックピット (イエロー)
    Window.draw_triangle(60, 40, 30, 32, 30, 48, color: [255, 230, 70, 255])
    # 翼 (オレンジ)
    Window.draw_triangle(40, 25, 10, 8, 18, 26, color: [255, 120, 30, 255])
    Window.draw_triangle(40, 55, 18, 54, 10, 72, color: [255, 120, 30, 255])
    # コア
    Window.draw_circle(32, 40, 6, color: [255, 255, 255, 255])
  end
  img
end

def create_gem_image
  img = Image.new(50, 50)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # ひし形 / 宝石
    Window.draw_triangle(25, 5, 45, 25, 5, 25, color: [180, 100, 255, 255])
    Window.draw_triangle(25, 45, 5, 25, 45, 25, color: [130, 50, 220, 255])
    Window.draw_triangle(25, 12, 38, 25, 12, 25, color: [220, 160, 255, 255])
  end
  img
end

def create_orb_image
  img = Image.new(60, 60)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])
    # 球体
    Window.draw_circle(30, 30, 26, color: [50, 220, 120, 255])
    Window.draw_circle(24, 24, 12, color: [160, 255, 200, 255])
    Window.draw_circle(20, 20, 5, color: [255, 255, 255, 255])
  end
  img
end

# ----------------------------------------------------
# 初期化 (Window.loop 前に画像・スプライトを生成)
# ----------------------------------------------------
@ship_img = create_ship_image
@gem_img  = create_gem_image
@orb_img  = create_orb_image

# プレイヤー
@player = Sprite.new(600, 320, @ship_img)
@player.pivot = :center

# ターゲット群 (Rect と Circle コライダー混在)
@targets = []
recreate_targets = lambda do
  @targets.clear
  6.times do |i|
    s = Sprite.new(200 + (i % 3) * 350, 150 + (i / 3) * 300, @gem_img)
    s.pivot = :center
    s.angle = rand(0..360)
    s.scale = rand(0.9..1.3)
    @targets << s
  end
  4.times do |i|
    s = Sprite.new(350 + (i % 2) * 450, 220 + (i / 2) * 220, @orb_img)
    s.pivot = :center
    s.set_collider(:circle, radius: 26)
    s.scale = rand(0.9..1.2)
    @targets << s
  end
end

recreate_targets.call
@recreate_targets = recreate_targets
@show_colliders = true

# ----------------------------------------------------
# メインループ
# ----------------------------------------------------
Window.loop(1280, 720, "Zenoo - Sprite & Collision Synchronization Demo") do

  # 入力処理
  mx = Input.mouse_x
  my = Input.mouse_y

  # プレイヤー位置をマウスへ追従 (滑らかに補間)
  @player.x += (mx - @player.x - 40) * 0.15
  @player.y += (my - @player.y - 40) * 0.15

  # キー操作: 回転と拡大
  @player.angle += 3.0 if Input.key_pressed?(:e) || Input.key_pressed?(:right)
  @player.angle -= 3.0 if Input.key_pressed?(:q) || Input.key_pressed?(:left)
  @player.scale_x = [@player.scale_x + 0.02, 2.5].min if Input.key_pressed?(:w) || Input.key_pressed?(:up)
  @player.scale_x = [@player.scale_x - 0.02, 0.4].max if Input.key_pressed?(:s) || Input.key_pressed?(:down)
  @player.scale_y = @player.scale_x

  # ターゲットの自転
  @targets.each_with_index do |t, idx|
    t.angle += (idx.even? ? 0.8 : -0.8)
  end

  # コライダー表示切り替え / 再配置
  @show_colliders = !@show_colliders if Input.key_push?(:c)
  @recreate_targets.call if Input.key_push?(:space)

  # 画面クリア (ダークネイビー)
  Window.clear([16, 22, 36, 255])

  # グリッド描画 (背景)
  Window.draw_rect(0, 0, 1280, 720, color: [20, 28, 46, 255])
  (0..1280).step(80) { |gx| Window.draw_line(gx, 0, gx, 720, color: [30, 42, 68, 255], width: 1.0) }
  (0..720).step(80)  { |gy| Window.draw_line(0, gy, 1280, gy, color: [30, 42, 68, 255], width: 1.0) }

  # 衝突判定とターゲットの色設定
  hit_count = 0
  @targets.each do |target|
    if @player.collide?(target)
      # 衝突中: レッドハイライト
      target.color = [255, 90, 100, 255]
      hit_count += 1
    else
      target.color = :white
    end
  end

  # スプライトの一括描画 (Window.draw_sprite)
  Window.draw_sprite(@targets)
  Window.draw_sprite(@player)

  # コライダー幾何形状の可視化デバッグ描画 (トグル表示)
  if @show_colliders
    # ターゲットコライダー
    @targets.each do |target|
      col = target.collider
      if col.is_a?(Collision::Circle)
        Window.draw_circle(col.center_x, col.center_y, col.radius * target.scale_x,
                          color: [0, 255, 180, 40],
                          border_color: [0, 255, 180, 220],
                          border_width: 1.5)
      elsif col.is_a?(Collision::Rect)
        Window.draw_rect(col.center_x - col.half_w * target.scale_x, col.center_y - col.half_h * target.scale_y,
                         col.width * target.scale_x, col.height * target.scale_y,
                         angle: col.angle,
                         color: [255, 200, 0, 40],
                         border_color: [255, 220, 50, 200],
                         border_width: 1.5)
      end
    end

    # プレイヤーコライダー
    p_col = @player.collider
    Window.draw_rect(p_col.center_x - p_col.half_w * @player.scale_x, p_col.center_y - p_col.half_h * @player.scale_y,
                     p_col.width * @player.scale_x, p_col.height * @player.scale_y,
                     angle: p_col.angle,
                     color: [0, 220, 255, 40],
                     border_color: [0, 240, 255, 220],
                     border_width: 1.5)
  end

  # UI / 情報表示
  status_color = hit_count > 0 ? [255, 100, 100, 255] : [100, 255, 180, 255]
  Window.draw_text(24, 20, "Zenoo Sprite & Collision Synchronization", font: Font::MPLUS, size: 28, color: :white)
  Window.draw_text(24, 58, "Colliding Targets: #{hit_count} / #{@targets.length}", font: Font::SINCLAIR, size: 16, color: status_color)
  Window.draw_text(24, 82, "Player Angle: #{@player.angle.round(1)} deg  Scale: #{@player.scale_x.round(2)}x  [C]: Collider Mesh (#{@show_colliders ? 'ON' : 'OFF'})", font: Font::SINCLAIR, size: 14, color: [180, 190, 210, 255])
  Window.draw_text(24, 680, "Controls: Mouse to Move | [Q][E] / Wheel to Rotate | [W][S] to Scale | [SPACE] to Reset", font: Font::SINCLAIR, size: 14, color: [140, 150, 170, 255])
end

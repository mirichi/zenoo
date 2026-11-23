# frozen_string_literal: true

require_relative '../lib/zenoo'

# ====================================================================
# Zenoo::GameScene デモ - オブジェクト管理 + 2層(Game/UI) + シーン連携
# ====================================================================
# GameScene が提供する「ゲーム制作の基本レール」の実例:
# - add(sprite)    : 単体スプライトの登録 (自動 update / draw / vanish 除去)
# - sprite_list    : グループ配列 (敵・弾など) の登録 (<< で追加、Sprite.check にそのまま渡せる)
# - camera         : Game レイヤーに自動適用されるカメラ (target 追従・画面シェイク・bounds)
# - ui             : UI レイヤーに自動配置される UI::Stage (UI クリック時はゲーム側のクリックを自動ブロック)
# - draw_game      : カメラ座標系 (ワールド) の背景・フィールド描画
# - draw_ui        : スクリーン固定座標系の HUD 描画
# ====================================================================

WORLD_W = 2000.0
WORLD_H = 1400.0

# --------------------------------------------------------------------
# テクスチャ生成ヘルパー
# --------------------------------------------------------------------
module Assets
  def self.player_image
    return @player_image if @player_image
    img = Image.new(36, 36)
    Image.render_to(img) do
      Window.draw_circle(18, 18, 16, color: [56, 189, 248, 255], border_width: 3, border_color: :white)
      Window.draw_rect(20, 14, 14, 8, radius: 3, color: :white)
    end
    @player_image = img
  end

  def self.bullet_image
    return @bullet_image if @bullet_image
    img = Image.new(14, 14)
    Image.render_to(img) do
      Window.draw_circle(7, 7, 6, color: [250, 204, 21, 255], border_width: 2, border_color: :white)
    end
    @bullet_image = img
  end

  def self.enemy_image
    return @enemy_image if @enemy_image
    img = Image.new(34, 34)
    Image.render_to(img) do
      Window.draw_rect(3, 3, 28, 28, radius: 7, color: [244, 63, 94, 255], border_width: 2, border_color: [255, 228, 230, 255])
    end
    @enemy_image = img
  end
end

# --------------------------------------------------------------------
# ゲームオブジェクト (Sprite サブクラス)
# --------------------------------------------------------------------
class Player < Sprite
  SPEED = 5.0

  def initialize(x, y)
    super(x, y, Assets.player_image, anchor: :center, pivot: :center, z: 10)
    set_collider(:circle, radius: 15)
  end

  def update
    dx, dy = Input.vector
    self.x = (x + dx * SPEED).clamp(24.0, WORLD_W - 24.0)
    self.y = (y + dy * SPEED).clamp(24.0, WORLD_H - 24.0)
    super
  end
end

class Bullet < Sprite
  SPEED = 12.0

  def initialize(x, y, angle_rad)
    super(x, y, Assets.bullet_image, anchor: :center, pivot: :center, z: 8)
    @vx = Math.cos(angle_rad) * SPEED
    @vy = Math.sin(angle_rad) * SPEED
    @life = 75
    set_collider(:circle, radius: 6)
  end

  def update
    self.x += @vx
    self.y += @vy
    @life -= 1
    if @life <= 0 || x < 0.0 || x > WORLD_W || y < 0.0 || y > WORLD_H
      vanish!
      return
    end
    super
  end
end

class Enemy < Sprite
  def initialize(x, y, target, speed: 2.2)
    super(x, y, Assets.enemy_image, anchor: :center, pivot: :center, z: 5)
    @target = target
    @speed = speed
    set_collider(:circle, radius: 15)
  end

  def update
    if @target && !@target.vanished?
      dx = @target.x - x
      dy = @target.y - y
      dist = Math.hypot(dx, dy)
      if dist > 0.001
        self.x += (dx / dist) * @speed
        self.y += (dy / dist) * @speed
      end
    end
    self.angle += 3.0
    super
  end
end

# --------------------------------------------------------------------
# 1. タイトルシーン (GameScene でも通常の Scene でも相互に遷移可能)
# --------------------------------------------------------------------
class TitleScene < GameScene
  def enter
    ui.panel(420, 210, width: 440, height: 300, padding: 24, gap: 16) do |p|
      p.label("ZENOO GAME SCENE DEMO", size: 24, color: [56, 189, 248, 255])
      p.label("Object Management + 2-Layer (Game/UI) + Scene Stack", size: 14, color: [148, 163, 184, 255])
      p.spacer(12)
      p.button("START GAME", width: 392, height: 44) do
        Scene.change(PlayScene.new, fade: 0.4)
      end
    end
  end

  def draw_game
    Window.clear([15, 23, 42, 255])
  end
end

# --------------------------------------------------------------------
# 2. ゲーム本編シーン (GameScene)
# --------------------------------------------------------------------
class PlayScene < GameScene
  def enter
    @score = 0
    @hp = 5

    # 単体スプライトの登録
    @player = add(Player.new(WORLD_W * 0.5, WORLD_H * 0.5))

    # グループ配列の登録 (以降は << で追加するだけで自動 update / clean / draw される)
    @bullets = sprite_list
    @enemies = sprite_list

    # カメラ設定 (プレイヤーを滑らかに追従 + ワールド境界制限)
    camera.x = @player.x
    camera.y = @player.y
    camera.target = @player
    camera.smooth_speed = 1.2
    camera.bounds = [0.0, 0.0, WORLD_W, WORLD_H]

    # UI レイヤー構築 (ここのボタンをクリックしても、ゲームの射撃には貫通しない！)
    ui.panel(16, 16, width: 348, height: 108, padding: 12, gap: 10) do |p|
      @info_label = p.label("SCORE: 0   HP: 5", size: 18, color: :white)
      p.hbox(gap: 8, padding: 0) do |row|
        row.button("Spawn x5", width: 100, height: 32) { spawn_enemies(5) }
        row.button("Zoom Toggle", width: 112, height: 32) do
          camera.zoom = (camera.zoom == 1.0 ? 1.25 : 1.0)
        end
        row.button("Pause (P)", width: 96, height: 32) do
          Scene.push(PauseScene.new, below: :freeze)
        end
      end
    end

    spawn_enemies(6)
  end

  def spawn_enemies(count)
    i = 0
    while i < count
      ang = rand * Math::PI * 2.0
      dist = 320.0 + rand * 260.0
      ex = (@player.x + Math.cos(ang) * dist).clamp(40.0, WORLD_W - 40.0)
      ey = (@player.y + Math.sin(ang) * dist).clamp(40.0, WORLD_H - 40.0)
      @enemies << Enemy.new(ex, ey, @player, speed: 1.8 + rand * 1.2)
      i += 1
    end
  end

  def update
    return if Scene.transitioning?

    # ポーズショートカット
    if Input.key_push?(:p) || Input.key_push?(:escape)
      Scene.push(PauseScene.new, below: :freeze)
      return
    end

    # マウス方向の計算 (スクリーン座標 → カメラでワールド座標へ逆変換)
    wx, wy = camera.screen_to_world(Input.mouse_x, Input.mouse_y)
    aim_angle = Math.atan2(wy - @player.y, wx - @player.x)
    @player.angle = aim_angle * 180.0 / Math::PI

    # 左クリックまたはスペースキーで弾を発射
    # ※ UI上のボタンをクリックした時は UI::Stage が Input.consume_mouse! を呼ぶため Input.mouse_push?(:left) は自動で false になる
    if Input.mouse_push?(:left) || (Input.mouse_pressed?(:left) && frames % 8 == 0) || Input.key_push?(:space)
      @bullets << Bullet.new(@player.x, @player.y, aim_angle)
    end

    # 一定間隔で敵が追加出現
    spawn_enemies(1) if frames % 75 == 0

    # 弾と敵の当たり判定 (sprite_list はただの Array なので Sprite.check にそのまま渡せる)
    Sprite.check(@bullets, @enemies) do |bullet, enemy|
      bullet.vanish!
      enemy.vanish!
      @score += 100
      camera.shake(4.0, 0.12)
      update_hud_text
    end

    # プレイヤーと敵の当たり判定
    Sprite.check(@player, @enemies) do |_player, enemy|
      enemy.vanish!
      @hp -= 1
      camera.shake(14.0, 0.25)
      update_hud_text
      if @hp <= 0
        Scene.change(GameOverScene.new(@score), fade: 0.5)
        return
      end
    end
  end

  def update_hud_text
    @info_label.text = "SCORE: #{@score}   HP: #{@hp}"
  end

  # Game レイヤー描画 (自動でカメラ変換が適用される)
  def draw_game
    Window.clear([18, 24, 38, 255])

    # ワールドのグリッド線を描画 (カメラが動いていることが一目でわかる)
    gx = 0.0
    while gx <= WORLD_W
      Window.draw_line(gx, 0.0, gx, WORLD_H, width: 1.0, color: [30, 41, 59, 255])
      gx += 100.0
    end
    gy = 0.0
    while gy <= WORLD_H
      Window.draw_line(0.0, gy, WORLD_W, gy, width: 1.0, color: [30, 41, 59, 255])
      gy += 100.0
    end

    # ワールド境界枠
    Window.draw_rect(0.0, 0.0, WORLD_W, WORLD_H, color: [0, 0, 0, 0], border_width: 4.0, border_color: [56, 189, 248, 160])
  end

  # UI レイヤー描画 (自動でカメラ外・スクリーン固定座標になる)
  def draw_ui
    Window.draw_text(
      Window.width - 16, 18,
      "WASD/Arrows: Move | Click/Space: Shoot | Enemies: #{@enemies.length} | Bullets: #{@bullets.length}",
      size: 16, color: [148, 163, 184, 255], align: :right
    )
  end
end

# --------------------------------------------------------------------
# 3. ポーズシーン (Scene.push で上に重なり、下の PlayScene は静止表示)
# --------------------------------------------------------------------
class PauseScene < GameScene
  def enter
    ui.panel(440, 220, width: 400, height: 260, padding: 24, gap: 14) do |p|
      p.label("PAUSED", size: 24, color: :white)
      p.label("Game layer is frozen in the background.", size: 14, color: [148, 163, 184, 255])
      p.spacer(8)
      p.button("Resume Game", width: 352, height: 40) { Scene.pop }
      p.button("Back to Title", width: 352, height: 40) { Scene.change(TitleScene.new, fade: 0.4) }
    end
  end

  def update
    Scene.pop if Input.key_push?(:p) || Input.key_push?(:escape)
  end

  def draw_ui
    Window.draw_rect(0, 0, Window.width, Window.height, color: [0, 0, 0, 150])
  end
end

# --------------------------------------------------------------------
# 4. ゲームオーバーシーン
# --------------------------------------------------------------------
class GameOverScene < GameScene
  def initialize(score)
    super()
    @score = score
  end

  def enter
    ui.panel(440, 210, width: 400, height: 280, padding: 24, gap: 16) do |p|
      p.label("GAME OVER", size: 28, color: [244, 63, 94, 255])
      p.label("FINAL SCORE: #{@score}", size: 20, color: :white)
      p.spacer(8)
      p.button("Retry", width: 352, height: 42) { Scene.change(PlayScene.new, fade: 0.4) }
      p.button("Title", width: 352, height: 40) { Scene.change(TitleScene.new, fade: 0.4) }
    end
  end

  def draw_game
    Window.clear([24, 15, 28, 255])
  end
end

# --------------------------------------------------------------------
# メインループ
# --------------------------------------------------------------------
Scene.change(PlayScene.new)

Window.loop(1280, 720, "Zenoo GameScene Framework Demo") do
  Scene.call
end

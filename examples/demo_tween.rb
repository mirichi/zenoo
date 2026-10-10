# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo Tween & Easing Animation デモ
# ==============================================================================
# 1. 豊富なイージング関数 (Bounce, Elastic, Back, Quad, Linear 等)
# 2. メソッドチェーン (.to, .delay, .call, .loop, .yoyo)
# 3. .call { ... } による時間軸イベント発火 (画像切替・SE・ステータス更新)
# 4. インタラクティブなクリック追従 Tween & 一括制御 (stop/finish)
# ==============================================================================

# アニメーション対象のボックス
class AnimatedBox
  attr_accessor :x, :y, :box_size, :color, :alpha, :label

  def initialize(x, y, label, color)
    @x = x.to_f
    @y = y.to_f
    @box_size = 36.0
    @label = label.to_s
    @color = color
    @alpha = 1.0
  end
end

# 1. イージング比較データ
EASINGS = [
  [:linear,        "Linear",      [100, 200, 255, 255]],
  [:quad_out,      "Quad Out",    [120, 240, 150, 255]],
  [:cubic_in_out,  "Cubic InOut", [255, 215, 0, 255]],
  [:back_out,      "Back Out",    [255, 140, 60, 255]],
  [:bounce_out,    "Bounce Out",  [255, 100, 150, 255]],
  [:elastic_out,   "Elastic Out", [180, 120, 255, 255]]
]

# 2. チェーン＆.call の実演キャラクター
class Hero
  attr_accessor :x, :y, :scale, :angle, :color, :status_text

  def initialize
    @x = 880.0
    @y = 260.0
    @scale = 1.0
    @angle = 0.0
    @color = [255, 215, 0, 255]
    @status_text = "Idle"
  end
end

# 状態変数
boxes = []
hero = Hero.new
hero_img = nil
click_target = nil
sfx_jump = nil
sfx_land = nil
sfx_spin = nil
start_hero_combo = nil
initialized = false

# ------------------------------------------------------------------------------
# メインループ
# ------------------------------------------------------------------------------
Window.loop(1280, 720, "Zenoo - Tween & Easing Animation Demo") do
  # ----------------------------------------------------
  # 初回初期化 (OpenGL / WebGL コンテキスト生成後に安全に実行)
  # ----------------------------------------------------
  unless initialized
    # 効果音 (SoundEffect)
    sfx_jump = SoundEffect.sweep(300, 800, 0.15, type: :square, volume: 0.15)
    sfx_land = SoundEffect.tone(150, 0.1, type: :triangle, volume: 0.2)
    sfx_spin = SoundEffect.sweep(600, 1200, 0.2, type: :sine, volume: 0.15)

    # 回転確認用スプライトの生成 (FBOベイク: 上向きポインタ付きで回転が一目でわかるデザイン)
    hero_img = Zenoo::Image.new(64, 64)
    Zenoo::Image.render_to(hero_img) do
      Zenoo::Window.clear([0, 0, 0, 0])
      # メインボディ (ゴールド)
      Zenoo::Window.draw_rect(8.0, 8.0, 48.0, 48.0, radius: 10.0, color: [255, 215, 0, 255], border_width: 2.0, border_color: :white)
      # コアフレーム
      Zenoo::Window.draw_rect(20.0, 20.0, 24.0, 24.0, radius: 6.0, color: [30, 40, 60, 255])
      Zenoo::Window.draw_circle(32.0, 32.0, 8.0, color: [80, 220, 255, 255])
      # 上向きヘッドマーカー (回転検知用の赤い突起ポインタ)
      Zenoo::Window.draw_triangle(32.0, 0.0, 22.0, 12.0, 42.0, 12.0, color: [255, 60, 80, 255])
    end

    # イージング比較ボックスの生成と Tween 開始
    EASINGS.each_with_index do |item, idx|
      ease = item[0]
      label = item[1]
      col = item[2]
      b = AnimatedBox.new(220.0, 140.0 + idx * 60.0, label, col)
      Tween.to(b, :x, to: 600.0, duration: 1.5, ease: ease).yoyo
      boxes << b
    end

    # クリック追従ターゲット
    click_target = AnimatedBox.new(880.0, 530.0, "Target", [255, 80, 120, 255])
    click_target.box_size = 32.0

    # ヒーローコンボ関数
    start_hero_combo = proc do
      Tween.kill(hero)
      hero.x = 880.0
      hero.y = 260.0
      hero.scale = 1.0
      hero.angle = 0.0
      hero.status_text = "Ready"

      Tween.to(hero, :y, to: 160.0, duration: 0.4, ease: :quad_out)
           .call { sfx_jump.play }
           .call { |t| hero.status_text = "Jumping!" }
           .to(:y, to: 260.0, duration: 0.3, ease: :bounce_out)
           .call { sfx_land.play; hero.status_text = "Landed!"; hero.scale = 1.35 }
           .to(:scale, to: 1.0, duration: 0.2, ease: :quad_out)
           .delay(0.2)
           .call { sfx_spin.play; hero.status_text = "Spin Attack!" }
           .to(:angle, to: 720.0, duration: 0.6, ease: :cubic_in_out)
           .call { hero.angle = 0.0; hero.status_text = "Done! Click button to replay" }
    end

    # 初回コンボ開始
    start_hero_combo.call
    initialized = true
  end

  t = Window.time
  mx, my = Input.mouse_pos

  # 画面クリア
  Window.clear([18, 22, 32, 255])

  # ヘッダー情報
  Window.draw_text(40, 25, "Zenoo Tween & Easing Engine", size: 26, color: :white)
  Window.draw_text(40, 58, "Fluid method chaining: .to(...).delay(...).call { ... }.yoyo", size: 15, color: [160, 175, 200, 255])
  Window.draw_text(1000, 25, "Active Tweens: #{Tween.count}", size: 16, color: :cyan)

  # ----------------------------------------------------
  # 左カラム: 各種イージング比較 (yoyo ループ)
  # ----------------------------------------------------
  Window.draw_rect(30, 95, 660, 580, radius: 12, color: [26, 32, 48, 200], border_width: 1, border_color: [60, 75, 110, 255])
  Window.draw_text(50, 110, "Easing Comparison (.yoyo loop)", size: 18, color: [220, 230, 255, 255])

  boxes.each do |b|
    # ガイドライン
    Window.draw_rect(220, b.y + 16, 380 + b.box_size, 2, color: [45, 55, 80, 255])
    # ラベル
    Window.draw_text(50, b.y + 8, b.label, size: 15, color: :white)
    # 動くカード
    Window.draw_rect(b.x, b.y, b.box_size, b.box_size, radius: 8, color: b.color, shadow_blur: 8)
  end

  # ----------------------------------------------------
  # 右上カラム: シーケンスチェーンと .call の実演
  # ----------------------------------------------------
  Window.draw_rect(710, 95, 540, 310, radius: 12, color: [26, 32, 48, 200], border_width: 1, border_color: [60, 75, 110, 255])
  Window.draw_text(730, 110, "Sequence Chaining with .call { ... }", size: 18, color: [220, 230, 255, 255])
  Window.draw_text(730, 138, "Status: #{hero.status_text}", size: 16, color: :yellow)

  # キャラクターの描画 (GPU Instanced 回転・拡縮スプライト)
  Window.draw_image(hero.x, hero.y, hero_img, angle: hero.angle, scale: hero.scale, pivot: :center, offset_mode: :center) if hero_img

  # アクション再開ボタン
  btn_x = 730
  btn_y = 340
  btn_w = 180
  btn_h = 42
  btn_hover = mx >= btn_x && mx <= btn_x + btn_w && my >= btn_y && my <= btn_y + btn_h
  btn_col = btn_hover ? [50, 140, 255, 255] : [30, 100, 220, 255]

  Window.draw_rect(btn_x, btn_y, btn_w, btn_h, radius: 8, color: btn_col, shadow_blur: 6)
  Window.draw_text(btn_x + 35, btn_y + 11, "Play Combo", size: 16, color: :white)

  if btn_hover && Input.mouse_pressed?(:left) && start_hero_combo
    start_hero_combo.call
  end

  # ----------------------------------------------------
  # 右下カラム: クリック追従 Tween (スムーズ補間)
  # ----------------------------------------------------
  Window.draw_rect(710, 425, 540, 250, radius: 12, color: [26, 32, 48, 200], border_width: 1, border_color: [60, 75, 110, 255])
  Window.draw_text(730, 440, "Interactive Click to Tween", size: 18, color: [220, 230, 255, 255])
  Window.draw_text(730, 468, "Click inside this panel to move target with :back_out", size: 14, color: [160, 175, 200, 255])

  # マウス入力チェック
  if Input.mouse_pressed?(:left) && click_target
    if mx >= 720 && mx <= 1240 && my >= 490 && my <= 660
      # 前のTweenを上書きして目標地点へスムーズに移動
      Tween.kill(click_target)
      target_x = mx - click_target.box_size / 2.0
      target_y = my - click_target.box_size / 2.0
      Tween.to(click_target, :x, to: target_x, duration: 0.6, ease: :back_out)
      Tween.to(click_target, :y, to: target_y, duration: 0.6, ease: :back_out)
    end
  end

  # 追従ターゲットの描画
  if click_target
    Window.draw_rect(click_target.x, click_target.y, click_target.box_size, click_target.box_size, radius: 8, color: click_target.color, border_width: 2, border_color: :white, shadow_blur: 10)
  end
end

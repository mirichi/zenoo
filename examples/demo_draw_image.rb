# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - Window.draw_image 新機能ショーケース
#
# 実装された新機能:
#   1. 回転 (angle: 角度度数法)
#   2. 拡大縮小 & 反転 (scale:, scale_x:, scale_y:)
#   3. ピボット位置指定 (pivot: :center, :top_left, [cx, cy])
#   4. 基準位置モード (offset_mode: :top_left, :center)
#   5. 不透明度 (alpha: 0..255)
#   6. ブレンドモード (blend: :alpha, :add, :multiply, :none)
# ==============================================================================

# ----------------------------------------------------
# ヘルパー: SDF による高品質円描画
# ----------------------------------------------------
def draw_circle(cx, cy, r, color = :white)
  Zenoo::Window.draw_rounded_rect(cx - r, cy - r, r * 2.0, r * 2.0, r, color)
end

# ----------------------------------------------------
# 1. デモ用スプライト画像の生成 (外部画像不要で自立起動)
# ----------------------------------------------------
def create_spaceship_sprite
  # 向き・上下左右がひと目でわかる非対称な宇宙船グラフィック (80x80)
  img = Zenoo::Image.new(80, 80)
  Zenoo::Image.render_to(img) do
    Zenoo::Window.clear([0, 0, 0, 0])

    # 船体メイン (シアンのくさび型)
    Zenoo::Window.draw_triangle(68, 40, 16, 20, 16, 60, [30, 200, 255, 255])

    # コックピット (先端付近のイエロー)
    Zenoo::Window.draw_triangle(62, 40, 35, 33, 35, 47, [255, 220, 50, 255])

    # 上翼 (濃いブルー)
    Zenoo::Window.draw_triangle(40, 26, 12, 8, 20, 28, [15, 100, 220, 255])

    # 下翼 (アクセントのレッド)
    Zenoo::Window.draw_triangle(40, 54, 20, 52, 12, 72, [255, 70, 70, 255])

    # エンジン噴射口 (後部)
    Zenoo::Window.draw_rect(10, 34, 6, 12, [255, 140, 0, 255])

    # 船体中央のコア
    draw_circle(36, 40, 5, [255, 255, 255, 255])

    #Zenoo::Window.flush_draw_queue
  end
  img
end

def create_orb_sprite
  # ブレンド合成確認用: 中心が明るい光球グラフィック (96x96)
  img = Zenoo::Image.new(96, 96)
  Zenoo::Image.render_to(img) do
    Zenoo::Window.clear([0, 0, 0, 0])

    # 多重円で滑らかなグラデーション光球を描く
    r = 44.0
    while r > 2.0
      t = 1.0 - (r / 44.0) # 0.0(外側) .. 1.0(中心)
      alpha = (t * t * 230).to_i
      color = [
        (100 + 155 * t).to_i,
        (160 + 95 * t).to_i,
        255,
        alpha
      ]
      draw_circle(48, 48, r, color)
      r -= 2.0
    end
    # コアの白光
    draw_circle(48, 48, 6, [255, 255, 255, 255])
  end
  img
end

def create_disc_sprite
  # 乗算・アルファ合成確認用: 均一な円形スプライト (80x80)
  img = Zenoo::Image.new(80, 80)
  Zenoo::Image.render_to(img) do
    Zenoo::Window.clear([0, 0, 0, 0])
    draw_circle(40, 40, 38, [255, 255, 255, 255])
  end
  img
end

# ----------------------------------------------------
# 2. メインループ
# ----------------------------------------------------
Window.loop(1280, 720, "Zenoo - Window.draw_image Showcase") do
  # 初期化 (初回のみテクスチャ生成)
  @ship_img ||= create_spaceship_sprite
  @orb_img  ||= create_orb_sprite
  @disc_img ||= create_disc_sprite

  t = Window.time

  # 背景描画
  Window.clear([16, 20, 32, 255])

  # タイトルヘッダー
  Window.draw_rounded_rect(24, 16, 1232, 54, 10, [26, 32, 48, 255], border_width: 1, border_color: [60, 75, 110, 255])
  Window.draw_text(44, 28, "Zenoo: Window.draw_image Showcase", size: 22, color: :white)
  Window.draw_text(600, 34, "GPU Instanced: Rotation / Scale / Flip / Pivot / offset_mode / Alpha / Blend", size: 14, color: [160, 180, 210, 255])

  # ----------------------------------------------------
  # パネル 1: 回転 (Rotation)
  # ----------------------------------------------------
  p1_x, p1_y, p1_w, p1_h = 24, 86, 396, 290
  Window.draw_rounded_rect(p1_x, p1_y, p1_w, p1_h, 12, [24, 28, 42, 255], border_width: 1, border_color: [50, 60, 85, 255])
  Window.draw_text(p1_x + 18, p1_y + 14, "1. 回転 (Rotation)", size: 17, color: :cyan)
  Window.draw_text(p1_x + 18, p1_y + 36, "angle: 0..360 (度数法) / 中心軸回転", size: 13, color: [150, 165, 190, 255])

  # 静止 (0度)
  Window.draw_image(p1_x + 30, p1_y + 70, @ship_img)
  Window.draw_text(p1_x + 45, p1_y + 160, "angle: 0", size: 13, color: :white)

  # 45度固定
  Window.draw_image(p1_x + 155, p1_y + 70, @ship_img, angle: 45)
  Window.draw_text(p1_x + 165, p1_y + 160, "angle: 45", size: 13, color: :white)

  # 連続回転
  rot_angle = (t * 120.0) % 360.0
  Window.draw_image(p1_x + 280, p1_y + 70, @ship_img, angle: rot_angle)
  Window.draw_text(p1_x + 275, p1_y + 160, "angle: #{rot_angle.round}°", size: 13, color: :yellow)

  # 逆回転 ＆ チント色付き
  Window.draw_image(p1_x + 100, p1_y + 195, @ship_img, color: [255, 150, 150, 255], angle: -rot_angle, scale: 0.8)
  Window.draw_text(p1_x + 180, p1_y + 225, "逆回転 + color tint", size: 13, color: [255, 180, 180, 255])

  # ----------------------------------------------------
  # パネル 2: 拡大縮小 ＆ 反転 (Scale & Flip)
  # ----------------------------------------------------
  p2_x, p2_y, p2_w, p2_h = 442, 86, 396, 290
  Window.draw_rounded_rect(p2_x, p2_y, p2_w, p2_h, 12, [24, 28, 42, 255], border_width: 1, border_color: [50, 60, 85, 255])
  Window.draw_text(p2_x + 18, p2_y + 14, "2. 拡大縮小 & 反転 (Scale & Flip)", size: 17, color: :cyan)
  Window.draw_text(p2_x + 18, p2_y + 36, "scale:, scale_x:, scale_y: (負値で反転)", size: 13, color: [150, 165, 190, 255])

  # 等倍 (1.0x)
  Window.draw_image(p2_x + 25, p2_y + 70, @ship_img, scale: 0.75)
  Window.draw_text(p2_x + 35, p2_y + 160, "scale: 0.75", size: 13, color: :white)

  # 脈動アニメーション
  pulse = 0.75 + Math.sin(t * 4.0) * 0.25
  Window.draw_image(p2_x + 150, p2_y + 70, @ship_img, scale: pulse)
  Window.draw_text(p2_x + 145, p2_y + 160, "scale: #{pulse.round(2)}", size: 13, color: :yellow)

  # 左右反転 (キャラの振り向き: scale_x: -1.0)
  flip_toggle = ((t * 1.5).to_i.even? ? 1.0 : -1.0)
  Window.draw_image(p2_x + 280, p2_y + 70, @ship_img, scale_x: flip_toggle, scale_y: 1.0)
  Window.draw_text(p2_x + 265, p2_y + 160, "scale_x: #{flip_toggle}", size: 13, color: (flip_toggle < 0 ? :magenta : :green))

  # 縦横比変形 (ストレッチ)
  stretch_x = 1.1 + Math.sin(t * 3.0) * 0.3
  stretch_y = 1.1 - Math.sin(t * 3.0) * 0.3
  Window.draw_image(p2_x + 60, p2_y + 195, @ship_img, scale_x: stretch_x * 0.7, scale_y: stretch_y * 0.7)
  Window.draw_text(p2_x + 160, p2_y + 225, "個別スケール (stretch)", size: 13, color: [180, 220, 255, 255])

  # ----------------------------------------------------
  # パネル 3: offset_mode と ピボット (Pivot)
  # ----------------------------------------------------
  p3_x, p3_y, p3_w, p3_h = 860, 86, 396, 290
  Window.draw_rounded_rect(p3_x, p3_y, p3_w, p3_h, 12, [24, 28, 42, 255], border_width: 1, border_color: [50, 60, 85, 255])
  Window.draw_text(p3_x + 18, p3_y + 14, "3. 基準点モード (offset_mode)", size: 17, color: :cyan)
  Window.draw_text(p3_x + 18, p3_y + 36, "赤十字 (+) が指定した描画座標 (x, y)", size: 13, color: [150, 165, 190, 255])

  # モード A: offset_mode: :top_left (デフォルト)
  # (x, y) が矩形の左上。回転はその中心を軸に行う
  c1_x, c1_y = p3_x + 50, p3_y + 80
  # ガイド枠 & 十字線 (x, y)
  Window.draw_rect(c1_x, c1_y, 80, 80, [40, 50, 75, 120])
  Window.draw_line(c1_x - 8, c1_y, c1_x + 8, c1_y, :red)
  Window.draw_line(c1_x, c1_y - 8, c1_x, c1_y + 8, :red)
  Window.draw_image(c1_x, c1_y, @ship_img, angle: rot_angle, offset_mode: :top_left)
  Window.draw_text(c1_x - 5, p3_y + 175, ":top_left (左上配置)", size: 13, color: :white)

  # モード B: offset_mode: :center
  # (x, y) そのものが画像の中心点となる
  c2_x, c2_y = p3_x + 270, p3_y + 120
  # 十字線 (x, y)
  Window.draw_line(c2_x - 14, c2_y, c2_x + 14, c2_y, :red)
  Window.draw_line(c2_x, c2_y - 14, c2_x, c2_y + 14, :red)
  draw_circle(c2_x, c2_y, 40, [40, 50, 75, 100])
  Window.draw_image(c2_x, c2_y, @ship_img, angle: rot_angle, offset_mode: :center)
  Window.draw_text(c2_x - 45, p3_y + 175, ":center (中心配置)", size: 13, color: :white)

  # ピボット変更デモ (先端回転 vs 根元回転)
  tip_x, tip_y = p3_x + 90, p3_y + 225
  draw_circle(tip_x, tip_y, 4, :yellow) # ピボット位置
  Window.draw_image(tip_x, tip_y, @ship_img, angle: rot_angle * 1.5, scale: 0.6, pivot: [0.85, 0.5], offset_mode: :center)
  Window.draw_text(p3_x + 150, p3_y + 220, "先端ピボット [0.85, 0.5]", size: 13, color: :yellow)
  Window.draw_text(p3_x + 150, p3_y + 238, "剣先を振るような動き", size: 11, color: [140, 160, 190, 255])

  # ----------------------------------------------------
  # パネル 4: 不透明度 (Alpha)
  # ----------------------------------------------------
  p4_x, p4_y, p4_w, p4_h = 24, 396, 500, 304
  Window.draw_rounded_rect(p4_x, p4_y, p4_w, p4_h, 12, [24, 28, 42, 255], border_width: 1, border_color: [50, 60, 85, 255])
  Window.draw_text(p4_x + 18, p4_y + 14, "4. 不透明度 (Alpha)", size: 17, color: :cyan)
  Window.draw_text(p4_x + 18, p4_y + 36, "alpha: 0..255 (DXRuby準拠) / 色ブレンドと連動", size: 13, color: [150, 165, 190, 255])

  # 背景にストライプ模様を描画して透過度をわかりやすくする
  12.times do |i|
    bx = p4_x + 20 + i * 38
    col = (i.even? ? [40, 50, 70, 255] : [20, 26, 40, 255])
    Window.draw_rect(bx, p4_y + 60, 38, 120, col)
  end

  # 4段階の固定アルファ
  alphas = [255, 166, 89, 38]
  alphas.each_with_index do |a, idx|
    ax = p4_x + 25 + idx * 115
    Window.draw_image(ax, p4_y + 75, @ship_img, alpha: a, scale: 0.9)
    Window.draw_text(ax + 12, p4_y + 185, "alpha: #{a}", size: 13, color: :white)
  end

  # 滑らかフェードイン・フェードアウト
  sine_alpha = ((0.5 + 0.5 * Math.sin(t * 3.0)) * 255.0).round
  Window.draw_image(p4_x + 40, p4_y + 220, @ship_img, alpha: sine_alpha, angle: t * 45, scale: 0.8)
  Window.draw_text(p4_x + 150, p4_y + 245, "リアルタイムフェード (Sine Wave)", size: 14, color: :yellow)
  Window.draw_text(p4_x + 150, p4_y + 265, "alpha: #{sine_alpha}", size: 13, color: [200, 215, 235, 255])

  # ----------------------------------------------------
  # パネル 5: ブレンドモード (Blend Modes)
  # ----------------------------------------------------
  p5_x, p5_y, p5_w, p5_h = 544, 396, 712, 304
  Window.draw_rounded_rect(p5_x, p5_y, p5_w, p5_h, 12, [24, 28, 42, 255], border_width: 1, border_color: [50, 60, 85, 255])
  Window.draw_text(p5_x + 18, p5_y + 14, "5. ブレンドモード (Blend Modes: :alpha / :add / :multiply)", size: 17, color: :cyan)
  Window.draw_text(p5_x + 18, p5_y + 36, "加算は暗い背景で発光し、乗算は明るい背景で色が重なり影になります", size: 13, color: [150, 165, 190, 255])

  osc = Math.sin(t * 2.5) * 16.0

  # 1. :alpha (標準アルファブレンド)
  b1_x, b1_y = p5_x + 25, p5_y + 65
  Window.draw_rounded_rect(b1_x, b1_y, 210, 175, 8, [16, 22, 34, 255], border_width: 1, border_color: [45, 55, 75, 255])
  Window.draw_image(b1_x + 25 - osc * 0.5, b1_y + 20, @disc_img, color: [0, 200, 255, 200], blend: :alpha, scale: 0.9)
  Window.draw_image(b1_x + 65 + osc * 0.5, b1_y + 20, @disc_img, color: [255, 60, 140, 200], blend: :alpha, scale: 0.9)
  Window.draw_text(b1_x + 16, b1_y + 125, "1. :alpha (標準透過)", size: 14, color: :white)
  Window.draw_text(b1_x + 16, b1_y + 148, "手前が奥を透過上書き", size: 12, color: [160, 175, 195, 255])

  # 2. :add (加算合成: 暗い背景で光輝く)
  b2_x, b2_y = p5_x + 255, p5_y + 65
  Window.draw_rounded_rect(b2_x, b2_y, 210, 175, 8, [10, 12, 18, 255], border_width: 1, border_color: [45, 55, 75, 255])
  Window.draw_image(b2_x + 25 - osc * 0.5, b2_y + 20, @disc_img, color: [0, 200, 255, 255], blend: :add, scale: 0.9)
  Window.draw_image(b2_x + 65 + osc * 0.5, b2_y + 20, @disc_img, color: [255, 60, 140, 255], blend: :add, scale: 0.9)
  Window.draw_text(b2_x + 16, b2_y + 125, "2. :add (加算合成)", size: 14, color: :yellow)
  Window.draw_text(b2_x + 16, b2_y + 148, "重なりが激しく発光！(光/炎)", size: 12, color: [255, 230, 160, 255])

  # 3. :multiply (乗算合成: 明るい背景で色が重なり影になる)
  b3_x, b3_y = p5_x + 485, p5_y + 65
  # 明るいキャンバス背景 (オフホワイト)
  Window.draw_rounded_rect(b3_x, b3_y, 210, 175, 8, [235, 240, 248, 255], border_width: 1, border_color: [180, 195, 220, 255])
  # 市松模様のガイド線
  Window.draw_rect(b3_x + 10, b3_y + 10, 190, 100, [215, 222, 235, 255])
  # 2つのカラーフィルターを乗算合成 (シアン x マゼンタ -> 重なりが濃い青紫に！)
  Window.draw_image(b3_x + 25 - osc * 0.5, b3_y + 20, @disc_img, color: [0, 200, 255, 255], blend: :multiply, scale: 0.9)
  Window.draw_image(b3_x + 65 + osc * 0.5, b3_y + 20, @disc_img, color: [255, 60, 140, 255], blend: :multiply, scale: 0.9)
  Window.draw_text(b3_x + 16, b3_y + 125, "3. :multiply (乗算)", size: 14, color: [30, 40, 70, 255])
  Window.draw_text(b3_x + 16, b3_y + 148, "重なりが濃く混色 (影/セロハン)", size: 12, color: [70, 90, 120, 255])

  # 下部に加算パーティクル演出のワンポイント
  orb_pulse = 0.8 + Math.sin(t * 5.0) * 0.2
  Window.draw_image(p5_x + 30, p5_y + 245, @orb_img, color: :yellow, blend: :add, scale: orb_pulse * 0.6)
  Window.draw_text(p5_x + 85, p5_y + 256, "エフェクト演出: 加算ブレンドによる美しい発光オーラ・弾幕・ビーム", size: 13, color: [255, 230, 150, 255])

  # キーボード終了 & 自動テスト判定
  exit if Input.key_pressed?(:escape) || Input.key_pressed?(:q)
  test_frames = ENV["ZENOO_AUTO_EXIT_FRAMES"] || ENV["ZENOO_TEST_FRAMES"]
  if test_frames
    @test_frame_counter = (@test_frame_counter || 0) + 1
    exit if @test_frame_counter >= test_frames.to_i
  end
end


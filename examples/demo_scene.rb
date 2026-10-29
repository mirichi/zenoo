# frozen_string_literal: true

require_relative '../lib/zenoo'

# ====================================================================
# Zenoo::Scene デモ - マウス GUI 操作で試せるシーン管理サンプル
# ====================================================================
# 確認できる機能:
# 1. フェード切り替え (黒フェード / 白フェード / 即座切り替え)
# 2. 背景停止モード (below: :freeze) - 下のゲームがピタッと静止
# 3. 背景実行モード (below: :live)   - 上に重ねても下のゲームが動き続ける
# 4. ブロック構文でのポップアップ (Scene.push { ... })
# ====================================================================

# GUI ボタンの簡易描画 & クリック判定ヘルパー
module UI
  def self.button(x, y, w, h, text, base_color: [59, 130, 246, 230])
    mx = Input.mouse_x
    my = Input.mouse_y
    hover = mx >= x && mx <= x + w && my >= y && my <= y + h

    # ホバー時は少し明るく光らせる
    r = [base_color[0] + (hover ? 35 : 0), 255].min
    g = [base_color[1] + (hover ? 35 : 0), 255].min
    b = [base_color[2] + (hover ? 35 : 0), 255].min
    col = [r, g, b, base_color[3] || 255]

    Window.draw_rect(x, y, w, h, radius: 8, color: col, shadow_blur: hover ? 12 : 4,
                     border_width: hover ? 2 : 1, border_color: hover ? :white : [255, 255, 255, 60])
    Window.draw_text(x + w / 2, y + (h - 20) / 2 + 1, text, size: 17, color: :white, align: :center)

    hover && Input.mouse_push?(:left)
  end
end

# --------------------------------------------------------------------
# 1. タイトル画面
# --------------------------------------------------------------------
class TitleScene < Scene
  def call
    Window.clear([15, 23, 42, 255])

    # 背景アニメーション
    t = elapsed * 2.5
    Window.draw_rect(540, 140, 200, 200, angle: t * 25, radius: 24, color: [59, 130, 246, 180], shadow_blur: 25)

    Window.draw_text(640, 380, "ZENOO SCENE & TRANSITION DEMO", size: 34, color: :white, align: :center)
    Window.draw_text(640, 425, "Click buttons below to test scene features", size: 18, color: [148, 163, 184, 255], align: :center)

    # フェード中は入力を受け付けない
    return if Scene.transitioning?

    # GUI ボタン配置
    if UI.button(390, 480, 240, 46, "Play (Black Fade: 0.5s)", base_color: [37, 99, 235, 240])
      Scene.change(PlayScene.new, fade: 0.5)
    end

    if UI.button(650, 480, 240, 46, "Play (White Fade: 0.5s)", base_color: [202, 138, 4, 240])
      Scene.change(PlayScene.new, fade: 0.5, color: :white)
    end

    if UI.button(520, 540, 240, 42, "Play (Immediate / No Fade)", base_color: [71, 85, 105, 240])
      Scene.change(PlayScene.new)
    end
  end
end

# --------------------------------------------------------------------
# 2. プレイ画面 (背景として動き続けるオブジェクトを持つ)
# --------------------------------------------------------------------
class PlayScene < Scene
  def initialize
    @x = 200.0
    @y = 330.0
    @vx = 320.0
  end

  def call
    Window.clear([20, 30, 45, 255])

    # ボールのアニメーション
    @x += @vx * Window.delta_time
    if @x > 1180.0 || @x < 100.0
      @vx = -@vx
    end

    # ボール & 地面 & 回転立方体
    Window.draw_line(80, 410, 1200, 410, width: 4.0, color: [100, 116, 139, 255])
    Window.draw_circle(@x, @y, 40, color: [244, 63, 94, 255], shadow_blur: 18)
    Window.draw_rect(640, 260, 60, 60, angle: elapsed * 90.0, radius: 8, color: [16, 185, 129, 220])

    Window.draw_text(640, 60, "PLAY SCENE (BACKGROUND GAME)", size: 30, color: :white, align: :center)
    Window.draw_text(640, 105, "Active Time: #{elapsed.round(2)}s  |  Frames: #{frames}", size: 18, color: [148, 163, 184, 255], align: :center)

    return if Scene.transitioning?

    # GUI ボタン配置
    # 1. below: :freeze (既定) → 背景のボールがピタッと止まる
    if UI.button(240, 500, 240, 46, "Pause (below: :freeze)", base_color: [225, 29, 72, 240])
      Scene.push(FreezePauseScene.new, below: :freeze)
    end

    # 2. below: :live → 背景のボールが止まらずに動き続ける！
    if UI.button(520, 500, 240, 46, "Overlay (below: :live)", base_color: [13, 148, 136, 240])
      Scene.push(LiveOverlayScene.new, below: :live)
    end

    # 3. ブロックによるポップアップダイアログ (below: :freeze)
    if UI.button(800, 500, 240, 46, "Block Dialog (push { })", base_color: [124, 58, 237, 240])
      Scene.push do
        Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 180])
        Window.draw_rect(440, 240, 400, 220, radius: 16, color: [30, 41, 59, 255], border_width: 2, border_color: :green)
        Window.draw_text(640, 280, "INLINE BLOCK DIALOG", size: 22, color: :green, align: :center)
        Window.draw_text(640, 325, "No class definition needed!", size: 16, color: :white, align: :center)
        Window.draw_text(640, 355, "Background is frozen (:freeze)", size: 15, color: [148, 163, 184, 255], align: :center)

        if UI.button(540, 395, 200, 40, "Close (Scene.pop)", base_color: [16, 185, 129, 240])
          Scene.pop
        end
      end
    end

    # 4. タイトルへ戻るボタン
    if UI.button(520, 580, 240, 42, "Back to Title (Fade 0.4s)", base_color: [71, 85, 105, 240])
      Scene.change(TitleScene.new, fade: 0.4)
    end
  end
end

# --------------------------------------------------------------------
# 3. 背景停止ポーズ画面 (below: :freeze の確認用)
# --------------------------------------------------------------------
class FreezePauseScene < Scene
  def call
    # 半透明の暗幕を敷く (下のゲーム画面は直前の状態のまま自動描画される)
    Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 160])

    Window.draw_rect(420, 200, 440, 300, radius: 16, color: [15, 23, 42, 245], border_width: 2, border_color: :cyan)
    Window.draw_text(640, 245, "PAUSED (FREEZE MODE)", size: 26, color: :white, align: :center)
    Window.draw_text(640, 285, "Background is completely stopped (:freeze)", size: 16, color: :yellow, align: :center)
    Window.draw_text(640, 315, "Ball and cube do not move at all.", size: 15, color: [148, 163, 184, 255], align: :center)

    return if Scene.transitioning?

    if UI.button(500, 360, 280, 44, "Resume Game (Scene.pop)", base_color: [37, 99, 235, 240])
      Scene.pop
    end

    if UI.button(500, 420, 280, 42, "Title Scene (Scene.change)", base_color: [71, 85, 105, 240])
      Scene.change(TitleScene.new, fade: 0.4)
    end
  end
end

# --------------------------------------------------------------------
# 4. 背景動作継続オーバーレイ (below: :live の確認用)
# --------------------------------------------------------------------
class LiveOverlayScene < Scene
  def call
    # 背景を暗くしすぎず、下のゲームが動いている様子を見せる
    Window.draw_rect(0, 0, 1280, 720, color: [0, 0, 0, 90])

    Window.draw_rect(420, 180, 440, 330, radius: 16, color: [15, 23, 42, 245], border_width: 2, border_color: :teal)
    Window.draw_text(640, 225, "OVERLAY (LIVE MODE)", size: 26, color: :teal, align: :center)
    Window.draw_text(640, 265, "Background game is RUNNING! (:live)", size: 16, color: [52, 211, 153, 255], align: :center)
    Window.draw_text(640, 295, "Notice the ball and cube moving behind!", size: 15, color: :white, align: :center)
    Window.draw_text(640, 330, "Overlay Active: #{elapsed.round(2)}s", size: 16, color: [148, 163, 184, 255], align: :center)

    return if Scene.transitioning?

    if UI.button(500, 380, 280, 44, "Close Overlay (Scene.pop)", base_color: [13, 148, 136, 240])
      Scene.pop
    end

    if UI.button(500, 440, 280, 42, "Title Scene (Scene.change)", base_color: [71, 85, 105, 240])
      Scene.change(TitleScene.new, fade: 0.4)
    end
  end
end

# --------------------------------------------------------------------
# メインループ
# --------------------------------------------------------------------
Scene.change(TitleScene.new)

Window.loop(1280, 720, "Zenoo Scene Demo (Mouse GUI)") do
  # 毎フレーム Scene.call を呼ぶだけで、更新・描画・スタック管理・フェードが完結
  Scene.call
end

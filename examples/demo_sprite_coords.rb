# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo - Sprite & Collision 座標系インタラクティブシミュレーター
#
# 【解説目的】
#   x, y / anchor / pivot / offset がゲーム内で「どこに」「どのように」
#   影響しているかを、リアルタイムに見て触って学べるデモプログラム。
#
# 【視覚要素のカラーガイド】
#   - 赤色クロスヘア [(x, y)]: ワールド空間での目標配置点
#   - 緑色マーカー [Anchor]: スプライト矩形の中で (x, y) に吸着している基準点
#   - 黄色十字スター [Pivot]: スプライトとコライダーが回転・拡縮するときの固定軸
#   - 紫色ベクトル [Offset]: スプライト中心からコライダー（当たり判定）への相対ズレ
#   - 水色実線枠: スプライト画像の外枠
#   - 緑/赤色破線枠: コライダー（当たり判定）の領域（マウス円接触時に赤く発光）
#   - オレンジ/赤色円: マウスカーソル追従の検査コライダー
#
# 【操作方法】
#   - マウス移動: 検査円を動かしてスプライトとの衝突判定をテスト
#   - 左ドラッグ: スプライトの (x, y) を画面上で自由に移動
#   - 右ドラッグ / [Q][E] / ホイール: スプライトの回転 (angle)
#   - [1] キー / 画面上ボタン: Anchor (配置基準) の切り替え
#   - [2] キー / 画面上ボタン: Pivot (回転軸) の切り替え
#   - [3] キー / 画面上ボタン: Collider (当たり判定の形状) の切り替え
#   - [W][A][S][D] / 矢印キー: Offset (当たり判定の相対ズレ) を移動
#   - [SPACE]: Offset を (0, 0) にリセット
#   - [R]: 全ての設定を初期状態にリセット
# ==============================================================================

# ----------------------------------------------------
# 向き・上下左右がはっきり分かるキャラクター画像の生成
# ----------------------------------------------------
def create_character_image
  w = 120
  h = 160
  img = Image.new(w, h)
  Image.render_to(img) do
    Window.clear([0, 0, 0, 0])

    # 1. 影
    Window.draw_circle(60, 150, 36, color: [0, 0, 0, 80])

    # 2. 足 (左右のブーツ)
    Window.draw_rect(32, 120, 20, 30, radius: 6, color: [40, 50, 70, 255])
    Window.draw_rect(68, 120, 20, 30, radius: 6, color: [40, 50, 70, 255])

    # 3. 胴体 / アーマー
    Window.draw_rect(30, 55, 60, 70, radius: 10, color: [50, 110, 180, 255])
    # 胸部プレート
    Window.draw_rect(38, 62, 44, 40, radius: 6, color: [75, 145, 225, 255])
    # エネルギーコア (胸の中央)
    Window.draw_circle(60, 82, 10, color: [255, 240, 100, 255])
    Window.draw_circle(60, 82, 5, color: [255, 255, 255, 255])

    # 4. 腕 / ショルダーアーマー
    Window.draw_circle(24, 65, 12, color: [40, 90, 150, 255])
    Window.draw_rect(16, 70, 16, 35, radius: 6, color: [50, 110, 180, 255])
    Window.draw_circle(96, 65, 12, color: [40, 90, 150, 255])
    Window.draw_rect(88, 70, 16, 35, radius: 6, color: [50, 110, 180, 255])

    # 5. 頭部 / ヘルメット
    Window.draw_circle(60, 35, 24, color: [60, 130, 200, 255])
    # バイザー (視線の向き: 前方)
    Window.draw_rect(44, 28, 32, 12, radius: 5, color: [0, 240, 255, 255])
    # アンテナ
    Window.draw_line(60, 12, 60, 4, color: [255, 220, 80, 255], width: 3)
    Window.draw_circle(60, 4, 3, color: [255, 240, 100, 255])
  end
  img
end

# ----------------------------------------------------
# プリセット定義
# ----------------------------------------------------
ANCHOR_PRESETS = [
  { name: ":top_left",      val: :top_left,      label: "左上 (0, 0)",    ax: 0.0, ay: 0.0 },
  { name: ":center",        val: :center,        label: "中央 (0.5, 0.5)", ax: 0.5, ay: 0.5 },
  { name: ":bottom_center", val: [0.5, 1.0],     label: "足元 (0.5, 1.0)", ax: 0.5, ay: 1.0 },
  { name: ":top_right",     val: [1.0, 0.0],     label: "右上 (1.0, 0.0)", ax: 1.0, ay: 0.0 },
  { name: ":bottom_right",  val: [1.0, 1.0],     label: "右下 (1.0, 1.0)", ax: 1.0, ay: 1.0 }
].freeze

PIVOT_PRESETS = [
  { name: ":center",        val: :center,        label: "中央 (0.5, 0.5)", px: 0.5, py: 0.5 },
  { name: ":bottom_center", val: [0.5, 1.0],     label: "足元 (0.5, 1.0)", px: 0.5, py: 1.0 },
  { name: ":top_left",      val: :top_left,      label: "左上 (0.0, 0.0)", px: 0.0, py: 0.0 },
  { name: ":top_right",     val: [1.0, 0.0],     label: "右上 (1.0, 0.0)", px: 1.0, py: 0.0 }
].freeze

# 縦長の6角形頂点データ (キャラクターのシルエットにフィット)
HEXAGON_VERTICES = [
  [0.0, -68.0],   # 上部尖り
  [42.0, -34.0],  # 右上
  [42.0, 34.0],   # 右下
  [0.0, 68.0],    # 下部尖り
  [-42.0, 34.0],  # 左下
  [-42.0, -34.0]  # 左上
].freeze

SHAPE_PRESETS = [
  { id: :rect,         name: "矩形 (Rect)",         btn_label: "矩形 (90x130)",      desc: "90x130" },
  { id: :rounded_rect, name: "角丸矩形 (Round)",     btn_label: "角丸矩形 (r=24)",    desc: "90x130 (r=24)" },
  { id: :circle,       name: "真円 (Circle)",       btn_label: "真円 (r=52)",        desc: "r=52" },
  { id: :ellipse,      name: "縦長楕円 (Ellipse)",   btn_label: "縦長楕円 (40x65)",    desc: "rx=40, ry=65" },
  { id: :hexagon,      name: "縦長6角形 (Hexagon)", btn_label: "縦長6角形 (84x136)", desc: "84x136" }
].freeze

# ----------------------------------------------------
# シミュレーター本体
# ----------------------------------------------------
class CoordsSimulator
  attr_accessor :sprite, :mouse_circle, :col_type, :is_hit
  attr_accessor :anchor_idx, :pivot_idx, :shape_idx
  attr_accessor :drag_target, :drag_start_mx, :drag_start_my
  attr_accessor :pulse_time

  def initialize
    # このデモ専用のカスタムテーマを登録 (新機能: Theme.register)
    GUI::Theme.register(:coords_navy,
      bg_normal:         [30, 40, 60, 200],
      bg_hover:          [60, 75, 105, 230],
      bg_active:         [40, 120, 220, 240],
      border_normal:     [1.0, [70, 90, 125, 180]],
      border_hover:      [1.0, [150, 180, 220, 220]],
      border_active:     [2.0, [100, 200, 255, 255]],
      win_bg:            [20, 26, 40, 230],
      win_border_normal: [1.0, [60, 80, 115, 210]],
      accent_color:      [50, 140, 230],
      accent_hover:      [80, 170, 255],
      track_bg:          [30, 40, 60, 255],
      track_border:      [1.0, [60, 80, 110, 200]],
      text_color:        [220, 230, 245],
      corner_radius:     6.0
    )

    @init_x = 640.0
    @init_y = 200.0
    @anchor_idx = 0
    @pivot_idx = 0
    @shape_idx = 0
    @mouse_circle = Collision.circle(0, 0, 32, anchor: :center)
    @is_hit = false
    @drag_target = nil
    @rotate_base_angle = 0.0
    @pulse_time = 0.0
    @initialized = false
  end

  def init_gl_resources!
    return if @initialized

    @char_img = create_character_image
    @sprite = Sprite.new(@init_x, @init_y, @char_img)
    apply_anchor(ANCHOR_PRESETS[@anchor_idx][:val])
    apply_pivot(PIVOT_PRESETS[@pivot_idx][:val])
    apply_collider_by_index(@shape_idx)
    @initialized = true
  end

  def apply_anchor(val)
    @sprite.anchor = val
  end

  def apply_pivot(val)
    @sprite.pivot = val
  end

  def apply_collider_by_index(idx)
    preset = SHAPE_PRESETS[idx]
    cur_ox = @sprite ? @sprite.collider_offset_x : 0.0
    cur_oy = @sprite ? @sprite.collider_offset_y : 0.0
    case preset[:id]
    when :rect
      @sprite.set_collider(:rect, width: 90, height: 130, radius: 0.0, offset_x: cur_ox, offset_y: cur_oy)
    when :rounded_rect
      @sprite.set_collider(:rect, width: 90, height: 130, radius: 24.0, offset_x: cur_ox, offset_y: cur_oy)
    when :circle
      @sprite.set_collider(:circle, radius: 52.0, offset_x: cur_ox, offset_y: cur_oy)
    when :ellipse
      @sprite.set_collider(:circle, radius_x: 40.0, radius_y: 65.0, offset_x: cur_ox, offset_y: cur_oy)
    when :hexagon
      @sprite.set_collider(:polygon, vertices: HEXAGON_VERTICES, offset_x: cur_ox, offset_y: cur_oy)
    end
  end

  def reset_all!
    @sprite.x = @init_x
    @sprite.y = @init_y
    @sprite.angle = 0.0
    @sprite.scale_x = 1.0
    @sprite.scale_y = 1.0
    @anchor_idx = 0
    @pivot_idx = 0
    @shape_idx = 0
    apply_anchor(ANCHOR_PRESETS[@anchor_idx][:val])
    apply_pivot(PIVOT_PRESETS[@pivot_idx][:val])
    @sprite.collider_offset_x = 0.0
    @sprite.collider_offset_y = 0.0
    apply_collider_by_index(@shape_idx)
    @slider_scale_x&.set_value_quietly(1.0)
    @slider_scale_y&.set_value_quietly(1.0)
    @slider_offset_x&.set_value_quietly(0.0)
    @slider_offset_y&.set_value_quietly(0.0)
    refresh_button_states
  end

  def update(mx, my)
    @pulse_time += Window.delta_time

    # マウス判定円の座標更新
    @mouse_circle.x = mx
    @mouse_circle.y = my

    # キーボードショートカット
    reset_all! if Input.key_push?(:r)

    # [1] Anchor 切替
    if Input.key_push?(:"1")
      @anchor_idx = (@anchor_idx + 1) % ANCHOR_PRESETS.length
      apply_anchor(ANCHOR_PRESETS[@anchor_idx][:val])
      refresh_button_states
    end

    # [2] Pivot 切替
    if Input.key_push?(:"2")
      @pivot_idx = (@pivot_idx + 1) % PIVOT_PRESETS.length
      apply_pivot(PIVOT_PRESETS[@pivot_idx][:val])
      refresh_button_states
    end

    # [3] Shape 切替 (全5種を順送り)
    if Input.key_push?(:"3")
      @shape_idx = (@shape_idx + 1) % SHAPE_PRESETS.length
      apply_collider_by_index(@shape_idx)
      refresh_button_states
    end

    # [W][A][S][D] / 矢印キー: Offset 移動
    spd = 2.0
    @sprite.collider_offset_x += spd if Input.key_pressed?(:d) || Input.key_pressed?(:right)
    @sprite.collider_offset_x -= spd if Input.key_pressed?(:a) || Input.key_pressed?(:left)
    @sprite.collider_offset_y += spd if Input.key_pressed?(:s) || Input.key_pressed?(:down)
    @sprite.collider_offset_y -= spd if Input.key_pressed?(:w) || Input.key_pressed?(:up)

    if Input.key_push?(:space)
      @sprite.collider_offset_x = 0.0
      @sprite.collider_offset_y = 0.0
    end

    # [Q][E]: 回転
    @sprite.angle += 2.0 if Input.key_pressed?(:e)
    @sprite.angle -= 2.0 if Input.key_pressed?(:q)

    # マウスによるドラッグ操作
    if @drag_target == :sprite
      if Input.mouse_pressed?(:left)
        @sprite.x = mx - @drag_start_mx
        @sprite.y = my - @drag_start_my
      else
        @drag_target = nil
      end
    elsif @drag_target == :rotate
      if Input.mouse_pressed?(:right)
        # ワールドピボットを中心とした相対ドラッグ回転
        tl_x = @sprite.x - @sprite.anchor_x * @sprite.width
        tl_y = @sprite.y - @sprite.anchor_y * @sprite.height
        wpv_x = tl_x + @sprite.pivot_x * @sprite.width
        wpv_y = tl_y + @sprite.pivot_y * @sprite.height

        dx = mx - wpv_x
        dy = my - wpv_y
        if dx * dx + dy * dy > 25.0
          mouse_ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
          @sprite.angle = mouse_ang - @rotate_base_angle
        end
      else
        @drag_target = nil
      end
    else
      # ドラッグ開始判定 (GUI操作・ホバーしていない場合のみ開始)
      unless GUI.mouse_captured?
        if Input.mouse_push?(:left)
          # スプライト掴み開始
          @drag_target = :sprite
          @drag_start_mx = mx - @sprite.x
          @drag_start_my = my - @sprite.y
        elsif Input.mouse_push?(:right)
          # 右ボタンドラッグ開始: ピボットとマウスの現在角度の差分を基準角として記録
          tl_x = @sprite.x - @sprite.anchor_x * @sprite.width
          tl_y = @sprite.y - @sprite.anchor_y * @sprite.height
          wpv_x = tl_x + @sprite.pivot_x * @sprite.width
          wpv_y = tl_y + @sprite.pivot_y * @sprite.height

          dx = mx - wpv_x
          dy = my - wpv_y
          mouse_ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
          @rotate_base_angle = mouse_ang - @sprite.angle
          @drag_target = :rotate
        end
      end
    end

    # 衝突判定の実行
    @is_hit = @sprite.collide?(@mouse_circle)
  end

  def draw(mx, my)
    Window.clear([16, 20, 30, 255])

    # 1. ワールド座標グリッド
    (0..1280).step(40) do |gx|
      col = (gx % 200 == 0) ? [35, 45, 65, 255] : [24, 30, 45, 255]
      Window.draw_line(gx, 0, gx, 720, color: col, width: 1.0)
    end
    (0..720).step(40) do |gy|
      col = (gy % 200 == 0) ? [35, 45, 65, 255] : [24, 30, 45, 255]
      Window.draw_line(0, gy, 1280, gy, color: col, width: 1.0)
    end

    # 幾何データの算出
    sp = @sprite
    w = sp.width
    h = sp.height
    ax = sp.anchor_x
    ay = sp.anchor_y
    px = sp.pivot_x
    py = sp.pivot_y
    ang = sp.angle
    rad = ang * Math::PI / 180.0
    col = sp.collider

    # スプライト左上ワールド座標
    tl_x = sp.x - ax * w
    tl_y = sp.y - ay * h

    # ワールド回転ピボット
    wpv_x = tl_x + px * w
    wpv_y = tl_y + py * h

    # スプライト中心 (未回転ローカル)
    sp_cx_world = tl_x + w * 0.5
    sp_cy_world = tl_y + h * 0.5

    # 2. ピボットの回転軸ガイド線 (十字点線)
    Window.draw_line(wpv_x - 120, wpv_y, wpv_x + 120, wpv_y, color: [70, 75, 95, 180], width: 1.0)
    Window.draw_line(wpv_x, wpv_y - 120, wpv_x, wpv_y + 120, color: [70, 75, 95, 180], width: 1.0)

    # 3. スプライト本体の描画
    Window.draw_sprite(sp)

    # 4. スプライト画像の外枠 (回転後バウンディング矩形)
    Window.draw_path do |c|
      c.save
      c.translate(wpv_x, wpv_y)
      c.rotate(rad)
      c.scale(sp.scale_x, sp.scale_y)
      # ピボットを原点としたスプライト左上
      c.begin_path
      c.rect(-px * w, -py * h, w, h)
      c.stroke([60, 160, 240, 200], 2.0)
      c.restore
    end

    # 5. コライダー（当たり判定）の描画
    if col
      col_border = @is_hit ? [255, 60, 80, 255] : [60, 230, 160, 240]
      col_body   = @is_hit ? [255, 60, 80, 80]  : [60, 230, 160, 40]
      col_w_px   = @is_hit ? 3.0 : 2.0

      if col.is_a?(Collision::Rect)
        Window.draw_path do |c|
          c.save
          c.translate(col.center_x, col.center_y)
          c.rotate(col.angle * Math::PI / 180.0)
          c.scale(col.scale_x, col.scale_y)
          c.begin_path
          if col.radius > 0.0
            c.round_rect(-col.half_w, -col.half_h, col.width, col.height, col.radius)
          else
            c.rect(-col.half_w, -col.half_h, col.width, col.height)
          end
          c.fill(col_body)
          c.stroke(col_border, col_w_px)
          c.restore
        end
      elsif col.is_a?(Collision::Circle)
        rx = col.radius_x * col.scale_x.abs
        ry = col.radius_y * col.scale_y.abs
        if (rx - ry).abs < 0.001
          Window.draw_circle(col.center_x, col.center_y, rx,
                            color: col_body,
                            border_color: col_border,
                            border_width: col_w_px)
        else
          Window.draw_path do |c|
            c.save
            c.begin_path
            c.ellipse(col.center_x, col.center_y, rx, ry, col.angle * Math::PI / 180.0)
            c.close_path
            c.fill(col_body)
            c.stroke(col_border, col_w_px)
            c.restore
          end
        end
      elsif col.is_a?(Collision::Polygon)
        col.update_cache if col.dirty?
        verts = col.local_vertices
        v_len = verts ? verts.length : 0
        if v_len > 0
          Window.draw_path do |c|
            c.save
            c.translate(col.center_x, col.center_y)
            c.rotate(col.angle * Math::PI / 180.0)
            c.scale(col.scale_x, col.scale_y)
            c.begin_path
            vi = 0
            while vi < v_len
              v = verts[vi]
              if vi == 0
                c.move_to(v[0], v[1])
              else
                c.line_to(v[0], v[1])
              end
              vi += 1
            end
            c.close_path
            c.fill(col_body)
            c.stroke(col_border, col_w_px)
            c.restore
          end
        end
      end

      # 6. Offset 矢印 (Sprite回転中心〜Collider中心)
      # スプライト画像の回転後幾何中心 (scale_x, scale_y を反映)
      cos_v = Math.cos(rad)
      sin_v = Math.sin(rad)
      sc_dx = (0.5 - px) * w * sp.scale_x
      sc_dy = (0.5 - py) * h * sp.scale_y
      rot_sp_cx = wpv_x + sc_dx * cos_v - sc_dy * sin_v
      rot_sp_cy = wpv_y + sc_dx * sin_v + sc_dy * cos_v

      if sp.collider_offset_x.abs > 0.5 || sp.collider_offset_y.abs > 0.5
        Window.draw_line(rot_sp_cx, rot_sp_cy, col.center_x, col.center_y, color: [200, 100, 255, 230], width: 2.0)
        Window.draw_circle(col.center_x, col.center_y, 4, color: [220, 120, 255, 255])
      end
    end

    # 7. ピボット位置マーカー (黄色の星 / 二重丸)
    Window.draw_circle(wpv_x, wpv_y, 8, color: [255, 210, 60, 255], border_color: [120, 90, 20, 255], border_width: 2.0)
    Window.draw_circle(wpv_x, wpv_y, 3, color: [255, 255, 255, 255])
    Window.draw_text(wpv_x + 12, wpv_y - 20, "Pivot (#{px.round(2)}, #{py.round(2)})", size: 15, color: [255, 220, 80, 255])

    # 回転ドラッグ中の操作ガイド線
    if @drag_target == :rotate
      Window.draw_line(wpv_x, wpv_y, mx, my, color: [255, 230, 80, 220], width: 2.0)
      Window.draw_circle(mx, my, 7, color: [255, 140, 60, 255])
    end

    # 8. ワールド (x, y) ターゲットマーカー (赤いクロスヘア)
    Window.draw_line(sp.x - 12, sp.y, sp.x + 12, sp.y, color: [255, 80, 90, 255], width: 2.0)
    Window.draw_line(sp.x, sp.y - 12, sp.x, sp.y + 12, color: [255, 80, 90, 255], width: 2.0)
    Window.draw_circle(sp.x, sp.y, 5, color: [0, 0, 0, 0], border_color: [255, 80, 90, 255], border_width: 2.0)
    Window.draw_text(sp.x + 14, sp.y + 4, "(x, y) = (#{sp.x.round(1)}, #{sp.y.round(1)})", size: 15, color: [255, 120, 130, 255])

    # 9. Anchor マーカー (緑色ピン)
    Window.draw_circle(sp.x, sp.y, 7, color: [50, 220, 120, 190])
    Window.draw_text(sp.x - 90, sp.y - 22, "Anchor: #{ANCHOR_PRESETS[@anchor_idx][:name]}", size: 15, color: [80, 230, 140, 255])

    # 10. マウス追従コライダー (検査円)
    m_body   = @is_hit ? [255, 60, 80, 180]  : [255, 190, 60, 140]
    m_border = @is_hit ? [255, 255, 255, 255] : [255, 230, 100, 255]
    Window.draw_circle(mx, my, @mouse_circle.radius, color: m_body, border_color: m_border, border_width: 3.0)
    # 照準芯
    Window.draw_circle(mx, my, 4, color: [255, 255, 255, 255])

    # 衝突エフェクト (パルス波紋)
    if @is_hit
      pulse_r = @mouse_circle.radius + 8.0 + (Math.sin(@pulse_time * 15.0) * 5.0)
      Window.draw_circle(mx, my, pulse_r, color: [0, 0, 0, 0], border_color: [255, 90, 110, 200], border_width: 2.5)
      Window.draw_text(mx - 32, my - 52, "HIT!!", size: 24, color: [255, 90, 110, 255])
    end

    # 11. ヘッダー / HUD 情報パネル & GUI コントロール
    # 一時的に専用カスタムテーマを適用して描画 (新機能: GUI.with_theme)
    GUI.with_theme(:coords_navy) do
      draw_hud(mx, my)
    end
  end

  def draw_hud(_mx, _my)
    # 左上タイトル
    GUI.label("Zenoo Sprite & Collision Coords Visualizer", x: 25, y: 18, size: 28, color: :white)
    GUI.label("Anchor / Pivot / Offset / Position 実機シミュレーター", x: 25, y: 54, size: 16, color: [150, 185, 230, 255])

    # 衝突ステータスバナー
    status_bg = @is_hit ? [220, 50, 70, 220] : [30, 45, 65, 200]
    status_border = @is_hit ? [255, 100, 120, 255] : [60, 85, 120, 200]
    status_text = @is_hit ? "COLLISION DETECTED! (HIT)" : "NO COLLISION (CLEAR)"
    status_tcol = @is_hit ? [255, 255, 255, 255] : [120, 230, 160, 255]

    GUI.panel(x: 25, y: 84, w: 430, h: 46, radius: 8, color: status_bg, border_color: status_border, border_width: 2.0)
    GUI.label(status_text, x: 42, y: 96, size: 18, color: status_tcol)

    # スライダー調整パネル (Scale X/Y, Offset X/Y)
    GUI.panel("[ スケール & オフセット調整 (スライダー) ]", x: 25, y: 140, w: 430, h: 260, title_size: 15, title_color: [160, 205, 255, 255], spacing_y: 10) do
      @sprite.scale_x = GUI.slider("Sprite Scale X", @sprite.scale_x, 0.2, 2.5, step: 0.05, unit: "x")
      @sprite.scale_y = GUI.slider("Sprite Scale Y", @sprite.scale_y, 0.2, 2.5, step: 0.05, unit: "x")
      @sprite.collider_offset_x = GUI.slider("Collider Offset X", @sprite.collider_offset_x, -80.0, 80.0, step: 1.0, unit: "px")
      @sprite.collider_offset_y = GUI.slider("Collider Offset Y", @sprite.collider_offset_y, -80.0, 80.0, step: 1.0, unit: "px")
    end

    # 左下パラメータモニター
    GUI.panel("[ リアルタイム・パラメータ ]", x: 25, y: 415, w: 530, h: 280, title_size: 16, title_color: [160, 205, 255, 255], spacing_y: 12) do
      sp = @sprite
      off_x = sp ? sp.collider_offset_x.round(1) : 0.0
      off_y = sp ? sp.collider_offset_y.round(1) : 0.0

      GUI.label("World Pos (x, y) : (#{sp.x.round(1)}, #{sp.y.round(1)}) [左ドラッグで移動]", size: 15, color: [255, 120, 130, 255])
      GUI.label("Scale (X, Y)     : (#{sp.scale_x.round(2)}, #{sp.scale_y.round(2)}) [スライダーで個別調整]", size: 15, color: [140, 220, 255, 255])
      GUI.label("Anchor           : #{ANCHOR_PRESETS[@anchor_idx][:name]} (#{sp.anchor_x.round(2)}, #{sp.anchor_y.round(2)})", size: 15, color: [80, 230, 140, 255])
      GUI.label("Pivot (回転支点) : #{PIVOT_PRESETS[@pivot_idx][:name]} (#{sp.pivot_x.round(2)}, #{sp.pivot_y.round(2)})", size: 15, color: [255, 210, 80, 255])
      GUI.label("Angle (回転角)   : #{sp.angle.round(1)} deg [右ドラッグ / Q / E]", size: 15, color: [120, 190, 255, 255])
      GUI.label("Collider Offset  : (#{off_x}, #{off_y}) [スライダー / WASD / SPACE]", size: 15, color: [210, 130, 255, 255])
      GUI.label("Collider Shape   : #{SHAPE_PRESETS[@shape_idx][:name]} (#{SHAPE_PRESETS[@shape_idx][:desc]})", size: 15, color: [180, 210, 230, 255])
      GUI.label("FPS: #{Window.fps.round(1)}  |  [R]キーで初期配置にリセット", size: 14, color: [140, 160, 195, 255])
    end

    # 右上パネル見出し & ボタン群 (GUI.button による即時モードUI)
    GUI.label("[ 1. Anchor (配置基準) ]  キー [1]", x: 860, y: 20, size: 16, color: [100, 235, 150, 255])
    ANCHOR_PRESETS.each_with_index do |p, i|
      bx = (i % 2 == 0) ? 860 : 1065
      by = 48 + (i / 2) * 40
      if GUI.button("Anchor: #{p[:label]}", x: bx, y: by, w: 195, h: 34, active: (i == @anchor_idx))
        @anchor_idx = i
        apply_anchor(p[:val])
      end
    end

    GUI.label("[ 2. Pivot (回転軸) ]    キー [2]", x: 860, y: 168, size: 16, color: [255, 220, 90, 255])
    PIVOT_PRESETS.each_with_index do |p, i|
      bx = (i % 2 == 0) ? 860 : 1065
      by = 196 + (i / 2) * 40
      if GUI.button("Pivot: #{p[:label]}", x: bx, y: by, w: 195, h: 34, active: (i == @pivot_idx))
        @pivot_idx = i
        apply_pivot(p[:val])
      end
    end

    GUI.label("[ 3. Collider 形状 (全5種) ]  キー [3]", x: 860, y: 290, size: 16, color: [160, 210, 255, 255])
    SHAPE_PRESETS.each_with_index do |p, i|
      bx = (i % 2 == 0) ? 860 : 1065
      by = 318 + (i / 2) * 40
      if GUI.button(p[:btn_label], x: bx, y: by, w: 195, h: 34, active: (i == @shape_idx))
        @shape_idx = i
        apply_collider_by_index(i)
      end
    end

    # 右側操作ヘルプパネル
    GUI.panel("[ 操作ガイド ]", x: 860, y: 440, w: 400, h: 255, title_size: 15, title_color: [255, 215, 120, 255], spacing_y: 11) do
      GUI.label("・マウス移動 : 検査円を動かしてリアルタイム衝突テスト", size: 13, color: [200, 215, 235, 255])
      GUI.label("・左ドラッグ : スプライト本体の (x, y) を移動", size: 13, color: [200, 215, 235, 255])
      GUI.label("・右ドラッグ / [Q][E] : スプライトを回転 (angle)", size: 13, color: [200, 215, 235, 255])
      GUI.label("・スライダー : Scale X/Y, Offset X/Y をドラッグ調整", size: 13, color: [255, 230, 140, 255])
      GUI.label("・[W][A][S][D] / 矢印 : 当たり判定 Offset を移動", size: 13, color: [200, 215, 235, 255])
      GUI.label("・[1][2][3] キー : Anchor / Pivot / 形状 を順送り", size: 13, color: [200, 215, 235, 255])
      GUI.label("・[SPACE] : Offsetリセット  |  [R] : 全設定リセット", size: 13, color: [255, 200, 150, 255])
    end
  end

  def step_frame
    init_gl_resources!

    mx = Input.mouse_x
    my = Input.mouse_y
    mx = 640.0 if mx < 0 || mx > 1280
    my = 360.0 if my < 0 || my > 720

    update(mx, my)
    draw(mx, my)
  end
end

# ----------------------------------------------------
# 実行エントリーポイント
# ----------------------------------------------------
simulator = CoordsSimulator.new
test_frames = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1280, 720, "Zenoo - Sprite & Collision Coords Visualizer", msaa: 4) do
  simulator.step_frame
  if test_frames > 0
    frame_count += 1
    if frame_count >= test_frames
      puts "Visualizer test completed! (#{frame_count} frames)"
      exit
    end
  end
end

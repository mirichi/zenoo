# frozen_string_literal: true
require_relative "../lib/zenoo"

# ====================================================================
# Zenoo Canvas × Mesh × Sprite デモ (examples/demo_canvas_mesh.rb)
#
# Canvas のベクター描画を Mesh 化 (Mesh.canvas) することで得られる 4 つの強み:
# 1. 【毎フレームの分割負荷ゼロ & 1ドローコール大量描画】
#    耳刈り分割 (fill) や太線展開 (stroke) を初回1回だけ実行して VRAM (VBO+IBO) に常駐。
#    同じベクター Mesh を共有する多数の Sprite を 1 ドローコールで高速バッチ描画！
# 2. 【拡大してもボケないベクター品質】
#    テクスチャ (Image) への焼き込みと異なり、何倍に拡大・回転してもエッジが完全にシャープ。
# 3. 【ベクター図形のリアルタイム頂点変形 (Mesh#deform)】
#    Canvas で描いた複雑な図形やグラデーションに対して、スライムのぷるぷる変形や波打ちが可能。
# 4. 【Sprite の親子階層 (Parent-Child) とのシームレスな融合】
#    多重魔法陣や多関節メカのパーツを Canvas で描き、Sprite の階層構造で自在にアニメーション。
# ====================================================================

# --------------------------------------------------------------------
# ① 幾何学クリスタル弾 (1ドローコールで120個を群れ描画する用)
# --------------------------------------------------------------------
crystal_mesh = Zenoo::Mesh.canvas(36, 36, blend: :add) do |c|
  grad = c.create_linear_gradient(18, 2, 18, 34)
  grad.add_color_stop(0.0, [255, 255, 255, 255])
  grad.add_color_stop(0.4, [120, 230, 255, 230])
  grad.add_color_stop(1.0, [40,  100, 255, 160])

  # 外側ダイヤ
  c.begin_path
  c.move_to(18, 2)
  c.line_to(30, 18)
  c.line_to(18, 34)
  c.line_to(6,  18)
  c.close_path
  c.fill(grad)
  c.stroke([200, 250, 255, 220], 1.5)

  # 内側コア
  c.begin_path
  c.move_to(18, 8)
  c.line_to(24, 18)
  c.line_to(18, 28)
  c.line_to(12, 18)
  c.close_path
  c.fill([255, 255, 255, 220])
end

# 同じ crystal_mesh を共有する 120 個の Sprite
PALETTE = [
  [120, 240, 255],
  [255, 130, 220],
  [255, 220, 100],
  [140, 255, 170]
].freeze

crystal_sprites = Array.new(120) do |i|
  s = Sprite.new(0, 0, crystal_mesh, anchor: :center, pivot: :center)
  s.color = PALETTE[i % PALETTE.size]
  s
end

# --------------------------------------------------------------------
# ② 多重ベクター魔法陣 (Sprite の親子階層 + 巨大拡大でもシャープなベクター線)
# --------------------------------------------------------------------
outer_ring_mesh = Zenoo::Mesh.canvas(220, 220, blend: :add) do |c|
  cx, cy = 110.0, 110.0
  c.stroke_circle(cx, cy, 102, [100, 220, 255, 220], 3.0)
  c.stroke_circle(cx, cy, 92,  [80,  180, 255, 160], 1.5)

  # 六芒星 (2つの正三角形)
  2.times do |k|
    c.begin_path
    3.times do |i|
      ang = k * (Math::PI / 3.0) + i * (Math::PI * 2.0 / 3.0)
      px = cx + Math.cos(ang) * 92.0
      py = cy + Math.sin(ang) * 92.0
      i == 0 ? c.move_to(px, py) : c.line_to(px, py)
    end
    c.close_path
    c.line_join = :miter
    c.stroke([140, 235, 255, 200], 2.5)
  end

  # 外周のルーン目盛り
  12.times do |i|
    ang = i * (Math::PI / 6.0)
    x1 = cx + Math.cos(ang) * 92.0
    y1 = cy + Math.sin(ang) * 92.0
    x2 = cx + Math.cos(ang) * 102.0
    y2 = cy + Math.sin(ang) * 102.0
    c.begin_path
    c.move_to(x1, y1)
    c.line_to(x2, y2)
    c.stroke([220, 250, 255, 240], 2.5)
  end
end

inner_gear_mesh = Zenoo::Mesh.canvas(140, 140, blend: :add) do |c|
  cx, cy = 70.0, 70.0
  grad = c.create_radial_gradient(cx, cy, 4, cx, cy, 60)
  grad.add_color_stop(0.0, [255, 240, 180, 220])
  grad.add_color_stop(0.6, [255, 160, 80,  120])
  grad.add_color_stop(1.0, [255, 80,  160, 0])
  c.fill_circle(cx, cy, 58, grad)

  # 8枚の光翼
  c.begin_path
  16.times do |i|
    ang = i * (Math::PI / 8.0)
    r = i.even? ? 56.0 : 24.0
    px = cx + Math.cos(ang) * r
    py = cy + Math.sin(ang) * r
    i == 0 ? c.move_to(px, py) : c.line_to(px, py)
  end
  c.close_path
  c.line_join = :round
  c.stroke([255, 220, 130, 230], 2.5)
end

# 親 Sprite (外輪) に 子 Sprite (内輪) をアタッチ (親の中心を原点 0, 0 として同心円配置)
magic_root = Sprite.new(770, 210, outer_ring_mesh, anchor: :center, pivot: :center)
magic_core = Sprite.new(0, 0, inner_gear_mesh, anchor: :center, pivot: :center, parent: magic_root)

# --------------------------------------------------------------------
# ③ ぷるぷる頂点変形するベクター・スライム (鮮やかな多段階グラデーション)
# --------------------------------------------------------------------
slime_mesh = Zenoo::Mesh.canvas(180, 160) do |c|
  # 上部(イエロー) → 中央(シアン) → 下部(マゼンタ・パープル) の鮮やかな3色グラデーション
  body_grad = c.create_linear_gradient(90, 28, 90, 145)
  body_grad.add_color_stop(0.0,  [255, 245, 90,  255]) # 頭頂部: ブライトイエロー
  body_grad.add_color_stop(0.45, [40,  235, 255, 250]) # 中央部: ネオンシアン
  body_grad.add_color_stop(1.0,  [220, 50,  200, 250]) # 底部:   ディープマゼンタ

  # スライムの輪郭を滑らかな多角形で構築
  c.begin_path
  steps = 36
  steps.times do |i|
    ang = i * (Math::PI * 2.0 / steps)
    rx = 66.0
    ry = Math.sin(ang) > 0 ? 48.0 : 62.0 # 下側を少し平らに、上側をドーム状に
    px = 90.0 + Math.cos(ang) * rx
    py = 92.0 + Math.sin(ang) * ry
    i == 0 ? c.move_to(px, py) : c.line_to(px, py)
  end
  c.close_path
  c.fill(body_grad)
  c.line_join = :round
  c.stroke([255, 255, 255, 245], 4.0)

  # ほっぺの赤み (放射グラデーション)
  [52.0, 128.0].each do |cheek_x|
    cheek_grad = c.create_radial_gradient(cheek_x, 102, 2, cheek_x, 102, 14)
    cheek_grad.add_color_stop(0.0, [255, 90, 150, 220])
    cheek_grad.add_color_stop(1.0, [255, 90, 150, 0])
    c.fill_circle(cheek_x, 102, 14, cheek_grad)
  end

  # ハイライト & 目
  c.fill_circle(64, 60, 11, [255, 255, 255, 210])
  c.fill_circle(54, 74, 5,  [255, 255, 255, 180])
  c.fill_circle(70, 92, 8,  [20, 25, 55, 255])
  c.fill_circle(110, 92, 8, [20, 25, 55, 255])
  c.fill_circle(68, 89, 3,  :white)
  c.fill_circle(108, 89, 3, :white)
end
slime_sprite = Sprite.new(770, 490, slime_mesh, anchor: :center, pivot: :center)

t = 0.0
frame_count = 0
max_test_frames = ENV["TEST_FRAMES"]&.to_i

Window.loop(1024, 640, "Zenoo Canvas-to-Mesh Showcase") do
  Window.clear([14, 18, 30])
  t += 1.0 / 60.0
  frame_count += 1

  # ----------------------------------------------------
  # ① 左半分: 120個のベクタークリスタル群 (1 Draw Call!)
  # ----------------------------------------------------
  cx_swarm = 270.0
  cy_swarm = 340.0
  crystal_sprites.each_with_index do |sp, i|
    ring = i / 20
    idx_in_ring = i % 20
    base_r = 42.0 + ring * 34.0
    speed = (ring.even? ? 1.0 : -1.0) * (1.2 - ring * 0.12)
    ang = idx_in_ring * (Math::PI * 2.0 / 20.0) + t * speed + Math.sin(t * 2.0 + ring) * 0.3

    r = base_r + Math.sin(t * 3.0 + i * 0.5) * 10.0
    sp.x = cx_swarm + Math.cos(ang) * r
    sp.y = cy_swarm + Math.sin(ang) * r
    sp.angle = (ang * 180.0 / Math::PI) + 90.0
    sc = 0.7 + 0.35 * Math.sin(t * 4.0 + i)
    sp.scale_x = sc
    sp.scale_y = sc
  end
  # 120 個のベクター Sprite をたった 1 回のドローコールで一括描画
  Sprite.draw(crystal_sprites)

  # ----------------------------------------------------
  # ② 右上: 多重ベクター魔法陣 (親子 Sprite 階層 + 拡縮してもシャープ)
  # ----------------------------------------------------
  magic_root.angle = t * 24.0
  pulse = 1.0 + Math.sin(t * 2.5) * 0.22
  magic_root.scale_x = pulse
  magic_root.scale_y = pulse
  # 子 Sprite は親の逆回転で回る
  magic_core.angle = -t * 65.0
  magic_root.draw
  magic_core.draw

  # ----------------------------------------------------
  # ③ 右下: 頂点変形 (deform) でぷるぷる揺れるベクター・スライム
  # ----------------------------------------------------
  slime_mesh.deform do |v|
    dx = v.base_x - 90.0
    dy = v.base_y - 92.0
    # 接地側 (下側) ほど横に広がり、頭頂部ほど縦に揺れるソフトボディ変形
    squash = Math.sin(t * 6.0) * 0.14
    wave_x = Math.sin(t * 8.0 + v.base_y * 0.06) * 4.5
    v.x = 90.0 + dx * (1.0 + squash) + wave_x
    v.y = 92.0 + dy * (1.0 - squash)
  end
  slime_sprite.angle = Math.sin(t * 3.0) * 5.0
  slime_sprite.draw

  # ----------------------------------------------------
  # UI 説明ラベル
  # ----------------------------------------------------
  Window.draw_text(28, 20, "Zenoo::Mesh.canvas Showcase (Vector Art -> 8-float Vertex Color VBO)", size: 22, color: :white)
  Window.draw_text(40, 68, "① 120 Vector Crystal Sprites = 1 Draw Call", size: 18, color: :yellow)
  Window.draw_text(40, 92, "   初回のみ Canvas で多角形分割し、毎フレームは GPU インスタンシングのみで描画", size: 14, color: [190, 220, 255])

  Window.draw_text(560, 68, "② Parent-Child Vector Magic Circle", size: 18, color: :yellow)
  Window.draw_text(560, 92, "   ベクター頂点なので拡大・回転しても線が一切ボケない", size: 14, color: [190, 220, 255])

  Window.draw_text(560, 365, "③ Mesh#deform on Vector Art", size: 18, color: :yellow)
  Window.draw_text(560, 389, "   Canvas で描いたグラデーション図形を直接ソフトボディ頂点変形", size: 14, color: [190, 220, 255])

  break if max_test_frames && frame_count >= max_test_frames
end

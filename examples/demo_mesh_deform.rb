# frozen_string_literal: true
require_relative "../lib/zenoo"

# ====================================================================
# Zenoo 2D Mesh 変形 & 2バッファインスタンシング デモ
# - Stream 0 (頂点VBO: [x, y, u, v, alpha] + IBO)
# - Stream 1 (インスタンスVBO: アフィン変換行列 + 色調 + UV矩形)
# ====================================================================

# 1. 旗・波揺らぎ用のテクスチャ生成 (160 x 100)
flag_img = Image.new(160, 100)
Image.render_to(flag_img) do
  Window.clear(:clear)
  Window.draw_rect(0, 0, 160, 100, radius: 10, color: [35, 110, 210, 255], border_width: 3, border_color: [160, 220, 255, 255])
  # 格子模様とエンブレム
  4.times do |i|
    Window.draw_line(32 * (i + 1), 6, 32 * (i + 1), 94, width: 2, color: [80, 160, 245, 140])
  end
  Window.draw_line(6, 50, 154, 50, width: 2, color: [80, 160, 245, 140])
  Window.draw_circle(80, 50, 26, color: [255, 215, 70, 255], border_width: 3, border_color: [255, 245, 180, 255])
  Window.draw_text(44, 38, "ZENOO", size: 22, color: [20, 45, 95, 255])
end

# 16×8 分割の格子メッシュを作成 (初期状態は GL_STATIC_DRAW で VRAM 常駐)
flag_mesh = Zenoo::Mesh.grid(flag_img, cols: 16, rows: 8)

# 同じ flag_mesh を共有する 3 つの Sprite (それぞれ位置・角度・スケール・色調が別でも 1 ドローコールで一括描画！)
flag_sprites = [
  Sprite.new(60,  110, flag_mesh),
  Sprite.new(250, 125, flag_mesh).tap { |s| s.scale_x = 0.75; s.scale_y = 0.75; s.angle = -8; s.color = [180, 255, 220] },
  Sprite.new(250, 220, flag_mesh).tap { |s| s.scale_x = 0.75; s.scale_y = 0.75; s.angle =  8; s.color = [255, 200, 230] }
]

# 2. 4隅自由変形 (set_corners) 用のカードテクスチャ (160 x 120)
card_img = Image.new(160, 120)
Image.render_to(card_img) do
  Window.clear(:clear)
  Window.draw_rect(0, 0, 160, 120, radius: 12, color: [50, 40, 95, 255], border_width: 4, border_color: [220, 180, 255, 255])
  4.times do |ix|
    3.times do |iy|
      next if (ix + iy).odd?
      Window.draw_rect(8 + ix * 36, 8 + iy * 34, 36, 34, color: [85, 70, 145, 180])
    end
  end
  Window.draw_text(22, 46, "4-CORNERS", size: 22, color: :yellow)
end
# 8×8 格子分割により対角線の折れ歪みが出ない滑らかな自由変形メッシュ
corner_mesh = Zenoo::Mesh.grid(card_img, cols: 8, rows: 8)

# 3. リボン・剣閃トレイル (set_ribbon) 用のテクスチャ (200 x 36)
trail_img = Image.new(200, 36)
Image.render_to(trail_img) do
  Window.clear(:clear)
  Window.draw_rect(0, 4, 200, 28, radius: 14, color: [60, 220, 255, 220])
  Window.draw_line(4, 18, 196, 18, width: 8, cap: :round, color: [230, 255, 255, 255])
end
trail_mesh = Zenoo::Mesh.grid(trail_img, cols: 24, rows: 2, blend: :add)
trail_points = Array.new(25) { [240.0, 460.0] }

# 4. リング・渦巻きメッシュ (Mesh.ring) 用のテクスチャ (160 x 160)
vortex_img = Image.new(160, 160)
Image.render_to(vortex_img) do
  Window.clear(:clear)
  Window.draw_circle(80, 80, 74, color: [30, 160, 190, 200], border_width: 4, border_color: [160, 250, 255, 255])
  8.times do |i|
    ang = i * Math::PI * 0.25
    x2 = 80 + Math.cos(ang) * 70
    y2 = 80 + Math.sin(ang) * 70
    Window.draw_line(80, 80, x2, y2, width: 4, color: [190, 250, 255, 200])
  end
  Window.draw_circle(80, 80, 28, color: [255, 120, 210, 230])
end
vortex_mesh = Zenoo::Mesh.ring(vortex_img, slices: 32, rings: 6, inner_radius: 0.15)

# 5. 多角形メッシュ (Mesh.polygon: 凹多角形の自動三角形分割)
star_pts = []
10.times do |i|
  ang = -Math::PI * 0.5 + i * Math::PI / 5.0
  r = i.even? ? 72.0 : 32.0
  star_pts << [80.0 + Math.cos(ang) * r, 80.0 + Math.sin(ang) * r]
end
star_mesh = Zenoo::Mesh.polygon(vortex_img, star_pts)

t = 0.0
frame_count = 0
max_test_frames = ENV["TEST_FRAMES"]&.to_i

Window.loop(1024, 640, "Zenoo 2D Mesh Deformation & 2-Stream Instancing Demo") do
  Window.clear([18, 22, 34])
  t += 1.0 / 60.0
  frame_count += 1

  # ----------------------------------------------------
  # ① 旗メッシュの波変形 + 頂点アルファ減衰 (deform)
  # ----------------------------------------------------
  flag_mesh.deform do |v|
    # 左端 (base_u == 0) は固定し、右に行くほど振幅を大きくする
    amp = v.base_u * 16.0
    wave = Math.sin(t * 5.0 - v.base_u * 6.0 + v.base_v * 1.5) * amp
    v.x = v.base_x + wave * 0.25
    v.y = v.base_y + wave
    # 右端に向かって少し透ける頂点アルファ演出
    v.alpha = 1.0 - v.base_u * 0.35 * (0.5 + 0.5 * Math.sin(t * 3.0 + v.base_v * 2.0))
  end

  # 同じ flag_mesh を持つ 3 つの Sprite を 1 ドローコールで描画
  Sprite.draw(flag_sprites)

  # ----------------------------------------------------
  # ② 4隅の自由変形 (set_corners)
  # ----------------------------------------------------
  sway_x = Math.sin(t * 2.2) * 28.0
  sway_y = Math.cos(t * 1.7) * 18.0
  corner_mesh.set_corners(
    [25.0 + sway_x,       10.0 - sway_y * 0.5], # 左上
    [135.0 + sway_x,      10.0 + sway_y * 0.5], # 右上
    [165.0 - sway_x * 0.6, 115.0 + sway_y],     # 右下
    [-5.0 - sway_x * 0.6,  115.0 - sway_y],     # 左下
    alphas: [0.85, 0.85, 1.0, 1.0]
  )
  Window.draw(480, 125, corner_mesh)

  # ----------------------------------------------------
  # ③ リボン・軌跡変形 (set_ribbon)
  # ----------------------------------------------------
  head_x = 230.0 + Math.cos(t * 2.8) * 140.0
  head_y = 470.0 + Math.sin(t * 5.6) * 65.0
  trail_points.unshift([head_x, head_y])
  trail_points.pop

  # 中心線に沿って太さ 36px、末端に向かって細く (taper: true) & 透明に減衰 (fade: true)
  trail_mesh.set_ribbon(trail_points, width: 36.0, fade: true, taper: [1.0, 0.05])
  trail_mesh.draw(0, 0)
  Window.draw_circle(head_x, head_y, 8, color: :white)

  # ----------------------------------------------------
  # ④ リングメッシュの渦巻き変形 (Mesh.ring + deform)
  # ----------------------------------------------------
  vortex_mesh.deform do |v|
    dx = v.base_x - 80.0
    dy = v.base_y - 80.0
    dist = Math.hypot(dx, dy)
    # 中心に近いほど強くねじる
    twist = (1.0 - (dist / 80.0).clamp(0.0, 1.0)) * Math.sin(t * 2.5) * 1.8
    ca = Math.cos(twist)
    sa = Math.sin(twist)
    v.x = 80.0 + dx * ca - dy * sa
    v.y = 80.0 + dx * sa + dy * ca
    v.alpha = 0.5 + 0.5 * (dist / 80.0).clamp(0.0, 1.0)
  end
  vortex_mesh.draw(500, 390, angle: t * 25.0)

  # ----------------------------------------------------
  # ⑤ 多角形メッシュの脈動変形 (Mesh.polygon + deform)
  # ----------------------------------------------------
  star_mesh.deform do |v|
    dx = v.base_x - 80.0
    dy = v.base_y - 80.0
    scale = 1.0 + Math.sin(t * 4.0 + v.index * 0.8) * 0.15
    v.x = 80.0 + dx * scale
    v.y = 80.0 + dy * scale
  end
  star_mesh.draw(760, 390, angle: -t * 20.0)

  # UI 説明ラベル
  Window.draw_text(30, 22, "Zenoo::Mesh Redesign Demo (8-float Vertex VBO + IBO + 16-float Instance VBO)", size: 22, color: :white)
  Window.draw_text(45, 78, "① Mesh.grid + deform (3 Sprites sharing 1 Mesh = 1 Draw Call)", size: 16, color: :yellow)
  Window.draw_text(460, 78, "② Mesh.grid + set_corners (4隅バイリニア自由変形)", size: 16, color: :yellow)
  Window.draw_text(45, 345, "③ Mesh.grid + set_ribbon (fade: true, taper: true 軌跡リボン)", size: 16, color: :yellow)
  Window.draw_text(460, 345, "④ Mesh.ring 渦巻き変形", size: 16, color: :yellow)
  Window.draw_text(740, 345, "⑤ Mesh.polygon 星型分割", size: 16, color: :yellow)

  break if max_test_frames && frame_count >= max_test_frames
end

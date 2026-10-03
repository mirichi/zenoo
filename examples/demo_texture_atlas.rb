# frozen_string_literal: true

require_relative '../lib/zenoo'

# 日本語フォントとテーマ
GUI.theme.font = Font::MPLUS
GUI.theme.font_size = 16

# ----------------------------------------------------
# 1. 動的テクスチャアトラスの構築 (オフスクリーン描画)
# ----------------------------------------------------
ATLAS_SIZE = 256
SLOT_SIZE  = 64 # 4x4 = 計 16 スロット

# 各サブ画像に対して Image.render_to でグラフィックスをベイク！
# ※ sub_image に対して render_to を呼ぶと、自動的にローカル (0, 0) 〜 (64, 64) にクリッピングされます。

# [行 0]: コイン回転 (4 フレーム: 幅を変えて回転を表現)
def bake_coins(slots)
  4.times do |i|
    slot = slots[i]
    Image.render_to(slot) do
      Window.clear(Color.new(0, 0, 0, 0))

      scale_x = Math.cos(i * (Math::PI / 2.0)).abs
      cw = [SLOT_SIZE * 0.7 * scale_x, 6.0].max
      ch = SLOT_SIZE * 0.7
      cx = (SLOT_SIZE - cw) / 2.0
      cy = (SLOT_SIZE - ch) / 2.0

      Window.draw_card(cx, cy, cw, ch, radius: [cw, ch].min / 2.0,
                                       color: Color.new(255, 215, 0),
                                       border_width: 2.0,
                                       border_color: Color.new(200, 150, 0))
      if cw > 14.0
        Window.draw_card(cx + 4.0, cy + 4.0, cw - 8.0, ch - 8.0,
                         radius: [cw - 8.0, ch - 8.0].min / 2.0,
                         color: Color.new(255, 235, 120))
      end
    end
  end
end

# [行 1]: クリスタル (4 フレーム: 輝きと脈動)
def bake_crystals(slots)
  4.times do |i|
    slot = slots[4 + i]
    Image.render_to(slot) do
      Window.clear(Color.new(0, 0, 0, 0))
      pulse = 1.0 + 0.1 * Math.sin(i * Math::PI / 2.0)
      size = 28.0 * pulse
      cx = SLOT_SIZE / 2.0
      cy = SLOT_SIZE / 2.0

      c_top = Color.new(120, 220, 255)
      c_bot = Color.new(40, 100, 230)
      Window.draw_triangle(cx, cy - size, cx - size * 0.6, cy, cx + size * 0.6, cy, c_top)
      Window.draw_triangle(cx, cy + size, cx - size * 0.6, cy, cx + size * 0.6, cy, c_bot)
    end
  end
end

# [行 2]: アイテム (ハート、スター、シールド、ポーション)
def bake_heart(slot)
  Image.render_to(slot) do
    Window.clear(Color.new(0, 0, 0, 0))
    Window.draw_card(14, 16, 20, 20, radius: 10.0, color: Color.new(255, 60, 100))
    Window.draw_card(30, 16, 20, 20, radius: 10.0, color: Color.new(255, 60, 100))
    Window.draw_triangle(14, 26, 50, 26, 32, 52, Color.new(255, 60, 100))
  end
end

def bake_star(slot)
  Image.render_to(slot) do
    Window.clear(Color.new(0, 0, 0, 0))
    Window.draw_triangle(32, 10, 14, 48, 50, 48, Color.new(255, 230, 50))
    Window.draw_triangle(32, 54, 14, 20, 50, 20, Color.new(255, 230, 50))
  end
end

def bake_shield(slot)
  Image.render_to(slot) do
    Window.clear(Color.new(0, 0, 0, 0))
    Window.draw_card(16, 12, 32, 38, radius: 12.0, color: Color.new(70, 180, 100),
                                    border_width: 3.0, border_color: Color.new(230, 255, 230))
  end
end

def bake_potion(slot)
  Image.render_to(slot) do
    Window.clear(Color.new(0, 0, 0, 0))
    Window.draw_card(26, 10, 12, 8, radius: 2.0, color: Color.new(200, 200, 220))
    Window.draw_card(18, 18, 28, 36, radius: 14.0, color: Color.new(180, 70, 240, 220),
                                    border_width: 2.0, border_color: Color.new(240, 200, 255))
  end
end

def bake_items(slots)
  bake_heart(slots[8])
  bake_star(slots[9])
  bake_shield(slots[10])
  bake_potion(slots[11])
end

# [行 3]: キャラクター (プレイヤーの 4 フレーム歩行)
def bake_players(slots)
  4.times do |i|
    slot = slots[12 + i]
    Image.render_to(slot) do
      Window.clear(Color.new(0, 0, 0, 0))
      bob = (i.even? ? 0.0 : 2.0)
      Window.draw_card(20, 12 - bob, 24, 24, radius: 12.0, color: Color.new(255, 210, 170))
      Window.draw_card(18, 32 - bob, 28, 22, radius: 6.0, color: Color.new(40, 130, 255))
      leg_offset = (i == 1 ? 4.0 : (i == 3 ? -4.0 : 0.0))
      Window.draw_card(20 + leg_offset, 50 - bob, 8, 10, radius: 2.0, color: Color.new(40, 50, 80))
      Window.draw_card(36 - leg_offset, 50 - bob, 8, 10, radius: 2.0, color: Color.new(40, 50, 80))
    end
  end
end

def build_texture_atlas
  atlas = Image.new(ATLAS_SIZE, ATLAS_SIZE)

  # 各スロットを sub_image で切り出す
  # [行 0]: コインの回転アニメーション (4フレーム)
  # [行 1]: クリスタルの浮遊アニメーション (4フレーム)
  # [行 2]: ゲームアイテム (ハート、スター、シールド、ポーション)
  # [行 3]: キャラクター (プレイヤーの 4 フレーム)
  slots = {}
  4.times do |row|
    4.times do |col|
      idx = row * 4 + col
      slots[idx] = atlas.sub_image(col * SLOT_SIZE, row * SLOT_SIZE, SLOT_SIZE, SLOT_SIZE)
    end
  end

  bake_coins(slots)
  bake_crystals(slots)
  bake_items(slots)
  bake_players(slots)

  [atlas, slots]
end

# ----------------------------------------------------
# 2. パーティクル & スプライト管理 (穏やかに浮遊)
# ----------------------------------------------------
class FloatingSprite
  attr_accessor :x, :y, :vx, :vy, :slot_type, :scale, :anim_timer, :anim_frame

  def initialize(slot_type)
    @slot_type = slot_type # 0: コイン, 1: クリスタル, 2: アイテム, 3: プレイヤー
    @anim_timer = rand(0.0..0.4) # パーティクルごとに位相をずらす
    @anim_frame = rand(0..3)
    reset
  end

  def reset
    @x = rand(40.0..720.0)
    @y = rand(360.0..670.0)
    angle = rand(0.0..(Math::PI * 2.0))
    speed = rand(15.0..40.0) # ゆっくりと穏やかに漂う
    @vx = Math.cos(angle) * speed
    @vy = Math.sin(angle) * speed
    @scale = rand(0.7..1.0)
  end

  def update(dt)
    @x += @vx * dt
    @y += @vy * dt

    # 各スプライトが個別にゆったりアニメーション (0.4秒間隔)
    @anim_timer += dt
    if @anim_timer >= 0.4
      @anim_timer = 0.0
      @anim_frame = (@anim_frame + 1) % 4
    end

    if @x < 30.0 || @x > 730.0
      @vx = -@vx
      @x = @x.clamp(30.0, 730.0)
    end
    if @y < 350.0 || @y > 670.0
      @vy = -@vy
      @y = @y.clamp(350.0, 670.0)
    end
  end

  def current_slot
    case @slot_type
    when 0 then @anim_frame      # コイン (0..3)
    when 1 then 4 + @anim_frame  # クリスタル (4..7)
    when 2 then 8 + @anim_frame  # アイテム (8..11)
    when 3 then 12 + @anim_frame # プレイヤー (12..15)
    end
  end
end

# ----------------------------------------------------
# 描画サブコンポーネント (Spinel 最適化 & C関数分割)
# ----------------------------------------------------

# 単一ギャラリーアイテムの描画
def draw_gallery_item(bx, by, cat, sprite)
  Window.draw_card(bx, by, 150.0, 170.0,
                   radius: 8.0,
                   color: Color.new(18, 22, 32),
                   border_width: 1.0,
                   border_color: Color.new(45, 60, 85),
                   z: 6.0)

  Window.draw_image(bx + 43.0, by + 30.0, sprite, z: 7.0)

  Window.draw_text(bx + 20.0, by + 115.0, cat[:title],
                   font: Font::MPLUS, size: 13, color: Color::WHITE, z: 7.0)
  Window.draw_text(bx + 20.0, by + 138.0, "Slot ##{cat[:slot]} (64x64)",
                   font: Font::MPLUS, size: 12, color: Color.new(130, 150, 180), z: 7.0)
end

# B. スプライトギャラリー展示台 (落ち着いて細部を観察できるエリア)
def draw_gallery_slots(gallery_x, gallery_y, slots, gallery_frame)
  gallery_w = 720.0
  gallery_h = 240.0

  Window.draw_card(gallery_x, gallery_y, gallery_w, gallery_h,
                   radius: 10.0,
                   color: Color.new(24, 30, 42, 230),
                   border_width: 1.0,
                   border_color: Color.new(50, 70, 95),
                   z: 5.0)

  Window.draw_text(gallery_x + 20.0, gallery_y + 15.0, "SubImage Gallery (Baked Slots)",
                   font: Font::MPLUS, size: 16, color: Color::CYAN, z: 6.0)

  # 4 つのカテゴリ展示
  categories = [
    { title: "Coin (Anim)",    slot: gallery_frame },
    { title: "Crystal (Anim)", slot: 4 + gallery_frame },
    { title: "Items (Static)", slot: 8 + gallery_frame },
    { title: "Player (Walk)",  slot: 12 + gallery_frame }
  ]

  categories.each_with_index do |cat, i|
    bx = gallery_x + 25.0 + i * 170.0
    by = gallery_y + 45.0
    draw_gallery_item(bx, by, cat, slots[cat[:slot]])
  end
end

# C. 下部エリア: 穏やかな浮遊スプライト (同一アトラスによる自動バッチ)
def draw_ambient_field(field_x, field_y, field_w, field_h, particles, slots, dt)
  Window.draw_card(field_x, field_y, field_w, field_h,
                   radius: 10.0,
                   color: Color.new(20, 25, 36, 200),
                   border_width: 1.0,
                   border_color: Color.new(45, 58, 80),
                   z: 5.0)

  Window.draw_text(field_x + 20.0, field_y + 15.0, "Ambient Batch Field (Smooth Floating)",
                   font: Font::MPLUS, size: 15, color: Color.new(170, 190, 220), z: 6.0)

  particles.each do |p|
    p.update(dt)
    sprite = slots[p.current_slot]
    Window.draw_image(
      p.x, p.y, sprite,
      scale: p.scale,
      pivot: :center,
      z: 10.0
    )
  end
end

# D-0. パネル内テキスト描画ヘルパー (Spinel AOT インライン展開の局所化)
def draw_panel_text(x, y, text, size = 14, color = Color::WHITE)
  Window.draw_text(x, y, text, font: Font::MPLUS, size: size, color: color, z: 52.0)
end

# D-1. アトラスグリッド枠線の描画
def draw_atlas_grid(atlas_draw_x, atlas_draw_y)
  4.times do |r|
    4.times do |c|
      gx = atlas_draw_x + c * SLOT_SIZE
      gy = atlas_draw_y + r * SLOT_SIZE
      Window.draw_card(gx, gy, SLOT_SIZE, SLOT_SIZE,
                       radius: 0.0, color: Color.new(0, 0, 0, 0),
                       border_width: 1.0, border_color: Color.new(255, 255, 255, 35), z: 53.0)
    end
  end
end

# D-2. src_rect による直接切り出しプレビュー
def draw_atlas_preview(prev_x, prev_y, atlas, gallery_frame)
  draw_panel_text(prev_x, prev_y, "src_rect Direct:", 13, Color.new(255, 215, 0))
  Window.draw_card(prev_x, prev_y + 22.0, 140.0, 140.0,
                   radius: 6.0, color: Color.new(14, 17, 24),
                   border_width: 1.0, border_color: Color.new(70, 90, 125), z: 51.0)

  Window.draw_image(
    prev_x + 38.0, prev_y + 50.0, atlas,
    src_rect: [gallery_frame * SLOT_SIZE, 3 * SLOT_SIZE, SLOT_SIZE, SLOT_SIZE],
    scale: 1.0,
    z: 52.0
  )
  draw_panel_text(prev_x + 15.0, prev_y + 125.0, "Player Frame #{gallery_frame}", 12, Color.new(160, 180, 210))
end

# D-3. パフォーマンス & バッチ統計情報
def draw_batch_stats(panel_x, stats_y, panel_w, sprite_count)
  Window.draw_card(panel_x + 20.0, stats_y - 20.0, panel_w - 40.0, 280.0,
                   radius: 8.0, color: Color.new(18, 22, 32, 230),
                   border_width: 1.0, border_color: Color.new(45, 60, 85), z: 51.0)

  draw_panel_text(panel_x + 35.0, stats_y, "Batching & Architecture", 16, Color::WHITE)
  draw_panel_text(panel_x + 35.0, stats_y + 30.0, "FPS: #{Window.fps.round(1)}", 14, Color.new(0, 255, 180))
  draw_panel_text(panel_x + 35.0, stats_y + 55.0, "Active Sprites: #{sprite_count}", 14, Color.new(255, 200, 80))
  draw_panel_text(panel_x + 35.0, stats_y + 80.0, "Texture Binds: 1 (Atlas Shared)", 14, Color.new(0, 220, 255))
  draw_panel_text(panel_x + 35.0, stats_y + 115.0, "Features Demonstrated:", 14, Color::WHITE)
  draw_panel_text(panel_x + 45.0, stats_y + 140.0, "- Image#sub_image (Zero Allocation View)", 13, Color.new(170, 190, 220))
  draw_panel_text(panel_x + 45.0, stats_y + 165.0, "- Image.render_to (Slot Local Clipping)", 13, Color.new(170, 190, 220))
  draw_panel_text(panel_x + 45.0, stats_y + 190.0, "- DrawQueue Auto-Batching (1 Draw Call)", 13, Color.new(170, 190, 220))
  draw_panel_text(panel_x + 45.0, stats_y + 215.0, "- Window.draw_image(..., src_rect: [...])", 13, Color.new(170, 190, 220))
end

# D. 右側サイドパネル: テクスチャアトラスインスペクター
def draw_inspector_panel(panel_x, panel_y, panel_w, panel_h, atlas, gallery_frame, sprite_count)
  Window.draw_card(panel_x, panel_y, panel_w, panel_h,
                   radius: 12.0,
                   color: Color.new(24, 30, 42, 245),
                   border_width: 1.5,
                   border_color: Color.new(50, 70, 100),
                   shadow_blur: 15.0,
                   z: 50.0)

  draw_panel_text(panel_x + 20.0, panel_y + 18.0, "Texture Atlas Inspector", 18, Color::CYAN)
  draw_panel_text(panel_x + 20.0, panel_y + 44.0, "Atlas: #{atlas.width}x#{atlas.height} px | Texture ID: #{atlas.texture_id}", 13, Color.new(160, 180, 210))

  # 元のアトラス全体 (256x256) を描画
  atlas_draw_x = panel_x + 20.0
  atlas_draw_y = panel_y + 75.0
  Window.draw_card(atlas_draw_x - 2.0, atlas_draw_y - 2.0, ATLAS_SIZE + 4.0, ATLAS_SIZE + 4.0,
                   radius: 4.0, color: Color.new(10, 12, 18),
                   border_width: 1.5, border_color: Color.new(70, 90, 125), z: 51.0)
  Window.draw_image(atlas_draw_x, atlas_draw_y, atlas, z: 52.0)

  draw_atlas_grid(atlas_draw_x, atlas_draw_y)
  draw_atlas_preview(atlas_draw_x + ATLAS_SIZE + 20.0, atlas_draw_y + 20.0, atlas, gallery_frame)
  draw_batch_stats(panel_x, panel_y + 380.0, panel_w, sprite_count)
end

# ----------------------------------------------------
# 3. メインループ
# ----------------------------------------------------
# 45 個の穏やかな浮遊スプライト (すべて同一アトラス)
particles = Array.new(45) do
  FloatingSprite.new(rand(0..3))
end

# ギャラリー用のアニメーションタイマー (0.4 秒周期)
gallery_timer = 0.0
gallery_frame = 0

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

atlas = nil
slots = nil

Window.loop(1280, 720, "Zenoo Texture Atlas & sub_image Showcase") do
  atlas, slots = build_texture_atlas if atlas.nil?

  dt = [Window.delta_time, 0.05].min

  # ギャラリーのアニメーション更新 (ゆっくり 0.4 秒周期)
  gallery_timer += dt
  if gallery_timer >= 0.4
    gallery_timer = 0.0
    gallery_frame = (gallery_frame + 1) % 4
  end

  # 背景描画 (落ち着いたダークネイビー)
  Window.clear(Color.new(16, 20, 30))

  # ----------------------------------------------------
  # A. ヘッダー & 説明UI
  # ----------------------------------------------------
  GUI.cursor(30.0, 20.0)
  GUI.label("=== Zenoo Texture Atlas & sub_image Showcase ===", size: 22, color: Color::WHITE)
  GUI.label("1枚のテクスチャ (256x256) から切り出した sub_image 群を、自動バッチ結合により単一ドローコールで高速描画しています。", size: 14, color: Color.new(160, 180, 210))

  # ----------------------------------------------------
  # B. スプライトギャラリー展示台
  # ----------------------------------------------------
  draw_gallery_slots(30.0, 85.0, slots, gallery_frame)

  # ----------------------------------------------------
  # C. 下部エリア: 穏やかな浮遊スプライト
  # ----------------------------------------------------
  draw_ambient_field(30.0, 340.0, 720.0, 350.0, particles, slots, dt)

  # ----------------------------------------------------
  # D. 右側サイドパネル: テクスチャアトラスインスペクター
  # ----------------------------------------------------
  draw_inspector_panel(770.0, 20.0, 480.0, 670.0, atlas, gallery_frame, particles.size + 5)

  # マウスクリックで穏やかに追加
  if Input.mouse_pressed?(:left) && Input.mouse_x < 770.0 && Input.mouse_y > 340.0
    p = FloatingSprite.new(rand(0..3))
    p.x = Input.mouse_x
    p.y = Input.mouse_y
    particles << p
  end

  # スペースキーでリセット
  if Input.key_push?(:space)
    particles = Array.new(45) { FloatingSprite.new(rand(0..3)) }
  end

  # 自動テスト終了
  if test_max > 0
    frame_count += 1
    if frame_count >= test_max
      puts "Texture Atlas demo test completed successfully! (#{frame_count} frames)"
      break
    end
  end
end

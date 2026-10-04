# frozen_string_literal: true

require_relative '../lib/zenoo'

# ==============================================================================
# Zenoo GJK Collision Demo (DXRuby Style Interactive Playground)
# - 左ボタンドラッグ: 図形を掴んで自由に移動
# - 右ボタンドラッグ: 図形を中心軸で直感的に回転
# - [R] キー: 全図形の配置と角度を初期状態にリセット
# ==============================================================================

class ShapeItem
  attr_accessor :name, :shape, :type, :init_x, :init_y, :init_angle, :hit

  def initialize(name, shape, type)
    @name = name
    @shape = shape
    @type = type
    @init_x = shape.x
    @init_y = shape.y
    @init_angle = shape.angle
    @hit = false
  end

  def reset!
    @shape.x = @init_x
    @shape.y = @init_y
    @shape.angle = @init_angle
    @hit = false
  end
end

class CollisionPlayground
  attr_accessor :items, :mouse_pt, :active_item, :drag_mode
  attr_accessor :drag_offset_x, :drag_offset_y, :rotate_base_angle
  attr_accessor :hit_count

  def initialize
    @items = create_items
    @mouse_pt = Collision.point(0.0, 0.0)
    @active_item = nil
    @drag_mode = nil
    @drag_offset_x = 0.0
    @drag_offset_y = 0.0
    @rotate_base_angle = 0.0
    @hit_count = 0
  end

  def create_items
    [
      # 1. 回転矩形 (OBB)
      ShapeItem.new("OBB (Rotated Rect)", Collision.rect(220, 220, 140, 80, angle: 25), :rect),

      # 2. 真円 (Circle)
      ShapeItem.new("Circle", Collision.circle(470, 220, 50), :circle),

      # 3. 楕円状の円 (Rotated Circle: rx != ry)
      ShapeItem.new("Ellipse", Collision.circle(730, 220, 75, 35, angle: 30), :ellipse),

      # 4. 角丸矩形 (Rounded Rect)
      ShapeItem.new("Rounded Rect", Collision.rect(1000, 220, 130, 80, radius: 20, angle: 10), :rounded_rect),

      # 5. 不等スケール角丸矩形 (Scaled Rounded Rect)
      ShapeItem.new("Scaled Rounded Rect", Collision.rect(220, 470, 110, 70, radius: 18, angle: -15, scale_x: 1.4, scale_y: 0.8), :rounded_rect),

      # 6. セグメント (Segment: 両端が半円)
      ShapeItem.new("Segment (Round Ends)", Collision.segment(420, 440, 560, 520, 25), :rounded_rect),

      # 7. 太線 (Line: 端面が直角の OBB)
      ShapeItem.new("Line (Flat Ends)", Collision.line(690, 460, 850, 510, 36), :rect),

      # 8. 凸五角形 (Polygon)
      ShapeItem.new(
        "Pentagon",
        Collision.polygon([
          [0.0, -50.0],
          [48.0, -15.0],
          [30.0, 42.0],
          [-30.0, 42.0],
          [-48.0, -15.0]
        ], x: 1020, y: 470, angle: 15),
        :polygon
      ),

      # 9. 三角形 (Polygon)
      ShapeItem.new(
        "Triangle",
        Collision.polygon([
          [0.0, -50.0],
          [45.0, 35.0],
          [-45.0, 35.0]
        ], x: 600, y: 340, angle: 45),
        :polygon
      )
    ]
  end

  def reset_all!
    i = 0
    len = @items.length
    while i < len
      @items[i].reset!
      i += 1
    end
    @active_item = nil
    @drag_mode = nil
  end

  def find_item_at(mx, my)
    @mouse_pt.x = mx
    @mouse_pt.y = my
    i = @items.length - 1
    while i >= 0
      item = @items[i]
      return item if Collision.check(@mouse_pt, item.shape)
      i -= 1
    end
    nil
  end

  def update(mx, my)
    reset_all! if Input.key_push?(:r)

    if Input.mouse_push?(:left)
      found = find_item_at(mx, my)
      if found
        @active_item = found
        @drag_mode = :move
        @drag_offset_x = mx - @active_item.shape.center_x
        @drag_offset_y = my - @active_item.shape.center_y
        @items.delete(@active_item)
        @items << @active_item
      else
        @active_item = nil
        @drag_mode = nil
      end
    end

    if Input.mouse_push?(:right)
      found = find_item_at(mx, my) || @active_item
      if found
        @active_item = found
        @drag_mode = :rotate
        dx = mx - @active_item.shape.center_x
        dy = my - @active_item.shape.center_y
        mouse_ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
        @rotate_base_angle = mouse_ang - @active_item.shape.angle
        @items.delete(@active_item)
        @items << @active_item
      end
    end

    if @drag_mode == :move && @active_item
      if Input.mouse_pressed?(:left)
        target_cx = mx - @drag_offset_x
        target_cy = my - @drag_offset_y
        diff_x = target_cx - @active_item.shape.center_x
        diff_y = target_cy - @active_item.shape.center_y
        @active_item.shape.x += diff_x
        @active_item.shape.y += diff_y
      else
        @drag_mode = nil
      end
    elsif @drag_mode == :rotate && @active_item
      if Input.mouse_pressed?(:right)
        dx = mx - @active_item.shape.center_x
        dy = my - @active_item.shape.center_y
        if dx * dx + dy * dy > 25.0
          mouse_ang = Math.atan2(dy, dx) * (180.0 / Math::PI)
          @active_item.shape.angle = mouse_ang - @rotate_base_angle
        end
      else
        @drag_mode = nil
      end
    end

    @drag_mode = nil if Input.mouse_release?(:left) && @drag_mode == :move
    @drag_mode = nil if Input.mouse_release?(:right) && @drag_mode == :rotate
  end

  def check_collisions
    len = @items.length
    i = 0
    while i < len
      @items[i].hit = false
      i += 1
    end

    @hit_count = 0
    i = 0
    while i < len
      a = @items[i]
      j = i + 1
      while j < len
        b = @items[j]
        if Collision.check(a.shape, b.shape)
          a.hit = true
          b.hit = true
          @hit_count += 1
        end
        j += 1
      end
      i += 1
    end
  end

  def draw_shape(item, is_active, is_hover)
    body_col = if item.hit
                 [240, 75, 95, 220]
               elsif is_active
                 [90, 185, 255, 230]
               elsif is_hover
                 [75, 160, 235, 215]
               else
                 [55, 130, 210, 190]
               end

    border_col = if is_active
                   [255, 240, 90, 255]
                 elsif is_hover
                   [220, 240, 255, 255]
                 elsif item.hit
                   [255, 180, 190, 255]
                 else
                   [150, 190, 230, 160]
                 end

    border_w = (is_active || item.hit) ? 3.0 : 1.5

    case item.type
    when :circle
      c = item.shape
      Window.draw_circle(c.center_x, c.center_y, c.effective_radius, color: body_col, border_color: border_col, border_width: border_w)

    when :ellipse
      el = item.shape
      Window.draw_path do |c|
        c.begin_path
        c.ellipse(el.center_x, el.center_y, el.radius_x * el.scale_x, el.radius_y * el.scale_y, el.angle * Math::PI / 180.0)
        c.close_path
        c.fill(body_col)
        c.stroke(border_col, border_w)
      end

    when :rect
      r = item.shape
      sx = r.scale_x.abs
      sy = r.scale_y.abs
      max_s = sx > sy ? sx : sy
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.scale(r.scale_x, r.scale_y)
        c.begin_path
        c.rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height)
        c.fill(body_col)
        c.stroke(border_col, border_w / max_s)
        c.restore
      end

    when :rounded_rect
      r = item.shape
      sx = r.scale_x.abs
      sy = r.scale_y.abs
      max_s = sx > sy ? sx : sy
      Window.draw_path do |c|
        c.save
        c.translate(r.center_x, r.center_y)
        c.rotate(r.angle * Math::PI / 180.0)
        c.scale(r.scale_x, r.scale_y)
        c.begin_path
        c.round_rect(-r.width * 0.5, -r.height * 0.5, r.width, r.height, r.radius)
        c.fill(body_col)
        c.stroke(border_col, border_w / max_s)
        c.restore
      end

    when :polygon
      poly = item.shape
      sx = poly.scale_x.abs
      sy = poly.scale_y.abs
      max_s = sx > sy ? sx : sy
      verts = poly.local_vertices
      v_len = verts.length
      Window.draw_path do |c|
        c.save
        c.translate(poly.center_x, poly.center_y)
        c.rotate(poly.angle * Math::PI / 180.0)
        c.scale(poly.scale_x, poly.scale_y)
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
        c.fill(body_col)
        c.stroke(border_col, border_w / max_s)
        c.restore
      end
    end

    label_y = item.shape.center_y + item.shape.bounding_radius + 8
    label_y = 705 if label_y > 705
    draw_ui_text(item.shape.center_x - (item.name.length * 3.5), label_y, item.name, size: 12, color: is_active ? [255, 230, 100, 255] : [170, 190, 210, 200])
  end

  def draw_ui_text(x, y, text, size: 14, color: :white)
    Window.draw_text(x, y, text, size: size, color: color)
  end

  def draw(mx, my)
    Window.clear([18, 22, 32, 255])

    draw_ui_text(40, 22, "Zenoo GJK Collision Playground", size: 24, color: :white)
    draw_ui_text(40, 52, "Pure Ruby GJK Engine - Zero Allocations - Infinite Shapes", size: 14, color: [140, 165, 195, 255])
    draw_ui_text(40, 76, "[左ドラッグ]: 図形をつかんで移動   |   [右ドラッグ]: 図形を回転   |   [R]: 初期配置にリセット", size: 14, color: [255, 215, 80, 255])

    hover_item = find_item_at(mx, my)

    i = 0
    len = @items.length
    while i < len
      item = @items[i]
      draw_shape(item, item == @active_item, item == hover_item)
      i += 1
    end

    if @drag_mode == :rotate && @active_item
      cx = @active_item.shape.center_x
      cy = @active_item.shape.center_y
      Window.draw_line(cx, cy, mx, my, color: [255, 230, 80, 200], width: 2)
      Window.draw_circle(cx, cy, 5, color: [255, 230, 80, 255])
      Window.draw_circle(mx, my, 6, color: [255, 120, 80, 255])
    end

    status_color = (@hit_count > 0) ? [255, 90, 90, 255] : [100, 255, 150, 255]
    Window.draw_rect(30, 645, 420, 52, radius: 8, color: [20, 28, 42, 220], border_width: 1, border_color: [60, 80, 110, 255])
    draw_ui_text(45, 653, "Status: #{@hit_count > 0 ? "COLLISION DETECTED (#{@hit_count} pairs)" : 'No Collision'}", size: 15, color: status_color)
    act_name = @active_item ? @active_item.name : 'None'
    dmode = @drag_mode ? @drag_mode.to_s : 'idle'
    draw_ui_text(45, 674, "FPS: #{Window.fps.round(1)}  |  Active: #{act_name} (#{dmode})", size: 13, color: [180, 200, 220, 255])
  end

  def step_frame
    mx, my = Input.mouse_pos
    mx = 640.0 if mx < 0 || mx > 1280
    my = 360.0 if my < 0 || my > 720

    update(mx, my)
    check_collisions
    draw(mx, my)
  end
end

playground = CollisionPlayground.new
test_frames = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_counter = 0

Window.loop(1280, 720, "Zenoo GJK Collision Playground") do
  playground.step_frame
  if test_frames > 0
    frame_counter += 1
    if frame_counter >= test_frames
      puts "Collision test completed successfully! (#{frame_counter} frames)"
      exit
    end
  end
end

# frozen_string_literal: true

require_relative 'color'
require_relative 'window'

module Zenoo
  class Canvas
    attr_accessor :fill_style, :stroke_style, :line_width, :line_cap, :line_join, :miter_limit, :global_alpha

    # 2D 変換行列 [a, c, e; b, d, f; 0, 0, 1]
    # x' = a*x + c*y + e
    # y' = b*x + d*y + f
    class Transform
      attr_accessor :a, :b, :c, :d, :e, :f

      def initialize(a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0)
        @a = a.to_f
        @b = b.to_f
        @c = c.to_f
        @d = d.to_f
        @e = e.to_f
        @f = f.to_f
      end

      def apply(x, y)
        [
          @a * x + @c * y + @e,
          @b * x + @d * y + @f
        ]
      end

      def multiply(other)
        Transform.new(
          @a * other.a + @c * other.b,
          @b * other.a + @d * other.b,
          @a * other.c + @c * other.d,
          @b * other.c + @d * other.d,
          @a * other.e + @c * other.f + @e,
          @b * other.e + @d * other.f + @f
        )
      end

      def translate(dx, dy)
        @e += @a * dx + @c * dy
        @f += @b * dx + @d * dy
      end

      def scale(sx, sy)
        @a *= sx
        @b *= sx
        @c *= sy
        @d *= sy
      end

      def rotate(rad)
        cos = Math.cos(rad)
        sin = Math.sin(rad)
        na = @a * cos + @c * sin
        nb = @b * cos + @d * sin
        nc = -@a * sin + @c * cos
        nd = -@b * sin + @d * cos
        @a = na
        @b = nb
        @c = nc
        @d = nd
      end

      def dup
        Transform.new(@a, @b, @c, @d, @e, @f)
      end
    end

    class SubPath
      attr_accessor :points, :closed

      def initialize
        @points = []
        @closed = false
      end

      def empty?
        @points.empty?
      end

      def last_point
        @points.last
      end
    end

    class LinearGradient
      attr_reader :x0, :y0, :x1, :y1, :stops

      def initialize(x0, y0, x1, y1)
        @x0 = x0.to_f
        @y0 = y0.to_f
        @x1 = x1.to_f
        @y1 = y1.to_f
        @stops = []
      end

      def add_color_stop(offset, color)
        @stops << [offset.to_f, color]
        @stops.sort_by! { |s| s[0] }
        self
      end
    end

    class RadialGradient
      attr_reader :x0, :y0, :r0, :x1, :y1, :r1, :stops

      def initialize(x0, y0, r0, x1 = x0, y1 = y0, r1 = r0)
        @x0 = x0.to_f
        @y0 = y0.to_f
        @r0 = r0.to_f
        @x1 = x1.to_f
        @y1 = y1.to_f
        @r1 = r1.to_f
        @stops = []
      end

      def add_color_stop(offset, color)
        @stops << [offset.to_f, color]
        @stops.sort_by! { |s| s[0] }
        self
      end
    end

    def initialize
      @fill_style = [1.0, 1.0, 1.0, 1.0]
      @stroke_style = [1.0, 1.0, 1.0, 1.0]
      @line_width = 1.0
      @line_cap = :butt     # :butt, :round, :square
      @line_join = :miter   # :miter, :bevel, :round
      @miter_limit = 10.0
      @global_alpha = 1.0

      @transform = Transform.new
      @state_stack = []
      @subpaths = []
      @mesh_capture = nil
      begin_path
    end

    # Canvas の描画内容を頂点カラー付き Zenoo::Mesh に変換するクラスメソッド
    # 例:
    #   mesh = Zenoo::Canvas.to_mesh(100, 100) do |c|
    #     c.fill_circle(50, 50, 40, :orange)
    #     c.stroke_circle(50, 50, 40, :white, 4)
    #   end
    def self.to_mesh(width_or_image = nil, height_arg = nil, width: nil, height: nil, image: nil, shader: nil, uniforms: nil, blend: :alpha, &block)
      new.to_mesh(width_or_image, height_arg, width: width, height: height, image: image, shader: shader, uniforms: uniforms, blend: blend, &block)
    end

    # 現在の Canvas またはブロック内の描画命令 (fill / stroke / fill_rect 等) をキャプチャし、
    # Sprite や Window.draw にそのまま渡せる Zenoo::Mesh (8 floats/頂点) を生成して返します。
    def to_mesh(width_or_image = nil, height_arg = nil, width: nil, height: nil, image: nil, shader: nil, uniforms: nil, blend: :alpha)
      if width_or_image.is_a?(Image)
        img = width_or_image
        explicit_w = width || img.width
        explicit_h = height || img.height
      else
        img = image
        explicit_w = width || width_or_image
        explicit_h = height || height_arg || (img ? img.height : nil)
      end

      prev_capture = @mesh_capture
      cap_verts = []
      cap_indices = []
      @mesh_capture = { vertices: cap_verts, indices: cap_indices }
      begin
        yield(self) if block_given?
        # ブロック内でパスだけ構築されて fill / stroke がまだ呼ばれていない場合は自動 fill
        if cap_verts.empty? && @subpaths.any? { |s| s.points.size >= 3 }
          fill
        end
      ensure
        @mesh_capture = prev_capture
      end

      v_count = cap_verts.length / 8
      if v_count == 0
        w = (explicit_w || 1.0).to_f
        h = (explicit_h || explicit_w || 1.0).to_f
        return Mesh.from_vertices([0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0] * 3, [0, 1, 2], width: w, height: h, image: img, shader: shader, uniforms: uniforms, blend: blend)
      end

      min_x = Float::INFINITY
      min_y = Float::INFINITY
      max_x = -Float::INFINITY
      max_y = -Float::INFINITY
      vi = 0
      while vi < cap_verts.length
        px = cap_verts[vi]
        py = cap_verts[vi + 1]
        min_x = px if px < min_x
        min_y = py if py < min_y
        max_x = px if px > max_x
        max_y = py if py > max_y
        vi += 8
      end

      # サイズ未指定かつ負の座標を含む場合 (例: 原点(0,0)中心で描画した場合) は左上を (0,0) に自動シフト
      if explicit_w.nil? && explicit_h.nil? && (min_x < 0.0 || min_y < 0.0)
        shift_x = -min_x
        shift_y = -min_y
        vi = 0
        while vi < cap_verts.length
          cap_verts[vi]     += shift_x
          cap_verts[vi + 1] += shift_y
          vi += 8
        end
        w = [max_x - min_x, 1.0].max
        h = [max_y - min_y, 1.0].max
      else
        w = (explicit_w || [max_x, 1.0].max).to_f
        h = (explicit_h || explicit_w || [max_y, 1.0].max).to_f
      end

      inv_w = w > 0.0 ? (1.0 / w) : 0.0
      inv_h = h > 0.0 ? (1.0 / h) : 0.0
      vi = 0
      while vi < cap_verts.length
        cap_verts[vi + 2] = cap_verts[vi] * inv_w
        cap_verts[vi + 3] = cap_verts[vi + 1] * inv_h
        vi += 8
      end

      Mesh.from_vertices(cap_verts, cap_indices, width: w, height: h, image: img, shader: shader, uniforms: uniforms, blend: blend)
    end

    # ----------------------------------------------------
    # 状態スタック & 座標変換
    # ----------------------------------------------------
    def save
      @state_stack.push({
        fill_style: @fill_style.dup,
        stroke_style: @stroke_style.dup,
        line_width: @line_width,
        line_cap: @line_cap,
        line_join: @line_join,
        miter_limit: @miter_limit,
        global_alpha: @global_alpha,
        transform: @transform.dup
      })
    end

    def restore
      return if @state_stack.empty?
      state = @state_stack.pop
      @fill_style = state[:fill_style]
      @stroke_style = state[:stroke_style]
      @line_width = state[:line_width]
      @line_cap = state[:line_cap]
      @line_join = state[:line_join]
      @miter_limit = state[:miter_limit]
      @global_alpha = state[:global_alpha]
      @transform = state[:transform]
    end

    def translate(dx, dy)
      @transform.translate(dx.to_f, dy.to_f)
    end

    def scale(sx, sy = sx)
      @transform.scale(sx.to_f, sy.to_f)
    end

    def rotate(angle_rad)
      @transform.rotate(angle_rad.to_f)
    end

    def reset_transform
      @transform = Transform.new
    end

    # ----------------------------------------------------
    # パス構築 API
    # ----------------------------------------------------
    def begin_path
      @subpaths = [SubPath.new]
    end

    def close_path
      return if current_subpath.empty?
      current_subpath.closed = true
    end

    def move_to(x, y)
      tx, ty = @transform.apply(x.to_f, y.to_f)
      if current_subpath.empty?
        current_subpath.points << [tx, ty]
      else
        new_sub = SubPath.new
        new_sub.points << [tx, ty]
        @subpaths << new_sub
      end
    end

    def line_to(x, y)
      tx, ty = @transform.apply(x.to_f, y.to_f)
      if current_subpath.empty?
        current_subpath.points << [tx, ty]
      else
        current_subpath.points << [tx, ty]
      end
    end

    # 2次ベジエ曲線
    def quadratic_curve_to(cpx, cpy, x, y, steps = 16)
      last = current_point
      p0x, p0y = last ? last : @transform.apply(0, 0)
      p1x, p1y = @transform.apply(cpx.to_f, cpy.to_f)
      p2x, p2y = @transform.apply(x.to_f, y.to_f)

      1.upto(steps) do |i|
        t = i / steps.to_f
        it = 1.0 - t
        bx = it * it * p0x + 2.0 * it * t * p1x + t * t * p2x
        by = it * it * p0y + 2.0 * it * t * p1y + t * t * p2y
        current_subpath.points << [bx, by]
      end
    end

    # 3次ベジエ曲線
    def bezier_curve_to(cp1x, cp1y, cp2x, cp2y, x, y, steps = 24)
      last = current_point
      p0x, p0y = last ? last : @transform.apply(0, 0)
      p1x, p1y = @transform.apply(cp1x.to_f, cp1y.to_f)
      p2x, p2y = @transform.apply(cp2x.to_f, cp2y.to_f)
      p3x, p3y = @transform.apply(x.to_f, y.to_f)

      1.upto(steps) do |i|
        t = i / steps.to_f
        it = 1.0 - t
        bx = it * it * it * p0x + 3.0 * it * it * t * p1x + 3.0 * it * t * t * p2x + t * t * t * p3x
        by = it * it * it * p0y + 3.0 * it * it * t * p1y + 3.0 * it * t * t * p2y + t * t * t * p3y
        current_subpath.points << [bx, by]
      end
    end

    # 円弧
    def arc(cx, cy, radius, start_angle, end_angle, counterclockwise = false)
      r = radius.to_f.abs
      return if r <= 0.0

      # 角度差分の計算
      da = end_angle.to_f - start_angle.to_f
      if counterclockwise
        da -= Math::PI * 2 while da > 0
        da += Math::PI * 2 while da < -Math::PI * 2
      else
        da += Math::PI * 2 while da < 0
        da -= Math::PI * 2 while da > Math::PI * 2
      end

      arc_len = (r * da.abs)
      steps = [[(arc_len / 4.0).to_i, 8].max, 64].min

      0.upto(steps) do |i|
        angle = start_angle + da * (i / steps.to_f)
        px = cx + Math.cos(angle) * r
        py = cy + Math.sin(angle) * r
        tx, ty = @transform.apply(px, py)

        if i == 0 && current_subpath.empty?
          current_subpath.points << [tx, ty]
        else
          current_subpath.points << [tx, ty]
        end
      end
    end

    # 円
    def circle(cx, cy, radius)
      arc(cx, cy, radius, 0, Math::PI * 2)
      close_path
    end

    # 楕円パス (HTML5 Canvas 2D 互換)
    def ellipse(cx, cy, rx, ry, rotation = 0.0, start_angle = 0.0, end_angle = Math::PI * 2, counterclockwise = false)
      rx = rx.to_f.abs
      ry = ry.to_f.abs
      return if rx <= 0.0 || ry <= 0.0

      da = end_angle.to_f - start_angle.to_f
      if counterclockwise
        da -= Math::PI * 2 while da > 0
        da += Math::PI * 2 while da < -Math::PI * 2
      else
        da += Math::PI * 2 while da < 0
        da -= Math::PI * 2 while da > Math::PI * 2
      end

      # ラマヌジャンの楕円周長近似による滑らかな分割数 (32〜96ステップ)
      approx_len = Math::PI * (3.0 * (rx + ry) - Math.sqrt((3.0 * rx + ry) * (rx + 3.0 * ry))) * (da.abs / (Math::PI * 2))
      steps = [[(approx_len / 4.0).to_i, 32].max, 96].min

      rot = rotation.to_f
      cos_rot = Math.cos(rot)
      sin_rot = Math.sin(rot)

      0.upto(steps) do |i|
        angle = start_angle + da * (i / steps.to_f)
        lx = Math.cos(angle) * rx
        ly = Math.sin(angle) * ry

        px = cx + (lx * cos_rot - ly * sin_rot)
        py = cy + (lx * sin_rot + ly * cos_rot)
        tx, ty = @transform.apply(px, py)

        if i == 0 && current_subpath.empty?
          current_subpath.points << [tx, ty]
        else
          current_subpath.points << [tx, ty]
        end
      end
    end

    # 矩形パス
    def rect(x, y, w, h)
      move_to(x, y)
      line_to(x + w, y)
      line_to(x + w, y + h)
      line_to(x, y + h)
      close_path
    end

    # 角丸矩形パス
    def round_rect(x, y, w, h, radius)
      r = [[radius.to_f, w.abs / 2.0].min, h.abs / 2.0].min
      if r <= 0.0
        rect(x, y, w, h)
        return
      end

      move_to(x + r, y)
      line_to(x + w - r, y)
      arc(x + w - r, y + r, r, -Math::PI / 2, 0)
      line_to(x + w, y + h - r)
      arc(x + w - r, y + h - r, r, 0, Math::PI / 2)
      line_to(x + r, y + h)
      arc(x + r, y + h - r, r, Math::PI / 2, Math::PI)
      line_to(x, y + r)
      arc(x + r, y + r, r, Math::PI, Math::PI * 1.5)
      close_path
    end

    # ----------------------------------------------------
    # グラデーション生成 API
    # ----------------------------------------------------
    def create_linear_gradient(x0, y0, x1, y1)
      tx0, ty0 = @transform.apply(x0.to_f, y0.to_f)
      tx1, ty1 = @transform.apply(x1.to_f, y1.to_f)
      LinearGradient.new(tx0, ty0, tx1, ty1)
    end

    def create_radial_gradient(x0, y0, r0, x1 = x0, y1 = y0, r1 = r0)
      tx0, ty0 = @transform.apply(x0.to_f, y0.to_f)
      tx1, ty1 = @transform.apply(x1.to_f, y1.to_f)
      sx = Math.hypot(@transform.a, @transform.b)
      RadialGradient.new(tx0, ty0, r0.to_f * sx, tx1, ty1, r1.to_f * sx)
    end

    # ----------------------------------------------------
    # 描画 API (fill / stroke)
    # ----------------------------------------------------
    def fill(style = nil)
      active_style = style || @fill_style
      coords = []

      @subpaths.each do |sub|
        next if sub.points.size < 3
        # 耳刈り取り法 (Ear Clipping) による多角形分割
        triangles = triangulate(sub.points)
        coords.concat(triangles)
      end

      return if coords.empty?
      render_triangles_with_style(coords, active_style)
    end

    def stroke(style = nil, width = nil)
      active_style = style || @stroke_style
      w = (width || @line_width).to_f
      return if w <= 0.0

      coords = []
      @subpaths.each do |sub|
        next if sub.points.size < 2
        # 太線ストロークリボンの生成
        triangles = generate_stroke(sub.points, w, sub.closed)
        coords.concat(triangles)
      end

      return if coords.empty?
      render_triangles_with_style(coords, active_style)
    end

    private

    def render_triangles_with_style(coords, style)
      if @mesh_capture
        capture_triangles_to_mesh(coords, style)
        return
      end

      num_verts = coords.size / 2
      verts = []
      i = 0
      shader = nil
      uniforms = nil

      if style.is_a?(LinearGradient)
        shader = Window.gradient_primitive_shader
        p0 = [style.x0.to_f, style.y0.to_f, 0.0, 0.0]
        p1 = [style.x1.to_f, style.y1.to_f, 0.0, 0.0]
        c0 = style.stops.first ? resolve_color(style.stops.first[1]) : [1.0, 1.0, 1.0, 1.0]
        c1 = style.stops.last ? resolve_color(style.stops.last[1]) : [0.0, 0.0, 0.0, 1.0]
        uniforms = {
          u_grad_type: 1,
          u_grad_p0: p0,
          u_grad_p1: p1,
          u_grad_color0: [c0[0].to_f, c0[1].to_f, c0[2].to_f, (c0[3] * @global_alpha).to_f],
          u_grad_color1: [c1[0].to_f, c1[1].to_f, c1[2].to_f, (c1[3] * @global_alpha).to_f]
        }
        while i < coords.size
          verts.push(coords[i].to_f, coords[i + 1].to_f, 1.0, 1.0, 1.0, 1.0)
          i += 2
        end
      elsif style.is_a?(RadialGradient)
        shader = Window.gradient_primitive_shader
        p0 = [style.x0.to_f, style.y0.to_f, style.r0.to_f, 0.0]
        p1 = [style.x1.to_f, style.y1.to_f, style.r1.to_f, 0.0]
        c0 = style.stops.first ? resolve_color(style.stops.first[1]) : [1.0, 1.0, 1.0, 1.0]
        c1 = style.stops.last ? resolve_color(style.stops.last[1]) : [0.0, 0.0, 0.0, 1.0]
        uniforms = {
          u_grad_type: 2,
          u_grad_p0: p0,
          u_grad_p1: p1,
          u_grad_color0: [c0[0].to_f, c0[1].to_f, c0[2].to_f, (c0[3] * @global_alpha).to_f],
          u_grad_color1: [c1[0].to_f, c1[1].to_f, c1[2].to_f, (c1[3] * @global_alpha).to_f]
        }
        while i < coords.size
          verts.push(coords[i].to_f, coords[i + 1].to_f, 1.0, 1.0, 1.0, 1.0)
          i += 2
        end
      else
        shader = Window.flat_primitive_shader
        color = resolve_color(style)
        cr = color[0].to_f
        cg = color[1].to_f
        cb = color[2].to_f
        ca = (color[3] * @global_alpha).to_f
        while i < coords.size
          verts.push(coords[i].to_f, coords[i + 1].to_f, cr, cg, cb, ca)
          i += 2
        end
      end

      data = verts.pack("f*")
      Backend.enqueue_draw(
        Backend::Pipelines::TRIANGLES,
        data,
        num_verts,
        shader: shader,
        uniforms: uniforms
      )
    end

    def capture_triangles_to_mesh(coords, style)
      cap_verts = @mesh_capture[:vertices]
      cap_indices = @mesh_capture[:indices]
      # 同一描画ステップ内の共有頂点をインデックス化
      vert_map = {}

      if style.is_a?(LinearGradient) || style.is_a?(RadialGradient)
        # グラデーション塗りつぶし時は外周頂点のみだと中間色ストップが欠落するため、
        # 全三角形を均一に中点4分割してTジャンクション(隙間)のない内部頂点を自動生成する
        passes = (coords.size / 6 <= 48) ? 2 : 1
        work_coords = subdivide_triangles_uniform(coords, passes)
        i = 0
        while i < work_coords.size
          px = work_coords[i].to_f
          py = work_coords[i + 1].to_f
          cr, cg, cb, ca = evaluate_gradient_color(style, px, py)
          key = [(px * 1000.0).round, (py * 1000.0).round]
          v_idx = vert_map[key]
          unless v_idx
            v_idx = cap_verts.length / 8
            cap_verts.push(px, py, 0.0, 0.0, cr, cg, cb, ca)
            vert_map[key] = v_idx
          end
          cap_indices << v_idx
          i += 2
        end
      else
        color = resolve_color(style)
        cr = color[0].to_f
        cg = color[1].to_f
        cb = color[2].to_f
        ca = (color[3] * @global_alpha).to_f
        i = 0
        while i < coords.size
          px = coords[i].to_f
          py = coords[i + 1].to_f
          key = [(px * 1000.0).round, (py * 1000.0).round]
          v_idx = vert_map[key]
          unless v_idx
            v_idx = cap_verts.length / 8
            cap_verts.push(px, py, 0.0, 0.0, cr, cg, cb, ca)
            vert_map[key] = v_idx
          end
          cap_indices << v_idx
          i += 2
        end
      end
    end

    # グラデーションおよび頂点変形向けに全三角形を均一に中点4分割 (Tジャンクションが発生しない適合分割)
    def subdivide_triangles_uniform(coords, passes = 1)
      current = coords
      passes.times do
        next_coords = Array.new(current.size * 4)
        ni = 0
        i = 0
        while i < current.size
          ax = current[i];     ay = current[i + 1]
          bx = current[i + 2]; by = current[i + 3]
          cx = current[i + 4]; cy = current[i + 5]

          mab_x = (ax + bx) * 0.5; mab_y = (ay + by) * 0.5
          mbc_x = (bx + cx) * 0.5; mbc_y = (by + cy) * 0.5
          mca_x = (cx + ax) * 0.5; mca_y = (cy + ay) * 0.5

          next_coords[ni]      = ax;    next_coords[ni + 1]  = ay
          next_coords[ni + 2]  = mab_x; next_coords[ni + 3]  = mab_y
          next_coords[ni + 4]  = mca_x; next_coords[ni + 5]  = mca_y

          next_coords[ni + 6]  = mab_x; next_coords[ni + 7]  = mab_y
          next_coords[ni + 8]  = bx;    next_coords[ni + 9]  = by
          next_coords[ni + 10] = mbc_x; next_coords[ni + 11] = mbc_y

          next_coords[ni + 12] = mca_x; next_coords[ni + 13] = mca_y
          next_coords[ni + 14] = mbc_x; next_coords[ni + 15] = mbc_y
          next_coords[ni + 16] = cx;    next_coords[ni + 17] = cy

          next_coords[ni + 18] = mab_x; next_coords[ni + 19] = mab_y
          next_coords[ni + 20] = mbc_x; next_coords[ni + 21] = mbc_y
          next_coords[ni + 22] = mca_x; next_coords[ni + 23] = mca_y

          ni += 24
          i += 6
        end
        current = next_coords
      end
      current
    end

    def evaluate_gradient_color(grad, px, py)
      stops = grad.stops
      return [1.0, 1.0, 1.0, @global_alpha.to_f] if stops.empty?

      if grad.is_a?(LinearGradient)
        dx = grad.x1 - grad.x0
        dy = grad.y1 - grad.y0
        len_sq = dx * dx + dy * dy
        t = len_sq > 1e-8 ? (((px - grad.x0) * dx + (py - grad.y0) * dy) / len_sq).clamp(0.0, 1.0) : 0.0
      else
        dist = Math.hypot(px - grad.x1, py - grad.y1)
        span = grad.r1 - grad.r0
        t = span.abs > 1e-8 ? ((dist - grad.r0) / span).clamp(0.0, 1.0) : 1.0
      end

      if stops.length == 1 || t <= stops.first[0]
        c = Backend.normalize_color(stops.first[1])
        return [c[0], c[1], c[2], c[3] * @global_alpha]
      elsif t >= stops.last[0]
        c = Backend.normalize_color(stops.last[1])
        return [c[0], c[1], c[2], c[3] * @global_alpha]
      end

      (stops.length - 1).times do |si|
        o0, col0 = stops[si]
        o1, col1 = stops[si + 1]
        if t >= o0 && t <= o1
          span_o = o1 - o0
          lt = span_o > 1e-8 ? ((t - o0) / span_o) : 0.0
          c0 = Backend.normalize_color(col0)
          c1 = Backend.normalize_color(col1)
          return [
            c0[0] + (c1[0] - c0[0]) * lt,
            c0[1] + (c1[1] - c0[1]) * lt,
            c0[2] + (c1[2] - c0[2]) * lt,
            (c0[3] + (c1[3] - c0[3]) * lt) * @global_alpha
          ]
        end
      end

      c = Backend.normalize_color(stops.last[1])
      [c[0], c[1], c[2], c[3] * @global_alpha]
    end

    public

    # ----------------------------------------------------
    # 即時描画ショートハンド
    # ----------------------------------------------------
    def fill_rect(x, y, w, h, style = nil)
      save
      begin_path
      rect(x, y, w, h)
      fill(style)
      restore
    end

    def stroke_rect(x, y, w, h, style = nil, width = nil)
      save
      begin_path
      rect(x, y, w, h)
      stroke(style, width)
      restore
    end

    def fill_circle(cx, cy, radius, style = nil)
      save
      begin_path
      circle(cx, cy, radius)
      fill(style)
      restore
    end

    def stroke_circle(cx, cy, radius, style = nil, width = nil)
      save
      begin_path
      circle(cx, cy, radius)
      stroke(style, width)
      restore
    end

    private

    def current_subpath
      sub = @subpaths.last
      unless sub
        sub = SubPath.new
        @subpaths << sub
      end
      sub
    end

    def current_point
      current_subpath.last_point
    end

    # ----------------------------------------------------
    # 色の正規化
    # ----------------------------------------------------
    def resolve_color(val)
      if val.is_a?(LinearGradient) || val.is_a?(RadialGradient)
        return resolve_color(val.stops.first ? val.stops.first[1] : :white)
      end

      Backend.normalize_color(val)
    end

    # ----------------------------------------------------
    # Ear Clipping (耳刈り取り法) 多角形テッセレーション
    # ----------------------------------------------------
    def triangulate(pts)
      cleaned = []
      pts.each do |p|
        if cleaned.empty?
          cleaned << p
        else
          last = cleaned.last
          if Math.hypot(p[0] - last[0], p[1] - last[1]) > 0.0001
            cleaned << p
          end
        end
      end

      if cleaned.size > 2 && Math.hypot(cleaned.first[0] - cleaned.last[0], cleaned.first[1] - cleaned.last[1]) < 0.0001
        cleaned.pop
      end
      n = cleaned.size
      return [] if n < 3

      if n == 3
        return [
          cleaned[0][0], cleaned[0][1],
          cleaned[1][0], cleaned[1][1],
          cleaned[2][0], cleaned[2][1]
        ]
      end

      # 符号付き面積を求めて頂点順序（CCW/CW）を判定
      area = 0.0
      0.upto(n - 1) do |i|
        p1 = cleaned[i]
        p2 = cleaned[(i + 1) % n]
        area += (p1[0] * p2[1] - p2[0] * p1[1])
      end

      # CW (area < 0) なら反転して CCW に揃える
      vertices = (area < 0.0) ? cleaned.reverse : cleaned
      indices = (0...n).to_a
      triangles = []

      limit = n * 3 # 無限ループ防止リミット
      while indices.size > 3 && limit > 0
        limit -= 1
        ear_found = false

        len = indices.size
        0.upto(len - 1) do |i|
          prev_idx = indices[(i - 1) % len]
          curr_idx = indices[i]
          next_idx = indices[(i + 1) % len]

          a = vertices[prev_idx]
          b = vertices[curr_idx]
          c = vertices[next_idx]

          # 外積 (凸角チェック)
          cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
          next if cross <= 0.000001 # 反射角または一直線

          # 他の全頂点が三角形 ABC の内部に含まれていないか判定
          is_ear = true
          0.upto(len - 1) do |j|
            test_idx = indices[j]
            next if test_idx == prev_idx || test_idx == curr_idx || test_idx == next_idx

            p = vertices[test_idx]
            if point_in_triangle(p, a, b, c)
              is_ear = false
              break
            end
          end

          if is_ear
            triangles.push(a[0], a[1], b[0], b[1], c[0], c[1])
            indices.delete_at(i)
            ear_found = true
            break
          end
        end

        # 耳が見つからなかった場合（縮退多角形など）の安全フォールバック
        unless ear_found
          i0 = indices[0]
          i1 = indices[1]
          i2 = indices[2]
          triangles.push(vertices[i0][0], vertices[i0][1], vertices[i1][0], vertices[i1][1], vertices[i2][0], vertices[i2][1])
          indices.delete_at(1)
        end
      end

      if indices.size == 3
        a = vertices[indices[0]]
        b = vertices[indices[1]]
        c = vertices[indices[2]]
        triangles.push(a[0], a[1], b[0], b[1], c[0], c[1])
      end

      triangles
    end

    # 三角形内部判定
    def point_in_triangle(p, a, b, c)
      # 重心座標系または外積符号による内外判定
      cp1 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
      cp2 = (c[0] - b[0]) * (p[1] - b[1]) - (c[1] - b[1]) * (p[0] - b[0])
      cp3 = (a[0] - c[0]) * (p[1] - c[1]) - (a[1] - c[1]) * (p[0] - c[0])
      (cp1 >= 0 && cp2 >= 0 && cp3 >= 0) || (cp1 <= 0 && cp2 <= 0 && cp3 <= 0)
    end

    # ----------------------------------------------------
    # 太線ストロークメッシュ生成
    # 各セグメントの矩形 ＋ 角ジョイント(Miter/Bevel/Round) ＋ 端点キャップ
    # ----------------------------------------------------
    def generate_stroke(pts, width, closed)
      pts_work = []
      pts.each do |p|
        if pts_work.empty?
          pts_work << p
        else
          last = pts_work.last
          if Math.hypot(p[0] - last[0], p[1] - last[1]) > 0.0001
            pts_work << p
          end
        end
      end

      # 始点と終点が一致している場合（明示的 closed、または 360 度円弧など幾何学的に同一座標で循環する場合）
      is_loop = closed || (pts_work.size > 2 && Math.hypot(pts_work.first[0] - pts_work.last[0], pts_work.first[1] - pts_work.last[1]) < 0.0001)

      if is_loop && pts_work.size > 2 && Math.hypot(pts_work.first[0] - pts_work.last[0], pts_work.first[1] - pts_work.last[1]) < 0.0001
        pts_work.pop
      end
      n = pts_work.size
      return [] if n < 2

      half_w = width.to_f * 0.5
      num_segments = is_loop ? n : (n - 1)

      # 各セグメントの方向ベクトルと法線オフセット
      seg_dirs_x = []
      seg_dirs_y = []
      seg_normals_x = []
      seg_normals_y = []

      0.upto(num_segments - 1) do |i|
        p1 = pts_work[i]
        p2 = pts_work[(i + 1) % n]
        dx = p2[0].to_f - p1[0].to_f
        dy = p2[1].to_f - p1[1].to_f
        len = Math.hypot(dx, dy)
        if len > 0.000001
          inv_len = 1.0 / len
          dir_x = dx * inv_len
          dir_y = dy * inv_len
          seg_dirs_x << dir_x
          seg_dirs_y << dir_y
          seg_normals_x << (-dir_y * half_w)
          seg_normals_y << (dir_x * half_w)
        else
          seg_dirs_x << 1.0
          seg_dirs_y << 0.0
          seg_normals_x << 0.0
          seg_normals_y << half_w
        end
      end

      triangles = []

      # 1. 各セグメントの矩形（長方形）
      0.upto(num_segments - 1) do |i|
        p1 = pts_work[i]
        p2 = pts_work[(i + 1) % n]
        nx = seg_normals_x[i]
        ny = seg_normals_y[i]

        l1x = p1[0].to_f + nx; l1y = p1[1].to_f + ny
        r1x = p1[0].to_f - nx; r1y = p1[1].to_f - ny
        l2x = p2[0].to_f + nx; l2y = p2[1].to_f + ny
        r2x = p2[0].to_f - nx; r2y = p2[1].to_f - ny

        # Tri 1: (l1, r1, l2)
        triangles.push(l1x, l1y, r1x, r1y, l2x, l2y)
        # Tri 2: (r1, r2, l2)
        triangles.push(r1x, r1y, r2x, r2y, l2x, l2y)
      end

      # 2. 中間頂点のジョイント (Join)
      miter_limit = (@miter_limit && @miter_limit > 0) ? @miter_limit.to_f : 10.0
      limit_sq = miter_limit * miter_limit
      joint_count = is_loop ? n : (n - 2)
      start_idx = is_loop ? 0 : 1

      start_idx.upto(start_idx + joint_count - 1) do |idx|
        curr_i = idx % n
        prev_seg = (curr_i - 1) % num_segments
        curr_seg = curr_i % num_segments

        d1x = seg_dirs_x[prev_seg]; d1y = seg_dirs_y[prev_seg]
        d2x = seg_dirs_x[curr_seg]; d2y = seg_dirs_y[curr_seg]
        n1x = seg_normals_x[prev_seg]; n1y = seg_normals_y[prev_seg]
        n2x = seg_normals_x[curr_seg]; n2y = seg_normals_y[curr_seg]

        p = pts_work[curr_i]
        px = p[0].to_f; py = p[1].to_f

        cross = d1x * d2y - d1y * d2x
        next if cross.abs < 0.0001

        dot = d1x * d2x + d1y * d2y
        denom = 1.0 + dot

        # 外側オフセットの選択
        if cross > 0.0
          # 左折: 外側は右 (符号反転)
          o1x = -n1x; o1y = -n1y
          o2x = -n2x; o2y = -n2y
        else
          # 右折: 外側は左
          o1x = n1x; o1y = n1y
          o2x = n2x; o2y = n2y
        end

        out1_x = px + o1x; out1_y = py + o1y
        out2_x = px + o2x; out2_y = py + o2y

        if @line_join == :miter && denom > 0.0001 && denom * limit_sq >= 2.0
          # マイター結合
          factor = 1.0 / denom
          tip_x = px + (o1x + o2x) * factor
          tip_y = py + (o1y + o2y) * factor

          triangles.push(px, py, out1_x, out1_y, tip_x, tip_y)
          triangles.push(px, py, tip_x, tip_y, out2_x, out2_y)
        elsif @line_join == :round
          # ラウンド結合 (円弧ファン)
          steps = 4
          a1 = Math.atan2(o1y, o1x)
          a2 = Math.atan2(o2y, o2x)
          da = a2 - a1
          if cross > 0.0
            da += Math::PI * 2 while da < 0.0
          else
            da -= Math::PI * 2 while da > 0.0
          end
          prev_rx = out1_x; prev_ry = out1_y
          1.upto(steps) do |s|
            ang = a1 + da * (s.to_f / steps)
            curr_rx = px + Math.cos(ang) * half_w
            curr_ry = py + Math.sin(ang) * half_w
            triangles.push(px, py, prev_rx, prev_ry, curr_rx, curr_ry)
            prev_rx = curr_rx; prev_ry = curr_ry
          end
        else
          # ベベル結合 (:bevel、またはマイター上限超過時)
          triangles.push(px, py, out1_x, out1_y, out2_x, out2_y)
        end
      end

      # 3. 端点キャップ (Cap) - 開いたパスのみ
      if !is_loop && n >= 2
        if @line_cap == :square
          d0x = seg_dirs_x[0]; d0y = seg_dirs_y[0]
          n0x = seg_normals_x[0]; n0y = seg_normals_y[0]
          p0 = pts_work[0]
          p0x = p0[0].to_f; p0y = p0[1].to_f
          cap_ox = -d0x * half_w; cap_oy = -d0y * half_w
          triangles.push(p0x + n0x, p0y + n0y, p0x - n0x, p0y - n0y, p0x + n0x + cap_ox, p0y + n0y + cap_oy)
          triangles.push(p0x - n0x, p0y - n0y, p0x - n0x + cap_ox, p0y - n0y + cap_oy, p0x + n0x + cap_ox, p0y + n0y + cap_oy)

          dlx = seg_dirs_x.last; dly = seg_dirs_y.last
          nlx = seg_normals_x.last; nly = seg_normals_y.last
          pl = pts_work.last
          plx = pl[0].to_f; ply = pl[1].to_f
          cap_ex = dlx * half_w; cap_ey = dly * half_w
          triangles.push(plx + nlx, ply + nly, plx - nlx, ply - nly, plx + nlx + cap_ex, ply + nly + cap_ey)
          triangles.push(plx - nlx, ply - nly, plx - nlx + cap_ex, ply - nly + cap_ey, plx + nlx + cap_ex, ply + nly + cap_ey)
        elsif @line_cap == :round
          [ [pts_work[0], -seg_dirs_x[0], -seg_dirs_y[0], seg_normals_x[0], seg_normals_y[0]],
            [pts_work.last, seg_dirs_x.last, seg_dirs_y.last, seg_normals_x.last, seg_normals_y.last] ].each do |pt, fwd_x, fwd_y, norm_x, norm_y|
            cpx = pt[0].to_f; cpy = pt[1].to_f
            base_a = Math.atan2(norm_y, norm_x)
            steps = 6
            prev_cx = cpx + norm_x; prev_cy = cpy + norm_y
            1.upto(steps) do |s|
              ang = base_a + Math::PI * (s.to_f / steps)
              cur_cx = cpx + Math.cos(ang) * half_w
              cur_cy = cpy + Math.sin(ang) * half_w
              triangles.push(cpx, cpy, prev_cx, prev_cy, cur_cx, cur_cy)
              prev_cx = cur_cx; prev_cy = cur_cy
            end
          end
        end
      end

      triangles
    end
  end
end

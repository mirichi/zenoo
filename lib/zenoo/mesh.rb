# frozen_string_literal: true

module Zenoo
  # ====================================================================
  # 2D メッシュ & 頂点バッファ管理クラス (Zenoo::Mesh)
  # - Sprite や Window.draw に Image の代わりとして渡せる描画リソース
  # - 標準頂点フォーマット: [x, y, u, v, r, g, b, a] (8 floats / 頂点) + インデックスバッファ (IBO)
  # - image が nil の場合はエンジンの 1x1 白テクスチャが自動バインドされ、頂点カラーメッシュとして描画されます。
  # - 生成時は GL_STATIC_DRAW として VRAM に常駐し、変形メソッドが呼ばれた際のみ
  #   自動的に GL_DYNAMIC_DRAW へ昇格して変更フレームのみ GPU へ転送します。
  # ====================================================================
  class Mesh
    VERTEX_STRIDE = 8
    INV_255 = 1.0 / 255.0

    # ------------------------------------------------------------------
    # Mesh#deform ブロック内で使い回される頂点カーソル (GCアロケーションゼロ)
    # 色・アルファはすべて 0〜255 で表現されます (内部で GPU 用の 0.0..1.0 と自動相互変換)
    # ------------------------------------------------------------------
    class VertexCursor
      attr_accessor :index, :col, :row
      attr_accessor :base_x, :base_y, :base_u, :base_v, :base_r, :base_g, :base_b, :base_alpha
      attr_accessor :x, :y, :u, :v, :r, :g, :b, :alpha

      def color=(val)
        c = Backend.normalize_color(val)
        @r     = c[0] * 255.0
        @g     = c[1] * 255.0
        @b     = c[2] * 255.0
        @alpha = c[3] * 255.0
      end

      def color
        [@r, @g, @b, @alpha]
      end
    end

    attr_accessor :image, :shader, :uniforms, :blend, :width, :height
    attr_reader   :cols, :rows, :vertex_count, :index_count, :pipeline, :native_mesh
    attr_reader   :vertices, :base_vertices, :indices, :data, :count

    # ------------------------------------------------------------------
    # 1. 自動分割ファクトリメソッド
    # ------------------------------------------------------------------

    # 格子分割メッシュを生成
    # 例:
    #   Mesh.grid(image, 8, 8)
    #   Mesh.grid(image, cols: 16, rows: 8)
    #   Mesh.grid(200, 100, cols: 8, rows: 4) # 画像なしメッシュ
    def self.grid(image_or_width, cols_arg = nil, rows_arg = nil, cols: nil, rows: nil, width: nil, height: nil, image: nil, color: :white, shader: nil, uniforms: nil, blend: :alpha)
      if image_or_width.is_a?(Image)
        img = image_or_width
        w = (width || img.width).to_f
        h = (height || img.height).to_f
        c = cols || cols_arg || 8
        r = rows || rows_arg || 8
      else
        img = image
        w = (width || image_or_width || 64).to_f
        if rows_arg.nil? && !cols.nil?
          h = (height || cols_arg || w).to_f
          c = cols
          r = rows || 8
        else
          h = (height || (img ? img.height : w)).to_f
          c = cols || cols_arg || 8
          r = rows || rows_arg || 8
        end
      end

      cr, cg, cb, ca = Backend.normalize_color(color)
      nx = [c.to_i, 1].max
      ny = [r.to_i, 1].max
      inv_nx = 1.0 / nx.to_f
      inv_ny = 1.0 / ny.to_f

      verts = Array.new((nx + 1) * (ny + 1) * VERTEX_STRIDE, 0.0)
      vi = 0
      0.upto(ny) do |iy|
        v_norm = iy * inv_ny
        py = v_norm * h
        0.upto(nx) do |ix|
          u_norm = ix * inv_nx
          px = u_norm * w
          verts[vi]     = px
          verts[vi + 1] = py
          verts[vi + 2] = u_norm
          verts[vi + 3] = v_norm
          verts[vi + 4] = cr
          verts[vi + 5] = cg
          verts[vi + 6] = cb
          verts[vi + 7] = ca
          vi += VERTEX_STRIDE
        end
      end

      stride_x = nx + 1
      idxs = Array.new(nx * ny * 6, 0)
      ii = 0
      ny.times do |iy|
        row0 = iy * stride_x
        row1 = (iy + 1) * stride_x
        nx.times do |ix|
          i00 = row0 + ix
          i10 = i00 + 1
          i01 = row1 + ix
          i11 = i01 + 1

          idxs[ii]     = i00
          idxs[ii + 1] = i01
          idxs[ii + 2] = i10
          idxs[ii + 3] = i10
          idxs[ii + 4] = i01
          idxs[ii + 5] = i11
          ii += 6
        end
      end

      allocate.__send__(
        :init_managed,
        img, w, h, nx, ny, verts, idxs,
        shader: shader, uniforms: uniforms, blend: blend
      )
    end

    # 4頂点クアッドメッシュを生成 (4隅の自由変形・疑似パース用)
    def self.quad(image_or_width, height: nil, image: nil, color: :white, shader: nil, uniforms: nil, blend: :alpha)
      grid(image_or_width, 1, 1, height: height, image: image, color: color, shader: shader, uniforms: uniforms, blend: blend)
    end

    # 放射・リング（円形・扇形・ドーナツ）分割メッシュを生成
    # - slices: 円周方向の分割数 (デフォルト: 24)
    # - rings:  半径方向の分割数 (デフォルト: 2)
    # - inner_radius: 内径比率 (0.0 なら中心まで埋まった円、0.0 < r < 1.0 ならドーナツ型、> 1.0 ならピクセル半径として解釈)
    # - start_angle, end_angle: 扇形の開始・終了角度 (度数法、デフォルト: 0.0 .. 360.0)
    # - uv_mode: :planar (画像のXYそのまま切り抜き) または :polar (円周=U, 半径=V で帯状テクスチャを円形に巻く)
    def self.ring(image_or_radius, slices_arg = nil, rings_arg = nil,
                  slices: nil, rings: nil,
                  inner_radius: 0.0, start_angle: 0.0, end_angle: 360.0,
                  uv_mode: :planar, width: nil, height: nil, image: nil, color: :white,
                  shader: nil, uniforms: nil, blend: :alpha)
      if image_or_radius.is_a?(Image)
        img = image_or_radius
        w = (width || img.width).to_f
        h = (height || img.height).to_f
      else
        img = image
        r_px = (image_or_radius || 64).to_f
        w = (width || r_px * 2.0).to_f
        h = (height || r_px * 2.0).to_f
      end

      cr, cg, cb, ca = Backend.normalize_color(color)
      nx = [slices || slices_arg || 24, 3].max.to_i
      ny = [rings || rings_arg || 2, 1].max.to_i
      inv_nx = 1.0 / nx.to_f
      inv_ny = 1.0 / ny.to_f

      cx = w * 0.5
      cy = h * 0.5
      rx = w * 0.5
      ry = h * 0.5

      in_r = inner_radius.to_f
      # inner_radius が 1.0 より大きい場合はピクセル指定として比率に変換
      min_half = [rx, ry].min
      in_ratio = (in_r > 1.0 && min_half > 0.0) ? (in_r / min_half).clamp(0.0, 1.0) : in_r.clamp(0.0, 1.0)

      ang0 = start_angle.to_f * (Math::PI / 180.0)
      ang1 = end_angle.to_f * (Math::PI / 180.0)
      ang_span = ang1 - ang0

      verts = Array.new((nx + 1) * (ny + 1) * VERTEX_STRIDE, 0.0)
      vi = 0
      0.upto(ny) do |iy|
        t_r = iy * inv_ny
        cur_ratio = in_ratio + (1.0 - in_ratio) * t_r
        0.upto(nx) do |ix|
          t_a = ix * inv_nx
          ang = ang0 + ang_span * t_a
          c_v = Math.cos(ang)
          s_v = Math.sin(ang)

          px = cx + c_v * rx * cur_ratio
          py = cy + s_v * ry * cur_ratio

          if uv_mode == :polar
            u_norm = t_a
            v_norm = t_r
          else
            u_norm = (w > 0.0) ? (px / w) : 0.5
            v_norm = (h > 0.0) ? (py / h) : 0.5
          end

          verts[vi]     = px
          verts[vi + 1] = py
          verts[vi + 2] = u_norm
          verts[vi + 3] = v_norm
          verts[vi + 4] = cr
          verts[vi + 5] = cg
          verts[vi + 6] = cb
          verts[vi + 7] = ca
          vi += VERTEX_STRIDE
        end
      end

      stride_x = nx + 1
      idxs = Array.new(nx * ny * 6, 0)
      ii = 0
      ny.times do |iy|
        row0 = iy * stride_x
        row1 = (iy + 1) * stride_x
        nx.times do |ix|
          i00 = row0 + ix
          i10 = i00 + 1
          i01 = row1 + ix
          i11 = i01 + 1

          idxs[ii]     = i00
          idxs[ii + 1] = i01
          idxs[ii + 2] = i10
          idxs[ii + 3] = i10
          idxs[ii + 4] = i01
          idxs[ii + 5] = i11
          ii += 6
        end
      end

      allocate.__send__(
        :init_managed,
        img, w, h, nx, ny, verts, idxs,
        shader: shader, uniforms: uniforms, blend: blend
      )
    end

    # 多角形メッシュを生成 (頂点リストから自動三角形分割)
    # - points: [[x, y], ...], [[x, y, u, v, alpha], ...], または [[x, y, u, v, r, g, b, a], ...]
    # - indices: 省略時は耳刈り法 (Ear Clipping) で凹多角形も含め自動三角形分割
    def self.polygon(image_or_points, points_arg = nil, points: nil, indices: nil, width: nil, height: nil, image: nil, color: :white, shader: nil, uniforms: nil, blend: :alpha)
      if image_or_points.is_a?(Image)
        img = image_or_points
        pts = points || points_arg || []
      else
        img = image
        pts = image_or_points.is_a?(Array) ? image_or_points : (points || points_arg || [])
      end

      raise ArgumentError, "Mesh.polygon requires at least 3 vertices" if pts.length < 3

      if width && height
        w = width.to_f
        h = height.to_f
      elsif img
        w = img.width.to_f
        h = img.height.to_f
      else
        max_x = 1.0
        max_y = 1.0
        pts.each do |pt|
          px = pt[0].to_f
          py = pt[1].to_f
          max_x = px if px > max_x
          max_y = py if py > max_y
        end
        w = max_x
        h = max_y
      end

      cr, cg, cb, ca = Backend.normalize_color(color)
      inv_w = w > 0.0 ? (1.0 / w) : 0.0
      inv_h = h > 0.0 ? (1.0 / h) : 0.0

      n = pts.length
      verts = Array.new(n * VERTEX_STRIDE, 0.0)
      poly_xy = Array.new(n)
      vi = 0
      pts.each_with_index do |pt, idx|
        px = pt[0].to_f
        py = pt[1].to_f
        u_norm = pt.length >= 4 && !pt[2].nil? ? pt[2].to_f : (px * inv_w)
        v_norm = pt.length >= 4 && !pt[3].nil? ? pt[3].to_f : (py * inv_h)
        if pt.length >= 8
          vr = pt[4].to_f
          vg = pt[5].to_f
          vb = pt[6].to_f
          va = normalize_alpha_val(pt[7])
        elsif pt.length >= 5 && !pt[4].nil?
          if pt[4].is_a?(Array) || pt[4].is_a?(Symbol) || pt[4].is_a?(String)
            vr, vg, vb, va = Backend.normalize_color(pt[4])
          else
            vr = cr
            vg = cg
            vb = cb
            va = normalize_alpha_val(pt[4])
          end
        else
          vr = cr
          vg = cg
          vb = cb
          va = ca
        end

        verts[vi]     = px
        verts[vi + 1] = py
        verts[vi + 2] = u_norm
        verts[vi + 3] = v_norm
        verts[vi + 4] = vr
        verts[vi + 5] = vg
        verts[vi + 6] = vb
        verts[vi + 7] = va
        poly_xy[idx]  = [px, py]
        vi += VERTEX_STRIDE
      end

      idxs = indices ? indices.map(&:to_i) : triangulate_polygon(poly_xy)

      allocate.__send__(
        :init_managed,
        img, w, h, nil, nil, verts, idxs,
        shader: shader, uniforms: uniforms, blend: blend
      )
    end

    # Canvas のベクター描画 (fill / stroke / 図形 / グラデーション) をそのまま頂点メッシュ化
    # 例:
    #   mesh = Zenoo::Mesh.canvas(100, 100) do |c|
    #     c.fill_circle(50, 50, 40, :orange)
    #     c.stroke_circle(50, 50, 40, :white, 4)
    #   end
    #   sprite = Zenoo::Sprite.new(200, 200, mesh)
    def self.canvas(width_or_image = nil, height_arg = nil, width: nil, height: nil, image: nil, shader: nil, uniforms: nil, blend: :alpha, &block)
      Canvas.to_mesh(width_or_image, height_arg, width: width, height: height, image: image, shader: shader, uniforms: uniforms, blend: blend, &block)
    end

    # 8-float 頂点配列 [x, y, u, v, r, g, b, a, ...] とインデックス配列から管理メッシュを直接構築
    def self.from_vertices(vertices, indices = nil, width: nil, height: nil, cols: nil, rows: nil, image: nil, shader: nil, uniforms: nil, blend: :alpha)
      verts = vertices.map(&:to_f)
      v_count = verts.length / VERTEX_STRIDE
      idxs = indices ? indices.map(&:to_i) : (0...v_count).to_a

      if width && height
        w = width.to_f
        h = height.to_f
      elsif image
        w = (width || image.width).to_f
        h = (height || image.height).to_f
      else
        max_x = 1.0
        max_y = 1.0
        vi = 0
        while vi < verts.length
          px = verts[vi]
          py = verts[vi + 1]
          max_x = px if px > max_x
          max_y = py if py > max_y
          vi += VERTEX_STRIDE
        end
        w = (width || max_x).to_f
        h = (height || max_y).to_f
      end

      allocate.__send__(
        :init_managed,
        image, w, h, cols, rows, verts, idxs,
        shader: shader, uniforms: uniforms, blend: blend
      )
    end

    # ------------------------------------------------------------------
    # 2. コンストラクタ (汎用・低レベル互換)
    # ------------------------------------------------------------------
    # - Mesh.new(image, cols: 8, rows: 8) のように Image を第1引数に渡した場合は Mesh.grid として動作
    # - Mesh.new(data: ..., count: ..., pipeline: ...) の場合は生バイナリ VBO メッシュとして動作
    def initialize(image_or_nil = nil,
                   cols: 8,
                   rows: 8,
                   data: nil,
                   indices: nil,
                   count: 0,
                   pipeline: :triangles,
                   image: nil,
                   shader: nil,
                   uniforms: nil,
                   blend: :alpha,
                   width: nil,
                   height: nil)
      if image_or_nil.is_a?(Image) || (data.nil? && image.is_a?(Image))
        target_img = image_or_nil.is_a?(Image) ? image_or_nil : image
        g = self.class.grid(target_img, cols: cols, rows: rows, width: width, height: height, shader: shader, uniforms: uniforms, blend: blend)
        init_from_other(g)
        return
      end

      @image = image
      @shader = shader
      @uniforms = uniforms
      @blend = blend || :alpha
      @pipeline = resolve_pipeline(pipeline)
      @data = data
      @count = count.to_i
      @vertex_count = @count
      @width = (width || (@image ? @image.width : 0)).to_f
      @height = (height || (@image ? @image.height : 0)).to_f
      @cols = nil
      @rows = nil
      @vertices = nil
      @base_vertices = nil
      @indices = indices ? indices.map(&:to_i) : nil
      @index_count = @indices ? @indices.length : 0
      @managed = false
      @dirty = false
      @cursor = VertexCursor.new

      if @data && @count > 0
        rebuild_raw_native_mesh
      else
        @native_mesh = nil
      end
    end

    # ------------------------------------------------------------------
    # 3. 頂点変形 API (呼び出し時に自動で Dirty 化 → 描画直前に GPU 転送)
    # ------------------------------------------------------------------

    # ブロックによる全頂点一括変形 (GC アロケーションゼロ)
    def deform
      return self unless @managed && @vertices && block_given?

      v = @cursor
      verts = @vertices
      base = @base_vertices
      nx = @cols
      stride_c = nx ? (nx + 1) : 0
      n = @vertex_count
      i = 0
      vi = 0
      while i < n
        v.index  = i
        if stride_c > 0
          v.col = i % stride_c
          v.row = i / stride_c
        else
          v.col = i
          v.row = 0
        end
        v.base_x     = base[vi]
        v.base_y     = base[vi + 1]
        v.base_u     = base[vi + 2]
        v.base_v     = base[vi + 3]
        v.base_r     = base[vi + 4] * 255.0
        v.base_g     = base[vi + 5] * 255.0
        v.base_b     = base[vi + 6] * 255.0
        v.base_alpha = base[vi + 7] * 255.0

        v.x      = verts[vi]
        v.y      = verts[vi + 1]
        v.u      = verts[vi + 2]
        v.v      = verts[vi + 3]
        v.r      = verts[vi + 4] * 255.0
        v.g      = verts[vi + 5] * 255.0
        v.b      = verts[vi + 6] * 255.0
        v.alpha  = verts[vi + 7] * 255.0

        yield(v)

        verts[vi]     = v.x.to_f
        verts[vi + 1] = v.y.to_f
        verts[vi + 2] = v.u.to_f
        verts[vi + 3] = v.v.to_f
        verts[vi + 4] = (v.r.to_f * INV_255).clamp(0.0, 1.0)
        verts[vi + 5] = (v.g.to_f * INV_255).clamp(0.0, 1.0)
        verts[vi + 6] = (v.b.to_f * INV_255).clamp(0.0, 1.0)
        verts[vi + 7] = (v.alpha.to_f * INV_255).clamp(0.0, 1.0)

        i += 1
        vi += VERTEX_STRIDE
      end

      @dirty = true
      self
    end

    # 初期座標 (base_x, base_y) からの相対オフセット (dx, dy) で頂点を移動
    # - 格子指定: mesh.set_offset(col, row, dx, dy, alpha: 1.0)
    # - 通し番号: mesh.set_offset(index, dx, dy, alpha: 1.0)
    def set_offset(col_or_index, arg2, arg3 = nil, arg4 = nil, du: 0.0, dv: 0.0, color: nil, alpha: nil)
      return self unless @managed && @vertices

      if arg4.nil? && (!@cols || arg3.nil?)
        idx = col_or_index.to_i
        dx = arg2.to_f
        dy = (arg3 || 0.0).to_f
      else
        c = col_or_index.to_i
        r = arg2.to_i
        dx = (arg3 || 0.0).to_f
        dy = (arg4 || 0.0).to_f
        idx = r * ((@cols || 0) + 1) + c
      end

      return self if idx < 0 || idx >= @vertex_count

      vi = idx * VERTEX_STRIDE
      @vertices[vi]     = @base_vertices[vi] + dx
      @vertices[vi + 1] = @base_vertices[vi + 1] + dy
      @vertices[vi + 2] = @base_vertices[vi + 2] + du.to_f if du != 0.0
      @vertices[vi + 3] = @base_vertices[vi + 3] + dv.to_f if dv != 0.0
      if color
        cr, cg, cb, ca = Backend.normalize_color(color)
        @vertices[vi + 4] = cr
        @vertices[vi + 5] = cg
        @vertices[vi + 6] = cb
        @vertices[vi + 7] = ca
      end
      @vertices[vi + 7] = self.class.normalize_alpha_val(alpha) unless alpha.nil?
      @dirty = true
      self
    end

    # 格子点 (col, row) のピクセル座標 (x, y) を直接設定
    def set_point(col, row, x, y, u: nil, v: nil, color: nil, alpha: nil)
      return self unless @managed && @vertices
      c = col.to_i
      r = row.to_i
      idx = @cols ? (r * (@cols + 1) + c) : c
      set_vertex(idx, x, y, u, v, alpha, color: color)
    end

    # 格子点 (col, row) または通し番号 (index) の現在の頂点情報 [x, y, u, v, alpha, r, g, b] を取得
    def get_point(col, row = nil)
      return nil unless @managed && @vertices
      if row.nil?
        get_vertex(col.to_i)
      else
        c = col.to_i
        r = row.to_i
        idx = @cols ? (r * (@cols + 1) + c) : c
        get_vertex(idx)
      end
    end
    alias [] get_point

    # 通し番号 (index) の頂点を直接設定
    def set_vertex(index, x, y, u = nil, v = nil, alpha = nil, color: nil)
      return self unless @managed && @vertices
      idx = index.to_i
      return self if idx < 0 || idx >= @vertex_count

      vi = idx * VERTEX_STRIDE
      @vertices[vi]     = x.to_f unless x.nil?
      @vertices[vi + 1] = y.to_f unless y.nil?
      @vertices[vi + 2] = u.to_f unless u.nil?
      @vertices[vi + 3] = v.to_f unless v.nil?
      if color
        cr, cg, cb, ca = Backend.normalize_color(color)
        @vertices[vi + 4] = cr
        @vertices[vi + 5] = cg
        @vertices[vi + 6] = cb
        @vertices[vi + 7] = ca
      end
      @vertices[vi + 7] = self.class.normalize_alpha_val(alpha) unless alpha.nil?
      @dirty = true
      self
    end

    # 通し番号 (index) の頂点情報 [x, y, u, v, alpha, r, g, b] を取得 (色・アルファは 0〜255)
    def get_vertex(index)
      return nil unless @managed && @vertices
      idx = index.to_i
      return nil if idx < 0 || idx >= @vertex_count
      vi = idx * VERTEX_STRIDE
      [
        @vertices[vi],
        @vertices[vi + 1],
        @vertices[vi + 2],
        @vertices[vi + 3],
        @vertices[vi + 7] * 255.0,
        @vertices[vi + 4] * 255.0,
        @vertices[vi + 5] * 255.0,
        @vertices[vi + 6] * 255.0
      ]
    end

    # 4隅の座標 (左上, 右上, 右下, 左下) を指定してメッシュ全体をバイリニア補間変形
    # DXRuby の draw_morph のような自由変形・台形パース表現が 1 行で行えます。
    # 8引数 (x0, y0, x1, y1, x2, y2, x3, y3) または 4配列 ([x0, y0], [x1, y1], [x2, y2], [x3, y3]) の両方に対応。
    # 格子分割された Mesh.grid(img, 8, 8) 等に対して呼ぶと、対角線の折れ歪みが出ない綺麗な自由変形になります。
    def set_corners(*args, alphas: nil, colors: nil)
      return self unless @managed && @vertices

      if args.length == 4 && args[0].is_a?(Array)
        x0f = args[0][0].to_f; y0f = args[0][1].to_f
        x1f = args[1][0].to_f; y1f = args[1][1].to_f
        x2f = args[2][0].to_f; y2f = args[2][1].to_f
        x3f = args[3][0].to_f; y3f = args[3][1].to_f
      elsif args.length >= 8
        x0f = args[0].to_f; y0f = args[1].to_f
        x1f = args[2].to_f; y1f = args[3].to_f
        x2f = args[4].to_f; y2f = args[5].to_f
        x3f = args[6].to_f; y3f = args[7].to_f
      else
        raise ArgumentError, "set_corners expects 8 coordinates (x0,y0..x3,y3) or 4 [x,y] pairs"
      end

      c0 = colors && colors[0] ? Backend.normalize_color(colors[0]) : nil
      c1 = colors && colors[1] ? Backend.normalize_color(colors[1]) : nil
      c2 = colors && colors[2] ? Backend.normalize_color(colors[2]) : nil
      c3 = colors && colors[3] ? Backend.normalize_color(colors[3]) : nil

      a0 = alphas && alphas[0] ? self.class.normalize_alpha_val(alphas[0]) : nil
      a1 = alphas && alphas[1] ? self.class.normalize_alpha_val(alphas[1]) : nil
      a2 = alphas && alphas[2] ? self.class.normalize_alpha_val(alphas[2]) : nil
      a3 = alphas && alphas[3] ? self.class.normalize_alpha_val(alphas[3]) : nil

      verts = @vertices
      base = @base_vertices
      n = @vertex_count
      vi = 0
      n.times do
        u = base[vi + 2]
        v = base[vi + 3]
        iu = 1.0 - u
        iv = 1.0 - v

        w0 = iu * iv # 左上 (0, 0)
        w1 = u  * iv # 右上 (1, 0)
        w2 = u  * v  # 右下 (1, 1)
        w3 = iu * v  # 左下 (0, 1)

        verts[vi]     = x0f * w0 + x1f * w1 + x2f * w2 + x3f * w3
        verts[vi + 1] = y0f * w0 + y1f * w1 + y2f * w2 + y3f * w3
        if c0 && c1 && c2 && c3
          verts[vi + 4] = c0[0] * w0 + c1[0] * w1 + c2[0] * w2 + c3[0] * w3
          verts[vi + 5] = c0[1] * w0 + c1[1] * w1 + c2[1] * w2 + c3[1] * w3
          verts[vi + 6] = c0[2] * w0 + c1[2] * w1 + c2[2] * w2 + c3[2] * w3
          verts[vi + 7] = c0[3] * w0 + c1[3] * w1 + c2[3] * w2 + c3[3] * w3
        end
        if a0 && a1 && a2 && a3
          verts[vi + 7] = a0 * w0 + a1 * w1 + a2 * w2 + a3 * w3
        end
        vi += VERTEX_STRIDE
      end

      @dirty = true
      self
    end

    # 中心線の点列 [[x0, y0], [x1, y1], ...] に沿って帯状（リボン・軌跡・触手）に頂点を配置
    # - width: リボンの太さ（ピクセル単位、または各節の太さの配列）
    # - fade: true の場合、先頭 (alpha=255) から末端 (alpha=0) へ自動的に透明度を減衰
    # - taper: true の場合、末端に向かって太さを徐々に細くする
    def set_ribbon(points, width: 24.0, fade: false, taper: false, start_alpha: 255.0, end_alpha: 0.0)
      return self unless @managed && @vertices && @cols && @rows
      return self if points.nil? || points.length < 2

      nx = @cols
      ny = @rows
      pts_len = points.length
      half_w_base = width.is_a?(Numeric) ? (width.to_f * 0.5) : 12.0
      sa = self.class.normalize_alpha_val(start_alpha)
      ea = self.class.normalize_alpha_val(end_alpha)

      verts = @vertices
      stride_x = nx + 1

      0.upto(nx) do |ix|
        t = ix.to_f / nx.to_f
        # 点列上の補間位置
        pos_f = t * (pts_len - 1)
        idx0 = pos_f.floor
        idx1 = [idx0 + 1, pts_len - 1].min
        frac = pos_f - idx0

        p0 = points[idx0]
        p1 = points[idx1]
        cx = p0[0].to_f + (p1[0].to_f - p0[0].to_f) * frac
        cy = p0[1].to_f + (p1[1].to_f - p0[1].to_f) * frac

        # 接線ベクトルから法線ベクトル (nx_v, ny_v) を算出
        tan_i0 = idx0 > 0 ? (idx0 - 1) : 0
        tan_i1 = [idx0 + 1, pts_len - 1].min
        dx = points[tan_i1][0].to_f - points[tan_i0][0].to_f
        dy = points[tan_i1][1].to_f - points[tan_i0][1].to_f
        len = Math.sqrt(dx * dx + dy * dy)
        if len > 0.0001
          nx_v = -dy / len
          ny_v = dx / len
        else
          nx_v = 0.0
          ny_v = 1.0
        end

        hw = if width.is_a?(Array)
               w_val = width[idx0].to_f + ((width[idx1] || width[idx0]).to_f - width[idx0].to_f) * frac
               w_val * 0.5
             else
               half_w_base
             end
        hw *= (1.0 - t) if taper
        col_alpha = fade ? (sa + (ea - sa) * t) : nil

        0.upto(ny) do |iy|
          v_ratio = (iy.to_f / ny.to_f) * 2.0 - 1.0 # -1.0 (上端) .. +1.0 (下端)
          vi = (iy * stride_x + ix) * VERTEX_STRIDE
          verts[vi]     = cx + nx_v * hw * v_ratio
          verts[vi + 1] = cy + ny_v * hw * v_ratio
          verts[vi + 7] = col_alpha if col_alpha
        end
      end

      @dirty = true
      self
    end

    # すべての頂点を生成時の初期状態にリセット
    def reset!
      return self unless @managed && @vertices && @base_vertices
      i = 0
      len = @vertices.length
      while i < len
        @vertices[i] = @base_vertices[i]
        i += 1
      end
      @dirty = true
      self
    end
    alias reset_deform! reset!

    # 低レベル互換: パック済みバイナリによる部分/全体更新
    def update(binary_data, offset: 0)
      return self unless binary_data
      if @data && offset > 0 && offset + binary_data.bytesize <= @data.bytesize
        @data[offset, binary_data.bytesize] = binary_data
      elsif offset == 0
        @data = binary_data
      end
      @native_mesh&.update_vertices(binary_data, offset, @count)
      self
    end

    # 変形により Dirty になっている場合のみ VRAM の VBO を更新
    def sync_to_gpu_if_dirty!
      return unless @dirty && @managed && @vertices && @native_mesh
      @data = @vertices.pack("f*")
      @native_mesh.update_vertices(@data, 0, @vertex_count)
      @dirty = false
    end

    def dynamic?
      @native_mesh ? @native_mesh.dynamic? : false
    end

    def data=(new_data)
      @data = new_data
      if @native_mesh && @data && @count > 0
        @native_mesh.update_vertices(@data, 0, @count)
      elsif @data && @count > 0
        rebuild_raw_native_mesh
      end
    end

    def count=(new_count)
      @count = new_count.to_i
      @vertex_count = @count
      if @native_mesh && @data && @count > 0
        @native_mesh.update_vertices(@data, 0, @count)
      elsif @data && @count > 0
        rebuild_raw_native_mesh
      end
    end

    def pipeline=(new_pipeline)
      @pipeline = resolve_pipeline(new_pipeline)
      rebuild_raw_native_mesh if !@managed && @data && @count > 0
    end

    # ------------------------------------------------------------------
    # 4. Image 互換インターフェース & 描画メソッド
    # ------------------------------------------------------------------
    def x
      @image ? @image.x : 0
    end

    def y
      @image ? @image.y : 0
    end

    def texture_width
      @image ? @image.texture_width : 1
    end

    def texture_height
      @image ? @image.texture_height : 1
    end

    def texture_id
      @image ? @image.texture_id : 0
    end

    def uv
      @image ? @image.uv : [0.0, 0.0, 1.0, 1.0]
    end

    def sub_image?
      @image ? @image.sub_image? : false
    end

    # 単体描画 (Window.draw と完全に同じ仕組みで描画)
    def draw(x = nil, y = nil,
             anchor: :top_left,
             pivot: :center,
             color: :white,
             angle: 0.0,
             scale: nil,
             scale_x: 1.0,
             scale_y: 1.0,
             alpha: 255,
             blend: nil,
             shader: nil,
             image: nil,
             uniforms: nil,
             camera: true,
             z: 0.0)
      Window.draw(
        x || 0.0,
        y || 0.0,
        self,
        anchor: anchor,
        pivot: pivot,
        color: color,
        angle: angle,
        scale: scale,
        scale_x: scale_x,
        scale_y: scale_y,
        alpha: alpha,
        blend: blend,
        shader: shader,
        uniforms: uniforms,
        image_override: image,
        camera: camera,
        z: z
      )
    end

    # アルファ値の正規化 (0〜255 -> 0.0..1.0)
    def self.normalize_alpha_val(val)
      return 1.0 if val.nil?
      (val.to_f * INV_255).clamp(0.0, 1.0)
    end

    # 多角形の耳刈り法 (Ear Clipping) による自動三角形分割 (凸・凹多角形対応)
    def self.triangulate_polygon(points)
      n = points.length
      return [0, 1, 2] if n == 3
      return [] if n < 3

      # 符号付き面積で向き (CCW / CW) を判定
      area2 = 0.0
      n.times do |i|
        p0 = points[i]
        p1 = points[(i + 1) % n]
        area2 += (p0[0] * p1[1] - p1[0] * p0[1])
      end
      sign = area2 >= 0.0 ? 1.0 : -1.0

      avail = (0...n).to_a
      tris = []
      guard = n * 3

      while avail.length > 3 && guard > 0
        guard -= 1
        ear_found = false
        len = avail.length

        len.times do |i|
          i_prev = avail[(i - 1) % len]
          i_curr = avail[i]
          i_next = avail[(i + 1) % len]

          ax, ay = points[i_prev]
          bx, by = points[i_curr]
          cx, cy = points[i_next]

          cross = ((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) * sign
          next if cross <= 1e-7

          # 三角形 (a, b, c) の内部に他の頂点が含まれていないかチェック
          has_point_inside = false
          avail.each do |idx|
            next if idx == i_prev || idx == i_curr || idx == i_next
            px, py = points[idx]
            c1 = ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) * sign
            c2 = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) * sign
            c3 = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) * sign
            if c1 >= -1e-7 && c2 >= -1e-7 && c3 >= -1e-7
              has_point_inside = true
              break
            end
          end

          unless has_point_inside
            tris.push(i_prev, i_curr, i_next)
            avail.delete_at(i)
            ear_found = true
            break
          end
        end

        unless ear_found
          # 自己交差等の縮退ケースではファン分割にフォールバック
          avail.delete_at(1)
          tris.push(avail[0], avail[1], avail[2]) if avail.length >= 3
        end
      end

      if avail.length == 3
        tris.push(avail[0], avail[1], avail[2])
      end
      tris
    end

    private

    def init_managed(img, w, h, cols, rows, verts, idxs, shader: nil, uniforms: nil, blend: :alpha)
      @image = img
      @width = w.to_f
      @height = h.to_f
      @cols = cols
      @rows = rows
      @vertices = verts
      @base_vertices = verts.dup
      @indices = idxs
      @vertex_count = verts.length / VERTEX_STRIDE
      @count = @vertex_count
      @index_count = idxs ? idxs.length : 0
      @pipeline = Backend::Pipelines::SPRITE
      @shader = shader
      @uniforms = uniforms
      @blend = blend || :alpha
      @managed = true
      @dirty = false
      @cursor = VertexCursor.new

      @data = @vertices.pack("f*")
      idx_bin = (@indices && !@indices.empty?) ? @indices.pack("I*") : ""
      @native_mesh = Native::Mesh.new(
        Backend::Topology::TRIANGLES,
        Backend::Layout::POS2_UV2_COLOR4,
        @data,
        @data.bytesize,
        @vertex_count,
        idx_bin,
        @index_count
      )
      self
    end

    def init_from_other(other)
      @image = other.image
      @width = other.width
      @height = other.height
      @cols = other.cols
      @rows = other.rows
      @vertices = other.vertices
      @base_vertices = other.base_vertices
      @indices = other.indices
      @vertex_count = other.vertex_count
      @count = other.vertex_count
      @index_count = other.index_count
      @pipeline = other.pipeline
      @shader = other.shader
      @uniforms = other.uniforms
      @blend = other.blend
      @managed = true
      @dirty = false
      @cursor = VertexCursor.new
      @data = other.instance_variable_get(:@data)
      @native_mesh = other.native_mesh
    end

    def resolve_pipeline(p)
      case p
      when Backend::Pipeline
        p
      when :triangles
        Backend::Pipelines::TRIANGLES
      when :lines
        Backend::Pipelines::LINES
      when :points
        Backend::Pipelines::POINTS
      when :triangle_strip
        Backend::Pipelines::TRIANGLE_STRIP
      when :textured_triangles
        Backend::Pipelines::TEXTURED_TRIANGLES
      when :textured_triangle_strip
        Backend::Pipelines::TEXTURED_TRIANGLE_STRIP
      when :sprite
        Backend::Pipelines::SPRITE
      when :card
        Backend::Pipelines::CARD
      else
        Backend::Pipelines::TRIANGLES
      end
    end

    def rebuild_raw_native_mesh
      idx_bin = (@indices && !@indices.empty?) ? @indices.pack("I*") : ""
      @native_mesh = Native::Mesh.new(
        @pipeline.topology,
        @pipeline.layout,
        @data,
        @data.bytesize,
        @count,
        idx_bin,
        @index_count
      )
    end
  end

  # ====================================================================
  # VRAM常駐インスタンスバッファ (Zenoo::InstanceBuffer)
  # - Stream 1 (divisor = 1) として大量のインスタンス属性を VRAM に保持するクラス
  # - GPU パーティクルや GPU 弾幕など、数万〜数十万個のインスタンスを
  #   毎フレームの CPU 転送ゼロで描画する用途に使用します。
  # - Stream 0 (形状) には 4頂点ビルボード (mesh: nil) または任意の Mesh を指定可能。
  # ====================================================================
  class InstanceBuffer
    attr_accessor :image, :mesh, :shader, :uniforms, :blend
    attr_reader   :layout, :count, :data, :native_buffer

    def initialize(data:, count:, layout:, image: nil, mesh: nil, shader: nil, uniforms: nil, blend: :alpha)
      @data = data
      @count = count.to_i
      @layout = normalize_layout(layout)
      @image = image
      @mesh = mesh
      @shader = shader
      @uniforms = uniforms
      @blend = blend || :alpha

      if @data && @count > 0
        @native_buffer = Native::Mesh.new(
          Backend::Topology::TRIANGLE_STRIP,
          @layout,
          @data,
          @data.bytesize,
          @count,
          "",
          0
        )
      else
        @native_buffer = nil
      end
    end

    def update(binary_data, offset: 0, count: nil)
      return self unless binary_data
      @count = count.to_i if count
      if @data && offset > 0 && offset + binary_data.bytesize <= @data.bytesize
        @data[offset, binary_data.bytesize] = binary_data
      elsif offset == 0
        @data = binary_data
      end
      @native_buffer&.update_vertices(binary_data, offset, @count)
      self
    end

    def dynamic?
      @native_buffer ? @native_buffer.dynamic? : false
    end

    def draw(z: 0.0, uniforms: nil, shader: nil, image: nil, mesh: nil, blend: nil)
      return unless @native_buffer && @count > 0

      eff_mesh = mesh || @mesh
      eff_mesh.sync_to_gpu_if_dirty! if eff_mesh.is_a?(Mesh)
      eff_image = image || @image || (eff_mesh.is_a?(Mesh) ? eff_mesh.image : nil)
      eff_shader = shader || @shader
      return unless eff_shader

      eff_blend = Backend.normalize_blend_mode(blend || @blend)
      eff_uniforms = if @uniforms && uniforms
                       @uniforms.merge(uniforms)
                     else
                       uniforms || @uniforms
                     end

      Backend.enqueue_draw(
        Backend::Pipelines::SPRITE,
        nil,
        @count,
        image: eff_image,
        shader: eff_shader,
        uniforms: eff_uniforms,
        blend: eff_blend,
        z: z,
        mesh: eff_mesh.is_a?(Mesh) ? eff_mesh.native_mesh : nil,
        inst_buffer: @native_buffer
      )
    end

    private

    def normalize_layout(l)
      if l.is_a?(Array)
        l.map(&:to_i).pack("C*")
      elsif l.is_a?(Backend::Pipeline)
        l.layout
      else
        l.to_s
      end
    end
  end
end

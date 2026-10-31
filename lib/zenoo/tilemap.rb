# frozen_string_literal: true

module Zenoo
  # ============================================================================
  # 2D タイルマップ描画・レイヤー・衝突管理クラス (Zenoo::Tilemap)
  # - 行 (Row) 単位の Mesh 構築により、高速描画・部分更新・視錐台カリングを実現
  # - Zオーダー (固定Z / 行単位のYソートZ) と根元オフセットにより、
  #   見下ろしゲームでの「柱や壁の裏への回り込み・手前での重なり」を自動解決
  # - 単一レイヤーでも複数レイヤーでも同じシンプルな記述で利用可能
  # ============================================================================
  class Tilemap
    # セル値のビットフィールド定義 (符号ビットに触れない正整数 28bit 構成)
    # - bit  0..15 (0x0000FFFF): タイルID (0..65535)
    # - bit 16..23 (0x00FF0000): 根元オフセット+1 (0=タイル定義に従う, 1..255=0..254マス下が根元)
    # - bit 24     (0x01000000): 左右反転 (FLIP_H)
    # - bit 25     (0x02000000): 上下反転 (FLIP_V)
    # - bit 26..27 (0x0C000000): 90度単位の時計回り回転 (0:0度, 1:90度, 2:180度, 3:270度)
    ID_MASK      = 0x0000FFFF
    OFFSET_SHIFT = 16
    OFFSET_MASK  = 0xFF
    FLIP_H       = 0x01000000
    FLIP_V       = 0x02000000
    ROT_SHIFT    = 26
    ROT_MASK     = 0x03
    ROT_90       = 1 << ROT_SHIFT
    ROT_180      = 2 << ROT_SHIFT
    ROT_270      = 3 << ROT_SHIFT

    # タイル番号に反転・回転・根元オフセットをパックした整数値を生成
    def self.tile(tile_id, flip_h: false, flip_v: false, rotate: 0, root_offset: nil)
      return nil if tile_id.nil? || tile_id < 0
      val = tile_id.to_i & ID_MASK
      if root_offset
        off = root_offset.to_i.clamp(0, 254) + 1
        val |= (off << OFFSET_SHIFT)
      end
      val |= FLIP_H if flip_h
      val |= FLIP_V if flip_v
      rot = rotate.to_i
      rot_code = if rot == 90 || rot == 1
                   1
                 elsif rot == 180 || rot == 2
                   2
                 elsif rot == 270 || rot == -90 || rot == 3
                   3
                 else
                   0
                 end
      val |= (rot_code << ROT_SHIFT)
      val
    end

    # ==========================================================================
    # Layer: 行単位 Mesh を管理する単一タイルレイヤー
    # ==========================================================================
    class Layer
      attr_reader   :name, :tilemap, :rows, :cols
      attr_accessor :z, :y_sort, :z_offset, :solid, :visible, :alpha, :color, :blend

      def initialize(tilemap, name, data,
                     z: 0.0,
                     y_sort: false,
                     z_offset: 0.0,
                     solid: false,
                     visible: true,
                     alpha: 255,
                     color: :white,
                     blend: :alpha)
        @tilemap = tilemap
        @name = name
        @data = data || []
        @z = z.to_f
        @y_sort = !!y_sort
        @z_offset = z_offset.to_f
        @solid = !!solid
        @visible = visible.nil? ? true : !!visible
        @alpha = alpha
        @color = color
        @blend = blend || :alpha

        @rows = 0
        @cols = 0
        @row_meshes = []
        @row_extras = []
        @row_dirty = []
        @all_dirty = true
        @max_cell_offset = 0
        @max_tall_rows = 0
        @temp_verts = []

        refresh_size!
      end

      def data
        @data
      end

      def data=(new_data)
        @data = new_data || []
        refresh_size!
      end

      def refresh_size!
        @rows = @data.is_a?(Array) ? @data.size : 0
        @cols = (@rows > 0 && @data[0].is_a?(Array)) ? @data[0].size : 0
        while @row_dirty.size < @rows
          @row_dirty << true
          @row_meshes << nil
          @row_extras << nil
        end
        @all_dirty = true
        scan_cell_offsets!
      end

      def invalidate!
        @all_dirty = true
      end

      # 生のセル整数値を取得
      def raw_at(col, row)
        return nil if row < 0 || row >= @rows || col < 0 || col >= @cols
        row_data = @data[row]
        row_data ? row_data[col] : nil
      end

      # タイルID (フラグを除いた番号) を取得
      def [](col, row)
        raw = raw_at(col, row)
        (raw && raw >= 0) ? (raw & ID_MASK) : nil
      end

      # タイルID (または Tilemap.tile で生成したセル値) を設定
      def []=(col, row, val)
        return if row < 0 || row >= @rows || col < 0 || col >= @cols
        row_data = @data[row]
        return unless row_data

        old_raw = row_data[col]
        return if old_raw == val
        row_data[col] = val

        # 変更前のタイルが帰属していた行と、変更後のタイルが帰属する行を Dirty にする
        mark_dirty_row_for_raw(row, old_raw)
        mark_dirty_row_for_raw(row, val)
      end

      def draw(x: nil, y: nil, z: nil, camera: nil)
        return unless @visible
        tw_base = @tilemap.tile_width.to_f
        th_base = @tilemap.tile_height.to_f
        return if @rows == 0 || @cols == 0 || tw_base <= 0.0 || th_base <= 0.0

        sx = @tilemap.scale_x
        sy = @tilemap.scale_y
        tw = tw_base * sx
        th = th_base * sy
        return if tw <= 0.0 || th <= 0.0

        draw_x = (x || @tilemap.x).to_f
        draw_y = (y || @tilemap.y).to_f
        base_z = (z || (@tilemap.z + @z)).to_f
        draw_camera = camera.nil? ? @tilemap.camera : camera

        eff_alpha = (@alpha * @tilemap.alpha) / 255
        eff_color = (@color == :white || @color.nil?) ? @tilemap.color : @color

        # 可視行範囲の算出 (Frustum Culling)
        cur_target = Backend.current_target
        win_w = cur_target ? cur_target.width.to_f : Window.width.to_f
        win_h = cur_target ? cur_target.height.to_f : Window.height.to_f
        if draw_camera && Window.camera_enabled?
          _left, top, _right, bottom = Window.camera.visible_rect(win_w, win_h)
        else
          top = 0.0
          bottom = win_h
        end

        max_off = @tilemap.max_root_offset
        max_off = @max_cell_offset if @max_cell_offset > max_off
        tall_margin = [max_off, @max_tall_rows].max + 1

        min_row = [((top - draw_y) / th).floor - 1, 0].max
        max_row = [((bottom - draw_y) / th).floor + tall_margin, @rows - 1].min
        return if min_row > max_row

        rebuild_all_dirty! if @all_dirty

        r = min_row
        while r <= max_row
          rebuild_row!(r) if @row_dirty[r]

          row_z = if @y_sort
                    base_z + draw_y + ((r + 1) * th) + (@z_offset * sy)
                  else
                    base_z
                  end

          mesh = @row_meshes[r]
          if mesh && mesh.count > 0
            Window.draw(
              draw_x,
              draw_y + r * th,
              mesh,
              anchor: :top_left,
              pivot: :top_left,
              scale_x: sx,
              scale_y: sy,
              color: eff_color,
              alpha: eff_alpha,
              blend: @blend,
              camera: draw_camera,
              z: row_z
            )
          end

          extras = @row_extras[r]
          if extras
            draw_row_extras(extras, draw_x, draw_y, sx, sy, tw, th, eff_color, eff_alpha, draw_camera, row_z)
          end

          r += 1
        end
      end

      private

      def mark_dirty_row_for_raw(row, raw)
        @row_dirty[row] = true
        return if raw.nil? || raw < 0
        tid = raw & ID_MASK
        cell_off = (raw >> OFFSET_SHIFT) & OFFSET_MASK
        if cell_off > 0
          off = cell_off - 1
          @max_cell_offset = off if off > @max_cell_offset
        else
          off = @tilemap.tile_root_offset(tid)
        end
        target_r = row + off
        target_r = @rows - 1 if target_r >= @rows
        @row_dirty[target_r] = true if target_r >= 0
      end

      def scan_cell_offsets!
        max_off = 0
        r = 0
        while r < @rows
          row_data = @data[r]
          if row_data
            c = 0
            len = row_data.size
            while c < len
              raw = row_data[c]
              if raw && raw > 0xFFFF
                cell_off = (raw >> OFFSET_SHIFT) & OFFSET_MASK
                if cell_off > 0
                  off = cell_off - 1
                  max_off = off if off > max_off
                end
              end
              c += 1
            end
          end
          r += 1
        end
        @max_cell_offset = max_off
      end

      def rebuild_all_dirty!
        r = 0
        while r < @rows
          @row_dirty[r] = true
          r += 1
        end
        @all_dirty = false
      end

      # 指定した行 target_row に帰属するタイル群から 1 行分の Mesh を構築
      def rebuild_row!(target_row)
        @row_dirty[target_row] = false
        tiles = @tilemap.tiles
        full_img = @tilemap.base_texture_image
        base_tex_id = full_img ? full_img.texture_id : 0
        tw = @tilemap.tile_width.to_f
        th = @tilemap.tile_height.to_f

        verts = @temp_verts
        verts.clear
        extras = nil

        max_off = @tilemap.max_root_offset
        max_off = @max_cell_offset if @max_cell_offset > max_off
        min_r = target_row - max_off
        min_r = 0 if min_r < 0

        r = min_r
        while r <= target_row
          row_data = @data[r]
          if row_data
            c = 0
            col_len = row_data.size
            col_len = @cols if col_len > @cols
            while c < col_len
              raw = row_data[c]
              if raw && raw >= 0
                tid = raw & ID_MASK
                img = tiles[tid]
                if img
                  cell_off = (raw >> OFFSET_SHIFT) & OFFSET_MASK
                  off = cell_off > 0 ? (cell_off - 1) : @tilemap.tile_root_offset(tid)
                  eff_row = r + off
                  eff_row = @rows - 1 if eff_row >= @rows

                  if eff_row == target_row
                    iw = img.width.to_f
                    ih = img.height.to_f
                    if ih > th
                      tall_rows = ((ih - th) / th).ceil + off
                      @max_tall_rows = tall_rows if tall_rows > @max_tall_rows
                    end

                    if img.texture_id == base_tex_id
                      append_tile_vertices(verts, img, c, r - target_row, tw, th, iw, ih, raw)
                    else
                      extras ||= []
                      extras.push(c, r - target_row, raw)
                    end
                  end
                end
              end
              c += 1
            end
          end
          r += 1
        end

        @row_extras[target_row] = extras
        v_count = verts.size / 8
        existing = @row_meshes[target_row]

        if v_count > 0 && full_img
          bin = verts.pack("f*")
          if existing
            existing.image = full_img
            existing.update(bin, count: v_count)
          else
            @row_meshes[target_row] = Mesh.new(
              data: bin,
              count: v_count,
              pipeline: :sprite,
              image: full_img,
              width: @cols * tw,
              height: th
            )
          end
        elsif existing
          existing.count = 0
        end
      end

      def append_tile_vertices(verts, img, col, rel_row, tw, th, iw, ih, raw)
        if iw == tw && ih == th
          x0 = col * tw
          y0 = rel_row * th
          x1 = x0 + tw
          y1 = y0 + th
        else
          # 大判タイルはマスの下端・水平中央を基準に上方向へ配置
          x0 = col * tw + (tw - iw) * 0.5
          y1 = (rel_row + 1) * th
          y0 = y1 - ih
          x1 = x0 + iw
        end

        tex_w = img.texture_width.to_f
        tex_h = img.texture_height.to_f
        u0 = tex_w > 0.0 ? (img.x.to_f / tex_w) : 0.0
        v0 = tex_h > 0.0 ? (img.y.to_f / tex_h) : 0.0
        u1 = tex_w > 0.0 ? ((img.x + img.width).to_f / tex_w) : 1.0
        v1 = tex_h > 0.0 ? ((img.y + img.height).to_f / tex_h) : 1.0

        if (raw & FLIP_H) != 0
          tmp = u0; u0 = u1; u1 = tmp
        end
        if (raw & FLIP_V) != 0
          tmp = v0; v0 = v1; v1 = tmp
        end

        rot = (raw >> ROT_SHIFT) & ROT_MASK
        if rot == 0
          ua = u0; va = v0
          ub = u1; vb = v0
          uc = u1; vc = v1
          ud = u0; vd = v1
        elsif rot == 1 # 90度時計回り
          ua = u0; va = v1
          ub = u0; vb = v0
          uc = u1; vc = v0
          ud = u1; vd = v1
        elsif rot == 2 # 180度
          ua = u1; va = v1
          ub = u0; vb = v1
          uc = u0; vc = v0
          ud = u1; vd = v0
        else           # 270度時計回り
          ua = u1; va = v0
          ub = u1; vb = v1
          uc = u0; vc = v1
          ud = u0; vd = v0
        end

        # 三角形1 (左上 a -> 左下 d -> 右上 b) & 三角形2 (右上 b -> 左下 d -> 右下 c)
        verts.push(
          x0, y0, ua, va, 1.0, 1.0, 1.0, 1.0,
          x0, y1, ud, vd, 1.0, 1.0, 1.0, 1.0,
          x1, y0, ub, vb, 1.0, 1.0, 1.0, 1.0,
          x1, y0, ub, vb, 1.0, 1.0, 1.0, 1.0,
          x0, y1, ud, vd, 1.0, 1.0, 1.0, 1.0,
          x1, y1, uc, vc, 1.0, 1.0, 1.0, 1.0
        )
      end

      def draw_row_extras(extras, draw_x, draw_y, sx, sy, tw, th, eff_color, eff_alpha, draw_camera, row_z)
        tiles = @tilemap.tiles
        i = 0
        len = extras.size
        while i < len
          c = extras[i]
          rel_r = extras[i + 1]
          raw = extras[i + 2]
          tid = raw & ID_MASK
          img = tiles[tid]
          if img
            iw = img.width * sx
            ih = img.height * sy
            tx = draw_x + c * tw + (tw - iw) * 0.5
            ty = draw_y + (rel_r + 1) * th - ih
            fx = (raw & FLIP_H) != 0 ? -sx : sx
            fy = (raw & FLIP_V) != 0 ? -sy : sy
            rot_ang = ((raw >> ROT_SHIFT) & ROT_MASK) * 90.0
            Window.draw(
              tx + iw * 0.5,
              ty + ih * 0.5,
              img,
              anchor: :center,
              pivot: :center,
              scale_x: fx,
              scale_y: fy,
              angle: rot_ang,
              color: eff_color,
              alpha: eff_alpha,
              blend: @blend,
              camera: draw_camera,
              z: row_z
            )
          end
          i += 3
        end
      end
    end

    # ==========================================================================
    # Tilemap 本体: 複数レイヤー・タイル属性・衝突判定の統括
    # ==========================================================================
    attr_accessor :x, :y, :z, :scale_x, :scale_y, :camera, :alpha, :color
    attr_reader   :tiles, :tile_width, :tile_height, :cols, :rows, :layers, :max_root_offset, :base_texture_image

    # 使い方1 (単一レイヤー): Tilemap.new(map_data, tiles, x: 0, y: 0, ...)
    # 使い方2 (複数レイヤー): Tilemap.new(tiles, tile_width: 32, tile_height: 32, ...)
    def initialize(arg1, arg2 = nil,
                   tile_width: nil,
                   tile_height: nil,
                   cols: 0,
                   rows: 0,
                   x: 0.0,
                   y: 0.0,
                   z: 0.0,
                   y_sort: false,
                   solid: false,
                   scale_x: 1.0,
                   scale_y: 1.0,
                   camera: true,
                   alpha: 255,
                   color: :white)
      if arg2.nil?
        init_data = nil
        @tiles = arg1 || []
      else
        init_data = arg1
        @tiles = arg2 || []
      end

      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
      @scale_x = scale_x.to_f
      @scale_y = scale_y.to_f
      @camera = camera
      @alpha = alpha
      @color = color

      first_tile = @tiles.is_a?(Array) ? @tiles.compact.first : nil
      @tile_width = (tile_width || (first_tile ? first_tile.width : 0)).to_i
      @tile_height = (tile_height || (first_tile ? first_tile.height : 0)).to_i
      @base_texture_image = build_base_texture_image(first_tile)

      @cols = cols.to_i
      @rows = rows.to_i

      @tile_root_offsets = []
      @tile_solids = []
      @max_root_offset = 0

      @layers = []
      @layer_names = []
      @temp_wall_rect = nil
      @candidate_buffer = []

      if init_data
        add_layer(:default, init_data, z: 0.0, y_sort: y_sort, solid: solid)
      end
    end

    def tiles=(new_tiles)
      @tiles = new_tiles || []
      first_tile = @tiles.is_a?(Array) ? @tiles.compact.first : nil
      if first_tile
        @tile_width = first_tile.width if @tile_width <= 0
        @tile_height = first_tile.height if @tile_height <= 0
      end
      @base_texture_image = build_base_texture_image(first_tile)
      invalidate_all_layers!
    end

    # タイル番号に対する属性 (根元オフセット・通行不可フラグ) を設定
    def set_tile(tile_id, root_offset: nil, solid: nil)
      return self if tile_id.nil? || tile_id < 0
      tid = tile_id.to_i
      if root_offset
        off = root_offset.to_i
        off = 0 if off < 0
        @tile_root_offsets[tid] = off
        @max_root_offset = off if off > @max_root_offset
        invalidate_all_layers!
      end
      unless solid.nil?
        @tile_solids[tid] = !!solid
      end
      self
    end

    # 縦に並ぶ柱や木などのタイル番号配列 (上から下へ) を一括定義
    # - 1次元配列 [top_id, mid_id, bottom_id] または 2次元配列 [[top_l, top_r], [bot_l, bot_r]] に対応
    # - 最下段 (根元) に solid フラグを設定し、上段には根元までの行数オフセットを自動設定します
    def define_column(tile_ids, solid: true)
      return self if !tile_ids.is_a?(Array) || tile_ids.empty?
      h = tile_ids.size
      i = 0
      while i < h
        off = (h - 1) - i
        is_bottom = (i == h - 1)
        item = tile_ids[i]
        if item.is_a?(Array)
          j = 0
          while j < item.size
            set_tile(item[j], root_offset: off, solid: is_bottom ? solid : false)
            j += 1
          end
        else
          set_tile(item, root_offset: off, solid: is_bottom ? solid : false)
        end
        i += 1
      end
      self
    end

    def tile_root_offset(tile_id)
      return 0 if tile_id.nil? || tile_id < 0
      @tile_root_offsets[tile_id] || 0
    end

    def tile_solid?(tile_id)
      return false if tile_id.nil? || tile_id < 0
      !!@tile_solids[tile_id]
    end

    # レイヤーを追加して返す
    def add_layer(name, data = nil,
                  z: 0.0,
                  y_sort: false,
                  z_offset: 0.0,
                  solid: false,
                  visible: true,
                  alpha: 255,
                  color: :white,
                  blend: :alpha)
      sym = name ? name.to_sym : :"layer_#{@layers.size}"
      grid = data
      unless grid
        grid = []
        r = 0
        while r < @rows
          grid << Array.new(@cols, nil)
          r += 1
        end
      end
      layer_obj = Layer.new(
        self, sym, grid,
        z: z, y_sort: y_sort, z_offset: z_offset,
        solid: solid, visible: visible,
        alpha: alpha, color: color, blend: blend
      )

      idx = @layer_names.index(sym)
      if idx
        @layers[idx] = layer_obj
      else
        @layer_names << sym
        @layers << layer_obj
      end

      @rows = layer_obj.rows if layer_obj.rows > @rows
      @cols = layer_obj.cols if layer_obj.cols > @cols
      layer_obj
    end

    # 名前またはインデックスでレイヤーを取得
    def layer(name_or_index)
      if name_or_index.is_a?(Integer)
        @layers[name_or_index]
      else
        idx = @layer_names.index(name_or_index.to_sym)
        idx ? @layers[idx] : nil
      end
    end

    # 単一レイヤー互換: data の取得・設定・サイズ更新
    def data
      first = @layers[0]
      first ? first.data : nil
    end

    def data=(new_data)
      if @layers.empty?
        add_layer(:default, new_data)
      else
        @layers[0].data = new_data
        refresh_size!
      end
    end

    def refresh_size!
      max_r = 0
      max_c = 0
      i = 0
      while i < @layers.size
        ly = @layers[i]
        ly.refresh_size!
        max_r = ly.rows if ly.rows > max_r
        max_c = ly.cols if ly.cols > max_c
        i += 1
      end
      @rows = max_r
      @cols = max_c
    end

    # マップ全体のピクセル幅
    def width
      @cols * @tile_width * @scale_x
    end

    # マップ全体のピクセル高さ
    def height
      @rows * @tile_height * @scale_y
    end

    # [col, row] で先頭レイヤーのタイルIDを取得、または [layer_name] で Layer を取得
    def [](arg1, row = nil)
      if row.nil?
        layer(arg1)
      else
        first = @layers[0]
        first ? first[arg1, row] : nil
      end
    end

    # 先頭レイヤーの指定した列・行にタイルIDを設定
    def []=(col, row, tile_id)
      first = @layers[0]
      first[col, row] = tile_id if first
    end

    # ピクセル座標 (px, py) から [col, row] を算出
    def tile_coords(px, py)
      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return nil if tw <= 0.0 || th <= 0.0

      col = ((px.to_f - @x) / tw).floor
      row = ((py.to_f - @y) / th).floor
      (col >= 0 && col < @cols && row >= 0 && row < @rows) ? [col, row] : nil
    end

    # ピクセル座標 (px, py) のタイルIDを取得
    def tile_at(px, py, layer_name: nil)
      coords = tile_coords(px, py)
      return nil unless coords
      target = layer_name ? layer(layer_name) : @layers[0]
      target ? target[coords[0], coords[1]] : nil
    end

    # ==========================================================================
    # 衝突判定 (Solid タイル判定 & 最寄り優先 MTV 壁ずり押し出し)
    # ==========================================================================

    # 指定したマス (col, row) が通行不可かどうか判定
    def solid_cell?(col, row)
      return false if col < 0 || col >= @cols || row < 0 || row >= @rows
      i = 0
      len = @layers.size
      while i < len
        ly = @layers[i]
        raw = ly.raw_at(col, row)
        if raw && raw >= 0
          return true if ly.solid
          tid = raw & ID_MASK
          return true if @tile_solids[tid]
        end
        i += 1
      end
      false
    end

    # ワールドピクセル座標 (px, py) が通行不可かどうか判定
    def solid_at?(px, py)
      coords = tile_coords(px, py)
      coords ? solid_cell?(coords[0], coords[1]) : false
    end

    # Sprite または Collision::Shape がマップの障害物タイルと接触しているか判定
    def collide?(target)
      return false unless target
      col_shape = target.is_a?(Collision::Shape) ? target : (target.respond_to?(:collider) ? target.collider : nil)
      return false unless col_shape

      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return false if tw <= 0.0 || th <= 0.0

      cx = col_shape.center_x
      cy = col_shape.center_y
      br = col_shape.bounding_radius

      min_c = [((cx - br - @x) / tw).floor, 0].max
      max_c = [((cx + br - @x) / tw).floor, @cols - 1].min
      min_r = [((cy - br - @y) / th).floor, 0].max
      max_r = [((cy + br - @y) / th).floor, @rows - 1].min
      return false if min_c > max_c || min_r > max_r

      wall = prepare_wall_rect(tw, th)
      r = min_r
      while r <= max_r
        c = min_c
        while c <= max_c
          if solid_cell?(c, r)
            wall.x = @x + c * tw
            wall.y = @y + r * th
            wall.update_cache
            return true if Collision.check(col_shape, wall)
          end
          c += 1
        end
        r += 1
      end
      false
    end

    # スプライトを障害物タイルから滑らかに壁ずり押し出し (最寄りタイル優先 MTV)
    def resolve_collision(sprite, target_root: true)
      return false if sprite.nil? || (sprite.respond_to?(:vanished?) && sprite.vanished?)
      col_shape = sprite.collider
      return false unless col_shape

      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return false if tw <= 0.0 || th <= 0.0

      cx = col_shape.center_x
      cy = col_shape.center_y
      br = col_shape.bounding_radius

      min_c = [((cx - br - @x) / tw).floor, 0].max
      max_c = [((cx + br - @x) / tw).floor, @cols - 1].min
      min_r = [((cy - br - @y) / th).floor, 0].max
      max_r = [((cy + br - @y) / th).floor, @rows - 1].min
      return false if min_c > max_c || min_r > max_r

      # 候補タイルをフラット配列 [c, r, dist_sq, ...] に収集し、距離の昇順で挿入ソート
      buf = @candidate_buffer
      buf.clear
      r = min_r
      while r <= max_r
        c = min_c
        while c <= max_c
          if solid_cell?(c, r)
            dx = (@x + (c + 0.5) * tw) - cx
            dy = (@y + (r + 0.5) * th) - cy
            d2 = dx * dx + dy * dy

            # 挿入位置を探索 (3要素単位)
            pos = buf.size
            while pos >= 3 && buf[pos - 1] > d2
              pos -= 3
            end
            buf.insert(pos, c, r, d2)
          end
          c += 1
        end
        r += 1
      end

      return false if buf.empty?

      wall = prepare_wall_rect(tw, th)
      resolved_any = false
      pass = 0
      while pass < 2
        hit_in_pass = false
        i = 0
        len = buf.size
        while i < len
          c = buf[i]
          r = buf[i + 1]
          wall.x = @x + c * tw
          wall.y = @y + r * th
          wall.update_cache
          if sprite.push_out_of(wall, target_root: target_root)
            hit_in_pass = true
            resolved_any = true
          end
          i += 3
        end
        break unless hit_in_pass
        pass += 1
      end
      resolved_any
    end

    # 全レイヤーを一括描画
    def draw(x: nil, y: nil, z: nil, camera: nil)
      i = 0
      len = @layers.size
      while i < len
        @layers[i].draw(x: x, y: y, z: z, camera: camera)
        i += 1
      end
    end

    private

    def build_base_texture_image(first_tile)
      return nil unless first_tile
      if first_tile.sub_image?
        first_tile.sub_image(-first_tile.x, -first_tile.y, first_tile.texture_width, first_tile.texture_height)
      else
        first_tile
      end
    end

    def invalidate_all_layers!
      i = 0
      while i < @layers.size
        @layers[i].invalidate!
        i += 1
      end
    end

    def prepare_wall_rect(tw, th)
      if @temp_wall_rect.nil?
        @temp_wall_rect = Collision::Rect.new(0.0, 0.0, tw, th, anchor: :top_left)
      elsif @temp_wall_rect.width != tw || @temp_wall_rect.height != th
        @temp_wall_rect.width = tw
        @temp_wall_rect.height = th
      end
      @temp_wall_rect
    end
  end
end

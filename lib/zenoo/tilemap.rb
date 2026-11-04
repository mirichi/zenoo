# frozen_string_literal: true

module Zenoo
  # ============================================================================
  # 2D タイルマップ描画・レイヤー・衝突管理クラス (Zenoo::Tilemap)
  # ============================================================================
  #
  # 【設計コンセプト】
  # 1. 行 (Row) 単位の Mesh 化:
  #    - タイル1枚ずつ draw を呼ぶのではなく、1行のタイル群を 1 つの Zenoo::Mesh
  #      (VBO頂点バッファ) にまとめて GPU へ転送します。
  #    - タイルが書き換わった時も、該当する 1 行の VBO のみをピンポイントで再構築・
  #      更新するため、VRAM 負荷と CPU-GPU 転送が最小限で済みます。
  #
  # 2. Zオーダーと行単位 Yソートの自動解決:
  #    - 見下ろし (クォータービュー) ゲームでは、Y座標が大きい (手前にある) 物体ほど
  #      手前に描画する必要があります。
  #    - レイヤーに `y_sort: true` を設定すると、各行の Mesh の Z値にその行の足元Y座標が
  #      自動設定されます。キャラ側も `sprite.z = sprite.y` とするだけで、
  #      エンジンの Z ソート機能によって「奥の壁 → キャラ → 手前の壁」の重なりが
  #      ソート処理のコードなしで完全自動解決します。
  #
  # 3. 柱や背の高い立体物の「根元Z統合 (root_offset)」:
  #    - 3マス分の高さがある柱などの場合、先端や中段パーツを行通りに描画すると
  #      キャラが裏へ回った時に頭を突き抜けてしまう問題が生じます。
  #    - 本クラスでは、上段パーツの頂点を「根元 (最下段) の行 Mesh」へ自動帰属させます。
  #      これにより、柱全体が「根元の足元Y座標の Z値」で描画されるため、
  #      「キャラが柱の手前に立つとキャラが手前に出る」「裏へ回ると柱の裏に綺麗に隠れる」
  #      が両立します。
  #
  # 4. 最寄り優先 MTV 壁ずり衝突判定:
  #    - キャラの足元コライダーと接触している周囲の障害物タイルを収集し、
  #      足元中心から最も近い順にソートして押し出し (MTV) を適用します。
  #    - これにより、ブロック同士の継ぎ目や角での引っかかりが原理的に排除され、
  #      滑らかな壁ずり移動が実現します。
  # ============================================================================
  class Tilemap
    # --------------------------------------------------------------------------
    # セル値のビットフィールド定義 (符号ビットに触れない正整数 28bit 構成)
    # --------------------------------------------------------------------------
    # マップ配列 (data[row][col]) を純粋な Integer 配列のまま維持しつつ、
    # タイルごとの反転・回転・オフセットを表現するために上位ビットを活用します。
    #
    # - bit  0..15 (0x0000FFFF): 純粋なタイルID (0..65535)
    # - bit 16..23 (0x00FF0000): 根元オフセット+1
    #                             0: 未指定 (タイル属性 set_tile の設定に従う)
    #                             1..255: このマスから 0..254 行下が根元
    # - bit 24     (0x01000000): 左右反転 (FLIP_H)
    # - bit 25     (0x02000000): 上下反転 (FLIP_V)
    # - bit 26..27 (0x0C000000): 90度単位の時計回り回転
    #                             0: 0度, 1: 90度, 2: 180度, 3: 270度
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

    # タイル番号に反転・回転・根元オフセットをパックした整数値を生成するヘルパー
    # 例:
    #   H = Tilemap.tile(10, flip_h: true)             # 10番タイルを左右反転
    #   R = Tilemap.tile(15, rotate: 90)               # 15番タイルを時計回りに90度回転
    #   P = Tilemap.tile(20, root_offset: 2)           # 20番タイルは2行下が根元
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
    # Animation: アニメーションタイルの定義と状態管理クラス (純粋なタイルID管理)
    # ==========================================================================
    class Animation
      attr_reader   :id, :frames, :weights, :total_frames
      attr_accessor :current_frame, :timer, :changed

      def initialize(id, frames:, wait: 10)
        @id = id.to_i
        @frames = frames.map(&:to_i)
        @total_frames = @frames.size
        if wait.is_a?(Array)
          @weights = wait.map { |w| [w.to_i, 1].max }
          while @weights.size < @total_frames
            @weights << (@weights.last || 10)
          end
        else
          w = [wait.to_i, 1].max
          @weights = Array.new(@total_frames, w)
        end
        @current_frame = 0
        @timer = 0
        @changed = false
      end

      # 現在表示すべきタイルID
      def current_tile_id
        @frames[@current_frame] || @id
      end

      # 1フレーム進める (コマが切り替わったら true を返す)
      def step!
        return false if @total_frames <= 1
        @changed = false
        @timer += 1
        cur_wait = @weights[@current_frame] || 10
        if @timer >= cur_wait
          @timer = 0
          @current_frame = (@current_frame + 1) % @total_frames
          @changed = true
        end
        @changed
      end

      def reset!
        @current_frame = 0
        @timer = 0
        @changed = false
      end
    end

    # ==========================================================================
    # Layer: 行単位 Mesh を管理する単一タイルレイヤー
    # ==========================================================================
    # 1つのタイル層 (床、壁、装飾、屋根など) を保持・描画するクラスです。
    # 通常は Tilemap#add_layer または Tilemap.from_array 経由で生成されます。
    class Layer
      attr_reader   :name, :tilemap, :rows, :cols
      attr_accessor :z, :y_sort, :z_offset, :solid, :height, :visible, :alpha, :color, :blend

      # @param tilemap [Tilemap] 親の Tilemap インスタンス
      # @param name [Symbol] レイヤー名 (:ground, :walls など)
      # @param data [Array<Array<Integer, nil>>] 2次元マップ配列 (data[row][col])
      # @param z [Float] 基準深度 Z
      # @param y_sort [Boolean] true の場合、各行の足元Y座標を自動的に Z値として描画
      # @param z_offset [Float] Yソート時の微調整オフセット (キャラより少し手前/奥にする場合など)
      # @param solid [Boolean] true の場合、このレイヤーの全タイルを通行不可 (壁) として扱う
      # @param height [Float, nil] このレイヤーの基準高さ
      # @param visible [Boolean] 表示 / 非表示
      # @param alpha [Integer] 不透明度 (0..255)
      # @param color [Symbol, Array] 乗算カラー
      # @param blend [Symbol] ブレンドモード (:alpha, :add 等)
      def initialize(tilemap, name, data,
                     z: 0.0,
                     y_sort: false,
                     z_offset: 0.0,
                     solid: false,
                     height: nil,
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
        @height = height ? height.to_f : nil
        @visible = visible.nil? ? true : !!visible
        @alpha = alpha
        @color = color
        @blend = blend || :alpha

        @rows = 0
        @cols = 0
        @row_meshes = []      # 各行の Zenoo::Mesh (代表テクスチャの頂点バッファ)
        @row_indices = []     # 各行の IBO インデックス配列キャッシュ
        @row_anim_entries = []# 各行のアニメーション配置情報 [ [tid, ibo_idx, base_v], ... ]
        @row_extras = []      # 代表テクスチャ以外の別画像タイル群 [col, rel_row, raw, ...]
        @row_dirty = []       # 行ごとの再構築フラグ (true の行のみ rebuild_row! を実行)
        @all_dirty = true     # 全行再構築フラグ
        @max_cell_offset = 0  # マップ配列内で使われている最大の root_offset (カリング余白計算用)
        @max_tall_rows = 0    # 大判タイルで上方向に突き出る最大行数 (カリング余白計算用)
        @temp_verts = []      # 行Mesh構築用の一時頂点配列 (GC削減のため再利用)
        @temp_indices = []    # 行Mesh構築用の一時インデックス配列 (GC削減のため再利用)

        refresh_size!
      end

      # 2次元マップ配列を取得
      def data
        @data
      end

      # 2次元マップ配列を差し替え
      def data=(new_data)
        @data = new_data || []
        refresh_size!
      end

      # 行列サイズの更新と、行管理バッファのリサイズ
      def refresh_size!
        @rows = @data.is_a?(Array) ? @data.size : 0
        @cols = (@rows > 0 && @data[0].is_a?(Array)) ? @data[0].size : 0
        while @row_dirty.size < @rows
          @row_dirty << true
          @row_meshes << nil
          @row_indices << nil
          @row_anim_entries << nil
          @row_extras << nil
        end
        @all_dirty = true
        scan_cell_offsets!
      end

      # レイヤー全体の Mesh を再構築対象としてマーク
      def invalidate!
        @all_dirty = true
      end

      # 指定したマス (col, row) の生のセル整数値 (ビットフラグ込み) を取得
      def raw_at(col, row)
        return nil if row < 0 || row >= @rows || col < 0 || col >= @cols
        row_data = @data[row]
        row_data ? row_data[col] : nil
      end

      # 指定したマス (col, row) の純粋なタイルID (0..65535) を取得
      def [](col, row)
        raw = raw_at(col, row)
        (raw && raw >= 0) ? (raw & ID_MASK) : nil
      end

      # 指定したマス (col, row) にタイルID (または Tilemap.tile で作成したセル値) を設定
      # タイルが変更された行と、オフセット先 (帰属する行) の Mesh のみが Dirty 化されます。
      def []=(col, row, val)
        return if row < 0 || row >= @rows || col < 0 || col >= @cols
        row_data = @data[row]
        return unless row_data

        old_raw = row_data[col]
        return if old_raw == val
        row_data[col] = val

        # 変更前のタイルが帰属していた行と、変更後のタイルが帰属する行をピンポイントで Dirty 化
        mark_dirty_row_for_raw(row, old_raw)
        mark_dirty_row_for_raw(row, val)
      end

      # レイヤーの描画処理
      # 画面内に映っている行 (min_row..max_row) の Mesh のみを描画します (視錐台カリング)。
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

        # ----------------------------------------------------------------------
        # 画面可視範囲 (Frustum Culling) の算出
        # オフスクリーン (Image.render_to) 描画時もその解像度を正しく取得して判定
        # ----------------------------------------------------------------------
        cur_target = Backend.current_target
        win_w = cur_target ? cur_target.width.to_f : Window.width.to_f
        win_h = cur_target ? cur_target.height.to_f : Window.height.to_f
        if draw_camera && Window.camera_enabled?
          _left, top, _right, bottom = Window.camera.visible_rect(win_w, win_h)
        else
          top = 0.0
          bottom = win_h
        end

        # 背の高い柱や大判タイルの先端が画面下端から上に伸びるため、
        # 画面外下端のマージンを「最大の root_offset / 大判高さ」分だけ広げてカリング
        max_off = @tilemap.max_root_offset
        max_off = @max_cell_offset if @max_cell_offset > max_off
        tall_margin = [max_off, @max_tall_rows].max + 1

        min_row = [((top - draw_y) / th).floor - 1, 0].max
        max_row = [((bottom - draw_y) / th).floor + tall_margin, @rows - 1].min
        return if min_row > max_row

        rebuild_all_dirty! if @all_dirty

        # ----------------------------------------------------------------------
        # 可視行の描画ループ
        # ----------------------------------------------------------------------
        r = min_row
        while r <= max_row
          rebuild_row!(r) if @row_dirty[r]

          # Yソートが有効な場合、その行の下端 Y 座標を Z値として渡す
          # (これによりキャラの sprite.z = sprite.y と完全に連動して前後関係が成立)
          row_z = if @y_sort
                    base_z + draw_y + ((r + 1) * th) + (@z_offset * sy)
                  else
                    base_z
                  end

          # メインの行 Mesh の描画 (同一テクスチャの全タイルを 1 回のドローコールで描画)
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

          # 別テクスチャ画像が混ざっていた場合のフォールバック個別描画
          extras = @row_extras[r]
          if extras
            draw_row_extras(extras, draw_x, draw_y, sx, sy, tw, th, eff_color, eff_alpha, draw_camera, row_z)
          end

          r += 1
        end
      end

      # アニメーションコマが変化した行の IBO (インデックスバッファ) のみを高速更新
      def update_animations
        return if @row_anim_entries.empty?

        r = 0
        while r < @rows
          # 再構築予定の行は次の描画で最新コマが反映されるためスキップ
          if !@row_dirty[r]
            entries = @row_anim_entries[r]
            if entries && !entries.empty?
              row_idxs = @row_indices[r]
              mesh = @row_meshes[r]
              if row_idxs && mesh && mesh.count > 0
                row_dirty_ibo = false
                i = 0
                num_entries = entries.size
                while i < num_entries
                  entry = entries[i]
                  anim_id = entry[0]
                  anim = @tilemap.tile_animation(anim_id)
                  if anim && anim.changed
                    ibo_idx = entry[1]
                    base_v = entry[2]
                    v = base_v + anim.current_frame * 4
                    row_idxs[ibo_idx]     = v
                    row_idxs[ibo_idx + 1] = v + 1
                    row_idxs[ibo_idx + 2] = v + 2
                    row_idxs[ibo_idx + 3] = v + 2
                    row_idxs[ibo_idx + 4] = v + 1
                    row_idxs[ibo_idx + 5] = v + 3
                    row_dirty_ibo = true
                  end
                  i += 1
                end

                if row_dirty_ibo
                  mesh.update_indices(row_idxs.pack("I*"), count: row_idxs.size)
                end
              end
            end
          end
          r += 1
        end
      end

      private

      # 指定したマスのセル値 (raw) が帰属する行 (row + root_offset) を Dirty にする
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

      # マップ配列内の全セルから、個別に指定されている最大の root_offset を走査
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

      # ------------------------------------------------------------------------
      # 指定した行 (target_row) の Mesh を再構築
      # ------------------------------------------------------------------------
      # 【重要: root_offset の集約】
      # 柱のように何マスか下の行に根元があるパーツは、配置されている行 (例: row 3)
      # ではなく、根元の行 (target_row = row 5) の Mesh に頂点を追加します。
      # そのため、走査範囲は target_row だけでなく、上方の行 (target_row - max_off)
      # から target_row までを対象とし、「この行に帰属するタイル」を漏れなく集めます。
      def rebuild_row!(target_row)
        @row_dirty[target_row] = false
        tiles = @tilemap.tiles
        full_img = @tilemap.base_texture_image
        base_tex_id = full_img ? full_img.texture_id : 0
        tw = @tilemap.tile_width.to_f
        th = @tilemap.tile_height.to_f

        verts = @temp_verts
        verts.clear
        indices = @temp_indices
        indices.clear
        extras = nil
        anim_entries = []

        max_off = @tilemap.max_root_offset
        max_off = @max_cell_offset if @max_cell_offset > max_off
        min_r = target_row - max_off
        min_r = 0 if min_r < 0

        # 上方の行から target_row までを走査し、target_row に帰属するタイルを抽出
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
                anim = @tilemap.tile_animation(tid)
                eff_tid = anim ? anim.current_tile_id : tid
                img = tiles[eff_tid]
                if img
                  # マスごとの個別オフセット または タイル定義のオフセットを取得
                  cell_off = (raw >> OFFSET_SHIFT) & OFFSET_MASK
                  off = cell_off > 0 ? (cell_off - 1) : @tilemap.tile_root_offset(tid)
                  eff_row = r + off
                  eff_row = @rows - 1 if eff_row >= @rows

                  # このタイルの帰属先が現在構築中の target_row と一致する場合のみ追加
                  if eff_row == target_row
                    iw = img.width.to_f
                    ih = img.height.to_f
                    if ih > th
                      tall_rows = ((ih - th) / th).ceil + off
                      @max_tall_rows = tall_rows if tall_rows > @max_tall_rows
                    end

                    rel_r = r - target_row

                    # ----------------------------------------------------------
                    # テクスチャ一致判定:
                    # 代表テクスチャと同じ画像なら行Mesh頂点バッファへ格納。
                    # 別ファイル等から読み込んだ異なるテクスチャの場合は、
                    # 1つのMeshに混在できないため extras へ退避して個別描画に回す。
                    # ----------------------------------------------------------
                    if anim && anim.total_frames > 1
                      all_same_tex = anim.frames.all? do |f_id|
                        f_img = tiles[f_id]
                        f_img && f_img.texture_id == base_tex_id
                      end
                      if all_same_tex
                        append_animated_tile_vertices(verts, indices, anim_entries, anim, tiles, c, rel_r, tw, th, iw, ih, raw)
                      else
                        extras ||= []
                        extras.push(c, rel_r, raw)
                      end
                    elsif img.texture_id == base_tex_id
                      append_tile_vertices(verts, indices, img, c, rel_r, tw, th, iw, ih, raw)
                    else
                      extras ||= []
                      extras.push(c, rel_r, raw)
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
        @row_anim_entries[target_row] = anim_entries.empty? ? nil : anim_entries
        @row_indices[target_row] = indices.empty? ? nil : indices.dup

        v_count = verts.size / 8
        i_count = indices.size
        existing = @row_meshes[target_row]

        # 頂点バッファおよびインデックスバッファを GPU (VRAM) へ転送・更新
        if v_count > 0 && full_img
          bin = verts.pack("f*")
          idx_bin = indices.pack("I*")
          if existing
            # 既存の Mesh があれば VBO/IBO を破棄せずバッファ上書き (メモリ再割り当て回避)
            existing.image = full_img
            existing.update(bin, count: v_count)
            existing.update_indices(idx_bin, count: i_count)
          else
            # 初回生成時は新しい Mesh を作成 (IBO 付き)
            @row_meshes[target_row] = Mesh.new(
              data: bin,
              count: v_count,
              indices: idx_bin,
              pipeline: :sprite,
              image: full_img,
              width: @cols * tw,
              height: th
            )
          end
        elsif existing
          existing.count = 0
          existing.update_indices("", count: 0)
        end
      end

      # タイルの画面配置矩形 (x0, y0, x1, y1) を計算
      def calc_tile_bounds(col, rel_row, tw, th, iw, ih)
        if iw == tw && ih == th
          x0 = col * tw
          y0 = rel_row * th
          x1 = x0 + tw
          y1 = y0 + th
        else
          x0 = col * tw + (tw - iw) * 0.5
          y1 = (rel_row + 1) * th
          y0 = y1 - ih
          x1 = x0 + iw
        end
        [x0, y0, x1, y1]
      end

      # タイル画像とビットフラグ (FLIP_H / FLIP_V / ROT) から 4隅の UV を計算
      # (32bit float 化やスクロール時の端数補間で隣接タイルのピクセルを拾うのを防ぐため微小量内側へオフセット)
      def calc_tile_uvs(img, raw)
        tex_w = img.texture_width.to_f
        tex_h = img.texture_height.to_f
        u0 = tex_w > 0.0 ? ((img.x.to_f + 0.01) / tex_w) : 0.0
        v0 = tex_h > 0.0 ? ((img.y.to_f + 0.01) / tex_h) : 0.0
        u1 = tex_w > 0.0 ? (((img.x + img.width).to_f - 0.01) / tex_w) : 1.0
        v1 = tex_h > 0.0 ? (((img.y + img.height).to_f - 0.01) / tex_h) : 1.0

        # 水平反転 (U 座標を左右逆転)
        if (raw & FLIP_H) != 0
          tmp = u0; u0 = u1; u1 = tmp
        end
        # 垂直反転 (V 座標を上下逆転)
        if (raw & FLIP_V) != 0
          tmp = v0; v0 = v1; v1 = tmp
        end

        # 90度単位の時計回り回転 (4隅の UV をサイクリックに巡回)
        rot = (raw >> ROT_SHIFT) & ROT_MASK
        if rot == 0
          ua = u0; va = v0 # 左上
          ub = u1; vb = v0 # 右上
          uc = u1; vc = v1 # 右下
          ud = u0; vd = v1 # 左下
        elsif rot == 1     # 90度時計回り
          ua = u0; va = v1
          ub = u0; vb = v0
          uc = u1; vc = v0
          ud = u1; vd = v1
        elsif rot == 2     # 180度
          ua = u1; va = v1
          ub = u0; vb = v1
          uc = u0; vc = v0
          ud = u1; vd = v0
        else               # 270度時計回り
          ua = u1; va = v0
          ub = u1; vb = v1
          uc = u0; vc = v1
          ud = u0; vd = v0
        end

        [ua, va, ub, vb, uc, vc, ud, vd]
      end

      # ------------------------------------------------------------------------
      # 静的タイルの 4頂点 (VBO) と 6インデックス (IBO) をバッファに追加
      # ------------------------------------------------------------------------
      def append_tile_vertices(verts, indices, img, col, rel_row, tw, th, iw, ih, raw)
        x0, y0, x1, y1 = calc_tile_bounds(col, rel_row, tw, th, iw, ih)
        ua, va, ub, vb, uc, vc, ud, vd = calc_tile_uvs(img, raw)

        base_v = verts.size / 8
        verts.push(
          x0, y0, ua, va, 1.0, 1.0, 1.0, 1.0,
          x0, y1, ud, vd, 1.0, 1.0, 1.0, 1.0,
          x1, y0, ub, vb, 1.0, 1.0, 1.0, 1.0,
          x1, y1, uc, vc, 1.0, 1.0, 1.0, 1.0
        )
        indices.push(
          base_v,     base_v + 1, base_v + 2,
          base_v + 2, base_v + 1, base_v + 3
        )
      end

      # ------------------------------------------------------------------------
      # アニメーションタイルの全コマ頂点 (VBO) と初期インデックス (IBO) を追加
      # ------------------------------------------------------------------------
      # VBO には全コマ分の頂点 (Nコマ x 4頂点) をあらかじめ配置し、
      # IBO には現在の再生コマを指す 6インデックスのみを追加します。
      # コマ更新時は IBO のインデックス値のみを更新することで GPU 転送量を極小化します。
      def append_animated_tile_vertices(verts, indices, anim_entries, anim, tiles, col, rel_row, tw, th, iw, ih, raw)
        x0, y0, x1, y1 = calc_tile_bounds(col, rel_row, tw, th, iw, ih)
        base_v = verts.size / 8
        tid = anim.id

        k = 0
        n = anim.total_frames
        while k < n
          f_img = tiles[anim.frames[k]]
          ua, va, ub, vb, uc, vc, ud, vd = calc_tile_uvs(f_img, raw)
          verts.push(
            x0, y0, ua, va, 1.0, 1.0, 1.0, 1.0,
            x0, y1, ud, vd, 1.0, 1.0, 1.0, 1.0,
            x1, y0, ub, vb, 1.0, 1.0, 1.0, 1.0,
            x1, y1, uc, vc, 1.0, 1.0, 1.0, 1.0
          )
          k += 1
        end

        cur_v = base_v + anim.current_frame * 4
        ibo_offset = indices.size
        indices.push(
          cur_v,     cur_v + 1, cur_v + 2,
          cur_v + 2, cur_v + 1, cur_v + 3
        )

        anim_entries << [tid, ibo_offset, base_v]
      end

      # ------------------------------------------------------------------------
      # 別テクスチャタイルの個別描画 (フォールバック)
      # ------------------------------------------------------------------------
      # 代表テクスチャと異なる Image が配置された場合のみ、
      # その行と同じ Z値 (row_z) を指定して個別に Window.draw で描画します。
      def draw_row_extras(extras, draw_x, draw_y, sx, sy, tw, th, eff_color, eff_alpha, draw_camera, row_z)
        tiles = @tilemap.tiles
        i = 0
        len = extras.size
        while i < len
          c = extras[i]
          rel_r = extras[i + 1]
          raw = extras[i + 2]
          tid = raw & ID_MASK
          anim = @tilemap.tile_animation(tid)
          eff_tid = anim ? anim.current_tile_id : tid
          img = tiles[eff_tid]
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

    # 単一レイヤーのタイルマップを 2次元配列から即座に生成するファクトリメソッド
    # @param data [Array<Array<Integer, nil>>] 2次元マップ配列
    # @param tiles [Array<Image>] タイル画像の配列
    def self.from_array(data, tiles,
                        tile_width: nil,
                        tile_height: nil,
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
      map = new(
        tiles,
        tile_width: tile_width,
        tile_height: tile_height,
        x: x,
        y: y,
        z: z,
        scale_x: scale_x,
        scale_y: scale_y,
        camera: camera,
        alpha: alpha,
        color: color
      )
      map.add_layer(:default, data, z: 0.0, y_sort: y_sort, solid: solid)
      map
    end

    attr_accessor :x, :y, :z, :scale_x, :scale_y, :camera, :alpha, :color
    attr_reader   :tiles, :tile_width, :tile_height, :cols, :rows, :layers, :max_root_offset, :base_texture_image

    # @param tiles [Array<Image>] タイル画像の配列 (Image.load_tiles または slice_tiles で生成)
    # @param tile_width [Integer, nil] タイルの標準幅 (省略時は最初のタイル画像の幅を採用)
    # @param tile_height [Integer, nil] タイルの標準高さ (省略時は最初のタイル画像の高さを採用)
    # @param cols [Integer] マップ列数
    # @param rows [Integer] マップ行数
    # @param x [Float] マップ基準ワールドX座標
    # @param y [Float] マップ基準ワールドY座標
    # @param z [Float] マップ基準深度Z
    # @param scale_x [Float] 水平拡大率
    # @param scale_y [Float] 垂直拡大率
    # @param camera [Boolean] カメラ変換の追従有無
    # @param alpha [Integer] 不透明度 (0..255)
    # @param color [Symbol, Array] 乗算カラー
    def initialize(tiles,
                   tile_width: nil,
                   tile_height: nil,
                   cols: 0,
                   rows: 0,
                   x: 0.0,
                   y: 0.0,
                   z: 0.0,
                   scale_x: 1.0,
                   scale_y: 1.0,
                   camera: true,
                   alpha: 255,
                   color: :white)
      @tiles = tiles || []
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
      @scale_x = scale_x.to_f
      @scale_y = scale_y.to_f
      @camera = camera
      @alpha = alpha
      @color = color

      # 最初の有効なタイル画像から標準サイズと代表テクスチャを取得
      first_tile = @tiles.is_a?(Array) ? @tiles.compact.first : nil
      @tile_width = (tile_width || (first_tile ? first_tile.width : 0)).to_i
      @tile_height = (tile_height || (first_tile ? first_tile.height : 0)).to_i
      @base_texture_image = build_base_texture_image(first_tile)

      @cols = cols.to_i
      @rows = rows.to_i

      @tile_root_offsets = [] # タイルIDごとの根元オフセットテーブル (@tile_root_offsets[tile_id] = 行数)
      @tile_solids = []       # タイルIDごとの通行不可フラグテーブル (@tile_solids[tile_id] = true/false)
      @tile_heights = []      # タイルIDごとの高さ(標高)テーブル (@tile_heights[tile_id] = Float)
      @max_root_offset = 0    # マップ全体で最大の根元オフセット

      @layers = []
      @layer_names = []
      @animations = {}        # アニメーション定義 (@animations[tile_id] = Animation)
      @temp_wall_rect = nil   # 衝突判定用の一時 Rect (GC削減のため再利用)
      @candidate_buffer = []  # 最寄り優先ソート用のフラットバッファ [c, r, d2, ...]
    end

    # タイル画像配列の差し替え
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

    # タイル番号に対する属性 (根元オフセット・通行不可フラグ・高さ) を設定
    # @param tile_id [Integer] タイルID
    # @param root_offset [Integer, nil] このタイルが何行下のマスに帰属するか (根元までの行数)
    # @param solid [Boolean, nil] 通行不可 (壁) かどうか
    # @param height [Float, nil] このタイルの高さ
    def set_tile(tile_id, root_offset: nil, solid: nil, height: nil)
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
      unless height.nil?
        @tile_heights[tid] = height.to_f
      end
      self
    end

    # 縦に並ぶ柱や木などの立体物タイル番号配列 (上から下へ) を一括定義
    # - 1次元配列 [top_id, mid_id, bottom_id] または 2次元配列 [[top_l, top_r], [bot_l, bot_r]] に対応
    # - 最下段 (根元) に solid: true を設定し、上段には根元までの行数オフセットを自動計算して設定します
    # 例:
    #   map.define_column([T_PILLAR_TOP, T_PILLAR_MID, T_PILLAR_BOT], solid: true)
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

    # 指定したタイルIDの根元オフセットを取得
    def tile_root_offset(tile_id)
      return 0 if tile_id.nil? || tile_id < 0
      @tile_root_offsets[tile_id] || 0
    end

    # 指定したタイルIDが通行不可 (solid) かどうか判定
    def tile_solid?(tile_id)
      return false if tile_id.nil? || tile_id < 0
      !!@tile_solids[tile_id]
    end

    # 新しいレイヤーを追加して返す
    # @param name [Symbol, String] レイヤー名 (:ground, :walls, :roof など)
    # @param data [Array<Array<Integer, nil>>, nil] 2次元マップ配列 (省略時は空レイヤー)
    # @param z [Float] 基準深度 Z
    # @param y_sort [Boolean] true の場合、各行の足元Y座標で自動 Yソート描画
    # @param solid [Boolean] true の場合、このレイヤー全体を通行不可として扱う
    # @param height [Float, nil] このレイヤーの基準高さ
    def add_layer(name, data = nil,
                  z: 0.0,
                  y_sort: false,
                  z_offset: 0.0,
                  solid: false,
                  height: nil,
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
        solid: solid, height: height,
        visible: visible,
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

    # レイヤー名 (Symbol/String) またはインデックス番号で Layer を取得
    def layer(name_or_index)
      if name_or_index.is_a?(Integer)
        @layers[name_or_index]
      else
        idx = @layer_names.index(name_or_index.to_sym)
        idx ? @layers[idx] : nil
      end
    end

    # 単一レイヤー互換: 先頭レイヤーの 2次元マップ配列を取得
    def data
      first = @layers[0]
      first ? first.data : nil
    end

    # 単一レイヤー互換: 先頭レイヤーの 2次元マップ配列を設定
    def data=(new_data)
      if @layers.empty?
        add_layer(:default, new_data)
      else
        @layers[0].data = new_data
        refresh_size!
      end
    end

    # 全レイヤーの最大行列サイズを再集計
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

    # [layer_name] で Layer を取得、または [col, row] で先頭レイヤーのタイルIDを取得
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

    # ピクセル座標 (px, py) からマスの列・行 [col, row] を算出
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

    # 指定したマス (col, row) が通行不可 (壁) かどうか判定
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

    # ワールドピクセル座標 (px, py) が通行不可 (壁) かどうか判定
    def solid_at?(px, py)
      coords = tile_coords(px, py)
      coords ? solid_cell?(coords[0], coords[1]) : false
    end

    # 指定したマス (col, row) の高さを取得 (複数レイヤーにある場合は最大値)
    def height_cell(col, row)
      return 0.0 if col < 0 || col >= @cols || row < 0 || row >= @rows
      max_h = 0.0
      i = 0
      len = @layers.size
      while i < len
        ly = @layers[i]
        raw = ly.raw_at(col, row)
        if raw && raw >= 0
          lh = ly.height
          max_h = lh if lh && lh > max_h
          tid = raw & ID_MASK
          th = @tile_heights[tid]
          max_h = th if th && th > max_h
        end
        i += 1
      end
      max_h
    end

    # ワールドピクセル座標 (px, py) の高さを取得
    def height_at(px, py)
      coords = tile_coords(px, py)
      coords ? height_cell(coords[0], coords[1]) : 0.0
    end

    # スプライトの足元が乗っている床面の最高標高を取得
    # スプライトの現在高度以下の床面の中で最大の標高を返します (浮遊中・段差から外れた瞬間の落下開始判定)
    #
    # @param sprite [Sprite] 判定対象のスプライト
    # @param altitude [Float] スプライトの現在の絶対高度 (デフォルト 0.0)
    # @param offset_y [Float] 見た目の描画段差オフセット (例: -PLATEAU_HEIGHT で足元と床描画範囲を一致させる)
    # @param probe_rx [Float] 左右の接地判定半径 (px)
    # @param probe_ry [Float] 上下の接地判定半径 (px)
    # @param step_tolerance [Float] 乗り越え許容高度差 (デフォルト 2.0px)
    # @return [Float] 支持されている床面の標高
    def support_height(sprite, altitude: 0.0, offset_y: 0.0, probe_rx: 6.0, probe_ry: 4.0, step_tolerance: 2.0)
      return 0.0 if sprite.nil?
      col = sprite.respond_to?(:collider) ? sprite.collider : sprite
      return height_at(sprite.x, sprite.y + offset_y) unless col && col.respond_to?(:center_x)

      cx = col.center_x
      cy = col.center_y + offset_y
      max_limit = altitude.to_f + step_tolerance.to_f
      max_h = 0.0

      # 中心と四方の 5 点接地判定
      points = [
        [cx, cy],
        [cx - probe_rx, cy],
        [cx + probe_rx, cy],
        [cx, cy - probe_ry],
        [cx, cy + probe_ry]
      ]
      i = 0
      while i < 5
        pt = points[i]
        h = height_at(pt[0], pt[1])
        max_h = h if h <= max_limit && h > max_h
        i += 1
      end
      max_h
    end

    # Sprite または Collision::Shape がマップの障害物タイルと接触しているか判定
    def collide?(target)
      return false unless target
      col_shape = target.respond_to?(:collider) ? target.collider : target
      return false unless col_shape && col_shape.respond_to?(:center_x)

      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return false if tw <= 0.0 || th <= 0.0

      cx = col_shape.center_x
      cy = col_shape.center_y
      br = col_shape.bounding_radius

      # コライダーの周囲のタイルインデックス範囲のみを抽出 (ブロードフェーズ)
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

    # --------------------------------------------------------------------------
    # スプライトを障害物タイルから滑らかに壁ずり押し出し (最寄りタイル優先 MTV)
    # --------------------------------------------------------------------------
    # 【なぜ最寄り優先でソートするのか？】
    # グリッド順 (左から右、上から下) のままタイルごとに順次押し出すと、
    # 走査順のバイアスによりブロックの角やタイルの継ぎ目にキャラが引っかかります。
    # コライダー中心から最も近い壁タイルから順に MTV (最小移動ベクトル) を適用することで、
    # 斜め移動時でも壁面に沿ってスムーズに滑る挙動になります。
    #
    # @param sprite [Sprite] 押し出し対象のスプライト
    # @param target_root [Boolean] true の場合、ルートスプライトの位置を補正
    # @param altitude [Float, nil] スプライトの絶対高度。指定時、自分の高度より高い段差タイルも壁として衝突
    # @param step_tolerance [Float] 乗り越え許容高度差 (デフォルト 2.0px)
    def resolve_collision(sprite, target_root: true, altitude: nil, step_tolerance: 2.0)
      return false if sprite.nil? || (sprite.respond_to?(:vanished?) && sprite.vanished?)
      col_shape = sprite.respond_to?(:collider) ? sprite.collider : sprite
      return false unless col_shape && col_shape.respond_to?(:center_x)

      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return false if tw <= 0.0 || th <= 0.0

      cx = col_shape.center_x
      cy = col_shape.center_y
      br = col_shape.bounding_radius

      # 高度判定有効時は、段差タイルが描画上 -Y に持ち上がっている分 (+max_h) だけ探索範囲を広げる
      check_elevation = !altitude.nil?
      cur_alt = altitude.to_f
      step_tol = step_tolerance.to_f
      elev_expand = check_elevation ? 32.0 : 0.0

      min_c = [((cx - br - @x) / tw).floor, 0].max
      max_c = [((cx + br - @x) / tw).floor, @cols - 1].min
      min_r = [((cy - elev_expand - br - @y) / th).floor, 0].max
      max_r = [((cy + br - @y) / th).floor, @rows - 1].min
      return false if min_c > max_c || min_r > max_r

      # 周囲の接触可能タイルをフラット配列 [wx, wy, dist_sq, ...] に収集し、
      # 距離の昇順 (近い順) で挿入ソート
      buf = @candidate_buffer
      buf.clear
      r = min_r
      while r <= max_r
        c = min_c
        while c <= max_c
          is_solid = solid_cell?(c, r)
          th_elev  = check_elevation ? height_cell(c, r) : 0.0
          is_elev_wall = check_elevation && th_elev > (cur_alt + step_tol)

          if is_solid || is_elev_wall
            # 段差タイルの接地当たり判定は、見た目の上面描画位置から +th_elev (下) にずらす
            wx = @x + c * tw
            wy = @y + r * th + (is_solid ? 0.0 : th_elev)
            dx = (wx + 0.5 * tw) - cx
            dy = (wy + 0.5 * th) - cy
            d2 = dx * dx + dy * dy

            # 3要素単位で距離の昇順に挿入
            pos = buf.size
            while pos >= 3 && buf[pos - 1] > d2
              pos -= 3
            end
            buf.insert(pos, wx, wy, d2)
          end
          c += 1
        end
        r += 1
      end

      return false if buf.empty?

      # 近いタイルから順に 2 パス押し出し (角へのめり込みも完全解消)
      wall = prepare_wall_rect(tw, th)
      resolved_any = false
      pass = 0
      while pass < 2
        hit_in_pass = false
        i = 0
        len = buf.size
        while i < len
          wall.x = buf[i]
          wall.y = buf[i + 1]
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

    # アニメーションタイルの定義
    # @param tile_id [Integer] マップ上で配置する代表タイルID
    # @param frames [Array<Integer>] コマとなるタイルIDの配列
    # @param wait [Integer, Array<Integer>] コマごとの待機フレーム数 (単一数値または配列)
    def define_animation(tile_id, frames:, wait: 10)
      @animations[tile_id.to_i] = Animation.new(tile_id, frames: frames, wait: wait)
      invalidate_all_layers!
      self
    end

    # アニメーション定義を取得
    def tile_animation(tile_id)
      @animations[tile_id]
    end

    # 登録されている全アニメーション定義のハッシュ
    def animations
      @animations
    end

    # アニメーションタイルの更新 (毎フレームのゲームループ内で呼び出し)
    def update
      return self if @animations.empty?

      any_changed = false
      @animations.each_value do |anim|
        any_changed = true if anim.step!
      end

      return self unless any_changed

      i = 0
      len = @layers.size
      while i < len
        @layers[i].update_animations
        i += 1
      end
      self
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

    # 最初のタイルからテクスチャ全体領域を指す Image を構築
    # (slice_tiles 等で切り分けられた sub_image の親テクスチャ全体を代表画像として取得)
    def build_base_texture_image(first_tile)
      return nil unless first_tile
      if first_tile.sub_image?
        first_tile.sub_image(-first_tile.x, -first_tile.y, first_tile.texture_width, first_tile.texture_height)
      else
        first_tile
      end
    end

    # 全レイヤーの Mesh を Dirty にする
    def invalidate_all_layers!
      i = 0
      while i < @layers.size
        @layers[i].invalidate!
        i += 1
      end
    end

    # 衝突判定用の Rect を準備 (サイズ変更時のみ更新し、再アロケーションを防止)
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

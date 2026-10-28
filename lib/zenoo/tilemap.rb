# frozen_string_literal: true

module Zenoo
  # 2D タイルマップ描画・管理クラス
  # 2次元マップ配列と Image タイル配列を受け取り、
  # カメラ可視範囲を高速カリング（Frustum Culling）しながら一括描画します。
  class Tilemap
    attr_accessor :data, :tiles, :x, :y, :z, :scale_x, :scale_y, :camera, :alpha, :color
    attr_reader :tile_width, :tile_height, :cols, :rows

    # @param data [Array<Array<Integer, nil>>] 2次元マップ配列 (data[row][col])
    # @param tiles [Array<Zenoo::Image>] 各タイルIDに対応する Image の配列
    # @param x [Float] マップ基準 X 座標
    # @param y [Float] マップ基準 Y 座標
    # @param z [Float] 描画深度 Z
    # @param scale_x [Float] 水平スケール
    # @param scale_y [Float] 垂直スケール
    # @param camera [Boolean] カメラ変換の追従有無
    # @param alpha [Integer, Float] 不透明度 (0..255)
    # @param color [Symbol, Zenoo::Color] 乗算カラー
    def initialize(data, tiles,
                   x: 0.0,
                   y: 0.0,
                   z: 0.0,
                   scale_x: 1.0,
                   scale_y: 1.0,
                   camera: true,
                   alpha: 255,
                   color: :white)
      @data = data
      @tiles = tiles
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
      @scale_x = scale_x.to_f
      @scale_y = scale_y.to_f
      @camera = camera
      @alpha = alpha
      @color = color

      # 最初のタイル画像から標準サイズを自動取得
      first_tile = @tiles.is_a?(Array) ? @tiles.compact.first : nil
      @tile_width = first_tile ? first_tile.width : 0
      @tile_height = first_tile ? first_tile.height : 0

      refresh_size!
    end

    # マップの行列サイズを更新
    def refresh_size!
      @rows = @data.is_a?(Array) ? @data.size : 0
      @cols = (@rows > 0 && @data[0].is_a?(Array)) ? @data[0].size : 0
    end

    # マップ全体のピクセル幅
    def width
      @cols * @tile_width * @scale_x
    end

    # マップ全体のピクセル高さ
    def height
      @rows * @tile_height * @scale_y
    end

    # 指定した列・行のタイルIDを取得
    def [](col, row)
      return nil if row < 0 || row >= @rows || col < 0 || col >= @cols
      row_data = @data[row]
      row_data ? row_data[col] : nil
    end

    # 指定した列・行のタイルIDを設定
    def []=(col, row, tile_id)
      return if row < 0 || row >= @rows || col < 0 || col >= @cols
      row_data = @data[row]
      row_data[col] = tile_id if row_data
    end

    # ピクセル座標 (px, py) から [col, row] を算出
    def tile_coords(px, py)
      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return nil if tw <= 0 || th <= 0

      col = ((px.to_f - @x) / tw).floor
      row = ((py.to_f - @y) / th).floor
      (col >= 0 && col < @cols && row >= 0 && row < @rows) ? [col, row] : nil
    end

    # ピクセル座標 (px, py) のタイルIDを取得
    def tile_at(px, py)
      coords = tile_coords(px, py)
      coords ? self[*coords] : nil
    end

    # タイルマップの描画
    def draw(x: nil, y: nil, z: nil, camera: nil)
      return if @rows == 0 || @cols == 0 || @tile_width <= 0 || @tile_height <= 0

      draw_x = (x || @x).to_f
      draw_y = (y || @y).to_f
      draw_z = (z || @z).to_f
      draw_camera = camera.nil? ? @camera : camera

      tw = @tile_width * @scale_x
      th = @tile_height * @scale_y
      return if tw <= 0 || th <= 0

      # 可視ワールド座標範囲の算出 (Frustum Culling)
      win_w = Window.width.to_f
      win_h = Window.height.to_f

      if draw_camera && Window.camera_enabled?
        left, top, right, bottom = Window.camera.visible_rect(win_w, win_h)
      else
        left = 0.0
        right = win_w
        top = 0.0
        bottom = win_h
      end

      # 可視タイルインデックス範囲 (余白1タイル分マージンを追加)
      min_col = [((left - draw_x) / tw).floor - 1, 0].max
      max_col = [((right - draw_x) / tw).floor + 1, @cols - 1].min
      min_row = [((top - draw_y) / th).floor - 1, 0].max
      max_row = [((bottom - draw_y) / th).floor + 1, @rows - 1].min

      return if min_col > max_col || min_row > max_row

      # 可視範囲のタイルのみ描画
      r = min_row
      while r <= max_row
        row_data = @data[r]
        if row_data
          c = min_col
          while c <= max_col
            tile_id = row_data[c]
            if tile_id && tile_id >= 0 && tile_id < @tiles.size
              img = @tiles[tile_id]
              if img
                tx = draw_x + c * tw
                ty = draw_y + r * th
                Window.draw(tx, ty, img,
                            scale_x: @scale_x,
                            scale_y: @scale_y,
                            color: @color,
                            alpha: @alpha,
                            camera: draw_camera,
                            z: draw_z)
              end
            end
            c += 1
          end
        end
        r += 1
      end
    end
  end
end

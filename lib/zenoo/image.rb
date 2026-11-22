# 2D テクスチャ・オフスクリーンレンダーターゲットを表す画像クラス。
# 画像ファイルの読み込み (`Image.load`)、空テクスチャ生成 (`Image.new`)、タイル分割 (`slice_tiles` / `Image.load_tiles`)、
# オフスクリーン描画 (`Image.render_to`)、シェーダーフィルター (`apply_filter`) などを提供します。
class Zenoo::Image
  # 内部描画キュー（Backend が使用）
  attr_accessor :__draw_queue

  # 指定したピクセルサイズまたは分割数で画像を格子状に分割した Image の配列を返す
  # - 分割数指定 (DXRuby互換): slice_tiles(xcount = 1, ycount = 1)
  # - ピクセル指定:           slice_tiles(tile_width: 32, tile_height: 32)
  # ※ 引数未指定時は 1x1 (画像全体) として処理します。
  #
  # - `xcount` (`Integer`): 横方向の分割数（`tile_width` / `tile_height` 未指定時に使用、デフォルト: 1）
  # - `ycount` (`Integer`): 縦方向の分割数（`tile_width` / `tile_height` 未指定時に使用、デフォルト: 1）
  # - `tile_width:` (`Integer`, `nil`): 1タイルあたりの幅（ピクセル単位、`tile_height:` とセットで指定）
  # - `tile_height:` (`Integer`, `nil`): 1タイルあたりの高さ（ピクセル単位、`tile_width:` とセットで指定）
  # - 戻り値: `Array<Image>` 分割された `sub_image` の配列（行優先順）
  def slice_tiles(xcount = 1, ycount = 1, tile_width: nil, tile_height: nil)
    if tile_width && tile_height
      tw = tile_width.to_i
      th = tile_height.to_i
      return [] if tw <= 0 || th <= 0
      xc = width / tw
      yc = height / th
    else
      xc = (xcount || 1).to_i
      yc = (ycount || 1).to_i
      return [] if xc <= 0 || yc <= 0
      tw = width / xc
      th = height / yc
    end

    return [] if xc <= 0 || yc <= 0 || tw <= 0 || th <= 0

    tiles = []
    yc.times do |cy|
      xc.times do |cx|
        tiles << sub_image(cx * tw, cy * th, tw, th)
      end
    end
    tiles
  end

  # ファイルから画像をロードし、格子状に分割した配列を生成
  # - 分割数指定 (DXRuby互換): load_tiles(filename, xcount = 1, ycount = 1)
  # - ピクセル指定:           load_tiles(filename, tile_width: 32, tile_height: 32)
  #
  # - `filename` (`String`): 読み込む画像ファイルのパス
  # - `xcount` (`Integer`): 横方向の分割数（デフォルト: 1）
  # - `ycount` (`Integer`): 縦方向の分割数（デフォルト: 1）
  # - `tile_width:` (`Integer`, `nil`): 1タイルあたりの幅（ピクセル単位）
  # - `tile_height:` (`Integer`, `nil`): 1タイルあたりの高さ（ピクセル単位）
  # - 戻り値: `Array<Image>` 分割された `Image` の配列（行優先順）
  def self.load_tiles(filename, xcount = 1, ycount = 1, tile_width: nil, tile_height: nil)
    img = Zenoo::Image.load(filename.to_s)
    img.slice_tiles(xcount, ycount, tile_width: tile_width, tile_height: tile_height)
  end

  # ピクセル色取得: image.get_pixel(x, y) -> Color
  #
  # - `x` (`Integer`): X座標（ピクセル単位）
  # - `y` (`Integer`): Y座標（ピクセル単位）
  # - 戻り値: `Color` 取得した RGBA カラー（各成分 0 〜 255）
  def get_pixel(x, y)
    col = raw_get_pixel(x.to_i, y.to_i)
    r = col & 0xFF
    g = (col >> 8) & 0xFF
    b = (col >> 16) & 0xFF
    a = (col >> 24) & 0xFF
    Zenoo::Color.new(r, g, b, a)
  end

  # ピクセル色設定: image.set_pixel(x, y, color)
  #
  # - `x` (`Integer`): X座標（ピクセル単位）
  # - `y` (`Integer`): Y座標（ピクセル単位）
  # - `color` (`Color`, `Symbol`, `Array<Integer>`): 設定する色（RGBA 0 〜 255、色名シンボル等）
  def set_pixel(x, y, color)
    c = Zenoo::Backend.normalize_color(color)
    r = (c[0] * 255.0).round.clamp(0, 255)
    g = (c[1] * 255.0).round.clamp(0, 255)
    b = (c[2] * 255.0).round.clamp(0, 255)
    a = (c[3] * 255.0).round.clamp(0, 255)
    raw_set_pixel_rgba(x.to_i, y.to_i, r, g, b, a)
  end


  # オフスクリーンFBO描画ブロック
  # Image.render_to(canvas) do
  #   Window.draw_rect(...)
  # end
  # ※ sub_image に対して呼び出された場合は、自動的に該当領域へクリッピングされます。
  #
  # - `target` (`Image`): 描画先となるオフスクリーン `Image`（`sub_image` も指定可）
  # - `&block`: 描画コマンド（`Window.draw_*` 等）を記述するブロック
  def self.render_to(target)
    state = __begin_render_to(target)
    yield
    __end_render_to(state)
  end

  def self.__begin_render_to(target)
    is_sub = target.sub_image?
    cam_state = Zenoo::Window.__save_and_reset_camera_state
    prev_ox = Zenoo::Window.__offset_x
    prev_oy = Zenoo::Window.__offset_y

    Zenoo::Backend.push_target(target)

    if is_sub
      Zenoo::Window.__offset_x = target.x.to_f
      Zenoo::Window.__offset_y = target.y.to_f
      Zenoo::Backend.push_clip([target.x.to_f, target.y.to_f, target.width.to_f, target.height.to_f], 0.0)
    else
      Zenoo::Window.__offset_x = 0.0
      Zenoo::Window.__offset_y = 0.0
    end
    [is_sub, cam_state, prev_ox, prev_oy]
  end

  def self.__end_render_to(state)
    if state[0]
      Zenoo::Backend.pop_clip
    end
    Zenoo::Window.__offset_x = state[2]
    Zenoo::Window.__offset_y = state[3]
    Zenoo::Window.__restore_camera_state(state[1])
    Zenoo::Backend.pop_target
  end

  # 画像のクリア (引数省略時は透明色 [0, 0, 0, 0])
  #
  # - `color` (`Color`, `Symbol`, `Array<Integer>`): 塗りつぶす背景色（デフォルト: `:clear` = 透明 `[0, 0, 0, 0]`）
  # - 戻り値: `Image` (`self`)
  def clear(color = :clear)
    Zenoo::Image.render_to(self) do
      if sub_image?
        Zenoo::Window.draw_rect(0.0, 0.0, width.to_f, height.to_f, color: color, blend: :none)
      else
        Zenoo::Window.clear(color)
      end
    end
    self
  end

  # シェーダーフィルターの適用 (画像加工・ポストプロセス)
  # 非破壊版: 加工済みの新しい Image を生成して返します
  #
  # - `shader` (`Shader`, `NativeShader`): 適用するフラグメントシェーダー
  # - `uniforms:` (`Hash`, `nil`): シェーダーに渡す追加の uniform 変数のハッシュ（デフォルト: `nil`）
  # - 戻り値: `Image` フィルター適用済みの新しい `Image`
  def apply_filter(shader, uniforms: nil)
    result = Zenoo::Image.new(width, height)
    Zenoo::Image.render_to(result) do
      Zenoo::Window.clear([0, 0, 0, 0])
      Zenoo::Window.draw(0, 0, self, shader: shader, uniforms: uniforms)
    end
    Zenoo::Backend.flush_image(result)
    result
  end

  # 破壊版: 自身のテクスチャをシェーダー処理で上書き加工します
  #
  # - `shader` (`Shader`, `NativeShader`): 適用するフラグメントシェーダー
  # - `uniforms:` (`Hash`, `nil`): シェーダーに渡す追加の uniform 変数のハッシュ（デフォルト: `nil`）
  # - 戻り値: `Image` (`self`)
  def apply_filter!(shader, uniforms: nil)
    filtered = apply_filter(shader, uniforms: uniforms)
    replace_texture!(filtered)
    self
  end
end

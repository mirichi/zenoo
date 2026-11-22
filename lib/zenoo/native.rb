# frozen_string_literal: true

# CRuby / Spinel AOT 共通ネイティブラッパー層
# 低レベル FFI 境界 (`Zenoo::Native::C`) をラップし、
# `Zenoo::Image` および `Zenoo::Native::*` の統一 API を提供する。

module Zenoo
  # Zenoo エンジンのバージョン定数
  VERSION = Native::C.zen_get_version

  # Zenoo エンジンのバージョン文字列を返す
  #
  # - 戻り値: `String`
  def self.version
    Native::C.zen_get_version
  end

  module Native
    KIND_IMAGE  = 1
    KIND_SHADER = 2
    KIND_MESH   = 3
    KIND_FONT     = 4
    KIND_SOUND    = 5
    KIND_SNAPSHOT = 6

    # @api private
    RAW_PTR = Object.new

    # Spinel AOT の ffi_callback 制約用・継承も再オープンもされない静的ブリッジモジュール
    # @api private
    module CallbackBridge
      def self.trigger_gc
        GC.start
      end

      def self.dispatch_frame
        Zenoo::Native::Window.dispatch_frame_callback
      end
    end

    # `box` と `kind` のみを受け取る別メソッドで Proc を生成し、`obj` をクロージャに捕捉させない。
    # @api private
    def self.make_finalizer(box, kind)
      proc do
        p = box[0]
        if p
          box[0] = nil
          C.zen_ffi_destroy_handle(p, kind)
        end
      end
    end

    # `obj` 本体の GC を妨げずにファイナライザを登録する。
    # @api private
    def self.install_finalizer(obj, box, kind)
      ObjectSpace.define_finalizer(obj, make_finalizer(box, kind))
    end
  end

  # ==========================================
  # 1. Zenoo::Image
  # ==========================================
  class Image
    # 内部用: ネイティブポインタ取得
    # @api private
    def __ptr
      @ptr
    end

    # 内部用: ネイティブポインタとファイナライザを紐付け
    # @api private
    def __bind_ptr(ptr)
      @ptr = ptr
      @box = [ptr]
      Native.install_finalizer(self, @box, Native::KIND_IMAGE)
      __refresh_metrics
    end

    # 内部用: C側の画像寸法・正規化UVをRubyインスタンス変数へ同期する
    # @api private
    def __refresh_metrics
      @width = Native::C.zen_ffi_image_width(@ptr)
      @height = Native::C.zen_ffi_image_height(@ptr)
      @x = Native::C.zen_ffi_image_x(@ptr)
      @y = Native::C.zen_ffi_image_y(@ptr)
      @texture_width = Native::C.zen_ffi_image_tex_width(@ptr)
      @texture_height = Native::C.zen_ffi_image_tex_height(@ptr)
      tw = @texture_width.to_f
      th = @texture_height.to_f
      if tw > 0.0 && th > 0.0
        @uv_cached = [@x.to_f / tw, @y.to_f / th, @width.to_f / tw, @height.to_f / th].freeze
      else
        @uv_cached = [0.0, 0.0, 1.0, 1.0].freeze
      end
      nil
    end

    # 新しい `Image` を生成する（ファイルパス指定、幅・高さ指定、またはオプション付き生成）。
    #
    # - 戻り値: `Image`
    def initialize(*args)
      argc = args.length
      if argc == 2 && args[0].equal?(Native::RAW_PTR)
        raise RuntimeError, "Failed to create Image" unless args[1]

        __bind_ptr(args[1])
        return
      end

      ptr = nil
      if argc >= 1 && args[0].is_a?(String)
        path = args[0]
        ptr = Native::C.zen_image_load(path)
        raise RuntimeError, "Failed to load image: #{path}" unless ptr

        if argc >= 2
          flt = args[1]
          Native::C.zen_image_set_filter(ptr, flt == :nearest ? 0 : 1) if flt == :nearest || flt == :linear
        end
      elsif argc == 2
        w = args[0].to_i
        h = args[1].to_i
        raise ArgumentError, "Image dimensions must be positive (#{w}x#{h})" if w <= 0 || h <= 0

        ptr = Native::C.zen_image_create(w, h)
        raise RuntimeError, "Failed to create Image (#{w}x#{h})" unless ptr
      elsif argc == 3
        w = args[0].to_i
        h = args[1].to_i
        raise ArgumentError, "Image dimensions must be positive (#{w}x#{h})" if w <= 0 || h <= 0

        opt = args[2]
        if opt.is_a?(Integer) && opt > 0
          ptr = Native::C.zen_image_create_msaa(w, h, opt)
          raise RuntimeError, "Failed to create MSAA Image (#{w}x#{h}, #{opt}x)" unless ptr
        else
          ptr = Native::C.zen_image_create(w, h)
          raise RuntimeError, "Failed to create Image (#{w}x#{h})" unless ptr

          Native::C.zen_image_set_filter(ptr, 0) if opt == :nearest
        end
      elsif argc == 4 && args[2] == -1
        w = args[0].to_i
        h = args[1].to_i
        fmt = args[3].to_i
        raise ArgumentError, "Image dimensions must be positive (#{w}x#{h})" if w <= 0 || h <= 0

        ptr = Native::C.zen_image_create_format(w, h, fmt)
        raise RuntimeError, "Failed to create Image format=#{fmt} (#{w}x#{h})" unless ptr
      else
        raise ArgumentError, "wrong arguments for Image.new (given #{argc})"
      end

      __bind_ptr(ptr)
    end

    # 画像ファイルを読み込んで `Image` を生成する。
    #
    # - `path` (`String`): 画像ファイルパス
    # - `filter` (`Symbol | nil`): 省略可（`:nearest` または `:linear`）
    # - 戻り値: `Image`
    def self.load(path, filter = nil)
      filter ? new(path.to_s, filter) : new(path.to_s)
    end

    # 内部用: ピクセルフォーマットを指定して `Image` を生成する
    # @api private
    def self.create_format(w, h, format)
      new(w.to_i, h.to_i, -1, format.to_i)
    end

    # 内部用: R8（1 チャンネル 8bit）フォーマットの `Image` を生成する
    # @api private
    def self.create_r8(w, h)
      create_format(w, h, 1)
    end

    # MSAA 対応のオフスクリーン描画用 `Image` を生成します。
    #
    # - `w` (`Integer`): 幅（ピクセル）
    # - `h` (`Integer`): 高さ（ピクセル）
    # - `samples` (`Integer`): MSAA サンプル数（デフォルト `4`）
    # - 戻り値: `Image`
    def self.create_msaa(w, h, samples = 4)
      new(w.to_i, h.to_i, samples.to_i)
    end

    # 描画先レンダーターゲットをデフォルトのウィンドウバックバッファに戻します。
    #
    # - 戻り値: `nil`
    def self.reset_render_target
      Native::C.zen_set_render_target(nil)
      nil
    end

    # GC 等により解放された `Image` ハンドル総数を返します（プロファイル・テスト用）。
    #
    # - 戻り値: `Integer`
    def self.free_count
      Native::C.zen_ffi_image_free_count
    end

    # 新規作成される画像にデフォルトで適用されるテクスチャ補間フィルタを取得します。
    #
    # - 戻り値: `Symbol` (`:nearest` または `:linear`)
    def self.default_texture_filter
      Native::C.zen_get_default_texture_filter == 0 ? :nearest : :linear
    end

    # 新規作成される画像のデフォルトのテクスチャ補間フィルタを設定します。
    #
    # - `val` (`Symbol`): `:nearest` または `:linear`
    def self.default_texture_filter=(val)
      Native::C.zen_set_default_texture_filter(val == :nearest ? 0 : 1)
    end

    # 画像の論理幅をピクセル単位で返します。
    #
    # - 戻り値: `Integer`
    def width
      @width
    end

    # 画像の論理高さをピクセル単位で返します。
    #
    # - 戻り値: `Integer`
    def height
      @height
    end

    # 親テクスチャ内におけるこの画像の切り出し開始 X 座標（ピクセル）を返します。
    #
    # - 戻り値: `Integer`
    def x
      @x
    end

    # 親テクスチャ内におけるこの画像の切り出し開始 Y 座標（ピクセル）を返します。
    #
    # - 戻り値: `Integer`
    def y
      @y
    end

    # GPU 上の物理テクスチャ全体の幅をピクセル単位で返します。
    #
    # - 戻り値: `Integer`
    def texture_width
      @texture_width
    end

    # GPU 上の物理テクスチャ全体の高さをピクセル単位で返します。
    #
    # - 戻り値: `Integer`
    def texture_height
      @texture_height
    end

    # OpenGL / WebGL のネイティブテクスチャ ID を返します。
    #
    # - 戻り値: `Integer`
    def texture_id
      Native::C.zen_image_get_texture_id(@ptr)
    end

    # テクスチャ全体における正規化 UV 座標 `[u, v, uw, vh]` を返します。
    #
    # - 戻り値: `Array<Float>` `[u, v, uw, vh]`（0.0 〜 1.0）
    def uv
      @uv_cached
    end

    # この画像が親テクスチャの一部を切り出したサブ画像かどうかを返します。
    #
    # - 戻り値: `Boolean`
    def sub_image?
      Native::C.zen_ffi_image_is_sub(@ptr) != 0
    end

    # この画像に適用されているテクスチャ補間フィルタを取得します。
    #
    # - 戻り値: `Symbol` (`:nearest` または `:linear`)
    def texture_filter
      Native::C.zen_image_get_filter(@ptr) == 0 ? :nearest : :linear
    end

    # この画像の拡大・縮小時のテクスチャ補間フィルタを設定します。
    #
    # - `val` (`Symbol`): `:nearest`（ドット絵向け）または `:linear`（滑らか補間）
    def texture_filter=(val)
      Native::C.zen_image_set_filter(@ptr, val == :nearest ? 0 : 1)
    end

    # 別の `Image` が保持する GPU テクスチャ実体でこの画像のテクスチャを置き換えます。
    #
    # - `src` (`Image`): 置き換え元の画像
    # - 戻り値: `nil`
    def replace_texture!(src)
      Native::C.zen_image_replace_texture(@ptr, src ? src.__ptr : nil)
      __refresh_metrics
      nil
    end

    # MSAA レンダーターゲット用の画像かどうかを返します。
    #
    # - 戻り値: `Boolean`
    def msaa?
      Native::C.zen_ffi_image_msaa_samples(@ptr) > 0
    end

    # MSAA サンプル数を返します（無効時は `0`）。
    #
    # - 戻り値: `Integer`
    def msaa_samples
      Native::C.zen_ffi_image_msaa_samples(@ptr)
    end

    # 内部用: この画像をアクティブなレンダーターゲット (FBO) として設定する
    # @api private
    def set_as_render_target
      Native::C.zen_set_render_target(@ptr)
      nil
    end

    # 部分領域を切り出した新しいサブ `Image` を返します（テクスチャ実体は共有）。
    #
    # - `sx` (`Integer`): 切り出し開始 X 座標
    # - `sy` (`Integer`): 切り出し開始 Y 座標
    # - `sw` (`Integer`): 切り出し幅
    # - `sh` (`Integer`): 切り出し高さ
    # - 戻り値: `Image | nil`
    def sub_image(sx, sy, sw, sh)
      sub_ptr = Native::C.zen_image_sub_image(@ptr, sx.to_i, sy.to_i, sw.to_i, sh.to_i)
      sub_ptr ? Image.new(Native::RAW_PTR, sub_ptr) : nil
    end

    # 内部用: 指定座標のパック済み 32bit ピクセル値 (ABGR) を取得する
    # @api private
    def raw_get_pixel(px, py)
      Native::C.zen_image_get_pixel(@ptr, px.to_i, py.to_i)
    end

    # 内部用: 指定座標にパック済み 32bit ピクセル値 (ABGR) を設定する
    # @api private
    def raw_set_pixel(px, py, packed_color)
      Native::C.zen_image_set_pixel(@ptr, px.to_i, py.to_i, packed_color.to_i & 0xFFFFFFFF)
      nil
    end

    # 内部用: 指定座標に RGBA 各成分 (0..255) でピクセルを設定する
    # @api private
    def raw_set_pixel_rgba(px, py, r, g, b, a)
      Native::C.zen_ffi_image_set_pixel_rgba(@ptr, px.to_i, py.to_i, r.to_i, g.to_i, b.to_i, a.to_i)
      nil
    end

    # 内部用: 画像全体の RGBA ピクセルデータをバイナリ文字列として取得する
    # @api private
    def raw_get_pixels
      w = width
      h = height
      return "" if w <= 0 || h <= 0

      Native::C.zen_ffi_image_get_pixels(@ptr, w * h * 4)
    end

    # 内部用: バイナリ文字列から画像全体の RGBA ピクセルデータを書き込む
    # @api private
    def raw_set_pixels(data)
      str = data.to_s
      required = width * height * 4
      if str.bytesize < required
        raise ArgumentError, "Pixel data buffer too short (expected #{required} bytes, got #{str.bytesize})"
      end

      Native::C.zen_ffi_image_set_pixels(@ptr, str)
      nil
    end

    # CPU 側のピクセル変更を GPU テクスチャへ同期します。
    #
    # - 戻り値: `nil`
    def sync
      Native::C.zen_image_sync_to_gpu(@ptr)
      nil
    end

    # この画像の独立した複製（ディープコピー）を作成して返します。
    #
    # - 戻り値: `Image`
    def clone
      c_ptr = Native::C.zen_image_clone(@ptr)
      raise RuntimeError, "Failed to clone Image" unless c_ptr

      Image.new(Native::RAW_PTR, c_ptr)
    end

    # 画像を PNG 等の画像ファイルへ保存します。
    #
    # - `filepath` (`String`): 保存先ファイルパス
    # - 戻り値: `Boolean`
    def save(filepath)
      Native::C.zen_image_save(@ptr, filepath.to_s) != 0
    end
  end

  module Native
    Image = Zenoo::Image

    # ==========================================
    # 2. Native::NativeShader
    # ==========================================
    class NativeShader
      def __ptr
        @ptr
      end

      def initialize(vert_src, frag_src)
        ptr = C.zen_ffi_shader_create(vert_src ? vert_src.to_s : "", frag_src ? frag_src.to_s : "")
        raise RuntimeError, "Failed to compile shader" unless ptr

        @ptr = ptr
        @box = [ptr]
        Native.install_finalizer(self, @box, KIND_SHADER)
      end

      def set_int(name, val)
        C.zen_shader_set_int(@ptr, name.to_s, val.to_i)
        nil
      end

      def set_float(name, val)
        C.zen_shader_set_float(@ptr, name.to_s, val.to_f)
        nil
      end

      def set_vec2(name, x, y)
        C.zen_shader_set_vec2(@ptr, name.to_s, x.to_f, y.to_f)
        nil
      end

      def set_vec3(name, x, y, z)
        C.zen_shader_set_vec3(@ptr, name.to_s, x.to_f, y.to_f, z.to_f)
        nil
      end

      def set_vec4(name, x, y, z, w)
        C.zen_shader_set_vec4(@ptr, name.to_s, x.to_f, y.to_f, z.to_f, w.to_f)
        nil
      end

      def set_vec4_array(name, data)
        str = data.is_a?(Array) ? data.pack("f*") : data.to_s
        count = str.bytesize / 16
        C.zen_ffi_shader_set_vec4_array(@ptr, name.to_s, count, str) if count > 0
        nil
      end

      def set_mat4(name, mat)
        str = mat.is_a?(Array) ? mat.pack("f*") : mat.to_s
        raise ArgumentError, "Expected 16-element Array of floats or 64-byte String for mat4" if str.bytesize < 64

        C.zen_ffi_shader_set_mat4(@ptr, name.to_s, str)
        nil
      end

      def set_texture(name, unit, image)
        C.zen_shader_set_texture(@ptr, name.to_s, unit.to_i, image ? image.__ptr : nil)
        nil
      end
    end

    # ==========================================
    # 3. Native::Mesh
    # ==========================================
    class Mesh
      def __ptr
        @ptr
      end

      def self.canvas(*args, &block)
        Zenoo::Mesh.canvas(*args, &block)
      end

      def self.grid(*args, &block)
        Zenoo::Mesh.grid(*args, &block)
      end

      def initialize(*args)
        argc = args.length
        dynamic = 0
        if argc >= 7
          topology = args[0]
          layout = args[1]
          vdata = args[2]
          vbytes = args[3].to_i
          vcount = args[4].to_i
          idata = args[5]
          icount = args[6].to_i
          dynamic = args[7] ? 1 : 0 if argc >= 8
        elsif argc >= 4
          topology = args[0]
          layout = args[1]
          vdata = args[2]
          vbytes = vdata ? vdata.to_s.bytesize : 0
          vcount = args[3].to_i
          idata = args[4]
          icount = args[5] ? args[5].to_i : (idata ? idata.to_s.bytesize / 4 : 0)
        else
          raise ArgumentError, "wrong number of arguments (given #{argc}, expected 4..7)"
        end

        lay_str = layout ? layout.to_s : ""
        v_str = vdata ? vdata.to_s : ""
        i_str = idata ? idata.to_s : ""
        ptr = C.zen_ffi_mesh_create(topology.to_i, lay_str, v_str, vbytes, vcount, i_str, icount, dynamic)
        raise RuntimeError, "Failed to create Mesh" unless ptr

        @ptr = ptr
        @box = [ptr]
        Native.install_finalizer(self, @box, KIND_MESH)
      end

      def update_vertices(*args)
        argc = args.length
        if argc == 4
          vdata, vbytes, offset, vcount = args[0], args[1].to_i, args[2].to_i, args[3].to_i
          s = vdata ? vdata.to_s : ""
        elsif argc >= 1 && argc <= 3
          vdata = args[0]
          offset = (args[1] || 0).to_i
          vcount = (args[2] || 0).to_i
          s = vdata ? vdata.to_s : ""
          vbytes = s.bytesize
        else
          raise ArgumentError, "wrong number of arguments (given #{argc}, expected 1..4)"
        end

        C.zen_ffi_mesh_update_vertices(@ptr, offset, s, vbytes, vcount)
        nil
      end

      def update_indices(idata, icount = 0)
        s = idata ? idata.to_s : ""
        cnt = icount.to_i > 0 ? icount.to_i : (s.bytesize / 4)
        raise ArgumentError, "Index buffer too short" if cnt > 0 && s.bytesize < cnt * 4

        C.zen_ffi_mesh_update_indices(@ptr, s, cnt)
        nil
      end

      def dynamic?
        C.zen_ffi_mesh_is_dynamic(@ptr) != 0
      end

      def vertex_count
        C.zen_ffi_mesh_vertex_count(@ptr)
      end

      def index_count
        C.zen_ffi_mesh_index_count(@ptr)
      end
    end

    # ==========================================
    # 4. Native::Window
    # ==========================================
    module Window
      @frame_callback = nil

      def self.dispatch_frame_callback
        @frame_callback.call if @frame_callback
      end

      def self.init(w, h, title, fullscreen = false, win_w = 0, win_h = 0, scale_mode = 0, scale = 1.0)
        ok = C.zen_ffi_win_init_scaled(
          w.to_i,
          h.to_i,
          title.to_s,
          win_w.to_i,
          win_h.to_i,
          fullscreen ? 1 : 0,
          (scale || 1.0).to_f
        )
        self.scale_mode = scale_mode
        ok != 0
      end

      def self.update
        C.zen_update != 0
      end

      def self.clear(color)
        C.zen_clear(color.to_i & 0xFFFFFFFF)
        nil
      end

      def self.size
        [C.zen_ffi_screen_w, C.zen_ffi_screen_h]
      end

      def self.size_w
        C.zen_ffi_screen_w
      end

      def self.size_h
        C.zen_ffi_screen_h
      end

      def self.window_size
        [C.zen_ffi_window_w, C.zen_ffi_window_h]
      end

      def self.set_window_size(w, h)
        C.zen_set_window_size(w.to_i, h.to_i)
        nil
      end

      def self.scale_mode=(val)
        mode = if val == :resize || val == 2
                 2
               elsif val == :integer || val == 1
                 1
               else
                 0
               end
        C.zen_set_scale_mode(mode)
      end

      def self.scale_mode
        m = C.zen_get_scale_mode
        if m == 2
          :resize
        elsif m == 1
          :integer
        else
          :fit
        end
      end

      def self.scale=(val)
        C.zen_set_window_scale(val.to_f)
      end

      def self.window_scale=(val)
        C.zen_set_window_scale(val.to_f)
      end

      def self.scale
        C.zen_get_scale
      end

      def self.window_scale
        C.zen_get_window_scale
      end

      def self.dpi_scale
        C.zen_get_dpi_scale
      end

      def self.title=(val)
        C.zen_set_window_title(val.to_s)
      end

      def self.title
        C.zen_get_window_title || ""
      end

      def self.window_position
        [C.zen_ffi_window_pos_x, C.zen_ffi_window_pos_y]
      end

      def self.set_window_position(x, y)
        C.zen_set_window_pos(x.to_i, y.to_i)
        nil
      end

      def self.focused?
        C.zen_is_window_focused != 0
      end

      def self.minimized?
        C.zen_is_window_minimized != 0
      end

      def self.maximized?
        C.zen_is_window_maximized != 0
      end

      def self.hovered?
        C.zen_is_window_hovered != 0
      end

      def self.resizing?
        C.zen_is_resizing != 0
      end

      def self.live_resize=(val)
        C.zen_set_live_resize(val ? 1 : 0)
      end

      def self.live_resize
        C.zen_get_live_resize != 0
      end

      def self.set_frame_callback(cb)
        @frame_callback = cb
        if cb
          C.zen_set_frame_callback(CallbackBridge.method(:dispatch_frame))
        else
          C.zen_ffi_clear_frame_callback
        end
        nil
      end

      def self.start_wasm_loop(cb)
        @frame_callback = cb
        C.zen_run_loop(CallbackBridge.method(:dispatch_frame))
        nil
      end

      def self.msaa_samples=(val)
        C.zen_window_set_msaa_samples(val.to_i)
      end

      def self.msaa_samples
        C.zen_window_get_msaa_samples
      end

      def self.vsync=(val)
        v = if val == true
              1
            elsif val == false || val.nil?
              0
            else
              val.to_i
            end
        C.zen_set_vsync(v)
      end

      def self.target_fps=(val)
        C.zen_set_target_fps(val.to_i)
      end

      def self.target_fps
        C.zen_get_target_fps
      end

      def self.delta_time
        C.zen_get_delta_time
      end

      def self.time
        C.zen_get_time
      end

      def self.shutdown
        C.zen_shutdown
        nil
      end

      def self.ensure_context
        C.zen_ensure_context != 0
      end

      def self.wasm?
        C.zen_is_wasm != 0
      end

      def self.show_cursor(show)
        C.zen_window_show_cursor(show ? 1 : 0)
        nil
      end

      def self.set_cursor(shape)
        C.zen_window_set_cursor(shape.to_i)
        nil
      end
    end

    # ==========================================
    # 5. Native::Input
    # ==========================================
    module Input
      def self.clipboard
        C.zen_window_get_clipboard_string || ""
      end

      def self.clipboard=(str)
        C.zen_window_set_clipboard_string(str.to_s)
      end

      def self.key_pressed?(key)
        C.zen_is_key_pressed(key.to_i) != 0
      end

      def self.key_push?(key)
        C.zen_is_key_push(key.to_i) != 0
      end

      def self.key_release?(key)
        C.zen_is_key_release(key.to_i) != 0
      end

      def self.key_repeat?(key)
        C.zen_is_key_repeat(key.to_i) != 0
      end

      def self.mouse_pos
        [C.zen_ffi_mouse_x, C.zen_ffi_mouse_y]
      end

      def self.mouse_x
        C.zen_ffi_mouse_x
      end

      def self.mouse_y
        C.zen_ffi_mouse_y
      end

      def self.mouse_pressed?(btn)
        C.zen_is_mouse_pressed(btn.to_i) != 0
      end

      def self.mouse_push?(btn)
        C.zen_is_mouse_push(btn.to_i) != 0
      end

      def self.mouse_release?(btn)
        C.zen_is_mouse_release(btn.to_i) != 0
      end

      def self.mouse_wheel_x
        C.zen_get_mouse_wheel_x
      end

      def self.mouse_wheel_y
        C.zen_get_mouse_wheel_y
      end

      def self.mouse_wheel
        C.zen_get_mouse_wheel_y
      end

      def self.gamepad_connected?(pad_id)
        C.zen_is_gamepad_connected(pad_id.to_i) != 0
      end

      def self.gamepad_axis(pad_id, axis)
        C.zen_get_gamepad_axis(pad_id.to_i, axis.to_i)
      end

      def self.gamepad_button_pressed?(pad_id, btn)
        C.zen_is_gamepad_button_pressed(pad_id.to_i, btn.to_i) != 0
      end

      def self.gamepad_button_push?(pad_id, btn)
        C.zen_is_gamepad_button_push(pad_id.to_i, btn.to_i) != 0
      end

      def self.gamepad_button_release?(pad_id, btn)
        C.zen_is_gamepad_button_release(pad_id.to_i, btn.to_i) != 0
      end

      def self.vibrate_gamepad(pad_id, strong, weak, duration)
        C.zen_gamepad_vibrate(pad_id.to_i, strong.to_f, weak.to_f, duration.to_f)
        nil
      end

      def self.vibrate(duration)
        C.zen_vibrate(duration.to_f)
        nil
      end

      def self.get_char
        C.zen_get_char
      end

      def self.input_chars
        chars = []
        while (cp = C.zen_get_char) != -1
          if cp >= 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF)
            chars << cp.chr(Encoding::UTF_8)
          end
        end
        chars
      end

      def self.set_ime_position(x, y)
        C.zen_set_ime_position(x.to_i, y.to_i)
        nil
      end

      def self.touch_event_count
        C.zen_get_touch_count
      end

      def self.touch_event_id(idx)
        C.zen_get_touch_event_id(idx.to_i)
      end

      def self.touch_event_type(idx)
        C.zen_get_touch_event_type(idx.to_i)
      end

      def self.touch_event_x(idx)
        C.zen_get_touch_event_x(idx.to_i)
      end

      def self.touch_event_y(idx)
        C.zen_get_touch_event_y(idx.to_i)
      end

      def self.touch_clear_events
        C.zen_clear_touch_events
        nil
      end

      def self.push_touch(id, type, x, y)
        C.zen_push_touch(id.to_i, type.to_i, x.to_f, y.to_f)
        nil
      end
    end

    # ==========================================
    # 6. Native::Renderer
    # ==========================================
    module Renderer
      def self.draw_buffer(topology, layout, divisors, base_vertex_count, data, count, img, sh)
        lay_str = layout ? layout.to_s : ""
        div_str = divisors ? divisors.to_s : ""
        data_str = data ? data.to_s : ""
        attr_count = lay_str.bytesize
        raise ArgumentError, "Empty vertex layout" if attr_count <= 0

        stride = 0
        i = 0
        while i < attr_count
          stride += lay_str.getbyte(i) * 4
          i += 1
        end
        raise ArgumentError, "Invalid vertex layout stride: #{stride}" if stride <= 0
        raise ArgumentError, "Divisor string shorter than layout" if div_str.bytesize < attr_count

        cnt = count.to_i
        if cnt > 0 && data_str.bytesize < stride * cnt
          raise ArgumentError, "Vertex/instance buffer too short (expected >= #{stride * cnt} bytes, got #{data_str.bytesize})"
        end

        C.zen_ffi_draw_buffer(
          topology.to_i,
          lay_str,
          div_str,
          base_vertex_count.to_i,
          data_str,
          cnt,
          img ? img.__ptr : nil,
          sh ? sh.__ptr : nil
        )
        nil
      end

      def self.draw_mesh(geom_mesh, inst_buffer, inst_layout, inst_data, inst_count, img, sh)
        C.zen_ffi_draw_mesh(
          geom_mesh ? geom_mesh.__ptr : nil,
          inst_buffer ? inst_buffer.__ptr : nil,
          inst_layout ? inst_layout.to_s : "",
          inst_data ? inst_data.to_s : "",
          inst_count.to_i,
          img ? img.__ptr : nil,
          sh ? sh.__ptr : nil
        )
        nil
      end

      def self.flush
        nil
      end

      def self.set_blend_mode(mode)
        C.zen_set_blend_mode(mode.to_i)
        nil
      end

      def self.set_scissor(x, y, w, h)
        C.zen_set_scissor(x.to_i, y.to_i, w.to_i, h.to_i)
        nil
      end

      def self.reset_scissor
        C.zen_reset_scissor
        nil
      end
    end

    # ==========================================
    # 7. Native::Font & Native::FontHelper
    # ==========================================
    module FontHelper
      @atlas_image = nil

      def self.set_atlas_image(img)
        @atlas_image = img
        C.zen_font_set_atlas_image(img ? img.__ptr : nil)
        nil
      end

      def self.atlas_image
        @atlas_image
      end

      def self.atlas_generation
        C.zen_font_atlas_generation
      end

      def self.glyph_visible
        C.zen_ffi_glyph_visible != 0
      end

      def self.glyph_u0
        C.zen_ffi_glyph_u0
      end

      def self.glyph_v0
        C.zen_ffi_glyph_v0
      end

      def self.glyph_u1
        C.zen_ffi_glyph_u1
      end

      def self.glyph_v1
        C.zen_ffi_glyph_v1
      end

      def self.glyph_x0
        C.zen_ffi_glyph_x0
      end

      def self.glyph_y0
        C.zen_ffi_glyph_y0
      end

      def self.glyph_x1
        C.zen_ffi_glyph_x1
      end

      def self.glyph_y1
        C.zen_ffi_glyph_y1
      end

      def self.glyph_advance
        C.zen_ffi_glyph_advance
      end

      def self.glyph_is_bitmap
        C.zen_ffi_glyph_is_bitmap != 0
      end
    end

    class Font
      def __ptr
        @ptr
      end

      def initialize(path, index = 0)
        p_str = path.to_s
        ptr = C.zen_font_load(p_str, index.to_i)
        raise RuntimeError, "Failed to load font: #{p_str}" unless ptr

        @ptr = ptr
        @box = [ptr]
        Native.install_finalizer(self, @box, KIND_FONT)
      end

      def self.load(path, index = 0)
        new(path.to_s, index.to_i)
      end

      def self.atlas_image
        FontHelper.atlas_image
      end

      def metrics(size)
        s = size.to_f
        [
          C.zen_ffi_font_ascent(@ptr, s),
          C.zen_ffi_font_descent(@ptr, s),
          C.zen_ffi_font_line_gap(@ptr, s)
        ]
      end

      def get_glyph(cp, size, mode = 0, r_scale = 1.0)
        ok = C.zen_ffi_font_query_glyph(@ptr, cp.to_i, size.to_f, mode.to_i, r_scale.to_f)
        return nil if ok == 0

        [
          C.zen_ffi_glyph_visible != 0,
          C.zen_ffi_glyph_u0,
          C.zen_ffi_glyph_v0,
          C.zen_ffi_glyph_u1,
          C.zen_ffi_glyph_v1,
          C.zen_ffi_glyph_x0,
          C.zen_ffi_glyph_y0,
          C.zen_ffi_glyph_x1,
          C.zen_ffi_glyph_y1,
          C.zen_ffi_glyph_advance,
          C.zen_ffi_glyph_is_bitmap != 0
        ]
      end
    end

    # ==========================================
    # 8. Native::Sound & Native::Audio
    # ==========================================
    class Sound
      def __bind_ptr(ptr)
        @ptr = ptr
        @box = [ptr]
        Native.install_finalizer(self, @box, KIND_SOUND)
      end

      def initialize(*args)
        if args.length == 2 && args[0].equal?(RAW_PTR)
          raise RuntimeError, "Failed to create Sound" unless args[1]

          __bind_ptr(args[1])
          return
        end

        if args.length == 4
          str = args[0].is_a?(Array) ? args[0].pack("e*") : args[0].to_s
          frames = args[1].to_i
          ch = args[2].to_i
          sr = args[3].to_i
          raise ArgumentError, "Invalid PCM arguments" if ch <= 0 || sr <= 0 || frames <= 0

          ptr = C.zen_ffi_sound_load_pcm(str, frames, ch, sr)
          raise RuntimeError, "Failed to load PCM sound" unless ptr
        elsif args.length >= 1 && args.length <= 2
          path = args[0].to_s
          stream = args[1] ? 1 : 0
          ptr = C.zen_sound_load_file(path, stream)
          raise RuntimeError, "Failed to load sound: #{path}" unless ptr
        else
          raise ArgumentError, "wrong number of arguments (given #{args.length}, expected 1..4)"
        end

        __bind_ptr(ptr)
      end

      def self.load(path, stream = false)
        new(path.to_s, !!stream)
      end

      def self.load_pcm(samples_or_binary, channels, sample_rate)
        ch = channels.to_i
        sr = sample_rate.to_i
        raise ArgumentError, "Invalid channels or sample_rate" if ch <= 0 || sr <= 0

        str = samples_or_binary.is_a?(Array) ? samples_or_binary.pack("e*") : samples_or_binary.to_s
        frame_count = str.bytesize / (4 * ch)
        raise ArgumentError, "Empty samples data" if frame_count <= 0

        ptr = C.zen_ffi_sound_load_pcm(str, frame_count, ch, sr)
        raise RuntimeError, "Failed to load PCM sound" unless ptr

        new(RAW_PTR, ptr)
      end

      def play
        C.zen_sound_play(@ptr)
        nil
      end

      def stop
        C.zen_sound_stop(@ptr)
        nil
      end

      def pause
        C.zen_sound_pause(@ptr)
        nil
      end

      def playing?
        C.zen_sound_is_playing(@ptr) != 0
      end

      def volume=(vol)
        C.zen_sound_set_volume(@ptr, vol.to_f)
      end

      def volume
        C.zen_sound_get_volume(@ptr)
      end

      def looping=(loop)
        C.zen_sound_set_looping(@ptr, loop ? 1 : 0)
      end

      def looping?
        C.zen_sound_is_looping(@ptr) != 0
      end

      def pitch=(pitch)
        C.zen_sound_set_pitch(@ptr, pitch.to_f)
      end

      def pitch
        C.zen_sound_get_pitch(@ptr)
      end

      def pan=(pan)
        C.zen_sound_set_pan(@ptr, pan.to_f)
      end

      def pan
        C.zen_sound_get_pan(@ptr)
      end

      def seek(seconds)
        C.zen_sound_seek(@ptr, seconds.to_f)
        nil
      end

      def cursor
        C.zen_sound_get_cursor(@ptr)
      end

      def length
        C.zen_sound_get_length(@ptr)
      end

      def sample_rate
        C.zen_sound_get_sample_rate(@ptr)
      end

      def length_pcm
        C.zen_ffi_sound_get_length_pcm(@ptr)
      end

      def set_loop_points(start_sec = 0.0, end_sec = 0.0)
        C.zen_sound_set_loop_points_seconds(@ptr, start_sec.to_f, end_sec.to_f)
        nil
      end

      def set_loop_points_pcm(start_pcm = 0, end_pcm = 0)
        C.zen_ffi_sound_set_loop_points_pcm(@ptr, start_pcm.to_i, end_pcm.to_i)
        nil
      end

      def loop_start
        C.zen_ffi_sound_get_loop_start_sec(@ptr)
      end

      def loop_start=(start_sec)
        C.zen_ffi_sound_set_loop_start_sec(@ptr, start_sec.to_f)
      end

      def loop_end
        C.zen_ffi_sound_get_loop_end_sec(@ptr)
      end

      def loop_end=(end_sec)
        C.zen_ffi_sound_set_loop_end_sec(@ptr, end_sec.to_f)
      end

      def loop_start_pcm
        C.zen_ffi_sound_get_loop_start_pcm(@ptr)
      end

      def loop_start_pcm=(start_pcm)
        C.zen_ffi_sound_set_loop_start_pcm(@ptr, start_pcm.to_i)
      end

      def loop_end_pcm
        C.zen_ffi_sound_get_loop_end_pcm(@ptr)
      end

      def loop_end_pcm=(end_pcm)
        C.zen_ffi_sound_set_loop_end_pcm(@ptr, end_pcm.to_i)
      end

      def has_loop_points?
        C.zen_sound_has_loop_points(@ptr) != 0
      end

      def clear_loop_points
        C.zen_sound_clear_loop_points(@ptr)
        nil
      end
    end

    module Audio
      def self.init
        C.zen_audio_init != 0
      end

      def self.shutdown
        C.zen_audio_shutdown
        nil
      end

      def self.master_volume=(vol)
        C.zen_audio_set_master_volume(vol.to_f)
      end

      def self.master_volume
        C.zen_audio_get_master_volume
      end
    end

    # ==========================================
    # 9. Native::Browser
    # ==========================================
    module Browser
      def self.raw_eval(code)
        C.zen_js_eval(code.to_s)
        nil
      end

      def self.raw_eval_num(code)
        C.zen_js_eval_num(code.to_s)
      end

      def self.raw_eval_str(code)
        C.zen_js_eval_str(code.to_s) || ""
      end

      def self.visible?
        C.zen_js_is_page_visible != 0
      end

      def self.raw_safe_area_left
        C.zen_ffi_safe_area_left
      end

      def self.raw_safe_area_top
        C.zen_ffi_safe_area_top
      end

      def self.raw_safe_area_right
        C.zen_ffi_safe_area_right
      end

      def self.raw_safe_area_bottom
        C.zen_ffi_safe_area_bottom
      end
    end

    # Spinel AOT / CRuby 双方で C 側のメモリ圧迫時 GC フックを有効化する
    C.zen_set_gc_trigger_callback(CallbackBridge.method(:trigger_gc))
  end
end

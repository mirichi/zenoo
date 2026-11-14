module Zenoo
  native_lib "glfw"
  native_lib "GL"
  native_lib "m"

  # C バックエンドのエンジンバージョン文字列を取得: Zenoo.version -> String
  native_func :version, [], :string, "sp_zen_get_version"
  VERSION = version

  # ==========================================
  # 1. Image (Spinel native_struct)
  # ※ C拡張のネイティブ画像バインディング（Ruby側の拡張メソッドは lib/zenoo/image.rb を参照）
  # ==========================================
  native_struct "Zenoo::Image", "sp_ZenImage", "sp_ZenImage_free"
  native_new [:int, :int], "sp_ZenImage_new"                       # 空の画像生成: Image.new(width, height)
  native_new [:int, :int, :int], "sp_ZenImage_new_msaa"            # MSAA 画像生成: Image.new(width, height, samples)
  native_new [:int, :int, :int, :int], "sp_ZenImage_new_format_internal" # 内部フォーマット指定生成 (R8 等)
  native_new [:string],    "sp_ZenImage_load"                      # 画像ファイル読み込み: Image.new(path)
  native_method :width,  [], :int, "sp_ZenImage_width"             # 画像の幅 (px)
  native_method :height, [], :int, "sp_ZenImage_height"            # 画像の高さ (px)
  native_method :msaa?,  [], :bool, "sp_ZenImage_msaa"             # MSAA レンダーターゲットかどうか
  native_method :msaa_samples, [], :int, "sp_ZenImage_msaa_samples" # MSAA サンプル数
  native_method :set_as_render_target, [], :nil, "sp_ZenImage_set_as_render_target" # 内部用: FBO をアクティブ化
  native_method :sub_image, [:int, :int, :int, :int], :self, "sp_ZenImage_sub_image" # 部分領域を切り出したサブ画像を返す
  native_method :x, [], :int, "sp_ZenImage_x"                      # サブ画像の元テクスチャ内 X オフセット (px)
  native_method :y, [], :int, "sp_ZenImage_y"                      # サブ画像の元テクスチャ内 Y オフセット (px)
  native_method :texture_width, [], :int, "sp_ZenImage_texture_width"   # 元テクスチャ全体の幅 (px)
  native_method :texture_height, [], :int, "sp_ZenImage_texture_height" # 元テクスチャ全体の高さ (px)
  native_method :texture_id, [], :int, "sp_ZenImage_texture_id"    # OpenGL / WebGL テクスチャ ID
  native_method :sub_image?, [], :bool, "sp_ZenImage_is_sub_image" # サブ画像かどうか
  native_method :raw_texture_filter=, [:int], :nil, "sp_ZenImage_set_filter"   # 内部用 (Image#texture_filter= を使用)
  native_method :raw_texture_filter, [], :int, "sp_ZenImage_get_filter"        # 内部用 (Image#texture_filter を使用)
  native_class_method :raw_default_texture_filter=, [:int], :nil, "sp_zen_image_set_default_filter" # 内部用
  native_class_method :raw_default_texture_filter, [], :int, "sp_zen_image_get_default_filter"      # 内部用
  native_method :replace_texture!, [:self], :nil, "sp_ZenImage_replace_texture" # 別 Image のテクスチャで自身を置き換える
  native_method :raw_get_pixel, [:int, :int], :int, "sp_ZenImage_get_pixel"    # 内部用 (Image#get_pixel を使用)
  native_method :raw_set_pixel, [:int, :int, :int], :nil, "sp_ZenImage_set_pixel" # 内部用 (Image#set_pixel を使用)
  native_method :raw_set_pixel_rgba, [:int, :int, :int, :int, :int, :int], :nil, "sp_ZenImage_set_pixel_rgba" # 内部用
  native_method :sync, [], :nil, "sp_ZenImage_sync"                # CPU ピクセルバッファ変更を GPU テクスチャへ反映
  native_method :clone, [], :self, "sp_ZenImage_clone"             # 画像の複製を作成
  native_method :dup, [], :self, "sp_ZenImage_clone"               # 画像の複製を作成
  native_method :save, [:string], :bool, "sp_ZenImage_save"        # 画像をファイル (PNG 等) に保存

  # ==========================================
  # 2. Native::NativeShader (Spinel native_struct)
  # ※ GLSL シェーダープログラムと uniform 転送バインディング（Ruby側エントリは lib/zenoo/shader.rb を参照）
  # ==========================================
  native_struct "Zenoo::Native::NativeShader", "sp_ZenShader", "sp_ZenShader_free"
  native_new [:string, :string], "sp_ZenShader_new"                              # 生成: new(vert_src, frag_src)
  native_method :set_int,   [:string, :int],   :nil, "sp_ZenShader_set_int"        # int uniform 設定: set_int(name, val)
  native_method :set_float, [:string, :float], :nil, "sp_ZenShader_set_float"      # float uniform 設定: set_float(name, val)
  native_method :set_vec2,  [:string, :float, :float], :nil, "sp_ZenShader_set_vec2"               # vec2 uniform 設定: set_vec2(name, x, y)
  native_method :set_vec3,  [:string, :float, :float, :float], :nil, "sp_ZenShader_set_vec3"       # vec3 uniform 設定: set_vec3(name, x, y, z)
  native_method :set_vec4,  [:string, :float, :float, :float, :float], :nil, "sp_ZenShader_set_vec4" # vec4 uniform 設定: set_vec4(name, x, y, z, w)
  native_method :raw_set_vec4_array, [:string, :int, :string], :nil, "sp_ZenShader_set_vec4_array" # 内部用: vec4配列転送(name, vec4個数, floatバイナリ)
  native_method :set_mat4,  [:string, :string], :nil, "sp_ZenShader_set_mat4"      # mat4 uniform 設定: set_mat4(name, 16要素floatパック文字列)
  native_method :set_texture, [:string, :int, :any], :nil, "sp_ZenShader_set_texture" # テクスチャ uniform バインド: set_texture(name, unit番号, Image)

  # ==========================================
  # 2.5. Native::Mesh (Spinel native_struct)
  # ※ VBO / IBO を保持する VRAM ジオメトリ & インスタンスバッファ（Ruby側APIは lib/zenoo/mesh.rb を参照）
  # ==========================================
  native_struct "Zenoo::Native::Mesh", "sp_ZenMesh", "sp_ZenMesh_free"
  native_new [:int, :string, :string, :int, :int, :string, :int], "sp_ZenMesh_new" # 生成: new(topology, layout文字列, 頂点バイナリ, 頂点バイト数, 頂点数, インデックスバイナリ, インデックス数)
  native_method :raw_update_vertices, [:string, :int, :int, :int], :nil, "sp_ZenMesh_update_vertices" # 内部用: 頂点バッファ更新(vdata, bytes, offset頂点, count頂点)
  native_method :raw_update_indices,  [:string, :int], :nil, "sp_ZenMesh_update_indices"             # 内部用: インデックスバッファ更新(idata, index数)
  native_method :dynamic?,     [], :bool, "sp_ZenMesh_is_dynamic"     # GL_DYNAMIC_DRAW へ昇格済みかどうか
  native_method :vertex_count, [], :int,  "sp_ZenMesh_vertex_count"   # 保持している頂点数（またはインスタンス数）
  native_method :index_count,  [], :int,  "sp_ZenMesh_index_count"    # 保持しているインデックス数（非インデックス時は 0）

  module Native
    # ==========================================
    # 3. Native::Window
    # ※ GLFW / Emscripten ウィンドウ制御・論理解像度・DPI・フレームタイミングの C バインディング
    # ==========================================
    module Window
      native_func :raw_init, [:int, :int, :string, :int], :int, "sp_zen_win_init"                              # 内部用: 基本初期化(w, h, title, fullscreen:0|1)
      native_func :raw_init_scaled, [:int, :int, :string, :int, :int, :int, :float], :int, "sp_zen_win_init_scaled" # 内部用: スケール付き初期化(base_w, base_h, title, win_w, win_h, fullscreen, scale)
      native_func :update, [], :bool, "sp_zen_win_update"                 # イベントポーリング＋SwapBuffers（ウィンドウ継続中は true、閉じる要求で false）
      native_func :clear, [:int], :nil, "sp_zen_win_clear"                # 現在のレンダーターゲットを指定の 0xRRGGBBAA 32bit RGBA 色でクリア
      native_func :size_w, [], :int, "sp_zen_win_size_w"                  # 論理（仮想）解像度の幅 (px)
      native_func :size_h, [], :int, "sp_zen_win_size_h"                  # 論理（仮想）解像度の高さ (px)
      native_func :os_size_w, [], :int, "sp_zen_win_os_size_w"            # OS 実ウィンドウのクライアント幅 (px)
      native_func :os_size_h, [], :int, "sp_zen_win_os_size_h"            # OS 実ウィンドウのクライアント高さ (px)
      native_func :raw_scale_mode=, [:int], :nil, "sp_zen_win_set_scale_mode" # 内部用: スケールモード設定 (0: fit, 1: integer)
      native_func :raw_scale_mode, [], :int, "sp_zen_win_get_scale_mode"      # 内部用: スケールモード取得 (0: fit, 1: integer)
      native_func :raw_set_scale, [:float], :nil, "sp_zen_win_set_scale"      # 内部用: ウィンドウ倍率設定
      native_func :scale, [], :float, "sp_zen_win_get_scale"                  # 現在の表示倍率
      native_func :window_scale, [], :float, "sp_zen_win_get_window_scale"    # ウィンドウ拡大倍率
      native_func :dpi_scale, [], :float, "sp_zen_win_get_dpi_scale"          # モニター DPI スケール係数
      native_func :set_window_size, [:int, :int], :nil, "sp_zen_win_set_window_size" # OS 実ウィンドウサイズ変更(w, h)
      native_func :raw_set_msaa_samples, [:int], :nil, "sp_zen_win_set_msaa_samples" # 内部用: 初期化前 MSAA サンプル数設定
      native_func :raw_get_msaa_samples, [], :int, "sp_zen_win_get_msaa_samples"     # 内部用: MSAA サンプル数取得
      native_func :title=, [:string], :nil, "sp_zen_win_set_title"        # ウィンドウタイトル文字列設定
      native_func :title, [], :string, "sp_zen_win_get_title"             # ウィンドウタイトル文字列取得
      native_func :pos_x, [], :int, "sp_zen_win_get_pos_x"                # ウィンドウ左上 X 座標 (スクリーン座標)
      native_func :pos_y, [], :int, "sp_zen_win_get_pos_y"                # ウィンドウ左上 Y 座標 (スクリーン座標)
      native_func :set_window_pos_raw, [:int, :int], :nil, "sp_zen_win_set_window_pos" # 内部用: ウィンドウ位置移動(x, y)
      native_func :focused?, [], :bool, "sp_zen_win_is_focused"           # ウィンドウが入力フォーカス中か
      native_func :minimized?, [], :bool, "sp_zen_win_is_minimized"       # 最小化されているか
      native_func :maximized?, [], :bool, "sp_zen_win_is_maximized"       # 最大化されているか
      native_func :hovered?, [], :bool, "sp_zen_win_is_hovered"           # マウスカーソルがウィンドウ上にあるか
      native_func :vsync=, [:int], :nil, "sp_zen_win_vsync_set"           # VSync 設定 (1: 有効, 0: 無効)
      native_func :target_fps=, [:int], :nil, "sp_zen_win_target_fps_set" # 目標 FPS 設定 (0 以下で無制限)
      native_func :delta_time, [], :float, "sp_zen_win_delta_time"        # 前フレームからの経過時間（秒）
      native_func :time, [], :float, "sp_zen_win_time"                    # 起動からの累計経過時間（秒）
      native_func :shutdown, [], :nil, "sp_zen_win_shutdown"              # ウィンドウ・GL コンテキストの終了処理
      native_func :ensure_context, [], :bool, "sp_zen_win_ensure_context" # ヘッドレス環境等で GL コンテキストが準備済みか確認／確保
      native_func :wasm?, [], :bool, "sp_zen_win_is_wasm"                 # Emscripten (Wasm) 環境で動作中か
      native_func :start_wasm_loop, [:any], :nil, "sp_zen_win_start_wasm_loop" # Wasm 用 `requestAnimationFrame` ループ開始(ステップ用 Proc)
      native_func :raw_show_cursor, [:int], :nil, "sp_zen_win_show_cursor" # 内部用: カーソル表示切替 (1: 表示, 0: 非表示)
      native_func :raw_set_cursor, [:int], :nil, "sp_zen_win_set_cursor"   # 内部用: カーソル形状 ID 設定

      # マウスカーソルの表示／非表示を切り替える
      #
      # - `show` (`Boolean`): `true` で表示、`false` で非表示
      # - 戻り値: `nil`
      def self.show_cursor(show)
        raw_show_cursor(show ? 1 : 0)
      end

      # OS 標準マウスカーソルの形状を設定する
      #
      # - `shape` (`Integer`): カーソル形状識別子
      # - 戻り値: `nil`
      def self.set_cursor(shape)
        raw_set_cursor(shape.to_i)
      end

      # ウィンドウの MSAA サンプル数を設定する
      #
      # - `val` (`Integer`): サンプル数（`0`, `2`, `4`, `8` 等）
      # - 戻り値: `nil`
      def self.msaa_samples=(val)
        Zenoo::Native::Window.raw_set_msaa_samples(val.to_i)
      end

      # 現在の MSAA サンプル数を返す
      #
      # - 戻り値: `Integer`
      def self.msaa_samples
        Zenoo::Native::Window.raw_get_msaa_samples
      end

      # ウィンドウリサイズ時のスケーリングモードを設定する
      #
      # - `val` (`Symbol | Integer`): `:integer`（または `1`）で整数倍スケーリング、それ以外は `:fit`（`0`）
      # - 戻り値: `nil`
      def self.scale_mode=(val)
        mode = (val == :integer || val == 1) ? 1 : 0
        Zenoo::Native::Window.raw_scale_mode = mode
      end

      # ウィンドウの表示倍率を設定する
      #
      # - `val` (`Float`): 表示倍率
      # - 戻り値: `nil`
      def self.scale=(val)
        Zenoo::Native::Window.raw_set_scale(val.to_f)
      end

      # ウィンドウの表示倍率を設定する（`scale=` と同等）
      #
      # - `val` (`Float`): 表示倍率
      # - 戻り値: `nil`
      def self.window_scale=(val)
        Zenoo::Native::Window.raw_set_scale(val.to_f)
      end

      # 現在のスケーリングモードをシンボルで返す
      #
      # - 戻り値: `Symbol`（`:integer` または `:fit`）
      def self.scale_mode
        Zenoo::Native::Window.raw_scale_mode == 1 ? :integer : :fit
      end

      # OS 実ウィンドウのクライアントサイズ `[width, height]` を返す
      #
      # - 戻り値: `Array<Integer>`
      def self.window_size
        [Zenoo::Native::Window.os_size_w, Zenoo::Native::Window.os_size_h]
      end

      # OS 上のウィンドウ左上位置 `[x, y]` を返す
      #
      # - 戻り値: `Array<Integer>`
      def self.window_position
        [Zenoo::Native::Window.pos_x, Zenoo::Native::Window.pos_y]
      end

      # OS 上のウィンドウ位置を設定する
      #
      # - `x` (`Integer`): スクリーン X 座標
      # - `y` (`Integer`): スクリーン Y 座標
      # - 戻り値: `nil`
      def self.set_window_position(x, y)
        Zenoo::Native::Window.set_window_pos_raw(x.to_i, y.to_i)
      end

      # 論理解像度・実ウィンドウサイズ・スケールモードを指定してウィンドウを初期化する
      #
      # - `w` (`Integer`): 論理（仮想）解像度の幅
      # - `h` (`Integer`): 論理（仮想）解像度の高さ
      # - `title` (`String`): ウィンドウタイトル
      # - `fullscreen` (`Boolean`): フルスクリーン起動するか（デフォルト `false`）
      # - `win_w` (`Integer`): 実ウィンドウ幅（`0` で自動計算）
      # - `win_h` (`Integer`): 実ウィンドウ高さ（`0` で自動計算）
      # - `scale_mode` (`Symbol | Integer`): スケーリングモード（`:fit` / `:integer`）
      # - `scale` (`Float`): 初期倍率（デフォルト `1.0`）
      # - 戻り値: `nil`
      def self.init(w, h, title, fullscreen = false, win_w = 0, win_h = 0, scale_mode = 0, scale = 1.0)
        Zenoo::Native::Window.raw_init_scaled(w.to_i, h.to_i, title.to_s, win_w.to_i, win_h.to_i, fullscreen ? 1 : 0, (scale || 1.0).to_f)
        Zenoo::Native::Window.scale_mode = scale_mode
      end
    end

    # ==========================================
    # 4. Native::Input
    # ※ キーボード・マウス・ゲームパッド・タッチ・テキスト入力・クリップボードの C バインディング
    # ==========================================
    module Input
      native_func :key_pressed?, [:int], :bool, "sp_zen_input_key_pressed"     # キー押下中判定(key_code)
      native_func :key_push?, [:int], :bool, "sp_zen_input_key_push"           # キー押下瞬間判定(key_code)
      native_func :key_release?, [:int], :bool, "sp_zen_input_key_release"     # キー離上瞬間判定(key_code)
      native_func :key_repeat?, [:int], :bool, "sp_zen_input_key_repeat"       # キーリピート含む押下判定(key_code)
      native_func :mouse_pressed?, [:int], :bool, "sp_zen_input_mouse_pressed" # マウスボタン押下中(btn)
      native_func :mouse_push?, [:int], :bool, "sp_zen_input_mouse_push"       # マウスボタン押下瞬間(btn)
      native_func :mouse_release?, [:int], :bool, "sp_zen_input_mouse_release" # マウスボタン離上瞬間(btn)
      native_func :mouse_x, [], :float, "sp_zen_input_mouse_x"                 # マウス X 座標（論理座標）
      native_func :mouse_y, [], :float, "sp_zen_input_mouse_y"                 # マウス Y 座標（論理座標）
      native_func :mouse_wheel_x, [], :float, "sp_zen_input_mouse_wheel_x"     # 水平ホイール量
      native_func :mouse_wheel_y, [], :float, "sp_zen_input_mouse_wheel_y"     # 垂直ホイール量
      native_func :mouse_wheel, [], :float, "sp_zen_input_mouse_wheel_y"       # 垂直ホイール量（mouse_wheel_y と同等）
      native_func :gamepad_connected?, [:int], :bool, "sp_zen_input_gamepad_connected" # ゲームパッド接続状態(pad_id)
      native_func :gamepad_axis, [:int, :int], :float, "sp_zen_input_gamepad_axis"     # アナログ軸値 -1.0..1.0 (pad_id, axis)
      native_func :gamepad_button_pressed?, [:int, :int], :bool, "sp_zen_input_gamepad_button_pressed" # ボタン押下中(pad_id, btn)
      native_func :gamepad_button_push?, [:int, :int], :bool, "sp_zen_input_gamepad_button_push"       # ボタン押下瞬間(pad_id, btn)
      native_func :gamepad_button_release?, [:int, :int], :bool, "sp_zen_input_gamepad_button_release" # ボタン離上瞬間(pad_id, btn)
      native_func :vibrate_gamepad, [:int, :float, :float, :float], :nil, "sp_zen_input_vibrate_gamepad" # ゲームパッド振動(pad_id, strong:0..1, weak:0..1, duration秒)
      native_func :vibrate, [:float], :nil, "sp_zen_input_vibrate"             # デバイス振動(duration秒、スマホブラウザ等)
      native_func :get_char, [], :int, "sp_zen_input_get_char"                 # 入力文字キューから UTF-32 コードポイントを 1 つ取り出す（空なら -1）
      native_func :set_ime_position, [:int, :int], :nil, "sp_zen_input_set_ime_position" # IME 変換候補ウィンドウ位置(x, y)
      native_func :touch_event_count, [], :int, "sp_zen_input_touch_count"     # 蓄積されたタッチイベント数
      native_func :touch_event_id, [:int], :int, "sp_zen_input_touch_event_id"       # タッチ指 ID(event_idx)
      native_func :touch_event_type, [:int], :int, "sp_zen_input_touch_event_type"   # イベント種別(event_idx: 0=down, 1=move, 2=up)
      native_func :touch_event_x, [:int], :float, "sp_zen_input_touch_event_x"       # タッチ X 座標(event_idx)
      native_func :touch_event_y, [:int], :float, "sp_zen_input_touch_event_y"       # タッチ Y 座標(event_idx)
      native_func :touch_clear_events, [], :nil, "sp_zen_input_touch_clear_events"   # タッチイベントキューをクリア

      # 現在のフレームに溜まった文字入力（IME 確定文字含む）を UTF-8 文字列配列としてすべて取り出す
      #
      # - 戻り値: `Array<String>`
      def self.input_chars
        chars = []
        while (cp = Zenoo::Native::Input.get_char) != -1
          begin
            chars << cp.chr(Encoding::UTF_8)
          rescue
          end
        end
        chars
      end

      native_func :clipboard, [], :string, "sp_zen_input_get_clipboard"        # クリップボード文字列取得
      native_func :clipboard=, [:string], :nil, "sp_zen_input_set_clipboard"   # クリップボード文字列設定
    end

    # ==========================================
    # 5. Native::Renderer
    # ※ OpenGL / WebGL2 低レベルドローコール発行の C バインディング
    # ==========================================
    module Renderer
      native_func :flush, [], :nil, "sp_zen_renderer_flush"                    # 保留中の GL コマンドをフラッシュ
      native_func :set_blend_mode, [:int], :nil, "sp_zen_renderer_set_blend_mode" # ブレンドモード設定 (BlendMode 定数)
      native_func :raw_set_scissor, [:int, :int, :int, :int], :nil, "sp_zen_renderer_set_scissor" # 内部用: シザー矩形設定(x, y, w, h)
      native_func :reset_scissor, [], :nil, "sp_zen_renderer_reset_scissor"    # シザーテストを無効化して全画面に戻す
      native_func :raw_draw_buffer, [
        :int, :string, :string, :int, :string, :int, :any, :any
      ], :nil, "sp_zen_renderer_draw_buffer"                                   # 内部用: 動的バッファ描画
      native_func :raw_draw_mesh, [
        :any, :any, :string, :string, :int, :any, :any
      ], :nil, "sp_zen_renderer_draw_mesh"                                     # 内部用: Mesh / インスタンス描画

      # OpenGL シザーテスト矩形を設定する
      #
      # - `x` (`Integer`): 左端 X 座標
      # - `y` (`Integer`): 上端 Y 座標
      # - `w` (`Integer`): 切り抜き幅
      # - `h` (`Integer`): 切り抜き高さ
      # - 戻り値: `nil`
      def self.set_scissor(x, y, w, h)
        Zenoo::Native::Renderer.raw_set_scissor(x.to_i, y.to_i, w.to_i, h.to_i)
      end

      # 動的頂点／インスタンスバッファを用いてプリミティブを描画する（`Backend` から呼び出し）
      #
      # - `topology` (`Integer`): `Backend::Topology` 定数
      # - `layout` (`String`): `Backend::Layout` 属性長バイナリ列
      # - `divisors` (`String`): `Backend::Divisor` 属性 Divisor バイナリ列
      # - `base_vertex_count` (`Integer`): インスタンス描画時のベース頂点数（非インスタンス時は `0`）
      # - `data` (`String`): パック済み頂点／インスタンスデータ文字列
      # - `count` (`Integer`): 頂点数またはインスタンス数
      # - `img` (`Image | nil`): バインドするテクスチャ画像
      # - `sh` (`NativeShader | nil`): 使用するシェーダー
      # - 戻り値: `nil`
      def self.draw_buffer(topology, layout, divisors, base_vertex_count, data, count, img, sh)
        Zenoo::Native::Renderer.raw_draw_buffer(
          topology.to_i,
          layout.to_s,
          divisors.to_s,
          base_vertex_count.to_i,
          data.to_s,
          count.to_i,
          img,
          sh
        )
      end

      # VRAM 常駐 `Native::Mesh` またはインスタンスバッファを用いて描画する（`Backend` から呼び出し）
      #
      # - `geom_mesh` (`Native::Mesh | nil`): ベース形状メッシュ（`nil` で 4 頂点ビルボード）
      # - `inst_buffer` (`Native::Mesh | nil`): VRAM 常駐インスタンスバッファ
      # - `inst_layout` (`String | nil`): 動的インスタンスデータの属性レイアウト列
      # - `inst_data` (`String | nil`): 動的インスタンスバイナリデータ
      # - `inst_count` (`Integer`): 頂点数またはインスタンス数
      # - `img` (`Image | nil`): バインドするテクスチャ画像
      # - `sh` (`NativeShader | nil`): 使用するシェーダー
      # - 戻り値: `nil`
      def self.draw_mesh(geom_mesh, inst_buffer, inst_layout, inst_data, inst_count, img, sh)
        Zenoo::Native::Renderer.raw_draw_mesh(
          geom_mesh,
          inst_buffer,
          inst_layout ? inst_layout.to_s : "",
          inst_data ? inst_data.to_s : "",
          inst_count.to_i,
          img,
          sh
        )
      end
    end
    # ==========================================
    # 6. Native::Image
    # ※ レンダーターゲット制御・特殊フォーマット生成などの内部向け C バインディング
    # ==========================================
    module Image
      native_func :reset_render_target, [], :nil, "sp_ZenImage_reset_render_target" # 描画先をウィンドウバックバッファへ戻す
      native_func :free_count, [], :int, "sp_zen_get_image_free_count"               # GC で解放された Image 総数（リークテスト／プロファイル用）

      # ライブラリ内部専用の内部フォーマット指定 `Image` を生成する
      #
      # - `w` (`Integer`): 幅（ピクセル）
      # - `h` (`Integer`): 高さ（ピクセル）
      # - `format` (`Integer`): 内部フォーマット定数（`1`: R8 等）
      # - 戻り値: `Image`
      def self.create_format(w, h, format)
        Zenoo::Image.new(w.to_i, h.to_i, -1, format.to_i)
      end

      # R8（1 チャンネル 8bit）フォーマットの `Image` を生成する（フォントアトラス用）
      #
      # - `w` (`Integer`): 幅（ピクセル）
      # - `h` (`Integer`): 高さ（ピクセル）
      # - 戻り値: `Image`
      def self.create_r8(w, h)
        create_format(w, h, 1)
      end

      # MSAA 有効なレンダーターゲット用 `Image` を生成する
      #
      # - `w` (`Integer`): 幅（ピクセル）
      # - `h` (`Integer`): 高さ（ピクセル）
      # - `samples` (`Integer`): MSAA サンプル数（デフォルト `4`）
      # - 戻り値: `Image`
      def self.create_msaa(w, h, samples = 4)
        Zenoo::Image.new(w.to_i, h.to_i, samples.to_i)
      end
    end

    # ==========================================
    # 7. Native::FontHelper
    # ※ 直前の Native::Font#query_glyph で問い合わせた 1 グリフ分の情報を取り出す一時バッファ群
    # ==========================================
    module FontHelper
      native_func :glyph_visible, [], :bool,  "sp_zen_font_glyph_visible"     # 描画可能な実体を持つか（空白文字等は false）
      native_func :glyph_u0,      [], :float, "sp_zen_font_glyph_u0"          # アトラス内 UV 左端
      native_func :glyph_v0,      [], :float, "sp_zen_font_glyph_v0"          # アトラス内 UV 上端
      native_func :glyph_u1,      [], :float, "sp_zen_font_glyph_u1"          # アトラス内 UV 右端
      native_func :glyph_v1,      [], :float, "sp_zen_font_glyph_v1"          # アトラス内 UV 下端
      native_func :glyph_x0,      [], :float, "sp_zen_font_glyph_x0"          # ベースライン基準の左オフセット (px)
      native_func :glyph_y0,      [], :float, "sp_zen_font_glyph_y0"          # ベースライン基準の上オフセット (px)
      native_func :glyph_x1,      [], :float, "sp_zen_font_glyph_x1"          # ベースライン基準の右オフセット (px)
      native_func :glyph_y1,      [], :float, "sp_zen_font_glyph_y1"          # ベースライン基準の下オフセット (px)
      native_func :glyph_advance,   [], :float, "sp_zen_font_glyph_advance"   # 次の文字への水平送り幅 (px)
      native_func :glyph_is_bitmap, [], :bool,  "sp_zen_font_glyph_is_bitmap" # カラー絵文字等のビットマップグリフか
      native_func :set_atlas_image, [:any], :nil, "sp_zen_font_set_atlas_image" # 共有フォントアトラス Image を C 側へ登録
    end

    # ==========================================
    # 8. Native::Audio
    # ※ miniaudio オーディオデバイス全体の初期化・終了・マスター音量制御
    # ==========================================
    module Audio
      native_func :init, [], :bool, "sp_zen_audio_init"                       # オーディオデバイス初期化
      native_func :shutdown, [], :nil, "sp_zen_audio_shutdown"                # オーディオデバイス終了
      native_func :master_volume=, [:float], :nil, "sp_zen_audio_set_master_volume" # マスター音量設定 (0.0..1.0)
      native_func :master_volume, [], :float, "sp_zen_audio_get_master_volume"      # マスター音量取得 (0.0..1.0)
    end

    # ==========================================
    # 10. Native::Browser
    # ※ Wasm (Emscripten) 実行時の JS eval とセーフエリア取得ブリッジ（非 Wasm 環境ではダミー返却）
    # ==========================================
    module Browser
      native_func :raw_eval, [:string], :nil, "sp_zen_browser_eval"           # 内部用: JS 文字列を実行
      native_func :raw_eval_num, [:string], :float, "sp_zen_browser_eval_num" # 内部用: JS 式を評価して数値を返す
      native_func :raw_eval_str, [:string], :string, "sp_zen_browser_eval_str" # 内部用: JS 式を評価して文字列を返す
      native_func :visible?, [], :bool, "sp_zen_browser_is_visible"           # ブラウザタブが可視状態か
      native_func :raw_safe_area_left, [], :float, "sp_zen_browser_safe_area_left"     # 左セーフエリア幅
      native_func :raw_safe_area_top, [], :float, "sp_zen_browser_safe_area_top"       # 上セーフエリア幅
      native_func :raw_safe_area_right, [], :float, "sp_zen_browser_safe_area_right"   # 右セーフエリア幅
      native_func :raw_safe_area_bottom, [], :float, "sp_zen_browser_safe_area_bottom" # 下セーフエリア幅
    end
  end

  # ==========================================
  # 8. Native::Font (Spinel native_struct)
  # ※ stb_truetype 等を用いたネイティブフォント読み込み・メトリクス・グリフ問い合わせ
  # ==========================================
  native_struct "Zenoo::Native::Font", "sp_ZenFont", "sp_ZenFont_free"
  native_new [:string, :int], "sp_ZenFont_load"                               # フォント読込: new(path, ttc_index)
  native_method :metrics_ascent,   [:float], :float, "sp_zen_font_metrics_ascent"   # アセント取得(size_px)
  native_method :metrics_descent,  [:float], :float, "sp_zen_font_metrics_descent"  # ディセント取得(size_px)
  native_method :metrics_line_gap, [:float], :float, "sp_zen_font_metrics_line_gap" # 行間取得(size_px)
  native_method :query_glyph,      [:int, :float], :bool, "sp_zen_font_query_glyph" # グリフ生成＆FontHelper へ結果格納(codepoint, size_px)

  # ==========================================
  # 9. Native::Sound (Spinel native_struct)
  # ※ miniaudio デコード・ストリーミング・PCM バッファ再生バインディング（Ruby側APIは lib/zenoo/sound.rb を参照）
  # ==========================================
  native_struct "Zenoo::Native::Sound", "sp_ZenSound", "sp_ZenSound_free"
  native_new [:string], "sp_ZenSound_load"                                    # メモリ全読込生成: new(path)
  native_new [:string, :bool], "sp_ZenSound_load_stream"                      # ストリーミング対応生成: new(path, stream_bool)
  native_new [:string, :int, :int, :int], "sp_ZenSound_load_pcm"              # PCM バイナリ生成: new(pcm_bin, frames, channels, sample_rate)
  native_method :play, [], :nil, "sp_ZenSound_play"                           # 再生開始／再開
  native_method :stop, [], :nil, "sp_ZenSound_stop"                           # 停止して先頭へ戻す
  native_method :pause, [], :nil, "sp_ZenSound_pause"                         # 現在位置で一時停止
  native_method :playing?, [], :bool, "sp_ZenSound_is_playing"                # 再生中かどうか
  native_method :volume=, [:float], :nil, "sp_ZenSound_set_volume"            # 音量設定 (0.0..1.0+)
  native_method :volume, [], :float, "sp_ZenSound_get_volume"                 # 音量取得
  native_method :looping=, [:bool], :nil, "sp_ZenSound_set_looping"           # ループ再生有効／無効
  native_method :looping?, [], :bool, "sp_ZenSound_is_looping"                # ループ再生有効か
  native_method :pitch=, [:float], :nil, "sp_ZenSound_set_pitch"              # ピッチ・再生速度倍率 (1.0=等速)
  native_method :pitch, [], :float, "sp_ZenSound_get_pitch"                   # ピッチ倍率取得
  native_method :pan=, [:float], :nil, "sp_ZenSound_set_pan"                  # パン設定 (-1.0=左 .. 0.0=中央 .. 1.0=右)
  native_method :pan, [], :float, "sp_ZenSound_get_pan"                       # パン取得
  native_method :seek, [:float], :nil, "sp_ZenSound_seek"                     # 再生位置移動(秒)
  native_method :cursor, [], :float, "sp_ZenSound_get_cursor"                 # 現在再生位置(秒)
  native_method :time, [], :float, "sp_ZenSound_get_cursor"                   # 現在再生位置(秒)
  native_method :time=, [:float], :nil, "sp_ZenSound_seek"                    # 再生位置移動(秒)
  native_method :length, [], :float, "sp_ZenSound_get_length"                 # 総再生時間(秒)
  native_method :sample_rate, [], :int, "sp_ZenSound_get_sample_rate"         # サンプルレート (Hz)
  native_method :length_pcm, [], :int, "sp_ZenSound_get_length_pcm"           # 総 PCM フレーム数
  native_method :set_loop_points_pcm, [:int, :int], :nil, "sp_ZenSound_set_loop_points_pcm"       # ループ区間設定(start_pcm, end_pcm)
  native_method :set_loop_points, [:float, :float], :nil, "sp_ZenSound_set_loop_points_seconds"   # ループ区間設定(start_sec, end_sec)
  native_method :loop_start, [], :float, "sp_ZenSound_get_loop_start"         # ループ開始位置(秒)
  native_method :loop_start=, [:float], :nil, "sp_ZenSound_set_loop_start"    # ループ開始位置設定(秒)
  native_method :loop_end, [], :float, "sp_ZenSound_get_loop_end"             # ループ終了位置(秒)
  native_method :loop_end=, [:float], :nil, "sp_ZenSound_set_loop_end"        # ループ終了位置設定(秒)
  native_method :loop_start_pcm, [], :int, "sp_ZenSound_get_loop_start_pcm"   # ループ開始位置(PCM フレーム)
  native_method :loop_start_pcm=, [:int], :nil, "sp_ZenSound_set_loop_start_pcm" # ループ開始位置設定(PCM フレーム)
  native_method :loop_end_pcm, [], :int, "sp_ZenSound_get_loop_end_pcm"       # ループ終了位置(PCM フレーム)
  native_method :loop_end_pcm=, [:int], :nil, "sp_ZenSound_set_loop_end_pcm"  # ループ終了位置設定(PCM フレーム)
  native_method :has_loop_points?, [], :bool, "sp_ZenSound_has_loop_points"   # ループ区間が設定済みか
  native_method :clear_loop_points, [], :nil, "sp_ZenSound_clear_loop_points" # ループ区間を解除
end

class Zenoo::Image
  # 描画先レンダーターゲットをデフォルトのウィンドウバックバッファに戻します。
  # 通常は `Image.render_to` ブロック終了時に自動で呼ばれるため、明示的な呼び出しは不要です。
  def self.reset_render_target
    Zenoo::Native::Image.reset_render_target
  end

  # ファイルから画像を読み込んで新しい `Image` インスタンスを生成します。
  # PNG / JPG / BMP / TGA 等に対応しています。
  #
  # - `path` (`String`): 読み込む画像ファイルのパス
  # - 戻り値: `Image`
  def self.load(path)
    new(path)
  end

  # マルチサンプルアンチエイリアス（MSAA）有効なオフスクリーン描画用 `Image` を生成します。
  #
  # - `w` (`Integer`): 画像の幅（ピクセル単位）
  # - `h` (`Integer`): 画像の高さ（ピクセル単位）
  # - `samples` (`Integer`): MSAA サンプル数（デフォルト: 4）
  # - 戻り値: `Image`
  def self.create_msaa(w, h, samples = 4)
    new(w.to_i, h.to_i, samples.to_i)
  end
end

# 内部用: ネイティブシェーダーラッパー拡張
class Zenoo::Native::NativeShader
  # 配列またはパック済みバイナリ文字列として `vec4` 配列 uniform を転送する
  #
  # - `name` (`String | Symbol`): GLSL uniform 変数名
  # - `data` (`Array<Float> | String`): 4 要素単位の数値配列、または float32 パック済みバイナリ文字列
  # - 戻り値: `nil`
  def set_vec4_array(name, data)
    str = data.is_a?(Array) ? data.pack("f*") : data.to_s
    count = str.bytesize / 16
    raw_set_vec4_array(name.to_s, count, str) if count > 0
  end
end

# 内部用: ネイティブメッシュラッパー拡張 (`Zenoo::Mesh` から委譲される)
class Zenoo::Native::Mesh
  # `Zenoo::Mesh.canvas` への委譲ショートカット
  #
  # - 戻り値: `Zenoo::Mesh`
  def self.canvas(*args, &block)
    Zenoo::Mesh.canvas(*args, &block)
  end

  # `Zenoo::Mesh.grid` への委譲ショートカット
  #
  # - 戻り値: `Zenoo::Mesh`
  def self.grid(*args, &block)
    Zenoo::Mesh.grid(*args, &block)
  end

  # パック済み頂点データをネイティブ側（GPU VBO）へ転送する
  #
  # - `vdata` (`String`): float32 パック済み頂点／インスタンスバイナリデータ
  # - `offset` (`Integer`): 書き込み開始位置（頂点／インスタンス単位オフセット、デフォルト `0`）
  # - `vcount` (`Integer`): 更新する頂点数／インスタンス数（デフォルト `0`）
  # - 戻り値: `nil`
  def update_vertices(vdata, offset = 0, vcount = 0)
    s = vdata.to_s
    raw_update_vertices(s, s.bytesize, offset.to_i, vcount.to_i)
  end

  # パック済みインデックスデータをネイティブ側（GPU IBO）へ転送する
  #
  # - `idata` (`String | nil`): uint32 パック済みインデックスバイナリデータ
  # - `icount` (`Integer`): インデックス数（`0` 以下の場合は `idata.bytesize / 4` から自動計算）
  # - 戻り値: `nil`
  def update_indices(idata, icount = 0)
    s = idata ? idata.to_s : ""
    cnt = icount.to_i > 0 ? icount.to_i : (s.bytesize / 4)
    raw_update_indices(s, cnt)
  end
end

# 内部用: ネイティブフォントラッパー拡張 (`Zenoo::Font` が使用)
class Zenoo::Native::Font
  # フォントファイルを読み込んで `Native::Font` インスタンスを生成する
  #
  # - `path` (`String`): フォントファイルパス（`.ttf`, `.otf`, `.ttc`）
  # - `index` (`Integer`): TTC コレクション内のフォントインデックス（デフォルト `0`）
  # - 戻り値: `Native::Font`
  def self.load(path, index = 0)
    new(path.to_s, index.to_i)
  end

  # `Zenoo::Font` が共有するフォントアトラス `Image` を返す
  #
  # - 戻り値: `Image`
  def self.atlas_image
    Zenoo::Font.atlas_image
  end

  # 指定フォントサイズでのメトリクス `[ascent, descent, line_gap]` を取得する
  #
  # - `size` (`Float`): フォントサイズ（ピクセル）
  # - 戻り値: `Array<Float>`
  def metrics(size)
    s = size.to_f
    [self.metrics_ascent(s), self.metrics_descent(s), self.metrics_line_gap(s)]
  end

  # 1 文字分のグリフ情報配列を取得する（見つからない／生成失敗時は `nil`）
  #
  # - `cp` (`Integer`): Unicode コードポイント
  # - `size` (`Float`): フォントサイズ（ピクセル）
  # - 戻り値: `Array | nil`（`[visible, u0, v0, u1, v1, x0, y0, x1, y1, advance, is_bitmap]`）
  def get_glyph(cp, size)
    ok = self.query_glyph(cp.to_i, size.to_f)
    return nil unless ok

    [
      Zenoo::Native::FontHelper.glyph_visible,
      Zenoo::Native::FontHelper.glyph_u0,
      Zenoo::Native::FontHelper.glyph_v0,
      Zenoo::Native::FontHelper.glyph_u1,
      Zenoo::Native::FontHelper.glyph_v1,
      Zenoo::Native::FontHelper.glyph_x0,
      Zenoo::Native::FontHelper.glyph_y0,
      Zenoo::Native::FontHelper.glyph_x1,
      Zenoo::Native::FontHelper.glyph_y1,
      Zenoo::Native::FontHelper.glyph_advance,
      Zenoo::Native::FontHelper.glyph_is_bitmap
    ]
  end
end

# 内部用: ネイティブサウンドラッパー拡張 (`Zenoo::Sound` が使用)
class Zenoo::Native::Sound
  # 音声ファイルを読み込んで `Native::Sound` インスタンスを生成する
  #
  # - `path` (`String`): 音声ファイルパス（`.wav`, `.ogg`, `.mp3`, `.flac`）
  # - `stream` (`Boolean`): ストリーミング再生にするか（`true` でデコードしつつ再生、デフォルト `false`）
  # - 戻り値: `Native::Sound`
  def self.load(path, stream = false)
    if stream
      new(path.to_s, true)
    else
      new(path.to_s)
    end
  end

  # メモリ上の Float32 インターリーブ PCM バイナリから `Native::Sound` を生成する
  #
  # - `samples_binary` (`String`): 32bit Float PCM サンプル列バイナリ
  # - `channels` (`Integer`): チャンネル数（`1`: モノラル、`2`: ステレオ等）
  # - `sample_rate` (`Integer`): サンプルレート (Hz)
  # - 戻り値: `Native::Sound`
  def self.load_pcm(samples_binary, channels, sample_rate)
    bytes = samples_binary.bytesize
    frame_count = bytes / 4 / channels
    new(samples_binary, frame_count, channels, sample_rate)
  end
end


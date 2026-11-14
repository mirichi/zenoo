module Zenoo
  # ウィンドウの生成・メインループ・2D 描画・カメラ・クリッピングを統括するモジュール。
  # `Window.loop` でゲームループを開始し、ブロック内で `Window.draw` や `Window.draw_rect` 等の描画 API を呼び出します。
  module Window
    # 現在の描画先レンダーターゲットを取得します（ウィンドウ画面の場合は `nil`、オフスクリーン描画中は `Image`）。
    #
    # - 戻り値: `Image`, `nil`
    def self.current_target
      Backend.current_target
    end

    # 現在の描画先レンダーターゲットを設定します（通常は `Image.render_to` により自動管理されます）。
    #
    # - `target` (`Image`, `nil`): 描画先 `Image`（`nil` でメイン画面に戻す）
    def self.current_target=(target)
      Backend.current_target = target
    end

    @bg_color = (18 << 24) | (20 << 16) | (30 << 8) | 255
    @game_time = 0.0
    @main_loop_block = nil
    @step_proc = nil
    @fps = 60.0
    @fps_frames = 0
    @fps_accum = 0.0
    @auto_pause = true
    @paused = false
    @pause_handlers = []
    @resume_handlers = []

    class << self
      # Web (Wasm) 環境等でブラウザタブが非表示になった際に、ゲームループと音声を自動一時停止するかどうかを設定します（デフォルト: `true`）。
      #
      # - `val` (`Boolean`): `true` で自動ポーズ有効、`false` で無効
      def auto_pause=(val)
        @auto_pause = !!val
        if Native::Window.wasm?
          Browser.eval(@auto_pause ? "window.__zen_auto_pause = true;" : "window.__zen_auto_pause = false;")
        end
      end

      # バックグラウンド移行時の自動一時停止が有効かどうかを返します。
      #
      # - 戻り値: `Boolean`
      def auto_pause
        @auto_pause
      end

      # 自動ポーズによりゲームが一時停止中かどうかを返します。
      #
      # - 戻り値: `Boolean`
      def paused?
        @paused || false
      end

      # バックグラウンド移行（タブ非表示）時ハンドラー登録
      #
      # - `&block`: 一時停止時に呼び出されるコールバックブロック
      def on_pause(&block)
        @pause_handlers << block if block
      end

      # フォアグラウンド復帰時ハンドラー登録
      #
      # - `&block`: 再開時に呼び出されるコールバックブロック
      def on_resume(&block)
        @resume_handlers << block if block
      end

      # セーフエリアインセット [left, top, right, bottom] (仮想解像度px)
      #
      # - 戻り値: `Array<Float>` `[left, top, right, bottom]`
      def safe_area
        Browser.safe_area
      end

      # 安全表示領域の矩形 [x, y, w, h] (仮想解像度px)
      #
      # - 戻り値: `Array<Float>` `[x, y, width, height]`
      def safe_area_rect
        Browser.safe_area_rect
      end

      # ブラウザ可視性変更イベントの登録 (Wasm実行時、RubyからBrowserモジュール経由で登録)
      def __setup_wasm_visibility_listener
        Browser.eval(
          "if (!window.__zen_visibility_installed) {" \
          "  window.__zen_visibility_installed = true;" \
          "  window.__zen_auto_pause = true;" \
          "  var updateAudio = function(hidden) {" \
          "    if (window.__zen_auto_pause && window.miniaudio && window.miniaudio.devices) {" \
          "      for (var i = 0; i < window.miniaudio.devices.length; i++) {" \
          "        var dev = window.miniaudio.devices[i];" \
          "        if (!dev || !dev.webaudio) continue;" \
          "        if (hidden) {" \
          "          if (dev.webaudio.state === 'running') {" \
          "            dev.webaudio.suspend();" \
          "            dev.__zen_suspended = true;" \
          "          }" \
          "        } else {" \
          "          if (dev.__zen_suspended) {" \
          "            dev.webaudio.resume();" \
          "            dev.__zen_suspended = false;" \
          "          }" \
          "        }" \
          "      }" \
          "    }" \
          "  };" \
          "  document.addEventListener('visibilitychange', function() {" \
          "    var hidden = (document.visibilityState === 'hidden') || document.hidden;" \
          "    updateAudio(hidden);" \
          "  });" \
          "  window.addEventListener('pagehide', function() {" \
          "    updateAudio(true);" \
          "  });" \
          "}"
        )
      end
    end

    # DXRuby風メインループ (scale: nil の場合はモニターのDPIスケールを自動検出)
    # ウィンドウを生成して毎フレーム `&block` を実行し、終了時まで制御を保ちます。
    #
    # - `width` (`Integer`): 論理（仮想）解像度の幅（デフォルト: 1280）
    # - `height` (`Integer`): 論理（仮想）解像度の高さ（デフォルト: 720）
    # - `title` (`String`): ウィンドウタイトル文字列（デフォルト: `"Zenoo"`）
    # - `scale:` (`Numeric`, `nil`): 初期ウィンドウ拡大率（`nil` の場合は環境に応じて 1.0 等で自動初期化）
    # - `scale_mode:` (`Symbol`): ウィンドウリサイズ時のスケーリング方式（`:fit`, `:fill`, `:stretch`, `:pixel`, `:crop` 等、デフォルト: `:fit`）
    # - `window_width:` (`Integer`, `nil`): 実ウィンドウ幅を直接指定（`nil` の場合は `width * scale`）
    # - `window_height:` (`Integer`, `nil`): 実ウィンドウ高さを直接指定（`nil` の場合は `height * scale`）
    # - `fullscreen:` (`Boolean`): フルスクリーン起動するかどうか（デフォルト: `false`）
    # - `vsync:` (`Boolean`): 垂直同期（VSync）を有効にするかどうか（デフォルト: `false`）
    # - `msaa:` (`Integer`, `Boolean`, `nil`): マルチサンプルアンチエイリアスのサンプル数（`nil` で変更なし、`true` で 4、整数で指定数）
    # - `fps:` (`Integer`): 目標フレームレート（0 以下で無制限、デフォルト: 60）
    # - `&block`: 毎フレーム呼び出される更新・描画処理ブロック
    def self.loop(width = 1280, height = 720, title = "Zenoo", scale: nil, scale_mode: :fit, window_width: nil, window_height: nil, fullscreen: false, vsync: false, msaa: nil, fps: 60, &block)
      self.msaa = msaa unless msaa.nil?
      win_w = window_width ? window_width.to_i : 0
      win_h = window_height ? window_height.to_i : 0
      init_scale = scale ? scale.to_f : 1.0
      Native::Window.init(width, height, title, fullscreen, win_w, win_h, scale_mode, init_scale)
      Native::Window.scale_mode = scale_mode
      Native::Window.vsync = (vsync ? 1 : 0)
      self.target_fps = fps
      Font.atlas_image

      @main_loop_block = block

      if Native::Window.wasm?
        __setup_wasm_visibility_listener
        @step_proc = proc { __step_frame }
        Native::Window.start_wasm_loop(@step_proc)
      else
        while Native::Window.update
          __step_frame
        end
        Native::Window.shutdown
      end
    end

    def self.__update_step
      # ブラウザの可視状態チェック (タブ非表示時の自動ポーズ＆BGM停止)
      if @auto_pause && Native::Window.wasm?
        is_visible = Browser.visible?
        if !is_visible && !@paused
          @paused = true
          Audio.pause_all
          i = 0
          while i < @pause_handlers.length
            @pause_handlers[i].call
            i += 1
          end
          return
        elsif is_visible && @paused
          @paused = false
          Audio.resume_all
          i = 0
          while i < @resume_handlers.length
            @resume_handlers[i].call
            i += 1
          end
        elsif !is_visible
          return # ポーズ中はゲーム内ロジックを進行させない
        end
      end

      Audio.update(delta_time)
      Tween.__update_step(delta_time)
      Input.__begin_frame
      ImGui.begin_frame
      UI.begin_frame
      Input.__update_virtual_pad
      @main_loop_block.call if @main_loop_block
      Input.__draw_virtual_pad
      UI.end_frame
      ImGui.end_frame
      Input.__update_step
    end

    def self.__draw_step
      if Profiler.enabled
        Profiler.measure(:draw) do
          Backend.flush_screen
          Backend.clear_clips
          @offset_x = 0.0
          @offset_y = 0.0
          Native::Renderer.reset_scissor
        end
      else
        Backend.flush_screen
        Backend.clear_clips
        @offset_x = 0.0
        @offset_y = 0.0
        Native::Renderer.reset_scissor
      end
    end

    def self.__step_frame
      __update_fps
      Backend.reset_frame
      Backend.current_target = nil
      Native::Image.reset_render_target
      __update_step
      __draw_step
      Profiler.end_frame
      Backend.current_target = nil
      Native::Image.reset_render_target
    end

    # OSの実経過時間 (秒)
    #
    # - 戻り値: `Float` アプリ起動からの経過時間（秒）
    def self.real_time
      Native::Window.time
    end

    # フレーム開始時の背景クリア色を 32bit RGBA 整数値として取得します。
    #
    # - 戻り値: `Integer` パック済み RGBA 値
    def self.bg_color
      @bg_color
    end

    # フレーム開始時の背景クリア色を設定します。
    #
    # - `val` (`Color`, `Symbol`, `Array<Integer>`, `Integer`): 背景色（RGBA 0 〜 255、色名シンボル等）
    def self.bg_color=(val)
      @bg_color = Backend.color_to_uint32(val)
    end

    # 画面またはレンダーターゲットのクリア (引数省略時: 画面は背景色、Imageは透明色)
    #
    # - `color` (`Color`, `Symbol`, `Array<Integer>`, `nil`): クリア色（省略時は描画先に応じたデフォルト色）
    def self.clear(color = nil)
      Backend.enqueue_clear(color)
    end

    # 論理（仮想）解像度の幅（ピクセル単位）を返します。
    #
    # - 戻り値: `Integer`
    def self.width
      Native::Window.size_w
    end

    # 論理（仮想）解像度の高さ（ピクセル単位）を返します。
    #
    # - 戻り値: `Integer`
    def self.height
      Native::Window.size_h
    end

    # 論理（仮想）解像度のサイズ `[width, height]` を返します。
    #
    # - 戻り値: `Array<Integer>` `[width, height]`
    def self.size
      [Native::Window.size_w, Native::Window.size_h]
    end

    # 論理解像度に対するウィンドウの拡大倍率を取得します。
    #
    # - 戻り値: `Float`
    def self.scale
      Native::Window.window_scale
    end

    # 論理解像度に対するウィンドウの拡大倍率を設定してウィンドウサイズを変更します。
    #
    # - `val` (`Numeric`): 拡大倍率（例: `2.0`）
    def self.scale=(val)
      Native::Window.window_scale = val.to_f
    end

    # 現在の実ビューポートにおける論理座標からのスケーリング倍率を返します。
    #
    # - 戻り値: `Float`
    def self.viewport_scale
      Native::Window.scale
    end

    # モニターの DPI スケール倍率を返します。
    #
    # - 戻り値: `Float`
    def self.dpi_scale
      Native::Window.dpi_scale
    end

    # 現在のスケーリングモード（`:fit`, `:fill`, `:stretch`, `:pixel`, `:crop` 等）を返します。
    #
    # - 戻り値: `Symbol`
    def self.scale_mode
      Native::Window.scale_mode
    end

    # ウィンドウリサイズ時のスケーリングモードを設定します。
    #
    # - `val` (`Symbol`): スケーリングモード（`:fit`, `:fill`, `:stretch`, `:pixel`, `:crop` 等）
    def self.scale_mode=(val)
      Native::Window.scale_mode = val
    end

    # OS 上の実際のウィンドウサイズ `[width, height]` を取得します。
    #
    # - 戻り値: `Array<Integer>` `[window_width, window_height]`
    def self.window_size
      Native::Window.window_size
    end

    # OS 上の実際のウィンドウサイズを設定します。
    #
    # - `size` (`Array<Integer>`): `[width, height]` 形式のウィンドウサイズ
    def self.window_size=(size)
      Native::Window.set_window_size(size[0].to_i, size[1].to_i)
    end

    # 現在のウィンドウタイトル文字列を取得します。
    #
    # - 戻り値: `String`
    def self.title
      Native::Window.title
    end

    # ウィンドウのタイトルバーに表示する文字列を設定します。
    #
    # - `val` (`String`): 新しいタイトル文字列
    def self.title=(val)
      Native::Window.title = val.to_s
      val
    end

    # デスクトップ上のウィンドウ左上座標 `[x, y]` を取得します。
    #
    # - 戻り値: `Array<Integer>` `[x, y]`
    def self.window_position
      Native::Window.window_position
    end

    # デスクトップ上のウィンドウ左上座標を設定します。
    #
    # - `pos` (`Array<Integer>`): `[x, y]` 形式の座標
    def self.window_position=(pos)
      if pos.is_a?(Array) && pos.length >= 2
        Native::Window.set_window_position(pos[0].to_i, pos[1].to_i)
      end
    end

    # ウィンドウが現在フォーカス（入力フォーカス）を持っているかどうかを返します。
    #
    # - 戻り値: `Boolean`
    def self.focused?
      Native::Window.focused?
    end

    # ウィンドウが最小化（アイコン化）されているかどうかを返します。
    #
    # - 戻り値: `Boolean`
    def self.minimized?
      Native::Window.minimized?
    end

    # ウィンドウが最大化されているかどうかを返します。
    #
    # - 戻り値: `Boolean`
    def self.maximized?
      Native::Window.maximized?
    end

    # マウスカーソルがウィンドウのクライアント領域上にあるかどうかを返します。
    #
    # - 戻り値: `Boolean`
    def self.hovered?
      Native::Window.hovered?
    end

    # 直前フレームからの経過時間（秒単位）を返します。
    #
    # - 戻り値: `Float`
    def self.delta_time
      Native::Window.delta_time
    end

    # 実測された現在のフレームレート（FPS）を返します。
    #
    # - 戻り値: `Float`
    def self.fps
      @fps || 60.0
    end

    # 目標フレームレート（FPS）を設定します（`0` または `nil` で上限解除）。
    #
    # - `val` (`Integer`, `nil`): 目標 FPS（デフォルト: 60）
    def self.target_fps=(val)
      t = (val.nil? || val.to_i <= 0) ? 0 : val.to_i
      Native::Window.target_fps = t
    end

    # 現在設定されている目標フレームレート（FPS）を返します。
    #
    # - 戻り値: `Integer`（`0` は無制限）
    def self.target_fps
      Native::Window.target_fps
    end

    def self.__update_fps
      dt = delta_time
      return if dt <= 0.0 || dt > 1.0
      @fps_frames = (@fps_frames || 0) + 1
      @fps_accum = (@fps_accum || 0.0) + dt
      if @fps_accum >= 0.25
        measured = @fps_frames.to_f / @fps_accum
        current = @fps || 60.0
        @fps = current * 0.2 + measured * 0.8
        @fps_frames = 0
        @fps_accum = 0.0
      end
    end

    # 垂直同期（VSync）の有効・無効を切り替えます。
    #
    # - `val` (`Boolean`): `true` で VSync 有効、`false` で無効
    def self.vsync=(val)
      Native::Window.vsync = (val ? 1 : 0)
    end

    # メイン画面の MSAA（マルチサンプルアンチエイリアス）サンプル数を返します。
    #
    # - 戻り値: `Integer`（`0` は無効）
    def self.msaa
      Native::Window.msaa_samples
    end

    # メイン画面の MSAA サンプル数を設定します（通常は `Window.loop` の `msaa:` 引数で起動前に指定します）。
    #
    # - `val` (`Integer`, `Boolean`, `nil`): サンプル数（`true` で 4、`false`/`nil`/`0` で無効）
    def self.msaa=(val)
      samples = val ? (val.is_a?(Integer) ? val : 4) : 0
      Native::Window.msaa_samples = samples
    end

    # `Window.cursor=` で指定可能な標準マウスカーソル形状の定義マップ
    CURSOR_SHAPES = {
      arrow: 0,
      ibeam: 1,
      crosshair: 2,
      hand: 3,
      hresize: 4,
      vresize: 5,
      resize_nwse: 6,
      resize_nesw: 7,
      resize_all: 8,
      not_allowed: 9
    }.freeze

    # マウスカーソルの表示・非表示を設定します。
    #
    # - `val` (`Boolean`): `true` で表示、`false` で非表示
    def self.cursor_visible=(val)
      Native::Window.show_cursor(!!val)
    end

    # 現在設定されているマウスカーソル形状を返します。
    #
    # - 戻り値: `Symbol`, `Integer`
    def self.cursor
      @current_cursor_shape || :arrow
    end

    # マウスカーソルの形状を変更します。
    #
    # - `shape` (`Symbol`, `Integer`): `CURSOR_SHAPES` のキー（`:arrow`, `:ibeam`, `:crosshair`, `:hand`, `:hresize`, `:vresize`, `:resize_nwse`, `:resize_nesw`, `:resize_all`, `:not_allowed`）または形状 ID
    def self.cursor=(shape)
      @current_cursor_shape = shape
      shape_id = CURSOR_SHAPES[shape] || (shape.is_a?(Integer) ? shape : 0)
      Native::Window.set_cursor(shape_id)
    end

    @card_shader = nil
    @default_sprite_shader = nil
    @flat_primitive_shader = nil
    @gradient_primitive_shader = nil

    # デフォルトのスプライト描画用シェーダーを取得します。
    #
    # - 戻り値: `Shader`
    def self.default_sprite_shader
      @default_sprite_shader ||= Shader.new(Shaders::DEFAULT_SPRITE_VERTEX, Shaders::DEFAULT_SPRITE_FRAGMENT)
    end

    # 単色プリミティブ描画用シェーダーを取得します。
    #
    # - 戻り値: `Shader`
    def self.flat_primitive_shader
      @flat_primitive_shader ||= Shader.new(Shaders::FLAT_PRIMITIVE_VERTEX, Shaders::FLAT_PRIMITIVE_FRAGMENT)
    end

    # グラデーション付きプリミティブ描画用シェーダーを取得します。
    #
    # - 戻り値: `Shader`
    def self.gradient_primitive_shader
      @gradient_primitive_shader ||= Shader.new(Shaders::GRADIENT_PRIMITIVE_VERTEX, Shaders::GRADIENT_PRIMITIVE_FRAGMENT)
    end

    # テクスチャ付きプリミティブ描画用シェーダーを取得します。
    #
    # - 戻り値: `Shader`
    def self.textured_primitive_shader
      @textured_primitive_shader ||= Shader.new(Shaders::TEXTURED_PRIMITIVE_VERTEX, Shaders::TEXTURED_PRIMITIVE_FRAGMENT)
    end

    # `Window.draw_rect` / `Window.draw_circle` 等で使用される SDF 図形カード描画用シェーダーを取得します。
    #
    # - 戻り値: `Shader`
    def self.card_shader
      @card_shader ||= Shader.new(Shaders::CARD_VERTEX, Shaders::CARD_FRAGMENT)
    end

    @offset_x = 0.0
    @offset_y = 0.0
    # @camera        : 設定中のカメラ (Window.camera が返すもの)
    # @active_camera : 描画に実際に適用するカメラ (without_camera 中などは nil)
    # 描画時は @active_camera.view ([zoom, ox, oy]) を都度参照する
    @camera = nil
    @active_camera = nil
    @camera_disabled_depth = 0

    def self.__sync_active_camera
      @active_camera = @camera_disabled_depth.zero? ? @camera : nil
    end

    # 現在描画に実際に適用されているカメラを取得します（`Window.without_camera` ブロック内では `nil` を返します）。
    #
    # - 戻り値: `Camera`, `nil`
    def self.active_camera
      @active_camera
    end

    # カメラ設定 (Zenoo::Camera)
    # - 引数なし: 現在のカメラを取得
    # - 引数あり (ブロックなし): カメラを設定
    # - ブロックあり: ブロック内のみカメラを適用
    #
    # - `cam` (`Camera`, `nil`): 適用するカメラオブジェクト（省略時は現在のカメラを取得）
    # - `&block`: 一時的にそのカメラを適用して描画を行うブロック
    def self.camera(cam = nil, &block)
      if block
        old_cam = @camera
        @camera = cam
        __sync_active_camera
        yield
        @camera = old_cam
        __sync_active_camera
      elsif cam
        self.camera = cam
      else
        @camera
      end
    end

    # 描画に使用するカメラを設定します（`nil` でカメラ解除）。
    #
    # - `cam` (`Camera`, `nil`): 設定するカメラオブジェクト
    def self.camera=(cam)
      @camera = cam
      __sync_active_camera
    end

    # カメラを一時的に無効化して UI などを画面ピクセル座標で描画
    #
    # - `&block`: カメラ変換を無効化した状態で描画を行うブロック
    def self.without_camera
      @camera_disabled_depth += 1
      __sync_active_camera
      yield
      @camera_disabled_depth -= 1
      __sync_active_camera
    end

    # 現在描画に対してカメラが有効に適用されているかどうかを返します。
    #
    # - 戻り値: `Boolean`
    def self.camera_enabled?
      !@active_camera.nil?
    end

    # 画面座標 -> ワールド座標変換 (マウス位置など)
    # アクティブなカメラが未設定の場合はそのまま `[sx.to_f, sy.to_f]` を返します。
    #
    # - `sx` (`Numeric`): 画面上の X 座標（論理ピクセル単位）
    # - `sy` (`Numeric`): 画面上の Y 座標（論理ピクセル単位）
    # - 戻り値: `Array<Float>` `[world_x, world_y]`
    def self.to_world(sx, sy)
      if @active_camera
        @active_camera.screen_to_world(sx, sy)
      else
        [sx.to_f, sy.to_f]
      end
    end

    # ワールド座標 -> 画面座標変換
    # アクティブなカメラが未設定の場合はそのまま `[wx.to_f, wy.to_f]` を返します。
    #
    # - `wx` (`Numeric`): ワールド空間の X 座標
    # - `wy` (`Numeric`): ワールド空間の Y 座標
    # - 戻り値: `Array<Float>` `[screen_x, screen_y]`
    def self.to_screen(wx, wy)
      if @active_camera
        @active_camera.world_to_screen(wx, wy)
      else
        [wx.to_f, wy.to_f]
      end
    end

    # 内部用描画座標オフセット (clip / render_to / ImGui 専用)
    def self.__offset_x
      @offset_x
    end

    def self.__offset_x=(val)
      @offset_x = val.to_f
    end

    def self.__offset_y
      @offset_y
    end

    def self.__offset_y=(val)
      @offset_y = val.to_f
    end

    # 現在有効なクリッピング矩形 `[x, y, w, h]` を取得します（未設定時は `nil`）。
    #
    # - 戻り値: `Array<Float>`, `nil`
    def self.current_clip
      Backend.current_clip
    end

    # ビューポート・矩形クリッピングスコープ (glScissor & 遅延ディファード適用)
    # - local: false => 元の画面座標系のまま指定矩形外をクリップ (Ebitengine SubImage 風)
    # - local: true  => クリップ矩形の左上を (0, 0) とするローカル相対座標系 (UI ウィンドウ用)
    # - z: Float     => クリップ全体の親キューにおける Z レベル。クリップ内部は独立して Z ソートされます。
    #
    # - `x` (`Numeric`): クリップ矩形の左上 X 座標
    # - `y` (`Numeric`): クリップ矩形の左上 Y 座標
    # - `w` (`Numeric`): クリップ矩形の幅
    # - `h` (`Numeric`): クリップ矩形の高さ
    # - `local:` (`Boolean`): `true` の場合、スコープ内の描画座標原点をクリップ矩形左上に設定（デフォルト: `false`）
    # - `z:` (`Numeric`): 親描画キューにおける Z ソート順（デフォルト: `0.0`）
    # - 戻り値: `Array<Float>` `pop_clip_scope` に渡す復元用オフセット `[prev_ox, prev_oy]`
    def self.push_clip_scope(x, y, w, h, local: false, z: 0.0)
      prev_ox = @offset_x
      prev_oy = @offset_y

      # 現在の座標系における絶対論理座標を算出
      abs_x = x.to_f + prev_ox
      abs_y = y.to_f + prev_oy
      req_w = w.to_f
      req_h = h.to_f

      # 親クリップ矩形との交差判定 (AABB Intersection)
      parent_clip = Backend.current_clip
      if parent_clip
        px = parent_clip[0]
        py = parent_clip[1]
        pw = parent_clip[2]
        ph = parent_clip[3]
        x1 = [abs_x, px].max
        y1 = [abs_y, py].max
        x2 = [abs_x + req_w, px + pw].min
        y2 = [abs_y + req_h, py + ph].min
        clip_x = x1
        clip_y = y1
        clip_w = [0.0, x2 - x1].max
        clip_h = [0.0, y2 - y1].max
      else
        clip_x = abs_x
        clip_y = abs_y
        clip_w = [0.0, req_w].max
        clip_h = [0.0, req_h].max
      end

      # ローカル座標系の場合はオフセットを更新
      if local
        @offset_x = abs_x
        @offset_y = abs_y
      end

      Backend.push_clip([clip_x, clip_y, clip_w, clip_h], z)
      [prev_ox, prev_oy]
    end

    # `push_clip_scope` で開始したクリッピングスコープを終了し、座標オフセットを復元します。
    # 通常はブロック付きの `Window.clip` の使用を推奨します。
    #
    # - `prev_ox` (`Float`): `push_clip_scope` が返した前の X オフセット
    # - `prev_oy` (`Float`): `push_clip_scope` が返した前の Y オフセット
    def self.pop_clip_scope(prev_ox, prev_oy)
      Backend.pop_clip
      @offset_x = prev_ox
      @offset_y = prev_oy
    end

    # 指定した矩形範囲内に描画を限定するクリッピングブロックを実行します（ネスト対応・親領域との交差で自動クリップ）。
    #
    # - `x` (`Numeric`): クリップ矩形の左上 X 座標
    # - `y` (`Numeric`): クリップ矩形の左上 Y 座標
    # - `w` (`Numeric`): クリップ矩形の幅
    # - `h` (`Numeric`): クリップ矩形の高さ
    # - `local:` (`Boolean`): `true` の場合、ブロック内の描画原点 `(0, 0)` をクリップ矩形左上にする（デフォルト: `false`）
    # - `z:` (`Numeric`): 親描画キューにおける Z ソート順（デフォルト: `0.0`）
    # - `&block`: クリップ範囲内に描画を行うブロック
    def self.clip(x, y, w, h, local: false, z: 0.0)
      prev_ox, prev_oy = push_clip_scope(x, y, w, h, local: local, z: z)
      yield
      pop_clip_scope(prev_ox, prev_oy)
    end

    DEFAULT_SHADOW_COLOR = [0, 0, 0, 180].freeze
    ZERO_COLOR_PARAMS = [0.0, 0.0, 0.0, 0.0].freeze

    # ----------------------------------------------------
    # 描画 API 
    # ----------------------------------------------------

    # SDF 角丸矩形描画 (アンチエイリアス・枠線・ドロップシャドウ・回転・画像マッピング対応)
    #
    # - `x` (`Numeric`): 左上X座標
    # - `y` (`Numeric`): 左上Y座標
    # - `w` (`Numeric`): 幅
    # - `h` (`Numeric`): 高さ
    # - `color:` (`Symbol, Array, Integer, Color, nil`): 塗りつぶし色 (画像指定時は乗算色。省略時は塗りつぶしなし、画像指定時は `:white`)
    # - `radius:` (`Numeric`): 角丸の半径 (ピクセル単位)
    # - `border_color:` (`Symbol, Array, Integer, Color, nil`): 枠線の色
    # - `border_width:` (`Numeric, nil`): 枠線の太さ (ピクセル単位、枠線色指定時のデフォルトは `1.0`)
    # - `shadow_blur:` (`Numeric`): ドロップシャドウ・光彩のぼかし幅
    # - `shadow_color:` (`Symbol, Array, Integer, Color, nil`): 影の色
    # - `angle:` (`Numeric`): 回転角度 (度数法)
    # - `pivot:` (`Symbol, Array, nil`): 回転中心 (`:center`, `:top_left`, `[px, py]` 等)
    # - `image:` (`Image, nil`): 矩形内に貼る画像
    # - `blend:` (`Symbol`): ブレンドモード (`:alpha`, `:add`, `:multiply`, `:none` 等)
    # - `camera:` (`Boolean`): カメラの座標変換を適用するか
    # - `z:` (`Numeric`): Zオーダー (描画順、大きいほど手前)
    def self.draw_rect(x, y, w, h,
                       color: nil,
                       radius: 0.0,
                       border_color: nil,
                       border_width: nil,
                       shadow_blur: 0.0,
                       shadow_color: nil,
                       angle: 0.0,
                       pivot: nil,
                       image: nil,
                       blend: :alpha,
                       camera: true,
                       z: 0.0)
      return if color.nil? && border_color.nil? && image.nil? && (shadow_blur.nil? || shadow_blur.to_f <= 0.0)

      actual_color = color || (image ? :white : nil)
      c_color = Backend.normalize_color(actual_color)
      b_mode = Backend.normalize_blend_mode(blend)

      cam = @active_camera
      if cam && camera
        cur_zoom, cam_ox, cam_oy = cam.view
        ax = (x.to_f * cur_zoom) + cam_ox + @offset_x
        ay = (y.to_f * cur_zoom) + cam_oy + @offset_y
        wf = w.to_f * cur_zoom
        hf = h.to_f * cur_zoom
        rad = radius.to_f * cur_zoom
      else
        cur_zoom = 1.0
        ax = x.to_f + @offset_x
        ay = y.to_f + @offset_y
        wf = w.to_f
        hf = h.to_f
        rad = radius.to_f
      end

      is_flat = (radius.nil? || rad <= 0.0) &&
                border_color.nil? &&
                (shadow_blur.nil? || shadow_blur.to_f <= 0.0) &&
                image.nil? &&
                (angle.nil? || (angle.to_f % 360.0).abs < 0.0001)

      if is_flat
        # 水平線・垂直線のピクセル境界スナップ & 極細線の消失防止
        if hf <= 1.5
          ay = ay.round
          hf = [hf.round, 1.0].max
        end
        if wf <= 1.5
          ax = ax.round
          wf = [wf.round, 1.0].max
        end
        x2 = ax + wf
        y2 = ay + hf
        cr = c_color[0].to_f; cg = c_color[1].to_f; cb = c_color[2].to_f; ca = c_color[3].to_f
        data = [
          ax, ay, cr, cg, cb, ca,
          ax, y2, cr, cg, cb, ca,
          x2, ay, cr, cg, cb, ca,
          x2, ay, cr, cg, cb, ca,
          ax, y2, cr, cg, cb, ca,
          x2, y2, cr, cg, cb, ca
        ].pack("f*")
        Backend.enqueue_draw(
          Backend::Pipelines::TRIANGLES,
          data,
          6,
          shader: flat_primitive_shader,
          blend: b_mode,
          z: z
        )
        return
      end

      # ピボット (pivot: :center, :top_left, :center_left 等)
      pv = Collision.parse_pivot(pivot)
      rot_rad = (angle ? angle.to_f : 0.0) * (Math::PI / 180.0)
      mode = image ? 1.0 : 0.0

      __enqueue_sdf_card(
        ax, ay, wf, hf, c_color, rad,
        border_color, border_width, shadow_blur, shadow_color, cur_zoom,
        rot_rad, pv[0], pv[1], mode, image, b_mode, z
      )
    end

    # SDF カードパイプラインへの共通エンキューヘルパー
    def self.__enqueue_sdf_card(ax, ay, wf, hf, c_color, rad,
                                border_color, border_width,
                                shadow_blur, shadow_color, cur_zoom,
                                rot_rad, pv_x, pv_y, mode, image, b_mode, z)
      b_width = 0.0
      b0 = 0.0; b1 = 0.0; b2 = 0.0; b3 = 0.0
      if border_color
        b_width = (border_width || 1.0).to_f * cur_zoom
        bc = Backend.normalize_color(border_color)
        b0 = bc[0].to_f; b1 = bc[1].to_f; b2 = bc[2].to_f; b3 = bc[3].to_f
      end

      s_blur = shadow_blur.to_f * cur_zoom
      s0 = 0.0; s1 = 0.0; s2 = 0.0; s3 = 0.0
      if s_blur > 0.0
        sc = Backend.normalize_color(shadow_color || DEFAULT_SHADOW_COLOR)
        s0 = sc[0].to_f; s1 = sc[1].to_f; s2 = sc[2].to_f; s3 = sc[3].to_f
      end

      if image
        tw = image.texture_width.to_f
        th = image.texture_height.to_f
        uv0 = tw > 0.0 ? image.x.to_f / tw : 0.0
        uv1 = th > 0.0 ? image.y.to_f / th : 0.0
        uv2 = tw > 0.0 ? image.width.to_f / tw : 1.0
        uv3 = th > 0.0 ? image.height.to_f / th : 1.0
      else
        uv0 = 0.0; uv1 = 0.0; uv2 = 1.0; uv3 = 1.0
      end

      data = [
        ax, ay, wf, hf,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        rad, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        uv0, uv1, uv2, uv3,
        rot_rad, pv_x, pv_y, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: image,
        shader: card_shader,
        blend: b_mode,
        z: z
      )
    end

    # SDF 円 / 楕円描画 (解析的アンチエイリアス・回転・画像マッピング・枠線・ドロップシャドウ対応)
    # `ry` を省略するか `r` と同じ値を指定すると真円、異なる値を指定すると楕円を描画します。
    #
    # - `x` (`Numeric`): 中心X座標
    # - `y` (`Numeric`): 中心Y座標
    # - `r` (`Numeric`): 円の半径 (`ry` 指定時はX軸の半径)
    # - `ry` (`Numeric, nil`): Y軸の半径 (省略時は `r` と同じ真円)
    # - `color:` (`Symbol, Array, Integer, Color, nil`): 塗りつぶし色 (画像指定時は乗算色。省略時は塗りつぶしなし、画像指定時は `:white`)
    # - `border_color:` (`Symbol, Array, Integer, Color, nil`): 枠線の色
    # - `border_width:` (`Numeric, nil`): 枠線の太さ (ピクセル単位)
    # - `shadow_blur:` (`Numeric`): ドロップシャドウ・光彩のぼかし幅
    # - `shadow_color:` (`Symbol, Array, Integer, Color, nil`): 影の色
    # - `angle:` (`Numeric`): 回転角度 (度数法)
    # - `image:` (`Image, nil`): 円・楕円内に貼る画像
    # - `blend:` (`Symbol`): ブレンドモード (`:alpha`, `:add`, `:multiply`, `:none` 等)
    # - `camera:` (`Boolean`): カメラ適用有無 (デフォルト: `true`)
    # - `z:` (`Numeric`): Zオーダー (デフォルト: `0.0`)
    def self.draw_circle(x, y, r, ry = nil,
                        color: nil,
                        border_color: nil,
                        border_width: nil,
                        shadow_blur: 0.0,
                        shadow_color: nil,
                        angle: 0.0,
                        image: nil,
                        blend: :alpha,
                        camera: true,
                        z: 0.0)
      rxf = r.to_f.abs
      ryf = ry ? ry.to_f.abs : rxf
      return if rxf <= 0.0 || ryf <= 0.0

      if rxf == ryf
        d = rxf * 2.0
        draw_rect(x.to_f - rxf, y.to_f - rxf, d, d,
                  radius: rxf,
                  color: color,
                  border_color: border_color,
                  border_width: border_width,
                  shadow_blur: shadow_blur,
                  shadow_color: shadow_color,
                  angle: angle,
                  pivot: :center,
                  image: image,
                  blend: blend,
                  camera: camera,
                  z: z)
        return
      end

      return if color.nil? && border_color.nil? && image.nil? && (shadow_blur.nil? || shadow_blur.to_f <= 0.0)

      actual_color = color || (image ? :white : nil)
      c_color = Backend.normalize_color(actual_color)
      b_mode = Backend.normalize_blend_mode(blend)

      cam = @active_camera
      if cam && camera
        cur_zoom, cam_ox, cam_oy = cam.view
        ax = ((x.to_f - rxf) * cur_zoom) + cam_ox + @offset_x
        ay = ((y.to_f - ryf) * cur_zoom) + cam_oy + @offset_y
        wf = (rxf * 2.0) * cur_zoom
        hf = (ryf * 2.0) * cur_zoom
      else
        cur_zoom = 1.0
        ax = (x.to_f - rxf) + @offset_x
        ay = (y.to_f - ryf) + @offset_y
        wf = rxf * 2.0
        hf = ryf * 2.0
      end

      rot_rad = (angle ? angle.to_f : 0.0) * (Math::PI / 180.0)
      mode = image ? 3.0 : 2.0
      __enqueue_sdf_card(
        ax, ay, wf, hf, c_color, 0.0,
        border_color, border_width, shadow_blur, shadow_color, cur_zoom,
        rot_rad, 0.5, 0.5, mode, image, b_mode, z
      )
    end

    # 画像またはメッシュを描画します
    #
    # - `x` (`Numeric`): 描画基準X座標
    # - `y` (`Numeric`): 描画基準Y座標
    # - `image` (`Image, Mesh, nil`): 描画する画像またはメッシュ (`nil` の場合は何もしない)
    # - `width:` (`Numeric, nil`): 描画幅 (省略時は `image.width`)
    # - `height:` (`Numeric, nil`): 描画高さ (省略時は `image.height`)
    # - `anchor:` (`Symbol, Array`): 自身のどの点を `(x, y)` に配置するか (`:top_left`, `:center`, `:bottom_center`, `[ax, ay]` 等)
    # - `pivot:` (`Symbol, Array`): 拡大・回転の中心位置 (`:center`, `:top_left`, `[px, py]` 等)
    # - `color:` (`Symbol, Array, Integer, Color, nil`): 乗算カラー (ティント)
    # - `angle:` (`Numeric`): 回転角度 (度数法)
    # - `scale:` (`Numeric, nil`): 縦横均等の拡大率 (指定時は `scale_x`, `scale_y` より優先)
    # - `scale_x:` (`Numeric`): X軸の拡大率 (マイナス値で左右反転)
    # - `scale_y:` (`Numeric`): Y軸の拡大率 (マイナス値で上下反転)
    # - `alpha:` (`Numeric`): 不透明度 (0〜255)
    # - `blend:` (`Symbol, nil`): ブレンドモード (`:alpha`, `:add`, `:multiply`, `:none` 等)
    # - `shader:` (`Shader, nil`): カスタムシェーダー
    # - `uniforms:` (`Hash, nil`): シェーダーに渡す Uniform 変数ハッシュ
    # - `image_override:` (`Image, nil`): テクスチャの上書き指定
    # - `camera:` (`Boolean, Camera`): カメラ適用の有無、または使用する Camera インスタンス
    # - `z:` (`Numeric`): Zオーダー (描画順)
    def self.draw(x, y, image,
                  width: nil,
                  height: nil,
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
                  uniforms: nil,
                  image_override: nil,
                  camera: true,
                  z: 0.0)
      return unless image

      is_mesh = image.is_a?(Mesh)
      if is_mesh
        image.sync_to_gpu_if_dirty!
        tex_img = image_override || image.image
        native_mesh = image.native_mesh
        return unless native_mesh && image.count > 0
        eff_pipeline = image.pipeline
        effective_shader = shader || image.shader || eff_pipeline.default_shader ||
                           if eff_pipeline == Backend::Pipelines::SPRITE
                             default_sprite_shader
                           elsif eff_pipeline == Backend::Pipelines::TEXTURED_TRIANGLES || eff_pipeline == Backend::Pipelines::TEXTURED_TRIANGLE_STRIP
                             textured_primitive_shader
                           elsif eff_pipeline == Backend::Pipelines::CARD
                             card_shader
                           else
                             flat_primitive_shader
                           end
        effective_uniforms = if image.uniforms && uniforms
                               image.uniforms.merge(uniforms)
                             else
                               uniforms || image.uniforms
                             end
        eff_blend = blend || image.blend || :alpha

        # カスタム頂点レイアウト (非 SPRITE パイプライン) の生 Mesh はそのまま描画
        if eff_pipeline != Backend::Pipelines::SPRITE
          return unless native_mesh && image.count > 0
          Backend.enqueue_draw(
            eff_pipeline,
            nil,
            1,
            image: tex_img,
            shader: effective_shader,
            uniforms: effective_uniforms,
            blend: Backend.normalize_blend_mode(eff_blend),
            z: z,
            mesh: native_mesh
          )
          return
        end
      else
        tex_img = image_override || image
        native_mesh = nil
        effective_shader = shader || default_sprite_shader
        effective_uniforms = uniforms
        eff_blend = blend || :alpha
      end

      if color.nil? && (alpha.nil? || alpha == 255)
        c0 = 1.0; c1 = 1.0; c2 = 1.0; c3 = 1.0
      else
        c_color = Backend.normalize_color(color || :white)
        c0 = c_color[0].to_f; c1 = c_color[1].to_f; c2 = c_color[2].to_f; c3 = c_color[3].to_f
        if alpha && alpha != 255
          af = alpha.to_f / 255.0
          af = 0.0 if af < 0.0
          af = 1.0 if af > 1.0
          c3 *= af
        end
      end

      draw_w = (width || image.width).to_f
      draw_h = (height || image.height).to_f

      anc_x, anc_y = Collision.parse_anchor(anchor)
      pv_x, pv_y = Collision.parse_pivot(pivot)
      wpv_x = x.to_f + (pv_x - anc_x) * draw_w
      wpv_y = y.to_f + (pv_y - anc_y) * draw_h

      sx = scale ? scale.to_f : scale_x.to_f
      sy = scale ? scale.to_f : scale_y.to_f

      cam = if camera.is_a?(Camera)
              camera
            elsif camera
              @active_camera
            else
              nil
            end
      if cam
        cz, cam_ox, cam_oy = cam.view
        cox = cam_ox + @offset_x
        coy = cam_oy + @offset_y
      else
        cz = 1.0
        cox = @offset_x
        coy = @offset_y
      end

      ang = angle ? angle.to_f : 0.0
      if ang == 0.0
        c_rot = 1.0
        s_rot = 0.0
      else
        rad = ang * (Math::PI / 180.0)
        c_rot = Math.cos(rad)
        s_rot = Math.sin(rad)
      end

      if is_mesh
        m00 = sx * c_rot * cz
        m01 = -sy * s_rot * cz
        m10 = sx * s_rot * cz
        m11 = sy * c_rot * cz
        local_px = pv_x * draw_w
        local_py = pv_y * draw_h
      else
        m00 = draw_w * sx * c_rot * cz
        m01 = -draw_h * sy * s_rot * cz
        m10 = draw_w * sx * s_rot * cz
        m11 = draw_h * sy * c_rot * cz
        local_px = pv_x
        local_py = pv_y
      end

      tx = (wpv_x * cz + cox) - (m00 * local_px + m01 * local_py)
      ty = (wpv_y * cz + coy) - (m10 * local_px + m11 * local_py)

      b_mode = Backend.normalize_blend_mode(eff_blend)

      if tex_img
        tw = tex_img.texture_width.to_f
        th = tex_img.texture_height.to_f
        uv0 = tw > 0.0 ? tex_img.x.to_f / tw : 0.0
        uv1 = th > 0.0 ? tex_img.y.to_f / th : 0.0
        uv2 = tw > 0.0 ? tex_img.width.to_f / tw : 1.0
        uv3 = th > 0.0 ? tex_img.height.to_f / th : 1.0
      else
        uv0 = 0.0; uv1 = 0.0; uv2 = 1.0; uv3 = 1.0
      end

      data = [
        m00, m01, m10, m11,
        tx, ty, 0.0, 0.0,
        c0, c1, c2, c3,
        uv0, uv1, uv2, uv3
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::SPRITE,
        data,
        1,
        image: tex_img,
        shader: effective_shader,
        uniforms: effective_uniforms,
        blend: b_mode,
        z: z,
        mesh: native_mesh
      )
    end


    # 三角形描画 (GPUポリゴンラスタライズ描画)
    # 複数三角形を組み合わせたメッシュでも継ぎ目(シーム)が出ないハードウェア描画です。
    # 頂点グラデーション (`color: [c1, c2, c3]`) に対応しています。
    #
    # - `x1`, `y1` (`Numeric`): 頂点1の座標
    # - `x2`, `y2` (`Numeric`): 頂点2の座標
    # - `x3`, `y3` (`Numeric`): 頂点3の座標
    # - `color:` (`Symbol, Array, Integer, Color`): 塗りつぶし色 または 3頂点分の色の配列 `[c1, c2, c3]`
    # - `blend:` (`Symbol`): ブレンドモード (`:alpha`, `:add` 等)
    # - `camera:` (`Boolean`): カメラ適用有無 (デフォルト: `true`)
    # - `z:` (`Numeric`): Zオーダー (デフォルト: `0.0`)
    def self.draw_triangle(x1, y1, x2, y2, x3, y3,
                          color: :white,
                          blend: :alpha,
                          camera: true,
                          z: 0.0)
      b_mode = Backend.normalize_blend_mode(blend)
      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        cam_ox += @offset_x
        cam_oy += @offset_y
        ax1 = (x1.to_f * cz) + cam_ox; ay1 = (y1.to_f * cz) + cam_oy
        ax2 = (x2.to_f * cz) + cam_ox; ay2 = (y2.to_f * cz) + cam_oy
        ax3 = (x3.to_f * cz) + cam_ox; ay3 = (y3.to_f * cz) + cam_oy
      else
        ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
        ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
        ax3 = x3.to_f + @offset_x; ay3 = y3.to_f + @offset_y
      end

      if color.is_a?(Array) && color.length == 3 && (color[0].is_a?(Color) || color[0].is_a?(Symbol) || color[0].is_a?(Array))
        # 頂点ごとの色指定 [c1, c2, c3]
        c1 = Backend.normalize_color(color[0])
        c2 = Backend.normalize_color(color[1])
        c3 = Backend.normalize_color(color[2])
        data = [
          ax1, ay1, c1[0].to_f, c1[1].to_f, c1[2].to_f, c1[3].to_f,
          ax2, ay2, c2[0].to_f, c2[1].to_f, c2[2].to_f, c2[3].to_f,
          ax3, ay3, c3[0].to_f, c3[1].to_f, c3[2].to_f, c3[3].to_f
        ].pack("f*")
      else
        c = Backend.normalize_color(color)
        cr = c[0].to_f; cg = c[1].to_f; cb = c[2].to_f; ca = c[3].to_f
        data = [
          ax1, ay1, cr, cg, cb, ca,
          ax2, ay2, cr, cg, cb, ca,
          ax3, ay3, cr, cg, cb, ca
        ].pack("f*")
      end

      Backend.enqueue_draw(
        Backend::Pipelines::TRIANGLES,
        data,
        3,
        shader: flat_primitive_shader,
        blend: b_mode,
        z: z
      )
    end

    # SDF 線分描画 (解析的アンチエイリアス・端点形状・枠線・影対応)
    #
    # - `x1`, `y1` (`Numeric`): 始点の座標
    # - `x2`, `y2` (`Numeric`): 終点の座標
    # - `color:` (`Symbol, Array, Integer, Color, nil`): 線の色
    # - `width:` (`Numeric`): 線の太さ (ピクセル単位、デフォルト: `1.0`)
    # - `cap:` (`Symbol`): 端点形状 (`:butt` [平ら], `:round` [丸端], `:square` [正方形])
    # - `border_color:` (`Symbol, Array, Integer, Color, nil`): 枠線の色
    # - `border_width:` (`Numeric, nil`): 枠線の幅
    # - `shadow_blur:` (`Numeric`): 影・光彩のぼかし幅
    # - `shadow_color:` (`Symbol, Array, Integer, Color, nil`): 影の色
    # - `blend:` (`Symbol`): ブレンドモード (`:alpha`, `:add` 等)
    # - `camera:` (`Boolean`): カメラ適用有無 (デフォルト: `true`)
    # - `z:` (`Numeric`): Zオーダー (デフォルト: `0.0`)
    def self.draw_line(x1, y1, x2, y2,
                      color: :white,
                      width: 1.0,
                      cap: :butt,
                      border_color: nil,
                      border_width: nil,
                      shadow_blur: 0.0,
                      shadow_color: nil,
                      blend: :alpha,
                      camera: true,
                      z: 0.0)
      actual_color = color || :white
      b_mode = Backend.normalize_blend_mode(blend)
      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        cam_ox += @offset_x
        cam_oy += @offset_y
        ax1 = (x1.to_f * cz) + cam_ox; ay1 = (y1.to_f * cz) + cam_oy
        ax2 = (x2.to_f * cz) + cam_ox; ay2 = (y2.to_f * cz) + cam_oy
        w = width.to_f * cz
        cur_zoom = cz
      else
        ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
        ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
        w = width.to_f
        cur_zoom = 1.0
      end

      dx = ax2 - ax1
      dy = ay2 - ay1
      len = Math.sqrt(dx * dx + dy * dy)
      return if len <= 0.0001 && w <= 0.0

      cx = (ax1 + ax2) * 0.5
      cy = (ay1 + ay2) * 0.5

      is_horiz = dy.abs < 0.0001
      is_vert  = !is_horiz && dx.abs < 0.0001
      w = 1.0 if (is_horiz || is_vert) && w < 1.0

      rad = 0.0
      total_len = len
      case cap
      when :round
        rad = w * 0.5
        total_len = len + w
      when :square
        total_len = len + w
      end

      # 水平線・垂直線は回転誤差を避けて軸並行矩形として描画し、太さ方向をピクセル境界にスナップ
      if is_horiz
        bx = cx - (total_len * 0.5)
        by = (cy - (w * 0.5)).round
        rect_w = total_len
        rect_h = w
        rot_rad = 0.0
      elsif is_vert
        bx = (cx - (w * 0.5)).round
        by = cy - (total_len * 0.5)
        rect_w = w
        rect_h = total_len
        rot_rad = 0.0
      else
        bx = cx - (total_len * 0.5)
        by = cy - (w * 0.5)
        rect_w = total_len
        rect_h = w
        rot_rad = Math.atan2(dy, dx)
      end

      c_color = Backend.normalize_color(actual_color)

      b_width = 0.0
      b0 = 0.0; b1 = 0.0; b2 = 0.0; b3 = 0.0
      if border_color
        b_width = (border_width || 1.0).to_f * cur_zoom
        bc = Backend.normalize_color(border_color)
        b0 = bc[0].to_f; b1 = bc[1].to_f; b2 = bc[2].to_f; b3 = bc[3].to_f
      end

      s_blur = shadow_blur.to_f * cur_zoom
      s0 = 0.0; s1 = 0.0; s2 = 0.0; s3 = 0.0
      if s_blur > 0.0
        sc = Backend.normalize_color(shadow_color || DEFAULT_SHADOW_COLOR)
        s0 = sc[0].to_f; s1 = sc[1].to_f; s2 = sc[2].to_f; s3 = sc[3].to_f
      end

      mode = 0.0 # 角丸矩形モード (SDF)

      data = [
        bx, by, rect_w, rect_h,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        rad, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        0.0, 0.0, 1.0, 1.0,
        rot_rad, 0.5, 0.5, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: nil,
        shader: card_shader,
        blend: b_mode,
        z: z
      )
    end

    @sdf_font_shader = nil

    # `Window.draw_text` で使用される SDF テキスト描画用シェーダーを取得します。
    #
    # - 戻り値: `Shader`
    def self.sdf_font_shader
      @sdf_font_shader ||= Shader.new(Shaders::FONT_SDF_VERTEX, Shaders::FONT_SDF_FRAGMENT)
    end

    # `Window.draw_text` にブロックを渡した際に各文字ごとに渡される装飾コンテキスト。
    # ブロック内で `c.x`, `c.y`, `c.color`, `c.scale`, `c.visible`, `c.outline_width`, `c.outline_color`, `c.weight` を書き換えることで、
    # 波打ち・タイプライター・文字ごとの色分けなどの演出を実現できます。
    class CharContext
      attr_accessor :char, :index, :line_index, :x, :y, :w, :h, :color, :visible
      attr_accessor :outline_width, :outline_color, :weight

      # この文字の拡大倍率を取得します（デフォルト: `1.0`）。
      #
      # - 戻り値: `Float`
      def scale
        @scale
      end

      # この文字の拡大倍率を設定します。
      #
      # - `val` (`Numeric`): 拡大倍率
      def scale=(val)
        @scale = val
      end

      # 内部用: 再利用インスタンスを次の文字の初期状態にリセットする
      def reset(char, index, gx, gy, gw, gh, default_color, def_out_w, def_out_c, def_weight = 0.0, line_index = 0)
        @char = char
        @index = index
        @line_index = line_index
        @x = gx
        @y = gy
        @w = gw
        @h = gh
        @color = default_color
        @scale = 1.0
        @visible = true
        @outline_width = def_out_w
        @outline_color = def_out_c
        @weight = def_weight
      end
    end

    @char_ctx = CharContext.new

    # テキスト描画幅の計算
    #
    # - `text` (`String`, `nil`): 計測対象の文字列
    # - `font:` (`Font`, `nil`): 使用するフォント（省略時は `Font.default`）
    # - `size:` (`Numeric`): フォントサイズ（ピクセル単位、デフォルト: 24）
    # - 戻り値: `Float` ピクセル単位の描画幅
    def self.text_width(text, font: nil, size: 24)
      target_font = font || Font.default
      return 0.0 unless target_font
      target_font.text_width(text, size)
    end

    # テキスト描画サイズの計算 [width, height] (複数行対応)
    #
    # - `text` (`String`, `nil`): 計測対象の文字列（`\n` による複数行に対応）
    # - `font:` (`Font`, `nil`): 使用するフォント（省略時は `Font.default`）
    # - `size:` (`Numeric`): フォントサイズ（ピクセル単位、デフォルト: 24）
    # - `line_spacing:` (`Numeric`, `nil`): 行間倍率（省略時はフォントの `line_height` を使用）
    # - 戻り値: `Array<Float>` `[width, height]`
    def self.text_size(text, font: nil, size: 24, line_spacing: nil)
      target_font = font || Font.default
      return [0.0, 0.0] unless target_font
      target_font.text_size(text, size, line_spacing: line_spacing)
    end

    # テキスト描画高さの計算 (複数行対応)
    #
    # - `text` (`String`, `nil`): 計測対象の文字列（`\n` による複数行に対応）
    # - `font:` (`Font`, `nil`): 使用するフォント（省略時は `Font.default`）
    # - `size:` (`Numeric`): フォントサイズ（ピクセル単位、デフォルト: 24）
    # - `line_spacing:` (`Numeric`, `nil`): 行間倍率（省略時はフォントの `line_height` を使用）
    # - 戻り値: `Float` ピクセル単位の描画高さ
    def self.text_height(text, font: nil, size: 24, line_spacing: nil)
      target_font = font || Font.default
      return 0.0 unless target_font
      target_font.text_height(text, size, line_spacing: line_spacing)
    end

    # 高品質 SDF テキスト描画 API (改行・アライメント対応)
    # ブロックが渡された場合は 1文字単位のカスタム装飾を実行します。
    #
    # - `x`, `y` (`Numeric`): 基準座標
    # - `text` (`String, Object`): 描画する文字列
    # - `font:` (`Font, nil`): フォントオブジェクト (省略時は `Font.default`)
    # - `size:` (`Numeric`): フォントサイズ (ピクセル単位)
    # - `color:` (`Symbol, Array, Integer, Color`): 文字色
    # - `align:` (`Symbol`): 水平方向のアライメント (`:left`, `:center`, `:right`)
    # - `valign:` (`Symbol`): 垂直方向のアライメント (`:top`, `:center`, `:bottom`, `:baseline`)
    # - `line_spacing:` (`Numeric, nil`): 行送り倍率 (省略時はフォントメトリクス準拠)
    # - `weight:` (`Numeric`): 文字の太さ調整 (太字補正値)
    # - `outline_width:` (`Numeric`): 縁取りの太さ (ピクセル単位)
    # - `outline_color:` (`Symbol, Array, Integer, Color`): 縁取りの色
    # - `shadow_blur:` (`Numeric`): 影のぼかし幅
    # - `shadow_color:` (`Symbol, Array, Integer, Color, nil`): 影の色
    # - `shadow_dx:` (`Numeric`): 影のX方向オフセット
    # - `shadow_dy:` (`Numeric`): 影のY方向オフセット
    # - `sdf:` (`Boolean, nil`): SDF描画の強制ON/OFF (省略時は装飾の有無で自動判定)
    # - `blend:` (`Symbol`): ブレンドモード (`:alpha`, `:add` 等)
    # - `camera:` (`Boolean`): カメラ適用有無 (デフォルト: `true`)
    # - `z:` (`Numeric`): Zオーダー (デフォルト: `0.0`)
    # - `&block`: 1文字ごとの装飾を行うブロック (`|ctx|`)
    def self.draw_text(x, y, text,
                       font: nil,
                       size: 24,
                       color: :white,
                       align: :left,
                       valign: :top,
                       line_spacing: nil,
                       weight: 0.0,
                       outline_width: 0.0,
                       outline_color: :black,
                       shadow_blur: 0.0,
                       shadow_color: nil,
                       shadow_dx: 0.0,
                       shadow_dy: 0.0,
                       sdf: nil,
                       blend: :alpha,
                       camera: true,
                       z: 0.0,
                       &block)
      return if text.nil?
      str = text.to_s
      return if str.empty?

      target_font = font || Font.default
      return unless target_font

      font_atlas = Font.atlas_image
      return unless font_atlas

      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        base_x = (x.to_f * cz) + cam_ox
        base_y = (y.to_f * cz) + cam_oy
        f_size = size.to_f * cz
      else
        base_x = x.to_f
        base_y = y.to_f
        f_size = size.to_f
      end
      f_size = 24.0 if f_size <= 0.0

      metrics = target_font.metrics(f_size)
      ascent = metrics[:ascent]
      __prepare_text_draw(f_size, color, weight, outline_width, outline_color,
                          shadow_blur, shadow_color, shadow_dx, shadow_dy, sdf)

      batch = (@text_batch ||= [])
      batch.clear
      @text_glyph_count = 0

      vp_scale = @_txt_vp_scale
      inv_vp_scale = @_txt_inv_vp_scale

      # 改行を含む複数行テキストの処理
      if str.include?("\n")
        lines = str.split("\n", -1)
        line_count = lines.length
        line_h = line_spacing ? (f_size * line_spacing.to_f) : (metrics[:line_height] || (f_size * 1.2))
        total_h = f_size + (line_count - 1) * line_h

        cur_base_y = base_y
        case valign
        when :center
          cur_base_y -= total_h * 0.5
        when :bottom
          cur_base_y -= total_h
        when :baseline
          cur_base_y -= (ascent || f_size * 0.8)
        end

        char_offset = 0
        line_idx = 0
        while line_idx < line_count
          line_text = lines[line_idx]
          line_y = cur_base_y + line_idx * line_h
          line_x = base_x
          if align == :center
            line_x -= target_font.text_width(line_text, f_size) * 0.5
          elsif align == :right
            line_x -= target_font.text_width(line_text, f_size)
          end

          pen_x = ((line_x + @offset_x) * vp_scale).round * inv_vp_scale
          pen_y = ((line_y + @offset_y + ascent) * vp_scale).round * inv_vp_scale

          if block
            char_offset = __draw_text_line_custom(line_text, line_idx, char_offset, pen_x, pen_y, target_font, f_size, &block)
          else
            __draw_text_line_simple(line_text, pen_x, pen_y, target_font, f_size)
          end
          line_idx += 1
        end
      else
        # 単一行テキストの揃え位置オフセット算出 (デフォルト :left / :top 時は text_width や追加分岐をスキップ)
        draw_x = base_x
        if align == :center
          draw_x -= target_font.text_width(str, f_size) * 0.5
        elsif align == :right
          draw_x -= target_font.text_width(str, f_size)
        end

        draw_y = base_y
        if valign != :top
          case valign
          when :center
            draw_y -= f_size * 0.5
          when :bottom
            draw_y -= f_size
          when :baseline
            draw_y -= (ascent || f_size * 0.8)
          end
        end

        pen_x = ((draw_x + @offset_x) * vp_scale).round * inv_vp_scale
        pen_y = ((draw_y + @offset_y + ascent) * vp_scale).round * inv_vp_scale

        if block
          __draw_text_line_custom(str, 0, 0, pen_x, pen_y, target_font, f_size, &block)
        else
          __draw_text_line_simple(str, pen_x, pen_y, target_font, f_size)
        end
      end

      if @text_glyph_count > 0
        Backend.enqueue_draw(
          Backend::Pipelines::FONT,
          batch.pack("f*"),
          @text_glyph_count,
          image: font_atlas,
          shader: sdf_font_shader,
          blend: Backend.normalize_blend_mode(blend),
          z: z
        )
      end
    end

    def self.__prepare_text_draw(f_size, color, weight, outline_width, outline_color,
                                 shadow_blur, shadow_color, shadow_dx, shadow_dy, sdf)
      @_txt_color = Backend.normalize_color(color)

      outline_w = outline_width.to_f
      @_txt_outline_w = outline_w
      @_txt_outline_c = (outline_w > 0.0) ? Backend.normalize_color(outline_color) : ZERO_COLOR_PARAMS

      s_blur = shadow_blur.to_f
      s_dx = shadow_dx.to_f
      s_dy = shadow_dy.to_f
      @_txt_shadow_c = (s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? Backend.normalize_color(shadow_color || DEFAULT_SHADOW_COLOR) : ZERO_COLOR_PARAMS

      s_weight = weight.to_f
      @_txt_weight = s_weight

      @_txt_effective_sdf = if sdf.nil?
                              (outline_w > 0.0 || s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0 || s_weight != 0.0) ? true : nil
                            else
                              sdf ? true : false
                            end

      scale_ratio = Font::SDF_BASE_SIZE / f_size
      @_txt_scale_ratio = scale_ratio
      @_txt_p0_0 = outline_w * scale_ratio
      @_txt_p0_1 = s_blur * scale_ratio
      @_txt_p0_2 = s_dx * scale_ratio
      @_txt_p0_3 = s_dy * scale_ratio

      vp_scale = Backend.current_target ? 1.0 : Native::Window.scale.to_f
      vp_scale = 1.0 if vp_scale < 1.0
      @_txt_vp_scale = vp_scale
      @_txt_inv_vp_scale = 1.0 / vp_scale
    end

    def self.__draw_text_line_simple(line_text, pen_x, pen_y, target_font, f_size)
      return if line_text.empty?

      batch = @text_batch
      effective_sdf = @_txt_effective_sdf
      vp_scale = @_txt_vp_scale
      inv_vp_scale = @_txt_inv_vp_scale

      c_color = @_txt_color
      cr = c_color[0].to_f; cg = c_color[1].to_f; cb = c_color[2].to_f; ca = c_color[3].to_f
      p0_0 = @_txt_p0_0; p0_1 = @_txt_p0_1; p0_2 = @_txt_p0_2; p0_3 = @_txt_p0_3
      out_c = @_txt_outline_c
      p1_0 = out_c[0].to_f; p1_1 = out_c[1].to_f; p1_2 = out_c[2].to_f; p1_3 = out_c[3].to_f
      shd_c = @_txt_shadow_c
      p2_0 = shd_c[0].to_f; p2_1 = shd_c[1].to_f; p2_2 = shd_c[2].to_f; p2_3 = shd_c[3].to_f
      s_weight = @_txt_weight

      glyph_count = @text_glyph_count
      line_text.each_char do |ch|
        glyph_data = target_font.get_glyph(ch, f_size, effective_sdf, vp_scale)
        adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

        if glyph_data && glyph_data[0] # visible == true
          _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv, is_bitmap = glyph_data
          if is_bitmap == true || is_bitmap == 1
            is_bmp = 1.0
            gx = (pen_x * vp_scale).round * inv_vp_scale + x0.to_f
            gy = pen_y + y0.to_f
          else
            is_bmp = 0.0
            gx = (pen_x + x0).to_f
            gy = (pen_y + y0).to_f
          end
          gw = (x1 - x0).to_f
          gh = (y1 - y0).to_f

          batch.push(
            gx, gy, gw, gh,
            cr, cg, cb, ca,
            p0_0, p0_1, p0_2, p0_3,
            p1_0, p1_1, p1_2, p1_3,
            p2_0, p2_1, p2_2, p2_3,
            s_weight, is_bmp, s_weight, 0.0,
            u0.to_f, v0.to_f, (u1 - u0).to_f, (v1 - v0).to_f
          )
          glyph_count += 1
        end

        pen_x += adv
      end
      @text_glyph_count = glyph_count
    end

    def self.__prepare_char_ctx(ctx, target_font, ch, char_index, line_index, pen_x, pen_y, f_size)
      glyph_data = target_font.get_glyph(ch, f_size, @_txt_effective_sdf, @_txt_vp_scale)
      @_cur_glyph_adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

      if glyph_data && glyph_data[0] # visible == true
        _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv, is_bitmap = glyph_data
        if is_bitmap == true || is_bitmap == 1
          @_cur_is_bmp = 1.0
          gx = (pen_x * @_txt_vp_scale).round * @_txt_inv_vp_scale + x0.to_f
          gy = pen_y + y0.to_f
        else
          @_cur_is_bmp = 0.0
          gx = (pen_x + x0).to_f
          gy = (pen_y + y0).to_f
        end
        @_cur_u0 = u0.to_f
        @_cur_v0 = v0.to_f
        @_cur_uw = (u1 - u0).to_f
        @_cur_vh = (v1 - v0).to_f
        ctx.reset(ch, char_index, gx, gy, (x1 - x0).to_f, (y1 - y0).to_f,
                  @_txt_color, @_txt_outline_w, @_txt_outline_c, @_txt_weight, line_index)
        @_cur_glyph_visible = true
      else
        @_cur_glyph_visible = false
      end
    end

    def self.__push_char_ctx(batch, ctx)
      return false unless ctx.visible

      cgx = ctx.x
      cgy = ctx.y
      cgw = ctx.w
      cgh = ctx.h

      if ctx.scale != 1.0
        sc = ctx.scale
        cx = cgx + cgw * 0.5
        cy = cgy + cgh * 0.5
        cgw *= sc
        cgh *= sc
        cgx = cx - cgw * 0.5
        cgy = cy - cgh * 0.5
      end

      cur_color = ctx.color.equal?(@_txt_color) ? @_txt_color : Backend.normalize_color(ctx.color)
      cur_out_w = (ctx.outline_width == @_txt_outline_w) ? @_txt_p0_0 : (ctx.outline_width.to_f * @_txt_scale_ratio)
      cur_out_c = ctx.outline_color.equal?(@_txt_outline_c) ? @_txt_outline_c : Backend.normalize_color(ctx.outline_color)
      cur_w = (ctx.weight == @_txt_weight) ? @_txt_weight : ctx.weight.to_f
      shd_c = @_txt_shadow_c

      batch.push(
        cgx.to_f, cgy.to_f, cgw.to_f, cgh.to_f,
        cur_color[0].to_f, cur_color[1].to_f, cur_color[2].to_f, cur_color[3].to_f,
        cur_out_w, @_txt_p0_1, @_txt_p0_2, @_txt_p0_3,
        cur_out_c[0].to_f, cur_out_c[1].to_f, cur_out_c[2].to_f, cur_out_c[3].to_f,
        shd_c[0].to_f, shd_c[1].to_f, shd_c[2].to_f, shd_c[3].to_f,
        cur_w, @_cur_is_bmp, cur_w, 0.0,
        @_cur_u0, @_cur_v0, @_cur_uw, @_cur_vh
      )
      true
    end

    def self.__draw_text_line_custom(line_text, line_idx, char_offset, pen_x, pen_y, target_font, f_size)
      return char_offset if line_text.empty?

      ctx = @char_ctx
      batch = @text_batch
      line_text.each_char do |ch|
        __prepare_char_ctx(ctx, target_font, ch, char_offset, line_idx, pen_x, pen_y, f_size)
        if @_cur_glyph_visible
          yield(ctx)
          @text_glyph_count += 1 if __push_char_ctx(batch, ctx)
        end
        pen_x += @_cur_glyph_adv
        char_offset += 1
      end
      char_offset
    end

    # ベクターパス描画 (`Window.draw_path`) で共有利用される `Canvas` インスタンスを返します。
    #
    # - 戻り値: `Canvas`
    def self.canvas
      @canvas ||= Canvas.new
    end

    # ベクターパス描画 (HTML5 Canvas 2D API 互換のベクター図形描画)
    #
    # - `camera:` (`Boolean`): カメラ適用有無 (デフォルト: `true`)
    # - `&block`: パス描画用の `Canvas` オブジェクトを渡すブロック (`|c|`)
    def self.draw_path(camera: true)
      c = canvas
      cam = camera ? @active_camera : nil
      zoom, cam_ox, cam_oy = cam ? cam.view : [1.0, 0.0, 0.0]
      cam_ox += @offset_x
      cam_oy += @offset_y

      has_transform = (cam_ox != 0.0 || cam_oy != 0.0 || zoom != 1.0)
      if has_transform
        c.save
        c.translate(cam_ox, cam_oy)
        c.scale(zoom, zoom) if zoom != 1.0
      end
      c.begin_path
      yield c
      c.restore if has_transform
    end
  end
end

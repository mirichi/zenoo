# frozen_string_literal: true

require_relative 'imgui/theme'
require_relative 'imgui/renderer'
require_relative 'imgui/card_renderer'
require_relative 'imgui/layout'
require_relative 'imgui/window_manager'
require_relative 'imgui/text_edit'
require_relative 'imgui/profile_graph'
require_relative 'imgui/widgets'

module Zenoo
  # 即時モード (Immediate Mode) GUI システム
  module ImGui
    extend Widgets

    @theme      = Theme.new
    @renderer   = CardRenderer.new
    @layout     = Layout.new
    @win_mgr    = WindowManager.new

    @mouse_x    = 0.0
    @mouse_y    = 0.0
    @mouse_down = false
    @mouse_push = false
    @mouse_rel  = false
    @hot_id        = nil
    @active_id     = nil
    @focus_id      = nil
    @prev_captured = false
    @evaluated     = false
    @cursor_pos    = 0
    @blink_time    = 0.0

    class << self
      attr_accessor :renderer
      attr_reader :layout, :focus_id, :hot_id, :active_id

      # テーマの取得・設定・上書きを行う
      #
      # - `preset` (`Symbol | Theme | nil`): 適用するプリセット名（`:tool_dark`, `:cyber`, または `Theme.register` で登録した名前）または `Theme` インスタンス（省略時は現在のテーマを取得またはキーワード引数で上書き）
      # - `overrides` (`Hash`): 上書きするテーマ属性（`Theme#configure` と同じキーワード引数。色は `0..255` 基準）
      # - 戻り値: `Theme`
      def theme(preset = nil, **overrides)
        if preset.nil? && overrides.empty?
          @theme
        elsif preset.is_a?(Symbol)
          @theme = Theme.new(preset, **overrides)
        elsif preset.is_a?(Theme)
          @theme = preset
          @theme.configure(**overrides) unless overrides.empty?
          @theme
        else
          @theme.configure(**overrides)
        end
      end

      # テーマを直接設定する
      #
      # - `val` (`Symbol | Theme`): プリセット名のシンボルまたは `Theme` インスタンス
      # - 戻り値: `Symbol | Theme`
      def theme=(val)
        @theme = val.is_a?(Symbol) ? Theme.new(val) : val
      end

      # ブロック実行中のみ一時的にテーマを切り替える
      #
      # - `target_theme` (`Symbol | Theme | Object`): 切り替え先のプリセット名または `Theme`（それ以外の値または `nil` の場合は現在のテーマを複製して上書き）
      # - `overrides` (`Hash`): 一時テーマへ適用する属性上書き（`Theme#configure` と同じキーワード引数）
      # - `&block`: 切り替え後のテーマで実行する描画ブロック
      # - 戻り値: `Theme`
      def with_theme(target_theme, **overrides)
        old_theme = @theme
        @theme = if target_theme.is_a?(Symbol)
                   Theme.new(target_theme, **overrides)
                 elsif target_theme.is_a?(Theme)
                   target_theme
                 else
                   @theme.dup.configure(**overrides)
                 end
        yield
        @theme = old_theme
      end

      # マウスカーソルが GUI コントロールまたはウィンドウ上にあるか、操作中かを返す（Dear ImGui の `WantCaptureMouse` 相当）
      #
      # - 戻り値: `Boolean`
      def mouse_captured?
        if @evaluated
          !@hot_id.nil? || !@active_id.nil? || !@focus_id.nil? || !@win_mgr.hovered_window_id.nil?
        else
          @prev_captured || !@active_id.nil? || !@focus_id.nil?
        end
      end

      # テキスト入力などのフォーカス先ウィジェット ID を設定する
      #
      # - `val` (`String | Symbol | nil`): フォーカスを与えるウィジェット ID（`nil` で解除）
      # - 戻り値: `nil`
      def focus_id=(val)
        @focus_id = val ? val.to_s : nil
        @blink_time = 0.0
        Input.set_ime_position(-1, -1) unless @focus_id
      end

      # 指定 ID のウィジェットが現在フォーカスを持っているかを返す
      #
      # - `id` (`String | Symbol`): 確認するウィジェット ID
      # - 戻り値: `Boolean`
      def has_focus?(id)
        @focus_id == id.to_s
      end

      # 現在のウィジェットフォーカスを解除する
      #
      # - 戻り値: `nil`
      def clear_focus
        self.focus_id = nil
      end

      # --------------------------------------------------
      # ウィンドウ管理状態へのアクセサ (WindowManager へ委譲)
      # --------------------------------------------------

      # 管理中の全ウィンドウ状態のハッシュ（`id => WindowState`）を返す
      #
      # - 戻り値: `Hash{String => WindowState}`
      def windows
        @win_mgr.windows
      end

      # ウィンドウの描画順（末尾が最前面）の ID 配列を返す
      #
      # - 戻り値: `Array<String>`
      def window_order
        @win_mgr.window_order
      end

      # 現在マウスカーソル直下にある最前面ウィンドウの ID を返す
      #
      # - 戻り値: `String | nil`
      def hovered_window_id
        @win_mgr.hovered_window_id
      end

      # 現在アクティブ（最前面）なウィンドウの ID を返す
      #
      # - 戻り値: `String | nil`
      def active_window_id
        @win_mgr.active_window_id
      end

      # --------------------------------------------------
      # フレーム開始・終了処理 (Window.loop で毎フレーム自動呼び出し)
      # --------------------------------------------------

      # フレーム開始時の入力・カーソル・レイアウト初期化を行う（`Window.loop` で自動呼び出し）
      #
      # - 戻り値: `nil`
      def begin_frame
        @mouse_x    = Input.mouse_x.to_f
        @mouse_y    = Input.mouse_y.to_f
        @mouse_down = Input.mouse_pressed?(:left)
        @mouse_push = Input.mouse_push?(:left)
        @mouse_rel  = Input.mouse_release?(:left)
        @prev_captured = !@hot_id.nil? || !@active_id.nil? || !@focus_id.nil? || !@win_mgr.hovered_window_id.nil?
        @hot_id     = nil
        @evaluated  = false
        @blink_time = (@blink_time || 0.0) + Window.delta_time
        @requested_cursor = :arrow

        @win_mgr.begin_frame(@mouse_x, @mouse_y, @mouse_down, @mouse_push)
        Input.consume_mouse! unless @win_mgr.hovered_window_id.nil?
        @layout.reset
      end

      # このフレームで要求するマウスカーソル形状を設定する
      #
      # - `shape` (`Symbol`): カーソル形状（`:arrow`, `:hand`, `:ibeam`, `:nwse` 等）
      # - 戻り値: `Symbol`
      def set_mouse_cursor(shape)
        @requested_cursor = shape
      end

      # このフレームで要求されているマウスカーソル形状を返す
      #
      # - 戻り値: `Symbol`
      def requested_cursor
        @requested_cursor
      end

      # フレーム終了時のカーソル反映処理を行う（`Window.loop` で自動呼び出し）
      #
      # - 戻り値: `Symbol`
      def end_frame
        if @requested_cursor != :arrow
          Window.cursor = @requested_cursor
        elsif UI.requested_cursor
          Window.cursor = UI.requested_cursor
        else
          Window.cursor = :arrow
        end
      end

      # --------------------------------------------------
      # レイアウト & カーソル操作 (Layout へ委譲)
      # --------------------------------------------------
      # レイアウトカーソル位置の取得または設定を行う
      #
      # - `x` (`Float | nil`): 設定する X 座標（`x`・`y` とも `nil` の場合は現在座標 `[cursor_x, cursor_y]` を取得）
      # - `y` (`Float | nil`): 設定する Y 座標
      # - 戻り値: `Array<Float>`
      def cursor(x = nil, y = nil)
        @layout.cursor(x, y)
      end

      # レイアウトカーソル位置を設定する
      #
      # - `x` (`Float`): 設定する X 座標
      # - `y` (`Float`): 設定する Y 座標
      # - 戻り値: `Array<Float>`
      def set_cursor(x, y)
        @layout.cursor(x, y)
      end

      # 現在のレイアウトカーソル X 座標を返す
      #
      # - 戻り値: `Float`
      def cursor_x
        @layout.cursor_x
      end

      # レイアウトカーソル X 座標を設定する
      #
      # - `val` (`Float`): X 座標
      # - 戻り値: `Float`
      def cursor_x=(val)
        @layout.cursor_x = val
        val
      end

      # 現在のレイアウトカーソル Y 座標を返す
      #
      # - 戻り値: `Float`
      def cursor_y
        @layout.cursor_y
      end

      # レイアウトカーソル Y 座標を設定する
      #
      # - `val` (`Float`): Y 座標
      # - 戻り値: `Float`
      def cursor_y=(val)
        @layout.cursor_y = val
        val
      end

      # ウィジェット間の余白（spacing）の取得または設定を行う
      #
      # - `x` (`Float | nil`): 横方向の間隔（`x`・`y` とも `nil` の場合は `[spacing_x, spacing_y]` を取得）
      # - `y` (`Float | nil`): 縦方向の間隔
      # - 戻り値: `Array<Float>`
      def spacing(x = nil, y = nil)
        @layout.spacing(x, y)
      end

      # 現在の横方向間隔を返す
      #
      # - 戻り値: `Float`
      def spacing_x
        @layout.spacing_x
      end

      # 横方向間隔を設定する
      #
      # - `val` (`Float`): 横方向間隔（ピクセル単位）
      # - 戻り値: `Float`
      def spacing_x=(val)
        @layout.spacing_x = val
        val
      end

      # 現在の縦方向間隔を返す
      #
      # - 戻り値: `Float`
      def spacing_y
        @layout.spacing_y
      end

      # 縦方向間隔を設定する
      #
      # - `val` (`Float`): 縦方向間隔（ピクセル単位）
      # - 戻り値: `Float`
      def spacing_y=(val)
        @layout.spacing_y = val
        val
      end

      # 指定サイズの要素を配置した前提でレイアウトカーソルを進める
      #
      # - `w` (`Float`): 配置した要素の幅
      # - `h` (`Float`): 配置した要素の高さ
      # - 戻り値: `Float`
      def advance_cursor(w, h)
        @layout.advance(w, h)
      end

      # レイアウトカーソルを指定ピクセル分進めて余白を空ける
      #
      # - `size` (`Float`): 空けるサイズ（ピクセル、デフォルト `8.0`）
      # - 戻り値: `Float`
      def spacer(size = 8.0)
        @layout.spacer(size)
      end

      # 横並びブロックを実行する（`cols` 指定時はコンテナ幅を等分した幅が自動割り当てされる）
      #
      # - `spacing` (`Float`): 要素間の横間隔（負値時は現在の `spacing_x` を使用）
      # - `cols` (`Integer | nil`): 列数（指定すると子要素の幅が自動等分される）
      # - `&block`: 横並びで配置するウィジェット呼び出しブロック
      # - 戻り値: `Object | nil`
      def row(spacing: -1.0, cols: nil, &block)
        @layout.row(spacing: spacing, cols: cols, &block)
      end

      # --------------------------------------------------
      # 座標・入力遮断ヘルパー
      # --------------------------------------------------
      # 点 `(px, py)` が矩形 `(rx, ry, rw, rh)` の内側にあるかを判定する
      #
      # - `px` (`Float`): 判定点の X 座標
      # - `py` (`Float`): 判定点の Y 座標
      # - `rx` (`Float`): 矩形左上 X 座標
      # - `ry` (`Float`): 矩形左上 Y 座標
      # - `rw` (`Float`): 矩形の幅
      # - `rh` (`Float`): 矩形の高さ
      # - 戻り値: `Boolean`
      def in_rect?(px, py, rx, ry, rw, rh)
        px >= rx && px <= (rx + rw) && py >= ry && py <= (ry + rh)
      end

      # 現在のウィジェットがマウス操作を受け付けられるかを判定する（最前面ウィンドウ・クリッピング範囲を考慮）
      #
      # - 戻り値: `Boolean`
      def can_interact?
        @evaluated = true
        # 1. ハードウェアクリッピング矩形外なら不可 (スクロールではみ出たコントロール等の遮断)
        clip = Backend.current_clip
        if clip
          return false unless in_rect?(@mouse_x, @mouse_y, clip[0], clip[1], clip[2], clip[3])
        end

        # 2. マウス直下の最前面ウィンドウと現在のウィジェット所属コンテキストが一致しているか
        @win_mgr.hovered_window_id == @win_mgr.current_window_id
      end

      # 現在のクリップ・オフセット空間に対応したマウス X 座標を返す
      #
      # - 戻り値: `Float`
      def gui_mouse_x
        @mouse_x - Window.__offset_x
      end

      # 現在のクリップ・オフセット空間に対応したマウス Y 座標を返す
      #
      # - 戻り値: `Float`
      def gui_mouse_y
        @mouse_y - Window.__offset_y
      end

      # --------------------------------------------------
      # コンテナ (Panel / Window)
      # --------------------------------------------------
      # パネルコンテナの描画とレイアウトスコープを開始する（通常はブロック付きの `ImGui.panel` を使用）
      #
      # - `title` (`String`): 上部に表示するタイトル文字列
      # - `x` (`Float | nil`): X座標（省略時は現在のレイアウトカーソル X）
      # - `y` (`Float | nil`): Y座標（省略時は現在のレイアウトカーソル Y）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `360.0`）
      # - `h` (`Float`): 高さ（デフォルト `400.0`）
      # - `padding` (`Float`): 内側余白（デフォルト `16.0`）
      # - `radius` (`Float`): 角丸半径（負値時はテーマ既定値を使用）
      # - `color` (`Color | Symbol | Array | nil`): 背景色（`0..255` 基準、省略時はテーマ準拠）
      # - `border_width` (`Float | nil`): 枠線太さ（ピクセル単位）
      # - `border_color` (`Color | Symbol | Array | nil`): 枠線色（`0..255` 基準）
      # - `shadow_blur` (`Float`): ドロップシャドウのぼかし半径（デフォルト `8.0`）
      # - `shadow_color` (`Color | Symbol | Array | nil`): ドロップシャドウ色（`0..255` 基準）
      # - `z` (`Float`): 描画 Z 深度（デフォルト `0.0`）
      # - `title_size` (`Integer`): タイトル文字列のフォントサイズ（デフォルト `18`）
      # - `title_color` (`Color | Symbol | Array | nil`): タイトル文字色（`0..255` 基準）
      # - `clip` (`Boolean`): 子ウィジェットをパネル領域内にクリッピングするか（デフォルト `false`）
      # - `spacing_x` (`Float | nil`): パネル内横間隔の上書き値
      # - `spacing_y` (`Float | nil`): パネル内縦間隔の上書き値
      # - 戻り値: `Array`（`end_panel` に渡す状態配列）
      def begin_panel(title = "", x: nil, y: nil, w: nil, h: 400.0, padding: 16.0,
                      radius: -1.0, color: nil,
                      border_width: nil, border_color: nil,
                      shadow_blur: 8.0, shadow_color: Color.new(0, 0, 0, 120),
                      z: 0.0, title_size: 18, title_color: nil, clip: false,
                      spacing_x: nil, spacing_y: nil)
        px  = x ? x.to_f : @layout.cursor_x
        py  = y ? y.to_f : @layout.cursor_y
        pw  = @layout.resolve_width(w, 360.0)
        ph  = h.to_f
        pad = padding.to_f
        rad = (radius < 0.0) ? (@theme.corner_radius || 4.0).to_f : radius.to_f

        border_cfg = @theme.win_border_normal || @theme.border_normal
        b_width = border_width ? border_width.to_f : (border_cfg ? border_cfg[0].to_f : 1.0)
        b_color = border_color || (border_cfg ? border_cfg[1] : Color.new(70, 70, 75, 200))

        opts = {
          w: pw,
          h: ph,
          padding: pad,
          radius: rad,
          color: color || @theme.win_bg || Color.new(30, 30, 32, 245),
          border_width: b_width,
          border_color: b_color,
          shadow_blur: shadow_blur.to_f,
          shadow_color: shadow_color,
          z: z.to_f,
          title_size: title_size.to_i,
          title_color: title_color || @theme.text_color
        }

        @renderer.draw_panel(px, py, pw, ph, title, @theme, **opts)

        header_h  = title.to_s.empty? ? 0.0 : (title_size.to_i + (spacing_y || @layout.spacing_y) + 4.0)
        content_x = px + pad
        content_y = py + pad + header_h
        content_w = [pw - pad * 2.0, 0.0].max
        content_h = [ph - pad * 2.0 - header_h, 0.0].max

        container_state = @layout.begin_container(content_x, content_y, content_w, content_h, clip: clip, z: z.to_f, spacing_x: spacing_x, spacing_y: spacing_y)
        [pw, ph, !x.nil? || !y.nil?, container_state]
      end

      # `begin_panel` で開始したパネルコンテナを終了しレイアウトカーソルを進める
      #
      # - `state` (`Array`): `begin_panel` の戻り値
      # - 戻り値: `Float | nil`
      def end_panel(state)
        pw, ph, is_manual_pos, container_state = state
        @layout.end_container(container_state)
        @layout.advance(pw, ph) unless is_manual_pos
      end

      # パネル（コンテナ枠）を描画し、ブロック内のウィジェットを自動レイアウトする
      #
      # - `title` (`String`): 上部に表示するタイトル文字列
      # - `x` (`Float | nil`): X座標（省略時は現在のレイアウトカーソル X）
      # - `y` (`Float | nil`): Y座標（省略時は現在のレイアウトカーソル Y）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `360.0`）
      # - `h` (`Float`): 高さ（デフォルト `400.0`）
      # - `padding` (`Float`): 内側余白（デフォルト `16.0`）
      # - `radius` (`Float`): 角丸半径（負値時はテーマ既定値を使用）
      # - `color` (`Color | Symbol | Array | nil`): 背景色（`0..255` 基準、省略時はテーマ準拠）
      # - `border_width` (`Float | nil`): 枠線太さ（ピクセル単位）
      # - `border_color` (`Color | Symbol | Array | nil`): 枠線色（`0..255` 基準）
      # - `shadow_blur` (`Float`): ドロップシャドウのぼかし半径（デフォルト `8.0`）
      # - `shadow_color` (`Color | Symbol | Array | nil`): ドロップシャドウ色（`0..255` 基準）
      # - `z` (`Float`): 描画 Z 深度（デフォルト `0.0`）
      # - `title_size` (`Integer`): タイトル文字列のフォントサイズ（デフォルト `18`）
      # - `title_color` (`Color | Symbol | Array | nil`): タイトル文字色（`0..255` 基準）
      # - `clip` (`Boolean`): 子ウィジェットをパネル領域内にクリッピングするか（デフォルト `false`）
      # - `spacing_x` (`Float | nil`): パネル内横間隔の上書き値
      # - `spacing_y` (`Float | nil`): パネル内縦間隔の上書き値
      # - `&block`: パネル内に配置するウィジェット描画ブロック
      # - 戻り値: `Float | nil`
      def panel(title = "", x: nil, y: nil, w: nil, h: 400.0, padding: 16.0,
                radius: -1.0, color: nil,
                border_width: nil, border_color: nil,
                shadow_blur: 8.0, shadow_color: Color.new(0, 0, 0, 120),
                z: 0.0, title_size: 18, title_color: nil, clip: false,
                spacing_x: nil, spacing_y: nil)
        state = begin_panel(
          title, x: x, y: y, w: w, h: h, padding: padding,
          radius: radius, color: color,
          border_width: border_width, border_color: border_color,
          shadow_blur: shadow_blur, shadow_color: shadow_color,
          z: z, title_size: title_size, title_color: title_color, clip: clip,
          spacing_x: spacing_x, spacing_y: spacing_y
        )
        if block_given?
          yield
          end_panel(state)
        else
          end_panel(state)
        end
      end

      # フローティングウィンドウの描画とレイアウトスコープを開始する（通常はブロック付きの `ImGui.window` を使用）
      #
      # - `title` (`String`): タイトルバー文字列（`id` 未指定時は識別 ID としても使用）
      # - `x` (`Float | nil`): 初期 X 座標
      # - `y` (`Float | nil`): 初期 Y 座標
      # - `w` (`Float`): 初期幅（デフォルト `320.0`）
      # - `h` (`Float`): 初期高さ（デフォルト `240.0`）
      # - `id` (`String`): ウィンドウ識別 ID（空文字時は `title` を使用）
      # - `padding` (`Float`): 内側余白（デフォルト `12.0`）
      # - `resizable` (`Boolean`): 右下ドラッグによるサイズ変更を許可するか（デフォルト `false`）
      # - `min_w` (`Float`): リサイズ時の最小幅（デフォルト `120.0`）
      # - `min_h` (`Float`): リサイズ時の最小高さ（デフォルト `80.0`）
      # - `collapsible` (`Boolean`): タイトルバーによる折りたたみを許可するか（デフォルト `true`）
      # - 戻り値: `Array | nil`（ウィンドウが閉じている場合は `nil`）
      def begin_window(title, x: nil, y: nil, w: 320.0, h: 240.0, id: "", padding: 12.0, resizable: false, min_w: 120.0, min_h: 80.0, collapsible: true)
        win_id = id.to_s.empty? ? title.to_s : id.to_s
        win = @win_mgr.find_or_create(win_id, title, x, y, w, h, resizable: resizable, min_w: min_w, min_h: min_h, collapsible: collapsible)
        return nil unless win.open

        title_bar_h = 36.0
        wx = win.x
        wy = win.y
        ww = win.w
        wh = win.collapsed ? title_bar_h : win.h
        pad = padding.to_f
        is_active = @win_mgr.active?(win_id)
        win_z = win.z

        # 最小化ボタンの操作判定
        btn_hover = @win_mgr.check_collapse_click(win, title_bar_h, @mouse_x, @mouse_y, @mouse_push)

        # ダブルクリック判定 (ボタン外のタイトルバー)
        double_clicked = false
        if @mouse_push && !btn_hover
          cur_time = (defined?(Audio) ? Audio.time : 0.0)
          double_clicked = @win_mgr.check_title_bar_double_click(win, title_bar_h, @mouse_x, @mouse_y, cur_time)
        end

        unless btn_hover || double_clicked
          unless @win_mgr.check_resize_start(win, @mouse_x, @mouse_y, @mouse_push)
            @win_mgr.check_drag_start(win, title_bar_h, @mouse_x, @mouse_y, @mouse_push)
          end
        end

        # 折りたたみ状態に応じた描画高さを反映
        wh = win.collapsed ? title_bar_h : win.h
        @renderer.draw_window(
          wx, wy, ww, wh, win.title, is_active, @theme,
          z: win_z, title_bar_h: title_bar_h,
          resizable: (win.resizable && !win.collapsed),
          collapsible: win.collapsible,
          collapsed: win.collapsed,
          btn_hover: btn_hover
        )

        content_x = wx + pad
        content_y = wy + title_bar_h + 8.0
        content_w = [ww - pad * 2.0, 0.0].max
        content_h = win.collapsed ? 0.0 : [wh - title_bar_h - pad - 8.0, 0.0].max

        container_state = @layout.begin_container(content_x, content_y, content_w, content_h, clip: true, z: win_z + 10.0)
        [win, win_id, container_state]
      end

      # `begin_window` で開始したウィンドウを終了しクリッピング／レイアウトスコープを閉じる
      #
      # - `state` (`Array | nil`): `begin_window` の戻り値
      # - 戻り値: `nil`
      def end_window(state)
        return unless state
        _win, _win_id, container_state = state
        @layout.end_container(container_state)
      end

      # ドラッグ移動・折りたたみ・最前面切り替え・クリッピング対応のフローティングウィンドウを描画する
      #
      # - `title` (`String`): タイトルバー文字列（`id` 未指定時は識別 ID としても使用）
      # - `x` (`Float | nil`): 初期 X 座標
      # - `y` (`Float | nil`): 初期 Y 座標
      # - `w` (`Float`): 初期幅（デフォルト `320.0`）
      # - `h` (`Float`): 初期高さ（デフォルト `240.0`）
      # - `id` (`String`): ウィンドウ識別 ID（空文字時は `title` を使用）
      # - `padding` (`Float`): 内側余白（デフォルト `12.0`）
      # - `resizable` (`Boolean`): 右下ドラッグによるサイズ変更を許可するか（デフォルト `false`）
      # - `min_w` (`Float`): リサイズ時の最小幅（デフォルト `120.0`）
      # - `min_h` (`Float`): リサイズ時の最小高さ（デフォルト `80.0`）
      # - `collapsible` (`Boolean`): タイトルバーによる折りたたみを許可するか（デフォルト `true`）
      # - `&block`: ウィンドウ内部のウィジェット構築ブロック（`WindowState` を引数に受け取る）
      # - 戻り値: `nil`
      def window(title, x: nil, y: nil, w: 320.0, h: 240.0, id: "", padding: 12.0, resizable: false, min_w: 120.0, min_h: 80.0, collapsible: true)
        state = begin_window(title, x: x, y: y, w: w, h: h, id: id, padding: padding, resizable: resizable, min_w: min_w, min_h: min_h, collapsible: collapsible)
        return unless state
        return unless block_given?

        win, win_id, _cs = state
        @win_mgr.with_window_context(win_id) do
          yield win unless win.collapsed
          end_window(state)
        end
      end

      # --------------------------------------------------
      # ウィジェット (Button / Slider / Label / TextBox / Divider / ProfileGraph)
      # --------------------------------------------------
      # ボタンを描画し、クリックされた瞬間のみ `true` を返す
      #
      # - `label` (`String`): ボタンラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置を使用）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置を使用）
      # - `w` (`Float | nil`): 幅（省略時はコンテナ幅等分または `140.0`）
      # - `h` (`Float`): 高さ（デフォルト `40.0`）
      # - `active` (`Boolean`): `true` の場合に選択・ハイライト状態で描画する（デフォルト `false`）
      # - `id` (`String`): ウィジェット識別 ID（ラベル重複時の衝突回避に使用）
      # - 戻り値: `Boolean`（このフレームでクリックが成立した場合 `true`）
      def button(label, x: nil, y: nil, w: nil, h: 40.0, active: false, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 140.0)
        rh = h.to_f

        hover = can_interact? && @renderer.hit_test_button(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)
        clicked = false

        if @active_id == widget_id
          Input.consume_mouse!
          if @mouse_rel || !@mouse_down
            clicked = true if hover
            @active_id = nil
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            Input.consume_mouse!
            if @mouse_rel
              clicked = true
            else
              @active_id = widget_id
            end
          end
        end

        # クリックが成立した瞬間、トグル/ラジオボタン等でアクティブ化されるケースを考慮し、
        # 1フレームだけホバー色に戻ってチラつくのを防止する
        is_active_visual = active || clicked
        state = is_active_visual ? :active : widget_visual_state(widget_id, hover, active_requires_hover: true)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        @renderer.draw_button(rx, ry, rw, rh, label, state, @theme)
        @layout.advance(rw, rh) if x.nil? && y.nil?
        clicked
      end

      # スライダーを描画し、ドラッグ操作で更新された現在値を返す
      #
      # - `label` (`String`): ラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `value` (`Numeric`): 現在の数値
      # - `min` (`Numeric`): 最小値
      # - `max` (`Numeric`): 最大値
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置を使用）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置を使用）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `200.0`）
      # - `h` (`Float`): 高さ（デフォルト `44.0`）
      # - `step` (`Numeric | nil`): 値の刻み幅（例: `0.1`, `1.0`）
      # - `unit` (`String`): 値表示の末尾に付ける単位文字列（例: `"px"`, `"%"`）
      # - `format` (`String | nil`): 値表示の `sprintf` 書式（例: `"%.2f"`, `"%d"`）
      # - `id` (`String`): ウィジェット識別 ID
      # - `enabled` (`Boolean`): 有効状態（`false` で操作無効・グレーアウト、デフォルト `true`）
      # - 戻り値: `Float`（更新後の値）
      def slider(label, value, min, max, x: nil, y: nil, w: nil, h: 44.0, step: nil, unit: "", format: nil, id: "", enabled: true)
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 200.0)
        rh = h.to_f
        v_val = value.to_f
        v_min = min.to_f
        v_max = max.to_f

        unless enabled
          @renderer.draw_slider(rx, ry, rw, rh, label, v_val, v_min, v_max, :disabled, @theme, unit: unit, format: format)
          @layout.advance(rw, rh) if x.nil? && y.nil?
          return v_val
        end

        hover = can_interact? && @renderer.hit_test_slider(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)

        if @active_id == widget_id
          Input.consume_mouse!
          if @mouse_rel || !@mouse_down
            @active_id = nil
          else
            v_val = calc_slider_value(rx, rw, v_min, v_max, step)
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            Input.consume_mouse!
            v_val = calc_slider_value(rx, rw, v_min, v_max, step)
            @active_id = widget_id unless @mouse_rel
          end
        end

        state = widget_visual_state(widget_id, hover, active_requires_hover: false)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        @renderer.draw_slider(rx, ry, rw, rh, label, v_val, v_min, v_max, state, @theme, unit: unit, format: format)
        @layout.advance(rw, rh) if x.nil? && y.nil?
        v_val
      end

      # テキストラベルを描画する
      #
      # - `text` (`String`): 表示する文字列
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `size` (`Integer`): フォントサイズ（ピクセル単位、デフォルト `18`）
      # - `color` (`Color | Symbol | Array | nil`): 文字色（`0..255` 基準、省略時はテーマ準拠）
      # - 戻り値: `nil`
      def label(text, x: nil, y: nil, size: 18, color: nil)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        f_size = size.to_i
        col = color || @theme.text_color

        @renderer.draw_label(rx, ry, text, f_size, col, @theme)

        f_font = @theme.font || Font.default
        w = f_font.text_width(text.to_s, f_size)
        h = f_size.to_f
        @layout.advance(w, h) if x.nil? && y.nil?
        nil
      end

      # 水平区切り線を描画する
      #
      # - `x` (`Float | nil`): 左端 X 座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y 座標（省略時はレイアウトカーソル + `spacing`）
      # - `w` (`Float | nil`): 線の長さ（省略時はコンテナ幅または `200.0`）
      # - `color` (`Color | Symbol | Array | nil`): 線の色（`0..255` 基準、省略時はテーマ準拠）
      # - `spacing` (`Float`): 上下の余白（ピクセル、デフォルト `6.0`）
      # - 戻り値: `nil`
      def divider(x: nil, y: nil, w: nil, color: nil, spacing: 6.0)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : (@layout.cursor_y + spacing.to_f)
        rw = @layout.resolve_width(w, 200.0)
        border_cfg = @theme.border_normal
        line_col = color || (border_cfg ? border_cfg[1] : Color.new(70, 70, 75, 180))

        Window.draw_line(rx, ry, rx + rw, ry, color: line_col, width: 1.0)
        @layout.advance(rw, spacing.to_f * 2.0 + 1.0) if x.nil? && y.nil?
        nil
      end

      # テキストボックスを描画し、フォーカス中の入力を反映した更新後文字列を返す
      #
      # - `label` (`String`): ウィジェット識別ラベル（`id` 未指定時は識別 ID として使用）
      # - `text` (`String`): 現在の入力テキスト
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `200.0`）
      # - `h` (`Float`): 高さ（デフォルト `42.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `String`（編集を反映した最新の文字列）
      def text_box(label, text, x: nil, y: nil, w: nil, h: 42.0, id: "")
        widget_id = id.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 200.0)
        rh = h.to_f
        cur_text = text.to_s

        hover = can_interact? && @renderer.hit_test_text_box(rx, ry, rw, rh, gui_mouse_x, gui_mouse_y, @theme)

        if @mouse_push
          if hover
            Input.consume_mouse!
            @focus_id = widget_id
            @blink_time = 0.0
            click_x = gui_mouse_x - (rx + 10.0)
            @cursor_pos = TextEdit.caret_index_from_click(cur_text, click_x, @theme)
          elsif @focus_id == widget_id
            clear_focus
          end
        end

        cur_text = cur_text.dup
        is_focused = (@focus_id == widget_id)

        if is_focused
          cur_text, @cursor_pos, reset_blink, unfocus =
            TextEdit.process_focused_input(cur_text, @cursor_pos, rx, ry, rh, @theme)
          @blink_time = 0.0 if reset_blink
          clear_focus if unfocus
          is_focused = (@focus_id == widget_id)
        end

        bt = @blink_time || 0.0
        blink_on = (bt % 1.0) < 0.5
        set_mouse_cursor(:ibeam) if hover || is_focused
        @renderer.draw_text_box(rx, ry, rw, rh, cur_text, is_focused, @cursor_pos || 0, blink_on, @theme)
        @layout.advance(rw, rh) if x.nil? && y.nil?
        cur_text
      end

      # フレーム時間プロファイルグラフ（積み上げヒストグラム＋内訳凡例）を描画する
      #
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `280.0`）
      # - `h` (`Float`): グラフ領域の高さ（デフォルト `80.0`）
      # - `max_ms` (`Float`): グラフ縦軸の最大ミリ秒（デフォルト `33.33`）
      # - `show_legend` (`Boolean`): グラフ下部にカテゴリ別内訳凡例を表示するか（デフォルト `true`）
      # - `id` (`String`): 識別用 ID
      # - 戻り値: `nil`
      def profile_graph(x: nil, y: nil, w: nil, h: 80.0, max_ms: 33.33, show_legend: true, id: "")
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 280.0)
        rh = h.to_f

        total_h = ProfileGraph.draw(
          rx, ry, rw, rh, max_ms.to_f, show_legend,
          can_interact?, gui_mouse_x, gui_mouse_y, @theme
        )
        @layout.advance(rw, total_h) if x.nil? && y.nil?
        nil
      end

      private

      def widget_visual_state(widget_id, hover, active_requires_hover: true)
        if @active_id == widget_id
          return :active if !active_requires_hover || hover
          :normal
        elsif @active_id.nil? && hover
          :hover
        else
          :normal
        end
      end

      def calc_slider_value(rx, rw, v_min, v_max, step = nil)
        knob_radius = 9.0
        usable_w = [rw - knob_radius * 2.0, 1.0].max
        ratio = (gui_mouse_x - (rx + knob_radius)) / usable_w
        ratio = 0.0 if ratio < 0.0
        ratio = 1.0 if ratio > 1.0
        val = v_min + ratio * (v_max - v_min)
        if step && step.to_f > 0.0
          st = step.to_f
          val = ((val - v_min) / st).round * st + v_min
        end
        [[val, v_min].max, v_max].min
      end
    end
  end
end

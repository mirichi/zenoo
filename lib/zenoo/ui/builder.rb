# frozen_string_literal: true

module Zenoo
  module UI
    # コンテナ（Box, Stage, Window, ScrollView 等）で子ウィジェットを手軽に
    # 生成・追加するためのビルダー DSL モジュール
    # Spinel AOT 最適化のため、主要引数を明示的に宣言して動的ディスパッチによる引数脱落を防止
    module Builder
      # コンテナ系

      # 汎用レイアウトコンテナ（`UI::Box`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅（省略時は自動または親レイアウト準拠）
      # - `height` (`Float | nil`): 高さ（省略時は自動または親レイアウト準拠）
      # - `opts` (`Hash`): `UI::Box.new` に渡すキーワードオプション
      # - `&block`: 子ウィジェット構築用ブロック（`UI::Box` インスタンスに渡される）
      # - 戻り値: `UI::Box`
      def box(x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(Box.new(x, y, width: width, height: height, **opts), &block)
      end

      # 縦並びレイアウトコンテナ（`UI::VBox`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅
      # - `height` (`Float | nil`): 高さ
      # - `opts` (`Hash`): `UI::VBox.new` に渡すキーワードオプション
      # - `&block`: 子ウィジェット構築用ブロック
      # - 戻り値: `UI::VBox`
      def vbox(x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(VBox.new(x, y, width: width, height: height, **opts), &block)
      end

      # 横並びレイアウトコンテナ（`UI::HBox`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅
      # - `height` (`Float | nil`): 高さ
      # - `opts` (`Hash`): `UI::HBox.new` に渡すキーワードオプション
      # - `&block`: 子ウィジェット構築用ブロック
      # - 戻り値: `UI::HBox`
      def hbox(x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(HBox.new(x, y, width: width, height: height, **opts), &block)
      end

      # 背景・枠線・タイトル付きパネル（`UI::Panel`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `320.0`）
      # - `height` (`Float`): 高さ（デフォルト `240.0`）
      # - `title` (`String`): パネル上部に表示するタイトル文字列
      # - `opts` (`Hash`): `UI::Panel.new` に渡すキーワードオプション
      # - `&block`: 子ウィジェット構築用ブロック
      # - 戻り値: `UI::Panel`
      def panel(x = 0.0, y = 0.0, width: 320.0, height: 240.0, title: "", **opts, &block)
        add(Panel.new(x, y, width: width, height: height, title: title, **opts), &block)
      end

      # ドラッグ移動・リサイズ・折りたたみ対応ウィンドウ（`UI::Window`）を生成する
      #
      # - `title` (`String`): タイトルバー文字列（デフォルト `"Window"`）
      # - `x` (`Float`): X座標（デフォルト `60.0`）
      # - `y` (`Float`): Y座標（デフォルト `60.0`）
      # - `width` (`Float`): 幅（デフォルト `340.0`）
      # - `height` (`Float`): 高さ（デフォルト `260.0`）
      # - `opts` (`Hash`): `UI::Window.new` に渡すキーワードオプション
      # - `&block`: 子ウィジェット構築用ブロック
      # - 戻り値: `UI::Window`
      def window(title = "Window", x = 60.0, y = 60.0, width: 340.0, height: 260.0, **opts, &block)
        add(Window.new(title, x, y, width: width, height: height, **opts), &block)
      end

      # スクロール可能コンテナ（`UI::ScrollView`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `200.0`）
      # - `height` (`Float`): 高さ（デフォルト `200.0`）
      # - `opts` (`Hash`): `UI::ScrollView.new` に渡すキーワードオプション
      # - `&block`: 子ウィジェット構築用ブロック
      # - 戻り値: `UI::ScrollView`
      def scroll_view(x = 0.0, y = 0.0, width: 200.0, height: 200.0, **opts, &block)
        add(ScrollView.new(x, y, width: width, height: height, **opts), &block)
      end

      # 基本ウィジェット系
      # テキストラベル（`UI::Label`）を生成する
      #
      # - `text` (`String`): 表示文字列
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅（省略時は自動計測）
      # - `height` (`Float | nil`): 高さ（省略時はフォントサイズ基準）
      # - `size` (`Integer | nil`): フォントサイズ
      # - `color` (`Color | Symbol | Array | nil`): テキスト色
      # - `opts` (`Hash`): `UI::Label.new` に渡すキーワードオプション
      # - `&block`: 構築後セットアップ用ブロック
      # - 戻り値: `UI::Label`
      def label(text = "", x = 0.0, y = 0.0, width: nil, height: nil, size: nil, color: nil, **opts, &block)
        add(Label.new(text, x, y, width: width, height: height, size: size, color: color, **opts), &block)
      end

      # 水平区切り線（`UI::Divider`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `200.0`）
      # - `height` (`Float`): 高さ（デフォルト `10.0`）
      # - `color` (`Color | Symbol | Array | nil`): 線の色
      # - `opts` (`Hash`): `UI::Divider.new` に渡すキーワードオプション
      # - `&block`: 構築後セットアップ用ブロック
      # - 戻り値: `UI::Divider`
      def divider(x = 0.0, y = 0.0, width: 200.0, height: 10.0, color: nil, **opts, &block)
        add(Divider.new(x, y, width: width, height: height, color: color, **opts), &block)
      end

      # レイアウト余白・伸縮用スペーサー（`UI::Spacer`）を生成する
      #
      # - `size` (`Float`): 基本サイズ（ピクセル、デフォルト `8.0`）
      # - `flex` (`Float | nil`): フレックス伸長係数
      # - `opts` (`Hash`): `UI::Spacer.new` に渡すキーワードオプション
      # - `&block`: 構築後セットアップ用ブロック
      # - 戻り値: `UI::Spacer`
      def spacer(size = 8.0, flex: nil, **opts, &block)
        add(Spacer.new(size, flex: flex, **opts), &block)
      end

      # 画像表示ウィジェット（`UI::ImageBox`）を生成する
      #
      # - `image` (`Image | nil`): 表示する画像オブジェクト
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅（省略時は画像サイズ）
      # - `height` (`Float | nil`): 高さ（省略時は画像サイズ）
      # - `opts` (`Hash`): `UI::ImageBox.new` に渡すキーワードオプション
      # - `&block`: 構築後セットアップ用ブロック
      # - 戻り値: `UI::ImageBox`
      def image_box(image = nil, x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(ImageBox.new(image, x, y, width: width, height: height, **opts), &block)
      end

      # プッシュ／トグル対応ボタン（`UI::Button`）を生成する
      #
      # - `label` (`String`): ボタンラベル文字列
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `140.0`）
      # - `height` (`Float`): 高さ（デフォルト `38.0`）
      # - `opts` (`Hash`): `UI::Button.new` に渡すキーワードオプション
      # - `&block`: クリック時コールバック（`on_click`）
      # - 戻り値: `UI::Button`
      def button(label = "Button", x = 0.0, y = 0.0, width: 140.0, height: 38.0, **opts, &block)
        add(Button.new(label, x, y, width: width, height: height, **opts, &block))
      end

      # チェックボックス（`UI::Checkbox`）を生成する
      #
      # - `label` (`String`): ラベル文字列
      # - `checked` (`Boolean`): 初期チェック状態（デフォルト `false`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅（省略時は自動計測）
      # - `height` (`Float`): 高さ（デフォルト `28.0`）
      # - `opts` (`Hash`): `UI::Checkbox.new` に渡すキーワードオプション
      # - `&block`: 値変更時コールバック（`on_change`）
      # - 戻り値: `UI::Checkbox`
      def checkbox(label = "", checked = false, x = 0.0, y = 0.0, width: nil, height: 28.0, **opts, &block)
        add(Checkbox.new(label, checked, x, y, width: width, height: height, **opts, &block))
      end

      # ラジオボタン（`UI::RadioButton`）を生成する
      #
      # - `label` (`String`): ラベル文字列
      # - `active` (`Boolean`): 初期選択状態（デフォルト `false`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float | nil`): 幅（省略時は自動計測）
      # - `height` (`Float`): 高さ（デフォルト `28.0`）
      # - `opts` (`Hash`): `UI::RadioButton.new` に渡すキーワードオプション
      # - `&block`: 選択時コールバック（`on_change`）
      # - 戻り値: `UI::RadioButton`
      def radio_button(label = "", active = false, x = 0.0, y = 0.0, width: nil, height: 28.0, **opts, &block)
        add(RadioButton.new(label, active, x, y, width: width, height: height, **opts, &block))
      end

      # プログレスバー（`UI::ProgressBar`）を生成する
      #
      # - `value` (`Float`): 現在値（デフォルト `0.0`）
      # - `min` (`Float`): 最小値（デフォルト `0.0`）
      # - `max` (`Float`): 最大値（デフォルト `100.0`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `220.0`）
      # - `height` (`Float`): 高さ（デフォルト `20.0`）
      # - `opts` (`Hash`): `UI::ProgressBar.new` に渡すキーワードオプション
      # - `&block`: 構築後セットアップ用ブロック
      # - 戻り値: `UI::ProgressBar`
      def progress_bar(value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0, width: 220.0, height: 20.0, **opts, &block)
        add(ProgressBar.new(value, min, max, x, y, width: width, height: height, **opts), &block)
      end

      # 数値調整用スライダー（`UI::Slider`）を生成する
      #
      # - `label` (`String`): ラベル文字列
      # - `value` (`Float`): 初期値（デフォルト `0.0`）
      # - `min` (`Float`): 最小値（デフォルト `0.0`）
      # - `max` (`Float`): 最大値（デフォルト `100.0`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `220.0`）
      # - `height` (`Float`): 高さ（デフォルト `42.0`）
      # - `opts` (`Hash`): `UI::Slider.new` に渡すキーワードオプション
      # - `&block`: 値変更時コールバック（`on_change`）
      # - 戻り値: `UI::Slider`
      def slider(label = "", value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0, width: 220.0, height: 42.0, **opts, &block)
        add(Slider.new(label, value, min, max, x, y, width: width, height: height, **opts, &block))
      end

      # ステップ増減スピナー（`UI::Spinner`）を生成する
      #
      # - `label` (`String`): ラベル文字列
      # - `value` (`Numeric`): 初期値（デフォルト `0`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `220.0`）
      # - `height` (`Float`): 高さ（デフォルト `34.0`）
      # - `opts` (`Hash`): `UI::Spinner.new` に渡すキーワードオプション
      # - `&block`: 値変更時コールバック（`on_change`）
      # - 戻り値: `UI::Spinner`
      def spinner(label = "", value = 0, x = 0.0, y = 0.0, width: 220.0, height: 34.0, **opts, &block)
        add(Spinner.new(label, value, x, y, width: width, height: height, **opts, &block))
      end

      # タブバー切り替えウィジェット（`UI::Tabs`）を生成する
      #
      # - `labels` (`Array<String>`): タブ項目のラベル配列
      # - `selected_index` (`Integer`): 初期選択インデックス（デフォルト `0`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `300.0`）
      # - `height` (`Float`): 高さ（デフォルト `36.0`）
      # - `opts` (`Hash`): `UI::Tabs.new` に渡すキーワードオプション
      # - `&block`: タブ変更時コールバック（`on_change`）
      # - 戻り値: `UI::Tabs`
      def tabs(labels = [], selected_index = 0, x = 0.0, y = 0.0, width: 300.0, height: 36.0, **opts, &block)
        add(Tabs.new(labels, selected_index, x, y, width: width, height: height, **opts, &block))
      end

      # テキスト入力ボックス（`UI::TextBox`）を生成する
      #
      # - `text` (`String`): 初期テキスト
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `220.0`）
      # - `height` (`Float`): 高さ（デフォルト `38.0`）
      # - `opts` (`Hash`): `UI::TextBox.new` に渡すキーワードオプション
      # - `&block`: テキスト変更時コールバック（`on_change`）
      # - 戻り値: `UI::TextBox`
      def text_box(text = "", x = 0.0, y = 0.0, width: 220.0, height: 38.0, **opts, &block)
        add(TextBox.new(text, x, y, width: width, height: height, **opts, &block))
      end

      # ドロップダウン選択（`UI::Dropdown`）を生成する
      #
      # - `items` (`Array<String>`): 選択肢の配列
      # - `selected_index` (`Integer`): 初期選択インデックス（デフォルト `0`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `200.0`）
      # - `height` (`Float`): 高さ（デフォルト `36.0`）
      # - `opts` (`Hash`): `UI::Dropdown.new` に渡すキーワードオプション
      # - `&block`: 選択変更時コールバック（`on_change`）
      # - 戻り値: `UI::Dropdown`
      def dropdown(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 200.0, height: 36.0, **opts, &block)
        add(Dropdown.new(items, selected_index, x, y, width: width, height: height, **opts, &block))
      end

      # リストボックス選択（`UI::ListBox`）を生成する
      #
      # - `items` (`Array<String>`): 選択肢の配列
      # - `selected_index` (`Integer`): 初期選択インデックス（デフォルト `0`）
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `240.0`）
      # - `height` (`Float`): 高さ（デフォルト `150.0`）
      # - `opts` (`Hash`): `UI::ListBox.new` に渡すキーワードオプション
      # - `&block`: 選択変更時コールバック（`on_change`）
      # - 戻り値: `UI::ListBox`
      def list_box(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 240.0, height: 150.0, **opts, &block)
        add(ListBox.new(items, selected_index, x, y, width: width, height: height, **opts, &block))
      end

      # 独自カスタムウィジェット用ヘルパー (on_draw をその場で適用)
      # カスタム描画・独自コライダー付きウィジェット（`UI::Widget`）を生成する
      #
      # - `x` (`Float`): X座標（デフォルト `0.0`）
      # - `y` (`Float`): Y座標（デフォルト `0.0`）
      # - `width` (`Float`): 幅（デフォルト `100.0`）
      # - `height` (`Float`): 高さ（デフォルト `32.0`）
      # - `collider` (`Array | Symbol | nil`): カスタムコライダー設定（指定時は `set_collider` を呼び出す）
      # - `opts` (`Hash`): `UI::Widget.new` に渡すキーワードオプション
      # - `&block`: 構築後セットアップ用ブロック（`on_draw` などの設定に使用）
      # - 戻り値: `UI::Widget`
      def custom(x = 0.0, y = 0.0, width: 100.0, height: 32.0, collider: nil, **opts, &block)
        w = add(Widget.new(x, y, width: width, height: height, **opts))
        w.set_collider(collider) if collider
        w.on_draw(&block) if block
        w
      end
    end
  end
end

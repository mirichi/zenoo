# frozen_string_literal: true

module Zenoo
  module ImGui
    # 描画レンダラー基底クラス (Pluggable Renderer)
    # ユーザーはこのクラスを継承して独自の描画ロジックに差し替えることができます。
    class Renderer
      # ボタンを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ボタンラベル文字列
      # - `state` (`Symbol`): 状態（`:normal`, `:hover`, `:active`）
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_button(x, y, w, h, label, state, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_button must be implemented"
      end

      # スライダーを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ラベル文字列
      # - `value` (`Float`): 現在値
      # - `min` (`Float`): 最小値
      # - `max` (`Float`): 最大値
      # - `state` (`Symbol`): 状態（`:normal`, `:hover`, `:active`, `:disabled`）
      # - `theme` (`Theme`): 適用テーマ
      # - `unit` (`String`): 値の単位サフィックス
      # - `format` (`String | nil`): 数値書式文字列
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_slider(x, y, w, h, label, value, min, max, state, theme, unit: "", format: nil, **opts)
        raise NotImplementedError, "#{self.class}#draw_slider must be implemented"
      end

      # ラベルテキストを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `text` (`String`): 表示文字列
      # - `size` (`Integer`): フォントサイズ
      # - `color` (`Color | Symbol | Array`): テキスト色（`0..255` 基準）
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_label(x, y, text, size, color, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_label must be implemented"
      end

      # テキストボックスを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `text` (`String`): 入力テキスト文字列
      # - `focused` (`Boolean`): フォーカス中か
      # - `cursor_pos` (`Integer`): キャレット文字インデックス
      # - `blink_on` (`Boolean`): キャレット点滅表示状態
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_text_box(x, y, w, h, text, focused, cursor_pos, blink_on, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_text_box must be implemented"
      end

      # チェックボックスを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ラベル文字列
      # - `checked` (`Boolean`): チェック状態
      # - `hover` (`Boolean`): ホバー中か
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_checkbox(x, y, w, h, label, checked, hover, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_checkbox must be implemented"
      end

      # ラジオボタンを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ラベル文字列
      # - `active` (`Boolean`): 選択状態か
      # - `hover` (`Boolean`): ホバー中か
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_radio(x, y, w, h, label, active, hover, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_radio must be implemented"
      end

      # タブバーを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `labels` (`Array<String>`): タブタイトル配列
      # - `selected_index` (`Integer`): 選択中のインデックス
      # - `hover_index` (`Integer | nil`): ホバー中のインデックス
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_tabs(x, y, w, h, labels, selected_index, hover_index, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_tabs must be implemented"
      end

      # スピンボタンを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ラベル文字列
      # - `value_str` (`String`): 表示用の整形済み数値文字列
      # - `minus_hover` (`Boolean`): マイナスボタンがホバー中か
      # - `plus_hover` (`Boolean`): プラスボタンがホバー中か
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_spinner(x, y, w, h, label, value_str, minus_hover, plus_hover, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_spinner must be implemented"
      end

      # スクロールバーを描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `thumb_y` (`Float`): ツマミの Y 座標
      # - `thumb_h` (`Float`): ツマミの高さ
      # - `state` (`Symbol`): 状態（`:normal`, `:hover`, `:active`, `:disabled`）
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_scrollbar(x, y, w, h, thumb_y, thumb_h, state, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_scrollbar must be implemented"
      end

      # リストボックスの外枠・タイトル・背景を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ラベル文字列
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_listbox_frame(x, y, w, h, label, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_listbox_frame must be implemented"
      end

      # リストボックスの 1 項目を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 項目高さ
      # - `text` (`String`): 項目文字列
      # - `selected` (`Boolean`): 選択中か
      # - `hover` (`Boolean`): ホバー中か
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_listbox_item(x, y, w, h, text, selected, hover, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_listbox_item must be implemented"
      end

      # ドロップダウン本体を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 本体高さ
      # - `label` (`String`): ラベル文字列
      # - `selected_text` (`String`): 選択中の文字列
      # - `is_open` (`Boolean`): ポップアップが開いているか
      # - `hover` (`Boolean`): ホバー中か
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_dropdown(x, y, w, h, label, selected_text, is_open, hover, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_dropdown must be implemented"
      end

      # ドロップダウンのポップアップ枠を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `z` (`Float`): 描画 Z 深度
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_dropdown_popup_frame(x, y, w, h, z, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_dropdown_popup_frame must be implemented"
      end

      # ドロップダウンポップアップ内の 1 項目を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 項目高さ
      # - `text` (`String`): 項目文字列
      # - `selected` (`Boolean`): 選択中か
      # - `hover` (`Boolean`): ホバー中か
      # - `z` (`Float`): 描画 Z 深度
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_dropdown_popup_item(x, y, w, h, text, selected, hover, z, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_dropdown_popup_item must be implemented"
      end

      # スクロールビューの外枠を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_scroll_view_frame(x, y, w, h, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_scroll_view_frame must be implemented"
      end

      # テーブルの外枠を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `label` (`String`): ラベル文字列
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_table_frame(x, y, w, h, label, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_table_frame must be implemented"
      end

      # テーブルのヘッダー行を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): ヘッダー高さ
      # - `col_names` (`Array<String>`): カラム名の配列
      # - `col_widths` (`Array<Float>`): 各カラムの幅配列
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_table_header(x, y, w, h, col_names, col_widths, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_table_header must be implemented"
      end

      # テーブルのデータ行を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 行高さ
      # - `row_data` (`Array`): 各セル値の配列
      # - `col_widths` (`Array<Float>`): 各カラムの幅配列
      # - `selected` (`Boolean`): 選択行か
      # - `hover` (`Boolean`): ホバー中か
      # - `stripe` (`Boolean`): 縞模様の偶数行か
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Object | nil`
      def draw_table_row(x, y, w, h, row_data, col_widths, selected, hover, stripe, theme, **opts)
        raise NotImplementedError, "#{self.class}#draw_table_row must be implemented"
      end

      # パネル（コンテナ枠）を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `title` (`String`): タイトル文字列
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 描画オプション（`:color`, `:border_color`, `:border_width`, `:title_size`, `:title_color`, `:padding`, `:font` 等）
      # - 戻り値: `nil`
      def draw_panel(x, y, w, h, title, theme, **opts)
        # デフォルトはシンプルな矩形描画
        bg_col = opts[:color] || Color.new(24, 28, 38, 240)
        border_col = opts[:border_color] || Color.new(60, 70, 90, 200)
        border_w = (opts[:border_width] || 1.5).to_f

        Window.draw_rect(x, y, w, h, color: bg_col, border_color: (border_w > 0.0 ? border_col : nil), border_width: border_w)

        if title && !title.to_s.empty?
          f_font = opts[:font] || theme.font || Font.default
          title_size = (opts[:title_size] || 20).to_i
          title_col = opts[:title_color] || Color::WHITE
          pad = (opts[:padding] || 16.0).to_f
          Window.draw_text(x + pad, y + pad, title.to_s, font: f_font, size: title_size, color: title_col)
        end
      end

      # フローティングウィンドウ装飾（外枠・タイトルバー・折りたたみアイコン）を描画する
      #
      # - `x` (`Float`): X座標
      # - `y` (`Float`): Y座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `title` (`String`): タイトルバー文字列
      # - `active` (`Boolean`): アクティブ（最前面）ウィンドウか
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 描画オプション（`:z`, `:title_bar_h`, `:collapsed`, `:collapsible`, `:btn_hover` 等）
      # - 戻り値: `nil`
      def draw_window(x, y, w, h, title, active, theme, **opts)
        win_z       = (opts[:z] || 0.0).to_f
        title_bar_h = (opts[:title_bar_h] || 36.0).to_f
        bg_col      = theme.win_bg || Color.new(30, 30, 32, 245)
        border_cfg  = active ? (theme.win_border_active || theme.border_active) : (theme.win_border_normal || theme.border_normal)
        border_w    = border_cfg ? border_cfg[0].to_f : 1.0
        border_col  = border_cfg ? border_cfg[1] : Color.new(80, 80, 80)
        title_bg    = active ? (theme.win_title_bg_active || Color.new(52, 52, 58)) : (theme.win_title_bg || Color.new(42, 42, 45))

        Window.draw_rect(x, y, w, h, color: bg_col, border_width: border_w, border_color: border_col, z: win_z)
        Window.draw_rect(x + 1.0, y + 1.0, w - 2.0, title_bar_h, color: title_bg, z: win_z + 1.0)
        unless opts[:collapsed]
          Window.draw_line(x + 1.0, y + title_bar_h + 1.0, x + w - 1.0, y + title_bar_h + 1.0, color: border_col, z: win_z + 1.5)
        end

        if title && !title.to_s.empty?
          f_font = theme.font || Font.default
          f_size = 14
          title_col = active ? (theme.text_color || Color::WHITE) : (theme.text_disabled || Color.new(160, 160, 165))
          Window.draw_text(x + 10.0, y + (title_bar_h - f_size.to_f) / 2.0 + 1.0, title.to_s, font: f_font, size: f_size, color: title_col, z: win_z + 2.0)
        end

        if opts[:collapsible]
          btn_size = 22.0
          bx = x + w - btn_size - 7.0
          by = y + (title_bar_h - btn_size) * 0.5
          icon_col = active ? (theme.text_color || Color::WHITE) : (theme.text_disabled || Color.new(160, 160, 165))

          if opts[:btn_hover]
            Window.draw_rect(bx, by, btn_size, btn_size, radius: 4.0, color: Color.new(255, 255, 255, 45), z: win_z + 2.0)
          end

          if opts[:collapsed]
            Window.draw_rect(bx + 5.0, by + 5.0, 12.0, 12.0, radius: 2.0, color: nil, border_width: 1.5, border_color: icon_col, z: win_z + 2.5)
          else
            Window.draw_line(bx + 5.0, by + 11.0, bx + 17.0, by + 11.0, color: icon_col, width: 2.0, z: win_z + 2.5)
          end
        end
      end

      # ----------------------------------------------------
      # 当たり判定 (Hit-Test)
      # レンダラーの描画形状に合わせてオーバーライド可能
      # ----------------------------------------------------
      # ボタンの当たり判定を行う
      #
      # - `x` (`Float`): ボタン左上 X 座標
      # - `y` (`Float`): ボタン左上 Y 座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `px` (`Float`): 判定点 X 座標
      # - `py` (`Float`): 判定点 Y 座標
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Boolean`
      def hit_test_button(x, y, w, h, px, py, theme, **opts)
        px >= x && px <= (x + w) && py >= y && py <= (y + h)
      end

      # スライダーの当たり判定を行う
      #
      # - `x` (`Float`): スライダー左上 X 座標
      # - `y` (`Float`): スライダー左上 Y 座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `px` (`Float`): 判定点 X 座標
      # - `py` (`Float`): 判定点 Y 座標
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Boolean`
      def hit_test_slider(x, y, w, h, px, py, theme, **opts)
        px >= x && px <= (x + w) && py >= y && py <= (y + h)
      end

      # テキストボックスの当たり判定を行う
      #
      # - `x` (`Float`): テキストボックス左上 X 座標
      # - `y` (`Float`): テキストボックス左上 Y 座標
      # - `w` (`Float`): 幅
      # - `h` (`Float`): 高さ
      # - `px` (`Float`): 判定点 X 座標
      # - `py` (`Float`): 判定点 Y 座標
      # - `theme` (`Theme`): 適用テーマ
      # - `opts` (`Hash`): 拡張レンダラー向けオプション
      # - 戻り値: `Boolean`
      def hit_test_text_box(x, y, w, h, px, py, theme, **opts)
        px >= x && px <= (x + w) && py >= y && py <= (y + h)
      end
    end
  end
end

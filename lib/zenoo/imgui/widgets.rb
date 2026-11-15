# frozen_string_literal: true

module Zenoo
  module ImGui
    # 拡張ウィジェット群 (チェックボックス, ラジオボタン, タブ, スピンボタン, リストボックス, ドロップダウン, スクロールバー)
    module Widgets
      # 状態保持用ハッシュ
      @scroll_states = {} # widget_id => Float (scroll_y)
      @dropdown_open = "" # 開いている widget_id (空文字なら閉)

      class << self
        attr_accessor :dropdown_open, :scroll_states
      end

      # ----------------------------------------------------
      # 1. チェックボックス (Checkbox)
      # ----------------------------------------------------
      # チェックボックスを描画し、クリックでトグルした真偽値を返す
      #
      # - `label` (`String`): 横に表示するラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `checked` (`Boolean`): 現在のチェック状態
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動計算）
      # - `h` (`Float`): 高さ（デフォルト `28.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Boolean`（トグル後のチェック状態）
      def checkbox(label, checked, x: nil, y: nil, w: nil, h: 28.0, id: "")
        widget_id = resolve_widget_id(label, id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rh = h.to_f
        f_font = @theme.font || Font.default
        f_size = @theme.font_size.to_i > 0 ? @theme.font_size.to_i : 15
        text_w = f_font.text_width(label.to_s, f_size)

        box_size = 20.0
        rw = @layout.resolve_width(w, box_size + 10.0 + text_w + 8.0)

        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        new_checked = !!checked

        if @active_id == widget_id
          Input.consume_mouse!
          if @mouse_rel || !@mouse_down
            new_checked = !checked if hover
            @active_id = nil
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            Input.consume_mouse!
            if @mouse_rel
              new_checked = !checked
            else
              @active_id = widget_id
            end
          end
        end

        # 描画
        @renderer.draw_checkbox(rx, ry, rw, rh, label, new_checked, hover, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        new_checked
      end

      # ----------------------------------------------------
      # 2. ラジオボタン (Radio Button)
      # ----------------------------------------------------
      # ラジオボタンを描画し、クリックされた瞬間のみ `true` を返す
      #
      # - `label` (`String`): 横に表示するラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `active` (`Boolean`): 現在選択されている状態か
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動計算）
      # - `h` (`Float`): 高さ（デフォルト `28.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Boolean`（このフレームでクリックされた場合 `true`）
      def radio(label, active, x: nil, y: nil, w: nil, h: 28.0, id: "")
        widget_id = resolve_widget_id(label, id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rh = h.to_f
        f_font = @theme.font || Font.default
        f_size = @theme.font_size.to_i > 0 ? @theme.font_size.to_i : 15
        text_w = f_font.text_width(label.to_s, f_size)

        circle_r = 9.0
        circle_d = circle_r * 2.0
        rw = @layout.resolve_width(w, circle_d + 10.0 + text_w + 8.0)

        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
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
            clicked = true
            @active_id = widget_id unless @mouse_rel
          end
        end

        # 描画 (現在選択中、または今クリックされたなら選択状態で描画)
        @renderer.draw_radio(rx, ry, rw, rh, label, !!active || clicked, hover, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        clicked
      end

      # ----------------------------------------------------
      # 3. タブバー (Tabs)
      # ----------------------------------------------------
      # タブバーを描画し、クリック操作を反映した選択インデックスを返す
      #
      # - `labels` (`Array<String>`): タブタイトル配列（例: `["General", "Audio", "Video"]`）
      # - `selected_index` (`Integer`): 現在選択中のタブインデックス（`0..`）
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `300.0`）
      # - `h` (`Float`): 高さ（デフォルト `36.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Integer`（更新後の選択インデックス）
      def tabs(labels, selected_index, x: nil, y: nil, w: nil, h: 36.0, id: "")
        widget_id = resolve_widget_id("tabs_#{labels.join('_')}", id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 300.0)
        rh = h.to_f
        count = labels.length
        return selected_index if count == 0 || rw <= 0.0

        tab_w = rw / count.to_f

        new_selected = selected_index.to_i
        hover_idx = nil

        if @active_id.nil?
          i = 0
          while i < count
            tx = rx + i.to_f * tab_w
            hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, tx, ry, tab_w, rh)

            if hover
              set_mouse_cursor(:hand)
              hover_idx = i
              @hot_id = "#{widget_id}_#{i}"
              if @mouse_push
                Input.consume_mouse!
                new_selected = i
              end
            end
            i += 1
          end
        end

        # 描画
        @renderer.draw_tabs(rx, ry, rw, rh, labels, new_selected, hover_idx, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        new_selected
      end

      # ----------------------------------------------------
      # 4. スピンボタン (Spinner / SpinBox)
      # ----------------------------------------------------
      # `[−] [数値表示] [+]` スタイルのステップ数値変更スピンボタンを描画し、更新後の値を返す
      #
      # - `label` (`String`): 左側に表示するラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `value` (`Numeric`): 現在の数値（`Float` を渡すと小数演算、`Integer` を渡すと整数演算）
      # - `min` (`Numeric | nil`): 最小値（`nil` で下限なし）
      # - `max` (`Numeric | nil`): 最大値（`nil` で上限なし）
      # - `step` (`Numeric`): `[−]`/`[+]` ボタン 1 クリックあたりの増減量（デフォルト `1`）
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `220.0`）
      # - `h` (`Float`): 高さ（デフォルト `36.0`）
      # - `format` (`String | nil`): 値表示の `sprintf` 書式（省略時は `Float` なら `"%.2f"`、`Integer` なら `"%d"`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Numeric`（更新後の値）
      def spinner(label, value, min: nil, max: nil, step: 1, x: nil, y: nil, w: nil, h: 36.0, format: nil, id: "")
        widget_id = resolve_widget_id(label, id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 220.0)
        rh = h.to_f
        cur_val = value.is_a?(Float) ? value.to_f : value.to_i
        st = step.is_a?(Float) ? step.to_f : step.to_i

        btn_w = 32.0
        f_font = @theme.font || Font.default
        f_size = @theme.font_size.to_i > 0 ? @theme.font_size.to_i : 14

        min_ctrl_w = btn_w * 2.0 + 30.0
        if label.to_s.empty?
          label_w = 0.0
        else
          raw_lw = f_font.text_width(label.to_s, f_size) + 12.0
          max_lw = [rw - min_ctrl_w, 0.0].max
          label_w = [raw_lw, max_lw].min
        end

        # 操作部分の矩形
        ctrl_x = rx + label_w
        ctrl_w = [rw - label_w, 0.0].max
        eff_btn_w = (btn_w * 2.0 + 8.0 > ctrl_w) ? [ctrl_w * 0.35, 4.0].max : btn_w

        # マイナスボタン領域
        minus_x = ctrl_x
        minus_hover = @active_id.nil? && can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, minus_x, ry, eff_btn_w, rh)

        # プラスボタン領域
        plus_x = ctrl_x + ctrl_w - eff_btn_w
        plus_hover = @active_id.nil? && can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, plus_x, ry, eff_btn_w, rh)

        # 入力処理
        set_mouse_cursor(:hand) if minus_hover || plus_hover
        if minus_hover
          @hot_id = "#{widget_id}_minus"
          if @mouse_push
            Input.consume_mouse!
            cur_val -= st
            cur_val = [cur_val, min].max if min
          end
        elsif plus_hover
          @hot_id = "#{widget_id}_plus"
          if @mouse_push
            Input.consume_mouse!
            cur_val += st
            cur_val = [cur_val, max].min if max
          end
        end

        cur_val = [cur_val, min].max if min
        cur_val = [cur_val, max].min if max

        fmt_str = format || (cur_val.is_a?(Float) ? "%.2f" : "%d")
        val_str = sprintf(fmt_str, cur_val)

        # 描画
        @renderer.draw_spinner(rx, ry, rw, rh, label, val_str, minus_hover, plus_hover, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        cur_val
      end

      # ----------------------------------------------------
      # 5. スクロールバー (ScrollBar)
      # ----------------------------------------------------
      # 縦スクロールバーを描画し、ドラッグ／ホイール操作を反映したスクロール位置を返す
      #
      # - `value` (`Float`): 現在のスクロール位置（`0.0..max_scroll`）
      # - `total_size` (`Float`): コンテンツ全体の高さ
      # - `view_size` (`Float`): 表示領域の高さ
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float`): 幅（デフォルト `14.0`）
      # - `h` (`Float`): 高さ（デフォルト `150.0`）
      # - `allow_wheel` (`Boolean`): ホイール操作を受け付けるか（デフォルト `true`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Float`（更新されたスクロール位置）
      def scrollbar(value, total_size, view_size, x: nil, y: nil, w: 14.0, h: 150.0, allow_wheel: true, id: "")
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        widget_id = resolve_widget_id("scrollbar_#{rx.to_i}_#{ry.to_i}", id)
        rw = w.to_f
        rh = h.to_f
        cur_val = value.to_f
        tot = total_size.to_f
        vw  = view_size.to_f

        max_scroll = [tot - vw, 0.0].max
        if max_scroll <= 0.0
          # スクロール不要時は無効バーを描画
          @renderer.draw_scrollbar(rx, ry, rw, rh, 0.0, 0.0, :disabled, @theme)
          @layout.advance(rw, rh) if x.nil? && y.nil?
          return 0.0
        end

        thumb_h = [[(vw / tot) * rh, 20.0].max, rh].min
        ratio = cur_val / max_scroll
        thumb_y = ry + ratio * (rh - thumb_h)

        hover_track = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        hover_thumb = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, thumb_y, rw, thumb_h)
        set_mouse_cursor(:hand) if hover_thumb || @active_id == widget_id

        if @active_id == widget_id
          Input.consume_mouse!
          if @mouse_rel || !@mouse_down
            @active_id = nil
          else
            # ドラッグによるスクロール値更新
            track_avail = [rh - thumb_h, 1.0].max
            cur_ratio = (gui_mouse_y - (ry + thumb_h * 0.5)) / track_avail
            cur_ratio = 0.0 if cur_ratio < 0.0
            cur_ratio = 1.0 if cur_ratio > 1.0
            cur_val = cur_ratio * max_scroll
          end
        elsif @active_id.nil? && hover_track
          @hot_id = widget_id
          if @mouse_push
            Input.consume_mouse!
            @active_id = widget_id
            track_avail = [rh - thumb_h, 1.0].max
            cur_ratio = (gui_mouse_y - (ry + thumb_h * 0.5)) / track_avail
            cur_ratio = 0.0 if cur_ratio < 0.0
            cur_ratio = 1.0 if cur_ratio > 1.0
            cur_val = cur_ratio * max_scroll
          end
        end

        # ホイールスクロール
        if allow_wheel && hover_track && Input.mouse_wheel_y != 0
          cur_val -= Input.mouse_wheel_y.to_f * 30.0
        end

        cur_val = [[cur_val, 0.0].max, max_scroll].min

        # 描画
        thumb_ratio = max_scroll > 0 ? (cur_val / max_scroll) : 0.0
        actual_thumb_y = ry + thumb_ratio * (rh - thumb_h)
        state = (@active_id == widget_id) ? :active : (hover_thumb ? :hover : :normal)
        @renderer.draw_scrollbar(rx, ry, rw, rh, actual_thumb_y, thumb_h, state, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        cur_val
      end

      # ----------------------------------------------------
      # 6. リストボックス (ListBox)
      # ----------------------------------------------------
      # スクロール対応のリストボックスを描画し、クリック選択を反映した選択インデックスを返す
      #
      # - `label` (`String`): 上部に表示するラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `selected_index` (`Integer`): 現在選択中のインデックス
      # - `items` (`Array<String>`): 選択肢文字列の配列
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `240.0`）
      # - `h` (`Float | nil`): リスト枠の高さ（省略時は項目数に応じて自動計算、最大 `140.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Integer`（更新された選択インデックス）
      def listbox(label, selected_index, items, x: nil, y: nil, w: nil, h: nil, id: "")
        widget_id = resolve_widget_id(label.to_s.empty? ? "listbox_#{items.length}" : label, id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 240.0)
        item_h = 28.0

        has_label = !label.to_s.empty?
        label_h = has_label ? 22.0 : 0.0

        list_h = h ? h.to_f : [items.length * item_h + 8.0, 140.0].min
        list_y = ry + label_h

        # 外枠描画 (ラベル＋背景ボックス)
        @renderer.draw_listbox_frame(rx, ry, rw, list_h, label, @theme)

        pad_y = 4.0
        total_content_h = items.length.to_f * item_h + pad_y * 2.0
        inner_h = [list_h - 4.0, 1.0].max
        needs_scroll = total_content_h > inner_h
        scroll_w = needs_scroll ? 12.0 : 0.0
        content_w = rw - scroll_w - 4.0

        # スクロールオフセット取得 / 更新
        Widgets.scroll_states[widget_id] ||= 0.0
        scroll_y = Widgets.scroll_states[widget_id]

        box_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, list_y, rw, list_h)
        if box_hover && Input.mouse_wheel_y != 0
          scroll_y -= Input.mouse_wheel_y.to_f * item_h
        end
        max_s = [total_content_h - inner_h, 0.0].max
        scroll_y = [[scroll_y, 0.0].max, max_s].min
        Widgets.scroll_states[widget_id] = scroll_y

        new_selected = selected_index.nil? ? nil : selected_index.to_i

        # クリップ領域内で各アイテムを描画
        prev_ox, prev_oy = Window.push_clip_scope(rx + 2.0, list_y + 2.0, content_w, inner_h, local: false)
        i = 0
        len = items.length
        while i < len
          it_text = items[i].to_s
          iy = list_y + pad_y + (i.to_f * item_h) - scroll_y

          # 画面外カリング (領域内に少しでも掛かっていれば描画)
          if iy + item_h >= (list_y + 2.0) && iy <= (list_y + list_h - 2.0)
            it_hover = @active_id.nil? && box_hover && in_rect?(gui_mouse_x, gui_mouse_y, rx + 2.0, iy, content_w, item_h)
            is_sel = (new_selected == i)

            if it_hover
              set_mouse_cursor(:hand)
              @hot_id = "#{widget_id}_item_#{i}"
              if @mouse_push
                Input.consume_mouse!
                new_selected = i
              end
            end

            # アイテム描画
            @renderer.draw_listbox_item(rx, iy, content_w, item_h, it_text, is_sel, it_hover, @theme)
          end
          i += 1
        end
        Window.pop_clip_scope(prev_ox, prev_oy)

        # スクロールバー描画 (必要な場合)
        if needs_scroll
          sb_x = rx + rw - scroll_w - 2.0
          sb_y = list_y + 2.0
          sb_h = list_h - 4.0
          Widgets.scroll_states[widget_id] = scrollbar(
            scroll_y, total_content_h, inner_h,
            x: sb_x, y: sb_y, w: scroll_w, h: sb_h, allow_wheel: false, id: "#{widget_id}_sb"
          )
        end

        total_advance_h = label_h + list_h
        @layout.advance(rw, total_advance_h) if x.nil? && y.nil?
        new_selected
      end

      # ----------------------------------------------------
      # 7. ドロップダウンリスト (Dropdown / ComboBox)
      # ----------------------------------------------------
      # ドロップダウンリスト（コンボボックス）を描画し、更新された選択インデックスを返す
      #
      # - `label` (`String`): 上部に表示するラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `selected_index` (`Integer`): 現在選択中のインデックス
      # - `items` (`Array<String>`): 選択肢の文字列配列
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `200.0`）
      # - `h` (`Float`): コントロール本体の高さ（デフォルト `36.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - 戻り値: `Integer`（更新された選択インデックス）
      def dropdown(label, selected_index, items, x: nil, y: nil, w: nil, h: 36.0, id: "")
        widget_id = resolve_widget_id(label.to_s.empty? ? "dropdown_#{items.length}" : label, id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 200.0)
        rh = h.to_f

        has_label = !label.to_s.empty?
        label_h = has_label ? 20.0 : 0.0
        ctrl_y = ry + label_h

        was_open = (Widgets.dropdown_open == widget_id)
        if was_open && items.empty?
          Widgets.dropdown_open = ""
          was_open = false
        end

        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ctrl_y, rw, rh)
        new_selected = selected_index.nil? ? nil : selected_index.to_i

        # 開閉トグル処理
        if hover
          set_mouse_cursor(:hand)
          @hot_id = widget_id if @active_id.nil?
          if @mouse_push && @active_id.nil?
            Input.consume_mouse!
            unless items.empty?
              Widgets.dropdown_open = was_open ? "" : widget_id
              Widgets.scroll_states["#{widget_id}_pop"] = 0.0 unless was_open
            end
          end
        end

        now_open = (Widgets.dropdown_open == widget_id) && !items.empty?
        item_h = 28.0
        pad_y = 3.0
        total_pop_h = items.length.to_f * item_h + pad_y * 2.0
        pop_h = [total_pop_h, 180.0].min
        max_pop_scroll = [total_pop_h - pop_h, 0.0].max
        pop_scroll = [[Widgets.scroll_states["#{widget_id}_pop"] || 0.0, 0.0].max, max_pop_scroll].min
        hover_idx = nil

        sx = rx + Window.__offset_x
        sy = ctrl_y + rh + 2.0 + Window.__offset_y

        if was_open && now_open
          @evaluated = true
          pop_hover = in_rect?(@mouse_x, @mouse_y, sx, sy, rw, pop_h)
          if pop_hover && max_pop_scroll > 0.0 && Input.mouse_wheel_y != 0
            pop_scroll -= Input.mouse_wheel_y.to_f * item_h
            pop_scroll = [[pop_scroll, 0.0].max, max_pop_scroll].min
          end

          if pop_hover
            i = 0
            len = items.length
            while i < len
              iy = sy + pad_y + i.to_f * item_h - pop_scroll
              if in_rect?(@mouse_x, @mouse_y, sx, iy, rw, item_h)
                hover_idx = i
                set_mouse_cursor(:hand)
                @hot_id = "#{widget_id}_pop_#{i}"
                if @mouse_push
                  Input.consume_mouse!
                  new_selected = i
                  Widgets.dropdown_open = ""
                  now_open = false
                end
                break
              end
              i += 1
            end
          elsif @mouse_push && !hover
            Widgets.dropdown_open = ""
            now_open = false
          end
        end

        Widgets.scroll_states["#{widget_id}_pop"] = pop_scroll if now_open || was_open

        # 現在選択中のテキスト
        sel_text = (new_selected && new_selected >= 0 && new_selected < items.length) ? items[new_selected].to_s : ""

        # コントロール本体の描画
        @renderer.draw_dropdown(rx, ry, rw, rh, label, sel_text, now_open, hover, @theme)

        if now_open
          queue_dropdown_overlay({
            px: sx, py: sy, pw: rw, ph: pop_h,
            items: items, selected: new_selected,
            scroll_y: pop_scroll, item_h: item_h, hover_idx: hover_idx
          })
        end

        total_advance_h = label_h + rh
        @layout.advance(rw, total_advance_h) if x.nil? && y.nil?
        new_selected
      end

      # ----------------------------------------------------
      # 8. スクロールビュー (Scroll View コンテナブロック)
      # ----------------------------------------------------
      # ブロック内のウィジェットを縦スクロール可能なクリップ領域内にレイアウトして描画する
      #
      # - `title_or_id` (`String | Symbol`): スクロール状態の保持に使用する識別 ID
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `300.0`）
      # - `h` (`Float | nil`): 枠高さ（省略時はコンテナの残り高さへ自動フィット、または `200.0`）
      # - `content_h` (`Float | nil`): 最小コンテンツ高さの明示指定（省略時は内部要素から自動計測）
      # - `&block`: スクロール領域内に描画するウィジェット構築ブロック
      # - 戻り値: `Float | nil`
      def scroll_view(title_or_id, x: nil, y: nil, w: nil, h: nil, content_h: nil)
        state = begin_scroll_view(title_or_id, x: x, y: y, w: w, h: h, content_h: content_h)
        yield if block_given?
        end_scroll_view(state)
      end

      # ----------------------------------------------------
      # 10. テーブル / リストビュー (Table)
      # ----------------------------------------------------
      # スクロール・カラム幅指定・行選択・カスタム描画に対応したテーブル（リストビュー）を描画する
      #
      # - `label` (`String`): 上部に表示するラベル文字列（`id` 未指定時は識別 ID としても使用）
      # - `columns` (`Array`): カラム定義の配列（文字列、`[名前, 幅]`、または `{ name:, width: }`）
      # - `rows` (`Array<Array>`): 行データの 2 次元配列
      # - `selected_index` (`Integer | nil`): 選択中の行インデックス（デフォルト `nil`）
      # - `x` (`Float | nil`): X座標（省略時はレイアウトカーソル位置）
      # - `y` (`Float | nil`): Y座標（省略時はレイアウトカーソル位置）
      # - `w` (`Float | nil`): 幅（省略時は自動割り当てまたは `280.0`）
      # - `h` (`Float | nil`): 全体の高さ（省略時は行数に応じて自動計算、最大 `180.0`）
      # - `item_height` (`Float`): 1 行あたりの高さ（デフォルト `20.0`）
      # - `id` (`String`): ウィジェット識別 ID
      # - `&block`: 行カスタム描画用ブロック（指定時は `(row, row_index, selected, hovered, x, y, w, row_h)` を渡す）
      # - 戻り値: `Integer | nil`（更新された選択行インデックス）
      def table(label, columns, rows, selected_index = nil, x: nil, y: nil, w: nil, h: nil, item_height: 20.0, id: "")
        state = prepare_table_state(label, columns, rows, selected_index, x, y, w, h, item_height, id)
        draw_table_chrome(state)
        new_selected = state[:selected]
        scroll_y = state[:scroll_y]
        rx = state[:rx]
        body_y = state[:body_y]
        body_h = state[:body_h]
        content_w = state[:content_w]
        row_h = state[:row_h]
        pad_y = state[:pad_y]

        prev_ox, prev_oy = Window.push_clip_scope(rx + 2.0, body_y, content_w, body_h, local: false)
        i = 0
        len = rows.length
        while i < len
          iy = body_y + pad_y + (i.to_f * row_h) - scroll_y
          if iy + row_h >= body_y && iy <= (body_y + body_h)
            it_hover, is_sel, new_selected = eval_table_row(state, i, iy, new_selected)
            if block_given?
              yield(rows[i], i, is_sel, it_hover, rx + 2.0, iy, content_w, row_h)
            else
              @renderer.draw_table_row(rx + 2.0, iy, content_w, row_h, rows[i], state[:col_widths], is_sel, it_hover, i.even?, @theme)
            end
          end
          i += 1
        end
        Window.pop_clip_scope(prev_ox, prev_oy)

        finish_table(state, x, y)
        new_selected
      end

      private

      def begin_scroll_view(title_or_id, x: nil, y: nil, w: nil, h: nil, content_h: nil)
        widget_id = resolve_widget_id(title_or_id, "")
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 300.0)

        avail_h = @layout.available_height
        rh = if h
               req_h = h.to_f
               avail_h ? [req_h, [avail_h - 4.0, 0.0].max].min : req_h
             elsif avail_h && avail_h > 40.0
               avail_h - 4.0
             else
               200.0
             end

        pad_y = 6.0
        clip_h = [rh - 4.0, 1.0].max

        stored_h = Widgets.scroll_states["#{widget_id}_content_h"] || (content_h ? content_h.to_f : rh)
        tot_h = [stored_h, content_h ? content_h.to_f : 0.0].max

        Widgets.scroll_states[widget_id] ||= 0.0
        scroll_y = Widgets.scroll_states[widget_id]

        total_range = tot_h + pad_y * 2.0
        max_s = [total_range - clip_h, 0.0].max

        needs_scroll = max_s > 0.0
        sb_w = needs_scroll ? 12.0 : 0.0
        view_w = rw - sb_w - 4.0

        box_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        if box_hover && Input.mouse_wheel_y != 0
          scroll_y -= Input.mouse_wheel_y.to_f * 30.0
        end
        scroll_y = [[scroll_y, 0.0].max, max_s].min
        Widgets.scroll_states[widget_id] = scroll_y

        @renderer.draw_scroll_view_frame(rx, ry, rw, rh, @theme)
        prev_ox, prev_oy = Window.push_clip_scope(rx + 2.0, ry + 2.0, view_w, clip_h, local: true)

        start_y = pad_y - scroll_y
        @layout.push_scope(content_w: view_w - 4.0, cursor_x: 4.0, cursor_y: start_y)

        {
          widget_id: widget_id, rx: rx, ry: ry, rw: rw, rh: rh,
          start_y: start_y, scroll_y: scroll_y, total_range: total_range,
          clip_h: clip_h, sb_w: sb_w, needs_scroll: needs_scroll,
          auto_pos: (x.nil? && y.nil?), prev_ox: prev_ox, prev_oy: prev_oy
        }
      end

      def end_scroll_view(state)
        end_y = @layout.cursor_y
        sp_y = @layout.spacing_y
        content_bottom = (end_y > state[:start_y]) ? [end_y - sp_y - state[:start_y], 0.0].max : 0.0
        Widgets.scroll_states["#{state[:widget_id]}_content_h"] = content_bottom

        @layout.pop_scope
        Window.pop_clip_scope(state[:prev_ox], state[:prev_oy])

        if state[:needs_scroll]
          sb_x = state[:rx] + state[:rw] - state[:sb_w] - 2.0
          sb_y = state[:ry] + 2.0
          Widgets.scroll_states[state[:widget_id]] = scrollbar(
            state[:scroll_y], state[:total_range], state[:clip_h],
            x: sb_x, y: sb_y, w: state[:sb_w], h: state[:clip_h],
            allow_wheel: false, id: "#{state[:widget_id]}_sb"
          )
        end

        @layout.advance(state[:rw], state[:rh]) if state[:auto_pos]
      end

      def prepare_table_state(label, columns, rows, selected_index, x, y, w, h, item_height, id)
        base_id = label.to_s.empty? ? "table_#{columns.length}_#{rows.length}" : label
        widget_id = resolve_widget_id(base_id, id)
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 280.0)
        row_h = item_height.to_f > 0.0 ? item_height.to_f : 20.0
        header_h = 22.0

        label_h = label.to_s.empty? ? 0.0 : 22.0
        table_y = ry + label_h
        table_h = if h
                    [h.to_f - label_h, 30.0].max
                  else
                    [rows.length.to_f * row_h + header_h + 8.0, 180.0].min
                  end

        pad_y = 2.0
        total_content_h = rows.length.to_f * row_h + pad_y * 2.0
        body_y = table_y + header_h + 2.0
        body_h = [table_h - header_h - 6.0, 1.0].max
        needs_scroll = total_content_h > body_h
        scroll_w = needs_scroll ? 10.0 : 0.0
        content_w = rw - scroll_w - 4.0

        col_names, col_widths = resolve_table_columns(columns, content_w)

        Widgets.scroll_states[widget_id] ||= 0.0
        scroll_y = Widgets.scroll_states[widget_id]
        box_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, table_y, rw, table_h)
        if box_hover && Input.mouse_wheel_y != 0
          scroll_y -= Input.mouse_wheel_y.to_f * row_h * 1.5
        end
        max_s = [total_content_h - body_h, 0.0].max
        scroll_y = [[scroll_y, 0.0].max, max_s].min
        Widgets.scroll_states[widget_id] = scroll_y

        {
          widget_id: widget_id, label: label, rx: rx, ry: ry, rw: rw,
          label_h: label_h, table_y: table_y, table_h: table_h, header_h: header_h,
          body_y: body_y, body_h: body_h, pad_y: pad_y, row_h: row_h,
          total_content_h: total_content_h, needs_scroll: needs_scroll,
          scroll_w: scroll_w, content_w: content_w,
          col_names: col_names, col_widths: col_widths,
          scroll_y: scroll_y, box_hover: box_hover,
          selected: selected_index.nil? ? nil : selected_index.to_i
        }
      end

      def resolve_table_columns(columns, content_w)
        col_names = []
        col_widths = []
        fixed_total = 0.0
        flex_count = 0
        ci = 0
        len = columns.length
        while ci < len
          col = columns[ci]
          if col.is_a?(Array)
            cname = col[0].to_s
            cwidth = col[1] ? col[1].to_f : nil
          elsif col.is_a?(Hash)
            cname = (col[:name] || col["name"]).to_s
            cwidth = (col[:width] || col["width"]) ? (col[:width] || col["width"]).to_f : nil
          else
            cname = col.to_s
            cwidth = nil
          end
          col_names << cname
          if cwidth && cwidth > 0.0
            col_widths << cwidth
            fixed_total += cwidth
          else
            col_widths << nil
            flex_count += 1
          end
          ci += 1
        end
        flex_w = flex_count > 0 ? [((content_w - fixed_total) / flex_count.to_f), 20.0].max : 0.0
        ci = 0
        while ci < len
          col_widths[ci] ||= flex_w
          ci += 1
        end
        [col_names, col_widths]
      end

      def draw_table_chrome(state)
        @renderer.draw_table_frame(state[:rx], state[:ry], state[:rw], state[:table_h], state[:label], @theme)
        @renderer.draw_table_header(
          state[:rx] + 2.0, state[:table_y] + 2.0, state[:content_w], state[:header_h],
          state[:col_names], state[:col_widths], @theme
        )
      end

      def eval_table_row(state, i, iy, new_selected)
        it_hover = @active_id.nil? && state[:box_hover] &&
                   in_rect?(gui_mouse_x, gui_mouse_y, state[:rx] + 2.0, iy, state[:content_w], state[:row_h])
        is_sel = (new_selected == i)
        if it_hover
          set_mouse_cursor(:hand)
          @hot_id = "#{state[:widget_id]}_row_#{i}"
          if @mouse_push
            Input.consume_mouse!
            new_selected = i
          end
        end
        [it_hover, is_sel, new_selected]
      end

      def finish_table(state, x, y)
        if state[:needs_scroll]
          sb_x = state[:rx] + state[:rw] - state[:scroll_w] - 2.0
          Widgets.scroll_states[state[:widget_id]] = scrollbar(
            state[:scroll_y], state[:total_content_h], state[:body_h],
            x: sb_x, y: state[:body_y], w: state[:scroll_w], h: state[:body_h],
            allow_wheel: false, id: "#{state[:widget_id]}_sb"
          )
        end
        @layout.advance(state[:rw], state[:label_h] + state[:table_h]) if x.nil? && y.nil?
      end
    end
  end
end

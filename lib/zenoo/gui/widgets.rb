# frozen_string_literal: true

module Zenoo
  module GUI
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
      # クリックで checked の真偽値をトグルし、新しい Boolean を返却
      def checkbox(label, checked, x: nil, y: nil, w: nil, h: 28.0, id: "")
        widget_id = id.to_s.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rh = h.to_f
        f_font = @theme.font || Font.default
        f_size = 15
        text_w = f_font.text_width(label.to_s, f_size)

        box_size = 20.0
        rw = w ? w.to_f : (box_size + 10.0 + text_w + 8.0)
        box_y = ry + (rh - box_size) * 0.5

        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        new_checked = !!checked

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            new_checked = !checked if hover
            @active_id = nil
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
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
      # クリックされた場合に true を返却 (選択状態の維持・更新)
      def radio(label, active, x: nil, y: nil, w: nil, h: 28.0, id: "")
        widget_id = id.to_s.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rh = h.to_f
        f_font = @theme.font || Font.default
        f_size = 15
        text_w = f_font.text_width(label.to_s, f_size)

        circle_r = 9.0
        circle_d = circle_r * 2.0
        rw = w ? w.to_f : (circle_d + 10.0 + text_w + 8.0)
        cx = rx + circle_r + 2.0
        cy = ry + rh * 0.5

        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        set_mouse_cursor(:hand) if hover || @active_id == widget_id
        new_active = !!active

        if @active_id == widget_id
          if @mouse_rel || !@mouse_down
            new_active = true if hover
            @active_id = nil
          end
        elsif @active_id.nil? && hover
          @hot_id = widget_id
          if @mouse_push
            new_active = true
            @active_id = widget_id unless @mouse_rel
          end
        end

        # 描画
        @renderer.draw_radio(rx, ry, rw, rh, label, new_active, hover, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        new_active
      end
      alias radio_button radio

      # ----------------------------------------------------
      # 3. タブバー (Tabs / Tab Bar)
      # ----------------------------------------------------
      # labels: タブタイトル配列 (例: ["General", "Audio", "Video"])
      # selected_index: 現在選択中のインデックス (0..)
      # 返り値: 更新された選択インデックス
      def tabs(labels, selected_index, x: nil, y: nil, w: nil, h: 36.0, id: "")
        widget_id = id.to_s.empty? ? "tabs_#{labels.join('_')}" : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 300.0)
        rh = h.to_f
        count = labels.length
        return selected_index if count == 0

        tab_w = rw / count.to_f
        f_font = @theme.font || Font.default
        f_size = 14
        accent = @theme.accent_color || Color.new(80, 140, 240)

        new_selected = selected_index.to_i
        hover_idx = nil

        i = 0
        while i < count
          tx = rx + i.to_f * tab_w
          hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, tx, ry, tab_w, rh)

          if hover
            set_mouse_cursor(:hand)
            hover_idx = i
            @hot_id = "#{widget_id}_#{i}"
            if @mouse_push
              new_selected = i
            end
          end
          i += 1
        end

        # 描画
        @renderer.draw_tabs(rx, ry, rw, rh, labels, new_selected, hover_idx, @theme)

        @layout.advance(rw, rh) if x.nil? && y.nil?
        new_selected
      end
      alias tab_bar tabs

      # ----------------------------------------------------
      # 4. スピンボタン (Spinner / SpinBox)
      # ----------------------------------------------------
      # [-] [ 数値表示 ] [+] スタイルのステップ数値変更コントロール
      def spinner(label, value, min: nil, max: nil, step: 1, x: nil, y: nil, w: nil, h: 36.0, format: nil, id: "")
        widget_id = id.to_s.empty? ? label.to_s : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 220.0)
        rh = h.to_f
        cur_val = value.is_a?(Float) ? value.to_f : value.to_i
        st = step.is_a?(Float) ? step.to_f : step.to_i

        btn_w = 32.0
        f_font = @theme.font || Font.default
        f_size = 14

        # ラベルがある場合は上部または左側に描画
        has_label = !label.to_s.empty?
        label_w = has_label ? f_font.text_width(label.to_s, f_size) + 12.0 : 0.0

        # 操作部分の矩形
        ctrl_x = rx + label_w
        ctrl_w = [rw - label_w, btn_w * 2.0 + 30.0].max

        # マイナスボタン領域
        minus_x = ctrl_x
        minus_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, minus_x, ry, btn_w, rh)

        # プラスボタン領域
        plus_x = ctrl_x + ctrl_w - btn_w
        plus_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, plus_x, ry, btn_w, rh)

        # 値枠領域
        val_x = ctrl_x + btn_w + 2.0
        val_w = ctrl_w - btn_w * 2.0 - 4.0

        # 入力処理
        set_mouse_cursor(:hand) if minus_hover || plus_hover
        if minus_hover
          @hot_id = "#{widget_id}_minus"
          if @mouse_push
            cur_val -= st
            cur_val = [cur_val, min].max if min
          end
        elsif plus_hover
          @hot_id = "#{widget_id}_plus"
          if @mouse_push
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
      alias spinbox spinner

      # ----------------------------------------------------
      # 5. スクロールバー (ScrollBar)
      # ----------------------------------------------------
      # value: 現在のスクロール位置 (0.0 .. max_scroll)
      # total_size: コンテンツ全体の長さ
      # view_size: 表示領域の長さ
      # 返り値: 更新されたスクロール位置 (Float)
      def scrollbar(value, total_size, view_size, x: nil, y: nil, w: 14.0, h: 150.0, id: "")
        widget_id = id.to_s.empty? ? "scrollbar_#{x}_#{y}" : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
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
            @active_id = widget_id
            track_avail = [rh - thumb_h, 1.0].max
            cur_ratio = (gui_mouse_y - (ry + thumb_h * 0.5)) / track_avail
            cur_ratio = 0.0 if cur_ratio < 0.0
            cur_ratio = 1.0 if cur_ratio > 1.0
            cur_val = cur_ratio * max_scroll
          end
        end

        # ホイールスクロール
        if hover_track && Input.mouse_wheel_y != 0
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
      # items: 選択肢文字列の配列
      # selected_index: 現在選択中のインデックス
      # 返り値: 更新された selected_index
      def listbox(label, selected_index, items, x: nil, y: nil, w: nil, h: nil, id: "")
        widget_id = id.to_s.empty? ? (label.to_s.empty? ? "listbox_#{items.length}" : label.to_s) : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 240.0)
        item_h = 28.0
        f_font = @theme.font || Font.default
        f_size = 14

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

        new_selected = selected_index.to_i
        accent = @theme.accent_color || Color.new(80, 140, 240)

        # クリップ領域内で各アイテムを描画
        Window.clip(rx + 2.0, list_y + 2.0, content_w, inner_h, local: false) do
          i = 0
          len = items.length
          while i < len
            it_text = items[i].to_s
            iy = list_y + pad_y + (i.to_f * item_h) - scroll_y

            # 画面外カリング (領域内に少しでも掛かっていれば描画)
            if iy + item_h >= (list_y + 2.0) && iy <= (list_y + list_h - 2.0)
              it_hover = box_hover && in_rect?(gui_mouse_x, gui_mouse_y, rx + 2.0, iy, content_w, item_h)
              is_sel = (i == new_selected)

              if it_hover
                set_mouse_cursor(:hand)
                @hot_id = "#{widget_id}_item_#{i}"
                if @mouse_push
                  new_selected = i
                end
              end

              # アイテム描画
              @renderer.draw_listbox_item(rx, iy, content_w, item_h, it_text, is_sel, it_hover, @theme)
            end
            i += 1
          end
        end

        # スクロールバー描画 (必要な場合)
        if needs_scroll
          sb_x = rx + rw - scroll_w - 2.0
          sb_y = list_y + 2.0
          sb_h = list_h - 4.0
          Widgets.scroll_states[widget_id] = scrollbar(
            scroll_y, total_content_h, inner_h,
            x: sb_x, y: sb_y, w: scroll_w, h: sb_h, id: "#{widget_id}_sb"
          )
        end

        total_advance_h = label_h + list_h
        @layout.advance(rw, total_advance_h) if x.nil? && y.nil?
        new_selected
      end
      alias list_box listbox

      # ----------------------------------------------------
      # 7. ドロップダウンリスト (Dropdown / ComboBox)
      # ----------------------------------------------------
      # items: 選択肢配列
      # selected_index: 現在選択中のインデックス
      # 返り値: 更新された selected_index
      def dropdown(label, selected_index, items, x: nil, y: nil, w: nil, h: 36.0, id: "")
        widget_id = id.to_s.empty? ? (label.to_s.empty? ? "dropdown_#{items.length}" : label.to_s) : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 200.0)
        rh = h.to_f
        f_font = @theme.font || Font.default
        f_size = 14

        has_label = !label.to_s.empty?
        label_h = has_label ? 20.0 : 0.0
        ctrl_y = ry + label_h

        is_open = (Widgets.dropdown_open == widget_id)
        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ctrl_y, rw, rh)
        new_selected = selected_index.to_i

        # 開閉トグル処理
        if hover
          set_mouse_cursor(:hand)
          @hot_id = widget_id
          if @mouse_push
            if is_open
              Widgets.dropdown_open = ""
            else
              Widgets.dropdown_open = widget_id
            end
          end
        elsif @mouse_push && is_open
          # ポップアップ領域外クリック判定は下部で行う
        end

        # 現在選択中のテキスト
        sel_text = (items[new_selected] || "").to_s

        # コントロール本体の描画
        @renderer.draw_dropdown(rx, ry, rw, rh, label, sel_text, is_open, hover, @theme)

        # 開いている場合のポップアップリスト描画
        if is_open
          item_h = 28.0
          pop_h = [items.length.to_f * item_h + 6.0, 180.0].min
          pop_y = ctrl_y + rh + 2.0
          pop_hover = in_rect?(gui_mouse_x, gui_mouse_y, rx, pop_y, rw, pop_h)

          # ポップアップ背景 (最前面 Z + 200.0)
          pop_z = 500.0
          @renderer.draw_dropdown_popup_frame(rx, pop_y, rw, pop_h, pop_z, @theme)

          # アイテム描画
          i = 0
          len = items.length
          while i < len
            iy = pop_y + 3.0 + i.to_f * item_h
            if iy + item_h <= pop_y + pop_h + 4.0
              it_hover = in_rect?(gui_mouse_x, gui_mouse_y, rx, iy, rw, item_h)
              is_sel = (i == new_selected)

              if it_hover
                set_mouse_cursor(:hand)
                @hot_id = "#{widget_id}_pop_#{i}"
                if @mouse_push
                  new_selected = i
                  Widgets.dropdown_open = ""
                end
              end

              @renderer.draw_dropdown_popup_item(rx, iy, rw, item_h, items[i], is_sel, it_hover, pop_z, @theme)
            end
            i += 1
          end

          # ポップアップ外クリックで閉じる
          if @mouse_push && !hover && !pop_hover
            Widgets.dropdown_open = ""
          end
        end

        total_advance_h = label_h + rh
        @layout.advance(rw, total_advance_h) if x.nil? && y.nil?
        new_selected
      end
      alias combo_box dropdown

      # ----------------------------------------------------
      # 8. スクロールビュー (Scroll View コンテナブロック)
      # ----------------------------------------------------
      # 内部でブロックを実行し、コンテンツが枠高さ h を超える場合に
      # スクロールバーで領域内をスクロール可能にするコンテナ
      def scroll_view(title_or_id, x: nil, y: nil, w: nil, h: nil, content_h: nil, &block)
        widget_id = title_or_id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 300.0)

        # 高さが未指定の場合、またはウィンドウの残り高さを超えている場合は自動フィット
        avail_h = @layout.available_height
        rh = if h
               req_h = h.to_f
               avail_h ? [[req_h, avail_h - 4.0].min, 60.0].max : req_h
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

        # 最大スクロール量: 最終要素の下端が下枠線からちょうど pad_y 手前に揃う
        total_range = tot_h + pad_y * 2.0
        max_s = [total_range - clip_h, 0.0].max

        needs_scroll = max_s > 0.0
        sb_w = needs_scroll ? 12.0 : 0.0
        view_w = rw - sb_w - 4.0

        # マウスホイールによるスクロール
        box_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        if box_hover && Input.mouse_wheel_y != 0
          scroll_y -= Input.mouse_wheel_y.to_f * 30.0
        end
        scroll_y = [[scroll_y, 0.0].max, max_s].min
        Widgets.scroll_states[widget_id] = scroll_y

        # 背景パネル
        @renderer.draw_scroll_view_frame(rx, ry, rw, rh, @theme)

        # クリップスコープ開始
        prev_ox, prev_oy = Window.push_clip_scope(rx + 2.0, ry + 2.0, view_w, clip_h, local: true)

        # レイアウトコンテナ開始 (スクロールオフセット分だけカーソルを上にオフセット)
        # content_w を view_w - 4.0 に設定することで、左右4pxパディングを保ちつつ
        # 自動幅ウィジェットがスクロールバーと重ならず綺麗に領域内に収まる
        start_y = pad_y - scroll_y
        @layout.push_scope(content_w: view_w - 4.0, cursor_x: 4.0, cursor_y: start_y)

        yield

        # 実際に配置された要素の最下端から純粋なコンテンツ高さを動的計測
        end_y = @layout.cursor_y
        sp_y = @layout.spacing_y
        content_bottom = (end_y > start_y) ? (end_y - sp_y - start_y) : 0.0
        Widgets.scroll_states["#{widget_id}_content_h"] = content_bottom

        @layout.pop_scope
        Window.pop_clip_scope(prev_ox, prev_oy)

        # スクロールバー描画
        if needs_scroll
          sb_x = rx + rw - sb_w - 2.0
          sb_y = ry + 2.0
          sb_h = clip_h
          Widgets.scroll_states[widget_id] = scrollbar(
            scroll_y, total_range, clip_h,
            x: sb_x, y: sb_y, w: sb_w, h: sb_h, id: "#{widget_id}_sb"
          )
        end

        @layout.advance(rw, rh) if x.nil? && y.nil?
      end

      # ----------------------------------------------------
      # 10. テーブル / リストビュー (Table / ListView)
      # ----------------------------------------------------
      # columns: カラム定義の配列 (文字列, [名前, 幅], { name:, width: } など)
      # rows: 2次元配列 (行データの配列)
      # selected_index: 選択中の行インデックス (Integer または nil)
      # 返り値: 更新された selected_index
      def table(label, columns, rows, selected_index = nil, x: nil, y: nil, w: nil, h: nil, item_height: 20.0, id: "", &block)
        widget_id = id.to_s.empty? ? (label.to_s.empty? ? "table_#{columns.length}_#{rows.length}" : label.to_s) : id.to_s
        rx = x ? x.to_f : @layout.cursor_x
        ry = y ? y.to_f : @layout.cursor_y
        rw = @layout.resolve_width(w, 280.0)
        row_h = item_height.to_f > 0.0 ? item_height.to_f : 20.0
        header_h = 22.0

        has_label = !label.to_s.empty?
        label_h = has_label ? 22.0 : 0.0
        table_y = ry + label_h
        table_h = if h
                    [h.to_f - label_h, 30.0].max
                  else
                    [rows.length.to_f * row_h + header_h + 8.0, 180.0].min
                  end

        # 外枠描画
        @renderer.draw_table_frame(rx, ry, rw, table_h, label, @theme)

        # カラム幅の計算
        pad_y = 2.0
        total_content_h = rows.length.to_f * row_h + pad_y * 2.0
        body_y = table_y + header_h + 2.0
        body_h = [table_h - header_h - 6.0, 1.0].max

        needs_scroll = total_content_h > body_h
        scroll_w = needs_scroll ? 10.0 : 0.0
        content_w = rw - scroll_w - 4.0

        # カラム情報のパース (col_names, col_widths)
        col_count = columns.length
        col_names = []
        col_widths = []
        fixed_total = 0.0
        flex_count = 0

        ci = 0
        while ci < col_count
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

        # 未指定カラムの幅均等分配
        flex_w = flex_count > 0 ? [((content_w - fixed_total) / flex_count.to_f), 20.0].max : 0.0
        ci = 0
        while ci < col_count
          col_widths[ci] ||= flex_w
          ci += 1
        end

        # ヘッダー描画
        @renderer.draw_table_header(rx + 2.0, table_y + 2.0, content_w, header_h, col_names, col_widths, @theme)

        # スクロールオフセットの計算
        Widgets.scroll_states[widget_id] ||= 0.0
        scroll_y = Widgets.scroll_states[widget_id]

        box_hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, table_y, rw, table_h)
        if box_hover && Input.mouse_wheel_y != 0
          scroll_y -= Input.mouse_wheel_y.to_f * row_h * 1.5
        end
        max_s = [total_content_h - body_h, 0.0].max
        scroll_y = [[scroll_y, 0.0].max, max_s].min
        Widgets.scroll_states[widget_id] = scroll_y

        new_selected = selected_index

        # 行の描画 & カリング (Window.clip 内)
        Window.clip(rx + 2.0, body_y, content_w, body_h, local: false) do
          i = 0
          len = rows.length
          while i < len
            iy = body_y + pad_y + (i.to_f * row_h) - scroll_y

            # カリング: 領域内に少しでも掛かっていれば描画
            if iy + row_h >= body_y && iy <= (body_y + body_h)
              it_hover = box_hover && in_rect?(gui_mouse_x, gui_mouse_y, rx + 2.0, iy, content_w, row_h)
              is_sel = (i == new_selected)

              if it_hover
                set_mouse_cursor(:hand)
                @hot_id = "#{widget_id}_row_#{i}"
                if @mouse_push
                  new_selected = i
                end
              end

              if block_given?
                yield(rows[i], i, is_sel, it_hover, rx + 2.0, iy, content_w, row_h)
              else
                @renderer.draw_table_row(rx + 2.0, iy, content_w, row_h, rows[i], col_widths, is_sel, it_hover, i.even?, @theme)
              end
            end
            i += 1
          end
        end

        # スクロールバー描画 (必要な場合)
        if needs_scroll
          sb_x = rx + rw - scroll_w - 2.0
          sb_y = body_y
          sb_h = body_h
          Widgets.scroll_states[widget_id] = scrollbar(
            scroll_y, total_content_h, body_h,
            x: sb_x, y: sb_y, w: scroll_w, h: sb_h, id: "#{widget_id}_sb"
          )
        end

        total_advance_h = label_h + table_h
        @layout.advance(rw, total_advance_h) if x.nil? && y.nil?
        new_selected
      end
      alias list_view table
    end
  end
end

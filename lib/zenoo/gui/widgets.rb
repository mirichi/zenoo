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
        border_cfg = hover ? (@theme.border_hover || @theme.border_normal) : @theme.border_normal
        b_width = border_cfg ? border_cfg[0].to_f : 1.0
        b_color = border_cfg ? border_cfg[1] : Color.new(80, 80, 85)
        bg_col = hover ? (@theme.bg_hover || Color.new(50, 50, 55)) : (@theme.bg_normal || Color.new(35, 35, 38))

        # 外枠
        Window.draw_rect(
          rx, box_y, box_size, box_size,
          radius: 4.0,
          color: bg_col,
          border_width: b_width,
          border_color: b_color
        )

        # チェック状態の描画 (アクセントカラーの内側角丸四角形 + 白チェック)
        if new_checked
          accent = @theme.accent_color || Color.new(80, 140, 240)
          inner_pad = 4.0
          Window.draw_rect(
            rx + inner_pad, box_y + inner_pad,
            box_size - inner_pad * 2.0, box_size - inner_pad * 2.0,
            radius: 2.0,
            color: accent
          )
        end

        # ラベルテキスト
        text_col = hover ? (@theme.text_color || Color::WHITE) : (@theme.text_color || Color.new(220, 220, 225))
        ty = ry + (rh - f_size.to_f) * 0.5
        Profiler.measure(:gui_text) do
          Window.draw_text(rx + box_size + 10.0, ty, label.to_s, font: f_font, size: f_size, color: text_col)
        end

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
        border_cfg = hover ? (@theme.border_hover || @theme.border_normal) : @theme.border_normal
        b_width = border_cfg ? border_cfg[0].to_f : 1.0
        b_color = border_cfg ? border_cfg[1] : Color.new(80, 80, 85)
        bg_col = hover ? (@theme.bg_hover || Color.new(50, 50, 55)) : (@theme.bg_normal || Color.new(35, 35, 38))

        # 外円
        Window.draw_circle(
          cx, cy, circle_r,
          color: bg_col,
          border_width: b_width,
          border_color: b_color
        )

        # 選択時の内丸
        if new_active
          accent = @theme.accent_color || Color.new(80, 140, 240)
          Window.draw_circle(cx, cy, 4.5, color: accent)
        end

        # ラベルテキスト
        text_col = hover ? (@theme.text_color || Color::WHITE) : (@theme.text_color || Color.new(220, 220, 225))
        ty = ry + (rh - f_size.to_f) * 0.5
        Profiler.measure(:gui_text) do
          Window.draw_text(rx + circle_d + 10.0, ty, label.to_s, font: f_font, size: f_size, color: text_col)
        end

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

        # 背景トラック
        Window.draw_rect(
          rx, ry, rw, rh,
          radius: 4.0,
          color: Color.new(26, 26, 29, 230),
          border_width: 1.0,
          border_color: Color.new(55, 55, 60, 180)
        )

        new_selected = selected_index.to_i

        i = 0
        while i < count
          lbl = labels[i].to_s
          tx = rx + i.to_f * tab_w
          is_cur = (i == new_selected)
          hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, tx, ry, tab_w, rh)

          if hover
            @hot_id = "#{widget_id}_#{i}"
            if @mouse_push
              new_selected = i
            end
          end

          # タブ背景 (選択中 / ホバー中)
          if is_cur
            Window.draw_rect(
              tx + 2.0, ry + 2.0, tab_w - 4.0, rh - 4.0,
              radius: 3.0,
              color: Color.new(48, 48, 54, 255)
            )
            # アクティブインジケータ (下線アクセントバー)
            Window.draw_rect(
              tx + 6.0, ry + rh - 3.5, tab_w - 12.0, 2.5,
              radius: 1.0,
              color: accent
            )
          elsif hover
            Window.draw_rect(
              tx + 2.0, ry + 2.0, tab_w - 4.0, rh - 4.0,
              radius: 3.0,
              color: Color.new(38, 38, 42, 180)
            )
          end

          # ラベル (中央揃え)
          tw = f_font.text_width(lbl, f_size)
          text_x = tx + (tab_w - tw) * 0.5
          text_y = ry + (rh - f_size.to_f) * 0.5 - 1.0
          tcol = is_cur ? (@theme.text_color || Color::WHITE) : (hover ? Color::WHITE : Color.new(160, 160, 165))
          Profiler.measure(:gui_text) do
            Window.draw_text(text_x, text_y, lbl, font: f_font, size: f_size, color: tcol)
          end

          i += 1
        end

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

        # ラベル描画
        if has_label
          ly = ry + (rh - f_size.to_f) * 0.5
          Profiler.measure(:gui_text) do
            Window.draw_text(rx, ly, label.to_s, font: f_font, size: f_size, color: @theme.text_color || Color::WHITE)
          end
        end

        # 中央の値表示ボックス
        Window.draw_rect(
          val_x, ry, val_w, rh,
          radius: 3.0,
          color: Color.new(28, 28, 32, 230),
          border_width: 1.0,
          border_color: Color.new(55, 55, 60, 200)
        )

        fmt_str = format || (cur_val.is_a?(Float) ? "%.2f" : "%d")
        val_str = sprintf(fmt_str, cur_val)
        tw = f_font.text_width(val_str, f_size)
        Profiler.measure(:gui_text) do
          Window.draw_text(val_x + (val_w - tw) * 0.5, ry + (rh - f_size.to_f) * 0.5, val_str, font: f_font, size: f_size, color: Color::WHITE)
        end

        # [-] ボタン描画
        m_bg = minus_hover ? (@theme.bg_hover || Color.new(55, 55, 60)) : (@theme.bg_normal || Color.new(40, 40, 44))
        Window.draw_rect(
          minus_x, ry, btn_w, rh,
          radius: 3.0,
          color: m_bg,
          border_width: 1.0,
          border_color: Color.new(65, 65, 70, 200)
        )
        Window.draw_rect(minus_x + 10.0, ry + rh * 0.5 - 1.0, btn_w - 20.0, 2.0, color: Color::WHITE)

        # [+] ボタン描画
        p_bg = plus_hover ? (@theme.bg_hover || Color.new(55, 55, 60)) : (@theme.bg_normal || Color.new(40, 40, 44))
        Window.draw_rect(
          plus_x, ry, btn_w, rh,
          radius: 3.0,
          color: p_bg,
          border_width: 1.0,
          border_color: Color.new(65, 65, 70, 200)
        )
        # 十字マーク
        Window.draw_rect(plus_x + 10.0, ry + rh * 0.5 - 1.0, btn_w - 20.0, 2.0, color: Color::WHITE)
        Window.draw_rect(plus_x + btn_w * 0.5 - 1.0, ry + 10.0, 2.0, rh - 20.0, color: Color::WHITE)

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
          Window.draw_rect(rx, ry, rw, rh, radius: rw * 0.5, color: Color.new(22, 22, 25, 120))
          @layout.advance(rw, rh) if x.nil? && y.nil?
          return 0.0
        end

        thumb_h = [[(vw / tot) * rh, 20.0].max, rh].min
        ratio = cur_val / max_scroll
        thumb_y = ry + ratio * (rh - thumb_h)

        hover_track = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ry, rw, rh)
        hover_thumb = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, thumb_y, rw, thumb_h)

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
        # トラック
        Window.draw_rect(rx, ry, rw, rh, radius: rw * 0.5, color: Color.new(20, 20, 22, 160))

        # サム (つまみ)
        thumb_ratio = max_scroll > 0 ? (cur_val / max_scroll) : 0.0
        actual_thumb_y = ry + thumb_ratio * (rh - thumb_h)
        thumb_col = (@active_id == widget_id) ? (@theme.accent_color || Color.new(100, 160, 255)) :
                    (hover_thumb ? Color.new(110, 110, 120, 240) : Color.new(75, 75, 82, 200))

        Window.draw_rect(
          rx + 2.0, actual_thumb_y, rw - 4.0, thumb_h,
          radius: (rw - 4.0) * 0.5,
          color: thumb_col
        )

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

        # ラベル描画
        if has_label
          Profiler.measure(:gui_text) do
            Window.draw_text(rx, ry + 2.0, label.to_s, font: f_font, size: f_size, color: @theme.text_color || Color::WHITE)
          end
        end

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

        # 背景ボックス
        Window.draw_rect(
          rx, list_y, rw, list_h,
          radius: 4.0,
          color: Color.new(24, 24, 27, 240),
          border_width: 1.0,
          border_color: Color.new(55, 55, 60, 200)
        )

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
                @hot_id = "#{widget_id}_item_#{i}"
                if @mouse_push
                  new_selected = i
                end
              end

              # 行背景 (選択 / ホバー)
              if is_sel
                Window.draw_rect(
                  rx + 4.0, iy + 1.0, content_w - 4.0, item_h - 2.0,
                  radius: 3.0,
                  color: Color.new(accent.r, accent.g, accent.b, 200)
                )
              elsif it_hover
                Window.draw_rect(
                  rx + 4.0, iy + 1.0, content_w - 4.0, item_h - 2.0,
                  radius: 3.0,
                  color: Color.new(45, 45, 50, 180)
                )
              end

              # アイテム名
              tcol = is_sel ? Color::WHITE : (it_hover ? Color::WHITE : Color.new(200, 200, 205))
              Profiler.measure(:gui_text) do
                Window.draw_text(rx + 10.0, iy + (item_h - f_size.to_f) * 0.5, it_text, font: f_font, size: f_size, color: tcol)
              end
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

        # ラベル描画
        if has_label
          Profiler.measure(:gui_text) do
            Window.draw_text(rx, ry + 1.0, label.to_s, font: f_font, size: f_size, color: @theme.text_color || Color::WHITE)
          end
        end

        is_open = (Widgets.dropdown_open == widget_id)
        hover = can_interact? && in_rect?(gui_mouse_x, gui_mouse_y, rx, ctrl_y, rw, rh)
        new_selected = selected_index.to_i

        # 開閉トグル処理
        if hover
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

        # コントロール本体の描画
        border_cfg = (hover || is_open) ? (@theme.border_hover || @theme.border_normal) : @theme.border_normal
        b_width = border_cfg ? border_cfg[0].to_f : 1.0
        b_color = border_cfg ? border_cfg[1] : Color.new(80, 80, 85)
        bg_col = (hover || is_open) ? (@theme.bg_hover || Color.new(50, 50, 55)) : (@theme.bg_normal || Color.new(35, 35, 38))

        Window.draw_rect(
          rx, ctrl_y, rw, rh,
          radius: 4.0,
          color: bg_col,
          border_width: b_width,
          border_color: b_color
        )

        # 現在選択中のテキスト
        sel_text = (items[new_selected] || "").to_s
        Profiler.measure(:gui_text) do
          Window.draw_text(
            rx + 10.0, ctrl_y + (rh - f_size.to_f) * 0.5,
            sel_text,
            font: f_font, size: f_size,
            color: Color::WHITE
          )
        end

        # 下向き三角矢印 (▼)
        arrow_x = rx + rw - 18.0
        arrow_y = ctrl_y + rh * 0.5 - 2.0
        Window.draw_triangle(
          arrow_x, arrow_y,
          arrow_x + 8.0, arrow_y,
          arrow_x + 4.0, arrow_y + 5.0,
          color: Color.new(180, 180, 185)
        )

        # 開いている場合のポップアップリスト描画
        if is_open
          item_h = 28.0
          pop_h = [items.length.to_f * item_h + 6.0, 180.0].min
          pop_y = ctrl_y + rh + 2.0
          pop_hover = in_rect?(gui_mouse_x, gui_mouse_y, rx, pop_y, rw, pop_h)

          # ポップアップ背景 (最前面 Z + 200.0)
          pop_z = 500.0
          Window.draw_rect(
            rx, pop_y, rw, pop_h,
            radius: 4.0,
            color: Color.new(28, 28, 32, 250),
            border_width: 1.0,
            border_color: @theme.accent_color || Color.new(80, 140, 240),
            shadow_blur: 8.0,
            shadow_color: Color.new(0, 0, 0, 160),
            z: pop_z
          )

          # アイテム描画
          i = 0
          len = items.length
          accent = @theme.accent_color || Color.new(80, 140, 240)
          while i < len
            iy = pop_y + 3.0 + i.to_f * item_h
            if iy + item_h <= pop_y + pop_h + 4.0
              it_hover = in_rect?(gui_mouse_x, gui_mouse_y, rx, iy, rw, item_h)
              is_sel = (i == new_selected)

              if it_hover
                @hot_id = "#{widget_id}_pop_#{i}"
                if @mouse_push
                  new_selected = i
                  Widgets.dropdown_open = ""
                end
              end

              if is_sel
                Window.draw_rect(rx + 3.0, iy, rw - 6.0, item_h, radius: 2.0, color: Color.new(accent.r, accent.g, accent.b, 200), z: pop_z + 1.0)
              elsif it_hover
                Window.draw_rect(rx + 3.0, iy, rw - 6.0, item_h, radius: 2.0, color: Color.new(48, 48, 54, 220), z: pop_z + 1.0)
              end

              it_col = is_sel ? Color::WHITE : (it_hover ? Color::WHITE : Color.new(200, 200, 205))
              Profiler.measure(:gui_text) do
                Window.draw_text(rx + 10.0, iy + (item_h - f_size.to_f) * 0.5, items[i].to_s, font: f_font, size: f_size, color: it_col, z: pop_z + 2.0)
              end
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
        Window.draw_rect(
          rx, ry, rw, rh,
          radius: 4.0,
          color: Color.new(22, 22, 25, 230),
          border_width: 1.0,
          border_color: Color.new(50, 50, 55, 200)
        )

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
    end
  end
end

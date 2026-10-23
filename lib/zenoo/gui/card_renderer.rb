# frozen_string_literal: true

require_relative 'renderer'

module Zenoo
  module GUI
    # draw_rect を活用した標準のモダン・カード描画レンダラー
    class CardRenderer < Renderer
      # ----------------------------------------------------
      # ボタン描画
      # ----------------------------------------------------
      def draw_button(x, y, w, h, label, state, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        # 状態別のスタイル選択
        bg_col     = theme.bg_normal
        border_cfg = theme.border_normal

        if state == :active
          bg_col     = theme.bg_active
          border_cfg = theme.border_active
        elsif state == :hover
          bg_col     = theme.bg_hover
          border_cfg = theme.border_hover
        end

        b_w = border_cfg ? border_cfg[0] : 0.0
        b_c = border_cfg ? border_cfg[1] : :cyan

        # 背景カード描画 (SDF角丸 + ボーダー、影なし)
        Window.draw_rect(
          rx, ry, rw, rh,
          radius: theme.corner_radius,
          color: bg_col,
          border_width: b_w,
          border_color: b_c
        )

        # テキストの描画 (ボタン幅に収まるよう厳密に計算 & センタリング)
        if label
          text_str = label.to_s
          if text_str.length > 0
            f_size = theme.font_size.to_i
            f_size = 14 if f_size <= 0
            f_font = theme.font || Font.default

            text_w = f_font.text_width(text_str, f_size)

            # ボタン枠 (左右パディング 12px) からはみ出す場合は、ボタン内に収まるサイズに自動スケール
            pad_x = 12.0
            avail_w = rw - pad_x * 2.0
            if avail_w > 8.0 && text_w > avail_w
              ratio = avail_w / text_w
              f_size = (f_size * ratio).to_i
              f_size = 8 if f_size < 8
              text_w = f_font.text_width(text_str, f_size)
            end

            text_x = rx + (rw - text_w) / 2.0
            text_y = ry + (rh - f_size.to_f) / 2.0

            # アクティブ時は1px押し込み演出
            if state == :active
              text_y += 1.0
            end

            Window.draw_text(text_x, text_y, text_str, font: f_font, size: f_size, color: theme.text_color)
          end
        end
      end

      # ----------------------------------------------------
      # スライダー描画
      # ----------------------------------------------------
      def draw_slider(x, y, w, h, label, value, min, max, state, theme, unit: "", format: nil, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        v_val = value.to_f
        v_min = min.to_f
        v_max = max.to_f
        range = v_max - v_min
        range = 1.0 if range <= 0.00001

        ratio = (v_val - v_min) / range
        ratio = 0.0 if ratio < 0.0
        ratio = 1.0 if ratio > 1.0

        f_size = theme.font_size.to_i
        f_size = 14 if f_size <= 0
        f_font = theme.font || Font.default

        # 上部: ラベル & 数値
        has_label = label && label.to_s.length > 0
        if has_label
          label_str = label.to_s
          Window.draw_text(rx, ry, label_str, font: f_font, size: f_size, color: theme.text_color)

          # 数値テキスト
          val_str = if format
                      sprintf(format, v_val)
                    elsif (v_val % 1.0).abs < 0.0001 && (v_min % 1.0).abs < 0.0001 && (v_max % 1.0).abs < 0.0001
                      v_val.round.to_s
                    else
                      v_int = v_val.to_i
                      v_dec = ((v_val - v_int.to_f).abs * 100.0).round
                      if v_dec == 0
                        v_int.to_s
                      else
                        v_dec_str = sprintf("%02d", v_dec).sub(/0$/, '')
                        "#{v_int}.#{v_dec_str}"
                      end
                    end
          val_str = "#{val_str}#{unit}" unless unit.to_s.empty?
          val_w = f_font.text_width(val_str, f_size)
          Window.draw_text(rx + rw - val_w, ry, val_str, font: f_font, size: f_size, color: theme.accent_color)

          track_y = ry + f_size.to_f + 8.0
          track_h = 8.0
        else
          track_y = ry + (rh - 8.0) / 2.0
          track_h = 8.0
        end

        # ノブ (つまみ) 寸法
        knob_size = 18.0
        knob_radius = knob_size / 2.0
        usable_w = [rw - knob_size, 0.0].max

        # トラック溝 (背景): ノブが左右境界からはみ出さないよう可動域に合わせる
        track_x = rx + knob_radius
        track_w = usable_w

        tb_w = theme.track_border ? theme.track_border[0].to_f : 0.0
        tb_c = theme.track_border ? theme.track_border[1] : :cyan
        Window.draw_rect(
          track_x, track_y, track_w, track_h,
          radius: 4.0,
          color: theme.track_bg,
          border_width: tb_w,
          border_color: tb_c
        )

        # 進行度フィル (左端からノブ中心まで)
        fill_w = track_w * ratio
        if fill_w > 0.0
          fill_color = (state == :hover || state == :active) ? theme.accent_hover : theme.accent_color
          Window.draw_rect(
            track_x, track_y, fill_w, track_h,
            radius: 4.0,
            color: fill_color
          )
        end

        # ノブ (つまみ)
        knob_x = rx + usable_w * ratio
        knob_y = track_y + (track_h - knob_size) / 2.0

        knob_color = theme.text_color || Color::WHITE
        kb_border = [2.0, (state == :active ? theme.accent_hover : theme.accent_color)]
        kb_shadow = (state == :active ? theme.shadow_active : theme.shadow_normal)
        kb_s_blur = kb_shadow ? kb_shadow[0].to_f : 0.0
        kb_s_col  = kb_shadow ? kb_shadow[1] : nil

        Window.draw_rect(
          knob_x, knob_y, knob_size, knob_size,
          radius: knob_radius,
          color: knob_color,
          border_width: kb_border[0].to_f,
          border_color: kb_border[1],
          shadow_blur: kb_s_blur,
          shadow_color: kb_s_col
        )
      end

      # ----------------------------------------------------
      # ラベル描画
      # ----------------------------------------------------
      def draw_label(x, y, text, size, color, theme, **_opts)
        return unless text
        f_size = size ? size.to_i : theme.font_size.to_i
        f_size = 16 if f_size <= 0
        c_color = color || theme.text_color
        f_font = theme.font || Font.default
        Window.draw_text(x.to_f, y.to_f, text.to_s, font: f_font, size: f_size, color: c_color)
      end

      # ----------------------------------------------------
      # ボタン当たり判定 (SDF Rounded Box 距離関数による厳密判定)
      # ----------------------------------------------------
      def hit_test_button(x, y, w, h, px, py, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        rpx = px.to_f
        rpy = py.to_f

        # 外接矩形による高速枝刈り
        return false if rpx < rx || rpx > rx + rw || rpy < ry || rpy > ry + rh

        r = theme.corner_radius.to_f
        return true if r <= 0.0

        half_w = rw * 0.5
        half_h = rh * 0.5
        center_x = rx + half_w
        center_y = ry + half_h

        # カード中心からのローカル座標
        lx = rpx - center_x
        ly = rpy - center_y

        # 半径クランプ (半幅・半高さ以下)
        max_r = half_w < half_h ? half_w : half_h
        r = max_r if r > max_r

        # SDF Rounded Box:
        # vec2 q = abs(p) - b + r;
        qx = lx.abs - half_w + r
        qy = ly.abs - half_h + r

        # min(max(q.x, q.y), 0.0)
        max_q = qx > qy ? qx : qy
        term1 = max_q < 0.0 ? max_q : 0.0

        # length(max(q, 0.0))
        cx = qx > 0.0 ? qx : 0.0
        cy = qy > 0.0 ? qy : 0.0
        term2 = Math.sqrt(cx * cx + cy * cy)

        # 符号付き距離 dist <= 0.0 なら描画カードの内側！
        (term1 + term2 - r) <= 0.0
      end

      # ----------------------------------------------------
      # テキストボックス描画
      # ----------------------------------------------------
      def draw_text_box(x, y, w, h, text, focused, cursor_pos, blink_on, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        # 背景色・枠線 (影なし)
        bg_col = theme.track_bg || theme.bg_normal
        border_cfg = focused ? (theme.border_active || [1.5, theme.accent_color]) : theme.border_normal

        b_w = border_cfg ? border_cfg[0].to_f : 1.0
        b_c = border_cfg ? border_cfg[1] : theme.accent_color

        Window.draw_rect(
          rx, ry, rw, rh,
          radius: theme.corner_radius,
          color: bg_col,
          border_width: b_w,
          border_color: b_c
        )

        f_size = theme.font_size.to_i
        f_size = 14 if f_size <= 0
        pad_x = 10.0
        text_y = ry + (rh - f_size.to_f) / 2.0
        f_font = theme.font || Font.default

        str = text.to_s
        sub_str = str[0...cursor_pos] || ""
        caret_offset_x = f_font.text_width(sub_str, f_size)

        avail_w = rw - pad_x * 2.0 - 4.0
        scroll_x = 0.0
        if caret_offset_x > avail_w
          scroll_x = caret_offset_x - avail_w
        end

        text_x = rx + pad_x - scroll_x
        Window.draw_text(text_x, text_y, str, font: f_font, size: f_size, color: theme.text_color)

        if focused && blink_on
          caret_x = text_x + caret_offset_x
          if caret_x >= rx + pad_x - 2.0 && caret_x <= rx + rw - pad_x + 2.0
            Window.draw_rect(caret_x, text_y - 1.0, 2.0, f_size.to_f + 2.0, color: theme.accent_color)
          end
        end
      end

      def hit_test_text_box(x, y, w, h, px, py, theme, **opts)
        hit_test_button(x, y, w, h, px, py, theme, **opts)
      end

      # パネル (カード枠) 描画
      def draw_panel(x, y, w, h, title, theme, **opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        b_cfg      = theme.border_normal
        s_cfg      = theme.shadow_normal

        radius     = (opts[:radius] || theme.corner_radius || 8.0).to_f
        bg_col     = opts[:color] || theme.win_bg || theme.bg_normal
        b_width    = (opts[:border_width] || (b_cfg ? b_cfg[0] : 1.0)).to_f
        b_col      = opts[:border_color] || (b_cfg ? b_cfg[1] : nil)
        s_blur     = (opts[:shadow_blur] || (s_cfg ? s_cfg[0] : 0.0)).to_f
        s_col      = opts[:shadow_color] || (s_cfg ? s_cfg[1] : nil)
        card_image = opts[:image]
        card_z     = (opts[:z] || 0.0).to_f

        Window.draw_rect(
          rx, ry, rw, rh,
          radius: radius,
          color: bg_col,
          border_width: b_width,
          border_color: b_col,
          shadow_blur: s_blur,
          shadow_color: s_col,
          image: card_image,
          z: card_z
        )

        if title && !title.to_s.empty?
          pad        = (opts[:padding] || 16.0).to_f
          f_font     = opts[:font] || theme.font || Font.default
          title_size = (opts[:title_size] || 20).to_i
          title_col  = opts[:title_color] || theme.text_color
          Window.draw_text(rx + pad, ry + pad, title.to_s, font: f_font, size: title_size, color: title_col)
        end
      end

      # フローティングウィンドウ (外枠・タイトルバー) 描画
      def draw_window(x, y, w, h, title, active, theme, **opts)
        wx          = x.to_f
        wy          = y.to_f
        ww          = w.to_f
        wh          = h.to_f
        win_z       = (opts[:z] || 0.0).to_f
        title_bar_h = (opts[:title_bar_h] || 36.0).to_f

        border_cfg   = active ? (theme.win_border_active || theme.border_active) : (theme.win_border_normal || theme.border_normal)
        border_w     = border_cfg ? border_cfg[0].to_f : 1.0
        border_color = border_cfg ? border_cfg[1] : theme.border_normal[1]

        shadow_cfg   = active ? theme.shadow_active : theme.shadow_normal
        shadow_blur  = shadow_cfg ? shadow_cfg[0].to_f : 0.0
        shadow_color = shadow_cfg ? shadow_cfg[1] : nil
        win_bg_col   = theme.win_bg || theme.bg_normal
        win_radius   = (theme.corner_radius || 4.0).to_f

        # 背景カード
        Window.draw_rect(
          wx, wy, ww, wh,
          radius: win_radius,
          color: win_bg_col,
          border_width: border_w,
          border_color: border_color,
          shadow_blur: shadow_blur,
          shadow_color: shadow_color,
          z: win_z
        )

        # タイトルバー帯
        title_bg = active ? (theme.win_title_bg_active || theme.bg_active) : (theme.win_title_bg || theme.bg_hover)
        title_bar_radius = [win_radius - 1.0, 0.0].max
        Window.draw_rect(
          wx + 1.0, wy + 1.0, ww - 2.0, title_bar_h,
          radius: title_bar_radius,
          color: title_bg,
          z: win_z + 1.0
        )

        # タイトルバー境界線
        Window.draw_line(
          wx + 1.0, wy + title_bar_h + 1.0,
          wx + ww - 1.0, wy + title_bar_h + 1.0,
          color: border_color,
          z: win_z + 1.5
        )

        # タイトル文字列
        if title && !title.to_s.empty?
          f_font = theme.font || Font.default
          f_size = 14
          title_col = active ? theme.text_color : (theme.text_disabled || theme.text_color)
          Profiler.measure(:gui_text) do
            Window.draw_text(
              wx + 10.0, wy + (title_bar_h - f_size.to_f) / 2.0 + 1.0,
              title.to_s,
              font: f_font,
              size: f_size,
              color: title_col,
              z: win_z + 2.0
            )
          end
        end

        # リサイズグリップ (右下隅)
        if opts[:resizable]
          grip_border = active ? (theme.win_border_active || theme.border_active) : (theme.win_border_normal || theme.border_normal)
          grip_color  = grip_border ? grip_border[1] : (active ? theme.accent_color : (theme.text_disabled || theme.text_color))
          rx = wx + ww - 15.0
          ry = wy + wh - 15.0
          Window.draw_line(rx + 8.0, ry + 12.0, rx + 12.0, ry + 8.0, color: grip_color, width: 1.5, z: win_z + 2.0)
          Window.draw_line(rx + 4.0, ry + 12.0, rx + 12.0, ry + 4.0, color: grip_color, width: 1.5, z: win_z + 2.0)
          Window.draw_line(rx + 0.0, ry + 12.0, rx + 12.0, ry + 0.0, color: grip_color, width: 1.5, z: win_z + 2.0)
        end
      end

      # ----------------------------------------------------
      # チェックボックス描画
      # ----------------------------------------------------
      def draw_checkbox(x, y, w, h, label, checked, hover, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rh = h.to_f
        box_size = 20.0
        box_y = ry + (rh - box_size) * 0.5

        border_cfg = hover ? theme.border_hover : theme.border_normal
        b_width = border_cfg ? border_cfg[0].to_f : 1.0
        b_color = border_cfg ? border_cfg[1] : theme.accent_color
        bg_col  = hover ? theme.bg_hover : theme.bg_normal

        Window.draw_rect(
          rx, box_y, box_size, box_size,
          radius: theme.corner_radius || 4.0,
          color: bg_col,
          border_width: b_width,
          border_color: b_color
        )

        if checked
          inner_pad = 4.0
          Window.draw_rect(
            rx + inner_pad, box_y + inner_pad,
            box_size - inner_pad * 2.0, box_size - inner_pad * 2.0,
            radius: [(theme.corner_radius || 4.0) * 0.5, 1.0].max,
            color: theme.accent_color
          )
        end

        if label && !label.to_s.empty?
          f_font = theme.font || Font.default
          f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 15
          text_col = hover ? theme.text_color : (theme.text_disabled || theme.text_color)
          ty = ry + (rh - f_size.to_f) * 0.5
          Profiler.measure(:gui_text) do
            Window.draw_text(rx + box_size + 10.0, ty, label.to_s, font: f_font, size: f_size, color: text_col)
          end
        end
      end

      # ----------------------------------------------------
      # ラジオボタン描画
      # ----------------------------------------------------
      def draw_radio(x, y, w, h, label, active, hover, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rh = h.to_f
        circle_r = 9.0
        cx = rx + circle_r + 2.0
        cy = ry + rh * 0.5

        border_cfg = hover ? theme.border_hover : theme.border_normal
        b_width = border_cfg ? border_cfg[0].to_f : 1.0
        b_color = border_cfg ? border_cfg[1] : theme.accent_color
        bg_col  = hover ? theme.bg_hover : theme.bg_normal

        Window.draw_circle(
          cx, cy, circle_r,
          color: bg_col,
          border_width: b_width,
          border_color: b_color
        )

        if active
          Window.draw_circle(cx, cy, 4.5, color: theme.accent_color)
        end

        if label && !label.to_s.empty?
          f_font = theme.font || Font.default
          f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 15
          text_col = hover ? theme.text_color : (theme.text_disabled || theme.text_color)
          ty = ry + (rh - f_size.to_f) * 0.5
          Profiler.measure(:gui_text) do
            Window.draw_text(rx + circle_r * 2.0 + 10.0, ty, label.to_s, font: f_font, size: f_size, color: text_col)
          end
        end
      end

      # ----------------------------------------------------
      # タブバー描画
      # ----------------------------------------------------
      def draw_tabs(x, y, w, h, labels, selected_index, hover_index, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        count = labels.length
        return if count == 0

        tab_w = rw / count.to_f
        f_font = theme.font || Font.default
        f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i - 1 : 14
        track_b = theme.track_border || theme.border_normal

        Window.draw_rect(
          rx, ry, rw, rh,
          radius: theme.corner_radius || 4.0,
          color: theme.track_bg || theme.bg_normal,
          border_width: track_b ? track_b[0].to_f : 1.0,
          border_color: track_b ? track_b[1] : nil
        )

        i = 0
        while i < count
          lbl = labels[i].to_s
          tx = rx + i.to_f * tab_w
          is_cur = (i == selected_index)
          is_hov = (i == hover_index)

          if is_cur
            Window.draw_rect(
              tx + 2.0, ry + 2.0, tab_w - 4.0, rh - 4.0,
              radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
              color: theme.bg_active
            )
            # アクティブインジケータ (下線アクセントバー)
            Window.draw_rect(
              tx + 6.0, ry + rh - 3.5, tab_w - 12.0, 2.5,
              radius: 1.0,
              color: theme.accent_color
            )
          elsif is_hov
            Window.draw_rect(
              tx + 2.0, ry + 2.0, tab_w - 4.0, rh - 4.0,
              radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
              color: theme.bg_hover
            )
          end

          tw = f_font.text_width(lbl, f_size)
          text_x = tx + (tab_w - tw) * 0.5
          text_y = ry + (rh - f_size.to_f) * 0.5 - 1.0
          tcol = (is_cur || is_hov) ? theme.text_color : (theme.text_disabled || theme.text_color)
          Profiler.measure(:gui_text) do
            Window.draw_text(text_x, text_y, lbl, font: f_font, size: f_size, color: tcol)
          end

          i += 1
        end
      end

      # ----------------------------------------------------
      # スピンボタン描画
      # ----------------------------------------------------
      def draw_spinner(x, y, w, h, label, value_str, minus_hover, plus_hover, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        btn_w = 32.0
        f_font = theme.font || Font.default
        f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 14

        has_label = !label.to_s.empty?
        label_w = has_label ? f_font.text_width(label.to_s, f_size) + 12.0 : 0.0

        if has_label
          ly = ry + (rh - f_size.to_f) * 0.5
          Profiler.measure(:gui_text) do
            Window.draw_text(rx, ly, label.to_s, font: f_font, size: f_size, color: theme.text_color)
          end
        end

        ctrl_x = rx + label_w
        ctrl_w = [rw - label_w, btn_w * 2.0 + 30.0].max
        minus_x = ctrl_x
        plus_x = ctrl_x + ctrl_w - btn_w
        val_x = ctrl_x + btn_w + 2.0
        val_w = ctrl_w - btn_w * 2.0 - 4.0

        # 中央の値表示ボックス
        track_b = theme.track_border || theme.border_normal
        Window.draw_rect(
          val_x, ry, val_w, rh,
          radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
          color: theme.track_bg || theme.bg_normal,
          border_width: track_b ? track_b[0].to_f : 1.0,
          border_color: track_b ? track_b[1] : nil
        )

        v_str = value_str.to_s
        tw = f_font.text_width(v_str, f_size)
        Profiler.measure(:gui_text) do
          Window.draw_text(val_x + (val_w - tw) * 0.5, ry + (rh - f_size.to_f) * 0.5, v_str, font: f_font, size: f_size, color: theme.text_color)
        end

        # [-] ボタン
        m_border = minus_hover ? theme.border_hover : theme.border_normal
        Window.draw_rect(
          minus_x, ry, btn_w, rh,
          radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
          color: minus_hover ? theme.bg_hover : theme.bg_normal,
          border_width: m_border ? m_border[0].to_f : 1.0,
          border_color: m_border ? m_border[1] : nil
        )
        minus_col = minus_hover ? theme.text_color : (theme.text_disabled || theme.text_color)
        Window.draw_rect(minus_x + 10.0, ry + rh * 0.5 - 1.0, btn_w - 20.0, 2.0, color: minus_col)

        # [+] ボタン
        p_border = plus_hover ? theme.border_hover : theme.border_normal
        Window.draw_rect(
          plus_x, ry, btn_w, rh,
          radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
          color: plus_hover ? theme.bg_hover : theme.bg_normal,
          border_width: p_border ? p_border[0].to_f : 1.0,
          border_color: p_border ? p_border[1] : nil
        )
        plus_col = plus_hover ? theme.text_color : (theme.text_disabled || theme.text_color)
        Window.draw_rect(plus_x + 10.0, ry + rh * 0.5 - 1.0, btn_w - 20.0, 2.0, color: plus_col)
        Window.draw_rect(plus_x + btn_w * 0.5 - 1.0, ry + 10.0, 2.0, rh - 20.0, color: plus_col)
      end

      # ----------------------------------------------------
      # スクロールバー描画
      # ----------------------------------------------------
      def draw_scrollbar(x, y, w, h, thumb_y, thumb_h, state, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        # トラック
        Window.draw_rect(rx, ry, rw, rh, radius: rw * 0.5, color: theme.track_bg || theme.bg_normal)

        if thumb_h && thumb_h > 0.0
          ty = thumb_y.to_f
          th = thumb_h.to_f
          thumb_col = if state == :active
                        theme.accent_hover || theme.accent_color
                      elsif state == :hover
                        theme.border_active ? theme.border_active[1] : theme.accent_color
                      else
                        theme.border_hover ? theme.border_hover[1] : theme.bg_active
                      end

          Window.draw_rect(
            rx + 2.0, ty, rw - 4.0, th,
            radius: (rw - 4.0) * 0.5,
            color: thumb_col
          )
        end
      end

      # ----------------------------------------------------
      # リストボックス枠描画
      # ----------------------------------------------------
      def draw_listbox_frame(x, y, w, h, label, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        f_font = theme.font || Font.default
        f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 14

        has_label = !label.to_s.empty?
        if has_label
          Profiler.measure(:gui_text) do
            Window.draw_text(rx, ry + 2.0, label.to_s, font: f_font, size: f_size, color: theme.text_color)
          end
        end

        label_h = has_label ? 22.0 : 0.0
        list_y = ry + label_h
        track_b = theme.track_border || theme.border_normal

        Window.draw_rect(
          rx, list_y, rw, rh,
          radius: theme.corner_radius || 4.0,
          color: theme.track_bg || theme.bg_normal,
          border_width: track_b ? track_b[0].to_f : 1.0,
          border_color: track_b ? track_b[1] : nil
        )
      end

      # ----------------------------------------------------
      # リストボックスアイテム描画
      # ----------------------------------------------------
      def draw_listbox_item(x, y, w, h, text, selected, hover, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        f_font = theme.font || Font.default
        f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 14

        if selected
          Window.draw_rect(
            rx + 4.0, ry + 1.0, rw - 4.0, rh - 2.0,
            radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
            color: theme.bg_active
          )
        elsif hover
          Window.draw_rect(
            rx + 4.0, ry + 1.0, rw - 4.0, rh - 2.0,
            radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max,
            color: theme.bg_hover
          )
        end

        tcol = (selected || hover) ? theme.text_color : (theme.text_disabled || theme.text_color)
        Profiler.measure(:gui_text) do
          Window.draw_text(rx + 10.0, ry + (rh - f_size.to_f) * 0.5, text.to_s, font: f_font, size: f_size, color: tcol)
        end
      end

      # ----------------------------------------------------
      # ドロップダウン本体描画
      # ----------------------------------------------------
      def draw_dropdown(x, y, w, h, label, selected_text, is_open, hover, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        f_font = theme.font || Font.default
        f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 14

        has_label = !label.to_s.empty?
        if has_label
          Profiler.measure(:gui_text) do
            Window.draw_text(rx, ry + 1.0, label.to_s, font: f_font, size: f_size, color: theme.text_color)
          end
        end

        label_h = has_label ? 20.0 : 0.0
        ctrl_y = ry + label_h

        border_cfg = (hover || is_open) ? theme.border_hover : theme.border_normal
        b_width = border_cfg ? border_cfg[0].to_f : 1.0
        b_color = border_cfg ? border_cfg[1] : theme.accent_color
        bg_col  = (hover || is_open) ? theme.bg_hover : theme.bg_normal

        Window.draw_rect(
          rx, ctrl_y, rw, rh,
          radius: theme.corner_radius || 4.0,
          color: bg_col,
          border_width: b_width,
          border_color: b_color
        )

        sel_str = selected_text.to_s
        Profiler.measure(:gui_text) do
          Window.draw_text(
            rx + 10.0, ctrl_y + (rh - f_size.to_f) * 0.5,
            sel_str,
            font: f_font, size: f_size,
            color: theme.text_color
          )
        end

        # 下向き三角矢印 (▼)
        arrow_x = rx + rw - 18.0
        arrow_y = ctrl_y + rh * 0.5 - 2.0
        arrow_col = (hover || is_open) ? theme.accent_color : (theme.text_disabled || theme.text_color)
        Window.draw_triangle(
          arrow_x, arrow_y,
          arrow_x + 8.0, arrow_y,
          arrow_x + 4.0, arrow_y + 5.0,
          color: arrow_col
        )
      end

      # ----------------------------------------------------
      # ドロップダウンポップアップ枠描画
      # ----------------------------------------------------
      def draw_dropdown_popup_frame(x, y, w, h, z, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        pop_z = z ? z.to_f : 500.0

        b_cfg = theme.border_hover || theme.border_normal
        s_cfg = theme.shadow_normal

        Window.draw_rect(
          rx, ry, rw, rh,
          radius: theme.corner_radius || 4.0,
          color: theme.win_bg || theme.bg_normal,
          border_width: b_cfg ? b_cfg[0].to_f : 1.0,
          border_color: theme.accent_color,
          shadow_blur: s_cfg ? s_cfg[0].to_f : 0.0,
          shadow_color: s_cfg ? s_cfg[1] : nil,
          z: pop_z
        )
      end

      # ----------------------------------------------------
      # ドロップダウンポップアップアイテム描画
      # ----------------------------------------------------
      def draw_dropdown_popup_item(x, y, w, h, text, selected, hover, z, theme, **_opts)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f
        pop_z = z ? z.to_f : 500.0
        f_font = theme.font || Font.default
        f_size = theme.font_size.to_i > 0 ? theme.font_size.to_i : 14

        if selected
          Window.draw_rect(rx + 3.0, ry, rw - 6.0, rh, radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max, color: theme.bg_active, z: pop_z + 1.0)
        elsif hover
          Window.draw_rect(rx + 3.0, ry, rw - 6.0, rh, radius: [ (theme.corner_radius || 4.0) - 1.0, 1.0 ].max, color: theme.bg_hover, z: pop_z + 1.0)
        end

        it_col = (selected || hover) ? theme.text_color : (theme.text_disabled || theme.text_color)
        Profiler.measure(:gui_text) do
          Window.draw_text(rx + 10.0, ry + (rh - f_size.to_f) * 0.5, text.to_s, font: f_font, size: f_size, color: it_col, z: pop_z + 2.0)
        end
      end

      # ----------------------------------------------------
      # スクロールビュー外枠描画
      # ----------------------------------------------------
      def draw_scroll_view_frame(x, y, w, h, theme, **_opts)
        track_b = theme.track_border || theme.border_normal
        Window.draw_rect(
          x.to_f, y.to_f, w.to_f, h.to_f,
          radius: theme.corner_radius || 4.0,
          color: theme.track_bg || theme.bg_normal,
          border_width: track_b ? track_b[0].to_f : 1.0,
          border_color: track_b ? track_b[1] : nil
        )
      end
    end
  end
end

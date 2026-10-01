# frozen_string_literal: true

require_relative 'renderer'

module Zenoo
  module GUI
    # draw_card を活用した標準のモダン・カード描画レンダラー
    class CardRenderer < Renderer
      # ----------------------------------------------------
      # ボタン描画
      # ----------------------------------------------------
      def draw_button(x, y, w, h, label, state, theme)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        # 状態別のスタイル選択
        bg_col     = theme.bg_normal
        border_cfg = theme.border_normal
        shadow_cfg = theme.shadow_normal

        if state == :active
          bg_col     = theme.bg_active
          border_cfg = theme.border_active
          shadow_cfg = theme.shadow_active
        elsif state == :hover
          bg_col     = theme.bg_hover
          border_cfg = theme.border_hover
          shadow_cfg = theme.shadow_hover
        end

        b_w = border_cfg ? border_cfg[0] : 0.0
        b_c = border_cfg ? border_cfg[1] : :cyan
        s_b = shadow_cfg ? shadow_cfg[0] : 0.0
        s_c = shadow_cfg ? shadow_cfg[1] : [0, 0, 0, 180]

        # 背景カード描画 (SDF角丸 + ボーダー + シャドウ)
        Window.draw_card(
          rx, ry, rw, rh,
          radius: theme.corner_radius,
          color: bg_col,
          border_width: b_w,
          border_color: b_c,
          shadow_blur: s_b,
          shadow_color: s_c
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
      def draw_slider(x, y, w, h, label, value, min, max, state, theme)
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

          # 数値テキスト (小数点以下1桁)
          v_int = v_val.to_i
          v_dec = ((v_val - v_int.to_f).abs * 10.0).to_i
          val_str = "#{v_int}.#{v_dec}"
          val_w = f_font.text_width(val_str, f_size)
          Window.draw_text(rx + rw - val_w, ry, val_str, font: f_font, size: f_size, color: theme.accent_color)

          track_y = ry + f_size.to_f + 8.0
          track_h = 8.0
        else
          track_y = ry + (rh - 8.0) / 2.0
          track_h = 8.0
        end

        # トラック溝 (背景)
        tb_w = theme.track_border ? theme.track_border[0].to_f : 0.0
        tb_c = theme.track_border ? theme.track_border[1] : :cyan
        Window.draw_card(
          rx, track_y, rw, track_h,
          radius: 4.0,
          color: theme.track_bg,
          border_width: tb_w,
          border_color: tb_c
        )

        # 進行度フィル (左端からノブ位置まで)
        fill_w = rw * ratio
        if fill_w > 4.0
          fill_color = (state == :hover || state == :active) ? theme.accent_hover : theme.accent_color
          Window.draw_card(
            rx, track_y, fill_w, track_h,
            radius: 4.0,
            color: fill_color
          )
        end

        # ノブ (つまみ)
        knob_size = 18.0
        knob_radius = knob_size / 2.0
        knob_x = rx + rw * ratio - knob_radius
        knob_y = track_y + (track_h - knob_size) / 2.0

        knob_color = Color::WHITE
        kb_border = [2.0, (state == :active ? theme.accent_hover : theme.accent_color)]
        kb_shadow = (state == :active ? theme.shadow_active : theme.shadow_normal)

        Window.draw_card(
          knob_x, knob_y, knob_size, knob_size,
          radius: knob_radius,
          color: knob_color,
          border_width: kb_border[0].to_f,
          border_color: kb_border[1],
          shadow_blur: kb_shadow[0].to_f,
          shadow_color: kb_shadow[1]
        )
      end

      # ----------------------------------------------------
      # ラベル描画
      # ----------------------------------------------------
      def draw_label(x, y, text, size, color, theme)
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
      def hit_test_button(x, y, w, h, px, py, theme)
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
      def draw_text_box(x, y, w, h, text, focused, cursor_pos, blink_on, theme)
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        # 背景色・枠線・影
        bg_col = theme.bg_normal
        if focused
          border_cfg = [2.0, theme.accent_color]
          shadow_cfg = theme.shadow_active
        else
          border_cfg = theme.border_normal
          shadow_cfg = theme.shadow_normal
        end

        b_w = border_cfg ? border_cfg[0] : 1.0
        b_c = border_cfg ? border_cfg[1] : [60, 70, 90, 255]
        s_b = shadow_cfg ? shadow_cfg[0] : 0.0
        s_c = shadow_cfg ? shadow_cfg[1] : [0, 0, 0, 180]

        Window.draw_card(
          rx, ry, rw, rh,
          radius: theme.corner_radius,
          color: bg_col,
          border_width: b_w,
          border_color: b_c,
          shadow_blur: s_b,
          shadow_color: s_c
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

      def hit_test_text_box(x, y, w, h, px, py, theme)
        hit_test_button(x, y, w, h, px, py, theme)
      end

      # パネル (カード枠) 描画
      def draw_panel(x, y, w, h, title, theme, opts = {})
        rx = x.to_f
        ry = y.to_f
        rw = w.to_f
        rh = h.to_f

        radius     = (opts[:radius] || theme.corner_radius || 12.0).to_f
        bg_col     = opts[:color] || Color.new(24, 28, 38, 240)
        b_width    = (opts[:border_width] || 1.5).to_f
        b_col      = opts[:border_color] || Color.new(60, 70, 90, 200)
        s_blur     = (opts[:shadow_blur] || 16.0).to_f
        s_col      = opts[:shadow_color] || Color.new(0, 0, 0, 150)
        card_image = opts[:image]
        card_z     = (opts[:z] || 0.0).to_f

        Window.draw_card(
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
          title_col  = opts[:title_color] || Color::WHITE
          Window.draw_text(rx + pad, ry + pad, title.to_s, font: f_font, size: title_size, color: title_col)
        end
      end
    end
  end
end

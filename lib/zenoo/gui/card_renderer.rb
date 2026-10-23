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

        knob_color = Color::WHITE
        kb_border = [2.0, (state == :active ? theme.accent_hover : theme.accent_color)]
        kb_shadow = (state == :active ? theme.shadow_active : theme.shadow_normal)

        Window.draw_rect(
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
        bg_col = theme.bg_normal
        if focused
          border_cfg = [2.0, theme.accent_color]
        else
          border_cfg = theme.border_normal
        end

        b_w = border_cfg ? border_cfg[0] : 1.0
        b_c = border_cfg ? border_cfg[1] : [60, 70, 90, 255]

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

        radius     = (opts[:radius] || theme.corner_radius || 12.0).to_f
        bg_col     = opts[:color] || Color.new(24, 28, 38, 240)
        b_width    = (opts[:border_width] || 1.5).to_f
        b_col      = opts[:border_color] || Color.new(60, 70, 90, 200)
        s_blur     = (opts[:shadow_blur] || 16.0).to_f
        s_col      = opts[:shadow_color] || Color.new(0, 0, 0, 150)
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
          title_col  = opts[:title_color] || Color::WHITE
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
        border_color = border_cfg ? border_cfg[1] : Color.new(80, 80, 80)

        shadow_blur  = active ? 8.0 : 4.0
        shadow_color = Color.new(0, 0, 0, active ? 140 : 100)
        win_bg_col   = theme.win_bg || Color.new(30, 30, 32, 245)
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
        title_bg = active ? (theme.win_title_bg_active || Color.new(52, 52, 58)) : (theme.win_title_bg || Color.new(42, 42, 45))
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
          title_col = active ? (theme.text_color || Color::WHITE) : (theme.text_disabled || Color.new(160, 160, 165))
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
          grip_color = active ? (theme.win_border_active ? theme.win_border_active[1] : Color.new(140, 140, 150)) : Color.new(80, 80, 85)
          rx = wx + ww - 15.0
          ry = wy + wh - 15.0
          Window.draw_line(rx + 8.0, ry + 12.0, rx + 12.0, ry + 8.0, color: grip_color, width: 1.5, z: win_z + 2.0)
          Window.draw_line(rx + 4.0, ry + 12.0, rx + 12.0, ry + 4.0, color: grip_color, width: 1.5, z: win_z + 2.0)
          Window.draw_line(rx + 0.0, ry + 12.0, rx + 12.0, ry + 0.0, color: grip_color, width: 1.5, z: win_z + 2.0)
        end
      end
    end
  end
end

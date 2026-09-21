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

        # 背景カード描画 (SDF角丸 + ボーダー + シャドウ)
        Window.draw_card(
          rx, ry, rw, rh,
          radius: theme.corner_radius,
          color: bg_col,
          border: border_cfg,
          shadow: shadow_cfg
        )

        # テキストの描画 (ボタン幅に収まるよう厳密に計算 & センタリング)
        if label
          text_str = label.to_s
          text_len = text_str.length
          if text_len > 0
            f_size = theme.font_size.to_i
            f_size = 14 if f_size <= 0

            # 8x8 等幅フォント: 1文字幅 = f_size
            text_w = text_len.to_f * f_size.to_f

            # ボタン枠 (左右パディング 12px) からはみ出す場合は、ボタン内に収まるサイズに自動スケール
            pad_x = 12.0
            avail_w = rw - pad_x * 2.0
            if avail_w > 8.0 && text_w > avail_w
              f_size = (avail_w / text_len.to_f).to_i
              f_size = 8 if f_size < 8
              text_w = text_len.to_f * f_size.to_f
            end

            text_x = rx + (rw - text_w) / 2.0
            text_y = ry + (rh - f_size.to_f) / 2.0

            # アクティブ時は1px押し込み演出
            if state == :active
              text_y += 1.0
            end

            Font.draw_text(text_x, text_y, text_str, size: f_size, color: theme.text_color)
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

        # 上部: ラベル & 数値
        has_label = label && label.to_s.length > 0
        if has_label
          label_str = label.to_s
          Font.draw_text(rx, ry, label_str, size: f_size, color: theme.text_color)

          # 数値テキスト (小数点以下1桁)
          v_int = v_val.to_i
          v_dec = ((v_val - v_int.to_f).abs * 10.0).to_i
          val_str = "#{v_int}.#{v_dec}"
          val_w = val_str.length.to_f * f_size.to_f
          Font.draw_text(rx + rw - val_w, ry, val_str, size: f_size, color: theme.accent_color)

          track_y = ry + f_size.to_f + 8.0
          track_h = 8.0
        else
          track_y = ry + (rh - 8.0) / 2.0
          track_h = 8.0
        end

        # トラック溝 (背景)
        Window.draw_card(
          rx, track_y, rw, track_h,
          radius: 4.0,
          color: theme.track_bg,
          border: theme.track_border,
          shadow: nil
        )

        # 進行度フィル (左端からノブ位置まで)
        fill_w = rw * ratio
        if fill_w > 4.0
          fill_color = (state == :hover || state == :active) ? theme.accent_hover : theme.accent_color
          Window.draw_card(
            rx, track_y, fill_w, track_h,
            radius: 4.0,
            color: fill_color,
            border: nil,
            shadow: nil
          )
        end

        # ノブ (つまみ)
        knob_size = 18.0
        knob_radius = knob_size / 2.0
        knob_x = rx + rw * ratio - knob_radius
        knob_y = track_y + (track_h - knob_size) / 2.0

        knob_color = Color::WHITE
        knob_border = [2.0, (state == :active ? theme.accent_hover : theme.accent_color)]
        knob_shadow = (state == :active) ? theme.shadow_active : theme.shadow_normal

        Window.draw_card(
          knob_x, knob_y, knob_size, knob_size,
          radius: knob_radius,
          color: knob_color,
          border: knob_border,
          shadow: knob_shadow
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
        Font.draw_text(x.to_f, y.to_f, text.to_s, size: f_size, color: c_color)
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
    end
  end
end

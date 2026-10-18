# frozen_string_literal: true

module Zenoo
  module GUI
    # プロファイルグラフ (Profile Graph / Frame Time Histogram) 描画モジュール
    module ProfileGraph
      class << self
        # 各処理の実行時間 (ms) をカテゴリ別に積み上げ棒グラフとして描画し、全体の高さを返却
        def draw(rx, ry, rw, rh, max_ms, show_legend, can_interact, mouse_x, mouse_y, theme)
          f_font = theme.font || Font.default

          # 1. グラフ枠・背景の描画
          graph_bg = Color.new(24, 24, 26, 230)
          graph_border = Color.new(55, 55, 60, 200)
          Window.draw_rect(rx, ry, rw, rh, color: graph_bg, border_color: graph_border, border_width: 1.0)

          # 2. ガイドライン描画 (16.6ms / 33.3ms)
          draw_guidelines(rx, ry, rw, rh, max_ms, f_font)

          # 3. フレーム履歴とホバー判定
          bar_w = 3.0
          max_bars = ((rw - 4.0) / bar_w).to_i
          visible_frames = Profiler.history.last(max_bars)
          hovered_idx = calc_hover(rx, ry, rw, rh, bar_w, visible_frames, can_interact, mouse_x, mouse_y)

          # 4. フレーム履歴の積み上げ棒グラフ描画 (一括バッチ)
          draw_bars(rx, ry, rw, rh, max_ms, bar_w, visible_frames, hovered_idx)

          # 5. 上部ステータステキスト & ホバー情報
          draw_header(rx, ry, rw, f_font, visible_frames, hovered_idx)

          # 6. 詳細内訳リスト (Legend)
          total_h = rh
          if show_legend
            total_h = draw_legend(rx, ry, rw, rh, f_font)
          end

          total_h
        end

        private

        def draw_guidelines(rx, ry, rw, rh, max_ms, f_font)
          target_60_y = ry + rh - (16.666 / max_ms) * rh
          if target_60_y >= ry && target_60_y <= ry + rh
            line_color = Color.new(80, 160, 180, 140)
            Window.draw_line(rx + 1.0, target_60_y, rx + rw - 1.0, target_60_y, color: line_color, width: 1.0)
            Profiler.measure(:gui_text) do
              Window.draw_text(rx + 4.0, target_60_y - 12.0, "16.6ms (60fps)", font: f_font, size: 10, color: line_color)
            end
          end

          return unless max_ms > 33.33
          target_30_y = ry + rh - (33.333 / max_ms) * rh
          if target_30_y >= ry && target_30_y <= ry + rh
            line_color_30 = Color.new(180, 80, 80, 140)
            Window.draw_line(rx + 1.0, target_30_y, rx + rw - 1.0, target_30_y, color: line_color_30, width: 1.0)
            Profiler.measure(:gui_text) do
              Window.draw_text(rx + 4.0, target_30_y - 12.0, "33.3ms (30fps)", font: f_font, size: 10, color: line_color_30)
            end
          end
        end

        def calc_hover(rx, ry, rw, rh, bar_w, visible_frames, can_interact, mx, my)
          in_bounds = mx >= rx && mx <= (rx + rw) && my >= ry && my <= (ry + rh)
          return nil unless can_interact && in_bounds && !visible_frames.empty?

          dist_from_right = (rx + rw - 2.0) - mx
          return nil if dist_from_right < 0

          idx_from_end = (dist_from_right / bar_w).to_i
          return nil if idx_from_end >= visible_frames.size
          visible_frames.size - 1 - idx_from_end
        end

        def draw_bars(rx, ry, rw, rh, max_ms, bar_w, visible_frames, hovered_idx)
          if hovered_idx && hovered_idx >= 0 && hovered_idx < visible_frames.size
            hbx = rx + rw - 2.0 - (visible_frames.size - hovered_idx) * bar_w
            Window.draw_rect(hbx, ry + 1.0, bar_w, rh - 2.0, color: Color.new(255, 255, 255, 60))
          end

          ox = Window.offset_x
          oy = Window.offset_y
          bars_batch = []
          rect_count = 0
          bw = [bar_w - 0.5, 1.0].max
          bar_col_cache = @bar_color_cache ||= {}
          categories = Profiler.categories

          visible_frames.each_with_index do |frame, i|
            bx = rx + rw - 2.0 - (visible_frames.size - i) * bar_w
            next if bx < rx + 1.0

            bx2 = bx + bw
            current_y = ry + rh - 1.0
            abx = bx + ox
            abx2 = bx2 + ox

            categories.each do |category|
              ms = frame[category]
              next unless ms && ms > 0.0001

              h_cat = (ms.to_f / max_ms) * rh
              next if h_cat < 0.5

              avail_h = current_y - (ry + 1.0)
              break if avail_h <= 0.0
              h_cat = avail_h if h_cat > avail_h

              top_y = current_y - h_cat
              col = bar_col_cache[category] ||= begin
                cat_color = Profiler.color_for(category)
                nc = Backend.normalize_color(cat_color)
                [nc[0].to_f, nc[1].to_f, nc[2].to_f, nc[3].to_f]
              end
              cr, cg, cb, ca = col

              atop_y = top_y + oy
              acur_y = current_y + oy

              bars_batch.push(
                abx, atop_y, cr, cg, cb, ca,
                abx, acur_y, cr, cg, cb, ca,
                abx2, atop_y, cr, cg, cb, ca,
                abx2, atop_y, cr, cg, cb, ca,
                abx, acur_y, cr, cg, cb, ca,
                abx2, acur_y, cr, cg, cb, ca
              )
              rect_count += 1
              current_y = top_y
            end
          end

          if rect_count > 0
            Backend.enqueue_draw(
              Backend::Pipelines::TRIANGLES,
              bars_batch.pack("f*"),
              rect_count * 6,
              shader: Window.flat_primitive_shader
            )
          end
        end

        def draw_header(rx, ry, rw, f_font, visible_frames, hovered_idx)
          total_last = Profiler.last_total_ms
          avg_last = visible_frames.empty? ? 0.0 : (visible_frames.last(30).map { |f| f.values.sum }.sum / [visible_frames.size, 30].min)
          status_text = "Avg: #{avg_last.round(1)}ms | Last: #{total_last.round(1)}ms | #{Window.fps.round(0)} FPS"
          Profiler.measure(:gui_text) do
            Window.draw_text(rx + rw - 6.0, ry + 4.0, status_text, font: f_font, size: 11, color: Color.new(200, 200, 200), align: :right)
          end

          if hovered_idx && visible_frames[hovered_idx]
            target_frame = visible_frames[hovered_idx]
            frame_tot = target_frame.values.sum.round(2)
            hover_str = "Frame: #{frame_tot}ms (" + target_frame.map { |k, v| "#{k}:#{v.round(1)}" }.join(", ") + ")"
            Profiler.measure(:gui_text) do
              Window.draw_text(rx + 6.0, ry + 4.0, hover_str, font: f_font, size: 11, color: Color.new(255, 240, 100))
            end
          end
        end

        def draw_legend(rx, ry, rw, rh, f_font)
          avg_map = Profiler.average_times(30)
          total_avg = [avg_map.values.sum, 0.0001].max
          sorted_cats = Profiler.categories.sort_by { |cat| -(avg_map[cat] || 0.0) }

          legend_y = ry + rh + 8.0
          chip_size = 8.0

          sorted_cats.each do |cat|
            avg_ms = avg_map[cat] || 0.0
            last_ms = (Profiler.last_times[cat] || 0.0)
            next if avg_ms < 0.005 && last_ms < 0.005

            pct = ((avg_ms / total_avg) * 100.0).round(0)
            cat_col = Profiler.color_for(cat)

            Window.draw_rect(rx + 4.0, legend_y + 2.0, chip_size, chip_size, color: cat_col)

            Profiler.measure(:gui_text) do
              Window.draw_text(rx + 16.0, legend_y, cat.to_s, font: f_font, size: 11, color: Color.new(200, 205, 210))

              val_100 = (avg_ms * 100).to_i
              val_dec = val_100 % 100
              val_str = "#{val_100 / 100}.#{val_dec < 10 ? '0' : ''}#{val_dec}ms"
              ms_str = "#{val_str} (#{pct}%)"
              Window.draw_text(rx + rw - 4.0, legend_y, ms_str, font: f_font, size: 11, color: Color.new(160, 210, 240), align: :right)
            end

            legend_y += 15.0
          end

          (legend_y + 4.0) - ry
        end
      end
    end
  end
end

# frozen_string_literal: true

# ==============================================================================
# Zenoo::Dev::Inspector - Smalltalk風 高密度ライブ・オブジェクトインスペクタ
# ※ CRuby 実行時専用。F12 キーで開閉。ゼロアロケーション指向に最適化済み。
# ==============================================================================

module Zenoo
  module Dev
    class Inspector
      # 定数カラー定義 (毎フレームの配列アロケーションをゼロにする)
      COL_BG_LIST     = [16, 20, 28, 230].freeze
      COL_BG_SHEET    = [14, 17, 24, 240].freeze
      COL_BORDER      = [50, 60, 80, 200].freeze
      COL_ROW_SEL     = [40, 80, 150, 200].freeze
      COL_ROW_HOVER   = [30, 45, 65, 180].freeze
      COL_ROW_EVEN    = [22, 28, 40, 100].freeze
      COL_PROP_SEL    = [35, 60, 95, 200].freeze
      COL_PROP_HOVER  = [25, 35, 50, 180].freeze
      COL_PROP_EVEN   = [18, 22, 32, 100].freeze
      COL_TBL_HDR     = [25, 32, 45, 255].freeze

      COL_TXT_TITLE   = [140, 180, 240, 255].freeze
      COL_TXT_GOLD    = [255, 215, 80, 255].freeze
      COL_TXT_HDR     = [130, 150, 180, 255].freeze
      COL_TXT_WHITE   = [255, 255, 255, 255].freeze
      COL_TXT_HOVER   = [200, 230, 255, 255].freeze
      COL_TXT_MUTED   = [170, 180, 195, 255].freeze
      COL_TXT_PROP    = [160, 200, 240, 255].freeze

      COL_VAL_NUM     = [255, 170, 90, 255].freeze  # オレンジ
      COL_VAL_BOOL    = [120, 230, 140, 255].freeze # ライトグリーン
      COL_VAL_SYM     = [230, 130, 230, 255].freeze # マゼンタ
      COL_VAL_STR     = [240, 240, 140, 255].freeze # イエロー
      COL_VAL_NIL     = [130, 130, 140, 255].freeze # グレー
      COL_VAL_DEF     = [210, 215, 225, 255].freeze

      COL_COL_SEL_BD  = [255, 230, 80, 255].freeze
      COL_COL_SEL_BG  = [255, 230, 80, 40].freeze
      COL_COL_NORM_BD = [80, 240, 140, 200].freeze
      COL_COL_NORM_BG = [80, 240, 140, 30].freeze

      class << self
        attr_accessor :visible, :show_colliders, :pause_game, :selected_object

        def init
          @visible = false
          @show_colliders = false
          @pause_game = false
          @selected_object = nil
          @tab_index = 0
          @selected_var = nil
          @scroll_sprites = 0.0
          @scroll_props = 0.0

          # キャッシュ用バッファ
          @sprites_cache = []
          @cache_frame = 0
          @props_buffer = []
        end

        def toggle
          @visible = !@visible
        end

        def update
          if Input.key_push?(:f12)
            toggle
          end
        end

        # コライダーの強制可視化オーバーレイ描画
        def draw_colliders
          return unless @show_colliders

          ObjectSpace.each_object(Zenoo::Sprite) do |sprite|
            next unless sprite.respond_to?(:collider)
            col = sprite.collider
            next unless col

            is_selected = (sprite == @selected_object)
            border_col = is_selected ? COL_COL_SEL_BD : COL_COL_NORM_BD
            bg_col = is_selected ? COL_COL_SEL_BG : COL_COL_NORM_BG

            if col.respond_to?(:radius) && col.radius > 0 && (!col.respond_to?(:half_w) || col.half_w == 0)
              cx = col.respond_to?(:center_x) ? col.center_x : sprite.x
              cy = col.respond_to?(:center_y) ? col.center_y : sprite.y
              Window.draw_circle(cx, cy, col.radius, color: bg_col, border_width: 1.5, border_color: border_col)
            elsif col.respond_to?(:half_w) && col.half_w > 0
              cx = col.respond_to?(:center_x) ? col.center_x : sprite.x
              cy = col.respond_to?(:center_y) ? col.center_y : sprite.y
              w = col.half_w * 2.0
              h = col.half_h * 2.0
              rot = col.respond_to?(:angle) ? col.angle : sprite.angle
              Window.draw_rect(
                cx - col.half_w, cy - col.half_h, w, h,
                angle: rot,
                color: bg_col,
                border_width: 1.5,
                border_color: border_col,
                radius: col.respond_to?(:radius) ? col.radius : 0.0
              )
            else
              w = sprite.width * sprite.scale_x.abs
              h = sprite.height * sprite.scale_y.abs
              Window.draw_rect(
                sprite.x - w * 0.5, sprite.y - h * 0.5, w, h,
                angle: sprite.angle,
                color: bg_col,
                border_width: 1.0,
                border_color: border_col
              )
            end
          end
        end

        # 即時モード GUI の描画
        def render_gui
          return unless @visible

          Window.without_camera do
            # スリムなコンパクトウィンドウ (GUI.window 内は自動でローカル座標系)
            GUI.window("🔍 Inspector (F12)", x: 20, y: 20, w: 360, h: 540, resizable: true, min_w: 280, min_h: 300) do |win|
              content_w = [win.w - 24.0, 100.0].max
              content_h = [win.h - 56.0, 100.0].max

              # 1. コンパクトなタブバー (ローカル座標 (0, 0))
              GUI.cursor(0, 0)
              @tab_index ||= 0
              @tab_index = GUI.tabs(["Sprites", "Stats", "Globals"], @tab_index, h: 26.0)

              # 2. コンパクトなオプションバー (ローカル座標 (0, 32))
              opt_y = 32.0
              GUI.cursor(0, opt_y)
              @show_colliders = GUI.checkbox("Colliders", @show_colliders, h: 22.0)
              GUI.cursor(110, opt_y)
              @pause_game = GUI.checkbox("Pause", @pause_game, h: 22.0)

              top_y = 60.0
              body_h = [content_h - top_y, 50.0].max

              case @tab_index
              when 0
                render_sprites_dense(content_w, body_h, top_y)
              when 1
                render_stats_dense(content_w, body_h, top_y)
              when 2
                render_globals_dense(content_w, body_h, top_y)
              end
            end
          end
        end

        private

        # スプライト一覧の取得 (毎フレーム全走査せず10フレームおきに更新)
        def active_sprites
          @cache_frame += 1
          if @sprites_cache.empty? || (@cache_frame % 10 == 0)
            @sprites_cache.clear
            ObjectSpace.each_object(Zenoo::Sprite) { |s| @sprites_cache << s }
          end
          @sprites_cache
        end

        # 高密度 2ペイン表示 (上: スプライト一覧, 下: プロパティシート)
        def render_sprites_dense(w, h, top_y)
          sprites = active_sprites

          # 上部: スプライトリスト (高さ 130px)
          list_h = [130.0, h * 0.35].min
          prop_h = [h - list_h - 8.0, 40.0].max

          # --- 1. スプライト一覧リスト ---
          Window.draw_rect(0.0, top_y, w, list_h, color: COL_BG_LIST, radius: 4.0, border_width: 1.0, border_color: COL_BORDER)
          Window.draw_text(6.0, top_y + 4.0, "Active Sprites (#{sprites.size})", size: 12, color: COL_TXT_TITLE)

          item_h = 18.0
          list_clip_y = top_y + 20.0
          list_clip_h = [list_h - 22.0, 1.0].max
          list_clip_w = w - 10.0
          total_list_h = [sprites.size * item_h, list_clip_h].max

          mx = GUI.gui_mouse_x
          my = GUI.gui_mouse_y
          click = Input.mouse_push?(:left)

          # マウスホイールによるスクロール
          if mx >= 0.0 && mx <= w && my >= top_y && my <= top_y + list_h
            if Input.mouse_wheel_y != 0
              @scroll_sprites -= Input.mouse_wheel_y.to_f * 24.0
            end
          end

          # スクロールバー描画 & ドラッグ操作
          @scroll_sprites = GUI.scrollbar(
            @scroll_sprites, total_list_h, list_clip_h,
            x: w - 8.0, y: list_clip_y, w: 6.0, h: list_clip_h, id: "sp_scroll"
          )
          max_sp_scroll = [total_list_h - list_clip_h, 0.0].max
          @scroll_sprites = @scroll_sprites.clamp(0.0, max_sp_scroll)

          # クリップ領域内でのアイテム描画
          Window.clip(0.0, list_clip_y, list_clip_w, list_clip_h, local: false) do
            sprites.each_with_index do |s, idx|
              ry = list_clip_y - @scroll_sprites + idx * item_h
              # カリング (可視範囲外は文字列生成・描画を完全スキップ)
              next if ry + item_h < list_clip_y || ry > list_clip_y + list_clip_h

              rx = 2.0
              rw = list_clip_w - 4.0
              is_hover = (mx >= rx && mx <= rx + rw && my >= ry && my <= ry + item_h && my >= list_clip_y && my <= list_clip_y + list_clip_h)
              is_sel = (s == @selected_object)

              if is_hover && click
                @selected_object = s
                @selected_var = nil
                @scroll_props = 0.0
              end

              # 行背景
              bg_col = is_sel ? COL_ROW_SEL : (is_hover ? COL_ROW_HOVER : (idx.even? ? COL_ROW_EVEN : nil))
              Window.draw_rect(rx, ry, rw, item_h, color: bg_col, radius: 2.0) if bg_col

              name = s.class.name || "Sprite"
              text = "#{name} (x:#{s.x.round(1)}, y:#{s.y.round(1)})"
              txt_col = is_sel ? COL_TXT_WHITE : (is_hover ? COL_TXT_HOVER : COL_TXT_MUTED)
              Window.draw_text(rx + 6.0, ry + 2.0, text, size: 12, color: txt_col)
            end
          end

          # --- 2. 下部: プロパティシート (Inspector) ---
          sheet_y = top_y + list_h + 6.0
          Window.draw_rect(0.0, sheet_y, w, prop_h, color: COL_BG_SHEET, radius: 4.0, border_width: 1.0, border_color: COL_BORDER)

          unless @selected_object
            Window.draw_text(8.0, sheet_y + 8.0, "Select a sprite above to inspect", size: 12, color: COL_TXT_HDR)
            return
          end

          obj = @selected_object
          hex_id = obj.object_id.to_s(16)
          short_id = hex_id.length > 6 ? hex_id[-6..-1] : hex_id
          title_text = "#{obj.class} [0x#{short_id}]"
          Window.draw_text(6.0, sheet_y + 4.0, title_text, size: 12, color: COL_TXT_GOLD)

          # 変数バッファの再利用
          props = (@props_buffer ||= [])
          props.clear
          props << ["x", obj.x.round(2)]
          props << ["y", obj.y.round(2)]
          props << ["angle", obj.angle.round(2)]
          props << ["scale_x", obj.scale_x.round(2)]
          props << ["scale_y", obj.scale_y.round(2)]
          props << ["alpha", obj.alpha.round(2)]

          obj.instance_variables.each do |ivar|
            next if [:@x, :@y, :@angle, :@scale_x, :@scale_y, :@alpha].include?(ivar)
            props << [ivar.to_s, obj.instance_variable_get(ivar)]
          end

          # テーブルヘッダー (Property / Value)
          tbl_header_y = sheet_y + 22.0
          Window.draw_rect(2.0, tbl_header_y, w - 4.0, 16.0, color: COL_TBL_HDR)
          Window.draw_text(6.0, tbl_header_y + 1.0, "Property", size: 11, color: COL_TXT_HDR)
          Window.draw_text(120.0, tbl_header_y + 1.0, "Value", size: 11, color: COL_TXT_HDR)

          p_item_h = 18.0
          prop_clip_y = tbl_header_y + 18.0
          prop_clip_h = [sheet_y + prop_h - prop_clip_y - 2.0, 1.0].max
          prop_clip_w = w - 10.0
          total_prop_h = [props.size * p_item_h, prop_clip_h].max

          # マウスホイールによるスクロール
          if mx >= 0.0 && mx <= w && my >= sheet_y && my <= sheet_y + prop_h
            if Input.mouse_wheel_y != 0
              @scroll_props -= Input.mouse_wheel_y.to_f * 24.0
            end
          end

          # スクロールバー描画 & ドラッグ操作
          @scroll_props = GUI.scrollbar(
            @scroll_props, total_prop_h, prop_clip_h,
            x: w - 8.0, y: prop_clip_y, w: 6.0, h: prop_clip_h, id: "prop_scroll"
          )
          max_prop_scroll = [total_prop_h - prop_clip_h, 0.0].max
          @scroll_props = @scroll_props.clamp(0.0, max_prop_scroll)

          # クリップ領域内でのプロパティ行描画
          Window.clip(0.0, prop_clip_y, prop_clip_w, prop_clip_h, local: false) do
            props.each_with_index do |(prop_name, val), p_idx|
              ry = prop_clip_y - @scroll_props + p_idx * p_item_h
              # 可視範囲外は完全スキップ
              next if ry + p_item_h < prop_clip_y || ry > prop_clip_y + prop_clip_h

              rx = 2.0
              rw = prop_clip_w - 4.0
              is_hover = (mx >= rx && mx <= rx + rw && my >= ry && my <= ry + p_item_h && my >= prop_clip_y && my <= prop_clip_y + prop_clip_h)
              is_selected_var = (@selected_var == prop_name)

              if is_hover && click
                @selected_var = prop_name
              end

              # 行背景
              bg_col = is_selected_var ? COL_PROP_SEL : (is_hover ? COL_PROP_HOVER : (p_idx.even? ? COL_PROP_EVEN : nil))
              Window.draw_rect(rx, ry, rw, p_item_h, color: bg_col) if bg_col

              # プロパティ名 (左カラム)
              Window.draw_text(rx + 4.0, ry + 2.0, prop_name, size: 12, color: COL_TXT_PROP)

              # 値 (右カラム) - 型に応じた色分け (定数参照)
              val_str = val.is_a?(String) ? "\"#{val}\"" : val.to_s
              val_str = val_str[0..26] + "..." if val_str.length > 26

              val_col = case val
                        when Numeric then COL_VAL_NUM
                        when TrueClass, FalseClass then COL_VAL_BOOL
                        when Symbol then COL_VAL_SYM
                        when String then COL_VAL_STR
                        when nil then COL_VAL_NIL
                        else COL_VAL_DEF
                        end

              Window.draw_text(rx + 120.0, ry + 2.0, val_str, size: 12, color: val_col)
            end
          end
        end

        # Stats タブ (高密度コンパクト表示)
        def render_stats_dense(w, h, top_y)
          Window.draw_rect(0.0, top_y, w, h, color: COL_BG_SHEET, radius: 4.0, border_width: 1.0, border_color: COL_BORDER)

          stat = GC.stat
          y = top_y + 10.0

          # アロケーション削減のため個別直接描画
          Window.draw_text(10.0, y, "FPS", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(130.0, y, "#{Window.fps.round(1)} (#{(Window.delta_time * 1000.0).round(2)} ms)", size: 12, color: COL_VAL_NUM)
          y += 20.0

          Window.draw_text(10.0, y, "Window Size", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(130.0, y, "#{Window.width} x #{Window.height}", size: 12, color: COL_VAL_NUM)
          y += 20.0

          Window.draw_text(10.0, y, "GC Count", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(130.0, y, stat[:count].to_s, size: 12, color: COL_VAL_NUM)
          y += 20.0

          Window.draw_text(10.0, y, "Live Heap Slots", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(130.0, y, stat[:heap_live_slots].to_s, size: 12, color: COL_VAL_NUM)
          y += 20.0

          Window.draw_text(10.0, y, "Total Allocated", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(130.0, y, "#{stat[:total_allocated_objects]} objs", size: 12, color: COL_VAL_NUM)
          y += 20.0

          # GC 実行ボタン (コンパクト)
          GUI.cursor(10.0, y + 10.0)
          if GUI.button("Run GC (Garbage Collection)", w: w - 20.0, h: 26.0)
            GC.start
          end
        end

        # Globals タブ (高密度コンパクト表示)
        def render_globals_dense(w, h, top_y)
          Window.draw_rect(0.0, top_y, w, h, color: COL_BG_SHEET, radius: 4.0, border_width: 1.0, border_color: COL_BORDER)

          y = top_y + 10.0
          Window.draw_text(10.0, y, "Program ($0)", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(110.0, y, File.basename($0.to_s), size: 12, color: COL_VAL_DEF)
          y += 20.0

          Window.draw_text(10.0, y, "Ruby Version", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(110.0, y, RUBY_VERSION, size: 12, color: COL_VAL_DEF)
          y += 20.0

          Window.draw_text(10.0, y, "Engine", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(110.0, y, defined?(RUBY_ENGINE) ? RUBY_ENGINE : "CRuby", size: 12, color: COL_VAL_DEF)
          y += 20.0

          Window.draw_text(10.0, y, "Dev Mode", size: 12, color: COL_TXT_TITLE)
          Window.draw_text(110.0, y, Dev.enabled ? "Active (Hot-reload)" : "Disabled", size: 12, color: COL_VAL_DEF)
        end
      end
    end
  end
end

Zenoo::Dev::Inspector.init

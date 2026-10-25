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

          # Stats キャッシュ
          @stats_cache_frame = 0
          @cached_stat_lines = []
          @prev_alloc_count = nil
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
              if @pause_game
                GUI.cursor(185, opt_y)
                if GUI.button("Step", w: 50.0, h: 22.0)
                  Zenoo::Dev.step_frame!
                end
              end

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
          list_h = [130.0, h * 0.38].min
          prop_h = [h - list_h - 10.0, 40.0].max

          # --- 1. スプライト一覧テーブル ---
          sprite_cols = [["Type", 120], ["X", 60], ["Y", 60], "Angle"]
          sprite_rows = sprites.map do |s|
            [s.class.name || "Sprite", s.x.round(1), s.y.round(1), s.angle.round(1)]
          end

          sel_idx = sprites.index(@selected_object)
          new_sel_idx = GUI.table(
            "Active Sprites (#{sprites.size})",
            sprite_cols, sprite_rows, sel_idx,
            x: 0.0, y: top_y, w: w, h: list_h, item_height: 18.0, id: "sp_tbl"
          )
          if new_sel_idx && sprites[new_sel_idx] && new_sel_idx != sel_idx
            @selected_object = sprites[new_sel_idx]
            @selected_var = nil
          end

          # --- 2. 下部: プロパティシート (Table) ---
          sheet_y = top_y + list_h + 8.0
          unless @selected_object
            Window.draw_rect(0.0, sheet_y, w, prop_h, color: COL_BG_SHEET, radius: 4.0, border_width: 1.0, border_color: COL_BORDER)
            Window.draw_text(8.0, sheet_y + 8.0, "Select a sprite above to inspect", size: 12, color: COL_TXT_HDR)
            return
          end

          obj = @selected_object
          hex_id = obj.object_id.to_s(16)
          short_id = hex_id.length > 6 ? hex_id[-6..-1] : hex_id
          title_text = "#{obj.class} [0x#{short_id}]"

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

          prop_cols = [["Property", 110], "Value"]
          sel_prop_idx = props.find_index { |p| p[0] == @selected_var }
          new_prop_idx = GUI.table(
            title_text,
            prop_cols, props, sel_prop_idx,
            x: 0.0, y: sheet_y, w: w, h: prop_h, item_height: 18.0, id: "prop_tbl"
          )
          if new_prop_idx && props[new_prop_idx]
            @selected_var = props[new_prop_idx][0]
          end
        end

        # Stats タブ (高密度コンパクト表示 & 15フレーム間引き更新で自己アロケーション激減)
        def render_stats_dense(w, h, top_y)
          @stats_cache_frame += 1
          if @cached_stat_lines.empty? || (@stats_cache_frame % 15 == 0)
            stat = GC.stat
            cur_alloc = stat[:total_allocated_objects]
            diff_alloc = @prev_alloc_count ? ((cur_alloc - @prev_alloc_count) / 15.0).round : 0
            @prev_alloc_count = cur_alloc

            @cached_stat_lines = [
              ["FPS", "#{Window.fps.round(1)}  (#{(Window.delta_time * 1000.0).round(2)} ms)"],
              ["Alloc / frame", "#{diff_alloc} objs/f"],
              ["Total Allocated", "#{cur_alloc} objs"],
              ["Minor GC (高速)", "#{stat[:minor_gc_count]} 回"],
              ["Major GC (全停止)", "#{stat[:major_gc_count]} 回"],
              ["Live Heap Slots", "#{stat[:heap_live_slots]} slots"],
              ["Window Size", "#{Window.width} x #{Window.height}"],
              ["Draw Target", Backend.current_target ? "FBO Texture" : "BackBuffer"]
            ]
          end

          tbl_h = [h - 40.0, 60.0].max
          GUI.table(
            "Runtime Statistics",
            [["Metric", 140], "Value"],
            @cached_stat_lines, nil,
            x: 0.0, y: top_y, w: w, h: tbl_h, item_height: 20.0, id: "stat_tbl"
          )

          # GC 実行ボタン (コンパクト)
          GUI.cursor(10.0, top_y + tbl_h + 8.0)
          if GUI.button("Run Full GC (rb_gc)", w: w - 20.0, h: 26.0)
            GC.start
            @cached_stat_lines.clear
          end
        end

        # Globals タブ (高密度コンパクト表示)
        def render_globals_dense(w, h, top_y)
          global_rows = [
            ["Program ($0)", File.basename($0.to_s)],
            ["Ruby Version", RUBY_VERSION],
            ["Engine", defined?(RUBY_ENGINE) ? RUBY_ENGINE : "CRuby"],
            ["Dev Mode", Dev.enabled ? "Active (Hot-reload)" : "Disabled"]
          ]
          GUI.table(
            "System Environment",
            [["Property", 140], "Value"],
            global_rows, nil,
            x: 0.0, y: top_y, w: w, h: h, item_height: 20.0, id: "sys_tbl"
          )
        end
      end
    end
  end
end

Zenoo::Dev::Inspector.init

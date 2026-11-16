# frozen_string_literal: true

# ==============================================================================
# Zenoo::Dev::Inspector - Smalltalk風 高密度ライブ・オブジェクトインスペクタ
# ※ CRuby 実行時専用。F12 キーで開閉。UI::Stage 分離構成。
# ==============================================================================

module Zenoo
  module Dev
    class Inspector
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

          @stage = nil
          @sprites_cache = []
          @cache_frame = 0
          @props_buffer = []
          @stats_cache_frame = 0
          @cached_stat_lines = []
          @prev_alloc_count = nil
        end

        def toggle
          @visible = !@visible
          if @visible
            ensure_ui
            refresh_active_tab(force: true)
          end
        end

        def update
          toggle if Input.key_push?(:f12)
        end

        def capturing_pointer?
          @visible && @stage ? @stage.capturing_pointer? : false
        end

        def capturing_keyboard?
          @visible && @stage ? !@stage.focused_widget.nil? : false
        end

        # インスペクタ UI の更新（ゲームブロックより前に独立 Stage で実行）
        def update_gui
          return unless @visible
          ensure_ui
          refresh_active_tab(force: false)
          @stage.update
        end

        # インスペクタ UI の描画（ゲームスナップショット取得後に描画）
        def draw_gui
          return unless @visible && @stage
          @stage.draw
        end

        # コライダーの強制可視化オーバーレイ描画
        def draw_colliders
          return unless @show_colliders

          ObjectSpace.each_object(Zenoo::Sprite) do |sprite|
            next if @stage && sprite.is_a?(UI::Widget) && sprite.stage.equal?(@stage)
            col = sprite.collider
            next unless col

            is_selected = (sprite == @selected_object)
            border_col = is_selected ? COL_COL_SEL_BD : COL_COL_NORM_BD
            bg_col = is_selected ? COL_COL_SEL_BG : COL_COL_NORM_BG

            case col.shape_type
            when Zenoo::Collision::TYPE_CIRCLE
              cx = col.center_x
              cy = col.center_y
              if col.is_true_circle
                rx = ry = col.effective_radius
              else
                rx = col.radius_x * col.scale_x.abs
                ry = col.radius_y * col.scale_y.abs
              end
              Window.draw_circle(cx, cy, rx, ry, angle: col.angle, color: bg_col, border_width: 1.5, border_color: border_col)
            when Zenoo::Collision::TYPE_RECT
              if col.is_rounded
                cx = col.center_x
                cy = col.center_y
                w = col.width * col.scale_x.abs
                h = col.height * col.scale_y.abs
                Window.draw_rect(
                  cx - w * 0.5, cy - h * 0.5, w, h,
                  angle: col.angle,
                  pivot: :center,
                  color: bg_col,
                  border_width: 1.5,
                  border_color: border_col,
                  radius: col.radius
                )
              elsif (verts = col.world_vertices)
                draw_polygon_outline(verts, bg_col, border_col)
              end
            when Zenoo::Collision::TYPE_POLYGON
              if (verts = col.world_vertices)
                draw_polygon_outline(verts, bg_col, border_col)
              end
            when Zenoo::Collision::TYPE_POINT
              Window.draw_circle(col.center_x, col.center_y, 3.0, color: border_col)
            end
          end
        end

        def draw_polygon_outline(verts, bg_col, border_col)
          len = verts.length
          return if len < 3

          p0 = verts[0]
          i = 1
          while i < len - 1
            p1 = verts[i]
            p2 = verts[i + 1]
            Window.draw_triangle(p0[0], p0[1], p1[0], p1[1], p2[0], p2[1], color: bg_col)
            i += 1
          end

          i = 0
          while i < len
            a = verts[i]
            b = verts[(i + 1) % len]
            Window.draw_line(a[0], a[1], b[0], b[1], color: border_col, width: 1.5)
            i += 1
          end
        end

        private

        def ensure_ui
          return if @stage

          @stage = UI::Stage.new(theme: UI::Theme.new(:compact, padding: 6.0, gap: 4.0, font_size: 13))
          @win = @stage.window("Inspector (F12)", 20.0, 20.0, width: 360.0, height: 540.0,
                               resizable: true, min_width: 280.0, min_height: 300.0)

          @win.tabs(["Sprites", "Stats", "Globals"], @tab_index) do |idx, _|
            switch_tab(idx)
          end

          @win.hbox(padding: 0, gap: 8, height: 22, align: :center) do |row|
            @chk_colliders = row.checkbox("Colliders", @show_colliders, width: 96) { |v| @show_colliders = v }
            @chk_pause     = row.checkbox("Pause", @pause_game, width: 76) do |v|
              @pause_game = v
              @btn_step.visible = v
            end
            @btn_step = row.button("Step", width: 52, height: 22, visible: @pause_game) { Zenoo::Dev.step_frame! }
          end

          @tab_panels = []
          @tab_panels << @win.panel(flex: 1, visible: @tab_index == 0, bg_color: [20, 24, 34, 180], border_color: [50, 60, 80, 140]) do |p0|
            @sprite_table = p0.table([["Type", 112], ["X", 54], ["Y", 54], "Angle"], [], nil,
                                     height: 155, item_height: 18, label: "Active Sprites (0)") do |idx, _row|
              if idx && @sprites_cache[idx]
                @selected_object = @sprites_cache[idx]
                @selected_var = nil
                refresh_props_table
              end
            end
            @prop_table = p0.table([["Property", 108], "Value"], [], nil,
                                   flex: 1, item_height: 18, label: "Select a sprite above to inspect") do |idx, row|
              @selected_var = row[0] if idx && row
            end
          end

          @tab_panels << @win.panel(flex: 1, visible: @tab_index == 1, bg_color: [20, 24, 34, 180], border_color: [50, 60, 80, 140]) do |p1|
            @stat_table = p1.table([["Metric", 135], "Value"], [], nil,
                                   flex: 1, item_height: 20, selectable: false, label: "Runtime Statistics")
            p1.button("Run Full GC (rb_gc)") do
              GC.start
              refresh_stats_table(force: true)
            end
          end

          @tab_panels << @win.panel(flex: 1, visible: @tab_index == 2, bg_color: [20, 24, 34, 180], border_color: [50, 60, 80, 140]) do |p2|
            @sys_table = p2.table([["Property", 135], "Value"], [], nil,
                                  flex: 1, item_height: 20, selectable: false, label: "System Environment")
          end
        end

        def switch_tab(idx)
          @tab_index = idx
          i = 0
          while i < @tab_panels.length
            @tab_panels[i].visible = (i == idx)
            i += 1
          end
          refresh_active_tab(force: true)
        end

        def refresh_active_tab(force: false)
          @chk_colliders.checked = @show_colliders
          @chk_pause.checked = @pause_game
          @btn_step.visible = @pause_game

          case @tab_index
          when 0
            refresh_sprites_table(force: force)
          when 1
            refresh_stats_table(force: force)
          when 2
            refresh_globals_table if force
          end
        end

        def active_sprites(force: false)
          @cache_frame += 1
          if force || @sprites_cache.empty? || (@cache_frame % 10 == 0)
            @sprites_cache.clear
            ObjectSpace.each_object(Zenoo::Sprite) do |s|
              next if @stage && s.is_a?(UI::Widget) && s.stage.equal?(@stage)
              @sprites_cache << s
            end
          end
          @sprites_cache
        end

        def refresh_sprites_table(force: false)
          return unless force || (@cache_frame % 10 == 0) || @sprites_cache.empty?
          sprites = active_sprites(force: force)
          rows = []
          sel_idx = nil
          i = 0
          while i < sprites.length
            s = sprites[i]
            sel_idx = i if s.equal?(@selected_object)
            rows << [s.class.name || "Sprite", s.x.round(1), s.y.round(1), s.angle.round(1)]
            i += 1
          end
          @sprite_table.label = "Active Sprites (#{sprites.length})"
          @sprite_table.rows = rows
          @sprite_table.selected_index = sel_idx
          refresh_props_table
        end

        def refresh_props_table
          obj = @selected_object
          unless obj
            @prop_table.label = "Select a sprite above to inspect"
            @prop_table.rows = []
            @prop_table.selected_index = nil
            return
          end

          hex_id = obj.object_id.to_s(16)
          short_id = hex_id.length > 6 ? hex_id[-6..-1] : hex_id
          @prop_table.label = "#{obj.class} [0x#{short_id}]"

          props = @props_buffer
          props.clear
          props << ["x", obj.x.round(2)]
          props << ["y", obj.y.round(2)]
          props << ["angle", obj.angle.round(2)]
          props << ["scale_x", obj.scale_x.round(2)]
          props << ["scale_y", obj.scale_y.round(2)]
          props << ["alpha", obj.alpha.round(2)]

          sel_prop_idx = nil
          obj.instance_variables.each do |ivar|
            next if [:@x, :@y, :@angle, :@scale_x, :@scale_y, :@alpha].include?(ivar)
            name = ivar.to_s
            sel_prop_idx = props.length if name == @selected_var
            props << [name, obj.instance_variable_get(ivar)]
          end

          @prop_table.rows = props
          @prop_table.selected_index = sel_prop_idx
        end

        def refresh_stats_table(force: false)
          @stats_cache_frame += 1
          return unless force || @cached_stat_lines.empty? || (@stats_cache_frame % 15 == 0)

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
          @stat_table.rows = @cached_stat_lines
        end

        def refresh_globals_table
          @sys_table.rows = [
            ["Program ($0)", File.basename($0.to_s)],
            ["Ruby Version", RUBY_VERSION],
            ["Engine", RUBY_ENGINE],
            ["Dev Mode", Dev.enabled ? "Active (Hot-reload)" : "Disabled"]
          ]
        end
      end
    end
  end
end

Zenoo::Dev::Inspector.init

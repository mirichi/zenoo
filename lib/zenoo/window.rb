module Zenoo
  module BlendMode
    ALPHA    = 0
    ADD      = 1
    MULTIPLY = 2
    NONE     = 3
  end

  module Window
    BLEND_MAP = {
      alpha: BlendMode::ALPHA,
      add: BlendMode::ADD,
      additive: BlendMode::ADD,
      multiply: BlendMode::MULTIPLY,
      none: BlendMode::NONE
    }.freeze

    def self.normalize_blend_mode(mode)
      return BlendMode::ALPHA if mode.nil?
      return BLEND_MAP[mode] if BLEND_MAP.key?(mode)
      mode.to_i
    end

    COLOR_MAP = {
      white:   [1.0, 1.0, 1.0, 1.0],
      black:   [0.0, 0.0, 0.0, 1.0],
      red:     [1.0, 0.2, 0.2, 1.0],
      green:   [0.2, 1.0, 0.3, 1.0],
      blue:    [0.1, 0.5, 1.0, 1.0],
      cyan:    [0.0, 0.9, 1.0, 1.0],
      magenta: [1.0, 0.2, 0.8, 1.0],
      yellow:  [1.0, 0.9, 0.1, 1.0],
      clear:   [0.0, 0.0, 0.0, 0.0]
    }

    def self.normalize_color(col)
      return [1.0, 1.0, 1.0, 1.0] if col.nil?
      return COLOR_MAP[col] if COLOR_MAP.key?(col)

      if col.is_a?(Color)
        col.to_f4
      elsif col.is_a?(Array)
        r = 0.0
        g = 0.0
        b = 0.0
        a = 255.0
        col.each_with_index do |v, i|
          vf = v.to_f
          r = vf if i == 0
          g = vf if i == 1
          b = vf if i == 2
          a = vf if i == 3
        end
        [r / 255.0, g / 255.0, b / 255.0, a / 255.0]
      elsif col.is_a?(String)
        Color.hex(col).to_f4
      elsif col.is_a?(Integer)
        r = ((col >> 24) & 0xFF) / 255.0
        g = ((col >> 16) & 0xFF) / 255.0
        b = ((col >> 8) & 0xFF) / 255.0
        a = (col & 0xFF) / 255.0
        [r, g, b, a]
      else
        [1.0, 1.0, 1.0, 1.0]
      end
    end

    def self.color_to_uint32(col)
      return col.to_i if col.is_a?(Color)

      floats = normalize_color(col)
      rf = 0.0
      gf = 0.0
      bf = 0.0
      af = 1.0
      floats.each_with_index do |v, i|
        vf = v.to_f
        rf = vf if i == 0
        gf = vf if i == 1
        bf = vf if i == 2
        af = vf if i == 3
      end
      r = (rf * 255).to_i & 0xFF
      g = (gf * 255).to_i & 0xFF
      b = (bf * 255).to_i & 0xFF
      a = (af * 255).to_i & 0xFF
      r_part = r >= 128 ? ((r - 256) * 16777216) : (r << 24)
      r_part | (g << 16) | (b << 8) | a
    end

    class DrawCommand
      attr_accessor :target, :z, :order, :topology, :layout, :divisors, :base_vertex_count, :data, :count, :image, :shader, :uniforms, :blend

      def initialize
        @target = nil
        @z = 0.0
        @order = 0
        @topology = 0
        @layout = ""
        @divisors = ""
        @base_vertex_count = 0
        @data = nil
        @count = 0
        @image = nil
        @shader = nil
        @uniforms = nil
        @blend = 0
      end

      def set(target, z, order, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms = nil, blend = 0)
        @target = target
        @z = z.to_f
        @order = order
        @topology = topology
        @layout = layout
        @divisors = divisors
        @base_vertex_count = base_vertex_count
        @data = data
        @count = count
        @image = image
        @shader = shader
        @uniforms = uniforms
        @blend = blend.to_i
      end
    end

    @command_pool = []
    @queue_count = 0
    @needs_z_sort = false
    @bg_color = (18 << 24) | (20 << 16) | (30 << 8) | 255
    @current_target = nil
    @active_gl_target = nil
    @pending_images = []
    @main_loop_block = nil
    @step_proc = nil

    def self.current_target
      @current_target
    end

    def self.active_gl_target
      @active_gl_target
    end

    def self.active_gl_target=(target)
      @active_gl_target = target
    end

    def self.register_pending_image(img)
      @pending_images << img unless @pending_images.include?(img)
    end

    def self.flush_pending_images
      return if @pending_images.empty?

      images = @pending_images.dup
      @pending_images.clear
      images.each do |img|
        img.flush_draw_queue if img.respond_to?(:flush_draw_queue)
      end
    end

    def self.with_target(target)
      old_target = @current_target
      @current_target = target
      yield
    ensure
      @current_target = old_target
    end

    def self.enqueue_draw(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms = nil, blend = 0)
      if @current_target
        @current_target.enqueue_draw(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms, blend)
        return
      end

      cmd = nil
      if @queue_count < @command_pool.length
        cmd = @command_pool[@queue_count]
      else
        cmd = DrawCommand.new
        @command_pool.push(cmd)
      end
      zf = z.to_f
      @needs_z_sort = true if zf != 0.0
      cmd.set(nil, zf, @queue_count, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms, blend)
      @queue_count += 1
    end

    # 安定挿入ソート (画面キュー用: 奥から手前へ昇順描画)
    def self.sort_draw_queue
      return unless @needs_z_sort
      return if @queue_count <= 1

      i = 1
      while i < @queue_count
        target_cmd = @command_pool[i]
        tz = target_cmd.z
        j = i - 1
        while j >= 0
          prev_cmd = @command_pool[j]
          break if prev_cmd.z <= tz
          @command_pool[j + 1] = prev_cmd
          j -= 1
        end
        @command_pool[j + 1] = target_cmd
        i += 1
      end
    end

    def self.apply_uniforms(shader, uniforms)
      return unless uniforms && shader

      uniforms.each do |k, v|
        case v
        when Integer
          shader.set_int(k.to_s, v)
        when Float
          shader.set_float(k.to_s, v)
        when Array
          case v.length
          when 2 then shader.set_vec2(k.to_s, v[0].to_f, v[1].to_f)
          when 3 then shader.set_vec3(k.to_s, v[0].to_f, v[1].to_f, v[2].to_f)
          when 4 then shader.set_vec4(k.to_s, v[0].to_f, v[1].to_f, v[2].to_f, v[3].to_f)
          end
        end
      end
    end

    def self.execute_commands(pool, count)
      return if count == 0

      i = 0
      while i < count
        cmd = pool[i]

        # 0. 描画元テクスチャに未消化の描画キューがあれば先にフラッシュして焼き込む (オンデマンド描画)
        if cmd.image && cmd.image.respond_to?(:has_pending_draws?) && cmd.image.has_pending_draws?
          cmd.image.flush_draw_queue
        end

        cur_topology = cmd.topology
        cur_layout = cmd.layout
        cur_divisors = cmd.divisors
        cur_base_vertex_count = cmd.base_vertex_count
        cur_data = cmd.data
        cur_count = cmd.count
        cur_image = cmd.image
        cur_shader = cmd.shader
        cur_uniforms = cmd.uniforms
        cur_blend = cmd.blend

        # ドローコールのまとめ（バッチング）
        can_batch = cur_base_vertex_count > 0 ||
                    cur_topology == Topology::TRIANGLES ||
                    cur_topology == Topology::LINES ||
                    cur_topology == Topology::POINTS

        next_idx = i + 1
        if can_batch
          while next_idx < count
            ncmd = pool[next_idx]
            if ncmd.image && ncmd.image.respond_to?(:has_pending_draws?) && ncmd.image.has_pending_draws?
              ncmd.image.flush_draw_queue
            end

            if ncmd.image == cur_image &&
               ncmd.shader == cur_shader &&
               ncmd.topology == cur_topology &&
               ncmd.uniforms == cur_uniforms &&
               ncmd.blend == cur_blend
              cur_data = cur_data + ncmd.data
              cur_count += ncmd.count
              ncmd.data = nil
              ncmd.image = nil
              ncmd.shader = nil
              ncmd.target = nil
              ncmd.uniforms = nil
              next_idx += 1
            else
              break
            end
          end
        end

        # ブレンドモードの適用
        Native::Renderer.set_blend_mode(cur_blend)

        # Uniform パラメータの適用
        apply_uniforms(cur_shader, cur_uniforms) if cur_uniforms

        # GPU への一括描画送信
        Native::Renderer.draw_buffer(
          cur_topology,
          cur_layout,
          cur_divisors,
          cur_base_vertex_count,
          cur_data,
          cur_count,
          cur_image,
          cur_shader
        )

        cmd.data = nil
        cmd.image = nil
        cmd.shader = nil
        cmd.target = nil
        cmd.uniforms = nil

        i = next_idx
      end
    end

    def self.flush_draw_queue
      if @queue_count > 0
        sort_draw_queue
        execute_commands(@command_pool, @queue_count)
        @queue_count = 0
        @needs_z_sort = false
      end

      # 画面で使われずに残った Image キューがあればフレーム末尾で一括フラッシュ
      flush_pending_images

      Native::Renderer.set_blend_mode(BlendMode::ALPHA)
    end

    # DXRuby風メインループ
    def self.loop(width = 1280, height = 720, title = "Zenoo", fullscreen: false, vsync: false, &block)
      Native::Window.init(width, height, title, fullscreen)
      Native::Window.vsync = (vsync ? 1 : 0)
      Native::Window.target_fps = 60

      @main_loop_block = block

      if Native::Window.wasm?
        @step_proc = proc { __step_frame }
        Zenoo::Native::Window.start_wasm_loop(@step_proc)
      else
        while Native::Window.update
          __step_frame
        end
      end
    ensure
      Native::Window.shutdown unless Native::Window.wasm?
    end

    def self.__update_step
      Zenoo::GUI.begin_frame if defined?(Zenoo::GUI)
      @main_loop_block.call if @main_loop_block
      Zenoo::GUI.end_frame if defined?(Zenoo::GUI)
    end

    def self.__draw_step
      Native::Window.clear(@bg_color)
      flush_draw_queue
    end

    def self.__step_frame
      __update_step
      __draw_step
    end

    def self.time
      Native::Window.time
    end

    def self.clear(color)
      @bg_color = color_to_uint32(color)
      Native::Window.clear(@bg_color)
    end

    def self.width
      Native::Window.size_w
    end

    def self.height
      Native::Window.size_h
    end

    def self.size
      [Native::Window.size_w, Native::Window.size_h]
    end

    def self.delta_time
      Native::Window.delta_time
    end

    def self.fps
      dt = delta_time
      if dt > 0.001 && dt < 1.0
        1.0 / dt
      else
        60.0
      end
    end

    def self.vsync=(val)
      Native::Window.vsync = (val ? 1 : 0)
    end

    @current_shader = nil
    @card_shader = nil
    @default_sprite_shader = nil
    @flat_primitive_shader = nil
    @gradient_primitive_shader = nil

    def self.default_sprite_shader
      @default_sprite_shader ||= Shader.new(Shaders::DEFAULT_SPRITE_VERTEX, Shaders::DEFAULT_SPRITE_FRAGMENT)
    end

    def self.default_quad_shader
      default_sprite_shader
    end

    def self.flat_primitive_shader
      @flat_primitive_shader ||= Shader.new(Shaders::FLAT_PRIMITIVE_VERTEX, Shaders::FLAT_PRIMITIVE_FRAGMENT)
    end

    def self.gradient_primitive_shader
      @gradient_primitive_shader ||= Shader.new(Shaders::GRADIENT_PRIMITIVE_VERTEX, Shaders::GRADIENT_PRIMITIVE_FRAGMENT)
    end

    def self.default_primitive_shader
      flat_primitive_shader
    end

    def self.card_shader
      @card_shader ||= Shader.new(Shaders::CARD_VERTEX, Shaders::CARD_FRAGMENT)
    end

    # ブロック内でのシェーダー適用スコープ (RAII / ensure で確実に元の状態に戻る)
    # ※ カスタムシェーダーは Image 描画 (draw_image) にのみ適用されます。
    def self.with_shader(shader)
      old_shader = @current_shader
      @current_shader = shader
      yield
    ensure
      @current_shader = old_shader
    end

    # ----------------------------------------------------
    # 描画 API 
    # ----------------------------------------------------
    def self.draw_card(x, y, w, h,
                       radius: 0.0,
                       color: :white,
                       border_width: 0.0,
                       border_color: :cyan,
                       shadow_blur: 0.0,
                       shadow_color: [0, 0, 0, 180],
                       image: nil,
                       z: 0.0)
      c_color = normalize_color(color)
      b_width = border_width.to_f
      b_color = (b_width > 0.0) ? normalize_color(border_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_color = (s_blur > 0.0) ? normalize_color(shadow_color) : [0.0, 0.0, 0.0, 0.0]

      mode = image ? 1.0 : 0.0
      data = [
        x.to_f, y.to_f, w.to_f, h.to_f,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        radius.to_f, b_width, s_blur, mode,
        b_color[0].to_f, b_color[1].to_f, b_color[2].to_f, b_color[3].to_f,
        s_color[0].to_f, s_color[1].to_f, s_color[2].to_f, s_color[3].to_f,
        0.0, 0.0, 1.0, 1.0
      ].pack("f*")

      enqueue_draw(
        z,
        Topology::TRIANGLE_STRIP,
        Layout::CARD_INSTANCED,
        Divisor::CARD_INSTANCED,
        4,
        data,
        1,
        image,
        card_shader
      )
    end

    def self.draw_rect(x, y, w, h, color = :white, z: 0.0, **opts)
      draw_card(x, y, w, h, color: color, z: z, **opts)
    end

    def self.draw_rounded_rect(x, y, w, h, radius, color = :white, z: 0.0, **opts)
      draw_card(x, y, w, h, radius: radius, color: color, z: z, **opts)
    end

    def self.draw_image(x, y, image,
                        color_or_opt = :white,
                        color: nil,
                        angle: 0.0,
                        scale: nil,
                        scale_x: 1.0,
                        scale_y: 1.0,
                        center_x: 0.5,
                        center_y: 0.5,
                        pivot: nil,
                        offset_mode: :top_left,
                        alpha: 255,
                        blend: :alpha,
                        shader: nil,
                        z: 0.0)
      return unless image
      effective_shader = shader || @current_shader || default_sprite_shader

      # 第4引数 color_or_opt が指定され、かつキーワード color: がない場合
      actual_color = color || color_or_opt || :white
      c_color = normalize_color(actual_color)

      # alpha の適用 (0..255)
      if alpha
        af = alpha.to_f / 255.0
        af = 0.0 if af < 0.0
        af = 1.0 if af > 1.0
        c_color = [c_color[0], c_color[1], c_color[2], c_color[3] * af]
      end

      # スケール
      sx = (scale ? scale.to_f : scale_x.to_f)
      sy = (scale ? scale.to_f : scale_y.to_f)

      # ピボット (center_x, center_y, または pivot: :center, :top_left, [px, py])
      cx = center_x.to_f
      cy = center_y.to_f
      if pivot == :center
        cx = 0.5
        cy = 0.5
      elsif pivot == :top_left
        cx = 0.0
        cy = 0.0
      elsif pivot.is_a?(Array) && pivot.length >= 2
        cx = pivot[0].to_f
        cy = pivot[1].to_f
      end

      # 角度（度数法からラジアンへ変換）
      rad = angle.to_f * (Math::PI / 180.0)

      # offset_mode: 0.0 (:top_left), 1.0 (:center)
      off_mode = (offset_mode == :center) ? 1.0 : 0.0

      # blend mode
      b_mode = normalize_blend_mode(blend)

      data = [
        x.to_f, y.to_f, image.width.to_f, image.height.to_f,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        0.0, 0.0, 1.0, 1.0,
        rad, sx, sy, off_mode,
        cx, cy, 0.0, 0.0
      ].pack("f*")

      enqueue_draw(
        z,
        Topology::TRIANGLE_STRIP,
        Layout::SPRITE_INSTANCED,
        Divisor::SPRITE_INSTANCED,
        4,
        data,
        1,
        image,
        effective_shader,
        nil,
        b_mode
      )
    end


    def self.draw_triangle(x1, y1, x2, y2, x3, y3, color = :white, z: 0.0)
      if color.is_a?(Array) && color.length == 3 && (color[0].is_a?(Color) || color[0].is_a?(Symbol) || color[0].is_a?(Array))
        # 頂点ごとの色指定 [c1, c2, c3]
        c1 = normalize_color(color[0])
        c2 = normalize_color(color[1])
        c3 = normalize_color(color[2])
        data = [
          x1.to_f, y1.to_f, c1[0].to_f, c1[1].to_f, c1[2].to_f, c1[3].to_f,
          x2.to_f, y2.to_f, c2[0].to_f, c2[1].to_f, c2[2].to_f, c2[3].to_f,
          x3.to_f, y3.to_f, c3[0].to_f, c3[1].to_f, c3[2].to_f, c3[3].to_f
        ].pack("f*")
      else
        c = normalize_color(color)
        cr = c[0].to_f; cg = c[1].to_f; cb = c[2].to_f; ca = c[3].to_f
        data = [
          x1.to_f, y1.to_f, cr, cg, cb, ca,
          x2.to_f, y2.to_f, cr, cg, cb, ca,
          x3.to_f, y3.to_f, cr, cg, cb, ca
        ].pack("f*")
      end

      enqueue_draw(
        z,
        Topology::TRIANGLES,
        Layout::POS2_COLOR4,
        Divisor::POS2_COLOR4,
        0,
        data,
        3,
        nil,
        flat_primitive_shader
      )
    end

    def self.draw_line(x1, y1, x2, y2, color = :white, z: 0.0)
      if color.is_a?(Array) && color.length == 2 && (color[0].is_a?(Color) || color[0].is_a?(Symbol) || color[0].is_a?(Array))
        # 始点・終点の色指定 [c1, c2]
        c1 = normalize_color(color[0])
        c2 = normalize_color(color[1])
        data = [
          x1.to_f, y1.to_f, c1[0].to_f, c1[1].to_f, c1[2].to_f, c1[3].to_f,
          x2.to_f, y2.to_f, c2[0].to_f, c2[1].to_f, c2[2].to_f, c2[3].to_f
        ].pack("f*")
      else
        c = normalize_color(color)
        cr = c[0].to_f; cg = c[1].to_f; cb = c[2].to_f; ca = c[3].to_f
        data = [
          x1.to_f, y1.to_f, cr, cg, cb, ca,
          x2.to_f, y2.to_f, cr, cg, cb, ca
        ].pack("f*")
      end

      enqueue_draw(
        z,
        Topology::LINES,
        Layout::LINE,
        Divisor::LINE,
        0,
        data,
        2,
        nil,
        flat_primitive_shader
      )
    end

    @sdf_font_shader = nil

    def self.sdf_font_shader
      @sdf_font_shader ||= Shader.new(Shaders::FONT_SDF_VERTEX, Shaders::FONT_SDF_FRAGMENT)
    end

    class CharContext
      attr_accessor :char, :index, :line_index, :x, :y, :w, :h, :color, :scale, :visible
      attr_accessor :outline_width, :outline_color, :weight

      def reset(char, index, gx, gy, gw, gh, default_color, def_out_w, def_out_c, def_weight = 0.0)
        @char = char
        @index = index
        @line_index = 0
        @x = gx
        @y = gy
        @w = gw
        @h = gh
        @color = default_color
        @scale = 1.0
        @visible = true
        @outline_width = def_out_w
        @outline_color = def_out_c
        @weight = def_weight
      end
    end

    @char_ctx = CharContext.new

    # ----------------------------------------------------
    # 高品質 SDF テキスト描画 API (改行なし・文字列直接描画)
    # ----------------------------------------------------
    def self.draw_text(x, y, text,
                       font: nil,
                       size: 24,
                       color: :white,
                       weight: 0.0,
                       outline_width: 0.0,
                       outline_color: :black,
                       shadow_blur: 0.0,
                       shadow_color: [0, 0, 0, 180],
                       shadow_dx: 0.0,
                       shadow_dy: 0.0,
                       sdf: nil,
                       z: 0.0,
                       &block)
      return if text.nil?

      target_font = font || Font.default
      return unless target_font

      atlas = Font.atlas_image
      return unless atlas

      f_size = size.to_f
      f_size = 24.0 if f_size <= 0.0

      c_color = normalize_color(color)

      outline_w = outline_width.to_f
      outline_c = (outline_w > 0.0) ? normalize_color(outline_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_dx = shadow_dx.to_f
      s_dy = shadow_dy.to_f
      s_c = (s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? normalize_color(shadow_color) : [0.0, 0.0, 0.0, 0.0]

      # sdf オプションの解決:
      # - sdf: true  -> 強制 SDF
      # - sdf: false -> 強制 ビットマップ (大文字でも直接ラスタライズ)
      # - sdf: nil   -> 自動判定 (エフェクトがあれば SDF、なければサイズ判定)
      effective_sdf = if sdf.nil?
                        (outline_w > 0.0 || s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? true : nil
                      else
                        sdf ? true : false
                      end

      # 画面上ピクセルとアトラスピクセルのスケール比補正 (アトラス基準サイズはFont::SDF_BASE_SIZE)
      scale_ratio = Font::SDF_BASE_SIZE / f_size
      s_atlas_dx = s_dx * scale_ratio
      s_atlas_dy = s_dy * scale_ratio
      s_atlas_blur = s_blur * scale_ratio
      s_atlas_outline_w = outline_w * scale_ratio
      s_weight = weight.to_f
      s_atlas_weight = s_weight * scale_ratio

      p0 = [s_atlas_outline_w, s_atlas_blur, s_atlas_dx, s_atlas_dy]
      p1 = outline_c
      p2 = s_c
      p3 = [s_atlas_weight, 0.0, 0.0, 0.0]
      shader = sdf_font_shader

      metrics = target_font.metrics(f_size)
      ascent = metrics[:ascent]

      pen_x = x.to_f
      pen_y = y.to_f + ascent

      str = text.to_s
      chars = str.chars
      len = chars.length
      return if len == 0

      batch = []
      glyph_count = 0

      if block_given?
        ctx = @char_ctx
        i = 0
        while i < len
          ch = chars[i]
          glyph_data = target_font.get_glyph(ch, f_size, effective_sdf)
          adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

          if glyph_data && glyph_data[0] # visible == true
            _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv, is_bitmap = glyph_data
            is_bmp = (is_bitmap == true || is_bitmap == 1) ? 1.0 : 0.0
            if is_bmp > 0.5 || f_size <= 20.0
              gx = (pen_x + x0).round
              gy = (pen_y + y0).round
            else
              gx = pen_x + x0
              gy = pen_y + y0
            end
            gw = x1 - x0
            gh = y1 - y0
            uv = [u0, v0, u1 - u0, v1 - v0]
            is_bmp = (is_bitmap == true || is_bitmap == 1) ? 1.0 : 0.0

            ctx.reset(ch, i, gx, gy, gw, gh, c_color, outline_w, outline_c, s_weight)
            yield(ctx)

            if ctx.visible
              cgx = ctx.x
              cgy = ctx.y
              cgw = ctx.w
              cgh = ctx.h

              if ctx.scale != 1.0
                sc = ctx.scale
                # 中心を基準にスケーリング
                cx = cgx + cgw * 0.5
                cy = cgy + cgh * 0.5
                cgw *= sc
                cgh *= sc
                cgx = cx - cgw * 0.5
                cgy = cy - cgh * 0.5
              end

              cur_color = (ctx.color.equal?(c_color)) ? c_color : normalize_color(ctx.color)
              cur_p0 = (ctx.outline_width == outline_w) ? p0 : [ctx.outline_width * scale_ratio, s_atlas_blur, s_atlas_dx, s_atlas_dy]
              cur_p1 = (ctx.outline_color.equal?(outline_c)) ? outline_c : normalize_color(ctx.outline_color)
              cur_p3 = (ctx.weight == s_weight) ? [s_atlas_weight, is_bmp, 0.0, 0.0] : [ctx.weight * scale_ratio, is_bmp, 0.0, 0.0]

              batch.push(
                cgx.to_f, cgy.to_f, cgw.to_f, cgh.to_f,
                cur_color[0].to_f, cur_color[1].to_f, cur_color[2].to_f, cur_color[3].to_f,
                cur_p0[0].to_f, cur_p0[1].to_f, cur_p0[2].to_f, cur_p0[3].to_f,
                cur_p1[0].to_f, cur_p1[1].to_f, cur_p1[2].to_f, cur_p1[3].to_f,
                p2[0].to_f, p2[1].to_f, p2[2].to_f, p2[3].to_f,
                cur_p3[0].to_f, cur_p3[1].to_f, cur_p3[2].to_f, cur_p3[3].to_f,
                uv[0].to_f, uv[1].to_f, uv[2].to_f, uv[3].to_f
              )
              glyph_count += 1
            end
          end

          pen_x += adv
          i += 1
        end
      else
        i = 0
        while i < len
          ch = chars[i]
          glyph_data = target_font.get_glyph(ch, f_size, effective_sdf)
          adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

          if glyph_data && glyph_data[0] # visible == true
            _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv, is_bitmap = glyph_data
            is_bmp = (is_bitmap == true || is_bitmap == 1) ? 1.0 : 0.0
            if is_bmp > 0.5 || f_size <= 20.0
              gx = (pen_x + x0).round
              gy = (pen_y + y0).round
            else
              gx = pen_x + x0
              gy = pen_y + y0
            end
            gw = x1 - x0
            gh = y1 - y0
            uv = [u0, v0, u1 - u0, v1 - v0]
            cur_p3 = [s_atlas_weight, is_bmp, 0.0, 0.0]

            batch.push(
              gx.to_f, gy.to_f, gw.to_f, gh.to_f,
              c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
              p0[0].to_f, p0[1].to_f, p0[2].to_f, p0[3].to_f,
              p1[0].to_f, p1[1].to_f, p1[2].to_f, p1[3].to_f,
              p2[0].to_f, p2[1].to_f, p2[2].to_f, p2[3].to_f,
              cur_p3[0].to_f, cur_p3[1].to_f, cur_p3[2].to_f, cur_p3[3].to_f,
              uv[0].to_f, uv[1].to_f, uv[2].to_f, uv[3].to_f
            )
            glyph_count += 1
          end

          pen_x += adv
          i += 1
        end
      end

      if glyph_count > 0
        enqueue_draw(
          z,
          Topology::TRIANGLE_STRIP,
          Layout::FONT_INSTANCED,
          Divisor::FONT_INSTANCED,
          4,
          batch.pack("f*"),
          glyph_count,
          atlas,
          shader
        )
      end
    end

    def self.canvas
      @canvas ||= Canvas.new
    end

    def self.draw_path
      c = canvas
      c.begin_path
      yield c
    end
  end
end

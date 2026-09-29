# frozen_string_literal: true

module Zenoo
  module BlendMode
    ALPHA    = 0
    ADD      = 1
    MULTIPLY = 2
    NONE     = 3
  end

  # Zenoo 内部パイプライン・レンダリングバックエンド
  # ユーザー向け API (Window, Image 等) の裏側で描画コマンドのバッチング、
  # Z ソート、FBO レンダーターゲット追跡、オンデマンドフラッシュを統括します。
  module Backend
    # ----------------------------------------------------
    # 描画プリミティブトポロジー (OpenGL GLenum準拠)
    # ----------------------------------------------------
    module Topology
      POINTS         = 0
      LINES          = 1
      LINE_LOOP      = 2
      LINE_STRIP     = 3
      TRIANGLES      = 4
      TRIANGLE_STRIP = 5
      TRIANGLE_FAN   = 6
    end

    # ----------------------------------------------------
    # 動的頂点レイアウト (1バイト属性要素数列)
    # ----------------------------------------------------
    module Layout
      POS2_COLOR4         = "\x02\x04"
      POS2_UV2_COLOR4     = "\x02\x02\x04"
      LINE                = "\x02\x04"
      CARD_INSTANCED      = "\x04\x04\x04\x04\x04\x04"
      QUAD_INSTANCED      = CARD_INSTANCED
      SPRITE_INSTANCED    = "\x04\x04\x04\x04\x04"
      FONT_INSTANCED      = "\x04\x04\x04\x04\x04\x04\x04"
    end

    # ----------------------------------------------------
    # 動的属性 Divisor
    # ----------------------------------------------------
    module Divisor
      DIRECT              = "\x00\x00"
      POS2_COLOR4         = "\x00\x00"
      POS2_UV2_COLOR4     = "\x00\x00\x00"
      LINE                = "\x00\x00"
      CARD_INSTANCED      = "\x01\x01\x01\x01\x01\x01"
      QUAD_INSTANCED      = CARD_INSTANCED
      SPRITE_INSTANCED    = "\x01\x01\x01\x01\x01"
      FONT_INSTANCED      = "\x01\x01\x01\x01\x01\x01\x01"
    end

    # ----------------------------------------------------
    # ブレンドモード
    # ----------------------------------------------------
    BLEND_MAP = {
      alpha:    Zenoo::BlendMode::ALPHA,
      add:      Zenoo::BlendMode::ADD,
      multiply: Zenoo::BlendMode::MULTIPLY,
      none:     Zenoo::BlendMode::NONE
    }.freeze

    def self.normalize_blend_mode(mode)
      return Zenoo::BlendMode::ALPHA if mode.nil?
      return BLEND_MAP[mode] if BLEND_MAP.key?(mode)
      mode.to_i
    end

    # ----------------------------------------------------
    # カラーマップと色変換 (0..255 統一)
    # ----------------------------------------------------
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
    }.freeze

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

    # ----------------------------------------------------
    # 描画コマンド
    # ----------------------------------------------------
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

    # ----------------------------------------------------
    # 描画キュー管理クラス (画面用・各Image用で共通)
    # ----------------------------------------------------
    class DrawQueue
      attr_reader :command_pool, :queue_count

      def initialize(owner = nil)
        @owner = owner # nil なら画面、Image ならその Image
        @command_pool = []
        @queue_count = 0
        @needs_z_sort = false
        @is_flushing = false
      end

      def has_pending_draws?
        @queue_count > 0
      end

      def enqueue(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms = nil, blend = 0)
        cmd = nil
        if @queue_count < @command_pool.length
          cmd = @command_pool[@queue_count]
        else
          cmd = DrawCommand.new
          @command_pool.push(cmd)
        end
        zf = z.to_f
        @needs_z_sort = true if zf != 0.0
        cmd.set(@owner, zf, @queue_count, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms, blend)
        @queue_count += 1
      end

      def sort
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

      def flush
        return if @is_flushing # 再帰 / 自己参照ガード
        return unless has_pending_draws?

        @is_flushing = true
        sort

        if @owner
          # Image (FBO) への描画
          old_target = Backend.active_gl_target
          @owner.set_as_render_target
          Backend.active_gl_target = @owner

          Backend.execute_commands(@command_pool, @queue_count)

          @queue_count = 0
          @needs_z_sort = false
          @is_flushing = false

          # 元のレンダーターゲットを復元
          if old_target
            old_target.set_as_render_target
          else
            Native::Image.reset_render_target
          end
          Backend.active_gl_target = old_target
        else
          # 画面への描画
          Backend.execute_commands(@command_pool, @queue_count)
          @queue_count = 0
          @needs_z_sort = false
          @is_flushing = false
        end
      end
    end

    # ----------------------------------------------------
    # バックエンド状態管理
    # ----------------------------------------------------
    @screen_queue = DrawQueue.new(nil)
    @current_target = nil
    @active_gl_target = nil
    @pending_images = []

    def self.screen_queue
      @screen_queue
    end

    def self.current_target
      @current_target
    end

    def self.active_gl_target
      @active_gl_target
    end

    def self.active_gl_target=(target)
      @active_gl_target = target
    end

    def self.with_target(target)
      old_target = @current_target
      @current_target = target
      yield
    ensure
      @current_target = old_target
    end

    def self.queue_for(image)
      image.__draw_queue ||= DrawQueue.new(image)
    end

    def self.has_pending_draws?(image)
      q = image.__draw_queue
      q && q.has_pending_draws?
    end

    def self.flush_image(image)
      q = image.__draw_queue
      q&.flush
    end

    def self.register_pending_image(img)
      @pending_images << img unless @pending_images.include?(img)
    end

    def self.flush_pending_images
      return if @pending_images.empty?

      images = @pending_images.dup
      @pending_images.clear
      images.each do |img|
        flush_image(img)
      end
    end

    def self.enqueue_draw(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms = nil, blend = 0)
      if @current_target
        queue = queue_for(@current_target)
        queue.enqueue(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms, blend)
        register_pending_image(@current_target)
      else
        @screen_queue.enqueue(z, topology, layout, divisors, base_vertex_count, data, count, image, shader, uniforms, blend)
      end
    end

    def self.flush_screen
      @screen_queue.flush
      flush_pending_images
      Native::Renderer.set_blend_mode(BlendMode::ALPHA)
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

        # 0. 描画元テクスチャに未消化キューがあれば先にフラッシュ (オンデマンド描画)
        if cmd.image && has_pending_draws?(cmd.image)
          flush_image(cmd.image)
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

        can_batch = cur_base_vertex_count > 0 ||
                    cur_topology == Topology::TRIANGLES ||
                    cur_topology == Topology::LINES ||
                    cur_topology == Topology::POINTS

        next_idx = i + 1
        if can_batch
          while next_idx < count
            ncmd = pool[next_idx]
            if ncmd.image && has_pending_draws?(ncmd.image)
              flush_image(ncmd.image)
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

        Native::Renderer.set_blend_mode(cur_blend)
        apply_uniforms(cur_shader, cur_uniforms) if cur_uniforms

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
  end
end

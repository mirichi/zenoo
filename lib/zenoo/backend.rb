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
    # 描画パイプライン定義 (トポロジー・レイアウト・Divisor・頂点数を集約)
    # ----------------------------------------------------
    class Pipeline
      attr_reader :topology, :layout, :divisors, :base_vertex_count, :default_shader

      def initialize(topology, layout, divisors, base_vertex_count, default_shader = nil)
        @topology = topology
        @layout = layout
        @divisors = divisors
        @base_vertex_count = base_vertex_count
        @default_shader = default_shader
      end
    end

    module Pipelines
      CARD      = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::CARD_INSTANCED, Divisor::CARD_INSTANCED, 4)
      SPRITE    = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::SPRITE_INSTANCED, Divisor::SPRITE_INSTANCED, 4)
      FONT      = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::FONT_INSTANCED, Divisor::FONT_INSTANCED, 4)
      TRIANGLES = Pipeline.new(Topology::TRIANGLES, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0)
      LINES     = Pipeline.new(Topology::LINES, Layout::LINE, Divisor::LINE, 0)
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
      attr_accessor :target, :z, :order, :pipeline, :data, :count, :image, :shader, :uniforms, :blend, :clip

      def initialize
        @target = nil
        @z = 0.0
        @order = 0
        @pipeline = nil
        @data = nil
        @count = 0
        @image = nil
        @shader = nil
        @uniforms = nil
        @blend = 0
        @clip = nil
      end

      def set(target, z, order, pipeline, data, count, image = nil, shader = nil, uniforms = nil, blend = 0, clip = nil)
        @target = target
        @z = z.to_f
        @order = order
        @pipeline = pipeline
        @data = data
        @count = count
        @image = image
        @shader = shader
        @uniforms = uniforms
        @blend = blend.to_i
        @clip = clip
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

      def enqueue(pipeline, data, count, image: nil, shader: nil, uniforms: nil, blend: 0, z: 0.0)
        cmd = nil
        if @queue_count < @command_pool.length
          cmd = @command_pool[@queue_count]
        else
          cmd = DrawCommand.new
          @command_pool.push(cmd)
        end
        zf = z.to_f
        @needs_z_sort = true if zf != 0.0
        clip = Backend.current_clip
        cmd.set(@owner, zf, @queue_count, pipeline, data, count, image, shader, uniforms, blend, clip)
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
    @target_images = []
    @target_queues = []
    @clip_stack = []

    def self.current_clip
      @clip_stack.last
    end

    def self.push_clip(rect)
      @clip_stack.push(rect)
    end

    def self.pop_clip
      @clip_stack.pop
    end

    def self.clear_clips
      @clip_stack.clear
    end

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
      idx = @target_images.index(image)
      if idx
        @target_queues[idx]
      else
        q = DrawQueue.new(image)
        @target_images << image
        @target_queues << q
        q
      end
    end

    def self.has_pending_draws?(image)
      idx = @target_images.index(image)
      if idx
        @target_queues[idx].has_pending_draws?
      else
        false
      end
    end

    def self.flush_image(image)
      idx = @target_images.index(image)
      if idx
        @target_queues[idx].flush
      end
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

    def self.enqueue_draw(pipeline, data, count, image: nil, shader: nil, uniforms: nil, blend: 0, z: 0.0)
      if @current_target
        queue = queue_for(@current_target)
        queue.enqueue(pipeline, data, count, image: image, shader: shader, uniforms: uniforms, blend: blend, z: z)
        register_pending_image(@current_target)
      else
        @screen_queue.enqueue(pipeline, data, count, image: image, shader: shader, uniforms: uniforms, blend: blend, z: z)
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

      active_gl_clip = :initial

      i = 0
      while i < count
        cmd = pool[i]

        # 0. 描画元テクスチャに未消化キューがあれば先にフラッシュ (オンデマンド描画)
        if cmd.image && has_pending_draws?(cmd.image)
          flush_image(cmd.image)
        end

        cur_pipeline = cmd.pipeline
        cur_data = cmd.data
        cur_count = cmd.count
        cur_image = cmd.image
        cur_shader = cmd.shader || cur_pipeline.default_shader
        cur_uniforms = cmd.uniforms
        cur_blend = cmd.blend
        cur_clip = cmd.clip

        # シザーテストの適用（変更があった場合のみ切り替え）
        if cur_clip != active_gl_clip
          if cur_clip
            Native::Renderer.set_scissor(cur_clip[0].to_i, cur_clip[1].to_i, cur_clip[2].to_i, cur_clip[3].to_i)
          else
            Native::Renderer.reset_scissor
          end
          active_gl_clip = cur_clip
        end

        can_batch = cur_pipeline.base_vertex_count > 0 ||
                    cur_pipeline.topology == Topology::TRIANGLES ||
                    cur_pipeline.topology == Topology::LINES ||
                    cur_pipeline.topology == Topology::POINTS

        next_idx = i + 1
        if can_batch
          while next_idx < count
            ncmd = pool[next_idx]
            if ncmd.image && has_pending_draws?(ncmd.image)
              flush_image(ncmd.image)
            end

            n_shader = ncmd.shader || ncmd.pipeline.default_shader
            if ncmd.pipeline == cur_pipeline &&
               ncmd.image == cur_image &&
               n_shader == cur_shader &&
               ncmd.uniforms == cur_uniforms &&
               ncmd.blend == cur_blend &&
               ncmd.clip == cur_clip
              cur_data = cur_data + ncmd.data
              cur_count += ncmd.count
              ncmd.data = nil
              ncmd.image = nil
              ncmd.shader = nil
              ncmd.target = nil
              ncmd.pipeline = nil
              ncmd.uniforms = nil
              ncmd.clip = nil
              next_idx += 1
            else
              break
            end
          end
        end

        Native::Renderer.set_blend_mode(cur_blend)
        apply_uniforms(cur_shader, cur_uniforms) if cur_uniforms

        Native::Renderer.draw_buffer(
          cur_pipeline.topology,
          cur_pipeline.layout,
          cur_pipeline.divisors,
          cur_pipeline.base_vertex_count,
          cur_data,
          cur_count,
          cur_image,
          cur_shader
        )

        cmd.data = nil
        cmd.image = nil
        cmd.shader = nil
        cmd.target = nil
        cmd.pipeline = nil
        cmd.uniforms = nil
        cmd.clip = nil

        i = next_idx
      end

      # ループ完了後にシザーをリセット
      Native::Renderer.reset_scissor if active_gl_clip != :initial
    end
  end
end

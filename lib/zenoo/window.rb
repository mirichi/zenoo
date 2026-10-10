module Zenoo
  module Window
    # オフスクリーンFBO描画ターゲットスコープ
    def self.with_target(target, &block)
      old_cam = @camera
      @camera = nil
      Backend.with_target(target, &block)
    ensure
      @camera = old_cam
    end

    def self.current_target
      Backend.current_target
    end

    def self.current_target=(target)
      Backend.current_target = target
    end

    @bg_color = (18 << 24) | (20 << 16) | (30 << 8) | 255
    @main_loop_block = nil
    @step_proc = nil
    @filter = nil
    @filter_uniforms = nil
    @screen_buffer = nil

    # 画面全体ポストプロセスフィルター (Shader オブジェクト、または nil で解除)
    def self.filter
      @filter
    end

    def self.filter=(shader)
      @filter = shader
    end

    # フィルター用 Uniform パラメータ (Hash: { u_time: t, ... })
    def self.filter_uniforms
      @filter_uniforms
    end

    def self.filter_uniforms=(uniforms)
      @filter_uniforms = uniforms
    end

    def self.__ensure_screen_buffer
      w = Native::Window.size_w
      h = Native::Window.size_h
      if @screen_buffer.nil? || @screen_buffer.width != w || @screen_buffer.height != h
        @screen_buffer = Zenoo::Image.new(w, h)
      end
      @screen_buffer
    end

    # DXRuby風メインループ
    def self.loop(width = 1280, height = 720, title = "Zenoo", scale: 1.0, scale_mode: :fit, window_width: nil, window_height: nil, fullscreen: false, vsync: false, &block)
      win_w = (window_width || (width * scale)).to_i
      win_h = (window_height || (height * scale)).to_i
      Native::Window.init(width, height, title, fullscreen, win_w, win_h, scale_mode)
      Native::Window.scale_mode = scale_mode if Native::Window.respond_to?(:scale_mode=)
      Native::Window.vsync = (vsync ? 1 : 0)
      Native::Window.target_fps = 60
      Font.atlas_image if defined?(Font) && Font.respond_to?(:atlas_image)

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
      Zenoo::Tween.__update_step(delta_time) if defined?(Zenoo::Tween)
      Zenoo::GUI.begin_frame if defined?(Zenoo::GUI)
      @main_loop_block.call if @main_loop_block
      Zenoo::GUI.end_frame if defined?(Zenoo::GUI)
      Zenoo::Input.__update_step if defined?(Zenoo::Input)
    end

    def self.__draw_step(active_filter = nil)
      if active_filter && @screen_buffer
        # 1. オフスクリーンバッファへの描画を完了
        Backend.flush_image(@screen_buffer)
        Backend.clear_clips
        @offset_x = 0.0
        @offset_y = 0.0
        Native::Renderer.reset_scissor

        # 2. 描画先を画面（メインフレームバッファ）に戻す
        Backend.current_target = nil
        Native::Image.reset_render_target if defined?(Native::Image) && Native::Image.respond_to?(:reset_render_target)

        # 3. 画面に @screen_buffer を active_filter（Shader）で全画面描画
        draw_image(0, 0, @screen_buffer, shader: active_filter, uniforms: @filter_uniforms)
        Backend.flush_screen
      else
        Backend.flush_screen
        Backend.clear_clips
        @offset_x = 0.0
        @offset_y = 0.0
        Native::Renderer.reset_scissor
      end
    end

    def self.__step_frame
      active_filter = @filter
      if active_filter
        buf = __ensure_screen_buffer
        Backend.current_target = buf
        draw_rect(0.0, 0.0, buf.width, buf.height, color: @bg_color)
        __update_step
        __draw_step(active_filter)
      else
        Backend.current_target = nil
        Native::Image.reset_render_target if defined?(Native::Image) && Native::Image.respond_to?(:reset_render_target)
        Native::Window.clear(@bg_color)
        __update_step
        __draw_step(nil)
      end
    ensure
      Backend.current_target = nil
      Native::Image.reset_render_target if defined?(Native::Image) && Native::Image.respond_to?(:reset_render_target)
    end

    def self.time
      Native::Window.time
    end

    def self.clear(color)
      target = Backend.current_target
      if target
        draw_rect(0.0, 0.0, target.width, target.height, color: color)
      else
        @bg_color = Backend.color_to_uint32(color)
        Native::Window.clear(@bg_color)
      end
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

    def self.scale
      Native::Window.scale
    end

    def self.scale=(val)
      Native::Window.scale = val.to_f
    end

    def self.scale_mode
      Native::Window.scale_mode
    end

    def self.scale_mode=(val)
      Native::Window.scale_mode = val
    end

    def self.window_size
      Native::Window.window_size
    end

    def self.window_size=(size)
      Native::Window.set_window_size(size[0].to_i, size[1].to_i)
    end

    def self.resize(w, h)
      Native::Window.set_window_size(w.to_i, h.to_i)
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

    @offset_x = 0.0
    @offset_y = 0.0
    @camera = nil
    @camera_disabled_stack = []
    @cam_ox = 0.0
    @cam_oy = 0.0
    @cam_zoom = 1.0
    @has_camera = false

    def self.__recalculate_camera_cache
      if @camera && @camera_disabled_stack.empty?
        @has_camera = true
        @cam_zoom = @camera.zoom.to_f
        @cam_ox   = @camera.calc_offset_x.to_f
        @cam_oy   = @camera.calc_offset_y.to_f
      else
        @has_camera = false
        @cam_zoom = 1.0
        @cam_ox   = 0.0
        @cam_oy   = 0.0
      end
    end

    # 2D カメラ設定 (Zenoo::Camera2D)
    # - 引数なし: 現在のカメラを取得
    # - 引数あり (ブロックなし): カメラを設定
    # - ブロックあり: ブロック内のみカメラを適用
    def self.camera(cam = nil, &block)
      if block
        old_cam  = @camera
        old_has  = @has_camera
        old_ox   = @cam_ox
        old_oy   = @cam_oy
        old_zoom = @cam_zoom

        @camera = cam
        __recalculate_camera_cache

        begin
          yield
        ensure
          @camera     = old_cam
          @has_camera = old_has
          @cam_ox     = old_ox
          @cam_oy     = old_oy
          @cam_zoom   = old_zoom
        end
      elsif cam
        @camera = cam
        __recalculate_camera_cache
      else
        @camera
      end
    end

    def self.camera=(cam)
      @camera = cam
      __recalculate_camera_cache
    end

    # カメラを一時的に無効化して UI などを画面ピクセル座標で描画
    def self.without_camera
      @camera_disabled_stack.push(true)
      old_has = @has_camera
      @has_camera = false
      begin
        yield
      ensure
        @camera_disabled_stack.pop
        @has_camera = old_has
      end
    end

    def self.camera_enabled?
      !@camera.nil? && @camera_disabled_stack.empty?
    end

    # 画面座標 -> ワールド座標変換 (マウス位置など)
    def self.to_world(sx, sy)
      if camera_enabled?
        @camera.screen_to_world(sx, sy)
      else
        [sx.to_f, sy.to_f]
      end
    end

    # ワールド座標 -> 画面座標変換
    def self.to_screen(wx, wy)
      if camera_enabled?
        @camera.world_to_screen(wx, wy)
      else
        [wx.to_f, wy.to_f]
      end
    end

    def self.offset_x
      @offset_x
    end

    def self.offset_x=(val)
      @offset_x = val.to_f
    end

    def self.offset_y
      @offset_y
    end

    def self.offset_y=(val)
      @offset_y = val.to_f
    end

    def self.current_clip
      Backend.current_clip
    end

    # ビューポート・矩形クリッピングスコープ (glScissor & 遅延ディファード適用)
    # - local: false => 元の画面座標系のまま指定矩形外をクリップ (Ebitengine SubImage 風)
    # - local: true  => クリップ矩形の左上を (0, 0) とするローカル相対座標系 (UI ウィンドウ用)
    # - z: Float     => クリップ全体の親キューにおける Z レベル。クリップ内部は独立して Z ソートされます。
    def self.clip(x, y, w, h, local: false, z: 0.0)
      prev_ox = @offset_x
      prev_oy = @offset_y

      # 現在の座標系における絶対論理座標を算出
      abs_x = x.to_f + prev_ox
      abs_y = y.to_f + prev_oy
      req_w = w.to_f
      req_h = h.to_f

      # 親クリップ矩形との交差判定 (AABB Intersection)
      parent_clip = Backend.current_clip
      if parent_clip
        px, py, pw, ph = parent_clip[0], parent_clip[1], parent_clip[2], parent_clip[3]
        x1 = [abs_x, px].max
        y1 = [abs_y, py].max
        x2 = [abs_x + req_w, px + pw].min
        y2 = [abs_y + req_h, py + ph].min
        clip_x = x1
        clip_y = y1
        clip_w = [0.0, x2 - x1].max
        clip_h = [0.0, y2 - y1].max
      else
        clip_x = abs_x
        clip_y = abs_y
        clip_w = [0.0, req_w].max
        clip_h = [0.0, req_h].max
      end

      # ローカル座標系の場合はオフセットを更新
      if local
        @offset_x = abs_x
        @offset_y = abs_y
      end

      Backend.push_clip([clip_x, clip_y, clip_w, clip_h], z)

      yield
    ensure
      Backend.pop_clip
      @offset_x = prev_ox
      @offset_y = prev_oy
    end

    DEFAULT_SHADOW_COLOR = [0, 0, 0, 180].freeze

    # ----------------------------------------------------
    # 描画 API 
    # ----------------------------------------------------
    def self.draw_rect(x, y, w, h,
                       color: nil,
                       radius: 0.0,
                       border_color: nil,
                       border_width: nil,
                       shadow_blur: 0.0,
                       shadow_color: nil,
                       image: nil,
                       camera: true,
                       z: 0.0)
      actual_color = color || (border_color ? nil : :white)
      c_color = Backend.normalize_color(actual_color)

      if @has_camera && camera
        cur_zoom = @cam_zoom
        ax = (x.to_f * cur_zoom) + @cam_ox + @offset_x
        ay = (y.to_f * cur_zoom) + @cam_oy + @offset_y
        wf = w.to_f * cur_zoom
        hf = h.to_f * cur_zoom
        rad = radius.to_f * cur_zoom
      else
        cur_zoom = 1.0
        ax = x.to_f + @offset_x
        ay = y.to_f + @offset_y
        wf = w.to_f
        hf = h.to_f
        rad = radius.to_f
      end

      is_flat = (radius.nil? || rad <= 0.0) &&
                border_color.nil? &&
                (shadow_blur.nil? || shadow_blur.to_f <= 0.0) &&
                image.nil?

      if is_flat
        x2 = ax + wf
        y2 = ay + hf
        cr = c_color[0].to_f; cg = c_color[1].to_f; cb = c_color[2].to_f; ca = c_color[3].to_f
        data = [
          ax, ay, cr, cg, cb, ca,
          ax, y2, cr, cg, cb, ca,
          x2, ay, cr, cg, cb, ca,
          x2, ay, cr, cg, cb, ca,
          ax, y2, cr, cg, cb, ca,
          x2, y2, cr, cg, cb, ca
        ].pack("f*")
        Backend.enqueue_draw(
          Backend::Pipelines::TRIANGLES,
          data,
          6,
          shader: flat_primitive_shader,
          z: z
        )
        return
      end

      b_width = 0.0
      b0 = 0.0; b1 = 0.0; b2 = 0.0; b3 = 0.0
      if border_color
        b_width = (border_width || 1.0).to_f * cur_zoom
        bc = Backend.normalize_color(border_color)
        b0 = bc[0].to_f; b1 = bc[1].to_f; b2 = bc[2].to_f; b3 = bc[3].to_f
      end

      s_blur = shadow_blur.to_f * cur_zoom
      s0 = 0.0; s1 = 0.0; s2 = 0.0; s3 = 0.0
      if s_blur > 0.0
        sc = Backend.normalize_color(shadow_color || DEFAULT_SHADOW_COLOR)
        s0 = sc[0].to_f; s1 = sc[1].to_f; s2 = sc[2].to_f; s3 = sc[3].to_f
      end

      mode = image ? 1.0 : 0.0
      data = [
        ax, ay, wf, hf,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        rad, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        0.0, 0.0, 1.0, 1.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: image,
        shader: card_shader,
        z: z
      )
    end

    def self.draw_circle(x, y, r,
                        color: nil,
                        border_color: nil,
                        border_width: nil,
                        shadow_blur: 0.0,
                        shadow_color: nil,
                        image: nil,
                        camera: true,
                        z: 0.0)
      rf = r.to_f
      d = rf * 2.0
      draw_rect(x.to_f - rf, y.to_f - rf, d, d,
                radius: rf,
                color: color,
                border_color: border_color,
                border_width: border_width,
                shadow_blur: shadow_blur,
                shadow_color: shadow_color,
                image: image,
                camera: camera,
                z: z)
    end

    def self.draw_image(x, y, image,
                        color: :white,
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
                        uniforms: nil,
                        src_rect: nil,
                        camera: true,
                        z: 0.0)
      return unless image
      effective_shader = shader || @current_shader || default_sprite_shader

      c_color = Backend.normalize_color(color || :white)

      # alpha の適用 (0..255)
      if alpha && alpha != 255
        af = alpha.to_f / 255.0
        af = 0.0 if af < 0.0
        af = 1.0 if af > 1.0
        c_color = [c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f * af]
      end

      if @has_camera && camera
        sx = (scale ? scale.to_f : scale_x.to_f) * @cam_zoom
        sy = (scale ? scale.to_f : scale_y.to_f) * @cam_zoom
        ax = (x.to_f * @cam_zoom) + @cam_ox + @offset_x
        ay = (y.to_f * @cam_zoom) + @cam_oy + @offset_y
      else
        sx = scale ? scale.to_f : scale_x.to_f
        sy = scale ? scale.to_f : scale_y.to_f
        ax = x.to_f + @offset_x
        ay = y.to_f + @offset_y
      end

      # ピボット (center_x, center_y, または pivot: :center, :top_left, [px, py])
      cx = center_x.to_f
      cy = center_y.to_f
      if pivot.nil?
        # デフォルト (center_x, center_y)
      elsif pivot == :center
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
      rad = (angle ? angle.to_f : 0.0) * (Math::PI / 180.0)

      # offset_mode: 0.0 (:top_left), 1.0 (:center)
      off_mode = (offset_mode == :center) ? 1.0 : 0.0

      # blend mode
      b_mode = Backend.normalize_blend_mode(blend)

      if src_rect
        tw = image.texture_width.to_f
        th = image.texture_height.to_f
        s_rx = image.x + src_rect[0].to_f
        s_ry = image.y + src_rect[1].to_f
        draw_w = src_rect[2].to_f
        draw_h = src_rect[3].to_f
        uv0 = tw > 0.0 ? s_rx / tw : 0.0
        uv1 = th > 0.0 ? s_ry / th : 0.0
        uv2 = tw > 0.0 ? draw_w / tw : 1.0
        uv3 = th > 0.0 ? draw_h / th : 1.0
      else
        draw_w = image.width.to_f
        draw_h = image.height.to_f
        tw = image.texture_width.to_f
        th = image.texture_height.to_f
        uv0 = tw > 0.0 ? image.x.to_f / tw : 0.0
        uv1 = th > 0.0 ? image.y.to_f / th : 0.0
        uv2 = tw > 0.0 ? draw_w / tw : 1.0
        uv3 = th > 0.0 ? draw_h / th : 1.0
      end

      data = [
        ax, ay, draw_w, draw_h,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        uv0, uv1, uv2, uv3,
        rad, sx, sy, off_mode,
        cx, cy, 0.0, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::SPRITE,
        data,
        1,
        image: image,
        shader: effective_shader,
        uniforms: uniforms,
        blend: b_mode,
        z: z
      )
    end


    def self.draw_triangle(x1, y1, x2, y2, x3, y3, color: :white, camera: true, z: 0.0)
      if @has_camera && camera
        cam_ox = @cam_ox + @offset_x
        cam_oy = @cam_oy + @offset_y
        ax1 = (x1.to_f * @cam_zoom) + cam_ox; ay1 = (y1.to_f * @cam_zoom) + cam_oy
        ax2 = (x2.to_f * @cam_zoom) + cam_ox; ay2 = (y2.to_f * @cam_zoom) + cam_oy
        ax3 = (x3.to_f * @cam_zoom) + cam_ox; ay3 = (y3.to_f * @cam_zoom) + cam_oy
      else
        ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
        ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
        ax3 = x3.to_f + @offset_x; ay3 = y3.to_f + @offset_y
      end

      if color.is_a?(Array) && color.length == 3 && (color[0].is_a?(Color) || color[0].is_a?(Symbol) || color[0].is_a?(Array))
        # 頂点ごとの色指定 [c1, c2, c3]
        c1 = Backend.normalize_color(color[0])
        c2 = Backend.normalize_color(color[1])
        c3 = Backend.normalize_color(color[2])
        data = [
          ax1, ay1, c1[0].to_f, c1[1].to_f, c1[2].to_f, c1[3].to_f,
          ax2, ay2, c2[0].to_f, c2[1].to_f, c2[2].to_f, c2[3].to_f,
          ax3, ay3, c3[0].to_f, c3[1].to_f, c3[2].to_f, c3[3].to_f
        ].pack("f*")
      else
        c = Backend.normalize_color(color)
        cr = c[0].to_f; cg = c[1].to_f; cb = c[2].to_f; ca = c[3].to_f
        data = [
          ax1, ay1, cr, cg, cb, ca,
          ax2, ay2, cr, cg, cb, ca,
          ax3, ay3, cr, cg, cb, ca
        ].pack("f*")
      end

      Backend.enqueue_draw(
        Backend::Pipelines::TRIANGLES,
        data,
        3,
        shader: flat_primitive_shader,
        z: z
      )
    end

    def self.draw_line(x1, y1, x2, y2, color: :white, width: 1.0, camera: true, z: 0.0)
      actual_color = color || :white
      if @has_camera && camera
        cam_ox = @cam_ox + @offset_x
        cam_oy = @cam_oy + @offset_y
        ax1 = (x1.to_f * @cam_zoom) + cam_ox; ay1 = (y1.to_f * @cam_zoom) + cam_oy
        ax2 = (x2.to_f * @cam_zoom) + cam_ox; ay2 = (y2.to_f * @cam_zoom) + cam_oy
        w = width.to_f * @cam_zoom
      else
        ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
        ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
        w = width.to_f
      end

      dx = ax2 - ax1
      dy = ay2 - ay1
      len = Math.sqrt(dx * dx + dy * dy)

      is_grad = actual_color.is_a?(Array) && actual_color.length == 2 && (actual_color[0].is_a?(Color) || actual_color[0].is_a?(Symbol) || actual_color[0].is_a?(Array))
      if is_grad
        c1 = Backend.normalize_color(actual_color[0])
        c2 = Backend.normalize_color(actual_color[1])
        c1_r = c1[0].to_f; c1_g = c1[1].to_f; c1_b = c1[2].to_f; c1_a = c1[3].to_f
        c2_r = c2[0].to_f; c2_g = c2[1].to_f; c2_b = c2[2].to_f; c2_a = c2[3].to_f
      else
        c = Backend.normalize_color(actual_color)
        cr = c[0].to_f; cg = c[1].to_f; cb = c[2].to_f; ca = c[3].to_f
        c1_r = c2_r = cr
        c1_g = c2_g = cg
        c1_b = c2_b = cb
        c1_a = c2_a = ca
      end

      if w > 1.0 && len > 0.0001
        inv_len = 1.0 / len
        nx = -dy * inv_len
        ny = dx * inv_len
        hw = w * 0.5
        ox = nx * hw
        oy = ny * hw

        px1 = ax1 + ox; py1 = ay1 + oy
        px2 = ax1 - ox; py2 = ay1 - oy
        px3 = ax2 - ox; py3 = ay2 - oy
        px4 = ax2 + ox; py4 = ay2 + oy

        data = [
          px1, py1, c1_r, c1_g, c1_b, c1_a,
          px2, py2, c1_r, c1_g, c1_b, c1_a,
          px3, py3, c2_r, c2_g, c2_b, c2_a,

          px1, py1, c1_r, c1_g, c1_b, c1_a,
          px3, py3, c2_r, c2_g, c2_b, c2_a,
          px4, py4, c2_r, c2_g, c2_b, c2_a
        ].pack("f*")

        Backend.enqueue_draw(
          Backend::Pipelines::TRIANGLES,
          data,
          6,
          shader: flat_primitive_shader,
          z: z
        )
      else
        data = [
          ax1, ay1, c1_r, c1_g, c1_b, c1_a,
          ax2, ay2, c2_r, c2_g, c2_b, c2_a
        ].pack("f*")

        Backend.enqueue_draw(
          Backend::Pipelines::LINES,
          data,
          2,
          shader: flat_primitive_shader,
          z: z
        )
      end
    end

    @sdf_font_shader = nil

    def self.sdf_font_shader
      @sdf_font_shader ||= Shader.new(Shaders::FONT_SDF_VERTEX, Shaders::FONT_SDF_FRAGMENT)
    end

    class CharContext
      attr_accessor :char, :index, :line_index, :x, :y, :w, :h, :color, :visible
      attr_accessor :outline_width, :outline_color, :weight

      def scale
        @scale
      end

      def scale=(val)
        @scale = val
      end

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

    # テキスト描画幅の計算
    def self.text_width(text, font: nil, size: 24)
      target_font = font || Font.default
      return 0.0 unless target_font
      target_font.text_width(text, size)
    end

    # ----------------------------------------------------
    # 高品質 SDF テキスト描画 API (改行・アライメント対応)
    # - align: :left (デフォルト), :center, :right
    # - valign: :top (デフォルト), :middle / :center, :bottom, :baseline
    # - line_spacing: 行送り倍率 (Float, デフォルトはフォントメトリクス準拠)
    # ブロックが渡された場合は 1文字単位のカスタム装飾を実行
    # ----------------------------------------------------
    def self.draw_text(x, y, text,
                       font: nil,
                       size: 24,
                       color: :white,
                       align: :left,
                       valign: :top,
                       line_spacing: nil,
                       weight: 0.0,
                       outline_width: 0.0,
                       outline_color: :black,
                       shadow_blur: 0.0,
                       shadow_color: nil,
                       shadow_dx: 0.0,
                       shadow_dy: 0.0,
                       sdf: nil,
                       camera: true,
                       z: 0.0,
                       &block)
      return if text.nil?
      str = text.to_s
      return if str.empty?

      target_font = font || Font.default
      return unless target_font

      if @has_camera && camera
        base_x = (x.to_f * @cam_zoom) + @cam_ox
        base_y = (y.to_f * @cam_zoom) + @cam_oy
        f_size = size.to_f * @cam_zoom
      else
        base_x = x.to_f
        base_y = y.to_f
        f_size = size.to_f
      end
      f_size = 24.0 if f_size <= 0.0

      # 改行を含む複数行テキストの処理
      if str.include?("\n")
        lines = str.split("\n", -1)
        line_count = lines.length
        metrics = target_font.metrics(f_size)
        line_h = line_spacing ? (f_size * line_spacing.to_f) : (metrics[:line_height] || (f_size * 1.2))
        total_h = f_size + (line_count - 1) * line_h

        cur_base_y = base_y
        case valign
        when :middle, :center
          cur_base_y -= total_h * 0.5
        when :bottom
          cur_base_y -= total_h
        when :baseline
          cur_base_y -= (metrics[:ascent] || f_size * 0.8)
        end

        lines.each_with_index do |line_text, idx|
          line_y = cur_base_y + idx * line_h
          line_x = base_x
          if align == :center
            line_x -= target_font.text_width(line_text, f_size) * 0.5
          elsif align == :right
            line_x -= target_font.text_width(line_text, f_size)
          end

          if block
            __draw_text_custom(line_x, line_y, line_text, font, size, color,
                               weight, outline_width, outline_color,
                               shadow_blur, shadow_color,
                               shadow_dx, shadow_dy, sdf, z, &block)
          else
            __draw_text_simple(line_x, line_y, line_text, font, size, color,
                               weight, outline_width, outline_color,
                               shadow_blur, shadow_color,
                               shadow_dx, shadow_dy, sdf, z)
          end
        end
        return
      end

      # 単一行テキストの揃え位置オフセット算出 (デフォルト :left / :top 時は text_width や metrics をスキップしてゼロコスト化)
      draw_x = base_x
      if align == :center
        draw_x -= target_font.text_width(str, f_size) * 0.5
      elsif align == :right
        draw_x -= target_font.text_width(str, f_size)
      end

      draw_y = base_y
      if valign != :top
        case valign
        when :middle, :center
          draw_y -= f_size * 0.5
        when :bottom
          draw_y -= f_size
        when :baseline
          metrics = target_font.metrics(f_size)
          draw_y -= (metrics[:ascent] || f_size * 0.8)
        end
      end

      if block
        __draw_text_custom(draw_x, draw_y, str, font, f_size, color,
                           weight, outline_width, outline_color,
                           shadow_blur, shadow_color,
                           shadow_dx, shadow_dy, sdf, z, &block)
      else
        __draw_text_simple(draw_x, draw_y, str, font, f_size, color,
                           weight, outline_width, outline_color,
                           shadow_blur, shadow_color,
                           shadow_dx, shadow_dy, sdf, z)
      end
    end

    def self.__draw_text_simple(x, y, text, font, size, color,
                                weight, outline_width, outline_color,
                                shadow_blur, shadow_color,
                                shadow_dx, shadow_dy, sdf, z)
      return if text.nil?

      target_font = font || Font.default
      return unless target_font

      font_atlas = Font.atlas_image
      return unless font_atlas

      f_size = size.to_f
      f_size = 24.0 if f_size <= 0.0

      c_color = Backend.normalize_color(color)

      outline_w = outline_width.to_f
      outline_c = (outline_w > 0.0) ? Backend.normalize_color(outline_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_dx = shadow_dx.to_f
      s_dy = shadow_dy.to_f
      s_c = (s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? Backend.normalize_color(shadow_color || DEFAULT_SHADOW_COLOR) : [0.0, 0.0, 0.0, 0.0]

      effective_sdf = if sdf.nil?
                        (outline_w > 0.0 || s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? true : nil
                      else
                        sdf ? true : false
                      end

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
      shader = sdf_font_shader

      metrics = target_font.metrics(f_size)
      ascent = metrics[:ascent]

      pen_x = (x.to_f + @offset_x).round
      pen_y = (y.to_f + @offset_y + ascent).round.to_f

      str = text.to_s
      chars = str.chars
      len = chars.length
      return if len == 0

      batch = []
      glyph_count = 0

      cr = c_color[0].to_f; cg = c_color[1].to_f; cb = c_color[2].to_f; ca = c_color[3].to_f
      p0_0 = p0[0].to_f; p0_1 = p0[1].to_f; p0_2 = p0[2].to_f; p0_3 = p0[3].to_f
      p1_0 = p1[0].to_f; p1_1 = p1[1].to_f; p1_2 = p1[2].to_f; p1_3 = p1[3].to_f
      p2_0 = p2[0].to_f; p2_1 = p2[1].to_f; p2_2 = p2[2].to_f; p2_3 = p2[3].to_f

      i = 0
      while i < len
        ch = chars[i]
        glyph_data = target_font.get_glyph(ch, f_size, effective_sdf)
        adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

        if glyph_data && glyph_data[0] # visible == true
          _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv, is_bitmap = glyph_data
          is_bmp = (is_bitmap == true || is_bitmap == 1) ? 1.0 : 0.0
          gx = (pen_x + x0).round.to_f
          gy = (pen_y + y0).round.to_f
          gw = (x1 - x0).to_f
          gh = (y1 - y0).to_f

          batch.push(
            gx, gy, gw, gh,
            cr, cg, cb, ca,
            p0_0, p0_1, p0_2, p0_3,
            p1_0, p1_1, p1_2, p1_3,
            p2_0, p2_1, p2_2, p2_3,
            s_atlas_weight, is_bmp, 0.0, 0.0,
            u0.to_f, v0.to_f, (u1 - u0).to_f, (v1 - v0).to_f
          )
          glyph_count += 1
        end

        pen_x += adv
        i += 1
      end

      if glyph_count > 0
        Backend.enqueue_draw(
          Backend::Pipelines::FONT,
          batch.pack("f*"),
          glyph_count,
          image: font_atlas,
          shader: shader,
          z: z
        )
      end
    end

    def self.__draw_text_custom(x, y, text, font, size, color,
                                weight, outline_width, outline_color,
                                shadow_blur, shadow_color,
                                shadow_dx, shadow_dy, sdf, z,
                                &block)
      return if text.nil?

      target_font = font || Font.default
      return unless target_font

      font_atlas = Font.atlas_image
      return unless font_atlas

      f_size = size.to_f
      f_size = 24.0 if f_size <= 0.0

      c_color = Backend.normalize_color(color)

      outline_w = outline_width.to_f
      outline_c = (outline_w > 0.0) ? Backend.normalize_color(outline_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_dx = shadow_dx.to_f
      s_dy = shadow_dy.to_f
      s_c = (s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? Backend.normalize_color(shadow_color || DEFAULT_SHADOW_COLOR) : [0.0, 0.0, 0.0, 0.0]

      effective_sdf = if sdf.nil?
                        (outline_w > 0.0 || s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? true : nil
                      else
                        sdf ? true : false
                      end

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

      pen_x = (x.to_f + @offset_x).round
      pen_y = (y.to_f + @offset_y + ascent).round.to_f

      str = text.to_s
      chars = str.chars
      len = chars.length
      return if len == 0

      batch = []
      glyph_count = 0

      ctx = @char_ctx
      i = 0
      while i < len
        ch = chars[i]
        glyph_data = target_font.get_glyph(ch, f_size, effective_sdf)
        adv = glyph_data ? glyph_data[9].to_f : (f_size * 0.5)

        if glyph_data && glyph_data[0] # visible == true
          _visible, u0, v0, u1, v1, x0, y0, x1, y1, _adv, is_bitmap = glyph_data
          is_bmp = (is_bitmap == true || is_bitmap == 1) ? 1.0 : 0.0
          gx = (pen_x + x0).round
          gy = (pen_y + y0).round
          gw = x1 - x0
          gh = y1 - y0
          uv = [u0, v0, u1 - u0, v1 - v0]

          ctx.reset(ch, i, gx, gy, gw, gh, c_color, outline_w, outline_c, s_weight)
          yield(ctx)

          if ctx.visible
            cgx = ctx.x
            cgy = ctx.y
            cgw = ctx.w
            cgh = ctx.h

            if ctx.scale != 1.0
              sc = ctx.scale
              cx = cgx + cgw * 0.5
              cy = cgy + cgh * 0.5
              cgw *= sc
              cgh *= sc
              cgx = cx - cgw * 0.5
              cgy = cy - cgh * 0.5
            end

            cur_color = (ctx.color.equal?(c_color)) ? c_color : Backend.normalize_color(ctx.color)
            cur_p0 = (ctx.outline_width == outline_w) ? p0 : [ctx.outline_width * scale_ratio, s_atlas_blur, s_atlas_dx, s_atlas_dy]
            cur_p1 = (ctx.outline_color.equal?(outline_c)) ? outline_c : Backend.normalize_color(ctx.outline_color)
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

      if glyph_count > 0
        Backend.enqueue_draw(
          Backend::Pipelines::FONT,
          batch.pack("f*"),
          glyph_count,
          image: font_atlas,
          shader: shader,
          z: z
        )
      end
    end

    def self.canvas
      @canvas ||= Canvas.new
    end

    def self.draw_path(camera: true)
      c = canvas
      cam = (@camera && @camera_disabled_stack.empty? && camera) ? @camera : nil
      zoom = cam ? cam.zoom : 1.0
      cam_ox = (cam ? cam.calc_offset_x : 0.0) + @offset_x
      cam_oy = (cam ? cam.calc_offset_y : 0.0) + @offset_y

      has_transform = (cam_ox != 0.0 || cam_oy != 0.0 || zoom != 1.0)
      if has_transform
        c.save
        c.translate(cam_ox, cam_oy)
        c.scale(zoom, zoom) if zoom != 1.0
      end
      c.begin_path
      yield c
    ensure
      c.restore if has_transform
    end
  end
end

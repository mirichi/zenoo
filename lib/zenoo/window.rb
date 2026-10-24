module Zenoo
  module Window
    def self.current_target
      Backend.current_target
    end

    def self.current_target=(target)
      Backend.current_target = target
    end

    @bg_color = (18 << 24) | (20 << 16) | (30 << 8) | 255
    @main_loop_block = nil
    @step_proc = nil
    @fps = 60.0
    @fps_frames = 0
    @fps_accum = 0.0

    # DXRuby風メインループ (scale: nil の場合はモニターのDPIスケールを自動検出)
    def self.loop(width = 1280, height = 720, title = "Zenoo", scale: nil, scale_mode: :fit, window_width: nil, window_height: nil, fullscreen: false, vsync: false, msaa: nil, fps: 60, &block)
      self.msaa = msaa unless msaa.nil?
      win_w = window_width ? window_width.to_i : (scale ? (width * scale).to_i : 0)
      win_h = window_height ? window_height.to_i : (scale ? (height * scale).to_i : 0)
      Native::Window.init(width, height, title, fullscreen, win_w, win_h, scale_mode)
      Native::Window.scale_mode = scale_mode
      Native::Window.vsync = (vsync ? 1 : 0)
      self.target_fps = fps
      Font.atlas_image

      @main_loop_block = block

      if Native::Window.wasm?
        @step_proc = proc { __step_frame }
        Native::Window.start_wasm_loop(@step_proc)
      else
        while Native::Window.update
          __step_frame
        end
        Native::Window.shutdown
      end
    end

    def self.__update_step
      Audio.update(delta_time)
      Tween.__update_step(delta_time)
      GUI.begin_frame
      @main_loop_block.call if @main_loop_block
      GUI.end_frame
      Input.__update_step
    end

    def self.__draw_step
      if Profiler.enabled
        Profiler.measure(:draw) do
          Backend.flush_screen
          Backend.clear_clips
          @offset_x = 0.0
          @offset_y = 0.0
          Native::Renderer.reset_scissor
        end
      else
        Backend.flush_screen
        Backend.clear_clips
        @offset_x = 0.0
        @offset_y = 0.0
        Native::Renderer.reset_scissor
      end
    end

    def self.__step_frame
      __update_fps
      Backend.current_target = nil
      Native::Image.reset_render_target
      if Profiler.enabled
        Profiler.measure(:draw) { Native::Window.clear(@bg_color) }
      else
        Native::Window.clear(@bg_color)
      end
      __update_step
      __draw_step
      Profiler.end_frame
      Backend.current_target = nil
      Native::Image.reset_render_target
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

    def self.title
      Native::Window.title
    end

    def self.title=(val)
      Native::Window.title = val.to_s
    end

    def self.window_position
      Native::Window.window_position
    end

    def self.window_position=(pos)
      if pos.is_a?(Array) && pos.length >= 2
        Native::Window.set_window_position(pos[0].to_i, pos[1].to_i)
      end
    end

    def self.position
      window_position
    end

    def self.position=(pos)
      self.window_position = pos
    end

    def self.focused?
      Native::Window.focused?
    end

    def self.active?
      focused?
    end

    def self.minimized?
      Native::Window.minimized?
    end

    def self.iconified?
      minimized?
    end

    def self.maximized?
      Native::Window.maximized?
    end

    def self.hovered?
      Native::Window.hovered?
    end

    def self.mouse_in_window?
      hovered?
    end

    def self.resize(w, h)
      Native::Window.set_window_size(w.to_i, h.to_i)
    end

    def self.delta_time
      Native::Window.delta_time
    end

    def self.fps
      @fps || 60.0
    end

    def self.fps=(val)
      self.target_fps = val
    end

    def self.target_fps=(val)
      t = (val.nil? || val.to_i <= 0) ? 0 : val.to_i
      Native::Window.target_fps = t
    end

    def self.target_fps
      Native::Window.target_fps
    end

    def self.__update_fps
      dt = delta_time
      return if dt <= 0.0 || dt > 1.0
      @fps_frames = (@fps_frames || 0) + 1
      @fps_accum = (@fps_accum || 0.0) + dt
      if @fps_accum >= 0.25
        measured = @fps_frames.to_f / @fps_accum
        current = @fps || 60.0
        @fps = current * 0.2 + measured * 0.8
        @fps_frames = 0
        @fps_accum = 0.0
      end
    end

    def self.vsync=(val)
      Native::Window.vsync = (val ? 1 : 0)
    end

    def self.msaa_samples=(val)
      Native::Window.msaa_samples = val.to_i
    end

    def self.msaa_samples
      Native::Window.msaa_samples
    end

    def self.msaa=(val)
      samples = val ? (val.is_a?(Integer) ? val : 4) : 0
      self.msaa_samples = samples
    end

    def self.msaa?
      msaa_samples > 0
    end

    CURSOR_SHAPES = {
      arrow: 0,
      ibeam: 1,
      crosshair: 2,
      hand: 3,
      hresize: 4,
      vresize: 5,
      resize_nwse: 6,
      resize_nesw: 7,
      resize_all: 8,
      not_allowed: 9,
      resize: 6,
      window_resize: 6
    }.freeze

    def self.show_cursor(show = true)
      Native::Window.show_cursor(show)
    end

    def self.hide_cursor
      Native::Window.show_cursor(false)
    end

    def self.mouse_cursor_visible=(val)
      Native::Window.show_cursor(!!val)
    end

    def self.cursor
      @current_cursor_shape || :arrow
    end

    def self.cursor=(shape)
      @current_cursor_shape = shape
      shape_id = CURSOR_SHAPES[shape] || (shape.is_a?(Integer) ? shape : 0)
      Native::Window.set_cursor(shape_id)
    end

    def self.set_cursor(shape)
      self.cursor = shape
    end

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

    def self.textured_primitive_shader
      @textured_primitive_shader ||= Shader.new(Shaders::TEXTURED_PRIMITIVE_VERTEX, Shaders::TEXTURED_PRIMITIVE_FRAGMENT)
    end

    def self.card_shader
      @card_shader ||= Shader.new(Shaders::CARD_VERTEX, Shaders::CARD_FRAGMENT)
    end

    @offset_x = 0.0
    @offset_y = 0.0
    # @camera        : 設定中のカメラ (Window.camera が返すもの)
    # @active_camera : 描画に実際に適用するカメラ (without_camera 中などは nil)
    # 描画時は @active_camera.view ([zoom, ox, oy]) を都度参照する
    @camera = nil
    @active_camera = nil
    @camera_disabled_depth = 0

    def self.__sync_active_camera
      @active_camera = @camera_disabled_depth.zero? ? @camera : nil
    end

    # カメラ設定 (Zenoo::Camera)
    # - 引数なし: 現在のカメラを取得
    # - 引数あり (ブロックなし): カメラを設定
    # - ブロックあり: ブロック内のみカメラを適用
    def self.camera(cam = nil, &block)
      if block
        old_cam = @camera
        @camera = cam
        __sync_active_camera
        yield
        @camera = old_cam
        __sync_active_camera
      elsif cam
        self.camera = cam
      else
        @camera
      end
    end

    def self.camera=(cam)
      @camera = cam
      __sync_active_camera
    end

    # カメラを一時的に無効化して UI などを画面ピクセル座標で描画
    def self.without_camera
      @camera_disabled_depth += 1
      __sync_active_camera
      yield
      @camera_disabled_depth -= 1
      __sync_active_camera
    end

    def self.camera_enabled?
      !@active_camera.nil?
    end

    # 画面座標 -> ワールド座標変換 (マウス位置など)
    def self.to_world(sx, sy)
      if @active_camera
        @active_camera.screen_to_world(sx, sy)
      else
        [sx.to_f, sy.to_f]
      end
    end

    # ワールド座標 -> 画面座標変換
    def self.to_screen(wx, wy)
      if @active_camera
        @active_camera.world_to_screen(wx, wy)
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
    def self.push_clip_scope(x, y, w, h, local: false, z: 0.0)
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
        px = parent_clip[0]
        py = parent_clip[1]
        pw = parent_clip[2]
        ph = parent_clip[3]
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
      [prev_ox, prev_oy]
    end

    def self.pop_clip_scope(prev_ox, prev_oy)
      Backend.pop_clip
      @offset_x = prev_ox
      @offset_y = prev_oy
    end

    def self.clip(x, y, w, h, local: false, z: 0.0)
      prev_ox, prev_oy = push_clip_scope(x, y, w, h, local: local, z: z)
      yield
      pop_clip_scope(prev_ox, prev_oy)
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
                       angle: 0.0,
                       pivot: nil,
                       image: nil,
                       blend: :alpha,
                       camera: true,
                       z: 0.0)
      actual_color = color || (border_color ? nil : :white)
      c_color = Backend.normalize_color(actual_color)
      b_mode = Backend.normalize_blend_mode(blend)

      cam = @active_camera
      if cam && camera
        cur_zoom, cam_ox, cam_oy = cam.view
        ax = (x.to_f * cur_zoom) + cam_ox + @offset_x
        ay = (y.to_f * cur_zoom) + cam_oy + @offset_y
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
                image.nil? &&
                (angle.nil? || (angle.to_f % 360.0).abs < 0.0001)

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
          blend: b_mode,
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

      # ピボット (pivot: :center, :top_left, :center_left 等)
      pv = Collision.parse_pivot(pivot)
      pv_x = pv[0]
      pv_y = pv[1]
      rot_rad = (angle ? angle.to_f : 0.0) * (Math::PI / 180.0)

      mode = image ? 1.0 : 0.0
      data = [
        ax, ay, wf, hf,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        rad, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        0.0, 0.0, 1.0, 1.0,
        rot_rad, pv_x, pv_y, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: image,
        shader: card_shader,
        blend: b_mode,
        z: z
      )
    end

    def self.draw_circle(x, y, r,
                        color: nil,
                        border_color: nil,
                        border_width: nil,
                        shadow_blur: 0.0,
                        shadow_color: nil,
                        blend: :alpha,
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
                blend: blend,
                camera: camera,
                z: z)
    end

    # SDF 楕円描画 (解析的アンチエイリアス・回転・枠線・影対応)
    #
    # cx, cy       : 楕円の中心座標
    # rx, ry       : X軸・Y軸の半径
    # color        : 塗りつぶし色 (シンボル、配列、Hex、Colorオブジェクト)
    # border_color : 枠線の色
    # border_width : 枠線の幅 (ピクセル単位)
    # shadow_blur  : ドロップシャドウ・外光彩のぼかし幅
    # shadow_color : 影の色
    # angle        : 楕円の回転角度 (度数法)
    # blend        : ブレンドモード (:alpha, :add 等)
    # camera       : カメラ適用有無 (デフォルト: true)
    # z            : Zオーダー (デフォルト: 0.0)
    def self.draw_ellipse(cx, cy, rx, ry,
                          color: nil,
                          border_color: nil,
                          border_width: nil,
                          shadow_blur: 0.0,
                          shadow_color: nil,
                          angle: 0.0,
                          blend: :alpha,
                          camera: true,
                          z: 0.0)
      rxf = rx.to_f.abs
      ryf = ry.to_f.abs
      return if rxf <= 0.0 || ryf <= 0.0

      actual_color = color || (border_color ? nil : :white)
      c_color = Backend.normalize_color(actual_color)
      b_mode = Backend.normalize_blend_mode(blend)

      cam = @active_camera
      if cam && camera
        cur_zoom, cam_ox, cam_oy = cam.view
        ax = ((cx.to_f - rxf) * cur_zoom) + cam_ox + @offset_x
        ay = ((cy.to_f - ryf) * cur_zoom) + cam_oy + @offset_y
        wf = (rxf * 2.0) * cur_zoom
        hf = (ryf * 2.0) * cur_zoom
      else
        cur_zoom = 1.0
        ax = (cx.to_f - rxf) + @offset_x
        ay = (cy.to_f - ryf) + @offset_y
        wf = rxf * 2.0
        hf = ryf * 2.0
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

      rot_rad = (angle ? angle.to_f : 0.0) * (Math::PI / 180.0)
      mode = 2.0 # 楕円モード (SDF)

      data = [
        ax, ay, wf, hf,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        0.0, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        0.0, 0.0, 1.0, 1.0,
        rot_rad, 0.5, 0.5, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: nil,
        shader: card_shader,
        blend: b_mode,
        z: z
      )
    end

    def self.draw_image(x, y, image,
                        anchor: :top_left,
                        pivot: :center,
                        color: :white,
                        angle: 0.0,
                        scale: nil,
                        scale_x: 1.0,
                        scale_y: 1.0,
                        alpha: 255,
                        blend: :alpha,
                        shader: nil,
                        uniforms: nil,
                        camera: true,
                        z: 0.0)
      return unless image
      effective_shader = shader || default_sprite_shader

      c_color = Backend.normalize_color(color || :white)

      # alpha の適用 (0..255)
      if alpha && alpha != 255
        af = alpha.to_f / 255.0
        af = 0.0 if af < 0.0
        af = 1.0 if af > 1.0
        c_color = [c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f * af]
      end

      # 画像サイズ
      draw_w = image.width.to_f
      draw_h = image.height.to_f

      # アンカー (anchor: 配置基準点) から画像の左上原点 (tl_x, tl_y) を算出
      anc_x, anc_y = Collision.parse_anchor(anchor)
      tl_x = x.to_f - anc_x * draw_w
      tl_y = y.to_f - anc_y * draw_h

      # ピボット (pivot: 回転・拡縮の中心点 [0.0..1.0])
      cx, cy = Collision.parse_pivot(pivot)

      sx = scale ? scale.to_f : scale_x.to_f
      sy = scale ? scale.to_f : scale_y.to_f

      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        ax = (tl_x * cz) + cam_ox + @offset_x
        ay = (tl_y * cz) + cam_oy + @offset_y
        zw = draw_w * cz
        zh = draw_h * cz
      else
        ax = tl_x + @offset_x
        ay = tl_y + @offset_y
        zw = draw_w
        zh = draw_h
      end

      # 角度（度数法からラジアンへ変換）
      rad = (angle ? angle.to_f : 0.0) * (Math::PI / 180.0)

      # blend mode
      b_mode = Backend.normalize_blend_mode(blend)

      tw = image.texture_width.to_f
      th = image.texture_height.to_f
      uv0 = tw > 0.0 ? image.x.to_f / tw : 0.0
      uv1 = th > 0.0 ? image.y.to_f / th : 0.0
      uv2 = tw > 0.0 ? draw_w / tw : 1.0
      uv3 = th > 0.0 ? draw_h / th : 1.0

      # シェーダーへは常に左上座標 (top_left) を渡し、off_mode = 0.0 とする
      data = [
        ax, ay, zw, zh,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        uv0, uv1, uv2, uv3,
        rad, sx, sy, 0.0,
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

    def self.draw_sprite(sprite)
      return unless sprite
      return if sprite.vanished?
      return unless sprite.visible && (img = sprite.image)

      eff_blend = sprite.blend || :alpha
      b_mode = Backend.normalize_blend_mode(eff_blend)
      eff_shader = sprite.shader || default_sprite_shader
      eff_uniforms = sprite.uniforms

      alpha = sprite.alpha
      col = sprite.color
      if col.nil? && (alpha.nil? || alpha == 255)
        c0 = 1.0; c1 = 1.0; c2 = 1.0; c3 = 1.0
      else
        c_color = Backend.normalize_color(col || :white)
        c0 = c_color[0].to_f; c1 = c_color[1].to_f; c2 = c_color[2].to_f; c3 = c_color[3].to_f
        if alpha && alpha != 255
          af = alpha.to_f / 255.0
          af = 0.0 if af < 0.0
          af = 1.0 if af > 1.0
          c3 *= af
        end
      end

      draw_w = img.width.to_f
      draw_h = img.height.to_f
      tl_x = sprite.x.to_f - sprite.anchor_x * draw_w
      tl_y = sprite.y.to_f - sprite.anchor_y * draw_h

      pv_x = sprite.pivot_x
      pv_y = sprite.pivot_y

      sx = sprite.scale_x.to_f
      sy = sprite.scale_y.to_f

      sp_cam = sprite.camera
      cam = if sp_cam.is_a?(Camera)
              sp_cam
            elsif sp_cam
              @active_camera
            else
              nil
            end
      if cam
        cz, cam_ox, cam_oy = cam.view
        ax = (tl_x * cz) + cam_ox + @offset_x
        ay = (tl_y * cz) + cam_oy + @offset_y
        zw = draw_w * cz
        zh = draw_h * cz
      else
        ax = tl_x + @offset_x
        ay = tl_y + @offset_y
        zw = draw_w
        zh = draw_h
      end

      rad = sprite.angle != 0.0 ? sprite.angle.to_f * (Math::PI / 180.0) : 0.0

      tw = img.texture_width.to_f
      th = img.texture_height.to_f
      uv0 = tw > 0.0 ? img.x.to_f / tw : 0.0
      uv1 = th > 0.0 ? img.y.to_f / th : 0.0
      uv2 = tw > 0.0 ? draw_w / tw : 1.0
      uv3 = th > 0.0 ? draw_h / th : 1.0

      data = [
        ax, ay, zw, zh,
        c0, c1, c2, c3,
        uv0, uv1, uv2, uv3,
        rad, sx, sy, 0.0,
        pv_x, pv_y, 0.0, 0.0
      ].pack("f*")

      eff_z = sprite.z.to_f
      Backend.enqueue_draw(
        Backend::Pipelines::SPRITE,
        data,
        1,
        image: img,
        shader: eff_shader,
        uniforms: eff_uniforms,
        blend: b_mode,
        z: eff_z
      )
    end

    def self.draw_tilemap(tilemap, x: nil, y: nil, z: nil, camera: nil)
      return unless tilemap
      tilemap.draw(x: x, y: y, z: z, camera: camera)
    end


    # SDF 三角形描画 (解析的アンチエイリアス・角丸・枠線・影対応)
    #
    # x1, y1, x2, y2, x3, y3 : 三角形の3頂点
    # color                  : 塗りつぶし色
    # radius                 : 角丸半径 (デフォルト: 0.0)
    # border_color           : 枠線の色
    # border_width           : 枠線の幅
    # shadow_blur            : 影・光彩のぼかし幅
    # shadow_color           : 影の色
    # blend                  : ブレンドモード (:alpha, :add 等)
    # camera                 : カメラ適用有無 (デフォルト: true)
    # z                      : Zオーダー (デフォルト: 0.0)
    def self.draw_triangle(x1, y1, x2, y2, x3, y3,
                          color: :white,
                          radius: 0.0,
                          border_color: nil,
                          border_width: nil,
                          shadow_blur: 0.0,
                          shadow_color: nil,
                          blend: :alpha,
                          camera: true,
                          z: 0.0)
      b_mode = Backend.normalize_blend_mode(blend)
      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        cam_ox += @offset_x
        cam_oy += @offset_y
        ax1 = (x1.to_f * cz) + cam_ox; ay1 = (y1.to_f * cz) + cam_oy
        ax2 = (x2.to_f * cz) + cam_ox; ay2 = (y2.to_f * cz) + cam_oy
        ax3 = (x3.to_f * cz) + cam_ox; ay3 = (y3.to_f * cz) + cam_oy
        cur_zoom = cz
      else
        ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
        ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
        ax3 = x3.to_f + @offset_x; ay3 = y3.to_f + @offset_y
        cur_zoom = 1.0
      end

      # バウンディングボックス計算
      min_x = [ax1, ax2, ax3].min
      max_x = [ax1, ax2, ax3].max
      min_y = [ay1, ay2, ay3].min
      max_y = [ay1, ay2, ay3].max

      wf = max_x - min_x
      hf = max_y - min_y
      return if wf <= 0.0 && hf <= 0.0

      # 中心
      cx = (min_x + max_x) * 0.5
      cy = (min_y + max_y) * 0.5

      # 中心からの相対座標 (ローカル座標)
      p1x = ax1 - cx; p1y = ay1 - cy
      p2x = ax2 - cx; p2y = ay2 - cy
      p3x = ax3 - cx; p3y = ay3 - cy

      actual_color = color || (border_color ? nil : :white)
      c_color = Backend.normalize_color(actual_color)

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

      rad = radius.to_f * cur_zoom
      mode = 4.0 # 三角形モード (SDF)

      data = [
        min_x, min_y, wf, hf,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        rad, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        p1x, p1y, p2x, p2y,
        p3x, p3y, 0.0, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: nil,
        shader: card_shader,
        blend: b_mode,
        z: z
      )
    end

    # SDF 線分描画 (解析的アンチエイリアス・端点形状・枠線・影対応)
    #
    # x1, y1, x2, y2 : 始点・終点
    # color          : 線の色
    # width          : 線の太さ (ピクセル単位、デフォルト: 1.0)
    # cap            : 端点形状 (:butt [平ら], :round [丸端], :square [正方形])
    # border_color   : 枠線の色
    # border_width   : 枠線の幅
    # shadow_blur    : 影・光彩のぼかし幅
    # shadow_color   : 影の色
    # blend          : ブレンドモード (:alpha, :add 等)
    # camera         : カメラ適用有無 (デフォルト: true)
    # z              : Zオーダー (デフォルト: 0.0)
    def self.draw_line(x1, y1, x2, y2,
                      color: :white,
                      width: 1.0,
                      cap: :butt,
                      border_color: nil,
                      border_width: nil,
                      shadow_blur: 0.0,
                      shadow_color: nil,
                      blend: :alpha,
                      camera: true,
                      z: 0.0)
      actual_color = color || :white
      b_mode = Backend.normalize_blend_mode(blend)
      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        cam_ox += @offset_x
        cam_oy += @offset_y
        ax1 = (x1.to_f * cz) + cam_ox; ay1 = (y1.to_f * cz) + cam_oy
        ax2 = (x2.to_f * cz) + cam_ox; ay2 = (y2.to_f * cz) + cam_oy
        w = width.to_f * cz
        cur_zoom = cz
      else
        ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
        ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
        w = width.to_f
        cur_zoom = 1.0
      end

      dx = ax2 - ax1
      dy = ay2 - ay1
      len = Math.sqrt(dx * dx + dy * dy)
      return if len <= 0.0001 && w <= 0.0

      cx = (ax1 + ax2) * 0.5
      cy = (ay1 + ay2) * 0.5
      rot_rad = Math.atan2(dy, dx)

      rad = 0.0
      total_len = len
      case cap
      when :round
        rad = w * 0.5
        total_len = len + w
      when :square
        total_len = len + w
      end

      bx = cx - (total_len * 0.5)
      by = cy - (w * 0.5)

      c_color = Backend.normalize_color(actual_color)

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

      mode = 0.0 # 角丸矩形モード (SDF)

      data = [
        bx, by, total_len, w,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        rad, b_width, s_blur, mode,
        b0, b1, b2, b3,
        s0, s1, s2, s3,
        0.0, 0.0, 1.0, 1.0,
        rot_rad, 0.5, 0.5, 0.0
      ].pack("f*")

      Backend.enqueue_draw(
        Backend::Pipelines::CARD,
        data,
        1,
        image: nil,
        shader: card_shader,
        blend: b_mode,
        z: z
      )
    end

    # ----------------------------------------------------
    # 頂点バッファ (Mesh) 描画 API
    # ----------------------------------------------------
    def self.draw_mesh(mesh,
                       z: 0.0,
                       uniforms: nil,
                       shader: nil,
                       image: nil,
                       blend: nil)
      return unless mesh && mesh.data && mesh.count > 0

      eff_pipeline = mesh.pipeline
      eff_image = image || mesh.image
      eff_shader = shader || mesh.shader || eff_pipeline.default_shader
      eff_blend = Backend.normalize_blend_mode(blend || mesh.blend)
      eff_uniforms = if mesh.uniforms && uniforms
                       mesh.uniforms.merge(uniforms)
                     else
                       uniforms || mesh.uniforms
                     end

      Backend.enqueue_draw(
        eff_pipeline,
        mesh.data,
        mesh.count,
        image: eff_image,
        shader: eff_shader,
        uniforms: eff_uniforms,
        blend: eff_blend,
        z: z
      )
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

    # テキスト描画サイズの計算 [width, height] (複数行対応)
    def self.text_size(text, font: nil, size: 24, line_spacing: nil)
      target_font = font || Font.default
      return [0.0, 0.0] unless target_font
      target_font.text_size(text, size, line_spacing: line_spacing)
    end

    # テキスト描画高さの計算 (複数行対応)
    def self.text_height(text, font: nil, size: 24, line_spacing: nil)
      target_font = font || Font.default
      return 0.0 unless target_font
      target_font.text_height(text, size, line_spacing: line_spacing)
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

      cam = @active_camera
      if cam && camera
        cz, cam_ox, cam_oy = cam.view
        base_x = (x.to_f * cz) + cam_ox
        base_y = (y.to_f * cz) + cam_oy
        f_size = size.to_f * cz
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

      vp_scale = Backend.current_target ? 1.0 : Native::Window.scale.to_f
      vp_scale = 1.0 if vp_scale < 1.0
      inv_vp_scale = 1.0 / vp_scale

      pen_x = ((x.to_f + @offset_x) * vp_scale).round * inv_vp_scale
      pen_y = ((y.to_f + @offset_y + ascent) * vp_scale).round * inv_vp_scale

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
          if is_bitmap == true || is_bitmap == 1
            is_bmp = 1.0
            gx = (pen_x * vp_scale).round * inv_vp_scale + x0.to_f
            gy = pen_y + y0.to_f
          else
            is_bmp = 0.0
            gx = (pen_x + x0).to_f
            gy = (pen_y + y0).to_f
          end
          gw = (x1 - x0).to_f
          gh = (y1 - y0).to_f

          batch.push(
            gx, gy, gw, gh,
            cr, cg, cb, ca,
            p0_0, p0_1, p0_2, p0_3,
            p1_0, p1_1, p1_2, p1_3,
            p2_0, p2_1, p2_2, p2_3,
            s_atlas_weight, is_bmp, s_weight, 0.0,
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
      p3 = [s_atlas_weight, 0.0, s_weight, 0.0]
      shader = sdf_font_shader

      metrics = target_font.metrics(f_size)
      ascent = metrics[:ascent]

      vp_scale = Backend.current_target ? 1.0 : Native::Window.scale.to_f
      vp_scale = 1.0 if vp_scale < 1.0
      inv_vp_scale = 1.0 / vp_scale

      pen_x = ((x.to_f + @offset_x) * vp_scale).round * inv_vp_scale
      pen_y = ((y.to_f + @offset_y + ascent) * vp_scale).round * inv_vp_scale

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
          if is_bitmap == true || is_bitmap == 1
            is_bmp = 1.0
            gx = (pen_x * vp_scale).round * inv_vp_scale + x0.to_f
            gy = pen_y + y0.to_f
          else
            is_bmp = 0.0
            gx = (pen_x + x0).to_f
            gy = (pen_y + y0).to_f
          end
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
            cur_p3 = (ctx.weight == s_weight) ? [s_atlas_weight, is_bmp, s_weight, 0.0] : [ctx.weight * scale_ratio, is_bmp, ctx.weight.to_f, 0.0]

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
      cam = camera ? @active_camera : nil
      zoom, cam_ox, cam_oy = cam ? cam.view : [1.0, 0.0, 0.0]
      cam_ox += @offset_x
      cam_oy += @offset_y

      has_transform = (cam_ox != 0.0 || cam_oy != 0.0 || zoom != 1.0)
      if has_transform
        c.save
        c.translate(cam_ox, cam_oy)
        c.scale(zoom, zoom) if zoom != 1.0
      end
      c.begin_path
      yield c
      c.restore if has_transform
    end
  end
end

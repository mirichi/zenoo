module Zenoo
  module Window
    # オフスクリーンFBO描画ターゲットスコープ
    def self.with_target(target, &block)
      Backend.with_target(target, &block)
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
      Backend.flush_screen
      Backend.clear_clips
      @offset_x = 0.0
      @offset_y = 0.0
      Native::Renderer.reset_scissor
    end

    def self.__step_frame
      Native::Window.clear(@bg_color)
      __update_step
      __draw_step
    end

    def self.time
      Native::Window.time
    end

    def self.clear(color)
      @bg_color = Backend.color_to_uint32(color)
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

    @offset_x = 0.0
    @offset_y = 0.0

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
      c_color = Backend.normalize_color(color)
      b_width = border_width.to_f
      b_color = (b_width > 0.0) ? Backend.normalize_color(border_color) : [0.0, 0.0, 0.0, 0.0]

      s_blur = shadow_blur.to_f
      s_color = (s_blur > 0.0) ? Backend.normalize_color(shadow_color) : [0.0, 0.0, 0.0, 0.0]

      ax = x.to_f + @offset_x
      ay = y.to_f + @offset_y

      mode = image ? 1.0 : 0.0
      data = [
        ax, ay, w.to_f, h.to_f,
        c_color[0].to_f, c_color[1].to_f, c_color[2].to_f, c_color[3].to_f,
        radius.to_f, b_width, s_blur, mode,
        b_color[0].to_f, b_color[1].to_f, b_color[2].to_f, b_color[3].to_f,
        s_color[0].to_f, s_color[1].to_f, s_color[2].to_f, s_color[3].to_f,
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
                        src_rect: nil,
                        z: 0.0)
      return unless image
      effective_shader = shader || @current_shader || default_sprite_shader

      # 第4引数 color_or_opt が指定され、かつキーワード color: がない場合
      actual_color = color || color_or_opt || :white
      c_color = Backend.normalize_color(actual_color)

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
      b_mode = Backend.normalize_blend_mode(blend)

      ax = x.to_f + @offset_x
      ay = y.to_f + @offset_y

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
        blend: b_mode,
        z: z
      )
    end


    def self.draw_triangle(x1, y1, x2, y2, x3, y3, color = :white, z: 0.0)
      ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
      ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y
      ax3 = x3.to_f + @offset_x; ay3 = y3.to_f + @offset_y

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

    def self.draw_line(x1, y1, x2, y2, color = :white, z: 0.0)
      ax1 = x1.to_f + @offset_x; ay1 = y1.to_f + @offset_y
      ax2 = x2.to_f + @offset_x; ay2 = y2.to_f + @offset_y

      if color.is_a?(Array) && color.length == 2 && (color[0].is_a?(Color) || color[0].is_a?(Symbol) || color[0].is_a?(Array))
        # 始点・終点の色指定 [c1, c2]
        c1 = Backend.normalize_color(color[0])
        c2 = Backend.normalize_color(color[1])
        data = [
          ax1, ay1, c1[0].to_f, c1[1].to_f, c1[2].to_f, c1[3].to_f,
          ax2, ay2, c2[0].to_f, c2[1].to_f, c2[2].to_f, c2[3].to_f
        ].pack("f*")
      else
        c = Backend.normalize_color(color)
        cr = c[0].to_f; cg = c[1].to_f; cb = c[2].to_f; ca = c[3].to_f
        data = [
          ax1, ay1, cr, cg, cb, ca,
          ax2, ay2, cr, cg, cb, ca
        ].pack("f*")
      end

      Backend.enqueue_draw(
        Backend::Pipelines::LINES,
        data,
        2,
        shader: flat_primitive_shader,
        z: z
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

    # テキスト描画幅の計算
    def self.text_width(text, font: nil, size: 24)
      target_font = font || Font.default
      return 0.0 unless target_font
      target_font.text_width(text, size)
    end

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
      s_c = (s_blur > 0.0 || s_dx != 0.0 || s_dy != 0.0) ? Backend.normalize_color(shadow_color) : [0.0, 0.0, 0.0, 0.0]

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

      pen_x = (x.to_f + @offset_x).round
      pen_y = (y.to_f + @offset_y + ascent).round.to_f

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
            gx = (pen_x + x0).round
            gy = (pen_y + y0).round
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
      else
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

    def self.draw_path
      c = canvas
      has_offset = (@offset_x != 0.0 || @offset_y != 0.0)
      if has_offset
        c.save
        c.translate(@offset_x, @offset_y)
      end
      c.begin_path
      yield c
    ensure
      c.restore if has_offset
    end
  end
end

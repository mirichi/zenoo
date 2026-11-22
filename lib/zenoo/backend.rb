# frozen_string_literal: true

module Zenoo
  # 描画時のカラー合成モード定数（C バックエンドに渡される整数値）
  module BlendMode
    ALPHA    = 0 # 通常アルファブレンド（SrcAlpha, OneMinusSrcAlpha）
    ADD      = 1 # 加算ブレンド（発光・エフェクト向け）
    MULTIPLY = 2 # 乗算ブレンド（影・減算表現向け）
    NONE     = 3 # ブレンド無効（アルファを含めそのまま上書き）
  end

  # Zenoo 内部パイプライン・レンダリングバックエンド (C 実装 `src/zenoo_batch.c` ラッパー)
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
    # ※ 各バイトが 1 つの頂点属性（attribute）の float 要素数（1..4）を表す
    # ----------------------------------------------------
    module Layout
      POS2_COLOR4         = "\x02\x04"                     # 頂点: (x, y), (r, g, b, a)
      POS2_UV2_COLOR4     = "\x02\x02\x04"                 # 頂点: (x, y), (u, v), (r, g, b, a)
      POS2_UV2_ALPHA1     = "\x02\x02\x04"                 # 頂点: (x, y), (u, v), (color4)
      LINE                = "\x02\x04"                     # 線分頂点: (x, y), (r, g, b, a)
      CARD_INSTANCED      = "\x04\x04\x04\x04\x04\x04\x04" # SDFカード用インスタンス属性 (vec4 x 7)
      QUAD_INSTANCED      = CARD_INSTANCED                 # 汎用インスタンス化矩形 (CARD_INSTANCED と共通)
      SPRITE_INSTANCED    = "\x04\x04\x04\x04"             # スプライトバッチ用インスタンス属性 (vec4 x 4)
      FONT_INSTANCED      = "\x04\x04\x04\x04\x04\x04\x04" # SDFフォント用インスタンス属性 (vec4 x 7)
    end

    # ----------------------------------------------------
    # 動的属性 Divisor
    # ※ 各バイトが対応する頂点属性の glVertexAttribDivisor 値（0: 頂点ごと / 1: インスタンスごと）を表す
    # ----------------------------------------------------
    module Divisor
      DIRECT              = "\x00\x00"
      POS2_COLOR4         = "\x00\x00"
      POS2_UV2_COLOR4     = "\x00\x00\x00"
      POS2_UV2_ALPHA1     = "\x00\x00\x00"
      LINE                = "\x00\x00"
      CARD_INSTANCED      = "\x01\x01\x01\x01\x01\x01\x01"
      QUAD_INSTANCED      = CARD_INSTANCED
      SPRITE_INSTANCED    = "\x01\x01\x01\x01"
      FONT_INSTANCED      = "\x01\x01\x01\x01\x01\x01\x01"
    end

    # ----------------------------------------------------
    # 描画パイプライン定義 (トポロジー・レイアウト・Divisor・頂点数を集約)
    # ----------------------------------------------------
    class Pipeline
      attr_reader :id, :topology, :layout, :divisors, :base_vertex_count, :default_shader

      # パイプライン定義を初期化する
      #
      # - `topology` (`Integer`): `Topology` 定数（`TRIANGLES`, `TRIANGLE_STRIP`, `LINES` 等）
      # - `layout` (`String`): `Layout` の 1 バイト属性長列
      # - `divisors` (`String`): `Divisor` の属性 Divisor 列
      # - `base_vertex_count` (`Integer`): インスタンス描画時の 1 インスタンスあたり頂点数（非インスタンス時は `0`）
      # - `default_shader` (`NativeShader | nil`): シェーダー未指定時に使われる既定シェーダー
      # - `id` (`Integer | nil`): C 側組み込みパイプライン ID（カスタム時は自動登録）
      # - 戻り値: `Pipeline`
      def initialize(topology, layout, divisors, base_vertex_count, default_shader = nil, id = nil)
        @topology = topology
        @layout = layout
        @divisors = divisors
        @base_vertex_count = base_vertex_count
        @default_shader = default_shader
        @id = id || Native::C.zen_batch_register_pipeline(
          topology.to_i,
          layout.to_s,
          layout.to_s.bytesize,
          divisors.to_s,
          divisors.to_s.bytesize,
          base_vertex_count.to_i,
          default_shader ? default_shader.__ptr : nil
        )
      end

      def default_shader=(sh)
        @default_shader = sh
        Native::C.zen_batch_set_pipeline_default_shader(@id, sh ? sh.__ptr : nil)
      end
    end

    # エンジン標準の描画パイプライン定義集 (C enum ZenPipelineId 0..8 と 1:1 対応)
    module Pipelines
      CARD                    = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::CARD_INSTANCED, Divisor::CARD_INSTANCED, 4, nil, 0)
      SPRITE                  = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::SPRITE_INSTANCED, Divisor::SPRITE_INSTANCED, 4, nil, 1)
      FONT                    = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::FONT_INSTANCED, Divisor::FONT_INSTANCED, 4, nil, 2)
      TRIANGLES               = Pipeline.new(Topology::TRIANGLES, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0, nil, 3)
      TRIANGLE_STRIP          = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0, nil, 4)
      LINES                   = Pipeline.new(Topology::LINES, Layout::LINE, Divisor::LINE, 0, nil, 5)
      POINTS                  = Pipeline.new(Topology::POINTS, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0, nil, 6)
      TEXTURED_TRIANGLES      = Pipeline.new(Topology::TRIANGLES, Layout::POS2_UV2_COLOR4, Divisor::POS2_UV2_COLOR4, 0, nil, 7)
      TEXTURED_TRIANGLE_STRIP = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::POS2_UV2_COLOR4, Divisor::POS2_UV2_COLOR4, 0, nil, 8)
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

    # シンボルまたは整数のブレンド指定を `Zenoo::BlendMode` の整数定数へ正規化する
    #
    # - `mode` (`Symbol | Integer | nil`): `:alpha`, `:add`, `:multiply`, `:none`、または整数値（`nil` は `:alpha`）
    # - 戻り値: `Integer`
    def self.normalize_blend_mode(mode)
      return Zenoo::BlendMode::ALPHA if mode.nil?
      return BLEND_MAP[mode] if BLEND_MAP.key?(mode)
      mode.to_i
    end

    # ----------------------------------------------------
    # カラーマップと色変換
    # ----------------------------------------------------
    WHITE_F4 = [1.0, 1.0, 1.0, 1.0].freeze
    CLEAR_F4 = [0.0, 0.0, 0.0, 0.0].freeze

    COLOR_MAP = {
      white:   WHITE_F4,
      black:   [0.0, 0.0, 0.0, 1.0].freeze,
      red:     [1.0, 0.2, 0.2, 1.0].freeze,
      green:   [0.2, 1.0, 0.3, 1.0].freeze,
      blue:    [0.1, 0.5, 1.0, 1.0].freeze,
      cyan:    [0.0, 0.9, 1.0, 1.0].freeze,
      magenta: [1.0, 0.2, 0.8, 1.0].freeze,
      yellow:  [1.0, 0.9, 0.1, 1.0].freeze,
      clear:   CLEAR_F4
    }.freeze

    # 各種色指定（シンボル・`Color`・`0..255` 配列・16進文字列・整数）をシェーダー送出用の正規化 Float 配列 `[r, g, b, a]`（`0.0..1.0`）へ変換する
    #
    # - `col` (`Color | Symbol | Array<Numeric> | String | Integer | nil`): ユーザー指定の色（配列の各要素は `0..255` 基準、`nil` は透明黒）
    # - 戻り値: `Array<Float>`（`[r, g, b, a]`、各要素 `0.0..1.0`）
    def self.normalize_color(col)
      return CLEAR_F4 if col.nil?
      return COLOR_MAP[col] if COLOR_MAP.key?(col)

      if col.is_a?(Color)
        col.to_f4
      elsif col.is_a?(Array)
        len = col.length
        r = len > 0 ? col[0].to_f : 0.0
        g = len > 1 ? col[1].to_f : 0.0
        b = len > 2 ? col[2].to_f : 0.0
        a = len > 3 ? col[3].to_f : 255.0
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
        WHITE_F4
      end
    end

    # 色指定を `Native::Window.clear` 等が受け取る 32bit RGBA 整数（`0xRRGGBBAA`）に変換する
    #
    # - `col` (`Color | Symbol | Array<Numeric> | String | Integer | nil`): 色指定
    # - 戻り値: `Integer`（符号付き 32bit 整数として表現した RGBA 値）
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
      val = ((r & 0x7F) << 24) | (g << 16) | (b << 8) | a
      (r >= 128) ? (val | -2147483648) : val
    end

    # ----------------------------------------------------
    # C 描画キュー用 Ruby 側互換ビュー (Scene / Dev が利用)
    # ----------------------------------------------------
    class DrawQueueView
      def initialize(screen)
        @screen = screen
      end

      def queue_count
        @screen ? Native::C.zen_batch_screen_queue_count : Native::C.zen_batch_active_queue_count
      end

      def clear_color
        @screen ? Backend.screen_clear_color : nil
      end

      def sort
        Native::C.zen_batch_sort_screen_queue if @screen
        nil
      end

      def flush
        bg = Backend.color_to_uint32(Zenoo::Window.bg_color || :black) & 0xFFFFFFFF
        if @screen
          Native::C.zen_batch_flush_screen(bg)
        else
          Native::C.zen_batch_flush_active(bg)
        end
        nil
      end
    end

    # ----------------------------------------------------
    # 描画スナップショット (Scene / Dev ポーズ用 C バッファラッパー)
    # ----------------------------------------------------
    class DrawSnapshot
      def initialize
        ptr = Native::C.zen_snapshot_create
        raise RuntimeError, "Failed to create ZenSnapshot" unless ptr

        @ptr = ptr
        @box = [ptr]
        @refs = nil
        Native.install_finalizer(self, @box, Native::KIND_SNAPSHOT)
      end

      def count
        Native::C.zen_snapshot_count(@ptr)
      end

      def empty?
        Native::C.zen_snapshot_count(@ptr) == 0
      end

      def capture(_queue, from = 0)
        Native::C.zen_snapshot_capture_active(@ptr, from.to_i)
        @refs = Backend.retained_refs_copy
        count
      end

      def capture_screen
        Native::C.zen_snapshot_capture_screen(@ptr)
        @refs = Backend.retained_refs_copy
        count
      end

      def replay
        return if count == 0

        Backend.retain_refs(@refs) if @refs
        Native::C.zen_snapshot_replay_to_active(@ptr)
      end

      def execute_direct
        return if count == 0

        Native::C.zen_snapshot_execute_direct(@ptr)
      end

      def clear
        @refs = nil
        Native::C.zen_snapshot_clear(@ptr)
        0
      end
    end

    # ----------------------------------------------------
    # バックエンド状態管理 (GC 保護 & ターゲット・クリップ追跡)
    # ----------------------------------------------------
    @screen_queue = DrawQueueView.new(true)
    @active_queue = DrawQueueView.new(false)
    @current_target = nil
    @active_gl_target = nil
    @clip_rects = []
    @target_stack = []
    @retained_refs = []
    @last_retained_target = nil
    @last_retained_image = nil
    @last_retained_shader = nil
    @last_retained_mesh = nil
    @screen_clear_color = nil

    def self.screen_clear_color
      @screen_clear_color
    end

    def self.retained_refs_copy
      @retained_refs.dup
    end

    def self.retain_refs(refs)
      @retained_refs.concat(refs) unless refs.empty?
    end

    def self.current_clip
      @clip_rects.last
    end

    def self.push_clip(rect, z = 0.0)
      r = [rect[0].to_f, rect[1].to_f, rect[2].to_f, rect[3].to_f]
      @clip_rects.push(r)
      Native::C.zen_batch_push_clip(r[0], r[1], r[2], r[3], z.to_f)
      @clip_rects
    end

    def self.pop_clip
      popped = @clip_rects.pop
      Native::C.zen_batch_pop_clip if popped
      @clip_rects
    end

    def self.clear_clips
      @clip_rects.clear
      Native::C.zen_batch_clear_clips
      nil
    end

    def self.active_queue
      @active_queue
    end

    def self.screen_queue
      @screen_queue
    end

    def self.reset_frame
      @screen_clear_color = nil
      @last_retained_target = nil
      @last_retained_image = nil
      @last_retained_shader = nil
      @last_retained_mesh = nil
      @clip_rects.clear
      @target_stack.clear
      @current_target = nil
      Native::C.zen_batch_reset_frame
      false
    end

    def self.mark_screen_cleared
      Native::C.zen_batch_mark_screen_cleared
      true
    end

    def self.current_target
      @current_target
    end

    def self.current_target=(target)
      @current_target = target
      Native::C.zen_batch_set_current_target(target ? target.__ptr : nil)
      target
    end

    def self.push_target(target)
      @target_stack.push([@current_target, @clip_rects])
      @current_target = target
      @clip_rects = []
      Native::C.zen_batch_push_target(target ? target.__ptr : nil)
      target
    end

    def self.pop_target
      prev = @target_stack.pop
      if prev
        @current_target = prev[0]
        @clip_rects = prev[1]
      else
        @current_target = nil
        @clip_rects = []
      end
      Native::C.zen_batch_pop_target
      @current_target
    end

    def self.active_gl_target
      @active_gl_target
    end

    def self.active_gl_target=(target)
      @active_gl_target = target
      Native::C.zen_batch_set_active_gl_target(target ? target.__ptr : nil)
      target
    end

    def self.with_target(target)
      push_target(target)
      yield
      pop_target
    end

    def self.has_pending_draws?(image)
      return false unless image

      Native::C.zen_batch_has_pending_draws(image.__ptr) != 0
    end

    def self.flush_image(image)
      return nil unless image

      Native::C.zen_batch_flush_image(image.__ptr)
      nil
    end

    def self.flush_pending_images
      Native::C.zen_batch_flush_pending_images
      nil
    end

    def self.stage_uniforms(uniforms)
      return unless uniforms && !uniforms.empty?

      c = Native::C
      c.zen_batch_begin_uniforms
      uniforms.each do |k, v|
        name = k.to_s
        case v
        when Zenoo::Image
          @retained_refs << v
          c.zen_batch_uniform_texture(name, v.__ptr)
        when Integer
          c.zen_batch_uniform_int(name, v)
        when Float
          c.zen_batch_uniform_float(name, v)
        when String
          cnt = v.bytesize / 16
          c.zen_batch_uniform_vec4_array(name, cnt, v) if cnt > 0
        when Array
          len = v.length
          if len == 2
            c.zen_batch_uniform_vec2(name, v[0].to_f, v[1].to_f)
          elsif len == 3
            c.zen_batch_uniform_vec3(name, v[0].to_f, v[1].to_f, v[2].to_f)
          elsif len == 4
            c.zen_batch_uniform_vec4(name, v[0].to_f, v[1].to_f, v[2].to_f, v[3].to_f)
          elsif len == 16
            c.zen_batch_uniform_mat4(name, v.pack("f*"))
          elsif len >= 8 && (len % 4).zero?
            c.zen_batch_uniform_vec4_array(name, len / 4, v.pack("f*"))
          end
        end
      end
    end

    # 直接 Ruby からシェーダーへ uniform をバインドする互換ヘルパー
    def self.apply_uniforms(shader, uniforms)
      return unless uniforms && shader

      tex_unit = 1
      uniforms.each do |k, v|
        name = k.to_s
        case v
        when Zenoo::Image
          flush_image(v) if has_pending_draws?(v)
          shader.set_texture(name, tex_unit, v) if tex_unit <= 15
          tex_unit += 1
        when Integer
          shader.set_int(name, v)
        when Float
          shader.set_float(name, v)
        when String
          shader.set_vec4_array(name, v)
        when Array
          case v.length
          when 2 then shader.set_vec2(name, v[0].to_f, v[1].to_f)
          when 3 then shader.set_vec3(name, v[0].to_f, v[1].to_f, v[2].to_f)
          when 4 then shader.set_vec4(name, v[0].to_f, v[1].to_f, v[2].to_f, v[3].to_f)
          when 16 then shader.set_mat4(name, v)
          else
            shader.set_vec4_array(name, v) if v.length >= 8 && (v.length % 4).zero?
          end
        end
      end
    end

    # 汎用描画コマンドエンキュー (Particle / Canvas / Tilemap / Mesh 等から利用)
    def self.enqueue_draw(pipeline, data, count, image: nil, shader: nil, uniforms: nil, blend: 0, z: 0.0, mesh: nil, inst_buffer: nil)
      @retained_refs << @current_target if @current_target
      @retained_refs << image if image
      @retained_refs << shader if shader
      @retained_refs << mesh if mesh
      @retained_refs << inst_buffer if inst_buffer
      stage_uniforms(uniforms) if uniforms

      data_str = data ? data.to_s : ""
      Native::C.zen_batch_enqueue_draw(
        pipeline.id,
        data_str,
        data_str.bytesize,
        count.to_i,
        image ? image.__ptr : nil,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f,
        mesh ? mesh.__ptr : nil,
        inst_buffer ? inst_buffer.__ptr : nil
      )
      nil
    end

    # ----------------------------------------------------
    # ホットパス直接エンキュー群 (Window.draw_* 用・pack 不要)
    # ----------------------------------------------------
    def self.enqueue_flat_rect(x1, y1, x2, y2, r, g, b, a, shader, blend, z)
      @retained_refs << @current_target if @current_target
      @retained_refs << shader if shader
      Native::C.zen_batch_enqueue_flat_rect(
        x1, y1, x2, y2, r, g, b, a,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f
      )
      nil
    end

    def self.stage_card_colors(cr, cg, cb, ca, br, bg, bb, ba, sr, sg, sb, sa)
      Native::C.zen_batch_stage_card_colors(cr, cg, cb, ca, br, bg, bb, ba, sr, sg, sb, sa)
    end

    def self.stage_card_params(rad, b_width, s_blur, mode, uv0, uv1, uv2, uv3, rot_rad, pv_x, pv_y)
      Native::C.zen_batch_stage_card_params(rad, b_width, s_blur, mode, uv0, uv1, uv2, uv3, rot_rad, pv_x, pv_y)
    end

    def self.enqueue_sdf_card(x, y, w, h, image, shader, blend, z)
      @retained_refs << @current_target if @current_target
      @retained_refs << image if image
      @retained_refs << shader if shader
      Native::C.zen_batch_enqueue_sdf_card(
        x, y, w, h,
        image ? image.__ptr : nil,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f
      )
      nil
    end

    def self.stage_color(c0, c1, c2, c3)
      Native::C.zen_batch_stage_color(c0, c1, c2, c3)
    end

    def self.enqueue_sprite(m00, m01, m10, m11, tx, ty, image, shader, uniforms, blend, z, mesh)
      if @current_target && !@last_retained_target.equal?(@current_target)
        @last_retained_target = @current_target
        @retained_refs << @current_target
      end
      if image && !@last_retained_image.equal?(image)
        @last_retained_image = image
        @retained_refs << image
      end
      if shader && !@last_retained_shader.equal?(shader)
        @last_retained_shader = shader
        @retained_refs << shader
      end
      if mesh && !@last_retained_mesh.equal?(mesh)
        @last_retained_mesh = mesh
        @retained_refs << mesh
      end
      stage_uniforms(uniforms) if uniforms
      Native::C.zen_batch_enqueue_sprite(
        m00, m01, m10, m11, tx, ty,
        image ? image.__ptr : nil,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f,
        mesh ? mesh.__ptr : nil
      )
      nil
    end

    def self.enqueue_triangle_flat(x1, y1, x2, y2, x3, y3, r, g, b, a, shader, blend, z)
      @retained_refs << @current_target if @current_target
      @retained_refs << shader if shader
      Native::C.zen_batch_enqueue_triangle_flat(
        x1, y1, x2, y2, x3, y3, r, g, b, a,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f
      )
      nil
    end

    def self.stage_tri_colors(r1, g1, b1, a1, r2, g2, b2, a2, r3, g3, b3, a3)
      Native::C.zen_batch_stage_tri_colors(r1, g1, b1, a1, r2, g2, b2, a2, r3, g3, b3, a3)
    end

    def self.enqueue_triangle_grad(x1, y1, x2, y2, x3, y3, shader, blend, z)
      @retained_refs << @current_target if @current_target
      @retained_refs << shader if shader
      Native::C.zen_batch_enqueue_triangle_grad(
        x1, y1, x2, y2, x3, y3,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f
      )
      nil
    end

    # テキスト描画用高速ステージング API
    def self.begin_text
      Native::C.zen_batch_begin_text
    end

    def self.set_text_color_outline(cr, cg, cb, ca, p0_0, p0_1, p0_2, p0_3, p1_0, p1_1, p1_2, p1_3)
      Native::C.zen_batch_set_text_color_outline(cr, cg, cb, ca, p0_0, p0_1, p0_2, p0_3, p1_0, p1_1, p1_2, p1_3)
    end

    def self.set_text_shadow_weight(p2_0, p2_1, p2_2, p2_3, weight)
      Native::C.zen_batch_set_text_shadow_weight(p2_0, p2_1, p2_2, p2_3, weight)
    end

    def self.stage_text_line(native_font, utf8_text, pen_x, pen_y, f_size, mode, vp_scale, inv_vp_scale)
      @retained_refs << native_font if native_font
      Native::C.zen_batch_stage_text_line(
        native_font ? native_font.__ptr : nil,
        utf8_text,
        pen_x, pen_y, f_size, mode, vp_scale, inv_vp_scale
      )
    end

    def self.set_glyph_override(cr, cg, cb, ca, out_w, ocr, ocg, ocb, oca, weight)
      Native::C.zen_batch_set_glyph_override(cr, cg, cb, ca, out_w, ocr, ocg, ocb, oca, weight)
    end

    def self.stage_glyph(gx, gy, gw, gh, is_bmp, u0, v0, uw, vh, has_override)
      Native::C.zen_batch_stage_glyph(gx, gy, gw, gh, is_bmp, u0, v0, uw, vh, has_override)
    end

    def self.staged_glyph_count
      Native::C.zen_batch_staged_glyph_count
    end

    def self.commit_text(atlas_image, shader, blend, z)
      @retained_refs << @current_target if @current_target
      @retained_refs << atlas_image if atlas_image
      @retained_refs << shader if shader
      Native::C.zen_batch_commit_text(
        atlas_image ? atlas_image.__ptr : nil,
        shader ? shader.__ptr : nil,
        blend.to_i,
        z.to_f
      )
      nil
    end

    def self.enqueue_clear(color = nil)
      if @current_target
        if @current_target.sub_image?
          actual_color = color || :clear
          c4 = normalize_color(actual_color)
          blend_mode = c4[3] <= 0.0001 ? :none : :alpha
          Zenoo::Window.draw_rect(
            0.0, 0.0, @current_target.width, @current_target.height,
            color: actual_color,
            blend: blend_mode,
            z: -Float::INFINITY
          )
        else
          @retained_refs << @current_target
          Native::C.zen_batch_set_clear(color_to_uint32(color || :clear) & 0xFFFFFFFF)
        end
      else
        actual = color || Zenoo::Window.bg_color
        @screen_clear_color = actual
        Zenoo::Window.bg_color = actual
        Native::C.zen_batch_set_clear(color_to_uint32(actual) & 0xFFFFFFFF)
      end
    end

    def self.flush_screen
      bg = color_to_uint32(Zenoo::Window.bg_color || :black) & 0xFFFFFFFF
      Native::C.zen_batch_flush_screen(bg)
      $last_draw_calls = Native::C.zen_batch_last_draw_calls
      @retained_refs.clear
      @last_retained_target = nil
      @last_retained_image = nil
      @last_retained_shader = nil
      @last_retained_mesh = nil
      nil
    end
  end
end

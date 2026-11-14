# frozen_string_literal: true

module Zenoo
  # 描画時のカラー合成モード定数（C バックエンドに渡される整数値）
  module BlendMode
    ALPHA    = 0 # 通常アルファブレンド（SrcAlpha, OneMinusSrcAlpha）
    ADD      = 1 # 加算ブレンド（発光・エフェクト向け）
    MULTIPLY = 2 # 乗算ブレンド（影・減算表現向け）
    NONE     = 3 # ブレンド無効（アルファを含めそのまま上書き）
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
    # ※ 各バイトが 1 つの頂点属性（attribute）の float 要素数（1..4）を表す
    # ----------------------------------------------------
    module Layout
      POS2_COLOR4         = "\x02\x04"                 # 頂点: (x, y), (r, g, b, a)
      POS2_UV2_COLOR4     = "\x02\x02\x04"             # 頂点: (x, y), (u, v), (r, g, b, a)
      POS2_UV2_ALPHA1     = "\x02\x02\x04"             # 頂点: (x, y), (u, v), (color4)
      LINE                = "\x02\x04"                 # 線分頂点: (x, y), (r, g, b, a)
      CARD_INSTANCED      = "\x04\x04\x04\x04\x04\x04\x04" # SDFカード用インスタンス属性 (vec4 x 7)
      QUAD_INSTANCED      = CARD_INSTANCED             # 汎用インスタンス化矩形 (CARD_INSTANCED と共通)
      SPRITE_INSTANCED    = "\x04\x04\x04\x04"         # スプライトバッチ用インスタンス属性 (vec4 x 4)
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
      attr_reader :topology, :layout, :divisors, :base_vertex_count, :default_shader

      # パイプライン定義を初期化する
      #
      # - `topology` (`Integer`): `Topology` 定数（`TRIANGLES`, `TRIANGLE_STRIP`, `LINES` 等）
      # - `layout` (`String`): `Layout` の 1 バイト属性長列
      # - `divisors` (`String`): `Divisor` の属性 Divisor 列
      # - `base_vertex_count` (`Integer`): インスタンス描画時の 1 インスタンスあたり頂点数（非インスタンス時は `0`）
      # - `default_shader` (`NativeShader | nil`): シェーダー未指定時に使われる既定シェーダー（起動後に `DefaultShaders` から設定される）
      # - 戻り値: `Pipeline`
      def initialize(topology, layout, divisors, base_vertex_count, default_shader = nil)
        @topology = topology
        @layout = layout
        @divisors = divisors
        @base_vertex_count = base_vertex_count
        @default_shader = default_shader
      end
    end

    # エンジン標準の描画パイプライン定義集
    module Pipelines
      CARD                    = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::CARD_INSTANCED, Divisor::CARD_INSTANCED, 4)         # 角丸・枠線・影付きカード矩形 (SDF)
      SPRITE                  = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::SPRITE_INSTANCED, Divisor::SPRITE_INSTANCED, 4)     # テクスチャ付きスプライト / 画像描画
      FONT                    = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::FONT_INSTANCED, Divisor::FONT_INSTANCED, 4)         # MSDF/ビットマップテキスト文字描画
      TRIANGLES               = Pipeline.new(Topology::TRIANGLES, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0)                    # 単色三角形リスト
      TRIANGLE_STRIP          = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0)               # 単色三角形ストリップ
      LINES                   = Pipeline.new(Topology::LINES, Layout::LINE, Divisor::LINE, 0)                                      # 線分リスト
      POINTS                  = Pipeline.new(Topology::POINTS, Layout::POS2_COLOR4, Divisor::POS2_COLOR4, 0)                       # 点リスト
      TEXTURED_TRIANGLES      = Pipeline.new(Topology::TRIANGLES, Layout::POS2_UV2_COLOR4, Divisor::POS2_UV2_COLOR4, 0)            # テクスチャ + 頂点カラー三角形リスト
      TEXTURED_TRIANGLE_STRIP = Pipeline.new(Topology::TRIANGLE_STRIP, Layout::POS2_UV2_COLOR4, Divisor::POS2_UV2_COLOR4, 0)       # テクスチャ + 頂点カラー三角形ストリップ
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

    # 各種色指定（シンボル・`Color`・`0..255` 配列・16進文字列・整数）をシェーダー送出用の正規化 Float 配列 `[r, g, b, a]`（`0.0..1.0`）へ変換する
    #
    # - `col` (`Color | Symbol | Array<Numeric> | String | Integer | nil`): ユーザー指定の色（配列の各要素は `0..255` 基準、`nil` は透明黒）
    # - 戻り値: `Array<Float>`（`[r, g, b, a]`、各要素 `0.0..1.0`）
    def self.normalize_color(col)
      return [0.0, 0.0, 0.0, 0.0] if col.nil?
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
    # 描画コマンド
    # 1 回の描画要求（頂点・インスタンス・テクスチャ・シェーダー・クリップ等）を保持し、
    # DrawQueue のプール内で GC アロケーションを避けて再利用される
    # ----------------------------------------------------
    class DrawCommand
      attr_accessor :target, :z, :order, :pipeline, :data, :count, :image, :shader, :uniforms, :blend, :clip, :mesh, :inst_buffer

      # 空の描画コマンドスロットを初期化する
      #
      # - 戻り値: `DrawCommand`
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
        @mesh = nil
        @inst_buffer = nil
      end

      # 再利用中のコマンドスロットに描画パラメータを設定する
      #
      # - `target` (`Image | nil`): 描画先レンダーターゲット（画面なら `nil`）
      # - `z` (`Float`): 描画深度（小さいほど奥、大きいほど手前）
      # - `order` (`Integer`): 登録順インデックス（同一 Z での安定ソート用）
      # - `pipeline` (`Pipeline`): 使用する `Pipelines` 定数
      # - `data` (`String | nil`): パック済み頂点／インスタンスバイナリデータ
      # - `count` (`Integer`): 頂点数またはインスタンス数
      # - `image` (`Image | nil`): バインドするテクスチャ画像
      # - `shader` (`NativeShader | nil`): カスタムシェーダー（`nil` でパイプライン既定値）
      # - `uniforms` (`Hash | nil`): シェーダーへ転送するユニフォーム変数ハッシュ
      # - `blend` (`Integer`): `BlendMode` の整数値
      # - `clip` (`Array<Numeric> | nil`): シザー矩形 `[x, y, w, h]`（デバイス／スクリーン座標系）
      # - `mesh` (`Native::Mesh | nil`): VRAM 常駐ジオメトリメッシュ
      # - `inst_buffer` (`Native::Mesh | nil`): VRAM 常駐インスタンスバッファ
      # - 戻り値: `Native::Mesh | nil`
      def set(target, z, order, pipeline, data, count, image = nil, shader = nil, uniforms = nil, blend = 0, clip = nil, mesh = nil, inst_buffer = nil)
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
        @mesh = mesh
        @inst_buffer = inst_buffer
      end
    end

    # ----------------------------------------------------
    # 描画キュー管理クラス (画面用・各Image用で共通)
    # ----------------------------------------------------
    class DrawQueue
      attr_reader :command_pool, :queue_count, :owner, :clear_color
      attr_accessor :needs_z_sort, :auto_clear

      # 描画キューを初期化する
      #
      # - `owner` (`Image | nil`): 描画先 `Image`（画面キューの場合は `nil`）
      # - 戻り値: `DrawQueue`
      def initialize(owner = nil)
        @owner = owner # nil なら画面、Image ならその Image
        @command_pool = []
        @queue_count = 0
        @needs_z_sort = false
        @is_flushing = false
        @auto_clear = (owner == nil)
        @clear_color = nil
        @cleared_this_frame = false
      end

      # 画面キュー用: フレーム開始時にクリア状態をリセットする
      #
      # - 戻り値: `false`
      def reset_frame
        @cleared_this_frame = false
      end

      # 画面キュー用: リプレイや外部フラッシュで画面クリアが行われたことを記録する
      #
      # - 戻り値: `true`
      def mark_cleared
        @cleared_this_frame = true
      end

      # 次回フラッシュ時に適用するクリア色を設定する
      #
      # - `color` (`Color | Symbol | Array<Numeric> | String | Integer | nil`): クリア色
      # - 戻り値: `Color | Symbol | Array<Numeric> | String | Integer | nil`
      def set_clear(color)
        @clear_color = color
      end

      # 未実行の描画コマンド・クリア予約・自動クリア待ちが残っているかを返す
      #
      # - 戻り値: `Boolean`
      def has_pending_draws?
        @queue_count > 0 || !@clear_color.nil? || (@auto_clear && !@cleared_this_frame)
      end

      # コマンドプールから次の空き `DrawCommand` を取得または確保する
      #
      # - 戻り値: `DrawCommand`
      def allocate_command
        if @queue_count < @command_pool.length
          @command_pool[@queue_count]
        else
          cmd = DrawCommand.new
          @command_pool.push(cmd)
          cmd
        end
      end

      # キュー内の有効コマンド数を 1 増やす（`allocate_command` 後に直接 `set` した場合に使用）
      #
      # - 戻り値: `Integer`
      def increment_count
        @queue_count += 1
      end

      # 描画コマンドをこのキューの末尾へ積む
      #
      # - `pipeline` (`Pipeline`): 使用する `Pipelines` 定数
      # - `data` (`String | nil`): パック済み頂点／インスタンスデータ
      # - `count` (`Integer`): 頂点数またはインスタンス数
      # - `image` (`Image | nil`): テクスチャ画像
      # - `shader` (`NativeShader | nil`): カスタムシェーダー
      # - `uniforms` (`Hash | nil`): ユニフォーム変数
      # - `blend` (`Integer`): `BlendMode` 定数値
      # - `z` (`Float`): Z 描画順（非 `0.0` を含む場合のみ Z ソートを有効化）
      # - `mesh` (`Native::Mesh | nil`): VRAM メッシュ
      # - `inst_buffer` (`Native::Mesh | nil`): VRAM インスタンスバッファ
      # - 戻り値: `Integer`
      def enqueue(pipeline, data, count, image: nil, shader: nil, uniforms: nil, blend: 0, z: 0.0, mesh: nil, inst_buffer: nil)
        cmd = allocate_command
        zf = z.to_f
        @needs_z_sort = true if zf != 0.0
        clip = Backend.current_clip
        cmd.set(@owner, zf, @queue_count, pipeline, data, count, image, shader, uniforms, blend, clip, mesh, inst_buffer)
        @queue_count += 1
      end

      # サブキュー（クリップ用）の内容をローカル Z 順でソートし、親キューへ指定 Z で一括転送する
      #
      # - `parent_queue` (`DrawQueue`): 転送先の親キュー
      # - `target_z` (`Float`): 親キュー上での統一 Z 値
      # - 戻り値: `false | nil`
      def transfer_to(parent_queue, target_z)
        return if @queue_count == 0

        # 1. クリップ内部のコマンド群をローカル Z 順に安定ソート
        sort

        target_zf = target_z.to_f
        parent_queue.needs_z_sort = true if target_zf != 0.0

        # 2. ソートされた順序を保ったまま親キューへ転送
        # (親キューでの z は target_zf に統一され、内部の前後関係は親キューの登録順序によって保持される)
        i = 0
        while i < @queue_count
          cmd = @command_pool[i]
          parent_cmd = parent_queue.allocate_command
          parent_cmd.set(
            parent_queue.owner, target_zf, parent_queue.queue_count,
            cmd.pipeline, cmd.data, cmd.count,
            cmd.image, cmd.shader, cmd.uniforms, cmd.blend, cmd.clip, cmd.mesh, cmd.inst_buffer
          )
          parent_queue.increment_count
          i += 1
        end

        # 転送完了したのでサブキューをリセット
        @queue_count = 0
        @needs_z_sort = false
      end

      # キュー内の有効コマンド列を `(z, order)` の昇順で安定ソートする
      #
      # - 戻り値: `Array<DrawCommand> | nil`
      def sort
        return unless @needs_z_sort
        return if @queue_count <= 1

        valid_cmds = @command_pool[0...@queue_count]
        valid_cmds.sort! do |a, b|
          comp = a.z <=> b.z
          comp == 0 ? (a.order <=> b.order) : comp
        end
        @command_pool[0...@queue_count] = valid_cmds
      end

      # キューに溜まったクリア処理と描画コマンドを FBO または画面へ実際にフラッシュする
      #
      # - 戻り値: `false | nil`
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

          if @clear_color
            Native::Window.clear(Backend.color_to_uint32(@clear_color))
            @clear_color = nil
          end

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
          Backend.cleanup_empty_queues
        else
          # 画面への描画
          if @clear_color
            Native::Window.clear(Backend.color_to_uint32(@clear_color))
            @clear_color = nil
            @cleared_this_frame = true
          elsif @auto_clear && !@cleared_this_frame
            Native::Window.clear(Backend.color_to_uint32(Zenoo::Window.bg_color || :black))
            @cleared_this_frame = true
          end

          Backend.execute_commands(@command_pool, @queue_count)
          @queue_count = 0
          @needs_z_sort = false
          @is_flushing = false
        end
      end
    end

    # ----------------------------------------------------
    # クリップコンテキスト (クリップ矩形、独立描画キュー、親Z値のカプセル化)
    # ----------------------------------------------------
    class ClipContext
      attr_accessor :rect, :queue, :z

      # 空のクリップコンテキストを初期化する
      #
      # - 戻り値: `ClipContext`
      def initialize
        @rect = nil
        @queue = DrawQueue.new(nil)
        @z = 0.0
      end

      # クリップ矩形・親 Z 値・描画先オーナーを設定する
      #
      # - `rect` (`Array<Numeric>`): シザー矩形 `[x, y, w, h]`（デバイス／スクリーン座標）
      # - `z` (`Float`): `pop_clip` 時に親キューへ転送する際の統一 Z 値
      # - `owner` (`Image | nil`): 描画先 `Image`（画面時は `nil`）
      # - 戻り値: `Image | nil`
      def set(rect, z, owner)
        @rect = rect
        @z = z.to_f
        @queue.instance_variable_set(:@owner, owner)
      end

      # プール返却前にコンテキストをリセットする
      #
      # - 戻り値: `false`
      def reset
        @rect = nil
        @z = 0.0
        @queue.instance_variable_set(:@queue_count, 0)
        @queue.needs_z_sort = false
      end
    end

    # ----------------------------------------------------
    # 描画スナップショット (あるフレームの描画コマンド列を記録し、後のフレームで再投入)
    # - 記録: キューの指定位置以降のコマンドを自前のプールへ浅くコピー (頂点データ String は共有)
    # - 再投入: 現在のアクティブキュー (画面 / render_to 先 / クリップ) へ通常の描画として積み直す
    #   → Z ソート・バッチング・ポストエフェクトの対象にそのまま乗る
    # ※ Mesh / InstanceBuffer など GPU 側で書き換わるリソースは「再投入時点の内容」で描画されます
    # ----------------------------------------------------
    class DrawSnapshot
      attr_reader :count

      # 空のスナップショットを初期化する
      #
      # - 戻り値: `DrawSnapshot`
      def initialize
        @pool = []
        @count = 0
      end

      # 記録されている描画コマンドが空かどうかを返す
      #
      # - 戻り値: `Boolean`
      def empty?
        @count == 0
      end

      # 指定キューの `from` 番目以降（このフレームに積まれた分）を記録する
      #
      # - `queue` (`DrawQueue`): 記録元の描画キュー
      # - `from` (`Integer`): 記録開始コマンドインデックス（デフォルト `0`）
      # - 戻り値: `Integer`
      def capture(queue, from = 0)
        n = queue.queue_count - from
        n = 0 if n < 0
        while @pool.length < n
          @pool << DrawCommand.new
        end

        src_pool = queue.command_pool
        i = 0
        while i < n
          s = src_pool[from + i]
          @pool[i].set(nil, s.z, i, s.pipeline, s.data, s.count, s.image, s.shader, s.uniforms, s.blend, s.clip, s.mesh, s.inst_buffer)
          i += 1
        end

        # 前回分の余りは参照を切って GC 可能にする
        j = n
        while j < @count
          @pool[j].set(nil, 0.0, 0, nil, nil, 0)
          j += 1
        end
        @count = n
      end

      # 記録したコマンド列を現在のアクティブキューへ再投入する
      #
      # - 戻り値: `Array<Image> | nil`
      def replay
        Backend.enqueue_snapshot(@pool, @count)
      end

      # 保持している描画コマンド参照を解放して空にする
      #
      # - 戻り値: `Integer`
      def clear
        i = 0
        while i < @count
          @pool[i].set(nil, 0.0, 0, nil, nil, 0)
          i += 1
        end
        @count = 0
      end
    end

    # ----------------------------------------------------
    # バックエンド状態管理
    # ----------------------------------------------------
    @screen_queue = DrawQueue.new(nil)
    @current_target = nil
    @active_gl_target = nil
    @pending_images = []
    @clip_stack = []        # ClipContext のスタック
    @clip_context_pool = [] # 再利用可能な ClipContext プール
    @batch_buffer = String.new(encoding: Encoding::BINARY) # バッチ結合用再利用バッファ (Mesh等の元データを破壊しない)
    @skip_ondemand_flush = false

    # 現在有効なシザークリップ矩形 `[x, y, w, h]` を返す（未クリップ時は `nil`）
    #
    # - 戻り値: `Array<Numeric> | nil`
    def self.current_clip
      @clip_stack.last&.rect
    end

    # クリップスコープを開始し、専用の独立描画キューをスタックへ積む
    #
    # - `rect` (`Array<Numeric>`): シザー矩形 `[x, y, w, h]`
    # - `z` (`Float`): `pop_clip` 時に親キューへ転送する際の Z 値（デフォルト `0.0`）
    # - 戻り値: `Array<ClipContext>`
    def self.push_clip(rect, z = 0.0)
      ctx = @clip_context_pool.pop || ClipContext.new
      ctx.set(rect, z, @current_target)
      @clip_stack.push(ctx)
    end

    # 現在のクリップスコープを終了し、内部コマンドをソートして親キューへ転送する
    #
    # - 戻り値: `Array<ClipContext> | nil`
    def self.pop_clip
      ctx = @clip_stack.pop
      return unless ctx

      parent_q = active_queue
      ctx.queue.transfer_to(parent_q, ctx.z)
      ctx.reset
      @clip_context_pool.push(ctx)
    end

    # 未終了のクリップスタックをすべて破棄してリセットする（フレーム終了時の安全網）
    #
    # - 戻り値: `nil`
    def self.clear_clips
      while (ctx = @clip_stack.pop)
        ctx.reset
        @clip_context_pool.push(ctx)
      end
    end

    # 現在描画コマンドを受け付けるアクティブキュー（クリップ中→クリップキュー、`render_to` 中→Image キュー、それ以外→画面キュー）を返す
    #
    # - 戻り値: `DrawQueue`
    def self.active_queue
      if !@clip_stack.empty?
        @clip_stack.last.queue
      elsif @current_target
        queue_for(@current_target)
      else
        @screen_queue
      end
    end

    # メインウィンドウ画面用の描画キューを返す
    #
    # - 戻り値: `DrawQueue`
    def self.screen_queue
      @screen_queue
    end

    # フレーム先頭で画面キューのクリア済みフラグをリセットする
    #
    # - 戻り値: `false`
    def self.reset_frame
      @screen_queue.reset_frame
    end

    # 画面キューに対して今フレームのクリアが完了済みであることを記録する
    #
    # - 戻り値: `true`
    def self.mark_screen_cleared
      @screen_queue.mark_cleared
    end

    # 現在の論理的な描画先レンダーターゲット（`Image` または画面 `nil`）を返す
    #
    # - 戻り値: `Image | nil`
    def self.current_target
      @current_target
    end

    # 現在の論理的な描画先レンダーターゲットを設定する
    #
    # - `target` (`Image | nil`): 描画先 `Image`（画面に戻す場合は `nil`）
    # - 戻り値: `Image | nil`
    def self.current_target=(target)
      @current_target = target
    end

    # OpenGL 側で実際にバインドされている FBO の `Image`（画面バックバッファ時は `nil`）を返す
    #
    # - 戻り値: `Image | nil`
    def self.active_gl_target
      @active_gl_target
    end

    # 現在 OpenGL 側でバインドされている FBO の `Image` を記録する
    #
    # - `target` (`Image | nil`): バインド中の `Image`（または `nil`）
    # - 戻り値: `Image | nil`
    def self.active_gl_target=(target)
      @active_gl_target = target
    end

    # ブロック実行中だけ一時的に論理レンダーターゲットを切り替える
    #
    # - `target` (`Image | nil`): 一時的な描画先 `Image`
    # - `&block`: 切り替え中に実行するブロック
    # - 戻り値: `Image | nil`
    def self.with_target(target)
      old_target = @current_target
      @current_target = target
      yield
      @current_target = old_target
    end

    @target_images = []
    @target_queues = []

    # 指定した `Image` に対応する描画キューを取得または新規作成する
    #
    # - `image` (`Image`): 描画先 `Image`
    # - 戻り値: `DrawQueue`
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

    # 指定した `Image` に未フラッシュの描画やクリア予約が残っているかを返す
    #
    # - `image` (`Image`): 確認対象の `Image`
    # - 戻り値: `Boolean`
    def self.has_pending_draws?(image)
      idx = @target_images.index(image)
      if idx
        @target_queues[idx].has_pending_draws?
      else
        false
      end
    end

    # 指定した `Image` に溜まっている描画コマンドを即時に FBO へフラッシュする
    #
    # - `image` (`Image`): フラッシュ対象の `Image`
    # - 戻り値: `false | nil`
    def self.flush_image(image)
      idx = @target_images.index(image)
      if idx
        @target_queues[idx].flush
      end
    end

    # 描画予約が空になった `Image` キュー管理エントリを掃除する
    #
    # - 戻り値: `nil`
    def self.cleanup_empty_queues
      i = @target_images.length - 1
      while i >= 0
        unless @target_queues[i].has_pending_draws?
          @target_images.delete_at(i)
          @target_queues.delete_at(i)
        end
        i -= 1
      end
    end

    # 未フラッシュ状態のオフスクリーン `Image` を保留リストに登録する
    #
    # - `img` (`Image`): 登録する `Image`
    # - 戻り値: `Array<Image> | nil`
    def self.register_pending_image(img)
      @pending_images << img unless @pending_images.include?(img)
    end

    # 画面に依存されないまま残っている保留中 `Image` の描画キューを一括フラッシュする
    #
    # - 戻り値: `nil`
    def self.flush_pending_images
      return if @pending_images.empty?

      images = @pending_images.dup
      @pending_images.clear
      images.each do |img|
        flush_image(img)
      end
      cleanup_empty_queues
    end

    # 現在のアクティブキューに描画コマンドを 1 件登録する（`Window.draw_*` 等から呼ばれる中核入口）
    #
    # - `pipeline` (`Pipeline`): 使用する `Pipelines` 定数
    # - `data` (`String | nil`): パック済み頂点／インスタンスバイナリデータ
    # - `count` (`Integer`): 頂点数またはインスタンス数
    # - `image` (`Image | nil`): テクスチャ画像
    # - `shader` (`NativeShader | nil`): カスタムシェーダー
    # - `uniforms` (`Hash | nil`): ユニフォーム変数ハッシュ
    # - `blend` (`Integer`): `BlendMode` の整数値
    # - `z` (`Float`): Z 描画順（小さいほど奥）
    # - `mesh` (`Native::Mesh | nil`): VRAM メッシュ
    # - `inst_buffer` (`Native::Mesh | nil`): VRAM インスタンスバッファ
    # - 戻り値: `Array<Image> | nil`
    def self.enqueue_draw(pipeline, data, count, image: nil, shader: nil, uniforms: nil, blend: 0, z: 0.0, mesh: nil, inst_buffer: nil)
      active_queue.enqueue(pipeline, data, count, image: image, shader: shader, uniforms: uniforms, blend: blend, z: z, mesh: mesh, inst_buffer: inst_buffer)
      register_pending_image(@current_target) if @current_target
    end

    # `DrawSnapshot` に記録されたコマンド群を現在のアクティブキューへまとめて再投入する
    #
    # - `pool` (`Array<DrawCommand>`): スナップショット側のコマンドプール
    # - `count` (`Integer`): 再投入するコマンド数
    # - 戻り値: `Array<Image> | nil`
    def self.enqueue_snapshot(pool, count)
      return if count == 0
      q = active_queue
      i = 0
      while i < count
        s = pool[i]
        cmd = q.allocate_command
        cmd.set(q.owner, s.z, q.queue_count, s.pipeline, s.data, s.count, s.image, s.shader, s.uniforms, s.blend, s.clip, s.mesh, s.inst_buffer)
        q.needs_z_sort = true if s.z != 0.0
        q.increment_count
        i += 1
      end
      register_pending_image(@current_target) if @current_target
    end

    # 現在の描画ターゲット（オフスクリーン `Image`・`sub_image`・メイン画面）に対してクリアを予約する
    #
    # - `color` (`Color | Symbol | Array<Numeric> | String | Integer | nil`): クリア色（省略時は対象に応じた既定色）
    # - 戻り値: `Color | Symbol | Array<Numeric> | String | Integer | Array | nil`
    def self.enqueue_clear(color = nil)
      if @current_target
        register_pending_image(@current_target)
        if @current_target.sub_image?
          # sub_image はアトラス等の部分領域のため、FBO全体を glClear すると他のスロットが消える
          # そのため該当矩形領域のみを塗りつぶす (最奥 Z = -Infinity, アルファ0なら blend: :none で上書き)
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
          color ||= :clear
          q = queue_for(@current_target)
          q.set_clear(color)
        end
      else
        color ||= Zenoo::Window.bg_color
        @screen_queue.set_clear(color)
        Zenoo::Window.bg_color = color
      end
    end

    # フレーム末にメイン画面と保留中オフスクリーン `Image` の描画キューをすべてフラッシュし、ブレンドモードを既定へ戻す
    #
    # - 戻り値: `nil`
    def self.flush_screen
      @screen_queue.flush
      flush_pending_images
      Native::Renderer.set_blend_mode(BlendMode::ALPHA)
    end

    # カスタムシェーダーへ Ruby ハッシュ形式の uniform 値（テクスチャ含む）を一括バインドする
    # ※ `Zenoo::Image` が未フラッシュの場合はここでオンデマンド描画を行う
    #
    # - `shader` (`NativeShader | nil`): 適用先のシェーダー
    # - `uniforms` (`Hash{Symbol, String => Object} | nil`): uniform 名と値（`Image`, `Integer`, `Float`, `Array`, `String`）
    # - 戻り値: `Hash | nil`
    def self.apply_uniforms(shader, uniforms)
      return unless uniforms && shader

      tex_unit = 1
      uniforms.each do |k, v|
        name = k.to_s
        case v
        when Zenoo::Image
          if !@skip_ondemand_flush && has_pending_draws?(v)
            flush_image(v)
          end
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

    # スナップショット等の記録済みコマンドプールを、元コマンドを破壊せずに直接実行する
    #
    # - `pool` (`Array<DrawCommand>`): コマンド配列
    # - `count` (`Integer`): 実行するコマンド数
    # - 戻り値: `false | nil`
    def self.execute_snapshot_commands(pool, count)
      return if count == 0
      Native::Image.reset_render_target
      @skip_ondemand_flush = true
      execute_commands(pool, count)
      @skip_ondemand_flush = false
    end

    # 描画コマンド列を動的バッチングしつつ OpenGL / Native レンダラーへ発行する
    #
    # - `pool` (`Array<DrawCommand>`): コマンド配列
    # - `count` (`Integer`): 実行するコマンド数
    # - 戻り値: `nil`
    def self.execute_commands(pool, count)
      return if count == 0

      if Zenoo::Profiler.enabled
        Zenoo::Profiler.measure(:draw) do
          __execute_commands_internal(pool, count)
        end
      else
        __execute_commands_internal(pool, count)
      end
    end

    def self.__execute_commands_internal(pool, count)
      $last_draw_calls = 0
      active_gl_clip = :initial

      i = 0
      while i < count
        cmd = pool[i]

        # 0. 描画元テクスチャに未消化キューがあれば先にフラッシュ (オンデマンド描画)
        if !@skip_ondemand_flush && cmd.image && has_pending_draws?(cmd.image)
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
        cur_mesh = cmd.mesh
        cur_inst_buffer = cmd.inst_buffer

        # シザーテストの適用（変更があった場合のみ切り替え）
        if cur_clip != active_gl_clip
          if cur_clip
            Native::Renderer.set_scissor(cur_clip[0].to_i, cur_clip[1].to_i, cur_clip[2].to_i, cur_clip[3].to_i)
          else
            Native::Renderer.reset_scissor
          end
          active_gl_clip = cur_clip
        end

        can_batch = !cur_data.nil? && cur_inst_buffer.nil? && (
                      cur_pipeline.base_vertex_count > 0 ||
                      cur_pipeline.topology == Topology::TRIANGLES ||
                      cur_pipeline.topology == Topology::LINES ||
                      cur_pipeline.topology == Topology::POINTS
                    )

        next_idx = i + 1
        final_data = cur_data
        if can_batch
          batched = false
          while next_idx < count
            ncmd = pool[next_idx]
            if ncmd.image && has_pending_draws?(ncmd.image)
              flush_image(ncmd.image)
            end

            n_shader = ncmd.shader || ncmd.pipeline.default_shader
            same_image = (ncmd.image == cur_image) ||
                         (ncmd.image && cur_image && ncmd.image.texture_id == cur_image.texture_id)
            if ncmd.pipeline == cur_pipeline &&
               ncmd.mesh == cur_mesh &&
               ncmd.inst_buffer.nil? &&
               !ncmd.data.nil? &&
               same_image &&
               n_shader == cur_shader &&
               ncmd.uniforms == cur_uniforms &&
               ncmd.blend == cur_blend &&
               ncmd.clip == cur_clip
              unless batched
                @batch_buffer.clear
                @batch_buffer << cur_data
                batched = true
              end
              @batch_buffer << ncmd.data
              cur_count += ncmd.count
              unless @skip_ondemand_flush
                ncmd.data = nil
                ncmd.image = nil
                ncmd.shader = nil
                ncmd.target = nil
                ncmd.pipeline = nil
                ncmd.uniforms = nil
                ncmd.clip = nil
                ncmd.mesh = nil
                ncmd.inst_buffer = nil
              end
              next_idx += 1
            else
              break
            end
          end
          final_data = @batch_buffer if batched
        end

        Native::Renderer.set_blend_mode(cur_blend)
        apply_uniforms(cur_shader, cur_uniforms) if cur_uniforms

        $last_draw_calls = ($last_draw_calls || 0) + 1
        if cur_mesh || cur_inst_buffer || cur_pipeline == Pipelines::SPRITE
          inst_layout = final_data ? cur_pipeline.layout : nil
          Native::Renderer.draw_mesh(
            cur_mesh,
            cur_inst_buffer,
            inst_layout,
            final_data,
            cur_count,
            cur_image,
            cur_shader
          )
        else
          Native::Renderer.draw_buffer(
            cur_pipeline.topology,
            cur_pipeline.layout,
            cur_pipeline.divisors,
            cur_pipeline.base_vertex_count,
            final_data,
            cur_count,
            cur_image,
            cur_shader
          )
        end

        unless @skip_ondemand_flush
          cmd.data = nil
          cmd.image = nil
          cmd.shader = nil
          cmd.target = nil
          cmd.pipeline = nil
          cmd.uniforms = nil
          cmd.clip = nil
          cmd.mesh = nil
          cmd.inst_buffer = nil
        end

        i = next_idx
      end

      # ループ完了後にシザーをリセット
      Native::Renderer.reset_scissor if active_gl_clip != :initial
    end
  end
end

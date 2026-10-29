# frozen_string_literal: true

module Zenoo
  # ====================================================================
  # Zenoo::Scene - メソッド 1 個で書ける、スタック型シーン管理
  # ====================================================================
  # シーン = 毎フレーム 1 回呼ばれる `call` を持つオブジェクト (更新と描画を分けない)。
  #
  #   class TitleScene < Scene
  #     def call
  #       Window.draw_text(640, 360, "PRESS ENTER", align: :center)
  #       Scene.change(PlayScene.new(world), fade: 0.5) if Input.key_push?(:enter)
  #     end
  #   end
  #
  #   Scene.change(TitleScene.new)
  #   Window.loop { Scene.call }
  #
  # 主な機能:
  # 1. change / push / pop だけのシンプルなスタック操作
  #    - change : 全シーンを破棄して新しいシーンへ (タイトル → 本編 など)
  #    - push   : 今のシーンの上に重ねる (ポーズ / レベルアップ / ダイアログ)
  #    - pop    : 一番上を閉じて下のシーンへ戻る
  # 2. push された下のシーンは「止まったまま見える」(below: :freeze, 既定)
  #    - 下のシーンは call されないのでゲームは完全に停止
  #    - 見た目は push 直前フレームの描画コマンドを再投入して再現 (テクスチャ不要・高解像度のまま)
  #    - below: :live なら下も動き続け、below: :hide なら下は描画しない
  # 3. fade: 秒数 を付けるだけでフェードアウト → 切り替え → フェードイン
  # 4. シーンごとの経過フレーム `frames` / 経過秒 `elapsed` (覆われている間は止まる)
  #    → 遷移直後の誤入力防止や点滅演出がタイマー変数なしで書ける
  # 5. 任意フック: enter (積まれた時) / leave (外された時) / resume (上が閉じて再開した時)
  # 6. クラスを作らずブロックだけでもシーンになる: Scene.push { ... }
  #
  # シーン操作はその場では反映されず、現在のフレームの call が終わった後に適用されます
  # (フレームの途中でスタックが変わって描画が欠ける事故を防ぐため)。
  # ====================================================================
  class Scene
    # ------------------------------------------------------------------
    # 予約されたシーン操作
    # ------------------------------------------------------------------
    class Op
      attr_reader :kind, :scene, :below, :fade

      def initialize(kind, scene, below, fade)
        @kind = kind   # :change / :push / :pop
        @scene = scene
        @below = below
        @fade = fade.to_f
      end
    end

    @stack = []
    @pending = []
    @fade_ops = []
    @fade_state = :none # :none / :out / :in
    @fade_t = 0.0
    @fade_half = 0.0
    @fade_color = [0.0, 0.0, 0.0, 1.0]
    @fade_source = nil

    class << self
      # 全シーンを破棄して scene へ切り替え
      def change(scene = nil, fade: 0.0, color: :black, &block)
        __request(:change, scene || Scene.new(&block), :freeze, fade, color)
      end

      # 現在のシーンの上に scene を重ねる
      # below: :freeze (下は止めて表示) / :live (下も動かす) / :hide (下は描画しない)
      def push(scene = nil, below: :freeze, fade: 0.0, color: :black, &block)
        __request(:push, scene || Scene.new(&block), below, fade, color)
      end

      # 一番上のシーンを閉じる
      def pop(fade: 0.0, color: :black)
        __request(:pop, nil, :freeze, fade, color)
      end

      # 1 フレーム分の実行 (Window.loop の中で毎フレーム呼ぶ)
      def call
        # ループ開始前に予約された最初のシーンなどを反映
        __apply(@pending) if @stack.empty? && !@pending.empty? && @fade_state == :none

        q = Backend.active_queue
        start = q.queue_count
        dt = Window.delta_time.to_f

        # フェードアウト中: シーンは一切動かさず、直前の画面を再投入して暗転させる
        if @fade_state == :out
          @fade_source.__replay if @fade_source
          @fade_t += dt
          ratio = @fade_half > 0.0 ? @fade_t / @fade_half : 1.0
          ratio = 1.0 if ratio > 1.0
          __draw_fade(ratio)
          if ratio >= 1.0
            __apply(@fade_ops)
            @fade_source = nil
            @fade_state = :in
            @fade_t = 0.0
          end
          return
        end

        top = @stack.last
        __run_layer(@stack.length - 1) if top

        # フェードイン中: 新しいシーンは動かしつつ、上に重ねた幕を薄くしていく
        if @fade_state == :in
          @fade_t += dt
          ratio = @fade_half > 0.0 ? @fade_t / @fade_half : 1.0
          ratio = 1.0 if ratio > 1.0
          __draw_fade(1.0 - ratio)
          @fade_state = :none if ratio >= 1.0
        end

        return if @pending.empty?

        # このフレームに予約された操作を適用
        fade = 0.0
        color = :black
        needs_capture = false
        @pending.each do |op|
          if op.fade > fade
            fade = op.fade
          end
          needs_capture = true if op.kind == :push && op.below != :hide
        end
        needs_capture = true if fade > 0.0

        # 下に残る / フェードで見せるシーンの見た目を、このフレームの描画コマンドから記録
        top.__capture(q, start) if needs_capture && top

        if fade > 0.0 && top
          @fade_ops = @pending
          @pending = []
          @fade_source = top
          @fade_state = :out
          @fade_t = 0.0
          @fade_half = fade * 0.5
        else
          ops = @pending
          @pending = []
          __apply(ops)
        end
      end

      # 一番上のシーン
      def current
        @stack.last
      end

      # 現在のシーンの経過フレーム数 (初回の call で 1。ブロックシーン内でもそのまま参照可能)
      def frames
        top = @stack.last
        top ? top.frames : 0
      end

      # 現在のシーンの経過秒数
      def elapsed
        top = @stack.last
        top ? top.elapsed : 0.0
      end

      def size
        @stack.length
      end

      def empty?
        @stack.empty?
      end

      # フェード演出中か
      def transitioning?
        @fade_state != :none
      end

      # 全シーンと予約を即座に破棄 (テストやリセット用)
      def clear
        @stack.reverse_each(&:leave)
        @stack.clear
        @pending.clear
        @fade_ops.clear
        @fade_state = :none
        @fade_source = nil
      end

      # ----------------------------------------------------------------
      # 内部処理
      # ----------------------------------------------------------------
      def __request(kind, scene, below, fade, color)
        @fade_color = Backend.normalize_color(color) if fade.to_f > 0.0
        @pending << Op.new(kind, scene, below, fade)
        nil
      end

      def __apply(ops)
        ops.each do |op|
          case op.kind
          when :change
            while (s = @stack.pop)
              s.leave
            end
            __enter(op.scene, :freeze)
          when :push
            __enter(op.scene, op.below)
          when :pop
            s = @stack.pop
            s.leave if s
            @stack.last.resume unless @stack.empty?
          end
        end
        ops.clear
      end

      def __enter(scene, below)
        scene.__attach(below)
        @stack << scene
        scene.enter
      end

      # i 番目のシーンを実行 (下のシーンは below 指定に従って表示・実行)
      def __run_layer(i)
        s = @stack[i]
        if i > 0
          below = s.__below
          if below == :live
            __run_layer(i - 1)
          elsif below == :freeze
            @stack[i - 1].__replay
          end
          # 下の階層の描画をこの時点で GPU へ確定発行 (Z オーダーの完全分離・突き抜け防止)
          Backend.active_queue.flush
        end
        s.__tick
        s.call
      end

      def __draw_fade(ratio)
        return if ratio <= 0.0
        c = @fade_color
        Window.without_camera do
          Window.draw_rect(0.0, 0.0, Window.width.to_f, Window.height.to_f,
                           color: [c[0] * 255.0, c[1] * 255.0, c[2] * 255.0, c[3] * 255.0 * ratio],
                           z: Float::INFINITY)
        end
      end
    end

    # ------------------------------------------------------------------
    # シーンインスタンス
    # ------------------------------------------------------------------

    # ブロックを渡すとクラスを作らずにシーンになる: Scene.new { ... }
    def initialize(&block)
      @scene_block = block
    end

    # 毎フレームの処理 (サブクラスで上書き)
    def call
      @scene_block.call if @scene_block
    end

    # 任意フック (必要なものだけ上書き)
    def enter; end   # スタックに積まれた時
    def leave; end   # スタックから外された時
    def resume; end  # 上のシーンが閉じて、再び一番上になった時

    # このシーンが動いた累計フレーム数 (初回の call で 1。覆われている間は増えない)
    def frames
      @scene_frames || 0
    end

    # このシーンが動いた累計秒数
    def elapsed
      @scene_elapsed || 0.0
    end

    # --- 以下はマネージャ用の内部メソッド ---
    def __attach(below)
      @scene_below = below
      @scene_frames = 0
      @scene_elapsed = 0.0
    end

    def __below
      @scene_below || :freeze
    end

    def __tick
      @scene_frames = frames + 1
      @scene_elapsed = elapsed + Window.delta_time.to_f
    end

    def __capture(queue, from)
      @scene_snapshot ||= Backend::DrawSnapshot.new
      @scene_snapshot.capture(queue, from)
    end

    def __replay
      @scene_snapshot.replay if @scene_snapshot
    end
  end
end

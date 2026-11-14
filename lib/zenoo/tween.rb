# frozen_string_literal: true

require_relative 'easing'

module Zenoo
  # ====================================================================
  # Zenoo::Tween - 直感的・軽量なメソッドチェーン対応アニメーションシステム
  # ====================================================================
  # 主な特徴:
  # 1. クラスメソッド Tween.to(target, duration, ...) で対象をバインドし、
  #    チェーン (.to, .delay, .call, .loop, .yoyo) で直列実行
  # 2. 複数プロパティ（x, y, angle, alpha 等）の同時トゥイーンに対応
  # 3. Spinel AOT コンパイルに最適化 (動的 send を完全排除し静的ディスパッチ)
  # 4. register_property によるカスタムプロパティ（Getter/Setter Proc）の柔軟な拡張
  # 5. .call { ... } による時間軸イベント（画像切替・SE再生・パーティクル等）の挿入
  # 6. オブジェクト指定一括停止 (Tween.kill(target)) や即時完了 (tween.finish)
  # ====================================================================
  class Tween
    # ------------------------------------------------------------------
    # クラスメソッド & グローバルマネージャ
    # ------------------------------------------------------------------
    @active_tweens = []
    @custom_accessors = {} # { prop_sym => [getter_proc, setter_proc] }

    class << self
      attr_reader :active_tweens, :custom_accessors

      # カスタムプロパティ用の Getter / Setter を Proc で登録
      #
      # - `name` (`Symbol`, `String`): プロパティ名
      # - `getter:` (`Proc`, `nil`): `->(target) { target.foo }`
      # - `setter:` (`Proc`, `nil`): `->(target, val) { target.foo = val }`
      def register_property(name, getter: nil, setter: nil)
        @custom_accessors[name.to_sym] = [getter, setter]
      end

      # 対象オブジェクトのプロパティをアニメーション開始 (クラスメソッドは target 必須)
      # 例: Tween.to(player, 1.0, x: 400, y: 300, ease: :quad_out)
      #
      # - `target` (`Object`): アニメーション対象オブジェクト（`x`, `y`, `angle`, `scale`, `alpha` 等を持つオブジェクト）
      # - `duration` (`Numeric`): 補間にかける時間（秒）
      # - `ease:` (`Symbol`, `Array`): イージング種別（デフォルト: `:linear`）
      # - `delay:` (`Numeric`): 開始前の待機時間（秒、デフォルト: 0.0）
      # - `from:` (`Hash`, `nil`): 開始値を明示指定するハッシュ（省略時は開始時の現在値を自動取得）
      # - `steps:` (`Integer`, `nil`): `:step` イージング使用時の段階分割数
      # - `round:` (`Boolean`, `nil`): `true` の場合は補間結果を整数に丸める
      # - `**props`: 目標値となるプロパティ名と値のペア（例: `x: 400, alpha: 255`）
      # - 戻り値: `Tween` メソッドチェーン用のインスタンス
      def to(target, duration, ease: :linear, delay: 0.0, from: nil, steps: nil, round: nil, **props)
        tween = new(target)
        tween.to(duration, ease: ease, delay: delay, from: from, steps: steps, round: round, **props)
        register(tween)
        tween
      end

      # 待機から始まるチェーンを作成
      # 例: Tween.delay(player, 0.5).to(1.0, x: 400)
      #
      # - `target` (`Object`, `nil`): 後続チェーンの対象オブジェクト
      # - `duration` (`Numeric`): 待機時間（秒）
      # - 戻り値: `Tween`
      def delay(target, duration)
        tween = new(target)
        tween.delay(duration)
        register(tween)
        tween
      end

      # 即座（または遅延後）にブロックを実行するステップから始まるチェーンを作成
      #
      # - `target` (`Object`, `nil`): 後続チェーンの対象オブジェクト（省略可）
      # - `&block`: 実行する処理ブロック
      # - 戻り値: `Tween`
      def call(target = nil, &block)
        tween = new(target)
        tween.call(&block)
        register(tween)
        tween
      end

      # 数値範囲を補間してブロックへ渡す（直接描画やカスタム値更新用）
      # 例: Tween.value(from: 0.0, to: 1.0, duration: 0.5) { |v| alpha = v }
      #
      # - `from:` (`Numeric`): 開始数値
      # - `to:` (`Numeric`): 終了数値
      # - `duration:` (`Numeric`): 補間時間（秒、デフォルト: 0.0）
      # - `ease:` (`Symbol`, `Array`): イージング種別（デフォルト: `:linear`）
      # - `delay:` (`Numeric`): 開始前待機時間（秒、デフォルト: 0.0）
      # - `steps:` (`Integer`, `nil`): `:step` イージング使用時の分割数
      # - `round:` (`Boolean`, `nil`): 整数丸め有無（`nil` 時は `from`・`to` が共に `Integer` なら自動で丸める）
      # - `&block`: 補間された現在値 `|val|` を受け取るブロック
      # - 戻り値: `Tween`
      def value(from:, to:, duration: 0.0, ease: :linear, delay: 0.0, steps: nil, round: nil, &block)
        tween = new(nil)
        tween.value(from: from, to: to, duration: duration, ease: ease, delay: delay, steps: steps, round: round, &block)
        register(tween)
        tween
      end

      # 対象オブジェクトに関わる全ての Tween を破棄・中断
      #
      # - `target` (`Object`, `nil`): 停止対象のオブジェクト
      def kill(target)
        return if target.nil?
        target.kill_tweens if target.respond_to?(:kill_tweens)
        @active_tweens.each do |t|
          t.stop if t.involves_target?(target)
        end
      end

      # 指定ターゲット、または全グローバル Tween を停止します（`target` 指定時は `Tween.kill`、省略時は `Tween.clear` と同等）。
      #
      # - `target` (`Object`, `nil`): 停止対象オブジェクト（`nil` で全クリア）
      def stop_all(target = nil)
        if target
          kill(target)
        else
          clear
        end
      end

      # 全ての Tween を強制クリア
      def clear
        @active_tweens.each(&:stop)
        @active_tweens.clear
      end

      # 対象オブジェクトの全 Tween を最終状態にスキップして完了
      #
      # - `target` (`Object`, `nil`): 対象オブジェクト（省略時はグローバル管理下の全 Tween を完了）
      def finish_all(target = nil)
        if target
          target.finish_tweens if target.respond_to?(:finish_tweens)
          @active_tweens.each do |t|
            t.finish if t.involves_target?(target)
          end
        else
          @active_tweens.each(&:finish)
        end
      end

      # 全 Tween の一時停止 / 再開
      #
      # グローバル管理下のアクティブな全 Tween を一時停止します。
      def pause_all
        @active_tweens.each(&:pause)
      end

      # 一時停止中のグローバル管理下の全 Tween を再開します。
      def resume_all
        @active_tweens.each(&:resume)
      end

      # 現在アクティブな Tween 数
      #
      # - 戻り値: `Integer`
      def count
        @active_tweens.size
      end

      # マネージャに登録
      #
      # - `tween` (`Tween`): グローバル自動更新対象に加える `Tween`
      def register(tween)
        @active_tweens << tween unless @active_tweens.include?(tween)
      end

      # マネージャから解除
      #
      # - `tween` (`Tween`): グローバル自動更新対象から外す `Tween`
      def unregister(tween)
        @active_tweens.delete(tween)
      end

      # エンジン内部フレーム更新 (Window.__update_step から自動呼び出し)
      def __update_step(dt)
        return if @active_tweens.empty?

        i = 0
        while i < @active_tweens.size
          t = @active_tweens[i]
          t.__update(dt)
          if t.completed?
            @active_tweens.delete_at(i)
          else
            i += 1
          end
        end
      end

      # ----------------------------------------------------------------
      # プロパティ アクセス用ヘルパー (Spinel AOT 最適化)
      # send を完全排除し、主要プロパティへの直接アクセスとカスタム Proc 呼び出し
      # ----------------------------------------------------------------
      def _get_prop(target, prop)
        return 0.0 unless target
        case prop
        when :x then target.x
        when :y then target.y
        when :z then target.z
        when :angle then target.angle
        when :scale then target.scale
        when :scale_x then target.scale_x
        when :scale_y then target.scale_y
        when :alpha then target.alpha
        when :color then target.color
        else
          acc = @custom_accessors[prop]
          if acc && acc[0]
            acc[0].call(target)
          else
            0.0
          end
        end
      end

      def _set_prop(target, prop, val)
        return unless target
        case prop
        when :x then target.x = val
        when :y then target.y = val
        when :z then target.z = val
        when :angle then target.angle = val
        when :scale then target.scale = val
        when :scale_x then target.scale_x = val
        when :scale_y then target.scale_y = val
        when :alpha then target.alpha = val
        when :color then target.color = val
        else
          acc = @custom_accessors[prop]
          if acc && acc[1]
            acc[1].call(target, val)
          end
        end
      end
    end

    # ------------------------------------------------------------------
    # インスタンス実装
    # ------------------------------------------------------------------
    attr_reader :target

    # Tween インスタンスを初期化します（通常は `Tween.to` または `sprite.tween` から生成します）。
    #
    # - `target` (`Object`, `nil`): プロパティを操作する対象オブジェクト
    def initialize(target = nil)
      @target = target
      @steps = []
      @step_index = 0
      @step_elapsed = 0.0
      @step_initialized = false
      @paused = false
      @completed = false
      @loop_mode = nil       # nil, :infinite, または Integer (残り回数)
      @initial_loop = nil
      @yoyo = false
      @yoyo_reverse = false
      @on_complete = nil
    end

    # チェーンの次のステップとしてプロパティ変更を追加 (インスタンスメソッドには target を渡さない)
    # 例: tween.to(1.0, x: 400, y: 300, ease: :quad_out)
    #
    # - `duration` (`Numeric`): 補間にかける時間（秒）
    # - `ease:` (`Symbol`, `Array`): イージング種別（デフォルト: `:linear`）
    # - `delay:` (`Numeric`): このステップの前に挿入する待機時間（秒、デフォルト: 0.0）
    # - `from:` (`Hash`, `nil`): 開始値を明示指定するハッシュ
    # - `steps:` (`Integer`, `nil`): `:step` イージング時の分割数
    # - `round:` (`Boolean`, `nil`): 補間結果を整数に丸めるかどうか
    # - `**props`: 目標値となるプロパティ名と値のペア
    # - 戻り値: `Tween` (`self`)
    def to(duration, ease: :linear, delay: 0.0, from: nil, steps: nil, round: nil, **props)
      self.delay(delay) if delay && delay > 0

      @steps << {
        type: :property,
        duration: [duration.to_f, 0.0].max,
        ease: ease,
        from: from,
        steps: steps,
        round: round,
        props: props
      }
      self
    end

    # チェーンの次のステップとして待機時間を追加
    #
    # - `duration` (`Numeric`): 待機時間（秒）
    # - 戻り値: `Tween` (`self`)
    def delay(duration)
      @steps << {
        type: :delay,
        duration: [duration.to_f, 0.0].max
      }
      self
    end

    # チェーンの次のステップとしてブロック実行を追加
    #
    # - `&block`: ステップ到達時に実行されるブロック（引数を取る場合は `self` が渡されます）
    # - 戻り値: `Tween` (`self`)
    def call(&block)
      @steps << {
        type: :call,
        block: block
      }
      self
    end

    # 数値補間ステップを追加 (カスタム値更新用)
    #
    # - `from:` (`Numeric`): 開始数値
    # - `to:` (`Numeric`): 終了数値
    # - `duration:` (`Numeric`): 補間時間（秒、デフォルト: 0.0）
    # - `ease:` (`Symbol`, `Array`): イージング種別（デフォルト: `:linear`）
    # - `delay:` (`Numeric`): このステップの前に挿入する待機時間（秒、デフォルト: 0.0）
    # - `steps:` (`Integer`, `nil`): `:step` イージング時の分割数
    # - `round:` (`Boolean`, `nil`): 整数丸め有無
    # - `&block`: 補間値 `|val|` を受け取るブロック
    # - 戻り値: `Tween` (`self`)
    def value(from:, to:, duration: 0.0, ease: :linear, delay: 0.0, steps: nil, round: nil, &block)
      self.delay(delay) if delay && delay > 0
      @steps << {
        type: :value,
        from: from,
        to: to,
        duration: [duration.to_f, 0.0].max,
        ease: ease,
        steps: steps,
        round: round,
        block: block
      }
      self
    end

    # 繰り返し回数を指定 (count = true または :infinite で無限ループ)
    #
    # - `count` (`Integer`, `Boolean`, `Symbol`): 繰り返し回数（`true` または `:infinite` で無限ループ）
    # - 戻り値: `Tween` (`self`)
    def repeat(count = true)
      @loop_mode = (count == true || count == :infinite) ? :infinite : count.to_i
      @initial_loop = @loop_mode
      self
    end

    # 順再生と逆再生を交互に行う
    #
    # - `count` (`Integer`, `Boolean`, `Symbol`): 往復回数（`true` または `:infinite` で無限往復、デフォルト: `true`）
    # - 戻り値: `Tween` (`self`)
    def yoyo(count = true)
      @yoyo = true
      repeat(count)
      self
    end

    # 全工程完了時のコールバック
    #
    # - `&block`: 完了時に呼び出されるブロック（`self` を引数に渡します）
    # - 戻り値: `Tween` (`self`)
    def on_complete(&block)
      @on_complete = block
      self
    end

    # 制御メソッド
    #
    # この Tween を直ちに停止・完了状態とし、マネージャから登録解除します。
    #
    # - 戻り値: `Tween` (`self`)
    def stop
      @completed = true
      Tween.unregister(self)
      self
    end

    # `stop` の別名（この Tween を直ちに中断して登録解除します）。
    #
    # - 戻り値: `Tween` (`self`)
    def kill
      stop
    end

    # この Tween の進行を一時停止します。
    #
    # - 戻り値: `Tween` (`self`)
    def pause
      @paused = true
      self
    end

    # 一時停止していた Tween の進行を再開します。
    #
    # - 戻り値: `Tween` (`self`)
    def resume
      @paused = false
      self
    end

    # 全ステップを瞬時に最終状態にして完了
    #
    # - 戻り値: `Tween` (`self`), `nil`
    def finish
      return if @completed

      @steps.each do |step|
        case step[:type]
        when :property
          props = step[:props]
          props.each do |prop, to_val|
            val = step[:round] ? to_val.round : to_val
            Tween._set_prop(@target, prop, val)
          end
        when :value
          val = step[:to]
          val = val.round if val && (step[:round] == true || (step[:round].nil? && val.is_a?(Integer)))
          step[:block]&.call(val)
        when :call
          call_step_block(step[:block])
        end
      end

      @completed = true
      Tween.unregister(self)
      @on_complete&.call(self)
      self
    end

    # Tween がすべてのステップを完了（または停止）したかどうかを返します。
    #
    # - 戻り値: `Boolean`
    def completed?
      @completed
    end

    # Tween が現在実行中（未完了かつ非ポーズ中）かどうかを返します。
    #
    # - 戻り値: `Boolean`
    def active?
      !@completed && !@paused
    end

    # Tween が現在一時停止中かどうかを返します。
    #
    # - 戻り値: `Boolean`
    def paused?
      @paused
    end

    # この Tween が指定したターゲットに関与しているか判定
    #
    # - `target` (`Object`): 比較対象オブジェクト
    # - 戻り値: `Boolean`
    def involves_target?(target)
      @target.equal?(target)
    end

    # ------------------------------------------------------------------
    # 内部更新ループ (__update)
    # ------------------------------------------------------------------
    def __update(dt)
      return if @completed || @paused

      while !@completed && dt >= 0
        if @step_index >= @steps.size
          handle_loop_completion
          break if @step_index >= @steps.size || @completed
        end

        step = current_step
        break unless step
        dt = process_step(step, dt)
        break if dt.nil?
      end
    end

    private

    # ステップを処理し、余剰時間 (残 dt) を返す。継続中の場合は nil を返す
    def process_step(step, dt)
      case step[:type]
      when :call
        call_step_block(step[:block])
        advance_step
        dt

      when :delay
        @step_elapsed += dt
        if @step_elapsed >= step[:duration]
          leftover = @step_elapsed - step[:duration]
          advance_step
          leftover
        else
          nil
        end

      when :property
        init_property_step(step) unless @step_initialized

        @step_elapsed += dt
        dur = step[:duration]
        t = dur <= 0 ? 1.0 : [@step_elapsed / dur, 1.0].min
        progress = Easing.calc(step[:ease], t, step[:steps] || 1)

        actual_props = step[:actual_props]
        actual_props.each do |prop, range|
          from_v, to_v = range
          cur_val = from_v + (to_v - from_v) * progress
          cur_val = cur_val.round if step[:round]
          Tween._set_prop(@target, prop, cur_val)
        end

        if @step_elapsed >= dur
          actual_props.each do |prop, range|
            to_v = range[1]
            final_val = step[:round] ? to_v.round : to_v
            Tween._set_prop(@target, prop, final_val)
          end
          leftover = dur <= 0 ? dt : (@step_elapsed - dur)
          advance_step
          leftover
        else
          nil
        end

      when :value
        init_value_step(step) unless @step_initialized

        @step_elapsed += dt
        dur = step[:duration]
        t = dur <= 0 ? 1.0 : [@step_elapsed / dur, 1.0].min
        progress = Easing.calc(step[:ease], t, step[:steps] || 1)

        current_val = step[:actual_from] + (step[:actual_to] - step[:actual_from]) * progress
        if step[:round] == true || (step[:round].nil? && step[:is_integer])
          current_val = current_val.round
        end
        step[:block]&.call(current_val)

        if @step_elapsed >= dur
          final_val = step[:actual_to]
          if step[:round] == true || (step[:round].nil? && step[:is_integer])
            final_val = final_val.round
          end
          step[:block]&.call(final_val)
          leftover = dur <= 0 ? dt : (@step_elapsed - dur)
          advance_step
          leftover
        else
          nil
        end

      else
        advance_step
        dt
      end
    end

    def current_step
      return nil if @step_index >= @steps.size
      idx = @yoyo_reverse ? (@steps.size - 1 - @step_index) : @step_index
      @steps[idx]
    end

    def init_property_step(step)
      unless step.key?(:initial_props)
        init_map = {}
        from_map = step[:from] || {}
        step[:props].each do |prop, to_val|
          val_from = from_map[prop]
          val_from ||= Tween._get_prop(@target, prop)
          init_map[prop] = [val_from.to_f, to_val.to_f]
        end
        step[:initial_props] = init_map
      end

      # yoyo 反転の適用
      actual_map = {}
      step[:initial_props].each do |prop, range|
        if @yoyo_reverse
          actual_map[prop] = [range[1], range[0]]
        else
          actual_map[prop] = [range[0], range[1]]
        end
      end
      step[:actual_props] = actual_map

      # steps の自動推論
      if step[:steps].nil?
        ease_sym = step[:ease].is_a?(Array) ? step[:ease][0] : step[:ease]
        if ease_sym == :step && !actual_map.empty?
          first_range = actual_map.values.first
          diff = (first_range[1] - first_range[0]).abs.round
          step[:steps] = diff > 0 ? diff : 1
        end
      end

      @step_initialized = true
    end

    def init_value_step(step)
      unless step.key?(:initial_from)
        step[:is_integer] = (step[:to].is_a?(Integer) && step[:from].is_a?(Integer))
        step[:initial_from] = step[:from].to_f
      end

      if @yoyo_reverse
        step[:actual_from] = step[:to].to_f
        step[:actual_to]   = step[:initial_from]
      else
        step[:actual_from] = step[:initial_from]
        step[:actual_to]   = step[:to].to_f
      end

      if step[:steps].nil?
        ease_sym = step[:ease].is_a?(Array) ? step[:ease][0] : step[:ease]
        if ease_sym == :step
          diff = (step[:actual_to] - step[:actual_from]).abs.round
          step[:steps] = diff > 0 ? diff : 1
        end
      end

      @step_initialized = true
    end

    def advance_step
      @step_index += 1
      @step_elapsed = 0.0
      @step_initialized = false
    end

    def call_step_block(block)
      return unless block
      if block.arity == 0
        block.call
      else
        block.call(self)
      end
    end

    def handle_loop_completion
      if @yoyo
        @yoyo_reverse = !@yoyo_reverse
        @step_index = 0
        @step_elapsed = 0.0
        @step_initialized = false

        if !@yoyo_reverse && @loop_mode.is_a?(Integer)
          @loop_mode -= 1
          if @loop_mode <= 0
            @completed = true
            @on_complete&.call(self)
          end
        end
      elsif @loop_mode == :infinite
        @step_index = 0
        @step_elapsed = 0.0
        @step_initialized = false
      elsif @loop_mode.is_a?(Integer) && @loop_mode > 1
        @loop_mode -= 1
        @step_index = 0
        @step_elapsed = 0.0
        @step_initialized = false
      else
        @completed = true
        @on_complete&.call(self)
      end
    end

    alias update __update
  end

  # ====================================================================
  # Zenoo::Tweenable - Sprite 等に Tween 機能を組み込むモジュール
  # ====================================================================
  # 各オブジェクト単位で Tween を保持・管理することで、
  # オブジェクト破棄 (vanish) 時の自動停止や、ヒットストップ・ポーズとの
  # 親和性を高めます。
  # ====================================================================
  module Tweenable
    # 対象オブジェクトのアクティブな Tween 配列 (遅延初期化)
    #
    # - 戻り値: `Array<Tween>`
    def tweens
      @tweens ||= []
    end

    # 新しい Tween を作成し、このオブジェクトの管理下に登録して返す
    # ※ グローバルマネージャ (Zenoo::Tween) には登録されず、このオブジェクトの更新に同期します
    # 例: sprite.tween.to(0.5, x: 200, ease: :quad_out)
    #     sprite.tween.delay(0.2).to(0.3, alpha: 0.0).call { sprite.vanish }
    #
    # - 戻り値: `Tween`
    def tween
      t = Tween.new(self)
      tweens << t
      t
    end

    # このオブジェクトに紐づく全ての Tween を即時停止・破棄
    #
    # - 戻り値: `self`
    def kill_tweens
      return self unless @tweens
      @tweens.each(&:stop)
      @tweens.clear
      self
    end

    # このオブジェクトに紐づく全ての Tween を即時完了
    #
    # - 戻り値: `self`
    def finish_tweens
      return self unless @tweens
      @tweens.each(&:finish)
      @tweens.clear
      self
    end

    # このオブジェクトに紐づく全ての Tween を一時停止
    #
    # - 戻り値: `self`
    def pause_tweens
      return self unless @tweens
      @tweens.each(&:pause)
      self
    end

    # このオブジェクトに紐づく全ての Tween を再開
    #
    # - 戻り値: `self`
    def resume_tweens
      return self unless @tweens
      @tweens.each(&:resume)
      self
    end

    # 現在アクティブな Tween 数
    #
    # - 戻り値: `Integer`
    def tween_count
      @tweens ? @tweens.size : 0
    end

    # Tween のフレーム更新処理 (Sprite#update から自動で呼ばれます)
    #
    # - `dt` (`Float`, `nil`): 経過時間（秒）。省略時は `Window.delta_time` を使用
    def update_tweens(dt = nil)
      return if @tweens.nil? || @tweens.empty?

      dt ||= Window.delta_time

      i = 0
      while i < @tweens.size
        t = @tweens[i]
        t.__update(dt)
        if t.completed?
          @tweens.delete_at(i)
        else
          i += 1
        end
      end
    end
  end
end

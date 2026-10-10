# frozen_string_literal: true

require_relative 'easing'

module Zenoo
  # ====================================================================
  # Zenoo::Tween - 直感的・軽量なメソッドチェーン対応アニメーションシステム
  # ====================================================================
  # 主な特徴:
  # 1. メソッドチェーンによる直列実行 (.to, .delay, .call, .loop, .yoyo)
  # 2. .call { ... } による時間軸イベント（画像切替・SE再生・パーティクル等）の挿入
  # 3. 豊富なイージング (:linear, :quad_out, :bounce_out, :elastic_out, :step 等)
  # 4. オブジェクト指定一括停止 (Tween.kill(target)) や即時完了 (tween.finish)
  # ====================================================================
  class Tween
    # ------------------------------------------------------------------
    # クラスメソッド (グローバルマネージャ)
    # ------------------------------------------------------------------
    @active_tweens = []

    def self.active_tweens
      @active_tweens
    end

    # 対象オブジェクトのプロパティをアニメーション開始
    # 例: Tween.to(player, :x, to: 400, duration: 1.0, ease: :bounce_out)
    def self.to(target = nil, property = nil, to: nil, duration: 0.0, ease: :linear, delay: 0.0, from: nil)
      tween = new
      tween.to(target, property, to: to, duration: duration, ease: ease, delay: delay, from: from)
      register(tween)
      tween
    end

    # 数値範囲を補間してブロックへ渡す（直接描画やカスタム値更新用）
    # 例: Tween.value(from: 0.0, to: 1.0, duration: 0.5) { |v| alpha = v }
    def self.value(from:, to:, duration: 0.0, ease: :linear, delay: 0.0, &block)
      tween = new
      tween.value(from: from, to: to, duration: duration, ease: ease, delay: delay, &block)
      register(tween)
      tween
    end

    # 待機から始まるチェーンを作成
    # 例: Tween.delay(0.5).to(player, :y, to: 100)
    def self.delay(duration)
      tween = new
      tween.delay(duration)
      register(tween)
      tween
    end

    # 即座（または遅延後）にブロックを実行するステップから始まるチェーンを作成
    # 例: Tween.call { Sound.play(:start) }.delay(0.2).to(...)
    def self.call(&block)
      tween = new
      tween.call(&block)
      register(tween)
      tween
    end

    # 対象オブジェクトに関わる全ての Tween を破棄・中断
    def self.kill(target)
      return if target.nil?
      @active_tweens.each do |t|
        t.stop if t.involves_target?(target)
      end
    end

    def self.stop_all(target = nil)
      if target
        kill(target)
      else
        clear
      end
    end

    # 全ての Tween を強制クリア
    def self.clear
      @active_tweens.each(&:stop)
      @active_tweens.clear
    end

    # 対象オブジェクトの全 Tween を最終状態にスキップして完了
    def self.finish_all(target = nil)
      if target
        @active_tweens.each do |t|
          t.finish if t.involves_target?(target)
        end
      else
        @active_tweens.each(&:finish)
      end
    end

    # 全 Tween の一時停止 / 再開
    def self.pause_all
      @active_tweens.each(&:pause)
    end

    def self.resume_all
      @active_tweens.each(&:resume)
    end

    # 現在アクティブな Tween 数
    def self.count
      @active_tweens.size
    end

    # マネージャに登録
    def self.register(tween)
      @active_tweens << tween unless @active_tweens.include?(tween)
    end

    # マネージャから解除
    def self.unregister(tween)
      @active_tweens.delete(tween)
    end

    # エンジン内部フレーム更新 (Window.__update_step から自動呼び出し)
    def self.__update_step(dt)
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

    # ------------------------------------------------------------------
    # インスタンス実装
    # ------------------------------------------------------------------
    attr_reader :last_target

    def initialize
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
      @last_target = nil
      @on_complete = nil
    end

    # チェーンの次のステップとしてプロパティ変更を追加
    def to(target = :__keep__, property = nil, to: nil, duration: 0.0, ease: :linear, delay: 0.0, from: nil)
      # 引数の柔軟な解決 (t.to(:y, to: 200) のように target 省略を許容)
      if target.is_a?(Symbol) && property.nil? && !to.nil?
        property = target
        target = @last_target
      elsif target == :__keep__
        target = @last_target
      else
        @last_target = target
      end

      # delay が指定されていれば先に delay ステップを追加
      self.delay(delay) if delay && delay > 0

      @steps << {
        type: :property,
        target: target,
        property: property,
        to: to,
        duration: [duration.to_f, 0.0].max,
        ease: ease,
        from: from
      }
      self
    end

    # チェーンの次のステップとして待機時間を追加
    def delay(duration)
      @steps << {
        type: :delay,
        duration: [duration.to_f, 0.0].max
      }
      self
    end

    # チェーンの次のステップとしてブロック実行を追加
    # ブロック引数 |t| には Tween 自身が渡される (引数なしブロックも可)
    def call(&block)
      @steps << {
        type: :call,
        block: block
      }
      self
    end

    # 数値補間ステップを追加
    def value(from:, to:, duration: 0.0, ease: :linear, delay: 0.0, &block)
      self.delay(delay) if delay && delay > 0
      @steps << {
        type: :value,
        from: from,
        to: to,
        duration: [duration.to_f, 0.0].max,
        ease: ease,
        block: block
      }
      self
    end

    # ループ回数を指定 (count = true または :infinite で無限ループ)
    def loop(count = true)
      @loop_mode = (count == true || count == :infinite) ? :infinite : count.to_i
      @initial_loop = @loop_mode
      self
    end
    alias repeat loop

    # 順再生と逆再生を交互に行う
    def yoyo(count = true)
      @yoyo = true
      loop(count)
      self
    end

    # 全工程完了時のコールバック
    def on_complete(&block)
      @on_complete = block
      self
    end

    # 制御メソッド
    def stop
      @completed = true
      Tween.unregister(self)
      self
    end

    def kill
      stop
    end

    def pause
      @paused = true
      self
    end

    def resume
      @paused = false
      self
    end

    # 全ステップを瞬時に最終状態にして完了
    def finish
      return if @completed

      # 残りの全プロパティステップの最終値を即時反映
      @steps.each do |step|
        case step[:type]
        when :property
          step[:target]&.send("#{step[:property]}=", step[:to])
        when :value
          step[:block]&.call(step[:to])
        when :call
          call_step_block(step[:block])
        end
      end

      @completed = true
      Tween.unregister(self)
      @on_complete&.call(self)
      self
    end

    def completed?
      @completed
    end

    def active?
      !@completed && !@paused
    end

    def paused?
      @paused
    end

    # この Tween が指定したターゲットに関与しているか判定
    def involves_target?(target)
      @steps.any? { |s| s[:type] == :property && s[:target].equal?(target) }
    end

    # ------------------------------------------------------------------
    # 内部更新ループ (__update)
    # ------------------------------------------------------------------
    def __update(dt)
      return if @completed || @paused

      # 1 フレーム内に複数の瞬時ステップ (:call 等) が連続する場合があるため while で進行
      while !@completed && dt >= 0
        if @step_index >= @steps.size
          handle_loop_completion
          break if @step_index >= @steps.size || @completed
        end

        step = current_step
        break unless step
        dt = process_step(step, dt)
        break if dt.nil? # ステップが継続中の場合はフレーム終了
      end
    end

    private

    # ステップを処理し、余剰時間 (残 dt) を返す。継続中の場合は nil を返す
    def process_step(step, dt)
      case step[:type]
      when :call
        call_step_block(step[:block])
        advance_step
        dt # 消費時間 0 なのでそのまま dt を次に渡す

      when :delay
        @step_elapsed += dt
        if @step_elapsed >= step[:duration]
          leftover = @step_elapsed - step[:duration]
          advance_step
          leftover
        else
          nil # まだ待機中
        end

      when :property
        init_property_step(step) unless @step_initialized

        @step_elapsed += dt
        dur = step[:duration]
        t = dur <= 0 ? 1.0 : [@step_elapsed / dur, 1.0].min
        progress = Easing.calc(step[:ease], t)

        current_val = step[:actual_from] + (step[:actual_to] - step[:actual_from]) * progress
        step[:target].send("#{step[:property]}=", current_val)

        if @step_elapsed >= dur
          # 最終値を確実にセット
          step[:target].send("#{step[:property]}=", step[:actual_to])
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
        progress = Easing.calc(step[:ease], t)

        current_val = step[:actual_from] + (step[:actual_to] - step[:actual_from]) * progress
        step[:block]&.call(current_val)

        if @step_elapsed >= dur
          step[:block]&.call(step[:actual_to])
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
      # 初回実行時に起点 (initial_from) を記録
      unless step.key?(:initial_from)
        from = step[:from]
        if from.nil?
          begin
            from = step[:target].send(step[:property])
          rescue StandardError
            from = 0.0
          end
        end
        step[:initial_from] = from.to_f
      end

      if @yoyo_reverse
        step[:actual_from] = step[:to].to_f
        step[:actual_to]   = step[:initial_from]
      else
        step[:actual_from] = step[:initial_from]
        step[:actual_to]   = step[:to].to_f
      end

      @step_initialized = true
    end

    def init_value_step(step)
      step[:initial_from] ||= step[:from].to_f

      if @yoyo_reverse
        step[:actual_from] = step[:to].to_f
        step[:actual_to]   = step[:initial_from]
      else
        step[:actual_from] = step[:initial_from]
        step[:actual_to]   = step[:to].to_f
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
        # yoyo: 往復切り替え
        @yoyo_reverse = !@yoyo_reverse
        @step_index = 0
        @step_elapsed = 0.0
        @step_initialized = false

        # 往復（1往復 = 順+逆）完了時のカウント減算
        if !@yoyo_reverse && @loop_mode.is_a?(Integer)
          @loop_mode -= 1
          if @loop_mode <= 0
            @completed = true
            @on_complete&.call(self)
          end
        end
      elsif @loop_mode == :infinite
        # 無限ループ
        @step_index = 0
        @step_elapsed = 0.0
        @step_initialized = false
      elsif @loop_mode.is_a?(Integer) && @loop_mode > 1
        # 回数指定ループ
        @loop_mode -= 1
        @step_index = 0
        @step_elapsed = 0.0
        @step_initialized = false
      else
        # 全工程終了
        @completed = true
        @on_complete&.call(self)
      end
    end
  end
end

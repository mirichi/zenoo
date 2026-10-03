# frozen_string_literal: true

module Zenoo
  # 動的波形生成・効果音ファクトリクラス (SoundEffect)
  # 生成されたサウンドはすべて Zenoo::Sound インスタンスとして統一的に操作可能
  class SoundEffect
    TWO_PI = Math::PI * 2.0

    class << self
      # 単音トーン生成
      # @param frequency [Numeric] 周波数 (Hz, 例: 440)
      # @param duration [Numeric] 長さ (秒, デフォルト: 0.5)
      # @param type [Symbol] 波形種別 (:sine, :square, :triangle, :sawtooth)
      # @param volume [Numeric] 音量 (0.0 .. 1.0)
      # @param attack [Numeric] アタック時間 (秒, クリックノイズ防止)
      # @param release [Numeric] リリース時間 (秒, クリックノイズ防止)
      # @param sample_rate [Integer] サンプリングレート (Hz)
      # @return [Sound] 生成された Sound インスタンス
      def tone(frequency, duration = 0.5, type: :sine, volume: 1.0, attack: 0.005, release: 0.01, sample_rate: 44100)
        total_frames = (duration * sample_rate).to_i
        return Sound.from_pcm([], sample_rate: sample_rate) if total_frames <= 0

        attack_frames = (attack * sample_rate).to_i
        release_frames = (release * sample_rate).to_i

        samples = Array.new(total_frames)
        freq = frequency.to_f
        vol = volume.to_f

        i = 0
        while i < total_frames
          t = i.to_f / sample_rate
          phase = (freq * t) % 1.0

          # 波形計算
          sample = calculate_waveform(phase, type)

          # エンベロープ (クリックノイズ低減)
          env = 1.0
          if i < attack_frames && attack_frames > 0
            env = i.to_f / attack_frames
          elsif i >= total_frames - release_frames && release_frames > 0
            env = (total_frames - i).to_f / release_frames
          end

          samples[i] = sample * vol * env
          i += 1
        end

        Sound.from_pcm(samples, channels: 1, sample_rate: sample_rate)
      end

      # 周波数スイープ (ピッチベンド、レーザー音、ジャンプ音など)
      # @param freq_start [Numeric] 開始周波数 (Hz)
      # @param freq_end [Numeric] 終了周波数 (Hz)
      # @param duration [Numeric] 長さ (秒)
      # @param type [Symbol] 波形種別 (:sine, :square, :triangle, :sawtooth)
      # @param volume [Numeric] 音量 (0.0 .. 1.0)
      # @return [Sound] 生成された Sound インスタンス
      def sweep(freq_start, freq_end, duration = 0.5, type: :sine, volume: 1.0, attack: 0.005, release: 0.01, sample_rate: 44100)
        total_frames = (duration * sample_rate).to_i
        return Sound.from_pcm([], sample_rate: sample_rate) if total_frames <= 0

        attack_frames = (attack * sample_rate).to_i
        release_frames = (release * sample_rate).to_i

        samples = Array.new(total_frames)
        f0 = freq_start.to_f
        f1 = freq_end.to_f
        vol = volume.to_f
        dur = duration.to_f

        i = 0
        while i < total_frames
          t = i.to_f / sample_rate
          # 瞬時周波数の積分による位相計算: φ(t) = f0 * t + 0.5 * ((f1 - f0) / dur) * t^2
          phase = (f0 * t + 0.5 * ((f1 - f0) / dur) * (t * t)) % 1.0

          sample = calculate_waveform(phase, type)

          env = 1.0
          if i < attack_frames && attack_frames > 0
            env = i.to_f / attack_frames
          elsif i >= total_frames - release_frames && release_frames > 0
            env = (total_frames - i).to_f / release_frames
          end

          samples[i] = sample * vol * env
          i += 1
        end

        Sound.from_pcm(samples, channels: 1, sample_rate: sample_rate)
      end

      # ホワイトノイズ生成 (爆発音、打楽器、摩擦音など)
      # @param duration [Numeric] 長さ (秒)
      # @param volume [Numeric] 音量 (0.0 .. 1.0)
      # @param attack [Numeric] アタック時間 (秒)
      # @param release [Numeric] リリース時間 (秒, 長めにすると爆発音風)
      # @return [Sound] 生成された Sound インスタンス
      def noise(duration = 0.5, volume: 1.0, attack: 0.002, release: 0.1, sample_rate: 44100)
        total_frames = (duration * sample_rate).to_i
        return Sound.from_pcm([], sample_rate: sample_rate) if total_frames <= 0

        attack_frames = (attack * sample_rate).to_i
        release_frames = (release * sample_rate).to_i

        samples = Array.new(total_frames)
        vol = volume.to_f
        rng = Random.new

        i = 0
        while i < total_frames
          # -1.0 .. 1.0 の一様乱数
          sample = rng.rand * 2.0 - 1.0

          env = 1.0
          if i < attack_frames && attack_frames > 0
            env = i.to_f / attack_frames
          elsif i >= total_frames - release_frames && release_frames > 0
            env = (total_frames - i).to_f / release_frames
          end

          samples[i] = sample * vol * env
          i += 1
        end

        Sound.from_pcm(samples, channels: 1, sample_rate: sample_rate)
      end

      # 任意の数式ブロックからサウンドを生成
      # @param duration [Numeric] 長さ (秒)
      # @param sample_rate [Integer] サンプリングレート (Hz)
      # @yieldparam t [Float] 現在の経過時間 (秒)
      # @yieldreturn [Float] -1.0 .. 1.0 のサンプル値
      # @return [Sound] 生成された Sound インスタンス
      def create(duration, sample_rate: 44100)
        total_frames = (duration * sample_rate).to_i
        return Sound.from_pcm([], sample_rate: sample_rate) if total_frames <= 0

        samples = Array.new(total_frames)
        i = 0
        while i < total_frames
          t = i.to_f / sample_rate
          samples[i] = yield(t).to_f
          i += 1
        end

        Sound.from_pcm(samples, channels: 1, sample_rate: sample_rate)
      end

      private

      # 位相 (0.0 .. 1.0) と波形種別からサンプル値 (-1.0 .. 1.0) を計算
      def calculate_waveform(phase, type)
        case type
        when :sine
          Math.sin(phase * TWO_PI)
        when :square
          phase < 0.5 ? 1.0 : -1.0
        when :triangle
          phase < 0.5 ? (4.0 * phase - 1.0) : (3.0 - 4.0 * phase)
        when :sawtooth
          2.0 * phase - 1.0
        else
          Math.sin(phase * TWO_PI)
        end
      end
    end
  end
end

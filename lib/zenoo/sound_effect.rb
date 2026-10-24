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

      # 統合シンセサイザー (PCM配列生成)
      # エディタ (tools/sound_generator.rb) 互換のパラメータ群から [-1.0 .. 1.0] の Float サンプル配列を生成
      def synthesize_pcm(
        wave: :square,
        freq: 440.0,
        min_freq: 20.0,
        slide: 0.0,
        slide_accel: 0.0,
        duty: 0.5,
        duty_sweep: 0.0,
        vib_depth: 0.0,
        vib_speed: 10.0,
        attack: 0.005,
        sustain: 0.1,
        punch: 0.0,
        decay: 0.15,
        arp_mod: 1.0,
        arp_time: 0.0,
        lpf_cutoff: 20000.0,
        volume: 0.8,
        sample_rate: 44100
      )
        total_time = attack.to_f + sustain.to_f + decay.to_f
        total_time = 0.05 if total_time < 0.05
        sr = sample_rate.to_i
        total_frames = (total_time * sr).to_i
        return [] if total_frames <= 0

        attack_frames  = (attack.to_f * sr).to_i
        sustain_frames = (sustain.to_f * sr).to_i
        decay_frames   = (decay.to_f * sr).to_i
        arp_frame      = (arp_time.to_f * sr).to_i

        samples = Array.new(total_frames)

        cur_freq  = freq.to_f
        min_f     = min_freq.to_f
        cur_slide = slide.to_f
        s_accel   = slide_accel.to_f
        cur_duty  = duty.to_f
        d_sweep   = duty_sweep.to_f
        v_depth   = vib_depth.to_f
        v_speed   = vib_speed.to_f
        p_punch   = punch.to_f
        a_mod     = arp_mod.to_f
        a_time    = arp_time.to_f
        vol       = volume.to_f
        lpf_cut   = lpf_cutoff.to_f

        wave_type = case wave
                    when :square, 0 then 0
                    when :sawtooth, :saw, 1 then 1
                    when :sine, 2 then 2
                    when :triangle, :tri, 3 then 3
                    when :noise, 4 then 4
                    else 0
                    end

        phase   = 0.0
        lpf_val = 0.0

        lpf_cut = 100.0 if lpf_cut < 100.0
        max_cut = sr * 0.45
        lpf_cut = max_cut if lpf_cut > max_cut
        lpf_alpha = 1.0 - Math.exp(-TWO_PI * lpf_cut / sr)

        dt = 1.0 / sr
        rng = Random.new

        i = 0
        while i < total_frames
          t = i * dt

          cur_slide += s_accel * dt
          cur_freq  += cur_slide * dt
          cur_freq   = min_f if cur_freq < min_f

          eff_freq = cur_freq
          if a_mod != 1.0 && a_time > 0.0 && i >= arp_frame
            eff_freq *= a_mod
          end

          if v_depth > 0.0
            eff_freq += Math.sin(t * v_speed * TWO_PI) * v_depth
          end
          eff_freq = 10.0 if eff_freq < 10.0

          cur_duty += d_sweep * dt
          cur_duty = 0.05 if cur_duty < 0.05
          cur_duty = 0.95 if cur_duty > 0.95

          phase = (phase + eff_freq * dt) % 1.0

          raw_sample = case wave_type
                       when 0
                         phase < cur_duty ? 1.0 : -1.0
                       when 1
                         2.0 * phase - 1.0
                       when 2
                         Math.sin(phase * TWO_PI)
                       when 3
                         phase < 0.5 ? (4.0 * phase - 1.0) : (3.0 - 4.0 * phase)
                       when 4
                         rng.rand * 2.0 - 1.0
                       else
                         Math.sin(phase * TWO_PI)
                       end

          if lpf_cut < 19000.0
            lpf_val += (raw_sample - lpf_val) * lpf_alpha
            raw_sample = lpf_val
          end

          env = 0.0
          if i < attack_frames && attack_frames > 0
            env = i.to_f / attack_frames
          elsif i < attack_frames + sustain_frames
            sustain_progress = (i - attack_frames).to_f / [sustain_frames, 1].max
            env = 1.0 + p_punch * (1.0 - sustain_progress)
          else
            decay_pos = i - (attack_frames + sustain_frames)
            env = [1.0 - (decay_pos.to_f / [decay_frames, 1].max), 0.0].max
          end

          sample_out = raw_sample * env * vol
          sample_out = -1.0 if sample_out < -1.0
          sample_out = 1.0 if sample_out > 1.0
          samples[i] = sample_out

          i += 1
        end

        samples
      end

      # 統合シンセサイザー (Sound インスタンス生成)
      # synthesize_pcm で生成された波形から直接 Sound インスタンスを生成
      def synthesize(
        wave: :square,
        freq: 440.0,
        min_freq: 20.0,
        slide: 0.0,
        slide_accel: 0.0,
        duty: 0.5,
        duty_sweep: 0.0,
        vib_depth: 0.0,
        vib_speed: 10.0,
        attack: 0.005,
        sustain: 0.1,
        punch: 0.0,
        decay: 0.15,
        arp_mod: 1.0,
        arp_time: 0.0,
        lpf_cutoff: 20000.0,
        volume: 0.8,
        sample_rate: 44100
      )
        samples = synthesize_pcm(
          wave: wave, freq: freq, min_freq: min_freq, slide: slide, slide_accel: slide_accel,
          duty: duty, duty_sweep: duty_sweep, vib_depth: vib_depth, vib_speed: vib_speed,
          attack: attack, sustain: sustain, punch: punch, decay: decay,
          arp_mod: arp_mod, arp_time: arp_time, lpf_cutoff: lpf_cutoff, volume: volume,
          sample_rate: sample_rate
        )
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

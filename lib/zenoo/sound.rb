# frozen_string_literal: true

module Zenoo
  # オーディオシステム制御モジュール
  module Audio
    @bus_volumes = {
      master: 1.0,
      bgm: 1.0,
      se: 1.0,
      voice: 1.0
    }
    @active_sounds = []
    @audio_time = 0.0
    @audio_frame = 0
    @oneshot_cache = {}

    class << self
      def time
        @audio_time || 0.0
      end

      def frame_count
        @audio_frame || 0
      end

      def master_volume
        Native::Audio.master_volume
      end

      def master_volume=(vol)
        Native::Audio.master_volume = vol.to_f
      end

      # バス音量取得 / 設定 (引数が2つの場合は設定)
      def bus_volume(bus = :master, vol = nil)
        if vol.nil?
          b = bus.to_sym
          @bus_volumes[b] || 1.0
        else
          set_bus_volume(bus, vol)
        end
      end

      # バス音量設定
      def set_bus_volume(bus, vol)
        b = bus.to_sym
        v = vol.to_f
        @bus_volumes[b] = v
        # このバスを使用している全サウンドの実効音量を更新
        i = 0
        len = @active_sounds.length
        while i < len
          s = @active_sounds[i]
          s.__update_volume if s && s.bus == b
          i += 1
        end
        v
      end

      # バス音量セッター（単一引数 / 多重代入 / 2引数呼び出し対応）
      def bus_volume=(bus_or_args, vol = nil)
        if vol
          set_bus_volume(bus_or_args, vol)
        elsif bus_or_args.is_a?(Array) && bus_or_args.length >= 2
          set_bus_volume(bus_or_args[0], bus_or_args[1])
        elsif bus_or_args.is_a?(Hash)
          bus_or_args.each { |k, val| set_bus_volume(k, val) }
        end
      end

      # フレーム毎のオーディオ更新 (フェード制御・タイマー更新)
      def update(dt = nil)
        frame_dt = dt ? dt.to_f : Window.delta_time
        @audio_time = (@audio_time || 0.0) + frame_dt
        @audio_frame = (@audio_frame || 0) + 1
        return if @active_sounds.empty?

        i = 0
        while i < @active_sounds.length
          s = @active_sounds[i]
          if s
            s.__update_fade(frame_dt)
            # フェードも終了し再生もしていなければ追跡リストから除外
            if !s.fading? && !s.playing?
              @active_sounds.delete_at(i)
              next
            end
          end
          i += 1
        end
      end

      def __register_sound(sound)
        @active_sounds << sound unless @active_sounds.include?(sound)
      end

      def __cached_oneshot(path, bus, stream, max_polyphony, min_interval, dedup_frame, polyphony_behavior)
        key = "#{path}:#{bus}:#{stream}"
        sound = @oneshot_cache[key]
        unless sound
          sound = Sound.load(path, bus: bus, stream: stream)
          sound.max_polyphony = max_polyphony
          sound.min_interval = min_interval
          sound.dedup_frame = dedup_frame
          sound.polyphony_behavior = polyphony_behavior
          @oneshot_cache[key] = sound
        end
        sound
      end

      # 再生中の全サウンドを一時停止
      def pause_all
        i = 0
        len = @active_sounds.length
        while i < len
          s = @active_sounds[i]
          s.pause if s && s.playing?
          i += 1
        end
      end

      # 一時停止中のサウンドを再開
      def resume_all
        i = 0
        len = @active_sounds.length
        while i < len
          s = @active_sounds[i]
          s.play if s && !s.playing?
          i += 1
        end
      end

      def init
        Native::Audio.init
      end

      def shutdown
        Native::Audio.shutdown
      end
    end
  end

  # サウンド再生クラス (WAV, MP3, OGG, PCM動的生成 共通)
  class Sound
    attr_reader :path
    attr_accessor :bus
    attr_accessor :max_polyphony
    attr_accessor :polyphony_behavior
    attr_accessor :min_interval
    attr_accessor :dedup_frame

    def stream?
      @stream
    end

    class << self
      # ファイルからサウンドをロード (stream: true でストリーミング再生)
      def load(path, bus: :se, stream: false, loop: false,
               loop_start: nil, loop_end: nil,
               loop_start_sample: nil, loop_end_sample: nil,
               max_polyphony: nil, min_interval: 0.0, dedup_frame: true,
               polyphony_behavior: :stop_oldest)
        sound = new(path, stream: stream)
        sound.bus = bus
        sound.looping = loop if loop

        if loop_start_sample || loop_end_sample
          sound.set_loop_points_pcm(loop_start_sample || 0, loop_end_sample || 0)
        elsif loop_start || loop_end
          sound.set_loop_points(loop_start || 0.0, loop_end || 0.0)
        end

        sound.max_polyphony = max_polyphony
        sound.min_interval = min_interval
        sound.dedup_frame = dedup_frame
        sound.polyphony_behavior = polyphony_behavior
        sound
      end

      # ワンショット再生用の簡易メソッド (重複抑制・同時発音数制御付き)
      def play(path, volume: 1.0, bus: :se, stream: false,
               max_polyphony: 3, min_interval: 0.03, dedup_frame: true,
               polyphony_behavior: :stop_oldest)
        sound = Audio.__cached_oneshot(path, bus, stream, max_polyphony, min_interval, dedup_frame, polyphony_behavior)
        sound.volume = volume if volume != sound.volume
        sound.play
        sound
      end

      # PCMサンプル配列またはバイナリ文字列から Sound インスタンスを生成
      def from_pcm(samples, channels: 1, sample_rate: 44100, bus: :se)
        if samples.is_a?(Array)
          packed = samples.pack('e*')
          native_sound = Native::Sound.load_pcm(packed, channels, sample_rate)
        else
          native_sound = Native::Sound.load_pcm(samples, channels, sample_rate)
        end

        sound = new(native_sound)
        sound.bus = bus
        sound.__set_pcm_data(samples, channels, sample_rate)
        sound
      end
    end

    def initialize(source, stream: false)
      if source.is_a?(String)
        @path = source.to_s
        @stream = !!stream
        @native = Native::Sound.load(@path, @stream)
      else
        @path = nil
        @stream = false
        @native = source
      end

      @pcm_samples = nil
      @pcm_channels = 1
      @pcm_sample_rate = 44100

      @bus = :se
      @base_volume = @native.volume
      @fade_volume = 1.0
      @fade_target = 1.0
      @fade_speed = 0.0 # 1秒あたりの変化量
      @fade_stop_on_complete = false

      # 同時発音数制御 & 重複抑制
      @max_polyphony = nil
      @polyphony_behavior = :stop_oldest
      @min_interval = 0.0
      @dedup_frame = true
      @last_play_time = -999.0
      @last_play_frame = -1

      @voices = [@native]
      @voice_times = [0.0]
      @voice_frames = [0]
    end

    def __set_pcm_data(samples, channels, sample_rate)
      @pcm_samples = samples
      @pcm_channels = channels
      @pcm_sample_rate = sample_rate
    end

    # 再生開始 (同一フレーム重複抑制、最小インターバル、多重発音数制限対応)
    def play
      cur_frame = Audio.frame_count
      cur_time = Audio.time

      # 1. 同一フレーム内の重複抑制
      if @dedup_frame && @last_play_frame == cur_frame
        return self
      end

      # 2. 最小発音間隔チェック (クールダウン)
      if @min_interval > 0.0 && (cur_time - @last_play_time) < @min_interval
        return self
      end

      # 3. 再生ボイスの確保 (ポリフォニー制御)
      voice = __acquire_voice(cur_time, cur_frame)
      return self unless voice

      @last_play_frame = cur_frame
      @last_play_time = cur_time
      @fade_speed = 0.0
      @fade_volume = 1.0

      __update_voice_volume(voice)

      # 再生中の場合は先頭へシークしてリトリガー
      voice.seek(0.0) if voice.playing?
      voice.play

      Audio.__register_sound(self)
      self
    end

    # 停止 (全ボイスの再生を停止し、先頭にリセット)
    def stop
      @fade_speed = 0.0
      i = 0
      while i < @voices.length
        @voices[i].stop
        i += 1
      end
      self
    end

    # 一時停止 (全ボイスの再生位置を保持して停止)
    def pause
      @fade_speed = 0.0
      i = 0
      while i < @voices.length
        @voices[i].pause
        i += 1
      end
      self
    end

    # フェードイン再生
    def fade_in(duration = 1.0, target_volume: nil)
      @base_volume = target_volume.to_f if target_volume
      @fade_volume = 0.0
      @fade_target = 1.0
      sec = [duration.to_f, 0.001].max
      @fade_speed = 1.0 / sec
      @fade_stop_on_complete = false
      __update_volume
      play unless playing?
      Audio.__register_sound(self)
      self
    end

    # フェードアウト
    def fade_out(duration = 1.0, stop_on_complete: true)
      return self unless playing?
      @fade_target = 0.0
      sec = [duration.to_f, 0.001].max
      cur = @fade_volume > 0.0 ? @fade_volume : 1.0
      @fade_speed = -(cur / sec)
      @fade_stop_on_complete = stop_on_complete
      Audio.__register_sound(self)
      self
    end

    # フェード中かどうか
    def fading?
      @fade_speed != 0.0
    end

    # 内部フェード計算 (Audio.update から呼ばれる)
    def __update_fade(dt)
      return if @fade_speed == 0.0

      @fade_volume += @fade_speed * dt
      if @fade_speed > 0.0 && @fade_volume >= @fade_target
        @fade_volume = @fade_target
        @fade_speed = 0.0
      elsif @fade_speed < 0.0 && @fade_volume <= @fade_target
        @fade_volume = @fade_target
        @fade_speed = 0.0
        if @fade_stop_on_complete
          stop
        else
          pause
        end
      end
      __update_volume
    end

    # 実効音量の再計算と全ボイスへの反映
    def __update_volume
      bus_vol = Audio.bus_volume(@bus)
      eff = @base_volume * bus_vol * @fade_volume
      i = 0
      while i < @voices.length
        @voices[i].volume = eff
        i += 1
      end
    end

    def __update_voice_volume(voice)
      bus_vol = Audio.bus_volume(@bus)
      voice.volume = @base_volume * bus_vol * @fade_volume
    end

    # 再生中かどうか (いずれかのボイスが再生中であれば true)
    def playing?
      i = 0
      while i < @voices.length
        return true if @voices[i].playing?
        i += 1
      end
      false
    end

    # ユーザー設定音量 (0.0 .. 1.0 またはそれ以上)
    def volume
      @base_volume
    end

    def volume=(vol)
      @base_volume = vol.to_f
      __update_volume
    end

    # ループ再生フラグ
    def looping?
      @native.looping?
    end

    def looping=(loop_flag)
      flag = !!loop_flag
      i = 0
      while i < @voices.length
        @voices[i].looping = flag
        i += 1
      end
      flag
    end

    # ピッチ / 再生速度
    def pitch
      @native.pitch
    end

    def pitch=(p)
      val = p.to_f
      i = 0
      while i < @voices.length
        @voices[i].pitch = val
        i += 1
      end
      val
    end

    # パン (-1.0: 左, 0.0: 中央, 1.0: 右)
    def pan
      @native.pan
    end

    def pan=(p)
      val = p.to_f
      i = 0
      while i < @voices.length
        @voices[i].pan = val
        i += 1
      end
      val
    end

    # シーク (秒数)
    def seek(seconds)
      sec = seconds.to_f
      i = 0
      while i < @voices.length
        @voices[i].seek(sec)
        i += 1
      end
      self
    end

    # 現在の再生位置 (秒数)
    def time
      @native.cursor
    end

    def time=(seconds)
      seek(seconds)
    end

    # サウンドの全長 (秒数)
    def length
      @native.length
    end

    # サンプリングレート (Hz)
    def sample_rate
      @native.sample_rate
    end

    # サウンドの全長 (PCMサンプル数)
    def length_pcm
      @native.length_pcm
    end

    # ==========================================
    # ループポイント制御 (イントロ付きループ等)
    # ==========================================
    def set_loop_points(start = 0.0, end_point = 0.0)
      s_sec = start.to_f
      e_sec = end_point.to_f
      i = 0
      while i < @voices.length
        @voices[i].set_loop_points(s_sec, e_sec)
        i += 1
      end
      self
    end

    def set_loop_points_pcm(start_pcm = 0, end_pcm = 0)
      s_frame = start_pcm.to_i
      e_frame = end_pcm.to_i
      i = 0
      while i < @voices.length
        @voices[i].set_loop_points_pcm(s_frame, e_frame)
        i += 1
      end
      self
    end

    def loop_start
      @native.loop_start
    end

    def loop_start=(sec)
      s_sec = sec.to_f
      i = 0
      while i < @voices.length
        @voices[i].loop_start = s_sec
        i += 1
      end
      s_sec
    end

    def loop_end
      @native.loop_end
    end

    def loop_end=(sec)
      e_sec = sec.to_f
      i = 0
      while i < @voices.length
        @voices[i].loop_end = e_sec
        i += 1
      end
      e_sec
    end

    def loop_start_sample
      @native.loop_start_pcm
    end
    alias loop_start_pcm loop_start_sample

    def loop_start_sample=(pcm)
      val = pcm.to_i
      i = 0
      while i < @voices.length
        @voices[i].loop_start_pcm = val
        i += 1
      end
      val
    end
    alias loop_start_pcm= loop_start_sample=

    def loop_end_sample
      @native.loop_end_pcm
    end
    alias loop_end_pcm loop_end_sample

    def loop_end_sample=(pcm)
      val = pcm.to_i
      i = 0
      while i < @voices.length
        @voices[i].loop_end_pcm = val
        i += 1
      end
      val
    end
    alias loop_end_pcm= loop_end_sample=

    def has_loop_points?
      @native.has_loop_points?
    end

    def clear_loop_points
      i = 0
      while i < @voices.length
        @voices[i].clear_loop_points
        i += 1
      end
      self
    end

    private

    # 同時発音数制御のためのボイス選択 / 拡張
    def __acquire_voice(cur_time, cur_frame)
      max_p = @max_polyphony
      if max_p.nil? || max_p <= 1
        @voice_times[0] = cur_time
        @voice_frames[0] = cur_frame
        return @native
      end

      # 停止中のボイスを探す
      i = 0
      while i < @voices.length
        unless @voices[i].playing?
          @voice_times[i] = cur_time
          @voice_frames[i] = cur_frame
          return @voices[i]
        end
        i += 1
      end

      # 空きボイスがなく、上限未満なら新規作成
      if @voices.length < max_p
        new_v = __create_new_voice
        if new_v
          @voices << new_v
          @voice_times << cur_time
          @voice_frames << cur_frame
          return new_v
        end
      end

      # 上限到達時の振る舞い
      if @polyphony_behavior == :drop
        nil
      else
        # :stop_oldest - 最も古いボイスを停止して再利用
        oldest_idx = 0
        min_t = @voice_times[0] || 0.0
        j = 1
        while j < @voice_times.length
          if (@voice_times[j] || 0.0) < min_t
            min_t = @voice_times[j]
            oldest_idx = j
          end
          j += 1
        end

        voice = @voices[oldest_idx]
        voice.stop
        @voice_times[oldest_idx] = cur_time
        @voice_frames[oldest_idx] = cur_frame
        voice
      end
    end

    # ボイスプール用の同一サウンドインスタンス複製
    def __create_new_voice
      nv = if @path
             Native::Sound.load(@path, @stream)
           elsif @pcm_samples
             if @pcm_samples.is_a?(Array)
               Native::Sound.load_pcm(@pcm_samples.pack('e*'), @pcm_channels, @pcm_sample_rate)
             else
               Native::Sound.load_pcm(@pcm_samples, @pcm_channels, @pcm_sample_rate)
             end
           else
             nil
           end
      return nil unless nv

      # 基本パラメータの同期
      nv.volume = @native.volume
      nv.pitch = @native.pitch
      nv.pan = @native.pan
      nv.looping = @native.looping?
      if @native.has_loop_points?
        nv.set_loop_points_pcm(@native.loop_start_pcm, @native.loop_end_pcm)
      end
      nv
    end
  end
end

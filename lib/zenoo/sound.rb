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

    class << self
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

      # 多重代入 Audio.bus_volume = :bgm, 0.8 対応
      def bus_volume=(args)
        if args.is_a?(Array) && args.length >= 2
          set_bus_volume(args[0], args[1])
        elsif args.is_a?(Hash)
          args.each { |k, val| set_bus_volume(k, val) }
        end
      end

      # フレーム毎のオーディオ更新 (フェード制御)
      def update(dt = nil)
        frame_dt = dt ? dt.to_f : Window.delta_time
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

    class << self
      # ファイルからサウンドをロード
      def load(path, bus: :se)
        sound = new(path)
        sound.bus = bus
        sound
      end

      # ワンショット再生用の簡易メソッド
      def play(path, volume: 1.0, bus: :se)
        sound = load(path, bus: bus)
        sound.volume = volume if volume != 1.0
        sound.play
        sound
      end

      # PCMサンプル配列またはバイナリ文字列から Sound インスタンスを生成
      # samples: [-1.0 .. 1.0] の Float 配列、または pack("e*") などの Float32 バイナリ文字列
      def from_pcm(samples, channels: 1, sample_rate: 44100, bus: :se)
        if samples.is_a?(Array)
          # Float 配列を Float32 リトルエンディアンのバイナリ文字列にパックして渡す (高速)
          packed = samples.pack('e*')
          native_sound = Native::Sound.load_pcm(packed, channels, sample_rate)
        else
          native_sound = Native::Sound.load_pcm(samples, channels, sample_rate)
        end

        sound = new(native_sound)
        sound.bus = bus
        sound
      end
    end

    def initialize(source)
      if source.is_a?(String)
        @path = source.to_s
        @native = Native::Sound.load(@path)
      else
        @path = nil
        @native = source
      end

      @bus = :se
      @base_volume = @native.volume
      @fade_volume = 1.0
      @fade_target = 1.0
      @fade_speed = 0.0 # 1秒あたりの変化量
      @fade_stop_on_complete = false
    end

    # 再生開始 (再生中なら先頭からリトリガー再生)
    def play
      @fade_speed = 0.0
      @fade_volume = 1.0
      __update_volume
      @native.play
      Audio.__register_sound(self)
      self
    end

    # 停止 (再生位置を先頭にリセット)
    def stop
      @fade_speed = 0.0
      @native.stop
      self
    end

    # 一時停止 (再生位置を保持)
    def pause
      @fade_speed = 0.0
      @native.pause
      self
    end

    # フェードイン再生
    # - duration: フェード時間 (秒数)
    # - target_volume: 最終到達音量
    def fade_in(duration = 1.0, target_volume: nil)
      @base_volume = target_volume.to_f if target_volume
      @fade_volume = 0.0
      @fade_target = 1.0
      sec = [duration.to_f, 0.001].max
      @fade_speed = 1.0 / sec
      @fade_stop_on_complete = false
      __update_volume
      @native.play unless playing?
      Audio.__register_sound(self)
      self
    end

    # フェードアウト
    # - duration: フェード時間 (秒数)
    # - stop_on_complete: フェード完了時に stop するか (false で一時停止)
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
          @native.stop
        else
          @native.pause
        end
      end
      __update_volume
    end

    # 実効音量の再計算と反映
    def __update_volume
      bus_vol = Audio.bus_volume(@bus)
      eff = @base_volume * bus_vol * @fade_volume
      @native.volume = eff
    end

    # 再生中かどうか
    def playing?
      @native.playing?
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
      @native.looping = !!loop_flag
    end

    # ピッチ / 再生速度 (1.0 = 標準, 2.0 = 1オクターブ上/2倍速, 0.5 = 1オクターブ下/半分速)
    def pitch
      @native.pitch
    end

    def pitch=(p)
      @native.pitch = p.to_f
    end

    # パン (-1.0: 左, 0.0: 中央, 1.0: 右)
    def pan
      @native.pan
    end

    def pan=(p)
      @native.pan = p.to_f
    end

    # シーク (秒数)
    def seek(seconds)
      @native.seek(seconds.to_f)
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
  end
end

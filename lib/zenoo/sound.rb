# frozen_string_literal: true

module Zenoo
  # オーディオシステム制御モジュール
  module Audio
    class << self
      def master_volume
        Native::Audio.master_volume
      end

      def master_volume=(vol)
        Native::Audio.master_volume = vol.to_f
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

    class << self
      # ファイルからサウンドをロード
      def load(path)
        new(path)
      end

      # ワンショット再生用の簡易メソッド
      def play(path, volume: 1.0)
        sound = load(path)
        sound.volume = volume if volume != 1.0
        sound.play
        sound
      end

      # PCMサンプル配列またはバイナリ文字列から Sound インスタンスを生成
      # samples: [-1.0 .. 1.0] の Float 配列、または pack("e*") などの Float32 バイナリ文字列
      def from_pcm(samples, channels: 1, sample_rate: 44100)
        if samples.is_a?(Array)
          # Float 配列を Float32 リトルエンディアンのバイナリ文字列にパックして渡す (高速)
          packed = samples.pack('e*')
          native_sound = Native::Sound.load_pcm(packed, channels, sample_rate)
        else
          native_sound = Native::Sound.load_pcm(samples, channels, sample_rate)
        end

        new(native_sound)
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
    end

    # 再生開始 (再生中なら先頭からリトリガー再生)
    def play
      @native.play
      self
    end

    # 停止 (再生位置を先頭にリセット)
    def stop
      @native.stop
      self
    end

    # 一時停止 (再生位置を保持)
    def pause
      @native.pause
      self
    end

    # 再生中かどうか
    def playing?
      @native.playing?
    end

    # 音量 (0.0 .. 1.0 またはそれ以上)
    def volume
      @native.volume
    end

    def volume=(vol)
      @native.volume = vol.to_f
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

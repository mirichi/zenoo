# frozen_string_literal: true

# ==============================================================================
# Zenoo: 8-bit / Arcade Sound Effect Generator (SE Synthesizer)
# ==============================================================================
# レトロゲーム風の効果音（コイン、レーザー、爆発、ジャンプ等）を
# GUIスライダーやプリセットでリアルタイムに生成・試聴・WAV保存できるツールです。
# ==============================================================================

require_relative '../lib/zenoo'

# ------------------------------------------------------------------------------
# 1. 効果音合成エンジン (RetroSynth)
# ------------------------------------------------------------------------------
class RetroSynth
  TWO_PI = Math::PI * 2.0
  SAMPLE_RATE = 44100

  attr_accessor :wave_type      # 0: Square, 1: Sawtooth, 2: Sine, 3: Triangle, 4: Noise
  attr_accessor :base_freq      # 基本周波数 (Hz)
  attr_accessor :min_freq       # 最小周波数 (Hz)
  attr_accessor :slide          # 周波数スライド (Hz/s)
  attr_accessor :slide_accel    # スライド加速度 (Hz/s^2)
  attr_accessor :duty           # デューティ比 (0.05 .. 0.95)
  attr_accessor :duty_sweep     # デューティ比変化率
  attr_accessor :vib_depth      # ビブラートの深さ (Hz)
  attr_accessor :vib_speed      # ビブラートの速さ (Hz)
  attr_accessor :env_attack     # アタック時間 (秒)
  attr_accessor :env_sustain    # サスティン時間 (秒)
  attr_accessor :env_punch      # サスティンパンチ (開始アクセント 0.0 .. 1.0)
  attr_accessor :env_decay      # ディケイ時間 (秒)
  attr_accessor :arp_mod        # アルペジオ周波数倍率 (例: 1.5)
  attr_accessor :arp_time       # アルペジオ切り替え時間 (秒)
  attr_accessor :lpf_cutoff     # ローパスフィルタ (Hz)
  attr_accessor :volume         # マスター音量 (0.0 .. 1.0)
  attr_accessor :sample_rate    # サンプリングレート (Hz, デフォルト: 44100)

  def initialize
    reset_defaults
  end

  def reset_defaults
    @wave_type   = 0     # Square
    @base_freq   = 440.0
    @min_freq    = 20.0
    @slide       = 0.0
    @slide_accel = 0.0
    @duty        = 0.5
    @duty_sweep  = 0.0
    @vib_depth   = 0.0
    @vib_speed   = 10.0
    @env_attack  = 0.005
    @env_sustain = 0.1
    @env_punch   = 0.0
    @env_decay   = 0.15
    @arp_mod     = 1.0
    @arp_time    = 0.0
    @lpf_cutoff  = 20000.0
    @volume      = 0.8
    @sample_rate = SAMPLE_RATE
    round_all_params
  end

  # プリセット: コイン / アイテム取得
  def preset_coin
    reset_defaults
    @wave_type   = 0 # Square
    @base_freq   = 450.0
    @env_attack  = 0.005
    @env_sustain = 0.06
    @env_decay   = 0.16
    @env_punch   = 0.2
    @arp_mod     = 1.5 # 完全5度上へ跳躍
    @arp_time    = 0.07
    @duty        = 0.5
    round_all_params
  end

  # プリセット: レーザー / ショット
  def preset_laser
    reset_defaults
    @wave_type   = 1 # Sawtooth
    @base_freq   = 1100.0
    @min_freq    = 80.0
    @slide       = -3800.0
    @env_attack  = 0.002
    @env_sustain = 0.05
    @env_decay   = 0.12
    @duty        = 0.4
    round_all_params
  end

  # プリセット: 爆発
  def preset_explosion
    reset_defaults
    @wave_type   = 4 # Noise
    @base_freq   = 220.0
    @min_freq    = 20.0
    @slide       = -300.0
    @env_attack  = 0.005
    @env_sustain = 0.12
    @env_punch   = 0.4
    @env_decay   = 0.45
    @lpf_cutoff  = 3500.0 # 低音を強調
    round_all_params
  end

  # プリセット: パワーアップ
  def preset_powerup
    reset_defaults
    @wave_type   = 0 # Square
    @base_freq   = 280.0
    @slide       = 1200.0
    @slide_accel = 600.0
    @env_attack  = 0.01
    @env_sustain = 0.18
    @env_decay   = 0.25
    @vib_depth   = 25.0
    @vib_speed   = 16.0
    round_all_params
  end

  # プリセット: ヒット / 被弾
  def preset_hit
    reset_defaults
    @wave_type   = 4 # Noise
    @base_freq   = 350.0
    @slide       = -1500.0
    @env_attack  = 0.002
    @env_sustain = 0.04
    @env_decay   = 0.12
    @lpf_cutoff  = 5000.0
    round_all_params
  end

  # プリセット: ジャンプ
  def preset_jump
    reset_defaults
    @wave_type   = 0 # Square
    @base_freq   = 180.0
    @slide       = 1400.0
    @env_attack  = 0.005
    @env_sustain = 0.08
    @env_decay   = 0.18
    @duty        = 0.5
    round_all_params
  end

  # プリセット: 決定 / クリック
  def preset_select
    reset_defaults
    @wave_type   = 2 # Sine
    @base_freq   = 880.0
    @env_attack  = 0.003
    @env_sustain = 0.02
    @env_decay   = 0.06
    round_all_params
  end

  # 微小変異 (現在の音を少し揺らす)
  def mutate
    @base_freq   = clamp(@base_freq * (1.0 + (rand - 0.5) * 0.15), 50.0, 3000.0)
    @slide       += (rand - 0.5) * 400.0
    @env_attack  = clamp(@env_attack * (1.0 + (rand - 0.5) * 0.2), 0.001, 0.5)
    @env_decay   = clamp(@env_decay * (1.0 + (rand - 0.5) * 0.2), 0.02, 1.5)
    @duty        = clamp(@duty + (rand - 0.5) * 0.1, 0.1, 0.9)
    @vib_depth   = clamp(@vib_depth + (rand - 0.5) * 10.0, 0.0, 100.0)
    round_all_params
  end

  # 完全ランダム
  def randomize
    @wave_type   = rand(5)
    @base_freq   = 80.0 + rand * 1200.0
    @min_freq    = 20.0 + rand * 100.0
    @slide       = (rand - 0.6) * 3000.0
    @slide_accel = (rand - 0.5) * 1000.0
    @duty        = 0.1 + rand * 0.8
    @duty_sweep  = (rand - 0.5) * 0.4
    @vib_depth   = (rand < 0.5) ? (rand * 40.0) : 0.0
    @vib_speed   = 2.0 + rand * 20.0
    @env_attack  = rand * 0.05
    @env_sustain = 0.02 + rand * 0.2
    @env_punch   = (rand < 0.4) ? (rand * 0.5) : 0.0
    @env_decay   = 0.05 + rand * 0.5
    @arp_mod     = (rand < 0.4) ? (1.2 + rand * 1.0) : 1.0
    @arp_time    = (rand < 0.4) ? (0.03 + rand * 0.15) : 0.0
    @lpf_cutoff  = 1000.0 + rand * 19000.0
    round_all_params
  end

  # パラメータを有効桁数に丸め (再生音と出力コードの完全一致を保証)
  def round_all_params
    @base_freq   = @base_freq.round(1)
    @min_freq    = @min_freq.round(1)
    @slide       = @slide.round(1)
    @slide_accel = @slide_accel.round(1)
    @duty        = @duty.round(2)
    @duty_sweep  = @duty_sweep.round(2)
    @vib_depth   = @vib_depth.round(1)
    @vib_speed   = @vib_speed.round(1)
    @env_attack  = @env_attack.round(3)
    @env_sustain = @env_sustain.round(3)
    @env_punch   = @env_punch.round(2)
    @env_decay   = @env_decay.round(3)
    @arp_mod     = @arp_mod.round(2)
    @arp_time    = @arp_time.round(3)
    @lpf_cutoff  = @lpf_cutoff.round(0)
    @volume      = @volume.round(2)
  end

  # PCM波形合成 (SoundEffect.synthesize_pcm で完全一本化)
  def synthesize(sample_rate = @sample_rate)
    SoundEffect.synthesize_pcm(
      wave:        @wave_type,
      freq:        @base_freq,
      min_freq:    @min_freq,
      slide:       @slide,
      slide_accel: @slide_accel,
      duty:        @duty,
      duty_sweep:  @duty_sweep,
      vib_depth:   @vib_depth,
      vib_speed:   @vib_speed,
      attack:      @env_attack,
      sustain:     @env_sustain,
      punch:       @env_punch,
      decay:       @env_decay,
      arp_mod:     @arp_mod,
      arp_time:    @arp_time,
      lpf_cutoff:  @lpf_cutoff,
      volume:      @volume,
      sample_rate: sample_rate
    )
  end

  # Zenoo::Sound インスタンスを生成 (SoundEffect.synthesize を呼び出し)
  def generate_sound(sample_rate = @sample_rate)
    SoundEffect.synthesize(
      wave:        @wave_type,
      freq:        @base_freq,
      min_freq:    @min_freq,
      slide:       @slide,
      slide_accel: @slide_accel,
      duty:        @duty,
      duty_sweep:  @duty_sweep,
      vib_depth:   @vib_depth,
      vib_speed:   @vib_speed,
      attack:      @env_attack,
      sustain:     @env_sustain,
      punch:       @env_punch,
      decay:       @env_decay,
      arp_mod:     @arp_mod,
      arp_time:    @arp_time,
      lpf_cutoff:  @lpf_cutoff,
      volume:      @volume,
      sample_rate: sample_rate
    )
  end

  # WAVファイルとして書き出し (標準 16-bit PCM Mono)
  def save_wav(filename, sample_rate = @sample_rate)
    samples = synthesize(sample_rate)
    num_samples = samples.length
    data_bytes = num_samples * 2
    file_size = 36 + data_bytes

    header = [
      "RIFF",
      file_size,
      "WAVE",
      "fmt ",
      16,                 # fmt chunk size (PCM = 16)
      1,                  # Audio format (1 = PCM)
      1,                  # Num channels (1 = Mono)
      sample_rate,        # Sample rate
      sample_rate * 2,    # Byte rate (SampleRate * Channels * Bits/8)
      2,                  # Block align (Channels * Bits/8)
      16,                 # Bits per sample
      "data",
      data_bytes
    ].pack("a4Va4a4VvvVVvva4V")

    # 16-bit signed PCM リトルエンディアン
    pcm_data = samples.map do |s|
      (clamp(s, -1.0, 1.0) * 32767.0).round
    end.pack("s<*")

    File.binwrite(filename, header + pcm_data)
  end

  # Zenoo 用の Ruby 再生コードを生成 (デフォルト値は省略し、改行無し1行呼び出し)
  def to_ruby_code
    args = []

    wave_syms = [":square", ":sawtooth", ":sine", ":triangle", ":noise"]
    args << "wave: #{wave_syms[@wave_type]}" if @wave_type != 0

    args << "freq: #{@base_freq}" if (@base_freq - 440.0).abs > 0.05
    args << "min_freq: #{@min_freq}" if (@min_freq - 20.0).abs > 0.05
    args << "slide: #{@slide}" if @slide.abs > 0.05
    args << "slide_accel: #{@slide_accel}" if @slide_accel.abs > 0.05

    if @wave_type == 0 # 矩形波のみ duty / duty_sweep を考慮
      args << "duty: #{@duty}" if (@duty - 0.5).abs > 0.005
      args << "duty_sweep: #{@duty_sweep}" if @duty_sweep.abs > 0.005
    end

    args << "vib_depth: #{@vib_depth}" if @vib_depth.abs > 0.05
    args << "vib_speed: #{@vib_speed}" if @vib_depth.abs > 0.05 && (@vib_speed - 10.0).abs > 0.05

    args << "attack: #{@env_attack}" if (@env_attack - 0.005).abs > 0.0005
    args << "sustain: #{@env_sustain}" if (@env_sustain - 0.1).abs > 0.0005
    args << "punch: #{@env_punch}" if @env_punch.abs > 0.005
    args << "decay: #{@env_decay}" if (@env_decay - 0.15).abs > 0.0005

    if (@arp_mod - 1.0).abs > 0.005 && @arp_time > 0.0005
      args << "arp_mod: #{@arp_mod}"
      args << "arp_time: #{@arp_time}"
    end

    args << "lpf_cutoff: #{@lpf_cutoff}" if (@lpf_cutoff - 20000.0).abs > 20.0
    args << "volume: #{@volume}"
    args << "sample_rate: #{@sample_rate}"

    "sound = SoundEffect.synthesize(#{args.join(', ')})\nsound.play\n"
  end

  # パラメータ変更検知用キー
  def params_key
    [
      @wave_type, @base_freq, @min_freq, @slide, @slide_accel,
      @duty, @duty_sweep, @vib_depth, @vib_speed,
      @env_attack, @env_sustain, @env_punch, @env_decay,
      @arp_mod, @arp_time, @lpf_cutoff, @volume, @sample_rate
    ]
  end

  private

  def clamp(val, min_v, max_v)
    return min_v if val < min_v
    return max_v if val > max_v
    val
  end
end

# ------------------------------------------------------------------------------
# 2. GUI メインアプリケーション
# ------------------------------------------------------------------------------
if __FILE__ == $0
  synth = RetroSynth.new
  synth.preset_coin

current_sound = nil
samples_cache = synth.synthesize
last_params   = synth.params_key
play_timer    = 0.0
sound_duration = samples_cache.length.to_f / synth.sample_rate
is_playing    = false
copy_timer    = 0.0

tab_index = 0
export_filename = "sound.wav"
status_message = "Ready. Press Space to Play, or pick a preset!"
wave_names = ["Square", "Sawtooth", "Sine", "Triangle", "Noise"]

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

# 初回再生
current_sound = synth.generate_sound
current_sound.play
is_playing = true
play_timer = 0.0

Window.loop(1280, 720, "Zenoo - Retro Sound Effect Synthesizer (SE Generator)", msaa: 4) do
  dt = Window.delta_time
  Window.clear(Color.new(20, 22, 28))

  # 背景の軽い装飾グリッド
  grid_step = 40.0
  gx = 0.0
  while gx < 1280.0
    Window.draw_line(gx, 0, gx, 720, color: Color.new(28, 30, 38))
    gx += grid_step
  end
  gy = 0.0
  while gy < 720.0
    Window.draw_line(0, gy, 1280, gy, color: Color.new(28, 30, 38))
    gy += grid_step
  end

  # タイトルバー
  Window.draw_text(30.0, 16.0, "Zenoo 8-Bit / Retro Sound Effect Generator", size: 24, color: Color::WHITE)
  Window.draw_text(30.0, 46.0, "Tweak parameters or pick presets to craft custom arcade sound effects on the fly.", size: 14, color: Color.new(160, 165, 180))

  # パラメータ変化を検知して波形をリアルタイム再合成
  cur_params = synth.params_key
  if cur_params != last_params
    samples_cache = synth.synthesize
    sound_duration = samples_cache.length.to_f / synth.sample_rate
    last_params = cur_params
  end

  # コピーフィードバックタイマー
  copy_timer -= dt if copy_timer > 0.0

  # 再生タイマー更新
  if is_playing
    play_timer += dt
    if play_timer >= sound_duration
      is_playing = false
      play_timer = 0.0
    end
  end

  # キーボードショートカット: スペースキーで再生
  if Input.key_push?(:space)
    current_sound&.stop
    current_sound = synth.generate_sound
    current_sound.play
    samples_cache = synth.synthesize
    sound_duration = samples_cache.length.to_f / synth.sample_rate
    play_timer = 0.0
    is_playing = true
    status_message = "Playing sound... (#{sound_duration.round(3)}s)"
  end

  # -------------------------------------------------------------------
  # パネル 1: プリセット＆アクション (左側: 幅 260)
  # -------------------------------------------------------------------
  GUI.panel("Presets & Actions", x: 20, y: 75, w: 260, h: 620, padding: 12.0) do
    GUI.label("=== Quick Presets ===", size: 14, color: Color.new(255, 200, 80))
    GUI.spacer(4)

    GUI.row(cols: 2, spacing: 4) do
      if GUI.button("Coin", h: 34.0)
        synth.preset_coin
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Coin"
      end
      if GUI.button("Laser", h: 34.0)
        synth.preset_laser
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Laser"
      end
    end

    GUI.spacer(3)
    GUI.row(cols: 2, spacing: 4) do
      if GUI.button("Explosion", h: 34.0)
        synth.preset_explosion
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Explosion"
      end
      if GUI.button("Powerup", h: 34.0)
        synth.preset_powerup
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Powerup"
      end
    end

    GUI.spacer(3)
    GUI.row(cols: 2, spacing: 4) do
      if GUI.button("Hit/Hurt", h: 34.0)
        synth.preset_hit
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Hit"
      end
      if GUI.button("Jump", h: 34.0)
        synth.preset_jump
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Jump"
      end
    end

    GUI.spacer(3)
    GUI.row(cols: 2, spacing: 4) do
      if GUI.button("Select", h: 34.0)
        synth.preset_select
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Preset: Select"
      end
      if GUI.button("Reset", h: 34.0)
        synth.reset_defaults
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Reset Defaults"
      end
    end

    GUI.spacer(6)
    GUI.divider
    GUI.label("=== Variation ===", size: 14, color: Color.new(255, 200, 80))
    GUI.spacer(3)

    GUI.row(cols: 2, spacing: 4) do
      if GUI.button("Mutate", h: 34.0)
        synth.mutate
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Mutated slightly."
      end
      if GUI.button("Random!", h: 34.0)
        synth.randomize
        samples_cache = synth.synthesize
        current_sound = synth.generate_sound.play
        sound_duration = samples_cache.length.to_f / synth.sample_rate
        play_timer = 0.0
        is_playing = true
        status_message = "Randomized!"
      end
    end

    GUI.spacer(8)
    GUI.divider

    GUI.label("=== Playback & Export ===", size: 14, color: Color.new(100, 220, 255))
    GUI.spacer(4)

    if GUI.button("[>] PLAY (Space)", h: 42.0)
      current_sound&.stop
      samples_cache = synth.synthesize
      current_sound = synth.generate_sound.play
      sound_duration = samples_cache.length.to_f / synth.sample_rate
      play_timer = 0.0
      is_playing = true
      status_message = "Playing sound..."
    end

    GUI.spacer(6)
    GUI.label("Sample Rate:", size: 12, color: Color.new(180, 180, 190))
    GUI.row(cols: 3, spacing: 4) do
      synth.sample_rate = 44100 if GUI.radio("44.1k", synth.sample_rate == 44100)
      synth.sample_rate = 22050 if GUI.radio("22k", synth.sample_rate == 22050)
      synth.sample_rate = 11025 if GUI.radio("11k", synth.sample_rate == 11025)
    end

    GUI.spacer(4)
    GUI.label("WAV Output File:", size: 12, color: Color.new(180, 180, 190))
    export_filename = GUI.text_box("filename_box", export_filename)

    GUI.spacer(6)
    if GUI.button("Save WAV File", h: 34.0)
      out_path = export_filename.to_s.empty? ? "sound.wav" : export_filename
      synth.save_wav(out_path)
      status_message = "Exported: #{File.expand_path(out_path)}"
    end

    GUI.spacer(6)
    GUI.divider
    GUI.label("Status: #{status_message}", size: 11, color: Color.new(140, 240, 180))
  end

  # -------------------------------------------------------------------
  # パネル 2: 全パラメータ一括表示 (中央: 幅 600, 2列グリッド)
  # -------------------------------------------------------------------
  GUI.panel("Synthesizer Controls", x: 295, y: 75, w: 600, h: 620, padding: 14.0) do
    # 波形選択 (5ボタン横並び)
    GUI.label("=== Waveform ===", size: 14, color: Color.new(255, 200, 80))
    GUI.spacer(2)
    GUI.row(cols: 5, spacing: 4) do
      synth.wave_type = 0 if GUI.radio("Square", synth.wave_type == 0)
      synth.wave_type = 1 if GUI.radio("Saw", synth.wave_type == 1)
      synth.wave_type = 2 if GUI.radio("Sine", synth.wave_type == 2)
      synth.wave_type = 3 if GUI.radio("Triangle", synth.wave_type == 3)
      synth.wave_type = 4 if GUI.radio("Noise", synth.wave_type == 4)
    end

    GUI.spacer(6)
    GUI.divider

    # セクション 1: エンベロープ (左) ＆ 周波数 (右)
    GUI.label("=== Envelope (Left) & Frequency (Right) ===", size: 13, color: Color.new(255, 200, 80))
    GUI.spacer(2)

    GUI.row(cols: 2, spacing: 14) do
      synth.env_attack = GUI.slider("Attack (s)", synth.env_attack, 0.0, 0.5, h: 36.0, step: 0.001).round(3)
      synth.base_freq  = GUI.slider("Start Freq (Hz)", synth.base_freq, 40.0, 2000.0, h: 36.0, step: 1.0).round(1)
    end
    GUI.row(cols: 2, spacing: 14) do
      synth.env_sustain = GUI.slider("Sustain (s)", synth.env_sustain, 0.0, 0.8, h: 36.0, step: 0.001).round(3)
      synth.min_freq    = GUI.slider("Min Freq (Hz)", synth.min_freq, 20.0, 500.0, h: 36.0, step: 1.0).round(1)
    end
    GUI.row(cols: 2, spacing: 14) do
      synth.env_punch = GUI.slider("Punch", synth.env_punch, 0.0, 1.0, h: 36.0, step: 0.01).round(2)
      synth.slide     = GUI.slider("Slide (Hz/s)", synth.slide, -4000.0, 4000.0, h: 36.0, step: 10.0).round(1)
    end
    GUI.row(cols: 2, spacing: 14) do
      synth.env_decay   = GUI.slider("Decay (s)", synth.env_decay, 0.01, 1.5, h: 36.0, step: 0.001).round(3)
      synth.slide_accel = GUI.slider("Slide Accel", synth.slide_accel, -2000.0, 2000.0, h: 36.0, step: 10.0).round(1)
    end

    GUI.spacer(6)
    GUI.divider

    # セクション 2: ビブラート・アルペジオ (左) ＆ デューティ・フィルタ・音量 (右)
    is_square = (synth.wave_type == 0)
    duty_label = is_square ? "Duty Cycle" : "Duty Cycle (Square only)"
    sweep_label = is_square ? "Duty Sweep" : "Duty Sweep (Square only)"

    GUI.label("=== Vibrato & Arp (Left) & Tone & Filter (Right) ===", size: 13, color: Color.new(255, 200, 80))
    GUI.spacer(2)

    GUI.row(cols: 2, spacing: 14) do
      synth.vib_depth = GUI.slider("Vibrato Depth (Hz)", synth.vib_depth, 0.0, 100.0, h: 36.0, step: 0.5).round(1)
      synth.duty      = GUI.slider(duty_label, synth.duty, 0.1, 0.9, h: 36.0, step: 0.01, enabled: is_square).round(2)
    end
    GUI.row(cols: 2, spacing: 14) do
      synth.vib_speed  = GUI.slider("Vibrato Speed (Hz)", synth.vib_speed, 0.5, 30.0, h: 36.0, step: 0.5).round(1)
      synth.duty_sweep = GUI.slider(sweep_label, synth.duty_sweep, -0.5, 0.5, h: 36.0, step: 0.01, enabled: is_square).round(2)
    end
    GUI.row(cols: 2, spacing: 14) do
      synth.arp_mod    = GUI.slider("Pitch Jump Multiplier", synth.arp_mod, 0.5, 2.5, h: 36.0, step: 0.01).round(2)
      synth.lpf_cutoff = GUI.slider("LPF Cutoff (Hz)", synth.lpf_cutoff, 500.0, 20000.0, h: 36.0, step: 50.0).round(0)
    end
    GUI.row(cols: 2, spacing: 14) do
      synth.arp_time = GUI.slider("Trigger Time (s)", synth.arp_time, 0.0, 0.3, h: 36.0, step: 0.001).round(3)
      synth.volume   = GUI.slider("Master Volume", synth.volume, 0.0, 1.0, h: 36.0, step: 0.01).round(2)
    end
  end

  # -------------------------------------------------------------------
  # パネル 3: 波形オシロスコープ & コード出力 (右側: 幅 350)
  # -------------------------------------------------------------------
  GUI.panel("Waveform & Snippet", x: 910, y: 75, w: 350, h: 620, padding: 12.0) do
    GUI.label("=== Waveform Visualizer ===", size: 14, color: Color.new(255, 200, 80))
    GUI.label("Duration: #{sound_duration.round(3)}s | #{samples_cache.length} samples", size: 11, color: Color.new(160, 160, 180))
    GUI.spacer(4)

    # コンテナ内ローカル座標でスコープを描画
    scope_x = 0.0
    scope_y = GUI.layout.cursor_y
    scope_w = 326.0
    scope_h = 135.0

    # スコープ背景
    Window.draw_rect(scope_x, scope_y, scope_w, scope_h, color: Color.new(12, 14, 18), border_color: Color.new(70, 75, 90), border_width: 1.0, radius: 4.0)
    # センターライン
    center_y = scope_y + scope_h * 0.5
    Window.draw_line(scope_x, center_y, scope_x + scope_w, center_y, color: Color.new(40, 50, 65))

    # 波形プロット
    if samples_cache.length > 1
      step_sample = samples_cache.length.to_f / scope_w
      prev_px = scope_x
      prev_py = center_y

      px = 0.0
      while px < scope_w
        idx = (px * step_sample).to_i
        idx = samples_cache.length - 1 if idx >= samples_cache.length
        s_val = samples_cache[idx]
        py = center_y - s_val * (scope_h * 0.44)

        Window.draw_line(prev_px, prev_py, scope_x + px, py, color: Color.new(80, 220, 140))
        prev_px = scope_x + px
        prev_py = py
        px += 1.0
      end
    end

    # 再生ヘッド (Playhead)
    if is_playing && sound_duration > 0.0
      head_ratio = [play_timer / sound_duration, 1.0].min
      head_x = scope_x + scope_w * head_ratio
      Window.draw_line(head_x, scope_y, head_x, scope_y + scope_h, color: Color.new(255, 240, 80), width: 2.0)
    end

    # スコープの高さ分レイアウトカーソルを進める
    GUI.spacer(scope_h + 8.0)
    GUI.divider

    GUI.label("=== Ruby Code Snippet ===", size: 14, color: Color.new(255, 200, 80))
    GUI.spacer(3)

    # クリップボードへコピーボタン
    btn_label = copy_timer > 0.0 ? "✓ Copied to Clipboard!" : "Copy Code to Clipboard"
    if GUI.button(btn_label, h: 32.0)
      Input.clipboard = synth.to_ruby_code
      copy_timer = 2.0
    end
    GUI.spacer(4)

    # to_ruby_code の出力をそのまま行分割してリアルタイム表示
    code_lines = synth.to_ruby_code.lines
    GUI.scroll_view("code_scroll", h: 185.0) do
      i = 0
      len = code_lines.length
      while i < len
        line = code_lines[i].rstrip
        if line.start_with?("#")
          GUI.label(line, size: 11, color: Color.new(120, 200, 140))
        elsif line.include?("se_data =") || line.include?("sound =") || line.include?("sound.play")
          GUI.label(line, size: 11, color: Color.new(255, 220, 100))
        else
          GUI.label(line, size: 11, color: Color.new(210, 220, 235))
        end
        i += 1
      end
    end
  end

  frame_count += 1
  break if test_max > 0 && frame_count >= test_max
end

  puts "Sound Generator test completed (#{frame_count} frames)."
end

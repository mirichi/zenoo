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
  WAVE_SYMS = [:square, :sawtooth, :sine, :triangle, :noise].freeze

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
      wave:        WAVE_SYMS[@wave_type] || :square,
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
      wave:        WAVE_SYMS[@wave_type] || :square,
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
# 2. UI メインアプリケーション (保持モード UI)
# ------------------------------------------------------------------------------
if __FILE__ == $0
  synth = RetroSynth.new
  synth.preset_coin

  current_sound  = nil
  samples_cache  = synth.synthesize
  sound_duration = samples_cache.length.to_f / synth.sample_rate
  play_timer     = 0.0
  is_playing     = false
  copy_timer     = 0.0
  export_filename = "sound.wav"
  status_message  = "Ready. Press Space to Play, or pick a preset!"

  stage = UI::Stage.new(width: 1280, height: 720, theme: UI::Theme.new(:compact, padding: 10, gap: 5))

  sl_map       = {}
  sr_radios    = {}
  wave_radios  = []
  lbl_status   = nil
  lbl_waveinfo = nil
  code_box     = nil
  btn_copy     = nil

  rebuild_snippet = lambda do
    return unless code_box
    code_box.children.dup.each { |c| c.parent = nil }
    synth.to_ruby_code.lines.each do |raw|
      line = raw.rstrip
      col = if line.start_with?("#")
              [120, 200, 140]
            elsif line.include?("se_data =") || line.include?("sound =") || line.include?("sound.play")
              [255, 220, 100]
            else
              [210, 220, 235]
            end
      code_box.label(line, size: 11, color: col)
    end
  end

  refresh_audio_preview = lambda do |play_now: false|
    samples_cache = synth.synthesize
    sound_duration = samples_cache.length.to_f / synth.sample_rate
    lbl_waveinfo.text = "Duration: #{sound_duration.round(3)}s | #{samples_cache.length} samples" if lbl_waveinfo
    rebuild_snippet.call
    if play_now
      current_sound&.stop
      current_sound = synth.generate_sound
      current_sound.play
      play_timer = 0.0
      is_playing = true
    end
  end

  sync_all_controls = lambda do
    sr_radios.each { |rate, r| r.checked = (synth.sample_rate == rate) }
    wave_radios.each_with_index { |r, idx| r.checked = (synth.wave_type == idx) }

    sl_map.each do |attr, sl|
      sl.value = synth.public_send(attr) unless sl.dragging?
    end
    is_sq = (synth.wave_type == 0)
    sl_map[:duty].enabled       = is_sq
    sl_map[:duty_sweep].enabled = is_sq
    lbl_status.text = "Status: #{status_message}" if lbl_status
  end

  trigger_preset = lambda do |msg, &action|
    action.call
    refresh_audio_preview.call(play_now: true)
    status_message = msg
    sync_all_controls.call
  end

  # パネル 1: プリセット＆アクション (左側: 幅 260)
  stage.panel(20, 75, width: 260, height: 620, title: "Presets & Actions") do |w|
    w.label("=== Quick Presets ===", size: 14, color: [255, 200, 80])

    [
      [["Coin", "Preset: Coin", :preset_coin],           ["Laser", "Preset: Laser", :preset_laser]],
      [["Explosion", "Preset: Explosion", :preset_explosion], ["Powerup", "Preset: Powerup", :preset_powerup]],
      [["Hit/Hurt", "Preset: Hit", :preset_hit],         ["Jump", "Preset: Jump", :preset_jump]],
      [["Select", "Preset: Select", :preset_select],     ["Reset", "Reset Defaults", :reset_defaults]]
    ].each do |pair|
      w.hbox(padding: 0, gap: 4, height: 30) do |row|
        pair.each do |lbl, msg, method_sym|
          row.button(lbl, flex: 1) { trigger_preset.call(msg) { synth.public_send(method_sym) } }
        end
      end
    end

    w.divider
    w.label("=== Variation ===", size: 14, color: [255, 200, 80])
    w.hbox(padding: 0, gap: 4, height: 30) do |row|
      row.button("Mutate", flex: 1)  { trigger_preset.call("Mutated slightly.") { synth.mutate } }
      row.button("Random!", flex: 1) { trigger_preset.call("Randomized!") { synth.randomize } }
    end

    w.divider
    w.label("=== Playback & Export ===", size: 14, color: [100, 220, 255])
    w.button("[>] PLAY (Space)", height: 36) do
      refresh_audio_preview.call(play_now: true)
      status_message = "Playing sound..."
      lbl_status.text = "Status: #{status_message}"
    end

    w.label("Sample Rate:", size: 12, color: [180, 180, 190])
    w.hbox(padding: 0, gap: 4, height: 22, align: :center) do |row|
      [[44100, "44.1k"], [22050, "22k"], [11025, "11k"]].each do |rate, lbl|
        sr_radios[rate] = row.radio_button(lbl, synth.sample_rate == rate, group: :sample_rate) do
          synth.sample_rate = rate
          refresh_audio_preview.call(play_now: false)
        end
      end
    end

    w.label("WAV Output File:", size: 12, color: [180, 180, 190])
    w.text_box(export_filename, placeholder: "sound.wav") { |txt| export_filename = txt }

    w.button("Save WAV File", height: 30) do
      out_path = export_filename.to_s.empty? ? "sound.wav" : export_filename
      synth.save_wav(out_path)
      status_message = "Exported: #{File.expand_path(out_path)}"
      lbl_status.text = "Status: #{status_message}"
    end

    w.divider
    lbl_status = w.label("Status: #{status_message}", size: 11, color: [140, 240, 180])
  end

  # パネル 2: 全パラメータ一括表示 (中央: 幅 600, 2列グリッド)
  stage.panel(295, 75, width: 600, height: 620, title: "Synthesizer Controls") do |w|
    w.label("=== Waveform ===", size: 14, color: [255, 200, 80])
    w.hbox(padding: 0, gap: 8, height: 24, align: :center) do |row|
      ["Square", "Saw", "Sine", "Triangle", "Noise"].each_with_index do |wname, idx|
        wave_radios << row.radio_button(wname, synth.wave_type == idx, group: :wave_type) do
          synth.wave_type = idx
          is_sq = (idx == 0)
          sl_map[:duty].enabled       = is_sq
          sl_map[:duty_sweep].enabled = is_sq
          refresh_audio_preview.call(play_now: false)
        end
      end
    end

    w.divider
    w.label("=== Envelope (Left) & Frequency (Right) ===", size: 13, color: [255, 200, 80])

    make_param_slider = lambda do |col, label, attr, min_v, max_v, digits, fmt|
      sl_map[attr] = col.stacked_slider(label, synth.public_send(attr), min_v, max_v, format: fmt) do |v|
        synth.public_send(:"#{attr}=", v.round(digits))
        refresh_audio_preview.call(play_now: false)
      end
    end

    w.hbox(padding: 0, gap: 16, height: 206) do |cols|
      cols.vbox(padding: 0, gap: 6, flex: 1) do |left|
        make_param_slider.call(left, "Attack (s)",  :env_attack,  0.0,  0.5, 3, "%.3f")
        make_param_slider.call(left, "Sustain (s)", :env_sustain, 0.0,  0.8, 3, "%.3f")
        make_param_slider.call(left, "Punch",       :env_punch,   0.0,  1.0, 2, "%.2f")
        make_param_slider.call(left, "Decay (s)",   :env_decay,   0.01, 1.5, 3, "%.3f")
      end
      cols.vbox(padding: 0, gap: 6, flex: 1) do |right|
        make_param_slider.call(right, "Start Freq (Hz)", :base_freq,   40.0,    2000.0, 1, "%.1f")
        make_param_slider.call(right, "Min Freq (Hz)",   :min_freq,    20.0,    500.0,  1, "%.1f")
        make_param_slider.call(right, "Slide (Hz/s)",    :slide,      -4000.0, 4000.0, 1, "%.1f")
        make_param_slider.call(right, "Slide Accel",     :slide_accel,-2000.0, 2000.0, 1, "%.1f")
      end
    end

    w.divider
    w.label("=== Vibrato & Arp (Left) & Tone & Filter (Right) ===", size: 13, color: [255, 200, 80])

    w.hbox(padding: 0, gap: 16, height: 206) do |cols|
      cols.vbox(padding: 0, gap: 6, flex: 1) do |left|
        make_param_slider.call(left, "Vibrato Depth (Hz)",    :vib_depth, 0.0, 100.0, 1, "%.1f")
        make_param_slider.call(left, "Vibrato Speed (Hz)",    :vib_speed, 0.5, 30.0,  1, "%.1f")
        make_param_slider.call(left, "Pitch Jump Multiplier", :arp_mod,   0.5, 2.5,   2, "%.2f")
        make_param_slider.call(left, "Trigger Time (s)",      :arp_time,  0.0, 0.3,   3, "%.3f")
      end
      cols.vbox(padding: 0, gap: 6, flex: 1) do |right|
        make_param_slider.call(right, "Duty Cycle",      :duty,       0.1,   0.9,     2, "%.2f")
        make_param_slider.call(right, "Duty Sweep",      :duty_sweep,-0.5,   0.5,     2, "%.2f")
        make_param_slider.call(right, "LPF Cutoff (Hz)", :lpf_cutoff, 500.0, 20000.0, 0, "%.0f")
        make_param_slider.call(right, "Master Volume",   :volume,     0.0,   1.0,     2, "%.2f")
      end
    end
  end

  # パネル 3: 波形オシロスコープ & コード出力 (右側: 幅 350)
  stage.panel(910, 75, width: 350, height: 620, title: "Waveform & Snippet") do |w|
    w.label("=== Waveform Visualizer ===", size: 14, color: [255, 200, 80])
    lbl_waveinfo = w.label("Duration: #{sound_duration.round(3)}s | #{samples_cache.length} samples", size: 11, color: [160, 160, 180])

    w.custom(height: 135) do |cw|
      sx = cw.screen_left
      sy = cw.screen_top
      sw = cw.screen_width
      sh = cw.screen_height
      Window.draw_rect(sx, sy, sw, sh, radius: 4.0, color: [12, 14, 18], border_color: [70, 75, 90], border_width: 1.0, camera: false)
      center_y = sy + sh * 0.5
      Window.draw_line(sx, center_y, sx + sw, center_y, color: [40, 50, 65], camera: false)

      if samples_cache.length > 1 && sw > 1.0
        step_sample = samples_cache.length.to_f / sw
        prev_px = sx
        prev_py = center_y
        px = 0.0
        while px < sw
          idx = (px * step_sample).to_i
          idx = samples_cache.length - 1 if idx >= samples_cache.length
          py = center_y - samples_cache[idx] * (sh * 0.44)
          Window.draw_line(prev_px, prev_py, sx + px, py, color: [80, 220, 140], camera: false)
          prev_px = sx + px
          prev_py = py
          px += 1.0
        end
      end

      if is_playing && sound_duration > 0.0
        head_ratio = [play_timer / sound_duration, 1.0].min
        head_x = sx + sw * head_ratio
        Window.draw_line(head_x, sy, head_x, sy + sh, color: [255, 240, 80], width: 2.0, camera: false)
      end
    end

    w.divider
    w.label("=== Ruby Code Snippet ===", size: 14, color: [255, 200, 80])
    btn_copy = w.button("Copy Code to Clipboard", height: 30) do
      Input.clipboard = synth.to_ruby_code
      copy_timer = 2.0
      btn_copy.label = "Copied to Clipboard!"
    end

    w.scroll_view(flex: 1, padding: 6, gap: 2) do |sv|
      code_box = sv.vbox(padding: 0, gap: 2)
    end
  end

  sync_all_controls.call
  rebuild_snippet.call

  test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
  frame_count = 0

  # 初回再生
  current_sound = synth.generate_sound
  current_sound.play
  is_playing = true
  play_timer = 0.0

  Window.loop(1280, 720, "Zenoo - Retro Sound Effect Synthesizer (SE Generator)", msaa: 4) do
    dt = Window.delta_time
    Window.clear([20, 22, 28])

    # 背景の軽い装飾グリッド
    grid_step = 40.0
    gx = 0.0
    while gx < 1280.0
      Window.draw_line(gx, 0, gx, 720, color: [28, 30, 38])
      gx += grid_step
    end
    gy = 0.0
    while gy < 720.0
      Window.draw_line(0, gy, 1280, gy, color: [28, 30, 38])
      gy += grid_step
    end

    Window.draw_text(30.0, 16.0, "Zenoo 8-Bit / Retro Sound Effect Generator", size: 24, color: :white)
    Window.draw_text(30.0, 46.0, "Tweak parameters or pick presets to craft custom arcade sound effects on the fly.", size: 14, color: [160, 165, 180])

    if copy_timer > 0.0
      copy_timer -= dt
      if copy_timer <= 0.0
        copy_timer = 0.0
        btn_copy.label = "Copy Code to Clipboard"
      end
    end

    if is_playing
      play_timer += dt
      if play_timer >= sound_duration
        is_playing = false
        play_timer = 0.0
      end
    end

    if Input.key_push?(:space) && !UI.has_keyboard_focus?
      refresh_audio_preview.call(play_now: true)
      status_message = "Playing sound... (#{sound_duration.round(3)}s)"
      lbl_status.text = "Status: #{status_message}"
    end

    stage.update
    stage.draw

    frame_count += 1
    break if test_max > 0 && frame_count >= test_max
  end

  puts "Sound Generator test completed (#{frame_count} frames)."
end

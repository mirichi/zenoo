# frozen_string_literal: true

require_relative '../lib/zenoo'

# サウンドリソースの検索 (ルート、build/、Wasm 等どのディレクトリから実行されても検出可能にする)
def find_asset_file(rel_path)
  candidates = [
    rel_path,
    "../#{rel_path}",
    "../../#{rel_path}",
    "/#{rel_path}",
    File.expand_path("../#{rel_path}", __dir__)
  ]
  candidates.each do |p|
    return p if File.exist?(p)
  end
  rel_path
end

ogg_path = find_asset_file("assets/sounds/sample.ogg")
wav_path = find_asset_file("assets/sounds/sample.wav")

bgm_ogg = File.exist?(ogg_path) ? Zenoo::Sound.load(ogg_path, bus: :bgm) : nil
bgm_wav = File.exist?(wav_path) ? Zenoo::Sound.load(wav_path, bus: :se) : nil

# 動的波形効果音 (SoundEffect) のプリセット
sound_sine     = SoundEffect.tone(440, 0.3, type: :sine)
sound_square   = SoundEffect.tone(440, 0.3, type: :square)
sound_triangle = SoundEffect.tone(440, 0.3, type: :triangle)
sound_saw      = SoundEffect.tone(440, 0.3, type: :sawtooth)
sound_laser    = SoundEffect.sweep(900, 200, 0.15, type: :sawtooth)
sound_jump     = SoundEffect.sweep(250, 700, 0.2, type: :square)
sound_boom     = SoundEffect.noise(0.4, volume: 0.8, release: 0.3)

# 状態変数
current_status = "Ready. Click buttons or press keys 1-7 to play sounds."
master_vol = 1.0
bgm_vol    = 1.0
bgm_pitch  = 1.0
bgm_pan    = 0.0
bgm_loop   = true

if bgm_ogg
  bgm_ogg.volume  = bgm_vol
  bgm_ogg.looping = bgm_loop
end

# 保持モード UI 構築
stage = UI::Stage.new(width: 1080, height: 760, theme: UI::Theme.new(:compact, padding: 12, gap: 8))

stage.panel(30, 80, width: 495, height: 615, title: "Dynamic Sound Effects (PCM)") do |w|
  w.label("Generated on-the-fly with mathematical waveforms", size: 13, color: [150, 160, 180])

  w.hbox(padding: 0, gap: 12, height: 42) do |row|
    row.button("[1] Sine (440Hz)", flex: 1) { sound_sine.play; current_status = "Playing Sine wave tone (440Hz)" }
    row.button("[2] Square (440Hz)", flex: 1) { sound_square.play; current_status = "Playing Square wave tone (440Hz)" }
  end

  w.hbox(padding: 0, gap: 12, height: 42) do |row|
    row.button("[3] Triangle (440Hz)", flex: 1) { sound_triangle.play; current_status = "Playing Triangle wave tone (440Hz)" }
    row.button("[4] Sawtooth (440Hz)", flex: 1) { sound_saw.play; current_status = "Playing Sawtooth wave tone (440Hz)" }
  end

  w.spacer(4)
  w.label("Chirps / Sweeps (Dynamic Pitch Bend):", size: 14, color: [220, 200, 120])

  w.hbox(padding: 0, gap: 12, height: 42) do |row|
    row.button("[5] Laser (Down)", flex: 1) { sound_laser.play; current_status = "Playing Laser sweep (900Hz -> 200Hz)" }
    row.button("[6] Jump (Up)", flex: 1) { sound_jump.play; current_status = "Playing Jump sweep (250Hz -> 700Hz)" }
  end

  w.spacer(4)
  w.label("Noise (Perlin / White Noise):", size: 14, color: [220, 200, 120])
  w.button("[7] Explosion (Noise)", height: 42) { sound_boom.play; current_status = "Playing White Noise explosion sound" }

  w.divider
  w.label("Polyphony & Limiter Test (Anti-Clipping):", size: 14, color: [120, 220, 180])

  w.hbox(padding: 0, gap: 10, height: 36) do |row|
    row.button("Rapid Fire (10x in 1 frame)", flex: 1) do
      sound_laser.max_polyphony = 3
      sound_laser.dedup_frame = true
      10.times { sound_laser.play }
      current_status = "Triggered 10x in same frame (Dedup: 1 sound played, 0 clipping!)"
    end
    row.button("Multi-Voice (Polyphony 3)", flex: 1) do
      sound_laser.max_polyphony = 3
      sound_laser.dedup_frame = false
      sound_laser.play
      current_status = "Multi-voice laser (Max polyphony: 3)"
    end
  end
end

lbl_ogg_state = nil
btn_loop_toggle = nil
btn_loop_points = nil

stage.panel(550, 80, width: 495, height: 615, title: "File Audio & Engine Controls") do |w|
  w.label("Decoded via stb_vorbis & miniaudio engine", size: 13, color: [150, 160, 180])

  if bgm_ogg
    lbl_ogg_state = w.label("Sample OGG [Bus: :bgm]: Stopped", size: 14, color: [240, 180, 100])

    w.hbox(padding: 0, gap: 10, height: 36) do |row|
      row.button("Play OGG", flex: 1) { bgm_ogg.play; current_status = "Playing sample.ogg" }
      row.button("Pause", flex: 1)    { bgm_ogg.pause; current_status = "Paused sample.ogg" }
      row.button("Stop", flex: 1)     { bgm_ogg.stop; current_status = "Stopped sample.ogg" }
    end

    w.hbox(padding: 0, gap: 10, height: 36) do |row|
      row.button("Fade In (2.0s)", flex: 1)  { bgm_ogg.fade_in(2.0); current_status = "Fade In sample.ogg (2.0s)" }
      row.button("Fade Out (2.0s)", flex: 1) { bgm_ogg.fade_out(2.0); current_status = "Fade Out sample.ogg (2.0s)" }
    end
  end

  if bgm_wav
    w.button("Play WAV [Bus: :se]", height: 36) { bgm_wav.play; current_status = "Playing sample.wav" }
  end

  w.divider
  w.label("Buses & Engine Parameters", size: 14, color: [180, 180, 200])

  w.slider("BGM Bus Vol", Audio.bus_volume(:bgm), 0.0, 1.5, format: "%.2f") { |v| Audio.set_bus_volume(:bgm, v) }
  w.slider("SE Bus Vol",  Audio.bus_volume(:se),  0.0, 1.5, format: "%.2f") { |v| Audio.set_bus_volume(:se, v) }
  w.slider("Master Vol",  master_vol,             0.0, 1.0, format: "%.2f") do |v|
    master_vol = v
    Audio.master_volume = master_vol
  end

  if bgm_ogg
    w.divider
    w.label("BGM Sound Properties", size: 14, color: [180, 180, 200])

    w.slider("Pitch", bgm_pitch, 0.5, 2.0, format: "%.2f") do |v|
      bgm_pitch = v
      bgm_ogg.pitch = bgm_pitch
    end
    w.slider("Pan", bgm_pan, -1.0, 1.0, format: "%.2f") do |v|
      bgm_pan = v
      bgm_ogg.pan = bgm_pan
    end

    w.hbox(padding: 0, gap: 10, height: 36) do |row|
      btn_loop_toggle = row.button("BGM Loop: Enabled", flex: 1) do
        bgm_loop = !bgm_loop
        bgm_ogg.looping = bgm_loop
        btn_loop_toggle.label = bgm_loop ? "BGM Loop: Enabled" : "BGM Loop: Disabled"
        current_status = "BGM Loop set to #{bgm_loop}"
      end

      btn_loop_points = row.button("Set Loop Point (1.0s~)", flex: 1) do
        if bgm_ogg.has_loop_points?
          bgm_ogg.clear_loop_points
          btn_loop_points.label = "Set Loop Point (1.0s~)"
          current_status = "Cleared BGM loop points"
        else
          bgm_ogg.set_loop_points(1.0)
          btn_loop_points.label = "Loop Point: Active (1.0s~)"
          current_status = "Set BGM loop point: Intro=1.0s (loops back to 1.0s)"
        end
      end
    end
  end
end

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1080, 760, "Zenoo Audio & Sound Demo (miniaudio + Ogg Vorbis + SoundEffect)") do
  frame_count += 1
  break if test_max > 0 && frame_count >= test_max

  # キーボードショートカット (1..7)
  if Input.key_push?(:"1")
    sound_sine.play; current_status = "Playing Sine wave tone (440Hz)"
  elsif Input.key_push?(:"2")
    sound_square.play; current_status = "Playing Square wave tone (440Hz)"
  elsif Input.key_push?(:"3")
    sound_triangle.play; current_status = "Playing Triangle wave tone (440Hz)"
  elsif Input.key_push?(:"4")
    sound_saw.play; current_status = "Playing Sawtooth wave tone (440Hz)"
  elsif Input.key_push?(:"5")
    sound_laser.play; current_status = "Playing Laser sweep (900Hz -> 200Hz)"
  elsif Input.key_push?(:"6")
    sound_jump.play; current_status = "Playing Jump sweep (250Hz -> 700Hz)"
  elsif Input.key_push?(:"7")
    sound_boom.play; current_status = "Playing White Noise explosion sound"
  end

  if bgm_ogg && lbl_ogg_state
    ogg_state = bgm_ogg.fading? ? "Fading..." : (bgm_ogg.playing? ? "Playing" : "Stopped")
    lbl_ogg_state.text = "Sample OGG [Bus: :bgm]: #{ogg_state} (#{bgm_ogg.time.to_f.round(1)}s / #{bgm_ogg.length.to_f.round(1)}s)"
  end

  # 背景・ヘッダー・ステータスバー
  Window.draw_rect(0, 0, 1080, 760, color: [20, 24, 32])
  Window.draw_rect(0, 0, 1080, 60, color: [30, 36, 48])
  Window.draw_text(30, 16, "Zenoo Audio Engine Demo", size: 24, color: [100, 180, 255])
  Window.draw_text(420, 22, "Powered by miniaudio & stb_vorbis", size: 14, color: [160, 170, 190])
  Window.draw_rect(0, 710, 1080, 50, color: [24, 28, 38])
  Window.draw_text(30, 725, "Status: #{current_status}", size: 15, color: [150, 220, 120])

  stage.update
  stage.draw
end

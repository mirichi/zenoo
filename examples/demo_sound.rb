# frozen_string_literal: true

require_relative '../lib/zenoo'

# サウンドリソースの準備
ogg_path = File.expand_path("../assets/sounds/sample.ogg", __dir__)
wav_path = File.expand_path("../assets/sounds/sample.wav", __dir__)

bgm_ogg = File.exist?(ogg_path) ? Sound.load(ogg_path) : nil
bgm_wav = File.exist?(wav_path) ? Sound.load(wav_path) : nil

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
bgm_pitch = 1.0
bgm_pan = 0.0
bgm_loop = true

if bgm_ogg
  bgm_ogg.looping = bgm_loop
end

test_max = ENV['ZENOO_TEST_FRAMES'] ? ENV['ZENOO_TEST_FRAMES'].to_i : 0
frame_count = 0

Window.loop(1080, 700, "Zenoo Audio & Sound Demo (miniaudio + Ogg Vorbis + SoundEffect)") do
  frame_count += 1
  break if test_max > 0 && frame_count >= test_max

  # 背景
  Window.draw_rect(0, 0, 1080, 700, color: Color.new(20, 24, 32))

  # ヘッダー描画
  Window.draw_rect(0, 0, 1080, 60, color: Color.new(30, 36, 48))
  Window.draw_text(30, 16, "Zenoo Audio Engine Demo", size: 24, color: Color.new(100, 180, 255))
  Window.draw_text(420, 22, "Powered by miniaudio & stb_vorbis", size: 14, color: Color.new(160, 170, 190))

  # ステータスバー
  Window.draw_rect(0, 650, 1080, 50, color: Color.new(24, 28, 38))
  Window.draw_text(30, 665, "Status: #{current_status}", size: 15, color: Color.new(150, 220, 120))

  # 左側: 動的波形生成 (SoundEffect)
  GUI.cursor(30.0, 80.0)
  GUI.panel("Dynamic Sound Effects (PCM)", w: 490.0, h: 550.0) do
    GUI.label("Generated on-the-fly with mathematical waveforms", size: 13, color: Color.new(150, 160, 180))

    GUI.row(spacing: 12) do
      if Input.key_push?(:"1") || GUI.button("[1] Sine (440Hz)", w: 220.0, h: 42.0)
        sound_sine.play
        current_status = "Playing Sine wave tone (440Hz)"
      end
      if Input.key_push?(:"2") || GUI.button("[2] Square (440Hz)", w: 220.0, h: 42.0)
        sound_square.play
        current_status = "Playing Square wave tone (440Hz)"
      end
    end

    GUI.row(spacing: 12) do
      if Input.key_push?(:"3") || GUI.button("[3] Triangle (440Hz)", w: 220.0, h: 42.0)
        sound_triangle.play
        current_status = "Playing Triangle wave tone (440Hz)"
      end
      if Input.key_push?(:"4") || GUI.button("[4] Sawtooth (440Hz)", w: 220.0, h: 42.0)
        sound_saw.play
        current_status = "Playing Sawtooth wave tone (440Hz)"
      end
    end

    GUI.label("Chirps / Sweeps (Dynamic Pitch Bend):", size: 14, color: Color.new(220, 200, 120))

    GUI.row(spacing: 12) do
      if Input.key_push?(:"5") || GUI.button("[5] Laser (Down)", w: 220.0, h: 42.0)
        sound_laser.play
        current_status = "Playing Laser sweep (900Hz -> 200Hz)"
      end
      if Input.key_push?(:"6") || GUI.button("[6] Jump (Up)", w: 220.0, h: 42.0)
        sound_jump.play
        current_status = "Playing Jump sweep (250Hz -> 700Hz)"
      end
    end

    GUI.label("Noise (Perlin / White Noise):", size: 14, color: Color.new(220, 200, 120))

    if Input.key_push?(:"7") || GUI.button("[7] Explosion (Noise)", w: 452.0, h: 42.0)
      sound_boom.play
      current_status = "Playing White Noise explosion sound"
    end
  end

  # 右側: ファイルオーディオ (OGG / WAV) & オーディオコントロール
  GUI.cursor(550.0, 80.0)
  GUI.panel("File Audio & Engine Controls", w: 490.0, h: 550.0) do
    GUI.label("Decoded via stb_vorbis & miniaudio engine", size: 13, color: Color.new(150, 160, 180))

    if bgm_ogg
      ogg_state = bgm_ogg.playing? ? "Playing" : "Stopped"
      GUI.label("Sample OGG: #{ogg_state} (#{bgm_ogg.time.to_f.round(1)}s / #{bgm_ogg.length.to_f.round(1)}s)", size: 14, color: Color.new(240, 180, 100))

      GUI.row(spacing: 10) do
        if GUI.button("Play OGG", w: 140.0, h: 40.0)
          bgm_ogg.play
          current_status = "Playing sample.ogg"
        end
        if GUI.button("Pause", w: 140.0, h: 40.0)
          bgm_ogg.pause
          current_status = "Paused sample.ogg"
        end
        if GUI.button("Stop", w: 140.0, h: 40.0)
          bgm_ogg.stop
          current_status = "Stopped sample.ogg"
        end
      end
    end

    GUI.label("--- Sound & Engine Parameters ---", size: 14, color: Color.new(180, 180, 200))

    GUI.label("Master Volume: #{(master_vol * 100).to_i}%", size: 13, color: Color.new(200, 210, 225))
    new_vol = GUI.slider("Master Vol", master_vol, 0.0, 1.0, w: 452.0)
    if (new_vol.to_f - master_vol).abs > 0.01
      master_vol = new_vol.to_f
      Audio.master_volume = master_vol
    end

    if bgm_ogg
      GUI.label("BGM Pitch: #{bgm_pitch.round(2)}x", size: 13, color: Color.new(200, 210, 225))
      new_pitch = GUI.slider("Pitch", bgm_pitch, 0.5, 2.0, w: 452.0)
      if (new_pitch.to_f - bgm_pitch).abs > 0.01
        bgm_pitch = new_pitch.to_f
        bgm_ogg.pitch = bgm_pitch
      end

      GUI.label("BGM Pan: #{bgm_pan.round(2)} (Left: -1.0, Right: +1.0)", size: 13, color: Color.new(200, 210, 225))
      new_pan = GUI.slider("Pan", bgm_pan, -1.0, 1.0, w: 452.0)
      if (new_pan.to_f - bgm_pan).abs > 0.01
        bgm_pan = new_pan.to_f
        bgm_ogg.pan = bgm_pan
      end

      if GUI.button(bgm_loop ? "BGM Loop: Enabled" : "BGM Loop: Disabled", w: 220.0, h: 38.0)
        bgm_loop = !bgm_loop
        bgm_ogg.looping = bgm_loop
        current_status = "BGM Loop set to #{bgm_loop}"
      end
    end
  end
end

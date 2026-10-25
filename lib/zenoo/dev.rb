# frozen_string_literal: true

# ==============================================================================
# Zenoo::Dev - CRuby専用 開発支援エンジン (Live Reload & Crash-Free Debugger)
# ※ このファイルは CRuby 実行時のみ動的にロードされ、Spinel AOT コンパイルからは除外されます。
# ==============================================================================

require_relative 'dev/inspector'

module Zenoo
  module Dev
    class << self
      attr_accessor :enabled, :watch_interval_frames, :current_error, :auto_reload, :test_frames, :watch_dirs

      def init
        @enabled = ENV["ZENOO_DEV"] != "0"
        @auto_reload = true
        @watch_interval_frames = 15 # 約0.25秒おきにチェック
        @frame_counter = 0
        @test_frames = ENV["ZENOO_TEST_FRAMES"] ? ENV["ZENOO_TEST_FRAMES"].to_i : nil
        @test_frames_counter = 0
        @file_mtimes = {}
        @current_error = nil
        @last_reported_error = nil
        @watch_dirs = []

        # 実行中スクリプトのディレクトリとカレントディレクトリを監視対象に追加
        add_watch_dir(Dir.pwd)
        if $0 && File.exist?($0)
          add_watch_dir(File.dirname(File.expand_path($0)))
        end

        scan_files(initial: true)
      end

      def add_watch_dir(dir)
        dir = File.expand_path(dir)
        @watch_dirs << dir unless @watch_dirs.include?(dir)
      end

      # 監視対象ファイルの走査と更新日時の記録
      def scan_files(initial: false)
        @watch_dirs.each do |dir|
          next unless Dir.exist?(dir)
          Dir.glob(File.join(dir, "**/*.rb")).each do |path|
            # lib/zenoo 自体はホットリロード対象から除外（ユーザーゲームコードのみを対象）
            next if path.include?("/lib/zenoo/") || path.include?("\\lib\\zenoo\\")
            next if path.end_with?("dev.rb")

            begin
              mtime = File.mtime(path)
              if initial
                @file_mtimes[path] = mtime
              elsif @file_mtimes[path] && mtime > @file_mtimes[path]
                @file_mtimes[path] = mtime
                reload_file(path)
              else
                @file_mtimes[path] = mtime
              end
            rescue Errno::ENOENT
              @file_mtimes.delete(path)
            end
          end
        end
      end

      # 単一ファイルのリロード
      def reload_file(path)
        puts "\e[36m[Zenoo::Dev]\e[0m 🔄 Reloading: #{File.basename(path)}..."
        begin
          load path
          puts "\e[32m[Zenoo::Dev]\e[0m ✅ Successfully reloaded: #{File.basename(path)}"
          # ロード成功時にエラーを解消
          if @current_error
            @current_error = nil
            @last_reported_error = nil
            puts "\e[32m[Zenoo::Dev]\e[0m 🚀 Exception resolved. Resuming game loop!"
          end
        rescue ScriptError, StandardError => e
          handle_exception(e, source: "Reload (#{File.basename(path)})")
        end
      end

      # 全監視対象ファイルを強制再ロード
      def reload_all
        puts "\e[36m[Zenoo::Dev]\e[0m 🔄 Force reloading all scripts..."
        @file_mtimes.keys.each do |path|
          next unless File.exist?(path)
          begin
            load path
          rescue ScriptError, StandardError => e
            handle_exception(e, source: "Force Reload")
            return
          end
        end
        @current_error = nil
        @last_reported_error = nil
        puts "\e[32m[Zenoo::Dev]\e[0m ✅ All scripts reloaded cleanly."
      end

      # 例外ハンドラ
      def handle_exception(e, source: "Game Loop")
        @current_error = e
        if @last_reported_error != e.to_s + e.backtrace.to_s
          @last_reported_error = e.to_s + e.backtrace.to_s
          warn "\e[31m[Zenoo::Dev] ⚠️ #{source} Exception: #{e.class}: #{e.message}\e[0m"
          if e.backtrace
            e.backtrace.first(10).each { |line| warn "    from #{line}" }
          end
        end

        # ZENOO_TEST_FRAMES 指定時は、エラーで停止させず即座にプロセスを終了 (exit 1)
        if @test_frames
          warn "\e[31m[Zenoo::Dev] ❌ Test run aborted due to exception.\e[0m"
          exit 1
        end
      end

      # フレーム毎の更新フック
      def on_frame_start
        return unless @enabled

        @frame_counter += 1
        if @auto_reload && (@frame_counter % @watch_interval_frames == 0)
          scan_files
        end

        # F5キーで強制リロード
        if Input.key_pressed?(:f5)
          reload_all
        end

        # F12キーでインスペクタトグル
        Inspector.update
      end

      # フレーム終了フック (ZENOO_TEST_FRAMES 判定)
      def on_frame_end
        return unless @enabled

        if @test_frames
          @test_frames_counter += 1
          if @test_frames_counter >= @test_frames
            puts "\e[32m[Zenoo::Dev] ✅ Test completed successfully after #{@test_frames} frames.\e[0m"
            exit 0
          end
        end
      end

      # エラーオーバーレイの描画
      def draw_error_overlay
        return unless @current_error

        w = Window.width.to_f
        h = Window.height.to_f

        Window.without_camera do
          # 画面全体の薄いダークマスク
          Window.draw_rect(0, 0, w, h, color: [10, 10, 15, 200])

          # エラーダイアログカード (中央配置)
          card_w = [w - 80.0, 1000.0].min
          card_h = [h - 80.0, 520.0].min
          card_x = (w - card_w) / 2.0
          card_y = (h - card_h) / 2.0

          # SDF 角丸カード (深紅〜ダークレッド、赤枠線、ドロップシャドウ)
          Window.draw_rect(
            card_x, card_y, card_w, card_h,
            radius: 12.0,
            color: [30, 12, 16, 250],
            border_width: 2.0,
            border_color: [240, 68, 68, 255],
            shadow_blur: 24.0,
            shadow_color: [240, 68, 68, 80]
          )

          # タイトルバー領域
          Window.draw_rect(
            card_x, card_y, card_w, 48.0,
            radius: 12.0,
            color: [50, 18, 24, 255]
          )

          # ヘッダーアイコン＆タイトル
          Window.draw_text(
            card_x + 20.0, card_y + 12.0,
            "⚠️  RUNTIME EXCEPTION: #{@current_error.class}",
            size: 18,
            color: [255, 220, 100, 255]
          )

          # エラーメッセージ本文
          msg = @current_error.message.to_s
          # 長すぎるメッセージのトリミング
          msg = msg[0..200] + "..." if msg.length > 200
          Window.draw_rect(
            card_x + 20.0, card_y + 60.0, card_w - 40.0, 64.0,
            radius: 6.0,
            color: [18, 8, 10, 255],
            border_width: 1.0,
            border_color: [120, 40, 45, 200]
          )
          Window.draw_text(
            card_x + 32.0, card_y + 78.0,
            msg,
            size: 16,
            color: [255, 255, 255, 255]
          )

          # スタックトレース表示
          Window.draw_text(
            card_x + 20.0, card_y + 138.0,
            "Stack Trace:",
            size: 14,
            color: [180, 180, 190, 255]
          )

          trace_box_y = card_y + 160.0
          trace_box_h = card_h - 225.0
          Window.draw_rect(
            card_x + 20.0, trace_box_y, card_w - 40.0, trace_box_h,
            radius: 6.0,
            color: [14, 6, 8, 255]
          )

          if @current_error.backtrace && !@current_error.backtrace.empty?
            visible_lines = [(@current_error.backtrace.size), 8].min
            @current_error.backtrace.first(visible_lines).each_with_index do |line, idx|
              # ユーザーコードの行をハイライト
              is_user_code = !line.include?("/lib/zenoo/") && !line.include?("\\lib\\zenoo\\")
              col = is_user_code ? [255, 180, 100, 255] : [150, 150, 160, 255]
              prefix = is_user_code ? "▶ " : "  "
              display_line = line.length > 110 ? line[0..107] + "..." : line

              Window.draw_text(
                card_x + 32.0, trace_box_y + 12.0 + idx * 24.0,
                "#{prefix}#{display_line}",
                size: 13,
                color: col
              )
            end
          else
            Window.draw_text(
              card_x + 32.0, trace_box_y + 12.0,
              "(No backtrace available)",
              size: 13,
              color: [120, 120, 130, 255]
            )
          end

          # フッター（操作ガイド）
          guide_y = card_y + card_h - 45.0
          Window.draw_text(
            card_x + 20.0, guide_y,
            "💡 コードを修正して保存すると自動でリロードして再開します (F5: 手動リロード)",
            size: 14,
            color: [100, 220, 255, 255]
          )
        end
      end
    end

    # Window.loop へのパッチ
    module WindowPatch
      def loop(*args, **kwargs, &block)
        if Zenoo::Dev.enabled && @in_dev_loop
          # すでにメインループが走っている最中に単一ファイルリロード等で再度 Window.loop が呼ばれた場合、
          # 新しいループを開始せず、最新のブロックを差し替えて即座にリターンする（スタックの積み重ねを防止）
          @main_loop_block = block if block
          puts "\e[32m[Zenoo::Dev]\e[0m 🔄 Main loop block updated without nesting stack."
          return
        end

        @in_dev_loop = true
        begin
          super
        ensure
          @in_dev_loop = false
        end
      end

      def __step_frame
        Zenoo::Dev.on_frame_start if Zenoo::Dev.enabled
        super
        Zenoo::Dev.on_frame_end if Zenoo::Dev.enabled
      end

      def __update_step
        if Zenoo::Dev.enabled && Zenoo::Dev.current_error
          # エラー発生中は通常のゲームロジック・GUI更新を一時停止
          # ただし入力（F5等）の更新は維持
          Input.__update_step
          return
        end

        # 通常のゲームブロック実行を begin ... rescue で保護
        Audio.update(delta_time)
        Tween.__update_step(delta_time)
        GUI.begin_frame
        if @main_loop_block
          begin
            @main_loop_block.call unless (Zenoo::Dev.enabled && Zenoo::Dev::Inspector.pause_game)
          rescue ScriptError, StandardError => e
            if Zenoo::Dev.enabled
              Zenoo::Dev.handle_exception(e)
            else
              raise e
            end
          end
        end

        # F12 インスペクタ GUI の描画
        Zenoo::Dev::Inspector.render_gui if Zenoo::Dev.enabled

        GUI.end_frame
        Input.__update_step
      end

      def __draw_step
        super

        if Zenoo::Dev.enabled
          # コライダー可視化オーバーレイ描画
          Zenoo::Dev::Inspector.draw_colliders

          # エラーオーバーレイを最前面描画
          if Zenoo::Dev.current_error
            Zenoo::Dev.draw_error_overlay
          end
          Backend.flush_screen
        end
      end
    end
  end
end

# 初期化 & Windowモジュールへの prepend
Zenoo::Dev.init
Zenoo::Window.singleton_class.prepend(Zenoo::Dev::WindowPatch)

puts "\e[32m[Zenoo]\e[0m 🛠️  Dev mode active: Hot-reload & Crash-free debugger enabled."

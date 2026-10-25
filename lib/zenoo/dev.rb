# frozen_string_literal: true

# ==============================================================================
# Zenoo::Dev - CRuby専用 開発支援エンジン (Live Reload & Crash-Free Debugger)
# ※ このファイルは CRuby 実行時のみ動的にロードされ、Spinel AOT コンパイルからは除外されます。
# ==============================================================================

require_relative 'dev/inspector'

module Zenoo
  module Dev
    class << self
      attr_accessor :enabled, :watch_interval_frames, :current_error, :auto_reload, :test_frames, :watch_dirs, :game_block_active

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
        @snapshot_pool = []
        @snapshot_count = 0
        @snapshot_clear_color = nil
        @has_snapshot = false
        @single_step_requested = false
        @game_block_active = false

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

      def step_frame!
        @single_step_requested = true
      end

      def single_step_requested?
        @single_step_requested
      end

      def clear_single_step!
        @single_step_requested = false
      end

      def has_snapshot?
        @has_snapshot
      end

      def game_block_active?
        @game_block_active
      end

      # ユーザーのゲームブロック実行中かつインスペクタ等のGUIがマウスを捕捉している場合はマスク
      def mask_mouse_input?
        return false unless @enabled && @game_block_active
        Zenoo::GUI.mouse_captured? || !Zenoo::GUI.hovered_window_id.nil?
      end

      # ユーザーのゲームブロック実行中かつインスペクタ等のGUI要素（テキスト入力等）にフォーカスがある場合はマスク
      def mask_keyboard_input?
        return false unless @enabled && @game_block_active
        !Zenoo::GUI.focus_id.nil?
      end

      # 画面キューのコマンド群をスナップショットとして保持
      def capture_screen_snapshot
        q = Backend.screen_queue
        # キューのソートを先に行う
        q.sort
        count = q.queue_count
        @snapshot_clear_color = q.clear_color || Zenoo::Window.bg_color
        @snapshot_count = count

        while @snapshot_pool.length < count
          @snapshot_pool << Backend::DrawCommand.new
        end

        pool = q.command_pool
        i = 0
        while i < count
          src = pool[i]
          dst = @snapshot_pool[i]
          dst.set(
            src.target, src.z, src.order,
            src.pipeline, src.data, src.count,
            src.image, src.shader, src.uniforms, src.blend, src.clip
          )
          i += 1
        end
        @has_snapshot = true
      end

      # ポーズ中: スナップショットのコマンド群を画面に再描画 (オフスクリーン描画はバイパス)
      def replay_screen_snapshot
        return unless @has_snapshot

        clear_c = @snapshot_clear_color || Zenoo::Window.bg_color || :black
        Native::Window.clear(Backend.color_to_uint32(clear_c))
        Backend.mark_screen_cleared
        Backend.execute_snapshot_commands(@snapshot_pool, @snapshot_count)
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

        is_paused = Zenoo::Dev.enabled && Zenoo::Dev::Inspector.pause_game
        @current_frame_ran_game = !is_paused || Zenoo::Dev.single_step_requested?

        # 通常のゲームブロック実行を begin ... rescue で保護
        Window.__advance_time if @current_frame_ran_game
        Audio.update(delta_time)
        Tween.__update_step(delta_time) if @current_frame_ran_game
        GUI.begin_frame
        if @main_loop_block
          begin
            if @current_frame_ran_game
              Zenoo::Dev.game_block_active = true
              @main_loop_block.call
            end
          rescue ScriptError, StandardError => e
            if Zenoo::Dev.enabled
              Zenoo::Dev.handle_exception(e)
            else
              raise e
            end
          ensure
            Zenoo::Dev.game_block_active = false
          end
        end

        # ゲームブロック直後: インスペクタGUIがキューに積まれる前に純粋なゲーム画面のスナップショットを取得！
        Zenoo::Dev.capture_screen_snapshot if Zenoo::Dev.enabled && @current_frame_ran_game

        # F12 インスペクタ GUI の描画
        Zenoo::Dev::Inspector.render_gui if Zenoo::Dev.enabled

        GUI.end_frame
        Input.__update_step
      end

      def __draw_step
        if @current_frame_ran_game || !Zenoo::Dev.has_snapshot?
          # ゲームを実行したフレーム、またはスナップショット未取得時: 通常通りゲーム画面とGUIを描画
          super
          Zenoo::Dev.clear_single_step! if Zenoo::Dev.single_step_requested?
        else
          # ポーズ中でゲームを実行しなかったフレーム: 直前の純粋なゲーム画面スナップショットをリプレイ
          Zenoo::Dev.replay_screen_snapshot
          Backend.clear_clips
          @offset_x = 0.0
          @offset_y = 0.0
          Native::Renderer.reset_scissor
        end

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

    # Input モジュールへのパッチ (インスペクタ等のGUI操作時にゲーム側の入力を自動マスク)
    module InputPatch
      # マウスボタン
      def mouse_pressed?(button = :left)
        return false if Zenoo::Dev.mask_mouse_input?
        super
      end

      def mouse_down?(button = :left)
        return false if Zenoo::Dev.mask_mouse_input?
        super
      end

      def mouse_push?(button = :left)
        return false if Zenoo::Dev.mask_mouse_input?
        super
      end

      def mouse_release?(button = :left)
        return false if Zenoo::Dev.mask_mouse_input?
        super
      end

      # マウスホイール
      def mouse_wheel
        return 0.0 if Zenoo::Dev.mask_mouse_input?
        super
      end

      def mouse_wheel_x
        return 0.0 if Zenoo::Dev.mask_mouse_input?
        super
      end

      def mouse_wheel_y
        return 0.0 if Zenoo::Dev.mask_mouse_input?
        super
      end

      # キーボード
      def key_pressed?(key)
        return false if Zenoo::Dev.mask_keyboard_input?
        super
      end

      def key_down?(key)
        return false if Zenoo::Dev.mask_keyboard_input?
        super
      end

      def key_push?(key)
        return false if Zenoo::Dev.mask_keyboard_input?
        super
      end

      def key_release?(key)
        return false if Zenoo::Dev.mask_keyboard_input?
        super
      end

      def key_repeat?(key)
        return false if Zenoo::Dev.mask_keyboard_input?
        super
      end

      def input_chars
        return [] if Zenoo::Dev.mask_keyboard_input?
        super
      end

      # アクションマップ
      def action_pressed?(name, id = 0)
        mask_m = Zenoo::Dev.mask_mouse_input?
        mask_k = Zenoo::Dev.mask_keyboard_input?
        return super unless mask_m || mask_k

        act = @actions[name.to_sym]
        return false unless act

        unless mask_k
          act[:keys].each do |k|
            return true if Native::Input.key_pressed?(k)
          end
        end

        act[:gamepad].each do |b|
          return true if Native::Input.gamepad_button_pressed?(id.to_i, b)
        end

        unless mask_m
          act[:mouse].each do |m|
            return true if Native::Input.mouse_pressed?(m)
          end
        end

        act[:axes].each do |ax_def|
          axis_name, dir, thresh, _deadzone = ax_def
          thresh ||= 0.5
          val = gamepad_axis(axis_name, id)
          case dir
          when :positive
            return true if val >= thresh
          when :negative
            return true if val <= -thresh
          else
            return true if val >= thresh
          end
        end

        false
      end

      def action_down?(name, id = 0)
        action_pressed?(name, id)
      end

      def action_push?(name, id = 0)
        mask_m = Zenoo::Dev.mask_mouse_input?
        mask_k = Zenoo::Dev.mask_keyboard_input?
        return super unless mask_m || mask_k

        act = @actions[name.to_sym]
        return false unless act

        unless mask_k
          act[:keys].each do |k|
            return true if Native::Input.key_push?(k)
          end
        end

        act[:gamepad].each do |b|
          return true if Native::Input.gamepad_button_push?(id.to_i, b)
        end

        unless mask_m
          act[:mouse].each do |m|
            return true if Native::Input.mouse_push?(m)
          end
        end

        act[:axes].each do |ax_def|
          axis_name, dir, thresh, _deadzone = ax_def
          thresh ||= 0.5
          val = gamepad_axis(axis_name, id)
          cur_active = case dir
                       when :positive then val >= thresh
                       when :negative then val <= -thresh
                       else val >= thresh
                       end
          key = [axis_name, id.to_i, dir]
          prev_active = @axis_state_prev[key] || false
          return true if cur_active && !prev_active
        end

        false
      end

      def action_release?(name, id = 0)
        mask_m = Zenoo::Dev.mask_mouse_input?
        mask_k = Zenoo::Dev.mask_keyboard_input?
        return super unless mask_m || mask_k

        act = @actions[name.to_sym]
        return false unless act

        unless mask_k
          act[:keys].each do |k|
            return true if Native::Input.key_release?(k)
          end
        end

        act[:gamepad].each do |b|
          return true if Native::Input.gamepad_button_release?(id.to_i, b)
        end

        unless mask_m
          act[:mouse].each do |m|
            return true if Native::Input.mouse_release?(m)
          end
        end

        act[:axes].each do |ax_def|
          axis_name, dir, thresh, _deadzone = ax_def
          thresh ||= 0.5
          val = gamepad_axis(axis_name, id)
          cur_active = case dir
                       when :positive then val >= thresh
                       when :negative then val <= -thresh
                       else val >= thresh
                       end
          key = [axis_name, id.to_i, dir]
          prev_active = @axis_state_prev[key] || false
          return true if !cur_active && prev_active
        end

        false
      end

      def action_strength(name, id = 0)
        mask_m = Zenoo::Dev.mask_mouse_input?
        mask_k = Zenoo::Dev.mask_keyboard_input?
        return super unless mask_m || mask_k

        act = @actions[name.to_sym]
        return 0.0 unless act

        max_val = 0.0

        unless mask_k
          act[:keys].each do |k|
            return 1.0 if Native::Input.key_pressed?(k)
          end
        end

        act[:gamepad].each do |b|
          return 1.0 if Native::Input.gamepad_button_pressed?(id.to_i, b)
        end

        unless mask_m
          act[:mouse].each do |m|
            return 1.0 if Native::Input.mouse_pressed?(m)
          end
        end

        act[:axes].each do |ax_def|
          axis_name, dir, _thresh, deadzone = ax_def
          deadzone ||= 0.2
          val = gamepad_axis(axis_name, id)
          raw = case dir
                when :positive then val > 0.0 ? val : 0.0
                when :negative then val < 0.0 ? -val : 0.0
                else val > 0.0 ? val : 0.0
                end

          strength = if raw <= deadzone
                       0.0
                     else
                       ((raw - deadzone) / (1.0 - deadzone)).clamp(0.0, 1.0)
                     end

          max_val = strength if strength > max_val
        end

        max_val
      end
    end
  end
end

# 初期化 & Window / Input モジュールへの prepend
Zenoo::Dev.init
Zenoo::Window.singleton_class.prepend(Zenoo::Dev::WindowPatch)
Zenoo::Input.singleton_class.prepend(Zenoo::Dev::InputPatch)

puts "\e[32m[Zenoo]\e[0m 🛠️  Dev mode active: Hot-reload & Crash-free debugger enabled."

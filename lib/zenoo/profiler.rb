# frozen_string_literal: true

require_relative 'color'

module Zenoo
  # ====================================================
  # Zenoo::Profiler - リアルタイムフレームタイムプロファイラ
  # ====================================================
  # 各処理の実行時間 (ms) をカテゴリ別に高精度計測し、
  # 履歴リングバッファとして保持・可視化するモジュール。
  module Profiler
    DEFAULT_CAPACITY = 120

    # カテゴリ別デフォルト表示色パレット
    CATEGORY_COLORS = {
      update:     Color.new(90, 200, 130),  # エメラルドグリーン
      physics:    Color.new(245, 175, 65),  # アンバー・オレンジ
      separate:   Color.new(255, 95, 95),   # コーラル・レッド (押し出し処理)
      enemy_move: Color.new(255, 190, 60),  # ウォーム・イエロー (敵移動)
      missile:    Color.new(230, 110, 190), # ピンク/マゼンタ (ミサイル追尾)
      player:     Color.new(100, 220, 180), # ターコイズ (自機処理)
      render:     Color.new(75, 170, 245),  # スカイブルー
      gui:        Color.new(185, 115, 235), # パープル (GUI全体)
      gui_text:   Color.new(235, 150, 255), # 明るいパープル/マゼンタ (GUIテキスト描画)
      hud:        Color.new(120, 220, 240), # スカイシアン (HUD描画)
      audio:      Color.new(240, 105, 130), # ローズ
      other:      Color.new(160, 165, 175)  # シルバーグレー
    }.freeze

    FALLBACK_PALETTE = [
      Color.new(100, 220, 180),
      Color.new(250, 140, 80),
      Color.new(140, 160, 250),
      Color.new(230, 110, 190),
      Color.new(210, 220, 90),
      Color.new(120, 200, 220)
    ].freeze

    @enabled = true
    @capacity = DEFAULT_CAPACITY
    @history = [] # 各フレームの { category => ms } の配列 (最新が末尾)
    @current_frame = Hash.new(0.0)
    @start_times = {}
    @section_stack = [] # ネスト計測用スタック: 各要素は [category, t0, child_time]
    @colors = CATEGORY_COLORS.dup
    @registered_categories = []
    @frame_count = 0

    class << self
      attr_accessor :enabled, :capacity

      # カテゴリごとの実行時間をブロックで計測 (ネスト対応: 子セクションの時間は自動で除外され排他自己消費時間を記録)
      # @param category [Symbol, String] 計測カテゴリ (例: :update, :physics, :render, :separate)
      def measure(category)
        return yield unless @enabled

        cat = category.to_sym
        register_category(cat)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        entry = [cat, t0, 0.0]
        @section_stack.push(entry)
        begin
          yield
        ensure
          @section_stack.pop
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          total_ms = (t1 - t0) * 1000.0
          self_ms = total_ms - entry[2]
          self_ms = 0.0 if self_ms < 0.0
          @current_frame[cat] += self_ms

          if (parent = @section_stack.last)
            parent[2] += total_ms
          end
        end
      end

      # 手動での計測開始
      def begin_section(category)
        return unless @enabled
        cat = category.to_sym
        register_category(cat)
        @start_times[cat] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # 手動での計測終了
      def end_section(category)
        return unless @enabled
        cat = category.to_sym
        t0 = @start_times.delete(cat)
        return unless t0
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @current_frame[cat] += (t1 - t0) * 1000.0
      end

      # フレーム終了：計測値を履歴に確定し、次フレームの準備
      def end_frame
        return unless @enabled

        # 現在フレームのスナップショット
        snapshot = @current_frame.dup
        @history << snapshot
        @history.shift if @history.size > @capacity

        @current_frame.clear
        @start_times.clear
        @section_stack.clear
        @frame_count += 1
      end

      # 直近 N フレームの履歴配列 (各要素は { category => ms })
      def history
        @history
      end

      # 登録されている全カテゴリ
      def categories
        @registered_categories
      end

      # カテゴリの表示色を取得
      def color_for(category)
        cat = category.to_sym
        @colors[cat] ||= begin
          idx = @registered_categories.index(cat) || @colors.size
          FALLBACK_PALETTE[idx % FALLBACK_PALETTE.size]
        end
      end

      # カテゴリのカスタム表示色を設定
      def set_color(category, color)
        @colors[category.to_sym] = color
      end

      # 直近フレームのカテゴリ別時間 { category => ms }
      def last_times
        @history.last || {}
      end

      # 直近フレームの合計時間 (ms)
      def last_total_ms
        last = @history.last
        return 0.0 unless last
        last.values.sum
      end

      # 直近 N フレームにおける平均時間 { category => ms }
      def average_times(samples = 30)
        return {} if @history.empty?
        recent = @history.last(samples)
        result = Hash.new(0.0)
        recent.each do |frame|
          frame.each do |cat, ms|
            result[cat] += ms
          end
        end
        count = recent.size.to_f
        result.transform_values! { |v| v / count }
        result
      end

      # 直近 N フレームの最大合計時間 (ms)
      def max_total_ms(samples = 60)
        return 0.0 if @history.empty?
        @history.last(samples).map { |f| f.values.sum }.max || 0.0
      end

      # 履歴のリセット
      def reset
        @history.clear
        @current_frame.clear
        @start_times.clear
      end

      private

      def register_category(cat)
        @registered_categories << cat unless @registered_categories.include?(cat)
      end
    end
  end
end

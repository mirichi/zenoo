# frozen_string_literal: true

module Zenoo
  module GUI
    # コンテナ・行ごとのレイアウトスコープ状態
    class LayoutScope
      attr_accessor :cursor_x, :cursor_y, :line_start_x, :line_max_h,
                    :in_row, :content_w, :content_h,
                    :cols, :col_width

      def spacing_x
        @spacing_x
      end

      def spacing_x=(v)
        @spacing_x = v.to_f
      end

      def spacing_y
        @spacing_y
      end

      def spacing_y=(v)
        @spacing_y = v.to_f
      end

      def initialize(cursor_x: 0.0, cursor_y: 0.0, spacing_x: 8.0, spacing_y: 8.0, content_w: nil, content_h: nil)
        @cursor_x     = cursor_x.to_f
        @cursor_y     = cursor_y.to_f
        @line_start_x = cursor_x.to_f
        @line_max_h   = 0.0
        @spacing_x    = spacing_x.to_f
        @spacing_y    = spacing_y.to_f
        @in_row       = false
        @content_w    = content_w
        @content_h    = content_h
        @cols         = nil
        @col_width    = nil
      end
    end

    # 自動レイアウト & コンテナスコープ管理クラス
    class Layout
      attr_accessor :default_spacing_x, :default_spacing_y

      def initialize
        @default_spacing_x = 8.0
        @default_spacing_y = 8.0
        @scope_stack = []
        reset
      end

      # フレーム先頭でのレイアウト初期化
      def reset
        @scope_stack.clear
        @current = LayoutScope.new(
          spacing_x: @default_spacing_x,
          spacing_y: @default_spacing_y
        )
      end

      def cursor_x
        @current.cursor_x
      end

      def cursor_x=(val)
        @current.cursor_x = val.to_f
        @current.line_start_x = @current.cursor_x unless @current.in_row
        val
      end

      def cursor_y
        @current.cursor_y
      end

      def cursor_y=(val)
        @current.cursor_y = val.to_f
        val
      end

      def cursor(x = nil, y = nil)
        if x && y
          @current.cursor_x = x.to_f
          @current.cursor_y = y.to_f
          unless @current.in_row
            @current.line_start_x = @current.cursor_x
            @current.line_max_h   = 0.0
          end
        end
        [@current.cursor_x, @current.cursor_y]
      end

      def spacing_x
        @current.spacing_x
      end

      def spacing_x=(val)
        @current.spacing_x = val.to_f
        @default_spacing_x = @current.spacing_x if @scope_stack.empty?
        val
      end

      def spacing_y
        @current.spacing_y
      end

      def spacing_y=(val)
        @current.spacing_y = val.to_f
        @default_spacing_y = @current.spacing_y if @scope_stack.empty?
        val
      end

      def spacing(x = nil, y = nil)
        if x
          self.spacing_x = x.to_f
          self.spacing_y = (y || x).to_f
        end
        [@current.spacing_x, @current.spacing_y]
      end

      def content_w
        @current.content_w
      end

      def content_h
        @current.content_h
      end

      # 現在のカーソル位置から利用可能な残り横幅
      def available_width
        return nil unless @current.content_w
        [@current.content_w - @current.cursor_x, 10.0].max
      end

      # 現在のカーソル位置から利用可能な残り縦幅
      def available_height
        return nil unless @current.content_h
        [@current.content_h - @current.cursor_y, 10.0].max
      end

      # ウィジェット横幅の解決:
      # 1. 明示指定 (w) があればその値を使用
      # 2. row(cols: N) のブロック内であれば均等分割された col_width を使用
      # 3. 縦並びかつコンテナ内 (content_w あり) であれば残り横幅いっぱいに自動フィット
      # 4. それ以外 (デスクトップ直置きや cols 指定なしの row 内) は default_w を使用
      def resolve_width(w, default_w)
        return w.to_f if w
        if @current.in_row
          return @current.col_width if @current.col_width
          return default_w.to_f
        end
        if @current.content_w
          return [@current.content_w - @current.cursor_x, 10.0].max
        end
        default_w.to_f
      end

      # ウィジェット配置後のカーソル移動
      def advance(w, h)
        w = w.to_f
        h = h.to_f
        if @current.in_row
          @current.cursor_x += w + @current.spacing_x
          @current.line_max_h = h if h > @current.line_max_h
        else
          @current.cursor_y += h + @current.spacing_y
          @current.cursor_x = @current.line_start_x
          @current.line_max_h = 0.0
        end
      end

      # 余白の挿入
      def spacer(size = 8.0)
        s = size.to_f
        if @current.in_row
          @current.cursor_x += s
        else
          @current.cursor_y += s
        end
      end

      # 横並びブロックの開始
      def begin_row(spacing: -1.0, cols: nil)
        prev_in_row       = @current.in_row
        prev_line_start_x = @current.line_start_x
        prev_line_max_h   = @current.line_max_h
        prev_spacing_x    = @current.spacing_x
        prev_cols         = @current.cols
        prev_col_width    = @current.col_width

        @current.spacing_x = spacing.to_f if spacing >= 0.0
        @current.in_row = true
        @current.line_start_x = @current.cursor_x
        @current.line_max_h   = 0.0

        if cols && cols.to_i > 0
          c_count = cols.to_i
          @current.cols = c_count
          avail = available_width
          if avail
            total_sp = @current.spacing_x * (c_count - 1)
            @current.col_width = [(avail - total_sp) / c_count.to_f, 10.0].max
          else
            @current.col_width = nil
          end
        else
          @current.cols = nil
          @current.col_width = nil
        end

        [prev_in_row, prev_line_start_x, prev_line_max_h, prev_spacing_x, prev_cols, prev_col_width]
      end

      # 横並びブロックの終了
      def end_row(prev)
        row_h = @current.line_max_h
        @current.in_row       = prev[0]
        @current.line_start_x = prev[1]
        @current.cursor_x     = prev[1]
        @current.spacing_x    = prev[3]
        @current.cols         = prev[4]
        @current.col_width    = prev[5]

        if @current.in_row
          @current.line_max_h = [prev[2], row_h].max
        else
          @current.cursor_y += row_h + @current.spacing_y
          @current.line_max_h = 0.0
        end
      end

      # 横並びブロック (cols: N を指定するとコンテナ幅を N 等分した幅を自動割り当て)
      def row(spacing: -1.0, cols: nil)
        prev = begin_row(spacing: spacing, cols: cols)
        yield
        end_row(prev)
      end

      # コンテナスコープの開始
      def begin_container(x, y, w, h, clip: false, z: 0.0, spacing_x: nil, spacing_y: nil)
        @scope_stack.push(@current)
        @current = LayoutScope.new(
          cursor_x: 0.0,
          cursor_y: 0.0,
          spacing_x: spacing_x ? spacing_x.to_f : @current.spacing_x,
          spacing_y: spacing_y ? spacing_y.to_f : @current.spacing_y,
          content_w: w.to_f,
          content_h: h.to_f
        )

        if clip
          clip_offsets = Window.push_clip_scope(x, y, w, h, local: true, z: z)
          [true, clip_offsets]
        else
          prev_ox = Window.offset_x
          prev_oy = Window.offset_y
          Window.offset_x = prev_ox + x.to_f
          Window.offset_y = prev_oy + y.to_f
          [false, [prev_ox, prev_oy]]
        end
      end

      # コンテナスコープの終了
      def end_container(state)
        is_clip, offsets = state
        if is_clip
          Window.pop_clip_scope(offsets[0], offsets[1])
        else
          Window.offset_x = offsets[0]
          Window.offset_y = offsets[1]
        end
        @current = @scope_stack.pop if @scope_stack.any?
      end

      # コンテナスコープ (panel / window 共通のローカル座標系 & スコープ退避)
      # - clip: true  => Window.clip(..., local: true, z: z) でハードウェアシザー + ローカル座標化
      # - clip: false => Window.offset_x / offset_y のみシフトしてローカル座標化
      def container(x, y, w, h, clip: false, z: 0.0, spacing_x: nil, spacing_y: nil)
        state = begin_container(x, y, w, h, clip: clip, z: z, spacing_x: spacing_x, spacing_y: spacing_y)
        yield
        end_container(state)
      end
    end
  end
end

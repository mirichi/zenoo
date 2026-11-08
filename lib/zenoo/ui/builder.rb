# frozen_string_literal: true

module Zenoo
  module UI
    # コンテナ（Box, Stage, Window, ScrollView 等）で子ウィジェットを手軽に
    # 生成・追加するためのビルダー DSL モジュール
    module Builder
      # コンテナ系
      def box(*args, **opts, &block)
        add(Box.new(*args, **opts), &block)
      end

      def vbox(*args, **opts, &block)
        add(VBox.new(*args, **opts), &block)
      end

      def hbox(*args, **opts, &block)
        add(HBox.new(*args, **opts), &block)
      end

      def panel(*args, **opts, &block)
        add(Panel.new(*args, **opts), &block)
      end

      def window(*args, **opts, &block)
        add(Window.new(*args, **opts), &block)
      end

      def scroll_view(*args, **opts, &block)
        add(ScrollView.new(*args, **opts), &block)
      end

      # 基本ウィジェット系
      def label(*args, **opts, &block)
        add(Label.new(*args, **opts), &block)
      end

      def divider(*args, **opts, &block)
        add(Divider.new(*args, **opts), &block)
      end

      def spacer(*args, **opts, &block)
        add(Spacer.new(*args, **opts), &block)
      end

      def image_box(*args, **opts, &block)
        add(ImageBox.new(*args, **opts), &block)
      end

      def button(*args, **opts, &block)
        add(Button.new(*args, **opts, &block))
      end

      def checkbox(*args, **opts, &block)
        add(Checkbox.new(*args, **opts, &block))
      end

      def radio_button(*args, **opts, &block)
        add(RadioButton.new(*args, **opts, &block))
      end

      def progress_bar(*args, **opts, &block)
        add(ProgressBar.new(*args, **opts), &block)
      end

      def slider(*args, **opts, &block)
        add(Slider.new(*args, **opts, &block))
      end

      def spinner(*args, **opts, &block)
        add(Spinner.new(*args, **opts, &block))
      end

      def tabs(*args, **opts, &block)
        add(Tabs.new(*args, **opts, &block))
      end

      def text_box(*args, **opts, &block)
        add(TextBox.new(*args, **opts, &block))
      end

      def dropdown(*args, **opts, &block)
        add(Dropdown.new(*args, **opts, &block))
      end

      def list_box(*args, **opts, &block)
        add(ListBox.new(*args, **opts, &block))
      end

      # 独自カスタムウィジェット用ヘルパー (on_draw をその場で適用)
      def custom(*args, **opts, &block)
        w = add(Widget.new(*args, **opts))
        w.on_draw(&block) if block
        w
      end
    end
  end
end

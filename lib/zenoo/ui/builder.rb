# frozen_string_literal: true

module Zenoo
  module UI
    # コンテナ（Box, Stage, Window, ScrollView 等）で子ウィジェットを手軽に
    # 生成・追加するためのビルダー DSL モジュール
    # Spinel AOT 最適化のため、主要引数を明示的に宣言して動的ディスパッチによる引数脱落を防止
    module Builder
      # コンテナ系
      def box(x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(Box.new(x, y, width: width, height: height, **opts), &block)
      end

      def vbox(x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(VBox.new(x, y, width: width, height: height, **opts), &block)
      end

      def hbox(x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(HBox.new(x, y, width: width, height: height, **opts), &block)
      end

      def panel(x = 0.0, y = 0.0, width: 320.0, height: 240.0, title: "", **opts, &block)
        add(Panel.new(x, y, width: width, height: height, title: title, **opts), &block)
      end

      def window(title = "Window", x = 60.0, y = 60.0, width: 340.0, height: 260.0, **opts, &block)
        add(Window.new(title, x, y, width: width, height: height, **opts), &block)
      end

      def scroll_view(x = 0.0, y = 0.0, width: 200.0, height: 200.0, **opts, &block)
        add(ScrollView.new(x, y, width: width, height: height, **opts), &block)
      end

      # 基本ウィジェット系
      def label(text = "", x = 0.0, y = 0.0, width: nil, height: nil, size: nil, color: nil, **opts, &block)
        add(Label.new(text, x, y, width: width, height: height, size: size, color: color, **opts), &block)
      end

      def divider(x = 0.0, y = 0.0, width: 200.0, height: 10.0, color: nil, **opts, &block)
        add(Divider.new(x, y, width: width, height: height, color: color, **opts), &block)
      end

      def spacer(size = 8.0, flex: nil, **opts, &block)
        add(Spacer.new(size, flex: flex, **opts), &block)
      end

      def image_box(image = nil, x = 0.0, y = 0.0, width: nil, height: nil, **opts, &block)
        add(ImageBox.new(image, x, y, width: width, height: height, **opts), &block)
      end

      def button(label = "Button", x = 0.0, y = 0.0, width: 140.0, height: 38.0, **opts, &block)
        add(Button.new(label, x, y, width: width, height: height, **opts, &block))
      end

      def checkbox(label = "", checked = false, x = 0.0, y = 0.0, width: nil, height: 28.0, **opts, &block)
        add(Checkbox.new(label, checked, x, y, width: width, height: height, **opts, &block))
      end

      def radio_button(label = "", active = false, x = 0.0, y = 0.0, width: nil, height: 28.0, **opts, &block)
        add(RadioButton.new(label, active, x, y, width: width, height: height, **opts, &block))
      end

      def progress_bar(value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0, width: 220.0, height: 20.0, **opts, &block)
        add(ProgressBar.new(value, min, max, x, y, width: width, height: height, **opts), &block)
      end

      def slider(label = "", value = 0.0, min = 0.0, max = 100.0, x = 0.0, y = 0.0, width: 220.0, height: 42.0, **opts, &block)
        add(Slider.new(label, value, min, max, x, y, width: width, height: height, **opts, &block))
      end

      def spinner(label = "", value = 0, x = 0.0, y = 0.0, width: 220.0, height: 34.0, **opts, &block)
        add(Spinner.new(label, value, x, y, width: width, height: height, **opts, &block))
      end

      def tabs(labels = [], selected_index = 0, x = 0.0, y = 0.0, width: 300.0, height: 36.0, **opts, &block)
        add(Tabs.new(labels, selected_index, x, y, width: width, height: height, **opts, &block))
      end

      def text_box(text = "", x = 0.0, y = 0.0, width: 220.0, height: 38.0, **opts, &block)
        add(TextBox.new(text, x, y, width: width, height: height, **opts, &block))
      end

      def dropdown(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 200.0, height: 36.0, **opts, &block)
        add(Dropdown.new(items, selected_index, x, y, width: width, height: height, **opts, &block))
      end

      def list_box(items = [], selected_index = 0, x = 0.0, y = 0.0, width: 240.0, height: 150.0, **opts, &block)
        add(ListBox.new(items, selected_index, x, y, width: width, height: height, **opts, &block))
      end

      # 独自カスタムウィジェット用ヘルパー (on_draw をその場で適用)
      def custom(x = 0.0, y = 0.0, width: 100.0, height: 32.0, collider: nil, **opts, &block)
        w = add(Widget.new(x, y, width: width, height: height, **opts))
        w.set_collider(collider) if collider
        w.on_draw(&block) if block
        w
      end
    end
  end
end

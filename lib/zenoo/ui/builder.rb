# frozen_string_literal: true

module Zenoo
  module UI
    # 宣言的 UI ツリー構築を提供するビルダー DSL
    module Builder
      def vbox(x = 0.0, y = 0.0, **opts, &block)
        w = add(VBox.new(x, y, **opts))
        yield(w) if block
        w
      end

      def hbox(x = 0.0, y = 0.0, **opts, &block)
        w = add(HBox.new(x, y, **opts))
        yield(w) if block
        w
      end

      def scroll_view(x = 0.0, y = 0.0, **opts, &block)
        w = add(ScrollView.new(x, y, **opts))
        yield(w) if block
        w
      end

      def window(title = "Window", x = 60.0, y = 60.0, **opts, &block)
        w = add(Window.new(title, x, y, **opts))
        yield(w) if block
        w
      end

      def panel(x = 0.0, y = 0.0, **opts, &block)
        w = add(Panel.new(x, y, **opts))
        yield(w) if block
        w
      end

      def divider(**opts)                                           = add(Divider.new(**opts))
      def spacer(size = 8.0, **opts)                                = add(Spacer.new(size, **opts))
      def image_box(image = nil, **opts)                            = add(ImageBox.new(image, **opts))
      def label(text = "", **opts)                                  = add(Label.new(text, **opts))
      def button(label = "Button", **opts, &block)                  = add(Button.new(label, **opts, &block))
      def checkbox(label = "", checked = false, **opts, &block)     = add(Checkbox.new(label, checked, **opts, &block))
      def switch(label = "", checked = false, **opts, &block)       = add(Switch.new(label, checked, **opts, &block))
      def radio_button(label = "", checked = false, **opts, &block) = add(RadioButton.new(label, checked, **opts, &block))
      def progress_bar(value = 0.0, min = 0.0, max = 1.0, **opts)   = add(ProgressBar.new(value, min, max, **opts))
      def spinner(label = "", value = 0, **opts, &block)            = add(Spinner.new(label, value, **opts, &block))
      def slider(label = "", value = 0.0, min = 0.0, max = 100.0, **opts, &block)         = add(Slider.new(label, value, min, max, **opts, &block))
      def stacked_slider(label = "", value = 0.0, min = 0.0, max = 100.0, **opts, &block) = add(StackedSlider.new(label, value, min, max, **opts, &block))
      def dropdown(items = [], selected_index = 0, **opts, &block)  = add(Dropdown.new(items, selected_index, **opts, &block))
      def text_box(text = "", **opts, &block)                       = add(TextBox.new(text, **opts, &block))
      def tabs(items = [], selected_index = 0, **opts, &block)      = add(Tabs.new(items, selected_index, **opts, &block))
      def table(columns = [], rows = [], selected_index = nil, **opts, &block) = add(Table.new(columns, rows, selected_index, **opts, &block))
      def profile_graph(**opts)                                     = add(ProfileGraph.new(**opts))
      def custom(width: 100.0, height: 32.0, **opts, &block)        = add(Widget.new(0.0, 0.0, width: width, height: height, **opts)).on_draw(&block)
    end
  end
end

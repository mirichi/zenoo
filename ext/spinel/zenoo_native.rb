module Zenoo
  native_lib "glfw"
  native_lib "GL"
  native_lib "m"

  # ==========================================
  # 1. Image (Spinel native_struct)
  # ==========================================
  native_struct "Zenoo::Image", "sp_ZenImage", "sp_ZenImage_free"
  native_new [:int, :int], "sp_ZenImage_new"
  native_new [:string],    "sp_ZenImage_load"
  native_method :width,  [], :int, "sp_ZenImage_width"
  native_method :height, [], :int, "sp_ZenImage_height"
  native_method :set_as_render_target, [], :nil, "sp_ZenImage_set_as_render_target"

  # ==========================================
  # 2. Native::NativeShader (Spinel native_struct)
  # ==========================================
  native_struct "Zenoo::Native::NativeShader", "sp_ZenShader", "sp_ZenShader_free"
  native_new [:string, :string], "sp_ZenShader_new"
  native_method :set_int,   [:string, :int],   :nil, "sp_ZenShader_set_int"
  native_method :set_float, [:string, :float], :nil, "sp_ZenShader_set_float"
  native_method :set_vec2,  [:string, :float, :float], :nil, "sp_ZenShader_set_vec2"
  native_method :set_vec3,  [:string, :float, :float, :float], :nil, "sp_ZenShader_set_vec3"
  native_method :set_vec4,  [:string, :float, :float, :float, :float], :nil, "sp_ZenShader_set_vec4"
  native_method :set_mat4,  [:string, :string], :nil, "sp_ZenShader_set_mat4"

  module Native
    # ==========================================
    # 3. Native::Window
    # ==========================================
    module Window
      native_func :raw_init, [:int, :int, :string, :int], :int, "sp_zen_win_init"
      native_func :update, [], :bool, "sp_zen_win_update"
      native_func :clear, [:int], :nil, "sp_zen_win_clear"
      native_func :size_w, [], :int, "sp_zen_win_size_w"
      native_func :size_h, [], :int, "sp_zen_win_size_h"
      native_func :vsync=, [:int], :nil, "sp_zen_win_vsync_set"
      native_func :target_fps=, [:int], :nil, "sp_zen_win_target_fps_set"
      native_func :delta_time, [], :float, "sp_zen_win_delta_time"
      native_func :time, [], :float, "sp_zen_win_time"
      native_func :shutdown, [], :nil, "sp_zen_win_shutdown"
      native_func :wasm?, [], :bool, "sp_zen_win_is_wasm"
      native_func :start_wasm_loop, [:any], :nil, "sp_zen_win_start_wasm_loop"

      def self.init(w, h, title, fullscreen = false)
        Zenoo::Native::Window.raw_init(w.to_i, h.to_i, title.to_s, fullscreen ? 1 : 0)
      end
    end

    # ==========================================
    # 4. Native::Input
    # ==========================================
    module Input
      native_func :key_pressed?, [:int], :bool, "sp_zen_input_key_pressed"
      native_func :key_push?, [:int], :bool, "sp_zen_input_key_push"
      native_func :key_release?, [:int], :bool, "sp_zen_input_key_release"
      native_func :mouse_pressed?, [:int], :bool, "sp_zen_input_mouse_pressed"
      native_func :mouse_push?, [:int], :bool, "sp_zen_input_mouse_push"
      native_func :mouse_release?, [:int], :bool, "sp_zen_input_mouse_release"
      native_func :mouse_x, [], :float, "sp_zen_input_mouse_x"
      native_func :mouse_y, [], :float, "sp_zen_input_mouse_y"
      native_func :gamepad_connected?, [:int], :bool, "sp_zen_input_gamepad_connected"
      native_func :gamepad_axis, [:int, :int], :float, "sp_zen_input_gamepad_axis"
      native_func :gamepad_button_pressed?, [:int, :int], :bool, "sp_zen_input_gamepad_button_pressed"
      native_func :gamepad_button_push?, [:int, :int], :bool, "sp_zen_input_gamepad_button_push"
      native_func :gamepad_button_release?, [:int, :int], :bool, "sp_zen_input_gamepad_button_release"
      native_func :get_char, [], :int, "sp_zen_input_get_char"
      native_func :set_ime_position, [:int, :int], :nil, "sp_zen_input_set_ime_position"
    end

    # ==========================================
    # 5. Native::Renderer
    # ==========================================
    module Renderer
      native_func :flush, [], :nil, "sp_zen_renderer_flush"
      native_func :set_blend_mode, [:int], :nil, "sp_zen_renderer_set_blend_mode"
      native_func :raw_draw_buffer, [
        :int, :string, :string, :int, :string, :int, :any, :any
      ], :nil, "sp_zen_renderer_draw_buffer"

      def self.draw_buffer(topology, layout, divisors, base_vertex_count, data, count, img, sh)
        Zenoo::Native::Renderer.raw_draw_buffer(
          topology.to_i,
          layout.to_s,
          divisors.to_s,
          base_vertex_count.to_i,
          data.to_s,
          count.to_i,
          img,
          sh
        )
      end
    end
    # ==========================================
    # 6. Native::Image
    # ==========================================
    module Image
      native_func :reset_render_target, [], :nil, "sp_ZenImage_reset_render_target"
      native_func :free_count, [], :int, "sp_zen_get_image_free_count"
    end

    # ==========================================
    # 7. Native::FontHelper
    # ==========================================
    module FontHelper
      native_func :glyph_visible, [], :bool,  "sp_zen_font_glyph_visible"
      native_func :glyph_u0,      [], :float, "sp_zen_font_glyph_u0"
      native_func :glyph_v0,      [], :float, "sp_zen_font_glyph_v0"
      native_func :glyph_u1,      [], :float, "sp_zen_font_glyph_u1"
      native_func :glyph_v1,      [], :float, "sp_zen_font_glyph_v1"
      native_func :glyph_x0,      [], :float, "sp_zen_font_glyph_x0"
      native_func :glyph_y0,      [], :float, "sp_zen_font_glyph_y0"
      native_func :glyph_x1,      [], :float, "sp_zen_font_glyph_x1"
      native_func :glyph_y1,      [], :float, "sp_zen_font_glyph_y1"
      native_func :glyph_advance,   [], :float, "sp_zen_font_glyph_advance"
      native_func :glyph_is_bitmap, [], :bool,  "sp_zen_font_glyph_is_bitmap"
      native_func :atlas_image_raw, [:int], :any, "sp_zen_font_atlas_image"
    end
  end

  # ==========================================
  # 8. Native::Font (Spinel native_struct)
  # ==========================================
  native_struct "Zenoo::Native::Font", "sp_ZenFont", "sp_ZenFont_free"
  native_new [:string], "sp_ZenFont_load"
  native_method :metrics_ascent,   [:float], :float, "sp_zen_font_metrics_ascent"
  native_method :metrics_descent,  [:float], :float, "sp_zen_font_metrics_descent"
  native_method :metrics_line_gap, [:float], :float, "sp_zen_font_metrics_line_gap"
  native_method :query_glyph,      [:int, :float], :bool, "sp_zen_font_query_glyph"
end

class Zenoo::Image
  def self.reset_render_target
    Zenoo::Native::Image.reset_render_target
  end

  def self.load(path)
    new(path)
  end
end

class Zenoo::Native::Font
  def self.load(path)
    new(path.to_s)
  end

  def self.atlas_image
    @atlas ||= Zenoo::Native::FontHelper.atlas_image_raw(0)
  end

  def metrics(size)
    s = size.to_f
    [metrics_ascent(s), metrics_descent(s), metrics_line_gap(s)]
  end

  def get_glyph(cp, size)
    ok = query_glyph(cp.to_i, size.to_f)
    return nil unless ok

    [
      Zenoo::Native::FontHelper.glyph_visible,
      Zenoo::Native::FontHelper.glyph_u0,
      Zenoo::Native::FontHelper.glyph_v0,
      Zenoo::Native::FontHelper.glyph_u1,
      Zenoo::Native::FontHelper.glyph_v1,
      Zenoo::Native::FontHelper.glyph_x0,
      Zenoo::Native::FontHelper.glyph_y0,
      Zenoo::Native::FontHelper.glyph_x1,
      Zenoo::Native::FontHelper.glyph_y1,
      Zenoo::Native::FontHelper.glyph_advance,
      Zenoo::Native::FontHelper.glyph_is_bitmap
    ]
  end
end

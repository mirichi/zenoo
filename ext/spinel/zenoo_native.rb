module Zenoo
  native_lib "glfw"
  native_lib "GL"
  native_lib "m"

  native_func :version, [], :string, "sp_zen_get_version"
  VERSION = version

  # ==========================================
  # 1. Image (Spinel native_struct)
  # ==========================================
  native_struct "Zenoo::Image", "sp_ZenImage", "sp_ZenImage_free"
  native_new [:int, :int], "sp_ZenImage_new"
  native_new [:int, :int, :int, :int], "sp_ZenImage_new_format_internal"
  native_new [:string],    "sp_ZenImage_load"
  native_method :width,  [], :int, "sp_ZenImage_width"
  native_method :height, [], :int, "sp_ZenImage_height"
  native_method :set_as_render_target, [], :nil, "sp_ZenImage_set_as_render_target"
  native_method :sub_image, [:int, :int, :int, :int], :self, "sp_ZenImage_sub_image"
  native_method :x, [], :int, "sp_ZenImage_x"
  native_method :y, [], :int, "sp_ZenImage_y"
  native_method :texture_width, [], :int, "sp_ZenImage_texture_width"
  native_method :texture_height, [], :int, "sp_ZenImage_texture_height"
  native_method :texture_id, [], :int, "sp_ZenImage_texture_id"
  native_method :sub_image?, [], :bool, "sp_ZenImage_is_sub_image"
  native_method :raw_texture_filter=, [:int], :nil, "sp_ZenImage_set_filter"
  native_method :raw_texture_filter, [], :int, "sp_ZenImage_get_filter"
  native_class_method :raw_default_texture_filter=, [:int], :nil, "sp_zen_image_set_default_filter"
  native_class_method :raw_default_texture_filter, [], :int, "sp_zen_image_get_default_filter"
  native_method :replace_texture!, [:self], :nil, "sp_ZenImage_replace_texture"

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
      native_func :raw_init_scaled, [:int, :int, :string, :int, :int, :int], :int, "sp_zen_win_init_scaled"
      native_func :update, [], :bool, "sp_zen_win_update"
      native_func :clear, [:int], :nil, "sp_zen_win_clear"
      native_func :size_w, [], :int, "sp_zen_win_size_w"
      native_func :size_h, [], :int, "sp_zen_win_size_h"
      native_func :os_size_w, [], :int, "sp_zen_win_os_size_w"
      native_func :os_size_h, [], :int, "sp_zen_win_os_size_h"
      native_func :raw_scale_mode=, [:int], :nil, "sp_zen_win_set_scale_mode"
      native_func :raw_scale_mode, [], :int, "sp_zen_win_get_scale_mode"
      native_func :scale=, [:float], :nil, "sp_zen_win_set_scale"
      native_func :scale, [], :float, "sp_zen_win_get_scale"
      native_func :set_window_size, [:int, :int], :nil, "sp_zen_win_set_window_size"
      native_func :vsync=, [:int], :nil, "sp_zen_win_vsync_set"
      native_func :target_fps=, [:int], :nil, "sp_zen_win_target_fps_set"
      native_func :delta_time, [], :float, "sp_zen_win_delta_time"
      native_func :time, [], :float, "sp_zen_win_time"
      native_func :shutdown, [], :nil, "sp_zen_win_shutdown"
      native_func :wasm?, [], :bool, "sp_zen_win_is_wasm"
      native_func :start_wasm_loop, [:any], :nil, "sp_zen_win_start_wasm_loop"

      def self.scale_mode=(val)
        mode = (val == :integer || val == 1) ? 1 : 0
        Zenoo::Native::Window.raw_scale_mode = mode
      end

      def self.scale_mode
        Zenoo::Native::Window.raw_scale_mode == 1 ? :integer : :fit
      end

      def self.window_size
        [Zenoo::Native::Window.os_size_w, Zenoo::Native::Window.os_size_h]
      end

      def self.init(w, h, title, fullscreen = false, win_w = 0, win_h = 0, scale_mode = 0)
        win_w = w.to_i if win_w.to_i <= 0
        win_h = h.to_i if win_h.to_i <= 0
        Zenoo::Native::Window.raw_init_scaled(w.to_i, h.to_i, title.to_s, win_w, win_h, fullscreen ? 1 : 0)
        Zenoo::Native::Window.scale_mode = scale_mode
      end
    end

    # ==========================================
    # 4. Native::Input
    # ==========================================
    module Input
      native_func :key_pressed?, [:int], :bool, "sp_zen_input_key_pressed"
      native_func :key_push?, [:int], :bool, "sp_zen_input_key_push"
      native_func :key_release?, [:int], :bool, "sp_zen_input_key_release"
      native_func :key_repeat?, [:int], :bool, "sp_zen_input_key_repeat"
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
      native_func :vibrate_gamepad, [:int, :float, :float, :float], :nil, "sp_zen_input_vibrate_gamepad"
      native_func :vibrate, [:float], :nil, "sp_zen_input_vibrate"
      native_func :get_char, [], :int, "sp_zen_input_get_char"
      native_func :set_ime_position, [:int, :int], :nil, "sp_zen_input_set_ime_position"

      def self.input_chars
        chars = []
        while (cp = Zenoo::Native::Input.get_char) != -1
          begin
            chars << cp.chr(Encoding::UTF_8)
          rescue
          end
        end
        chars
      end
    end

    # ==========================================
    # 5. Native::Renderer
    # ==========================================
    module Renderer
      native_func :flush, [], :nil, "sp_zen_renderer_flush"
      native_func :set_blend_mode, [:int], :nil, "sp_zen_renderer_set_blend_mode"
      native_func :raw_set_scissor, [:int, :int, :int, :int], :nil, "sp_zen_renderer_set_scissor"
      native_func :reset_scissor, [], :nil, "sp_zen_renderer_reset_scissor"
      native_func :raw_draw_buffer, [
        :int, :string, :string, :int, :string, :int, :any, :any
      ], :nil, "sp_zen_renderer_draw_buffer"

      def self.set_scissor(x, y, w, h)
        Zenoo::Native::Renderer.raw_set_scissor(x.to_i, y.to_i, w.to_i, h.to_i)
      end

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

      # ライブラリ内部専用のフォーマット指定生成メソッド
      def self.create_format(w, h, format)
        Zenoo::Image.new(w.to_i, h.to_i, -1, format.to_i)
      end

      def self.create_r8(w, h)
        create_format(w, h, 1)
      end
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
      native_func :set_atlas_image, [:any], :nil, "sp_zen_font_set_atlas_image"
    end

    # ==========================================
    # 8. Native::Audio
    # ==========================================
    module Audio
      native_func :init, [], :bool, "sp_zen_audio_init"
      native_func :shutdown, [], :nil, "sp_zen_audio_shutdown"
      native_func :master_volume=, [:float], :nil, "sp_zen_audio_set_master_volume"
      native_func :master_volume, [], :float, "sp_zen_audio_get_master_volume"
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

  # ==========================================
  # 9. Native::Sound (Spinel native_struct)
  # ==========================================
  native_struct "Zenoo::Native::Sound", "sp_ZenSound", "sp_ZenSound_free"
  native_new [:string], "sp_ZenSound_load"
  native_new [:string, :int, :int, :int], "sp_ZenSound_load_pcm"
  native_method :play, [], :nil, "sp_ZenSound_play"
  native_method :stop, [], :nil, "sp_ZenSound_stop"
  native_method :pause, [], :nil, "sp_ZenSound_pause"
  native_method :playing?, [], :bool, "sp_ZenSound_is_playing"
  native_method :volume=, [:float], :nil, "sp_ZenSound_set_volume"
  native_method :volume, [], :float, "sp_ZenSound_get_volume"
  native_method :looping=, [:bool], :nil, "sp_ZenSound_set_looping"
  native_method :looping?, [], :bool, "sp_ZenSound_is_looping"
  native_method :pitch=, [:float], :nil, "sp_ZenSound_set_pitch"
  native_method :pitch, [], :float, "sp_ZenSound_get_pitch"
  native_method :pan=, [:float], :nil, "sp_ZenSound_set_pan"
  native_method :pan, [], :float, "sp_ZenSound_get_pan"
  native_method :seek, [:float], :nil, "sp_ZenSound_seek"
  native_method :cursor, [], :float, "sp_ZenSound_get_cursor"
  native_method :time, [], :float, "sp_ZenSound_get_cursor"
  native_method :time=, [:float], :nil, "sp_ZenSound_seek"
  native_method :length, [], :float, "sp_ZenSound_get_length"
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
    Zenoo::Font.atlas_image
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

class Zenoo::Native::Sound
  def self.load(path)
    new(path.to_s)
  end

  def self.load_pcm(samples_binary, channels, sample_rate)
    bytes = samples_binary.bytesize
    frame_count = bytes / 4 / channels
    new(samples_binary, frame_count, channels, sample_rate)
  end
end


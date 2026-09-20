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
  # 2. Shader (Spinel native_struct)
  # ==========================================
  native_struct "Zenoo::Shader", "sp_ZenShader", "sp_ZenShader_free"
  native_new [:string, :string], "sp_ZenShader_new"
  native_method :set_int,   [:string, :int],   :nil, "sp_ZenShader_set_int"
  native_method :set_float, [:string, :float], :nil, "sp_ZenShader_set_float"
  native_method :set_vec2,  [:string, :float, :float], :nil, "sp_ZenShader_set_vec2"
  native_method :set_vec3,  [:string, :float, :float, :float], :nil, "sp_ZenShader_set_vec3"
  native_method :set_vec4,  [:string, :float, :float, :float, :float], :nil, "sp_ZenShader_set_vec4"

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
    end

    # ==========================================
    # 5. Native::Renderer
    # ==========================================
    module Renderer
      native_func :flush, [], :nil, "sp_zen_renderer_flush"
      native_func :draw_triangle, [
        :float, :float, :float, :float, :float, :float,
        :float, :float, :float, :float
      ], :nil, "sp_zen_renderer_draw_triangle"
      native_func :draw_line, [
        :float, :float, :float, :float,
        :float, :float, :float, :float
      ], :nil, "sp_zen_renderer_draw_line"
      native_func :raw_draw_quad, [
        :float, :float, :float, :float,
        :float, :float, :float, :float,
        :float, :float, :float, :float,
        :float, :float, :float, :float,
        :float, :float, :float, :float,
        :float, :float, :float, :float,
        :any, :any
      ], :nil, "sp_zen_renderer_draw_quad_generic_wrapper"

      def self.draw_quad(x, y, w, h, uv, color, p0, p1, p2, img, sh)
        u0 = uv ? uv[0].to_f : 0.0
        v0 = uv ? uv[1].to_f : 0.0
        u1 = uv ? (uv[2] || 1.0).to_f : 1.0
        v1 = uv ? (uv[3] || 1.0).to_f : 1.0

        cr = color ? (color[0] || 1.0).to_f : 1.0
        cg = color ? (color[1] || 1.0).to_f : 1.0
        cb = color ? (color[2] || 1.0).to_f : 1.0
        ca = color ? (color[3] || 1.0).to_f : 1.0

        p0_0 = p0 ? p0[0].to_f : 0.0
        p0_1 = p0 ? p0[1].to_f : 0.0
        p0_2 = p0 ? p0[2].to_f : 0.0
        p0_3 = p0 ? p0[3].to_f : 0.0

        p1_0 = p1 ? p1[0].to_f : 0.0
        p1_1 = p1 ? p1[1].to_f : 0.0
        p1_2 = p1 ? p1[2].to_f : 0.0
        p1_3 = p1 ? p1[3].to_f : 0.0

        p2_0 = p2 ? p2[0].to_f : 0.0
        p2_1 = p2 ? p2[1].to_f : 0.0
        p2_2 = p2 ? p2[2].to_f : 0.0
        p2_3 = p2 ? p2[3].to_f : 0.0

        Zenoo::Native::Renderer.raw_draw_quad(
          x.to_f, y.to_f, w.to_f, h.to_f,
          u0, v0, u1, v1,
          cr, cg, cb, ca,
          p0_0, p0_1, p0_2, p0_3,
          p1_0, p1_1, p1_2, p1_3,
          p2_0, p2_1, p2_2, p2_3,
          img, sh
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
  end
end

class Zenoo::Image
  def self.reset_render_target
    Zenoo::Native::Image.reset_render_target
  end

  def self.load(path)
    new(path)
  end
end

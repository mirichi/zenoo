# frozen_string_literal: true

# Spinel AOT FFI バインディング宣言
# 兼 CRuby C 拡張 (tools/generate_cruby_ext.rb -> ext/zenoo/zenoo_ext.c) 生成用マスター宣言ファイル

module Zenoo
  module Native
    module C
      ffi_lib ""

      ffi_callback :zen_void_cb, [], :void

      # ==========================================
      # System / Lifecycle / Handle Management
      # ==========================================
      ffi_func :zen_get_version, [], :str
      ffi_func :zen_ensure_context, [], :int
      ffi_func :zen_ffi_win_init, [:int, :int, :str, :int], :int
      ffi_func :zen_ffi_win_init_scaled, [:int, :int, :str, :int, :int, :int, :float], :int
      ffi_func :zen_shutdown, [], :void
      ffi_func :zen_toggle_fullscreen, [], :void
      ffi_func :zen_update, [], :int
      ffi_func :zen_begin_frame, [], :int
      ffi_func :zen_end_frame, [], :void
      ffi_func :zen_clear, [:uint32], :void
      ffi_func :zen_run_loop, [:zen_void_cb], :void
      ffi_func :zen_set_frame_callback, [:zen_void_cb], :void
      ffi_func :zen_ffi_clear_frame_callback, [], :void
      ffi_func :zen_is_wasm, [], :int
      ffi_func :zen_set_gc_trigger_callback, [:zen_void_cb], :void

      ffi_func :zen_ffi_destroy_handle, [:ptr, :int], :void
      ffi_func :zen_ffi_image_free_count, [], :int

      # ==========================================
      # Window Info & Settings
      # ==========================================
      ffi_func :zen_ffi_screen_w, [], :int
      ffi_func :zen_ffi_screen_h, [], :int
      ffi_func :zen_ffi_window_w, [], :int
      ffi_func :zen_ffi_window_h, [], :int
      ffi_func :zen_set_window_size, [:int, :int], :void
      ffi_func :zen_set_window_title, [:str], :void
      ffi_func :zen_get_window_title, [], :str
      ffi_func :zen_ffi_window_pos_x, [], :int
      ffi_func :zen_ffi_window_pos_y, [], :int
      ffi_func :zen_set_window_pos, [:int, :int], :void
      ffi_func :zen_is_window_focused, [], :int
      ffi_func :zen_is_window_minimized, [], :int
      ffi_func :zen_is_window_maximized, [], :int
      ffi_func :zen_is_window_hovered, [], :int
      ffi_func :zen_is_resizing, [], :int
      ffi_func :zen_set_live_resize, [:int], :void
      ffi_func :zen_get_live_resize, [], :int
      ffi_func :zen_set_scale_mode, [:int], :void
      ffi_func :zen_get_scale_mode, [], :int
      ffi_func :zen_get_scale, [], :float
      ffi_func :zen_set_window_scale, [:float], :void
      ffi_func :zen_get_window_scale, [], :float
      ffi_func :zen_get_dpi_scale, [], :float
      ffi_func :zen_set_target_fps, [:int], :void
      ffi_func :zen_get_target_fps, [], :int
      ffi_func :zen_set_vsync, [:int], :void
      ffi_func :zen_window_set_msaa_samples, [:int], :void
      ffi_func :zen_window_get_msaa_samples, [], :int
      ffi_func :zen_get_delta_time, [], :float
      ffi_func :zen_get_time, [], :double
      ffi_func :zen_window_show_cursor, [:int], :void
      ffi_func :zen_window_set_cursor, [:int], :void

      # ==========================================
      # Input / IME / Touch / Gamepad
      # ==========================================
      ffi_func :zen_window_get_clipboard_string, [], :str
      ffi_func :zen_window_set_clipboard_string, [:str], :void
      ffi_func :zen_is_key_pressed, [:int], :int
      ffi_func :zen_is_key_push, [:int], :int
      ffi_func :zen_is_key_release, [:int], :int
      ffi_func :zen_is_key_repeat, [:int], :int
      ffi_func :zen_ffi_mouse_x, [], :float
      ffi_func :zen_ffi_mouse_y, [], :float
      ffi_func :zen_is_mouse_pressed, [:int], :int
      ffi_func :zen_is_mouse_push, [:int], :int
      ffi_func :zen_is_mouse_release, [:int], :int
      ffi_func :zen_get_mouse_wheel_x, [], :float
      ffi_func :zen_get_mouse_wheel_y, [], :float
      ffi_func :zen_is_gamepad_connected, [:int], :int
      ffi_func :zen_get_gamepad_axis, [:int, :int], :float
      ffi_func :zen_is_gamepad_button_pressed, [:int, :int], :int
      ffi_func :zen_is_gamepad_button_push, [:int, :int], :int
      ffi_func :zen_is_gamepad_button_release, [:int, :int], :int
      ffi_func :zen_gamepad_vibrate, [:int, :float, :float, :float], :void
      ffi_func :zen_vibrate, [:float], :void
      ffi_func :zen_get_char, [], :int
      ffi_func :zen_set_ime_position, [:int, :int], :void
      ffi_func :zen_push_touch, [:int, :int, :float, :float], :void
      ffi_func :zen_get_touch_count, [], :int
      ffi_func :zen_get_touch_event_id, [:int], :int
      ffi_func :zen_get_touch_event_type, [:int], :int
      ffi_func :zen_get_touch_event_x, [:int], :float
      ffi_func :zen_get_touch_event_y, [:int], :float
      ffi_func :zen_clear_touch_events, [], :void

      # ==========================================
      # Image / Texture
      # ==========================================
      ffi_func :zen_set_default_texture_filter, [:int], :void
      ffi_func :zen_get_default_texture_filter, [], :int
      ffi_func :zen_image_set_filter, [:ptr, :int], :void
      ffi_func :zen_image_get_filter, [:ptr], :int
      ffi_func :zen_image_replace_texture, [:ptr, :ptr], :void
      ffi_func :zen_image_create, [:int, :int], :ptr
      ffi_func :zen_image_create_format, [:int, :int, :int], :ptr
      ffi_func :zen_image_create_msaa, [:int, :int, :int], :ptr
      ffi_func :zen_image_load, [:str], :ptr
      ffi_func :zen_image_sub_image, [:ptr, :int, :int, :int, :int], :ptr
      ffi_func :zen_image_clone, [:ptr], :ptr
      ffi_func :zen_set_render_target, [:ptr], :void
      ffi_func :zen_ffi_image_width, [:ptr], :int
      ffi_func :zen_ffi_image_height, [:ptr], :int
      ffi_func :zen_ffi_image_x, [:ptr], :int
      ffi_func :zen_ffi_image_y, [:ptr], :int
      ffi_func :zen_ffi_image_tex_width, [:ptr], :int
      ffi_func :zen_ffi_image_tex_height, [:ptr], :int
      ffi_func :zen_image_get_texture_id, [:ptr], :uint32
      ffi_func :zen_ffi_image_is_sub, [:ptr], :int
      ffi_func :zen_ffi_image_msaa_samples, [:ptr], :int
      ffi_func :zen_image_get_pixel, [:ptr, :int, :int], :uint32
      ffi_func :zen_image_set_pixel, [:ptr, :int, :int, :uint32], :void
      ffi_func :zen_ffi_image_set_pixel_rgba, [:ptr, :int, :int, :int, :int, :int, :int], :void
      ffi_func :zen_ffi_image_set_pixels, [:ptr, :binstr], :void
      ffi_func :zen_image_sync_to_gpu, [:ptr], :void
      ffi_func :zen_image_save, [:ptr, :str], :int

      # 画像全体のピクセル配列 (RGBA uint32_t パックバイナリ) 取得ヘルパー
      # CRuby 側では ext/zenoo/zenoo_ext.c 内の専用 C 関数で実装される。
      def self.zen_ffi_image_get_pixels(ptr, _byte_size)
        return "" unless ptr

        w = Zenoo::Native::C.zen_ffi_image_width(ptr)
        h = Zenoo::Native::C.zen_ffi_image_height(ptr)
        return "" if w <= 0 || h <= 0

        pixels = []
        y = 0
        while y < h
          x = 0
          while x < w
            pixels << Zenoo::Native::C.zen_image_get_pixel(ptr, x, y)
            x += 1
          end
          y += 1
        end
        pixels.pack("L*")
      end

      # ==========================================
      # Shader
      # ==========================================
      ffi_func :zen_ffi_shader_create, [:str, :str], :ptr
      ffi_func :zen_shader_set_int, [:ptr, :str, :int], :void
      ffi_func :zen_shader_set_float, [:ptr, :str, :float], :void
      ffi_func :zen_shader_set_vec2, [:ptr, :str, :float, :float], :void
      ffi_func :zen_shader_set_vec3, [:ptr, :str, :float, :float, :float], :void
      ffi_func :zen_shader_set_vec4, [:ptr, :str, :float, :float, :float, :float], :void
      ffi_func :zen_ffi_shader_set_vec4_array, [:ptr, :str, :int, :binstr], :void
      ffi_func :zen_ffi_shader_set_mat4, [:ptr, :str, :binstr], :void
      ffi_func :zen_shader_set_texture, [:ptr, :str, :int, :ptr], :void

      # ==========================================
      # Mesh & Renderer
      # ==========================================
      ffi_func :zen_ffi_mesh_create, [:int, :binstr, :binstr, :int, :int, :binstr, :int, :int], :ptr
      ffi_func :zen_ffi_mesh_update_vertices, [:ptr, :int, :binstr, :int, :int], :void
      ffi_func :zen_ffi_mesh_update_indices, [:ptr, :binstr, :int], :void
      ffi_func :zen_ffi_mesh_is_dynamic, [:ptr], :int
      ffi_func :zen_ffi_mesh_vertex_count, [:ptr], :int
      ffi_func :zen_ffi_mesh_index_count, [:ptr], :int
      ffi_func :zen_set_blend_mode, [:int], :void
      ffi_func :zen_set_scissor, [:int, :int, :int, :int], :void
      ffi_func :zen_reset_scissor, [], :void
      ffi_func :zen_ffi_draw_buffer, [:int, :binstr, :binstr, :int, :binstr, :int, :ptr, :ptr], :void
      ffi_func :zen_ffi_draw_mesh, [:ptr, :ptr, :binstr, :binstr, :int, :ptr, :ptr], :void

      # ==========================================
      # Font & Glyph
      # ==========================================
      ffi_func :zen_font_load, [:str, :int], :ptr
      ffi_func :zen_ffi_font_query_glyph, [:ptr, :int, :float, :int, :float], :int
      ffi_func :zen_ffi_glyph_visible, [], :int
      ffi_func :zen_ffi_glyph_u0, [], :float
      ffi_func :zen_ffi_glyph_v0, [], :float
      ffi_func :zen_ffi_glyph_u1, [], :float
      ffi_func :zen_ffi_glyph_v1, [], :float
      ffi_func :zen_ffi_glyph_x0, [], :float
      ffi_func :zen_ffi_glyph_y0, [], :float
      ffi_func :zen_ffi_glyph_x1, [], :float
      ffi_func :zen_ffi_glyph_y1, [], :float
      ffi_func :zen_ffi_glyph_advance, [], :float
      ffi_func :zen_ffi_glyph_is_bitmap, [], :int
      ffi_func :zen_ffi_font_ascent, [:ptr, :float], :float
      ffi_func :zen_ffi_font_descent, [:ptr, :float], :float
      ffi_func :zen_ffi_font_line_gap, [:ptr, :float], :float
      ffi_func :zen_font_set_atlas_image, [:ptr], :void
      ffi_func :zen_font_atlas_generation, [], :uint32

      # ==========================================
      # Audio & Sound
      # ==========================================
      ffi_func :zen_audio_init, [], :int
      ffi_func :zen_audio_shutdown, [], :void
      ffi_func :zen_audio_set_master_volume, [:float], :void
      ffi_func :zen_audio_get_master_volume, [], :float
      ffi_func :zen_sound_load_file, [:str, :int], :ptr
      ffi_func :zen_ffi_sound_load_pcm, [:binstr, :int, :int, :int], :ptr
      ffi_func :zen_sound_play, [:ptr], :void
      ffi_func :zen_sound_stop, [:ptr], :void
      ffi_func :zen_sound_pause, [:ptr], :void
      ffi_func :zen_sound_is_playing, [:ptr], :int
      ffi_func :zen_sound_set_volume, [:ptr, :float], :void
      ffi_func :zen_sound_get_volume, [:ptr], :float
      ffi_func :zen_sound_set_looping, [:ptr, :int], :void
      ffi_func :zen_sound_is_looping, [:ptr], :int
      ffi_func :zen_sound_set_pitch, [:ptr, :float], :void
      ffi_func :zen_sound_get_pitch, [:ptr], :float
      ffi_func :zen_sound_set_pan, [:ptr, :float], :void
      ffi_func :zen_sound_get_pan, [:ptr], :float
      ffi_func :zen_sound_seek, [:ptr, :float], :void
      ffi_func :zen_sound_get_cursor, [:ptr], :float
      ffi_func :zen_sound_get_length, [:ptr], :float
      ffi_func :zen_sound_get_sample_rate, [:ptr], :uint32
      ffi_func :zen_ffi_sound_get_length_pcm, [:ptr], :int64
      ffi_func :zen_ffi_sound_set_loop_points_pcm, [:ptr, :int64, :int64], :void
      ffi_func :zen_sound_set_loop_points_seconds, [:ptr, :float, :float], :void
      ffi_func :zen_ffi_sound_get_loop_start_sec, [:ptr], :float
      ffi_func :zen_ffi_sound_get_loop_end_sec, [:ptr], :float
      ffi_func :zen_ffi_sound_set_loop_start_sec, [:ptr, :float], :void
      ffi_func :zen_ffi_sound_set_loop_end_sec, [:ptr, :float], :void
      ffi_func :zen_ffi_sound_get_loop_start_pcm, [:ptr], :int64
      ffi_func :zen_ffi_sound_get_loop_end_pcm, [:ptr], :int64
      ffi_func :zen_ffi_sound_set_loop_start_pcm, [:ptr, :int64], :void
      ffi_func :zen_ffi_sound_set_loop_end_pcm, [:ptr, :int64], :void
      ffi_func :zen_sound_has_loop_points, [:ptr], :int
      ffi_func :zen_sound_clear_loop_points, [:ptr], :void

      # ==========================================
      # Browser / Safe Area Bridge
      # ==========================================
      ffi_func :zen_js_eval, [:str], :void
      ffi_func :zen_js_eval_num, [:str], :double
      ffi_func :zen_js_eval_str, [:str], :str
      ffi_func :zen_js_is_page_visible, [], :int
      ffi_func :zen_ffi_safe_area_left, [], :float
      ffi_func :zen_ffi_safe_area_top, [], :float
      ffi_func :zen_ffi_safe_area_right, [], :float
      ffi_func :zen_ffi_safe_area_bottom, [], :float

      # ==========================================
      # Batch Backend & Snapshot
      # ==========================================
      ffi_func :zen_batch_register_pipeline, [:int, :binstr, :int, :binstr, :int, :int, :ptr], :int
      ffi_func :zen_batch_set_pipeline_default_shader, [:int, :ptr], :void
      ffi_func :zen_batch_reset_frame, [], :void
      ffi_func :zen_batch_mark_screen_cleared, [], :void
      ffi_func :zen_batch_set_current_target, [:ptr], :void
      ffi_func :zen_batch_get_current_target, [], :ptr
      ffi_func :zen_batch_set_active_gl_target, [:ptr], :void
      ffi_func :zen_batch_get_active_gl_target, [], :ptr
      ffi_func :zen_batch_push_clip, [:float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_pop_clip, [], :void
      ffi_func :zen_batch_clear_clips, [], :void
      ffi_func :zen_batch_has_pending_draws, [:ptr], :int
      ffi_func :zen_batch_flush_image, [:ptr], :void
      ffi_func :zen_batch_flush_pending_images, [], :void
      ffi_func :zen_batch_set_clear, [:uint32], :void
      ffi_func :zen_batch_flush_screen, [:uint32], :void
      ffi_func :zen_batch_flush_active, [:uint32], :void
      ffi_func :zen_batch_last_draw_calls, [], :int
      ffi_func :zen_batch_active_queue_count, [], :int
      ffi_func :zen_batch_screen_queue_count, [], :int
      ffi_func :zen_batch_sort_screen_queue, [], :void

      ffi_func :zen_batch_begin_uniforms, [], :void
      ffi_func :zen_batch_uniform_int, [:str, :int], :void
      ffi_func :zen_batch_uniform_float, [:str, :float], :void
      ffi_func :zen_batch_uniform_vec2, [:str, :float, :float], :void
      ffi_func :zen_batch_uniform_vec3, [:str, :float, :float, :float], :void
      ffi_func :zen_batch_uniform_vec4, [:str, :float, :float, :float, :float], :void
      ffi_func :zen_batch_uniform_mat4, [:str, :binstr], :void
      ffi_func :zen_batch_uniform_vec4_array, [:str, :int, :binstr], :void
      ffi_func :zen_batch_uniform_texture, [:str, :ptr], :void

      ffi_func :zen_batch_enqueue_draw, [:int, :binstr, :int, :int, :ptr, :ptr, :int, :float, :ptr, :ptr], :void
      ffi_func :zen_batch_enqueue_flat_rect, [:float, :float, :float, :float, :float, :float, :float, :float, :ptr, :int, :float], :void
      ffi_func :zen_batch_stage_card_colors, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_stage_card_params, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_enqueue_sdf_card, [:float, :float, :float, :float, :ptr, :ptr, :int, :float], :void
      ffi_func :zen_batch_stage_color_uv, [:float, :float, :float, :float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_enqueue_sprite, [:float, :float, :float, :float, :float, :float, :ptr, :ptr, :int, :float, :ptr], :void
      ffi_func :zen_batch_enqueue_triangle_flat, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :ptr, :int, :float], :void
      ffi_func :zen_batch_stage_tri_colors, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_enqueue_triangle_grad, [:float, :float, :float, :float, :float, :float, :ptr, :int, :float], :void

      ffi_func :zen_batch_begin_text, [], :void
      ffi_func :zen_batch_set_text_color_outline, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_set_text_shadow_weight, [:float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_stage_text_line, [:ptr, :str, :float, :float, :float, :int, :float, :float], :void
      ffi_func :zen_batch_set_glyph_override, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :float], :void
      ffi_func :zen_batch_stage_glyph, [:float, :float, :float, :float, :float, :float, :float, :float, :float, :int], :void
      ffi_func :zen_batch_staged_glyph_count, [], :int
      ffi_func :zen_batch_commit_text, [:ptr, :ptr, :int, :float], :void

      ffi_func :zen_snapshot_create, [], :ptr
      ffi_func :zen_snapshot_count, [:ptr], :int
      ffi_func :zen_snapshot_clear, [:ptr], :void
      ffi_func :zen_snapshot_capture_active, [:ptr, :int], :void
      ffi_func :zen_snapshot_capture_screen, [:ptr], :void
      ffi_func :zen_snapshot_replay_to_active, [:ptr], :void
      ffi_func :zen_snapshot_execute_direct, [:ptr], :void
    end
  end
end

/*
 * AUTO-GENERATED FILE — DO NOT EDIT DIRECTLY.
 * Generated from ext/spinel/zenoo_ffi.rb by tools/generate_cruby_ext.rb
 */
#include <ruby.h>
#include <stdint.h>
#include "../../include/zenoo.h"

static VALUE s_frame_callback_proc = Qnil;
static int s_pending_jump_tag = 0;

static void rb_zenoo_gc_hook(void) {
    rb_gc();
}

static VALUE call_frame_callback_protected(VALUE arg) {
    return rb_funcall(arg, rb_intern("call"), 0);
}

static void rb_zenoo_frame_callback(void) {
    if (NIL_P(s_frame_callback_proc)) return;
    int state = 0;
    rb_protect(call_frame_callback_protected, s_frame_callback_proc, &state);
    if (state) {
        s_pending_jump_tag = state;
    }
}

/* ==========================================
 * Special CRuby Handlers (Callback / GC / Buffer)
 * ========================================== */
static VALUE cruby_zen_set_frame_callback(VALUE self, VALUE cb) {
    (void)self;
    s_frame_callback_proc = cb;
    if (NIL_P(cb)) {
        zen_set_frame_callback(NULL);
    } else {
        zen_set_frame_callback(rb_zenoo_frame_callback);
    }
    return Qnil;
}

static VALUE cruby_zen_ffi_clear_frame_callback(VALUE self) {
    (void)self;
    s_frame_callback_proc = Qnil;
    zen_set_frame_callback(NULL);
    return Qnil;
}

static VALUE cruby_zen_run_loop(VALUE self, VALUE cb) {
    (void)self;
    s_frame_callback_proc = cb;
    s_pending_jump_tag = 0;
    zen_run_loop(NIL_P(cb) ? NULL : rb_zenoo_frame_callback);
    if (s_pending_jump_tag) {
        int tag = s_pending_jump_tag;
        s_pending_jump_tag = 0;
        rb_jump_tag(tag);
    }
    return Qnil;
}

static VALUE cruby_zen_update(VALUE self) {
    (void)self;
    s_pending_jump_tag = 0;
    int res = zen_update();
    if (s_pending_jump_tag) {
        int tag = s_pending_jump_tag;
        s_pending_jump_tag = 0;
        rb_jump_tag(tag);
    }
    return INT2NUM(res);
}

static VALUE cruby_zen_set_gc_trigger_callback(VALUE self, VALUE cb) {
    (void)self;
    (void)cb;
    zen_set_gc_trigger_callback(rb_zenoo_gc_hook);
    return Qnil;
}

static VALUE cruby_zen_ffi_image_get_pixels(VALUE self, VALUE v_ptr, VALUE v_byte_size) {
    (void)self;
    ZenImage* img = NIL_P(v_ptr) ? NULL : (ZenImage*)(uintptr_t)NUM2ULL(v_ptr);
    int byte_size = NUM2INT(v_byte_size);
    if (!img || byte_size <= 0) {
        return rb_str_new("", 0);
    }
    int w = zen_ffi_image_width(img);
    int h = zen_ffi_image_height(img);
    if (w <= 0 || h <= 0) {
        return rb_str_new("", 0);
    }
    long required = (long)w * (long)h * 4L;
    long alloc_size = ((long)byte_size > required) ? (long)byte_size : required;
    VALUE str = rb_str_new(NULL, alloc_size);
    zen_image_get_pixels(img, (uint32_t*)RSTRING_PTR(str));
    if (alloc_size > required) {
        rb_str_set_len(str, required);
    }
    return str;
}

/* ==========================================
 * Auto-generated FFI Wrappers
 * ========================================== */

static VALUE cruby_zen_get_version(VALUE self) {
    (void)self;
    const char* ret = zen_get_version();
    return (ret) ? rb_utf8_str_new_cstr(ret) : Qnil;
}

static VALUE cruby_zen_ensure_context(VALUE self) {
    (void)self;
    int ret = zen_ensure_context();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_win_init(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    VALUE s_arg2 = arg2; const char* c_arg2 = NIL_P(s_arg2) ? NULL : StringValueCStr(s_arg2);
    int c_arg3 = NUM2INT(arg3);
    int ret = zen_ffi_win_init(c_arg0, c_arg1, c_arg2, c_arg3);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_win_init_scaled(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    VALUE s_arg2 = arg2; const char* c_arg2 = NIL_P(s_arg2) ? NULL : StringValueCStr(s_arg2);
    int c_arg3 = NUM2INT(arg3);
    int c_arg4 = NUM2INT(arg4);
    int c_arg5 = NUM2INT(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    int ret = zen_ffi_win_init_scaled(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6);
    return INT2NUM(ret);
}

static VALUE cruby_zen_shutdown(VALUE self) {
    (void)self;
    zen_shutdown();
    return Qnil;
}

static VALUE cruby_zen_toggle_fullscreen(VALUE self) {
    (void)self;
    zen_toggle_fullscreen();
    return Qnil;
}

static VALUE cruby_zen_begin_frame(VALUE self) {
    (void)self;
    int ret = zen_begin_frame();
    return INT2NUM(ret);
}

static VALUE cruby_zen_end_frame(VALUE self) {
    (void)self;
    zen_end_frame();
    return Qnil;
}

static VALUE cruby_zen_clear(VALUE self, VALUE arg0) {
    (void)self;
    uint32_t c_arg0 = (uint32_t)NUM2LL(arg0);
    zen_clear(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_is_wasm(VALUE self) {
    (void)self;
    int ret = zen_is_wasm();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_destroy_handle(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_ffi_destroy_handle(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_ffi_image_free_count(VALUE self) {
    (void)self;
    int ret = zen_ffi_image_free_count();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_screen_w(VALUE self) {
    (void)self;
    int ret = zen_ffi_screen_w();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_screen_h(VALUE self) {
    (void)self;
    int ret = zen_ffi_screen_h();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_window_w(VALUE self) {
    (void)self;
    int ret = zen_ffi_window_w();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_window_h(VALUE self) {
    (void)self;
    int ret = zen_ffi_window_h();
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_window_size(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_set_window_size(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_set_window_title(VALUE self, VALUE arg0) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    zen_set_window_title(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_window_title(VALUE self) {
    (void)self;
    const char* ret = zen_get_window_title();
    return (ret) ? rb_utf8_str_new_cstr(ret) : Qnil;
}

static VALUE cruby_zen_ffi_window_pos_x(VALUE self) {
    (void)self;
    int ret = zen_ffi_window_pos_x();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_window_pos_y(VALUE self) {
    (void)self;
    int ret = zen_ffi_window_pos_y();
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_window_pos(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_set_window_pos(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_is_window_focused(VALUE self) {
    (void)self;
    int ret = zen_is_window_focused();
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_window_minimized(VALUE self) {
    (void)self;
    int ret = zen_is_window_minimized();
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_window_maximized(VALUE self) {
    (void)self;
    int ret = zen_is_window_maximized();
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_window_hovered(VALUE self) {
    (void)self;
    int ret = zen_is_window_hovered();
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_resizing(VALUE self) {
    (void)self;
    int ret = zen_is_resizing();
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_live_resize(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_set_live_resize(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_live_resize(VALUE self) {
    (void)self;
    int ret = zen_get_live_resize();
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_scale_mode(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_set_scale_mode(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_scale_mode(VALUE self) {
    (void)self;
    int ret = zen_get_scale_mode();
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_scale(VALUE self) {
    (void)self;
    float ret = zen_get_scale();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_set_window_scale(VALUE self, VALUE arg0) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    zen_set_window_scale(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_window_scale(VALUE self) {
    (void)self;
    float ret = zen_get_window_scale();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_get_dpi_scale(VALUE self) {
    (void)self;
    float ret = zen_get_dpi_scale();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_set_target_fps(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_set_target_fps(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_target_fps(VALUE self) {
    (void)self;
    int ret = zen_get_target_fps();
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_vsync(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_set_vsync(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_window_set_msaa_samples(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_window_set_msaa_samples(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_window_get_msaa_samples(VALUE self) {
    (void)self;
    int ret = zen_window_get_msaa_samples();
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_delta_time(VALUE self) {
    (void)self;
    float ret = zen_get_delta_time();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_get_time(VALUE self) {
    (void)self;
    double ret = zen_get_time();
    return DBL2NUM(ret);
}

static VALUE cruby_zen_window_show_cursor(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_window_show_cursor(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_window_set_cursor(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_window_set_cursor(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_window_get_clipboard_string(VALUE self) {
    (void)self;
    const char* ret = zen_window_get_clipboard_string();
    return (ret) ? rb_utf8_str_new_cstr(ret) : Qnil;
}

static VALUE cruby_zen_window_set_clipboard_string(VALUE self, VALUE arg0) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    zen_window_set_clipboard_string(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_is_key_pressed(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_key_pressed(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_key_push(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_key_push(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_key_release(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_key_release(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_key_repeat(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_key_repeat(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_mouse_x(VALUE self) {
    (void)self;
    float ret = zen_ffi_mouse_x();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_mouse_y(VALUE self) {
    (void)self;
    float ret = zen_ffi_mouse_y();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_is_mouse_pressed(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_mouse_pressed(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_mouse_push(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_mouse_push(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_mouse_release(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_mouse_release(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_mouse_wheel_x(VALUE self) {
    (void)self;
    float ret = zen_get_mouse_wheel_x();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_get_mouse_wheel_y(VALUE self) {
    (void)self;
    float ret = zen_get_mouse_wheel_y();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_is_gamepad_connected(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_is_gamepad_connected(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_gamepad_axis(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    float ret = zen_get_gamepad_axis(c_arg0, c_arg1);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_is_gamepad_button_pressed(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    int ret = zen_is_gamepad_button_pressed(c_arg0, c_arg1);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_gamepad_button_push(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    int ret = zen_is_gamepad_button_push(c_arg0, c_arg1);
    return INT2NUM(ret);
}

static VALUE cruby_zen_is_gamepad_button_release(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    int ret = zen_is_gamepad_button_release(c_arg0, c_arg1);
    return INT2NUM(ret);
}

static VALUE cruby_zen_gamepad_vibrate(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    zen_gamepad_vibrate(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_vibrate(VALUE self, VALUE arg0) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    zen_vibrate(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_char(VALUE self) {
    (void)self;
    int ret = zen_get_char();
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_ime_position(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_set_ime_position(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_push_touch(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    zen_push_touch(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_get_touch_count(VALUE self) {
    (void)self;
    int ret = zen_get_touch_count();
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_touch_event_id(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_get_touch_event_id(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_touch_event_type(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int ret = zen_get_touch_event_type(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_get_touch_event_x(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    float ret = zen_get_touch_event_x(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_get_touch_event_y(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    float ret = zen_get_touch_event_y(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_clear_touch_events(VALUE self) {
    (void)self;
    zen_clear_touch_events();
    return Qnil;
}

static VALUE cruby_zen_set_default_texture_filter(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_set_default_texture_filter(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_get_default_texture_filter(VALUE self) {
    (void)self;
    int ret = zen_get_default_texture_filter();
    return INT2NUM(ret);
}

static VALUE cruby_zen_image_set_filter(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_image_set_filter(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_image_get_filter(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_image_get_filter(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_image_replace_texture(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    void* c_arg1 = NIL_P(arg1) ? NULL : (void*)(uintptr_t)NUM2ULL(arg1);
    zen_image_replace_texture(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_image_create(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    void* ret = (void*)(zen_image_create(c_arg0, c_arg1));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_image_create_format(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    void* ret = (void*)(zen_image_create_format(c_arg0, c_arg1, c_arg2));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_image_create_msaa(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    void* ret = (void*)(zen_image_create_msaa(c_arg0, c_arg1, c_arg2));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_image_load(VALUE self, VALUE arg0) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    void* ret = (void*)(zen_image_load(c_arg0));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_image_sub_image(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    int c_arg3 = NUM2INT(arg3);
    int c_arg4 = NUM2INT(arg4);
    void* ret = (void*)(zen_image_sub_image(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_image_clone(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    void* ret = (void*)(zen_image_clone(c_arg0));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_set_render_target(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_set_render_target(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_ffi_image_width(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_width(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_image_height(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_height(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_image_x(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_x(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_image_y(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_y(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_image_tex_width(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_tex_width(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_image_tex_height(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_tex_height(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_image_get_texture_id(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    uint32_t ret = zen_image_get_texture_id(c_arg0);
    return ULONG2NUM((unsigned long)(ret));
}

static VALUE cruby_zen_ffi_image_is_sub(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_is_sub(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_image_msaa_samples(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_image_msaa_samples(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_image_get_pixel(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    uint32_t ret = zen_image_get_pixel(c_arg0, c_arg1, c_arg2);
    return ULONG2NUM((unsigned long)(ret));
}

static VALUE cruby_zen_image_set_pixel(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    uint32_t c_arg3 = (uint32_t)NUM2LL(arg3);
    zen_image_set_pixel(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_ffi_image_set_pixel_rgba(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    int c_arg3 = NUM2INT(arg3);
    int c_arg4 = NUM2INT(arg4);
    int c_arg5 = NUM2INT(arg5);
    int c_arg6 = NUM2INT(arg6);
    zen_ffi_image_set_pixel_rgba(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6);
    return Qnil;
}

static VALUE cruby_zen_ffi_image_set_pixels(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    zen_ffi_image_set_pixels(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_image_sync_to_gpu(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_image_sync_to_gpu(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_image_save(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    int ret = zen_image_save(c_arg0, c_arg1);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_shader_create(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    void* ret = (void*)(zen_ffi_shader_create(c_arg0, c_arg1));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_shader_set_int(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    int c_arg2 = NUM2INT(arg2);
    zen_shader_set_int(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_shader_set_float(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    zen_shader_set_float(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_shader_set_vec2(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    zen_shader_set_vec2(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_shader_set_vec3(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    zen_shader_set_vec3(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4);
    return Qnil;
}

static VALUE cruby_zen_shader_set_vec4(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    zen_shader_set_vec4(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5);
    return Qnil;
}

static VALUE cruby_zen_ffi_shader_set_vec4_array(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    int c_arg2 = NUM2INT(arg2);
    VALUE s_arg3 = arg3; const void* c_arg3 = NULL;
    if (!NIL_P(s_arg3)) { StringValue(s_arg3); c_arg3 = (const void*)RSTRING_PTR(s_arg3); }
    zen_ffi_shader_set_vec4_array(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_ffi_shader_set_mat4(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    VALUE s_arg2 = arg2; const void* c_arg2 = NULL;
    if (!NIL_P(s_arg2)) { StringValue(s_arg2); c_arg2 = (const void*)RSTRING_PTR(s_arg2); }
    zen_ffi_shader_set_mat4(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_shader_set_texture(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    int c_arg2 = NUM2INT(arg2);
    void* c_arg3 = NIL_P(arg3) ? NULL : (void*)(uintptr_t)NUM2ULL(arg3);
    zen_shader_set_texture(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_ffi_mesh_create(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    VALUE s_arg2 = arg2; const void* c_arg2 = NULL;
    if (!NIL_P(s_arg2)) { StringValue(s_arg2); c_arg2 = (const void*)RSTRING_PTR(s_arg2); }
    int c_arg3 = NUM2INT(arg3);
    int c_arg4 = NUM2INT(arg4);
    VALUE s_arg5 = arg5; const void* c_arg5 = NULL;
    if (!NIL_P(s_arg5)) { StringValue(s_arg5); c_arg5 = (const void*)RSTRING_PTR(s_arg5); }
    int c_arg6 = NUM2INT(arg6);
    int c_arg7 = NUM2INT(arg7);
    void* ret = (void*)(zen_ffi_mesh_create(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_ffi_mesh_update_vertices(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    VALUE s_arg2 = arg2; const void* c_arg2 = NULL;
    if (!NIL_P(s_arg2)) { StringValue(s_arg2); c_arg2 = (const void*)RSTRING_PTR(s_arg2); }
    int c_arg3 = NUM2INT(arg3);
    int c_arg4 = NUM2INT(arg4);
    zen_ffi_mesh_update_vertices(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4);
    return Qnil;
}

static VALUE cruby_zen_ffi_mesh_update_indices(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    int c_arg2 = NUM2INT(arg2);
    zen_ffi_mesh_update_indices(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_ffi_mesh_is_dynamic(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_mesh_is_dynamic(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_mesh_vertex_count(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_mesh_vertex_count(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_mesh_index_count(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_ffi_mesh_index_count(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_set_blend_mode(VALUE self, VALUE arg0) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    zen_set_blend_mode(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_set_scissor(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    int c_arg3 = NUM2INT(arg3);
    zen_set_scissor(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_reset_scissor(VALUE self) {
    (void)self;
    zen_reset_scissor();
    return Qnil;
}

static VALUE cruby_zen_ffi_draw_buffer(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    VALUE s_arg2 = arg2; const void* c_arg2 = NULL;
    if (!NIL_P(s_arg2)) { StringValue(s_arg2); c_arg2 = (const void*)RSTRING_PTR(s_arg2); }
    int c_arg3 = NUM2INT(arg3);
    VALUE s_arg4 = arg4; const void* c_arg4 = NULL;
    if (!NIL_P(s_arg4)) { StringValue(s_arg4); c_arg4 = (const void*)RSTRING_PTR(s_arg4); }
    int c_arg5 = NUM2INT(arg5);
    void* c_arg6 = NIL_P(arg6) ? NULL : (void*)(uintptr_t)NUM2ULL(arg6);
    void* c_arg7 = NIL_P(arg7) ? NULL : (void*)(uintptr_t)NUM2ULL(arg7);
    zen_ffi_draw_buffer(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7);
    return Qnil;
}

static VALUE cruby_zen_ffi_draw_mesh(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    void* c_arg1 = NIL_P(arg1) ? NULL : (void*)(uintptr_t)NUM2ULL(arg1);
    VALUE s_arg2 = arg2; const void* c_arg2 = NULL;
    if (!NIL_P(s_arg2)) { StringValue(s_arg2); c_arg2 = (const void*)RSTRING_PTR(s_arg2); }
    VALUE s_arg3 = arg3; const void* c_arg3 = NULL;
    if (!NIL_P(s_arg3)) { StringValue(s_arg3); c_arg3 = (const void*)RSTRING_PTR(s_arg3); }
    int c_arg4 = NUM2INT(arg4);
    void* c_arg5 = NIL_P(arg5) ? NULL : (void*)(uintptr_t)NUM2ULL(arg5);
    void* c_arg6 = NIL_P(arg6) ? NULL : (void*)(uintptr_t)NUM2ULL(arg6);
    zen_ffi_draw_mesh(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6);
    return Qnil;
}

static VALUE cruby_zen_font_load(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    int c_arg1 = NUM2INT(arg1);
    void* ret = (void*)(zen_font_load(c_arg0, c_arg1));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_ffi_font_query_glyph(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    int c_arg3 = NUM2INT(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    int ret = zen_ffi_font_query_glyph(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4);
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_glyph_visible(VALUE self) {
    (void)self;
    int ret = zen_ffi_glyph_visible();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_glyph_u0(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_u0();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_v0(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_v0();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_u1(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_u1();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_v1(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_v1();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_x0(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_x0();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_y0(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_y0();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_x1(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_x1();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_y1(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_y1();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_advance(VALUE self) {
    (void)self;
    float ret = zen_ffi_glyph_advance();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_glyph_is_bitmap(VALUE self) {
    (void)self;
    int ret = zen_ffi_glyph_is_bitmap();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_font_ascent(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float ret = zen_ffi_font_ascent(c_arg0, c_arg1);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_font_descent(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float ret = zen_ffi_font_descent(c_arg0, c_arg1);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_font_line_gap(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float ret = zen_ffi_font_line_gap(c_arg0, c_arg1);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_font_set_atlas_image(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_font_set_atlas_image(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_font_atlas_generation(VALUE self) {
    (void)self;
    uint32_t ret = zen_font_atlas_generation();
    return ULONG2NUM((unsigned long)(ret));
}

static VALUE cruby_zen_audio_init(VALUE self) {
    (void)self;
    int ret = zen_audio_init();
    return INT2NUM(ret);
}

static VALUE cruby_zen_audio_shutdown(VALUE self) {
    (void)self;
    zen_audio_shutdown();
    return Qnil;
}

static VALUE cruby_zen_audio_set_master_volume(VALUE self, VALUE arg0) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    zen_audio_set_master_volume(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_audio_get_master_volume(VALUE self) {
    (void)self;
    float ret = zen_audio_get_master_volume();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_sound_load_file(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    int c_arg1 = NUM2INT(arg1);
    void* ret = (void*)(zen_sound_load_file(c_arg0, c_arg1));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_ffi_sound_load_pcm(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    VALUE s_arg0 = arg0; const void* c_arg0 = NULL;
    if (!NIL_P(s_arg0)) { StringValue(s_arg0); c_arg0 = (const void*)RSTRING_PTR(s_arg0); }
    int c_arg1 = NUM2INT(arg1);
    int c_arg2 = NUM2INT(arg2);
    int c_arg3 = NUM2INT(arg3);
    void* ret = (void*)(zen_ffi_sound_load_pcm(c_arg0, c_arg1, c_arg2, c_arg3));
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_sound_play(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_sound_play(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_sound_stop(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_sound_stop(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_sound_pause(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_sound_pause(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_sound_is_playing(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_sound_is_playing(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_sound_set_volume(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_sound_set_volume(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_sound_get_volume(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_sound_get_volume(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_sound_set_looping(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_sound_set_looping(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_sound_is_looping(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_sound_is_looping(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_sound_set_pitch(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_sound_set_pitch(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_sound_get_pitch(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_sound_get_pitch(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_sound_set_pan(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_sound_set_pan(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_sound_get_pan(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_sound_get_pan(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_sound_seek(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_sound_seek(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_sound_get_cursor(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_sound_get_cursor(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_sound_get_length(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_sound_get_length(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_sound_get_sample_rate(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    uint32_t ret = zen_sound_get_sample_rate(c_arg0);
    return ULONG2NUM((unsigned long)(ret));
}

static VALUE cruby_zen_ffi_sound_get_length_pcm(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int64_t ret = zen_ffi_sound_get_length_pcm(c_arg0);
    return LL2NUM(ret);
}

static VALUE cruby_zen_ffi_sound_set_loop_points_pcm(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int64_t c_arg1 = (int64_t)NUM2LL(arg1);
    int64_t c_arg2 = (int64_t)NUM2LL(arg2);
    zen_ffi_sound_set_loop_points_pcm(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_sound_set_loop_points_seconds(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    zen_sound_set_loop_points_seconds(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_ffi_sound_get_loop_start_sec(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_ffi_sound_get_loop_start_sec(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_sound_get_loop_end_sec(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float ret = zen_ffi_sound_get_loop_end_sec(c_arg0);
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_sound_set_loop_start_sec(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_ffi_sound_set_loop_start_sec(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_ffi_sound_set_loop_end_sec(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_ffi_sound_set_loop_end_sec(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_ffi_sound_get_loop_start_pcm(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int64_t ret = zen_ffi_sound_get_loop_start_pcm(c_arg0);
    return LL2NUM(ret);
}

static VALUE cruby_zen_ffi_sound_get_loop_end_pcm(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int64_t ret = zen_ffi_sound_get_loop_end_pcm(c_arg0);
    return LL2NUM(ret);
}

static VALUE cruby_zen_ffi_sound_set_loop_start_pcm(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int64_t c_arg1 = (int64_t)NUM2LL(arg1);
    zen_ffi_sound_set_loop_start_pcm(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_ffi_sound_set_loop_end_pcm(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int64_t c_arg1 = (int64_t)NUM2LL(arg1);
    zen_ffi_sound_set_loop_end_pcm(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_sound_has_loop_points(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_sound_has_loop_points(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_sound_clear_loop_points(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_sound_clear_loop_points(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_js_eval(VALUE self, VALUE arg0) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    zen_js_eval(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_js_eval_num(VALUE self, VALUE arg0) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    double ret = zen_js_eval_num(c_arg0);
    return DBL2NUM(ret);
}

static VALUE cruby_zen_js_eval_str(VALUE self, VALUE arg0) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    const char* ret = zen_js_eval_str(c_arg0);
    return (ret) ? rb_utf8_str_new_cstr(ret) : Qnil;
}

static VALUE cruby_zen_js_is_page_visible(VALUE self) {
    (void)self;
    int ret = zen_js_is_page_visible();
    return INT2NUM(ret);
}

static VALUE cruby_zen_ffi_safe_area_left(VALUE self) {
    (void)self;
    float ret = zen_ffi_safe_area_left();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_safe_area_top(VALUE self) {
    (void)self;
    float ret = zen_ffi_safe_area_top();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_safe_area_right(VALUE self) {
    (void)self;
    float ret = zen_ffi_safe_area_right();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_ffi_safe_area_bottom(VALUE self) {
    (void)self;
    float ret = zen_ffi_safe_area_bottom();
    return DBL2NUM((double)(ret));
}

static VALUE cruby_zen_batch_register_pipeline(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    int c_arg2 = NUM2INT(arg2);
    VALUE s_arg3 = arg3; const void* c_arg3 = NULL;
    if (!NIL_P(s_arg3)) { StringValue(s_arg3); c_arg3 = (const void*)RSTRING_PTR(s_arg3); }
    int c_arg4 = NUM2INT(arg4);
    int c_arg5 = NUM2INT(arg5);
    void* c_arg6 = NIL_P(arg6) ? NULL : (void*)(uintptr_t)NUM2ULL(arg6);
    int ret = zen_batch_register_pipeline(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6);
    return INT2NUM(ret);
}

static VALUE cruby_zen_batch_set_pipeline_default_shader(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    void* c_arg1 = NIL_P(arg1) ? NULL : (void*)(uintptr_t)NUM2ULL(arg1);
    zen_batch_set_pipeline_default_shader(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_batch_reset_frame(VALUE self) {
    (void)self;
    zen_batch_reset_frame();
    return Qnil;
}

static VALUE cruby_zen_batch_mark_screen_cleared(VALUE self) {
    (void)self;
    zen_batch_mark_screen_cleared();
    return Qnil;
}

static VALUE cruby_zen_batch_set_current_target(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_batch_set_current_target(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_batch_get_current_target(VALUE self) {
    (void)self;
    void* ret = (void*)(zen_batch_get_current_target());
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_batch_set_active_gl_target(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_batch_set_active_gl_target(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_batch_get_active_gl_target(VALUE self) {
    (void)self;
    void* ret = (void*)(zen_batch_get_active_gl_target());
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_batch_push_clip(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    zen_batch_push_clip(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4);
    return Qnil;
}

static VALUE cruby_zen_batch_pop_clip(VALUE self) {
    (void)self;
    zen_batch_pop_clip();
    return Qnil;
}

static VALUE cruby_zen_batch_clear_clips(VALUE self) {
    (void)self;
    zen_batch_clear_clips();
    return Qnil;
}

static VALUE cruby_zen_batch_has_pending_draws(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_batch_has_pending_draws(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_batch_flush_image(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_batch_flush_image(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_batch_flush_pending_images(VALUE self) {
    (void)self;
    zen_batch_flush_pending_images();
    return Qnil;
}

static VALUE cruby_zen_batch_set_clear(VALUE self, VALUE arg0) {
    (void)self;
    uint32_t c_arg0 = (uint32_t)NUM2LL(arg0);
    zen_batch_set_clear(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_batch_flush_screen(VALUE self, VALUE arg0) {
    (void)self;
    uint32_t c_arg0 = (uint32_t)NUM2LL(arg0);
    zen_batch_flush_screen(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_batch_flush_active(VALUE self, VALUE arg0) {
    (void)self;
    uint32_t c_arg0 = (uint32_t)NUM2LL(arg0);
    zen_batch_flush_active(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_batch_last_draw_calls(VALUE self) {
    (void)self;
    int ret = zen_batch_last_draw_calls();
    return INT2NUM(ret);
}

static VALUE cruby_zen_batch_active_queue_count(VALUE self) {
    (void)self;
    int ret = zen_batch_active_queue_count();
    return INT2NUM(ret);
}

static VALUE cruby_zen_batch_screen_queue_count(VALUE self) {
    (void)self;
    int ret = zen_batch_screen_queue_count();
    return INT2NUM(ret);
}

static VALUE cruby_zen_batch_sort_screen_queue(VALUE self) {
    (void)self;
    zen_batch_sort_screen_queue();
    return Qnil;
}

static VALUE cruby_zen_batch_begin_uniforms(VALUE self) {
    (void)self;
    zen_batch_begin_uniforms();
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_int(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_batch_uniform_int(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_float(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    zen_batch_uniform_float(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_vec2(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    zen_batch_uniform_vec2(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_vec3(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    zen_batch_uniform_vec3(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_vec4(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    zen_batch_uniform_vec4(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_mat4(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    zen_batch_uniform_mat4(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_vec4_array(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    int c_arg1 = NUM2INT(arg1);
    VALUE s_arg2 = arg2; const void* c_arg2 = NULL;
    if (!NIL_P(s_arg2)) { StringValue(s_arg2); c_arg2 = (const void*)RSTRING_PTR(s_arg2); }
    zen_batch_uniform_vec4_array(c_arg0, c_arg1, c_arg2);
    return Qnil;
}

static VALUE cruby_zen_batch_uniform_texture(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    VALUE s_arg0 = arg0; const char* c_arg0 = NIL_P(s_arg0) ? NULL : StringValueCStr(s_arg0);
    void* c_arg1 = NIL_P(arg1) ? NULL : (void*)(uintptr_t)NUM2ULL(arg1);
    zen_batch_uniform_texture(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_batch_enqueue_draw(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9) {
    (void)self;
    int c_arg0 = NUM2INT(arg0);
    VALUE s_arg1 = arg1; const void* c_arg1 = NULL;
    if (!NIL_P(s_arg1)) { StringValue(s_arg1); c_arg1 = (const void*)RSTRING_PTR(s_arg1); }
    int c_arg2 = NUM2INT(arg2);
    int c_arg3 = NUM2INT(arg3);
    void* c_arg4 = NIL_P(arg4) ? NULL : (void*)(uintptr_t)NUM2ULL(arg4);
    void* c_arg5 = NIL_P(arg5) ? NULL : (void*)(uintptr_t)NUM2ULL(arg5);
    int c_arg6 = NUM2INT(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    void* c_arg8 = NIL_P(arg8) ? NULL : (void*)(uintptr_t)NUM2ULL(arg8);
    void* c_arg9 = NIL_P(arg9) ? NULL : (void*)(uintptr_t)NUM2ULL(arg9);
    zen_batch_enqueue_draw(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9);
    return Qnil;
}

static VALUE cruby_zen_batch_enqueue_flat_rect(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    void* c_arg8 = NIL_P(arg8) ? NULL : (void*)(uintptr_t)NUM2ULL(arg8);
    int c_arg9 = NUM2INT(arg9);
    float c_arg10 = (float)NUM2DBL(arg10);
    zen_batch_enqueue_flat_rect(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10);
    return Qnil;
}

static VALUE cruby_zen_batch_stage_card_colors(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10, VALUE arg11) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    float c_arg10 = (float)NUM2DBL(arg10);
    float c_arg11 = (float)NUM2DBL(arg11);
    zen_batch_stage_card_colors(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10, c_arg11);
    return Qnil;
}

static VALUE cruby_zen_batch_stage_card_params(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    float c_arg10 = (float)NUM2DBL(arg10);
    zen_batch_stage_card_params(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10);
    return Qnil;
}

static VALUE cruby_zen_batch_enqueue_sdf_card(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    void* c_arg4 = NIL_P(arg4) ? NULL : (void*)(uintptr_t)NUM2ULL(arg4);
    void* c_arg5 = NIL_P(arg5) ? NULL : (void*)(uintptr_t)NUM2ULL(arg5);
    int c_arg6 = NUM2INT(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    zen_batch_enqueue_sdf_card(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7);
    return Qnil;
}

static VALUE cruby_zen_batch_stage_color(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    zen_batch_stage_color(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_batch_enqueue_sprite(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    void* c_arg6 = NIL_P(arg6) ? NULL : (void*)(uintptr_t)NUM2ULL(arg6);
    void* c_arg7 = NIL_P(arg7) ? NULL : (void*)(uintptr_t)NUM2ULL(arg7);
    int c_arg8 = NUM2INT(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    void* c_arg10 = NIL_P(arg10) ? NULL : (void*)(uintptr_t)NUM2ULL(arg10);
    zen_batch_enqueue_sprite(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10);
    return Qnil;
}

static VALUE cruby_zen_batch_enqueue_triangle_flat(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10, VALUE arg11, VALUE arg12) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    void* c_arg10 = NIL_P(arg10) ? NULL : (void*)(uintptr_t)NUM2ULL(arg10);
    int c_arg11 = NUM2INT(arg11);
    float c_arg12 = (float)NUM2DBL(arg12);
    zen_batch_enqueue_triangle_flat(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10, c_arg11, c_arg12);
    return Qnil;
}

static VALUE cruby_zen_batch_stage_tri_colors(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10, VALUE arg11) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    float c_arg10 = (float)NUM2DBL(arg10);
    float c_arg11 = (float)NUM2DBL(arg11);
    zen_batch_stage_tri_colors(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10, c_arg11);
    return Qnil;
}

static VALUE cruby_zen_batch_enqueue_triangle_grad(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    void* c_arg6 = NIL_P(arg6) ? NULL : (void*)(uintptr_t)NUM2ULL(arg6);
    int c_arg7 = NUM2INT(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    zen_batch_enqueue_triangle_grad(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8);
    return Qnil;
}

static VALUE cruby_zen_batch_begin_text(VALUE self) {
    (void)self;
    zen_batch_begin_text();
    return Qnil;
}

static VALUE cruby_zen_batch_set_text_color_outline(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9, VALUE arg10, VALUE arg11) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    float c_arg10 = (float)NUM2DBL(arg10);
    float c_arg11 = (float)NUM2DBL(arg11);
    zen_batch_set_text_color_outline(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9, c_arg10, c_arg11);
    return Qnil;
}

static VALUE cruby_zen_batch_set_text_shadow_weight(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    zen_batch_set_text_shadow_weight(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4);
    return Qnil;
}

static VALUE cruby_zen_batch_stage_text_line(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    VALUE s_arg1 = arg1; const char* c_arg1 = NIL_P(s_arg1) ? NULL : StringValueCStr(s_arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    int c_arg5 = NUM2INT(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    zen_batch_stage_text_line(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7);
    return Qnil;
}

static VALUE cruby_zen_batch_set_glyph_override(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    float c_arg9 = (float)NUM2DBL(arg9);
    zen_batch_set_glyph_override(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9);
    return Qnil;
}

static VALUE cruby_zen_batch_stage_glyph(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3, VALUE arg4, VALUE arg5, VALUE arg6, VALUE arg7, VALUE arg8, VALUE arg9) {
    (void)self;
    float c_arg0 = (float)NUM2DBL(arg0);
    float c_arg1 = (float)NUM2DBL(arg1);
    float c_arg2 = (float)NUM2DBL(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    float c_arg4 = (float)NUM2DBL(arg4);
    float c_arg5 = (float)NUM2DBL(arg5);
    float c_arg6 = (float)NUM2DBL(arg6);
    float c_arg7 = (float)NUM2DBL(arg7);
    float c_arg8 = (float)NUM2DBL(arg8);
    int c_arg9 = NUM2INT(arg9);
    zen_batch_stage_glyph(c_arg0, c_arg1, c_arg2, c_arg3, c_arg4, c_arg5, c_arg6, c_arg7, c_arg8, c_arg9);
    return Qnil;
}

static VALUE cruby_zen_batch_staged_glyph_count(VALUE self) {
    (void)self;
    int ret = zen_batch_staged_glyph_count();
    return INT2NUM(ret);
}

static VALUE cruby_zen_batch_commit_text(VALUE self, VALUE arg0, VALUE arg1, VALUE arg2, VALUE arg3) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    void* c_arg1 = NIL_P(arg1) ? NULL : (void*)(uintptr_t)NUM2ULL(arg1);
    int c_arg2 = NUM2INT(arg2);
    float c_arg3 = (float)NUM2DBL(arg3);
    zen_batch_commit_text(c_arg0, c_arg1, c_arg2, c_arg3);
    return Qnil;
}

static VALUE cruby_zen_snapshot_create(VALUE self) {
    (void)self;
    void* ret = (void*)(zen_snapshot_create());
    return (ret) ? ULL2NUM((unsigned long long)(uintptr_t)(ret)) : Qnil;
}

static VALUE cruby_zen_snapshot_count(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int ret = zen_snapshot_count(c_arg0);
    return INT2NUM(ret);
}

static VALUE cruby_zen_snapshot_clear(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_snapshot_clear(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_snapshot_capture_active(VALUE self, VALUE arg0, VALUE arg1) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    int c_arg1 = NUM2INT(arg1);
    zen_snapshot_capture_active(c_arg0, c_arg1);
    return Qnil;
}

static VALUE cruby_zen_snapshot_capture_screen(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_snapshot_capture_screen(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_snapshot_replay_to_active(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_snapshot_replay_to_active(c_arg0);
    return Qnil;
}

static VALUE cruby_zen_snapshot_execute_direct(VALUE self, VALUE arg0) {
    (void)self;
    void* c_arg0 = NIL_P(arg0) ? NULL : (void*)(uintptr_t)NUM2ULL(arg0);
    zen_snapshot_execute_direct(c_arg0);
    return Qnil;
}

void Init_zenoo(void) {
    rb_gc_register_address(&s_frame_callback_proc);
    zen_set_gc_trigger_callback(rb_zenoo_gc_hook);

    VALUE rb_mZenoo = rb_define_module("Zenoo");
    VALUE rb_mNative = rb_define_module_under(rb_mZenoo, "Native");
    VALUE rb_mC = rb_define_module_under(rb_mNative, "C");


    rb_define_singleton_method(rb_mC, "zen_get_version", cruby_zen_get_version, 0);
    rb_define_singleton_method(rb_mC, "zen_ensure_context", cruby_zen_ensure_context, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_win_init", cruby_zen_ffi_win_init, 4);
    rb_define_singleton_method(rb_mC, "zen_ffi_win_init_scaled", cruby_zen_ffi_win_init_scaled, 7);
    rb_define_singleton_method(rb_mC, "zen_shutdown", cruby_zen_shutdown, 0);
    rb_define_singleton_method(rb_mC, "zen_toggle_fullscreen", cruby_zen_toggle_fullscreen, 0);
    rb_define_singleton_method(rb_mC, "zen_update", cruby_zen_update, 0);
    rb_define_singleton_method(rb_mC, "zen_begin_frame", cruby_zen_begin_frame, 0);
    rb_define_singleton_method(rb_mC, "zen_end_frame", cruby_zen_end_frame, 0);
    rb_define_singleton_method(rb_mC, "zen_clear", cruby_zen_clear, 1);
    rb_define_singleton_method(rb_mC, "zen_run_loop", cruby_zen_run_loop, 1);
    rb_define_singleton_method(rb_mC, "zen_set_frame_callback", cruby_zen_set_frame_callback, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_clear_frame_callback", cruby_zen_ffi_clear_frame_callback, 0);
    rb_define_singleton_method(rb_mC, "zen_is_wasm", cruby_zen_is_wasm, 0);
    rb_define_singleton_method(rb_mC, "zen_set_gc_trigger_callback", cruby_zen_set_gc_trigger_callback, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_destroy_handle", cruby_zen_ffi_destroy_handle, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_free_count", cruby_zen_ffi_image_free_count, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_screen_w", cruby_zen_ffi_screen_w, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_screen_h", cruby_zen_ffi_screen_h, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_window_w", cruby_zen_ffi_window_w, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_window_h", cruby_zen_ffi_window_h, 0);
    rb_define_singleton_method(rb_mC, "zen_set_window_size", cruby_zen_set_window_size, 2);
    rb_define_singleton_method(rb_mC, "zen_set_window_title", cruby_zen_set_window_title, 1);
    rb_define_singleton_method(rb_mC, "zen_get_window_title", cruby_zen_get_window_title, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_window_pos_x", cruby_zen_ffi_window_pos_x, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_window_pos_y", cruby_zen_ffi_window_pos_y, 0);
    rb_define_singleton_method(rb_mC, "zen_set_window_pos", cruby_zen_set_window_pos, 2);
    rb_define_singleton_method(rb_mC, "zen_is_window_focused", cruby_zen_is_window_focused, 0);
    rb_define_singleton_method(rb_mC, "zen_is_window_minimized", cruby_zen_is_window_minimized, 0);
    rb_define_singleton_method(rb_mC, "zen_is_window_maximized", cruby_zen_is_window_maximized, 0);
    rb_define_singleton_method(rb_mC, "zen_is_window_hovered", cruby_zen_is_window_hovered, 0);
    rb_define_singleton_method(rb_mC, "zen_is_resizing", cruby_zen_is_resizing, 0);
    rb_define_singleton_method(rb_mC, "zen_set_live_resize", cruby_zen_set_live_resize, 1);
    rb_define_singleton_method(rb_mC, "zen_get_live_resize", cruby_zen_get_live_resize, 0);
    rb_define_singleton_method(rb_mC, "zen_set_scale_mode", cruby_zen_set_scale_mode, 1);
    rb_define_singleton_method(rb_mC, "zen_get_scale_mode", cruby_zen_get_scale_mode, 0);
    rb_define_singleton_method(rb_mC, "zen_get_scale", cruby_zen_get_scale, 0);
    rb_define_singleton_method(rb_mC, "zen_set_window_scale", cruby_zen_set_window_scale, 1);
    rb_define_singleton_method(rb_mC, "zen_get_window_scale", cruby_zen_get_window_scale, 0);
    rb_define_singleton_method(rb_mC, "zen_get_dpi_scale", cruby_zen_get_dpi_scale, 0);
    rb_define_singleton_method(rb_mC, "zen_set_target_fps", cruby_zen_set_target_fps, 1);
    rb_define_singleton_method(rb_mC, "zen_get_target_fps", cruby_zen_get_target_fps, 0);
    rb_define_singleton_method(rb_mC, "zen_set_vsync", cruby_zen_set_vsync, 1);
    rb_define_singleton_method(rb_mC, "zen_window_set_msaa_samples", cruby_zen_window_set_msaa_samples, 1);
    rb_define_singleton_method(rb_mC, "zen_window_get_msaa_samples", cruby_zen_window_get_msaa_samples, 0);
    rb_define_singleton_method(rb_mC, "zen_get_delta_time", cruby_zen_get_delta_time, 0);
    rb_define_singleton_method(rb_mC, "zen_get_time", cruby_zen_get_time, 0);
    rb_define_singleton_method(rb_mC, "zen_window_show_cursor", cruby_zen_window_show_cursor, 1);
    rb_define_singleton_method(rb_mC, "zen_window_set_cursor", cruby_zen_window_set_cursor, 1);
    rb_define_singleton_method(rb_mC, "zen_window_get_clipboard_string", cruby_zen_window_get_clipboard_string, 0);
    rb_define_singleton_method(rb_mC, "zen_window_set_clipboard_string", cruby_zen_window_set_clipboard_string, 1);
    rb_define_singleton_method(rb_mC, "zen_is_key_pressed", cruby_zen_is_key_pressed, 1);
    rb_define_singleton_method(rb_mC, "zen_is_key_push", cruby_zen_is_key_push, 1);
    rb_define_singleton_method(rb_mC, "zen_is_key_release", cruby_zen_is_key_release, 1);
    rb_define_singleton_method(rb_mC, "zen_is_key_repeat", cruby_zen_is_key_repeat, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_mouse_x", cruby_zen_ffi_mouse_x, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_mouse_y", cruby_zen_ffi_mouse_y, 0);
    rb_define_singleton_method(rb_mC, "zen_is_mouse_pressed", cruby_zen_is_mouse_pressed, 1);
    rb_define_singleton_method(rb_mC, "zen_is_mouse_push", cruby_zen_is_mouse_push, 1);
    rb_define_singleton_method(rb_mC, "zen_is_mouse_release", cruby_zen_is_mouse_release, 1);
    rb_define_singleton_method(rb_mC, "zen_get_mouse_wheel_x", cruby_zen_get_mouse_wheel_x, 0);
    rb_define_singleton_method(rb_mC, "zen_get_mouse_wheel_y", cruby_zen_get_mouse_wheel_y, 0);
    rb_define_singleton_method(rb_mC, "zen_is_gamepad_connected", cruby_zen_is_gamepad_connected, 1);
    rb_define_singleton_method(rb_mC, "zen_get_gamepad_axis", cruby_zen_get_gamepad_axis, 2);
    rb_define_singleton_method(rb_mC, "zen_is_gamepad_button_pressed", cruby_zen_is_gamepad_button_pressed, 2);
    rb_define_singleton_method(rb_mC, "zen_is_gamepad_button_push", cruby_zen_is_gamepad_button_push, 2);
    rb_define_singleton_method(rb_mC, "zen_is_gamepad_button_release", cruby_zen_is_gamepad_button_release, 2);
    rb_define_singleton_method(rb_mC, "zen_gamepad_vibrate", cruby_zen_gamepad_vibrate, 4);
    rb_define_singleton_method(rb_mC, "zen_vibrate", cruby_zen_vibrate, 1);
    rb_define_singleton_method(rb_mC, "zen_get_char", cruby_zen_get_char, 0);
    rb_define_singleton_method(rb_mC, "zen_set_ime_position", cruby_zen_set_ime_position, 2);
    rb_define_singleton_method(rb_mC, "zen_push_touch", cruby_zen_push_touch, 4);
    rb_define_singleton_method(rb_mC, "zen_get_touch_count", cruby_zen_get_touch_count, 0);
    rb_define_singleton_method(rb_mC, "zen_get_touch_event_id", cruby_zen_get_touch_event_id, 1);
    rb_define_singleton_method(rb_mC, "zen_get_touch_event_type", cruby_zen_get_touch_event_type, 1);
    rb_define_singleton_method(rb_mC, "zen_get_touch_event_x", cruby_zen_get_touch_event_x, 1);
    rb_define_singleton_method(rb_mC, "zen_get_touch_event_y", cruby_zen_get_touch_event_y, 1);
    rb_define_singleton_method(rb_mC, "zen_clear_touch_events", cruby_zen_clear_touch_events, 0);
    rb_define_singleton_method(rb_mC, "zen_set_default_texture_filter", cruby_zen_set_default_texture_filter, 1);
    rb_define_singleton_method(rb_mC, "zen_get_default_texture_filter", cruby_zen_get_default_texture_filter, 0);
    rb_define_singleton_method(rb_mC, "zen_image_set_filter", cruby_zen_image_set_filter, 2);
    rb_define_singleton_method(rb_mC, "zen_image_get_filter", cruby_zen_image_get_filter, 1);
    rb_define_singleton_method(rb_mC, "zen_image_replace_texture", cruby_zen_image_replace_texture, 2);
    rb_define_singleton_method(rb_mC, "zen_image_create", cruby_zen_image_create, 2);
    rb_define_singleton_method(rb_mC, "zen_image_create_format", cruby_zen_image_create_format, 3);
    rb_define_singleton_method(rb_mC, "zen_image_create_msaa", cruby_zen_image_create_msaa, 3);
    rb_define_singleton_method(rb_mC, "zen_image_load", cruby_zen_image_load, 1);
    rb_define_singleton_method(rb_mC, "zen_image_sub_image", cruby_zen_image_sub_image, 5);
    rb_define_singleton_method(rb_mC, "zen_image_clone", cruby_zen_image_clone, 1);
    rb_define_singleton_method(rb_mC, "zen_set_render_target", cruby_zen_set_render_target, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_width", cruby_zen_ffi_image_width, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_height", cruby_zen_ffi_image_height, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_x", cruby_zen_ffi_image_x, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_y", cruby_zen_ffi_image_y, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_tex_width", cruby_zen_ffi_image_tex_width, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_tex_height", cruby_zen_ffi_image_tex_height, 1);
    rb_define_singleton_method(rb_mC, "zen_image_get_texture_id", cruby_zen_image_get_texture_id, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_is_sub", cruby_zen_ffi_image_is_sub, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_msaa_samples", cruby_zen_ffi_image_msaa_samples, 1);
    rb_define_singleton_method(rb_mC, "zen_image_get_pixel", cruby_zen_image_get_pixel, 3);
    rb_define_singleton_method(rb_mC, "zen_image_set_pixel", cruby_zen_image_set_pixel, 4);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_set_pixel_rgba", cruby_zen_ffi_image_set_pixel_rgba, 7);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_set_pixels", cruby_zen_ffi_image_set_pixels, 2);
    rb_define_singleton_method(rb_mC, "zen_image_sync_to_gpu", cruby_zen_image_sync_to_gpu, 1);
    rb_define_singleton_method(rb_mC, "zen_image_save", cruby_zen_image_save, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_shader_create", cruby_zen_ffi_shader_create, 2);
    rb_define_singleton_method(rb_mC, "zen_shader_set_int", cruby_zen_shader_set_int, 3);
    rb_define_singleton_method(rb_mC, "zen_shader_set_float", cruby_zen_shader_set_float, 3);
    rb_define_singleton_method(rb_mC, "zen_shader_set_vec2", cruby_zen_shader_set_vec2, 4);
    rb_define_singleton_method(rb_mC, "zen_shader_set_vec3", cruby_zen_shader_set_vec3, 5);
    rb_define_singleton_method(rb_mC, "zen_shader_set_vec4", cruby_zen_shader_set_vec4, 6);
    rb_define_singleton_method(rb_mC, "zen_ffi_shader_set_vec4_array", cruby_zen_ffi_shader_set_vec4_array, 4);
    rb_define_singleton_method(rb_mC, "zen_ffi_shader_set_mat4", cruby_zen_ffi_shader_set_mat4, 3);
    rb_define_singleton_method(rb_mC, "zen_shader_set_texture", cruby_zen_shader_set_texture, 4);
    rb_define_singleton_method(rb_mC, "zen_ffi_mesh_create", cruby_zen_ffi_mesh_create, 8);
    rb_define_singleton_method(rb_mC, "zen_ffi_mesh_update_vertices", cruby_zen_ffi_mesh_update_vertices, 5);
    rb_define_singleton_method(rb_mC, "zen_ffi_mesh_update_indices", cruby_zen_ffi_mesh_update_indices, 3);
    rb_define_singleton_method(rb_mC, "zen_ffi_mesh_is_dynamic", cruby_zen_ffi_mesh_is_dynamic, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_mesh_vertex_count", cruby_zen_ffi_mesh_vertex_count, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_mesh_index_count", cruby_zen_ffi_mesh_index_count, 1);
    rb_define_singleton_method(rb_mC, "zen_set_blend_mode", cruby_zen_set_blend_mode, 1);
    rb_define_singleton_method(rb_mC, "zen_set_scissor", cruby_zen_set_scissor, 4);
    rb_define_singleton_method(rb_mC, "zen_reset_scissor", cruby_zen_reset_scissor, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_draw_buffer", cruby_zen_ffi_draw_buffer, 8);
    rb_define_singleton_method(rb_mC, "zen_ffi_draw_mesh", cruby_zen_ffi_draw_mesh, 7);
    rb_define_singleton_method(rb_mC, "zen_font_load", cruby_zen_font_load, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_font_query_glyph", cruby_zen_ffi_font_query_glyph, 5);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_visible", cruby_zen_ffi_glyph_visible, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_u0", cruby_zen_ffi_glyph_u0, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_v0", cruby_zen_ffi_glyph_v0, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_u1", cruby_zen_ffi_glyph_u1, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_v1", cruby_zen_ffi_glyph_v1, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_x0", cruby_zen_ffi_glyph_x0, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_y0", cruby_zen_ffi_glyph_y0, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_x1", cruby_zen_ffi_glyph_x1, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_y1", cruby_zen_ffi_glyph_y1, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_advance", cruby_zen_ffi_glyph_advance, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_glyph_is_bitmap", cruby_zen_ffi_glyph_is_bitmap, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_font_ascent", cruby_zen_ffi_font_ascent, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_font_descent", cruby_zen_ffi_font_descent, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_font_line_gap", cruby_zen_ffi_font_line_gap, 2);
    rb_define_singleton_method(rb_mC, "zen_font_set_atlas_image", cruby_zen_font_set_atlas_image, 1);
    rb_define_singleton_method(rb_mC, "zen_font_atlas_generation", cruby_zen_font_atlas_generation, 0);
    rb_define_singleton_method(rb_mC, "zen_audio_init", cruby_zen_audio_init, 0);
    rb_define_singleton_method(rb_mC, "zen_audio_shutdown", cruby_zen_audio_shutdown, 0);
    rb_define_singleton_method(rb_mC, "zen_audio_set_master_volume", cruby_zen_audio_set_master_volume, 1);
    rb_define_singleton_method(rb_mC, "zen_audio_get_master_volume", cruby_zen_audio_get_master_volume, 0);
    rb_define_singleton_method(rb_mC, "zen_sound_load_file", cruby_zen_sound_load_file, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_load_pcm", cruby_zen_ffi_sound_load_pcm, 4);
    rb_define_singleton_method(rb_mC, "zen_sound_play", cruby_zen_sound_play, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_stop", cruby_zen_sound_stop, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_pause", cruby_zen_sound_pause, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_is_playing", cruby_zen_sound_is_playing, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_set_volume", cruby_zen_sound_set_volume, 2);
    rb_define_singleton_method(rb_mC, "zen_sound_get_volume", cruby_zen_sound_get_volume, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_set_looping", cruby_zen_sound_set_looping, 2);
    rb_define_singleton_method(rb_mC, "zen_sound_is_looping", cruby_zen_sound_is_looping, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_set_pitch", cruby_zen_sound_set_pitch, 2);
    rb_define_singleton_method(rb_mC, "zen_sound_get_pitch", cruby_zen_sound_get_pitch, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_set_pan", cruby_zen_sound_set_pan, 2);
    rb_define_singleton_method(rb_mC, "zen_sound_get_pan", cruby_zen_sound_get_pan, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_seek", cruby_zen_sound_seek, 2);
    rb_define_singleton_method(rb_mC, "zen_sound_get_cursor", cruby_zen_sound_get_cursor, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_get_length", cruby_zen_sound_get_length, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_get_sample_rate", cruby_zen_sound_get_sample_rate, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_get_length_pcm", cruby_zen_ffi_sound_get_length_pcm, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_set_loop_points_pcm", cruby_zen_ffi_sound_set_loop_points_pcm, 3);
    rb_define_singleton_method(rb_mC, "zen_sound_set_loop_points_seconds", cruby_zen_sound_set_loop_points_seconds, 3);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_get_loop_start_sec", cruby_zen_ffi_sound_get_loop_start_sec, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_get_loop_end_sec", cruby_zen_ffi_sound_get_loop_end_sec, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_set_loop_start_sec", cruby_zen_ffi_sound_set_loop_start_sec, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_set_loop_end_sec", cruby_zen_ffi_sound_set_loop_end_sec, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_get_loop_start_pcm", cruby_zen_ffi_sound_get_loop_start_pcm, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_get_loop_end_pcm", cruby_zen_ffi_sound_get_loop_end_pcm, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_set_loop_start_pcm", cruby_zen_ffi_sound_set_loop_start_pcm, 2);
    rb_define_singleton_method(rb_mC, "zen_ffi_sound_set_loop_end_pcm", cruby_zen_ffi_sound_set_loop_end_pcm, 2);
    rb_define_singleton_method(rb_mC, "zen_sound_has_loop_points", cruby_zen_sound_has_loop_points, 1);
    rb_define_singleton_method(rb_mC, "zen_sound_clear_loop_points", cruby_zen_sound_clear_loop_points, 1);
    rb_define_singleton_method(rb_mC, "zen_js_eval", cruby_zen_js_eval, 1);
    rb_define_singleton_method(rb_mC, "zen_js_eval_num", cruby_zen_js_eval_num, 1);
    rb_define_singleton_method(rb_mC, "zen_js_eval_str", cruby_zen_js_eval_str, 1);
    rb_define_singleton_method(rb_mC, "zen_js_is_page_visible", cruby_zen_js_is_page_visible, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_safe_area_left", cruby_zen_ffi_safe_area_left, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_safe_area_top", cruby_zen_ffi_safe_area_top, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_safe_area_right", cruby_zen_ffi_safe_area_right, 0);
    rb_define_singleton_method(rb_mC, "zen_ffi_safe_area_bottom", cruby_zen_ffi_safe_area_bottom, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_register_pipeline", cruby_zen_batch_register_pipeline, 7);
    rb_define_singleton_method(rb_mC, "zen_batch_set_pipeline_default_shader", cruby_zen_batch_set_pipeline_default_shader, 2);
    rb_define_singleton_method(rb_mC, "zen_batch_reset_frame", cruby_zen_batch_reset_frame, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_mark_screen_cleared", cruby_zen_batch_mark_screen_cleared, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_set_current_target", cruby_zen_batch_set_current_target, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_get_current_target", cruby_zen_batch_get_current_target, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_set_active_gl_target", cruby_zen_batch_set_active_gl_target, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_get_active_gl_target", cruby_zen_batch_get_active_gl_target, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_push_clip", cruby_zen_batch_push_clip, 5);
    rb_define_singleton_method(rb_mC, "zen_batch_pop_clip", cruby_zen_batch_pop_clip, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_clear_clips", cruby_zen_batch_clear_clips, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_has_pending_draws", cruby_zen_batch_has_pending_draws, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_flush_image", cruby_zen_batch_flush_image, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_flush_pending_images", cruby_zen_batch_flush_pending_images, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_set_clear", cruby_zen_batch_set_clear, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_flush_screen", cruby_zen_batch_flush_screen, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_flush_active", cruby_zen_batch_flush_active, 1);
    rb_define_singleton_method(rb_mC, "zen_batch_last_draw_calls", cruby_zen_batch_last_draw_calls, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_active_queue_count", cruby_zen_batch_active_queue_count, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_screen_queue_count", cruby_zen_batch_screen_queue_count, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_sort_screen_queue", cruby_zen_batch_sort_screen_queue, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_begin_uniforms", cruby_zen_batch_begin_uniforms, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_int", cruby_zen_batch_uniform_int, 2);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_float", cruby_zen_batch_uniform_float, 2);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_vec2", cruby_zen_batch_uniform_vec2, 3);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_vec3", cruby_zen_batch_uniform_vec3, 4);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_vec4", cruby_zen_batch_uniform_vec4, 5);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_mat4", cruby_zen_batch_uniform_mat4, 2);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_vec4_array", cruby_zen_batch_uniform_vec4_array, 3);
    rb_define_singleton_method(rb_mC, "zen_batch_uniform_texture", cruby_zen_batch_uniform_texture, 2);
    rb_define_singleton_method(rb_mC, "zen_batch_enqueue_draw", cruby_zen_batch_enqueue_draw, 10);
    rb_define_singleton_method(rb_mC, "zen_batch_enqueue_flat_rect", cruby_zen_batch_enqueue_flat_rect, 11);
    rb_define_singleton_method(rb_mC, "zen_batch_stage_card_colors", cruby_zen_batch_stage_card_colors, 12);
    rb_define_singleton_method(rb_mC, "zen_batch_stage_card_params", cruby_zen_batch_stage_card_params, 11);
    rb_define_singleton_method(rb_mC, "zen_batch_enqueue_sdf_card", cruby_zen_batch_enqueue_sdf_card, 8);
    rb_define_singleton_method(rb_mC, "zen_batch_stage_color", cruby_zen_batch_stage_color, 4);
    rb_define_singleton_method(rb_mC, "zen_batch_enqueue_sprite", cruby_zen_batch_enqueue_sprite, 11);
    rb_define_singleton_method(rb_mC, "zen_batch_enqueue_triangle_flat", cruby_zen_batch_enqueue_triangle_flat, 13);
    rb_define_singleton_method(rb_mC, "zen_batch_stage_tri_colors", cruby_zen_batch_stage_tri_colors, 12);
    rb_define_singleton_method(rb_mC, "zen_batch_enqueue_triangle_grad", cruby_zen_batch_enqueue_triangle_grad, 9);
    rb_define_singleton_method(rb_mC, "zen_batch_begin_text", cruby_zen_batch_begin_text, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_set_text_color_outline", cruby_zen_batch_set_text_color_outline, 12);
    rb_define_singleton_method(rb_mC, "zen_batch_set_text_shadow_weight", cruby_zen_batch_set_text_shadow_weight, 5);
    rb_define_singleton_method(rb_mC, "zen_batch_stage_text_line", cruby_zen_batch_stage_text_line, 8);
    rb_define_singleton_method(rb_mC, "zen_batch_set_glyph_override", cruby_zen_batch_set_glyph_override, 10);
    rb_define_singleton_method(rb_mC, "zen_batch_stage_glyph", cruby_zen_batch_stage_glyph, 10);
    rb_define_singleton_method(rb_mC, "zen_batch_staged_glyph_count", cruby_zen_batch_staged_glyph_count, 0);
    rb_define_singleton_method(rb_mC, "zen_batch_commit_text", cruby_zen_batch_commit_text, 4);
    rb_define_singleton_method(rb_mC, "zen_snapshot_create", cruby_zen_snapshot_create, 0);
    rb_define_singleton_method(rb_mC, "zen_snapshot_count", cruby_zen_snapshot_count, 1);
    rb_define_singleton_method(rb_mC, "zen_snapshot_clear", cruby_zen_snapshot_clear, 1);
    rb_define_singleton_method(rb_mC, "zen_snapshot_capture_active", cruby_zen_snapshot_capture_active, 2);
    rb_define_singleton_method(rb_mC, "zen_snapshot_capture_screen", cruby_zen_snapshot_capture_screen, 1);
    rb_define_singleton_method(rb_mC, "zen_snapshot_replay_to_active", cruby_zen_snapshot_replay_to_active, 1);
    rb_define_singleton_method(rb_mC, "zen_snapshot_execute_direct", cruby_zen_snapshot_execute_direct, 1);
    rb_define_singleton_method(rb_mC, "zen_ffi_image_get_pixels", cruby_zen_ffi_image_get_pixels, 2);
}

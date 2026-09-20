#include <ruby.h>
#include "zenoo.h"

static VALUE rb_mZenoo;
static VALUE rb_mNative;
static VALUE rb_cNativeImage;
static VALUE rb_cNativeShader;

// ==========================================
// GC トリガーコールバック
// ==========================================
static void rb_zenoo_gc_hook(void) {
    rb_gc();
}

// ==========================================
// Zenoo::Native::Image (TypedData)
// ==========================================
static void image_free(void* ptr) {
    ZenImage* img = (ZenImage*)ptr;
    if (img) {
        zen_image_destroy(img);
    }
}

static size_t image_memsize(const void* ptr) {
    return ptr ? sizeof(ZenImage) : 0;
}

static const rb_data_type_t zenoo_image_data_type = {
    .wrap_struct_name = "Zenoo::Native::Image",
    .function = {
        .dmark = NULL,
        .dfree = image_free,
        .dsize = image_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE image_allocate(VALUE klass) {
    return TypedData_Wrap_Struct(klass, &zenoo_image_data_type, NULL);
}

static VALUE image_init(VALUE self, VALUE rb_w, VALUE rb_h) {
    int w = NUM2INT(rb_w);
    int h = NUM2INT(rb_h);
    ZenImage* img = zen_image_create(w, h);
    if (!img) {
        rb_raise(rb_eRuntimeError, "Failed to create Image (%dx%d)", w, h);
    }
    DATA_PTR(self) = img;
    return self;
}

static VALUE image_s_load(VALUE klass, VALUE rb_path) {
    const char* path = StringValueCStr(rb_path);
    ZenImage* img = zen_image_load(path);
    if (!img) {
        rb_raise(rb_eRuntimeError, "Failed to load image from file: %s", path);
    }
    return TypedData_Wrap_Struct(klass, &zenoo_image_data_type, img);
}

static VALUE image_get_width(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    int w = 0, h = 0;
    zen_image_get_size(img, &w, &h);
    return INT2NUM(w);
}

static VALUE image_get_height(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    int w = 0, h = 0;
    zen_image_get_size(img, &w, &h);
    return INT2NUM(h);
}

static VALUE image_set_as_render_target(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    zen_set_render_target(img);
    return Qnil;
}

static VALUE image_s_reset_render_target(VALUE klass) {
    (void)klass;
    zen_set_render_target(NULL);
    return Qnil;
}

// ==========================================
// Zenoo::Native::Shader (TypedData)
// ==========================================
static void shader_free(void* ptr) {
    ZenShader* shader = (ZenShader*)ptr;
    if (shader) {
        zen_shader_destroy(shader);
    }
}

static const rb_data_type_t zenoo_shader_data_type = {
    .wrap_struct_name = "Zenoo::Native::Shader",
    .function = {
        .dmark = NULL,
        .dfree = shader_free,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE shader_allocate(VALUE klass) {
    return TypedData_Wrap_Struct(klass, &zenoo_shader_data_type, NULL);
}

static VALUE shader_init(VALUE self, VALUE rb_vert, VALUE rb_frag) {
    const char* vert = (NIL_P(rb_vert)) ? NULL : StringValueCStr(rb_vert);
    const char* frag = (NIL_P(rb_frag)) ? NULL : StringValueCStr(rb_frag);

    ZenShader* shader = zen_shader_create(vert, frag);
    if (!shader) {
        rb_raise(rb_eRuntimeError, "Failed to compile/link Shader");
    }
    DATA_PTR(self) = shader;
    return self;
}

static VALUE shader_set_int(VALUE self, VALUE rb_name, VALUE rb_val) {
    ZenShader* shader;
    TypedData_Get_Struct(self, ZenShader, &zenoo_shader_data_type, shader);
    zen_shader_set_int(shader, StringValueCStr(rb_name), NUM2INT(rb_val));
    return Qnil;
}

static VALUE shader_set_float(VALUE self, VALUE rb_name, VALUE rb_val) {
    ZenShader* shader;
    TypedData_Get_Struct(self, ZenShader, &zenoo_shader_data_type, shader);
    zen_shader_set_float(shader, StringValueCStr(rb_name), (float)NUM2DBL(rb_val));
    return Qnil;
}

static VALUE shader_set_vec2(VALUE self, VALUE rb_name, VALUE rb_x, VALUE rb_y) {
    ZenShader* shader;
    TypedData_Get_Struct(self, ZenShader, &zenoo_shader_data_type, shader);
    zen_shader_set_vec2(shader, StringValueCStr(rb_name), (float)NUM2DBL(rb_x), (float)NUM2DBL(rb_y));
    return Qnil;
}

static VALUE shader_set_vec3(VALUE self, VALUE rb_name, VALUE rb_x, VALUE rb_y, VALUE rb_z) {
    ZenShader* shader;
    TypedData_Get_Struct(self, ZenShader, &zenoo_shader_data_type, shader);
    zen_shader_set_vec3(shader, StringValueCStr(rb_name), (float)NUM2DBL(rb_x), (float)NUM2DBL(rb_y), (float)NUM2DBL(rb_z));
    return Qnil;
}

static VALUE shader_set_vec4(VALUE self, VALUE rb_name, VALUE rb_x, VALUE rb_y, VALUE rb_z, VALUE rb_w) {
    ZenShader* shader;
    TypedData_Get_Struct(self, ZenShader, &zenoo_shader_data_type, shader);
    zen_shader_set_vec4(shader, StringValueCStr(rb_name), (float)NUM2DBL(rb_x), (float)NUM2DBL(rb_y), (float)NUM2DBL(rb_z), (float)NUM2DBL(rb_w));
    return Qnil;
}

// ==========================================
// Zenoo::Native::Window
// ==========================================
static VALUE win_init(int argc, VALUE* argv, VALUE self) {
    (void)self;
    VALUE rb_w, rb_h, rb_title, rb_fullscreen;
    rb_scan_args(argc, argv, "22", &rb_w, &rb_h, &rb_title, &rb_fullscreen);

    int w = NUM2INT(rb_w);
    int h = NUM2INT(rb_h);
    const char* title = NIL_P(rb_title) ? "Zenoo" : StringValueCStr(rb_title);
    int fullscreen = RTEST(rb_fullscreen);

    int ok = fullscreen ? zen_init_fullscreen(title) : zen_init(w, h, title);
    if (!ok) {
        rb_raise(rb_eRuntimeError, "Failed to initialize Zenoo Window");
    }
    return Qtrue;
}

static VALUE win_update(VALUE self) {
    (void)self;
    return zen_update() ? Qtrue : Qfalse;
}

static VALUE win_clear(VALUE self, VALUE rb_color) {
    (void)self;
    zen_clear((uint32_t)NUM2UINT(rb_color));
    return Qnil;
}

static VALUE win_get_size(VALUE self) {
    (void)self;
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return rb_ary_new_from_args(2, INT2NUM(w), INT2NUM(h));
}

static VALUE win_get_size_w(VALUE self) {
    (void)self;
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return INT2NUM(w);
}

static VALUE win_get_size_h(VALUE self) {
    (void)self;
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return INT2NUM(h);
}

static VALUE win_set_vsync(VALUE self, VALUE rb_vsync) {
    (void)self;
    int vsync = 0;
    if (FIXNUM_P(rb_vsync)) {
        vsync = (NUM2INT(rb_vsync) != 0) ? 1 : 0;
    } else {
        vsync = RTEST(rb_vsync) ? 1 : 0;
    }
    zen_set_vsync(vsync);
    return rb_vsync;
}

static VALUE win_set_target_fps(VALUE self, VALUE rb_fps) {
    (void)self;
    zen_set_target_fps(NUM2INT(rb_fps));
    return rb_fps;
}

static VALUE win_get_delta_time(VALUE self) {
    (void)self;
    return DBL2NUM(zen_get_delta_time());
}

static VALUE win_get_time(VALUE self) {
    (void)self;
    return DBL2NUM(zen_get_time());
}

static VALUE win_shutdown(VALUE self) {
    (void)self;
    zen_shutdown();
    return Qnil;
}

// ==========================================
// Zenoo::Native::Input
// ==========================================
static VALUE input_key_pressed(VALUE self, VALUE rb_key) {
    (void)self;
    return zen_is_key_pressed(NUM2INT(rb_key)) ? Qtrue : Qfalse;
}

static VALUE input_key_push(VALUE self, VALUE rb_key) {
    (void)self;
    return zen_is_key_push(NUM2INT(rb_key)) ? Qtrue : Qfalse;
}

static VALUE input_key_release(VALUE self, VALUE rb_key) {
    (void)self;
    return zen_is_key_release(NUM2INT(rb_key)) ? Qtrue : Qfalse;
}

static VALUE input_mouse_pos(VALUE self) {
    (void)self;
    float x = 0, y = 0;
    zen_get_mouse_pos(&x, &y);
    return rb_ary_new_from_args(2, DBL2NUM(x), DBL2NUM(y));
}

static VALUE input_mouse_x(VALUE self) {
    (void)self;
    float x = 0, y = 0;
    zen_get_mouse_pos(&x, &y);
    return DBL2NUM(x);
}

static VALUE input_mouse_y(VALUE self) {
    (void)self;
    float x = 0, y = 0;
    zen_get_mouse_pos(&x, &y);
    return DBL2NUM(y);
}

static VALUE input_mouse_pressed(VALUE self, VALUE rb_btn) {
    (void)self;
    return zen_is_mouse_pressed(NUM2INT(rb_btn)) ? Qtrue : Qfalse;
}

static VALUE input_mouse_push(VALUE self, VALUE rb_btn) {
    (void)self;
    return zen_is_mouse_push(NUM2INT(rb_btn)) ? Qtrue : Qfalse;
}

static VALUE input_mouse_release(VALUE self, VALUE rb_btn) {
    (void)self;
    return zen_is_mouse_release(NUM2INT(rb_btn)) ? Qtrue : Qfalse;
}

static VALUE input_gamepad_connected(VALUE self, VALUE rb_id) {
    (void)self;
    return zen_is_gamepad_connected(NUM2INT(rb_id)) ? Qtrue : Qfalse;
}

static VALUE input_gamepad_axis(VALUE self, VALUE rb_id, VALUE rb_axis) {
    (void)self;
    float val = zen_get_gamepad_axis(NUM2INT(rb_id), NUM2INT(rb_axis));
    return DBL2NUM((double)val);
}

static VALUE input_gamepad_button_pressed(VALUE self, VALUE rb_id, VALUE rb_button) {
    (void)self;
    return zen_is_gamepad_button_pressed(NUM2INT(rb_id), NUM2INT(rb_button)) ? Qtrue : Qfalse;
}

static VALUE input_gamepad_button_push(VALUE self, VALUE rb_id, VALUE rb_button) {
    (void)self;
    return zen_is_gamepad_button_push(NUM2INT(rb_id), NUM2INT(rb_button)) ? Qtrue : Qfalse;
}

static VALUE input_gamepad_button_release(VALUE self, VALUE rb_id, VALUE rb_button) {
    (void)self;
    return zen_is_gamepad_button_release(NUM2INT(rb_id), NUM2INT(rb_button)) ? Qtrue : Qfalse;
}

// ==========================================
// Zenoo::Native::Renderer
// ==========================================
static void array_to_floats4(VALUE ary, float out[4], float def_val) {
    if (NIL_P(ary) || !RB_TYPE_P(ary, T_ARRAY)) {
        out[0] = def_val; out[1] = def_val; out[2] = def_val; out[3] = def_val;
        return;
    }
    long len = RARRAY_LEN(ary);
    for (int i = 0; i < 4; i++) {
        out[i] = (i < len) ? (float)NUM2DBL(RARRAY_AREF(ary, i)) : def_val;
    }
}

static VALUE renderer_draw_quad(int argc, VALUE* argv, VALUE self) {
    (void)self;
    VALUE rb_x, rb_y, rb_w, rb_h;
    VALUE rb_uv, rb_color, rb_p0, rb_p1, rb_p2, rb_image, rb_shader;
    rb_scan_args(argc, argv, "47", &rb_x, &rb_y, &rb_w, &rb_h,
                 &rb_uv, &rb_color, &rb_p0, &rb_p1, &rb_p2, &rb_image, &rb_shader);

    float x = (float)NUM2DBL(rb_x);
    float y = (float)NUM2DBL(rb_y);
    float w = (float)NUM2DBL(rb_w);
    float h = (float)NUM2DBL(rb_h);

    float uv[4], color[4], p0[4], p1[4], p2[4];
    array_to_floats4(rb_uv, uv, 0.0f);
    if (NIL_P(rb_uv)) { uv[0] = 0.0f; uv[1] = 0.0f; uv[2] = 1.0f; uv[3] = 1.0f; }

    array_to_floats4(rb_color, color, 1.0f);
    array_to_floats4(rb_p0, p0, 0.0f);
    array_to_floats4(rb_p1, p1, 0.0f);
    array_to_floats4(rb_p2, p2, 0.0f);

    ZenImage* img = NULL;
    if (!NIL_P(rb_image)) {
        TypedData_Get_Struct(rb_image, ZenImage, &zenoo_image_data_type, img);
    }

    ZenShader* shader = NULL;
    if (!NIL_P(rb_shader)) {
        TypedData_Get_Struct(rb_shader, ZenShader, &zenoo_shader_data_type, shader);
    }

    zen_draw_quad_generic(x, y, w, h, uv, color, p0, p1, p2, img, shader);
    return Qnil;
}

static VALUE renderer_flush(VALUE self) {
    (void)self;
    zen_flush();
    return Qnil;
}

static VALUE renderer_draw_triangle(VALUE self, VALUE rb_x1, VALUE rb_y1, VALUE rb_x2, VALUE rb_y2, VALUE rb_x3, VALUE rb_y3, VALUE rb_r, VALUE rb_g, VALUE rb_b, VALUE rb_a) {
    (void)self;
    float color[4] = {
        (float)NUM2DBL(rb_r),
        (float)NUM2DBL(rb_g),
        (float)NUM2DBL(rb_b),
        (float)NUM2DBL(rb_a)
    };
    zen_draw_triangle(
        (float)NUM2DBL(rb_x1), (float)NUM2DBL(rb_y1),
        (float)NUM2DBL(rb_x2), (float)NUM2DBL(rb_y2),
        (float)NUM2DBL(rb_x3), (float)NUM2DBL(rb_y3),
        color
    );
    return Qnil;
}

static VALUE renderer_draw_line(VALUE self, VALUE rb_x1, VALUE rb_y1, VALUE rb_x2, VALUE rb_y2, VALUE rb_r, VALUE rb_g, VALUE rb_b, VALUE rb_a) {
    (void)self;
    float color[4] = {
        (float)NUM2DBL(rb_r),
        (float)NUM2DBL(rb_g),
        (float)NUM2DBL(rb_b),
        (float)NUM2DBL(rb_a)
    };
    zen_draw_line(
        (float)NUM2DBL(rb_x1), (float)NUM2DBL(rb_y1),
        (float)NUM2DBL(rb_x2), (float)NUM2DBL(rb_y2),
        color
    );
    return Qnil;
}

// ==========================================
// C拡張初期化エントリポイント
// ==========================================
void Init_zenoo(void) {
    // GCトリガーコールバック登録 (テクスチャ不足時に rb_gc() をキック)
    zen_set_gc_trigger_callback(rb_zenoo_gc_hook);

    rb_mZenoo = rb_define_module("Zenoo");
    rb_mNative = rb_define_module_under(rb_mZenoo, "Native");

    // 1. Window
    VALUE mWindow = rb_define_module_under(rb_mNative, "Window");
    rb_define_singleton_method(mWindow, "init", win_init, -1);
    rb_define_singleton_method(mWindow, "update", win_update, 0);
    rb_define_singleton_method(mWindow, "clear", win_clear, 1);
    rb_define_singleton_method(mWindow, "size", win_get_size, 0);
    rb_define_singleton_method(mWindow, "size_w", win_get_size_w, 0);
    rb_define_singleton_method(mWindow, "size_h", win_get_size_h, 0);
    rb_define_singleton_method(mWindow, "vsync=", win_set_vsync, 1);
    rb_define_singleton_method(mWindow, "target_fps=", win_set_target_fps, 1);
    rb_define_singleton_method(mWindow, "delta_time", win_get_delta_time, 0);
    rb_define_singleton_method(mWindow, "time", win_get_time, 0);
    rb_define_singleton_method(mWindow, "shutdown", win_shutdown, 0);

    // 2. Input
    VALUE mInput = rb_define_module_under(rb_mNative, "Input");
    rb_define_singleton_method(mInput, "key_pressed?", input_key_pressed, 1);
    rb_define_singleton_method(mInput, "key_push?", input_key_push, 1);
    rb_define_singleton_method(mInput, "key_release?", input_key_release, 1);
    rb_define_singleton_method(mInput, "mouse_pos", input_mouse_pos, 0);
    rb_define_singleton_method(mInput, "mouse_x", input_mouse_x, 0);
    rb_define_singleton_method(mInput, "mouse_y", input_mouse_y, 0);
    rb_define_singleton_method(mInput, "mouse_pressed?", input_mouse_pressed, 1);
    rb_define_singleton_method(mInput, "mouse_push?", input_mouse_push, 1);
    rb_define_singleton_method(mInput, "mouse_release?", input_mouse_release, 1);
    rb_define_singleton_method(mInput, "gamepad_connected?", input_gamepad_connected, 1);
    rb_define_singleton_method(mInput, "gamepad_axis", input_gamepad_axis, 2);
    rb_define_singleton_method(mInput, "gamepad_button_pressed?", input_gamepad_button_pressed, 2);
    rb_define_singleton_method(mInput, "gamepad_button_push?", input_gamepad_button_push, 2);
    rb_define_singleton_method(mInput, "gamepad_button_release?", input_gamepad_button_release, 2);

    // 3. Image (Zenoo::Image)
    rb_cNativeImage = rb_define_class_under(rb_mZenoo, "Image", rb_cObject);
    rb_define_const(rb_mNative, "Image", rb_cNativeImage);
    rb_define_alloc_func(rb_cNativeImage, image_allocate);
    rb_define_method(rb_cNativeImage, "initialize", image_init, 2);
    rb_define_singleton_method(rb_cNativeImage, "load", image_s_load, 1);
    rb_define_method(rb_cNativeImage, "width", image_get_width, 0);
    rb_define_method(rb_cNativeImage, "height", image_get_height, 0);
    rb_define_method(rb_cNativeImage, "set_as_render_target", image_set_as_render_target, 0);
    rb_define_singleton_method(rb_cNativeImage, "reset_render_target", image_s_reset_render_target, 0);

    // 4. Shader (Zenoo::Shader)
    rb_cNativeShader = rb_define_class_under(rb_mZenoo, "Shader", rb_cObject);
    rb_define_const(rb_mNative, "Shader", rb_cNativeShader);
    rb_define_alloc_func(rb_cNativeShader, shader_allocate);
    rb_define_method(rb_cNativeShader, "initialize", shader_init, 2);
    rb_define_method(rb_cNativeShader, "set_int", shader_set_int, 2);
    rb_define_method(rb_cNativeShader, "set_float", shader_set_float, 2);
    rb_define_method(rb_cNativeShader, "set_vec2", shader_set_vec2, 3);
    rb_define_method(rb_cNativeShader, "set_vec3", shader_set_vec3, 4);
    rb_define_method(rb_cNativeShader, "set_vec4", shader_set_vec4, 5);

    // 5. Renderer
    VALUE mRenderer = rb_define_module_under(rb_mNative, "Renderer");
    rb_define_singleton_method(mRenderer, "draw_quad", renderer_draw_quad, -1);
    rb_define_singleton_method(mRenderer, "draw_triangle", renderer_draw_triangle, 10);
    rb_define_singleton_method(mRenderer, "draw_line", renderer_draw_line, 8);
    rb_define_singleton_method(mRenderer, "flush", renderer_flush, 0);
}

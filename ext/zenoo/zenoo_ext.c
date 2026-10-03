#include <ruby.h>
#include "zenoo.h"

static VALUE rb_mZenoo;
static VALUE rb_mNative;
static VALUE rb_cNativeImage;
static VALUE rb_cNativeShader;
static VALUE rb_cNativeFont;


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

static VALUE image_sub_image(VALUE self, VALUE rb_x, VALUE rb_y, VALUE rb_w, VALUE rb_h) {
    ZenImage* parent;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, parent);
    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);
    int w = NUM2INT(rb_w);
    int h = NUM2INT(rb_h);

    ZenImage* sub = zen_image_sub_image(parent, x, y, w, h);
    if (!sub) {
        rb_raise(rb_eRuntimeError, "Failed to create SubImage (%d, %d, %dx%d)", x, y, w, h);
    }
    return TypedData_Wrap_Struct(rb_obj_class(self), &zenoo_image_data_type, sub);
}

static VALUE image_get_x(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    return INT2NUM(img ? img->x : 0);
}

static VALUE image_get_y(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    return INT2NUM(img ? img->y : 0);
}

static VALUE image_get_texture_width(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    int tw = 0, th = 0;
    zen_image_get_texture_size(img, &tw, &th);
    return INT2NUM(tw);
}

static VALUE image_get_texture_height(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    int tw = 0, th = 0;
    zen_image_get_texture_size(img, &tw, &th);
    return INT2NUM(th);
}

static VALUE image_get_texture_id(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    return UINT2NUM(zen_image_get_texture_id(img));
}

static VALUE image_get_uv(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    float u = 0.0f, v = 0.0f, uw = 1.0f, vh = 1.0f;
    zen_image_get_uv(img, &u, &v, &uw, &vh);
    return rb_ary_new_from_args(4, DBL2NUM(u), DBL2NUM(v), DBL2NUM(uw), DBL2NUM(vh));
}

static VALUE image_is_sub_image(VALUE self) {
    ZenImage* img;
    TypedData_Get_Struct(self, ZenImage, &zenoo_image_data_type, img);
    if (!img || !img->texture) return Qfalse;
    if (img->x != 0 || img->y != 0 ||
        img->width != img->texture->width ||
        img->height != img->texture->height) {
        return Qtrue;
    }
    return Qfalse;
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

static VALUE shader_set_mat4(VALUE self, VALUE rb_name, VALUE rb_mat) {
    ZenShader* shader;
    TypedData_Get_Struct(self, ZenShader, &zenoo_shader_data_type, shader);
    float m[16];
    if (RB_TYPE_P(rb_mat, T_ARRAY) && RARRAY_LEN(rb_mat) >= 16) {
        for (int i = 0; i < 16; i++) {
            m[i] = (float)NUM2DBL(rb_ary_entry(rb_mat, i));
        }
    } else if (RB_TYPE_P(rb_mat, T_STRING) && RSTRING_LEN(rb_mat) >= (long)(16 * sizeof(float))) {
        memcpy(m, RSTRING_PTR(rb_mat), 16 * sizeof(float));
    } else {
        rb_raise(rb_eArgError, "Expected 16-element Array of floats or packed String for mat4");
    }
    zen_shader_set_mat4(shader, StringValueCStr(rb_name), m);
    return Qnil;
}

// ==========================================
// Zenoo::Native::Font (TypedData)
// ==========================================
static void font_free(void* ptr) {
    ZenFont* font = (ZenFont*)ptr;
    if (font) {
        zen_font_destroy(font);
    }
}

static const rb_data_type_t zenoo_font_data_type = {
    .wrap_struct_name = "Zenoo::Native::Font",
    .function = {
        .dmark = NULL,
        .dfree = font_free,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE font_allocate(VALUE klass) {
    return TypedData_Wrap_Struct(klass, &zenoo_font_data_type, NULL);
}

static VALUE font_s_load(VALUE klass, VALUE rb_path) {
    const char* path = StringValueCStr(rb_path);
    ZenFont* font = zen_font_load(path);
    if (!font) {
        rb_raise(rb_eRuntimeError, "Failed to load Font from file: %s", path);
    }
    return TypedData_Wrap_Struct(klass, &zenoo_font_data_type, font);
}

static VALUE font_get_glyph(VALUE self, VALUE rb_cp, VALUE rb_size) {
    ZenFont* font;
    TypedData_Get_Struct(self, ZenFont, &zenoo_font_data_type, font);

    int cp = NUM2INT(rb_cp);
    float size = (float)NUM2DBL(rb_size);

    ZenGlyph g;
    int ok = zen_font_get_glyph(font, cp, size, &g);
    if (!ok) {
        return Qnil;
    }

    VALUE ary = rb_ary_new_capa(11);
    rb_ary_push(ary, g.visible ? Qtrue : Qfalse);
    rb_ary_push(ary, DBL2NUM(g.u0));
    rb_ary_push(ary, DBL2NUM(g.v0));
    rb_ary_push(ary, DBL2NUM(g.u1));
    rb_ary_push(ary, DBL2NUM(g.v1));
    rb_ary_push(ary, DBL2NUM(g.x0));
    rb_ary_push(ary, DBL2NUM(g.y0));
    rb_ary_push(ary, DBL2NUM(g.x1));
    rb_ary_push(ary, DBL2NUM(g.y1));
    rb_ary_push(ary, DBL2NUM(g.advance_x));
    rb_ary_push(ary, g.is_bitmap ? Qtrue : Qfalse);
    return ary;
}

static VALUE font_get_metrics(VALUE self, VALUE rb_size) {
    ZenFont* font;
    TypedData_Get_Struct(self, ZenFont, &zenoo_font_data_type, font);

    float size = (float)NUM2DBL(rb_size);
    float ascent = 0, descent = 0, line_gap = 0;
    zen_font_get_metrics(font, size, &ascent, &descent, &line_gap);

    return rb_ary_new_from_args(3, DBL2NUM(ascent), DBL2NUM(descent), DBL2NUM(line_gap));
}

static VALUE s_atlas_image_obj = Qnil;

static VALUE font_s_atlas_image(VALUE klass) {
    (void)klass;
    ZenImage* img = zen_font_get_atlas_image();
    if (!img) return Qnil;

    if (NIL_P(s_atlas_image_obj)) {
        s_atlas_image_obj = TypedData_Wrap_Struct(rb_cNativeImage, &zenoo_image_data_type, img);
        rb_gc_register_address(&s_atlas_image_obj);
    }
    return s_atlas_image_obj;
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

static VALUE win_wasm_p(VALUE self) {
    (void)self;
    return Qfalse;
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

static VALUE input_key_repeat(VALUE self, VALUE rb_key) {
    (void)self;
    return zen_is_key_repeat(NUM2INT(rb_key)) ? Qtrue : Qfalse;
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

static int zen_ext_utf32_to_utf8(uint32_t cp, char* out) {
    if (cp <= 0x7F) {
        out[0] = (char)cp;
        out[1] = '\0';
        return 1;
    } else if (cp <= 0x7FF) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        out[2] = '\0';
        return 2;
    } else if (cp <= 0xFFFF) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        out[3] = '\0';
        return 3;
    } else if (cp <= 0x10FFFF) {
        out[0] = (char)(0xF0 | (cp >> 18));
        out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[3] = (char)(0x80 | (cp & 0x3F));
        out[4] = '\0';
        return 4;
    }
    return 0;
}

static VALUE input_input_chars(VALUE self) {
    (void)self;
    uint32_t buf[64];
    int count = zen_get_char_queue(buf, 64);
    VALUE ary = rb_ary_new_capa(count);
    char utf8_buf[8];
    for (int i = 0; i < count; i++) {
        int len = zen_ext_utf32_to_utf8(buf[i], utf8_buf);
        if (len > 0) {
            rb_ary_push(ary, rb_utf8_str_new(utf8_buf, len));
        }
    }
    return ary;
}

static VALUE input_set_ime_position(VALUE self, VALUE rb_x, VALUE rb_y) {
    (void)self;
    zen_set_ime_position(NUM2INT(rb_x), NUM2INT(rb_y));
    return Qnil;
}

// ==========================================
// Zenoo::Native::Renderer
// ==========================================
static VALUE renderer_flush(VALUE self) {
    (void)self;
    zen_flush();
    return Qnil;
}

static VALUE renderer_set_blend_mode(VALUE self, VALUE rb_mode) {
    (void)self;
    int mode = NUM2INT(rb_mode);
    zen_set_blend_mode(mode);
    return Qnil;
}

static VALUE renderer_draw_buffer(VALUE self, VALUE rb_topology, VALUE rb_layout, VALUE rb_divisors, VALUE rb_base_vertex_count, VALUE rb_data, VALUE rb_count, VALUE rb_tex, VALUE rb_shader) {
    (void)self;
    int topology = NUM2INT(rb_topology);
    const uint8_t* layout = (const uint8_t*)StringValuePtr(rb_layout);
    const uint8_t* divisors = NIL_P(rb_divisors) ? NULL : (const uint8_t*)StringValuePtr(rb_divisors);
    int base_vertex_count = NUM2INT(rb_base_vertex_count);
    Check_Type(rb_data, T_STRING);
    const void* data = (const void*)RSTRING_PTR(rb_data);
    int count = NUM2INT(rb_count);

    ZenImage* img = NULL;
    if (rb_obj_is_kind_of(rb_tex, rb_cNativeImage)) {
        TypedData_Get_Struct(rb_tex, ZenImage, &zenoo_image_data_type, img);
    }

    ZenShader* sh = NULL;
    if (rb_obj_is_kind_of(rb_shader, rb_cNativeShader)) {
        TypedData_Get_Struct(rb_shader, ZenShader, &zenoo_shader_data_type, sh);
    }

    zen_draw_buffer(topology, layout, divisors, base_vertex_count, data, count, img, sh);
    return Qnil;
}

static VALUE renderer_set_scissor(VALUE self, VALUE rb_x, VALUE rb_y, VALUE rb_w, VALUE rb_h) {
    (void)self;
    int x = NUM2INT(rb_x);
    int y = NUM2INT(rb_y);
    int w = NUM2INT(rb_w);
    int h = NUM2INT(rb_h);
    zen_set_scissor(x, y, w, h);
    return Qnil;
}

static VALUE renderer_reset_scissor(VALUE self) {
    (void)self;
    zen_reset_scissor();
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
    rb_define_singleton_method(mWindow, "wasm?", win_wasm_p, 0);

    // 2. Input
    VALUE mInput = rb_define_module_under(rb_mNative, "Input");
    rb_define_singleton_method(mInput, "key_pressed?", input_key_pressed, 1);
    rb_define_singleton_method(mInput, "key_push?", input_key_push, 1);
    rb_define_singleton_method(mInput, "key_release?", input_key_release, 1);
    rb_define_singleton_method(mInput, "key_repeat?", input_key_repeat, 1);
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
    rb_define_singleton_method(mInput, "input_chars", input_input_chars, 0);
    rb_define_singleton_method(mInput, "set_ime_position", input_set_ime_position, 2);

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
    rb_define_method(rb_cNativeImage, "sub_image", image_sub_image, 4);
    rb_define_method(rb_cNativeImage, "x", image_get_x, 0);
    rb_define_method(rb_cNativeImage, "y", image_get_y, 0);
    rb_define_method(rb_cNativeImage, "texture_width", image_get_texture_width, 0);
    rb_define_method(rb_cNativeImage, "texture_height", image_get_texture_height, 0);
    rb_define_method(rb_cNativeImage, "texture_id", image_get_texture_id, 0);
    rb_define_method(rb_cNativeImage, "uv", image_get_uv, 0);
    rb_define_method(rb_cNativeImage, "sub_image?", image_is_sub_image, 0);

    // 4. NativeShader (Zenoo::Native::NativeShader)
    rb_cNativeShader = rb_define_class_under(rb_mNative, "NativeShader", rb_cObject);
    rb_define_const(rb_mNative, "Shader", rb_cNativeShader);
    rb_define_alloc_func(rb_cNativeShader, shader_allocate);
    rb_define_method(rb_cNativeShader, "initialize", shader_init, 2);
    rb_define_method(rb_cNativeShader, "set_int", shader_set_int, 2);
    rb_define_method(rb_cNativeShader, "set_float", shader_set_float, 2);
    rb_define_method(rb_cNativeShader, "set_vec2", shader_set_vec2, 3);
    rb_define_method(rb_cNativeShader, "set_vec3", shader_set_vec3, 4);
    rb_define_method(rb_cNativeShader, "set_vec4", shader_set_vec4, 5);
    rb_define_method(rb_cNativeShader, "set_mat4", shader_set_mat4, 2);

    // 5. Renderer
    VALUE mRenderer = rb_define_module_under(rb_mNative, "Renderer");
    rb_define_singleton_method(mRenderer, "draw_buffer", renderer_draw_buffer, 8);
    rb_define_singleton_method(mRenderer, "flush", renderer_flush, 0);
    rb_define_singleton_method(mRenderer, "set_blend_mode", renderer_set_blend_mode, 1);
    rb_define_singleton_method(mRenderer, "set_scissor", renderer_set_scissor, 4);
    rb_define_singleton_method(mRenderer, "reset_scissor", renderer_reset_scissor, 0);

    // 6. Font (Zenoo::Native::Font)
    rb_cNativeFont = rb_define_class_under(rb_mNative, "Font", rb_cObject);
    rb_define_alloc_func(rb_cNativeFont, font_allocate);
    rb_define_singleton_method(rb_cNativeFont, "load", font_s_load, 1);
    rb_define_singleton_method(rb_cNativeFont, "atlas_image", font_s_atlas_image, 0);
    rb_define_method(rb_cNativeFont, "get_glyph", font_get_glyph, 2);
    rb_define_method(rb_cNativeFont, "metrics", font_get_metrics, 1);
}

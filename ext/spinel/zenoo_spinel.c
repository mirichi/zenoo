#include "zenoo_spinel.h"
#include <stdlib.h>
#include <string.h>

// GCトリガーフック
static void spinel_gc_hook(void) {
    sp_gc_collect();
}

// ==========================================
// Image (sp_ZenImage)
// ==========================================
static int s_image_free_count = 0;

void sp_ZenImage_free(void* p) {
    sp_ZenImage* s = (sp_ZenImage*)p;
    if (s && s->image) {
        zen_image_destroy(s->image);
        s->image = NULL;
        s_image_free_count++;
    }
}

sp_int sp_zen_get_image_free_count(void) {
    return (sp_int)s_image_free_count;
}

sp_ZenImage* sp_ZenImage_new(sp_int cls_id, sp_int w, sp_int h) {
    zen_set_gc_trigger_callback(spinel_gc_hook);
    sp_ZenImage* s = (sp_ZenImage*)sp_gc_alloc(sizeof(sp_ZenImage), sp_ZenImage_free, NULL);
    memset(s, 0, sizeof(*s));
    s->cls_id = cls_id;
    s->image = zen_image_create((int)w, (int)h);
    return s;
}

sp_ZenImage* sp_ZenImage_load(sp_int cls_id, const char* path) {
    zen_set_gc_trigger_callback(spinel_gc_hook);
    sp_ZenImage* s = (sp_ZenImage*)sp_gc_alloc(sizeof(sp_ZenImage), sp_ZenImage_free, NULL);
    memset(s, 0, sizeof(*s));
    s->cls_id = cls_id;
    s->image = zen_image_load(path);
    return s;
}

sp_int sp_ZenImage_width(sp_ZenImage* s) {
    if (!s || !s->image) return 0;
    int w = 0, h = 0;
    zen_image_get_size(s->image, &w, &h);
    return (sp_int)w;
}

sp_int sp_ZenImage_height(sp_ZenImage* s) {
    if (!s || !s->image) return 0;
    int w = 0, h = 0;
    zen_image_get_size(s->image, &w, &h);
    return (sp_int)h;
}

void sp_ZenImage_set_as_render_target(sp_ZenImage* s) {
    zen_set_render_target(s ? s->image : NULL);
}

void sp_ZenImage_reset_render_target(void) {
    zen_set_render_target(NULL);
}

// ==========================================
// Shader (sp_ZenShader)
// ==========================================
void sp_ZenShader_free(void* p) {
    sp_ZenShader* s = (sp_ZenShader*)p;
    if (s && s->shader) {
        zen_shader_destroy(s->shader);
        s->shader = NULL;
    }
}

sp_ZenShader* sp_ZenShader_new(sp_int cls_id, const char* vert, const char* frag) {
    sp_ZenShader* s = (sp_ZenShader*)sp_gc_alloc(sizeof(sp_ZenShader), sp_ZenShader_free, NULL);
    memset(s, 0, sizeof(*s));
    s->cls_id = cls_id;
    s->shader = zen_shader_create(vert, frag);
    return s;
}

void sp_ZenShader_set_int(sp_ZenShader* s, const char* name, sp_int val) {
    if (s && s->shader) zen_shader_set_int(s->shader, name, (int)val);
}

void sp_ZenShader_set_float(sp_ZenShader* s, const char* name, double val) {
    if (s && s->shader) zen_shader_set_float(s->shader, name, (float)val);
}

void sp_ZenShader_set_vec2(sp_ZenShader* s, const char* name, double x, double y) {
    if (s && s->shader) zen_shader_set_vec2(s->shader, name, (float)x, (float)y);
}

void sp_ZenShader_set_vec3(sp_ZenShader* s, const char* name, double x, double y, double z) {
    if (s && s->shader) zen_shader_set_vec3(s->shader, name, (float)x, (float)y, (float)z);
}

void sp_ZenShader_set_vec4(sp_ZenShader* s, const char* name, double x, double y, double z, double w) {
    if (s && s->shader) zen_shader_set_vec4(s->shader, name, (float)x, (float)y, (float)z, (float)w);
}

void sp_ZenShader_set_mat4(sp_ZenShader* s, const char* name, const char* mat4_bytes) {
    if (s && s->shader && mat4_bytes) {
        zen_shader_set_mat4(s->shader, name, (const float*)mat4_bytes);
    }
}

// ==========================================
// Window / Input / Renderer
// ==========================================
sp_int sp_zen_win_init(sp_int w, sp_int h, const char* title, sp_int fullscreen) {
    zen_set_gc_trigger_callback(spinel_gc_hook);
    if (fullscreen) {
        return (sp_int)zen_init_fullscreen(title);
    } else {
        return (sp_int)zen_init((int)w, (int)h, title);
    }
}

sp_int sp_zen_win_update(void) {
    return (sp_int)zen_update();
}

void sp_zen_win_clear(uint32_t color) {
    zen_clear(color);
}

#include "sp_proc.h"

static sp_Proc* s_wasm_step_proc = NULL;

static void spinel_wasm_step_wrapper(void) {
    if (s_wasm_step_proc) {
        sp_int args[16] = {0};
        sp_proc_call(s_wasm_step_proc, 0, args);
    }
}

void sp_zen_win_start_wasm_loop(sp_RbVal proc_val) {
    if (proc_val.tag == SP_TAG_OBJ && proc_val.v.p) {
        s_wasm_step_proc = (sp_Proc*)proc_val.v.p;
    }
    zen_set_step_callback(spinel_wasm_step_wrapper);
    zen_start_wasm_loop();
}

sp_bool sp_zen_win_is_wasm(void) {
    return zen_is_wasm() ? true : false;
}

void sp_zen_win_shutdown(void) {
    zen_shutdown();
}

sp_int sp_zen_win_size_w(void) {
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return (sp_int)w;
}

sp_int sp_zen_win_size_h(void) {
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return (sp_int)h;
}

void sp_zen_win_vsync_set(sp_int vsync) {
    zen_set_vsync((int)vsync);
}

void sp_zen_win_target_fps_set(sp_int fps) {
    zen_set_target_fps((int)fps);
}

double sp_zen_win_delta_time(void) {
    return (double)zen_get_delta_time();
}

double sp_zen_win_time(void) {
    return zen_get_time();
}

sp_bool sp_zen_input_key_pressed(sp_int key) {
    return zen_is_key_pressed((int)key) ? true : false;
}

sp_bool sp_zen_input_key_push(sp_int key) {
    return zen_is_key_push((int)key) ? true : false;
}

sp_bool sp_zen_input_key_release(sp_int key) {
    return zen_is_key_release((int)key) ? true : false;
}

sp_bool sp_zen_input_key_repeat(sp_int key) {
    return zen_is_key_repeat((int)key) ? true : false;
}

double sp_zen_input_mouse_x(void) {
    float x = 0, y = 0;
    zen_get_mouse_pos(&x, &y);
    return (double)x;
}

double sp_zen_input_mouse_y(void) {
    float x = 0, y = 0;
    zen_get_mouse_pos(&x, &y);
    return (double)y;
}

sp_bool sp_zen_input_mouse_pressed(sp_int btn) {
    return zen_is_mouse_pressed((int)btn) ? true : false;
}

sp_bool sp_zen_input_mouse_push(sp_int btn) {
    return zen_is_mouse_push((int)btn) ? true : false;
}

sp_bool sp_zen_input_mouse_release(sp_int btn) {
    return zen_is_mouse_release((int)btn) ? true : false;
}

sp_bool sp_zen_input_gamepad_connected(sp_int id) {
    return zen_is_gamepad_connected((int)id) ? true : false;
}

double sp_zen_input_gamepad_axis(sp_int id, sp_int axis) {
    return (double)zen_get_gamepad_axis((int)id, (int)axis);
}

sp_bool sp_zen_input_gamepad_button_pressed(sp_int id, sp_int button) {
    return zen_is_gamepad_button_pressed((int)id, (int)button) ? true : false;
}

sp_bool sp_zen_input_gamepad_button_push(sp_int id, sp_int button) {
    return zen_is_gamepad_button_push((int)id, (int)button) ? true : false;
}

sp_bool sp_zen_input_gamepad_button_release(sp_int id, sp_int button) {
    return zen_is_gamepad_button_release((int)id, (int)button) ? true : false;
}

sp_int sp_zen_input_get_char(void) {
    return (sp_int)zen_get_char();
}

void sp_zen_input_set_ime_position(sp_int x, sp_int y) {
    zen_set_ime_position((int)x, (int)y);
}

static ZenImage* unpack_image(sp_RbVal val) {
    if (val.tag == SP_TAG_OBJ && val.v.p) {
        sp_ZenImage* img = (sp_ZenImage*)val.v.p;
        return img->image;
    }
    return NULL;
}

static ZenShader* unpack_shader(sp_RbVal val) {
    if (val.tag == SP_TAG_OBJ && val.v.p) {
        sp_ZenShader* sh = (sp_ZenShader*)val.v.p;
        return sh->shader;
    }
    return NULL;
}



void sp_zen_renderer_draw_buffer(
    sp_int topology,
    const char* layout,
    const char* divisors,
    sp_int base_vertex_count,
    const char* data,
    sp_int count,
    sp_RbVal image_val,
    sp_RbVal shader_val
) {
    ZenImage*  img = unpack_image(image_val);
    ZenShader* sh  = unpack_shader(shader_val);
    zen_draw_buffer((int)topology, (const uint8_t*)layout, (const uint8_t*)divisors, (int)base_vertex_count, (const void*)data, (int)count, img, sh);
}

void sp_zen_renderer_flush(void) {
    zen_flush();
}

void sp_zen_renderer_set_blend_mode(sp_int mode) {
    zen_set_blend_mode((int)mode);
}

void sp_zen_renderer_set_scissor(sp_int x, sp_int y, sp_int w, sp_int h) {
    zen_set_scissor((int)x, (int)y, (int)w, (int)h);
}

void sp_zen_renderer_reset_scissor(void) {
    zen_reset_scissor();
}

// ==========================================
// Font (sp_ZenFont)
// ==========================================
static ZenGlyph s_query_glyph_cache;
static sp_ZenImage* s_atlas_zen_image = NULL;

static void sp_ZenAtlasImage_noop_free(void* p) {
    (void)p;
}

void sp_ZenFont_free(void* p) {
    sp_ZenFont* s = (sp_ZenFont*)p;
    if (s && s->font) {
        zen_font_destroy(s->font);
        s->font = NULL;
    }
}

sp_ZenFont* sp_ZenFont_load(sp_int cls_id, const char* path) {
    ZenFont* font = zen_font_load(path);
    if (!font) return NULL;

    sp_ZenFont* s = (sp_ZenFont*)sp_gc_alloc(sizeof(sp_ZenFont), sp_ZenFont_free, NULL);
    memset(s, 0, sizeof(*s));
    s->cls_id = cls_id;
    s->font = font;
    return s;
}

sp_RbVal sp_zen_font_atlas_image(sp_int image_cls_id) {
    ZenImage* img = zen_font_get_atlas_image();
    if (!img) return sp_box_nil();

    if (!s_atlas_zen_image) {
        s_atlas_zen_image = (sp_ZenImage*)sp_gc_alloc(sizeof(sp_ZenImage), sp_ZenAtlasImage_noop_free, NULL);
        memset(s_atlas_zen_image, 0, sizeof(*s_atlas_zen_image));
        s_atlas_zen_image->cls_id = image_cls_id;
        s_atlas_zen_image->image = img;
    }
    return sp_box_obj(s_atlas_zen_image, (int)image_cls_id);
}

sp_bool sp_zen_font_query_glyph(sp_ZenFont* s, sp_int cp, double size) {
    if (!s || !s->font) return false;
    int ok = zen_font_get_glyph(s->font, (int)cp, (float)size, &s_query_glyph_cache);
    return ok ? true : false;
}

sp_bool sp_zen_font_glyph_visible(void)  { return s_query_glyph_cache.visible ? true : false; }
double  sp_zen_font_glyph_u0(void)       { return (double)s_query_glyph_cache.u0; }
double  sp_zen_font_glyph_v0(void)       { return (double)s_query_glyph_cache.v0; }
double  sp_zen_font_glyph_u1(void)       { return (double)s_query_glyph_cache.u1; }
double  sp_zen_font_glyph_v1(void)       { return (double)s_query_glyph_cache.v1; }
double  sp_zen_font_glyph_x0(void)       { return (double)s_query_glyph_cache.x0; }
double  sp_zen_font_glyph_y0(void)       { return (double)s_query_glyph_cache.y0; }
double  sp_zen_font_glyph_x1(void)       { return (double)s_query_glyph_cache.x1; }
double  sp_zen_font_glyph_y1(void)       { return (double)s_query_glyph_cache.y1; }
double  sp_zen_font_glyph_advance(void)  { return (double)s_query_glyph_cache.advance_x; }
sp_bool sp_zen_font_glyph_is_bitmap(void) { return s_query_glyph_cache.is_bitmap ? true : false; }

double sp_zen_font_metrics_ascent(sp_ZenFont* s, double size) {
    if (!s || !s->font) return 0.0;
    float ascent = 0.0f;
    zen_font_get_metrics(s->font, (float)size, &ascent, NULL, NULL);
    return (double)ascent;
}

double sp_zen_font_metrics_descent(sp_ZenFont* s, double size) {
    if (!s || !s->font) return 0.0;
    float descent = 0.0f;
    zen_font_get_metrics(s->font, (float)size, NULL, &descent, NULL);
    return (double)descent;
}

double sp_zen_font_metrics_line_gap(sp_ZenFont* s, double size) {
    if (!s || !s->font) return 0.0;
    float line_gap = 0.0f;
    zen_font_get_metrics(s->font, (float)size, NULL, NULL, &line_gap);
    return (double)line_gap;
}


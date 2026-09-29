#ifndef ZENOO_SPINEL_H
#define ZENOO_SPINEL_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include "sp_gc.h"
#include "sp_alloc.h"
#include "zenoo.h"

// Spinel GC管理のネイティブ構造体
typedef struct sp_ZenImage_s {
    sp_int cls_id;
    ZenImage* image;
} sp_ZenImage;

typedef struct sp_ZenShader_s {
    sp_int cls_id;
    ZenShader* shader;
} sp_ZenShader;

// Image メソッド
void sp_ZenImage_free(void* p);
sp_ZenImage* sp_ZenImage_new(sp_int cls_id, sp_int w, sp_int h);
sp_ZenImage* sp_ZenImage_load(sp_int cls_id, const char* path);
sp_int sp_ZenImage_width(sp_ZenImage* s);
sp_int sp_ZenImage_height(sp_ZenImage* s);
void sp_ZenImage_set_as_render_target(sp_ZenImage* s);
void sp_ZenImage_reset_render_target(void);
sp_int sp_zen_get_image_free_count(void);

// Shader メソッド
void sp_ZenShader_free(void* p);
sp_ZenShader* sp_ZenShader_new(sp_int cls_id, const char* vert, const char* frag);
void sp_ZenShader_set_int(sp_ZenShader* s, const char* name, sp_int val);
void sp_ZenShader_set_float(sp_ZenShader* s, const char* name, double val);
void sp_ZenShader_set_vec2(sp_ZenShader* s, const char* name, double x, double y);
void sp_ZenShader_set_vec3(sp_ZenShader* s, const char* name, double x, double y, double z);
void sp_ZenShader_set_vec4(sp_ZenShader* s, const char* name, double x, double y, double z, double w);
void sp_ZenShader_set_mat4(sp_ZenShader* s, const char* name, const char* mat4_bytes);

// Window / Input / Renderer ラッパー
sp_int sp_zen_win_init(sp_int w, sp_int h, const char* title, sp_int fullscreen);
sp_int sp_zen_win_update(void);
void sp_zen_win_clear(uint32_t color);
void sp_zen_win_start_wasm_loop(sp_RbVal proc_val);
sp_bool sp_zen_win_is_wasm(void);
void sp_zen_win_shutdown(void);
sp_int sp_zen_win_size_w(void);
sp_int sp_zen_win_size_h(void);
void sp_zen_win_vsync_set(sp_int vsync);
void sp_zen_win_target_fps_set(sp_int fps);
double sp_zen_win_delta_time(void);
double sp_zen_win_time(void);

sp_bool sp_zen_input_key_pressed(sp_int key);
sp_bool sp_zen_input_key_push(sp_int key);
sp_bool sp_zen_input_key_release(sp_int key);
sp_bool sp_zen_input_key_repeat(sp_int key);
double sp_zen_input_mouse_x(void);
double sp_zen_input_mouse_y(void);
sp_bool sp_zen_input_mouse_pressed(sp_int btn);
sp_bool sp_zen_input_mouse_push(sp_int btn);
sp_bool sp_zen_input_mouse_release(sp_int btn);
sp_bool sp_zen_input_gamepad_connected(sp_int id);
double  sp_zen_input_gamepad_axis(sp_int id, sp_int axis);
sp_bool sp_zen_input_gamepad_button_pressed(sp_int id, sp_int button);
sp_bool sp_zen_input_gamepad_button_push(sp_int id, sp_int button);
sp_bool sp_zen_input_gamepad_button_release(sp_int id, sp_int button);
sp_int  sp_zen_input_get_char(void);
void    sp_zen_input_set_ime_position(sp_int x, sp_int y);



void sp_zen_renderer_draw_buffer(
    sp_int topology,
    const char* layout,
    const char* divisors,
    sp_int base_vertex_count,
    const char* data,
    sp_int count,
    sp_RbVal image_val,
    sp_RbVal shader_val
);

void sp_zen_renderer_flush(void);
void sp_zen_renderer_set_blend_mode(sp_int mode);

// ==========================================
// Font (sp_ZenFont)
// ==========================================
typedef struct sp_ZenFont_s {
    sp_int cls_id;
    ZenFont* font;
} sp_ZenFont;

void sp_ZenFont_free(void* p);
sp_ZenFont* sp_ZenFont_load(sp_int cls_id, const char* path);
sp_RbVal sp_zen_font_atlas_image(sp_int image_cls_id);

sp_bool sp_zen_font_query_glyph(sp_ZenFont* s, sp_int cp, double size);
sp_bool sp_zen_font_glyph_visible(void);
double  sp_zen_font_glyph_u0(void);
double  sp_zen_font_glyph_v0(void);
double  sp_zen_font_glyph_u1(void);
double  sp_zen_font_glyph_v1(void);
double  sp_zen_font_glyph_x0(void);
double  sp_zen_font_glyph_y0(void);
double  sp_zen_font_glyph_x1(void);
double  sp_zen_font_glyph_y1(void);
double  sp_zen_font_glyph_advance(void);
sp_bool sp_zen_font_glyph_is_bitmap(void);

double sp_zen_font_metrics_ascent(sp_ZenFont* s, double size);
double sp_zen_font_metrics_descent(sp_ZenFont* s, double size);
double sp_zen_font_metrics_line_gap(sp_ZenFont* s, double size);

#endif // ZENOO_SPINEL_H

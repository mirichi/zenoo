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

// Window / Input / Renderer ラッパー
sp_int sp_zen_win_init(sp_int w, sp_int h, const char* title, sp_int fullscreen);
sp_int sp_zen_win_update(void);
void sp_zen_win_clear(uint32_t color);
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
double sp_zen_input_mouse_x(void);
double sp_zen_input_mouse_y(void);
sp_bool sp_zen_input_mouse_pressed(sp_int btn);
sp_bool sp_zen_input_mouse_push(sp_int btn);
sp_bool sp_zen_input_mouse_release(sp_int btn);

void sp_zen_renderer_draw_quad_rect(
    double x, double y, double w, double h,
    double u, double v, double uw, double vh,
    double r, double g, double b, double a,
    sp_RbVal image_val,
    sp_RbVal shader_val
);

void sp_zen_renderer_draw_quad_card(
    double x, double y, double w, double h,
    double u, double v, double uw, double vh,
    double r, double g, double b, double a,
    double radius, double border_w, double shadow_blur, double mode,
    double br, double bg, double bb, double ba,
    double sr, double sg, double sb, double sa,
    sp_RbVal image_val,
    sp_RbVal shader_val
);

void sp_zen_renderer_draw_quad_generic_wrapper(
    double x, double y, double w, double h,
    double u, double v, double uw, double vh,
    double r, double g, double b, double a,
    double p0_0, double p0_1, double p0_2, double p0_3,
    double p1_0, double p1_1, double p1_2, double p1_3,
    double p2_0, double p2_1, double p2_2, double p2_3,
    sp_RbVal image_val,
    sp_RbVal shader_val
);

void sp_zen_renderer_draw_triangle(
    double x1, double y1, double x2, double y2, double x3, double y3,
    double r, double g, double b, double a
);

void sp_zen_renderer_draw_line(
    double x1, double y1, double x2, double y2,
    double r, double g, double b, double a
);

void sp_zen_renderer_flush(void);

#endif // ZENOO_SPINEL_H

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

void sp_zen_renderer_draw_quad_rect(
    double x, double y, double w, double h,
    double u, double v, double uw, double vh,
    double r, double g, double b, double a,
    sp_RbVal image_val,
    sp_RbVal shader_val
) {
    float uv[4]    = { (float)u, (float)v, (float)uw, (float)vh };
    float color[4] = { (float)r, (float)g, (float)b,  (float)a  };
    ZenImage*  img = unpack_image(image_val);
    ZenShader* sh  = unpack_shader(shader_val);

    zen_draw_quad_generic((float)x, (float)y, (float)w, (float)h,
                          uv, color, NULL, NULL, NULL, img, sh);
}

void sp_zen_renderer_draw_quad_card(
    double x, double y, double w, double h,
    double u, double v, double uw, double vh,
    double r, double g, double b, double a,
    double radius, double border_w, double shadow_blur, double mode,
    double br, double bg, double bb, double ba,
    double sr, double sg, double sb, double sa,
    sp_RbVal image_val,
    sp_RbVal shader_val
) {
    float uv[4]    = { (float)u, (float)v, (float)uw, (float)vh };
    float color[4] = { (float)r, (float)g, (float)b,  (float)a  };
    float p0[4]    = { (float)radius, (float)border_w, (float)shadow_blur, (float)mode };
    float p1[4]    = { (float)br, (float)bg, (float)bb, (float)ba };
    float p2[4]    = { (float)sr, (float)sg, (float)sb, (float)sa };
    ZenImage*  img = unpack_image(image_val);
    ZenShader* sh  = unpack_shader(shader_val);

    zen_draw_quad_generic((float)x, (float)y, (float)w, (float)h,
                          uv, color, p0, p1, p2, img, sh);
}

void sp_zen_renderer_draw_quad_generic_wrapper(
    double x, double y, double w, double h,
    double u, double v, double uw, double vh,
    double r, double g, double b, double a,
    double p0_0, double p0_1, double p0_2, double p0_3,
    double p1_0, double p1_1, double p1_2, double p1_3,
    double p2_0, double p2_1, double p2_2, double p2_3,
    sp_RbVal image_val,
    sp_RbVal shader_val
) {
    float uv[4]    = { (float)u, (float)v, (float)uw, (float)vh };
    float color[4] = { (float)r, (float)g, (float)b,  (float)a  };
    float p0[4]    = { (float)p0_0, (float)p0_1, (float)p0_2, (float)p0_3 };
    float p1[4]    = { (float)p1_0, (float)p1_1, (float)p1_2, (float)p1_3 };
    float p2[4]    = { (float)p2_0, (float)p2_1, (float)p2_2, (float)p2_3 };
    ZenImage*  img = unpack_image(image_val);
    ZenShader* sh  = unpack_shader(shader_val);

    zen_draw_quad_generic((float)x, (float)y, (float)w, (float)h,
                          uv, color, p0, p1, p2, img, sh);
}

void sp_zen_renderer_draw_triangle(
    double x1, double y1, double x2, double y2, double x3, double y3,
    double r, double g, double b, double a
) {
    float color[4] = { (float)r, (float)g, (float)b, (float)a };
    zen_draw_triangle((float)x1, (float)y1, (float)x2, (float)y2, (float)x3, (float)y3, color);
}

void sp_zen_renderer_draw_line(
    double x1, double y1, double x2, double y2,
    double r, double g, double b, double a
) {
    float color[4] = { (float)r, (float)g, (float)b, (float)a };
    zen_draw_line((float)x1, (float)y1, (float)x2, (float)y2, color);
}

void sp_zen_renderer_flush(void) {
    zen_flush();
}

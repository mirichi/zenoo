/*
 * Pure C FFI Shim for Zenoo (Spinel AOT & CRuby shared core boundary)
 *
 * Depends ONLY on zenoo.h and standard C headers (no Spinel / Ruby headers).
 */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "zenoo.h"

enum ZenFfiHandleKind {
    ZEN_FFI_KIND_IMAGE    = 1,
    ZEN_FFI_KIND_SHADER   = 2,
    ZEN_FFI_KIND_MESH     = 3,
    ZEN_FFI_KIND_FONT     = 4,
    ZEN_FFI_KIND_SOUND    = 5,
    ZEN_FFI_KIND_SNAPSHOT = 6
};

static int s_ffi_image_free_count = 0;
static ZenGlyph s_ffi_glyph_cache;

/* ==========================================
 * Handle Management
 * ========================================== */
void zen_ffi_destroy_handle(void* ptr, int kind) {
    if (!ptr) return;
    switch (kind) {
        case ZEN_FFI_KIND_IMAGE:
            zen_image_destroy((ZenImage*)ptr);
            s_ffi_image_free_count++;
            break;
        case ZEN_FFI_KIND_SHADER:
            zen_shader_destroy((ZenShader*)ptr);
            break;
        case ZEN_FFI_KIND_MESH:
            zen_mesh_destroy((ZenMesh*)ptr);
            break;
        case ZEN_FFI_KIND_FONT:
            zen_font_destroy((ZenFont*)ptr);
            break;
        case ZEN_FFI_KIND_SOUND:
            zen_sound_destroy((ZenSound*)ptr);
            break;
        case ZEN_FFI_KIND_SNAPSHOT:
            zen_snapshot_destroy((ZenSnapshot*)ptr);
            break;
        default:
            break;
    }
}

int zen_ffi_image_free_count(void) {
    return s_ffi_image_free_count;
}

/* ==========================================
 * Window & Input Helpers
 * ========================================== */
int zen_ffi_win_init(int w, int h, const char* title, int fullscreen) {
    if (fullscreen) {
        return zen_init_fullscreen(title);
    }
    return zen_init(w, h, title);
}

int zen_ffi_win_init_scaled(int base_w, int base_h, const char* title, int win_w, int win_h, int fullscreen, float scale) {
    if (fullscreen) {
        return zen_init_fullscreen(title);
    }
    return zen_init_scaled_ex(base_w, base_h, title, win_w, win_h, scale);
}

int zen_ffi_screen_w(void) {
    int w = 0, h = 0;
    zen_get_screen_size(&w, &h);
    return w;
}

int zen_ffi_screen_h(void) {
    int w = 0, h = 0;
    zen_get_screen_size(&w, &h);
    return h;
}

int zen_ffi_window_w(void) {
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return w;
}

int zen_ffi_window_h(void) {
    int w = 0, h = 0;
    zen_get_window_size(&w, &h);
    return h;
}

int zen_ffi_window_pos_x(void) {
    int x = 0, y = 0;
    zen_get_window_pos(&x, &y);
    return x;
}

int zen_ffi_window_pos_y(void) {
    int x = 0, y = 0;
    zen_get_window_pos(&x, &y);
    return y;
}

void zen_ffi_clear_frame_callback(void) {
    zen_set_frame_callback(NULL);
}

float zen_ffi_mouse_x(void) {
    float x = 0.0f, y = 0.0f;
    zen_get_mouse_pos(&x, &y);
    return x;
}

float zen_ffi_mouse_y(void) {
    float x = 0.0f, y = 0.0f;
    zen_get_mouse_pos(&x, &y);
    return y;
}

float zen_ffi_safe_area_left(void) {
    float l = 0.0f, t = 0.0f, r = 0.0f, b = 0.0f;
    zen_js_get_safe_area(&l, &t, &r, &b);
    return l;
}

float zen_ffi_safe_area_top(void) {
    float l = 0.0f, t = 0.0f, r = 0.0f, b = 0.0f;
    zen_js_get_safe_area(&l, &t, &r, &b);
    return t;
}

float zen_ffi_safe_area_right(void) {
    float l = 0.0f, t = 0.0f, r = 0.0f, b = 0.0f;
    zen_js_get_safe_area(&l, &t, &r, &b);
    return r;
}

float zen_ffi_safe_area_bottom(void) {
    float l = 0.0f, t = 0.0f, r = 0.0f, b = 0.0f;
    zen_js_get_safe_area(&l, &t, &r, &b);
    return b;
}

/* ==========================================
 * Image Helpers
 * ========================================== */
int zen_ffi_image_width(const ZenImage* img) {
    return img ? img->width : 0;
}

int zen_ffi_image_height(const ZenImage* img) {
    return img ? img->height : 0;
}

int zen_ffi_image_x(const ZenImage* img) {
    return img ? img->x : 0;
}

int zen_ffi_image_y(const ZenImage* img) {
    return img ? img->y : 0;
}

int zen_ffi_image_tex_width(const ZenImage* img) {
    int tw = 0, th = 0;
    if (img) zen_image_get_texture_size(img, &tw, &th);
    return tw;
}

int zen_ffi_image_tex_height(const ZenImage* img) {
    int tw = 0, th = 0;
    if (img) zen_image_get_texture_size(img, &tw, &th);
    return th;
}

int zen_ffi_image_is_sub(const ZenImage* img) {
    if (!img || !img->texture) return 0;
    if (img->x != 0 || img->y != 0 ||
        img->width != img->texture->width ||
        img->height != img->texture->height) {
        return 1;
    }
    return 0;
}

int zen_ffi_image_msaa_samples(const ZenImage* img) {
    return img ? img->msaa_samples : 0;
}

void zen_ffi_image_set_pixel_rgba(ZenImage* img, int x, int y, int r, int g, int b, int a) {
    if (!img) return;
    uint32_t col = ((uint32_t)(a & 0xFF) << 24) |
                   ((uint32_t)(b & 0xFF) << 16) |
                   ((uint32_t)(g & 0xFF) << 8)  |
                   (uint32_t)(r & 0xFF);
    zen_image_set_pixel(img, x, y, col);
}

void zen_ffi_image_set_pixels(ZenImage* img, const void* in_pixels) {
    if (img && in_pixels) {
        zen_image_set_pixels(img, (const uint32_t*)in_pixels);
    }
}

/* ==========================================
 * Shader Helpers
 * ========================================== */
ZenShader* zen_ffi_shader_create(const char* vert_src, const char* frag_src) {
    const char* v = (vert_src && vert_src[0]) ? vert_src : NULL;
    const char* f = (frag_src && frag_src[0]) ? frag_src : NULL;
    return zen_shader_create(v, f);
}

void zen_ffi_shader_set_vec4_array(ZenShader* shader, const char* name, int count, const void* data) {
    if (shader && data && count > 0) {
        zen_shader_set_vec4_array(shader, name, count, (const float*)data);
    }
}

void zen_ffi_shader_set_mat4(ZenShader* shader, const char* name, const void* data) {
    if (shader && data) {
        zen_shader_set_mat4(shader, name, (const float*)data);
    }
}

/* ==========================================
 * Mesh & Renderer Helpers
 * ========================================== */
ZenMesh* zen_ffi_mesh_create(
    int topology,
    const void* layout,
    const void* vdata,
    int vbytes,
    int vcount,
    const void* idata,
    int icount,
    int dynamic
) {
    const uint8_t* lay = (const uint8_t*)layout;
    ZenMesh* mesh = zen_mesh_create(
        topology,
        (lay && lay[0]) ? lay : NULL,
        (vbytes > 0 && vdata) ? vdata : NULL,
        (size_t)(vbytes > 0 ? vbytes : 0),
        vcount,
        (icount > 0 && idata) ? (const uint32_t*)idata : NULL,
        icount
    );
    if (mesh && dynamic) {
        mesh->is_dynamic = 1;
    }
    return mesh;
}

void zen_ffi_mesh_update_vertices(ZenMesh* mesh, int offset_bytes, const void* vdata, int vbytes, int vcount) {
    if (mesh && vdata && vbytes > 0) {
        zen_mesh_update_vertices(mesh, (size_t)(offset_bytes >= 0 ? offset_bytes : 0), vdata, (size_t)vbytes, vcount);
    }
}

void zen_ffi_mesh_update_indices(ZenMesh* mesh, const void* idata, int icount) {
    if (mesh) {
        zen_mesh_update_indices(mesh, (icount > 0 && idata) ? (const uint32_t*)idata : NULL, icount);
    }
}

int zen_ffi_mesh_is_dynamic(const ZenMesh* mesh) {
    return (mesh && mesh->is_dynamic) ? 1 : 0;
}

int zen_ffi_mesh_vertex_count(const ZenMesh* mesh) {
    return mesh ? mesh->vertex_count : 0;
}

int zen_ffi_mesh_index_count(const ZenMesh* mesh) {
    return mesh ? mesh->index_count : 0;
}

void zen_ffi_draw_buffer(
    int topology,
    const void* layout,
    const void* divisors,
    int base_vertex_count,
    const void* vertex_data,
    int count,
    ZenImage* texture,
    ZenShader* shader
) {
    const uint8_t* lay = (const uint8_t*)layout;
    const uint8_t* div = (const uint8_t*)divisors;
    zen_draw_buffer(
        topology,
        (lay && lay[0]) ? lay : NULL,
        (div && div[0]) ? div : NULL,
        base_vertex_count,
        vertex_data,
        count,
        texture,
        shader
    );
}

void zen_ffi_draw_mesh(
    ZenMesh* geom_mesh,
    ZenMesh* inst_buffer,
    const void* inst_layout,
    const void* inst_data,
    int instance_count,
    ZenImage* texture,
    ZenShader* shader
) {
    const uint8_t* ilay = (const uint8_t*)inst_layout;
    zen_draw_mesh_instanced(
        geom_mesh,
        inst_buffer,
        (ilay && ilay[0]) ? ilay : NULL,
        (instance_count > 0 && inst_data) ? inst_data : NULL,
        instance_count,
        texture,
        shader
    );
}

/* ==========================================
 * Font & Glyph Cache Helpers
 * ========================================== */
int zen_ffi_font_query_glyph(ZenFont* font, int codepoint, float font_size, int mode, float render_scale) {
    if (!font) {
        memset(&s_ffi_glyph_cache, 0, sizeof(s_ffi_glyph_cache));
        return 0;
    }
    return zen_font_get_glyph(font, codepoint, font_size, mode, render_scale, &s_ffi_glyph_cache) ? 1 : 0;
}

int   zen_ffi_glyph_visible(void)   { return s_ffi_glyph_cache.visible ? 1 : 0; }
float zen_ffi_glyph_u0(void)        { return s_ffi_glyph_cache.u0; }
float zen_ffi_glyph_v0(void)        { return s_ffi_glyph_cache.v0; }
float zen_ffi_glyph_u1(void)        { return s_ffi_glyph_cache.u1; }
float zen_ffi_glyph_v1(void)        { return s_ffi_glyph_cache.v1; }
float zen_ffi_glyph_x0(void)        { return s_ffi_glyph_cache.x0; }
float zen_ffi_glyph_y0(void)        { return s_ffi_glyph_cache.y0; }
float zen_ffi_glyph_x1(void)        { return s_ffi_glyph_cache.x1; }
float zen_ffi_glyph_y1(void)        { return s_ffi_glyph_cache.y1; }
float zen_ffi_glyph_advance(void)   { return s_ffi_glyph_cache.advance_x; }
int   zen_ffi_glyph_is_bitmap(void) { return s_ffi_glyph_cache.is_bitmap ? 1 : 0; }

float zen_ffi_font_ascent(ZenFont* font, float font_size) {
    float ascent = 0.0f;
    if (font) zen_font_get_metrics(font, font_size, &ascent, NULL, NULL);
    return ascent;
}

float zen_ffi_font_descent(ZenFont* font, float font_size) {
    float descent = 0.0f;
    if (font) zen_font_get_metrics(font, font_size, NULL, &descent, NULL);
    return descent;
}

float zen_ffi_font_line_gap(ZenFont* font, float font_size) {
    float line_gap = 0.0f;
    if (font) zen_font_get_metrics(font, font_size, NULL, NULL, &line_gap);
    return line_gap;
}

/* ==========================================
 * Sound Helpers
 * ========================================== */
ZenSound* zen_ffi_sound_load_pcm(const void* pcm_data, int frame_count, int channels, int sample_rate) {
    if (!pcm_data || frame_count <= 0) return NULL;
    return zen_sound_load_memory_pcm((const float*)pcm_data, frame_count, channels, sample_rate);
}

int64_t zen_ffi_sound_get_length_pcm(const ZenSound* sound) {
    return sound ? (int64_t)zen_sound_get_length_pcm(sound) : 0;
}

void zen_ffi_sound_set_loop_points_pcm(ZenSound* sound, int64_t start_frame, int64_t end_frame) {
    if (sound) {
        zen_sound_set_loop_points_pcm(sound, (uint64_t)(start_frame >= 0 ? start_frame : 0),
                                      (uint64_t)(end_frame >= 0 ? end_frame : 0));
    }
}

float zen_ffi_sound_get_loop_start_sec(const ZenSound* sound) {
    float s = 0.0f;
    if (sound) zen_sound_get_loop_points_seconds(sound, &s, NULL);
    return s;
}

float zen_ffi_sound_get_loop_end_sec(const ZenSound* sound) {
    float e = 0.0f;
    if (sound) zen_sound_get_loop_points_seconds(sound, NULL, &e);
    return e;
}

void zen_ffi_sound_set_loop_start_sec(ZenSound* sound, float start_sec) {
    if (sound) {
        float e = 0.0f;
        zen_sound_get_loop_points_seconds(sound, NULL, &e);
        zen_sound_set_loop_points_seconds(sound, start_sec, e);
    }
}

void zen_ffi_sound_set_loop_end_sec(ZenSound* sound, float end_sec) {
    if (sound) {
        float s = 0.0f;
        zen_sound_get_loop_points_seconds(sound, &s, NULL);
        zen_sound_set_loop_points_seconds(sound, s, end_sec);
    }
}

int64_t zen_ffi_sound_get_loop_start_pcm(const ZenSound* sound) {
    uint64_t s = 0;
    if (sound) zen_sound_get_loop_points_pcm(sound, &s, NULL);
    return (int64_t)s;
}

int64_t zen_ffi_sound_get_loop_end_pcm(const ZenSound* sound) {
    uint64_t e = 0;
    if (sound) zen_sound_get_loop_points_pcm(sound, NULL, &e);
    return (int64_t)e;
}

void zen_ffi_sound_set_loop_start_pcm(ZenSound* sound, int64_t start_pcm) {
    if (sound) {
        uint64_t e = 0;
        zen_sound_get_loop_points_pcm(sound, NULL, &e);
        zen_sound_set_loop_points_pcm(sound, (uint64_t)(start_pcm >= 0 ? start_pcm : 0), e);
    }
}

void zen_ffi_sound_set_loop_end_pcm(ZenSound* sound, int64_t end_pcm) {
    if (sound) {
        uint64_t s = 0;
        zen_sound_get_loop_points_pcm(sound, &s, NULL);
        zen_sound_set_loop_points_pcm(sound, s, (uint64_t)(end_pcm >= 0 ? end_pcm : 0));
    }
}

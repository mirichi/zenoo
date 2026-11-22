/*
 * C Rendering Backend & Zero-Pack Hotpath Queue (src/zenoo_batch.c)
 *
 * Replaces Ruby Backend draw queue, Z-sort, dynamic batching, clip stack,
 * on-demand offscreen FBO flush, uniform arena, and snapshot buffers with C.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "zenoo.h"

#define ZEN_MAX_PIPELINES    64
#define ZEN_MAX_EXEC_DEPTH   32
#define ZEN_LAYOUT_CAP       16

typedef struct ZenPipelineDef {
    int        topology;
    uint8_t    layout[ZEN_LAYOUT_CAP];
    uint8_t    divisors[ZEN_LAYOUT_CAP];
    int        base_vertex_count;
    ZenShader* default_shader;
    int        initialized;
} ZenPipelineDef;

typedef struct ZenDrawCmd {
    ZenImage*  target;
    float      z;
    int        order;
    int        pipeline_id;
    uint32_t   data_offset;
    uint32_t   data_bytes;
    int        count;
    ZenImage*  image;
    ZenShader* shader;
    uint32_t   uniform_offset;
    uint32_t   uniform_bytes;
    int        blend;
    int        has_clip;
    float      clip_x;
    float      clip_y;
    float      clip_w;
    float      clip_h;
    ZenMesh*   mesh;
    ZenMesh*   inst_buffer;
} ZenDrawCmd;

typedef struct ZenDrawQueue {
    ZenImage*   owner;
    ZenDrawCmd* cmds;
    int         count;
    int         cap;
    int         needs_z_sort;
    int         is_flushing;
    int         auto_clear;
    int         has_clear;
    uint32_t    clear_color;
    int         cleared_this_frame;
} ZenDrawQueue;

typedef struct ZenClipCtx {
    float        x, y, w, h;
    float        z;
    ZenDrawQueue queue;
} ZenClipCtx;

typedef enum ZenUniformTag {
    ZEN_UNI_INT        = 1,
    ZEN_UNI_FLOAT      = 2,
    ZEN_UNI_VEC2       = 3,
    ZEN_UNI_VEC3       = 4,
    ZEN_UNI_VEC4       = 5,
    ZEN_UNI_MAT4       = 6,
    ZEN_UNI_VEC4_ARRAY = 7,
    ZEN_UNI_TEXTURE    = 8
} ZenUniformTag;

typedef struct ZenUniformHeader {
    uint8_t  tag;
    uint8_t  name_len;
    uint16_t count;
    uint32_t data_bytes;
} ZenUniformHeader;

struct ZenSnapshot {
    ZenDrawCmd* cmds;
    int         count;
    int         cap;
    uint8_t*    vbuf;
    uint32_t    vbytes;
    uint32_t    vcap;
    uint8_t*    ubuf;
    uint32_t    ubytes;
    uint32_t    ucap;
};

/* ==========================================
 * Static Engine Batch State
 * ========================================== */
static ZenPipelineDef s_pipelines[ZEN_MAX_PIPELINES];
static int            s_pipeline_count = 0;
static int            s_builtin_inited = 0;

static uint8_t*       s_vertex_arena = NULL;
static uint32_t       s_vertex_used  = 0;
static uint32_t       s_vertex_cap   = 0;

static uint8_t*       s_uniform_arena = NULL;
static uint32_t       s_uniform_used  = 0;
static uint32_t       s_uniform_cap   = 0;
static uint32_t       s_uniform_staging_start = 0;
static int            s_uniform_staging_active = 0;

static ZenDrawQueue   s_screen_queue = { NULL, NULL, 0, 0, 0, 0, 1, 0, 0, 0 };

static ZenDrawQueue*  s_target_queues = NULL;
static int            s_target_count  = 0;
static int            s_target_cap    = 0;

static ZenImage**     s_pending_images = NULL;
static int            s_pending_count  = 0;
static int            s_pending_cap    = 0;

static ZenImage*      s_current_target   = NULL;
static ZenImage*      s_active_gl_target = NULL;

static ZenClipCtx*    s_clip_stack = NULL;
static int            s_clip_depth = 0;
static int            s_clip_cap   = 0;

typedef struct ZenBatchBuf {
    uint8_t* data;
    uint32_t cap;
} ZenBatchBuf;

static ZenBatchBuf    s_batch_buffers[ZEN_MAX_EXEC_DEPTH];
static int            s_exec_depth = 0;
static int            s_skip_ondemand_flush = 0;
static int            s_last_draw_calls = 0;

/* Hotpath Staging State */
static float s_card_rgba[12];  /* fill(4), border(4), shadow(4) */
static float s_card_params[11];/* rad, b_width, s_blur, mode, uv(4), rot_rad, pv(2) */
static float s_sprite_color[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
static int   s_sprite_color_staged = 0;
static float s_tri_rgba[12];   /* c1(4), c2(4), c3(4) */

/* Text Staging State */
static float* s_text_floats = NULL;
static int    s_text_glyphs = 0;
static int    s_text_cap    = 0; /* in glyphs (1 glyph = 28 floats) */
static float  s_txt_c[4];
static float  s_txt_p0[4];
static float  s_txt_p1[4];
static float  s_txt_p2[4];
static float  s_txt_weight = 0.0f;
static float  s_ov_c[4];
static float  s_ov_out_w = 0.0f;
static float  s_ov_out_c[4];
static float  s_ov_weight = 0.0f;

/* ==========================================
 * Pipeline Setup
 * ========================================== */
static void set_builtin_pipe(int id, int topo, const uint8_t* lay, int l_len, const uint8_t* div, int d_len, int base_v) {
    ZenPipelineDef* p = &s_pipelines[id];
    memset(p, 0, sizeof(*p));
    p->topology = topo;
    if (l_len > ZEN_LAYOUT_CAP - 1) l_len = ZEN_LAYOUT_CAP - 1;
    if (d_len > ZEN_LAYOUT_CAP - 1) d_len = ZEN_LAYOUT_CAP - 1;
    if (lay && l_len > 0) memcpy(p->layout, lay, (size_t)l_len);
    if (div && d_len > 0) memcpy(p->divisors, div, (size_t)d_len);
    p->base_vertex_count = base_v;
    p->initialized = 1;
}

static void ensure_builtin_pipelines(void) {
    if (s_builtin_inited) return;
    s_builtin_inited = 1;

    static const uint8_t l_card[8]  = {4,4,4,4,4,4,4,0};
    static const uint8_t d_card[8]  = {1,1,1,1,1,1,1,0};
    static const uint8_t l_spr[5]   = {4,4,4,4,0};
    static const uint8_t d_spr[5]   = {1,1,1,1,0};
    static const uint8_t l_p2c4[3]  = {2,4,0};
    static const uint8_t d_p2c4[3]  = {0,0,0};
    static const uint8_t l_p2u2c[4] = {2,2,4,0};
    static const uint8_t d_p2u2c[4] = {0,0,0,0};

    set_builtin_pipe(ZEN_PIPE_CARD,                    ZEN_TOPOLOGY_TRIANGLE_STRIP, l_card,  7, d_card,  7, 4);
    set_builtin_pipe(ZEN_PIPE_SPRITE,                  ZEN_TOPOLOGY_TRIANGLE_STRIP, l_spr,   4, d_spr,   4, 4);
    set_builtin_pipe(ZEN_PIPE_FONT,                    ZEN_TOPOLOGY_TRIANGLE_STRIP, l_card,  7, d_card,  7, 4);
    set_builtin_pipe(ZEN_PIPE_TRIANGLES,               ZEN_TOPOLOGY_TRIANGLES,      l_p2c4,  2, d_p2c4,  2, 0);
    set_builtin_pipe(ZEN_PIPE_TRIANGLE_STRIP,          ZEN_TOPOLOGY_TRIANGLE_STRIP, l_p2c4,  2, d_p2c4,  2, 0);
    set_builtin_pipe(ZEN_PIPE_LINES,                   ZEN_TOPOLOGY_LINES,          l_p2c4,  2, d_p2c4,  2, 0);
    set_builtin_pipe(ZEN_PIPE_POINTS,                  ZEN_TOPOLOGY_POINTS,         l_p2c4,  2, d_p2c4,  2, 0);
    set_builtin_pipe(ZEN_PIPE_TEXTURED_TRIANGLES,      ZEN_TOPOLOGY_TRIANGLES,      l_p2u2c, 3, d_p2u2c, 3, 0);
    set_builtin_pipe(ZEN_PIPE_TEXTURED_TRIANGLE_STRIP, ZEN_TOPOLOGY_TRIANGLE_STRIP, l_p2u2c, 3, d_p2u2c, 3, 0);
    s_pipeline_count = 9;
}

int zen_batch_register_pipeline(
    int topology,
    const void* layout, int layout_len,
    const void* divisors, int div_len,
    int base_vertex_count,
    ZenShader* default_shader
) {
    ensure_builtin_pipelines();
    if (s_pipeline_count >= ZEN_MAX_PIPELINES) return -1;
    int id = s_pipeline_count++;
    set_builtin_pipe(id, topology, (const uint8_t*)layout, layout_len, (const uint8_t*)divisors, div_len, base_vertex_count);
    s_pipelines[id].default_shader = default_shader;
    return id;
}

void zen_batch_set_pipeline_default_shader(int pipe_id, ZenShader* shader) {
    ensure_builtin_pipelines();
    if (pipe_id >= 0 && pipe_id < s_pipeline_count) {
        s_pipelines[pipe_id].default_shader = shader;
    }
}

/* ==========================================
 * Arenas
 * ========================================== */
static uint32_t alloc_vertex_bytes(uint32_t bytes, float** out_floats) {
    uint32_t aligned = (s_vertex_used + 3u) & ~3u;
    uint32_t needed  = aligned + bytes;
    if (needed > s_vertex_cap) {
        uint32_t new_cap = s_vertex_cap == 0 ? 65536u : s_vertex_cap;
        while (new_cap < needed) {
            new_cap *= 2u;
        }
        uint8_t* grown = (uint8_t*)realloc(s_vertex_arena, new_cap);
        if (!grown) {
            if (out_floats) *out_floats = NULL;
            return UINT32_MAX;
        }
        s_vertex_arena = grown;
        s_vertex_cap   = new_cap;
    }
    s_vertex_used = needed;
    if (out_floats) *out_floats = (float*)(s_vertex_arena + aligned);
    return aligned;
}

static uint32_t alloc_uniform_space(uint32_t bytes) {
    uint32_t aligned = (s_uniform_used + 7u) & ~7u;
    uint32_t needed  = aligned + bytes;
    if (needed > s_uniform_cap) {
        uint32_t new_cap = s_uniform_cap == 0 ? 8192u : s_uniform_cap;
        while (new_cap < needed) {
            new_cap *= 2u;
        }
        uint8_t* grown = (uint8_t*)realloc(s_uniform_arena, new_cap);
        if (!grown) return UINT32_MAX;
        s_uniform_arena = grown;
        s_uniform_cap   = new_cap;
    }
    s_uniform_used = needed;
    return aligned;
}

static void push_uniform_entry(uint8_t tag, const char* name, uint16_t count, const void* payload, uint32_t payload_bytes) {
    if (!name || !s_uniform_staging_active) return;
    size_t nlen_full = strlen(name);
    uint8_t nlen = (uint8_t)(nlen_full > 254 ? 254 : nlen_full);
    uint32_t name_padded = ((uint32_t)nlen + 1u + 7u) & ~7u;
    uint32_t payload_padded = (payload_bytes + 7u) & ~7u;
    uint32_t total = (uint32_t)sizeof(ZenUniformHeader) + name_padded + payload_padded;

    uint32_t off = alloc_uniform_space(total);
    if (off == UINT32_MAX) return;

    uint8_t* dst = s_uniform_arena + off;
    memset(dst, 0, total);
    ZenUniformHeader hdr;
    hdr.tag = tag;
    hdr.name_len = nlen;
    hdr.count = count;
    hdr.data_bytes = payload_bytes;
    memcpy(dst, &hdr, sizeof(hdr));
    memcpy(dst + sizeof(hdr), name, nlen);
    if (payload && payload_bytes > 0) {
        memcpy(dst + sizeof(hdr) + name_padded, payload, payload_bytes);
    }
}

void zen_batch_begin_uniforms(void) {
    s_uniform_staging_start = (s_uniform_used + 7u) & ~7u;
    s_uniform_used = s_uniform_staging_start;
    s_uniform_staging_active = 1;
}

void zen_batch_uniform_int(const char* name, int val) {
    int32_t v = (int32_t)val;
    push_uniform_entry(ZEN_UNI_INT, name, 1, &v, (uint32_t)sizeof(v));
}

void zen_batch_uniform_float(const char* name, float val) {
    push_uniform_entry(ZEN_UNI_FLOAT, name, 1, &val, (uint32_t)sizeof(val));
}

void zen_batch_uniform_vec2(const char* name, float x, float y) {
    float v[2] = { x, y };
    push_uniform_entry(ZEN_UNI_VEC2, name, 1, v, (uint32_t)sizeof(v));
}

void zen_batch_uniform_vec3(const char* name, float x, float y, float z) {
    float v[3] = { x, y, z };
    push_uniform_entry(ZEN_UNI_VEC3, name, 1, v, (uint32_t)sizeof(v));
}

void zen_batch_uniform_vec4(const char* name, float x, float y, float z, float w) {
    float v[4] = { x, y, z, w };
    push_uniform_entry(ZEN_UNI_VEC4, name, 1, v, (uint32_t)sizeof(v));
}

void zen_batch_uniform_mat4(const char* name, const void* mat16_floats) {
    if (!mat16_floats) return;
    push_uniform_entry(ZEN_UNI_MAT4, name, 16, mat16_floats, 16u * (uint32_t)sizeof(float));
}

void zen_batch_uniform_vec4_array(const char* name, int vec4_count, const void* float_data) {
    if (!float_data || vec4_count <= 0) return;
    uint32_t bytes = (uint32_t)vec4_count * 4u * (uint32_t)sizeof(float);
    push_uniform_entry(ZEN_UNI_VEC4_ARRAY, name, (uint16_t)vec4_count, float_data, bytes);
}

void zen_batch_uniform_texture(const char* name, ZenImage* image) {
    uintptr_t ptr = (uintptr_t)image;
    push_uniform_entry(ZEN_UNI_TEXTURE, name, 1, &ptr, (uint32_t)sizeof(ptr));
}

/* ==========================================
 * Queues & Target Lookup
 * ========================================== */
static int same_image_tex(ZenImage* a, ZenImage* b) {
    if (a == b) return 1;
    if (!a || !b) return 0;
    uint32_t ida = zen_image_get_texture_id(a);
    uint32_t idb = zen_image_get_texture_id(b);
    return (ida != 0 && ida == idb) ? 1 : 0;
}

static ZenDrawQueue* queue_for_target(ZenImage* image, int create) {
    if (!image) return &s_screen_queue;
    for (int i = 0; i < s_target_count; i++) {
        if (same_image_tex(s_target_queues[i].owner, image)) {
            return &s_target_queues[i];
        }
    }
    if (!create) return NULL;
    if (s_target_count == s_target_cap) {
        int new_cap = s_target_cap == 0 ? 16 : s_target_cap * 2;
        ZenDrawQueue* grown = (ZenDrawQueue*)realloc(s_target_queues, (size_t)new_cap * sizeof(ZenDrawQueue));
        if (!grown) return NULL;
        s_target_queues = grown;
        s_target_cap = new_cap;
    }
    ZenDrawQueue* q = &s_target_queues[s_target_count++];
    memset(q, 0, sizeof(*q));
    q->owner = image;
    return q;
}

static ZenDrawQueue* active_queue(void) {
    if (s_clip_depth > 0) {
        return &s_clip_stack[s_clip_depth - 1].queue;
    }
    if (s_current_target) {
        return queue_for_target(s_current_target, 1);
    }
    return &s_screen_queue;
}

static int queue_has_pending(const ZenDrawQueue* q) {
    if (!q) return 0;
    return (q->count > 0 || q->has_clear || (q->auto_clear && !q->cleared_this_frame)) ? 1 : 0;
}

static void register_pending_image(ZenImage* img) {
    if (!img) return;
    for (int i = 0; i < s_pending_count; i++) {
        if (same_image_tex(s_pending_images[i], img)) return;
    }
    if (s_pending_count == s_pending_cap) {
        int new_cap = s_pending_cap == 0 ? 16 : s_pending_cap * 2;
        ZenImage** grown = (ZenImage**)realloc(s_pending_images, (size_t)new_cap * sizeof(ZenImage*));
        if (!grown) return;
        s_pending_images = grown;
        s_pending_cap = new_cap;
    }
    s_pending_images[s_pending_count++] = img;
}

static ZenDrawCmd* push_cmd_slot(ZenDrawQueue* q, float z) {
    if (!q) return NULL;
    if (q->count == q->cap) {
        int new_cap = q->cap == 0 ? 256 : q->cap * 2;
        ZenDrawCmd* grown = (ZenDrawCmd*)realloc(q->cmds, (size_t)new_cap * sizeof(ZenDrawCmd));
        if (!grown) return NULL;
        q->cmds = grown;
        q->cap = new_cap;
    }
    if (z != 0.0f) q->needs_z_sort = 1;
    ZenDrawCmd* cmd = &q->cmds[q->count];
    memset(cmd, 0, sizeof(*cmd));
    cmd->target = q->owner;
    cmd->z      = z;
    cmd->order  = q->count;
    if (s_clip_depth > 0) {
        const ZenClipCtx* top = &s_clip_stack[s_clip_depth - 1];
        cmd->has_clip = 1;
        cmd->clip_x = top->x;
        cmd->clip_y = top->y;
        cmd->clip_w = top->w;
        cmd->clip_h = top->h;
    }
    if (s_uniform_staging_active) {
        cmd->uniform_offset = s_uniform_staging_start;
        cmd->uniform_bytes  = (s_uniform_used > s_uniform_staging_start) ? (s_uniform_used - s_uniform_staging_start) : 0u;
        s_uniform_staging_active = 0;
    }
    q->count++;
    if (s_current_target && s_clip_depth == 0) {
        register_pending_image(s_current_target);
    } else if (s_current_target && q->owner == s_current_target) {
        register_pending_image(s_current_target);
    }
    return cmd;
}

static int compare_draw_cmds(const void* pa, const void* pb) {
    const ZenDrawCmd* a = (const ZenDrawCmd*)pa;
    const ZenDrawCmd* b = (const ZenDrawCmd*)pb;
    if (a->z < b->z) return -1;
    if (a->z > b->z) return 1;
    if (a->order < b->order) return -1;
    if (a->order > b->order) return 1;
    return 0;
}

static void sort_queue(ZenDrawQueue* q) {
    if (!q || !q->needs_z_sort || q->count <= 1) return;
    qsort(q->cmds, (size_t)q->count, sizeof(ZenDrawCmd), compare_draw_cmds);
}

static void cleanup_empty_target_queues(void) {
    if (s_exec_depth > 0) return;
    for (int i = 0; i < s_target_count; i++) {
        if (s_target_queues[i].is_flushing) return;
    }
    for (int i = s_target_count - 1; i >= 0; i--) {
        if (!s_target_queues[i].is_flushing && !queue_has_pending(&s_target_queues[i])) {
            free(s_target_queues[i].cmds);
            if (i != s_target_count - 1) {
                s_target_queues[i] = s_target_queues[s_target_count - 1];
            }
            s_target_count--;
        }
    }
}

void zen_batch_on_image_destroy(ZenImage* image) {
    if (!image) return;
    if (s_current_target == image) s_current_target = NULL;
    if (s_active_gl_target == image) s_active_gl_target = NULL;
    for (int i = s_pending_count - 1; i >= 0; i--) {
        if (s_pending_images[i] == image) {
            if (i != s_pending_count - 1) {
                s_pending_images[i] = s_pending_images[s_pending_count - 1];
            }
            s_pending_count--;
        }
    }
    for (int i = s_target_count - 1; i >= 0; i--) {
        if (s_target_queues[i].owner == image) {
            free(s_target_queues[i].cmds);
            if (i != s_target_count - 1) {
                s_target_queues[i] = s_target_queues[s_target_count - 1];
            }
            s_target_count--;
        }
    }
}

/* ==========================================
 * Execution & Dynamic Batching
 * ========================================== */
static void apply_command_uniforms(ZenShader* shader, const uint8_t* uarena, uint32_t offset, uint32_t bytes) {
    if (!shader || !uarena || bytes == 0) return;
    int tex_unit = 1;
    uint32_t pos = offset;
    uint32_t end = offset + bytes;

    while (pos + sizeof(ZenUniformHeader) <= end) {
        ZenUniformHeader hdr;
        memcpy(&hdr, uarena + pos, sizeof(hdr));
        uint32_t name_padded = ((uint32_t)hdr.name_len + 1u + 7u) & ~7u;
        uint32_t payload_padded = (hdr.data_bytes + 7u) & ~7u;
        uint32_t entry_size = (uint32_t)sizeof(hdr) + name_padded + payload_padded;
        if (pos + entry_size > end) break;

        const char* name = (const char*)(uarena + pos + sizeof(hdr));
        const uint8_t* payload = uarena + pos + sizeof(hdr) + name_padded;

        switch (hdr.tag) {
            case ZEN_UNI_INT: {
                int32_t v = 0;
                memcpy(&v, payload, sizeof(v));
                zen_shader_set_int(shader, name, (int)v);
                break;
            }
            case ZEN_UNI_FLOAT: {
                float v = 0.0f;
                memcpy(&v, payload, sizeof(v));
                zen_shader_set_float(shader, name, v);
                break;
            }
            case ZEN_UNI_VEC2: {
                float v[2];
                memcpy(v, payload, sizeof(v));
                zen_shader_set_vec2(shader, name, v[0], v[1]);
                break;
            }
            case ZEN_UNI_VEC3: {
                float v[3];
                memcpy(v, payload, sizeof(v));
                zen_shader_set_vec3(shader, name, v[0], v[1], v[2]);
                break;
            }
            case ZEN_UNI_VEC4: {
                float v[4];
                memcpy(v, payload, sizeof(v));
                zen_shader_set_vec4(shader, name, v[0], v[1], v[2], v[3]);
                break;
            }
            case ZEN_UNI_MAT4:
                zen_shader_set_mat4(shader, name, (const float*)payload);
                break;
            case ZEN_UNI_VEC4_ARRAY:
                zen_shader_set_vec4_array(shader, name, (int)hdr.count, (const float*)payload);
                break;
            case ZEN_UNI_TEXTURE: {
                uintptr_t ptr = 0;
                memcpy(&ptr, payload, sizeof(ptr));
                if (tex_unit <= 15) {
                    zen_shader_set_texture(shader, name, tex_unit, (ZenImage*)ptr);
                }
                tex_unit++;
                break;
            }
            default:
                break;
        }
        pos += entry_size;
    }
}

static int flush_uniform_texture_deps(const uint8_t* uarena, uint32_t offset, uint32_t bytes) {
    if (!uarena || bytes == 0) return 0;
    int flushed = 0;
    uint32_t pos = offset;
    uint32_t end = offset + bytes;

    while (pos + sizeof(ZenUniformHeader) <= end) {
        ZenUniformHeader hdr;
        memcpy(&hdr, uarena + pos, sizeof(hdr));
        uint32_t name_padded = ((uint32_t)hdr.name_len + 1u + 7u) & ~7u;
        uint32_t payload_padded = (hdr.data_bytes + 7u) & ~7u;
        uint32_t entry_size = (uint32_t)sizeof(hdr) + name_padded + payload_padded;
        if (pos + entry_size > end) break;

        if (hdr.tag == ZEN_UNI_TEXTURE) {
            const uint8_t* payload = uarena + pos + sizeof(hdr) + name_padded;
            uintptr_t ptr = 0;
            memcpy(&ptr, payload, sizeof(ptr));
            ZenImage* uimg = (ZenImage*)ptr;
            if (uimg && zen_batch_has_pending_draws(uimg)) {
                zen_batch_flush_image(uimg);
                flushed = 1;
            }
        }
        pos += entry_size;
    }
    return flushed;
}

static uint8_t* ensure_batch_buffer(int depth, uint32_t bytes) {
    if (depth < 0 || depth >= ZEN_MAX_EXEC_DEPTH) return NULL;
    ZenBatchBuf* buf = &s_batch_buffers[depth];
    if (bytes > buf->cap) {
        uint32_t new_cap = buf->cap == 0 ? 65536u : buf->cap;
        while (new_cap < bytes) {
            new_cap *= 2u;
        }
        uint8_t* grown = (uint8_t*)realloc(buf->data, new_cap);
        if (!grown) return NULL;
        buf->data = grown;
        buf->cap = new_cap;
    }
    return buf->data;
}

static ZenShader* effective_shader(const ZenDrawCmd* cmd) {
    if (cmd->shader) return cmd->shader;
    if (cmd->pipeline_id >= 0 && cmd->pipeline_id < s_pipeline_count) {
        return s_pipelines[cmd->pipeline_id].default_shader;
    }
    return NULL;
}

static int same_clip(const ZenDrawCmd* a, const ZenDrawCmd* b) {
    if (a->has_clip != b->has_clip) return 0;
    if (!a->has_clip) return 1;
    return (a->clip_x == b->clip_x && a->clip_y == b->clip_y &&
            a->clip_w == b->clip_w && a->clip_h == b->clip_h) ? 1 : 0;
}

static void execute_commands_with_arenas(
    const ZenDrawCmd* cmds, int count,
    const uint8_t* varena, const uint8_t* uarena
) {
    if (!cmds || count <= 0) return;
    ensure_builtin_pipelines();

    int depth = s_exec_depth;
    if (depth >= ZEN_MAX_EXEC_DEPTH) return;
    s_exec_depth = depth + 1;
    if (depth == 0) s_last_draw_calls = 0;

    int   clip_state_inited = 0; /* 0 = :initial */
    int   active_has_clip = 0;
    float active_cx = 0.0f, active_cy = 0.0f, active_cw = 0.0f, active_ch = 0.0f;

    int i = 0;
    while (i < count) {
        const ZenDrawCmd* cmd = &cmds[i];

        if (!s_skip_ondemand_flush) {
            int flushed_dep = 0;
            if (cmd->image && zen_batch_has_pending_draws(cmd->image)) {
                zen_batch_flush_image(cmd->image);
                flushed_dep = 1;
            }
            if (cmd->uniform_bytes > 0 && flush_uniform_texture_deps(uarena, cmd->uniform_offset, cmd->uniform_bytes)) {
                flushed_dep = 1;
            }
            if (flushed_dep) {
                clip_state_inited = 0;
            }
        }

        if (!clip_state_inited || active_has_clip != cmd->has_clip ||
            (cmd->has_clip && (active_cx != cmd->clip_x || active_cy != cmd->clip_y ||
                               active_cw != cmd->clip_w || active_ch != cmd->clip_h))) {
            if (cmd->has_clip) {
                zen_set_scissor((int)cmd->clip_x, (int)cmd->clip_y, (int)cmd->clip_w, (int)cmd->clip_h);
            } else {
                zen_reset_scissor();
            }
            clip_state_inited = 1;
            active_has_clip = cmd->has_clip;
            active_cx = cmd->clip_x;
            active_cy = cmd->clip_y;
            active_cw = cmd->clip_w;
            active_ch = cmd->clip_h;
        }

        const ZenPipelineDef* pipe = (cmd->pipeline_id >= 0 && cmd->pipeline_id < s_pipeline_count)
                                     ? &s_pipelines[cmd->pipeline_id]
                                     : &s_pipelines[ZEN_PIPE_TRIANGLES];
        ZenShader* cur_shader = effective_shader(cmd);
        int cur_count = cmd->count;

        int can_batch = (cmd->data_bytes > 0 && cmd->inst_buffer == NULL) &&
                        (pipe->base_vertex_count > 0 ||
                         pipe->topology == ZEN_TOPOLOGY_TRIANGLES ||
                         pipe->topology == ZEN_TOPOLOGY_LINES ||
                         pipe->topology == ZEN_TOPOLOGY_POINTS);

        int next_idx = i + 1;
        uint32_t total_data_bytes = cmd->data_bytes;
        int all_contiguous = 1;
        uint32_t prev_end = cmd->data_offset + cmd->data_bytes;

        if (can_batch) {
            while (next_idx < count) {
                const ZenDrawCmd* ncmd = &cmds[next_idx];
                if (!s_skip_ondemand_flush && ncmd->image && zen_batch_has_pending_draws(ncmd->image)) {
                    break;
                }
                if (ncmd->pipeline_id != cmd->pipeline_id ||
                    ncmd->mesh != cmd->mesh ||
                    ncmd->inst_buffer != NULL ||
                    ncmd->data_bytes == 0 ||
                    !same_image_tex(ncmd->image, cmd->image) ||
                    effective_shader(ncmd) != cur_shader ||
                    ncmd->uniform_bytes != cmd->uniform_bytes ||
                    (cmd->uniform_bytes > 0 &&
                     memcmp(uarena + cmd->uniform_offset, uarena + ncmd->uniform_offset, cmd->uniform_bytes) != 0) ||
                    ncmd->blend != cmd->blend ||
                    !same_clip(ncmd, cmd)) {
                    break;
                }

                if (ncmd->data_offset != prev_end) {
                    all_contiguous = 0;
                }
                prev_end = ncmd->data_offset + ncmd->data_bytes;
                total_data_bytes += ncmd->data_bytes;
                cur_count += ncmd->count;
                next_idx++;
            }
        }

        const void* final_data = NULL;
        if (cmd->data_bytes > 0 && varena) {
            if (next_idx == i + 1 || all_contiguous) {
                final_data = (const void*)(varena + cmd->data_offset);
            } else {
                uint8_t* dst = ensure_batch_buffer(depth, total_data_bytes);
                if (dst) {
                    uint32_t off = 0;
                    for (int k = i; k < next_idx; k++) {
                        memcpy(dst + off, varena + cmds[k].data_offset, cmds[k].data_bytes);
                        off += cmds[k].data_bytes;
                    }
                    final_data = (const void*)dst;
                }
            }
        }

        zen_set_blend_mode(cmd->blend);
        if (cmd->uniform_bytes > 0) {
            apply_command_uniforms(cur_shader, uarena, cmd->uniform_offset, cmd->uniform_bytes);
        }

        s_last_draw_calls++;
        if (cmd->mesh || cmd->inst_buffer || cmd->pipeline_id == ZEN_PIPE_SPRITE) {
            const uint8_t* inst_layout = final_data ? pipe->layout : NULL;
            zen_draw_mesh_instanced(
                cmd->mesh,
                cmd->inst_buffer,
                (inst_layout && inst_layout[0]) ? inst_layout : NULL,
                final_data,
                cur_count,
                cmd->image,
                cur_shader
            );
        } else {
            zen_draw_buffer(
                pipe->topology,
                pipe->layout,
                pipe->divisors,
                pipe->base_vertex_count,
                final_data,
                cur_count,
                cmd->image,
                cur_shader
            );
        }

        i = next_idx;
    }

    if (clip_state_inited) {
        zen_reset_scissor();
    }
    s_exec_depth = depth;
}

static void flush_queue(ZenDrawQueue* q, uint32_t default_bg_color) {
    if (!q || q->is_flushing || !queue_has_pending(q)) return;

    q->is_flushing = 1;
    sort_queue(q);

    if (q->owner != NULL) {
        ZenImage* old_target = s_active_gl_target;
        ZenImage* prev_ct = q->owner;
        for (int i = 0; i < q->count; i++) {
            ZenImage* ct = q->cmds[i].target;
            if (ct && ct != q->owner && ct != prev_ct) {
                zen_set_render_target(ct);
                prev_ct = ct;
            }
        }
        zen_set_render_target(q->owner);
        s_active_gl_target = q->owner;

        if (q->has_clear) {
            zen_clear(q->clear_color);
            q->has_clear = 0;
        }
        execute_commands_with_arenas(q->cmds, q->count, s_vertex_arena, s_uniform_arena);

        q->count = 0;
        q->needs_z_sort = 0;
        q->is_flushing = 0;

        zen_set_render_target(old_target);
        s_active_gl_target = old_target;
        cleanup_empty_target_queues();
    } else {
        if (q->has_clear) {
            zen_clear(q->clear_color);
            q->has_clear = 0;
            q->cleared_this_frame = 1;
        } else if (q->auto_clear && !q->cleared_this_frame) {
            zen_clear(default_bg_color);
            q->cleared_this_frame = 1;
        }
        execute_commands_with_arenas(q->cmds, q->count, s_vertex_arena, s_uniform_arena);

        q->count = 0;
        q->needs_z_sort = 0;
        q->is_flushing = 0;
    }
}

/* ==========================================
 * Public Lifecycle / Target / Clip API
 * ========================================== */
void zen_batch_reset_frame(void) {
    s_screen_queue.cleared_this_frame = 0;
    s_uniform_staging_active = 0;
    s_sprite_color_staged = 0;
    s_text_glyphs = 0;
}

void zen_batch_mark_screen_cleared(void) {
    s_screen_queue.cleared_this_frame = 1;
}

void zen_batch_set_current_target(ZenImage* target) {
    s_current_target = target;
}

ZenImage* zen_batch_get_current_target(void) {
    return s_current_target;
}

void zen_batch_set_active_gl_target(ZenImage* target) {
    s_active_gl_target = target;
}

ZenImage* zen_batch_get_active_gl_target(void) {
    return s_active_gl_target;
}

void zen_batch_push_clip(float x, float y, float w, float h, float z) {
    if (s_clip_depth == s_clip_cap) {
        int new_cap = s_clip_cap == 0 ? 16 : s_clip_cap * 2;
        ZenClipCtx* grown = (ZenClipCtx*)realloc(s_clip_stack, (size_t)new_cap * sizeof(ZenClipCtx));
        if (!grown) return;
        for (int i = s_clip_cap; i < new_cap; i++) {
            memset(&grown[i], 0, sizeof(ZenClipCtx));
        }
        s_clip_stack = grown;
        s_clip_cap = new_cap;
    }
    ZenClipCtx* ctx = &s_clip_stack[s_clip_depth++];
    ctx->x = x;
    ctx->y = y;
    ctx->w = w;
    ctx->h = h;
    ctx->z = z;
    ctx->queue.owner = s_current_target;
    ctx->queue.count = 0;
    ctx->queue.needs_z_sort = 0;
    ctx->queue.has_clear = 0;
    ctx->queue.auto_clear = 0;
    ctx->queue.is_flushing = 0;
}

void zen_batch_pop_clip(void) {
    if (s_clip_depth <= 0) return;
    ZenClipCtx* ctx = &s_clip_stack[--s_clip_depth];
    ZenDrawQueue* src = &ctx->queue;
    if (src->count <= 0) {
        src->count = 0;
        src->needs_z_sort = 0;
        return;
    }

    sort_queue(src);
    ZenDrawQueue* parent = active_queue();
    if (!parent) {
        src->count = 0;
        src->needs_z_sort = 0;
        return;
    }
    if (ctx->z != 0.0f) {
        parent->needs_z_sort = 1;
    }
    if (parent->count + src->count > parent->cap) {
        int new_cap = parent->cap == 0 ? 256 : parent->cap;
        while (new_cap < parent->count + src->count) {
            new_cap *= 2;
        }
        ZenDrawCmd* grown = (ZenDrawCmd*)realloc(parent->cmds, (size_t)new_cap * sizeof(ZenDrawCmd));
        if (!grown) {
            src->count = 0;
            src->needs_z_sort = 0;
            return;
        }
        parent->cmds = grown;
        parent->cap = new_cap;
    }
    for (int i = 0; i < src->count; i++) {
        ZenDrawCmd c = src->cmds[i];
        c.target = parent->owner;
        c.z      = ctx->z;
        c.order  = parent->count;
        parent->cmds[parent->count++] = c;
    }
    if (parent->owner != NULL) {
        register_pending_image(parent->owner);
    }
    src->count = 0;
    src->needs_z_sort = 0;
}

void zen_batch_clear_clips(void) {
    for (int i = 0; i < s_clip_depth; i++) {
        s_clip_stack[i].queue.count = 0;
        s_clip_stack[i].queue.needs_z_sort = 0;
    }
    s_clip_depth = 0;
}

int zen_batch_has_pending_draws(ZenImage* image) {
    ZenDrawQueue* q = image ? queue_for_target(image, 0) : &s_screen_queue;
    return queue_has_pending(q);
}

void zen_batch_flush_image(ZenImage* image) {
    if (!image) return;
    ZenDrawQueue* q = queue_for_target(image, 0);
    if (q) flush_queue(q, 0);
}

void zen_batch_flush_pending_images(void) {
    if (s_pending_count <= 0) return;

    int count = s_pending_count;
    ZenImage** list = (ZenImage**)malloc((size_t)count * sizeof(ZenImage*));
    if (!list) return;
    memcpy(list, s_pending_images, (size_t)count * sizeof(ZenImage*));
    s_pending_count = 0;

    for (int i = 0; i < count; i++) {
        zen_batch_flush_image(list[i]);
    }
    free(list);
    cleanup_empty_target_queues();
}

void zen_batch_set_clear(uint32_t rgba_color) {
    if (s_current_target) {
        register_pending_image(s_current_target);
        ZenDrawQueue* q = queue_for_target(s_current_target, 1);
        if (q) {
            q->has_clear = 1;
            q->clear_color = rgba_color;
        }
    } else {
        s_screen_queue.has_clear = 1;
        s_screen_queue.clear_color = rgba_color;
    }
}

void zen_batch_flush_screen(uint32_t default_bg_color) {
    s_exec_depth = 0;
    flush_queue(&s_screen_queue, default_bg_color);
    zen_batch_flush_pending_images();
    zen_set_blend_mode(ZEN_BLEND_ALPHA);

    /* Reset per-frame arenas when no draw commands remain queued */
    int any_remaining = (s_screen_queue.count > 0);
    for (int i = 0; i < s_target_count && !any_remaining; i++) {
        if (s_target_queues[i].count > 0) any_remaining = 1;
    }
    for (int i = 0; i < s_clip_depth && !any_remaining; i++) {
        if (s_clip_stack[i].queue.count > 0) any_remaining = 1;
    }
    if (!any_remaining) {
        s_vertex_used = 0;
        s_uniform_used = 0;
        s_uniform_staging_active = 0;
    }
}

void zen_batch_flush_active(uint32_t default_bg_color) {
    ZenDrawQueue* q = active_queue();
    if (q) flush_queue(q, default_bg_color);
}

int zen_batch_last_draw_calls(void) {
    return s_last_draw_calls;
}

int zen_batch_active_queue_count(void) {
    ZenDrawQueue* q = active_queue();
    return q ? q->count : 0;
}

int zen_batch_screen_queue_count(void) {
    return s_screen_queue.count;
}

void zen_batch_sort_screen_queue(void) {
    sort_queue(&s_screen_queue);
}

/* ==========================================
 * Enqueue API (Generic & Zero-Pack Hotpaths)
 * ========================================== */
void zen_batch_enqueue_draw(
    int pipeline_id,
    const void* data, int data_bytes,
    int count,
    ZenImage* image, ZenShader* shader,
    int blend, float z,
    ZenMesh* mesh, ZenMesh* inst_buffer
) {
    uint32_t off = 0;
    uint32_t dbytes = 0;
    if (data && data_bytes > 0) {
        dbytes = (uint32_t)data_bytes;
        float* dst = NULL;
        off = alloc_vertex_bytes(dbytes, &dst);
        if (off == UINT32_MAX || !dst) return;
        memcpy(dst, data, dbytes);
    }

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = pipeline_id;
    cmd->data_offset = off;
    cmd->data_bytes  = dbytes;
    cmd->count       = count;
    cmd->image       = image;
    cmd->shader      = shader;
    cmd->blend       = blend;
    cmd->mesh        = mesh;
    cmd->inst_buffer = inst_buffer;
}

void zen_batch_enqueue_flat_rect(
    float x1, float y1, float x2, float y2,
    float r, float g, float b, float a,
    ZenShader* shader, int blend, float z
) {
    const uint32_t bytes = 36u * (uint32_t)sizeof(float);
    float* v = NULL;
    uint32_t off = alloc_vertex_bytes(bytes, &v);
    if (off == UINT32_MAX || !v) return;

    v[0]=x1; v[1]=y1; v[2]=r;  v[3]=g;  v[4]=b;  v[5]=a;
    v[6]=x1; v[7]=y2; v[8]=r;  v[9]=g;  v[10]=b; v[11]=a;
    v[12]=x2; v[13]=y1; v[14]=r; v[15]=g; v[16]=b; v[17]=a;
    v[18]=x2; v[19]=y1; v[20]=r; v[21]=g; v[22]=b; v[23]=a;
    v[24]=x1; v[25]=y2; v[26]=r; v[27]=g; v[28]=b; v[29]=a;
    v[30]=x2; v[31]=y2; v[32]=r; v[33]=g; v[34]=b; v[35]=a;

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = ZEN_PIPE_TRIANGLES;
    cmd->data_offset = off;
    cmd->data_bytes  = bytes;
    cmd->count       = 6;
    cmd->shader      = shader;
    cmd->blend       = blend;
}

void zen_batch_stage_card_colors(
    float cr, float cg, float cb, float ca,
    float br, float bg, float bb, float ba,
    float sr, float sg, float sb, float sa
) {
    s_card_rgba[0]=cr;  s_card_rgba[1]=cg;  s_card_rgba[2]=cb;  s_card_rgba[3]=ca;
    s_card_rgba[4]=br;  s_card_rgba[5]=bg;  s_card_rgba[6]=bb;  s_card_rgba[7]=ba;
    s_card_rgba[8]=sr;  s_card_rgba[9]=sg;  s_card_rgba[10]=sb; s_card_rgba[11]=sa;
}

void zen_batch_stage_card_params(
    float rad, float b_width, float s_blur, float mode,
    float uv0, float uv1, float uv2, float uv3,
    float rot_rad, float pv_x, float pv_y
) {
    s_card_params[0]=rad;     s_card_params[1]=b_width; s_card_params[2]=s_blur; s_card_params[3]=mode;
    s_card_params[4]=uv0;     s_card_params[5]=uv1;     s_card_params[6]=uv2;    s_card_params[7]=uv3;
    s_card_params[8]=rot_rad; s_card_params[9]=pv_x;    s_card_params[10]=pv_y;
}

void zen_batch_enqueue_sdf_card(
    float x, float y, float w, float h,
    ZenImage* image, ZenShader* shader, int blend, float z
) {
    const uint32_t bytes = 28u * (uint32_t)sizeof(float);
    float* v = NULL;
    uint32_t off = alloc_vertex_bytes(bytes, &v);
    if (off == UINT32_MAX || !v) return;

    v[0]=x;  v[1]=y;  v[2]=w;  v[3]=h;
    v[4]=s_card_rgba[0];  v[5]=s_card_rgba[1];  v[6]=s_card_rgba[2];  v[7]=s_card_rgba[3];
    v[8]=s_card_params[0]; v[9]=s_card_params[1]; v[10]=s_card_params[2]; v[11]=s_card_params[3];
    v[12]=s_card_rgba[4]; v[13]=s_card_rgba[5]; v[14]=s_card_rgba[6]; v[15]=s_card_rgba[7];
    v[16]=s_card_rgba[8]; v[17]=s_card_rgba[9]; v[18]=s_card_rgba[10]; v[19]=s_card_rgba[11];
    v[20]=s_card_params[4]; v[21]=s_card_params[5]; v[22]=s_card_params[6]; v[23]=s_card_params[7];
    v[24]=s_card_params[8]; v[25]=s_card_params[9]; v[26]=s_card_params[10]; v[27]=0.0f;

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = ZEN_PIPE_CARD;
    cmd->data_offset = off;
    cmd->data_bytes  = bytes;
    cmd->count       = 1;
    cmd->image       = image;
    cmd->shader      = shader;
    cmd->blend       = blend;
}

void zen_batch_stage_color(float c0, float c1, float c2, float c3) {
    s_sprite_color[0] = c0;
    s_sprite_color[1] = c1;
    s_sprite_color[2] = c2;
    s_sprite_color[3] = c3;
    s_sprite_color_staged = 1;
}

void zen_batch_enqueue_sprite(
    float m00, float m01, float m10, float m11,
    float tx, float ty,
    ZenImage* image, ZenShader* shader, int blend, float z, ZenMesh* mesh
) {
    const uint32_t bytes = 16u * (uint32_t)sizeof(float);
    float* v = NULL;
    uint32_t off = alloc_vertex_bytes(bytes, &v);
    if (off == UINT32_MAX || !v) {
        s_sprite_color_staged = 0;
        return;
    }

    v[0]=m00; v[1]=m01; v[2]=m10; v[3]=m11;
    v[4]=tx;  v[5]=ty;  v[6]=0.0f; v[7]=0.0f;
    if (s_sprite_color_staged) {
        v[8]=s_sprite_color[0]; v[9]=s_sprite_color[1]; v[10]=s_sprite_color[2]; v[11]=s_sprite_color[3];
        s_sprite_color_staged = 0;
    } else {
        v[8]=1.0f; v[9]=1.0f; v[10]=1.0f; v[11]=1.0f;
    }

    if (image && image->texture && image->texture->width > 0 && image->texture->height > 0) {
        float inv_tw = 1.0f / (float)image->texture->width;
        float inv_th = 1.0f / (float)image->texture->height;
        v[12] = (float)image->x * inv_tw;
        v[13] = (float)image->y * inv_th;
        v[14] = (float)image->width * inv_tw;
        v[15] = (float)image->height * inv_th;
    } else {
        v[12]=0.0f; v[13]=0.0f; v[14]=1.0f; v[15]=1.0f;
    }

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = ZEN_PIPE_SPRITE;
    cmd->data_offset = off;
    cmd->data_bytes  = bytes;
    cmd->count       = 1;
    cmd->image       = image;
    cmd->shader      = shader;
    cmd->blend       = blend;
    cmd->mesh        = mesh;
}

void zen_batch_enqueue_triangle_flat(
    float x1, float y1, float x2, float y2, float x3, float y3,
    float r, float g, float b, float a,
    ZenShader* shader, int blend, float z
) {
    const uint32_t bytes = 18u * (uint32_t)sizeof(float);
    float* v = NULL;
    uint32_t off = alloc_vertex_bytes(bytes, &v);
    if (off == UINT32_MAX || !v) return;

    v[0]=x1;  v[1]=y1;  v[2]=r;  v[3]=g;  v[4]=b;  v[5]=a;
    v[6]=x2;  v[7]=y2;  v[8]=r;  v[9]=g;  v[10]=b; v[11]=a;
    v[12]=x3; v[13]=y3; v[14]=r; v[15]=g; v[16]=b; v[17]=a;

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = ZEN_PIPE_TRIANGLES;
    cmd->data_offset = off;
    cmd->data_bytes  = bytes;
    cmd->count       = 3;
    cmd->shader      = shader;
    cmd->blend       = blend;
}

void zen_batch_stage_tri_colors(
    float r1, float g1, float b1, float a1,
    float r2, float g2, float b2, float a2,
    float r3, float g3, float b3, float a3
) {
    s_tri_rgba[0]=r1; s_tri_rgba[1]=g1; s_tri_rgba[2]=b1;  s_tri_rgba[3]=a1;
    s_tri_rgba[4]=r2; s_tri_rgba[5]=g2; s_tri_rgba[6]=b2;  s_tri_rgba[7]=a2;
    s_tri_rgba[8]=r3; s_tri_rgba[9]=g3; s_tri_rgba[10]=b3; s_tri_rgba[11]=a3;
}

void zen_batch_enqueue_triangle_grad(
    float x1, float y1, float x2, float y2, float x3, float y3,
    ZenShader* shader, int blend, float z
) {
    const uint32_t bytes = 18u * (uint32_t)sizeof(float);
    float* v = NULL;
    uint32_t off = alloc_vertex_bytes(bytes, &v);
    if (off == UINT32_MAX || !v) return;

    v[0]=x1;  v[1]=y1;  v[2]=s_tri_rgba[0];  v[3]=s_tri_rgba[1];  v[4]=s_tri_rgba[2];   v[5]=s_tri_rgba[3];
    v[6]=x2;  v[7]=y2;  v[8]=s_tri_rgba[4];  v[9]=s_tri_rgba[5];  v[10]=s_tri_rgba[6];  v[11]=s_tri_rgba[7];
    v[12]=x3; v[13]=y3; v[14]=s_tri_rgba[8]; v[15]=s_tri_rgba[9]; v[16]=s_tri_rgba[10]; v[17]=s_tri_rgba[11];

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = ZEN_PIPE_TRIANGLES;
    cmd->data_offset = off;
    cmd->data_bytes  = bytes;
    cmd->count       = 3;
    cmd->shader      = shader;
    cmd->blend       = blend;
}

/* ==========================================
 * Fast C Text Staging & Commit
 * ========================================== */
static float* alloc_staged_glyph(void) {
    if (s_text_glyphs == s_text_cap) {
        int new_cap = s_text_cap == 0 ? 256 : s_text_cap * 2;
        float* grown = (float*)realloc(s_text_floats, (size_t)new_cap * 28u * sizeof(float));
        if (!grown) return NULL;
        s_text_floats = grown;
        s_text_cap = new_cap;
    }
    return s_text_floats + (size_t)(s_text_glyphs++) * 28u;
}

static int decode_utf8_char(const unsigned char** p) {
    const unsigned char* s = *p;
    unsigned char c0 = s[0];
    if (c0 < 0x80) {
        *p = s + 1;
        return (int)c0;
    }
    if ((c0 & 0xE0) == 0xC0 && (s[1] & 0xC0) == 0x80) {
        *p = s + 2;
        return ((c0 & 0x1F) << 6) | (s[1] & 0x3F);
    }
    if ((c0 & 0xF0) == 0xE0 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80) {
        *p = s + 3;
        return ((c0 & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
    }
    if ((c0 & 0xF8) == 0xF0 && (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80 && (s[3] & 0xC0) == 0x80) {
        *p = s + 4;
        return ((c0 & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
    }
    *p = s + 1;
    return 0xFFFD;
}

void zen_batch_begin_text(void) {
    s_text_glyphs = 0;
}

void zen_batch_set_text_color_outline(
    float cr, float cg, float cb, float ca,
    float p0_0, float p0_1, float p0_2, float p0_3,
    float p1_0, float p1_1, float p1_2, float p1_3
) {
    s_txt_c[0]=cr;    s_txt_c[1]=cg;    s_txt_c[2]=cb;    s_txt_c[3]=ca;
    s_txt_p0[0]=p0_0; s_txt_p0[1]=p0_1; s_txt_p0[2]=p0_2; s_txt_p0[3]=p0_3;
    s_txt_p1[0]=p1_0; s_txt_p1[1]=p1_1; s_txt_p1[2]=p1_2; s_txt_p1[3]=p1_3;
}

void zen_batch_set_text_shadow_weight(
    float p2_0, float p2_1, float p2_2, float p2_3, float weight
) {
    s_txt_p2[0]=p2_0; s_txt_p2[1]=p2_1; s_txt_p2[2]=p2_2; s_txt_p2[3]=p2_3;
    s_txt_weight = weight;
}

void zen_batch_stage_text_line(
    ZenFont* font, const char* utf8_text,
    float pen_x, float pen_y, float f_size, int mode,
    float vp_scale, float inv_vp_scale
) {
    if (!font || !utf8_text || utf8_text[0] == '\0') return;
    float eff_scale = vp_scale < 1.0f ? 1.0f : vp_scale;
    const unsigned char* p = (const unsigned char*)utf8_text;

    while (*p != '\0') {
        int cp = decode_utf8_char(&p);
        ZenGlyph g;
        int ok = zen_font_get_glyph(font, cp, f_size, mode, eff_scale, &g);
        float adv = ok ? g.advance_x : (f_size * 0.5f);

        if (ok && g.visible) {
            float is_bmp, gx, gy;
            if (g.is_bitmap) {
                is_bmp = 1.0f;
                gx = roundf(pen_x * vp_scale) * inv_vp_scale + g.x0;
                gy = pen_y + g.y0;
            } else {
                is_bmp = 0.0f;
                gx = pen_x + g.x0;
                gy = pen_y + g.y0;
            }
            float* dst = alloc_staged_glyph();
            if (dst) {
                dst[0]=gx; dst[1]=gy; dst[2]=g.x1 - g.x0; dst[3]=g.y1 - g.y0;
                dst[4]=s_txt_c[0];  dst[5]=s_txt_c[1];  dst[6]=s_txt_c[2];  dst[7]=s_txt_c[3];
                dst[8]=s_txt_p0[0]; dst[9]=s_txt_p0[1]; dst[10]=s_txt_p0[2]; dst[11]=s_txt_p0[3];
                dst[12]=s_txt_p1[0]; dst[13]=s_txt_p1[1]; dst[14]=s_txt_p1[2]; dst[15]=s_txt_p1[3];
                dst[16]=s_txt_p2[0]; dst[17]=s_txt_p2[1]; dst[18]=s_txt_p2[2]; dst[19]=s_txt_p2[3];
                dst[20]=s_txt_weight; dst[21]=is_bmp; dst[22]=s_txt_weight; dst[23]=0.0f;
                dst[24]=g.u0; dst[25]=g.v0; dst[26]=g.u1 - g.u0; dst[27]=g.v1 - g.v0;
            }
        }
        pen_x += adv;
    }
}

void zen_batch_set_glyph_override(
    float cr, float cg, float cb, float ca,
    float out_w, float ocr, float ocg, float ocb, float oca, float weight
) {
    s_ov_c[0]=cr; s_ov_c[1]=cg; s_ov_c[2]=cb; s_ov_c[3]=ca;
    s_ov_out_w = out_w;
    s_ov_out_c[0]=ocr; s_ov_out_c[1]=ocg; s_ov_out_c[2]=ocb; s_ov_out_c[3]=oca;
    s_ov_weight = weight;
}

void zen_batch_stage_glyph(
    float gx, float gy, float gw, float gh,
    float is_bmp, float u0, float v0, float uw, float vh, int has_override
) {
    float* dst = alloc_staged_glyph();
    if (!dst) return;
    dst[0]=gx; dst[1]=gy; dst[2]=gw; dst[3]=gh;
    if (has_override) {
        dst[4]=s_ov_c[0];     dst[5]=s_ov_c[1];     dst[6]=s_ov_c[2];     dst[7]=s_ov_c[3];
        dst[8]=s_ov_out_w;    dst[9]=s_txt_p0[1];   dst[10]=s_txt_p0[2];  dst[11]=s_txt_p0[3];
        dst[12]=s_ov_out_c[0]; dst[13]=s_ov_out_c[1]; dst[14]=s_ov_out_c[2]; dst[15]=s_ov_out_c[3];
        dst[20]=s_ov_weight;  dst[21]=is_bmp;       dst[22]=s_ov_weight;  dst[23]=0.0f;
    } else {
        dst[4]=s_txt_c[0];    dst[5]=s_txt_c[1];    dst[6]=s_txt_c[2];    dst[7]=s_txt_c[3];
        dst[8]=s_txt_p0[0];   dst[9]=s_txt_p0[1];   dst[10]=s_txt_p0[2];  dst[11]=s_txt_p0[3];
        dst[12]=s_txt_p1[0];  dst[13]=s_txt_p1[1];  dst[14]=s_txt_p1[2];  dst[15]=s_txt_p1[3];
        dst[20]=s_txt_weight; dst[21]=is_bmp;       dst[22]=s_txt_weight; dst[23]=0.0f;
    }
    dst[16]=s_txt_p2[0]; dst[17]=s_txt_p2[1]; dst[18]=s_txt_p2[2]; dst[19]=s_txt_p2[3];
    dst[24]=u0; dst[25]=v0; dst[26]=uw; dst[27]=vh;
}

int zen_batch_staged_glyph_count(void) {
    return s_text_glyphs;
}

void zen_batch_commit_text(ZenImage* atlas_image, ZenShader* shader, int blend, float z) {
    if (s_text_glyphs <= 0) return;
    int cnt = s_text_glyphs;
    s_text_glyphs = 0;

    uint32_t bytes = (uint32_t)cnt * 28u * (uint32_t)sizeof(float);
    float* dst = NULL;
    uint32_t off = alloc_vertex_bytes(bytes, &dst);
    if (off == UINT32_MAX || !dst) return;
    memcpy(dst, s_text_floats, bytes);

    ZenDrawCmd* cmd = push_cmd_slot(active_queue(), z);
    if (!cmd) return;
    cmd->pipeline_id = ZEN_PIPE_FONT;
    cmd->data_offset = off;
    cmd->data_bytes  = bytes;
    cmd->count       = cnt;
    cmd->image       = atlas_image;
    cmd->shader      = shader;
    cmd->blend       = blend;
}

/* ==========================================
 * Snapshots (Scene transitions / Dev pause)
 * ========================================== */
ZenSnapshot* zen_snapshot_create(void) {
    return (ZenSnapshot*)calloc(1, sizeof(ZenSnapshot));
}

void zen_snapshot_destroy(ZenSnapshot* snap) {
    if (!snap) return;
    free(snap->cmds);
    free(snap->vbuf);
    free(snap->ubuf);
    free(snap);
}

int zen_snapshot_count(const ZenSnapshot* snap) {
    return snap ? snap->count : 0;
}

void zen_snapshot_clear(ZenSnapshot* snap) {
    if (!snap) return;
    snap->count = 0;
    snap->vbytes = 0;
    snap->ubytes = 0;
}

static void capture_queue_range(ZenSnapshot* snap, const ZenDrawQueue* q, int from_index) {
    if (!snap) return;
    if (!q || from_index >= q->count) {
        zen_snapshot_clear(snap);
        return;
    }
    if (from_index < 0) from_index = 0;
    int n = q->count - from_index;

    uint32_t total_v = 0;
    uint32_t total_u = 0;
    for (int i = 0; i < n; i++) {
        const ZenDrawCmd* s = &q->cmds[from_index + i];
        total_v = (total_v + 3u) & ~3u;
        total_v += s->data_bytes;
        total_u = (total_u + 7u) & ~7u;
        total_u += s->uniform_bytes;
    }

    if (n > snap->cap) {
        ZenDrawCmd* grown = (ZenDrawCmd*)realloc(snap->cmds, (size_t)n * sizeof(ZenDrawCmd));
        if (!grown) return;
        snap->cmds = grown;
        snap->cap = n;
    }
    if (total_v > snap->vcap) {
        uint8_t* grown = (uint8_t*)realloc(snap->vbuf, total_v);
        if (!grown) return;
        snap->vbuf = grown;
        snap->vcap = total_v;
    }
    if (total_u > snap->ucap) {
        uint8_t* grown = (uint8_t*)realloc(snap->ubuf, total_u);
        if (!grown) return;
        snap->ubuf = grown;
        snap->ucap = total_u;
    }

    uint32_t vpos = 0;
    uint32_t upos = 0;
    for (int i = 0; i < n; i++) {
        ZenDrawCmd c = q->cmds[from_index + i];
        c.target = NULL;
        if (c.data_bytes > 0 && s_vertex_arena) {
            vpos = (vpos + 3u) & ~3u;
            memcpy(snap->vbuf + vpos, s_vertex_arena + c.data_offset, c.data_bytes);
            c.data_offset = vpos;
            vpos += c.data_bytes;
        } else {
            c.data_offset = 0;
        }
        if (c.uniform_bytes > 0 && s_uniform_arena) {
            upos = (upos + 7u) & ~7u;
            memcpy(snap->ubuf + upos, s_uniform_arena + c.uniform_offset, c.uniform_bytes);
            c.uniform_offset = upos;
            upos += c.uniform_bytes;
        } else {
            c.uniform_offset = 0;
        }
        snap->cmds[i] = c;
    }
    snap->count = n;
    snap->vbytes = vpos;
    snap->ubytes = upos;
}

void zen_snapshot_capture_active(ZenSnapshot* snap, int from_index) {
    capture_queue_range(snap, active_queue(), from_index);
}

void zen_snapshot_capture_screen(ZenSnapshot* snap) {
    sort_queue(&s_screen_queue);
    capture_queue_range(snap, &s_screen_queue, 0);
}

void zen_snapshot_replay_to_active(const ZenSnapshot* snap) {
    if (!snap || snap->count <= 0) return;
    ZenDrawQueue* q = active_queue();
    if (!q) return;

    uint32_t base_voff = 0;
    if (snap->vbytes > 0 && snap->vbuf) {
        float* vdst = NULL;
        base_voff = alloc_vertex_bytes(snap->vbytes, &vdst);
        if (base_voff == UINT32_MAX || !vdst) return;
        memcpy(vdst, snap->vbuf, snap->vbytes);
    }

    uint32_t base_uoff = 0;
    if (snap->ubytes > 0 && snap->ubuf) {
        base_uoff = alloc_uniform_space(snap->ubytes);
        if (base_uoff == UINT32_MAX) return;
        memcpy(s_uniform_arena + base_uoff, snap->ubuf, snap->ubytes);
    }

    if (q->count + snap->count > q->cap) {
        int new_cap = q->cap == 0 ? 256 : q->cap;
        while (new_cap < q->count + snap->count) {
            new_cap *= 2;
        }
        ZenDrawCmd* grown = (ZenDrawCmd*)realloc(q->cmds, (size_t)new_cap * sizeof(ZenDrawCmd));
        if (!grown) return;
        q->cmds = grown;
        q->cap = new_cap;
    }

    for (int i = 0; i < snap->count; i++) {
        ZenDrawCmd c = snap->cmds[i];
        c.target = q->owner;
        c.order  = q->count;
        if (c.z != 0.0f) q->needs_z_sort = 1;
        if (c.data_bytes > 0) c.data_offset += base_voff;
        if (c.uniform_bytes > 0) c.uniform_offset += base_uoff;
        q->cmds[q->count++] = c;
    }
    if (s_current_target) {
        register_pending_image(s_current_target);
    }
}

void zen_snapshot_execute_direct(const ZenSnapshot* snap) {
    if (!snap || snap->count <= 0) return;
    zen_set_render_target(NULL);
    s_skip_ondemand_flush = 1;
    execute_commands_with_arenas(snap->cmds, snap->count, snap->vbuf, snap->ubuf);
    s_skip_ondemand_flush = 0;
}

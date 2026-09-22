#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#ifdef __EMSCRIPTEN__
#include <GLES3/gl3.h>
#else
#include "glad/glad.h"
#endif
#include "zenoo.h"

#define MAX_QUADS 65536

// GPUに送る1つのQuadインスタンスの構造体 (汎用スロット方式)
typedef struct {
    float bounds[4];   // x, y, width, height (location = 1)
    float color[4];    // r, g, b, a (location = 2)
    float param0[4];   // 汎用パラメータスロット 0 (location = 3)
    float param1[4];   // 汎用パラメータスロット 1 (location = 4)
    float param2[4];   // 汎用パラメータスロット 2 (location = 5)
    float uv[4];       // u, v, uw, vh (location = 6)
} GpuQuad;

static GpuQuad s_quad_buffer[MAX_QUADS];
static int s_quad_count = 0;

// 三角形・ライン用 頂点構造体
typedef struct {
    float pos[2];
    float color[4];
} SimpleVertex;

#define MAX_PRIMITIVE_VERTS 16384

static SimpleVertex s_tri_buffer[MAX_PRIMITIVE_VERTS];
static int s_tri_count = 0;
static GLuint s_tri_vao = 0;
static GLuint s_tri_vbo = 0;

static SimpleVertex s_line_buffer[MAX_PRIMITIVE_VERTS];
static int s_line_count = 0;
static GLuint s_line_vao = 0;
static GLuint s_line_vbo = 0;

static GLuint s_simple_program = 0;
static int   s_tri_grad_type = 0; // 0: none, 1: linear, 2: radial
static float s_tri_grad_p0[4] = {0.0f, 0.0f, 0.0f, 0.0f};
static float s_tri_grad_p1[4] = {0.0f, 0.0f, 0.0f, 0.0f};
static float s_tri_grad_color0[4] = {1.0f, 1.0f, 1.0f, 1.0f};
static float s_tri_grad_color1[4] = {1.0f, 1.0f, 1.0f, 1.0f};

typedef enum {
    RENDER_MODE_NONE = 0,
    RENDER_MODE_QUAD,
    RENDER_MODE_TRIANGLE,
    RENDER_MODE_LINE
} RenderMode;

static RenderMode s_current_mode = RENDER_MODE_NONE;

static GLuint s_quad_vao = 0;
static GLuint s_unit_vbo = 0;
static GLuint s_instance_vbo = 0;
static GLuint s_shader_program = 0;

static GLuint s_white_texture = 0;
static GLuint s_active_texture = 0;
static GLuint s_active_program = 0;
static ZenImage* s_current_render_target = NULL;
static void (*s_gc_callback)(void) = NULL;

// ヘルパー: 0xRRGGBBAA -> float[4]
static void color_to_floats(uint32_t c, float out[4]) {
    out[0] = ((c >> 24) & 0xFF) / 255.0f;
    out[1] = ((c >> 16) & 0xFF) / 255.0f;
    out[2] = ((c >> 8)  & 0xFF) / 255.0f;
    out[3] = (c         & 0xFF) / 255.0f;
}

static GLuint compile_shader(GLenum type, const char* source) {
    const char* src_to_compile = source;
#ifdef __EMSCRIPTEN__
    char* patched_source = NULL;
    const char* version_pos = strstr(source, "#version 330 core");
    if (version_pos) {
        size_t prefix_len = version_pos - source;
        const char* rest = version_pos + strlen("#version 330 core");
        const char* header = "#version 300 es\nprecision highp float;\nprecision highp int;\n";
        size_t total_len = prefix_len + strlen(header) + strlen(rest) + 1;
        patched_source = (char*)malloc(total_len);
        if (patched_source) {
            memcpy(patched_source, source, prefix_len);
            strcpy(patched_source + prefix_len, header);
            strcat(patched_source, rest);
            src_to_compile = patched_source;
        }
    }
#endif

    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &src_to_compile, NULL);
    glCompileShader(shader);

#ifdef __EMSCRIPTEN__
    if (patched_source) {
        free(patched_source);
    }
#endif

    GLint status;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (!status) {
        char log[512];
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        fprintf(stderr, "[Zenoo GFX] Shader compile error: %s\n", log);
    }
    return shader;
}

static const char* s_default_vert_src = 
"#version 330 core\n"
"layout (location = 0) in vec2 in_unit_pos;\n"
"layout (location = 1) in vec4 in_bounds;\n"
"layout (location = 2) in vec4 in_color;\n"
"layout (location = 3) in vec4 in_param0;\n"
"layout (location = 4) in vec4 in_param1;\n"
"layout (location = 5) in vec4 in_param2;\n"
"layout (location = 6) in vec4 in_uv;\n"
"uniform vec2 u_resolution;\n"
"out vec4 v_color;\n"
"out vec2 v_uv;\n"
"void main() {\n"
"    vec2 pos = in_bounds.xy + in_unit_pos * in_bounds.zw;\n"
"    vec2 ndc = (pos / u_resolution) * 2.0 - 1.0;\n"
"    ndc.y = -ndc.y;\n"
"    gl_Position = vec4(ndc, 0.0, 1.0);\n"
"    v_color = in_color;\n"
"    v_uv = in_uv.xy + in_unit_pos * in_uv.zw;\n"
"}\n";

static const char* s_default_frag_src =
"#version 330 core\n"
"in vec4 v_color;\n"
"in vec2 v_uv;\n"
"uniform sampler2D u_texture;\n"
"out vec4 fragColor;\n"
"void main() {\n"
"    fragColor = v_color * texture(u_texture, v_uv);\n"
"}\n";

static const char* s_simple_vert_src =
"#version 330 core\n"
"layout (location = 0) in vec2 in_pos;\n"
"layout (location = 1) in vec4 in_color;\n"
"uniform vec2 u_resolution;\n"
"out vec4 v_color;\n"
"out vec2 v_pos;\n"
"void main() {\n"
"    vec2 ndc = (in_pos / u_resolution) * 2.0 - 1.0;\n"
"    ndc.y = -ndc.y;\n"
"    gl_Position = vec4(ndc, 0.0, 1.0);\n"
"    v_color = in_color;\n"
"    v_pos = in_pos;\n"
"}\n";

static const char* s_simple_frag_src =
"#version 330 core\n"
"in vec4 v_color;\n"
"in vec2 v_pos;\n"
"uniform int u_grad_type;\n"
"uniform vec4 u_grad_p0;\n"
"uniform vec4 u_grad_p1;\n"
"uniform vec4 u_grad_color0;\n"
"uniform vec4 u_grad_color1;\n"
"out vec4 fragColor;\n"
"void main() {\n"
"    if (u_grad_type == 1) {\n"
"        vec2 dir = u_grad_p1.xy - u_grad_p0.xy;\n"
"        float len_sq = dot(dir, dir);\n"
"        vec2 dpos = v_pos - u_grad_p0.xy;\n"
"        float t = (len_sq > 0.0001) ? clamp(dot(dpos, dir) / len_sq, 0.0, 1.0) : 0.0;\n"
"        fragColor = mix(u_grad_color0, u_grad_color1, t);\n"
"    } else if (u_grad_type == 2) {\n"
"        vec2 center = u_grad_p0.xy;\n"
"        float r0 = u_grad_p0.z;\n"
"        float r1 = u_grad_p1.z;\n"
"        float d = length(v_pos - center);\n"
"        float dr = r1 - r0;\n"
"        float t = (abs(dr) > 0.0001) ? clamp((d - r0) / dr, 0.0, 1.0) : 0.0;\n"
"        fragColor = mix(u_grad_color0, u_grad_color1, t);\n"
"    } else {\n"
"        fragColor = v_color;\n"
"    }\n"
"}\n";

void zen_gfx_init(int width, int height) {
    (void)width; (void)height;

    GLuint vs = compile_shader(GL_VERTEX_SHADER, s_default_vert_src);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, s_default_frag_src);

    s_shader_program = glCreateProgram();
    glAttachShader(s_shader_program, vs);
    glAttachShader(s_shader_program, fs);
    glLinkProgram(s_shader_program);

    glDeleteShader(vs);
    glDeleteShader(fs);

    // 単色プリミティブ用シェーダー (三角形・ライン)
    GLuint vs_s = compile_shader(GL_VERTEX_SHADER, s_simple_vert_src);
    GLuint fs_s = compile_shader(GL_FRAGMENT_SHADER, s_simple_frag_src);
    s_simple_program = glCreateProgram();
    glAttachShader(s_simple_program, vs_s);
    glAttachShader(s_simple_program, fs_s);
    glLinkProgram(s_simple_program);
    glDeleteShader(vs_s);
    glDeleteShader(fs_s);

    // 1x1 白テクスチャの生成 (単色描画用: テクスチャ未指定時はこれをサンプリング)
    glGenTextures(1, &s_white_texture);
    glBindTexture(GL_TEXTURE_2D, s_white_texture);
    uint32_t white_pixel = 0xFFFFFFFF;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, &white_pixel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    s_active_texture = s_white_texture;

    static const float unit_quad[] = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
    };

    glGenVertexArrays(1, &s_quad_vao);
    glBindVertexArray(s_quad_vao);

    glGenBuffers(1, &s_unit_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s_unit_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(unit_quad), unit_quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), (void*)0);

    glGenBuffers(1, &s_instance_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s_instance_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(GpuQuad) * MAX_QUADS, NULL, GL_DYNAMIC_DRAW);

    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(GpuQuad), (void*)offsetof(GpuQuad, bounds));
    glVertexAttribDivisor(1, 1);

    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(GpuQuad), (void*)offsetof(GpuQuad, color));
    glVertexAttribDivisor(2, 1);

    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, sizeof(GpuQuad), (void*)offsetof(GpuQuad, param0));
    glVertexAttribDivisor(3, 1);

    glEnableVertexAttribArray(4);
    glVertexAttribPointer(4, 4, GL_FLOAT, GL_FALSE, sizeof(GpuQuad), (void*)offsetof(GpuQuad, param1));
    glVertexAttribDivisor(4, 1);

    glEnableVertexAttribArray(5);
    glVertexAttribPointer(5, 4, GL_FLOAT, GL_FALSE, sizeof(GpuQuad), (void*)offsetof(GpuQuad, param2));
    glVertexAttribDivisor(5, 1);

    glEnableVertexAttribArray(6);
    glVertexAttribPointer(6, 4, GL_FLOAT, GL_FALSE, sizeof(GpuQuad), (void*)offsetof(GpuQuad, uv));
    glVertexAttribDivisor(6, 1);

    glBindVertexArray(0);

    // 三角形バッファ初期化
    glGenVertexArrays(1, &s_tri_vao);
    glBindVertexArray(s_tri_vao);
    glGenBuffers(1, &s_tri_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s_tri_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SimpleVertex) * MAX_PRIMITIVE_VERTS, NULL, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(SimpleVertex), (void*)offsetof(SimpleVertex, pos));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(SimpleVertex), (void*)offsetof(SimpleVertex, color));
    glBindVertexArray(0);

    // ラインバッファ初期化
    glGenVertexArrays(1, &s_line_vao);
    glBindVertexArray(s_line_vao);
    glGenBuffers(1, &s_line_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s_line_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SimpleVertex) * MAX_PRIMITIVE_VERTS, NULL, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(SimpleVertex), (void*)offsetof(SimpleVertex, pos));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(SimpleVertex), (void*)offsetof(SimpleVertex, color));
    glBindVertexArray(0);
}

void zen_gfx_shutdown(void) {
    if (s_white_texture) glDeleteTextures(1, &s_white_texture);
    if (s_unit_vbo) glDeleteBuffers(1, &s_unit_vbo);
    if (s_instance_vbo) glDeleteBuffers(1, &s_instance_vbo);
    if (s_quad_vao) glDeleteVertexArrays(1, &s_quad_vao);
    if (s_shader_program) glDeleteProgram(s_shader_program);

    if (s_tri_vbo) glDeleteBuffers(1, &s_tri_vbo);
    if (s_tri_vao) glDeleteVertexArrays(1, &s_tri_vao);
    if (s_line_vbo) glDeleteBuffers(1, &s_line_vbo);
    if (s_line_vao) glDeleteVertexArrays(1, &s_line_vao);
    if (s_simple_program) glDeleteProgram(s_simple_program);
}

void zen_gfx_begin(uint32_t clear_color, int width, int height) {
    // オフスクリーン描画ターゲットの場合のみビューポートとクリアを実行
    if (s_current_render_target) {
        glViewport(0, 0, s_current_render_target->width, s_current_render_target->height);
        float clr[4];
        color_to_floats(clear_color, clr);
        glClearColor(clr[0], clr[1], clr[2], clr[3]);
        glClear(GL_COLOR_BUFFER_BIT);
    } else {
        (void)width; (void)height; (void)clear_color;
    }

    glEnable(GL_BLEND);
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    s_quad_count = 0;
    s_tri_count = 0;
    s_line_count = 0;
    s_current_mode = RENDER_MODE_NONE;
    s_active_program = s_shader_program;
    s_active_texture = s_white_texture;
}

static void flush_quads(void) {
    if (s_quad_count == 0) return;

    int cur_w, cur_h;
    if (s_current_render_target) {
        cur_w = s_current_render_target->width;
        cur_h = s_current_render_target->height;
    } else {
        zen_get_window_size(&cur_w, &cur_h);
    }

    GLuint prog = (s_active_program != 0) ? s_active_program : s_shader_program;
    glUseProgram(prog);

    GLint u_res = glGetUniformLocation(prog, "u_resolution");
    if (u_res >= 0) {
        glUniform2f(u_res, (float)cur_w, (float)cur_h);
    }

    GLint u_tex = glGetUniformLocation(prog, "u_texture");
    if (u_tex >= 0) {
        glUniform1i(u_tex, 0);
    }

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, s_active_texture);

    glBindVertexArray(s_quad_vao);

    glBindBuffer(GL_ARRAY_BUFFER, s_instance_vbo);
    // Buffer Orphaning: GPUの描画完了待ち(ストール)を完全に排除するため、
    // 古いバッファ領域を破棄して即座に新しいメモリを確保する
    glBufferData(GL_ARRAY_BUFFER, sizeof(GpuQuad) * MAX_QUADS, NULL, GL_STREAM_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(GpuQuad) * s_quad_count, s_quad_buffer);

    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, s_quad_count);

    glBindVertexArray(0);
    s_quad_count = 0;
}

static void flush_triangles(void) {
    if (s_tri_count == 0) return;

    int cur_w, cur_h;
    if (s_current_render_target) {
        cur_w = s_current_render_target->width;
        cur_h = s_current_render_target->height;
    } else {
        zen_get_window_size(&cur_w, &cur_h);
    }

    glUseProgram(s_simple_program);
    GLint u_res = glGetUniformLocation(s_simple_program, "u_resolution");
    if (u_res >= 0) {
        glUniform2f(u_res, (float)cur_w, (float)cur_h);
    }

    glUniform1i(glGetUniformLocation(s_simple_program, "u_grad_type"), s_tri_grad_type);
    if (s_tri_grad_type > 0) {
        glUniform4f(glGetUniformLocation(s_simple_program, "u_grad_p0"),
                    s_tri_grad_p0[0], s_tri_grad_p0[1], s_tri_grad_p0[2], s_tri_grad_p0[3]);
        glUniform4f(glGetUniformLocation(s_simple_program, "u_grad_p1"),
                    s_tri_grad_p1[0], s_tri_grad_p1[1], s_tri_grad_p1[2], s_tri_grad_p1[3]);
        glUniform4f(glGetUniformLocation(s_simple_program, "u_grad_color0"),
                    s_tri_grad_color0[0], s_tri_grad_color0[1], s_tri_grad_color0[2], s_tri_grad_color0[3]);
        glUniform4f(glGetUniformLocation(s_simple_program, "u_grad_color1"),
                    s_tri_grad_color1[0], s_tri_grad_color1[1], s_tri_grad_color1[2], s_tri_grad_color1[3]);
    }

    glBindVertexArray(s_tri_vao);
    glBindBuffer(GL_ARRAY_BUFFER, s_tri_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SimpleVertex) * MAX_PRIMITIVE_VERTS, NULL, GL_STREAM_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(SimpleVertex) * s_tri_count, s_tri_buffer);

    glDrawArrays(GL_TRIANGLES, 0, s_tri_count);

    glBindVertexArray(0);
    s_tri_count = 0;
}

static void flush_lines(void) {
    if (s_line_count == 0) return;

    int cur_w, cur_h;
    if (s_current_render_target) {
        cur_w = s_current_render_target->width;
        cur_h = s_current_render_target->height;
    } else {
        zen_get_window_size(&cur_w, &cur_h);
    }

    glUseProgram(s_simple_program);
    GLint u_res = glGetUniformLocation(s_simple_program, "u_resolution");
    if (u_res >= 0) {
        glUniform2f(u_res, (float)cur_w, (float)cur_h);
    }
    glUniform1i(glGetUniformLocation(s_simple_program, "u_grad_type"), 0);

    glBindVertexArray(s_line_vao);
    glBindBuffer(GL_ARRAY_BUFFER, s_line_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(SimpleVertex) * MAX_PRIMITIVE_VERTS, NULL, GL_STREAM_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(SimpleVertex) * s_line_count, s_line_buffer);

    glDrawArrays(GL_LINES, 0, s_line_count);

    glBindVertexArray(0);
    s_line_count = 0;
}

void zen_gfx_flush(void) {
    if (s_quad_count > 0) flush_quads();
    if (s_tri_count > 0) flush_triangles();
    if (s_line_count > 0) flush_lines();
    s_current_mode = RENDER_MODE_NONE;
}

static void set_render_mode(RenderMode mode) {
    if (s_current_mode != mode) {
        zen_gfx_flush();
        s_current_mode = mode;
    }
}

static void bind_texture(GLuint tex_id) {
    GLuint target_tex = (tex_id != 0) ? tex_id : s_white_texture;
    if (s_active_texture != target_tex) {
        zen_gfx_flush();
        s_active_texture = target_tex;
    }
}

static void push_quad(const GpuQuad* q) {
    set_render_mode(RENDER_MODE_QUAD);
    if (s_quad_count >= MAX_QUADS) {
        flush_quads();
    }
    s_quad_buffer[s_quad_count++] = *q;
}

// ==========================================
// 画像 (Image) & オフスクリーン描画実装
// ==========================================
ZenImage* zen_image_create(int width, int height) {
    if (width <= 0 || height <= 0) return NULL;

    ZenImage* img = (ZenImage*)calloc(1, sizeof(ZenImage));
    if (!img && s_gc_callback) {
        // メモリ不足: RubyのGCをトリガーして再試行
        s_gc_callback();
        img = (ZenImage*)calloc(1, sizeof(ZenImage));
    }
    if (!img) return NULL;

    img->width = width;
    img->height = height;

    glGenTextures(1, &img->texture_id);
    if (!img->texture_id && s_gc_callback) {
        s_gc_callback();
        glGenTextures(1, &img->texture_id);
    }

    glBindTexture(GL_TEXTURE_2D, img->texture_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

    return img;
}

ZenImage* zen_image_create_from_pixels(int width, int height, const uint32_t* pixels) {
    if (width <= 0 || height <= 0 || !pixels) return NULL;

    ZenImage* img = (ZenImage*)calloc(1, sizeof(ZenImage));
    if (!img && s_gc_callback) {
        s_gc_callback();
        img = (ZenImage*)calloc(1, sizeof(ZenImage));
    }
    if (!img) return NULL;

    img->width = width;
    img->height = height;

    glGenTextures(1, &img->texture_id);
    if (!img->texture_id && s_gc_callback) {
        s_gc_callback();
        glGenTextures(1, &img->texture_id);
    }

    glBindTexture(GL_TEXTURE_2D, img->texture_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    return img;
}

ZenImage* zen_image_load(const char* filepath) {
    if (!filepath) return NULL;

    int w, h, channels;
    stbi_set_flip_vertically_on_load(0);
    unsigned char* data = stbi_load(filepath, &w, &h, &channels, 4);
    if (!data) {
        fprintf(stderr, "[Zenoo Image] Failed to load image: %s (%s)\n", filepath, stbi_failure_reason());
        return NULL;
    }

    ZenImage* img = zen_image_create_from_pixels(w, h, (const uint32_t*)data);
    stbi_image_free(data);
    return img;
}

void zen_image_destroy(ZenImage* image) {
    if (!image) return;
    zen_gfx_flush();

    if (s_current_render_target == image) {
        zen_set_render_target(NULL);
    }
    if (s_active_texture == image->texture_id) {
        s_active_texture = s_white_texture;
    }

    if (image->has_fbo) {
        glDeleteFramebuffers(1, &image->fbo);
    }
    if (image->texture_id) {
        glDeleteTextures(1, &image->texture_id);
    }
    free(image);
}

void zen_image_get_size(const ZenImage* image, int* width, int* height) {
    if (!image) {
        if (width) *width = 0;
        if (height) *height = 0;
        return;
    }
    if (width) *width = image->width;
    if (height) *height = image->height;
}

void zen_set_render_target(ZenImage* target) {
    zen_gfx_flush();

    s_current_render_target = target;

    if (target != NULL) {
        if (!target->has_fbo) {
            glGenFramebuffers(1, &target->fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, target->fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target->texture_id, 0);
            target->has_fbo = 1;
        } else {
            glBindFramebuffer(GL_FRAMEBUFFER, target->fbo);
        }
        glViewport(0, 0, target->width, target->height);
    } else {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        int win_w, win_h;
        zen_get_window_size(&win_w, &win_h);
        glViewport(0, 0, win_w, win_h);
    }
}

// ==========================================
// 汎用シェーダー (ZenShader) API 実装
// ==========================================
struct ZenShader {
    GLuint program_id;
};

ZenShader* zen_shader_create(const char* vert_src, const char* frag_src) {
    const char* vs_code = (vert_src && strlen(vert_src) > 0) ? vert_src : s_default_vert_src;
    const char* fs_code = (frag_src && strlen(frag_src) > 0) ? frag_src : s_default_frag_src;

    GLuint vs = compile_shader(GL_VERTEX_SHADER, vs_code);
    if (!vs) return NULL;
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, fs_code);
    if (!fs) {
        glDeleteShader(vs);
        return NULL;
    }

    GLuint prog = glCreateProgram();
    glAttachShader(prog, vs);
    glAttachShader(prog, fs);
    glLinkProgram(prog);

    GLint status;
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (!status) {
        char log[512];
        glGetProgramInfoLog(prog, sizeof(log), NULL, log);
        fprintf(stderr, "[Zenoo Shader] Link error: %s\n", log);
        glDeleteShader(vs);
        glDeleteShader(fs);
        glDeleteProgram(prog);
        return NULL;
    }

    glDeleteShader(vs);
    glDeleteShader(fs);

    ZenShader* shader = (ZenShader*)malloc(sizeof(ZenShader));
    if (!shader) {
        glDeleteProgram(prog);
        return NULL;
    }
    shader->program_id = prog;
    return shader;
}

static void bind_shader(ZenShader* shader) {
    GLuint prog = shader ? shader->program_id : s_shader_program;
    if (s_active_program != prog) {
        zen_gfx_flush();
        s_active_program = prog;
    }
}

void zen_shader_destroy(ZenShader* shader) {
    if (!shader) return;
    if (s_active_program == shader->program_id) {
        zen_gfx_flush();
        s_active_program = s_shader_program;
    }
    if (shader->program_id) {
        glDeleteProgram(shader->program_id);
    }
    free(shader);
}

void zen_shader_set_int(ZenShader* shader, const char* name, int value) {
    if (!shader) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniform1i(loc, value);
}

void zen_shader_set_float(ZenShader* shader, const char* name, float value) {
    if (!shader) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniform1f(loc, value);
}

void zen_shader_set_vec2(ZenShader* shader, const char* name, float x, float y) {
    if (!shader) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniform2f(loc, x, y);
}

void zen_shader_set_vec3(ZenShader* shader, const char* name, float x, float y, float z) {
    if (!shader) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniform3f(loc, x, y, z);
}

void zen_shader_set_vec4(ZenShader* shader, const char* name, float x, float y, float z, float w) {
    if (!shader) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniform4f(loc, x, y, z, w);
}

void zen_shader_set_mat4(ZenShader* shader, const char* name, const float* mat4) {
    if (!shader || !mat4) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniformMatrix4fv(loc, 1, GL_FALSE, mat4);
}

// ==========================================
// 汎用 Quad バッチ & GC トリガー
// ==========================================

void zen_set_gc_trigger_callback(void (*callback)(void)) {
    s_gc_callback = callback;
}

uint32_t zen_image_get_texture_id(const ZenImage* image) {
    return image ? (uint32_t)image->texture_id : 0;
}

void zen_draw_quad_generic(float x, float y, float w, float h,
                           const float uv[4],
                           const float color[4],
                           const float p0[4],
                           const float p1[4],
                           const float p2[4],
                           ZenImage* texture,
                           ZenShader* shader) {
    bind_shader(shader);

    if (texture) {
        bind_texture(texture->texture_id);
    } else {
        bind_texture(0);
    }

    GpuQuad q;
    q.bounds[0] = x; q.bounds[1] = y; q.bounds[2] = w; q.bounds[3] = h;

    if (uv) memcpy(q.uv, uv, sizeof(float) * 4);
    else { q.uv[0] = 0.0f; q.uv[1] = 0.0f; q.uv[2] = 1.0f; q.uv[3] = 1.0f; }

    if (color) memcpy(q.color, color, sizeof(float) * 4);
    else { q.color[0] = 1.0f; q.color[1] = 1.0f; q.color[2] = 1.0f; q.color[3] = 1.0f; }

    if (p0) memcpy(q.param0, p0, sizeof(float) * 4);
    else memset(q.param0, 0, sizeof(float) * 4);

    if (p1) memcpy(q.param1, p1, sizeof(float) * 4);
    else memset(q.param1, 0, sizeof(float) * 4);

    if (p2) memcpy(q.param2, p2, sizeof(float) * 4);
    else memset(q.param2, 0, sizeof(float) * 4);

    push_quad(&q);
}

void zen_draw_triangle(float x1, float y1, float x2, float y2, float x3, float y3, const float color[4]) {
    if (s_tri_grad_type != 0 && s_tri_count > 0) flush_triangles();
    s_tri_grad_type = 0;
    set_render_mode(RENDER_MODE_TRIANGLE);
    if (s_tri_count + 3 > MAX_PRIMITIVE_VERTS) {
        flush_triangles();
    }
    float c[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
    if (color) memcpy(c, color, sizeof(float) * 4);

    s_tri_buffer[s_tri_count].pos[0] = x1;
    s_tri_buffer[s_tri_count].pos[1] = y1;
    memcpy(s_tri_buffer[s_tri_count].color, c, sizeof(float) * 4);
    s_tri_count++;

    s_tri_buffer[s_tri_count].pos[0] = x2;
    s_tri_buffer[s_tri_count].pos[1] = y2;
    memcpy(s_tri_buffer[s_tri_count].color, c, sizeof(float) * 4);
    s_tri_count++;

    s_tri_buffer[s_tri_count].pos[0] = x3;
    s_tri_buffer[s_tri_count].pos[1] = y3;
    memcpy(s_tri_buffer[s_tri_count].color, c, sizeof(float) * 4);
    s_tri_count++;
}

void zen_draw_triangles(const float* coords, int num_vertices, const float color[4]) {
    if (!coords || num_vertices <= 0) return;
    if (s_tri_grad_type != 0 && s_tri_count > 0) flush_triangles();
    s_tri_grad_type = 0;
    set_render_mode(RENDER_MODE_TRIANGLE);

    float c[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
    if (color) memcpy(c, color, sizeof(float) * 4);

    for (int i = 0; i < num_vertices; i++) {
        if (s_tri_count >= MAX_PRIMITIVE_VERTS) {
            flush_triangles();
        }
        s_tri_buffer[s_tri_count].pos[0] = coords[i * 2 + 0];
        s_tri_buffer[s_tri_count].pos[1] = coords[i * 2 + 1];
        memcpy(s_tri_buffer[s_tri_count].color, c, sizeof(float) * 4);
        s_tri_count++;
    }
}

void zen_draw_triangles_gradient(const float* coords, int num_vertices, int grad_type,
                                const float p0[4], const float p1[4],
                                const float color0[4], const float color1[4]) {
    if (!coords || num_vertices <= 0) return;

    bool param_changed = (s_tri_grad_type != grad_type);
    if (!param_changed && grad_type > 0) {
        if (p0 && memcmp(s_tri_grad_p0, p0, sizeof(float) * 4) != 0) param_changed = true;
        if (p1 && memcmp(s_tri_grad_p1, p1, sizeof(float) * 4) != 0) param_changed = true;
        if (color0 && memcmp(s_tri_grad_color0, color0, sizeof(float) * 4) != 0) param_changed = true;
        if (color1 && memcmp(s_tri_grad_color1, color1, sizeof(float) * 4) != 0) param_changed = true;
    }

    if (param_changed && s_tri_count > 0) {
        flush_triangles();
    }

    set_render_mode(RENDER_MODE_TRIANGLE);
    s_tri_grad_type = grad_type;
    if (p0) memcpy(s_tri_grad_p0, p0, sizeof(float) * 4);
    if (p1) memcpy(s_tri_grad_p1, p1, sizeof(float) * 4);
    if (color0) memcpy(s_tri_grad_color0, color0, sizeof(float) * 4);
    if (color1) memcpy(s_tri_grad_color1, color1, sizeof(float) * 4);

    for (int i = 0; i < num_vertices; i++) {
        if (s_tri_count >= MAX_PRIMITIVE_VERTS) {
            flush_triangles();
        }
        s_tri_buffer[s_tri_count].pos[0] = coords[i * 2 + 0];
        s_tri_buffer[s_tri_count].pos[1] = coords[i * 2 + 1];
        memcpy(s_tri_buffer[s_tri_count].color, s_tri_grad_color0, sizeof(float) * 4);
        s_tri_count++;
    }
}

void zen_draw_line(float x1, float y1, float x2, float y2, const float color[4]) {
    set_render_mode(RENDER_MODE_LINE);
    if (s_line_count + 2 > MAX_PRIMITIVE_VERTS) {
        flush_lines();
    }
    float c[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
    if (color) memcpy(c, color, sizeof(float) * 4);

    s_line_buffer[s_line_count].pos[0] = x1;
    s_line_buffer[s_line_count].pos[1] = y1;
    memcpy(s_line_buffer[s_line_count].color, c, sizeof(float) * 4);
    s_line_count++;

    s_line_buffer[s_line_count].pos[0] = x2;
    s_line_buffer[s_line_count].pos[1] = y2;
    memcpy(s_line_buffer[s_line_count].color, c, sizeof(float) * 4);
    s_line_count++;
}

void zen_flush(void) {
    zen_gfx_flush();
}

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


static GLuint s_dynamic_vao = 0;
static GLuint s_dynamic_vbo = 0;

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

void zen_gfx_init(int width, int height) {
    (void)width; (void)height;

    // 1x1 白テクスチャの生成 (単色描画用: テクスチャ未指定時はこれをサンプリング)
    glGenTextures(1, &s_white_texture);
    glBindTexture(GL_TEXTURE_2D, s_white_texture);
    uint32_t white_pixel = 0xFFFFFFFF;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, &white_pixel);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    s_active_texture = s_white_texture;

    // 汎用動的バッファ初期化
    glGenBuffers(1, &s_dynamic_vbo);
    glGenVertexArrays(1, &s_dynamic_vao);
}

void zen_gfx_shutdown(void) {
    if (s_white_texture) glDeleteTextures(1, &s_white_texture);
    if (s_dynamic_vbo) glDeleteBuffers(1, &s_dynamic_vbo);
    if (s_dynamic_vao) glDeleteVertexArrays(1, &s_dynamic_vao);
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

    s_active_program = 0;
    s_active_texture = s_white_texture;
}

void zen_gfx_flush(void) {
    // マイクロカーネル化により即時描画（draw_buffer）に統一されたため Flush 処理は不要
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
    if (!vert_src || !frag_src || strlen(vert_src) == 0 || strlen(frag_src) == 0) {
        return NULL;
    }

    GLuint vs = compile_shader(GL_VERTEX_SHADER, vert_src);
    if (!vs) return NULL;
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, frag_src);
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



void zen_shader_destroy(ZenShader* shader) {
    if (!shader) return;
    if (s_active_program == shader->program_id) {
        s_active_program = 0;
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

void zen_flush(void) {
    zen_gfx_flush();
}

void zen_draw_buffer(int topology,
                      const uint8_t* layout,
                      const uint8_t* divisors,
                      int base_vertex_count,
                      const void* vertex_data,
                      int count,
                      ZenImage* texture,
                      ZenShader* shader) {
    if (!layout || count <= 0 || !vertex_data || !shader) return;

    // 1. シェーダーの準備
    GLuint prog = shader->program_id;
    glUseProgram(prog);
    s_active_program = prog;

    int cur_w, cur_h;
    if (s_current_render_target) {
        cur_w = s_current_render_target->width;
        cur_h = s_current_render_target->height;
    } else {
        zen_get_window_size(&cur_w, &cur_h);
    }
    GLint u_res = glGetUniformLocation(prog, "u_resolution");
    if (u_res >= 0) {
        glUniform2f(u_res, (float)cur_w, (float)cur_h);
    }

    // 2. テクスチャの準備
    GLuint tex_id = texture ? texture->texture_id : s_white_texture;
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    s_active_texture = tex_id;
    GLint u_tex = glGetUniformLocation(prog, "u_texture");
    if (u_tex >= 0) {
        glUniform1i(u_tex, 0);
    }

    // 3. stride の計算 (1バイト/属性の単純ループ)
    int stride = 0;
    for (int i = 0; layout[i] != 0; i++) {
        stride += (int)layout[i] * (int)sizeof(float);
    }
    if (stride == 0) return;

    size_t total_bytes = (size_t)stride * (size_t)count;

    // 4. VAOとVBOのバインド・データ転送
    glBindVertexArray(s_dynamic_vao);
    glBindBuffer(GL_ARRAY_BUFFER, s_dynamic_vbo);

    // Buffer Orphaning: 同期ストールを完全に排除
    glBufferData(GL_ARRAY_BUFFER, total_bytes, NULL, GL_STREAM_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, total_bytes, vertex_data);

    // 5. 頂点属性の設定 (常に location 0 から開始)
    uintptr_t offset = 0;
    int num_attrs = 0;
    for (int i = 0; layout[i] != 0; i++) {
        int size = (int)layout[i];
        int div = (divisors && divisors[i] != 0) ? (int)divisors[i] : 0;
        glEnableVertexAttribArray(i);
        glVertexAttribPointer(i, size, GL_FLOAT, GL_FALSE, stride, (void*)offset);
        if (div > 0) {
            glVertexAttribDivisor(i, div);
        }
        offset += (size_t)size * sizeof(float);
        num_attrs++;
    }

    // 6. トポロジー判定とドローコール
    GLenum gl_mode;
    switch (topology) {
        case ZEN_TOPOLOGY_POINTS:         gl_mode = GL_POINTS; break;
        case ZEN_TOPOLOGY_LINES:          gl_mode = GL_LINES; break;
        case ZEN_TOPOLOGY_LINE_LOOP:      gl_mode = GL_LINE_LOOP; break;
        case ZEN_TOPOLOGY_LINE_STRIP:     gl_mode = GL_LINE_STRIP; break;
        case ZEN_TOPOLOGY_TRIANGLES:      gl_mode = GL_TRIANGLES; break;
        case ZEN_TOPOLOGY_TRIANGLE_STRIP: gl_mode = GL_TRIANGLE_STRIP; break;
        case ZEN_TOPOLOGY_TRIANGLE_FAN:   gl_mode = GL_TRIANGLE_FAN; break;
        default:                          gl_mode = GL_TRIANGLES; break;
    }

    if (base_vertex_count > 0) {
        glDrawArraysInstanced(gl_mode, 0, base_vertex_count, count);
    } else {
        glDrawArrays(gl_mode, 0, count);
    }

    // 7. クリーンアップ (属性の無効化とDivisorリセット)
    for (int i = 0; i < num_attrs; i++) {
        int div = (divisors && divisors[i] != 0) ? (int)divisors[i] : 0;
        if (div > 0) {
            glVertexAttribDivisor(i, 0);
        }
        glDisableVertexAttribArray(i);
    }

    glBindVertexArray(0);
}

// ==========================================
// 描画コア (Graphics / Shader / Batching) 実装
// ==========================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "zenoo_internal.h"

static GLuint s_dynamic_vao = 0;
static GLuint s_dynamic_vbo = 0;

static GLuint s_white_texture = 0;
static GLuint s_active_texture = 0;
static GLuint s_active_program = 0;
static int s_current_blend_mode = -1;
static ZenImage* s_current_render_target = NULL;

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

// ------------------------------------------
// ライフサイクル & 内部参照
// ------------------------------------------
void zen__gfx_init(void) {
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

    s_current_render_target = NULL;
    s_current_blend_mode = -1;
}

void zen__gfx_shutdown(void) {
    if (s_white_texture) {
        glDeleteTextures(1, &s_white_texture);
        s_white_texture = 0;
    }
    if (s_dynamic_vbo) {
        glDeleteBuffers(1, &s_dynamic_vbo);
        s_dynamic_vbo = 0;
    }
    if (s_dynamic_vao) {
        glDeleteVertexArrays(1, &s_dynamic_vao);
        s_dynamic_vao = 0;
    }
    s_current_render_target = NULL;
}

ZenImage* zen__gfx_render_target(void) {
    return s_current_render_target;
}

uint32_t zen__gfx_white_texture(void) {
    return (uint32_t)s_white_texture;
}

// フレーム開始時の初期化 (画面をターゲットにし、余白を黒クリア、ゲーム領域を設定)
void zen__gfx_begin_frame(void) {
    const ZenViewport* vp = zen__viewport();

    s_current_render_target = NULL;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);

    // 1. 全体を黒でクリア (レターボックス余白)
    glDisable(GL_SCISSOR_TEST);
    glViewport(0, 0, vp->fb_w, vp->fb_h);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // 2. 仮想解像度アスペクト比のゲーム領域ビューポートとシザーを設定
    glViewport(vp->x, vp->y, vp->w, vp->h);
    glEnable(GL_SCISSOR_TEST);
    glScissor(vp->x, vp->y, vp->w, vp->h);

    // 3. ブレンドモード初期化
    s_current_blend_mode = -1;
    zen_set_blend_mode(ZEN_BLEND_ALPHA);

    s_active_program = 0;
    s_active_texture = s_white_texture;
}

// ------------------------------------------
// クリア (現在の描画先を指定色で塗るだけ)
// ------------------------------------------
void zen_clear(uint32_t color) {
    float clr[4];
    color_to_floats(color, clr);

    if (s_current_render_target) {
        int tw = s_current_render_target->texture ? s_current_render_target->texture->width : s_current_render_target->width;
        int th = s_current_render_target->texture ? s_current_render_target->texture->height : s_current_render_target->height;
        glViewport(0, 0, tw, th);
        glDisable(GL_SCISSOR_TEST);
        glClearColor(clr[0], clr[1], clr[2], clr[3]);
        glClear(GL_COLOR_BUFFER_BIT);
    } else {
        const ZenViewport* vp = zen__viewport();
        glViewport(vp->x, vp->y, vp->w, vp->h);
        glEnable(GL_SCISSOR_TEST);
        glScissor(vp->x, vp->y, vp->w, vp->h);
        glClearColor(clr[0], clr[1], clr[2], clr[3]);
        glClear(GL_COLOR_BUFFER_BIT);
    }
}

// ------------------------------------------
// レンダーターゲット切り替え
// ------------------------------------------
void zen_set_render_target(ZenImage* target) {
    s_current_render_target = target;

    if (target != NULL && target->texture != NULL) {
        if (!target->has_fbo) {
            glGenFramebuffers(1, &target->fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, target->fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target->texture->id, 0);
            target->has_fbo = 1;
        } else {
            glBindFramebuffer(GL_FRAMEBUFFER, target->fbo);
        }
        int tw = target->texture->width;
        int th = target->texture->height;
        glViewport(0, 0, tw, th);
        glDisable(GL_SCISSOR_TEST); // FBO切り替え時は画面用シザーを解除
    } else {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        // 画面復帰時はレターボックスのゲーム領域ビューポートとシザーを正しく復元
        const ZenViewport* vp = zen__viewport();
        glViewport(vp->x, vp->y, vp->w, vp->h);
        glEnable(GL_SCISSOR_TEST);
        glScissor(vp->x, vp->y, vp->w, vp->h);
    }
}

// ------------------------------------------
// ブレンドモード
// ------------------------------------------
void zen_set_blend_mode(int mode) {
    if (s_current_blend_mode == mode) return;
    s_current_blend_mode = mode;
    switch (mode) {
        case ZEN_BLEND_ADD:
            glEnable(GL_BLEND);
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ONE, GL_ONE);
            break;
        case ZEN_BLEND_MULTIPLY:
            glEnable(GL_BLEND);
            glBlendFuncSeparate(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA, GL_ZERO, GL_ONE);
            break;
        case ZEN_BLEND_NONE:
            glDisable(GL_BLEND);
            break;
        case ZEN_BLEND_ALPHA:
        default:
            glEnable(GL_BLEND);
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            break;
    }
}

// ------------------------------------------
// クリッピング (シザー)
// ------------------------------------------
void zen_set_scissor(int x, int y, int w, int h) {
    if (w < 0) w = 0;
    if (h < 0) h = 0;

    glEnable(GL_SCISSOR_TEST);

    if (s_current_render_target) {
        glScissor(x, y, w, h);
    } else {
        const ZenViewport* vp = zen__viewport();

        int sx = vp->x + (int)floorf((float)x * vp->scale);
        int sy = vp->y + (int)floorf((float)(vp->base_h - (y + h)) * vp->scale);
        int sw = (int)ceilf((float)w * vp->scale);
        int sh = (int)ceilf((float)h * vp->scale);

        // ゲーム領域の枠外にはみ出さないよう clamp
        if (sx < vp->x) {
            sw -= (vp->x - sx);
            sx = vp->x;
        }
        if (sy < vp->y) {
            sh -= (vp->y - sy);
            sy = vp->y;
        }
        if (sx + sw > vp->x + vp->w) {
            sw = (vp->x + vp->w) - sx;
        }
        if (sy + sh > vp->y + vp->h) {
            sh = (vp->y + vp->h) - sy;
        }
        if (sw < 0) sw = 0;
        if (sh < 0) sh = 0;

        glScissor(sx, sy, sw, sh);
    }
}

void zen_reset_scissor(void) {
    if (s_current_render_target) {
        glDisable(GL_SCISSOR_TEST);
    } else {
        const ZenViewport* vp = zen__viewport();
        glEnable(GL_SCISSOR_TEST);
        glScissor(vp->x, vp->y, vp->w, vp->h);
    }
}

// ------------------------------------------
// シェーダー (ZenShader)
// ------------------------------------------
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

// ------------------------------------------
// 汎用動的頂点バッファ描画 API
// ------------------------------------------
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
        cur_w = (s_current_render_target->texture) ? s_current_render_target->texture->width : s_current_render_target->width;
        cur_h = (s_current_render_target->texture) ? s_current_render_target->texture->height : s_current_render_target->height;
    } else {
        const ZenViewport* vp = zen__viewport();
        cur_w = vp->base_w;
        cur_h = vp->base_h;
    }
    GLint u_res = glGetUniformLocation(prog, "u_resolution");
    if (u_res >= 0) {
        glUniform2f(u_res, (float)cur_w, (float)cur_h);
    }
    GLint u_flip = glGetUniformLocation(prog, "u_flip_y");
    if (u_flip >= 0) {
        glUniform1f(u_flip, s_current_render_target ? 1.0f : -1.0f);
    }

    // 2. テクスチャの準備
    GLuint tex_id = (texture && texture->texture) ? texture->texture->id : s_white_texture;
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

    // Buffer Orphaning: 同期ストールを排除
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

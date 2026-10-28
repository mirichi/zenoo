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
static GLuint s_quad_vbo = 0;
static size_t s_dynamic_vbo_capacity = 0;

static GLuint s_white_texture = 0;
static GLuint s_active_texture = 0;
static GLuint s_active_program = 0;
static int s_current_blend_mode = -1;
static int s_context_gen = 1;
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

    // 共有 4頂点 Quad VBO 初期化 (layout: pos2, uv2, color4 = 8 floats/頂点)
    static const float quad_vertices[4 * 8] = {
        0.0f, 0.0f,  0.0f, 0.0f,  1.0f, 1.0f, 1.0f, 1.0f,
        1.0f, 0.0f,  1.0f, 0.0f,  1.0f, 1.0f, 1.0f, 1.0f,
        0.0f, 1.0f,  0.0f, 1.0f,  1.0f, 1.0f, 1.0f, 1.0f,
        1.0f, 1.0f,  1.0f, 1.0f,  1.0f, 1.0f, 1.0f, 1.0f
    };
    glGenBuffers(1, &s_quad_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, s_quad_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad_vertices), quad_vertices, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    s_current_render_target = NULL;
    s_current_blend_mode = -1;
#if !defined(__EMSCRIPTEN__) && defined(GL_MULTISAMPLE)
    glEnable(GL_MULTISAMPLE);
#endif
}

void zen__gfx_on_context_recreated(void) {
    // 共有コンテキスト再生成時: テクスチャ・VBO・IBO・Shaderは共有されるが、
    // VAO・FBO はコンテキスト固有オブジェクトのため新しいコンテキスト側で再生成する
    s_context_gen++;
    s_dynamic_vao = 0;
    glGenVertexArrays(1, &s_dynamic_vao);
    s_current_render_target = NULL;
    s_current_blend_mode = -1;
    s_active_program = 0;
    s_active_texture = s_white_texture;
#if !defined(__EMSCRIPTEN__) && defined(GL_MULTISAMPLE)
    glEnable(GL_MULTISAMPLE);
#endif
}

void zen__gfx_shutdown(void) {
    if (s_white_texture) {
        glDeleteTextures(1, &s_white_texture);
        s_white_texture = 0;
    }
    if (s_quad_vbo) {
        glDeleteBuffers(1, &s_quad_vbo);
        s_quad_vbo = 0;
    }
    if (s_dynamic_vbo) {
        glDeleteBuffers(1, &s_dynamic_vbo);
        s_dynamic_vbo = 0;
    }
    if (s_dynamic_vao) {
        glDeleteVertexArrays(1, &s_dynamic_vao);
        s_dynamic_vao = 0;
    }
    s_dynamic_vbo_capacity = 0;
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
// レンダーターゲット切り替え & MSAA解決 (Resolve)
// ------------------------------------------
void zen_image_resolve_msaa(ZenImage* image) {
    if (!image || image->msaa_samples <= 0 || image->msaa_fbo == 0 || !image->has_fbo) {
        return;
    }
    int tw = image->texture ? image->texture->width : image->width;
    int th = image->texture ? image->texture->height : image->height;

    glDisable(GL_SCISSOR_TEST);

    glBindFramebuffer(GL_READ_FRAMEBUFFER, image->msaa_fbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, image->fbo);
    glBlitFramebuffer(0, 0, tw, th, 0, 0, tw, th, GL_COLOR_BUFFER_BIT, GL_NEAREST);

    if (s_current_render_target == image) {
        glBindFramebuffer(GL_FRAMEBUFFER, image->msaa_fbo);
    } else if (s_current_render_target != NULL) {
        if (s_current_render_target->msaa_samples > 0 && s_current_render_target->msaa_fbo != 0) {
            glBindFramebuffer(GL_FRAMEBUFFER, s_current_render_target->msaa_fbo);
        } else {
            glBindFramebuffer(GL_FRAMEBUFFER, s_current_render_target->fbo);
        }
    } else {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
}

void zen_set_render_target(ZenImage* target) {
    zen_ensure_context();

    // 直前のターゲットがMSAAを使用していたら、テクスチャへ解決(Resolve)する
    if (s_current_render_target != NULL && s_current_render_target != target) {
        if (s_current_render_target->msaa_samples > 0 && s_current_render_target->msaa_fbo != 0) {
            zen_image_resolve_msaa(s_current_render_target);
        }
    }

    s_current_render_target = target;
    if (target) {
        target->cpu_dirty = 1;
    }

    if (target != NULL && target->texture != NULL) {
        // 1. 通常 FBO の確保 (テクスチャのアタッチ)
        if (target->has_fbo != s_context_gen) {
            glGenFramebuffers(1, &target->fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, target->fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target->texture->id, 0);
            target->has_fbo = s_context_gen;
            target->msaa_fbo = 0;
        }

        // 2. MSAA が有効な場合
        if (target->msaa_samples > 0) {
            int tw = target->texture->width;
            int th = target->texture->height;
            if (target->msaa_fbo == 0) {
                static GLint s_max_samples = 0;
                if (s_max_samples <= 0) {
                    glGetIntegerv(GL_MAX_SAMPLES, &s_max_samples);
                    if (s_max_samples < 2) s_max_samples = 2;
                }
                GLsizei samples = (GLsizei)target->msaa_samples;
                if (samples > s_max_samples) {
                    samples = (GLsizei)s_max_samples;
                }
                if (samples < 2) samples = 2;
                target->msaa_samples = (int)samples;

                glGenFramebuffers(1, &target->msaa_fbo);
                glGenRenderbuffers(1, &target->msaa_rbo);
                glBindRenderbuffer(GL_RENDERBUFFER, target->msaa_rbo);
                glRenderbufferStorageMultisample(GL_RENDERBUFFER, samples, GL_RGBA8, tw, th);
                glBindFramebuffer(GL_FRAMEBUFFER, target->msaa_fbo);
                glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, target->msaa_rbo);
            } else {
                glBindFramebuffer(GL_FRAMEBUFFER, target->msaa_fbo);
            }
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
    GLint  loc_resolution;
    GLint  loc_flip_y;
    GLint  loc_texture;
};

ZenShader* zen_shader_create(const char* vert_src, const char* frag_src) {
    if (!vert_src || !frag_src || strlen(vert_src) == 0 || strlen(frag_src) == 0) {
        return NULL;
    }
    zen_ensure_context();

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
    shader->loc_resolution = glGetUniformLocation(prog, "u_resolution");
    shader->loc_flip_y     = glGetUniformLocation(prog, "u_flip_y");
    shader->loc_texture    = glGetUniformLocation(prog, "u_texture");
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

void zen_shader_set_vec4_array(ZenShader* shader, const char* name, int count, const float* vec4_data) {
    if (!shader || !name || !vec4_data || count <= 0) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc < 0) {
        char buf[128];
        snprintf(buf, sizeof(buf), "%s[0]", name);
        loc = glGetUniformLocation(shader->program_id, buf);
    }
    if (loc >= 0) {
        if (((uintptr_t)vec4_data & 3) != 0) {
            // Emscripten/WebGL などの環境で 4バイト境界にアラインされていない場合の救済
            float aligned_buf[64];
            size_t bytes = (size_t)count * 4 * sizeof(float);
            if (bytes <= sizeof(aligned_buf)) {
                memcpy(aligned_buf, vec4_data, bytes);
                glUniform4fv(loc, (GLsizei)count, aligned_buf);
            } else {
                float* heap_buf = (float*)malloc(bytes);
                if (heap_buf) {
                    memcpy(heap_buf, vec4_data, bytes);
                    glUniform4fv(loc, (GLsizei)count, heap_buf);
                    free(heap_buf);
                }
            }
        } else {
            glUniform4fv(loc, (GLsizei)count, vec4_data);
        }
    }
}

void zen_shader_set_mat4(ZenShader* shader, const char* name, const float* mat4) {
    if (!shader || !mat4) return;
    glUseProgram(shader->program_id);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) {
        if (((uintptr_t)mat4 & 3) != 0) {
            float aligned[16];
            memcpy(aligned, mat4, sizeof(aligned));
            glUniformMatrix4fv(loc, 1, GL_FALSE, aligned);
        } else {
            glUniformMatrix4fv(loc, 1, GL_FALSE, mat4);
        }
    }
}

void zen_shader_set_texture(ZenShader* shader, const char* name, int unit, ZenImage* image) {
    if (!shader || unit < 0 || unit > 15) return;
    glUseProgram(shader->program_id);
    GLuint tex_id = (image && image->texture) ? image->texture->id : s_white_texture;
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    glActiveTexture(GL_TEXTURE0);
    GLint loc = glGetUniformLocation(shader->program_id, name);
    if (loc >= 0) glUniform1i(loc, unit);
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
    if (shader->loc_resolution >= 0) {
        glUniform2f(shader->loc_resolution, (float)cur_w, (float)cur_h);
    }
    if (shader->loc_flip_y >= 0) {
        glUniform1f(shader->loc_flip_y, s_current_render_target ? 1.0f : -1.0f);
    }

    // 2. テクスチャの準備
    GLuint tex_id = (texture && texture->texture) ? texture->texture->id : s_white_texture;
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    s_active_texture = tex_id;
    if (shader->loc_texture >= 0) {
        glUniform1i(shader->loc_texture, 0);
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

// ------------------------------------------
// メッシュ (ZenMesh: VRAM VBO/IBO & 2バッファインスタンシング)
// ------------------------------------------
static GLenum topology_to_gl_mode(int topology) {
    switch (topology) {
        case ZEN_TOPOLOGY_POINTS:         return GL_POINTS;
        case ZEN_TOPOLOGY_LINES:          return GL_LINES;
        case ZEN_TOPOLOGY_LINE_LOOP:      return GL_LINE_LOOP;
        case ZEN_TOPOLOGY_LINE_STRIP:     return GL_LINE_STRIP;
        case ZEN_TOPOLOGY_TRIANGLES:      return GL_TRIANGLES;
        case ZEN_TOPOLOGY_TRIANGLE_STRIP: return GL_TRIANGLE_STRIP;
        case ZEN_TOPOLOGY_TRIANGLE_FAN:   return GL_TRIANGLE_FAN;
        default:                          return GL_TRIANGLES;
    }
}

ZenMesh* zen_mesh_create(int topology,
                         const uint8_t* layout,
                         const void* vertex_data,
                         size_t vertex_bytes,
                         int vertex_count,
                         const uint32_t* index_data,
                         int index_count) {
    zen_ensure_context();

    ZenMesh* mesh = (ZenMesh*)zen__alloc(sizeof(ZenMesh));
    if (!mesh) return NULL;

    mesh->topology = topology;
    mesh->vertex_count = vertex_count;
    mesh->index_count = index_count;
    mesh->is_dynamic = 0;

    if (layout && layout[0] != 0) {
        int i = 0;
        while (i < 15 && layout[i] != 0) {
            mesh->layout[i] = layout[i];
            i++;
        }
        mesh->layout[i] = 0;
    } else {
        // デフォルト標準レイアウト: pos(2), uv(2), color(4)
        mesh->layout[0] = 2;
        mesh->layout[1] = 2;
        mesh->layout[2] = 4;
        mesh->layout[3] = 0;
    }

    if (vertex_bytes > 0) {
        GLuint vbo = 0;
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)vertex_bytes, vertex_data, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        mesh->vbo = (uint32_t)vbo;
        mesh->vbo_bytes = vertex_bytes;
    }

    if (index_data && index_count > 0) {
        size_t ibo_bytes = (size_t)index_count * sizeof(uint32_t);
        GLuint ibo = 0;
        glGenBuffers(1, &ibo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)ibo_bytes, index_data, GL_STATIC_DRAW);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        mesh->ibo = (uint32_t)ibo;
        mesh->ibo_bytes = ibo_bytes;
    }

    return mesh;
}

void zen_mesh_destroy(ZenMesh* mesh) {
    if (!mesh) return;
    if (zen__window() != NULL) {
        if (mesh->vbo) {
            GLuint vbo = (GLuint)mesh->vbo;
            glDeleteBuffers(1, &vbo);
        }
        if (mesh->ibo) {
            GLuint ibo = (GLuint)mesh->ibo;
            glDeleteBuffers(1, &ibo);
        }
    }
    free(mesh);
}

void zen_mesh_update_vertices(ZenMesh* mesh,
                              size_t offset_bytes,
                              const void* vertex_data,
                              size_t byte_size,
                              int vertex_count) {
    if (!mesh || !vertex_data || byte_size == 0) return;
    zen_ensure_context();

    // 頂点が更新された時点で自動的に GL_DYNAMIC_DRAW へ昇格
    mesh->is_dynamic = 1;
    if (vertex_count > 0) {
        mesh->vertex_count = vertex_count;
    }

    if (mesh->vbo == 0) {
        GLuint vbo = 0;
        glGenBuffers(1, &vbo);
        mesh->vbo = (uint32_t)vbo;
        mesh->vbo_bytes = 0;
    }

    glBindBuffer(GL_ARRAY_BUFFER, (GLuint)mesh->vbo);
    if (offset_bytes == 0 && byte_size == mesh->vbo_bytes) {
        // Buffer Orphaning: GPU使用中のストールを回避して高速更新
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)mesh->vbo_bytes, NULL, GL_DYNAMIC_DRAW);
        glBufferSubData(GL_ARRAY_BUFFER, 0, (GLsizeiptr)byte_size, vertex_data);
    } else if (offset_bytes + byte_size <= mesh->vbo_bytes) {
        glBufferSubData(GL_ARRAY_BUFFER, (GLintptr)offset_bytes, (GLsizeiptr)byte_size, vertex_data);
    } else {
        size_t total = offset_bytes + byte_size;
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)total, NULL, GL_DYNAMIC_DRAW);
        glBufferSubData(GL_ARRAY_BUFFER, (GLintptr)offset_bytes, (GLsizeiptr)byte_size, vertex_data);
        mesh->vbo_bytes = total;
    }
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

void zen_mesh_update_indices(ZenMesh* mesh,
                             const uint32_t* index_data,
                             int index_count) {
    if (!mesh) return;
    zen_ensure_context();

    mesh->index_count = index_count;
    if (!index_data || index_count <= 0) {
        return;
    }

    size_t ibo_bytes = (size_t)index_count * sizeof(uint32_t);
    if (mesh->ibo == 0) {
        GLuint ibo = 0;
        glGenBuffers(1, &ibo);
        mesh->ibo = (uint32_t)ibo;
        mesh->ibo_bytes = 0;
    }

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, (GLuint)mesh->ibo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, (GLsizeiptr)ibo_bytes, index_data, GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    mesh->ibo_bytes = ibo_bytes;
}

void zen_draw_mesh_instanced(ZenMesh* geom_mesh,
                             ZenMesh* inst_buffer,
                             const uint8_t* inst_layout,
                             const void* inst_data,
                             int instance_count,
                             ZenImage* texture,
                             ZenShader* shader) {
    if (!shader) return;

    // 1. シェーダーと共通Uniformの準備
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
    if (shader->loc_resolution >= 0) {
        glUniform2f(shader->loc_resolution, (float)cur_w, (float)cur_h);
    }
    if (shader->loc_flip_y >= 0) {
        glUniform1f(shader->loc_flip_y, s_current_render_target ? 1.0f : -1.0f);
    }

    // 2. テクスチャのバインド
    GLuint tex_id = (texture && texture->texture) ? texture->texture->id : s_white_texture;
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex_id);
    s_active_texture = tex_id;
    if (shader->loc_texture >= 0) {
        glUniform1i(shader->loc_texture, 0);
    }

    glBindVertexArray(s_dynamic_vao);

    int attr_idx = 0;

    // 3. Stream 0: 頂点バッファ (divisor = 0)
    // - geom_mesh が指定されていればその VBO を使用
    // - geom_mesh が NULL かつ inst_buffer も NULL (通常の Image 描画) なら共通4頂点 s_quad_vbo を使用
    // - geom_mesh が NULL かつ inst_buffer が指定されている場合 (gl_VertexID ビルボードの GPU パーティクル等) は Stream 0 属性なし
    if (geom_mesh || !inst_buffer) {
        GLuint geom_vbo = geom_mesh ? (GLuint)geom_mesh->vbo : s_quad_vbo;
        if (!geom_vbo) {
            glBindVertexArray(0);
            return;
        }

        static const uint8_t default_quad_layout[] = { 2, 2, 4, 0 };
        const uint8_t* v_layout = (geom_mesh && geom_mesh->layout[0] != 0) ? geom_mesh->layout : default_quad_layout;

        int v_stride = 0;
        for (int i = 0; v_layout[i] != 0; i++) {
            v_stride += (int)v_layout[i] * (int)sizeof(float);
        }
        if (v_stride == 0) {
            glBindVertexArray(0);
            return;
        }

        glBindBuffer(GL_ARRAY_BUFFER, geom_vbo);
        uintptr_t v_offset = 0;
        for (int i = 0; v_layout[i] != 0; i++) {
            int size = (int)v_layout[i];
            glEnableVertexAttribArray(attr_idx);
            glVertexAttribPointer(attr_idx, size, GL_FLOAT, GL_FALSE, v_stride, (void*)v_offset);
            v_offset += (size_t)size * sizeof(float);
            attr_idx++;
        }
    }
    int geom_attr_count = attr_idx;

    // 4. Stream 1: インスタンスバッファ (divisor = 1)
    // - inst_buffer (VRAM 常駐 InstanceBuffer) または inst_data (CPU 動的転送バッチ)
    int eff_instances = 1;
    int has_inst_stream = 0;

    if (inst_buffer && inst_buffer->vbo != 0 && inst_buffer->vertex_count > 0) {
        const uint8_t* ib_layout = inst_buffer->layout;
        int i_stride = 0;
        for (int i = 0; ib_layout[i] != 0; i++) {
            i_stride += (int)ib_layout[i] * (int)sizeof(float);
        }
        if (i_stride > 0) {
            glBindBuffer(GL_ARRAY_BUFFER, (GLuint)inst_buffer->vbo);
            uintptr_t i_offset = 0;
            for (int i = 0; ib_layout[i] != 0; i++) {
                int size = (int)ib_layout[i];
                glEnableVertexAttribArray(attr_idx);
                glVertexAttribPointer(attr_idx, size, GL_FLOAT, GL_FALSE, i_stride, (void*)i_offset);
                glVertexAttribDivisor(attr_idx, 1);
                i_offset += (size_t)size * sizeof(float);
                attr_idx++;
            }
            eff_instances = inst_buffer->vertex_count;
            has_inst_stream = 1;
        }
    } else if (inst_layout && inst_layout[0] != 0 && inst_data && instance_count > 0) {
        int i_stride = 0;
        for (int i = 0; inst_layout[i] != 0; i++) {
            i_stride += (int)inst_layout[i] * (int)sizeof(float);
        }
        if (i_stride > 0) {
            size_t total_inst_bytes = (size_t)i_stride * (size_t)instance_count;
            glBindBuffer(GL_ARRAY_BUFFER, s_dynamic_vbo);
            glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)total_inst_bytes, NULL, GL_STREAM_DRAW);
            glBufferSubData(GL_ARRAY_BUFFER, 0, (GLsizeiptr)total_inst_bytes, inst_data);

            uintptr_t i_offset = 0;
            for (int i = 0; inst_layout[i] != 0; i++) {
                int size = (int)inst_layout[i];
                glEnableVertexAttribArray(attr_idx);
                glVertexAttribPointer(attr_idx, size, GL_FLOAT, GL_FALSE, i_stride, (void*)i_offset);
                glVertexAttribDivisor(attr_idx, 1);
                i_offset += (size_t)size * sizeof(float);
                attr_idx++;
            }
            eff_instances = instance_count;
            has_inst_stream = 1;
        }
    } else if (instance_count > 1) {
        eff_instances = instance_count;
    }

    // 5. ドローコール (IBO があれば glDrawElementsInstanced、なければ glDrawArraysInstanced)
    GLenum gl_mode = geom_mesh ? topology_to_gl_mode(geom_mesh->topology) : GL_TRIANGLE_STRIP;

    if (geom_mesh && geom_mesh->ibo != 0 && geom_mesh->index_count > 0) {
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, (GLuint)geom_mesh->ibo);
        if (has_inst_stream || eff_instances > 1) {
            glDrawElementsInstanced(gl_mode, geom_mesh->index_count, GL_UNSIGNED_INT, (void*)0, eff_instances);
        } else {
            glDrawElements(gl_mode, geom_mesh->index_count, GL_UNSIGNED_INT, (void*)0);
        }
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    } else {
        int v_count = geom_mesh ? geom_mesh->vertex_count : 4;
        if (v_count > 0) {
            if (has_inst_stream || eff_instances > 1) {
                glDrawArraysInstanced(gl_mode, 0, v_count, eff_instances);
            } else {
                glDrawArrays(gl_mode, 0, v_count);
            }
        }
    }

    // 6. クリーンアップ
    for (int i = 0; i < attr_idx; i++) {
        if (i >= geom_attr_count) {
            glVertexAttribDivisor(i, 0);
        }
        glDisableVertexAttribArray(i);
    }
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
}

// ==========================================
// テクスチャ & 画像 (Texture & Image) 実装
// ==========================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include "zenoo_internal.h"

static void (*s_gc_callback)(void) = NULL;
static int s_default_texture_filter = ZEN_FILTER_LINEAR;

void zen_set_gc_trigger_callback(void (*callback)(void)) {
    s_gc_callback = callback;
}

void* zen__alloc(size_t size) {
    void* p = calloc(1, size);
    if (!p && s_gc_callback) {
        s_gc_callback();
        p = calloc(1, size);
    }
    return p;
}

// ------------------------------------------
// テクスチャ実体操作
// ------------------------------------------
ZenTexture* zen_texture_create(int width, int height) {
    if (width <= 0 || height <= 0) return NULL;

    ZenTexture* tex = (ZenTexture*)zen__alloc(sizeof(ZenTexture));
    if (!tex) return NULL;

    tex->width = width;
    tex->height = height;
    tex->ref_count = 1;

    glGenTextures(1, &tex->id);
    if (!tex->id && s_gc_callback) {
        s_gc_callback();
        glGenTextures(1, &tex->id);
    }

    return tex;
}

void zen_texture_release(ZenTexture* texture) {
    if (!texture) return;
    texture->ref_count--;
    if (texture->ref_count <= 0) {
        if (texture->id) {
            glDeleteTextures(1, &texture->id);
        }
        free(texture);
    }
}

void zen__texture_release(ZenTexture* texture) {
    zen_texture_release(texture);
}

// ------------------------------------------
// フィルタ設定
// ------------------------------------------
void zen_set_default_texture_filter(int filter) {
    s_default_texture_filter = filter;
}

int zen_get_default_texture_filter(void) {
    return s_default_texture_filter;
}

void zen_image_set_filter(ZenImage* image, int filter) {
    if (!image || !image->texture || !image->texture->id) return;
    image->texture->filter = filter;
    GLint gl_f = (filter == ZEN_FILTER_NEAREST) ? GL_NEAREST : GL_LINEAR;
    glBindTexture(GL_TEXTURE_2D, image->texture->id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_f);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_f);
}

int zen_image_get_filter(const ZenImage* image) {
    if (!image || !image->texture) return ZEN_FILTER_LINEAR;
    return image->texture->filter;
}

void zen_image_set_texture_filter(ZenImage* image, int filter) {
    zen_image_set_filter(image, filter);
}

int zen_image_get_texture_filter(const ZenImage* image) {
    return zen_image_get_filter(image);
}

void zen_image_replace_texture(ZenImage* dst, ZenImage* src) {
    if (!dst || !src || !src->texture) return;
    if (dst->texture == src->texture) return;

    if (dst->has_fbo) {
        glDeleteFramebuffers(1, &dst->fbo);
        dst->fbo = 0;
        dst->has_fbo = 0;
    }

    if (dst->texture) {
        zen_texture_release(dst->texture);
    }

    dst->texture = src->texture;
    dst->texture->ref_count++;
    dst->x = src->x;
    dst->y = src->y;
    dst->width = src->width;
    dst->height = src->height;
}

// ------------------------------------------
// 画像生成 & ロード & 破棄
// ------------------------------------------
ZenImage* zen_image_create_format(int width, int height, int format) {
    if (width <= 0 || height <= 0) return NULL;

    ZenTexture* tex = zen_texture_create(width, height);
    if (!tex) return NULL;
    tex->filter = s_default_texture_filter;

    GLint gl_f = (s_default_texture_filter == ZEN_FILTER_NEAREST) ? GL_NEAREST : GL_LINEAR;
    glBindTexture(GL_TEXTURE_2D, tex->id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_f);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_f);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    if (format == ZEN_IMAGE_FORMAT_R8) {
        unsigned char* clear_buf = (unsigned char*)calloc(1, (size_t)width * (size_t)height);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, width, height, 0, GL_RED, GL_UNSIGNED_BYTE, clear_buf);
        if (clear_buf) free(clear_buf);
    } else {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    }

    ZenImage* img = (ZenImage*)zen__alloc(sizeof(ZenImage));
    if (!img) {
        zen_texture_release(tex);
        return NULL;
    }

    img->texture = tex;
    img->x = 0;
    img->y = 0;
    img->width = width;
    img->height = height;

    return img;
}

ZenImage* zen_image_create(int width, int height) {
    return zen_image_create_format(width, height, ZEN_IMAGE_FORMAT_RGBA);
}

ZenImage* zen_image_create_from_pixels(int width, int height, const uint32_t* pixels) {
    if (width <= 0 || height <= 0 || !pixels) return NULL;

    ZenTexture* tex = zen_texture_create(width, height);
    if (!tex) return NULL;
    tex->filter = s_default_texture_filter;

    GLint gl_f = (s_default_texture_filter == ZEN_FILTER_NEAREST) ? GL_NEAREST : GL_LINEAR;
    glBindTexture(GL_TEXTURE_2D, tex->id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, gl_f);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, gl_f);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);

    ZenImage* img = (ZenImage*)zen__alloc(sizeof(ZenImage));
    if (!img) {
        zen_texture_release(tex);
        return NULL;
    }

    img->texture = tex;
    img->x = 0;
    img->y = 0;
    img->width = width;
    img->height = height;

    return img;
}

ZenImage* zen_image_sub_image(ZenImage* parent, int x, int y, int width, int height) {
    if (!parent || !parent->texture || width <= 0 || height <= 0) return NULL;

    ZenImage* img = (ZenImage*)zen__alloc(sizeof(ZenImage));
    if (!img) return NULL;

    img->texture = parent->texture;
    img->texture->ref_count++;
    img->x = parent->x + x;
    img->y = parent->y + y;
    img->width = width;
    img->height = height;

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

    if (zen__gfx_render_target() == image) {
        zen_set_render_target(NULL);
    }

    if (image->has_fbo) {
        glDeleteFramebuffers(1, &image->fbo);
    }
    if (image->texture) {
        zen_texture_release(image->texture);
        image->texture = NULL;
    }
    free(image);
}

// ------------------------------------------
// プロパティ取得
// ------------------------------------------
void zen_image_get_size(const ZenImage* image, int* width, int* height) {
    if (!image) {
        if (width) *width = 0;
        if (height) *height = 0;
        return;
    }
    if (width) *width = image->width;
    if (height) *height = image->height;
}

void zen_image_get_bounds(const ZenImage* image, int* x, int* y, int* w, int* h) {
    if (!image) {
        if (x) *x = 0; if (y) *y = 0; if (w) *w = 0; if (h) *h = 0;
        return;
    }
    if (x) *x = image->x;
    if (y) *y = image->y;
    if (w) *w = image->width;
    if (h) *h = image->height;
}

void zen_image_get_texture_size(const ZenImage* image, int* tex_w, int* tex_h) {
    if (!image || !image->texture) {
        if (tex_w) *tex_w = 0; if (tex_h) *tex_h = 0;
        return;
    }
    if (tex_w) *tex_w = image->texture->width;
    if (tex_h) *tex_h = image->texture->height;
}

void zen_image_get_uv(const ZenImage* image, float* u, float* v, float* uw, float* vh) {
    if (!image || !image->texture || image->texture->width <= 0 || image->texture->height <= 0) {
        if (u) *u = 0.0f; if (v) *v = 0.0f; if (uw) *uw = 1.0f; if (vh) *vh = 1.0f;
        return;
    }
    float tw = (float)image->texture->width;
    float th = (float)image->texture->height;
    if (u)  *u  = (float)image->x / tw;
    if (v)  *v  = (float)image->y / th;
    if (uw) *uw = (float)image->width / tw;
    if (vh) *vh = (float)image->height / th;
}

uint32_t zen_image_get_texture_id(const ZenImage* image) {
    return (image && image->texture) ? (uint32_t)image->texture->id : 0;
}

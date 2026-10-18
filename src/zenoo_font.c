#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include "zenoo_internal.h"


#define ATLAS_WIDTH   2048
#define ATLAS_HEIGHT  2048
#define SDF_BASE_SIZE 64.0f // SDFを生成する基準フォント高さ
#define SDF_PADDING   10    // アウトライン・影用の余白ピクセル
#define SDF_ONEDGE    128   // エッジ境界値 (0.5相当)
#define BITMAP_PAD    1     // ビットマップ外周の透明パディング (GL_LINEAR端欠け・滲み防止)
#define FONT_OPTICAL_SCALE 1.14f // M+ 1p 等の広い hhea バウンディングボックスに対する視覚サイズ補正
#define HASH_TABLE_SIZE 4096

// グリフキャッシュエントリ
typedef struct GlyphEntry {
    int font_id;
    int codepoint;
    int pixel_size; // ビットマップの場合はそのピクセル高さ (SDFの場合は 0)
    ZenGlyph glyph;
    struct GlyphEntry* next;
} GlyphEntry;

// フォント構造体
struct ZenFont {
    int id;
    stbtt_fontinfo info;
    unsigned char* data;
    size_t data_size;
    float ascent;
    float descent;
    float line_gap;
};

// アトラス状態
static ZenImage* s_atlas_image = NULL;
static int s_atlas_x = 1;
static int s_atlas_y = 1;
static int s_atlas_row_h = 0;
static GlyphEntry* s_glyph_hash[HASH_TABLE_SIZE] = {0};
static int s_next_font_id = 1;

// アトラス初期化
static void init_atlas_if_needed(void) {
    if (s_atlas_image) return;

    ZenTexture* tex = zen_texture_create(ATLAS_WIDTH, ATLAS_HEIGHT);
    if (!tex) return;

    glBindTexture(GL_TEXTURE_2D, tex->id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // 1チャンネル GL_R8 (GLES3/GL3.3 Core共通: WebGL 2.0 準拠の Sized Internal Format)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, ATLAS_WIDTH, ATLAS_HEIGHT, 0, GL_RED, GL_UNSIGNED_BYTE, NULL);

    // 初期クリア (全ピクセルを外側 0 に初期化)
    unsigned char* clear_buf = (unsigned char*)calloc(1, ATLAS_WIDTH * ATLAS_HEIGHT);
    if (clear_buf) {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, ATLAS_WIDTH, ATLAS_HEIGHT, GL_RED, GL_UNSIGNED_BYTE, clear_buf);
        free(clear_buf);
    }

    s_atlas_image = (ZenImage*)calloc(1, sizeof(ZenImage));
    if (!s_atlas_image) {
        zen_texture_release(tex);
        return;
    }

    s_atlas_image->texture = tex;
    s_atlas_image->x = 0;
    s_atlas_image->y = 0;
    s_atlas_image->width = ATLAS_WIDTH;
    s_atlas_image->height = ATLAS_HEIGHT;


    s_atlas_x = 1;
    s_atlas_y = 1;
    s_atlas_row_h = 0;
}

void zen_font_set_atlas_image(ZenImage* img) {
    if (s_atlas_image == img) return;
    s_atlas_image = img;
    s_atlas_x = 1;
    s_atlas_y = 1;
    s_atlas_row_h = 0;
}

ZenImage* zen_font_get_atlas_image(void) {
    init_atlas_if_needed();
    return s_atlas_image;
}

// ハッシュ関数
static unsigned int hash_key(int font_id, int codepoint, int pixel_size) {
    unsigned int h = ((unsigned int)font_id * 31) ^ ((unsigned int)codepoint * 17) ^ ((unsigned int)pixel_size * 53);
    return h % HASH_TABLE_SIZE;
}

// ----------------------------------------------------------------------------
// 小サイズビットマップの高精細化フィルタ:
// 1. 垂直ステム・グリッドフィッティング (漢字の横線が2ピクセルに割れてボヤける現象を1px芯へ収束)
// 2. 光学的ステム・ダークニング (ヒンティングなしラスタライズでの細선のかすれ・ムラを補正)
// ----------------------------------------------------------------------------
static void enhance_bitmap_glyph(unsigned char* pixels, int w, int h, float pixel_size) {
    if (!pixels || w <= 0 || h <= 0) return;

    // 1. 垂直方向のステム収束 (2行にまたがって薄く割れた横ストロークを主行へ寄せる)
    if (h >= 3 && pixel_size <= 28.0f) {
        for (int x = 0; x < w; x++) {
            for (int y = 0; y < h - 1; y++) {
                int p0 = pixels[y * w + x];
                int p1 = pixels[(y + 1) * w + x];

                // 両行とも中程度のカバレッジを持ち、上下が抜けている場合 (= 約1px幅の横線が境界を跨いでいる)
                if (p0 >= 55 && p0 <= 190 && p1 >= 55 && p1 <= 190) {
                    int up   = (y > 0) ? pixels[(y - 1) * w + x] : 0;
                    int down = (y + 2 < h) ? pixels[(y + 2) * w + x] : 0;
                    int sum  = p0 + p1;
                    if (up < 55 && down < 55 && sum >= 130 && sum <= 340) {
                        if (p0 >= p1) {
                            int transfer = (int)(p1 * 0.42f);
                            int np0 = p0 + transfer;
                            if (np0 > 255) np0 = 255;
                            pixels[y * w + x]       = (unsigned char)np0;
                            pixels[(y + 1) * w + x] = (unsigned char)(p1 - (int)(transfer * 0.65f));
                        } else {
                            int transfer = (int)(p0 * 0.42f);
                            int np1 = p1 + transfer;
                            if (np1 > 255) np1 = 255;
                            pixels[(y + 1) * w + x] = (unsigned char)np1;
                            pixels[y * w + x]       = (unsigned char)(p0 - (int)(transfer * 0.65f));
                        }
                        y++; // 処理済みペアをスキップ
                    }
                }
            }
        }
    }

    // 2. 水平方向の縦線収束 (2列にまたがって薄く割れた縦ストロークを主列へ寄せる)
    if (w >= 3 && pixel_size <= 28.0f) {
        for (int y = 0; y < h; y++) {
            unsigned char* row = pixels + y * w;
            for (int x = 0; x < w - 1; x++) {
                int p0 = row[x];
                int p1 = row[x + 1];
                if (p0 >= 55 && p0 <= 190 && p1 >= 55 && p1 <= 190) {
                    int left  = (x > 0) ? row[x - 1] : 0;
                    int right = (x + 2 < w) ? row[x + 2] : 0;
                    int sum   = p0 + p1;
                    if (left < 55 && right < 55 && sum >= 130 && sum <= 340) {
                        if (p0 >= p1) {
                            int transfer = (int)(p1 * 0.35f);
                            int np0 = p0 + transfer;
                            if (np0 > 255) np0 = 255;
                            row[x]     = (unsigned char)np0;
                            row[x + 1] = (unsigned char)(p1 - (int)(transfer * 0.55f));
                        } else {
                            int transfer = (int)(p0 * 0.35f);
                            int np1 = p1 + transfer;
                            if (np1 > 255) np1 = 255;
                            row[x + 1] = (unsigned char)np1;
                            row[x]     = (unsigned char)(p0 - (int)(transfer * 0.55f));
                        }
                        x++;
                    }
                }
            }
        }
    }

    // 3. 光学的ステム・ダークニング (サイズに応じた芯の濃度補正)
    float darken_strength = 0.0f;
    if (pixel_size < 28.0f) {
        darken_strength = (28.0f - pixel_size) / 28.0f * 0.28f;
    }
    if (darken_strength > 0.01f) {
        int total = w * h;
        for (int i = 0; i < total; i++) {
            float a = (float)pixels[i] / 255.0f;
            if (a > 0.05f && a < 0.99f) {
                // 中間〜高カバレッジ領域 (ストロークの芯) を引き上げる
                float boosted = a + darken_strength * a * (1.0f - a * 0.5f);
                if (boosted > 1.0f) boosted = 1.0f;
                pixels[i] = (unsigned char)(boosted * 255.0f + 0.5f);
            }
        }
    }
}

// フォント読み込み (メモリ)
ZenFont* zen_font_load_memory(const unsigned char* data, size_t size) {
    if (!data || size == 0) return NULL;

    ZenFont* font = (ZenFont*)calloc(1, sizeof(ZenFont));
    if (!font) return NULL;

    font->id = s_next_font_id++;
    font->data = (unsigned char*)malloc(size);
    if (!font->data) {
        free(font);
        return NULL;
    }
    memcpy(font->data, data, size);
    font->data_size = size;

    // TTC (フォントコレクション) の場合は最初のフォント (index 0) を使用
    int offset = stbtt_GetFontOffsetForIndex(font->data, 0);
    if (offset < 0) offset = 0;

    if (!stbtt_InitFont(&font->info, font->data, offset)) {
        fprintf(stderr, "[Zenoo Font] Failed to initialize font with stb_truetype\n");
        free(font->data);
        free(font);
        return NULL;
    }

    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(&font->info, &ascent, &descent, &line_gap);
    font->ascent = (float)ascent;
    font->descent = (float)descent;
    font->line_gap = (float)line_gap;

    return font;
}

// フォント読み込み (ファイルパス)
ZenFont* zen_font_load(const char* filepath) {
    if (!filepath) {
        return NULL;
    }

    FILE* f = fopen(filepath, "rb");
    if (!f) {
        return NULL;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size <= 0) {
        fclose(f);
        return NULL;
    }

    unsigned char* buffer = (unsigned char*)malloc(size);
    if (!buffer) {
        fclose(f);
        return NULL;
    }

    if (fread(buffer, 1, size, f) != (size_t)size) {
        free(buffer);
        fclose(f);
        return NULL;
    }
    fclose(f);

    ZenFont* font = zen_font_load_memory(buffer, (size_t)size);
    free(buffer);
    return font;
}

void zen_font_destroy(ZenFont* font) {
    if (!font) return;
    if (font->data) {
        free(font->data);
    }
    free(font);
}

void zen_font_get_metrics(ZenFont* font, float font_size, float* ascent, float* descent, float* line_gap) {
    if (!font) return;
    float scale = stbtt_ScaleForPixelHeight(&font->info, font_size * FONT_OPTICAL_SCALE);
    // 視覚的な上下センタリングがずれないよう、論理的なベースライン位置を font_size に合わせて正規化
    float raw_asc = font->ascent * scale;
    float raw_desc = font->descent * scale;
    float extra = (raw_asc - raw_desc) - font_size;
    if (ascent)   *ascent   = raw_asc - extra * 0.65f;
    if (descent)  *descent  = raw_desc + extra * 0.35f;
    if (line_gap) *line_gap = font->line_gap * scale;
}

#define BITMAP_SIZE_THRESHOLD 36.0f // 36px以下の文字は直接ラスタライズ + ステム強調フィルタで高精細描画

// グリフ取得 (キャッシュにあれば即返却、なければビットマップまたはSDF生成してアトラス転送)
int zen_font_get_glyph(ZenFont* font, int codepoint, float font_size, ZenGlyph* out_glyph) {
    if (!font || !out_glyph) {
        return 0;
    }

    init_atlas_if_needed();

    int force_sdf = 0;
    int force_bitmap = 0;
    float actual_size = font_size;

    if (font_size < 0.0f) {
        force_sdf = 1;
        actual_size = -font_size;
    } else if (font_size >= 10000.0f) {
        force_bitmap = 1;
        actual_size = font_size - 10000.0f;
    }

    if (actual_size <= 0.0f) actual_size = 24.0f;

    int use_bitmap = force_bitmap || (!force_sdf && actual_size < BITMAP_SIZE_THRESHOLD);
    const ZenViewport* vp = zen__viewport();
    float render_scale = (!zen__gfx_render_target() && vp && vp->scale > 1.0f) ? vp->scale : 1.0f;
    int pixel_size = use_bitmap ? (int)roundf(actual_size * render_scale) : 0;
    if (use_bitmap && pixel_size < 1) pixel_size = 1;
    float inv_render_scale = (use_bitmap && pixel_size > 0) ? (actual_size / (float)pixel_size) : 1.0f;

    unsigned int h = hash_key(font->id, codepoint, pixel_size);
    GlyphEntry* entry = s_glyph_hash[h];
    while (entry) {
        if (entry->font_id == font->id && entry->codepoint == codepoint && entry->pixel_size == pixel_size) {
            if (use_bitmap) {
                *out_glyph = entry->glyph;
                out_glyph->x0 *= inv_render_scale;
                out_glyph->y0 *= inv_render_scale;
                out_glyph->x1 *= inv_render_scale;
                out_glyph->y1 *= inv_render_scale;
                out_glyph->advance_x *= inv_render_scale;
            } else {
                float scale_ratio = actual_size / SDF_BASE_SIZE;
                *out_glyph = entry->glyph;
                out_glyph->x0 *= scale_ratio;
                out_glyph->y0 *= scale_ratio;
                out_glyph->x1 *= scale_ratio;
                out_glyph->y1 *= scale_ratio;
                out_glyph->advance_x *= scale_ratio;
            }
            return 1;
        }
        entry = entry->next;
    }

    // 未キャッシュ: 生成処理
    float req_pixel_size = use_bitmap ? (float)pixel_size : SDF_BASE_SIZE;
    float scale = stbtt_ScaleForPixelHeight(&font->info, req_pixel_size * FONT_OPTICAL_SCALE);

    int advance_width = 0, lsb = 0;
    stbtt_GetCodepointHMetrics(&font->info, codepoint, &advance_width, &lsb);

    // 空白文字（スペース等）の処理
    int glyph_index = stbtt_FindGlyphIndex(&font->info, codepoint);
    int is_empty = (glyph_index == 0 && codepoint == ' ') || stbtt_IsGlyphEmpty(&font->info, glyph_index);

    ZenGlyph base_glyph;
    memset(&base_glyph, 0, sizeof(ZenGlyph));
    base_glyph.codepoint = codepoint;
    base_glyph.advance_x = (float)advance_width * scale;
    base_glyph.visible = !is_empty;
    base_glyph.is_bitmap = use_bitmap;

    if (!is_empty) {
        int w = 0, h_out = 0, xoff = 0, yoff = 0;
        unsigned char* pixels = NULL;

        if (use_bitmap) {
            pixels = stbtt_GetCodepointBitmap(
                &font->info,
                scale, scale,
                codepoint,
                &w, &h_out,
                &xoff, &yoff
            );
            if (pixels && w > 0 && h_out > 0) {
                enhance_bitmap_glyph(pixels, w, h_out, req_pixel_size);
            }
        } else {
            float dist_scale = (float)SDF_ONEDGE / (float)SDF_PADDING;
            pixels = stbtt_GetCodepointSDF(
                &font->info,
                scale,
                codepoint,
                SDF_PADDING,
                SDF_ONEDGE,
                dist_scale,
                &w, &h_out,
                &xoff, &yoff
            );
        }

        if (pixels && w > 0 && h_out > 0) {
            int pad = use_bitmap ? BITMAP_PAD : 0;
            int pack_w = w + pad * 2;
            int pack_h = h_out + pad * 2;

            // アトラスへパッキング (棚詰め)
            if (s_atlas_x + pack_w + 1 >= ATLAS_WIDTH) {
                s_atlas_y += s_atlas_row_h + 1;
                s_atlas_x = 1;
                s_atlas_row_h = 0;
            }

            if (s_atlas_y + pack_h + 1 >= ATLAS_HEIGHT) {
                fprintf(stderr, "[Zenoo Font] Warning: Texture Atlas Full!\n");
                s_atlas_x = 1;
                s_atlas_y = 1;
                s_atlas_row_h = 0;
            }

            int dest_x = s_atlas_x;
            int dest_y = s_atlas_y;

            // OpenGL テクスチャへ部分転送 (BITMAP_PAD 分の内側に転送し、外周1pxは透明0を維持)
            glBindTexture(GL_TEXTURE_2D, s_atlas_image->texture ? s_atlas_image->texture->id : 0);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            glTexSubImage2D(GL_TEXTURE_2D, 0, dest_x + pad, dest_y + pad, w, h_out, GL_RED, GL_UNSIGNED_BYTE, pixels);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 4);

            if (use_bitmap) {
                stbtt_FreeBitmap(pixels, NULL);
            } else {
                stbtt_FreeSDF(pixels, NULL);
            }

            // UV 座標 (0.0 .. 1.0)
            base_glyph.u0 = (float)dest_x / (float)ATLAS_WIDTH;
            base_glyph.v0 = (float)dest_y / (float)ATLAS_HEIGHT;
            base_glyph.u1 = (float)(dest_x + pack_w) / (float)ATLAS_WIDTH;
            base_glyph.v1 = (float)(dest_y + pack_h) / (float)ATLAS_HEIGHT;

            // 描画オフセット (ベースラインからの相対位置)
            base_glyph.x0 = (float)(xoff - pad);
            base_glyph.y0 = (float)(yoff - pad);
            base_glyph.x1 = (float)(xoff + w + pad);
            base_glyph.y1 = (float)(yoff + h_out + pad);

            s_atlas_x += pack_w + 1;
            if (pack_h > s_atlas_row_h) {
                s_atlas_row_h = pack_h;
            }
        } else {
            base_glyph.visible = 0;
            if (pixels) {
                if (use_bitmap) stbtt_FreeBitmap(pixels, NULL);
                else stbtt_FreeSDF(pixels, NULL);
            }
        }
    }

    // キャッシュに登録
    GlyphEntry* new_entry = (GlyphEntry*)malloc(sizeof(GlyphEntry));
    if (new_entry) {
        new_entry->font_id = font->id;
        new_entry->codepoint = codepoint;
        new_entry->pixel_size = pixel_size;
        new_entry->glyph = base_glyph;
        new_entry->next = s_glyph_hash[h];
        s_glyph_hash[h] = new_entry;
    }

    if (use_bitmap) {
        *out_glyph = base_glyph;
        out_glyph->x0 *= inv_render_scale;
        out_glyph->y0 *= inv_render_scale;
        out_glyph->x1 *= inv_render_scale;
        out_glyph->y1 *= inv_render_scale;
        out_glyph->advance_x *= inv_render_scale;
    } else {
        float scale_ratio = actual_size / SDF_BASE_SIZE;
        *out_glyph = base_glyph;
        out_glyph->x0 *= scale_ratio;
        out_glyph->y0 *= scale_ratio;
        out_glyph->x1 *= scale_ratio;
        out_glyph->y1 *= scale_ratio;
        out_glyph->advance_x *= scale_ratio;
    }

    return 1;
}

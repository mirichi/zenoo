#ifndef ZENOO_H
#define ZENOO_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// カラーヘルパーマクロ (0xRRGGBBAA)
#define ZEN_RGBA(r, g, b, a) (((uint32_t)(r) << 24) | ((uint32_t)(g) << 16) | ((uint32_t)(b) << 8) | (uint32_t)(a))
#define ZEN_RGB(r, g, b)     ZEN_RGBA(r, g, b, 255)

// キーコード定数 (GLFW準拠)
enum ZenKey {
    ZEN_KEY_SPACE         = 32,
    ZEN_KEY_0             = 48,
    ZEN_KEY_1             = 49,
    ZEN_KEY_2             = 50,
    ZEN_KEY_3             = 51,
    ZEN_KEY_4             = 52,
    ZEN_KEY_5             = 53,
    ZEN_KEY_6             = 54,
    ZEN_KEY_7             = 55,
    ZEN_KEY_8             = 56,
    ZEN_KEY_9             = 57,
    ZEN_KEY_A             = 65,
    ZEN_KEY_B             = 66,
    ZEN_KEY_C             = 67,
    ZEN_KEY_D             = 68,
    ZEN_KEY_E             = 69,
    ZEN_KEY_F             = 70,
    ZEN_KEY_G             = 71,
    ZEN_KEY_H             = 72,
    ZEN_KEY_I             = 73,
    ZEN_KEY_J             = 74,
    ZEN_KEY_K             = 75,
    ZEN_KEY_L             = 76,
    ZEN_KEY_M             = 77,
    ZEN_KEY_N             = 78,
    ZEN_KEY_O             = 79,
    ZEN_KEY_P             = 80,
    ZEN_KEY_Q             = 81,
    ZEN_KEY_R             = 82,
    ZEN_KEY_S             = 83,
    ZEN_KEY_T             = 84,
    ZEN_KEY_U             = 85,
    ZEN_KEY_V             = 86,
    ZEN_KEY_W             = 87,
    ZEN_KEY_X             = 88,
    ZEN_KEY_Y             = 89,
    ZEN_KEY_Z             = 90,
    ZEN_KEY_ESCAPE        = 256,
    ZEN_KEY_ENTER         = 257,
    ZEN_KEY_TAB           = 258,
    ZEN_KEY_BACKSPACE     = 259,
    ZEN_KEY_RIGHT         = 262,
    ZEN_KEY_LEFT          = 263,
    ZEN_KEY_DOWN          = 264,
    ZEN_KEY_UP            = 265,
};

enum ZenMouseButton {
    ZEN_MOUSE_LEFT        = 0,
    ZEN_MOUSE_RIGHT       = 1,
    ZEN_MOUSE_MIDDLE      = 2,
};

// ==========================================
// 1. システム & ライフサイクル API
// ==========================================
int  zen_init(int width, int height, const char* title);
int  zen_init_fullscreen(const char* title); // 全画面 (排他フルスクリーン) で初期化
void zen_toggle_fullscreen(void);            // フルスクリーンとウィンドウの切り替え
void zen_shutdown(void);

// 【ハイブリッド方式 A】DXRuby風の手軽なメインループ用 (1行でPresent/入力/時間更新/終了判定)
// 使用例: while (zen_update()) { zen_clear(0x181818FF); zen_draw_rect(...); }
int  zen_update(void);
void zen_clear(uint32_t color);

// 【ハイブリッド方式 B】ロジックと描画を明示的に分離したい場合用
int  zen_window_should_close(void);
void zen_poll_events(void);                 // 純粋に入力・OSイベント・時間更新のみ
void zen_begin_frame(uint32_t clear_color); // 純粋に描画開始・クリアのみ
void zen_end_frame(void);                   // 純粋に描画Flush・SwapBuffers(Present)のみ

// 時間 & ウィンドウ情報 & フレームレート制御
double zen_get_time(void);
float  zen_get_delta_time(void);
void   zen_get_window_size(int* width, int* height);
void   zen_set_target_fps(int fps); // 目標FPS設定 (デフォルト60fps固定。0で無制限)
int    zen_get_target_fps(void);
void   zen_set_vsync(int vsync);    // 1: VSync有効, 0: VSync無効

// 入力 API
void   zen_get_mouse_pos(float* x, float* y);
int    zen_is_mouse_pressed(int button); // 押されている状態 (持続)
int    zen_is_mouse_push(int button);    // 押した瞬間 (トリガー)
int    zen_is_mouse_release(int button); // 離した瞬間 (リリース)

int    zen_is_key_pressed(int key);      // 押されている状態 (持続)
int    zen_is_key_push(int key);         // 押した瞬間 (トリガー)
int    zen_is_key_release(int key);      // 離した瞬間 (リリース)

// ゲームパッド (GLFW標準ゲームパッドマッピング準拠)
enum ZenGamepadButton {
    ZEN_GAMEPAD_BUTTON_A            = 0,
    ZEN_GAMEPAD_BUTTON_B            = 1,
    ZEN_GAMEPAD_BUTTON_X            = 2,
    ZEN_GAMEPAD_BUTTON_Y            = 3,
    ZEN_GAMEPAD_BUTTON_LEFT_BUMPER  = 4,
    ZEN_GAMEPAD_BUTTON_RIGHT_BUMPER = 5,
    ZEN_GAMEPAD_BUTTON_BACK         = 6,
    ZEN_GAMEPAD_BUTTON_START        = 7,
    ZEN_GAMEPAD_BUTTON_GUIDE        = 8,
    ZEN_GAMEPAD_BUTTON_LEFT_THUMB   = 9,
    ZEN_GAMEPAD_BUTTON_RIGHT_THUMB  = 10,
    ZEN_GAMEPAD_BUTTON_DPAD_UP      = 11,
    ZEN_GAMEPAD_BUTTON_DPAD_RIGHT   = 12,
    ZEN_GAMEPAD_BUTTON_DPAD_DOWN    = 13,
    ZEN_GAMEPAD_BUTTON_DPAD_LEFT    = 14,
};

enum ZenGamepadAxis {
    ZEN_GAMEPAD_AXIS_LEFT_X         = 0,
    ZEN_GAMEPAD_AXIS_LEFT_Y         = 1,
    ZEN_GAMEPAD_AXIS_RIGHT_X        = 2,
    ZEN_GAMEPAD_AXIS_RIGHT_Y        = 3,
    ZEN_GAMEPAD_AXIS_LEFT_TRIGGER   = 4,
    ZEN_GAMEPAD_AXIS_RIGHT_TRIGGER  = 5,
};

int    zen_is_gamepad_connected(int id);
float  zen_get_gamepad_axis(int id, int axis);
int    zen_is_gamepad_button_pressed(int id, int button);
int    zen_is_gamepad_button_push(int id, int button);
int    zen_is_gamepad_button_release(int id, int button);

// ==========================================
// 2. 画像 (Image) & オフスクリーン描画 API
// ==========================================
struct ZenImage {
    uint32_t texture_id;
    uint32_t fbo;
    int width;
    int height;
    int has_fbo;
};
typedef struct ZenImage ZenImage;

// 画像生成 & ロード
ZenImage* zen_image_create(int width, int height);
ZenImage* zen_image_load(const char* filepath);
ZenImage* zen_image_create_from_pixels(int width, int height, const uint32_t* pixels);
void      zen_image_destroy(ZenImage* image);
void      zen_image_get_size(const ZenImage* image, int* width, int* height);
uint32_t  zen_image_get_texture_id(const ZenImage* image);

// 描画先ターゲットの切り替え (NULL でメイン画面に戻る)
void      zen_set_render_target(ZenImage* target);

// ==========================================
// 3. 汎用シェーダー (Shader) API
// ==========================================
typedef struct ZenShader ZenShader;

ZenShader* zen_shader_create(const char* vert_src, const char* frag_src);
void       zen_shader_destroy(ZenShader* shader);

void       zen_shader_set_int(ZenShader* shader, const char* name, int value);
void       zen_shader_set_float(ZenShader* shader, const char* name, float value);
void       zen_shader_set_vec2(ZenShader* shader, const char* name, float x, float y);
void       zen_shader_set_vec3(ZenShader* shader, const char* name, float x, float y, float z);
void       zen_shader_set_vec4(ZenShader* shader, const char* name, float x, float y, float z, float w);
void       zen_shader_set_mat4(ZenShader* shader, const char* name, const float* mat4);

// ==========================================
// 4. 汎用 Quad バッチ & GC フック
// ==========================================
// メモリ不足時に言語側 (CRubyのrb_gc()やSpinelのGC) を呼び出すためのコールバック
void       zen_set_gc_trigger_callback(void (*callback)(void));

// 汎用Quad送出 (x, y, w, h, uv[4], color[4], param0[4], param1[4], param2[4], texture, shader)
void       zen_draw_quad_generic(float x, float y, float w, float h,
                                 const float uv[4],
                                 const float color[4],
                                 const float p0[4],
                                 const float p1[4],
                                 const float p2[4],
                                 ZenImage* texture,
                                 ZenShader* shader);
void       zen_draw_triangle(float x1, float y1, float x2, float y2, float x3, float y3, const float color[4]);
void       zen_draw_line(float x1, float y1, float x2, float y2, const float color[4]);
void       zen_flush(void);

// ==========================================
// 5. フォント (Font) & 動的SDFテクスチャアトラス API
// ==========================================
typedef struct ZenFont ZenFont;

typedef struct {
    int   codepoint;
    float u0, v0, u1, v1; // テクスチャアトラス上のUV (0.0 .. 1.0)
    float x0, y0, x1, y1; // ベースライン原点からの描画オフセット (ピクセル)
    float advance_x;      // 次の文字までの送り幅 (ピクセル)
    int   visible;        // 描画が必要か (空白文字は 0)
} ZenGlyph;

ZenFont*  zen_font_load(const char* filepath);
ZenFont*  zen_font_load_memory(const unsigned char* data, size_t size);
void      zen_font_destroy(ZenFont* font);
int       zen_font_get_glyph(ZenFont* font, int codepoint, float font_size, ZenGlyph* out_glyph);
void      zen_font_get_metrics(ZenFont* font, float font_size, float* ascent, float* descent, float* line_gap);
ZenImage* zen_font_get_atlas_image(void);

#ifdef __cplusplus
}
#endif

#endif // ZENOO_H

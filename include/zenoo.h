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

// スケーリングモード
enum {
    ZEN_SCALE_FIT     = 0, // アスペクト比維持の最大化 (余白黒帯)
    ZEN_SCALE_INTEGER = 1, // 整数倍スケーリング (ドット絵用、余白黒帯)
};

// テクスチャフィルタ
enum {
    ZEN_FILTER_NEAREST = 0, // GL_NEAREST (ドット絵クッキリ)
    ZEN_FILTER_LINEAR  = 1, // GL_LINEAR (滑らかバイリニア)
};

// ==========================================
// 1. システム & ライフサイクル API
// ==========================================
int  zen_init(int width, int height, const char* title);
int  zen_init_scaled(int base_width, int base_height, const char* title, int window_width, int window_height);
int  zen_init_fullscreen(const char* title); // 全画面 (排他フルスクリーン) で初期化
void zen_toggle_fullscreen(void);            // フルスクリーンとウィンドウの切り替え
void zen_shutdown(void);

// 【ハイブリッド方式 A】DXRuby風の手軽なメインループ用 (1行でPresent/入力/時間更新/終了判定)
// 使用例: while (zen_update()) { zen_clear(0x181818FF); zen_draw_rect(...); }
int  zen_update(void);
void zen_clear(uint32_t color);

// Wasm (Emscripten) requestAnimationFrame 駆動用 API
typedef void (*zen_step_callback_fn)(void);
void zen_set_step_callback(zen_step_callback_fn fn);
void zen_start_wasm_loop(void);
int  zen_is_wasm(void);

// 【ハイブリッド方式 B】ロジックと描画を明示的に分離したい場合用
int  zen_window_should_close(void);
void zen_poll_events(void);                 // 純粋に入力・OSイベント・時間更新のみ
void zen_begin_frame(uint32_t clear_color); // 純粋に描画開始・クリアのみ
void zen_end_frame(void);                   // 純粋に描画Flush・SwapBuffers(Present)のみ

// 時間 & ウィンドウ情報 & フレームレート制御 & スケーリング
double zen_get_time(void);
float  zen_get_delta_time(void);
void   zen_get_window_size(int* width, int* height);
void   zen_get_os_window_size(int* width, int* height);
void   zen_set_window_size(int width, int height);
void   zen_set_scale_mode(int mode);
int    zen_get_scale_mode(void);
float  zen_get_scale(void);
int    zen_is_window_active(void);
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
int    zen_is_key_repeat(int key);       // 押した瞬間またはOSキーリピート時

// テキスト入力 & IME
int    zen_get_char_queue(uint32_t* buffer, int max_count);
int    zen_get_char(void);
void   zen_push_char(unsigned int codepoint);
void   zen_set_ime_position(int x, int y);

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
// 2. テクスチャ (Texture) & 画像 (Image) API
// ==========================================
struct ZenTexture {
    uint32_t id;         // OpenGL テクスチャ ID
    int width;           // 物理テクスチャ幅
    int height;          // 物理テクスチャ高さ
    int ref_count;       // 参照カウンタ (共有している ZenImage の数)
    int filter;          // テクスチャフィルタ (ZEN_FILTER_NEAREST / ZEN_FILTER_LINEAR)
};
typedef struct ZenTexture ZenTexture;

struct ZenImage {
    ZenTexture* texture; // GPU テクスチャ実体への参照
    int x;               // テクスチャ内の切り出し開始 X
    int y;               // テクスチャ内の切り出し開始 Y
    int width;           // この Image の論理幅 (切り出し幅)
    int height;          // この Image の論理高さ (切り出し高さ)
    uint32_t fbo;        // オフスクリーン描画用 FBO
    int has_fbo;
};
typedef struct ZenImage ZenImage;

// テクスチャ実体操作
ZenTexture* zen_texture_create(int width, int height);
void        zen_texture_release(ZenTexture* texture);

// テクスチャフィルタ設定
void      zen_set_default_texture_filter(int filter);
int       zen_get_default_texture_filter(void);
void      zen_image_set_filter(ZenImage* image, int filter);
int       zen_image_get_filter(const ZenImage* image);

// 画像生成 & ロード & サブ画像切り出し
ZenImage* zen_image_create(int width, int height);
ZenImage* zen_image_load(const char* filepath);
ZenImage* zen_image_create_from_pixels(int width, int height, const uint32_t* pixels);
ZenImage* zen_image_sub_image(ZenImage* parent, int x, int y, int width, int height);
void      zen_image_destroy(ZenImage* image);
void      zen_image_get_size(const ZenImage* image, int* width, int* height);
void      zen_image_get_bounds(const ZenImage* image, int* x, int* y, int* w, int* h);
void      zen_image_get_texture_size(const ZenImage* image, int* tex_w, int* tex_h);
void      zen_image_get_uv(const ZenImage* image, float* u, float* v, float* uw, float* vh);
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

void       zen_flush(void);

// ビューポート & クリッピング (glScissor)
void       zen_get_viewport_info(int* vp_x, int* vp_y, int* vp_w, int* vp_h, float* vp_scale, int* base_h);
void       zen_set_scissor(int x, int y, int w, int h);
void       zen_reset_scissor(void);

// トポロジー種別定数 (OpenGL GLenum準拠)
enum ZenTopology {
    ZEN_TOPOLOGY_POINTS         = 0, // GL_POINTS
    ZEN_TOPOLOGY_LINES          = 1, // GL_LINES
    ZEN_TOPOLOGY_LINE_LOOP      = 2, // GL_LINE_LOOP
    ZEN_TOPOLOGY_LINE_STRIP     = 3, // GL_LINE_STRIP
    ZEN_TOPOLOGY_TRIANGLES      = 4, // GL_TRIANGLES
    ZEN_TOPOLOGY_TRIANGLE_STRIP = 5, // GL_TRIANGLE_STRIP
    ZEN_TOPOLOGY_TRIANGLE_FAN   = 6  // GL_TRIANGLE_FAN
};

// 汎用動的頂点バッファ描画 API (1バイト属性列 & Divisor列 & バイナリバッファ)
void       zen_draw_buffer(int topology,
                           const uint8_t* layout,
                           const uint8_t* divisors,
                           int base_vertex_count,
                           const void* vertex_data,
                           int count,
                           ZenImage* texture,
                           ZenShader* shader);

// ブレンドモード定数と制御 API
enum ZenBlendMode {
    ZEN_BLEND_ALPHA    = 0, // 通常アルファブレンド
    ZEN_BLEND_ADD      = 1, // 加算合成
    ZEN_BLEND_MULTIPLY = 2, // 乗算合成
    ZEN_BLEND_NONE     = 3  // ブレンド無効
};

void       zen_set_blend_mode(int mode);

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
    int   is_bitmap;      // 直接ラスタライズビットマップなら 1, SDFなら 0
} ZenGlyph;

ZenFont*  zen_font_load(const char* filepath);
ZenFont*  zen_font_load_memory(const unsigned char* data, size_t size);
void      zen_font_destroy(ZenFont* font);
int       zen_font_get_glyph(ZenFont* font, int codepoint, float font_size, ZenGlyph* out_glyph);
void      zen_font_get_metrics(ZenFont* font, float font_size, float* ascent, float* descent, float* line_gap);
ZenImage* zen_font_get_atlas_image(void);

// ==========================================
// 6. オーディオ (Audio & Sound) API
// ==========================================
typedef struct ZenSound ZenSound;

// オーディオシステム初期化・終了
int   zen_audio_init(void);
void  zen_audio_shutdown(void);
void  zen_audio_set_master_volume(float volume);
float zen_audio_get_master_volume(void);

// サウンドの生成・破棄
ZenSound* zen_sound_load_file(const char* filepath);
ZenSound* zen_sound_load_memory_pcm(const float* frames, int frame_count, int channels, int sample_rate);
void      zen_sound_destroy(ZenSound* sound);

// 再生制御
void  zen_sound_play(ZenSound* sound);
void  zen_sound_stop(ZenSound* sound);
void  zen_sound_pause(ZenSound* sound);
int   zen_sound_is_playing(const ZenSound* sound);

// パラメータ制御
void  zen_sound_set_volume(ZenSound* sound, float volume);
float zen_sound_get_volume(const ZenSound* sound);
void  zen_sound_set_looping(ZenSound* sound, int looping);
int   zen_sound_is_looping(const ZenSound* sound);
void  zen_sound_set_pitch(ZenSound* sound, float pitch);
float zen_sound_get_pitch(const ZenSound* sound);
void  zen_sound_set_pan(ZenSound* sound, float pan);
float zen_sound_get_pan(const ZenSound* sound);

// シーク & 時間情報
void  zen_sound_seek(ZenSound* sound, float seconds);
float zen_sound_get_cursor(const ZenSound* sound);
float zen_sound_get_length(const ZenSound* sound);

#ifdef __cplusplus
}
#endif

#endif // ZENOO_H

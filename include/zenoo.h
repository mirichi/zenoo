#ifndef ZENOO_H
#define ZENOO_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ZENOO_VERSION "0.3.0"

// カラーヘルパーマクロ (0xRRGGBBAA)
#define ZEN_RGBA(r, g, b, a) (((uint32_t)(r) << 24) | ((uint32_t)(g) << 16) | ((uint32_t)(b) << 8) | (uint32_t)(a))
#define ZEN_RGB(r, g, b)     ZEN_RGBA(r, g, b, 255)

// キーコード定数 (SDL_Scancode 準拠)
enum ZenKey {
    ZEN_KEY_A             = 4,
    ZEN_KEY_B             = 5,
    ZEN_KEY_C             = 6,
    ZEN_KEY_D             = 7,
    ZEN_KEY_E             = 8,
    ZEN_KEY_F             = 9,
    ZEN_KEY_G             = 10,
    ZEN_KEY_H             = 11,
    ZEN_KEY_I             = 12,
    ZEN_KEY_J             = 13,
    ZEN_KEY_K             = 14,
    ZEN_KEY_L             = 15,
    ZEN_KEY_M             = 16,
    ZEN_KEY_N             = 17,
    ZEN_KEY_O             = 18,
    ZEN_KEY_P             = 19,
    ZEN_KEY_Q             = 20,
    ZEN_KEY_R             = 21,
    ZEN_KEY_S             = 22,
    ZEN_KEY_T             = 23,
    ZEN_KEY_U             = 24,
    ZEN_KEY_V             = 25,
    ZEN_KEY_W             = 26,
    ZEN_KEY_X             = 27,
    ZEN_KEY_Y             = 28,
    ZEN_KEY_Z             = 29,
    ZEN_KEY_1             = 30,
    ZEN_KEY_2             = 31,
    ZEN_KEY_3             = 32,
    ZEN_KEY_4             = 33,
    ZEN_KEY_5             = 34,
    ZEN_KEY_6             = 35,
    ZEN_KEY_7             = 36,
    ZEN_KEY_8             = 37,
    ZEN_KEY_9             = 38,
    ZEN_KEY_0             = 39,
    ZEN_KEY_ENTER         = 40,
    ZEN_KEY_ESCAPE        = 41,
    ZEN_KEY_BACKSPACE     = 42,
    ZEN_KEY_TAB           = 43,
    ZEN_KEY_SPACE         = 44,
    ZEN_KEY_MINUS         = 45,
    ZEN_KEY_EQUAL         = 46,
    ZEN_KEY_LEFT_BRACKET  = 47,
    ZEN_KEY_RIGHT_BRACKET = 48,
    ZEN_KEY_BACKSLASH     = 49,
    ZEN_KEY_SEMICOLON     = 51,
    ZEN_KEY_APOSTROPHE    = 52,
    ZEN_KEY_GRAVE_ACCENT  = 53,
    ZEN_KEY_COMMA         = 54,
    ZEN_KEY_PERIOD        = 55,
    ZEN_KEY_SLASH         = 56,
    ZEN_KEY_CAPS_LOCK     = 57,
    ZEN_KEY_F1            = 58,
    ZEN_KEY_F2            = 59,
    ZEN_KEY_F3            = 60,
    ZEN_KEY_F4            = 61,
    ZEN_KEY_F5            = 62,
    ZEN_KEY_F6            = 63,
    ZEN_KEY_F7            = 64,
    ZEN_KEY_F8            = 65,
    ZEN_KEY_F9            = 66,
    ZEN_KEY_F10           = 67,
    ZEN_KEY_F11           = 68,
    ZEN_KEY_F12           = 69,
    ZEN_KEY_PRINT_SCREEN  = 70,
    ZEN_KEY_SCROLL_LOCK   = 71,
    ZEN_KEY_PAUSE         = 72,
    ZEN_KEY_INSERT        = 73,
    ZEN_KEY_HOME          = 74,
    ZEN_KEY_PAGE_UP       = 75,
    ZEN_KEY_DELETE        = 76,
    ZEN_KEY_END           = 77,
    ZEN_KEY_PAGE_DOWN     = 78,
    ZEN_KEY_RIGHT         = 79,
    ZEN_KEY_LEFT          = 80,
    ZEN_KEY_DOWN          = 81,
    ZEN_KEY_UP            = 82,
    ZEN_KEY_NUM_LOCK      = 83,
    ZEN_KEY_KP_DIVIDE     = 84,
    ZEN_KEY_KP_MULTIPLY   = 85,
    ZEN_KEY_KP_SUBTRACT   = 86,
    ZEN_KEY_KP_ADD        = 87,
    ZEN_KEY_KP_ENTER      = 88,
    ZEN_KEY_KP_1          = 89,
    ZEN_KEY_KP_2          = 90,
    ZEN_KEY_KP_3          = 91,
    ZEN_KEY_KP_4          = 92,
    ZEN_KEY_KP_5          = 93,
    ZEN_KEY_KP_6          = 94,
    ZEN_KEY_KP_7          = 95,
    ZEN_KEY_KP_8          = 96,
    ZEN_KEY_KP_9          = 97,
    ZEN_KEY_KP_0          = 98,
    ZEN_KEY_KP_DECIMAL    = 99,
    ZEN_KEY_MENU          = 101,
    ZEN_KEY_KP_EQUAL      = 103,
    ZEN_KEY_LEFT_CONTROL  = 224,
    ZEN_KEY_LEFT_SHIFT    = 225,
    ZEN_KEY_LEFT_ALT      = 226,
    ZEN_KEY_LEFT_SUPER    = 227,
    ZEN_KEY_RIGHT_CONTROL = 228,
    ZEN_KEY_RIGHT_SHIFT   = 229,
    ZEN_KEY_RIGHT_ALT     = 230,
    ZEN_KEY_RIGHT_SUPER   = 231,
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
    ZEN_SCALE_RESIZE  = 2, // ウィンドウリサイズに論理解像度を追従 (DPI独立)
};

// テクスチャフィルタ
enum {
    ZEN_FILTER_NEAREST = 0, // GL_NEAREST (ドット絵クッキリ)
    ZEN_FILTER_LINEAR  = 1, // GL_LINEAR (滑らかバイリニア)
};

// ==========================================
// 1. システム & ライフサイクル API
// ==========================================
int  zen_ensure_context(void); // 必要に応じて非表示ウィンドウ&GLコンテキストを先行初期化
int  zen_init(int width, int height, const char* title);
int  zen_init_scaled(int base_width, int base_height, const char* title, int window_width, int window_height);
int  zen_init_scaled_ex(int base_width, int base_height, const char* title, int window_width, int window_height, float scale);
int  zen_init_fullscreen(const char* title); // 全画面 (排他フルスクリーン) で初期化
void zen_toggle_fullscreen(void);            // フルスクリーンとウィンドウの切り替え
void zen_shutdown(void);
const char* zen_get_version(void);

// ------------------------------------------
// フレーム制御
// ------------------------------------------
// 1フレームは必ず「begin_frame → (clear・描画) → end_frame」の順で進む。
// 各関数は自分の役割だけを行い、互いを呼び合わない (zen_update を除く)。
//
//   方式A (DXRuby風):  while (zen_update()) { zen_clear(0x181818FF); ...描画... }
//   方式B (明示):      while (zen_begin_frame()) { zen_clear(c); ...描画...; zen_end_frame(); }
//   方式C (コールバック): zen_run_loop(frame_fn);  // Wasm ではこれを使う
//
int  zen_begin_frame(void);      // 入力・時間の更新と画面描画の準備。終了要求があれば 0 を返す
void zen_end_frame(void);        // 画面への表示 (SwapBuffers) と目標FPSまでの待機
int  zen_update(void);           // 「前フレームの zen_end_frame + zen_begin_frame」の省略形
void zen_clear(uint32_t color);  // 現在の描画先 (画面のゲーム領域 or レンダーターゲット) を塗りつぶすだけ

// フレームごとに fn を呼ぶメインループ。
// ネイティブ: ウィンドウが閉じられるまでブロックする。
// Wasm      : requestAnimationFrame に登録して即座に戻る。
typedef void (*zen_frame_fn)(void);
void zen_run_loop(zen_frame_fn fn);
void zen_set_frame_callback(zen_frame_fn fn);
int  zen_is_wasm(void);

// ウィンドウ移動・リサイズ中のライブ更新制御
void zen_set_live_resize(int enabled);
int  zen_get_live_resize(void);
int  zen_is_resizing(void);

// 時間 & ウィンドウ情報 & フレームレート制御 & スケーリング
double zen_get_time(void);
float  zen_get_delta_time(void);
void   zen_get_screen_size(int* width, int* height);  // 仮想解像度 (ゲーム内の論理座標系)
void   zen_get_window_size(int* width, int* height);  // OS ウィンドウのサイズ
void   zen_set_window_size(int width, int height);    // OS ウィンドウのサイズ変更
void   zen_set_window_title(const char* title);       // ウィンドウタイトルの動的変更
const char* zen_get_window_title(void);              // ウィンドウタイトルの取得
void   zen_get_window_pos(int* x, int* y);            // OS ウィンドウの位置取得
void   zen_set_window_pos(int x, int y);              // OS ウィンドウの位置変更
int    zen_is_window_focused(void);                  // フォーカス状態
int    zen_is_window_minimized(void);                // 最小化 (アイコン化) 状態
int    zen_is_window_maximized(void);                // 最大化状態
int    zen_is_window_hovered(void);                  // マウスカーソルがウィンドウ内にあるか
void   zen_set_scale_mode(int mode);
int    zen_get_scale_mode(void);
float  zen_get_scale(void);
void   zen_set_window_scale(float scale);
float  zen_get_window_scale(void);
float  zen_get_dpi_scale(void);
void   zen_set_target_fps(int fps); // 目標FPS設定 (デフォルト60fps固定。0で無制限)
int    zen_get_target_fps(void);
void   zen_set_vsync(int vsync);    // 1: VSync有効, 0: VSync無効
void   zen_window_set_msaa_samples(int samples); // ウィンドウ直接描画のMSAAサンプル数 (デフォルト0: 無効, 4等で有効化)
int    zen_window_get_msaa_samples(void);

// マウスカーソル & クリップボード
enum ZenCursorShape {
    ZEN_CURSOR_ARROW       = 0,
    ZEN_CURSOR_IBEAM       = 1,
    ZEN_CURSOR_CROSSHAIR   = 2,
    ZEN_CURSOR_HAND        = 3,
    ZEN_CURSOR_HRESIZE     = 4,
    ZEN_CURSOR_VRESIZE     = 5,
    ZEN_CURSOR_RESIZE_NWSE = 6,
    ZEN_CURSOR_RESIZE_NESW = 7,
    ZEN_CURSOR_RESIZE_ALL  = 8,
    ZEN_CURSOR_NOT_ALLOWED = 9
};

void        zen_window_show_cursor(int show);
void        zen_window_set_cursor(int shape);
const char* zen_window_get_clipboard_string(void);
void        zen_window_set_clipboard_string(const char* text);

// 入力 API
void   zen_get_mouse_pos(float* x, float* y);
int    zen_is_mouse_pressed(int button); // 押されている状態 (持続)
int    zen_is_mouse_push(int button);    // 押した瞬間 (トリガー)
int    zen_is_mouse_release(int button); // 離した瞬間 (リリース)
float  zen_get_mouse_wheel_x(void);
float  zen_get_mouse_wheel_y(void);

int    zen_is_key_pressed(int key);      // 押されている状態 (持続)
int    zen_is_key_push(int key);         // 押した瞬間 (トリガー)
int    zen_is_key_release(int key);      // 離した瞬間 (リリース)
int    zen_is_key_repeat(int key);       // 押した瞬間またはOSキーリピート時

// テキスト入力 & IME
int    zen_get_char_queue(uint32_t* buffer, int max_count);
int    zen_get_char(void);
void   zen_push_char(unsigned int codepoint);
void   zen_set_ime_position(int x, int y);

// タッチ入力 (生イベントキュー)
#define ZEN_TOUCH_QUEUE_MAX 128
void   zen_push_touch(int id, int type, float win_x, float win_y);
int    zen_get_touch_count(void);
int    zen_get_touch_event_id(int idx);
int    zen_get_touch_event_type(int idx);
float  zen_get_touch_event_x(int idx);
float  zen_get_touch_event_y(int idx);
void   zen_clear_touch_events(void);

// ゲームパッド (SDL_GamepadButton / SDL_GamepadAxis 準拠)
enum ZenGamepadButton {
    ZEN_GAMEPAD_BUTTON_A            = 0,
    ZEN_GAMEPAD_BUTTON_B            = 1,
    ZEN_GAMEPAD_BUTTON_X            = 2,
    ZEN_GAMEPAD_BUTTON_Y            = 3,
    ZEN_GAMEPAD_BUTTON_BACK         = 4,
    ZEN_GAMEPAD_BUTTON_GUIDE        = 5,
    ZEN_GAMEPAD_BUTTON_START        = 6,
    ZEN_GAMEPAD_BUTTON_LEFT_THUMB   = 7,
    ZEN_GAMEPAD_BUTTON_RIGHT_THUMB  = 8,
    ZEN_GAMEPAD_BUTTON_LEFT_BUMPER  = 9,
    ZEN_GAMEPAD_BUTTON_RIGHT_BUMPER = 10,
    ZEN_GAMEPAD_BUTTON_DPAD_UP      = 11,
    ZEN_GAMEPAD_BUTTON_DPAD_DOWN    = 12,
    ZEN_GAMEPAD_BUTTON_DPAD_LEFT    = 13,
    ZEN_GAMEPAD_BUTTON_DPAD_RIGHT   = 14,
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
void   zen_gamepad_vibrate(int id, float strong, float weak, float duration);
void   zen_vibrate(float duration);

// ==========================================
// 2. テクスチャ (Texture) & 画像 (Image) API
// ==========================================
struct ZenTexture {
    uint32_t id;         // OpenGL テクスチャ ID
    int width;           // 物理テクスチャ幅
    int height;          // 物理テクスチャ高さ
    int ref_count;       // 参照カウンタ (共有している ZenImage の数)
    int filter;          // テクスチャフィルタ (ZEN_FILTER_NEAREST / ZEN_FILTER_LINEAR)
    int format;          // ピクセルフォーマット (ZEN_IMAGE_FORMAT_RGBA / ZEN_IMAGE_FORMAT_R8)
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
    uint32_t msaa_fbo;   // MSAA用 FBO (0なら未生成)
    uint32_t msaa_rbo;   // MSAA用 レンダーバッファ (0なら未生成)
    int msaa_samples;   // MSAAサンプル数 (0なら無効、通常4)
    uint32_t* pixels;   // CPU側ピクセルバッファ (RGBA)
    int cpu_dirty;      // CPU側がGPUより古い場合 1
    int gpu_dirty;      // GPU側がCPUより古い場合 1
};
typedef struct ZenImage ZenImage;

// テクスチャフィルタ設定
void      zen_set_default_texture_filter(int filter);
int       zen_get_default_texture_filter(void);
void      zen_image_set_filter(ZenImage* image, int filter);
int       zen_image_get_filter(const ZenImage* image);
void      zen_image_set_texture_filter(ZenImage* image, int filter);
int       zen_image_get_texture_filter(const ZenImage* image);
void      zen_image_replace_texture(ZenImage* dst, ZenImage* src);

enum ZenImageFormat {
    ZEN_IMAGE_FORMAT_RGBA = 0,
    ZEN_IMAGE_FORMAT_R8   = 1
};

// 画像生成 & ロード & サブ画像切り出し
ZenImage* zen_image_create(int width, int height);
ZenImage* zen_image_create_format(int width, int height, int format);
ZenImage* zen_image_create_msaa(int width, int height, int samples);
ZenImage* zen_image_load(const char* filepath);
ZenImage* zen_image_create_from_pixels(int width, int height, const uint32_t* pixels);
ZenImage* zen_image_sub_image(ZenImage* parent, int x, int y, int width, int height);
ZenImage* zen_image_clone(const ZenImage* image);
void      zen_image_destroy(ZenImage* image);
void      zen_image_resolve_msaa(ZenImage* image);
void      zen_image_get_size(const ZenImage* image, int* width, int* height);
void      zen_image_get_bounds(const ZenImage* image, int* x, int* y, int* w, int* h);
void      zen_image_get_texture_size(const ZenImage* image, int* tex_w, int* tex_h);
void      zen_image_get_uv(const ZenImage* image, float* u, float* v, float* uw, float* vh);
uint32_t  zen_image_get_texture_id(const ZenImage* image);

// ピクセル直接アクセス & 保存
uint32_t  zen_image_get_pixel(ZenImage* image, int x, int y);
void      zen_image_set_pixel(ZenImage* image, int x, int y, uint32_t color);
void      zen_image_get_pixels(ZenImage* image, uint32_t* out_pixels);
void      zen_image_set_pixels(ZenImage* image, const uint32_t* in_pixels);
void      zen_image_sync_to_gpu(ZenImage* image);
int       zen_image_save(ZenImage* image, const char* filepath);

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
void       zen_shader_set_vec4_array(ZenShader* shader, const char* name, int count, const float* vec4_data);
void       zen_shader_set_mat4(ZenShader* shader, const char* name, const float* mat4);
void       zen_shader_set_texture(ZenShader* shader, const char* name, int unit, ZenImage* image);

// ==========================================
// 4. 汎用 Quad バッチ & GC フック
// ==========================================
// メモリ不足時に言語側 (CRubyのrb_gc()やSpinelのGC) を呼び出すためのコールバック
void       zen_set_gc_trigger_callback(void (*callback)(void));

// クリッピング (glScissor)
// 座標は現在の描画先の論理座標。描画先を切り替えるとクリップは解除される。
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

// ==========================================
// 4.5. メッシュ (ZenMesh: VRAM VBO/IBO & 2バッファインスタンシング)
// ==========================================
typedef struct ZenMesh {
    uint32_t vbo;          // バッファ ID (Stream 0 頂点VBO または Stream 1 インスタンスVBO)
    uint32_t ibo;          // インデックスバッファ ID (0 = 未使用)
    int      vertex_count; // 要素数 (頂点数 または インスタンス数)
    int      index_count;  // インデックス数 (0 = インデックスなし)
    int      topology;     // ZEN_TOPOLOGY_TRIANGLES 等
    int      is_dynamic;   // 0 = GL_STATIC_DRAW, 1 = GL_DYNAMIC_DRAW (自動昇格)
    size_t   vbo_bytes;    // 現在のVBO確保バイト数
    size_t   ibo_bytes;    // 現在のIBO確保バイト数
    uint8_t  layout[16];   // 属性レイアウト (null終端バイト列, 例: "\x02\x02\x01")
} ZenMesh;

ZenMesh*   zen_mesh_create(int topology,
                           const uint8_t* layout,
                           const void* vertex_data,
                           size_t vertex_bytes,
                           int vertex_count,
                           const uint32_t* index_data,
                           int index_count);
void       zen_mesh_destroy(ZenMesh* mesh);
void       zen_mesh_update_vertices(ZenMesh* mesh,
                                    size_t offset_bytes,
                                    const void* vertex_data,
                                    size_t byte_size,
                                    int vertex_count);
void       zen_mesh_update_indices(ZenMesh* mesh,
                                   const uint32_t* index_data,
                                   int index_count);

// 2ストリームVBO (Stream 0: 頂点VBO [geom_mesh または s_quad_vbo] + IBO, Stream 1: インスタンスVBO [inst_buffer または inst_data]) 描画 API
void       zen_draw_mesh_instanced(ZenMesh* geom_mesh,
                                   ZenMesh* inst_buffer,
                                   const uint8_t* inst_layout,
                                   const void* inst_data,
                                   int instance_count,
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

enum ZenFontMode {
    ZEN_FONT_MODE_AUTO   = 0,
    ZEN_FONT_MODE_SDF    = 1,
    ZEN_FONT_MODE_BITMAP = 2
};

ZenFont*     zen_font_load(const char* filepath, int index);
ZenFont*     zen_font_load_memory(const unsigned char* data, size_t size, int index);
void         zen_font_destroy(ZenFont* font);
int          zen_font_get_glyph(ZenFont* font, int codepoint, float font_size, int mode, float render_scale, ZenGlyph* out_glyph);
void         zen_font_get_metrics(ZenFont* font, float font_size, float* ascent, float* descent, float* line_gap);
void         zen_font_set_atlas_image(ZenImage* image);
ZenImage*    zen_font_get_atlas_image(void);
unsigned int zen_font_atlas_generation(void);

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
ZenSound* zen_sound_load_file(const char* filepath, int stream);
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
void     zen_sound_seek(ZenSound* sound, float seconds);
float    zen_sound_get_cursor(const ZenSound* sound);
float    zen_sound_get_length(const ZenSound* sound);
uint32_t zen_sound_get_sample_rate(const ZenSound* sound);
uint64_t zen_sound_get_length_pcm(const ZenSound* sound);

// ループポイント制御 (イントロ付きループ等)
void     zen_sound_set_loop_points_pcm(ZenSound* sound, uint64_t start_frame, uint64_t end_frame);
void     zen_sound_get_loop_points_pcm(const ZenSound* sound, uint64_t* out_start, uint64_t* out_end);
void     zen_sound_set_loop_points_seconds(ZenSound* sound, float start_sec, float end_sec);
void     zen_sound_get_loop_points_seconds(const ZenSound* sound, float* out_start, float* out_end);
int      zen_sound_has_loop_points(const ZenSound* sound);
void     zen_sound_clear_loop_points(ZenSound* sound);

// ------------------------------------------
// ブラウザ / Web 連携ブリッジ
// ------------------------------------------
void        zen_js_eval(const char* code);
double      zen_js_eval_num(const char* code);
const char* zen_js_eval_str(const char* code);
int         zen_js_is_page_visible(void);
void        zen_js_get_safe_area(float* left, float* top, float* right, float* bottom);

// ------------------------------------------
// FFI シム API (Spinel / CRuby 共通)
// ------------------------------------------
void zen_ffi_destroy_handle(void* ptr, int kind);
int  zen_ffi_image_free_count(void);

int   zen_ffi_win_init(int w, int h, const char* title, int fullscreen);
int   zen_ffi_win_init_scaled(int base_w, int base_h, const char* title, int win_w, int win_h, int fullscreen, float scale);
int   zen_ffi_screen_w(void);
int   zen_ffi_screen_h(void);
int   zen_ffi_window_w(void);
int   zen_ffi_window_h(void);
int   zen_ffi_window_pos_x(void);
int   zen_ffi_window_pos_y(void);
void  zen_ffi_clear_frame_callback(void);

float zen_ffi_mouse_x(void);
float zen_ffi_mouse_y(void);
float zen_ffi_safe_area_left(void);
float zen_ffi_safe_area_top(void);
float zen_ffi_safe_area_right(void);
float zen_ffi_safe_area_bottom(void);

int   zen_ffi_image_width(const ZenImage* img);
int   zen_ffi_image_height(const ZenImage* img);
int   zen_ffi_image_x(const ZenImage* img);
int   zen_ffi_image_y(const ZenImage* img);
int   zen_ffi_image_tex_width(const ZenImage* img);
int   zen_ffi_image_tex_height(const ZenImage* img);
int   zen_ffi_image_is_sub(const ZenImage* img);
int   zen_ffi_image_msaa_samples(const ZenImage* img);
void  zen_ffi_image_set_pixel_rgba(ZenImage* img, int x, int y, int r, int g, int b, int a);
void  zen_ffi_image_set_pixels(ZenImage* img, const void* in_pixels);

ZenShader* zen_ffi_shader_create(const char* vert_src, const char* frag_src);
void       zen_ffi_shader_set_vec4_array(ZenShader* shader, const char* name, int count, const void* data);
void       zen_ffi_shader_set_mat4(ZenShader* shader, const char* name, const void* data);

ZenMesh* zen_ffi_mesh_create(int topology, const void* layout, const void* vdata, int vbytes, int vcount, const void* idata, int icount, int dynamic);
void     zen_ffi_mesh_update_vertices(ZenMesh* mesh, int offset_bytes, const void* vdata, int vbytes, int vcount);
void     zen_ffi_mesh_update_indices(ZenMesh* mesh, const void* idata, int icount);
int      zen_ffi_mesh_is_dynamic(const ZenMesh* mesh);
int      zen_ffi_mesh_vertex_count(const ZenMesh* mesh);
int      zen_ffi_mesh_index_count(const ZenMesh* mesh);

void zen_ffi_draw_buffer(int topology, const void* layout, const void* divisors, int base_vertex_count, const void* vertex_data, int count, ZenImage* texture, ZenShader* shader);
void zen_ffi_draw_mesh(ZenMesh* geom_mesh, ZenMesh* inst_buffer, const void* inst_layout, const void* inst_data, int instance_count, ZenImage* texture, ZenShader* shader);

int   zen_ffi_font_query_glyph(ZenFont* font, int codepoint, float font_size, int mode, float render_scale);
int   zen_ffi_glyph_visible(void);
float zen_ffi_glyph_u0(void);
float zen_ffi_glyph_v0(void);
float zen_ffi_glyph_u1(void);
float zen_ffi_glyph_v1(void);
float zen_ffi_glyph_x0(void);
float zen_ffi_glyph_y0(void);
float zen_ffi_glyph_x1(void);
float zen_ffi_glyph_y1(void);
float zen_ffi_glyph_advance(void);
int   zen_ffi_glyph_is_bitmap(void);
float zen_ffi_font_ascent(ZenFont* font, float font_size);
float zen_ffi_font_descent(ZenFont* font, float font_size);
float zen_ffi_font_line_gap(ZenFont* font, float font_size);

ZenSound* zen_ffi_sound_load_pcm(const void* pcm_data, int frame_count, int channels, int sample_rate);
int64_t   zen_ffi_sound_get_length_pcm(const ZenSound* sound);
void      zen_ffi_sound_set_loop_points_pcm(ZenSound* sound, int64_t start_frame, int64_t end_frame);
float     zen_ffi_sound_get_loop_start_sec(const ZenSound* sound);
float     zen_ffi_sound_get_loop_end_sec(const ZenSound* sound);
void      zen_ffi_sound_set_loop_start_sec(ZenSound* sound, float start_sec);
void      zen_ffi_sound_set_loop_end_sec(ZenSound* sound, float end_sec);
int64_t   zen_ffi_sound_get_loop_start_pcm(const ZenSound* sound);
int64_t   zen_ffi_sound_get_loop_end_pcm(const ZenSound* sound);
void      zen_ffi_sound_set_loop_start_pcm(ZenSound* sound, int64_t start_pcm);
void      zen_ffi_sound_set_loop_end_pcm(ZenSound* sound, int64_t end_pcm);

// ------------------------------------------
// 8. C バックエンド描画キュー & バッチング API
// ------------------------------------------
enum ZenPipelineId {
    ZEN_PIPE_CARD                    = 0,
    ZEN_PIPE_SPRITE                  = 1,
    ZEN_PIPE_FONT                    = 2,
    ZEN_PIPE_TRIANGLES               = 3,
    ZEN_PIPE_TRIANGLE_STRIP          = 4,
    ZEN_PIPE_LINES                   = 5,
    ZEN_PIPE_POINTS                  = 6,
    ZEN_PIPE_TEXTURED_TRIANGLES      = 7,
    ZEN_PIPE_TEXTURED_TRIANGLE_STRIP = 8
};

typedef struct ZenSnapshot ZenSnapshot;

// パイプライン管理
int  zen_batch_register_pipeline(int topology, const void* layout, int layout_len, const void* divisors, int div_len, int base_vertex_count, ZenShader* default_shader);
void zen_batch_set_pipeline_default_shader(int pipe_id, ZenShader* shader);

// フレーム・レンダーターゲット・クリップ制御
void      zen_batch_reset_frame(void);
void      zen_batch_mark_screen_cleared(void);
void      zen_batch_set_current_target(ZenImage* target);
ZenImage* zen_batch_get_current_target(void);
void      zen_batch_set_active_gl_target(ZenImage* target);
ZenImage* zen_batch_get_active_gl_target(void);
void      zen_batch_push_clip(float x, float y, float w, float h, float z);
void      zen_batch_pop_clip(void);
void      zen_batch_clear_clips(void);
int       zen_batch_has_pending_draws(ZenImage* image);
void      zen_batch_flush_image(ZenImage* image);
void      zen_batch_flush_pending_images(void);
void      zen_batch_set_clear(uint32_t rgba_color);
void      zen_batch_flush_screen(uint32_t default_bg_color);
void      zen_batch_flush_active(uint32_t default_bg_color);
int       zen_batch_last_draw_calls(void);
int       zen_batch_active_queue_count(void);
int       zen_batch_screen_queue_count(void);
void      zen_batch_sort_screen_queue(void);
void      zen_batch_on_image_destroy(ZenImage* image);

// Uniform アリーナ登録
void zen_batch_begin_uniforms(void);
void zen_batch_uniform_int(const char* name, int val);
void zen_batch_uniform_float(const char* name, float val);
void zen_batch_uniform_vec2(const char* name, float x, float y);
void zen_batch_uniform_vec3(const char* name, float x, float y, float z);
void zen_batch_uniform_vec4(const char* name, float x, float y, float z, float w);
void zen_batch_uniform_mat4(const char* name, const void* mat16_floats);
void zen_batch_uniform_vec4_array(const char* name, int vec4_count, const void* float_data);
void zen_batch_uniform_texture(const char* name, ZenImage* image);

// 汎用エンキュー & ホットパス直接エンキュー（全関数 13 引数以下）
void zen_batch_enqueue_draw(int pipeline_id, const void* data, int data_bytes, int count, ZenImage* image, ZenShader* shader, int blend, float z, ZenMesh* mesh, ZenMesh* inst_buffer);
void zen_batch_enqueue_flat_rect(float x1, float y1, float x2, float y2, float r, float g, float b, float a, ZenShader* shader, int blend, float z);
void zen_batch_stage_card_colors(float cr, float cg, float cb, float ca, float br, float bg, float bb, float ba, float sr, float sg, float sb, float sa);
void zen_batch_stage_card_params(float rad, float b_width, float s_blur, float mode, float uv0, float uv1, float uv2, float uv3, float rot_rad, float pv_x, float pv_y);
void zen_batch_enqueue_sdf_card(float x, float y, float w, float h, ZenImage* image, ZenShader* shader, int blend, float z);
void zen_batch_stage_color_uv(float c0, float c1, float c2, float c3, float uv0, float uv1, float uv2, float uv3);
void zen_batch_enqueue_sprite(float m00, float m01, float m10, float m11, float tx, float ty, ZenImage* image, ZenShader* shader, int blend, float z, ZenMesh* mesh);
void zen_batch_enqueue_triangle_flat(float x1, float y1, float x2, float y2, float x3, float y3, float r, float g, float b, float a, ZenShader* shader, int blend, float z);
void zen_batch_stage_tri_colors(float r1, float g1, float b1, float a1, float r2, float g2, float b2, float a2, float r3, float g3, float b3, float a3);
void zen_batch_enqueue_triangle_grad(float x1, float y1, float x2, float y2, float x3, float y3, ZenShader* shader, int blend, float z);

// テキスト高速ステージング＆コミット
void zen_batch_begin_text(void);
void zen_batch_set_text_color_outline(float cr, float cg, float cb, float ca, float p0_0, float p0_1, float p0_2, float p0_3, float p1_0, float p1_1, float p1_2, float p1_3);
void zen_batch_set_text_shadow_weight(float p2_0, float p2_1, float p2_2, float p2_3, float weight);
void zen_batch_stage_text_line(ZenFont* font, const char* utf8_text, float pen_x, float pen_y, float f_size, int mode, float vp_scale, float inv_vp_scale);
void zen_batch_set_glyph_override(float cr, float cg, float cb, float ca, float out_w, float ocr, float ocg, float ocb, float oca, float weight);
void zen_batch_stage_glyph(float gx, float gy, float gw, float gh, float is_bmp, float u0, float v0, float uw, float vh, int has_override);
int  zen_batch_staged_glyph_count(void);
void zen_batch_commit_text(ZenImage* atlas_image, ZenShader* shader, int blend, float z);

// スナップショット (Scene / Dev)
ZenSnapshot* zen_snapshot_create(void);
void         zen_snapshot_destroy(ZenSnapshot* snap);
int          zen_snapshot_count(const ZenSnapshot* snap);
void         zen_snapshot_clear(ZenSnapshot* snap);
void         zen_snapshot_capture_active(ZenSnapshot* snap, int from_index);
void         zen_snapshot_capture_screen(ZenSnapshot* snap);
void         zen_snapshot_replay_to_active(const ZenSnapshot* snap);
void         zen_snapshot_execute_direct(const ZenSnapshot* snap);

#ifdef __cplusplus
}
#endif

#endif // ZENOO_H

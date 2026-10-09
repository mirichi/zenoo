// ==========================================
// Zenoo 内部ヘッダ (src/ 内のモジュール間でのみ使用)
// ==========================================
// 依存の向き:
//   window (フレーム制御) ──→ input / vibration / gfx / image / audio
//   gfx ──→ window (ビューポート参照のみ)
//   font ──→ image
// 内部関数は zen__ (アンダースコア2つ) で始める。
#ifndef ZENOO_INTERNAL_H
#define ZENOO_INTERNAL_H

#include "zenoo.h"

#ifdef __EMSCRIPTEN__
#include <GLES3/gl3.h>
#else
#include "glad/glad.h"
#endif
#include <GLFW/glfw3.h>

#ifndef GL_R8
#define GL_R8 0x8229
#endif
#ifndef GL_UNPACK_ALIGNMENT
#define GL_UNPACK_ALIGNMENT 0x0CF5
#endif

#define ZEN_MAX_GAMEPADS 4

// ------------------------------------------
// window (zenoo_window.c)
// ------------------------------------------
// 仮想解像度 (base) を物理フレームバッファ上にレターボックス配置した結果
typedef struct {
    int   base_w, base_h;   // 仮想解像度 (ゲーム内論理座標系)
    int   fb_w, fb_h;       // 物理フレームバッファ解像度
    int   x, y, w, h;       // フレームバッファ内のゲーム領域 (GL座標: 左下原点)
    float scale;            // 論理座標 → 物理ピクセルの倍率
} ZenViewport;

GLFWwindow*        zen__window(void);    // 未初期化なら NULL
const ZenViewport* zen__viewport(void);

// ------------------------------------------
// input (zenoo_input.c)
// ------------------------------------------
void zen__input_install(GLFWwindow* window); // GLFW コールバック登録
void zen__input_poll(void);                  // ゲームパッド状態の取得 (begin_frame から)
void zen__input_end_frame(void);             // 押下/離上などワンショット入力のクリア (end_frame から)

// ------------------------------------------
// vibration (zenoo_vibration.c)
// ------------------------------------------
void zen__vibration_init(void);
void zen__vibration_update(float dt);        // 振動タイマー進行 (begin_frame から)
void zen__vibration_stop_all(void);
void zen__vibration_shutdown(void);

// ------------------------------------------
// gfx (zenoo_gfx.c)
// ------------------------------------------
void      zen__gfx_init(void);
void      zen__gfx_shutdown(void);
void      zen__gfx_begin_frame(void);        // 画面を描画先にし、余白を黒で塗り、描画状態を初期化
ZenImage* zen__gfx_render_target(void);      // 現在のレンダーターゲット (画面なら NULL)
uint32_t  zen__gfx_white_texture(void);

// ------------------------------------------
// image (zenoo_image.c)
// ------------------------------------------
void*       zen__alloc(size_t size);         // calloc。失敗時は GC コールバックを呼んで再試行
ZenTexture* zen_texture_create(int width, int height);
void        zen_texture_release(ZenTexture* texture);
void        zen__texture_release(ZenTexture* texture);

#endif // ZENOO_INTERNAL_H

// ==========================================
// ウィンドウ & フレーム制御 & 時間
// ==========================================
// 1フレームの流れ (どの方式でも同じ):
//
//   zen_begin_frame()  … OSイベント取得 → dt計算 → 入力/振動の更新 → 画面描画の準備
//   (ユーザー処理)      … zen_clear() / 描画 / 入力参照
//   zen_end_frame()    … SwapBuffers → ワンショット入力クリア → 目標FPSまで待機
//
// zen_update() と zen_run_loop() はこの2つを並べて呼ぶだけの薄いラッパー。
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#include <mmsystem.h>
#endif
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <errno.h>
#include <ucontext.h>
// Emscripten には ucontext 系が無いため、リンクを通すためのスタブを用意する
int getcontext(ucontext_t *uc) { (void)uc; errno = ENOSYS; return -1; }
void makecontext(ucontext_t *uc, void (*func)(void), int argc, ...) { (void)uc; (void)func; (void)argc; }
int swapcontext(ucontext_t *oucp, const ucontext_t *ucp) { (void)oucp; (void)ucp; errno = ENOSYS; return -1; }
#endif
#include "zenoo_internal.h"

#ifdef _WIN32
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) DWORD AmdPowerXpressRequestHighPerformance = 0x00000001;
#endif

#define ZEN_DEFAULT_DT (1.0 / 60.0)

// ウィンドウ状態
static GLFWwindow* s_window = NULL;
static ZenViewport s_viewport = { 1280, 720, 1280, 720, 0, 0, 1280, 720, 1.0f };
static int s_scale_mode = ZEN_SCALE_FIT;
static int s_is_fullscreen = 0;
static int s_saved_win_x = 100, s_saved_win_y = 100;
static int s_saved_win_w = 960, s_saved_win_h = 540;

// フレーム & 時間状態
static int    s_frame_open = 0;          // begin_frame 済みで end_frame 前なら 1
static int    s_first_frame = 1;         // 初回フレームは dt を既定値にする
static double s_frame_start_time = 0.0;  // 現フレームの begin_frame 時刻
static float  s_delta_time = (float)ZEN_DEFAULT_DT;
static int    s_target_fps = 60;         // デフォルト60fpsに固定
static int    s_vsync = 0;               // デフォルト 0 (ソフトウェア精密制御)

// ------------------------------------------
// 内部: ビューポート計算
// ------------------------------------------
static void update_viewport(int fb_w, int fb_h) {
    ZenViewport* vp = &s_viewport;
    if (fb_w <= 0) fb_w = 1;
    if (fb_h <= 0) fb_h = 1;
    vp->fb_w = fb_w;
    vp->fb_h = fb_h;

    if (vp->base_w <= 0 || vp->base_h <= 0) return;

    float scale_x = (float)fb_w / (float)vp->base_w;
    float scale_y = (float)fb_h / (float)vp->base_h;
    float min_scale = (scale_x < scale_y) ? scale_x : scale_y;

    if (s_scale_mode == ZEN_SCALE_INTEGER) {
        int int_scale = (int)min_scale;
        vp->scale = (float)(int_scale < 1 ? 1 : int_scale);
    } else {
        vp->scale = (min_scale <= 0.0001f) ? 1.0f : min_scale;
    }

    vp->w = (int)(vp->base_w * vp->scale);
    vp->h = (int)(vp->base_h * vp->scale);
    vp->x = (fb_w - vp->w) / 2;
    vp->y = (fb_h - vp->h) / 2;
}

static void glfw_error_callback(int error, const char* description) {
    fprintf(stderr, "[Zenoo/GLFW Error %d]: %s\n", error, description);
}

static void framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    (void)window;
    update_viewport(width, height);
}

GLFWwindow* zen__window(void) {
    return s_window;
}

const ZenViewport* zen__viewport(void) {
    return &s_viewport;
}

// ------------------------------------------
// 初期化 & 終了
// ------------------------------------------
static int init_window(int width, int height, const char* title, GLFWmonitor* monitor, int win_width, int win_height) {
    glfwSetErrorCallback(glfw_error_callback);

#ifdef _WIN32
    // Windowsのタイマー解像度を1msに引き上げる (Sleepの粒度を安定化)
    timeBeginPeriod(1);
#endif

#if defined(__linux__) && !defined(__EMSCRIPTEN__)
    // WSL2/Linux環境でGPUハードウェアアクセラレーション(D3D12)を自動有効化
    setenv("GALLIUM_DRIVER", "d3d12", 0);
#if defined(GLFW_PLATFORM) && defined(GLFW_PLATFORM_X11)
    // Linux/WSLg環境では、WaylandではなくX11バックエンドを明示
    glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_X11);
#endif
#endif

    if (!glfwInit()) {
        fprintf(stderr, "[Zenoo] Failed to initialize GLFW\n");
        return 0;
    }

#ifdef __EMSCRIPTEN__
    glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
#else
    // OpenGL 3.3 Core Profile
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
#endif
    glfwWindowHint(GLFW_DOUBLEBUFFER, GLFW_TRUE);
    glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
    glfwWindowHint(GLFW_FOCUSED, GLFW_TRUE);
    glfwWindowHint(GLFW_DECORATED, GLFW_TRUE);

    s_viewport.base_w = width;
    s_viewport.base_h = height;

    int create_w = (win_width > 0) ? win_width : width;
    int create_h = (win_height > 0) ? win_height : height;
    if (monitor) {
        create_w = width;
        create_h = height;
    }

    s_window = glfwCreateWindow(create_w, create_h, title, monitor, NULL);
    if (!s_window) {
        glfwDefaultWindowHints();
        glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
        s_window = glfwCreateWindow(create_w, create_h, title, monitor, NULL);
        if (!s_window) {
            fprintf(stderr, "[Zenoo] Failed to create GLFW window\n");
            glfwTerminate();
            return 0;
        }
    }

    if (!monitor) {
        s_saved_win_w = create_w;
        s_saved_win_h = create_h;
    }

    int fb_w = create_w, fb_h = create_h;
    glfwGetFramebufferSize(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);

    glfwSetWindowShouldClose(s_window, GLFW_FALSE);
    glfwShowWindow(s_window);
    glfwFocusWindow(s_window);
    glfwMakeContextCurrent(s_window);
    glfwSwapInterval(s_vsync ? 1 : 0);

    glfwSetFramebufferSizeCallback(s_window, framebuffer_size_callback);
    zen__input_install(s_window);

#ifndef __EMSCRIPTEN__
    // GLAD のロード
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        fprintf(stderr, "[Zenoo] Failed to load OpenGL with GLAD\n");
        glfwDestroyWindow(s_window);
        s_window = NULL;
        glfwTerminate();
        return 0;
    }
#endif

    const GLubyte* renderer = glGetString(GL_RENDERER);
    const GLubyte* version = glGetString(GL_VERSION);
    printf("[Zenoo v%s] Initialized successfully (%s).\n", ZENOO_VERSION, monitor ? "Fullscreen Mode" : "Windowed Mode");
    printf("        GPU Renderer : %s\n", renderer ? (const char*)renderer : "Unknown");
    printf("        OpenGL Ver   : %s\n", version ? (const char*)version : "Unknown");

    s_frame_open = 0;
    s_first_frame = 1;

    zen__gfx_init();
    zen_audio_init();
    zen__vibration_init();
    return 1;
}

int zen_init(int width, int height, const char* title) {
    s_is_fullscreen = 0;
    return init_window(width, height, title, NULL, width, height);
}

int zen_init_scaled(int base_width, int base_height, const char* title, int window_width, int window_height) {
    s_is_fullscreen = 0;
    return init_window(base_width, base_height, title, NULL, window_width, window_height);
}

int zen_init_fullscreen(const char* title) {
    if (!glfwInit()) return 0;
    GLFWmonitor* monitor = glfwGetPrimaryMonitor();
    const GLFWvidmode* mode = monitor ? glfwGetVideoMode(monitor) : NULL;
    int w = mode ? mode->width : 1920;
    int h = mode ? mode->height : 1080;
    s_is_fullscreen = 1;
    return init_window(w, h, title, monitor, w, h);
}

void zen_shutdown(void) {
    zen__vibration_shutdown();
    zen__gfx_shutdown();
    if (s_window) {
        glfwDestroyWindow(s_window);
        s_window = NULL;
    }
    glfwTerminate();
    s_frame_open = 0;
#ifdef _WIN32
    timeEndPeriod(1);
#endif
}

const char* zen_get_version(void) {
    return ZENOO_VERSION;
}

int zen_is_wasm(void) {
#ifdef __EMSCRIPTEN__
    return 1;
#else
    return 0;
#endif
}

// ------------------------------------------
// フレーム制御
// ------------------------------------------
#ifndef __EMSCRIPTEN__
// 目標FPSに達するまで待機 (Sleep で大半を待ち、残りをスピンで詰める)
// 120Hz/144Hz などの高リフレッシュレートモニターでも目標FPSを超えないよう制御
static void wait_for_target_fps(void) {
    if (s_target_fps <= 0) return;
    double target_dt = 1.0 / (double)s_target_fps;
    double elapsed = glfwGetTime() - s_frame_start_time;
    if (elapsed >= target_dt) return;

    double remain = target_dt - elapsed;
    if (remain > 0.002) {
#ifdef _WIN32
        Sleep((DWORD)((remain - 0.001) * 1000.0));
#else
        struct timespec ts;
        ts.tv_sec = 0;
        ts.tv_nsec = (long)((remain - 0.001) * 1e9);
        if (ts.tv_nsec > 0) nanosleep(&ts, NULL);
#endif
    }
    while ((glfwGetTime() - s_frame_start_time) < target_dt) {
        // スピンウェイト
    }
}
#endif

int zen_begin_frame(void) {
    if (!s_window) return 0;

    // 1. OSイベント取得 (キー/マウスのコールバックはここで発火する)
    glfwPollEvents();

    // 2. 時間更新 (dt を計算するのはここだけ)
    double now = glfwGetTime();
    double dt = s_first_frame ? ZEN_DEFAULT_DT : (now - s_frame_start_time);
    if (dt <= 0.0001) dt = ZEN_DEFAULT_DT;
#ifdef __EMSCRIPTEN__
    // 極端なラグ時（タブバックグラウンド移行等）のスパイラル防止
    if (dt > 0.2) dt = 0.2;
#endif
    s_delta_time = (float)dt;
    s_frame_start_time = now;
    s_first_frame = 0;

    // 3. 入力 (ゲームパッド) と振動タイマーの更新
    zen__input_poll();
    zen__vibration_update(s_delta_time);

    // 4. 終了判定
    if (glfwWindowShouldClose(s_window)) return 0;

    // 5. 画面描画の準備 (ビューポート更新 → 余白を黒で塗る → 描画状態の初期化)
    int fb_w = s_viewport.fb_w, fb_h = s_viewport.fb_h;
    glfwGetFramebufferSize(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);
    zen__gfx_begin_frame();

    s_frame_open = 1;
    return 1;
}

void zen_end_frame(void) {
    if (!s_window || !s_frame_open) return;
    s_frame_open = 0;

    // 1. 画面へ表示
    glfwSwapBuffers(s_window);

    // 2. このフレームで参照されたワンショット入力 (push/release/文字) をクリア
    //    クリアをフレーム末尾で行うことで、次の begin_frame までに届いた入力を取りこぼさない
    zen__input_end_frame();

#ifndef __EMSCRIPTEN__
    // 3. SwapBuffersの直後に即座にOSイベントをポーリング (DWMのキュー詰まりを根絶)
    glfwPollEvents();

    // 4. 目標FPSまで精密待機 (Wasm は requestAnimationFrame 側で間引く)
    wait_for_target_fps();
#endif
}

int zen_update(void) {
    zen_end_frame();          // 前フレームがあれば表示して待機
    return zen_begin_frame(); // 次フレームを開始
}

#ifdef __EMSCRIPTEN__
static zen_frame_fn s_frame_fn = NULL;
static double s_wasm_accumulator = 0.0;
static double s_wasm_prev_time = 0.0;

static void wasm_tick(void) {
    if (!s_window) return;

    double now = emscripten_get_now() * 0.001; // 秒
    if (s_wasm_prev_time <= 0.0) s_wasm_prev_time = now;
    double dt = now - s_wasm_prev_time;
    s_wasm_prev_time = now;

    // 極端なラグ時（タブバックグラウンド移行等）のスパイラル防止
    if (dt > 0.2) dt = 0.2;
    if (dt <= 0.0) dt = 0.0001;
    s_wasm_accumulator += dt;

    // 固定時間蓄積法: 蓄積時間が fixed_step を超えた時のみ更新＆描画 (rAF間引き制御)
    // 蓄積時間が足りないフレーム (144Hzでの間引き時など) は何もしない
    double fixed_step = 1.0 / (double)((s_target_fps > 0) ? s_target_fps : 60);
    if (s_wasm_accumulator < fixed_step) return;

    int steps = 0;
    while (s_wasm_accumulator >= fixed_step && steps < 2) {
        s_wasm_accumulator -= fixed_step;
        steps++;
    }
    if (s_wasm_accumulator > fixed_step * 2.0) {
        s_wasm_accumulator = 0.0; // 追いつかない過度な蓄積はリセット
    }

    if (!zen_begin_frame()) {
        emscripten_cancel_main_loop();
        return;
    }
    if (s_frame_fn) s_frame_fn();
    zen_end_frame();
}

void zen_run_loop(zen_frame_fn fn) {
    s_frame_fn = fn;
    s_wasm_prev_time = emscripten_get_now() * 0.001;
    s_wasm_accumulator = 0.0;
    // 0 = requestAnimationFrame に同期, 0 = do not simulate infinite loop (return normally so main() completes safely)
    emscripten_set_main_loop(wasm_tick, 0, 0);
}
#else
void zen_run_loop(zen_frame_fn fn) {
    while (zen_begin_frame()) {
        if (fn) fn();
        zen_end_frame();
    }
}
#endif

// ------------------------------------------
// 時間 & フレームレート
// ------------------------------------------
double zen_get_time(void) {
    return glfwGetTime();
}

float zen_get_delta_time(void) {
    return s_delta_time;
}

void zen_set_target_fps(int fps) {
    s_target_fps = fps;
}

int zen_get_target_fps(void) {
    return s_target_fps;
}

void zen_set_vsync(int vsync) {
    s_vsync = vsync;
    if (s_window) {
        glfwSwapInterval(vsync ? 1 : 0);
    }
}

// ------------------------------------------
// サイズ & スケーリング & フルスクリーン
// ------------------------------------------
void zen_get_screen_size(int* width, int* height) {
    if (width) *width = s_viewport.base_w;
    if (height) *height = s_viewport.base_h;
}

void zen_get_window_size(int* width, int* height) {
    if (s_window) {
        glfwGetWindowSize(s_window, width, height);
    } else {
        zen_get_screen_size(width, height);
    }
}

void zen_set_window_size(int width, int height) {
    if (s_window && width > 0 && height > 0) {
        glfwSetWindowSize(s_window, width, height);
    }
}

void zen_set_scale_mode(int mode) {
    s_scale_mode = mode;
    update_viewport(s_viewport.fb_w, s_viewport.fb_h);
}

int zen_get_scale_mode(void) {
    return s_scale_mode;
}

float zen_get_scale(void) {
    return s_viewport.scale;
}

void zen_toggle_fullscreen(void) {
    if (!s_window) return;
    GLFWmonitor* monitor = glfwGetPrimaryMonitor();
    const GLFWvidmode* mode = monitor ? glfwGetVideoMode(monitor) : NULL;

    if (!s_is_fullscreen) {
        glfwGetWindowPos(s_window, &s_saved_win_x, &s_saved_win_y);
        glfwGetWindowSize(s_window, &s_saved_win_w, &s_saved_win_h);
        if (monitor && mode) {
            glfwSetWindowMonitor(s_window, monitor, 0, 0, mode->width, mode->height, mode->refreshRate);
            s_is_fullscreen = 1;
        }
    } else {
        glfwSetWindowMonitor(s_window, NULL, s_saved_win_x, s_saved_win_y, s_saved_win_w, s_saved_win_h, 0);
        s_is_fullscreen = 0;
    }
}

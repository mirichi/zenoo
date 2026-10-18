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
// NVIDIA Optimus: GeForce dGPU を優先して有効化
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
// ※ AMD Ryzen 内蔵 Radeon + NVIDIA GeForce のノートPC環境では、
//    AmdPowerXpressRequestHighPerformance が有効だと内蔵 Radeon が優先されてしまうため無効化
// __declspec(dllexport) DWORD AmdPowerXpressRequestHighPerformance = 0x00000001;
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

static int s_window_visible = 0;
static GLFWmonitor* s_current_monitor = NULL;
static int s_in_auto_resize = 0;

// ウィンドウが現在属しているモニターを取得 (use_cursor=1 の場合はドラッグ中のマウス座標を優先)
static GLFWmonitor* find_window_monitor(GLFWwindow* window, int use_cursor) {
    if (!window) return glfwGetPrimaryMonitor();
    int count = 0;
    GLFWmonitor** monitors = glfwGetMonitors(&count);
    if (!monitors || count <= 0) return glfwGetPrimaryMonitor();

#ifdef _WIN32
    if (use_cursor) {
        POINT pt;
        if (GetCursorPos(&pt)) {
            for (int i = 0; i < count; i++) {
                int mx = 0, my = 0, mw = 0, mh = 0;
                glfwGetMonitorWorkarea(monitors[i], &mx, &my, &mw, &mh);
                const GLFWvidmode* mode = glfwGetVideoMode(monitors[i]);
                if (mode) {
                    glfwGetMonitorPos(monitors[i], &mx, &my);
                    mw = mode->width;
                    mh = mode->height;
                }
                if (pt.x >= mx && pt.x < mx + mw && pt.y >= my && pt.y < my + mh) {
                    return monitors[i];
                }
            }
        }
    }
#else
    (void)use_cursor;
#endif

    int wx = 0, wy = 0, ww = 0, wh = 0;
    glfwGetWindowPos(window, &wx, &wy);
    glfwGetWindowSize(window, &ww, &wh);

    // 1. タイトルバー中央点 (wx + ww/2, wy + 8) が含まれるモニターを優先
    int cx = wx + ww / 2;
    int cy = wy + 8;
    for (int i = 0; i < count; i++) {
        int mx = 0, my = 0, mw = 0, mh = 0;
        glfwGetMonitorWorkarea(monitors[i], &mx, &my, &mw, &mh);
        const GLFWvidmode* mode = glfwGetVideoMode(monitors[i]);
        if (mode) {
            glfwGetMonitorPos(monitors[i], &mx, &my);
            mw = mode->width;
            mh = mode->height;
        }
        if (cx >= mx && cx < mx + mw && cy >= my && cy < my + mh) {
            return monitors[i];
        }
    }

    // 2. ウィンドウ矩形との重なり面積が最大のモニターを選択
    GLFWmonitor* best_mon = glfwGetPrimaryMonitor();
    long long best_area = -1;
    for (int i = 0; i < count; i++) {
        int mx = 0, my = 0, mw = 0, mh = 0;
        glfwGetMonitorWorkarea(monitors[i], &mx, &my, &mw, &mh);
        const GLFWvidmode* mode = glfwGetVideoMode(monitors[i]);
        if (mode) {
            glfwGetMonitorPos(monitors[i], &mx, &my);
            mw = mode->width;
            mh = mode->height;
        }
        int x1 = (wx > mx) ? wx : mx;
        int y1 = (wy > my) ? wy : my;
        int x2 = (wx + ww < mx + mw) ? (wx + ww) : (mx + mw);
        int y2 = (wy + wh < my + mh) ? (wy + wh) : (my + mh);
        if (x2 > x1 && y2 > y1) {
            long long area = (long long)(x2 - x1) * (long long)(y2 - y1);
            if (area > best_area) {
                best_area = area;
                best_mon = monitors[i];
            }
        }
    }
    return best_mon;
}

// 指定モニターのDPIスケールとワークエリアに合わせて最適な物理ウィンドウサイズを算出
static void compute_auto_window_size_for_monitor(GLFWmonitor* monitor, float override_scale, int base_w, int base_h, int* out_w, int* out_h) {
    if (!monitor) monitor = glfwGetPrimaryMonitor();
    float scale = override_scale;
    if (scale <= 0.0f && monitor) {
        float xscale = 1.0f, yscale = 1.0f;
        glfwGetMonitorContentScale(monitor, &xscale, &yscale);
        if (xscale > 0.0f) {
            scale = xscale;
        }
    }
    if (scale <= 0.0f && s_window) {
        float xscale = 1.0f, yscale = 1.0f;
        glfwGetWindowContentScale(s_window, &xscale, &yscale);
        if (xscale > 0.0f) {
            scale = xscale;
        }
    }
#ifdef _WIN32
    if (scale <= 0.0f) {
        HDC hdc = GetDC(NULL);
        if (hdc) {
            int dpi = GetDeviceCaps(hdc, LOGPIXELSX);
            ReleaseDC(NULL, hdc);
            if (dpi > 0) {
                scale = (float)dpi / 96.0f;
            }
        }
    }
#endif
    if (scale <= 0.0f) scale = 1.0f;

    int target_w = (int)((float)base_w * scale + 0.5f);
    int target_h = (int)((float)base_h * scale + 0.5f);

    if (monitor) {
        int wx = 0, wy = 0, ww = 0, wh = 0;
        glfwGetMonitorWorkarea(monitor, &wx, &wy, &ww, &wh);
        int left = 0, top = 0, right = 0, bottom = 0;
        if (s_window) {
            glfwGetWindowFrameSize(s_window, &left, &top, &right, &bottom);
        }
        int pad_w = (left + right > 0) ? (left + right + 12) : 16;
        int pad_h = (top + bottom > 0) ? (top + bottom + 12) : 44;
        int max_w = ww - pad_w;
        int max_h = wh - pad_h;
        if (max_w > 0 && max_h > 0 && (target_w > max_w || target_h > max_h)) {
            float fit_x = (float)max_w / (float)base_w;
            float fit_y = (float)max_h / (float)base_h;
            float fit = (fit_x < fit_y) ? fit_x : fit_y;
            if (fit < 0.25f) fit = 0.25f;
            target_w = (int)((float)base_w * fit + 0.5f);
            target_h = (int)((float)base_h * fit + 0.5f);
        }
    }

    *out_w = (target_w > 0) ? target_w : base_w;
    *out_h = (target_h > 0) ? target_h : base_h;
}

static void compute_auto_window_size(int base_w, int base_h, int* out_w, int* out_h) {
    GLFWmonitor* mon = s_window ? find_window_monitor(s_window, 0) : glfwGetPrimaryMonitor();
    compute_auto_window_size_for_monitor(mon, 0.0f, base_w, base_h, out_w, out_h);
}

// ウィンドウ位置がモニターのワークエリアからはみ出さないように補正
static void clamp_window_to_monitor_workarea(GLFWwindow* window, GLFWmonitor* monitor, int win_w, int win_h) {
    if (!window || !monitor) return;
    int mx = 0, my = 0, mw = 0, mh = 0;
    glfwGetMonitorWorkarea(monitor, &mx, &my, &mw, &mh);
    if (mw <= 0 || mh <= 0) return;

    int left = 0, top = 0, right = 0, bottom = 0;
    glfwGetWindowFrameSize(window, &left, &top, &right, &bottom);
    if (top <= 0) top = 32;
    if (left <= 0) left = 8;
    if (right <= 0) right = 8;
    if (bottom <= 0) bottom = 8;

    int wx = 0, wy = 0;
    glfwGetWindowPos(window, &wx, &wy);
    int new_x = wx;
    int new_y = wy;

    if (new_x + win_w + right > mx + mw) {
        new_x = mx + mw - win_w - right;
    }
    if (new_y + win_h + bottom > my + mh) {
        new_y = my + mh - win_h - bottom;
    }
    if (new_x < mx + left) {
        new_x = mx + left;
    }
    if (new_y < my + top) {
        new_y = my + top;
    }

    if (new_x != wx || new_y != wy) {
        glfwSetWindowPos(window, new_x, new_y);
    }
    s_saved_win_x = new_x;
    s_saved_win_y = new_y;
}

static void center_window_on_monitor(GLFWwindow* window, int win_w, int win_h) {
    GLFWmonitor* mon = find_window_monitor(window, 0);
    if (!mon || !window) return;
    int wx = 0, wy = 0, ww = 0, wh = 0;
    glfwGetMonitorWorkarea(mon, &wx, &wy, &ww, &wh);
    if (ww > 0 && wh > 0) {
        int cx = wx + (ww - win_w) / 2;
        int cy = wy + (wh - win_h) / 2;
        if (cx < wx) cx = wx;
        if (cy < wy + 28) cy = wy + 28;
        glfwSetWindowPos(window, cx, cy);
        s_saved_win_x = cx;
        s_saved_win_y = cy;
    }
}

// 別ディスプレイへの移動等でDPIスケールが変化した際にウィンドウサイズを自動調整
static void window_content_scale_callback(GLFWwindow* window, float xscale, float yscale) {
    (void)yscale;
    if (!window || s_is_fullscreen || !s_window_visible || s_in_auto_resize) return;
    if (s_viewport.base_w <= 0 || s_viewport.base_h <= 0) return;

    s_in_auto_resize = 1;
    GLFWmonitor* mon = find_window_monitor(window, 1);
    int old_w = 0, old_h = 0, old_x = 0, old_y = 0;
    glfwGetWindowSize(window, &old_w, &old_h);
    glfwGetWindowPos(window, &old_x, &old_y);

    int new_w = old_w, new_h = old_h;
    compute_auto_window_size_for_monitor(mon, xscale, s_viewport.base_w, s_viewport.base_h, &new_w, &new_h);

    if (new_w != old_w || new_h != old_h) {
        int new_x = old_x;
        int new_y = old_y;
        int mouse_dragging = 0;
#ifdef _WIN32
        if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0) {
            POINT pt;
            if (GetCursorPos(&pt)) {
                mouse_dragging = 1;
                float ratio_x = (old_w > 0) ? (float)(pt.x - old_x) / (float)old_w : 0.5f;
                if (ratio_x < 0.1f) ratio_x = 0.1f;
                if (ratio_x > 0.9f) ratio_x = 0.9f;
                new_x = pt.x - (int)(ratio_x * (float)new_w + 0.5f);
            }
        }
#endif
        if (mouse_dragging) {
            glfwSetWindowPos(window, new_x, new_y);
            glfwSetWindowSize(window, new_w, new_h);
        } else {
            glfwSetWindowSize(window, new_w, new_h);
            clamp_window_to_monitor_workarea(window, mon, new_w, new_h);
        }
        s_saved_win_w = new_w;
        s_saved_win_h = new_h;
    }

    int fb_w = new_w, fb_h = new_h;
    glfwGetFramebufferSize(window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);
    s_in_auto_resize = 0;
}

// ------------------------------------------
// 初期化 & 終了
// ------------------------------------------
static int init_window(int width, int height, const char* title, GLFWmonitor* monitor, int win_width, int win_height, int visible) {
    if (s_window) {
        // すでにウィンドウ(コンテキスト)が存在する場合は、サイズ・タイトル等の更新と可視化を行う
        s_viewport.base_w = width;
        s_viewport.base_h = height;

        int create_w = win_width;
        int create_h = win_height;
        if (create_w <= 0 || create_h <= 0) {
            if (visible) {
                compute_auto_window_size(width, height, &create_w, &create_h);
            } else {
                create_w = width;
                create_h = height;
            }
        }

        if (title && strlen(title) > 0) {
            glfwSetWindowTitle(s_window, title);
        }

        if (monitor) {
            glfwSetWindowMonitor(s_window, monitor, 0, 0, width, height, GLFW_DONT_CARE);
            s_is_fullscreen = 1;
        } else {
            if (s_is_fullscreen) {
                glfwSetWindowMonitor(s_window, NULL, s_saved_win_x, s_saved_win_y, create_w, create_h, 0);
                s_is_fullscreen = 0;
            } else {
                glfwSetWindowSize(s_window, create_w, create_h);
            }
            s_saved_win_w = create_w;
            s_saved_win_h = create_h;
        }

        int fb_w = create_w, fb_h = create_h;
        glfwGetFramebufferSize(s_window, &fb_w, &fb_h);
        update_viewport(fb_w, fb_h);

        if (visible && !s_window_visible) {
            if (!monitor) {
                center_window_on_monitor(s_window, create_w, create_h);
                s_current_monitor = find_window_monitor(s_window, 0);
            }
            glfwShowWindow(s_window);
            glfwFocusWindow(s_window);
            s_window_visible = 1;
        }
        return 1;
    }

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
    glfwWindowHint(GLFW_VISIBLE, visible ? GLFW_TRUE : GLFW_FALSE);
    glfwWindowHint(GLFW_FOCUSED, visible ? GLFW_TRUE : GLFW_FALSE);
    glfwWindowHint(GLFW_DECORATED, GLFW_TRUE);

    s_viewport.base_w = width;
    s_viewport.base_h = height;

    int create_w = win_width;
    int create_h = win_height;
    if (monitor) {
        create_w = width;
        create_h = height;
    } else if (create_w <= 0 || create_h <= 0) {
        if (visible) {
            compute_auto_window_size(width, height, &create_w, &create_h);
        } else {
            create_w = width;
            create_h = height;
        }
    }

    s_window = glfwCreateWindow(create_w, create_h, title, monitor, NULL);
    if (!s_window) {
        glfwDefaultWindowHints();
        glfwWindowHint(GLFW_VISIBLE, visible ? GLFW_TRUE : GLFW_FALSE);
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
    if (visible) {
        if (!monitor) {
            center_window_on_monitor(s_window, create_w, create_h);
            s_current_monitor = find_window_monitor(s_window, 0);
        }
        glfwShowWindow(s_window);
        glfwFocusWindow(s_window);
        s_window_visible = 1;
    } else {
        s_window_visible = 0;
    }
    glfwMakeContextCurrent(s_window);
    glfwSwapInterval(s_vsync ? 1 : 0);

    glfwSetFramebufferSizeCallback(s_window, framebuffer_size_callback);
    glfwSetWindowContentScaleCallback(s_window, window_content_scale_callback);
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

int zen_ensure_context(void) {
    if (s_window) return 1;
    return init_window(1280, 720, "Zenoo", NULL, 1280, 720, 0);
}

int zen_init(int width, int height, const char* title) {
    s_is_fullscreen = 0;
    return init_window(width, height, title, NULL, 0, 0, 1);
}

int zen_init_scaled(int base_width, int base_height, const char* title, int window_width, int window_height) {
    s_is_fullscreen = 0;
    return init_window(base_width, base_height, title, NULL, window_width, window_height, 1);
}

int zen_init_fullscreen(const char* title) {
    if (!zen_ensure_context()) return 0;
    GLFWmonitor* monitor = glfwGetPrimaryMonitor();
    const GLFWvidmode* mode = monitor ? glfwGetVideoMode(monitor) : NULL;
    int w = mode ? mode->width : 1920;
    int h = mode ? mode->height : 1080;
    s_is_fullscreen = 1;
    return init_window(w, h, title, monitor, w, h, 1);
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
    s_window_visible = 0;
    s_current_monitor = NULL;
    s_in_auto_resize = 0;
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

    // 1.5. 別モニターへの移動検知 (同DPIモニター間の移動やドラッグ完了時のサイズ・位置フィット補正)
    if (s_window_visible && !s_is_fullscreen && !s_in_auto_resize && !glfwGetWindowAttrib(s_window, GLFW_ICONIFIED)) {
        int mouse_down = 0;
#ifdef _WIN32
        mouse_down = ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0);
#endif
        if (!mouse_down) {
            GLFWmonitor* cur_mon = find_window_monitor(s_window, 0);
            if (cur_mon && cur_mon != s_current_monitor) {
                s_current_monitor = cur_mon;
                s_in_auto_resize = 1;
                int target_w = 0, target_h = 0;
                compute_auto_window_size_for_monitor(cur_mon, 0.0f, s_viewport.base_w, s_viewport.base_h, &target_w, &target_h);
                int cur_w = 0, cur_h = 0;
                glfwGetWindowSize(s_window, &cur_w, &cur_h);
                if (abs(cur_w - target_w) > 2 || abs(cur_h - target_h) > 2) {
                    glfwSetWindowSize(s_window, target_w, target_h);
                    cur_w = target_w;
                    cur_h = target_h;
                }
                clamp_window_to_monitor_workarea(s_window, cur_mon, cur_w, cur_h);
                s_saved_win_w = cur_w;
                s_saved_win_h = cur_h;
                s_in_auto_resize = 0;
            }
        }
    }

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
    GLFWmonitor* monitor = find_window_monitor(s_window, 0);
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

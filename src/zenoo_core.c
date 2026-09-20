#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#include <mmsystem.h>
#endif
#include "glad/glad.h"
#include <GLFW/glfw3.h>
#include "zenoo.h"

// 内部状態
static GLFWwindow* s_window = NULL;
static int s_win_width = 1280;
static int s_win_height = 720;
static double s_last_time = 0.0;
static double s_frame_start_time = 0.0;
static float s_delta_time = 0.016667f;
static int s_target_fps = 60; // デフォルト60fpsに固定

// 入力状態
static double s_mouse_x = 0.0;
static double s_mouse_y = 0.0;
static char s_keys_pressed[512] = {0}; // 押されている状態 (持続)
static char s_keys_push[512] = {0};    // 押した瞬間 (トリガー)
static char s_keys_release[512] = {0}; // 離した瞬間 (リリース)

static char s_mouse_pressed[8] = {0};  // 押されている状態 (持続)
static char s_mouse_push[8] = {0};     // 押した瞬間 (トリガー)
static char s_mouse_release[8] = {0};  // 離した瞬間 (リリース)
static int s_is_in_update_loop = 0;

// 前方宣言
void zen_gfx_init(int width, int height);
void zen_gfx_shutdown(void);
void zen_gfx_begin(uint32_t clear_color, int width, int height);
void zen_gfx_flush(void);

static void glfw_error_callback(int error, const char* description) {
    fprintf(stderr, "[Zenoo/GLFW Error %d]: %s\n", error, description);
}

static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    (void)window; (void)scancode; (void)mods;
    if (key >= 0 && key < 512) {
        if (action == GLFW_PRESS) {
            s_keys_pressed[key] = 1;
            s_keys_push[key] = 1;
        } else if (action == GLFW_RELEASE) {
            s_keys_pressed[key] = 0;
            s_keys_release[key] = 1;
        }
    }
}

static void mouse_button_callback(GLFWwindow* window, int button, int action, int mods) {
    (void)window; (void)mods;
    if (button >= 0 && button < 8) {
        if (action == GLFW_PRESS) {
            s_mouse_pressed[button] = 1;
            s_mouse_push[button] = 1;
        } else if (action == GLFW_RELEASE) {
            s_mouse_pressed[button] = 0;
            s_mouse_release[button] = 1;
        }
    }
}

static void cursor_pos_callback(GLFWwindow* window, double xpos, double ypos) {
    (void)window;
    s_mouse_x = xpos;
    s_mouse_y = ypos;
}

static void framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    (void)window;
    s_win_width = width;
    s_win_height = height;
    glViewport(0, 0, width, height);
}

static int s_is_fullscreen = 0;
static int s_saved_win_x = 100, s_saved_win_y = 100;
static int s_saved_win_w = 960, s_saved_win_h = 540;

#ifdef _WIN32
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) DWORD AmdPowerXpressRequestHighPerformance = 0x00000001;
#endif

static int zen_init_internal(int width, int height, const char* title, GLFWmonitor* monitor) {
    glfwSetErrorCallback(glfw_error_callback);

#ifdef _WIN32
    // Windowsのタイマー解像度を1msに引き上げる (Sleepの粒度を安定化)
    timeBeginPeriod(1);
#endif

#if defined(__linux__)
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

    // OpenGL 3.3 Core Profile
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_DOUBLEBUFFER, GLFW_TRUE);
    glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
    glfwWindowHint(GLFW_FOCUSED, GLFW_TRUE);
    glfwWindowHint(GLFW_DECORATED, GLFW_TRUE);

    s_win_width = width;
    s_win_height = height;
    s_window = glfwCreateWindow(width, height, title, monitor, NULL);
    if (!s_window) {
        glfwDefaultWindowHints();
        glfwWindowHint(GLFW_VISIBLE, GLFW_TRUE);
        s_window = glfwCreateWindow(width, height, title, monitor, NULL);
        if (!s_window) {
            fprintf(stderr, "[Zenoo] Failed to create GLFW window\n");
            glfwTerminate();
            return 0;
        }
    }

    glfwSetWindowShouldClose(s_window, GLFW_FALSE);
    glfwShowWindow(s_window);
    glfwFocusWindow(s_window);
    glfwMakeContextCurrent(s_window);
    glfwSwapInterval(0); // デフォルトでドライバのVSyncロックを解除 (SwapBuffersの100ms停止を排除)

    // コールバック登録
    glfwSetKeyCallback(s_window, key_callback);
    glfwSetMouseButtonCallback(s_window, mouse_button_callback);
    glfwSetCursorPosCallback(s_window, cursor_pos_callback);
    glfwSetFramebufferSizeCallback(s_window, framebuffer_size_callback);

    // GLAD のロード
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        fprintf(stderr, "[Zenoo] Failed to load OpenGL with GLAD\n");
        glfwDestroyWindow(s_window);
        glfwTerminate();
        return 0;
    }

    const GLubyte* renderer = glGetString(GL_RENDERER);
    const GLubyte* version = glGetString(GL_VERSION);
    printf("[Zenoo] Initialized successfully (%s).\n", monitor ? "Fullscreen Mode" : "Windowed Mode");
    printf("        GPU Renderer : %s\n", renderer ? (const char*)renderer : "Unknown");
    printf("        OpenGL Ver   : %s\n", version ? (const char*)version : "Unknown");

    s_last_time = glfwGetTime();
    s_frame_start_time = s_last_time;

    // 描画システムの初期化
    zen_gfx_init(width, height);
    s_is_in_update_loop = 0;

    return 1;
}

int zen_init(int width, int height, const char* title) {
    s_is_fullscreen = 0;
    return zen_init_internal(width, height, title, NULL);
}

int zen_init_fullscreen(const char* title) {
    if (!glfwInit()) return 0;
    GLFWmonitor* monitor = glfwGetPrimaryMonitor();
    const GLFWvidmode* mode = monitor ? glfwGetVideoMode(monitor) : NULL;
    int w = mode ? mode->width : 1920;
    int h = mode ? mode->height : 1080;
    s_is_fullscreen = 1;
    return zen_init_internal(w, h, title, monitor);
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

void zen_shutdown(void) {
    zen_gfx_shutdown();
    if (s_window) {
        glfwDestroyWindow(s_window);
        s_window = NULL;
    }
    glfwTerminate();
#ifdef _WIN32
    timeEndPeriod(1);
#endif
}

int zen_window_should_close(void) {
    return s_window ? glfwWindowShouldClose(s_window) : 1;
}

void zen_set_target_fps(int fps) {
    s_target_fps = fps;
}

int zen_get_target_fps(void) {
    return s_target_fps;
}

void zen_poll_events(void) {
    memset(s_keys_push, 0, sizeof(s_keys_push));
    memset(s_keys_release, 0, sizeof(s_keys_release));
    memset(s_mouse_push, 0, sizeof(s_mouse_push));
    memset(s_mouse_release, 0, sizeof(s_mouse_release));
    
    glfwPollEvents();

    double current_time = glfwGetTime();
    double dt = current_time - s_last_time;
    if (dt <= 0.0001) dt = 0.016667;
    s_delta_time = (float)dt;
    s_last_time = current_time;
}

void zen_begin_frame(uint32_t clear_color) {
    glfwGetFramebufferSize(s_window, &s_win_width, &s_win_height);
    zen_gfx_begin(clear_color, s_win_width, s_win_height);
}

void zen_clear(uint32_t color) {
    zen_begin_frame(color);
}

static int s_vsync = 0; // デフォルト 0 (ソフトウェア精密制御)

void zen_set_vsync(int vsync) {
    s_vsync = vsync;
    if (s_window) {
        glfwSwapInterval(vsync ? 1 : 0);
    }
}

void zen_end_frame(void) {
    zen_gfx_flush();
    glfwSwapBuffers(s_window);
}

int zen_update(void) {
    if (!s_window) return 0;

    if (s_is_in_update_loop) {
        // 1. 前フレームの描画を Flush & SwapBuffers
        zen_end_frame();

        // 2. ★Raylib方式★ SwapBuffersの直後に即座にOSイベントをポーリング (DWMのキュー詰まりを根絶)
        zen_poll_events();

        // 3. イベント処理後に目標FPSまで精密待機 (WaitTime)
        if (!s_vsync && s_target_fps > 0) {
            double target_dt = 1.0 / (double)s_target_fps;
            double elapsed = glfwGetTime() - s_frame_start_time;
            if (elapsed < target_dt) {
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
        }
        s_frame_start_time = glfwGetTime();
    } else {
        s_is_in_update_loop = 1;
        zen_poll_events();
        s_frame_start_time = glfwGetTime();
    }

    // 4. 終了判定
    if (glfwWindowShouldClose(s_window)) {
        s_is_in_update_loop = 0;
        return 0;
    }

    // 5. 新しいフレームの描画バッチ開始
    glfwGetFramebufferSize(s_window, &s_win_width, &s_win_height);
    zen_gfx_begin(ZEN_RGBA(0, 0, 0, 255), s_win_width, s_win_height);

    return 1;
}

double zen_get_time(void) {
    return glfwGetTime();
}

float zen_get_delta_time(void) {
    return s_delta_time;
}

void zen_get_window_size(int* width, int* height) {
    if (width) *width = s_win_width;
    if (height) *height = s_win_height;
}

void zen_get_mouse_pos(float* x, float* y) {
    if (x) *x = (float)s_mouse_x;
    if (y) *y = (float)s_mouse_y;
}

int zen_is_mouse_pressed(int button) {
    if (button >= 0 && button < 8) return s_mouse_pressed[button];
    return 0;
}

int zen_is_mouse_push(int button) {
    if (button >= 0 && button < 8) return s_mouse_push[button];
    return 0;
}

int zen_is_mouse_release(int button) {
    if (button >= 0 && button < 8) return s_mouse_release[button];
    return 0;
}

int zen_is_key_pressed(int key) {
    if (key >= 0 && key < 512) return s_keys_pressed[key];
    return 0;
}

int zen_is_key_push(int key) {
    if (key >= 0 && key < 512) return s_keys_push[key];
    return 0;
}

int zen_is_key_release(int key) {
    if (key >= 0 && key < 512) return s_keys_release[key];
    return 0;
}

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
#include <GLES3/gl3.h>
#include <emscripten.h>
#else
#include "glad/glad.h"
#endif
#include <GLFW/glfw3.h>
#include "zenoo.h"

// 内部状態
static GLFWwindow* s_window = NULL;
static int s_base_width = 1280;   // 仮想解像度 (ゲーム内論理座標系)
static int s_base_height = 720;
static int s_fb_width = 1280;     // 実際のフレームバッファ解像度 (物理ピクセル)
static int s_fb_height = 720;
static int s_vp_x = 0;            // レターボックスビューポート
static int s_vp_y = 0;
static int s_vp_w = 1280;
static int s_vp_h = 720;
static float s_vp_scale = 1.0f;
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

#define ZEN_MAX_GAMEPADS 4
#define ZEN_GAMEPAD_BUTTON_COUNT 15
#define ZEN_GAMEPAD_AXIS_COUNT 6

static unsigned char s_gamepad_buttons_pressed[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static unsigned char s_gamepad_buttons_push[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static unsigned char s_gamepad_buttons_release[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static float s_gamepad_axes[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_AXIS_COUNT] = {{0}};
static unsigned char s_gamepad_connected[ZEN_MAX_GAMEPADS] = {0};

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

static void update_viewport(int fb_w, int fb_h) {
    if (fb_w <= 0) fb_w = 1;
    if (fb_h <= 0) fb_h = 1;
    s_fb_width = fb_w;
    s_fb_height = fb_h;

    if (s_base_width <= 0 || s_base_height <= 0) return;

    float scale_x = (float)fb_w / (float)s_base_width;
    float scale_y = (float)fb_h / (float)s_base_height;
    s_vp_scale = (scale_x < scale_y) ? scale_x : scale_y;
    if (s_vp_scale <= 0.0001f) s_vp_scale = 1.0f;

    s_vp_w = (int)(s_base_width * s_vp_scale);
    s_vp_h = (int)(s_base_height * s_vp_scale);
    s_vp_x = (fb_w - s_vp_w) / 2;
    s_vp_y = (fb_h - s_vp_h) / 2;
}

static void framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    (void)window;
    update_viewport(width, height);
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

    s_base_width = width;
    s_base_height = height;
    s_fb_width = width;
    s_fb_height = height;
    update_viewport(width, height);
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
    glfwSwapInterval(0);

    // コールバック登録
    glfwSetKeyCallback(s_window, key_callback);
    glfwSetMouseButtonCallback(s_window, mouse_button_callback);
    glfwSetCursorPosCallback(s_window, cursor_pos_callback);
    glfwSetFramebufferSizeCallback(s_window, framebuffer_size_callback);

#ifndef __EMSCRIPTEN__
    // GLAD のロード
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        fprintf(stderr, "[Zenoo] Failed to load OpenGL with GLAD\n");
        glfwDestroyWindow(s_window);
        glfwTerminate();
        return 0;
    }
#endif

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
    memset(s_gamepad_buttons_push, 0, sizeof(s_gamepad_buttons_push));
    memset(s_gamepad_buttons_release, 0, sizeof(s_gamepad_buttons_release));
    
    glfwPollEvents();

#ifdef __EMSCRIPTEN__
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        int jid = GLFW_JOYSTICK_1 + i;
        if (glfwJoystickPresent(jid)) {
            int axes_count = 0;
            const float* axes = glfwGetJoystickAxes(jid, &axes_count);
            int btn_count = 0;
            const unsigned char* buttons = glfwGetJoystickButtons(jid, &btn_count);

            if (axes || buttons) {
                s_gamepad_connected[i] = 1;
                if (axes) {
                    for (int a = 0; a < ZEN_GAMEPAD_AXIS_COUNT; a++) {
                        s_gamepad_axes[i][a] = (a < axes_count) ? axes[a] : 0.0f;
                    }
                }
                if (buttons) {
                    static const int html5_to_zen_btn[17] = {
                        ZEN_GAMEPAD_BUTTON_A,            // 0 -> A
                        ZEN_GAMEPAD_BUTTON_B,            // 1 -> B
                        ZEN_GAMEPAD_BUTTON_X,            // 2 -> X
                        ZEN_GAMEPAD_BUTTON_Y,            // 3 -> Y
                        ZEN_GAMEPAD_BUTTON_LEFT_BUMPER,  // 4 -> LB
                        ZEN_GAMEPAD_BUTTON_RIGHT_BUMPER, // 5 -> RB
                        -1,                              // 6 -> LT
                        -1,                              // 7 -> RT
                        ZEN_GAMEPAD_BUTTON_BACK,         // 8 -> Back
                        ZEN_GAMEPAD_BUTTON_START,        // 9 -> Start
                        ZEN_GAMEPAD_BUTTON_LEFT_THUMB,   // 10 -> LThumb
                        ZEN_GAMEPAD_BUTTON_RIGHT_THUMB,  // 11 -> RThumb
                        ZEN_GAMEPAD_BUTTON_DPAD_UP,      // 12 -> Dpad Up
                        ZEN_GAMEPAD_BUTTON_DPAD_DOWN,    // 13 -> Dpad Down
                        ZEN_GAMEPAD_BUTTON_DPAD_LEFT,    // 14 -> Dpad Left
                        ZEN_GAMEPAD_BUTTON_DPAD_RIGHT,   // 15 -> Dpad Right
                        ZEN_GAMEPAD_BUTTON_GUIDE         // 16 -> Guide
                    };
                    unsigned char new_buttons[ZEN_GAMEPAD_BUTTON_COUNT] = {0};
                    for (int h = 0; h < btn_count && h < 17; h++) {
                        int zb = html5_to_zen_btn[h];
                        if (zb >= 0 && zb < ZEN_GAMEPAD_BUTTON_COUNT) {
                            new_buttons[zb] = buttons[h];
                        }
                    }
                    if (btn_count > 6 && axes_count <= 4) {
                        s_gamepad_axes[i][ZEN_GAMEPAD_AXIS_LEFT_TRIGGER] = buttons[6] ? 1.0f : -1.0f;
                    }
                    if (btn_count > 7 && axes_count <= 5) {
                        s_gamepad_axes[i][ZEN_GAMEPAD_AXIS_RIGHT_TRIGGER] = buttons[7] ? 1.0f : -1.0f;
                    }

                    for (int b = 0; b < ZEN_GAMEPAD_BUTTON_COUNT; b++) {
                        unsigned char new_state = new_buttons[b];
                        unsigned char old_state = s_gamepad_buttons_pressed[i][b];
                        if (!old_state && new_state) {
                            s_gamepad_buttons_push[i][b] = 1;
                        } else if (old_state && !new_state) {
                            s_gamepad_buttons_release[i][b] = 1;
                        }
                        s_gamepad_buttons_pressed[i][b] = new_state;
                    }
                }
                continue;
            }
        }
        s_gamepad_connected[i] = 0;
        memset(s_gamepad_buttons_pressed[i], 0, sizeof(s_gamepad_buttons_pressed[i]));
        memset(s_gamepad_axes[i], 0, sizeof(s_gamepad_axes[i]));
    }
#else
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        int jid = GLFW_JOYSTICK_1 + i;
        if (glfwJoystickPresent(jid) && glfwJoystickIsGamepad(jid)) {
            GLFWgamepadstate state;
            if (glfwGetGamepadState(jid, &state)) {
                s_gamepad_connected[i] = 1;
                for (int b = 0; b < ZEN_GAMEPAD_BUTTON_COUNT; b++) {
                    unsigned char new_state = state.buttons[b];
                    unsigned char old_state = s_gamepad_buttons_pressed[i][b];
                    if (!old_state && new_state) {
                        s_gamepad_buttons_push[i][b] = 1;
                    } else if (old_state && !new_state) {
                        s_gamepad_buttons_release[i][b] = 1;
                    }
                    s_gamepad_buttons_pressed[i][b] = new_state;
                }
                for (int a = 0; a < ZEN_GAMEPAD_AXIS_COUNT; a++) {
                    s_gamepad_axes[i][a] = state.axes[a];
                }
                continue;
            }
        }
        s_gamepad_connected[i] = 0;
        memset(s_gamepad_buttons_pressed[i], 0, sizeof(s_gamepad_buttons_pressed[i]));
        memset(s_gamepad_axes[i], 0, sizeof(s_gamepad_axes[i]));
    }
#endif

    if (!s_is_in_update_loop) {
        double current_time = glfwGetTime();
        double dt = current_time - s_last_time;
        if (dt <= 0.0001) dt = 0.016667;
        s_delta_time = (float)dt;
        s_last_time = current_time;
    }
}

void zen_begin_frame(uint32_t clear_color) {
    int fb_w = s_fb_width, fb_h = s_fb_height;
    if (s_window) {
        glfwGetFramebufferSize(s_window, &fb_w, &fb_h);
        update_viewport(fb_w, fb_h);
    }

    // 1. 全体を黒でクリア (レターボックス余白)
    glDisable(GL_SCISSOR_TEST);
    glViewport(0, 0, s_fb_width, s_fb_height);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // 2. 仮想解像度アスペクト比のゲーム領域ビューポートとシザーを設定
    glViewport(s_vp_x, s_vp_y, s_vp_w, s_vp_h);
    glEnable(GL_SCISSOR_TEST);
    glScissor(s_vp_x, s_vp_y, s_vp_w, s_vp_h);

    // 3. ゲーム領域を指定色でクリア
    float clr[4];
    clr[0] = ((clear_color >> 24) & 0xFF) / 255.0f;
    clr[1] = ((clear_color >> 16) & 0xFF) / 255.0f;
    clr[2] = ((clear_color >> 8)  & 0xFF) / 255.0f;
    clr[3] = (clear_color         & 0xFF) / 255.0f;
    glClearColor(clr[0], clr[1], clr[2], clr[3]);
    glClear(GL_COLOR_BUFFER_BIT);

    zen_gfx_begin(clear_color, s_base_width, s_base_height);
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
    glDisable(GL_SCISSOR_TEST);
    if (s_window) {
        glfwSwapBuffers(s_window);
    }
}

int zen_update(void) {
    if (!s_window) return 0;

    if (s_is_in_update_loop) {
        // 1. 前フレームの描画を Flush & SwapBuffers
        zen_end_frame();

        // 2. ★Raylib方式★ SwapBuffersの直後に即座にOSイベントをポーリング (DWMのキュー詰まりを根絶)
        zen_poll_events();

#ifdef __EMSCRIPTEN__
        if (s_target_fps > 0) {
            double target_dt = 1.0 / (double)s_target_fps;
            double elapsed = glfwGetTime() - s_frame_start_time;
            if (elapsed < target_dt) {
                double remain_ms = (target_dt - elapsed) * 1000.0;
                if (remain_ms >= 1.0) {
                    emscripten_sleep((unsigned int)remain_ms);
                } else {
                    emscripten_sleep(1);
                }
            } else {
                emscripten_sleep(0);
            }
        } else {
            emscripten_sleep(0);
        }
#else
        // 3. イベント処理後に目標FPSまで精密待機 (WaitTime)
        // 120Hz/144Hz などの高リフレッシュレートモニターでも目標FPSを超えないよう制御
        if (s_target_fps > 0) {
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
#endif
        double now = glfwGetTime();
        double dt = now - s_frame_start_time;
        if (dt <= 0.0001) dt = 0.016667;
        s_delta_time = (float)dt;
        s_frame_start_time = now;
    } else {
        s_is_in_update_loop = 1;
        zen_poll_events();
        s_frame_start_time = glfwGetTime();
        s_delta_time = 0.016667f;
    }

    // 4. 終了判定
    if (glfwWindowShouldClose(s_window)) {
        s_is_in_update_loop = 0;
        return 0;
    }

    // 5. 新しいフレームの描画バッチ開始
    zen_begin_frame(ZEN_RGBA(0, 0, 0, 255));

    return 1;
}

double zen_get_time(void) {
    return glfwGetTime();
}

float zen_get_delta_time(void) {
    return s_delta_time;
}

void zen_get_window_size(int* width, int* height) {
    if (width) *width = s_base_width;
    if (height) *height = s_base_height;
}

void zen_get_mouse_pos(float* x, float* y) {
    int win_w = 1, win_h = 1;
    if (s_window) glfwGetWindowSize(s_window, &win_w, &win_h);
    if (win_w <= 0) win_w = 1;
    if (win_h <= 0) win_h = 1;

    // ウィンドウ論理座標 -> フレームバッファ物理ピクセル座標
    float fb_mouse_x = (float)s_mouse_x * ((float)s_fb_width / (float)win_w);
    float fb_mouse_y = (float)s_mouse_y * ((float)s_fb_height / (float)win_h);

    // ビューポート内オフセットとスケールで仮想座標 (1280x720) に逆変換
    float vx = (fb_mouse_x - (float)s_vp_x) / s_vp_scale;
    float vy = (fb_mouse_y - (float)s_vp_y) / s_vp_scale;

    if (x) *x = vx;
    if (y) *y = vy;
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

int zen_is_gamepad_connected(int id) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return 0;
    return s_gamepad_connected[id];
}

float zen_get_gamepad_axis(int id, int axis) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return 0.0f;
    if (axis < 0 || axis >= ZEN_GAMEPAD_AXIS_COUNT) return 0.0f;
    return s_gamepad_axes[id][axis];
}

int zen_is_gamepad_button_pressed(int id, int button) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return 0;
    if (button < 0 || button >= ZEN_GAMEPAD_BUTTON_COUNT) return 0;
    return s_gamepad_buttons_pressed[id][button];
}

int zen_is_gamepad_button_push(int id, int button) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return 0;
    if (button < 0 || button >= ZEN_GAMEPAD_BUTTON_COUNT) return 0;
    return s_gamepad_buttons_push[id][button];
}

int zen_is_gamepad_button_release(int id, int button) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return 0;
    if (button < 0 || button >= ZEN_GAMEPAD_BUTTON_COUNT) return 0;
    return s_gamepad_buttons_release[id][button];
}


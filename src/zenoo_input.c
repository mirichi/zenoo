// ==========================================
// 入力 (Input / IME / Gamepad) 実装
// ==========================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zenoo_internal.h"

#ifdef _WIN32
#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3native.h>
#include <imm.h>
#endif
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// 入力状態
static double s_mouse_x = 0.0;
static double s_mouse_y = 0.0;
static char s_keys_pressed[512] = {0}; // 押されている状態 (持続)
static char s_keys_push[512] = {0};    // 押した瞬間 (トリガー)
static char s_keys_release[512] = {0}; // 離した瞬間 (リリース)
static char s_keys_repeat[512] = {0};  // 押した瞬間またはリピート

static char s_mouse_pressed[8] = {0};  // 押されている状態 (持続)
static char s_mouse_push[8] = {0};     // 押した瞬間 (トリガー)
static char s_mouse_release[8] = {0};  // 離した瞬間 (リリース)

#define ZEN_CHAR_QUEUE_MAX 64
static uint32_t s_char_queue[ZEN_CHAR_QUEUE_MAX] = {0};
static int s_char_queue_count = 0;
static int s_char_queue_read_idx = 0;

#define ZEN_GAMEPAD_BUTTON_COUNT 15
#define ZEN_GAMEPAD_AXIS_COUNT 6

static unsigned char s_gamepad_buttons_pressed[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static unsigned char s_gamepad_buttons_push[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static unsigned char s_gamepad_buttons_release[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static float s_gamepad_axes[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_AXIS_COUNT] = {{0}};
static unsigned char s_gamepad_connected[ZEN_MAX_GAMEPADS] = {0};

// ------------------------------------------
// GLFW コールバック
// ------------------------------------------
static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods) {
    (void)window; (void)scancode; (void)mods;
    if (key >= 0 && key < 512) {
        if (action == GLFW_PRESS) {
            s_keys_pressed[key] = 1;
            s_keys_push[key] = 1;
            s_keys_repeat[key] = 1;
        } else if (action == GLFW_REPEAT) {
            s_keys_repeat[key] = 1;
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

static void char_callback(GLFWwindow* window, unsigned int codepoint) {
    (void)window;
#ifndef __EMSCRIPTEN__
    if (s_char_queue_count < ZEN_CHAR_QUEUE_MAX) {
        s_char_queue[s_char_queue_count++] = (uint32_t)codepoint;
    }
#else
    // Emscripten環境では透明<input>経由 (zen_push_char) で英数・日本語とも入力されるため、
    // GLFW onKeyPress からの二重注入を抑止する
    (void)codepoint;
#endif
}

static void window_focus_callback(GLFWwindow* window, int focused) {
    (void)window;
    if (!focused) {
        for (int i = 0; i < 8; i++) {
            if (s_mouse_pressed[i]) {
                s_mouse_pressed[i] = 0;
                s_mouse_release[i] = 1;
            }
        }
        for (int i = 0; i < 512; i++) {
            if (s_keys_pressed[i]) {
                s_keys_pressed[i] = 0;
                s_keys_release[i] = 1;
            }
        }
        zen__vibration_stop_all();
    }
}

void zen__input_install(GLFWwindow* window) {
    glfwSetKeyCallback(window, key_callback);
    glfwSetCharCallback(window, char_callback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetCursorPosCallback(window, cursor_pos_callback);
    glfwSetWindowFocusCallback(window, window_focus_callback);
}

// ------------------------------------------
// フレームごとのポーリング & クリア
// ------------------------------------------
void zen__input_poll(void) {
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
}

void zen__input_end_frame(void) {
    memset(s_keys_push, 0, sizeof(s_keys_push));
    memset(s_keys_release, 0, sizeof(s_keys_release));
    memset(s_keys_repeat, 0, sizeof(s_keys_repeat));
    memset(s_mouse_push, 0, sizeof(s_mouse_push));
    memset(s_mouse_release, 0, sizeof(s_mouse_release));
    memset(s_gamepad_buttons_push, 0, sizeof(s_gamepad_buttons_push));
    memset(s_gamepad_buttons_release, 0, sizeof(s_gamepad_buttons_release));
    s_char_queue_count = 0;
    s_char_queue_read_idx = 0;
}

// ------------------------------------------
// 公開入力 API
// ------------------------------------------
void zen_get_mouse_pos(float* x, float* y) {
    GLFWwindow* win = zen__window();
    int win_w = 1, win_h = 1;
    if (win) glfwGetWindowSize(win, &win_w, &win_h);
    if (win_w <= 0) win_w = 1;
    if (win_h <= 0) win_h = 1;

    const ZenViewport* vp = zen__viewport();

    // ウィンドウ論理座標 -> フレームバッファ物理ピクセル座標
    float fb_mouse_x = (float)s_mouse_x * ((float)vp->fb_w / (float)win_w);
    float fb_mouse_y = (float)s_mouse_y * ((float)vp->fb_h / (float)win_h);

    // ビューポート内オフセットとスケールで仮想座標に逆変換
    float vx = (fb_mouse_x - (float)vp->x) / vp->scale;
    float vy = (fb_mouse_y - (float)vp->y) / vp->scale;

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

int zen_is_key_repeat(int key) {
    if (key >= 0 && key < 512) return s_keys_repeat[key];
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

int zen_get_char_queue(uint32_t* buffer, int max_count) {
    if (!buffer || max_count <= 0) return 0;
    int count = (s_char_queue_count < max_count) ? s_char_queue_count : max_count;
    for (int i = 0; i < count; i++) {
        buffer[i] = s_char_queue[i];
    }
    return count;
}

int zen_get_char(void) {
    if (s_char_queue_read_idx < s_char_queue_count) {
        return (int)s_char_queue[s_char_queue_read_idx++];
    }
    return -1;
}

#ifdef __EMSCRIPTEN__
EMSCRIPTEN_KEEPALIVE
#endif
void zen_push_char(unsigned int codepoint) {
    if (s_char_queue_count < ZEN_CHAR_QUEUE_MAX) {
        s_char_queue[s_char_queue_count++] = (uint32_t)codepoint;
    }
}

#if defined(_WIN32)
void zen_set_ime_position(int x, int y) {
    GLFWwindow* win = zen__window();
    if (!win) return;
    HWND hwnd = glfwGetWin32Window(win);
    if (!hwnd) return;
    HIMC himc = ImmGetContext(hwnd);
    if (himc) {
        if (x < 0 || y < 0) {
            ImmReleaseContext(hwnd, himc);
            return;
        }
        int win_w = 0, win_h = 0;
        glfwGetWindowSize(win, &win_w, &win_h);
        const ZenViewport* vp = zen__viewport();
        float fb_to_win = (vp->fb_w > 0 && win_w > 0) ? ((float)win_w / (float)vp->fb_w) : 1.0f;
        int screen_x = (int)((vp->x + (float)x * vp->scale) * fb_to_win);
        int screen_y = (int)((vp->y + (float)y * vp->scale) * fb_to_win);

        COMPOSITIONFORM cf;
        cf.dwStyle = CFS_POINT;
        cf.ptCurrentPos.x = screen_x;
        cf.ptCurrentPos.y = screen_y;
        ImmSetCompositionWindow(himc, &cf);
        ImmReleaseContext(hwnd, himc);
    }
}
#elif defined(__EMSCRIPTEN__)
void zen_set_ime_position(int x, int y) {
    EM_ASM({
        if (window.zenooOnFocusTextInput) {
            window.zenooOnFocusTextInput($0, $1);
        }
    }, x, y);
}
#else
void zen_set_ime_position(int x, int y) {
    (void)x; (void)y;
}
#endif

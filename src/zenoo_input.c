// ==========================================
// 入力 (Input / IME / Gamepad) 実装 (SDL3 バックエンド)
// ==========================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zenoo_internal.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// 入力状態
static double s_mouse_x = 0.0;
static double s_mouse_y = 0.0;
static double s_mouse_wheel_x = 0.0;
static double s_mouse_wheel_y = 0.0;
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

static SDL_Gamepad*   s_gamepads[ZEN_MAX_GAMEPADS] = {NULL};
static SDL_JoystickID s_gamepad_ids[ZEN_MAX_GAMEPADS] = {0};
static unsigned char  s_gamepad_buttons_pressed[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static unsigned char  s_gamepad_buttons_push[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static unsigned char  s_gamepad_buttons_release[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_BUTTON_COUNT] = {{0}};
static float          s_gamepad_axes[ZEN_MAX_GAMEPADS][ZEN_GAMEPAD_AXIS_COUNT] = {{0}};
static unsigned char  s_gamepad_connected[ZEN_MAX_GAMEPADS] = {0};

// ------------------------------------------
// SDL3 イベント処理
// ------------------------------------------
static int sdl_button_to_zen(Uint8 sdl_btn) {
    if (sdl_btn == SDL_BUTTON_LEFT)   return ZEN_MOUSE_LEFT;
    if (sdl_btn == SDL_BUTTON_RIGHT)  return ZEN_MOUSE_RIGHT;
    if (sdl_btn == SDL_BUTTON_MIDDLE) return ZEN_MOUSE_MIDDLE;
    if (sdl_btn >= 4 && sdl_btn <= 8) return (int)sdl_btn - 1;
    return -1;
}

#ifdef __EMSCRIPTEN__
static void zen__setup_web_input_bridge(void) {
    /* ブラウザ側の IME テキスト入力 (<input>) とマルチタッチ入力を Zenoo エンジン側で自己完結させる */
    EM_ASM({
        if (window.__zen_input_bridge_installed) return;
        window.__zen_input_bridge_installed = true;

        var getCanvas = function() {
            return (typeof Module !== "undefined" && Module.canvas)
                || document.getElementById("canvas")
                || document.querySelector("canvas");
        };

        /* 1. IME テキスト入力連携 (非表示 <input> を自動生成・制御) */
        var hiddenInput = document.getElementById("zenoo-hidden-input");
        if (!hiddenInput) {
            hiddenInput = document.createElement("input");
            hiddenInput.id = "zenoo-hidden-input";
            hiddenInput.type = "text";
            hiddenInput.setAttribute("autocomplete", "off");
            hiddenInput.setAttribute("autocorrect", "off");
            hiddenInput.setAttribute("autocapitalize", "off");
            hiddenInput.setAttribute("spellcheck", "false");
            var cv0 = getCanvas();
            var host = (cv0 && cv0.parentElement) ? cv0.parentElement : document.body;
            if (host) host.appendChild(hiddenInput);
        }

        hiddenInput.style.position = "fixed";
        hiddenInput.style.top = "-9999px";
        hiddenInput.style.left = "-9999px";
        hiddenInput.style.width = "1px";
        hiddenInput.style.height = "20px";
        hiddenInput.style.padding = "0";
        hiddenInput.style.border = "0";
        hiddenInput.style.opacity = "0";
        hiddenInput.style.pointerEvents = "none";
        hiddenInput.style.fontSize = "16px";
        hiddenInput.style.webkitUserSelect = "text";
        hiddenInput.style.userSelect = "text";

        var isComposing = false;

        var sendStringToZenoo = function(text) {
            if (!text) return;
            for (var i = 0; i < text.length; i++) {
                var code = text.charCodeAt(i);
                if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
                    var high = code;
                    var low = text.charCodeAt(++i);
                    code = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
                }
                _zen_push_char(code);
            }
        };

        /* SDL3 Emscripten の window 上 keypress リスナーによる preventDefault() を回避 */
        hiddenInput.addEventListener("keypress", function(e) {
            e.stopPropagation();
        });

        /* IME 変換中のキー操作 (Enter / Backspace / 矢印等) が SDL3 へバブリングしないようにする */
        hiddenInput.addEventListener("keydown", function(e) {
            if (isComposing || e.isComposing || e.keyCode === 229) {
                e.stopPropagation();
            }
        });

        hiddenInput.addEventListener("compositionstart", function() {
            isComposing = true;
        });

        hiddenInput.addEventListener("compositionend", function(e) {
            isComposing = false;
            var text = e.data || hiddenInput.value;
            if (text && text.length > 0) {
                sendStringToZenoo(text);
            }
            hiddenInput.value = "";
        });

        hiddenInput.addEventListener("input", function() {
            if (!isComposing && hiddenInput.value.length > 0) {
                sendStringToZenoo(hiddenInput.value);
                hiddenInput.value = "";
            }
        });

        window.__zen_focus_text_input = function(x, y) {
            if (x >= 0 && y >= 0) {
                var cv = getCanvas();
                if (cv) {
                    var rect = cv.getBoundingClientRect();
                    if (rect.width > 0 && rect.height > 0 && cv.width > 0 && cv.height > 0) {
                        var sx = rect.width / cv.width;
                        var sy = rect.height / cv.height;
                        var ix = rect.left + x * sx;
                        var iy = rect.top + y * sy;
                        var maxX = Math.max(0, window.innerWidth - 2);
                        var maxY = Math.max(0, window.innerHeight - 2);
                        hiddenInput.style.left = Math.max(0, Math.min(maxX, ix)) + "px";
                        hiddenInput.style.top = Math.max(0, Math.min(maxY, iy)) + "px";
                    }
                }
                if (document.activeElement !== hiddenInput) {
                    hiddenInput.focus({ preventScroll: true });
                }
            } else {
                if (document.activeElement === hiddenInput) {
                    hiddenInput.blur();
                }
            }
        };

        /* 2. マルチタッチイベント連携 (_zen_push_touch) */
        var activeTouchIds = {};

        var isHtmlUiTarget = function(target) {
            return !!(target && target.closest && target.closest("button, a, input, textarea, select, label, [data-zenoo-ui]"));
        };

        var getCanvasOffset = function(cv, touch) {
            var rect = cv.getBoundingClientRect();
            var scaleX = rect.width > 0 ? (cv.width / rect.width) : 1.0;
            var scaleY = rect.height > 0 ? (cv.height / rect.height) : 1.0;
            var pos = {};
            pos.x = (touch.clientX - rect.left) * scaleX;
            pos.y = (touch.clientY - rect.top) * scaleY;
            return pos;
        };

        var cvInit = getCanvas();
        var touchStartTarget = cvInit;
        if (cvInit && cvInit.parentElement) {
            var pe = cvInit.parentElement;
            if (pe.id === "canvas-container" || pe.hasAttribute("data-zenoo-touch-area")) {
                touchStartTarget = pe;
            }
        }

        if (touchStartTarget) {
            touchStartTarget.addEventListener("touchstart", function(e) {
                if (isHtmlUiTarget(e.target)) return;
                var cv = getCanvas();
                if (!cv) return;
                if (e.cancelable) e.preventDefault();
                var touches = e.changedTouches;
                if (!touches) return;
                for (var i = 0; i < touches.length; i++) {
                    var t = touches[i];
                    activeTouchIds[t.identifier] = true;
                    var pos = getCanvasOffset(cv, t);
                    _zen_push_touch(t.identifier, 0, pos.x, pos.y);
                }
            }, { passive: false });
        }

        var handleTrackedTouch = function(e, type) {
            var touches = e.changedTouches;
            if (!touches) return;
            var matched = false;
            for (var i = 0; i < touches.length; i++) {
                if (activeTouchIds[touches[i].identifier]) {
                    matched = true;
                    break;
                }
            }
            if (!matched) return;
            var cv = getCanvas();
            if (!cv) return;
            if (e.cancelable) e.preventDefault();
            for (var j = 0; j < touches.length; j++) {
                var t = touches[j];
                if (!activeTouchIds[t.identifier]) continue;
                var pos = getCanvasOffset(cv, t);
                _zen_push_touch(t.identifier, type, pos.x, pos.y);
                if (type === 2 || type === 3) {
                    delete activeTouchIds[t.identifier];
                }
            }
        };

        window.addEventListener("touchmove", function(e) { handleTrackedTouch(e, 1); }, { passive: false });
        window.addEventListener("touchend", function(e) { handleTrackedTouch(e, 2); }, { passive: false });
        window.addEventListener("touchcancel", function(e) { handleTrackedTouch(e, 3); }, { passive: false });
    });
}
#endif

void zen__input_init(SDL_Window* window) {
    if (window) {
        SDL_StartTextInput(window);
    }
#ifdef __EMSCRIPTEN__
    zen__setup_web_input_bridge();
#endif
}

void zen__input_shutdown(void) {
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        if (s_gamepads[i]) {
            SDL_CloseGamepad(s_gamepads[i]);
            s_gamepads[i] = NULL;
        }
        s_gamepad_ids[i] = 0;
        s_gamepad_connected[i] = 0;
    }
}

SDL_Gamepad* zen__input_gamepad(int id) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return NULL;
    return s_gamepads[id];
}

void zen__input_handle_event(const SDL_Event* event) {
    if (!event) return;

    switch (event->type) {
    case SDL_EVENT_KEY_DOWN: {
        int sc = (int)event->key.scancode;
        if (sc > 0 && sc < 512) {
            if (!event->key.repeat) {
                s_keys_pressed[sc] = 1;
                s_keys_push[sc] = 1;
            }
            s_keys_repeat[sc] = 1;
        }
        break;
    }
    case SDL_EVENT_KEY_UP: {
        int sc = (int)event->key.scancode;
        if (sc > 0 && sc < 512) {
            s_keys_pressed[sc] = 0;
            s_keys_release[sc] = 1;
        }
        break;
    }
    case SDL_EVENT_TEXT_INPUT: {
#ifndef __EMSCRIPTEN__
        const char* p = event->text.text;
        if (p) {
            while (*p && s_char_queue_count < ZEN_CHAR_QUEUE_MAX) {
                Uint32 cp = SDL_StepUTF8(&p, NULL);
                if (cp == 0) break;
                if (cp != SDL_INVALID_UNICODE_CODEPOINT) {
                    s_char_queue[s_char_queue_count++] = (uint32_t)cp;
                }
            }
        }
#endif
        break;
    }
    case SDL_EVENT_MOUSE_BUTTON_DOWN: {
        if (event->button.which == SDL_TOUCH_MOUSEID) break;
        s_mouse_x = (double)event->button.x;
        s_mouse_y = (double)event->button.y;
        int btn = sdl_button_to_zen(event->button.button);
        if (btn >= 0 && btn < 8) {
            s_mouse_pressed[btn] = 1;
            s_mouse_push[btn] = 1;
#ifndef __EMSCRIPTEN__
            SDL_CaptureMouse(true);
#endif
        }
        break;
    }
    case SDL_EVENT_MOUSE_BUTTON_UP: {
        if (event->button.which == SDL_TOUCH_MOUSEID) break;
        s_mouse_x = (double)event->button.x;
        s_mouse_y = (double)event->button.y;
        int btn = sdl_button_to_zen(event->button.button);
        if (btn >= 0 && btn < 8) {
            s_mouse_pressed[btn] = 0;
            s_mouse_release[btn] = 1;
#ifndef __EMSCRIPTEN__
            int any_pressed = 0;
            for (int i = 0; i < 8; i++) {
                if (s_mouse_pressed[i]) any_pressed = 1;
            }
            if (!any_pressed) {
                SDL_CaptureMouse(false);
            }
#endif
        }
        break;
    }
    case SDL_EVENT_MOUSE_MOTION:
        if (event->motion.which == SDL_TOUCH_MOUSEID) break;
        s_mouse_x = (double)event->motion.x;
        s_mouse_y = (double)event->motion.y;
        break;
    case SDL_EVENT_MOUSE_WHEEL:
        s_mouse_wheel_x += (double)event->wheel.x;
        s_mouse_wheel_y += (double)event->wheel.y;
        break;
#ifndef __EMSCRIPTEN__
    case SDL_EVENT_FINGER_DOWN:
    case SDL_EVENT_FINGER_MOTION:
    case SDL_EVENT_FINGER_UP:
    case SDL_EVENT_FINGER_CANCELED: {
        SDL_Window* win = zen__window();
        int win_w = 1, win_h = 1;
        if (win) SDL_GetWindowSize(win, &win_w, &win_h);
        int ttype = 0;
        if (event->type == SDL_EVENT_FINGER_MOTION) ttype = 1;
        else if (event->type == SDL_EVENT_FINGER_UP) ttype = 2;
        else if (event->type == SDL_EVENT_FINGER_CANCELED) ttype = 3;
        zen_push_touch((int)(event->tfinger.fingerID & 0x7FFFFFFF), ttype, event->tfinger.x * (float)win_w, event->tfinger.y * (float)win_h);
        break;
    }
#endif
    case SDL_EVENT_WINDOW_FOCUS_LOST:
#ifndef __EMSCRIPTEN__
        SDL_CaptureMouse(false);
#endif
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
        s_mouse_wheel_x = 0.0;
        s_mouse_wheel_y = 0.0;
        zen__vibration_stop_all();
        break;
    default:
        break;
    }
}

// ------------------------------------------
// フレームごとのポーリング & クリア
// ------------------------------------------
void zen__input_poll(void) {
    // 1. 切断されたゲームパッドをクローズ
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        if (s_gamepads[i] && !SDL_GamepadConnected(s_gamepads[i])) {
            SDL_CloseGamepad(s_gamepads[i]);
            s_gamepads[i] = NULL;
            s_gamepad_ids[i] = 0;
            s_gamepad_connected[i] = 0;
            memset(s_gamepad_buttons_pressed[i], 0, sizeof(s_gamepad_buttons_pressed[i]));
            memset(s_gamepad_axes[i], 0, sizeof(s_gamepad_axes[i]));
        }
    }

    // 2. 新規接続されたゲームパッドを空きスロットに割り当て
    int count = 0;
    SDL_JoystickID* ids = SDL_GetGamepads(&count);
    if (ids) {
        for (int j = 0; j < count; j++) {
            SDL_JoystickID jid = ids[j];
            int already_open = 0;
            for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
                if (s_gamepads[i] && s_gamepad_ids[i] == jid) {
                    already_open = 1;
                    break;
                }
            }
            if (!already_open) {
                for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
                    if (!s_gamepads[i]) {
                        SDL_Gamepad* pad = SDL_OpenGamepad(jid);
                        if (pad) {
                            s_gamepads[i] = pad;
                            s_gamepad_ids[i] = jid;
                        }
                        break;
                    }
                }
            }
        }
        SDL_free(ids);
    }

    // 3. 各スロットのボタン・アナログ軸状態を更新
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        SDL_Gamepad* pad = s_gamepads[i];
        if (pad && SDL_GamepadConnected(pad)) {
            s_gamepad_connected[i] = 1;
            for (int b = 0; b < ZEN_GAMEPAD_BUTTON_COUNT; b++) {
                unsigned char new_state = SDL_GetGamepadButton(pad, (SDL_GamepadButton)b) ? 1 : 0;
                unsigned char old_state = s_gamepad_buttons_pressed[i][b];
                if (!old_state && new_state) {
                    s_gamepad_buttons_push[i][b] = 1;
                } else if (old_state && !new_state) {
                    s_gamepad_buttons_release[i][b] = 1;
                }
                s_gamepad_buttons_pressed[i][b] = new_state;
            }
            for (int a = 0; a < ZEN_GAMEPAD_AXIS_COUNT; a++) {
                Sint16 raw = SDL_GetGamepadAxis(pad, (SDL_GamepadAxis)a);
                float v = 0.0f;
                if (a == ZEN_GAMEPAD_AXIS_LEFT_TRIGGER || a == ZEN_GAMEPAD_AXIS_RIGHT_TRIGGER) {
                    v = (float)raw / 32767.0f;
                    if (v < 0.0f) v = 0.0f;
                    if (v > 1.0f) v = 1.0f;
                } else {
                    v = (raw < 0) ? ((float)raw / 32768.0f) : ((float)raw / 32767.0f);
                    if (v < -1.0f) v = -1.0f;
                    if (v > 1.0f) v = 1.0f;
                }
                s_gamepad_axes[i][a] = v;
            }
        } else {
            s_gamepad_connected[i] = 0;
            memset(s_gamepad_buttons_pressed[i], 0, sizeof(s_gamepad_buttons_pressed[i]));
            memset(s_gamepad_axes[i], 0, sizeof(s_gamepad_axes[i]));
        }
    }
}

void zen__input_end_frame(void) {
    memset(s_keys_push, 0, sizeof(s_keys_push));
    memset(s_keys_release, 0, sizeof(s_keys_release));
    memset(s_keys_repeat, 0, sizeof(s_keys_repeat));
    memset(s_mouse_push, 0, sizeof(s_mouse_push));
    memset(s_mouse_release, 0, sizeof(s_mouse_release));
    memset(s_gamepad_buttons_push, 0, sizeof(s_gamepad_buttons_push));
    memset(s_gamepad_buttons_release, 0, sizeof(s_gamepad_buttons_release));
    s_mouse_wheel_x = 0.0;
    s_mouse_wheel_y = 0.0;
    s_char_queue_count = 0;
    s_char_queue_read_idx = 0;
}

// ------------------------------------------
// 公開入力 API
// ------------------------------------------
void zen_get_mouse_pos(float* x, float* y) {
    SDL_Window* win = zen__window();
    int win_w = 1, win_h = 1;
    if (win) SDL_GetWindowSize(win, &win_w, &win_h);
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

float zen_get_mouse_wheel_x(void) {
    return (float)s_mouse_wheel_x;
}

float zen_get_mouse_wheel_y(void) {
    return (float)s_mouse_wheel_y;
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

void zen_set_ime_position(int x, int y) {
#if defined(__EMSCRIPTEN__)
    EM_ASM({
        if (window.__zen_focus_text_input) {
            window.__zen_focus_text_input($0, $1);
        }
    }, x, y);
#else
    SDL_Window* win = zen__window();
    if (!win) return;
    if (x < 0 || y < 0) {
        SDL_SetTextInputArea(win, NULL, 0);
        return;
    }
    int win_w = 0, win_h = 0;
    SDL_GetWindowSize(win, &win_w, &win_h);
    const ZenViewport* vp = zen__viewport();
    float fb_to_win = (vp->fb_w > 0 && win_w > 0) ? ((float)win_w / (float)vp->fb_w) : 1.0f;
    int screen_x = (int)((vp->x + (float)x * vp->scale) * fb_to_win);
    int screen_y = (int)((vp->y + (float)y * vp->scale) * fb_to_win);

    SDL_Rect rect = { screen_x, screen_y, 1, 20 };
    SDL_SetTextInputArea(win, &rect, 0);
#endif
}

// ------------------------------------------
// タッチ入力キュー
// ------------------------------------------
typedef struct {
    int id;
    int type; // 0: DOWN, 1: MOVE, 2: UP, 3: CANCEL
    float x;
    float y;
} ZenRawTouchEvent;

static ZenRawTouchEvent s_touch_queue[ZEN_TOUCH_QUEUE_MAX];
static int s_touch_queue_count = 0;

static void zen__screen_to_virtual(float win_x, float win_y, float* out_vx, float* out_vy) {
    SDL_Window* win = zen__window();
    if (!win) {
        if (out_vx) *out_vx = win_x;
        if (out_vy) *out_vy = win_y;
        return;
    }
    int win_w = 1, win_h = 1;
    SDL_GetWindowSize(win, &win_w, &win_h);
    if (win_w <= 0) win_w = 1;
    if (win_h <= 0) win_h = 1;

    const ZenViewport* vp = zen__viewport();
    if (!vp || vp->scale <= 0.0001f) {
        if (out_vx) *out_vx = win_x;
        if (out_vy) *out_vy = win_y;
        return;
    }

    float fb_x = win_x * ((float)vp->fb_w / (float)win_w);
    float fb_y = win_y * ((float)vp->fb_h / (float)win_h);

    if (out_vx) *out_vx = (fb_x - (float)vp->x) / vp->scale;
    if (out_vy) *out_vy = (fb_y - (float)vp->y) / vp->scale;
}

#ifdef __EMSCRIPTEN__
EMSCRIPTEN_KEEPALIVE
#endif
void zen_push_touch(int id, int type, float win_x, float win_y) {
    if (s_touch_queue_count < ZEN_TOUCH_QUEUE_MAX) {
        float vx = 0.0f, vy = 0.0f;
        zen__screen_to_virtual(win_x, win_y, &vx, &vy);
        s_touch_queue[s_touch_queue_count].id = id;
        s_touch_queue[s_touch_queue_count].type = type;
        s_touch_queue[s_touch_queue_count].x = vx;
        s_touch_queue[s_touch_queue_count].y = vy;
        s_touch_queue_count++;
    }
}

int zen_get_touch_count(void) {
    return s_touch_queue_count;
}

int zen_get_touch_event_id(int idx) {
    if (idx >= 0 && idx < s_touch_queue_count) return s_touch_queue[idx].id;
    return -1;
}

int zen_get_touch_event_type(int idx) {
    if (idx >= 0 && idx < s_touch_queue_count) return s_touch_queue[idx].type;
    return -1;
}

float zen_get_touch_event_x(int idx) {
    if (idx >= 0 && idx < s_touch_queue_count) return s_touch_queue[idx].x;
    return 0.0f;
}

float zen_get_touch_event_y(int idx) {
    if (idx >= 0 && idx < s_touch_queue_count) return s_touch_queue[idx].y;
    return 0.0f;
}

void zen_clear_touch_events(void) {
    s_touch_queue_count = 0;
}

// ==========================================
// 振動 (Vibration / Force Feedback) 実装
// ==========================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zenoo_internal.h"

#if defined(_WIN32)
#include <windows.h>
static float s_gamepad_vibration_timer[ZEN_MAX_GAMEPADS] = {0};
typedef struct _ZEN_XINPUT_VIBRATION {
    unsigned short wLeftMotorSpeed;
    unsigned short wRightMotorSpeed;
} ZEN_XINPUT_VIBRATION;

typedef unsigned long (WINAPI *pfn_XInputSetState)(unsigned long dwUserIndex, ZEN_XINPUT_VIBRATION* pVibration);
static pfn_XInputSetState s_pfnXInputSetState = NULL;
static HMODULE s_hXInputDll = NULL;
static int s_xinput_initialized = 0;

static void init_xinput(void) {
    if (s_xinput_initialized) return;
    s_xinput_initialized = 1;
    const char* dll_names[] = {"xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll"};
    for (int i = 0; i < 3; i++) {
        s_hXInputDll = LoadLibraryA(dll_names[i]);
        if (s_hXInputDll) {
            s_pfnXInputSetState = (pfn_XInputSetState)GetProcAddress(s_hXInputDll, "XInputSetState");
            if (s_pfnXInputSetState) break;
            FreeLibrary(s_hXInputDll);
            s_hXInputDll = NULL;
        }
    }
}
#elif defined(__linux__) && !defined(__EMSCRIPTEN__)
#include <linux/input.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
static int s_linux_ff_fds[ZEN_MAX_GAMEPADS] = {-1, -1, -1, -1};
static int s_linux_ff_effect_ids[ZEN_MAX_GAMEPADS] = {-1, -1, -1, -1};

static void init_linux_ff(int id) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return;
    if (s_linux_ff_fds[id] >= 0) return;

    char path[64];
    int match_count = 0;
    for (int ev = 0; ev < 32; ev++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", ev);
        int fd = open(path, O_RDWR | O_NONBLOCK);
        if (fd < 0) continue;

        unsigned long ev_bits[(EV_MAX + 7) / 8] = {0};
        unsigned long ff_bits[(FF_MAX + 7) / 8] = {0};
        if (ioctl(fd, EVIOCGBIT(0, sizeof(ev_bits)), ev_bits) >= 0) {
            if (ev_bits[EV_FF / 8] & (1 << (EV_FF % 8))) {
                if (ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ff_bits)), ff_bits) >= 0) {
                    if (ff_bits[FF_RUMBLE / 8] & (1 << (FF_RUMBLE % 8))) {
                        if (match_count == id) {
                            s_linux_ff_fds[id] = fd;
                            return;
                        }
                        match_count++;
                    }
                }
            }
        }
        close(fd);
    }
}
#elif defined(__EMSCRIPTEN__)
#include <emscripten.h>
#endif

void zen__vibration_init(void) {
#if defined(_WIN32)
    init_xinput();
#elif defined(__EMSCRIPTEN__)
    EM_ASM({
        if (!window.__zen_vibration_cleanup_registered) {
            window.__zen_vibration_cleanup_registered = true;
            var stopAll = function() {
                try {
                    if (navigator.getGamepads) {
                        var gps = navigator.getGamepads();
                        for (var i = 0; i < gps.length; i++) {
                            var g = gps[i];
                            if (g && g.vibrationActuator) {
                                if (g.vibrationActuator.reset) g.vibrationActuator.reset().catch(function(){});
                                if (g.vibrationActuator.playEffect) {
                                    g.vibrationActuator.playEffect('dual-rumble', {
                                        startDelay: 0,
                                        duration: 1,
                                        weakMagnitude: 0,
                                        strongMagnitude: 0
                                    }).catch(function(){});
                                }
                            }
                        }
                    }
                    if (navigator.vibrate) {
                        navigator.vibrate(0);
                    }
                } catch(e) {}
            };
            window.addEventListener('pagehide', stopAll);
            window.addEventListener('beforeunload', stopAll);
            document.addEventListener('visibilitychange', function() {
                if (document.visibilityState === 'hidden') {
                    stopAll();
                }
            });
        }
    });
#endif
}

void zen__vibration_update(float dt) {
#if defined(_WIN32)
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        if (s_gamepad_vibration_timer[i] > 0.0f) {
            s_gamepad_vibration_timer[i] -= dt;
            if (s_gamepad_vibration_timer[i] <= 0.0f) {
                s_gamepad_vibration_timer[i] = 0.0f;
                if (s_pfnXInputSetState) {
                    ZEN_XINPUT_VIBRATION vib = {0, 0};
                    s_pfnXInputSetState((unsigned long)i, &vib);
                }
            }
        }
    }
#elif defined(__linux__) && !defined(__EMSCRIPTEN__)
    // 切断されたゲームパッドのFF用fdを閉じる
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        if (!zen_is_gamepad_connected(i) && s_linux_ff_fds[i] >= 0) {
            close(s_linux_ff_fds[i]);
            s_linux_ff_fds[i] = -1;
            s_linux_ff_effect_ids[i] = -1;
        }
    }
#else
    (void)dt;
#endif
}

void zen__vibration_stop_all(void) {
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        zen_gamepad_vibrate(i, 0.0f, 0.0f, 0.0f);
    }
    zen_vibrate(0.0f);
}

void zen__vibration_shutdown(void) {
    zen__vibration_stop_all();

#if defined(_WIN32)
    if (s_hXInputDll) {
        FreeLibrary(s_hXInputDll);
        s_hXInputDll = NULL;
        s_pfnXInputSetState = NULL;
        s_xinput_initialized = 0;
    }
#elif defined(__linux__) && !defined(__EMSCRIPTEN__)
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        if (s_linux_ff_fds[i] >= 0) {
            if (s_linux_ff_effect_ids[i] >= 0) {
                ioctl(s_linux_ff_fds[i], EVIOCRMFF, s_linux_ff_effect_ids[i]);
                s_linux_ff_effect_ids[i] = -1;
            }
            close(s_linux_ff_fds[i]);
            s_linux_ff_fds[i] = -1;
        }
    }
#endif
}

void zen_gamepad_vibrate(int id, float strong, float weak, float duration) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return;

#if defined(_WIN32)
    init_xinput();
    if (s_pfnXInputSetState) {
        if (duration <= 0.0f) {
            s_gamepad_vibration_timer[id] = 0.0f;
            ZEN_XINPUT_VIBRATION vib = {0, 0};
            s_pfnXInputSetState((unsigned long)id, &vib);
            return;
        }
        if (strong < 0.0f) strong = 0.0f; else if (strong > 1.0f) strong = 1.0f;
        if (weak < 0.0f) weak = 0.0f; else if (weak > 1.0f) weak = 1.0f;
        ZEN_XINPUT_VIBRATION vib;
        vib.wLeftMotorSpeed = (unsigned short)(strong * 65535.0f);
        vib.wRightMotorSpeed = (unsigned short)(weak * 65535.0f);
        s_pfnXInputSetState((unsigned long)id, &vib);
        s_gamepad_vibration_timer[id] = duration;
    }
#elif defined(__EMSCRIPTEN__)
    if (duration <= 0.0f || (strong <= 0.0f && weak <= 0.0f)) {
        EM_ASM({
            var id = $0;
            var gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
            if (gamepads && gamepads[id] && gamepads[id].vibrationActuator) {
                var act = gamepads[id].vibrationActuator;
                if (act.reset) act.reset().catch(function(e) {});
                if (act.playEffect) {
                    act.playEffect('dual-rumble', {
                        startDelay: 0,
                        duration: 1,
                        weakMagnitude: 0,
                        strongMagnitude: 0
                    }).catch(function(e) {});
                }
            }
        }, id);
        return;
    }
    EM_ASM({
        var id = $0;
        var strong = $1;
        var weak = $2;
        var duration = $3 * 1000.0;
        var gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
        if (gamepads && gamepads[id] && gamepads[id].vibrationActuator) {
            gamepads[id].vibrationActuator.playEffect('dual-rumble', {
                startDelay: 0,
                duration: duration,
                weakMagnitude: weak,
                strongMagnitude: strong
            }).catch(function(e) {});
        }
    }, id, strong, weak, duration);
#elif defined(__linux__) && !defined(__EMSCRIPTEN__)
    init_linux_ff(id);
    int fd = s_linux_ff_fds[id];
    if (fd >= 0) {
        if (duration <= 0.0f || (strong <= 0.0f && weak <= 0.0f)) {
            if (s_linux_ff_effect_ids[id] >= 0) {
                struct input_event stop_ev;
                memset(&stop_ev, 0, sizeof(stop_ev));
                stop_ev.type = EV_FF;
                stop_ev.code = (unsigned short)s_linux_ff_effect_ids[id];
                stop_ev.value = 0;
                ssize_t _w = write(fd, &stop_ev, sizeof(stop_ev));
                (void)_w;

                ioctl(fd, EVIOCRMFF, s_linux_ff_effect_ids[id]);
                s_linux_ff_effect_ids[id] = -1;
            }
            return;
        }

        if (strong < 0.0f) strong = 0.0f; else if (strong > 1.0f) strong = 1.0f;
        if (weak < 0.0f) weak = 0.0f; else if (weak > 1.0f) weak = 1.0f;

        struct ff_effect effect;
        memset(&effect, 0, sizeof(effect));
        effect.type = FF_RUMBLE;
        effect.id = s_linux_ff_effect_ids[id];
        effect.u.rumble.strong_magnitude = (unsigned short)(strong * 65535.0f);
        effect.u.rumble.weak_magnitude = (unsigned short)(weak * 65535.0f);
        effect.replay.length = (unsigned short)(duration * 1000.0f);
        effect.replay.delay = 0;

        if (ioctl(fd, EVIOCSFF, &effect) < 0) {
            effect.id = -1;
            if (ioctl(fd, EVIOCSFF, &effect) < 0) {
                return;
            }
        }
        s_linux_ff_effect_ids[id] = effect.id;

        struct input_event play_ev;
        memset(&play_ev, 0, sizeof(play_ev));
        play_ev.type = EV_FF;
        play_ev.code = (unsigned short)effect.id;
        play_ev.value = 1;
        ssize_t _w2 = write(fd, &play_ev, sizeof(play_ev));
        (void)_w2;
    }
#else
    (void)id; (void)strong; (void)weak; (void)duration;
#endif
}

void zen_vibrate(float duration) {
#if defined(__EMSCRIPTEN__)
    if (duration > 0.0f) {
        EM_ASM({
            var duration = $0 * 1000.0;
            if (navigator.vibrate) {
                try {
                    navigator.vibrate(duration);
                } catch(e) {}
            }
        }, duration);
    } else {
        EM_ASM({
            if (navigator.vibrate) {
                try {
                    navigator.vibrate(0);
                } catch(e) {}
            }
        });
    }
#else
    (void)duration;
#endif
}

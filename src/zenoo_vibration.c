// ==========================================
// 振動 (Vibration / Force Feedback) 実装 (SDL3 バックエンド)
// ==========================================
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zenoo_internal.h"

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

void zen__vibration_init(void) {
#ifdef __EMSCRIPTEN__
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
    (void)dt;
}

void zen__vibration_stop_all(void) {
    for (int i = 0; i < ZEN_MAX_GAMEPADS; i++) {
        zen_gamepad_vibrate(i, 0.0f, 0.0f, 0.0f);
    }
    zen_vibrate(0.0f);
}

void zen__vibration_shutdown(void) {
    zen__vibration_stop_all();
}

void zen_gamepad_vibrate(int id, float strong, float weak, float duration) {
    if (id < 0 || id >= ZEN_MAX_GAMEPADS) return;

#ifdef __EMSCRIPTEN__
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
    if (strong < 0.0f) strong = 0.0f; else if (strong > 1.0f) strong = 1.0f;
    if (weak < 0.0f) weak = 0.0f; else if (weak > 1.0f) weak = 1.0f;
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
#else
    SDL_Gamepad* pad = zen__input_gamepad(id);
    if (!pad) return;
    if (duration <= 0.0f || (strong <= 0.0f && weak <= 0.0f)) {
        SDL_RumbleGamepad(pad, 0, 0, 0);
        return;
    }
    if (strong < 0.0f) strong = 0.0f; else if (strong > 1.0f) strong = 1.0f;
    if (weak < 0.0f) weak = 0.0f; else if (weak > 1.0f) weak = 1.0f;
    Uint16 low_freq = (Uint16)(strong * 65535.0f);
    Uint16 high_freq = (Uint16)(weak * 65535.0f);
    Uint32 dur_ms = (Uint32)(duration * 1000.0f);
    if (dur_ms < 1) dur_ms = 1;
    SDL_RumbleGamepad(pad, low_freq, high_freq, dur_ms);
#endif
}

void zen_vibrate(float duration) {
#ifdef __EMSCRIPTEN__
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

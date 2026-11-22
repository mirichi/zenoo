// ==========================================
// ウィンドウ & フレーム制御 & 時間 (SDL3 バックエンド)
// ==========================================
// 1フレームの流れ (どの方式でも同じ):
//
//   zen_begin_frame()  … OSイベント取得 → dt計算 → 入力/振動の更新 → 画面描画の準備
//   (ユーザー処理)      … zen_clear() / 描画 / 入力参照
//   zen_end_frame()    … SwapWindow → ワンショット入力クリア → 目標FPSまで待機
//
// zen_update() と zen_run_loop() はこの2つを並べて呼ぶだけの薄いラッパー。
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#ifndef WM_DPICHANGED
#define WM_DPICHANGED 0x02E0
#endif
#ifndef WM_GETDPISCALEDSIZE
#define WM_GETDPISCALEDSIZE 0x02E4
#endif
// NVIDIA Optimus: GeForce dGPU を優先して有効化
__declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
#endif

#define ZEN_DEFAULT_DT (1.0 / 60.0)

// ウィンドウ状態
static SDL_Window*   s_window = NULL;
static SDL_GLContext s_gl_context = NULL;
static int           s_should_close = 0;
static char          s_window_title[256] = "Zenoo";
static ZenViewport   s_viewport = { 1280, 720, 1280, 720, 0, 0, 1280, 720, 1.0f };
static int           s_initial_base_w = 1280;
static int           s_initial_base_h = 720;
static int           s_scale_mode = ZEN_SCALE_FIT;
static float         s_active_dpi_scale = 0.0f;
static int           s_is_fullscreen = 0;
static int           s_saved_win_x = 100, s_saved_win_y = 100;
static int           s_saved_win_w = 960, s_saved_win_h = 540;
static SDL_Cursor*   s_cursors[10] = { NULL };
static char*         s_clipboard_buf = NULL;

static int           s_window_visible = 0;
static int           s_in_auto_resize = 0;
static float         s_user_window_scale = 1.0f;
static int           s_follow_dpi_scale = 1;
static int           s_has_manual_size = 0;
static float         s_manual_logical_w = 0.0f;
static float         s_manual_logical_h = 0.0f;
static int           s_event_watch_installed = 0;
static SDL_DisplayID s_last_synced_display_id = 0;
static float         s_last_synced_dpi = 0.0f;
#ifdef _WIN32
static HWND          s_hooked_hwnd = NULL;
static WNDPROC       s_prev_wndproc = NULL;
#endif

// フレーム & 時間状態
static int           s_frame_open = 0;          // begin_frame 済みで end_frame 前なら 1
static int           s_first_frame = 1;         // 初回フレームは dt を既定値にする
static Uint64        s_frame_start_ns = 0;      // 現フレームの begin_frame 時刻 (ns)
static float         s_delta_time = (float)ZEN_DEFAULT_DT;
static int           s_target_fps = 60;         // デフォルト60fpsに固定
static int           s_vsync = 0;               // デフォルト 0 (ソフトウェア精密制御)
static int           s_window_msaa_samples = 0; // ウィンドウ直接描画のMSAA (デフォルト 0: 完全無効・最高速)
static int           s_created_msaa_samples = 0;

// ライブ更新 (移動・リサイズドラッグ中のフレーム継続) 状態
static int           s_live_resize = 1;
static int           s_in_live_resize_tick = 0;
static zen_frame_fn  s_step_callback = NULL;

static int  begin_frame_internal(int poll_events);
static void end_frame_internal(int post_wait);

// ------------------------------------------
// 内部: ビューポート計算
// ------------------------------------------
static void update_viewport(int fb_w, int fb_h) {
    ZenViewport* vp = &s_viewport;
    if (fb_w <= 0) fb_w = 1;
    if (fb_h <= 0) fb_h = 1;
    vp->fb_w = fb_w;
    vp->fb_h = fb_h;

    if (s_scale_mode == ZEN_SCALE_RESIZE) {
        if (s_active_dpi_scale <= 0.0f) {
            s_active_dpi_scale = zen_get_dpi_scale();
        }
        float dpi = (s_active_dpi_scale > 0.0001f) ? s_active_dpi_scale : 1.0f;
        int base_w = (int)((float)fb_w / dpi);
        int base_h = (int)((float)fb_h / dpi);
        vp->base_w = (base_w < 1) ? 1 : base_w;
        vp->base_h = (base_h < 1) ? 1 : base_h;
        vp->scale = dpi;
        vp->w = (int)((float)vp->base_w * dpi + 0.5f);
        vp->h = (int)((float)vp->base_h * dpi + 0.5f);
        vp->x = 0;
        vp->y = fb_h - vp->h;
        return;
    }

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

SDL_Window* zen__window(void) {
    return s_window;
}

const ZenViewport* zen__viewport(void) {
    return &s_viewport;
}

// ------------------------------------------
// DPI スケール & ウィンドウサイズ自動計算
// ------------------------------------------
static SDL_DisplayID get_current_display_id(void) {
    SDL_DisplayID id = 0;
    if (s_window) {
        id = SDL_GetDisplayForWindow(s_window);
    }
    if (id == 0) {
        id = SDL_GetPrimaryDisplay();
    }
    return id;
}

static float get_display_dpi_scale(SDL_DisplayID display_id, float override_scale) {
#ifdef __EMSCRIPTEN__
    (void)display_id;
    (void)override_scale;
    // Web版ではCSSピクセル単位でブラウザが自動スケーリングするため、常に 1.0 とする
    return 1.0f;
#else
    if (override_scale > 0.0f) return override_scale;
    if (display_id != 0) {
        SDL_DisplayID win_disp = s_window ? SDL_GetDisplayForWindow(s_window) : 0;
        if (s_window && display_id == win_disp) {
            float ws = SDL_GetWindowDisplayScale(s_window);
            if (ws > 0.0f) return ws;
        }
        float ds = SDL_GetDisplayContentScale(display_id);
        if (ds > 0.0f) return ds;
    }
    if (s_window) {
        float ws = SDL_GetWindowDisplayScale(s_window);
        if (ws > 0.0f) return ws;
    }
    return 1.0f;
#endif
}

// 指定ディスプレイのDPIスケール・設定倍率・ワークエリアに合わせて最適なウィンドウ座標サイズを算出
static void compute_auto_window_size_for_display(SDL_DisplayID display_id, float override_scale, float user_scale, int base_w, int base_h, int* out_w, int* out_h) {
    if (display_id == 0) display_id = get_current_display_id();
    float dpi_scale = get_display_dpi_scale(display_id, override_scale);
    float pixel_density = s_window ? SDL_GetWindowPixelDensity(s_window) : 1.0f;
    if (pixel_density <= 0.0f) pixel_density = 1.0f;
    float u_scale = (user_scale > 0.0f) ? user_scale : 1.0f;

    float ref_w = (s_has_manual_size && s_manual_logical_w > 0.0f) ? s_manual_logical_w : ((float)base_w * u_scale);
    float ref_h = (s_has_manual_size && s_manual_logical_h > 0.0f) ? s_manual_logical_h : ((float)base_h * u_scale);

    // Windows/X11 では pixel_density=1.0 のため dpi_scale 倍、macOS/Wayland では論理座標系のため自動相殺
    float scale = dpi_scale / pixel_density;

    int target_w = (int)(ref_w * scale + 0.5f);
    int target_h = (int)(ref_h * scale + 0.5f);

#ifndef __EMSCRIPTEN__
    SDL_Rect usable;
    if (display_id != 0 && SDL_GetDisplayUsableBounds(display_id, &usable) && usable.w > 0 && usable.h > 0) {
        int top = 0, left = 0, bottom = 0, right = 0;
        if (s_window) {
            SDL_GetWindowBordersSize(s_window, &top, &left, &bottom, &right);
        }
        int pad_w = (left + right > 0) ? (left + right + 12) : 16;
        int pad_h = (top + bottom > 0) ? (top + bottom + 12) : 44;
        int max_w = usable.w - pad_w;
        int max_h = usable.h - pad_h;
        if (max_w > 0 && max_h > 0 && target_w > 0 && target_h > 0 && (target_w > max_w || target_h > max_h)) {
            float fit_x = (float)max_w / (float)target_w;
            float fit_y = (float)max_h / (float)target_h;
            float fit = (fit_x < fit_y) ? fit_x : fit_y;
            target_w = (int)((float)target_w * fit + 0.5f);
            target_h = (int)((float)target_h * fit + 0.5f);
            if (target_w < 1) target_w = 1;
            if (target_h < 1) target_h = 1;
        }
    }
#endif

    *out_w = (target_w > 0) ? target_w : base_w;
    *out_h = (target_h > 0) ? target_h : base_h;
}

static void compute_auto_window_size(int base_w, int base_h, int* out_w, int* out_h) {
    compute_auto_window_size_for_display(get_current_display_id(), 0.0f, s_user_window_scale, base_w, base_h, out_w, out_h);
}

static void get_reference_base_size(int* out_w, int* out_h) {
    if (s_scale_mode == ZEN_SCALE_RESIZE && s_initial_base_w > 0 && s_initial_base_h > 0) {
        *out_w = s_initial_base_w;
        *out_h = s_initial_base_h;
    } else {
        *out_w = s_viewport.base_w;
        *out_h = s_viewport.base_h;
    }
}

static void clamp_window_to_display_usable_bounds(SDL_Window* window, SDL_DisplayID display_id, int win_w, int win_h) {
#ifdef __EMSCRIPTEN__
    (void)window; (void)display_id; (void)win_w; (void)win_h;
#else
    if (!window) return;
    if (display_id == 0) display_id = SDL_GetDisplayForWindow(window);
    SDL_Rect usable;
    if (display_id == 0 || !SDL_GetDisplayUsableBounds(display_id, &usable) || usable.w <= 0 || usable.h <= 0) return;

    int top = 0, left = 0, bottom = 0, right = 0;
    SDL_GetWindowBordersSize(window, &top, &left, &bottom, &right);
    if (top <= 0) top = 32;
    if (left <= 0) left = 8;
    if (right <= 0) right = 8;
    if (bottom <= 0) bottom = 8;

    int wx = 0, wy = 0;
    SDL_GetWindowPosition(window, &wx, &wy);
    int new_x = wx;
    int new_y = wy;

    if (new_x + win_w + right > usable.x + usable.w) {
        new_x = usable.x + usable.w - win_w - right;
    }
    if (new_y + win_h + bottom > usable.y + usable.h) {
        new_y = usable.y + usable.h - win_h - bottom;
    }
    if (new_x < usable.x + left) {
        new_x = usable.x + left;
    }
    if (new_y < usable.y + top) {
        new_y = usable.y + top;
    }

    if (new_x != wx || new_y != wy) {
        SDL_SetWindowPosition(window, new_x, new_y);
    }
    s_saved_win_x = new_x;
    s_saved_win_y = new_y;
#endif
}

static void center_window_on_display(SDL_Window* window, int win_w, int win_h) {
#ifdef __EMSCRIPTEN__
    (void)window; (void)win_w; (void)win_h;
#else
    if (!window) return;
    SDL_DisplayID display_id = get_current_display_id();
    SDL_Rect usable;
    if (display_id != 0 && SDL_GetDisplayUsableBounds(display_id, &usable) && usable.w > 0 && usable.h > 0) {
        int cx = usable.x + (usable.w - win_w) / 2;
        int cy = usable.y + (usable.h - win_h) / 2;
        if (cx < usable.x) cx = usable.x;
        if (cy < usable.y + 28) cy = usable.y + 28;
        SDL_SetWindowPosition(window, cx, cy);
        s_saved_win_x = cx;
        s_saved_win_y = cy;
    } else if (display_id != 0) {
        SDL_SetWindowPosition(window, (int)SDL_WINDOWPOS_CENTERED_DISPLAY(display_id), (int)SDL_WINDOWPOS_CENTERED_DISPLAY(display_id));
    }
#endif
}

#ifdef _WIN32
typedef BOOL (WINAPI *PFN_AdjustWindowRectExForDpi)(LPRECT, DWORD, BOOL, DWORD, UINT);

static void adjust_rect_for_dpi(HWND hwnd, RECT* rc, UINT dpi) {
    static PFN_AdjustWindowRectExForDpi s_pfn_adjust_dpi = NULL;
    static int s_checked = 0;
    if (!s_checked) {
        HMODULE user32 = GetModuleHandleW(L"user32.dll");
        if (user32) {
            s_pfn_adjust_dpi = (PFN_AdjustWindowRectExForDpi)(void*)GetProcAddress(user32, "AdjustWindowRectExForDpi");
        }
        s_checked = 1;
    }
    DWORD style = (DWORD)GetWindowLongPtrW(hwnd, GWL_STYLE);
    DWORD ex_style = (DWORD)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    BOOL has_menu = (GetMenu(hwnd) != NULL);
    if (s_pfn_adjust_dpi && dpi > 0) {
        s_pfn_adjust_dpi(rc, style, has_menu, ex_style, dpi);
    } else {
        AdjustWindowRectEx(rc, style, has_menu, ex_style);
    }
}

static SDL_DisplayID find_display_for_dpi(int dpi) {
    float target_scale = (dpi > 0) ? ((float)dpi / 96.0f) : 1.0f;
    float gx = 0.0f, gy = 0.0f;
    SDL_GetGlobalMouseState(&gx, &gy);
    SDL_Point pt = { (int)gx, (int)gy };
    SDL_DisplayID cursor_disp = SDL_GetDisplayForPoint(&pt);
    if (cursor_disp != 0) {
        float cs = SDL_GetDisplayContentScale(cursor_disp);
        float diff = cs - target_scale;
        if (diff < 0.0f) diff = -diff;
        if (cs > 0.0f && diff < 0.05f) {
            return cursor_disp;
        }
    }
    int count = 0;
    SDL_DisplayID* displays = SDL_GetDisplays(&count);
    SDL_DisplayID best = cursor_disp ? cursor_disp : get_current_display_id();
    float best_diff = 1e9f;
    if (displays) {
        for (int i = 0; i < count; i++) {
            float ds = SDL_GetDisplayContentScale(displays[i]);
            float diff = ds - target_scale;
            if (diff < 0.0f) diff = -diff;
            if (diff < best_diff) {
                best_diff = diff;
                best = displays[i];
            }
        }
        SDL_free(displays);
    }
    return best;
}

static void uninstall_win32_dpi_hook(void) {
    if (s_hooked_hwnd && s_prev_wndproc) {
        if ((WNDPROC)GetWindowLongPtrW(s_hooked_hwnd, GWLP_WNDPROC) == s_prev_wndproc) {
            // 既に差し替えられていないため何もしない
        } else {
            SetWindowLongPtrW(s_hooked_hwnd, GWLP_WNDPROC, (LONG_PTR)s_prev_wndproc);
        }
    }
    s_hooked_hwnd = NULL;
    s_prev_wndproc = NULL;
}

static LRESULT CALLBACK zen_win32_wndproc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    WNDPROC prev = s_prev_wndproc;

    if (msg == WM_NCDESTROY) {
        uninstall_win32_dpi_hook();
        return prev ? CallWindowProcW(prev, hwnd, msg, wParam, lParam) : DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    if (s_window && !s_is_fullscreen && s_follow_dpi_scale &&
        s_viewport.base_w > 0 && s_viewport.base_h > 0) {
        if (msg == WM_GETDPISCALEDSIZE) {
            int next_dpi = (int)wParam;
            SIZE* size_in_out = (SIZE*)lParam;
            if (size_in_out && next_dpi > 0) {
                float next_scale = (float)next_dpi / 96.0f;
                SDL_DisplayID disp = find_display_for_dpi(next_dpi);
                int ref_w = s_viewport.base_w, ref_h = s_viewport.base_h;
                get_reference_base_size(&ref_w, &ref_h);
                int client_w = ref_w;
                int client_h = ref_h;
                compute_auto_window_size_for_display(disp, next_scale, s_user_window_scale, ref_w, ref_h, &client_w, &client_h);

                RECT rc = { 0, 0, client_w, client_h };
                adjust_rect_for_dpi(hwnd, &rc, (UINT)next_dpi);
                size_in_out->cx = rc.right - rc.left;
                size_in_out->cy = rc.bottom - rc.top;
                return TRUE;
            }
        } else if (msg == WM_DPICHANGED) {
            if (s_in_auto_resize) {
                return 0;
            }
            int new_dpi = HIWORD(wParam);
            const RECT* suggested = (const RECT*)lParam;
            if (suggested && new_dpi > 0) {
                float new_scale = (float)new_dpi / 96.0f;
                s_active_dpi_scale = new_scale;
                s_last_synced_dpi = new_scale;

                s_in_auto_resize = 1;
                SetWindowPos(hwnd,
                             NULL,
                             suggested->left,
                             suggested->top,
                             suggested->right - suggested->left,
                             suggested->bottom - suggested->top,
                             SWP_NOZORDER | SWP_NOACTIVATE);
                s_in_auto_resize = 0;

                SDL_DisplayID disp = SDL_GetDisplayForWindow(s_window);
                if (disp != 0) {
                    s_last_synced_display_id = disp;
                }
                int wx = 0, wy = 0, ww = 0, wh = 0;
                SDL_GetWindowPosition(s_window, &wx, &wy);
                SDL_GetWindowSize(s_window, &ww, &wh);
                s_saved_win_x = wx;
                s_saved_win_y = wy;
                s_saved_win_w = ww;
                s_saved_win_h = wh;

                int fb_w = 0, fb_h = 0;
                SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
                if (fb_w > 0 && fb_h > 0) {
                    update_viewport(fb_w, fb_h);
                }
                return 0;
            }
        }
    }

    return prev ? CallWindowProcW(prev, hwnd, msg, wParam, lParam) : DefWindowProcW(hwnd, msg, wParam, lParam);
}

static void install_win32_dpi_hook(SDL_Window* window) {
    uninstall_win32_dpi_hook();
    if (!window) return;
    SDL_PropertiesID props = SDL_GetWindowProperties(window);
    HWND hwnd = (HWND)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
    if (!hwnd) return;
    s_hooked_hwnd = hwnd;
    s_prev_wndproc = (WNDPROC)SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)zen_win32_wndproc);
}
#endif

// ------------------------------------------
// ライブ更新 & イベント監視 (SDL_AddEventWatch)
// ------------------------------------------
static void run_live_resize_frame(void) {
    if (!s_window || s_in_live_resize_tick || s_frame_open) return;
    if (!s_live_resize || !s_step_callback) return;

    s_in_live_resize_tick = 1;
    if (begin_frame_internal(0)) {
        s_step_callback();
        end_frame_internal(0);
    }
    s_in_live_resize_tick = 0;
}

static void sync_window_to_display(void) {
#ifndef __EMSCRIPTEN__
    if (!s_window || s_in_auto_resize) return;

    SDL_DisplayID disp = SDL_GetDisplayForWindow(s_window);
    if (disp == 0) {
        disp = get_current_display_id();
    }

    float new_dpi = get_display_dpi_scale(disp, 0.0f);
    if (new_dpi > 0.0f) {
        s_active_dpi_scale = new_dpi;
    }

    if (s_is_fullscreen || !s_window_visible || !s_follow_dpi_scale ||
        s_viewport.base_w <= 0 || s_viewport.base_h <= 0) {
        s_last_synced_display_id = disp;
        s_last_synced_dpi = new_dpi;
        return;
    }

    s_in_auto_resize = 1;
    int old_w = 0, old_h = 0;
    SDL_GetWindowSize(s_window, &old_w, &old_h);

    int ref_w = s_viewport.base_w, ref_h = s_viewport.base_h;
    get_reference_base_size(&ref_w, &ref_h);
    int new_w = old_w, new_h = old_h;
    compute_auto_window_size_for_display(disp, new_dpi, s_user_window_scale, ref_w, ref_h, &new_w, &new_h);

    if (abs(new_w - old_w) > 2 || abs(new_h - old_h) > 2) {
        SDL_SetWindowSize(s_window, new_w, new_h);
        clamp_window_to_display_usable_bounds(s_window, disp, new_w, new_h);
        s_saved_win_w = new_w;
        s_saved_win_h = new_h;
    }

    int fb_w = new_w, fb_h = new_h;
    SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);
    s_last_synced_display_id = disp;
    s_last_synced_dpi = new_dpi;
    s_in_auto_resize = 0;
#endif
}

static void try_live_resize_redraw(void) {
    if (!s_window || !s_window_visible || s_in_auto_resize) return;
    if (!s_live_resize || !s_step_callback || s_frame_open || s_in_live_resize_tick) return;

    if (s_target_fps > 0 && s_frame_start_ns > 0) {
        Uint64 target_ns = (Uint64)(1000000000ULL / (Uint64)s_target_fps);
        Uint64 now_ns = SDL_GetTicksNS();
        if (now_ns > s_frame_start_ns && (now_ns - s_frame_start_ns) < target_ns) {
            return;
        }
    }

    int fb_w = 0, fb_h = 0;
    SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
    if (fb_w > 0 && fb_h > 0) {
        update_viewport(fb_w, fb_h);
        run_live_resize_frame();
    }
}

static bool SDLCALL zen_sdl_event_watch(void* userdata, SDL_Event* event) {
    (void)userdata;
    if (!s_window || !event) return true;

    if (event->type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) {
        if (event->window.data1 > 0 && event->window.data2 > 0) {
            update_viewport(event->window.data1, event->window.data2);
            try_live_resize_redraw();
        }
    } else if (event->type == SDL_EVENT_WINDOW_RESIZED) {
        if (!s_in_auto_resize && s_window_visible && !s_is_fullscreen &&
            event->window.data1 > 0 && event->window.data2 > 0 &&
            !(SDL_GetWindowFlags(s_window) & (SDL_WINDOW_FULLSCREEN | SDL_WINDOW_MAXIMIZED | SDL_WINDOW_MINIMIZED))) {
            s_saved_win_w = event->window.data1;
            s_saved_win_h = event->window.data2;
            if (s_follow_dpi_scale) {
                float cur_dpi = get_display_dpi_scale(SDL_GetDisplayForWindow(s_window), 0.0f);
                float pixel_density = SDL_GetWindowPixelDensity(s_window);
                if (pixel_density <= 0.0f) pixel_density = 1.0f;
                float scale = cur_dpi / pixel_density;
                if (scale <= 0.0f) scale = 1.0f;
                s_manual_logical_w = (float)event->window.data1 / scale;
                s_manual_logical_h = (float)event->window.data2 / scale;
                s_has_manual_size = 1;
            }
        }
    } else if (event->type == SDL_EVENT_WINDOW_EXPOSED && event->window.data1 == 1) {
        // SDL3 のライブ・リサイズ通知 (data1 == 1): 目標FPSでペーシングしつつ再描画
        try_live_resize_redraw();
    }
    return true;
}

static void handle_window_event(const SDL_Event* ev) {
    switch (ev->type) {
    case SDL_EVENT_QUIT:
    case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
        s_should_close = 1;
        break;
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
        if (ev->window.data1 > 0 && ev->window.data2 > 0) {
            update_viewport(ev->window.data1, ev->window.data2);
        }
        break;
    case SDL_EVENT_WINDOW_RESIZED:
        // イベントウォッチ側で s_in_auto_resize を同期判定して更新済み
        break;
    case SDL_EVENT_WINDOW_MOVED:
        if (!s_is_fullscreen) {
            s_saved_win_x = ev->window.data1;
            s_saved_win_y = ev->window.data2;
        }
        break;
    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
    case SDL_EVENT_WINDOW_DISPLAY_CHANGED:
        // イベントウォッチ側で処理済み。キューに残った古いディスプレイIDで誤移動しないようここでは再実行しない
        break;
    case SDL_EVENT_WINDOW_ENTER_FULLSCREEN:
        s_is_fullscreen = 1;
        break;
    case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:
        s_is_fullscreen = 0;
        break;
    default:
        break;
    }
}

static void setup_gl_attributes(int msaa_samples, int share_context) {
#ifdef __EMSCRIPTEN__
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
#else
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
#endif
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, share_context ? 1 : 0);
    if (msaa_samples > 0) {
        SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
        SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, msaa_samples);
    } else {
        SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
        SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
    }
}

// ------------------------------------------
// 初期化 & 終了
// ------------------------------------------
static int init_window(int width, int height, const char* title, int fullscreen, int win_width, int win_height, int visible) {
    if (s_window) {
        s_initial_base_w = width;
        s_initial_base_h = height;
        s_viewport.base_w = width;
        s_viewport.base_h = height;
        s_active_dpi_scale = 0.0f;
        s_should_close = 0;

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
            strncpy(s_window_title, title, sizeof(s_window_title) - 1);
            s_window_title[sizeof(s_window_title) - 1] = '\0';
        }

#ifndef __EMSCRIPTEN__
        if (s_created_msaa_samples != s_window_msaa_samples) {
            setup_gl_attributes(s_window_msaa_samples, 1);
            SDL_WindowFlags flags = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIDDEN;
#ifndef __EMSCRIPTEN__
            flags |= SDL_WINDOW_HIGH_PIXEL_DENSITY;
#endif
            if (fullscreen) flags |= SDL_WINDOW_FULLSCREEN;
            SDL_Window* new_win = SDL_CreateWindow(s_window_title, create_w, create_h, flags);
            if (new_win) {
                SDL_GLContext new_ctx = SDL_GL_CreateContext(new_win);
                if (new_ctx) {
                    SDL_Window* old_win = s_window;
                    SDL_GLContext old_ctx = s_gl_context;
                    s_window = new_win;
                    s_gl_context = new_ctx;
                    s_created_msaa_samples = s_window_msaa_samples;
                    s_window_visible = 0;
                    SDL_GL_MakeCurrent(s_window, s_gl_context);
                    SDL_GL_SetSwapInterval(s_vsync ? 1 : 0);
                    zen__input_init(s_window);
#ifdef _WIN32
                    install_win32_dpi_hook(s_window);
#endif
                    zen__gfx_on_context_recreated();
                    SDL_GL_DestroyContext(old_ctx);
                    SDL_DestroyWindow(old_win);
                } else {
                    SDL_DestroyWindow(new_win);
                }
            }
        } else if (title && strlen(title) > 0) {
            SDL_SetWindowTitle(s_window, s_window_title);
        }
#else
        if (title && strlen(title) > 0) {
            SDL_SetWindowTitle(s_window, s_window_title);
        }
#endif

        if (fullscreen) {
            SDL_SetWindowFullscreenMode(s_window, NULL);
            SDL_SetWindowFullscreen(s_window, true);
            s_is_fullscreen = 1;
        } else {
            if (s_is_fullscreen) {
                SDL_SetWindowFullscreen(s_window, false);
                s_is_fullscreen = 0;
            }
            s_in_auto_resize = 1;
            SDL_SetWindowSize(s_window, create_w, create_h);
            s_in_auto_resize = 0;
            s_saved_win_w = create_w;
            s_saved_win_h = create_h;
        }

        int fb_w = create_w, fb_h = create_h;
        SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
        update_viewport(fb_w, fb_h);

        if (visible && !s_window_visible) {
            if (!fullscreen) {
                center_window_on_display(s_window, create_w, create_h);
                SDL_DisplayID disp = get_current_display_id();
                s_active_dpi_scale = get_display_dpi_scale(disp, 0.0f);
                s_last_synced_display_id = disp;
                s_last_synced_dpi = s_active_dpi_scale;
                SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
                update_viewport(fb_w, fb_h);
            }
            SDL_ShowWindow(s_window);
            SDL_RaiseWindow(s_window);
            s_window_visible = 1;
        }
        return 1;
    }

#if defined(__linux__) && !defined(__EMSCRIPTEN__)
    // WSL2/Linux環境でGPUハードウェアアクセラレーション(D3D12)を自動有効化
    setenv("GALLIUM_DRIVER", "d3d12", 0);
    // Linux/WSLg環境では、X11バックエンドを優先 (ウィンドウ座標制御等の互換性確保)
    SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "x11,wayland");
#endif

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD)) {
        fprintf(stderr, "[Zenoo] Failed to initialize SDL3: %s\n", SDL_GetError());
        return 0;
    }

    setup_gl_attributes(s_window_msaa_samples, 0);
    s_created_msaa_samples = s_window_msaa_samples;

    s_initial_base_w = width;
    s_initial_base_h = height;
    s_viewport.base_w = width;
    s_viewport.base_h = height;
    s_active_dpi_scale = 0.0f;
    s_should_close = 0;

    int create_w = win_width;
    int create_h = win_height;
    if (fullscreen) {
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

    SDL_WindowFlags win_flags = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE;
#ifndef __EMSCRIPTEN__
    win_flags |= SDL_WINDOW_HIGH_PIXEL_DENSITY;
#endif
    if (!visible) {
        win_flags |= SDL_WINDOW_HIDDEN;
    }
    if (fullscreen) {
        win_flags |= SDL_WINDOW_FULLSCREEN;
    }

    s_window = SDL_CreateWindow(title ? title : "Zenoo", create_w, create_h, win_flags);
    if (!s_window && s_window_msaa_samples > 0) {
        setup_gl_attributes(0, 0);
        s_created_msaa_samples = 0;
        s_window = SDL_CreateWindow(title ? title : "Zenoo", create_w, create_h, win_flags);
    }
    if (!s_window) {
        fprintf(stderr, "[Zenoo] Failed to create SDL3 window: %s\n", SDL_GetError());
        SDL_Quit();
        return 0;
    }

#ifdef __EMSCRIPTEN__
    SDL_SetWindowSize(s_window, create_w, create_h);
#endif

    s_gl_context = SDL_GL_CreateContext(s_window);
    if (!s_gl_context) {
        fprintf(stderr, "[Zenoo] Failed to create OpenGL context: %s\n", SDL_GetError());
        SDL_DestroyWindow(s_window);
        s_window = NULL;
        SDL_Quit();
        return 0;
    }
    SDL_GL_MakeCurrent(s_window, s_gl_context);
    SDL_GL_SetSwapInterval(s_vsync ? 1 : 0);

    if (title && strlen(title) > 0) {
        strncpy(s_window_title, title, sizeof(s_window_title) - 1);
        s_window_title[sizeof(s_window_title) - 1] = '\0';
    }

    if (!fullscreen) {
        s_saved_win_w = create_w;
        s_saved_win_h = create_h;
    }

    int fb_w = create_w, fb_h = create_h;
    SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);

    if (visible) {
        if (!fullscreen) {
            center_window_on_display(s_window, create_w, create_h);
            SDL_DisplayID disp = get_current_display_id();
            s_active_dpi_scale = get_display_dpi_scale(disp, 0.0f);
            s_last_synced_display_id = disp;
            s_last_synced_dpi = s_active_dpi_scale;
            SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
            update_viewport(fb_w, fb_h);
        }
        SDL_ShowWindow(s_window);
        SDL_RaiseWindow(s_window);
        s_window_visible = 1;
    } else {
        s_window_visible = 0;
    }

    zen__input_init(s_window);
#ifdef _WIN32
    install_win32_dpi_hook(s_window);
#endif
    if (!s_event_watch_installed) {
        SDL_AddEventWatch(zen_sdl_event_watch, NULL);
        s_event_watch_installed = 1;
    }

#ifndef __EMSCRIPTEN__
    // GLAD のロード
    if (!gladLoadGLLoader((GLADloadproc)SDL_GL_GetProcAddress)) {
        fprintf(stderr, "[Zenoo] Failed to load OpenGL with GLAD\n");
        SDL_GL_DestroyContext(s_gl_context);
        s_gl_context = NULL;
        SDL_DestroyWindow(s_window);
        s_window = NULL;
        SDL_Quit();
        return 0;
    }
#endif

    const GLubyte* renderer = glGetString(GL_RENDERER);
    const GLubyte* version = glGetString(GL_VERSION);
    printf("[Zenoo v%s] Initialized successfully (%s, SDL3).\n", ZENOO_VERSION, fullscreen ? "Fullscreen Mode" : "Windowed Mode");
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
    return init_window(1280, 720, "Zenoo", 0, 1280, 720, 0);
}

int zen_init(int width, int height, const char* title) {
    s_is_fullscreen = 0;
    s_user_window_scale = 1.0f;
    s_follow_dpi_scale = 1;
    s_has_manual_size = 0;
    s_manual_logical_w = 0.0f;
    s_manual_logical_h = 0.0f;
    return init_window(width, height, title, 0, 0, 0, 1);
}

int zen_init_scaled_ex(int base_width, int base_height, const char* title, int window_width, int window_height, float scale) {
    s_is_fullscreen = 0;
    s_has_manual_size = 0;
    s_manual_logical_w = 0.0f;
    s_manual_logical_h = 0.0f;
    if (window_width > 0 && window_height > 0) {
        s_user_window_scale = 1.0f;
        s_follow_dpi_scale = 0;
    } else {
        s_user_window_scale = (scale > 0.0f) ? scale : 1.0f;
        s_follow_dpi_scale = 1;
    }
    return init_window(base_width, base_height, title, 0, window_width, window_height, 1);
}

int zen_init_scaled(int base_width, int base_height, const char* title, int window_width, int window_height) {
    return zen_init_scaled_ex(base_width, base_height, title, window_width, window_height, 1.0f);
}

int zen_init_fullscreen(const char* title) {
    if (!zen_ensure_context()) return 0;
    SDL_DisplayID disp = get_current_display_id();
    const SDL_DisplayMode* mode = disp ? SDL_GetCurrentDisplayMode(disp) : NULL;
    int w = mode ? mode->w : 1920;
    int h = mode ? mode->h : 1080;
    s_is_fullscreen = 1;
    return init_window(w, h, title, 1, w, h, 1);
}

void zen_shutdown(void) {
    zen_audio_shutdown();
    zen__vibration_shutdown();
    zen__input_shutdown();
    zen__gfx_shutdown();
    if (s_event_watch_installed) {
        SDL_RemoveEventWatch(zen_sdl_event_watch, NULL);
        s_event_watch_installed = 0;
    }
    for (int i = 0; i < 10; i++) {
        if (s_cursors[i]) {
            SDL_DestroyCursor(s_cursors[i]);
            s_cursors[i] = NULL;
        }
    }
    if (s_gl_context) {
        SDL_GL_DestroyContext(s_gl_context);
        s_gl_context = NULL;
    }
#ifdef _WIN32
    uninstall_win32_dpi_hook();
#endif
    if (s_window) {
        SDL_DestroyWindow(s_window);
        s_window = NULL;
    }
    if (s_clipboard_buf) {
        free(s_clipboard_buf);
        s_clipboard_buf = NULL;
    }
    SDL_Quit();
    s_frame_open = 0;
    s_window_visible = 0;
    s_created_msaa_samples = 0;
    s_in_auto_resize = 0;
    s_active_dpi_scale = 0.0f;
    s_should_close = 0;
    s_last_synced_display_id = 0;
    s_last_synced_dpi = 0.0f;
    s_has_manual_size = 0;
    s_manual_logical_w = 0.0f;
    s_manual_logical_h = 0.0f;
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
static void wait_for_target_fps(void) {
    if (s_target_fps <= 0) return;
    Uint64 target_ns = (Uint64)(1000000000ULL / (Uint64)s_target_fps);
    Uint64 now_ns = SDL_GetTicksNS();
    if (now_ns <= s_frame_start_ns) return;
    Uint64 elapsed_ns = now_ns - s_frame_start_ns;
    if (elapsed_ns < target_ns) {
        SDL_DelayPrecise(target_ns - elapsed_ns);
    }
}
#endif

static void poll_sdl_events(void) {
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        handle_window_event(&ev);
        zen__input_handle_event(&ev);
    }
}

static int begin_frame_internal(int poll_events) {
    if (!s_window) return 0;

    if (poll_events) {
        poll_sdl_events();
#ifndef __EMSCRIPTEN__
        if (!s_in_auto_resize && s_window_visible && !s_is_fullscreen && s_follow_dpi_scale) {
            if ((SDL_GetGlobalMouseState(NULL, NULL) & SDL_BUTTON_LMASK) == 0) {
                SDL_DisplayID cur_disp = SDL_GetDisplayForWindow(s_window);
                float cur_dpi = get_display_dpi_scale(cur_disp, 0.0f);
                float dpi_diff = cur_dpi - s_last_synced_dpi;
                if (dpi_diff < 0.0f) dpi_diff = -dpi_diff;
                if ((cur_disp != 0 && cur_disp != s_last_synced_display_id) || dpi_diff >= 0.001f) {
                    sync_window_to_display();
                }
            }
        }
#endif
    }

    // 時間更新 (dt を計算するのはここだけ)
    Uint64 now_ns = SDL_GetTicksNS();
    double dt = s_first_frame ? ZEN_DEFAULT_DT : ((double)(now_ns - s_frame_start_ns) * 1e-9);
    if (dt <= 0.0) dt = 0.000001;
#ifdef __EMSCRIPTEN__
    // 極端なラグ時（タブバックグラウンド移行等）のスパイラル防止
    if (dt > 0.2) dt = 0.2;
#endif
    s_delta_time = (float)dt;
    s_frame_start_ns = now_ns;
    s_first_frame = 0;

    // 入力 (ゲームパッド) と振動の更新
    zen__input_poll();
    zen__vibration_update(s_delta_time);

    // 終了判定
    if (s_should_close) return 0;

    // 画面描画の準備 (ビューポート更新 → 余白を黒で塗る → 描画状態の初期化)
    int fb_w = s_viewport.fb_w, fb_h = s_viewport.fb_h;
    SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);
    zen__gfx_begin_frame();

    s_frame_open = 1;
    return 1;
}

static void end_frame_internal(int post_wait) {
    if (!s_window || !s_frame_open) return;
    s_frame_open = 0;

    // 1. 画面へ表示
    SDL_GL_SwapWindow(s_window);

    // 2. このフレームで参照されたワンショット入力 (push/release/文字) をクリア
    zen__input_end_frame();

#ifndef __EMSCRIPTEN__
    if (post_wait) {
        // 3. SwapWindowの直後に即座にOSイベントをポーリング
        poll_sdl_events();

        // 4. 目標FPSまで精密待機 (Wasm は requestAnimationFrame 側で間引く)
        wait_for_target_fps();
    }
#else
    (void)post_wait;
#endif
}

int zen_begin_frame(void) {
    return begin_frame_internal(1);
}

void zen_end_frame(void) {
    end_frame_internal(1);
}

int zen_update(void) {
    zen_end_frame();          // 前フレームがあれば表示して待機
    return zen_begin_frame(); // 次フレームを開始
}

#ifdef __EMSCRIPTEN__
extern void __real_sp_fin_run_exit(void);
static int s_wasm_loop_active = 0;

void __wrap_sp_fin_run_exit(void) {
    /* Emscripten のメインループ起動後は main() 復帰時にランタイム終了扱いとせず、
       ウィンドウや画像・シェーダ等のファイナライザを即時発火させない */
    if (!s_wasm_loop_active) {
        __real_sp_fin_run_exit();
    }
}

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

    if (s_target_fps > 0) {
        s_wasm_accumulator += dt;
        double fixed_step = 1.0 / (double)s_target_fps;
        // requestAnimationFrame の 16.3ms 等の微少ジッターによるフレーム落ちを防止
        if (s_wasm_accumulator + 0.002 < fixed_step) return;
        while (s_wasm_accumulator >= fixed_step) {
            s_wasm_accumulator -= fixed_step;
        }
        if (s_wasm_accumulator < 0.0) s_wasm_accumulator = 0.0;
    } else {
        s_wasm_accumulator = 0.0;
    }

    if (!zen_begin_frame()) {
        emscripten_cancel_main_loop();
        if (s_wasm_loop_active) {
            s_wasm_loop_active = 0;
            __real_sp_fin_run_exit();
        }
        return;
    }
    if (s_frame_fn) s_frame_fn();
    zen_end_frame();
}

void zen_run_loop(zen_frame_fn fn) {
    s_frame_fn = fn;
    s_wasm_prev_time = emscripten_get_now() * 0.001;
    s_wasm_accumulator = 0.0;
    s_wasm_loop_active = 1;
    emscripten_set_main_loop(wasm_tick, 0, 0);
}
#else
void zen_run_loop(zen_frame_fn fn) {
    s_step_callback = fn;
    while (zen_begin_frame()) {
        if (fn) fn();
        zen_end_frame();
    }
    s_step_callback = NULL;
}
#endif

void zen_set_frame_callback(zen_frame_fn fn) {
    s_step_callback = fn;
}

void zen_set_live_resize(int enabled) {
    s_live_resize = enabled ? 1 : 0;
}

int zen_get_live_resize(void) {
    return s_live_resize;
}

int zen_is_resizing(void) {
    return s_in_live_resize_tick;
}

// ------------------------------------------
// 時間 & フレームレート
// ------------------------------------------
double zen_get_time(void) {
    return (double)SDL_GetTicksNS() * 1e-9;
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
    if (s_window && s_gl_context) {
        SDL_GL_SetSwapInterval(vsync ? 1 : 0);
    }
}

int zen__is_wsl_d3d12(void) {
#if defined(__linux__) && !defined(__EMSCRIPTEN__)
    static int s_checked = 0;
    static int s_is_d3d12 = 0;
    if (!s_checked) {
        if (getenv("WSL_DISTRO_NAME") != NULL || getenv("WSL_INTEROP") != NULL) {
            s_is_d3d12 = 1;
            s_checked = 1;
        } else if (s_window != NULL) {
            const char* r = (const char*)glGetString(GL_RENDERER);
            if (r && strstr(r, "D3D12") != NULL) {
                s_is_d3d12 = 1;
            }
            s_checked = 1;
        }
    }
    return s_is_d3d12;
#else
    return 0;
#endif
}

void zen_window_set_msaa_samples(int samples) {
    if (zen__is_wsl_d3d12()) {
        s_window_msaa_samples = 0;
        return;
    }
    s_window_msaa_samples = (samples < 0) ? 0 : samples;
}

int zen_window_get_msaa_samples(void) {
    return s_window_msaa_samples;
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
        SDL_GetWindowSize(s_window, width, height);
    } else {
        zen_get_screen_size(width, height);
    }
}

void zen_set_window_size(int width, int height) {
    if (s_window && width > 0 && height > 0) {
        s_follow_dpi_scale = 0;
        s_in_auto_resize = 1;
        SDL_SetWindowSize(s_window, width, height);
        s_in_auto_resize = 0;
        int fb_w = width, fb_h = height;
        SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
        update_viewport(fb_w, fb_h);
    }
}

void zen_set_scale_mode(int mode) {
    s_scale_mode = mode;
    if (s_scale_mode != ZEN_SCALE_RESIZE && s_initial_base_w > 0 && s_initial_base_h > 0) {
        s_viewport.base_w = s_initial_base_w;
        s_viewport.base_h = s_initial_base_h;
    }
    update_viewport(s_viewport.fb_w, s_viewport.fb_h);
}

int zen_get_scale_mode(void) {
    return s_scale_mode;
}

float zen_get_scale(void) {
    return s_viewport.scale;
}

float zen_get_dpi_scale(void) {
    return get_display_dpi_scale(get_current_display_id(), 0.0f);
}

void zen_set_window_scale(float scale) {
    if (scale <= 0.0f) return;
    s_user_window_scale = scale;
    s_follow_dpi_scale = 1;
    s_has_manual_size = 0;
    s_manual_logical_w = 0.0f;
    s_manual_logical_h = 0.0f;
    if (!s_window || s_is_fullscreen) return;
    if (s_viewport.base_w <= 0 || s_viewport.base_h <= 0) return;

#ifndef __EMSCRIPTEN__
    s_in_auto_resize = 1;
    SDL_DisplayID disp = get_current_display_id();
    int ref_w = s_viewport.base_w, ref_h = s_viewport.base_h;
    get_reference_base_size(&ref_w, &ref_h);
    int new_w = 0, new_h = 0;
    compute_auto_window_size_for_display(disp, 0.0f, s_user_window_scale, ref_w, ref_h, &new_w, &new_h);
    SDL_SetWindowSize(s_window, new_w, new_h);
    clamp_window_to_display_usable_bounds(s_window, disp, new_w, new_h);
    s_saved_win_w = new_w;
    s_saved_win_h = new_h;
    s_last_synced_display_id = disp;
    s_last_synced_dpi = get_display_dpi_scale(disp, 0.0f);
    int fb_w = new_w, fb_h = new_h;
    SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);
    s_in_auto_resize = 0;
#else
    float dpi = zen_get_dpi_scale();
    float total_scale = s_user_window_scale * dpi;
    int new_w = (int)((float)s_viewport.base_w * total_scale + 0.5f);
    int new_h = (int)((float)s_viewport.base_h * total_scale + 0.5f);
    if (new_w > 0 && new_h > 0) {
        SDL_SetWindowSize(s_window, new_w, new_h);
        int fb_w = new_w, fb_h = new_h;
        SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
        update_viewport(fb_w, fb_h);
    }
#endif
}

float zen_get_window_scale(void) {
    float dpi = zen_get_dpi_scale();
    if (dpi <= 0.0001f) dpi = 1.0f;
    return s_viewport.scale / dpi;
}

void zen_toggle_fullscreen(void) {
    if (!s_window) return;
    if (!s_is_fullscreen) {
        SDL_GetWindowPosition(s_window, &s_saved_win_x, &s_saved_win_y);
        SDL_GetWindowSize(s_window, &s_saved_win_w, &s_saved_win_h);
        SDL_SetWindowFullscreenMode(s_window, NULL);
        if (SDL_SetWindowFullscreen(s_window, true)) {
            s_is_fullscreen = 1;
        }
    } else {
        if (SDL_SetWindowFullscreen(s_window, false)) {
            s_is_fullscreen = 0;
            s_in_auto_resize = 1;
            SDL_SetWindowSize(s_window, s_saved_win_w, s_saved_win_h);
            SDL_SetWindowPosition(s_window, s_saved_win_x, s_saved_win_y);
            s_in_auto_resize = 0;
        }
    }
    int fb_w = s_viewport.fb_w, fb_h = s_viewport.fb_h;
    SDL_GetWindowSizeInPixels(s_window, &fb_w, &fb_h);
    update_viewport(fb_w, fb_h);
}

void zen_set_window_title(const char* title) {
    if (!title) return;
    strncpy(s_window_title, title, sizeof(s_window_title) - 1);
    s_window_title[sizeof(s_window_title) - 1] = '\0';
    if (s_window) {
        SDL_SetWindowTitle(s_window, s_window_title);
    }
}

const char* zen_get_window_title(void) {
    return s_window_title;
}

void zen_get_window_pos(int* x, int* y) {
    if (s_window) {
        SDL_GetWindowPosition(s_window, x, y);
    } else {
        if (x) *x = 0;
        if (y) *y = 0;
    }
}

void zen_set_window_pos(int x, int y) {
    if (s_window) {
        SDL_SetWindowPosition(s_window, x, y);
    }
}

int zen_is_window_focused(void) {
    if (!s_window) return 0;
    return (SDL_GetWindowFlags(s_window) & SDL_WINDOW_INPUT_FOCUS) ? 1 : 0;
}

int zen_is_window_minimized(void) {
    if (!s_window) return 0;
    return (SDL_GetWindowFlags(s_window) & SDL_WINDOW_MINIMIZED) ? 1 : 0;
}

int zen_is_window_maximized(void) {
    if (!s_window) return 0;
    return (SDL_GetWindowFlags(s_window) & SDL_WINDOW_MAXIMIZED) ? 1 : 0;
}

int zen_is_window_hovered(void) {
    if (!s_window) return 0;
    return (SDL_GetWindowFlags(s_window) & SDL_WINDOW_MOUSE_FOCUS) ? 1 : 0;
}

// ------------------------------------------
// マウスカーソル & クリップボード
// ------------------------------------------
void zen_window_show_cursor(int show) {
    if (!s_window) return;
    if (show) {
        SDL_ShowCursor();
    } else {
        SDL_HideCursor();
    }
}

void zen_window_set_cursor(int shape) {
    if (!s_window) return;
    if (shape < 0 || shape >= 10) shape = 0;
    if (!s_cursors[shape]) {
        static const SDL_SystemCursor sdl_shapes[10] = {
            SDL_SYSTEM_CURSOR_DEFAULT,      // 0: ARROW
            SDL_SYSTEM_CURSOR_TEXT,         // 1: IBEAM
            SDL_SYSTEM_CURSOR_CROSSHAIR,    // 2: CROSSHAIR
            SDL_SYSTEM_CURSOR_POINTER,      // 3: HAND
            SDL_SYSTEM_CURSOR_EW_RESIZE,    // 4: HRESIZE
            SDL_SYSTEM_CURSOR_NS_RESIZE,    // 5: VRESIZE
            SDL_SYSTEM_CURSOR_NWSE_RESIZE,  // 6: RESIZE_NWSE
            SDL_SYSTEM_CURSOR_NESW_RESIZE,  // 7: RESIZE_NESW
            SDL_SYSTEM_CURSOR_MOVE,         // 8: RESIZE_ALL
            SDL_SYSTEM_CURSOR_NOT_ALLOWED   // 9: NOT_ALLOWED
        };
        s_cursors[shape] = SDL_CreateSystemCursor(sdl_shapes[shape]);
    }
    if (s_cursors[shape]) {
        SDL_SetCursor(s_cursors[shape]);
    }
}

const char* zen_window_get_clipboard_string(void) {
#ifdef __EMSCRIPTEN__
    return s_clipboard_buf ? s_clipboard_buf : "";
#else
    if (!s_window) return "";
    char* text = SDL_GetClipboardText();
    if (!text) return "";
    if (s_clipboard_buf) {
        free(s_clipboard_buf);
        s_clipboard_buf = NULL;
    }
    s_clipboard_buf = strdup(text);
    SDL_free(text);
    return s_clipboard_buf ? s_clipboard_buf : "";
#endif
}

void zen_window_set_clipboard_string(const char* text) {
    if (!text) return;
#ifdef __EMSCRIPTEN__
    if (s_clipboard_buf) {
        free(s_clipboard_buf);
        s_clipboard_buf = NULL;
    }
    s_clipboard_buf = strdup(text);

    EM_ASM({
        var str = UTF8ToString($0);
        function fallbackCopy(val) {
            try {
                var ta = document.createElement("textarea");
                ta.value = val;
                ta.style.position = "fixed";
                ta.style.left = "-9999px";
                ta.style.top = "0";
                ta.setAttribute("readonly", "");
                document.body.appendChild(ta);
                ta.focus();
                ta.select();
                document.execCommand("copy");
                document.body.removeChild(ta);
            } catch (e) {
                console.warn("[Zenoo] Clipboard fallback copy failed:", e);
            }
        }

        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(str).catch(function(err) {
                fallbackCopy(str);
            });
        } else {
            fallbackCopy(str);
        }
    }, text);
#else
    if (!s_window) return;
    SDL_SetClipboardText(text);
#endif
}

// ------------------------------------------
// ブラウザ / Web 連携ブリッジ
// ------------------------------------------
#ifdef __EMSCRIPTEN__
static char s_js_eval_str_buf[1024] = {0};

void zen_js_eval(const char* code) {
    if (!code || !code[0]) return;
    emscripten_run_script(code);
}

double zen_js_eval_num(const char* code) {
    if (!code || !code[0]) return 0.0;
    return EM_ASM_DOUBLE({
        try {
            var v = Number(eval(UTF8ToString($0)));
            return isFinite(v) ? v : 0.0;
        } catch (e) {
            return 0.0;
        }
    }, code);
}

const char* zen_js_eval_str(const char* code) {
    if (!code || !code[0]) return "";
    char* res = emscripten_run_script_string(code);
    if (!res) return "";
    strncpy(s_js_eval_str_buf, res, sizeof(s_js_eval_str_buf) - 1);
    s_js_eval_str_buf[sizeof(s_js_eval_str_buf) - 1] = '\0';
    return s_js_eval_str_buf;
}

int zen_js_is_page_visible(void) {
    return EM_ASM_INT({
        return (document.visibilityState === "visible") ? 1 : 0;
    });
}

void zen_js_get_safe_area(float* left, float* top, float* right, float* bottom) {
    if (!left || !top || !right || !bottom) return;
    *left = 0.0f; *top = 0.0f; *right = 0.0f; *bottom = 0.0f;

    // Canvas のクライアント矩形と safe-area-inset を取得し、Zenoo の仮想座標系へ逆算
    double l = EM_ASM_DOUBLE({
        var d = document.getElementById("zenoo-safe-area-probe");
        if (!d) {
            d = document.createElement("div");
            d.id = "zenoo-safe-area-probe";
            d.style.position = "fixed";
            d.style.top = "0";
            d.style.left = "0";
            d.style.width = "0";
            d.style.height = "0";
            d.style.visibility = "hidden";
            d.style.pointerEvents = "none";
            d.style.paddingLeft = "env(safe-area-inset-left, 0px)";
            d.style.paddingTop = "env(safe-area-inset-top, 0px)";
            d.style.paddingRight = "env(safe-area-inset-right, 0px)";
            d.style.paddingBottom = "env(safe-area-inset-bottom, 0px)";
            document.body.appendChild(d);
        }
        var cs = window.getComputedStyle(d);
        var pl = parseFloat(cs.paddingLeft) || 0;
        var pt = parseFloat(cs.paddingTop) || 0;
        var pr = parseFloat(cs.paddingRight) || 0;
        var pb = parseFloat(cs.paddingBottom) || 0;

        var cv = document.getElementById("canvas") || document.querySelector("canvas");
        if (!cv) return 0;
        var rect = cv.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return 0;

        var cvLeft = rect.left;
        var cvTop = rect.top;
        var cvRight = window.innerWidth - rect.right;
        var cvBottom = window.innerHeight - rect.bottom;

        var inLeft = Math.max(0, pl - cvLeft);
        var inTop = Math.max(0, pt - cvTop);
        var inRight = Math.max(0, pr - cvRight);
        var inBottom = Math.max(0, pb - cvBottom);

        var scaleX = cv.width / rect.width;
        var scaleY = cv.height / rect.height;

        if (!window.__zen_safe_area) window.__zen_safe_area = new Array(4);
        window.__zen_safe_area[0] = inLeft * scaleX;
        window.__zen_safe_area[1] = inTop * scaleY;
        window.__zen_safe_area[2] = inRight * scaleX;
        window.__zen_safe_area[3] = inBottom * scaleY;
        return window.__zen_safe_area[0];
    });

    double t = EM_ASM_DOUBLE({ return window.__zen_safe_area ? window.__zen_safe_area[1] : 0; });
    double r = EM_ASM_DOUBLE({ return window.__zen_safe_area ? window.__zen_safe_area[2] : 0; });
    double b = EM_ASM_DOUBLE({ return window.__zen_safe_area ? window.__zen_safe_area[3] : 0; });

    *left   = (float)l;
    *top    = (float)t;
    *right  = (float)r;
    *bottom = (float)b;
}
#else
void zen_js_eval(const char* code) {
    (void)code;
}

double zen_js_eval_num(const char* code) {
    (void)code;
    return 0.0;
}

const char* zen_js_eval_str(const char* code) {
    (void)code;
    return "";
}

int zen_js_is_page_visible(void) {
    return zen_is_window_focused();
}

void zen_js_get_safe_area(float* left, float* top, float* right, float* bottom) {
    if (left) *left = 0.0f;
    if (top) *top = 0.0f;
    if (right) *right = 0.0f;
    if (bottom) *bottom = 0.0f;
}
#endif

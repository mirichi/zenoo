#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// stb_vorbis を先にインクルードして、miniaudio のビルトイン stb_vorbis バインディングを有効化
#include "stb_vorbis.c"
#undef L
#undef C
#undef R
#undef PLAYBACK_LEFT
#undef PLAYBACK_RIGHT
#undef PLAYBACK_MONO

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "zenoo.h"

struct ZenSound {
    ma_sound sound;
    int is_data_source;
    ma_audio_buffer audio_buf;
    ma_uint64 loop_start_pcm;
    ma_uint64 loop_end_pcm;
    int has_loop_points;
};

// Ogg Vorbis のコメントから LOOPSTART / LOOPLENGTH / LOOPEND を検出
static int parse_ogg_comments_for_loop(const char* filepath, uint64_t* out_start, uint64_t* out_end) {
    if (!filepath) return 0;
    int error = 0;
    stb_vorbis* v = stb_vorbis_open_filename(filepath, &error, NULL);
    if (!v) return 0;

    stb_vorbis_comment comment = stb_vorbis_get_comment(v);
    int found = 0;
    int64_t start = -1;
    int64_t length = -1;
    int64_t end = -1;

    for (int i = 0; i < comment.comment_list_length; ++i) {
        char* str = comment.comment_list[i];
        if (!str) continue;
        char* eq = strchr(str, '=');
        if (!eq) continue;

        size_t keylen = (size_t)(eq - str);
        char key[64];
        if (keylen >= sizeof(key)) keylen = sizeof(key) - 1;
        for (size_t k = 0; k < keylen; ++k) {
            key[k] = (char)toupper((unsigned char)str[k]);
        }
        key[keylen] = '\0';

        const char* val = eq + 1;
        while (*val == ' ') val++;

        if (strcmp(key, "LOOPSTART") == 0 || strcmp(key, "LOOP_START") == 0 || strcmp(key, "LOOPPOINT") == 0) {
            start = (int64_t)strtoll(val, NULL, 10);
            found = 1;
        } else if (strcmp(key, "LOOPLENGTH") == 0 || strcmp(key, "LOOP_LENGTH") == 0) {
            length = (int64_t)strtoll(val, NULL, 10);
            found = 1;
        } else if (strcmp(key, "LOOPEND") == 0 || strcmp(key, "LOOP_END") == 0) {
            end = (int64_t)strtoll(val, NULL, 10);
            found = 1;
        }
    }
    stb_vorbis_close(v);

    if (found && start >= 0) {
        if (out_start) *out_start = (uint64_t)start;
        if (length > 0 && end <= 0) {
            end = start + length;
        }
        if (out_end) *out_end = (end > start) ? (uint64_t)end : 0;
        return 1;
    }
    return 0;
}

static bool s_audio_initialized = false;
static ma_resource_manager s_resource_manager;
static ma_engine s_engine;

// ==========================================
// ライフサイクル & グローバル制御
// ==========================================
int zen_audio_init(void) {
    if (s_audio_initialized) {
        return 1;
    }

    // stb_vorbis をカスタムデコーダとして登録
    ma_decoding_backend_vtable* custom_backends[] = {
        &g_ma_decoding_backend_vtable_stbvorbis
    };

    ma_resource_manager_config rm_config = ma_resource_manager_config_init();
    rm_config.ppCustomDecodingBackendVTables = custom_backends;
    rm_config.customDecodingBackendCount = (ma_uint32)(sizeof(custom_backends) / sizeof(custom_backends[0]));
#if defined(__EMSCRIPTEN__) && !defined(__EMSCRIPTEN_PTHREADS__)
    rm_config.jobThreadCount = 0;
    rm_config.flags |= MA_RESOURCE_MANAGER_FLAG_NO_THREADING;
#endif

    ma_result res = ma_resource_manager_init(&rm_config, &s_resource_manager);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[Zenoo Audio] Failed to initialize resource manager (error %d)\n", res);
        return 0;
    }

    ma_engine_config engine_config = ma_engine_config_init();
    engine_config.pResourceManager = &s_resource_manager;

    res = ma_engine_init(&engine_config, &s_engine);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[Zenoo Audio] Failed to initialize audio engine (error %d)\n", res);
        ma_resource_manager_uninit(&s_resource_manager);
        return 0;
    }

    s_audio_initialized = true;
    return 1;
}

void zen_audio_shutdown(void) {
    if (!s_audio_initialized) {
        return;
    }

    ma_engine_uninit(&s_engine);
    ma_resource_manager_uninit(&s_resource_manager);
    s_audio_initialized = false;
}

void zen_audio_set_master_volume(float volume) {
    if (!s_audio_initialized && !zen_audio_init()) {
        return;
    }
    ma_engine_set_volume(&s_engine, volume);
}

float zen_audio_get_master_volume(void) {
    if (!s_audio_initialized && !zen_audio_init()) {
        return 1.0f;
    }
    return ma_engine_get_volume(&s_engine);
}

// ==========================================
// サウンドの生成・破棄
// ==========================================
ZenSound* zen_sound_load_file(const char* filepath, int stream) {
    if (!filepath) {
        return NULL;
    }
    if (!s_audio_initialized && !zen_audio_init()) {
        return NULL;
    }

    ZenSound* s = (ZenSound*)calloc(1, sizeof(ZenSound));
    if (!s) {
        return NULL;
    }
    s->is_data_source = 0;

    ma_uint32 flags = stream ? MA_SOUND_FLAG_STREAM : 0;
    ma_result res = ma_sound_init_from_file(&s_engine, filepath, flags, NULL, NULL, &s->sound);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[Zenoo Audio] Failed to load sound from file: %s (error %d)\n", filepath, res);
        free(s);
        return NULL;
    }

    uint64_t ogg_start = 0, ogg_end = 0;
    if (parse_ogg_comments_for_loop(filepath, &ogg_start, &ogg_end)) {
        zen_sound_set_loop_points_pcm(s, ogg_start, ogg_end);
    }

    return s;
}

ZenSound* zen_sound_load_memory_pcm(const float* frames, int frame_count, int channels, int sample_rate) {
    if (!frames || frame_count <= 0 || channels <= 0 || sample_rate <= 0) {
        return NULL;
    }
    if (!s_audio_initialized && !zen_audio_init()) {
        return NULL;
    }

    ZenSound* s = (ZenSound*)calloc(1, sizeof(ZenSound));
    if (!s) {
        return NULL;
    }
    s->is_data_source = 1;

    ma_audio_buffer_config buf_config = ma_audio_buffer_config_init(ma_format_f32, (ma_uint32)channels, (ma_uint64)frame_count, frames, NULL);
    buf_config.sampleRate = (ma_uint32)sample_rate;

    ma_result res = ma_audio_buffer_init_copy(&buf_config, &s->audio_buf);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[Zenoo Audio] Failed to init audio buffer copy (error %d)\n", res);
        free(s);
        return NULL;
    }

    res = ma_sound_init_from_data_source(&s_engine, (ma_data_source*)&s->audio_buf, 0, NULL, &s->sound);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[Zenoo Audio] Failed to init sound from data source (error %d)\n", res);
        ma_audio_buffer_uninit(&s->audio_buf);
        free(s);
        return NULL;
    }

    return s;
}

void zen_sound_destroy(ZenSound* sound) {
    if (!sound) {
        return;
    }

    if (s_audio_initialized) {
        ma_sound_uninit(&sound->sound);
        if (sound->is_data_source) {
            ma_audio_buffer_uninit(&sound->audio_buf);
        }
    }
    free(sound);
}

// ==========================================
// 再生制御
// ==========================================
void zen_sound_play(ZenSound* sound) {
    if (!sound) {
        return;
    }
    // 再生中の場合は先頭からリトリガー再生
    if (ma_sound_is_playing(&sound->sound)) {
        ma_sound_seek_to_pcm_frame(&sound->sound, 0);
    }
    ma_sound_start(&sound->sound);
}

void zen_sound_stop(ZenSound* sound) {
    if (!sound) {
        return;
    }
    ma_sound_stop(&sound->sound);
    ma_sound_seek_to_pcm_frame(&sound->sound, 0);
}

void zen_sound_pause(ZenSound* sound) {
    if (!sound) {
        return;
    }
    ma_sound_stop(&sound->sound);
}

int zen_sound_is_playing(const ZenSound* sound) {
    if (!sound) {
        return 0;
    }
    return ma_sound_is_playing(&sound->sound) ? 1 : 0;
}

// ==========================================
// パラメータ制御
// ==========================================
void zen_sound_set_volume(ZenSound* sound, float volume) {
    if (!sound) return;
    ma_sound_set_volume(&sound->sound, volume);
}

float zen_sound_get_volume(const ZenSound* sound) {
    if (!sound) return 0.0f;
    return ma_sound_get_volume(&sound->sound);
}

void zen_sound_set_looping(ZenSound* sound, int looping) {
    if (!sound) return;
    ma_sound_set_looping(&sound->sound, looping ? MA_TRUE : MA_FALSE);
}

int zen_sound_is_looping(const ZenSound* sound) {
    if (!sound) return 0;
    return ma_sound_is_looping(&sound->sound) ? 1 : 0;
}

void zen_sound_set_pitch(ZenSound* sound, float pitch) {
    if (!sound) return;
    ma_sound_set_pitch(&sound->sound, pitch);
}

float zen_sound_get_pitch(const ZenSound* sound) {
    if (!sound) return 1.0f;
    return ma_sound_get_pitch(&sound->sound);
}

void zen_sound_set_pan(ZenSound* sound, float pan) {
    if (!sound) return;
    ma_sound_set_pan(&sound->sound, pan);
}

float zen_sound_get_pan(const ZenSound* sound) {
    if (!sound) return 0.0f;
    return ma_sound_get_pan(&sound->sound);
}

// ==========================================
// シーク & 時間情報
// ==========================================
void zen_sound_seek(ZenSound* sound, float seconds) {
    if (!sound) return;
    ma_sound_seek_to_second(&sound->sound, seconds);
}

float zen_sound_get_cursor(const ZenSound* sound) {
    if (!sound) return 0.0f;
    float cursor = 0.0f;
    ma_sound_get_cursor_in_seconds((ma_sound*)&sound->sound, &cursor);
    return cursor;
}

float zen_sound_get_length(const ZenSound* sound) {
    if (!sound) return 0.0f;
    float length = 0.0f;
    ma_sound_get_length_in_seconds((ma_sound*)&sound->sound, &length);
    return length;
}

uint32_t zen_sound_get_sample_rate(const ZenSound* sound) {
    if (!sound) return 0;
    ma_uint32 sample_rate = 0;
    ma_sound_get_data_format((ma_sound*)&sound->sound, NULL, NULL, &sample_rate, NULL, 0);
    return sample_rate;
}

uint64_t zen_sound_get_length_pcm(const ZenSound* sound) {
    if (!sound) return 0;
    ma_uint64 length = 0;
    ma_sound_get_length_in_pcm_frames((ma_sound*)&sound->sound, &length);
    return length;
}

// ==========================================
// ループポイント制御
// ==========================================
void zen_sound_set_loop_points_pcm(ZenSound* sound, uint64_t start_frame, uint64_t end_frame) {
    if (!sound) return;
    ma_data_source* ds = ma_sound_get_data_source(&sound->sound);
    if (!ds) return;

    ma_uint64 total_frames = 0;
    ma_sound_get_length_in_pcm_frames(&sound->sound, &total_frames);

    ma_uint64 end = end_frame;
    if (end == 0 || (total_frames > 0 && end > total_frames)) {
        end = (total_frames > 0) ? total_frames : ~((ma_uint64)0);
    }

    ma_result res = ma_data_source_set_loop_point_in_pcm_frames(ds, (ma_uint64)start_frame, end);
    if (res == MA_SUCCESS) {
        sound->loop_start_pcm = (ma_uint64)start_frame;
        sound->loop_end_pcm = (end == total_frames) ? 0 : (ma_uint64)end;
        sound->has_loop_points = 1;
        ma_sound_set_looping(&sound->sound, MA_TRUE);
    }
}

void zen_sound_get_loop_points_pcm(const ZenSound* sound, uint64_t* out_start, uint64_t* out_end) {
    if (!sound) {
        if (out_start) *out_start = 0;
        if (out_end) *out_end = 0;
        return;
    }
    if (out_start) *out_start = sound->loop_start_pcm;
    if (out_end) {
        if (sound->loop_end_pcm == 0) {
            ma_uint64 total = 0;
            ma_sound_get_length_in_pcm_frames((ma_sound*)&sound->sound, &total);
            *out_end = total;
        } else {
            *out_end = sound->loop_end_pcm;
        }
    }
}

void zen_sound_set_loop_points_seconds(ZenSound* sound, float start_sec, float end_sec) {
    if (!sound) return;
    uint32_t sr = zen_sound_get_sample_rate(sound);
    if (sr == 0) sr = 44100;

    uint64_t start_frame = (uint64_t)(start_sec * (float)sr);
    uint64_t end_frame = (end_sec > 0.0f) ? (uint64_t)(end_sec * (float)sr) : 0;
    zen_sound_set_loop_points_pcm(sound, start_frame, end_frame);
}

void zen_sound_get_loop_points_seconds(const ZenSound* sound, float* out_start, float* out_end) {
    if (!sound) {
        if (out_start) *out_start = 0.0f;
        if (out_end) *out_end = 0.0f;
        return;
    }
    uint32_t sr = zen_sound_get_sample_rate(sound);
    if (sr == 0) sr = 44100;

    if (out_start) *out_start = (float)sound->loop_start_pcm / (float)sr;
    if (out_end) {
        if (sound->loop_end_pcm == 0) {
            *out_end = zen_sound_get_length(sound);
        } else {
            *out_end = (float)sound->loop_end_pcm / (float)sr;
        }
    }
}

int zen_sound_has_loop_points(const ZenSound* sound) {
    return (sound && sound->has_loop_points) ? 1 : 0;
}

void zen_sound_clear_loop_points(ZenSound* sound) {
    if (!sound) return;
    ma_data_source* ds = ma_sound_get_data_source(&sound->sound);
    if (ds) {
        ma_data_source_set_loop_point_in_pcm_frames(ds, 0, ~((ma_uint64)0));
    }
    sound->loop_start_pcm = 0;
    sound->loop_end_pcm = 0;
    sound->has_loop_points = 0;
}

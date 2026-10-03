#!/usr/bin/env bash
set -e

# ====================================================
# Zenoo 単体 Wasm ビルドスクリプト
# 任意の Ruby アプリを build/wasm にコンパイル
# ====================================================

# 1. Emscripten 環境の有効化
if [ -z "$EMSDK" ]; then
    if [ -f "$HOME/emsdk/emsdk_env.sh" ]; then
        source "$HOME/emsdk/emsdk_env.sh" > /dev/null 2>&1
    else
        echo "Error: EMSDK not found in $HOME/emsdk"
        exit 1
    fi
fi

SPINEL_DIR="${HOME}/spinel"
SPINEL_BIN="${SPINEL_DIR}/bin/spinel"

TARGET_RB="${1:-examples/game_zenoo.rb}"
OUTPUT_DIR="build/wasm"
CACHE_DIR="build/wasm_cache"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${CACHE_DIR}/rt"
mkdir -p "${CACHE_DIR}/regexp"

echo "=== [1/4] Generating C code with Spinel AOT (${TARGET_RB}) ==="
"${SPINEL_BIN}" --no-inline-hot -Ilib "${TARGET_RB}" -c -o "${OUTPUT_DIR}/app.c"
sed -i 's/__attribute__((always_inline))//g' "${OUTPUT_DIR}/app.c"

echo "=== [2/4] Building Spinel Runtime for Wasm ==="
RT_FILES=(sp_bigint.c sp_crypto.c sp_pack.c sp_time.c sp_core.c sp_net.c sp_system.c sp_gc.c sp_slab.c sp_alloc.c sp_dtoa.c sp_marshal.c sp_format.c sp_string.c sp_inspect.c sp_array.c sp_str.c sp_hash.c sp_proc.c sp_exc.c sp_re.c sp_random.c sp_fiber.c sp_sched.c sp_io.c sp_iobuffer.c sp_cold.c sp_process.c sp_process_status.c)

for f in "${RT_FILES[@]}"; do
    obj="${CACHE_DIR}/rt/${f%.c}.o"
    if [ ! -f "$obj" ] || [ "${SPINEL_DIR}/lib/$f" -nt "$obj" ]; then
        emcc -c -O2 -I"${SPINEL_DIR}/lib" -I"${SPINEL_DIR}/lib/regexp" "${SPINEL_DIR}/lib/$f" -o "$obj"
    fi
done

for f in "${SPINEL_DIR}"/lib/regexp/*.c; do
    bn=$(basename "$f" .c)
    obj="${CACHE_DIR}/regexp/${bn}.o"
    if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
        emcc -c -O2 -I"${SPINEL_DIR}/lib/regexp" "$f" -o "$obj"
    fi
done

emar rcs "${CACHE_DIR}/libspinel_rt.a" "${CACHE_DIR}/rt"/*.o "${CACHE_DIR}/regexp"/*.o

echo "=== [3/4] Building Zenoo C Kernel for Wasm ==="
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_core.c -o "${CACHE_DIR}/zenoo_core.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_gfx.c -o "${CACHE_DIR}/zenoo_gfx.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_font.c -o "${CACHE_DIR}/zenoo_font.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_audio.c -o "${CACHE_DIR}/zenoo_audio.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" ext/spinel/zenoo_spinel.c -o "${CACHE_DIR}/zenoo_spinel.o"

echo "=== [4/4] Linking Wasm + WebGL Application ==="
emcc -O2 \
    -s USE_GLFW=3 \
    -s MAX_WEBGL_VERSION=2 \
    -s MIN_WEBGL_VERSION=2 \
    -s STACK_SIZE=1048576 \
    -s INITIAL_MEMORY=67108864 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s WASM=1 \
    -s EXPORTED_FUNCTIONS="['_main','_zen_push_char']" \
    --preload-file assets@/assets \
    -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" \
    "${OUTPUT_DIR}/app.c" \
    "${CACHE_DIR}/zenoo_core.o" \
    "${CACHE_DIR}/zenoo_gfx.o" \
    "${CACHE_DIR}/zenoo_font.o" \
    "${CACHE_DIR}/zenoo_audio.o" \
    "${CACHE_DIR}/zenoo_spinel.o" \
    "${CACHE_DIR}/libspinel_rt.a" \
    -o "${OUTPUT_DIR}/index.html" \
    --shell-file examples/web/shell.html

rm -f "${OUTPUT_DIR}/app.c"

echo ""
echo "=========================================================="
echo " Wasm Build Complete!"
echo " Output : ${OUTPUT_DIR}/index.html"
echo " Run    : ruby server.rb wasm"
echo "=========================================================="

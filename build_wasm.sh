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
python3 -c "import sys, re; p=sys.argv[1]; s=open(p, 'r', encoding='utf-8', errors='ignore').read().replace('__attribute__((always_inline))', ''); s=re.sub(r'/mnt/c/Users/[^/\"\'\s]+', '/workspace', s); open(p, 'w', encoding='utf-8').write(s)" "${OUTPUT_DIR}/app.c"

echo "=== [2/4] Building Spinel Runtime for Wasm ==="
for f in "${SPINEL_DIR}"/lib/*.c; do
    bn=$(basename "$f" .c)
    obj="${CACHE_DIR}/rt/${bn}.o"
    if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
        emcc -c -O2 -I"${SPINEL_DIR}/lib" -I"${SPINEL_DIR}/lib/regexp" "$f" -o "$obj"
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
    -fmacro-prefix-map="${PWD}"=. \
    -fdebug-prefix-map="${PWD}"=. \
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

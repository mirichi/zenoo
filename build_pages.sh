#!/usr/bin/env bash
set -e

# ====================================================
# Zenoo GitHub Pages 一括ビルドスクリプト
# Game (Survival Shooting) & GUI Demo を docs/ に生成
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

DOCS_DIR="docs"
CACHE_DIR="build/wasm_cache"
mkdir -p "${DOCS_DIR}/game"
mkdir -p "${DOCS_DIR}/gui"
mkdir -p "${CACHE_DIR}/rt"
mkdir -p "${CACHE_DIR}/regexp"

echo "=== [1/5] Setting up GitHub Pages structure ==="
# Jekyll 処理を無効化 (Wasmファイルの配信を確実にする)
touch "${DOCS_DIR}/.nojekyll"
# ポータルページを配置
cp examples/web/portal.html "${DOCS_DIR}/index.html"

echo "=== [2/5] Building Common Spinel Runtime for Wasm ==="
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

echo "=== [3/5] Building Common Zenoo C Kernel ==="
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_core.c -o "${CACHE_DIR}/zenoo_core.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_gfx.c -o "${CACHE_DIR}/zenoo_gfx.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" src/zenoo_font.c -o "${CACHE_DIR}/zenoo_font.o"
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" ext/spinel/zenoo_spinel.c -o "${CACHE_DIR}/zenoo_spinel.o"

COMMON_EMCC_FLAGS=(
    -O2
    -s USE_GLFW=3
    -s MAX_WEBGL_VERSION=2
    -s MIN_WEBGL_VERSION=2
    -s ASYNCIFY
    -s ASYNCIFY_STACK_SIZE=65536
    -s STACK_SIZE=1048576
    -s INITIAL_MEMORY=67108864
    -s ALLOW_MEMORY_GROWTH=1
    -s WASM=1
    --preload-file assets@/assets
    -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib"
)

COMMON_OBJS=(
    "${CACHE_DIR}/zenoo_core.o"
    "${CACHE_DIR}/zenoo_gfx.o"
    "${CACHE_DIR}/zenoo_font.o"
    "${CACHE_DIR}/zenoo_spinel.o"
    "${CACHE_DIR}/libspinel_rt.a"
)

echo "=== [4/6] Building Survival Shooting Game (docs/game) ==="
"${SPINEL_BIN}" --no-inline-hot -Ilib examples/game_zenoo.rb -c -o "${DOCS_DIR}/game/app.c"
sed -i 's/__attribute__((always_inline))//g' "${DOCS_DIR}/game/app.c"

emcc "${COMMON_EMCC_FLAGS[@]}" \
    "${DOCS_DIR}/game/app.c" \
    "${COMMON_OBJS[@]}" \
    -o "${DOCS_DIR}/game/index.html" \
    --shell-file examples/web/shell_game.html

rm -f "${DOCS_DIR}/game/app.c"

echo "=== [5/6] Building Immediate Mode GUI Demo (docs/gui) ==="
"${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_gui.rb -c -o "${DOCS_DIR}/gui/app.c"
sed -i 's/__attribute__((always_inline))//g' "${DOCS_DIR}/gui/app.c"

emcc "${COMMON_EMCC_FLAGS[@]}" \
    "${DOCS_DIR}/gui/app.c" \
    "${COMMON_OBJS[@]}" \
    -o "${DOCS_DIR}/gui/index.html" \
    --shell-file examples/web/shell_gui.html

rm -f "${DOCS_DIR}/gui/app.c"

echo "=== [6/6] Building SDF Text & Font Demo (docs/font) ==="
mkdir -p "${DOCS_DIR}/font"
"${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_ttf_sdf_font.rb -c -o "${DOCS_DIR}/font/app.c"
sed -i 's/__attribute__((always_inline))//g' "${DOCS_DIR}/font/app.c"

emcc "${COMMON_EMCC_FLAGS[@]}" \
    "${DOCS_DIR}/font/app.c" \
    "${COMMON_OBJS[@]}" \
    -o "${DOCS_DIR}/font/index.html" \
    --shell-file examples/web/shell_font.html

rm -f "${DOCS_DIR}/font/app.c"

echo ""
echo "=========================================================="
echo " Showcase build complete!"
echo " Portal: ${DOCS_DIR}/index.html"
echo " Game  : ${DOCS_DIR}/game/index.html"
echo " GUI   : ${DOCS_DIR}/gui/index.html"
echo " Font  : ${DOCS_DIR}/font/index.html"
echo "=========================================================="

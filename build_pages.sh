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
emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" ext/spinel/zenoo_spinel.c -o "${CACHE_DIR}/zenoo_spinel.o"

echo "=== [4/5] Building Survival Shooting Game (docs/game) ==="
"${SPINEL_BIN}" -Ilib examples/game_zenoo.rb -c -o "${DOCS_DIR}/game/app.c"
sed -i 's/__attribute__((always_inline))//g' "${DOCS_DIR}/game/app.c"

emcc -O2 \
    -s USE_GLFW=3 \
    -s MAX_WEBGL_VERSION=2 \
    -s MIN_WEBGL_VERSION=2 \
    -s ASYNCIFY \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s WASM=1 \
    -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" \
    "${DOCS_DIR}/game/app.c" \
    "${CACHE_DIR}/zenoo_core.o" \
    "${CACHE_DIR}/zenoo_gfx.o" \
    "${CACHE_DIR}/zenoo_spinel.o" \
    "${CACHE_DIR}/libspinel_rt.a" \
    -o "${DOCS_DIR}/game/index.html" \
    --shell-file examples/web/shell_game.html

rm -f "${DOCS_DIR}/game/app.c"

echo "=== [5/5] Building Immediate Mode GUI Demo (docs/gui) ==="
"${SPINEL_BIN}" -Ilib examples/demo_gui.rb -c -o "${DOCS_DIR}/gui/app.c"
sed -i 's/__attribute__((always_inline))//g' "${DOCS_DIR}/gui/app.c"

emcc -O2 \
    -s USE_GLFW=3 \
    -s MAX_WEBGL_VERSION=2 \
    -s MIN_WEBGL_VERSION=2 \
    -s ASYNCIFY \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s WASM=1 \
    -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" \
    "${DOCS_DIR}/gui/app.c" \
    "${CACHE_DIR}/zenoo_core.o" \
    "${CACHE_DIR}/zenoo_gfx.o" \
    "${CACHE_DIR}/zenoo_spinel.o" \
    "${CACHE_DIR}/libspinel_rt.a" \
    -o "${DOCS_DIR}/gui/index.html" \
    --shell-file examples/web/shell_gui.html

rm -f "${DOCS_DIR}/gui/app.c"

echo ""
echo "=========================================================="
echo " Showcase build complete!"
echo " Portal: ${DOCS_DIR}/index.html"
echo " Game  : ${DOCS_DIR}/game/index.html"
echo " GUI   : ${DOCS_DIR}/gui/index.html"
echo "=========================================================="

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
mkdir -p "${DOCS_DIR}/image"
mkdir -p "${DOCS_DIR}/font"
mkdir -p "${DOCS_DIR}/vector"
mkdir -p "${DOCS_DIR}/atlas"
mkdir -p "${DOCS_DIR}/window"
mkdir -p "${DOCS_DIR}/clip"
mkdir -p "${DOCS_DIR}/sound"
mkdir -p "${DOCS_DIR}/collision"
mkdir -p "${DOCS_DIR}/tween"
mkdir -p "${CACHE_DIR}/rt"
mkdir -p "${CACHE_DIR}/regexp"

echo "=== [1/5] Setting up GitHub Pages structure ==="
# Jekyll 処理を無効化 (Wasmファイルの配信を確実にする)
touch "${DOCS_DIR}/.nojekyll"
# ポータルページを配置
cp examples/web/portal.html "${DOCS_DIR}/index.html"

echo "=== [2/5] Building Common Spinel Runtime for Wasm ==="
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
        emcc -c -O2 -I"${SPINEL_DIR}/lib/regexp" -I"${SPINEL_DIR}/lib/regexp/shim" "$f" -o "$obj"
    fi
done

emar rcs "${CACHE_DIR}/libspinel_rt.a" "${CACHE_DIR}/rt"/*.o "${CACHE_DIR}/regexp"/*.o

echo "=== [3/5] Building Common Zenoo C Kernel ==="
build_c_kernel_obj() {
    src="$1"
    obj="$2"
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
        emcc -c -O2 -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" "$src" -o "$obj"
    fi
}
build_c_kernel_obj "src/zenoo_window.c" "${CACHE_DIR}/zenoo_window.o"
build_c_kernel_obj "src/zenoo_input.c" "${CACHE_DIR}/zenoo_input.o"
build_c_kernel_obj "src/zenoo_vibration.c" "${CACHE_DIR}/zenoo_vibration.o"
build_c_kernel_obj "src/zenoo_image.c" "${CACHE_DIR}/zenoo_image.o"
build_c_kernel_obj "src/zenoo_gfx.c" "${CACHE_DIR}/zenoo_gfx.o"
build_c_kernel_obj "src/zenoo_font.c" "${CACHE_DIR}/zenoo_font.o"
build_c_kernel_obj "src/zenoo_audio.c" "${CACHE_DIR}/zenoo_audio.o"
build_c_kernel_obj "ext/spinel/zenoo_spinel.c" "${CACHE_DIR}/zenoo_spinel.o"

OPT_LEVEL="${OPT_LEVEL:--O1}"
DEBUG_FLAGS="${DEBUG_FLAGS:--g0}"

COMMON_EMCC_FLAGS=(
    "${OPT_LEVEL}"
    ${DEBUG_FLAGS}
    -s USE_GLFW=3
    -s MAX_WEBGL_VERSION=2
    -s MIN_WEBGL_VERSION=2
    -s STACK_SIZE=1048576
    -s INITIAL_MEMORY=67108864
    -s ALLOW_MEMORY_GROWTH=1
    -s NO_EXIT_RUNTIME=1
    -s WASM=1
    -s EXPORTED_FUNCTIONS="['_main','_zen_push_char']"
    --preload-file assets@/assets
    -fmacro-prefix-map="${PWD}"=.
    -fdebug-prefix-map="${PWD}"=.
    -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib"
)

COMMON_OBJS=(
    "${CACHE_DIR}/zenoo_window.o"
    "${CACHE_DIR}/zenoo_input.o"
    "${CACHE_DIR}/zenoo_vibration.o"
    "${CACHE_DIR}/zenoo_image.o"
    "${CACHE_DIR}/zenoo_gfx.o"
    "${CACHE_DIR}/zenoo_font.o"
    "${CACHE_DIR}/zenoo_audio.o"
    "${CACHE_DIR}/zenoo_spinel.o"
    "${CACHE_DIR}/libspinel_rt.a"
)

TARGET="${1:-all}"

strip_always_inline() {
    python3 -c "import sys, re; p=sys.argv[1]; s=open(p, 'r', encoding='utf-8', errors='ignore').read().replace('__attribute__((always_inline))', ''); s=re.sub(r'/mnt/c/Users/[^/\"\'\s]+', '/workspace', s); open(p, 'w', encoding='utf-8').write(s)" "$1"
}

build_game() {
    echo "=== Building Survival Shooting Game (${DOCS_DIR}/game) ==="
    mkdir -p "${DOCS_DIR}/game"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/game_zenoo.rb -c -o "${DOCS_DIR}/game/app.c"
    strip_always_inline "${DOCS_DIR}/game/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/game/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/game/index.html" \
        --shell-file examples/web/shell_game.html

    rm -f "${DOCS_DIR}/game/app.c"
    echo "-> Game build done!"
}

build_gui() {
    echo "=== Building Immediate Mode GUI Demo (${DOCS_DIR}/gui) ==="
    mkdir -p "${DOCS_DIR}/gui"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_gui.rb -c -o "${DOCS_DIR}/gui/app.c"
    strip_always_inline "${DOCS_DIR}/gui/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/gui/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/gui/index.html" \
        --shell-file examples/web/shell_gui.html

    rm -f "${DOCS_DIR}/gui/app.c"
    echo "-> GUI build done!"
}

build_font() {
    echo "=== Building SDF Text & Font Demo (${DOCS_DIR}/font) ==="
    mkdir -p "${DOCS_DIR}/font"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_ttf_sdf_font.rb -c -o "${DOCS_DIR}/font/app.c"
    strip_always_inline "${DOCS_DIR}/font/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/font/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/font/index.html" \
        --shell-file examples/web/shell_font.html

    rm -f "${DOCS_DIR}/font/app.c"
    echo "-> Font build done!"
}

build_vector() {
    echo "=== Building Vector Graphics Demo (${DOCS_DIR}/vector) ==="
    mkdir -p "${DOCS_DIR}/vector"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_vector_graphics.rb -c -o "${DOCS_DIR}/vector/app.c"
    strip_always_inline "${DOCS_DIR}/vector/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/vector/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/vector/index.html" \
        --shell-file examples/web/shell.html

    rm -f "${DOCS_DIR}/vector/app.c"
    echo "-> Vector build done!"
}

build_image() {
    echo "=== Building Sprite & Blend Modes Demo (${DOCS_DIR}/image) ==="
    mkdir -p "${DOCS_DIR}/image"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_draw_image.rb -c -o "${DOCS_DIR}/image/app.c"
    strip_always_inline "${DOCS_DIR}/image/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/image/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/image/index.html" \
        --shell-file examples/web/shell_image.html

    rm -f "${DOCS_DIR}/image/app.c"
    echo "-> Image build done!"
}

build_atlas() {
    echo "=== Building Texture Atlas Demo (${DOCS_DIR}/atlas) ==="
    mkdir -p "${DOCS_DIR}/atlas"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_texture_atlas.rb -c -o "${DOCS_DIR}/atlas/app.c"
    strip_always_inline "${DOCS_DIR}/atlas/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/atlas/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/atlas/index.html" \
        --shell-file examples/web/shell_atlas.html

    rm -f "${DOCS_DIR}/atlas/app.c"
    echo "-> Atlas build done!"
}

build_window() {
    echo "=== Building Multi-Window & Occlusion Demo (${DOCS_DIR}/window) ==="
    mkdir -p "${DOCS_DIR}/window"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_window_drag.rb -c -o "${DOCS_DIR}/window/app.c"
    strip_always_inline "${DOCS_DIR}/window/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/window/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/window/index.html" \
        --shell-file examples/web/shell_window.html

    rm -f "${DOCS_DIR}/window/app.c"
    echo "-> Window build done!"
}

build_clip() {
    echo "=== Building Hardware Clipping Demo (${DOCS_DIR}/clip) ==="
    mkdir -p "${DOCS_DIR}/clip"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_window_clip.rb -c -o "${DOCS_DIR}/clip/app.c"
    strip_always_inline "${DOCS_DIR}/clip/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/clip/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/clip/index.html" \
        --shell-file examples/web/shell_clip.html

    rm -f "${DOCS_DIR}/clip/app.c"
    echo "-> Clip build done!"
}

build_sound() {
    echo "=== Building Audio & Sound Demo (${DOCS_DIR}/sound) ==="
    mkdir -p "${DOCS_DIR}/sound"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_sound.rb -c -o "${DOCS_DIR}/sound/app.c"
    strip_always_inline "${DOCS_DIR}/sound/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/sound/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/sound/index.html" \
        --shell-file examples/web/shell_sound.html

    rm -f "${DOCS_DIR}/sound/app.c"
    echo "-> Sound build done!"
}

build_collision() {
    echo "=== Building GJK Collision Playground (${DOCS_DIR}/collision) ==="
    mkdir -p "${DOCS_DIR}/collision"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_collision.rb -c -o "${DOCS_DIR}/collision/app.c"
    strip_always_inline "${DOCS_DIR}/collision/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/collision/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/collision/index.html" \
        --shell-file examples/web/shell_collision.html

    rm -f "${DOCS_DIR}/collision/app.c"
    echo "-> Collision build done!"
}

build_tween() {
    echo "=== Building Tween & Easing Animation (${DOCS_DIR}/tween) ==="
    mkdir -p "${DOCS_DIR}/tween"
    "${SPINEL_BIN}" --no-inline-hot -Ilib examples/demo_tween.rb -c -o "${DOCS_DIR}/tween/app.c"
    strip_always_inline "${DOCS_DIR}/tween/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${DOCS_DIR}/tween/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${DOCS_DIR}/tween/index.html" \
        --shell-file examples/web/shell_tween.html

    rm -f "${DOCS_DIR}/tween/app.c"
    echo "-> Tween build done!"
}

case "$TARGET" in
    game)      build_game ;;
    gui)       build_gui ;;
    font)      build_font ;;
    vector)    build_vector ;;
    image)     build_image ;;
    atlas)     build_atlas ;;
    window)    build_window ;;
    clip)      build_clip ;;
    sound)     build_sound ;;
    collision) build_collision ;;
    tween)     build_tween ;;
    all)
        build_game
        sleep 0.5
        build_gui
        sleep 0.5
        build_font
        sleep 0.5
        build_vector
        sleep 0.5
        build_image
        sleep 0.5
        build_atlas
        sleep 0.5
        build_window
        sleep 0.5
        build_clip
        sleep 0.5
        build_sound
        sleep 0.5
        build_collision
        sleep 0.5
        build_tween
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [game|gui|font|vector|image|atlas|window|clip|sound|collision|tween|all]"
        exit 1
        ;;
esac

echo ""
echo "=========================================================="
echo " Showcase build complete! (target: $TARGET)"
echo " Portal   : ${DOCS_DIR}/index.html"
echo " Game     : ${DOCS_DIR}/game/index.html"
echo " GUI      : ${DOCS_DIR}/gui/index.html"
echo " Font     : ${DOCS_DIR}/font/index.html"
echo " Vector   : ${DOCS_DIR}/vector/index.html"
echo " Image    : ${DOCS_DIR}/image/index.html"
echo " Atlas    : ${DOCS_DIR}/atlas/index.html"
echo " Window   : ${DOCS_DIR}/window/index.html"
echo " Clip     : ${DOCS_DIR}/clip/index.html"
echo " Sound    : ${DOCS_DIR}/sound/index.html"
echo " Collision: ${DOCS_DIR}/collision/index.html"
echo " Tween    : ${DOCS_DIR}/tween/index.html"
echo "=========================================================="

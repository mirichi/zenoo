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
mkdir -p "${DOCS_DIR}/coords"
mkdir -p "${DOCS_DIR}/billiards"
mkdir -p "${DOCS_DIR}/zero_gravity"
mkdir -p "${DOCS_DIR}/particles"
mkdir -p "${DOCS_DIR}/danmaku"
mkdir -p "${CACHE_DIR}/rt"
mkdir -p "${CACHE_DIR}/regexp"

echo "=== [1/5] Setting up GitHub Pages structure ==="
# Jekyll 処理を無効化 (Wasmファイルの配信を確実にする)
touch "${DOCS_DIR}/.nojekyll"
# ポータルページを配置
cp examples/web/portal.html "${DOCS_DIR}/index.html"

# ビルドモード判定 (サイズより速度優先)
#   BUILD_MODE=dev  (または fast) : -O1 (Clang最適化を軽量化し、ビルド時間を短縮)
#   BUILD_MODE=release (デフォルト) : -O2 (実行速度重視の標準最適化)
#   BUILD_MODE=max  (または o3)   : -O3 (最高速の実行速度)
case "${BUILD_MODE:-release}" in
    dev|fast)
        OPT_LEVEL="${OPT_LEVEL:--O1}"
        ;;
    max|o3)
        OPT_LEVEL="${OPT_LEVEL:--O3}"
        ;;
    *)
        OPT_LEVEL="${OPT_LEVEL:--O2}"
        ;;
esac
DEBUG_FLAGS="${DEBUG_FLAGS:--g0}"
echo "=== Build Mode: ${BUILD_MODE:-release} (${OPT_LEVEL}) ==="

echo "=== [2/5] Building Common Spinel Runtime for Wasm ==="
for f in "${SPINEL_DIR}"/lib/*.c; do
    bn=$(basename "$f" .c)
    obj="${CACHE_DIR}/rt/${bn}.o"
    if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
        emcc -c "${OPT_LEVEL}" -I"${SPINEL_DIR}/lib" -I"${SPINEL_DIR}/lib/regexp" "$f" -o "$obj"
    fi
done

for f in "${SPINEL_DIR}"/lib/regexp/*.c; do
    bn=$(basename "$f" .c)
    obj="${CACHE_DIR}/regexp/${bn}.o"
    if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
        emcc -c "${OPT_LEVEL}" -I"${SPINEL_DIR}/lib/regexp" -I"${SPINEL_DIR}/lib/regexp/shim" "$f" -o "$obj"
    fi
done

emar rcs "${CACHE_DIR}/libspinel_rt.a" "${CACHE_DIR}/rt"/*.o "${CACHE_DIR}/regexp"/*.o

echo "=== [3/5] Building Common Zenoo C Kernel ==="
build_c_kernel_obj() {
    src="$1"
    obj="$2"
    if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
        emcc -c "${OPT_LEVEL}" -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" "$src" -o "$obj"
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
    -s MINIFY_HTML=0
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
    python3 -c "import sys, re; p=sys.argv[1]; s=open(p, 'r', encoding='utf-8', errors='ignore').read(); s=re.sub(r'/mnt/c/Users/[^/\"\'\s]+', '/workspace', s); open(p, 'w', encoding='utf-8').write(s)" "$1"
}

patch_emscripten_js() {
    python3 -c "
import sys
p = sys.argv[1]
try:
    s = open(p, 'r', encoding='utf-8').read()
    s = s.replace('const total=Number(headers.get(\"Content-Length\")||packageSize);', 'const total=packageSize||Number(headers.get(\"Content-Length\")||0);')
    if 'totalLoaded+=download.loaded;totalSize+=download.total}' in s and 'totalSize=Math.max(totalSize,totalLoaded);' not in s:
        s = s.replace('totalLoaded+=download.loaded;totalSize+=download.total}', 'totalLoaded+=download.loaded;totalSize+=download.total}totalSize=Math.max(totalSize,totalLoaded);')
    open(p, 'w', encoding='utf-8').write(s)
except Exception as e:
    print('Failed to patch', p, e)
" "$1"
}

build_item() {
    title="$1"
    dir_name="$2"
    src_rb="$3"
    shell_file="$4"

    echo "=== Building ${title} (${DOCS_DIR}/${dir_name}) ==="
    out_dir="${DOCS_DIR}/${dir_name}"
    tmp_out="/tmp/zenoo_wasm/${dir_name}"
    mkdir -p "${out_dir}"
    rm -rf "${tmp_out}"
    mkdir -p "${tmp_out}"

    "${SPINEL_BIN}" --no-inline-hot -Ilib "${src_rb}" -c -o "${tmp_out}/app.c"
    strip_always_inline "${tmp_out}/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${tmp_out}/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${tmp_out}/index.html" \
        --shell-file "${shell_file}"

    patch_emscripten_js "${tmp_out}/index.js"
    rm -f "${tmp_out}/app.c"

    # docs/ へ一括コピー (NTFSファイル共有違反を完全回避)
    cp "${tmp_out}"/* "${out_dir}/"
    rm -rf "${tmp_out}"
    echo "-> ${title} build done!"
}

build_game()         { build_item "Survival Shooting Game" "game" "examples/game_zenoo.rb" "examples/web/shell_game.html"; }
build_gui()          { build_item "Immediate Mode GUI Demo" "gui" "examples/demo_gui_widgets.rb" "examples/web/shell_gui.html"; }
build_font()         { build_item "SDF Text & Font Demo" "font" "examples/demo_ttf_sdf_font.rb" "examples/web/shell_font.html"; }
build_vector()       { build_item "Vector Graphics Demo" "vector" "examples/demo_vector_graphics.rb" "examples/web/shell.html"; }
build_image()        { build_item "Sprite & Blend Modes Demo" "image" "examples/demo_draw_image.rb" "examples/web/shell_image.html"; }
build_atlas()        { build_item "Texture Atlas Demo" "atlas" "examples/demo_texture_atlas.rb" "examples/web/shell_atlas.html"; }
build_clip()         { build_item "Hardware Clipping Demo" "clip" "examples/demo_window_clip.rb" "examples/web/shell_clip.html"; }
build_sound()        { build_item "Audio & Sound Demo" "sound" "examples/demo_sound.rb" "examples/web/shell_sound.html"; }
build_collision()    { build_item "GJK Collision Playground" "collision" "examples/demo_collision.rb" "examples/web/shell_collision.html"; }
build_tween()        { build_item "Tween & Easing Animation" "tween" "examples/demo_tween.rb" "examples/web/shell_tween.html"; }
build_coords()       { build_item "Sprite Coords & Collision Visualizer" "coords" "examples/demo_sprite_coords.rb" "examples/web/shell_coords.html"; }
build_billiards()    { build_item "Billiards & 3D Rolling Shader Demo" "billiards" "examples/demo_billiards.rb" "examples/web/shell_billiards.html"; }
build_zero_gravity() { build_item "Zero-Gravity 2D Physics Demo" "zero_gravity" "examples/demo_zero_gravity.rb" "examples/web/shell_zero_gravity.html"; }
build_particles()    { build_item "GPU Particle Storm Demo" "particles" "examples/gpu_particles.rb" "examples/web/shell_particles.html"; }
build_danmaku()      { build_item "GPU Danmaku Storm Demo" "danmaku" "examples/demo_gpu_danmaku.rb" "examples/web/shell_danmaku.html"; }

case "$TARGET" in
    game)         build_game ;;
    gui)          build_gui ;;
    font)         build_font ;;
    vector)       build_vector ;;
    image)        build_image ;;
    atlas)        build_atlas ;;
    clip)         build_clip ;;
    sound)        build_sound ;;
    collision)    build_collision ;;
    tween)        build_tween ;;
    coords)       build_coords ;;
    billiards)    build_billiards ;;
    zero_gravity) build_zero_gravity ;;
    particles)    build_particles ;;
    danmaku)      build_danmaku ;;
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
        build_clip
        sleep 0.5
        build_sound
        sleep 0.5
        build_collision
        sleep 0.5
        build_tween
        sleep 0.5
        build_coords
        sleep 0.5
        build_billiards
        sleep 0.5
        build_zero_gravity
        sleep 0.5
        build_particles
        sleep 0.5
        build_danmaku
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [game|gui|font|vector|image|atlas|clip|sound|collision|tween|coords|billiards|zero_gravity|particles|danmaku|all]"
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
echo " Clip     : ${DOCS_DIR}/clip/index.html"
echo " Sound    : ${DOCS_DIR}/sound/index.html"
echo " Collision: ${DOCS_DIR}/collision/index.html"
echo " Tween    : ${DOCS_DIR}/tween/index.html"
echo " Coords   : ${DOCS_DIR}/coords/index.html"
echo " Billiards: ${DOCS_DIR}/billiards/index.html"
echo " Zero-Grav: ${DOCS_DIR}/zero_gravity/index.html"
echo " Particles: ${DOCS_DIR}/particles/index.html"
echo " Danmaku  : ${DOCS_DIR}/danmaku/index.html"
echo "=========================================================="

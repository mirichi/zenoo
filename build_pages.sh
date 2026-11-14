#!/usr/bin/env bash
set -e

# ====================================================
# Zenoo GitHub Pages 一括ビルドスクリプト
# Game (Survival Shooting) & GUI Demo を別リポジトリ (../zenoo-pages/examples) に生成
# ====================================================

START_TIME=$(date +%s)

# 0. 引数解析 (-j N / --jobs N / ターゲット名)
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jobs)
            JOBS="${2:?Error: $1 requires a numeric argument}"
            shift 2
            ;;
        -j*)
            JOBS="${1#-j}"
            shift
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done
TARGET="${TARGET:-all}"

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

# ビルドモード判定 (デフォルト: release = -O2)
#   BUILD_MODE=dev  (または fast) : -O1 (Clang最適化を軽量化し、ビルド時間を短縮)
#   BUILD_MODE=release            : -O2 (ビルド速度と実行速度のバランスに優れた標準最適化, デフォルト)
#   BUILD_MODE=max  (または o3)   : -O3 (最高速の実行速度)
case "${BUILD_MODE:-release}" in
    dev|fast)
        OPT_LEVEL="${OPT_LEVEL:--O1}"
        BUILD_MODE_NAME="dev"
        ;;
    max|o3)
        OPT_LEVEL="${OPT_LEVEL:--O3}"
        BUILD_MODE_NAME="max"
        ;;
    release|*)
        OPT_LEVEL="${OPT_LEVEL:--O2}"
        BUILD_MODE_NAME="release"
        ;;
esac
DEBUG_FLAGS="${DEBUG_FLAGS:--g0}"

# 並列数決定 (C単体コンパイルはコア数、巨大app.cのemcc並列は実測RSS(~400MB)に基づく安全上限も考慮)
CPU_CORES=$(nproc 2>/dev/null || echo 4)
MEM_MB=$(awk '/MemTotal/ {printf "%d", $2 / 1024}' /proc/meminfo 2>/dev/null || echo 8192)
MEM_GB=$(( MEM_MB / 1024 ))
SAFE_MEM_JOBS=$(( MEM_MB / 900 ))
[ "$SAFE_MEM_JOBS" -lt 1 ] && SAFE_MEM_JOBS=1
DEFAULT_DEMO_JOBS=$(( CPU_CORES < SAFE_MEM_JOBS ? CPU_CORES : SAFE_MEM_JOBS ))
C_JOBS="${C_JOBS:-${CPU_CORES}}"
DEMO_JOBS="${JOBS:-${DEFAULT_DEMO_JOBS}}"
if [ "$DEMO_JOBS" -lt 1 ] 2>/dev/null; then
    DEMO_JOBS=1
fi

PAGES_ROOT="${PAGES_ROOT:-../zenoo-pages}"
DOCS_DIR="${PAGES_ROOT}/examples"
# Linux ネイティブFS側にキャッシュを配置し、WSL2上の NTFS(/mnt/c) への I/O 遅延を回避
CACHE_DIR="${CACHE_DIR:-${HOME}/.cache/zenoo_wasm/${OPT_LEVEL#-}}"

WORK_ROOT="/tmp/zenoo_wasm_$$"
STAGE_DIR="${WORK_ROOT}/stage"
LOG_DIR="${WORK_ROOT}/logs"
OUT_ROOT="${WORK_ROOT}/out"

cleanup() {
    rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT

mkdir -p "${CACHE_DIR}/rt" "${CACHE_DIR}/regexp" "${STAGE_DIR}" "${LOG_DIR}" "${OUT_ROOT}"

# デモ一覧定義 ("target|title|dir_name|src_rb|shell_file")
DEMOS=(
    "game|Survival Shooting Game|game|examples/game_zenoo.rb|examples/web/shell_game.html"
    "gui|Retained Mode GUI Showcase Demo|gui|examples/demo_gui_widgets.rb|examples/web/shell_gui.html"
    "font|SDF Text & Font Demo|font|examples/demo_ttf_sdf_font.rb|examples/web/shell_font.html"
    "vector|Vector Graphics Demo|vector|examples/demo_vector_graphics.rb|examples/web/shell.html"
    "image|Sprite & Blend Modes Demo|image|examples/demo_draw_image.rb|examples/web/shell_image.html"
    "atlas|Texture Atlas Demo|atlas|examples/demo_texture_atlas.rb|examples/web/shell_atlas.html"
    "clip|Hardware Clipping Demo|clip|examples/demo_window_clip.rb|examples/web/shell_clip.html"
    "sound|Audio & Sound Demo|sound|examples/demo_sound.rb|examples/web/shell_sound.html"
    "collision|GJK Collision Playground|collision|examples/demo_collision.rb|examples/web/shell_collision.html"
    "tween|Tween & Easing Animation|tween|examples/demo_tween.rb|examples/web/shell_tween.html"
    "coords|Sprite Coords & Collision Visualizer|coords|examples/demo_sprite_coords.rb|examples/web/shell_coords.html"
    "billiards|Billiards & 3D Rolling Shader Demo|billiards|examples/demo_billiards.rb|examples/web/shell_billiards.html"
    "zero_gravity|Zero-Gravity 2D Physics Demo|zero_gravity|examples/demo_zero_gravity.rb|examples/web/shell_zero_gravity.html"
    "particles|GPU Particle Storm Demo|particles|examples/gpu_particles.rb|examples/web/shell_particles.html"
    "danmaku|GPU Danmaku Storm Demo|danmaku|examples/demo_gpu_danmaku.rb|examples/web/shell_danmaku.html"
    "articulated|Articulated Sprite & Hierarchy Demo|articulated|examples/demo_articulated_sprite.rb|examples/web/shell_articulated.html"
    "skinned_mesh|2D SkinnedMesh & Bone Demo|skinned_mesh|examples/demo_skinned_mesh.rb|examples/web/shell_skinned_mesh.html"
    "canvas_mesh|Canvas to Mesh & Vector Sprites|canvas_mesh|examples/demo_canvas_mesh.rb|examples/web/shell_canvas_mesh.html"
    "mesh_deform|2D Mesh Deformation & 2-Stream Instancing|mesh_deform|examples/demo_mesh_deform.rb|examples/web/shell_mesh_deform.html"
    "scene|Scene & Transition Demo|scene|examples/demo_scene.rb|examples/web/shell_scene.html"
    "sound_generator|Retro Sound Generator|sound_generator|tools/sound_generator.rb|examples/web/shell_sound_generator.html"
    "particle_editor|GPU Particle Designer & Editor|particle_editor|tools/particle_editor.rb|examples/web/shell_particle_editor.html"
    "sprite_animation|Diagonal Sprite & Multi-Layer Tilemap|sprite_animation|examples/demo_sprite_animation.rb|examples/web/shell_sprite_animation.html"
    "procedural_runner|Procedural Runner & Sword IK Demo|procedural_runner|examples/demo_procedural_runner.rb|examples/web/shell_procedural_runner.html"
)

# ターゲット検証 (all または定義済みターゲットか)
if [ "$TARGET" != "all" ]; then
    target_found=0
    for entry in "${DEMOS[@]}"; do
        IFS='|' read -r t _ <<< "$entry"
        if [ "$t" = "$TARGET" ]; then
            target_found=1
            break
        fi
    done
    if [ "$target_found" -eq 0 ]; then
        echo "Unknown target: $TARGET"
        valid_targets=""
        for entry in "${DEMOS[@]}"; do
            IFS='|' read -r t _ <<< "$entry"
            valid_targets="${valid_targets}${valid_targets:+|}${t}"
        done
        echo "Usage: $0 [-j N] [${valid_targets}|all]"
        exit 1
    fi
fi

for entry in "${DEMOS[@]}"; do
    IFS='|' read -r _ _ dir_name _ _ <<< "$entry"
    mkdir -p "${DOCS_DIR}/${dir_name}"
done

echo "=== [1/5] Setting up GitHub Pages structure ==="
# Jekyll 処理を無効化 (Wasmファイルの配信を確実にする)
touch "${PAGES_ROOT}/.nojekyll"
touch "${DOCS_DIR}/.nojekyll"
# ポータルページを配置
cp examples/web/portal.html "${DOCS_DIR}/index.html"
# シェルHTMLを同期 (ターゲット指定時はそのデモのみ、未指定/all時は全体)
if [ "$TARGET" != "all" ]; then
    DOCS_DIR="${DOCS_DIR}" python3 tools/generate_shells.py "$TARGET"
else
    DOCS_DIR="${DOCS_DIR}" python3 tools/generate_shells.py
fi

# lib/ / ext/ / assets/ / examples/ / tools/ / include/ を Linux 側 /tmp に1回だけステージング (並列ジョブの NTFS I/O 削減)
cp -a assets lib ext examples tools include "${STAGE_DIR}/"

echo "=== Build Mode: ${BUILD_MODE_NAME} (${OPT_LEVEL}) | Demo Jobs: ${DEMO_JOBS} (CPU: ${CPU_CORES}, Mem: ${MEM_GB}GB) ==="
echo "=== Cache Dir: ${CACHE_DIR} ==="

# 並列バックグラウンドジョブ用ヘルパー (C単体コンパイル向け)
C_PIDS=()
wait_c_slot() {
    while [ "${#C_PIDS[@]}" -ge "$C_JOBS" ]; do
        local done_pid=""
        if ! wait -n -p done_pid "${C_PIDS[@]}"; then
            echo "Error: C compilation job (PID: ${done_pid}) failed."
            for p in "${C_PIDS[@]}"; do
                kill "$p" 2>/dev/null || true
            done
            exit 1
        fi
        local next_pids=()
        for p in "${C_PIDS[@]}"; do
            [ "$p" != "$done_pid" ] && next_pids+=("$p")
        done
        C_PIDS=("${next_pids[@]}")
    done
}

flush_c_jobs() {
    for p in "${C_PIDS[@]}"; do
        if ! wait "$p"; then
            echo "Error: C compilation job (PID: ${p}) failed."
            exit 1
        fi
    done
    C_PIDS=()
}

echo "=== [2/5] Building Common Spinel Runtime for Wasm ==="
rt_updated=0
for f in "${SPINEL_DIR}"/lib/*.c; do
    bn=$(basename "$f" .c)
    obj="${CACHE_DIR}/rt/${bn}.o"
    if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
        wait_c_slot
        emcc -c "${OPT_LEVEL}" -DSP_ONE_STRING -I"${SPINEL_DIR}/lib" -I"${SPINEL_DIR}/lib/regexp" "$f" -o "$obj" &
        C_PIDS+=($!)
        rt_updated=1
    fi
done

for f in "${SPINEL_DIR}"/lib/regexp/*.c; do
    bn=$(basename "$f" .c)
    obj="${CACHE_DIR}/regexp/${bn}.o"
    if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
        wait_c_slot
        emcc -c "${OPT_LEVEL}" -DSP_ONE_STRING -I"${SPINEL_DIR}/lib/regexp" -I"${SPINEL_DIR}/lib/regexp/shim" "$f" -o "$obj" &
        C_PIDS+=($!)
        rt_updated=1
    fi
done
flush_c_jobs

if [ "$rt_updated" -eq 1 ] || [ ! -f "${CACHE_DIR}/libspinel_rt.a" ]; then
    emar rcs "${CACHE_DIR}/libspinel_rt.a" "${CACHE_DIR}/rt"/*.o "${CACHE_DIR}/regexp"/*.o
fi

echo "=== [3/5] Building Common Zenoo C Kernel ==="
needs_c_rebuild() {
    local src="$1"
    local obj="$2"
    [ ! -f "$obj" ] && return 0
    [ "$src" -nt "$obj" ] && return 0
    local h
    for h in include/*.h ext/spinel/*.h; do
        [ -e "$h" ] && [ "$h" -nt "$obj" ] && return 0
    done
    return 1
}

build_c_kernel_obj() {
    local src="$1"
    local obj="$2"
    if needs_c_rebuild "$src" "$obj"; then
        wait_c_slot
        emcc -c "${OPT_LEVEL}" -Iinclude -Iext/spinel -I"${SPINEL_DIR}/lib" "$src" -o "$obj" &
        C_PIDS+=($!)
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
flush_c_jobs

COMMON_EMCC_BASE_FLAGS=(
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
    -s EXPORTED_FUNCTIONS="['_main','_zen_push_char','_zen_push_touch']"
    -fmacro-prefix-map="${PWD}"=.
    -fdebug-prefix-map="${PWD}"=.
    -fmacro-prefix-map="${STAGE_DIR}"=.
    -fdebug-prefix-map="${STAGE_DIR}"=.
    -I"${STAGE_DIR}/include" -I"${STAGE_DIR}/ext/spinel" -I"${SPINEL_DIR}/lib"
)

COMMON_EMCC_FLAGS=(
    "${COMMON_EMCC_BASE_FLAGS[@]}"
    --preload-file "${STAGE_DIR}/assets@/assets"
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
    local title="$1"
    local dir_name="$2"
    local src_rb="$3"
    local shell_file="$4"

    local t0
    t0=$(date +%s)
    echo "=== Building ${title} (${DOCS_DIR}/${dir_name}) ==="
    local out_dir="${DOCS_DIR}/${dir_name}"
    local tmp_out="${OUT_ROOT}/${dir_name}"
    mkdir -p "${out_dir}"
    rm -rf "${tmp_out}"
    mkdir -p "${tmp_out}"

    "${SPINEL_BIN}" --no-inline-hot -I"${STAGE_DIR}/lib" "${STAGE_DIR}/${src_rb}" -c -o "${tmp_out}/app.c"
    strip_always_inline "${tmp_out}/app.c"

    emcc "${COMMON_EMCC_FLAGS[@]}" \
        "${tmp_out}/app.c" \
        "${COMMON_OBJS[@]}" \
        -o "${tmp_out}/index.html" \
        --shell-file "${STAGE_DIR}/${shell_file}"

    patch_emscripten_js "${tmp_out}/index.js"
    rm -f "${tmp_out}/app.c"

    # docs/ へ一括コピー (NTFSファイル共有違反を完全回避)
    cp "${tmp_out}"/* "${out_dir}/"
    rm -rf "${tmp_out}"
    local t1
    t1=$(date +%s)
    echo "-> ${title} build done! ($((t1 - t0))s)"
}

echo "=== [4/5] Building WebAssembly Demos ==="
if [ "$TARGET" = "all" ]; then
    # 並列リンク前に Emscripten システムライブラリ (USE_GLFW=3 等) を確実にウォームアップ
    if [ ! -f "${CACHE_DIR}/.syslibs_ready" ]; then
        echo "=== Pre-building Emscripten system libraries ==="
        probe_dir="${WORK_ROOT}/syslib_probe"
        mkdir -p "${probe_dir}"
        echo 'int main(void) { return 0; } void zen_push_char(void) {} void zen_push_touch(void) {}' > "${probe_dir}/probe.c"
        emcc "${COMMON_EMCC_BASE_FLAGS[@]}" "${probe_dir}/probe.c" -o "${probe_dir}/probe.js"
        rm -rf "${probe_dir}"
        touch "${CACHE_DIR}/.syslibs_ready"
    fi

    declare -A PID_TO_TITLE
    declare -A PID_TO_LOG
    declare -A PID_TO_START
    DEMO_PIDS=()
    total_demos="${#DEMOS[@]}"
    idx=0
    done_count=0

    reap_one_demo() {
        local done_pid=""
        local rc=0
        if wait -n -p done_pid "${DEMO_PIDS[@]}"; then
            rc=0
        else
            rc=$?
        fi
        local t_done
        t_done=$(date +%s)
        local title="${PID_TO_TITLE[$done_pid]}"
        local log_file="${PID_TO_LOG[$done_pid]}"
        local t_start="${PID_TO_START[$done_pid]}"
        done_count=$((done_count + 1))

        local next_pids=()
        for p in "${DEMO_PIDS[@]}"; do
            [ "$p" != "$done_pid" ] && next_pids+=("$p")
        done
        DEMO_PIDS=("${next_pids[@]}")

        if [ "$rc" -ne 0 ]; then
            echo ""
            echo "!!! [FAIL] (${done_count}/${total_demos}) ${title} (exit=${rc}) !!!"
            echo "--- Build Log: ${title} ---"
            cat "${log_file}"
            echo "----------------------------------------"
            for p in "${DEMO_PIDS[@]}"; do
                kill "$p" 2>/dev/null || true
            done
            wait "${DEMO_PIDS[@]}" 2>/dev/null || true
            exit "$rc"
        fi
        echo "[DONE ${done_count}/${total_demos}] ${title} ($((t_done - t_start))s)"
    }

    for entry in "${DEMOS[@]}"; do
        IFS='|' read -r _ title dir_name src_rb shell_file <<< "$entry"
        while [ "${#DEMO_PIDS[@]}" -ge "$DEMO_JOBS" ]; do
            reap_one_demo
        done
        idx=$((idx + 1))
        log_file="${LOG_DIR}/${dir_name}.log"
        echo "[START ${idx}/${total_demos}] ${title}..."
        ( build_item "$title" "$dir_name" "$src_rb" "$shell_file" ) > "${log_file}" 2>&1 &
        pid=$!
        DEMO_PIDS+=("$pid")
        PID_TO_TITLE["$pid"]="$title"
        PID_TO_LOG["$pid"]="$log_file"
        PID_TO_START["$pid"]=$(date +%s)
    done

    while [ "${#DEMO_PIDS[@]}" -gt 0 ]; do
        reap_one_demo
    done
else
    for entry in "${DEMOS[@]}"; do
        IFS='|' read -r t title dir_name src_rb shell_file <<< "$entry"
        if [ "$t" = "$TARGET" ]; then
            build_item "$title" "$dir_name" "$src_rb" "$shell_file"
            break
        fi
    done
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "=== [5/5] Summary ==="
echo ""
echo "=========================================================="
echo " Showcase build complete! (target: $TARGET, elapsed: ${ELAPSED}s)"
echo " Portal   : ${DOCS_DIR}/index.html"
echo " TopDown  : ${DOCS_DIR}/sprite_animation/index.html"
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
echo " Articulated: ${DOCS_DIR}/articulated/index.html"
echo " SkinnedMesh: ${DOCS_DIR}/skinned_mesh/index.html"
echo " CanvasMesh : ${DOCS_DIR}/canvas_mesh/index.html"
echo " MeshDeform : ${DOCS_DIR}/mesh_deform/index.html"
echo " Scene      : ${DOCS_DIR}/scene/index.html"
echo " SFX Gen    : ${DOCS_DIR}/sound_generator/index.html"
echo " ParticleEd : ${DOCS_DIR}/particle_editor/index.html"
echo " ProcRunner : ${DOCS_DIR}/procedural_runner/index.html"
echo "=========================================================="

#!/usr/bin/env bash
set -e

# ====================================================
# Zenoo サンプル専用 Wasm ビルドスクリプト
# samples/*.rb をビルドし docs/samples/<name>/ に配置
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

DOCS_SAMPLES_DIR="docs/samples"
CACHE_DIR="build/wasm_cache"
mkdir -p "${DOCS_SAMPLES_DIR}"
mkdir -p "${CACHE_DIR}/rt"
mkdir -p "${CACHE_DIR}/regexp"

# サンプル一覧目次 (docs/samples/index.html) を更新
python3 tools/generate_sample_pages.py

# ビルドモード判定 (サイズより速度優先)
case "${BUILD_MODE:-dev}" in
    release)
        OPT_LEVEL="-O2"
        ;;
    max|o3)
        OPT_LEVEL="-O3"
        ;;
    dev|fast|*)
        OPT_LEVEL="-O1"
        ;;
esac
DEBUG_FLAGS="${DEBUG_FLAGS:--g0}"

# 2. Spinel 共通ランタイムのキャッシュ確認
if [ ! -f "${CACHE_DIR}/libspinel_rt.a" ]; then
    echo "=== Building Common Spinel Runtime for Wasm ==="
    for f in "${SPINEL_DIR}"/lib/*.c; do
        bn=$(basename "$f" .c)
        obj="${CACHE_DIR}/rt/${bn}.o"
        if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
            emcc -c "${OPT_LEVEL}" -DSP_ONE_STRING -I"${SPINEL_DIR}/lib" -I"${SPINEL_DIR}/lib/regexp" "$f" -o "$obj"
        fi
    done
    for f in "${SPINEL_DIR}"/lib/regexp/*.c; do
        bn=$(basename "$f" .c)
        obj="${CACHE_DIR}/regexp/${bn}.o"
        if [ ! -f "$obj" ] || [ "$f" -nt "$obj" ]; then
            emcc -c "${OPT_LEVEL}" -DSP_ONE_STRING -I"${SPINEL_DIR}/lib/regexp" -I"${SPINEL_DIR}/lib/regexp/shim" "$f" -o "$obj"
        fi
    done
    emar rcs "${CACHE_DIR}/libspinel_rt.a" "${CACHE_DIR}/rt"/*.o "${CACHE_DIR}/regexp"/*.o
fi

# 3. Zenoo C カーネル共通オブジェクトのキャッシュ確認
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
    -s EXPORTED_FUNCTIONS="['_main','_zen_push_char','_zen_push_touch']"
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

build_single_sample() {
    name="$1"
    src_rb="samples/${name}.rb"
    shell_file="tools/templates/sample_shell.html"
    out_dir="${DOCS_SAMPLES_DIR}/${name}"
    tmp_out="/tmp/zenoo_sample_wasm/${name}"

    if [ ! -f "${src_rb}" ]; then
        echo "Error: Sample file not found: ${src_rb}"
        return 1
    fi

    echo "=== Building Sample: ${name} ==="
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
    python3 tools/generate_sample_pages.py --inject "${tmp_out}/index.html" "${src_rb}"
    rm -f "${tmp_out}/app.c"

    cp "${tmp_out}"/* "${out_dir}/"
    rm -rf "${tmp_out}"
    echo "-> Sample ${name} build done: ${out_dir}/index.html"
}

TARGET="${1:-all}"

if [ "$TARGET" = "all" ]; then
    echo "=== Building ALL Samples ==="
    for sample_name in $(python3 tools/generate_sample_pages.py --list); do
        build_single_sample "$sample_name"
    done
else
    clean_target=$(basename "$TARGET" .rb)
    build_single_sample "$clean_target"
fi

echo "=== All requested samples built successfully! ==="

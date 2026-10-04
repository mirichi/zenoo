#!/usr/bin/env bash
set -e

SPINEL_BIN="${HOME}/spinel/bin/spinel"
if [ ! -f "$SPINEL_BIN" ]; then
    SPINEL_BIN="spinel"
fi

echo "=== [1/2] Building Zenoo Spinel C Archive (libzenoo_spinel.a) ==="
mkdir -p build
gcc -O2 -fPIC -Iinclude -Iext/spinel -I${HOME}/spinel/lib -c src/glad.c -o build/glad.o
gcc -O2 -fPIC -Iinclude -Iext/spinel -I${HOME}/spinel/lib -c src/zenoo_core.c -o build/zenoo_core.o
gcc -O2 -fPIC -Iinclude -Iext/spinel -I${HOME}/spinel/lib -c src/zenoo_gfx.c -o build/zenoo_gfx.o
gcc -O2 -fPIC -Iinclude -Iext/spinel -I${HOME}/spinel/lib -c src/zenoo_font.c -o build/zenoo_font.o
gcc -O2 -fPIC -Iinclude -Iext/spinel -I${HOME}/spinel/lib -c src/zenoo_audio.c -o build/zenoo_audio.o
gcc -O2 -fPIC -Iinclude -Iext/spinel -I${HOME}/spinel/lib -c ext/spinel/zenoo_spinel.c -o build/zenoo_spinel.o
ar rcs build/libzenoo_spinel.a build/glad.o build/zenoo_core.o build/zenoo_gfx.o build/zenoo_font.o build/zenoo_audio.o build/zenoo_spinel.o
echo "  -> build/libzenoo_spinel.a created successfully."

TARGET_RB="${1:-examples/demo_spinel_interactive.rb}"
OUT_BIN="build/$(basename "${TARGET_RB}" .rb)"

echo "=== [2/2] AOT Compiling Ruby app: ${TARGET_RB} ==="
"$SPINEL_BIN" -Ilib "${TARGET_RB}" -o "${OUT_BIN}" \
    --link build/libzenoo_spinel.a \
    --link -lglfw \
    --link -lGL \
    --link -lpthread \
    --link -ldl \
    --link -lm

echo "  -> Compiled binary created: ${OUT_BIN}"
echo "=== Build Complete! Run with: ./${OUT_BIN} ==="

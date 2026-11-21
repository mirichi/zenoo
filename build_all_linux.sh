#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

SPINEL_BIN="${HOME}/spinel/bin/spinel"
if [ ! -f "$SPINEL_BIN" ]; then
    SPINEL_BIN="spinel"
fi

SDL_INC=""
SDL_LINK_FLAGS=()
if [ -d "${HOME}/.local/include/SDL3" ]; then
    SDL_INC="-I${HOME}/.local/include"
fi
if [ -d "${HOME}/.local/lib/x86_64-linux-gnu" ]; then
    SDL_LINK_FLAGS+=(--link "-L${HOME}/.local/lib/x86_64-linux-gnu" --link "-Wl,--disable-new-dtags,-rpath,${HOME}/.local/lib/x86_64-linux-gnu")
fi

echo "=== [1/2] Building Zenoo Spinel C Archive (libzenoo_spinel.a) ==="
mkdir -p build
rm -f build/libzenoo_spinel.a build/zenoo_core.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/glad.c -o build/glad.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_window.c -o build/zenoo_window.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_input.c -o build/zenoo_input.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_vibration.c -o build/zenoo_vibration.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_image.c -o build/zenoo_image.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_gfx.c -o build/zenoo_gfx.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_font.c -o build/zenoo_font.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_audio.c -o build/zenoo_audio.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_batch.c -o build/zenoo_batch.o
gcc -O2 -fPIC -Iinclude ${SDL_INC} -c src/zenoo_ffi_shim.c -o build/zenoo_ffi_shim.o
ar rcs build/libzenoo_spinel.a build/glad.o build/zenoo_window.o build/zenoo_input.o build/zenoo_vibration.o build/zenoo_image.o build/zenoo_gfx.o build/zenoo_font.o build/zenoo_audio.o build/zenoo_batch.o build/zenoo_ffi_shim.o
echo "  -> build/libzenoo_spinel.a created successfully."

DEMOS=(
    "examples/game_zenoo.rb"
    "examples/demo_vector_graphics.rb"
    "examples/demo_draw_image.rb"
    "examples/demo_texture_atlas.rb"
    "examples/demo_window_clip.rb"
    "examples/demo_gui_widgets.rb"
    "examples/demo_ttf_sdf_font.rb"
    "examples/demo_sound.rb"
    "examples/demo_collision.rb"
    "examples/demo_vibration.rb"
)

echo "=== [2/2] AOT Compiling All Demos for Linux ==="
for demo in "${DEMOS[@]}"; do
    out_bin="build/$(basename "${demo}" .rb)"
    echo "--- Compiling ${demo} -> ${out_bin} ---"
    "$SPINEL_BIN" --no-inline-hot -Ilib "${demo}" -o "${out_bin}" \
        --link build/libzenoo_spinel.a \
        "${SDL_LINK_FLAGS[@]}" \
        --link -lSDL3 \
        --link -lGL \
        --link -lpthread \
        --link -ldl \
        --link -lm
    echo "  -> Success: ${out_bin}"
done

echo "=== All Linux Demos Built Successfully! ==="
ls -lh build/

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Zenoo Shell Generator
examples/web/shell_template.html を元に、全デモ用の shell_*.html を一括生成します。
アスペクト比固定を全廃し、全画面制御やスタイルを完全統一します。
"""

import os
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_PATH = os.path.join(BASE_DIR, 'examples', 'web', 'shell_template.html')
WEB_DIR = os.path.join(BASE_DIR, 'examples', 'web')

DEMOS = {
    "shell.html": {
        "title": "Zenoo Vector Graphics Showcase (Spinel Wasm)",
        "heading": "ZENOO VECTOR GRAPHICS SHOWCASE",
        "desc": "HTML5 Canvas 2D Style API &amp; Shader Gradients | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_vector_graphics.rb",
        "menu": False
    },
    "shell_articulated.html": {
        "title": "Zenoo 2D Articulated Sprite &amp; Hierarchical Collision (Spinel Wasm)",
        "heading": "Zenoo 2D Articulated Sprite &amp; Hierarchy",
        "desc": "Pure Ruby + WebGL 2.0 (Spinel AOT) | 2Dボーン・親子階層コライダー同期",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_articulated_sprite.rb",
        "menu": False
    },
    "shell_atlas.html": {
        "title": "Zenoo Texture Atlas Showcase (Spinel Wasm)",
        "heading": "ZENOO TEXTURE ATLAS &amp; SUB-IMAGE SHOWCASE",
        "desc": "Image#sub_image &amp; Auto-Batching (1 Draw Call) | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_texture_atlas.rb",
        "menu": False
    },
    "shell_billiards.html": {
        "title": "Zenoo Billiards & 3D Rolling Shader (Spinel Wasm)",
        "heading": "ZENOO BILLIARDS &amp; 3D ROLLING SHADER",
        "desc": "MTV (Penetration) 2D 剛体物理 + 3D クオータニオン転がりシェーダー",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_billiards.rb",
        "menu": False
    },
    "shell_canvas_mesh.html": {
        "title": "Zenoo Canvas to Mesh &amp; Vector Sprites (Spinel Wasm)",
        "heading": "Zenoo Canvas to Mesh &amp; Vector Sprites",
        "desc": "Pure Ruby + WebGL 2.0 (Spinel AOT) | Canvas 描画の VBO メッシュ化・1ドローコール大量バッチ描画",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_canvas_mesh.rb",
        "menu": False
    },
    "shell_clip.html": {
        "title": "Zenoo Hardware Clipping Showcase (Spinel Wasm)",
        "heading": "ZENOO HARDWARE CLIPPING SHOWCASE",
        "desc": "Window.clip (local: false vs local: true) | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_window_clip.rb",
        "menu": False
    },
    "shell_collision.html": {
        "title": "Zenoo GJK Collision Playground (Spinel Wasm)",
        "heading": "ZENOO GJK COLLISION PLAYGROUND",
        "desc": "Pure Ruby GJK Algorithm × Spinel AOT Transpiler × WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_collision.rb",
        "menu": False
    },
    "shell_coords.html": {
        "title": "Zenoo Sprite &amp; Collision Coords Visualizer (Spinel Wasm)",
        "heading": "ZENOO SPRITE &amp; COLLISION COORDS VISUALIZER",
        "desc": "Anchor / Pivot / Offset / Position 実機シミュレーター",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_sprite_coords.rb",
        "menu": False
    },
    "shell_danmaku.html": {
        "title": "Zenoo GPU Danmaku Storm (Spinel Wasm)",
        "heading": "Zenoo: GPU Danmaku Storm (75,000 Bullets)",
        "desc": "WebGL 2.0 GPU Instancing &bull; Annular Sector Collision Detection &bull; Spinel AOT Wasm",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_gpu_danmaku.rb",
        "menu": False
    },
    "shell_font.html": {
        "title": "Zenoo SDF Text &amp; Font Showcase (Spinel Wasm)",
        "heading": "ZENOO SDF TEXT &amp; FONT SHOWCASE",
        "desc": "SDF Dynamic Atlas &amp; High Quality Typography | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_ttf_sdf_font.rb",
        "menu": False
    },
    "shell_game.html": {
        "title": "Zenoo Survival Shooting (Spinel Wasm)",
        "heading": "ZENOO SURVIVAL SHOOTING",
        "desc": "Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/game_zenoo.rb",
        "menu": True
    },
    "shell_gui.html": {
        "title": "Zenoo Extended GUI Showcase (Spinel Wasm)",
        "heading": "ZENOO EXTENDED GUI &amp; RESIZABLE WINDOW",
        "desc": "Pure Ruby Immediate Mode GUI System | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_gui_widgets.rb",
        "menu": False
    },
    "shell_image.html": {
        "title": "Zenoo Sprite & Blend Modes Showcase (Spinel Wasm)",
        "heading": "Zenoo: Sprite &amp; Blend Modes Showcase",
        "desc": "Rotation / Scale / Flip / Pivot / offset_mode / Alpha / :alpha, :add, :multiply Blend",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_draw_image.rb",
        "menu": False
    },
    "shell_mesh_deform.html": {
        "title": "Zenoo 2D Mesh Deformation &amp; 2-Stream Instancing (Spinel Wasm)",
        "heading": "Zenoo 2D Mesh Deformation &amp; 2-Stream Instancing",
        "desc": "Pure Ruby + WebGL 2.0 (Spinel AOT) | 2ストリームVBO &amp; Mesh変形API",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_mesh_deform.rb",
        "menu": False
    },
    "shell_particles.html": {
        "title": "Zenoo GPU Particle Storm (Spinel Wasm)",
        "heading": "Zenoo: GPU Particle Storm",
        "desc": "WebGL 2.0 GPU Instancing &bull; 100,000+ Particles &bull; Spinel AOT Wasm",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/gpu_particles.rb",
        "menu": False
    },
    "shell_scene.html": {
        "title": "Zenoo Scene & Transition Demo (Spinel Wasm)",
        "heading": "ZENOO SCENE &amp; TRANSITION DEMO",
        "desc": "Stack-based Scenes, Transitions, Below Freeze/Live | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_scene.rb",
        "menu": False
    },
    "shell_skinned_mesh.html": {
        "title": "Zenoo 2D SkinnedMesh &amp; Bone Demo (Spinel Wasm)",
        "heading": "Zenoo 2D SkinnedMesh &amp; Bone",
        "desc": "Pure Ruby + WebGL 2.0 (Spinel AOT) | 頂点シェーダースキニング &amp; 重みマップ (Weight Map)",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_skinned_mesh.rb",
        "menu": False
    },
    "shell_sound.html": {
        "title": "Zenoo Audio & Sound Demo (Spinel Wasm)",
        "heading": "Zenoo Audio & Sound Engine",
        "desc": "miniaudio + stb_vorbis + SoundEffect (PCM Synthesis) on WebAssembly",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_sound.rb",
        "menu": False
    },
    "shell_sound_generator.html": {
        "title": "Zenoo Retro SE Synthesizer & Generator (Spinel Wasm)",
        "heading": "ZENOO RETRO SOUND EFFECT GENERATOR",
        "desc": "8-bit / Arcade Sound Synthesizer &amp; Real-time Waveform Scope | Powered by Spinel AOT",
        "src": "https://github.com/mirichi/zenoo/blob/master/tools/sound_generator.rb",
        "menu": False
    },
    "shell_sprite_animation.html": {
        "title": "Zenoo Diagonal Animated Sprite &amp; Multi-Layer Tilemap (Spinel Wasm)",
        "heading": "ZENOO DIAGONAL SPRITE &amp; MULTI-LAYER TILEMAP",
        "desc": "斜め4方向スプライト (右下/右上) &amp; 行単位多層YソートTilemap | Powered by Spinel AOT",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_sprite_animation.rb",
        "menu": False
    },
    "shell_tween.html": {
        "title": "Zenoo Tween & Easing Animation (Spinel Wasm)",
        "heading": "ZENOO TWEEN &amp; EASING ANIMATION",
        "desc": "Fluid Method Chaining &amp; Event Triggering × Spinel AOT Transpiler × WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_tween.rb",
        "menu": False
    },
    "shell_window.html": {
        "title": "Zenoo Multi-Window &amp; Occlusion Showcase (Spinel Wasm)",
        "heading": "ZENOO MULTI-WINDOW &amp; OCCLUSION SHOWCASE",
        "desc": "GUI.window Floating Windows &amp; Hardware Clipping | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_new_features.rb",
        "menu": False
    },
    "shell_zero_gravity.html": {
        "title": "Zenoo Zero-Gravity Immediate-Mode Physics (Spinel Wasm)",
        "heading": "ZENOO ZERO-GRAVITY 2D RIGID BODY PHYSICS",
        "desc": "無重力 2D 剛体物理シミュレーション (多角形・楕円・OBB・カプセル)",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_zero_gravity.rb",
        "menu": False
    }
}

MENU_BUTTON_HTML = '<button class="btn btn-menu" id="btn-menu">MENU (右クリック/ESC)</button>'

def generate_all():
    if not os.path.exists(TEMPLATE_PATH):
        print(f"Error: Template not found at {TEMPLATE_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(TEMPLATE_PATH, 'r', encoding='utf-8') as f:
        template = f.read()

    count = 0
    for filename, meta in DEMOS.items():
        out_path = os.path.join(WEB_DIR, filename)
        extra_btn = MENU_BUTTON_HTML if meta.get("menu") else ""
        
        content = template
        content = content.replace("{{TITLE}}", meta["title"])
        content = content.replace("{{HEADING}}", meta["heading"])
        content = content.replace("{{DESCRIPTION}}", meta["desc"])
        content = content.replace("{{SOURCE_URL}}", meta["src"])
        content = content.replace("{{EXTRA_BUTTONS}}", extra_btn)

        with open(out_path, 'w', encoding='utf-8') as f:
            f.write(content)
        count += 1

    print(f"Successfully generated {count} shell HTML files from shell_template.html!")

if __name__ == "__main__":
    generate_all()

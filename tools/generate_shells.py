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
DOCS_DIR = os.environ.get('DOCS_DIR') or os.path.join(os.path.dirname(BASE_DIR), 'zenoo-pages', 'examples')

DOCS_MAP = {
    "shell.html": "vector",
    "shell_articulated.html": "articulated",
    "shell_atlas.html": "atlas",
    "shell_billiards.html": "billiards",
    "shell_canvas_mesh.html": "canvas_mesh",
    "shell_clip.html": "clip",
    "shell_collision.html": "collision",
    "shell_coords.html": "coords",
    "shell_danmaku.html": "danmaku",
    "shell_font.html": "font",
    "shell_game.html": "game",
    "shell_gui.html": "gui",
    "shell_image.html": "image",
    "shell_mesh_deform.html": "mesh_deform",
    "shell_particle_editor.html": "particle_editor",
    "shell_particles.html": "particles",
    "shell_procedural_runner.html": "procedural_runner",
    "shell_scene.html": "scene",
    "shell_skinned_mesh.html": "skinned_mesh",
    "shell_sound.html": "sound",
    "shell_sound_generator.html": "sound_generator",
    "shell_sprite_animation.html": "sprite_animation",
    "shell_tween.html": "tween",
    "shell_zero_gravity.html": "zero_gravity",
}

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
        "title": "Zenoo Retained-Mode GUI Showcase (Spinel Wasm)",
        "heading": "ZENOO RETAINED-MODE GUI &amp; RESIZABLE WINDOW",
        "desc": "Pure Ruby Sprite-based Retained Mode UI System | Powered by Spinel AOT &amp; WebGL 2.0",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_gui_widgets.rb",
        "menu": False
    },
    "shell_procedural_runner.html": {
        "title": "Zenoo Procedural Runner & Sword IK (Spinel Wasm)",
        "heading": "ZENOO PROCEDURAL RUNNER &amp; SWORD IK",
        "desc": "走る脚の楕円接地IK・凝った腰の4大挙動 &amp; 肩子Sprite腕IK剣撃デモ | Powered by Spinel AOT",
        "src": "https://github.com/mirichi/zenoo/blob/master/examples/demo_procedural_runner.rb",
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
    "shell_particle_editor.html": {
        "title": "Zenoo 2D GPU Particle Designer & Editor (Spinel Wasm)",
        "heading": "ZENOO GPU PARTICLE DESIGNER &amp; EDITOR",
        "desc": "InstanceBuffer + GPU解析シェーダー マルチレイヤーパーティクルエディタ | Powered by Spinel AOT",
        "src": "https://github.com/mirichi/zenoo/blob/master/tools/particle_editor.rb",
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

def generate_targets(targets=None):
    if not os.path.exists(TEMPLATE_PATH):
        print(f"Error: Template not found at {TEMPLATE_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(TEMPLATE_PATH, 'r', encoding='utf-8') as f:
        template = f.read()

    # 指定された対象のみに絞り込み (未指定なら全件)
    # 引数は "shell_procedural_runner.html", "shell_procedural_runner", "procedural_runner" いずれの形式でも受け付ける
    items = []
    if targets:
        target_keys = set()
        for t in targets:
            name = t.strip()
            if not name.endswith(".html"):
                name = name + ".html"
            if not name.startswith("shell_") and name != "shell.html":
                name = "shell_" + name
            target_keys.add(name)

        for filename, meta in DEMOS.items():
            if filename in target_keys:
                items.append((filename, meta))
        if not items:
            print(f"Warning: No matching demos found for targets: {targets}", file=sys.stderr)
            return
    else:
        items = list(DEMOS.items())

    count = 0
    skipped = 0
    for filename, meta in items:
        out_path = os.path.join(WEB_DIR, filename)
        extra_btn = MENU_BUTTON_HTML if meta.get("menu") else ""
        
        content = template
        content = content.replace("{{TITLE}}", meta["title"])
        content = content.replace("{{HEADING}}", meta["heading"])
        content = content.replace("{{DESCRIPTION}}", meta["desc"])
        content = content.replace("{{SOURCE_URL}}", meta["src"])
        content = content.replace("{{EXTRA_BUTTONS}}", extra_btn)

        # 改行コードの差異や内容に変更がない場合は上書き書き込みせずスキップ (git dirty防止)
        need_write_web = True
        if os.path.exists(out_path):
            with open(out_path, 'r', encoding='utf-8') as ef:
                existing = ef.read()
            if existing == content:
                need_write_web = False
                skipped += 1

        if need_write_web:
            with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
                f.write(content)
            count += 1

        # docs/<dir>/index.html が既に存在する場合、Wasm再ビルド不要でシェルHTMLのみ即座に同期
        dir_name = DOCS_MAP.get(filename)
        if dir_name:
            docs_target = os.path.join(DOCS_DIR, dir_name, "index.html")
            if os.path.exists(docs_target):
                docs_content = content.replace("{{{ SCRIPT }}}", '<script async type="text/javascript" src="index.js"></script>')
                with open(docs_target, 'r', encoding='utf-8') as df:
                    existing_docs = df.read()
                if existing_docs != docs_content:
                    with open(docs_target, 'w', encoding='utf-8', newline='\n') as df:
                        df.write(docs_content)

    if targets:
        print(f"Successfully generated {count} shell HTML files (targets: {', '.join(targets)})!")
    else:
        print(f"Successfully updated {count} shell HTML files ({skipped} unchanged files skipped)!")

def generate_all():
    generate_targets(None)

if __name__ == "__main__":
    args = sys.argv[1:]
    if args:
        generate_targets(args)
    else:
        generate_all()

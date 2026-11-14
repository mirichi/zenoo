# Zenoo (ぜぬー) - 2D Micro Engine for Ruby

**Zenoo** は、**Pure Ruby** の親しみやすい記述力と、**Spinel AOT コンパイラ** による C / WebAssembly への直接トランスパイル、そして **OpenGL 3.3 / WebGL 2.0** によるハードウェアアクセラレーションを融合させた、軽量・ハイパフォーマンスな次世代 2D ゲーム＆グラフィックスエンジンです。

DXRuby に着想を得た直感的な API を備え、デスクトップ（CRuby / ネイティブバイナリ）でも Web ブラウザ（WebAssembly）でも、同一の Ruby コードが 60fps で軽快に動作します。

※開発中なのでAPIや機能は予告/遠慮なく変わります。

---

## 🌟 主な特徴

1. **Pure Ruby 記述 $\to$ Spinel AOT による Wasm / ネイティブ超高速実行**
   - ゲームロジック、UI、衝突判定、シェーダー管理のすべてを Pure Ruby で記述。
   - Spinel AOT コンパイラにより C / WebAssembly へ直接トランスパイルされ、デスクトップ（ネイティブ）でもブラウザでも 60fps で軽快に動作します。

2. **GPU SDF & インスタンシングによる美麗・軽量グラフィックス**
   - MSAA 不要でジャギーが出ない SDF プリミティブ（角丸矩形・線・影）と、日本語対応のリアルタイム動的 SDF フォントエンジン。
   - 極小 C カーネルと OpenGL 3.3 / WebGL 2.0 による GPU Instancing で、大量のスプライトや弾幕を 1 ドローコールで一括描画。

3. **2D ゲーム開発に直結する組み込み機能**
   - スプライト（親子階層・ボーン連携）＆変形同期コライダー、GJK/SAT 衝突判定、および滑らかな壁ずりを実現する MTV（めり込み解消）、剛体物理応答。
   - キーボード・マウス・ゲームパッド・マルチタッチ／仮想パッドを統合するアクションマップ、miniaudio 音源再生＆動的波形合成、Tween、多層 Tilemap、保持モード UI (`UI`) & 即時モード GUI (`ImGui`)、メッシュ変形、GPU パーティクルを標準搭載。

---

## 🎮 WebAssembly ショーケース (デモ一覧)

Spinel AOT コンパイラにより WebAssembly 出力に対応しており、ブラウザ上で動作するインタラクティブデモを GitHub Pages にて公開しています。
👉 **[Zenoo WebAssembly Showcase (GitHub Pages)](https://mirichi.github.io/zenoo/)**

`./build_pages.sh` を実行すると、隣接ディレクトリ `../zenoo-pages/examples/` に WebAssembly 向けにビルドされた **全 24 種類のデモ・ツール** とポータルハブ（`index.html`）が生成されます（また `./build_samples.sh` により `samples/` 配下の基礎サンプル群が `../zenoo-pages/samples/` に出力されます）。

| デモ名 | 出力パス (`../zenoo-pages/examples/`) | 内容 |
|---|---|---|
| **Zenoo Portal** | `index.html` | 全デモを一覧・起動できるポータルハブ |
| **Survival Shooting** | `game/` | 群がる敵を倒しオーブで強化する 2D サバイバルアクション |
| **Retained Mode GUI & Windows** | `gui/` | Pure Ruby Sprite ベースの保持モード UI・リサイズ可能ウィンドウ・各種ウィジェット |
| **SDF Font & Sinclair** | `font/` | ハイブリッドSDF/ビットマップ動的アトラス、高品質日本語・袋文字・8x8 レトロ文字 |
| **Vector Graphics** | `vector/` | Canvas 2D 互換 API、ベジエ曲線、多角形分割、グラデーション |
| **Sprite & Blend Modes** | `image/` | GPU Instanced な回転・拡縮・反転・ピボット・加算/乗算ブレンド合成 |
| **Texture Atlas & sub_image** | `atlas/` | FBO への動的ベイク、sub_image ゼロアロケーション切り出し、1ドローコール描画 |
| **Hardware Clipping** | `clip/` | glScissor ハードウェアクリッピング、画面全体マスクとローカルビューポート |
| **Audio & Sound Synthesis** | `sound/` | miniaudio & Ogg Vorbis、DXRuby風動的波形合成 (SoundEffect) |
| **2D Collision Playground** | `collision/` | GJK 2D 凸図形衝突判定、円・カプセル・OBB・凸多角形リアルタイム交差 |
| **Tween & Easing Animation** | `tween/` | 10種以上のイージング関数、メソッドチェーン (.to/.delay/.call/.yoyo)、時間軸イベント発火 |
| **Sprite Coords Visualizer** | `coords/` | スプライト配置基準(Anchor)・支点(Pivot)・コライダーOffset相互作用可視化 |
| **Billiards & 3D Rolling Shader** | `billiards/` | めり込み解消 (MTV) 2D 剛体物理＆フラグメントシェーダーによる 3D クオータニオン転がり球体レンダリング |
| **Zero-Gravity Physics** | `zero_gravity/` | 即時モード 2D 剛体物理 (PhysicsSprite / SAT / MTV) による無重力反発・投擲・摩擦スピン |
| **GPU Particle Storm** | `particles/` | GPU Instancing による 10万〜20万パーティクル・リアルタイム引力＆衝撃波ストーム |
| **GPU Danmaku Storm** | `danmaku/` | GPU Instancing による 75,000発 弾幕 &amp; 円環セクター（Annular Sector）階層衝突判定 |
| **Articulated Sprite & Hierarchy** | `articulated/` | 親子階層構造・多関節キャラクター＆コライダー連動・関節外れ防止 MTV |
| **2D SkinnedMesh & Bone** | `skinned_mesh/` | GPU 頂点スキニング、ボーン連動、ウェイトマップによるリアルタイムメッシュ変形 |
| **Canvas to Mesh & Vector Sprites** | `canvas_mesh/` | Canvas ベクターパスの VBO メッシュ化＆120個のベクター弾幕 1 ドローコール一括描画 |
| **2D Mesh Deformation** | `mesh_deform/` | 2ストリーム VBO パイプライン、旗の波打ち・リボン剣閃・4隅バイリニア自由変形 |
| **Scene & Transition** | `scene/` | スタック型シーン管理（描画キュー保持によるフリーズ・ポーズ・トランジション演出） |
| **Diagonal Sprite & Tilemap** | `sprite_animation/` | 斜め4方向スプライト反転アニメ &amp; 行単位 Mesh による多層 Yソート Tilemap |
| **Procedural Runner & Sword IK** | `procedural_runner/` | 2D ボーン・楕円接地 IK によるプロシージャル歩行＆腕 IK 剣撃デモ |
| **Retro Sound Generator** | `sound_generator/` | 8-bit / アーケード風 動的波形シンセサイザ &amp; リアルタイム波形スコープツール |
| **GPU Particle Editor** | `particle_editor/` | マルチレイヤー GPU パーティクル・インタラクティブ設計エディタツール |

---

## 🚀 クイックスタート (サンプルコード)

### 1. 最小ゲームループと SDF プリミティブ描画

```ruby
require 'zenoo'

# 1280x720 仮想解像度でメインループ開始
frame = 0
Window.loop(1280, 720, "Zenoo Quickstart") do
  frame += 1
  t = frame / 60.0

  # 画面クリア (デフォルトは黒クリア)
  Window.clear([15, 23, 42, 255])

  # SDF 角丸カード (枠線・外光彩ドロップシャドウ付き、MSAA不要)
  Window.draw_rect(100, 100, 320, 180, radius: 16, color: [30, 41, 59, 255], border_width: 2, border_color: :cyan, shadow_blur: 20)

  # SDF 丸端ネオンライン
  Window.draw_line(120, 220, 380, 220, width: 4.0, cap: :round, color: [255, 200, 50, 255], shadow_blur: 8)

  # SDF 日本語テキスト描画 (動的アトラス生成)
  Window.draw_text(130, 130, "こんにちは、Zenoo！", size: 24, color: :white)
  Window.draw_text(130, 170, "Time: #{t.round(2)}s", font: Font::SINCLAIR, size: 16, color: :green)
end
```

### 2. アクションマップ入力 & スプライト

キーボード、マウス、ゲームパッド（Xbox / PS）を透過的に統合します。

```ruby
# アクションマップの登録
Input.define_action(:attack, keys: [:j, :z], mouse: :left, gamepad: [:x, :a])
Input.define_action(:dash,   keys: [:space, :left_shift], gamepad: [:b, :rb])

# 毎フレームの移動ベクトル取得 (WASD・矢印・パッドスティック統合、斜め移動正規化済み)
dx, dy = Input.vector

# アクション判定
if Input.action_pressed?(:attack)
  # 攻撃処理
end
```

### 3. 2D 幾何コライダー & MTV めり込み解消 (壁ずり)

```ruby
# 幾何コライダーの作成 (円、OBB、カプセル、多角形に対応)
player_box = Collision.rect(player_x, player_y, 40, 40)
wall_box   = Collision.rect(200, 200, 80, 80)

# GJK / SAT アルゴリズムによる交差判定
if Collision.check(player_box, wall_box)
  # 衝突検知
end

# めり込み量・押し出しベクトル (MTV) を取得してスムーズに壁ずり
if (hit = Collision.penetration(player_box, wall_box))
  player_x += hit.push_x
  player_y += hit.push_y
end
```

### 4. サウンド再生 & 動的効果音生成 (DXRuby スタイル)

```ruby
# 音声ファイルの再生 (WAV, MP3, Ogg Vorbis 対応)
bgm = Sound.load("assets/sounds/sample.ogg")
bgm.looping = true
bgm.play

# 動的波形生成 (DXRuby 風 SoundEffect / チップチューン即時合成)
jump_sound = SoundEffect.sweep(250, 700, 0.2, type: :square) # ピープ音
boom_sound = SoundEffect.noise(0.4, volume: 0.8)             # 爆発ノイズ

jump_sound.play
```

---

## 🛠️ ビルドと実行

### ローカル開発サーバーの起動

```bash
# ../zenoo-pages (examples/ & samples/) をポート 8088 で配信
ruby server.rb

# サブディレクトリ指定 (examples / samples は 8088、build/wasm は 8089)
ruby server.rb examples
ruby server.rb samples
ruby server.rb wasm

# ブラウザでアクセス:
# PC: http://localhost:8088/examples/ (または /samples/)
# スマホ (同LAN内): http://<PCのローカルIP>:8088/examples/
```

### 全デモ・サンプルの一括 Wasm ビルド (GitHub Pages 配信用)

WSL2 または Linux 環境で以下を実行します：

```bash
# ショーケース全 24 デモ＆ツールを ../zenoo-pages/examples/ に出力
./build_pages.sh

# 基礎サンプル集 (samples/*.rb) を ../zenoo-pages/samples/ に出力
./build_samples.sh
```
特定ターゲットのみビルドする場合は `./build_pages.sh game` のように引数を指定できます（出力先ルートは環境変数 `PAGES_ROOT` で変更可能、デフォルト `../zenoo-pages`）。

#### Wasm ビルドモードの指定 (速度優先 / 開発イテレーション)

環境変数 `BUILD_MODE` を指定することで、ビルド速度（開発イテレーション）と実行速度を切り替えることができます：

| モード | 指定例 | 最適化 | 特徴・用途 |
|---|---|---|---|
| **`dev`** / `fast` | `BUILD_MODE=dev ./build_pages.sh game` | `-O1` | **ビルド速度最優先**。試行錯誤・デバッグ用（`build_samples.sh` のデフォルト） |
| **`release`** | `BUILD_MODE=release ./build_pages.sh game` | `-O2` | **標準リリース最適化**。速度と安定性のバランス重視（`build_wasm.sh` のデフォルト） |
| **`max`** / `o3` | `BUILD_MODE=max ./build_pages.sh game` | `-O3` | **最高実行速度**（`build_pages.sh` のデフォルト） |

> **Note (Spinel 向けパッチについて)**:
> ブラウザ (Emscripten) 上でのメモリ肥大化防止および Fiber スタックスイッチ回避のため、Spinel のランタイム (`lib/sp_slab.c`, `lib/sp_fiber.c`) に最小限のパッチを適用しています。詳細は `patches/README.md` を参照してください。

### 任意の Ruby スクリプトを単体 Wasm ビルド

```bash
# 開発モード (ビルド最速)
BUILD_MODE=dev ./build_wasm.sh examples/game_zenoo.rb

# リリースモード (デフォルト -O2)
./build_wasm.sh examples/game_zenoo.rb

# 実行確認 (ポート 8089 で build/wasm を配信)
ruby server.rb wasm
```

### CRuby ネイティブ C 拡張のビルド (デスクトップ版)

通常の CRuby（MRI）環境で実行するための C 拡張（`zenoo.so`）をビルドします。

- **Windows (MSYS2 / ucrt64)**:
  ```cmd
  build.bat
  ruby -Ilib examples\game_zenoo.rb
  ```

- **Linux / macOS**:
  ```bash
  ./build.sh
  ruby -Ilib examples/game_zenoo.rb
  ```

### Spinel ネイティブバイナリ AOT ビルド (Linux / WSL2)

Spinel を用いてスタンドアロンの ELF ネイティブバイナリを生成します：

```bash
# 単一スクリプトのコンパイル
./build_spinel.sh examples/game_zenoo.rb
./build/game_zenoo

# 全デモの一括コンパイル
./build_all_linux.sh
```

---

## 📂 プロジェクト構成

```
zenoo/
├── examples/                  # 各種ショーケースデモ & Web シェルテンプレート (examples/web/)
├── samples/                   # API ごとの基礎サンプル集
├── tools/                     # エンジン付属ツール & Web シェル生成スクリプト
│   ├── particle_editor.rb     # GPU パーティクルエディタ
│   ├── sound_generator.rb     # レトロ効果音ジェネレータ
│   ├── generate_shells.py     # デモ用 Wasm シェル HTML 生成
│   └── generate_sample_pages.py # サンプル一覧・Wasm シェル HTML 生成
├── include/                   # C 言語ヘッダー & サードパーティライブラリ
│   ├── zenoo.h                # マイクロカーネル C API
│   ├── miniaudio.h            # miniaudio オーディオエンジン
│   ├── stb_image.h            # stb_image 画像デコーダー
│   ├── stb_image_write.h      # stb_image_write 画像エンコーダー
│   ├── stb_truetype.h         # stb_truetype フォントパーサー
│   ├── stb_vorbis.c           # stb_vorbis Ogg Vorbis デコーダー
│   └── glad/ GLFW/ KHR/       # OpenGL / GLFW ヘッダー
├── src/                       # C 言語マイクロカーネル実装 (OpenGL 3.3 / WebGL 2.0)
│   ├── glad.c                 # OpenGL 3.3 ローダー
│   ├── zenoo_core.c           # コア共通ヘルパ
│   ├── zenoo_window.c         # ウィンドウ・ライフサイクル・フレーム制御
│   ├── zenoo_input.c          # 入力 (キー・マウス・ゲームパッド・マルチタッチ)
│   ├── zenoo_vibration.c      # 振動 (XInput / Linux FF / Web Gamepad)
│   ├── zenoo_image.c          # テクスチャ・画像・FBO
│   ├── zenoo_gfx.c            # 描画状態・GLSL・動的頂点バッファ
│   ├── zenoo_font.c           # SDF アトラス・stb_truetype 統合
│   └── zenoo_audio.c          # miniaudio オーディオブリッジ
├── lib/                       # Pure Ruby クラスライブラリ
│   ├── zenoo.rb               # エントリポイント
│   └── zenoo/
│       ├── window.rb          # メインループ & 描画 DSL
│       ├── scene.rb           # スタック型シーン管理 (描画キュー保存・ポーズ・フェード)
│       ├── sprite.rb          # スプライト & 親子階層・変形同期コライダー
│       ├── collision.rb       # GJK / SAT 2D 凸図形衝突判定 & MTV
│       ├── input.rb           # アクションマップ・入力統合
│       ├── virtual_pad.rb     # タッチ用仮想ゲームパッド
│       ├── browser.rb         # Web ブラウザ連携ユーティリティ
│       ├── camera.rb          # 2D カメラ & ビューポート制御
│       ├── tilemap.rb         # タイルマップ描画 & Yソート
│       ├── easing.rb          # イージング関数
│       ├── tween.rb           # Tween アニメーション
│       ├── mesh.rb            # 2D メッシュ・頂点変形 & インスタンシング
│       ├── bone.rb            # 2D ボーン / IK
│       ├── skinned_mesh.rb    # 2D スキニングメッシュ
│       ├── particle.rb        # GPU パーティクルシステム
│       ├── physics.rb         # 即時モード 2D 剛体物理応答
│       ├── canvas.rb          # HTML5 Canvas 互換ベクター API & 耳刈り取り
│       ├── font.rb            # 動的 SDF フォント & テキスト配置 API
│       ├── ui.rb / ui/        # Sprite ベース保持モード UI システム
│       ├── imgui.rb / imgui/  # 即時モード GUI ウィジェット & ウィンドウ
│       ├── color.rb           # 色操作 & プリセット
│       ├── image.rb           # テクスチャ、sub_image & オフスクリーン FBO
│       ├── shader.rb / shaders/ # カスタム＆組み込みシェーダー管理
│       ├── sound.rb           # サウンド再生 (Audio / Sound)
│       ├── sound_effect.rb    # 動的波形合成 (SoundEffect)
│       ├── backend.rb         # CRuby / Spinel 抽象化バックエンド
│       ├── profiler.rb        # パフォーマンス・プロファイラ
│       └── dev.rb / dev/      # CRuby 向けホットリロード＆開発デバッガ
├── ext/                       # バインディング
│   ├── zenoo/                 # CRuby C 拡張 (mkmf)
│   └── spinel/                # Spinel AOT コンパイル用グルー
├── patches/                   # 外部依存 (Spinel 等) 向けパッチ
│   ├── README.md              # パッチ概要・適用手順
│   ├── 0001-fix-sp_slab-emscripten-wasm-memory.patch # Wasm メモリ肥大化対策
│   └── 0002-fix-sp_fiber-emscripten-stack.patch      # Fiber スタック確保パッチ
├── test/                      # テストコード
├── server.rb                  # 統合開発サーバー (../zenoo-pages / build/wasm 配信)
├── build_pages.sh             # GitHub Pages 全デモ一括ビルドスクリプト (出力先: ../zenoo-pages/examples/)
├── build_samples.sh           # サンプル集一括 Wasm ビルドスクリプト (出力先: ../zenoo-pages/samples/)
├── build_wasm.sh              # 単体 Wasm ビルドスクリプト (出力先: build/wasm/)
├── build_spinel.sh            # 単体 Linux ネイティブ AOT ビルドスクリプト
├── build_all_linux.sh         # 全デモ Linux ネイティブ一括 AOT ビルドスクリプト
├── build.bat / build.sh       # CRuby C 拡張ビルドスクリプト
└── README.md                  # 本ドキュメント
```

※ `build_pages.sh` / `build_samples.sh` の Web 成果物は隣接する配布リポジトリ `../zenoo-pages/`（`examples/`・`samples/`）に出力されます。

---

## 📜 ライセンス

MIT License

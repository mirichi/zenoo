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
   - スプライト＆変形同期コライダー、GJK/SAT 衝突判定、および滑らかな壁ずりを実現する MTV（めり込み解消）、剛体物理応答。
   - キーボード・マウス・ゲームパッドを統合するアクションマップ、miniaudio 音源再生＆動的波形合成、Tween、タイルマップ、即時モード GUI、メッシュ変形を標準搭載。

---

## 🎮 WebAssembly ショーケース (デモ一覧)

Spinel AOT コンパイラにより WebAssembly 出力に対応しており、ブラウザ上で動作するインタラクティブデモを GitHub Pages にて公開しています。
👉 **[Zenoo WebAssembly Showcase (GitHub Pages)](https://mirichi.github.io/zenoo/)**

リポジトリ内の `docs/` ディレクトリに、WebAssembly 向けにビルド済みの全 19 種類のデモとポータルハブが収録されています。

| デモ名 | パス | 内容 |
|---|---|---|
| **Zenoo Portal** | `docs/index.html` | 全デモを一覧・起動できるポータルハブ |
| **Survival Shooting** | `docs/game/` | 群がる敵を倒しオーブで強化する 2D サバイバルアクション |
| **Extended GUI & Windows**| `docs/gui/` | チェックボックス・ラジオ・タブ・スピン・ドロップダウン・リスト・スクロールビュー・サイズ変更ウィンドウ |
| **SDF Font & Sinclair** | `docs/font/` | ハイブリッドSDF/ビットマップ動的アトラス、高品質日本語・袋文字・8x8 レトロ文字 |
| **Vector Graphics** | `docs/vector/` | Canvas 2D 互換 API、ベジエ曲線、多角形分割、グラデーション |
| **Sprite & Blend Modes** | `docs/image/` | GPU Instanced な回転・拡縮・反転・ピボット・加算/乗算ブレンド合成 |
| **Texture Atlas & sub_image** | `docs/atlas/` | FBO への動的ベイク、sub_image ゼロアロケーション切り出し、1ドローコール描画 |
| **Hardware Clipping** | `docs/clip/` | glScissor ハードウェアクリッピング、画面全体マスクとローカルビューポート |
| **Audio & Sound Synthesis** | `docs/sound/` | miniaudio & Ogg Vorbis、DXRuby風動的波形合成 (SoundEffect) |
| **2D Collision Playground** | `docs/collision/` | GJK 2D 凸図形衝突判定、円・カプセル・OBB・凸多角形リアルタイム交差 |
| **Tween & Easing Animation** | `docs/tween/` | 10種以上のイージング関数、メソッドチェーン (.to/.delay/.call/.yoyo)、時間軸イベント発火 |
| **Sprite Coords Visualizer** | `docs/coords/` | スプライト配置基準(Anchor)・支点(Pivot)・コライダーOffset相互作用可視化 |
| **Billiards & 3D Rolling Shader** | `docs/billiards/` | めり込み解消 (MTV) 2D 剛体物理＆フラグメントシェーダーによる 3D クオータニオン転がり球体レンダリング |
| **Zero-Gravity Physics** | `docs/zero_gravity/` | 即時モード 2D 剛体物理 (PhysicsSprite / SAT / MTV) による無重力反発・投擲・摩擦スピン |
| **GPU Particle Storm** | `docs/particles/` | GPU Instancing による 10万〜20万パーティクル・リアルタイム引力＆衝撃波ストーム |
| **GPU Danmaku Storm** | `docs/danmaku/` | GPU Instancing による 75,000発 弾幕 &amp; 円環セクター（Annular Sector）階層衝突判定 |
| **Articulated Sprite & Hierarchy** | `docs/articulated/` | 親子階層構造・多関節キャラクター＆コライダー連動・関節外れ防止 MTV |
| **2D SkinnedMesh & Bone** | `docs/skinned_mesh/` | GPU 頂点スキニング、ボーン連動、ウェイトマップによるリアルタイムメッシュ変形 |
| **Canvas to Mesh & Vector Sprites** | `docs/canvas_mesh/` | Canvas ベクターパスの VBO メッシュ化＆120個のベクター弾幕 1 ドローコール一括描画 |
| **2D Mesh Deformation** | `docs/mesh_deform/` | 2ストリーム VBO パイプライン、旗の波打ち・リボン剣閃・4隅バイリニア自由変形 |

---

## 🚀 クイックスタート (サンプルコード)

### 1. 最小ゲームループと SDF プリミティブ描画

```ruby
require 'zenoo'

# 1280x720 仮想解像度でメインループ開始
Window.loop(1280, 720, "Zenoo Quickstart") do
  t = Window.time

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
bgm = Sound.load("assets/sounds/bgm.ogg")
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
# docs/ (全デモポータル) をポート 8088 で配信
ruby server.rb

# ブラウザでアクセス:
# PC: http://localhost:8088/
# スマホ (同LAN内): http://<PCのローカルIP>:8088/
```

### 全デモの一括 Wasm ビルド (GitHub Pages 配信用)

WSL2 または Linux 環境で以下を実行します：

```bash
./build_pages.sh
```
`docs/` 配下に全デモとポータル（`index.html`）が一括生成されます（特定ターゲットのみビルドする場合は `./build_pages.sh game` のように引数を指定）。

#### Wasm ビルドモードの指定 (速度優先 / 開発イテレーション)

環境変数 `BUILD_MODE` を指定することで、ビルド速度（開発イテレーション）と実行速度（リリース）を切り替えることができます：

| モード | 指定例 | 最適化 | 特徴・用途 |
|---|---|---|---|
| **`dev`** / `fast` | `BUILD_MODE=dev ./build_pages.sh game` | `-O1` | **ビルド速度最優先**（ビルド時間が約 1/4 に短縮）。試行錯誤・デバッグ用 |
| **`release`** (デフォルト) | `./build_pages.sh game` | `-O2` | **実行速度重視**。60 FPS を維持する本番用標準ビルド |
| **`max`** / `o3` | `BUILD_MODE=max ./build_pages.sh game` | `-O3` | **最高実行速度**。重い計算を極限まで最適化 |

> **Note (Spinel 向けパッチについて)**:
> ブラウザ上でのメモリ肥大化防止、Fiber スタックオーバーフロー回避、およびクラスエイリアス / `native_struct` 連携の正常化のため、Spinel にパッチを適用しています。詳細は `patches/README.md` を参照してください。

### 任意の Ruby スクリプトを単体 Wasm ビルド

```bash
# 開発モード (ビルド最速)
BUILD_MODE=dev ./build_wasm.sh examples/game_zenoo.rb

# リリースモード (実行速度最優先)
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
├── docs/                      # GitHub Pages 配信用 Web 成果物 (全 21 デモ & ポータル)
│   ├── index.html             # ショーケースポータル
│   ├── game/                  # Survival Shooting デモ
│   ├── gui/                   # Extended GUI & Resizable Windows デモ
│   ├── font/                  # SDF Font & Sinclair デモ
│   ├── vector/                # Vector Graphics デモ
│   ├── image/                 # Sprite & Blend Modes デモ
│   ├── atlas/                 # Texture Atlas & sub_image デモ
│   ├── clip/                  # Hardware Clipping デモ
│   ├── sound/                 # Audio & Sound Synthesis デモ
│   ├── collision/             # 2D Collision Playground デモ
│   ├── tween/                 # Tween & Easing Animation デモ
│   ├── coords/                # Sprite Coords Visualizer デモ
│   ├── billiards/             # Billiards & 3D Rolling Shader デモ
│   ├── zero_gravity/          # 2D 剛体物理エンジンデモ
│   ├── particles/             # GPU パーティクルストームデモ
│   ├── danmaku/               # GPU 弾幕ストームデモ
│   ├── articulated/           # 多関節スプライト & 階層構造デモ
│   ├── skinned_mesh/          # 2D スキニングメッシュ & ボーンデモ
│   ├── canvas_mesh/           # Canvas to Mesh & ベクタースプライトデモ
│   ├── mesh_deform/           # 2D メッシュ変形 & 2ストリームVBOデモ
│   ├── scene/                 # スタック型シーン管理 & フェードデモ
│   └── sound_generator/       # レトロ効果音シンセサイザ & SEジェネレータデモ
│   ├── zero_gravity/          # Zero-Gravity 2D Rigid Body Physics デモ
│   ├── particles/             # GPU Particle Storm デモ
│   ├── danmaku/               # GPU Danmaku Storm デモ
│   ├── articulated/           # Articulated Sprite & Hierarchy デモ
│   ├── skinned_mesh/          # 2D SkinnedMesh & Bone デモ
│   ├── canvas_mesh/           # Canvas to Mesh & Vector Sprites デモ
│   └── mesh_deform/           # 2D Mesh Deformation デモ
├── examples/                  # サンプルコード集
├── include/                   # C 言語ヘッダー & サードパーティライブラリ
│   ├── zenoo.h                # マイクロカーネル C API
│   ├── miniaudio.h            # miniaudio オーディオエンジン
│   ├── stb_image.h            # stb_image 画像デコーダー
│   ├── stb_truetype.h         # stb_truetype フォントパーサー
│   └── stb_vorbis.c           # stb_vorbis Ogg Vorbis デコーダー
├── src/                       # C 言語マイクロカーネル実装 (OpenGL 3.3 / WebGL 2.0)
│   ├── glad.c                 # OpenGL 3.3 ローダー
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
│       ├── sprite.rb          # スプライト & 変形同期コライダー
│       ├── collision.rb       # GJK / SAT 2D 凸図形衝突判定 & MTV
│       ├── input.rb           # アクションマップ・入力統合
│       ├── camera.rb          # 2D カメラ & ビューポート制御
│       ├── tilemap.rb         # タイルマップ描画
│       ├── tween.rb           # Tween / イージングアニメーション
│       ├── mesh.rb            # 2D メッシュ・頂点変形 & インスタンシング
│       ├── skinned_mesh.rb    # 2D ボーン＆GPU スキニング
│       ├── physics.rb         # 即時モード 2D 剛体物理応答
│       ├── canvas.rb          # HTML5 Canvas 互換ベクター API & 耳刈り取り
│       ├── font.rb            # 動的 SDF フォント & テキスト配置 API
│       ├── gui.rb             # 即時モード GUI ウィジェット & ウィンドウ
│       ├── color.rb           # 色操作 & プリセット
│       ├── image.rb           # テクスチャ、sub_image & オフスクリーン FBO
│       ├── shader.rb          # カスタムシェーダー管理
│       ├── sound.rb           # サウンド再生 (Sound)
│       ├── sound_effect.rb    # 動的波形合成 (SoundEffect)
│       ├── backend.rb         # CRuby / Spinel 抽象化バックエンド
│       └── profiler.rb        # パフォーマンス・プロファイラ
├── ext/                       # バインディング
│   ├── zenoo/                 # CRuby C 拡張 (mkmf)
│   └── spinel/                # Spinel AOT コンパイル用グルー
├── patches/                   # 外部依存 (Spinel 等) 向けパッチ
│   ├── README.md              # パッチ概要・適用手順
│   ├── 0001-fix-sp_slab-emscripten-wasm-memory.patch # Wasm メモリ肥大化対策
│   ├── 0002-fix-sp_fiber-emscripten-stack.patch      # Fiber スタック確保パッチ
│   └── 0003-fix-avoid-qualifying-own-native-struct-and-alias.patch # クラスエイリアス & native_struct 連携修正
├── server.rb                  # 統合開発サーバー (docs / wasm 切り替え対応)
├── build_pages.sh             # GitHub Pages 全デモ一括ビルドスクリプト
├── build_wasm.sh              # 単体 Wasm ビルドスクリプト
├── build_spinel.sh            # 単体 Linux ネイティブ AOT ビルドスクリプト
├── build_all_linux.sh         # 全デモ Linux ネイティブ一括 AOT ビルドスクリプト
├── build.bat / build.sh       # CRuby C 拡張ビルドスクリプト
└── README.md                  # 本ドキュメント
```

---

## 📜 ライセンス

MIT License

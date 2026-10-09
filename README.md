# Zenoo (ぜぬー) - 2D Micro Engine for Ruby

**Zenoo** は、**Pure Ruby** の親しみやすい記述力と、**Spinel AOT コンパイラ** による C / WebAssembly への直接トランスパイル、そして **OpenGL 3.3 / WebGL 2.0** によるハードウェアアクセラレーションを融合させた、軽量・ハイパフォーマンスな次世代 2D ゲーム＆グラフィックスエンジンです。

DXRuby に着想を得た直感的な API を備え、デスクトップ（CRuby / ネイティブバイナリ）でも Web ブラウザ（Wasm / スマホ対応）でも、まったく同一の Ruby コードが 60fps で軽快に動作します。

※開発中なのでAPIや機能は予告/遠慮なく変わります。

---

## 🌟 主な特徴

1. **Pure Ruby 記述 $\to$ Spinel AOT による Wasm / ネイティブ超高速実行**
   - ゲームロジック、UI、シェーダー管理、フォントレイアウト、ベクターテセレーションのすべてを Pure Ruby で記述。
   - Spinel AOT コンパイラによって C 言語に変換され、WebAssembly（Wasm）またはネイティブ ELF/EXE として高速実行。

2. **極小 C マイクロカーネル & WebGL 2.0 インスタンス描画**
   - C 言語コアは「ウィンドウ管理」「入力」「Quad バッチ描画（GPU Instancing）」「テクスチャ・FBO」「シェーダー Uniform 転送」のみを担当。
   - 大量のスプライトやパーティクル、弾幕を 1 ドローコールで一括描画。

3. **オンデマンド動的 SDF フォントエンジン**
   - `stb_truetype` によるリアルタイム SDF（Signed Distance Field）ラスタライズ。
   - 日本語フォント（M+ 1p）およびレトロ 8x8（Sinclair ZX Spectrum）を内蔵。
   - 拡大・回転しても一切ジャギーが出ない高品質テキスト、袋文字（アウトライン）、ドロップシャドウ、リアルタイム文字アニメーション（ウェーブ等）を標準サポート。

4. **HTML5 Canvas 2D 互換 ベクターグラフィックス**
   - `move_to`, `line_to`, `bezier_curve_to`, `arc` などの直感的なパス構築 API。
   - **耳刈り取り法 (Ear Clipping)** による凹凸多角形のリアルタイム GPU メッシュ化。
   - モバイル GPU に最適化された 32bit 高精度（`highp`）シェーダーによる線形 (Linear) / 放射 (Radial) グラデーション。

5. **Pure Ruby 即時モード (Immediate Mode) GUI**
   - ステートレスに毎フレーム構築可能な UI システム。
   - GPU SDF シェーダーによるモダン角丸カード、ドロップシャドウ、押し込みアニメーション、スライダー、ラベルを標準装備。
   - モダンテーマとレトロフラットテーマのリアルタイム切り替えに対応。

6. **スマートフォン・マルチプラットフォーム完全最適化**
   - 16:9 仮想解像度のアスペクト比自動維持。
   - スマホ横画面時の自動全画面フィット（上下見切れ解消）＆半透明フローティング操作ボタン。
   - 画面の **2本指タップで右クリック（メニュー開閉など）** を直感的にエミュレート。
   - ワンタップでアドレスバーを消す全画面（イマーシブ）モード対応。

7. **miniaudio & stb_vorbis 統合オーディオエンジン**
   - WAV, MP3, Ogg Vorbis の透過的デコード＆ストリーミング再生。
   - DXRuby 風の動的波形生成（`SoundEffect.tone`, `sweep`, `noise`, `create`）。
   - 音量・ピッチ・パン・ループ・シーク・一時停止などのフルコントロール。
   - ファイル音と動的生成音を共通の `Sound` インスタンスとして透過操作可能。

8. **GJK 2D 衝突判定エンジン (`Zenoo::Collision`)**
   - Pure Ruby による GJK (Gilbert-Johnson-Keerthi) / SAT アルゴリズム実装。
   - 円 (Circle)、点 (Point)、線分 (Segment)、矩形 (AABB)、回転矩形 (OBB)、カプセル (Capsule)、任意凸多角形 (Polygon) の高精度・リアルタイム交差判定。
   - ゲームロジックへの組み込みやデバッグ可視化が容易。

---

## 🎮 WebAssembly ショーケース (デモ一覧)

Web ブラウザ上で動作するインタラクティブデモは、GitHub Pages にて公開されています。
👉 **[Zenoo WebAssembly Showcase (GitHub Pages)](https://mirichi.github.io/zenoo/)**

リポジトリ内の `docs/` ディレクトリに、WebAssembly 向けにビルド済みの全 10 種類のデモとポータルハブが収録されています。

| デモ名 | パス | 内容 |
|---|---|---|
| **Zenoo Portal** | `docs/index.html` | 全デモを一覧・起動できるポータルハブ |
| **Survival Shooting** | `docs/game/` | 群がる敵を倒しオーブで強化する 2D サバイバルアクション |
| **Immediate Mode GUI** | `docs/gui/` | Pure Ruby 即時モード GUI（ボタン・スライダー・SDF カード） |
| **SDF Font & Sinclair** | `docs/font/` | ハイブリッドSDF/ビットマップ動的アトラス、高品質日本語・袋文字・8x8 レトロ文字 |
| **Vector Graphics** | `docs/vector/` | Canvas 2D 互換 API、ベジエ曲線、多角形分割、グラデーション |
| **Sprite & Blend Modes** | `docs/image/` | GPU Instanced な回転・拡縮・反転・ピボット・加算/乗算ブレンド合成 |
| **Texture Atlas & sub_image** | `docs/atlas/` | FBO への動的ベイク、sub_image ゼロアロケーション切り出し、1ドローコール描画 |
| **Multi-Window & Occlusion** | `docs/window/` | ドラッグ移動・Zオーダー制御・背面クリック遮断・内部クリッピング |
| **Hardware Clipping** | `docs/clip/` | glScissor ハードウェアクリッピング、画面全体マスクとローカルビューポート |
| **Audio & Sound Synthesis** | `docs/sound/` | miniaudio & Ogg Vorbis、DXRuby風動的波形合成 (SoundEffect) |
| **2D Collision Playground** | `docs/collision/` | GJK 2D 凸図形衝突判定、円・カプセル・OBB・凸多角形リアルタイム交差 |

---

## 🚀 クイックスタート (サンプルコード)

### 1. 基本的なゲームループと図形描画

```ruby
require 'zenoo'

# 1280x720 仮想解像度でメインループ開始
Window.loop(1280, 720, "Zenoo Quickstart") do
  t = Window.time

  # 画面クリア
  Window.clear([15, 23, 42, 255])

  # SDF 矩形・カード描画 (角丸・ボーダー・ドロップシャドウを統合)
  Window.draw_rect(100, 100, 300, 180, radius: 16, color: [30, 41, 59, 255], border_width: 2, border_color: :cyan, shadow_blur: 20)

  # SDF 日本語テキスト描画
  Window.draw_text(130, 140, "こんにちは、Zenoo！", size: 24, color: :white)
  Window.draw_text(130, 180, "Time: #{t.round(2)}s", font: Font::SINCLAIR, size: 16, color: :green)

  # マウス入力
  mx, my = Input.mouse_pos
  if Input.mouse_pressed?(:left)
    Window.draw_circle(mx, my, 20, color: :yellow)
  end
end
```

### 2. ベクターグラフィックス (Canvas 2D スタイル)

```ruby
Window.draw_path do |c|
  c.save
  c.translate(640, 360)
  c.rotate(Window.time)

  # 線形グラデーション
  grad = c.create_linear_gradient(-100, -100, 100, 100)
  grad.add_color_stop(0.0, [1.0, 0.8, 0.2, 1.0])
  grad.add_color_stop(1.0, [1.0, 0.2, 0.5, 1.0])

  # パス構築と塗りつぶし
  c.begin_path
  c.round_rect(-100, -100, 200, 200, 24)
  c.fill(grad)
  c.stroke(:white, 4)

  c.restore
end
```

### 3. サウンド再生 & 動的効果音生成 (DXRuby スタイル)

```ruby
# ファイルから再生 (WAV, MP3, Ogg Vorbis 対応)
bgm = Sound.load("assets/sounds/bgm.ogg")
bgm.looping = true
bgm.volume = 0.7
bgm.play

# 動的波形生成 (DXRuby 風 SoundEffect)
jump_sound = SoundEffect.sweep(250, 700, 0.2, type: :square) # ジャンプ音
boom_sound = SoundEffect.noise(0.4, volume: 0.8)             # 爆発音
sine_sound = SoundEffect.tone(440, 0.3)                       # 単音サイン波

# 再生・ピッチ変更
jump_sound.pitch = 1.2
jump_sound.play

# マスター音量調整
Audio.master_volume = 0.8
```

### 4. 2D 幾何・GJK 衝突判定 (`Zenoo::Collision`)

```ruby
# 回転矩形 (OBB) と円の作成
box = Collision.rect(200, 200, 120, 60, angle: 30)
ball = Collision.circle(230, 210, 30)

# GJK アルゴリズムによる交差判定
if Collision.check(box, ball)
  puts "Hit detected!"
end

# 線分（カプセル）や凸多角形との交差判定も同一インターフェース
capsule = Collision.segment(100, 100, 300, 200, 15)
poly = Collision.polygon([[0, 0], [50, -30], [80, 20], [30, 60]])
puts "Intersecting!" if Collision.check(capsule, poly)
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
`docs/` 配下に全 10 種類のデモとポータル（`index.html`）が一括生成されます。

> **Note (Wasm メモリ & Fiber 最適化)**:
> ブラウザ上でのメモリ肥大化防止および Fiber スタックオーバーフロー回避のため、Spinel に Wasm 向けパッチを適用しています。詳細は patches/README.md を参照してください。

### 任意の Ruby スクリプトを単体 Wasm ビルド

```bash
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

# 全 10 デモの一括コンパイル
./build_all_linux.sh
```

---

## 📂 プロジェクト構成

```
zenoo/
├── docs/                      # GitHub Pages 配信用 Web 成果物
│   ├── index.html             # ショーケースポータル
│   ├── favicon.ico            # ファビコン
│   ├── game/                  # Survival Shooting デモ
│   ├── gui/                   # Immediate Mode GUI デモ
│   ├── font/                  # SDF Font & Sinclair デモ
│   ├── vector/                # Vector Graphics デモ
│   ├── image/                 # Sprite & Blend Modes デモ
│   ├── atlas/                 # Texture Atlas & sub_image デモ
│   ├── window/                # Multi-Window & Occlusion デモ
│   ├── clip/                  # Hardware Clipping デモ
│   ├── sound/                 # Audio & Sound Synthesis デモ
│   └── collision/             # 2D Collision Playground デモ
├── examples/                  # サンプルコード集
│   ├── game_zenoo.rb          # サバイバルシューティング
│   ├── demo_gui.rb            # 即時モード GUI
│   ├── demo_ttf_sdf_font.rb   # SDF フォント描画
│   ├── demo_vector_graphics.rb# ベクターグラフィックス
│   ├── demo_draw_image.rb     # スプライト描画 & ブレンド合成
│   ├── demo_texture_atlas.rb  # テクスチャアトラス & sub_image
│   ├── demo_window_drag.rb    # マルチウィンドウ & ドラッグ移動
│   ├── demo_window_clip.rb    # ハードウェアクリッピング
│   ├── demo_sound.rb          # オーディオ & 動的波形合成
│   ├── demo_collision.rb      # 2D GJK 衝突判定プレイグラウンド
│   └── web/                   # Wasm 配信用 HTML シェルテンプレート
├── include/                   # C 言語ヘッダー & サードパーティライブラリ
│   ├── zenoo.h                # マイクロカーネル C API
│   ├── miniaudio.h            # miniaudio オーディオエンジン
│   ├── stb_image.h            # stb_image 画像デコーダー
│   ├── stb_truetype.h         # stb_truetype フォントパーサー
│   └── stb_vorbis.c           # stb_vorbis Ogg Vorbis デコーダー
├── src/                       # C 言語マイクロカーネル実装
│   ├── glad.c                 # OpenGL 3.3 ローダー
│   ├── zenoo_window.c         # ウィンドウ・ライフサイクル・フレーム制御
│   ├── zenoo_input.c          # 入力 (キー・マウス・ゲームパッド・IME)
│   ├── zenoo_vibration.c      # 振動 (XInput / Linux FF / Web)
│   ├── zenoo_image.c          # テクスチャ・画像・FBO
│   ├── zenoo_gfx.c            # 描画状態・GLSL・動的頂点バッファ
│   ├── zenoo_font.c           # SDF アトラス・stb_truetype 統合
│   └── zenoo_audio.c          # miniaudio オーディオブリッジ
├── lib/                       # Pure Ruby クラスライブラリ
│   ├── zenoo.rb               # エントリポイント
│   └── zenoo/
│       ├── window.rb          # メインループ & 描画 DSL
│       ├── canvas.rb          # HTML5 Canvas 互換ベクター API & 耳刈り取り
│       ├── collision.rb       # GJK / SAT 2D 凸図形衝突判定
│       ├── font.rb            # フォント & テキスト配置 API
│       ├── gui.rb             # 即時モード GUI ウィジェット & ウィンドウ
│       ├── input.rb           # キーボード・マウス・ゲームパッド入力
│       ├── color.rb           # 色操作 & プリセット
│       ├── image.rb           # テクスチャ、sub_image & オフスクリーン FBO
│       ├── shader.rb          # カスタムシェーダー管理
│       ├── sound.rb           # サウンド再生 (Sound)
│       ├── sound_effect.rb    # 動的波形合成 (SoundEffect)
│       ├── backend.rb         # CRuby / Spinel 抽象化バックエンド
│       └── layout.rb          # レイアウトヘルパー
├── ext/                       # バインディング
│   ├── zenoo/                 # CRuby C 拡張 (mkmf)
│   └── spinel/                # Spinel AOT コンパイル用グルー
├── patches/                   # 外部依存 (Spinel 等) 向けパッチ
│   ├── README.md              # パッチ概要・適用手順
│   ├── 0001-fix-sp_slab-emscripten-wasm-memory.patch # Wasm メモリ肥大化対策
│   └── 0002-fix-sp_fiber-emscripten-stack.patch      # Fiber スタック確保パッチ
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

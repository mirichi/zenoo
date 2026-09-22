# Zenoo (ぜぬー) - 2D Micro Engine for Ruby

**Zenoo** は、**Pure Ruby** の親しみやすい記述力と、**Spinel AOT コンパイラ** による C / WebAssembly への直接トランスパイル、そして **OpenGL 3.3 / WebGL 2.0** によるハードウェアアクセラレーションを融合させた、超軽量・ハイパフォーマンスな次世代 2D ゲーム＆グラフィックスエンジンです。

DXRuby や Raylib に着想を得た直感的な API を備え、デスクトップ（CRuby / ネイティブバイナリ）でも Web ブラウザ（Wasm / スマホ対応）でも、まったく同一の Ruby コードが 60fps で軽快に動作します。

---

## 🌟 主な特徴

1. **Pure Ruby 記述 $\to$ Spinel AOT による Wasm / ネイティブ超高速実行**
   - ゲームロジック、UI、シェーダー管理、フォントレイアウト、ベクターテセレーションのすべてを Pure Ruby で記述。
   - Spinel AOT コンパイラによって C 言語に変換され、WebAssembly（Wasm）またはネイティブ ELF/EXE として高速実行。

2. **極小 C マイクロカーネル & WebGL 2.0 インスタンス描画**
   - C 言語コア（約 1,000 行）は「ウィンドウ管理」「入力」「Quad バッチ描画（GPU Instancing）」「テクスチャ・FBO」「シェーダー Uniform 転送」のみを担当。
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

---

## 🎮 WebAssembly ショーケース (デモ一覧)

リポジトリ内の `docs/` ディレクトリに、GitHub Pages 向けにビルド済みの 4 つのインタラクティブデモが収録されています。

| デモ名 | URL | 内容 |
|---|---|---|
| **Zenoo Portal** | `docs/index.html` | 全デモを一覧・起動できるポータルハブ |
| **Survival Shooting** | `docs/game/` | 群がる敵を倒しオーブで強化する 2D サバイバルアクション |
| **Immediate Mode GUI** | `docs/gui/` | Pure Ruby 即時モード GUI（ボタン・スライダー・SDF カード） |
| **SDF Font & Sinclair** | `docs/font/` | SDF 動的アトラス、高品質日本語・袋文字・8x8 レトロ文字 |
| **Vector Graphics** | `docs/vector/` | Canvas 2D 互換 API、ベジエ曲線、多角形分割、グラデーション |

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

  # SDF 角丸カード (x, y, w, h, radius, color, border_width, border_color, shadow_blur)
  Window.draw_rounded_rect(100, 100, 300, 180, 16, [30, 41, 59, 255], border_width: 2, border_color: :cyan, shadow_blur: 20)

  # SDF 日本語テキスト描画
  Window.draw_text(130, 140, "こんにちは、Zenoo！", size: 24, color: :white)
  Window.draw_text(130, 180, "Time: #{t.round(2)}s", font: Font::SINCLAIR, size: 16, color: :green)

  # マウス入力
  mx, my = Input.mouse_pos
  if Input.mouse_pressed?(:left)
    Window.draw_circle(mx, my, 20, :yellow)
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
`docs/` 配下に全デモ（`game`, `gui`, `font`, `vector`）とポータル（`index.html`）が一括生成されます。

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
./build_spinel.sh examples/game_zenoo.rb
./build/game_zenoo
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
│   └── vector/                # Vector Graphics デモ
├── examples/                  # サンプルコード集
│   ├── game_zenoo.rb          # サバイバルシューティング
│   ├── demo_gui.rb            # 即時モード GUI
│   ├── demo_ttf_sdf_font.rb   # SDF フォント描画
│   ├── demo_vector_graphics.rb# ベクターグラフィックス
│   └── web/                   # Wasm 配信用 HTML シェルテンプレート
├── include/                   # C 言語ヘッダー
│   ├── zenoo.h                # マイクロカーネル C API
│   ├── stb_truetype.h         # TrueType フォントパーサー
│   └── stb_image.h            # 画像デコーダー
├── src/                       # C 言語マイクロカーネル実装
│   ├── zenoo_core.c           # ウィンドウ・入力・イベント
│   ├── zenoo_gfx.c            # Quad バッチ・GPU Instancing・GLSL
│   └── zenoo_font.c           # SDF アトラス・stb_truetype 統合
├── lib/                       # Pure Ruby クラスライブラリ
│   ├── zenoo.rb               # エントリポイント
│   └── zenoo/
│       ├── window.rb          # メインループ & 描画 DSL
│       ├── canvas.rb          # HTML5 Canvas 互換ベクター API & 耳刈り取り
│       ├── font.rb            # フォント & テキスト配置 API
│       ├── gui.rb             # 即時モード GUI ウィジェット
│       ├── input.rb           # キーボード・マウス・ゲームパッド入力
│       ├── color.rb           # 色操作 & プリセット
│       ├── image.rb           # テクスチャ & オフスクリーン FBO
│       └── shader.rb          # カスタムシェーダー管理
├── ext/                       # バインディング
│   ├── zenoo/                 # CRuby C 拡張 (mkmf)
│   └── spinel/                # Spinel AOT コンパイル用グルー
├── server.rb                  # 統合開発サーバー (docs / wasm 切り替え対応)
├── build_pages.sh             # GitHub Pages 全デモ一括ビルドスクリプト
├── build_wasm.sh              # 単体 Wasm ビルドスクリプト
├── build.bat / build.sh       # CRuby C 拡張ビルドスクリプト
└── README.md                  # 本ドキュメント
```

---

## 📜 ライセンス

MIT License

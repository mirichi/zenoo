# Zenoo (ぜぬー) - 2D Micro Engine for Ruby

C言語 (GLFW + OpenGL 3.3 Core) の極小マイクロカーネルと、Pure Ruby で記述されたシェーダー＆描画DSLで構築された、超軽量・高性能な2Dゲームエンジンです。
DXRuby の手軽な精神を継承しつつ、現代的な SDF (Signed Distance Field) 描画と自動GCリソース管理を備えています。

---

## 🌟 特徴

1. **極小Cマイクロカーネル**
   - C言語側は「ウィンドウ制御」「入力」「Quadバッチ送出（GPU Instancing）」「テクスチャ/FBO」「シェーダーUniform転送」「GCトリガー」のみを担当。
   - 不要な描画プリミティブやフォントテーブル、個別関数を徹底的に削ぎ落としたシンプルな設計。

2. **SDFシェーダーも描画ロジックも Pure Ruby で完結**
   - GLSLシェーダーコードは Ruby のヒアドキュメントとして管理 (`lib/zenoo/shaders/sdf_card_shader.rb`)。
   - Ruby 側から自由にシェーダーのパラメータ調整や新規シェーダーの追加が可能。

3. **Ruby の GC と連動した OpenGL リソース管理**
   - CRuby の `TypedData_Wrap_Struct` による安全なライフサイクル管理。
   - `Image` や `Shader` オブジェクトが Ruby の GC に回収されると、自動的に `glDeleteTextures` / `glDeleteProgram` を実行。
   - メモリ逼迫時に言語側の GC をキックするフック (`zen_set_gc_trigger_callback`) を実装。

4. **DXRuby風の直感的かつ柔軟な API**
   - `Window.loop { Window.draw_card(...) }` による手軽な記述。
   - シンボル対応の入力 API (`Input.key_push?(:space)`, `Input.mouse_pos`)。

---

## 📂 ディレクトリ構成

```
scratch/zenoo/
├── ext/
│   └── zenoo/
│       ├── extconf.rb         # mkmf ビルド設定
│       ├── zenoo_all.c        # Unity build (高速・安全リンク)
│       └── zenoo_ext.c        # CRuby C拡張バインディング (TypedData & GC連携)
├── include/
│   ├── zenoo.h                # マイクロカーネル C APIヘッダー
│   ├── glad/glad.h
│   ├── GLFW/
│   └── stb_image.h
├── src/
│   ├── glad.c                 # OpenGL 3.3 Core ローダー
│   ├── zenoo_core.c           # ウィンドウ & 入力 & 時間管理
│   └── zenoo_gfx.c            # 汎用Quadバッチ & テクスチャ & FBO & シェーダー
├── lib/
│   ├── zenoo.rb               # エントリポイント
│   └── zenoo/
│       ├── image.rb           # 画像 & オフスクリーン描画 (FBO)
│       ├── input.rb           # キー & マウス入力
│       ├── shader.rb          # 汎用カスタムシェーダー管理
│       ├── window.rb          # DXRuby風メインループ & 描画DSL
│       └── shaders/
│           └── sdf_card_shader.rb # Ruby定義の万能SDFシェーダー (角丸/枠/影)
├── examples/
│   ├── demo_ruby_sdf.rb       # Ruby側SDFシェーダーによる対話型デモ
│   └── test_gc.rb             # 2.0GB相当のテクスチャ大量生成・GC自動回収テスト
├── build.bat                  # C拡張ビルドスクリプト (Windows)
└── build.sh                   # C拡張ビルドスクリプト (Linux)
```

---

## 🚀 ビルドと実行

### 1. ビルド (Windows / ucrt64)
```cmd
cd C:\Users\sawar\.gemini\antigravity\scratch\zenoo
build.bat
```

### 2. サンプルの実行

#### SDF インタラクティブデモ
```cmd
ruby -Ilib examples\demo_ruby_sdf.rb
```
マウスポインタに追従する発光カード、回転する角丸カード、ブラーのかかったドロップシャドウをリアルタイム描画します。

#### GC 連動自動解放テスト
```cmd
ruby -Ilib examples\test_gc.rb
```
1024x1024 (約4MB) のテクスチャ 500枚（計 2.0GB）を連続生成・解放し、VRAM が即座にクリーンアップされることを検証します。

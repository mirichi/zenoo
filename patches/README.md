# Spinel 向けパッチ一覧 (Patches for Spinel)

Zenoo を WebAssembly (Emscripten / ブラウザ) 環境向けにビルドする際、依存コンパイラである Spinel に対して適用しているパッチの記録です。

> [!NOTE]
> 現在の Spinel (`020275b35`) では、コンパイラ本体 (`src/`) へのパッチはすべて不要になりました。必要なのは Emscripten ランタイム向けの下記 2 点のみです。
> なお、ビルド時に `-D__wasi__` を指定して代用すると `sp_crypto.c` で未宣言の `getentropy()` 呼び出しとなりコンパイルエラーになるほか、タイムゾーンや I/O などの分岐も WASI 扱いになるため、`__EMSCRIPTEN__` 用のパッチを直接適用しています。

---

## 0001-fix-sp_slab-emscripten-wasm-memory.patch

- **対象ファイル**: `~/spinel/lib/sp_slab.c`
- **対象バージョン**: Spinel master (commit: `020275b35` / 2026.10.25+4900)

### 発生していた現象
- ブラウザ上でデモ（GUI、Font、Game 等）を開いた際、**初回起動だけでタブのメモリ消費が 700MB に達し**、ページ遷移（戻る・進む）を繰り返すたびに **1.3GB → 1.9GB** とメモリが累積・肥大化する現象が発生していました。

### 原因
- Spinel の GC スラブアロケータ (`sp_slab.c`) では、起動時にアドレス空間を事前予約する処理があります。
- WASI (`__wasi__`) 向けには「Wasm のリニアメモリは拡張しかできないため 64MB だけ確保する」という専用ルートが用意されていましたが、Emscripten 向けの条件分岐が漏れていました。
- そのため、Emscripten (`__EMSCRIPTEN__`) 環境でもネイティブ 32bit Linux 向けのフォールバック処理に入り、起動時に `mmap(516MB)` を発行していました。
- Emscripten の `mmap` は WebAssembly のリニアメモリを即座に強制拡張 (`memory.grow()`) するため、起動直後に 516MB 以上のメモリが一気にコミットされていました。

### 修正内容
`sp_slab.c` の予約分岐条件を以下のように変更しました：

```c
// 修正前:
#ifdef __wasi__

// 修正後:
#if defined(__wasi__) || defined(__EMSCRIPTEN__)
```

これにより、Emscripten 環境でも 516MB の巨大 `mmap` が発行されず、Wasm 専用の安全なメモリ管理が行われるようになります。

---

## 0002-fix-sp_fiber-emscripten-stack.patch

- **対象ファイル**: `~/spinel/lib/sp_fiber.c`
- **対象バージョン**: Spinel master (commit: `020275b35` / 2026.10.25+4900)

### 発生していた現象
- WebAssembly (Emscripten / ブラウザ) 環境において、アプリ起動時にクラッシュまたはスタックオーバーフロー等の例外が発生し、正常にメインループが開始しない現象が発生していました。

### 原因
- Spinel のランタイム起動処理 (`sp_main_stack_run`) では、メイン処理を実行する前に `mmap` で独自のスタック領域を確保してスタックスイッチを行おうとします。
- しかし WebAssembly / Emscripten 環境では OS レベルのスタック切り替え（コンテキストスイッチ）に対応していません。
- WASI 向けにはスタックスイッチを行わずに直接 `body()` を呼び出すバイパスルートがありましたが、Emscripten 向けの分岐が漏れていました。

### 修正内容
`sp_fiber.c` のスタック切り替えバイパス条件に `__EMSCRIPTEN__` を追加しました：

```c
// 修正前:
void sp_main_stack_run(void (*body)(void)) {

// 修正後:
void sp_main_stack_run(void (*body)(void)) {
#if defined(__wasi__) || defined(__EMSCRIPTEN__)
  body();
  return;
#else
  // 通常のスタックスイッチ処理
#endif
}
```

これにより、Emscripten 環境でも不要・非対応なスタック切り替えを行わず、安全にメイン処理が起動するようになります。

---

## (廃止・適用不要) 0003-fix-avoid-qualifying-own-native-struct-and-alias.patch

- **対象ファイル**: `~/spinel/src/analyze.c`, `~/spinel/src/analyze_scope.c`
- **状態**: **適用不要**（Spinel 上流 `020275b35` での改善、および Zenoo 側 `lib/zenoo.rb` / `lib/zenoo/image.rb` における `RUBY_ENGINE == "spinel"` への統一により解消）

---

### パッチの適用手順

Spinel ディレクトリで以下のコマンドを実行します：

```bash
cd ~/spinel
git apply /path/to/zenoo/patches/0001-fix-sp_slab-emscripten-wasm-memory.patch
git apply /path/to/zenoo/patches/0002-fix-sp_fiber-emscripten-stack.patch
```

適用後は、Zenoo リポジトリ側でキャッシュをクリアして再ビルドを行います（`lib/*.c` のみ変更のため、`bin/spinel` 本体の再ビルドは不要です）：
```bash
# Zenoo のキャッシュクリア & Wasm 再ビルド
rm -rf build/wasm_cache
./build_pages.sh
```

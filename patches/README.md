# Spinel 向けパッチ一覧 (Patches for Spinel)

Zenoo を WebAssembly (Emscripten / ブラウザ) 環境向けにビルドする際、依存コンパイラである [Spinel](https://github.com/...) に対して適用しているパッチの記録です。

---

## 0001-fix-sp_slab-emscripten-wasm-memory.patch

- **対象ファイル**: `~/spinel/lib/sp_slab.c`
- **対象バージョン**: Spinel master (commit: `abbfc73b0` / 2026.10.31 / 旧 `2814693f6`)

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

これにより、Emscripten 環境でも 516MB の巨大 mmap が発行されず、Wasm 専用の安全なメモリ管理が行われるようになります。

---

## 0002-fix-sp_fiber-emscripten-stack.patch

- **対象ファイル**: `~/spinel/lib/sp_fiber.c`
- **対象バージョン**: Spinel master (commit: `abbfc73b0` / 2026.10.31 / 旧 `2814693f6`)

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
```

これにより、Emscripten 環境でも不要・非対応なスタック切り替えを行わず、安全にメイン処理が起動するようになります。

---

## 0003-fix-avoid-qualifying-own-native-struct-and-alias.patch

- **対象ファイル**: `~/spinel/src/analyze.c`, `~/spinel/src/analyze_scope.c`
- **対象バージョン**: Spinel master (commit: `abbfc73b0` / 2026.10.31 / 旧 `2814693f6`)

> [!NOTE]
> 以前含まれていた「自身の `native_struct` との衝突誤認（`qc_native_leaf_declared`）」は、Spinel 公式 upstream のコミット `6712b2678` にて本体に取り込まれました。そのため本パッチでは、残る「クラスエイリアス衝突誤認」および「名前修飾後のクラスに対する `native_struct` 紐付け処理」に絞り込まれています。

### 発生していた現象
- `Zenoo::Image` などのクラスで `native_struct` を定義し、Ruby 側で同名クラスを開いてメソッド（`initialize` 等）を追加している場合、または `Image = Zenoo::Image` のようにトップレベルで定数エイリアスを定義している場合、さらに別スコープに同名モジュール（`Zenoo::Native::Image` 等）が存在する場合に、ブラウザ実行時や実行時に以下のエラーが発生していました：
  ```
  wrong number of arguments (given 2, expected 0) (ArgumentError)
  ```
  また、生成される Wasm バイナリサイズが正常時（約 2.5MB）から激減（約 800KB）し、必要なコードが正しくリンクされない問題が発生していました。

### 原因
- Spinel のクラス名衝突解決パス（`qualify_colliding_classes`）および FFI 宣言登録（`register_ffi_decls`）において、以下の誤判定と欠落が存在していました：
  1. **クラスエイリアスとの衝突誤認**:
     トップレベルで `Image = Zenoo::Image` のようにクラスエイリアスを定義した際、`qc_leaf_elsewhere` がクラス代入を「同名の通常定数との衝突」と誤認し、再度クラス修飾名を強制書き換えしていました。
  2. **修飾されたクラスに対する `native_struct` の紐付け欠落**:
     同名リーフ（`Zenoo::Image` と `Zenoo::Native::Image` など）によってクラスが修飾名（例: `Zenoo__Image`）に改名された際、`analyze_scope.c` の `native_struct` 登録処理が素のリーフ名（`"Image"`）だけでクラスを検索していたため、改名後の実クラスを見失って空のダミークラスを新規作成し、そこに `native_struct` を紐付けてしまっていました。これによりプログラム本体が使う修飾クラスはネイティブ構造体との連携が切断され、引数0個の空クラスコンストラクタが生成されていました。

### 修正内容
1. `src/analyze.c`:
   - `qc_is_class_alias`: 定数代入の右辺が同一クラスを参照しているエイリアスであるかを判定し、エイリアスによる重複を衝突判定（`qc_leaf_elsewhere`）から除外。
2. `src/analyze_scope.c`:
   - `register_ffi_decls` の pre-scan および main walk において、`constant_path` の `qc_ruby_name` と `clsname` が一致するクラスノードが存在する場合は、修飾後のクラス名を取得して登録・バインドを行うよう修正。これにより、クラスが名前修飾（改名）された場合でも C のネイティブ構造体との紐付けが一切失われなくなります。

---

### パッチの適用手順

Spinel ディレクトリで以下のコマンドを実行します：

```bash
cd ~/spinel
git apply /path/to/zenoo/patches/0001-fix-sp_slab-emscripten-wasm-memory.patch
git apply /path/to/zenoo/patches/0002-fix-sp_fiber-emscripten-stack.patch
git apply /path/to/zenoo/patches/0003-fix-avoid-qualifying-own-native-struct-and-alias.patch
```

適用後は、Spinel バイナリを再ビルドし、Zenoo リポジトリ側でキャッシュをクリアして再ビルドを行います：
```bash
# Spinel 本体の再ビルド
make -C ~/spinel bin/spinel

# Zenoo のキャッシュクリア & Wasm 再ビルド
rm -rf build/wasm_cache
./build_pages.sh
```

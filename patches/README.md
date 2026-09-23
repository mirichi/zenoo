# Spinel 向けパッチ一覧 (Patches for Spinel)

Zenoo を WebAssembly (Emscripten / ブラウザ) 環境向けにビルドする際、依存コンパイラである [Spinel](https://github.com/...) に対して適用しているパッチの記録です。

---

## 0001-fix-sp_slab-emscripten-wasm-memory.patch

- **対象ファイル**: `~/spinel/lib/sp_slab.c`
- **対象バージョン**: Spinel master (commit: `fe340608` 付近)

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

### パッチの適用手順

Spinel ディレクトリで以下のコマンドを実行します：

```bash
cd ~/spinel
git apply /path/to/zenoo/patches/0001-fix-sp_slab-emscripten-wasm-memory.patch
```

または手動で `~/spinel/lib/sp_slab.c` の 245 行目付近を上記のように修正してください。

適用後は、Zenoo リポジトリ側でキャッシュをクリアして再ビルドを行います：
```bash
rm -f build/wasm_cache/rt/sp_slab.o build/wasm_cache/libspinel_rt.a
./build_pages.sh
```

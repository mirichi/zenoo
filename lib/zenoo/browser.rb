# frozen_string_literal: true

module Zenoo
  # ==============================================================================
  # Zenoo::Browser
  # Webブラウザ / スマホ環境との相互運用ブリッジ。
  # Wasm環境ではブラウザのJSエンジンを直接評価し、DOM/環境情報を取得・制御します。
  # 非Wasm環境（CRuby / Win32等）では安全にフォールバック（ダミー動作）します。
  # ==============================================================================
  module Browser
    # ブラウザ上で任意の JavaScript コードを評価・実行します（戻り値は取得しない副作用用）。
    # 非 Wasm 環境では何も行いません。
    #
    # - `code` (`String`): 実行する JavaScript コード文字列
    def self.eval(code)
      Native::Browser.raw_eval(code.to_s)
    end

    # ブラウザ上で JavaScript 式を評価し、数値として結果を取得します。
    # 非 Wasm 環境では `0.0` 等のフォールバック値を返します。
    #
    # - `code` (`String`): 評価する JavaScript 式文字列
    # - 戻り値: `Float`
    def self.eval_num(code)
      Native::Browser.raw_eval_num(code.to_s)
    end

    # ブラウザ上で JavaScript 式を評価し、文字列として結果を取得します。
    # 非 Wasm 環境では空文字列を返します。
    #
    # - `code` (`String`): 評価する JavaScript 式文字列
    # - 戻り値: `String`
    def self.eval_str(code)
      Native::Browser.raw_eval_str(code.to_s)
    end

    # タブ/ページが表示されているか (document.visibilityState === 'visible')
    #
    # - 戻り値: `Boolean` 表示中なら `true`、バックグラウンドタブ等なら `false`
    def self.visible?
      Native::Browser.visible?
    end

    # セーフエリアインセット [left, top, right, bottom] (仮想解像度px)
    # スマホのノッチやホームバー等を避けるための余白幅を論理ピクセル単位で返します。
    #
    # - 戻り値: `Array<Float>` `[left, top, right, bottom]`
    def self.safe_area
      [
        Native::Browser.raw_safe_area_left.to_f,
        Native::Browser.raw_safe_area_top.to_f,
        Native::Browser.raw_safe_area_right.to_f,
        Native::Browser.raw_safe_area_bottom.to_f
      ]
    end

    # 安全表示領域の矩形 [x, y, w, h] (仮想解像度px)
    # セーフエリアインセットを除いた、UI を安全に配置できる領域の矩形を返します。
    #
    # - 戻り値: `Array<Float>` `[x, y, width, height]`
    def self.safe_area_rect
      l, t, r, b = safe_area
      win_w = Window.width.to_f
      win_h = Window.height.to_f
      [l, t, win_w - l - r, win_h - t - b]
    end
  end
end

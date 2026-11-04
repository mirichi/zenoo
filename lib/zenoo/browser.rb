# frozen_string_literal: true

module Zenoo
  # ==============================================================================
  # Zenoo::Browser
  # Webブラウザ / スマホ環境との相互運用ブリッジ。
  # Wasm環境ではブラウザのJSエンジンを直接評価し、DOM/環境情報を取得・制御します。
  # 非Wasm環境（CRuby / Win32等）では安全にフォールバック（ダミー動作）します。
  # ==============================================================================
  module Browser
    def self.eval(code)
      Native::Browser.raw_eval(code.to_s)
    end

    def self.eval_num(code)
      Native::Browser.raw_eval_num(code.to_s)
    end

    def self.eval_str(code)
      Native::Browser.raw_eval_str(code.to_s)
    end

    # タブ/ページが表示されているか (document.visibilityState === 'visible')
    def self.visible?
      Native::Browser.visible?
    end

    # セーフエリアインセット [left, top, right, bottom] (仮想解像度px)
    def self.safe_area
      [
        Native::Browser.raw_safe_area_left.to_f,
        Native::Browser.raw_safe_area_top.to_f,
        Native::Browser.raw_safe_area_right.to_f,
        Native::Browser.raw_safe_area_bottom.to_f
      ]
    end

    # 安全表示領域の矩形 [x, y, w, h] (仮想解像度px)
    def self.safe_area_rect
      l, t, r, b = safe_area
      win_w = Window.width.to_f
      win_h = Window.height.to_f
      [l, t, win_w - l - r, win_h - t - b]
    end
  end
end

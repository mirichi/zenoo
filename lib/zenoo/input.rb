module Zenoo
  module Input
    # キーシンボルからGLFWキーコードへのマッピング
    KEY_MAP = {
      space: 32,
      escape: 256,
      enter: 257,
      tab: 258,
      backspace: 259,
      right: 262,
      left: 263,
      down: 264,
      up: 265,
      f11: 290,
    }

    # アルファベットキー (a..z)
    (?a..?z).each do |ch|
      KEY_MAP[ch.to_sym] = ch.upcase.ord
    end

    # 数字キー (0..9)
    (?0..?9).each do |ch|
      KEY_MAP[ch.to_sym] = ch.ord
    end

    MOUSE_MAP = {
      left: 0,
      right: 1,
      middle: 2
    }

    def self.resolve_key(key)
      KEY_MAP[key] || key.to_i
    end

    def self.resolve_mouse(button)
      MOUSE_MAP[button] || button.to_i
    end

    # 押されている状態 (持続)
    def self.key_pressed?(key)
      Native::Input.key_pressed?(resolve_key(key))
    end

    # 押した瞬間 (トリガー)
    def self.key_push?(key)
      Native::Input.key_push?(resolve_key(key))
    end

    # 離した瞬間 (リリース)
    def self.key_release?(key)
      Native::Input.key_release?(resolve_key(key))
    end

    # マウス座標
    def self.mouse_x
      Native::Input.mouse_x
    end

    def self.mouse_y
      Native::Input.mouse_y
    end

    def self.mouse_pos
      [Native::Input.mouse_x, Native::Input.mouse_y]
    end

    def self.mouse_pressed?(button = :left)
      Native::Input.mouse_pressed?(resolve_mouse(button))
    end

    def self.mouse_push?(button = :left)
      Native::Input.mouse_push?(resolve_mouse(button))
    end

    def self.mouse_release?(button = :left)
      Native::Input.mouse_release?(resolve_mouse(button))
    end
  end
end

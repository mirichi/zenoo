# frozen_string_literal: true

module Zenoo
  module Font
    # 8x8 ASCII ビットマップフォント (32..126)
    # 760バイト分の 16進文字列
    FONT_HEX = "0000000000000000181818181800180066662400000000006c6cfe6cfe6c6c00187e183c187e180000c6cc183066c600386c3876dccc760018183000000000000c18303030180c0030180c0c0c18300000663cff3c6600000018187e1818000000000000001818300000007e000000000000000000181800060c183060c080007cc6ced6e6c67c001838181818187e007cc6061c3066fe007cc6063c06c67c001c3c6cccfe0c1e00fec0fc0606c67c007cc6c0fcc6c67c00fec60c18303030007cc6c67cc6c67c007cc6c67e060c7800001818001818000000181800181830000c18306030180c0000007e007e00000030180c060c1830007cc60c18180018007cc6dededcc07c00386cc6c6fec6c600fc66667c6666fc003c66c0c0c0663c00f86c6666666cf800fe6268786862fe00fe6268786860f0003c66c0c0ce663e00c6c6c6fec6c6c6007e18181818187e001e0c0c0ccccc7800e6666c786c66e600f06060606266fe00c6eefefed6c6c600c6e6f6fedecec6007cc6c6c6c6c67c00fc66667c6060f0007cc6c6c6d6de7c0efc66667c6c66e6007cc660380cc67c007e7e5a1818183c00c6c6c6c6c6c67c00c6c6c6c6c66c3800c6c6d6fefeeec600c6c66c386cc6c6006666663c18183c00fec60c183063fe003c30303030303c00c06030180c0602003c0c0c0c0c0c3c0010386cc60000000000000000000000ff30180c00000000000000780c7ccc7600e0607c666666dc00000078ccc0cc78001c0c7ccccccc7600000078ccfcc07800386c60f06060f000000076cccc7c0cf8e0606c766666e6001800381818183c0006000e060666663ce060666c786ce6003818181818183c000000e6ffdbc9c9000000dc666666660000007cc6c6c67c000000dc66667c60f0000076cccc7c0c1e0000dc766060f00000007cc07c06fc0010307c30303418000000cccccccc76000000c6c6c66c38000000c6c6d6fe6c000000c66c386cc6000000c6c6ce76067c0000fc983064fc000e18187018180e0018181818181818007018180e1818700076dc000000000000".freeze

    def self.hex_val(byte)
      if byte >= 48 && byte <= 57
        byte - 48
      elsif byte >= 97 && byte <= 102
        byte - 87
      elsif byte >= 65 && byte <= 70
        byte - 55
      else
        0
      end
    end

    def self.get_font_byte(offset)
      h_idx = offset * 2
      (hex_val(FONT_HEX.getbyte(h_idx)) << 4) | hex_val(FONT_HEX.getbyte(h_idx + 1))
    end

    def self.draw_text(x, y, text, size: 16, color: :white)
      return unless text
      text_str = text.to_s
      len = text_str.length
      return if len == 0

      scale = size.to_f / 8.0
      char_w = 8.0 * scale
      pixel_w = scale

      cur_x = x.to_f
      cur_y = y.to_f

      i = 0
      while i < len
        ch_code = text_str.getbyte(i)
        if ch_code == 10 # '\n'
          cur_x = x.to_f
          cur_y += 10.0 * scale
          i += 1
          next
        end

        if ch_code >= 32 && ch_code <= 126
          font_offset = (ch_code - 32) * 8
          row = 0
          while row < 8
            byte = get_font_byte(font_offset + row)
            if byte != 0
              py = cur_y + row * pixel_w
              col = 0
              while col < 8
                if ((byte >> (7 - col)) & 1) == 1
                  # 連続するピクセルをまとめて描画
                  run_start = col
                  while col < 8 && ((byte >> (7 - col)) & 1) == 1
                    col += 1
                  end
                  run_len = col - run_start
                  Window.draw_rect(cur_x + run_start * pixel_w, py, run_len * pixel_w, pixel_w, color)
                else
                  col += 1
                end
              end
            end
            row += 1
          end
        end

        cur_x += char_w
        i += 1
      end
    end
  end
end

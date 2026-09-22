# ====================================================
# Zenoo バインダのロード
# ====================================================
if defined?(RUBY_ENGINE) && RUBY_ENGINE == "spinel"
  # Spinel AOT 環境
  require_relative '../ext/spinel/zenoo_native'
else
  # CRuby C拡張 (.so) 環境
  so_path = File.expand_path("../ext/zenoo/zenoo.so", __dir__)
  if File.exist?(so_path)
    require so_path
  else
    require 'zenoo'
  end
end

# ====================================================
# 共通 Ruby レイヤー (CRuby / Spinel 完全共通)
# ====================================================
require_relative 'zenoo/color'
require_relative 'zenoo/font'
require_relative 'zenoo/shader'
require_relative 'zenoo/shaders/sdf_card_shader'
require_relative 'zenoo/shaders/sdf_font_shader'
require_relative 'zenoo/image'
require_relative 'zenoo/input'
require_relative 'zenoo/window'
require_relative 'zenoo/canvas'
require_relative 'zenoo/gui'

# トップレベルへの便利エイリアス (DXRubyスタイル)
Window     = Zenoo::Window     unless defined?(Window)
Canvas     = Zenoo::Canvas     unless defined?(Canvas)
Input      = Zenoo::Input      unless defined?(Input)
Image      = Zenoo::Image      unless defined?(Image)
Shader     = Zenoo::Shader     unless defined?(Shader)
Color      = Zenoo::Color      unless defined?(Color)
Font       = Zenoo::Font       unless defined?(Font)
GUI        = Zenoo::GUI        unless defined?(GUI)

# ====================================================
# Zenoo バインダのロード
# ====================================================
if defined?(RUBY_ENGINE) && RUBY_ENGINE == "spinel"
  # Spinel AOT 環境
  require_relative '../ext/spinel/zenoo_native'
else
  # CRuby C拡張 (.so) 環境
  begin
    send(:require_relative, '../ext/zenoo/zenoo')
  rescue LoadError
    # ロードできなかった場合は呼び出し側で処理
  end
end

# ==========================================
# 共通 Ruby レイヤー (CRuby / Spinel 完全共通)
# ==========================================
require_relative 'zenoo/color'
require_relative 'zenoo/backend'
require_relative 'zenoo/font'
require_relative 'zenoo/shaders/default_shaders'
require_relative 'zenoo/shaders/sdf_card_shader'
require_relative 'zenoo/shaders/sdf_font_shader'
require_relative 'zenoo/shader'
require_relative 'zenoo/image'
require_relative 'zenoo/input'
require_relative 'zenoo/window'
require_relative 'zenoo/canvas'
require_relative 'zenoo/gui'
require_relative 'zenoo/sound'
require_relative 'zenoo/sound_effect'
require_relative 'zenoo/collision'
require_relative 'zenoo/sprite'
require_relative 'zenoo/tilemap'
require_relative 'zenoo/physics'
require_relative 'zenoo/camera'
require_relative 'zenoo/easing'
require_relative 'zenoo/tween'
require_relative 'zenoo/mesh'
require_relative 'zenoo/profiler'

# トップレベルへの便利エイリアス (DXRubyスタイル)
Window        = Zenoo::Window        unless defined?(Window)
Canvas        = Zenoo::Canvas        unless defined?(Canvas)
Input         = Zenoo::Input         unless defined?(Input)
Image         = Zenoo::Image         unless defined?(Image)
Mesh          = Zenoo::Mesh          unless defined?(Mesh)
Shader        = Zenoo::Shader        unless defined?(Shader)
Color         = Zenoo::Color         unless defined?(Color)
Font          = Zenoo::Font          unless defined?(Font)
GUI           = Zenoo::GUI           unless defined?(GUI)
Audio         = Zenoo::Audio         unless defined?(Audio)
Sound         = Zenoo::Sound         unless defined?(Sound)
SoundEffect   = Zenoo::SoundEffect   unless defined?(SoundEffect)
Collision     = Zenoo::Collision     unless defined?(Collision)
Physics       = Zenoo::Physics       unless defined?(Physics)
Camera2D      = Zenoo::Camera2D      unless defined?(Camera2D)
Easing        = Zenoo::Easing        unless defined?(Easing)
Tween         = Zenoo::Tween         unless defined?(Tween)
Sprite        = Zenoo::Sprite        unless defined?(Sprite)
Tilemap       = Zenoo::Tilemap       unless defined?(Tilemap)
PhysicsSprite = Zenoo::PhysicsSprite unless defined?(PhysicsSprite)
Profiler      = Zenoo::Profiler      unless defined?(Profiler)



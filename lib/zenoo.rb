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
require_relative 'zenoo/skinned_mesh'
require_relative 'zenoo/profiler'

# トップレベルへの便利エイリアス (DXRubyスタイル)
Window        = Zenoo::Window
Canvas        = Zenoo::Canvas
Input         = Zenoo::Input
Image         = Zenoo::Image
Mesh          = Zenoo::Mesh
InstanceBuffer = Zenoo::InstanceBuffer
Bone          = Zenoo::Bone
SkinnedMesh   = Zenoo::SkinnedMesh
Shader        = Zenoo::Shader
Color         = Zenoo::Color
Font          = Zenoo::Font
GUI           = Zenoo::GUI
Audio         = Zenoo::Audio
Sound         = Zenoo::Sound
SoundEffect   = Zenoo::SoundEffect
Collision     = Zenoo::Collision
Physics       = Zenoo::Physics
Camera        = Zenoo::Camera
Easing        = Zenoo::Easing
Tween         = Zenoo::Tween
Sprite        = Zenoo::Sprite
Tilemap       = Zenoo::Tilemap
PhysicsSprite = Zenoo::PhysicsSprite
Profiler      = Zenoo::Profiler

# ====================================================
# CRuby 専用 開発支援モジュール (Spinel 静的走査回避)
# ====================================================
if !(defined?(RUBY_ENGINE) && RUBY_ENGINE == "spinel")
  begin
    send(:require_relative, 'zenoo/dev')
  rescue LoadError
    # ロードできなかった場合は無視
  end
end




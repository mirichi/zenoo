require 'mkmf'

# インクルードパス
$INCFLAGS << " -I../../include -I../../include/glad"

# ソースファイル (単一コンパイル単位)
$srcs = ["zenoo_all.c"]

# Windows (MinGW/UCRT) リンクライブラリ
if Gem.win_platform?
  candidates = []
  candidates << ENV['MSYSTEM_PREFIX'] if ENV['MSYSTEM_PREFIX']
  ruby_prefix = RbConfig::CONFIG['prefix']
  candidates << File.join(ruby_prefix, 'msys64/ucrt64')
  candidates << File.join(ruby_prefix, 'msys64/mingw64')
  candidates << "C:/msys64/ucrt64"
  candidates << "C:/msys64/mingw64"

  ucrt_base = candidates.find { |p| p && Dir.exist?(p) }
  if ucrt_base
    inc_dir = File.join(ucrt_base, 'include')
    lib_dir = File.join(ucrt_base, 'lib')
    $INCFLAGS << " -I#{inc_dir}" if Dir.exist?(inc_dir)
    $LDFLAGS << " -L#{lib_dir}" if Dir.exist?(lib_dir)
  end

  $libs << " -lglfw3 -lopengl32 -lgdi32 -luser32 -lkernel32 -lshell32 -lwinmm -limm32 -lole32"
else
  $libs << " -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -ldl -lm"
end

create_makefile('zenoo/zenoo')

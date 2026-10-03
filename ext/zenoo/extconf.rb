require 'mkmf'

# インクルードパス
$INCFLAGS << " -I../../include -I../../include/glad"

# ソースファイル (単一コンパイル単位)
$srcs = ["zenoo_all.c"]

# Windows (MinGW/UCRT) リンクライブラリ
if Gem.win_platform?
  $INCFLAGS << " -IC:/Ruby34-x64/msys64/ucrt64/include"
  $LDFLAGS << " -LC:/Ruby34-x64/msys64/ucrt64/lib"
  $libs << " -lglfw3 -lopengl32 -lgdi32 -luser32 -lkernel32 -lshell32 -lwinmm -limm32 -lole32"
else
  $libs << " -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -ldl -lm"
end

create_makefile('zenoo/zenoo')

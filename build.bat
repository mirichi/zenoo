@echo off
set "PATH=C:\Ruby34-x64\msys64\ucrt64\bin;C:\Ruby34-x64\msys64\usr\bin;C:\Ruby34-x64\bin;%PATH%"

echo [Building Zenoo C Extension...]
cd ext\zenoo
ruby extconf.rb
make clean
make
if errorlevel 1 (
    echo [ERROR] Build failed!
    cd ..\..
    exit /b 1
)
cd ..\..
echo.
echo =======================================================
echo  Zenoo C Extension (zenoo.so) Build Successful!
echo  Run demos:
echo    ruby -Ilib examples\game_zenoo.rb
echo    ruby -Ilib examples\demo_vector_graphics.rb
echo    ruby -Ilib examples\demo_gui.rb
echo    ruby -Ilib examples\demo_window_clip.rb
echo    ruby -Ilib examples\demo_texture_atlas.rb
echo    ruby -Ilib examples\demo_ttf_sdf_font.rb
echo =======================================================

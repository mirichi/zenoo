@echo off
setlocal

rem MSYS2 / DevKit 環境の有効化 (未設定の場合)
where gcc >nul 2>&1
if errorlevel 1 (
    where ridk >nul 2>&1
    if not errorlevel 1 (
        call ridk enable >nul 2>&1
    ) else (
        for /f "delims=" %%i in ('ruby -rrbconfig -e "puts RbConfig::CONFIG['prefix'].gsub('/', '\\')" 2^>nul') do (
            if exist "%%i\msys64\ucrt64\bin" (
                set "PATH=%%i\msys64\ucrt64\bin;%%i\msys64\usr\bin;%PATH%"
            )
        )
    )
)

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

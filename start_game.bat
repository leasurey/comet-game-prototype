@echo off
rem COMET launcher - double click to run the game.
rem Kept ASCII-only on purpose: no non-ASCII path text inside, so no codepage corruption.
rem %~dp0 = directory of this .bat itself, therefore the Chinese project path never appears here.

chcp 65001 >nul 2>&1
setlocal

set "PROJ_DIR=%~dp0"
set "GODOT_EXE=%PROJ_DIR%..\tools\Godot\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
    echo.
    echo [ERROR] Godot executable not found:
    echo   %GODOT_EXE%
    echo.
    echo Expected layout:
    echo   <workspace>\comet-game-prototype\  <- this project
    echo   <workspace>\tools\Godot\Godot_v4.7.2-stable_win64.exe
    echo.
    echo Download Godot 4.7.2-stable from:
    echo   https://github.com/godotengine/godot/releases/tag/4.7.2-stable
    echo.
    pause
    exit /b 1
)

echo Starting COMET ...
"%GODOT_EXE%" --path "%PROJ_DIR%"

endlocal

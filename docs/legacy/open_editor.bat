@echo off
rem COMET launcher - double click to open the project in Godot editor.
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
    pause
    exit /b 1
)

echo Opening COMET in Godot editor ...
"%GODOT_EXE%" --editor --path "%PROJ_DIR%"

endlocal

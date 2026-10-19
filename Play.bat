@echo off
rem Double-click to play the Hexhunt sandbox (needs the Godot 4.7 binary in Downloads).
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
start "" "%GODOT%" --path "%~dp0." -- --fight swampfang --cam 30,42

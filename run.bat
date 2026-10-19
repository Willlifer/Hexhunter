@echo off
rem Open the Hexhunt sandbox windowed. Extra args pass through, e.g. run.bat --fight swampfang --seed 3
if "%GODOT%"=="" set GODOT=%USERPROFILE%\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe
"%GODOT%" --path "%~dp0." -- %*

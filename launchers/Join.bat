@echo off
rem Double-click: join a friend's co-op party. Type the address their lobby shows (e.g. 192.168.1.20).
rem Put this file next to Hexhunt.exe.
set /p ADDR=Host's address:
if "%ADDR%"=="" (
  echo No address given.
  pause
  exit /b 1
)
set /p NAME=Your name (Enter for Guest):
if "%NAME%"=="" set NAME=Guest
start "" "%~dp0Hexhunt.exe" -- --join "%ADDR%" --name "%NAME%"

@echo off
rem Double-click: the lobby, already hosting a co-op party on this machine (port 24631).
rem Your friends run Join.bat and type the address the lobby shows. Put this file next to Hexhunt.exe.
set /p NAME=Your name (Enter for Host):
if "%NAME%"=="" set NAME=Host
start "" "%~dp0Hexhunt.exe" -- --host --name "%NAME%"

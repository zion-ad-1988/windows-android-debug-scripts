@echo off
setlocal
set "PATH=%~dp0scrcpy;%PATH%"
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0testApp_gui.ps1"

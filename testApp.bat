@echo off
setlocal
set "PATH=%~dp0scrcpy;%PATH%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0testApp.ps1"

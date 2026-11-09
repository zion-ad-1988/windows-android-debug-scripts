@echo off
setlocal
cd /d "%~dp0"
rem Route through the GUI-subsystem VBS launcher to avoid a console flash.
start "" wscript.exe "%~dp0testApp_gui.vbs"
endlocal
exit /b 0

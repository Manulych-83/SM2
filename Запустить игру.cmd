@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\run_game.ps1" %*
exit /b %errorlevel%

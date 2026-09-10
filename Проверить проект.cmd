@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\run_checks.ps1" -ShowResult %*
exit /b %errorlevel%

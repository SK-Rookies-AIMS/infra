@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0up_Mon.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo up_Mon failed. ExitCode=%EXIT_CODE%
pause
exit /b %EXIT_CODE%

@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0down_Fri.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo down_Fri failed. ExitCode=%EXIT_CODE%
pause
exit /b %EXIT_CODE%

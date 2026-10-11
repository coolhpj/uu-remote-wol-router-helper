@echo off
chcp 65001 >nul
setlocal
echo.
echo   UU REMOTE - Windows 快速启动
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows-launcher.ps1" %*
set "status=%ERRORLEVEL%"
if not "%status%"=="0" echo 启动未完成。错误码: %status%
echo.
pause
exit /b %status%

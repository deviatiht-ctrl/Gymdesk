@echo off
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Demann dwa Administrate...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title SecurGYM - KOREKSYON AK ANALIZ TOTAL
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0repare.ps1"
pause

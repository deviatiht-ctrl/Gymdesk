@echo off
title SecurGYM - Sevis WhatsApp (whatsapp-web.js)
cd /d "%~dp0"

set "PATH=%ProgramFiles%\nodejs;%APPDATA%\npm;%PATH%"
set "PUPPETEER_SKIP_DOWNLOAD=true"

rem 0. Verifier si sevis la ap kouri deja sou port 47812
curl -s -m 1 http://127.0.0.1:47812/health >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    exit /b 0
)

rem 1. Verifier si Node.js enstale
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%ProgramFiles%\nodejs\node.exe" (
        set "PATH=%ProgramFiles%\nodejs;%PATH%"
    ) else (
        winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements
        set "PATH=%ProgramFiles%\nodejs;%PATH%"
    )
)

rem 2. Verifier depandans npm yo
if not exist "node_modules\whatsapp-web.js" (
    call npm.cmd install
)

rem 3. Demare sevis la
node server.js

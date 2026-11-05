@echo off
title SecurGYM - Sevis WhatsApp (whatsapp-web.js)
cd /d "%~dp0whatsapp_service"

set "PATH=%ProgramFiles%\nodejs;%APPDATA%\npm;%PATH%"
set "PUPPETEER_SKIP_DOWNLOAD=true"

rem 0. Verifier si sevis la ap kouri deja sou port 47812
curl -s -m 1 http://127.0.0.1:47812/health >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [*] Sevis WhatsApp la ap kouri deja sou port 47812!
    echo [*] URL: http://127.0.0.1:47812
    echo [*] Ou ka ouvri GymDesk pou w we Kod QR la oswa estati a.
    timeout /t 3 >nul
    exit /b 0
)

echo ====================================================
echo     SecurGYM / GymDesk - Sevis WhatsApp
echo ====================================================
echo.

rem 1. Verifier si Node.js enstale
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%ProgramFiles%\nodejs\node.exe" (
        set "PATH=%ProgramFiles%\nodejs;%PATH%"
    ) else (
        echo [!] Node.js pa jwenn. N ap enstale l otomatikman...
        winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements
        if %ERRORLEVEL% NEQ 0 (
            echo Tanpri telechaje epi enstale Node.js sou https://nodejs.org
            pause
            exit /b 1
        )
        set "PATH=%ProgramFiles%\nodejs;%PATH%"
    )
)

rem 2. Verifier depandans npm yo
if not exist "node_modules\whatsapp-web.js" (
    echo [*] Enstalasyon depandans WhatsApp yo (whatsapp-web.js, express, qrcode)...
    call npm.cmd install
    if %ERRORLEVEL% NEQ 0 (
        echo [!] Ere pandan npm install.
        pause
        exit /b 1
    )
)

rem 3. Demare sevis la
echo [*] N ap demare sevis WhatsApp la sou port 47812...
echo [*] URL Sevis: http://127.0.0.1:47812
echo [*] Ou ka ouvri GymDesk pou w eskane Kod QR la nan panel Admin an.
echo.
node server.js
pause

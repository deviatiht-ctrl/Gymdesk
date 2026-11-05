@echo off
title SecurGYM - Sevis WhatsApp (whatsapp-web.js)
cd /d "%~dp0"

set "PATH=%ProgramFiles%\nodejs;%APPDATA%\npm;%PATH%"
set "PUPPETEER_SKIP_DOWNLOAD=true"

echo ====================================================
echo     SecurGYM / GymDesk - Sevis WhatsApp
echo ====================================================
echo.

rem Verifier si Node.js enstale
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] Node.js pa jwenn nan PATH.
    if exist "%ProgramFiles%\nodejs\node.exe" (
        set "PATH=%ProgramFiles%\nodejs;%PATH%"
    ) else (
        echo N ap eseye enstale Node.js otomatikman...
        winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements
        if %ERRORLEVEL% NEQ 0 (
            echo Tanpri telechaje epi enstale Node.js sou https://nodejs.org
            pause
            exit /b 1
        )
    )
)

rem Verifier depandans npm yo
if not exist "node_modules\whatsapp-web.js" (
    echo [*] Enstalasyon depandans WhatsApp yo (whatsapp-web.js, express, qrcode)...
    call npm.cmd install
    if %ERRORLEVEL% NEQ 0 (
        echo [!] Ere pandan npm install.
        pause
        exit /b 1
    )
)

echo [*] N ap demare sevis WhatsApp la sou port 47812...
node server.js
pause

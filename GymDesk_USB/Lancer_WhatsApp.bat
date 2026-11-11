@echo off
setlocal
set "SILENT_MODE=0"
if /i "%~1"=="--silent" set "SILENT_MODE=1"
if /i "%~1"=="--bg" set "SILENT_MODE=1"

if "%SILENT_MODE%"=="0" title SecurGYM - Sevis WhatsApp (whatsapp-web.js)
cd /d "%~dp0whatsapp_service" 2>nul || cd /d "%~dp0"

set "PATH=%ProgramFiles%\nodejs;%ProgramFiles(x86)%\nodejs;%LOCALAPPDATA%\Programs\nodejs;%APPDATA%\npm;%PATH%"
set "PUPPETEER_SKIP_DOWNLOAD=true"

rem 0. Verifye si sevis la ap kouri deja sou port 47812
curl -s -m 1 http://127.0.0.1:47812/health >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if "%SILENT_MODE%"=="0" (
        echo [*] Sevis WhatsApp la ap kouri deja sou port 47812!
        echo [*] URL: http://127.0.0.1:47812
        timeout /t 3 >nul
    )
    exit /b 0
)

rem 1. Verifye si Node.js enstale
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%ProgramFiles%\nodejs\node.exe" (
        set "PATH=%ProgramFiles%\nodejs;%PATH%"
    ) else if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" (
        set "PATH=%LOCALAPPDATA%\Programs\nodejs;%PATH%"
    ) else (
        echo [!] Node.js pa jwenn. N ap enstale Node.js LTS otomatikman...
        winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements >nul 2>&1
        if not exist "%ProgramFiles%\nodejs\node.exe" (
            powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $p=\"$env:TEMP\node-lts-x64.msi\"; Invoke-WebRequest 'https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi' -OutFile $p -UseBasicParsing; Start-Process msiexec.exe -ArgumentList \"/i `\"$p`\" /qn /norestart\" -Wait"
        )
        set "PATH=%ProgramFiles%\nodejs;%LOCALAPPDATA%\Programs\nodejs;%PATH%"
    )
)

rem 2. Verifye depandans npm yo
if not exist "node_modules\whatsapp-web.js" (
    echo [*] Enstalasyon depandans WhatsApp yo (whatsapp-web.js, express, qrcode)...
    call npm.cmd install --omit=dev --no-audit --no-fund
    if %ERRORLEVEL% NEQ 0 (
        echo [!] Ere pandan npm install.
        if "%SILENT_MODE%"=="0" pause
        exit /b 1
    )
)

rem 3. Si mode background (--bg / --silent), lanse watchdog VBS an silans epi soti
if "%SILENT_MODE%"=="1" (
    if exist "%~dp0Demarrer_WhatsApp_Silencieux.vbs" (
        wscript.exe "%~dp0Demarrer_WhatsApp_Silencieux.vbs"
        exit /b 0
    )
)

echo ====================================================
echo     SecurGYM / GymDesk - Sevis WhatsApp
echo ====================================================
echo [*] N ap demare sevis WhatsApp la sou port 47812...
echo [*] URL Sevis: http://127.0.0.1:47812
echo.
node server.js
if "%SILENT_MODE%"=="0" pause

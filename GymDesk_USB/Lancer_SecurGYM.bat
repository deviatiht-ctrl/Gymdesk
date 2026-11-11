@echo off
title SecurGYM - Demarrage Ultra-Rapid (Web + USB + Terminal IP + WhatsApp)

cd /d "%~dp0"

rem --- 1. Enregistrement automatique au demarrage de Windows (Ajan + WhatsApp) ---
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SecurGYM_AccessAgent" /t REG_SZ /d "wscript.exe \"%~dp0Demarrer_Agent_Silencieux.vbs\"" /f >nul 2>&1
if exist "%~dp0Demarrer_WhatsApp_Silencieux.vbs" (
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SecurGYM_WhatsApp" /t REG_SZ /d "wscript.exe \"%~dp0Demarrer_WhatsApp_Silencieux.vbs\"" /f >nul 2>&1
)

rem --- 2. Verifier si l'agent v3.6.3 tourne deja en arriere-plan ---
curl -s -m 1 http://127.0.0.1:47811/health | findstr /i "3.6.3" >nul 2>&1 && goto :agent_ready

rem Tue SELMAN ansyen vbs/access_agent (pa JANM touye Demarrer_WhatsApp_Silencieux.vbs!)
taskkill /f /im access_agent.exe >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='wscript.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*Demarrer_Agent_Silencieux*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>&1
timeout /t 1 /nobreak >nul

echo Demarrage de l'agent materiel SecurGYM v3.6.3...
if exist "%~dp0Demarrer_Agent_Silencieux.vbs" (
    wscript.exe "%~dp0Demarrer_Agent_Silencieux.vbs"
) else if exist "%~dp0access_agent.exe" (
    start /min "" "%~dp0access_agent.exe"
)

for /l %%i in (1,1,15) do (
    curl -s -m 1 http://127.0.0.1:47811/health >nul 2>&1 && goto :agent_ready
    timeout /t 1 /nobreak >nul 2>&1
)

:agent_ready
set "DATA_DIR=%~dp0data\profile"

rem Nettoyer les caches de scripts pour garantir la derniere version de l'interface
if exist "%DATA_DIR%\Default\Cache" rmdir /s /q "%DATA_DIR%\Default\Cache" >nul 2>&1
if exist "%DATA_DIR%\Default\Code Cache" rmdir /s /q "%DATA_DIR%\Default\Code Cache" >nul 2>&1
if exist "%DATA_DIR%\Default\GPUCache" rmdir /s /q "%DATA_DIR%\Default\GPUCache" >nul 2>&1
if exist "%DATA_DIR%\Default\Service Worker\CacheStorage" rmdir /s /q "%DATA_DIR%\Default\Service Worker\CacheStorage" >nul 2>&1

rem --- 2b. Demarrage automatique du service WhatsApp en arriere-plan permanent (port 47812) ---
curl -s -m 1 http://127.0.0.1:47812/health >nul 2>&1 || (
    if exist "%~dp0Demarrer_WhatsApp_Silencieux.vbs" (
        wscript.exe "%~dp0Demarrer_WhatsApp_Silencieux.vbs"
    ) else if exist "%~dp0Lancer_WhatsApp.bat" (
        start /min "" cmd /c "%~dp0Lancer_WhatsApp.bat" --bg
    )
)

rem --- 3. Ouverture instantanee de SecurGYM ---
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" --app=http://127.0.0.1:47811 --user-data-dir="%DATA_DIR%" --no-first-run --window-size=1280,800
) else if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" --app=http://127.0.0.1:47811 --user-data-dir="%DATA_DIR%" --no-first-run --window-size=1280,800
) else if exist "%LocalAppData%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%LocalAppData%\Microsoft\Edge\Application\msedge.exe" --app=http://127.0.0.1:47811 --user-data-dir="%DATA_DIR%" --no-first-run --window-size=1280,800
) else if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
    start "" "%ProgramFiles%\Google\Chrome\Application\chrome.exe" --app=http://127.0.0.1:47811 --user-data-dir="%DATA_DIR%" --no-first-run --window-size=1280,800
) else (
    start "" http://127.0.0.1:47811
)

exit

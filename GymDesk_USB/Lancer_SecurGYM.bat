@echo off
title SecurGYM - Demarrage Instantane (Web + USB + Terminal IP)

cd /d "%~dp0"

rem --- 1. Enregistrement automatique au demarrage de Windows (sans besoin d'informaticien ni d'admin) ---
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SecurGYM_AccessAgent" /t REG_SZ /d "wscript.exe \"%~dp0Demarrer_Agent_Silencieux.vbs\"" /f >nul 2>&1

rem --- 2. Verifier si l'agent tourne deja en arriere-plan (0 seconde d'attente!) ---
curl -s -m 1 http://127.0.0.1:47811/health >nul 2>&1 && goto :agent_ready

echo Demarrage de l'agent materiel SecurGYM (USB BioMini + Terminal IP W2)...
if exist "%~dp0Demarrer_Agent_Silencieux.vbs" (
    wscript.exe "%~dp0Demarrer_Agent_Silencieux.vbs"
) else (
    start /min "" "%~dp0access_agent.exe"
)

for /l %%i in (1,1,15) do (
    curl -s -m 1 http://127.0.0.1:47811/health >nul 2>&1 && goto :agent_ready
    pathping -n -q 1 -p 150 127.0.0.1 >nul 2>&1
)

:agent_ready
set "DATA_DIR=%~dp0data\profile"

rem --- 3. Ouverture instantanee de la version Web SecurGYM (compatible USB + IP) ---
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

@echo off
title GymDesk V3 - Demarrage Logiciel Portable
echo ==========================================================
echo   GymDesk V3 - Demarrage Logiciel Portable (Cle USB)
echo ==========================================================
echo.
echo [1/2] Lancement du pilote biometrique et serveur local...

cd /d "%~dp0"

taskkill /f /im access_agent.exe >nul 2>&1

start "" "%~dp0access_agent.exe"

echo [2/2] Ouverture de l'application GymDesk (Mode Bureau Dedie)...
timeout /t 2 /nobreak >nul

set "DATA_DIR=%~dp0data\profile"

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

echo.
echo GymDesk est lance !
echo Gardez cette fenetre reduite ou fermez-la.
exit

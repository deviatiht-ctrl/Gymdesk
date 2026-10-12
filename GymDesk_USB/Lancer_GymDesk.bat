@echo off
title GymDesk V3 - Demarrage Logiciel Portable
echo ==========================================================
echo   GymDesk V3 - Demarrage Logiciel Portable (Cle USB)
echo ==========================================================
echo.
echo [1/2] Lancement du pilote biometrique et serveur local...

cd /d "%~dp0"

taskkill /f /im access_agent.exe >nul 2>&1
taskkill /f /im suprema_bridge32.exe >nul 2>&1

start "" "%~dp0access_agent.exe"

echo Attente du serveur local (127.0.0.1:47811)...
set "AGENT_UP="
for /l %%i in (1,1,20) do (
    curl -s -m 1 http://127.0.0.1:47811/health >nul 2>&1 && set "AGENT_UP=1" && goto :agent_ready
    timeout /t 1 /nobreak >nul
)

echo.
echo [ERREUR] L'agent local n'a pas demarre.
echo   - Si Windows affiche "Windows protected your PC", cliquez
echo     "More info" puis "Run anyway".
echo   - Verifiez que ce dossier a ete copie EN ENTIER sur la cle USB.
pause
exit /b 1

:agent_ready
echo [2/2] Ouverture de l'application GymDesk (Mode Bureau Dedie)...
timeout /t 1 /nobreak >nul

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

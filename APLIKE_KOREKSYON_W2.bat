@echo off
:: Mete fichye sa a nan C:\Users\cbj1_u3\Documents\GYM\gym_desk epi lanse l (double-klik).
setlocal
cd /d "%~dp0"
if not exist "tools\access_agent\biostar_tool.cs" (
  echo [ERE] Mete fichye sa a nan dosye gym_desk la.
  pause & exit /b 1
)
echo [1/6] Fenmen ajan SecurGYM la pou yon ti moman...
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='wscript.exe'\" | Where-Object { $_.CommandLine -like '*Demarrer_Agent_Silencieux*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; Stop-Process -Name access_agent,biostar_tool -Force -ErrorAction SilentlyContinue; Start-Sleep 2"

echo [2/6] Mete kod la ajou...
git log --oneline -5 | findstr /c:"one-touch fingerprint" >nul
if errorlevel 1 (
  if exist "GymDesk_USB\Ekspote_Tout_Manm_BioStar.ps1" del "GymDesk_USB\Ekspote_Tout_Manm_BioStar.ps1"
  git pull -q --ff-only origin main
  git am -q "..\p3.patch" || (echo [ERE] git am echwe & git am --abort & goto restart)
)
if exist "..\p3.patch" del "..\p3.patch"

echo [3/6] Konpile biostar_tool.exe...
pushd tools\access_agent
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -nologo -platform:x64 -target:exe -out:biostar_tool.exe biostar_tool.cs || (popd & echo [ERE] konpilasyon & goto restart)
copy /y biostar_tool.exe ..\..\GymDesk_USB\biostar_tool.exe >nul
popd

echo [4/6] W2: kapte toujou limen, san LFD (1 sel kontak)...
pushd GymDesk_USB\Lib\Window\lib\x64
..\..\..\..\biostar_tool.exe . fpfix 192.168.1.41 51211
popd

echo [5/6] Push sou GitHub...
git add tools/access_agent/biostar_tool.exe GymDesk_USB/biostar_tool.exe
git commit -q -m "build: biostar_tool with fpfix" 2>nul
git pull -q --rebase origin main
git push origin main
git log --oneline -3

:restart
echo [6/6] Relanse ajan SecurGYM la...
start "" wscript.exe "%~dp0GymDesk_USB\Demarrer_Agent_Silencieux.vbs"
echo.
echo FINI. Fenmen epi relouvri SecurGYM pou anprent yo remonte sou W2 a.
pause

@echo off
:: ========================================================================
::  DEMARE_TOUT_ULTIME.bat - SecurGYM + teminal W2 (BioEntry) sou kab
:: ------------------------------------------------------------------------
::  1. Gadyen: IP 192.168.1.50 fiks sou kab W2 a (pa janm sou Wi-Fi a),
::     wout direk pou W2 a, firewall, tach SYSTEM ki re-aplike l otomatikman.
::  2. Jwenn W2 a, remete IP li fiks (192.168.1.41), fose l verifye anprent
::     yo li menm: manm yo valid jiska dat fen abonman yo, anplwaye yo
::     toujou valid, menm si kab la pa konekte sou PC a.
::  3. Lanse ajan SecurGYM la ak aplikasyon an.
:: ========================================================================
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Demann dwa Administrate...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title SecurGYM + W2 - DEMARAJ ULTIME
cd /d "%~dp0"

if not exist "%~dp0Gadyen_Ultime.ps1" (
    echo [ERE] Gadyen_Ultime.ps1 pa jwenn bo kote fichye sa a. Kopye TOUT dosye GymDesk_USB la.
    pause
    exit /b 1
)

echo [1/3] Gadyen rezo: IP fiks sou kab W2, Wi-Fi pa touche...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gadyen_Ultime.ps1" -Enstale
echo.

echo [2/3] Teminal W2: IP fiks + verifikasyon anprent sou teminal la menm...
taskkill /f /im access_agent.exe >nul 2>&1
taskkill /f /im biostar_tool.exe >nul 2>&1
timeout /t 1 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gadyen_Ultime.ps1" -Repare -ToolDir "%~dp0."
echo.

echo [3/3] Lanse SecurGYM...
start "" cmd /c "%~dp0Lancer_SecurGYM.bat"

echo.
echo ==========================================================
echo   SecurGYM : http://127.0.0.1:47811
echo   Teminal  : W2 sou kab, IP fiks (gade terminal.json)
echo   Eta      : type C:\ProgramData\SecurGYM\gadyen_eta.txt
echo   Jounal   : C:\ProgramData\SecurGYM\gadyen_ultime.log
echo ==========================================================
timeout /t 15

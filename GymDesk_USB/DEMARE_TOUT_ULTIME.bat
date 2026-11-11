@echo off
:: ========================================================================
::  DEMARE_TOUT_ULTIME.bat - SecurGYM + teminal W2 (BioEntry) + WhatsApp
:: ------------------------------------------------------------------------
::  1. Gadyen: IP 192.168.1.50 fiks sou kab W2 a (pa janm touche Wi-Fi a),
::     pa janm kite dock USB/PCIe al nan veille, tach SYSTEM 150ms.
::  2. W2: jwenn teminal la, fikse AutoLock + 1 kontak, verifye anprent yo.
::  3. Lanse ajan SecurGYM v3.6.3 (:47811) AK WhatsApp (:47812) an silans.
:: ========================================================================
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Demann dwa Administrate...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title SecurGYM + W2 + WhatsApp - DEMARAJ ULTIME
cd /d "%~dp0"

if not exist "%~dp0Gadyen_Ultime.ps1" (
    echo [ERE] Gadyen_Ultime.ps1 pa jwenn bo kote fichye sa a. Kopye TOUT dosye GymDesk_USB la.
    pause
    exit /b 1
)

echo [1/4] Femen ansyen pwosesis background yo pwop...
taskkill /f /im access_agent.exe >nul 2>&1
taskkill /f /im biostar_tool.exe >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='wscript.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*Demarrer_Agent_Silencieux*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>&1
timeout /t 1 /nobreak >nul
echo.

echo [2/4] Gadyen rezo: IP fiks sou kab W2 (dock extender, usb, kat entegre)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gadyen_Ultime.ps1" -Enstale
echo.

echo [3/4] Teminal W2: IP fiks + AutoLock + verifikasyon anprent sou teminal la menm...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gadyen_Ultime.ps1" -Repare -ToolDir "%~dp0."
echo.

echo [4/4] Lanse SecurGYM v3.6.3 ak Sevis WhatsApp pemanan (:47811 / :47812)...
start "" cmd /c "%~dp0Lancer_SecurGYM.bat"

echo.
echo ==========================================================
echo   SecurGYM : http://127.0.0.1:47811 (Web Vercel: https://gymdesk.vercel.app)
echo   WhatsApp : http://127.0.0.1:47812 (background san kanpe)
echo   Teminal  : W2 sou kab, IP fiks + AutoLock pemanan
echo   Eta      : type C:\ProgramData\SecurGYM\gadyen_eta.txt
echo   Jounal   : C:\ProgramData\SecurGYM\gadyen_ultime.log
echo ==========================================================
timeout /t 12

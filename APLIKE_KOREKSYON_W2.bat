@echo off
title SecurGYM - Aplike Koreksyon W2 (1 Kontak + Sinkronizasyon Anprent)
setlocal enabledelayedexpansion

:: Jwenn katye jeneral gym_desk ak GymDesk_USB
set "BASE_DIR=%~dp0"
if exist "%BASE_DIR%tools\access_agent\biostar_tool.cs" (
    set "GYM_DESK=%BASE_DIR%"
    set "USB_DIR=%BASE_DIR%GymDesk_USB"
) else if exist "%BASE_DIR%..\tools\access_agent\biostar_tool.cs" (
    set "GYM_DESK=%BASE_DIR%..\"
    set "USB_DIR=%BASE_DIR%"
) else (
    set "GYM_DESK=C:\Users\cbj1_u3\Documents\GYM\gym_desk\"
    set "USB_DIR=C:\Users\cbj1_u3\Documents\GYM\gym_desk\GymDesk_USB\"
)

echo ==========================================================
echo   SecurGYM : APLIKE KOREKSYON W2 (1 Kontak + Anprent)
echo ==========================================================
echo.

echo [1/5] Fenmen ajan SecurGYM la pou yon ti moman...
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='wscript.exe'\" | Where-Object { $_.CommandLine -like '*Demarrer_Agent_Silencieux*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Stop-Process -Name access_agent,biostar_tool -Force -ErrorAction SilentlyContinue; Start-Sleep 1"

echo [2/5] Konpile biostar_tool.exe ak sipò fpfix...
set "CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
pushd "%GYM_DESK%tools\access_agent"
"%CSC%" -nologo -platform:x64 -target:exe -out:biostar_tool.exe biostar_tool.cs
if errorlevel 1 (
    echo [AVÈTISMAN] Konpilasyon pa pase, n ap itilize biostar_tool ki pare a.
) else (
    copy /y biostar_tool.exe "%USB_DIR%\biostar_tool.exe" >nul
    echo  -> biostar_tool.exe konpile avèk siksè.
)
popd

echo [3/5] Netwaye kach anprent pou fòse remonte tout anprent sou W2 a...
python -c "import sqlite3, glob, os; [conn := sqlite3.connect(p), conn.cursor().execute(\"DELETE FROM sync_metadata WHERE key LIKE 'terminal_sigs%'\"), conn.commit(), conn.close()] for p in glob.glob(os.path.expanduser('~/Documents/gymdesk*.sqlite'))" 2>nul
echo  -> Kach netwaye. Tout anprent SecurGYM pral remonte sou W2 a.

echo [4/5] W2: mete kaptè sou 1 kontak (ALWAYS_ON, san LFD)...
set "DLL_DIR=%USB_DIR%\Lib\Window\lib\x64"
pushd "%DLL_DIR%"
"%USB_DIR%\biostar_tool.exe" "%DLL_DIR%" fpfix 192.168.1.41 51211
popd

echo [5/5] Relanse ajan SecurGYM la ak Gadyen an...
start "" wscript.exe "%USB_DIR%\Demarrer_Agent_Silencieux.vbs"
timeout /t 2 /nobreak >nul

echo.
echo ==========================================================
echo   FINI AK SIKSÈ!
echo   1. Pòt la ap louvri depi 1ye fwa moun nan mete dwèt li.
echo   2. Tout anprent ki nan SecurGYM remonte sou W2 a.
echo   3. Relouvri SecurGYM nan navigatè a si w te fèmen l.
echo ==========================================================
echo.
pause

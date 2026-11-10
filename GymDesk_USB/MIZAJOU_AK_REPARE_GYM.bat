@echo off
:: ========================================================================
::  MIZAJOU_AK_REPARE_GYM.bat - Korije Endpoint Terminal & Dock Extender
:: ========================================================================
setlocal EnableDelayedExpansion
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Demann dwa Administrate...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title SecurGYM - MIZAJOU AK REPARASYON TOTAL
cd /d "%~dp0"
color 0b

echo ========================================================================
echo   MIZAJOU AK REPARASYON SECERGYM (DOCK EXTENDER + ESKAN SOU POT W2)
echo ========================================================================
echo.

echo [1/5] Femen tout ansyen ajan ak pwosesis ki te bloke nan background...
taskkill /f /im access_agent.exe >nul 2>&1
taskkill /f /im biostar_tool.exe >nul 2>&1
taskkill /f /im wscript.exe >nul 2>&1
taskkill /f /im msedge.exe >nul 2>&1
timeout /t 2 /nobreak >nul
echo       -> Tout pwosesis femen avek sikse.
echo.

echo [2/5] Konfigire kat rezo W2 (Dock Extender / Hub USB / Ethernet)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gadyen_Ultime.ps1" -Enstale
echo.

echo [3/5] Fikse IP Teminal W2 (192.168.1.41) ak verifikasyon anprent...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Gadyen_Ultime.ps1" -Repare -ToolDir "%~dp0."
echo.

echo [4/5] Lanse Nouvo Ajan SecurGYM v3.6.2...
start "" "%~dp0access_agent.exe"
timeout /t 3 /nobreak >nul
echo.

echo [5/5] Tcheke si Nouvo Endpoint Eskan sou Pot la aktif...
set "STATUS_OK=0"
for /l %%i in (1,1,10) do (
    if !STATUS_OK! equ 0 (
        curl -s -m 2 http://127.0.0.1:47811/status | findstr /i "3.6.2" >nul 2>&1
        if !errorlevel! equ 0 (
            set "STATUS_OK=1"
        ) else (
            timeout /t 1 /nobreak >nul
        )
    )
)

if !STATUS_OK! equ 1 (
    color 0a
    echo.
    echo ========================================================================
    echo   [SIKSE TOTAL] Ajan v3.6.2 ak Eskan sou Pot W2 ap mache 100%%!
    echo   Endpoint eskan: http://127.0.0.1:47811/api/terminals/scan [AKTIF]
    echo ========================================================================
) else (
    color 0c
    echo.
    echo   [AVÈTISMAN] Ajan an poko reponn sou v3.6.2, men konfigirasyon an fin aplike.
)

echo.
echo Ouvri SecurGYM...
start "" cmd /c "%~dp0Lancer_SecurGYM.bat"

echo.
echo Fini! Ou ka enskri anprent sou pot la kounye a san pwoblem.
timeout /t 10

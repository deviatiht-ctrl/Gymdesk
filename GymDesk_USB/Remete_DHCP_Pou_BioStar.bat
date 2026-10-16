@echo off
title Remete Rezo an Otomatik (DHCP) pou BioStar
echo ==========================================================
echo   Remete Kat Rezo an Otomatik (DHCP) pou Ansyen BioStar
echo ==========================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ATANSYON] Ou dwe klike a dwat sou fichye sa a epi chwazi "Run as administrator" (Executer en tant qu'administrateur).
    echo.
    pause
    exit /b 1
)

echo [1/3] Femen SecurGYM ak Access Agent pou yo pa okipe po 51211...
taskkill /f /im access_agent.exe >nul 2>&1
taskkill /f /im SecurGYM.exe >nul 2>&1
taskkill /f /im biostar_tool.exe >nul 2>&1

echo.
echo [2/3] Remete kat Ethernet la sou IP otomatik (DHCP)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$adapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ASIX*' -or $_.Name -like '*Ethernet*' -and $_.Status -ne 'Disabled' }; foreach ($a in $adapters) { try { netsh interface ipv4 set address name=$a.Name source=dhcp; netsh interface ipv4 set dns name=$a.Name source=dhcp; Write-Host ('Kat rezo ' + $a.Name + ' remete sou DHCP otomatik !') -ForegroundColor Green } catch {} }"

echo.
echo [3/3] Verifye sevis BioStar 2 yo...
echo Si sevis BioStar 2 yo te kanpe, ale nan Start Menu -> "BioStar 2 Setting" epi klike "Start All".
echo Apre sa, louvri navigatè a sou: https://127.0.0.1
echo.
echo ==========================================================
echo Operasyon fini!
echo ==========================================================
pause

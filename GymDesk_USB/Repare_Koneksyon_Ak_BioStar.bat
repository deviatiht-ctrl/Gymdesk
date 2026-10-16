@echo off
title Repare Koneksyon Rezo ak BioStar
echo ==========================================================
echo   Repare Koneksyon Rezo (Prive) ak Demare Ansyen BioStar
echo ==========================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ATANSYON] Ou dwe klike a dwat sou fichye sa a epi chwazi:
    echo "Run as administrator" (Executer en tant qu'administrateur).
    echo.
    pause
    exit /b 1
)

echo [1/5] Fose tout rezo yo (Wi-Fi, Ethernet, USB Dock) pase nan mòd PRIVE...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetConnectionProfile | ForEach-Object { try { Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private; Write-Host ('  -> ' + $_.InterfaceAlias + ' chanje an PRIVE avèk siksè!') -ForegroundColor Green } catch { Write-Host ('  -> Pa t ka chanje ' + $_.InterfaceAlias) -ForegroundColor Yellow } }"

echo.
echo [2/5] Konfigire IP statik 192.168.1.50 sou kat Ethernet USB a...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$a = Get-NetAdapter | Where-Object { ($_.InterfaceDescription -like '*ASIX*' -or $_.InterfaceDescription -like '*Realtek*' -or $_.InterfaceDescription -like '*USB*' -or $_.Name -like '*Ethernet*') -and $_.Status -ne 'Disabled' } | Select-Object -First 1; if ($a) { netsh interface ipv4 set address name=$a.Name static 192.168.1.50 255.255.255.0; Write-Host ('  -> Kat ' + $a.Name + ' konfigire sou 192.168.1.50!') -ForegroundColor Green } else { Write-Host '  -> Kat Ethernet la pa jwenn.' -ForegroundColor Red }"

echo.
echo [3/5] Ouvri tout pò BioStar ak lektè a nan Firewall (Piblik ak Prive)...
netsh advfirewall firewall delete rule name="BioEntry_W2_All" >nul 2>&1
netsh advfirewall firewall delete rule name="BioStar_All_Ports" >nul 2>&1
netsh advfirewall firewall add rule name="BioEntry_W2_All" dir=in action=allow protocol=TCP localport=51211 profile=any >nul 2>&1
netsh advfirewall firewall add rule name="BioEntry_W2_All_UDP" dir=in action=allow protocol=UDP localport=51211 profile=any >nul 2>&1
netsh advfirewall firewall add rule name="BioStar_All_Ports" dir=in action=allow protocol=TCP localport=80,443,51211,51212,8443 profile=any >nul 2>&1
echo   -> Pò 51211, 51212, 443, 80 otorize nan tout nivo Firewall la!

echo.
echo [4/5] Chèche ak demare sèvis BioStar 2 si yo te kanpe...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$services = Get-Service | Where-Object { $_.DisplayName -like '*BioStar*' -or $_.Name -like '*BioStar*' -or $_.DisplayName -like '*mariadb*' -or $_.DisplayName -like '*nginx*' }; if ($services) { foreach ($s in $services) { try { Start-Service $s.Name -ErrorAction SilentlyContinue; Write-Host ('  -> Sèvis ' + $s.DisplayName + ' demare!') -ForegroundColor Green } catch {} } } else { Write-Host '  -> Pa gen sèvis Windows BioStar sou machin sa a (ou ka louvri BioStar 2 Setting manyèlman).' -ForegroundColor Gray }"

echo.
echo [5/5] Test kominikasyon dirèk ak lektè BioEntry a (192.168.1.41)...
cd /d "%~dp0"
ping -n 2 192.168.1.41

echo.
echo ==========================================================
echo Operasyon fini!
echo 1. Si w ap itilize BioStar 2, louvri navigatè a sou:
echo    https://127.0.0.1  oubyen  https://localhost
echo 2. Si w ap itilize SecurGYM, double-klike:
echo    Lancer_SecurGYM.bat
echo ==========================================================
pause

@echo off
title Konfigirasyon Rezo BioEntry W2
echo ==========================================================
echo   Konfigirasyon Rezo BioEntry W2 pou SecurGYM
echo ==========================================================
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ATANSYON] Ou dwe klike a dwat sou fichye sa a epi chwazi "Run as administrator" (Executer en tant qu'administrateur).
    echo.
    pause
    exit /b 1
)

echo [1/3] Konfigirasyon IP statik sou adapte USB Ethernet la...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$a = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ASIX*' -or $_.Name -like '*Ethernet 2*' -or ($_.Name -eq 'Ethernet' -and $_.Status -eq 'Up') } | Select-Object -First 1; if ($a) { netsh interface ipv4 set address name=$a.Name static 192.168.1.50 255.255.255.0; Set-NetConnectionProfile -InterfaceIndex $a.InterfaceIndex -NetworkCategory Private -ErrorAction SilentlyContinue; Write-Host ('Kat rezo ' + $a.Name + ' konfigire sou 192.168.1.50 !') -ForegroundColor Green } else { Write-Host 'Kat Ethernet USB a pa jwenn.' -ForegroundColor Red }"

echo.
echo [2/3] Otorizasyon po 51211 nan Firewall Windows la...
netsh advfirewall firewall add rule name="BioEntry_W2_TCP" dir=in action=allow protocol=TCP localport=51211 >nul 2>&1
netsh advfirewall firewall add rule name="BioEntry_W2_UDP" dir=in action=allow protocol=UDP localport=51211 >nul 2>&1

echo.
echo [3/3] Tes kominikasyon direk ak BioEntry W2 (192.168.1.41)...
cd /d "%~dp0"
if exist "biostar_tool.exe" (
    biostar_tool.exe Lib\Window\lib\x64 ping 192.168.1.41 51211
) else if exist "app\biostar_tool.exe" (
    app\biostar_tool.exe app\Lib\Window\lib\x64 ping 192.168.1.41 51211
)

echo.
echo ==========================================================
echo Konfigirasyon fini! Ou ka louvri SecurGYM kounye a.
echo ==========================================================
pause

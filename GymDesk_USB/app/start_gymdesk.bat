@echo off
title SecurGYM Launcher
echo Demare SecurGYM ak sevis anprent la...

cd /d "%~dp0"

taskkill /f /im access_agent.exe >nul 2>&1
taskkill /f /im suprema_bridge32.exe >nul 2>&1

echo Lanse Access Agent sou port 47811...
start "" access_agent.exe

ping 127.0.0.1 -n 3 >nul

if exist "SecurGYM.exe" (
    start "" "SecurGYM.exe"
) else if exist "gym_desk.exe" (
    start "" "gym_desk.exe"
)

exit


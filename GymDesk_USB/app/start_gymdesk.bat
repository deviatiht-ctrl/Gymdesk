@echo off
title GymDesk V3 Launcher
echo Demare GymDesk ak sevis anprent la...

tasklist /FI "IMAGENAME eq access_agent.exe" 2>NUL | find /I /N "access_agent.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo Access Agent deja ap kouri nan background.
) else (
    echo Lanse Access Agent nan background sou port 47811...
    start "" /B access_agent.exe
)

start "" gym_desk.exe
exit

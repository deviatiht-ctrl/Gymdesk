@echo off
title Efase tout anprent sou BioEntry W2
echo ==========================================================
echo   EFASE TOUT ANPRENT SOU BIOENTRY W2 (192.168.1.41)
echo ==========================================================
echo.
echo [!] ATANSYON: Aksyon sa a pral retire TOUT ansyen anprent
echo     ak tout itilizate ki te anrejistre sou teminal la!
echo.
set /p confirm="Eske ou vle efase yo tout vre ? Tape OUI epi peze Enter: "
if /i not "%confirm%"=="OUI" (
    echo Aksyon anile. Okenn anprent pa efase.
    echo.
    pause
    exit /b
)

echo.
echo [1/2] Koneksyon ak BioEntry W2 sou 192.168.1.41:51211...
cd /d "%~dp0"
if exist "biostar_tool.exe" (
    biostar_tool.exe Lib\Window\lib\x64 clearusers 192.168.1.41 51211
) else if exist "app\biostar_tool.exe" (
    app\biostar_tool.exe app\Lib\Window\lib\x64 clearusers 192.168.1.41 51211
)

echo.
echo [2/2] Verifikasyon memwa teminal la...
if exist "biostar_tool.exe" (
    biostar_tool.exe Lib\Window\lib\x64 users 192.168.1.41 51211
) else if exist "app\biostar_tool.exe" (
    app\biostar_tool.exe app\Lib\Window\lib\x64 users 192.168.1.41 51211
)

echo.
echo ==========================================================
echo Fini! Teminal BioEntry W2 a netwaye net.
echo ==========================================================
pause

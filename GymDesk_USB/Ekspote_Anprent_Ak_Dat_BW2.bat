@echo off
title Ekspote Anprent ak Dat sou BioEntry W2
echo ==========================================================
echo   EKSPOTE ANPRENT AK DAT EXPIRASYON SOU BIOENTRY W2
echo ==========================================================
echo.
echo Koneksyon ak BioEntry W2 sou 192.168.1.41:51211...
cd /d "%~dp0"

if exist "biostar_tool.exe" (
    biostar_tool.exe Lib\Window\lib\x64 dump 192.168.1.41 anprent_bw2_export.txt 51211
) else if exist "app\biostar_tool.exe" (
    app\biostar_tool.exe app\Lib\Window\lib\x64 dump 192.168.1.41 anprent_bw2_export.txt 51211
)

echo.
echo ==========================================================
echo Fichye yo kreye avek sikse nan dosye sa a :
echo  1. anprent_bw2_export.txt  (Pou kole nan SecurGYM)
echo  2. anprent_bw2_export.json (Gen tout Non, Dat expirasyon ak Anprent)
echo ==========================================================
pause

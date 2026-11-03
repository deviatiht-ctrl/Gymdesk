@echo off
title SecurGYM - Enpote Anprent BioStar nan Baz Done
cd /d "%~dp0"

echo ==========================================================
echo   SecurGYM : Enpotasyon Anprent BioStar San Doublon
echo ==========================================================
echo.
echo Sa a pral:
echo  1. Pran tout anprent ki nan BioStar_Anprent_*.csv
echo  2. Sote moun ki deja gen anprent nan SecurGYM (pa ranplase yo)
echo  3. Ajoute anprent pou moun ki pa t genyen
echo  4. Kreye manm aktif ki nouvo yo san doublon
echo  5. Remete tout anprent yo sou W2 a
echo.

python "%~dp0Enpote_Anprent_Nan_SecurGYM.py" %*
if errorlevel 1 (
    echo.
    echo [ATANSYON] Si python pa enstale, w ka itilize PowerShell.
)

echo.
pause

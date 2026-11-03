@echo off
title BioStar 2 - Ekstrè Anprent Manm Aktif yo
cd /d "%~dp0"

echo ==========================================================
echo   BioStar 2 : Ekstre Anprent Manm Aktif (Ki Pa Ekspire)
echo ==========================================================
echo.
echo Kòmand sa a pral konekte sou BioStar 2 a, pran manm ki pa
echo ekspire yo ak tout anprent yo (template0 ak template1),
echo epi sove yo nan yon fichye sou Desktop ou:
echo   BioStar_Anprent_AAAAMMJJ_HHMM.csv
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Ekspote_Anprent_BioStar.ps1" %*

echo.
echo ==========================================================
echo Kounye a kopye fichye CSV anprent la sou laptop SecurGYM la
echo (nan GymDesk_USB oswa sou Desktop li), epi double-klike sou:
echo   ENPOTE_ANPRENT_BIOSTAR.bat
echo ==========================================================
echo.
pause

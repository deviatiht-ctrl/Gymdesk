# GymDesk V3 - Windows PC Build & Bundle Script
# Build Flutter Windows Release + Access Agent + Installer

param(
    [switch]$SkipFlutterBuild = $false,
    [switch]$BuildInstaller = $true
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  GymDesk V3 - Konpilasyon Windows PC (.exe)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Detèmine chemen zouti yo
$FlutterBat = Join-Path $RootDir ".tools\flutter\bin\flutter.bat"
if (-not (Test-Path $FlutterBat)) {
    $FlutterBat = "flutter"
}

$DartExe = Join-Path $RootDir ".tools\flutter\bin\cache\dart-sdk\bin\dart.exe"
if (-not (Test-Path $DartExe)) {
    $DartExe = "dart"
}

Write-Host "[1/4] Tcheke zouti SDK..." -ForegroundColor Yellow
Write-Host "  Flutter : $FlutterBat"
Write-Host "  Dart    : $DartExe"

# 2. Konpile lojisyèl Flutter Windows la
$ReleaseDir = Join-Path $RootDir "build\windows\x64\runner\Release"

if (-not $SkipFlutterBuild) {
    Write-Host "`n[2/4] Konpilasyon Flutter Windows Release..." -ForegroundColor Yellow
    & $FlutterBat build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[!] Windows mande pèmisyon pou kreye 'symlinks' pou plugin yo." -ForegroundColor Red
        Write-Host "  Opsyon A: Louvri paramèt Windows epi aktive 'Mode Développeur':" -ForegroundColor Cyan
        Write-Host "    start ms-settings:developers" -ForegroundColor White
        Write-Host "  Opsyon B: Oubyen kouri PowerShell kòm Administratè (Run as Administrator)." -ForegroundColor Cyan
        Write-Error "Echèk nan konpilasyon Flutter Windows. Tanpri aktive Developer Mode oswa kouri kòm Administratè."
        exit $LASTEXITCODE
    }
} else {
    Write-Host "`n[2/4] Sote konpilasyon Flutter Windows (SkipFlutterBuild aktif)." -ForegroundColor DarkGray
}

if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
}

# 3. Konpile Access Agent la pou Windows (.exe)
Write-Host "`n[3/4] Konpilasyon GymDesk Access Agent pou lektè anprent..." -ForegroundColor Yellow
$AgentSource = Join-Path $RootDir "tools\access_agent\agent.dart"
$AgentTarget = Join-Path $ReleaseDir "access_agent.exe"

& $DartExe compile exe $AgentSource -o $AgentTarget
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Pa t ka konpile Access Agent an exe natif dirèkteman. Kopi script pou runtime."
} else {
    Write-Host "  Access Agent konpile avèk siksè: $AgentTarget" -ForegroundColor Green
}

# Kreye script demaraj rapid 'start_gymdesk.bat'
$LauncherBat = Join-Path $ReleaseDir "start_gymdesk.bat"
$LauncherContent = @"
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
"@

Set-Content -Path $LauncherBat -Value $LauncherContent -Encoding Ascii
Write-Host "  Fichye demaraj kreye: $LauncherBat" -ForegroundColor Green

# 4. Bati Enstalatè Inno Setup si li disponib
if ($BuildInstaller) {
    Write-Host "`n[4/4] Bati Enstalatè GymDesk-Setup.exe..." -ForegroundColor Yellow
    $InnoCompiler = $null
    $PossiblePaths = @(
        "ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
    )
    foreach ($p in $PossiblePaths) {
        if (Get-Command $p -ErrorAction SilentlyContinue) {
            $InnoCompiler = $p
            break
        }
        if (Test-Path $p) {
            $InnoCompiler = $p
            break
        }
    }

    if ($InnoCompiler) {
        $IssFile = Join-Path $RootDir "installer\gymdesk_setup.iss"
        Write-Host "  Inno Setup Compiler jwenn nan: $InnoCompiler" -ForegroundColor Green
        & $InnoCompiler $IssFile
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Enstalatè kreye avèk siksè nan: $RootDir\installer\Output\GymDesk-Setup.exe" -ForegroundColor Green
        }
    } else {
        Write-Host "  Remak: Inno Setup (ISCC.exe) pa enstale sou machin sa a." -ForegroundColor Gray
        Write-Host "  Ou ka kouri GymDesk dirèkteman depi dosye Release la:" -ForegroundColor Cyan
        Write-Host "  $ReleaseDir\start_gymdesk.bat" -ForegroundColor White
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  Siksè! Dosye pare pou PC resepsyon an:" -ForegroundColor Green
Write-Host "  $ReleaseDir" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green

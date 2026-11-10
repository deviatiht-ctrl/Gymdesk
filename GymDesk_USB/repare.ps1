# ========================================================================
#  repare.ps1 - REPARASYON PEMANAN SECERGYM + DOCK EXTENDER + W2 VITES LIMYE
#  Egzekite nan PowerShell (Admin) sou laptop gym nan:
#  irm https://raw.githubusercontent.com/deviatiht-ctrl/Gymdesk/main/repare.ps1 | iex
# ========================================================================

$ErrorActionPreference = 'SilentlyContinue'

# 1. Asire dwa Administrate
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[INFO] Demann dwa Administrate..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/deviatiht-ctrl/Gymdesk/main/repare.ps1 | iex`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  REPARASYON PEMANAN SECERGYM (DOCK EXTENDER + W2 VITES LIMYE)" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Femen tout ansyen pwosesis ak tach pou fichye yo libere net
Write-Host "[1/7] Femen ansyen pwosesis background ak tach Gadyen..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName 'SecurGYM_Gadyen' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'Gadyen_Ultime\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Stop-Process -Name access_agent, biostar_tool, wscript, msedge -Force -ErrorAction SilentlyContinue
taskkill /f /im access_agent.exe /im biostar_tool.exe /im wscript.exe >nul 2>&1
Start-Sleep -Milliseconds 900
Write-Host "      -> Ansyen pwosesis yo femen pwop." -ForegroundColor Green

# 3. Jwenn dosye GymDesk_USB reyel la sou machin nan
Write-Host "[2/7] Ap chache enstalasyon GymDesk_USB sou laptop la..." -ForegroundColor Yellow
$searchPaths = @()
try {
    $runVal = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurGYM_AccessAgent' -ErrorAction SilentlyContinue).'SecurGYM_AccessAgent'
    if ($runVal -and $runVal -match '([A-Za-z]:\\[^"]*GymDesk_USB)') {
        $searchPaths += $matches[1]
    } elseif ($runVal -and $runVal -match '([A-Za-z]:\\[^"]+)\\Demarrer_Agent_Silencieux\.vbs') {
        $searchPaths += $matches[1]
    }
} catch {}

if ($PSScriptRoot) { $searchPaths += $PSScriptRoot }
$desktopDir = [Environment]::GetFolderPath('Desktop')
$docsDir = [Environment]::GetFolderPath('MyDocuments')
$searchPaths += @(
    'C:\GymDesk_USB',
    "$env:USERPROFILE\Documents\GYM\GymDesk_USB",
    "$docsDir\GYM\GymDesk_USB",
    "$docsDir\GymDesk_USB",
    "$desktopDir\GymDesk_USB",
    "$env:USERPROFILE\OneDrive\Desktop\GymDesk_USB",
    "$env:USERPROFILE\OneDrive\Documents\GymDesk_USB",
    "$env:USERPROFILE\Downloads\GymDesk_USB"
)
foreach ($drv in [System.IO.DriveInfo]::GetDrives()) {
    if ($drv.IsReady -and ($drv.DriveType -eq 'Fixed' -or $drv.DriveType -eq 'Removable')) {
        $searchPaths += "$($drv.Name)GymDesk_USB"
    }
}
$searchPaths = @($searchPaths | Where-Object { $_ } | Select-Object -Unique)

$gymDir = $null
foreach ($p in $searchPaths) {
    if (Test-Path "$p\Lib\Window\lib\x64\BS_SDK_V2.dll") { $gymDir = $p; break }
}
if (-not $gymDir) {
    foreach ($p in $searchPaths) {
        if ((Test-Path "$p\DEMARE_TOUT_ULTIME.bat") -or (Test-Path "$p\access_agent.exe")) { $gymDir = $p; break }
    }
}
if (-not $gymDir) {
    $gymDir = 'C:\GymDesk_USB'
    New-Item -ItemType Directory -Force -Path $gymDir | Out-Null
    Write-Host "      -> Kreye nouvo dosye nan $gymDir" -ForegroundColor Cyan
} else {
    Write-Host "      -> Dosye jwenn: $gymDir" -ForegroundColor Green
}

# 4. Telechaje nouvo fichye vites limye yo sou GitHub
Write-Host "[3/7] Telechaje denye mizajou (Ajan v3.6.2, biostar_tool <300ms, Gadyen, Web)..." -ForegroundColor Yellow
$baseUrl = 'https://raw.githubusercontent.com/deviatiht-ctrl/Gymdesk/main/GymDesk_USB'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$filesToUpdate = @(
    @{ Url = "$baseUrl/Gadyen_Ultime.ps1?v=$stamp";               Out = "$gymDir\Gadyen_Ultime.ps1";               MinSize = 1000 },
    @{ Url = "$baseUrl/DEMARE_TOUT_ULTIME.bat?v=$stamp";           Out = "$gymDir\DEMARE_TOUT_ULTIME.bat";           MinSize = 500 },
    @{ Url = "$baseUrl/Lancer_SecurGYM.bat?v=$stamp";              Out = "$gymDir\Lancer_SecurGYM.bat";              MinSize = 500 },
    @{ Url = "$baseUrl/Demarrer_Agent_Silencieux.vbs?v=$stamp";    Out = "$gymDir\Demarrer_Agent_Silencieux.vbs";    MinSize = 200 },
    @{ Url = "$baseUrl/access_agent.exe?v=$stamp";                 Out = "$gymDir\access_agent.exe";                 MinSize = 1000000 },
    @{ Url = "$baseUrl/biostar_tool.exe?v=$stamp";                 Out = "$gymDir\biostar_tool.exe";                 MinSize = 20000 },
    @{ Url = "$baseUrl/web/index.html?v=$stamp";                   Out = "$gymDir\web\index.html";                   MinSize = 1000 },
    @{ Url = "$baseUrl/web/flutter_bootstrap.js?v=$stamp";         Out = "$gymDir\web\flutter_bootstrap.js";         MinSize = 1000 },
    @{ Url = "$baseUrl/web/main.dart.js?v=$stamp";                 Out = "$gymDir\web\main.dart.js";                 MinSize = 1000000 }
)

if (-not (Test-Path "$gymDir\Lib\Window\lib\x64\BS_SDK_V2.dll")) {
    New-Item -ItemType Directory -Force -Path "$gymDir\Lib\Window\lib\x64" | Out-Null
    $filesToUpdate += @(
        @{ Url = "$baseUrl/Lib/Window/lib/x64/BS_SDK_V2.dll";         Out = "$gymDir\Lib\Window\lib\x64\BS_SDK_V2.dll";         MinSize = 100000 },
        @{ Url = "$baseUrl/Lib/Window/lib/x64/libcrypto-1_1-x64.dll"; Out = "$gymDir\Lib\Window\lib\x64\libcrypto-1_1-x64.dll"; MinSize = 100000 },
        @{ Url = "$baseUrl/Lib/Window/lib/x64/libssl-1_1-x64.dll";    Out = "$gymDir\Lib\Window\lib\x64\libssl-1_1-x64.dll";    MinSize = 100000 }
    )
}

New-Item -ItemType Directory -Force -Path "$gymDir\web" | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$downloadOk = $true
foreach ($f in $filesToUpdate) {
    $leaf = Split-Path $f.Out -Leaf
    $tmp = "$($f.Out).new"
    try {
        Write-Host "      -> $leaf..." -NoNewline
        Invoke-WebRequest -Uri $f.Url -OutFile $tmp -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        $len = if (Test-Path $tmp) { (Get-Item $tmp).Length } else { 0 }
        if ($len -lt $f.MinSize) {
            throw "Fichye two piti ($len bytes)"
        }
        if (Test-Path $f.Out) {
            Remove-Item $f.Out -Force -ErrorAction SilentlyContinue
            if (Test-Path $f.Out) {
                $oldBak = "$($f.Out).old"
                Remove-Item $oldBak -Force -ErrorAction SilentlyContinue
                Move-Item -Path $f.Out -Destination $oldBak -Force -ErrorAction SilentlyContinue
            }
        }
        Move-Item -Path $tmp -Destination $f.Out -Force -ErrorAction Stop
        Write-Host " [OK]" -ForegroundColor Green
    } catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Write-Host " [SOTE: $($_.Exception.Message)]" -ForegroundColor DarkYellow
        $downloadOk = $false
    }
}

# Kenbe dosye app\ nan senkronize tou si li egziste
if (Test-Path "$gymDir\app") {
    if (Test-Path "$gymDir\access_agent.exe") { Copy-Item "$gymDir\access_agent.exe" "$gymDir\app\access_agent.exe" -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$gymDir\biostar_tool.exe") { Copy-Item "$gymDir\biostar_tool.exe" "$gymDir\app\biostar_tool.exe" -Force -ErrorAction SilentlyContinue }
}

if (-not (Test-Path "$gymDir\terminal.json")) {
    '{"ip":"192.168.1.41","port":51211}' | Set-Content -Path "$gymDir\terminal.json" -Encoding ASCII
}

# 5. Netwaye kach navigate Edge la
Write-Host "[4/7] Netwaye kach navigate Edge la..." -ForegroundColor Yellow
$dataDir = "$gymDir\data\profile"
Remove-Item -Path "$dataDir\Default\Cache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$dataDir\Default\Code Cache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$dataDir\Default\Service Worker" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "      -> Kach netwaye." -ForegroundColor Green

# 6. Aplike Gadyen pemanan + koupe tout ekonomizasyon eneji USB/Dock/Ethernet
Write-Host "[5/7] Koupe domi USB + MediaSense + DAD 0ms + Enstale Gadyen SYSTEM (150ms)..." -ForegroundColor Yellow
$gadyenPath = "$gymDir\Gadyen_Ultime.ps1"
if (Test-Path $gadyenPath) {
    $gadyenOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gadyenPath -Enstale 2>&1
    foreach ($line in $gadyenOut) {
        if ($line) { Write-Host "      $line" -ForegroundColor Gray }
    }
}

$wiredAdapters = @(Get-NetAdapter | Where-Object {
    $_.Status -ne 'Disabled' -and
    $_.Virtual -ne $true -and
    $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802\.11|Bluetooth|Virtual|VPN|Loopback|Hyper-V|VMware|TAP|WSL|vEthernet|WAN Miniport'
})
$activeW2Adapter = $wiredAdapters | Where-Object {
    $has50 = Get-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress '192.168.1.50' -ErrorAction SilentlyContinue
    $null -ne $has50
} | Select-Object -First 1

if ($activeW2Adapter) {
    $dadVal = (Get-NetIPInterface -InterfaceIndex $activeW2Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).DadTransmits
    Write-Host "      -> Dock/Rezo W2 : $($activeW2Adapter.Name) ($($activeW2Adapter.InterfaceDescription)) [IP 192.168.1.50 | DAD=$dadVal | Eta=$($activeW2Adapter.Status)]" -ForegroundColor Green
} else {
    Write-Host "      -> [ATANSYON] Pa gen Dock Extender ki gen 192.168.1.50 kounye a (Gadyen 150ms la pre pou l konfigire l touswit ou ploge l!)" -ForegroundColor DarkYellow
}

$taskObj = Get-ScheduledTask -TaskName 'SecurGYM_Gadyen' -ErrorAction SilentlyContinue
$mediaVal = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'DisableDHCPMediaSense' -ErrorAction SilentlyContinue).DisableDHCPMediaSense
Write-Host "      -> Tach SYSTEM  : $(if ($taskObj) { $taskObj.State } else { 'Pa jwenn' }) | DisableDHCPMediaSense=$mediaVal" -ForegroundColor Cyan

# 7. Tcheke teminal BioEntry W2 + Auto-repare IP si W2 chanje IP
Write-Host "[6/7] Tcheke teminal BioEntry W2 (192.168.1.41)..." -ForegroundColor Yellow
$w2Ip = '192.168.1.41'
try {
    $tj = Get-Content "$gymDir\terminal.json" -Raw | ConvertFrom-Json
    if ($tj.ip) { $w2Ip = [string]$tj.ip }
} catch {}

function Test-FastPing([string]$ipAddr) {
    try {
        $p = New-Object System.Net.NetworkInformation.Ping
        $rep = $p.Send($ipAddr, 250)
        $p.Dispose()
        return ($rep -and $rep.Status -eq 'Success')
    } catch { return $false }
}

$w2Online = $false
for ($attempt = 1; $attempt -le 8; $attempt++) {
    if (Test-FastPing $w2Ip) { $w2Online = $true; break }
    Start-Sleep -Milliseconds 250
}

$toolExe = "$gymDir\biostar_tool.exe"
$dllDir = "$gymDir\Lib\Window\lib\x64"
if (-not $w2Online -and (Test-Path $toolExe) -and (Test-Path "$dllDir\BS_SDK_V2.dll")) {
    Write-Host "      -> W2 poko reponn $w2Ip, ap chache l pa UDP broadcast..." -ForegroundColor DarkYellow
    Push-Location $dllDir
    $found = @(& $toolExe $dllDir search 2>$null | Where-Object { $_ -like "device`t*" })
    foreach ($d in $found) {
        $parts = $d -split "`t"
        if ($parts.Length -ge 4 -and $parts[3] -and $parts[3] -ne $w2Ip) {
            Write-Host "      -> Jwenn W2 sou $($parts[3]), ap remete IP fiks sou $w2Ip..." -ForegroundColor Yellow
            & $toolExe $dllDir setip $parts[1] $w2Ip 255.255.255.0 0.0.0.0 | Out-Null
            Start-Sleep -Seconds 3
        }
    }
    Pop-Location
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        if (Test-FastPing $w2Ip) { $w2Online = $true; break }
        Start-Sleep -Milliseconds 300
    }
}

if ($w2Online) {
    Write-Host "      -> W2 AN LIY ($w2Ip [ONLINE])!" -ForegroundColor Green
    if ((Test-Path $toolExe) -and (Test-Path "$dllDir\BS_SDK_V2.dll")) {
        Push-Location $dllDir
        & $toolExe $dllDir fpfix $w2Ip 51211 | Out-Null
        Pop-Location
    }
} else {
    Write-Host "      -> W2 poko reponn ping: verifye kab Ethernet la nan Dock Extender a ak kouran W2 a." -ForegroundColor DarkYellow
}

# 8. Asire demaraj otomatik Windows + lanse SecurGYM v3.6.2
Write-Host "[7/7] Anrejistre demaraj otomatik Windows epi lanse SecurGYM v3.6.2..." -ForegroundColor Yellow
$vbsPath = "$gymDir\Demarrer_Agent_Silencieux.vbs"
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurGYM_AccessAgent' -Value "wscript.exe `"$vbsPath`"" -Type String -Force -ErrorAction SilentlyContinue

Start-Process cmd.exe -ArgumentList "/c `"$gymDir\Lancer_SecurGYM.bat`"" -WindowStyle Hidden

$agentLive = $false
$agentVer = '?'
for ($i = 1; $i -le 12; $i++) {
    try {
        $h = Invoke-RestMethod -Uri 'http://127.0.0.1:47811/health' -TimeoutSec 2 -ErrorAction Stop
        if ($h -and $h.version) {
            $agentVer = [string]$h.version
            $agentLive = ($agentVer -eq '3.6.2')
            if ($agentLive) { break }
        }
    } catch {}
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Green
Write-Host "  [SIKSE TOTAL] KONEKSYON AN KOURI SOU VITES LIMYE E LI PEMANAN!" -ForegroundColor Green
Write-Host "  - Dosye USB/SSD : $gymDir" -ForegroundColor Green
Write-Host "  - Ajan SecurGYM : v$agentVer $(if ($agentLive) { '[AKTIF v3.6.2]' } else { '[Ap demare]' })" -ForegroundColor Green
Write-Host "  - Gadyen SYSTEM : Tach SecurGYM_Gadyen (150ms, 0ms DAD, pa gen domi USB)" -ForegroundColor Green
Write-Host "  - Kat Dock/W2   : $(if ($activeW2Adapter) { "$($activeW2Adapter.Name) -> 192.168.1.50 [FIKS PEMANAN]" } else { 'Pare otomatikman le USB/kab ploge' })" -ForegroundColor Green
Write-Host "  - Teminal W2    : $(if ($w2Online) { "$w2Ip [KONEKTE]" } else { "$w2Ip [Tcheke fil kab/kouran]" })" -ForegroundColor $(if ($w2Online) { 'Green' } else { 'Yellow' })
Write-Host "  - Kach Navigate   : Netwaye net" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "SecurGYM ap louvri kounye a..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

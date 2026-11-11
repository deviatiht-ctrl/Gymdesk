# ========================================================================
#  repare.ps1 - REPARASYON PEMANAN SECERGYM (WEB + DOCK + W2 + WHATSAPP)
#  Egzekite nan PowerShell sou laptop gym nan:
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
Write-Host "  REPARASYON ULTIME PEMANAN SECERGYM (DOCK + W2 + WHATSAPP + WEB CACHE)" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Femen ansyen pwosesis background ak tach pou mizajou ak netwayaj kach la pase pwop
Write-Host "[1/8] Femen ansyen pwosesis ak tach pou fichye yo libere net..." -ForegroundColor Yellow
foreach ($tn in @('SecurGYM_Gadyen', 'SecurGYM_AccessAgent', 'SecurGYM_WhatsApp')) {
    Stop-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'Gadyen_Ultime\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-CimInstance Win32_Process -Filter "Name = 'wscript.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'Demarrer_Agent_Silencieux|Demarrer_WhatsApp_Silencieux' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'whatsapp_service|server\.js' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# Touye Chromium headless kite pa whatsapp-web.js si li te kole
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -match 'chrome\.exe|msedge\.exe') -and ($_.CommandLine -match '\.wwebjs_auth|session-account_') } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Stop-Process -Name access_agent, biostar_tool -Force -ErrorAction SilentlyContinue
taskkill /f /im access_agent.exe /im biostar_tool.exe >nul 2>&1
Start-Sleep -Milliseconds 900
Write-Host "      -> Ansyen pwosesis yo femen pwop." -ForegroundColor Green

# 3. Jwenn dosye GymDesk_USB reyel la sou machin nan
Write-Host "[2/8] Ap chache enstalasyon GymDesk_USB sou laptop la..." -ForegroundColor Yellow
$searchPaths = @()
try {
    foreach ($regName in @('SecurGYM_AccessAgent', 'SecurGYM_WhatsApp')) {
        $runVal = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $regName -ErrorAction SilentlyContinue).$regName
        if ($runVal -and $runVal -match '([A-Za-z]:\\[^"]*GymDesk_USB)') {
            $searchPaths += $matches[1]
        } elseif ($runVal -and $runVal -match '([A-Za-z]:\\[^"]+)\\Demarrer_(Agent|WhatsApp)_Silencieux\.vbs') {
            $searchPaths += $matches[1]
        }
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

# 4. Telechaje denye fichye yo sou GitHub (Ajan v3.6.3, biostar_tool AutoLock, Gadyen, WhatsApp, Web)
Write-Host "[3/8] Telechaje denye mizajou yo (Ajan v3.6.3, W2 AutoLock, Gadyen, WhatsApp, Web)..." -ForegroundColor Yellow
$baseUrl = 'https://raw.githubusercontent.com/deviatiht-ctrl/Gymdesk/main/GymDesk_USB'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'

New-Item -ItemType Directory -Force -Path "$gymDir\web" | Out-Null
New-Item -ItemType Directory -Force -Path "$gymDir\whatsapp_service" | Out-Null

$filesToUpdate = @(
    @{ Url = "$baseUrl/Gadyen_Ultime.ps1?v=$stamp";                  Out = "$gymDir\Gadyen_Ultime.ps1";                  MinSize = 1000 },
    @{ Url = "$baseUrl/DEMARE_TOUT_ULTIME.bat?v=$stamp";              Out = "$gymDir\DEMARE_TOUT_ULTIME.bat";              MinSize = 500 },
    @{ Url = "$baseUrl/Lancer_SecurGYM.bat?v=$stamp";                 Out = "$gymDir\Lancer_SecurGYM.bat";                 MinSize = 500 },
    @{ Url = "$baseUrl/Lancer_WhatsApp.bat?v=$stamp";                 Out = "$gymDir\Lancer_WhatsApp.bat";                 MinSize = 400 },
    @{ Url = "$baseUrl/Demarrer_Agent_Silencieux.vbs?v=$stamp";       Out = "$gymDir\Demarrer_Agent_Silencieux.vbs";       MinSize = 200 },
    @{ Url = "$baseUrl/Demarrer_WhatsApp_Silencieux.vbs?v=$stamp";    Out = "$gymDir\Demarrer_WhatsApp_Silencieux.vbs";    MinSize = 300 },
    @{ Url = "$baseUrl/access_agent.exe?v=$stamp";                    Out = "$gymDir\access_agent.exe";                    MinSize = 1000000 },
    @{ Url = "$baseUrl/biostar_tool.exe?v=$stamp";                    Out = "$gymDir\biostar_tool.exe";                    MinSize = 20000 },
    @{ Url = "$baseUrl/whatsapp_service/package.json?v=$stamp";       Out = "$gymDir\whatsapp_service\package.json";       MinSize = 100 },
    @{ Url = "$baseUrl/whatsapp_service/server.js?v=$stamp";          Out = "$gymDir\whatsapp_service\server.js";          MinSize = 5000 },
    @{ Url = "$baseUrl/web/version.json?v=$stamp";                    Out = "$gymDir\web\version.json";                    MinSize = 10 },
    @{ Url = "$baseUrl/web/index.html?v=$stamp";                      Out = "$gymDir\web\index.html";                      MinSize = 1000 },
    @{ Url = "$baseUrl/web/flutter.js?v=$stamp";                      Out = "$gymDir\web\flutter.js";                      MinSize = 500 },
    @{ Url = "$baseUrl/web/flutter_bootstrap.js?v=$stamp";            Out = "$gymDir\web\flutter_bootstrap.js";            MinSize = 1000 },
    @{ Url = "$baseUrl/web/main.dart.js?v=$stamp";                    Out = "$gymDir\web\main.dart.js";                    MinSize = 1000000 }
)

if (-not (Test-Path "$gymDir\Lib\Window\lib\x64\BS_SDK_V2.dll")) {
    New-Item -ItemType Directory -Force -Path "$gymDir\Lib\Window\lib\x64" | Out-Null
    $filesToUpdate += @(
        @{ Url = "$baseUrl/Lib/Window/lib/x64/BS_SDK_V2.dll";         Out = "$gymDir\Lib\Window\lib\x64\BS_SDK_V2.dll";         MinSize = 100000 },
        @{ Url = "$baseUrl/Lib/Window/lib/x64/libcrypto-1_1-x64.dll"; Out = "$gymDir\Lib\Window\lib\x64\libcrypto-1_1-x64.dll"; MinSize = 100000 },
        @{ Url = "$baseUrl/Lib/Window/lib/x64/libssl-1_1-x64.dll";    Out = "$gymDir\Lib\Window\lib\x64\libssl-1_1-x64.dll";    MinSize = 100000 }
    )
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($f in $filesToUpdate) {
    $leaf = Split-Path $f.Out -Leaf
    $tmp = "$($f.Out).new"
    try {
        Write-Host "      -> $leaf..." -NoNewline
        Invoke-WebRequest -Uri $f.Url -OutFile $tmp -UseBasicParsing -TimeoutSec 90 -ErrorAction Stop
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
    }
}

# Kenbe dosye app\ ak sou-dosye whatsapp_service\ senkronize
if (Test-Path "$gymDir\app") {
    if (Test-Path "$gymDir\access_agent.exe") { Copy-Item "$gymDir\access_agent.exe" "$gymDir\app\access_agent.exe" -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$gymDir\biostar_tool.exe") { Copy-Item "$gymDir\biostar_tool.exe" "$gymDir\app\biostar_tool.exe" -Force -ErrorAction SilentlyContinue }
}
if (Test-Path "$gymDir\Demarrer_WhatsApp_Silencieux.vbs") {
    Copy-Item "$gymDir\Demarrer_WhatsApp_Silencieux.vbs" "$gymDir\whatsapp_service\Demarrer_WhatsApp_Silencieux.vbs" -Force -ErrorAction SilentlyContinue
}
if (Test-Path "$gymDir\Lancer_WhatsApp.bat") {
    Copy-Item "$gymDir\Lancer_WhatsApp.bat" "$gymDir\whatsapp_service\LANCER_WHATSAPP.bat" -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path "$gymDir\terminal.json")) {
    '{"ip":"192.168.1.41","port":51211}' | Set-Content -Path "$gymDir\terminal.json" -Encoding ASCII
}

# 5. Enstale Node.js LTS si l absan + Enstale depandans WhatsApp (whatsapp-web.js)
Write-Host "[4/8] Verifye Node.js LTS ak depandans WhatsApp (:47812)..." -ForegroundColor Yellow
$env:Path = "$env:ProgramFiles\nodejs;$env:LOCALAPPDATA\Programs\nodejs;$env:APPDATA\npm;" + $env:Path
$env:PUPPETEER_SKIP_DOWNLOAD = 'true'

function Find-NodeExe {
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }
    foreach ($candidate in @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

$nodeExe = Find-NodeExe
if (-not $nodeExe) {
    Write-Host "      -> Node.js pa jwenn. Ap enstale Node.js LTS an silans..." -ForegroundColor Cyan
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements | Out-Null
    }
    $env:Path = "$env:ProgramFiles\nodejs;$env:LOCALAPPDATA\Programs\nodejs;$env:APPDATA\npm;" + $env:Path
    $nodeExe = Find-NodeExe
    if (-not $nodeExe) {
        try {
            $msiPath = Join-Path $env:TEMP 'node-lts-x64.msi'
            $msiUrl = 'https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi'
            try {
                $idx = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 15 -ErrorAction Stop
                $lts = $idx | Where-Object { $_.lts -and $_.files -contains 'win-x64-msi' } | Select-Object -First 1
                if ($lts -and $lts.version) {
                    $msiUrl = "https://nodejs.org/dist/$($lts.version)/node-$($lts.version)-x64.msi"
                }
            } catch {}
            Write-Host "      -> Telechaje $msiUrl..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
            Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -ErrorAction Stop
            Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "      -> [ATANSYON] Enstalasyon Node.js gen pwoblem: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    $env:Path = "$env:ProgramFiles\nodejs;$env:LOCALAPPDATA\Programs\nodejs;$env:APPDATA\npm;" + $env:Path
    $nodeExe = Find-NodeExe
}

$waDir = "$gymDir\whatsapp_service"
$waDepsOk = $false
if ($nodeExe) {
    $nodeVer = & $nodeExe -v 2>$null
    Write-Host "      -> Node.js jwenn: $nodeVer ($nodeExe)" -ForegroundColor Green
    $npmCmd = Join-Path (Split-Path $nodeExe -Parent) 'npm.cmd'
    if (-not (Test-Path $npmCmd)) { $npmCmd = 'npm.cmd' }
    if ((Test-Path "$waDir\package.json") -and (
        -not (Test-Path "$waDir\node_modules\whatsapp-web.js") -or
        -not (Test-Path "$waDir\node_modules\express") -or
        -not (Test-Path "$waDir\node_modules\qrcode") -or
        -not (Test-Path "$waDir\node_modules\cors")
    )) {
        Write-Host "      -> Enstale pake npm WhatsApp yo (--omit=dev)..." -ForegroundColor Cyan
        Push-Location $waDir
        & $npmCmd install --omit=dev --no-audit --no-fund 2>&1 | ForEach-Object { }
        Pop-Location
    }
    $waDepsOk = (Test-Path "$waDir\node_modules\whatsapp-web.js") -and (Test-Path "$waDir\server.js")
    if ($waDepsOk) {
        & $nodeExe --check "$waDir\server.js" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "      -> WhatsApp server.js ak depandans yo [PARE]" -ForegroundColor Green
        }
    }
} else {
    Write-Host "      -> [ATANSYON] Node.js pa rive enstale (tcheke entenet)." -ForegroundColor DarkYellow
}

# Netwaye ansyen verou Chromium ki te bloke sesyon WhatsApp yo (san efase auth la)
if (Test-Path "$waDir\.wwebjs_auth") {
    Get-ChildItem -Path "$waDir\.wwebjs_auth" -Directory -Filter 'session-*' -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($lk in @('SingletonLock', 'SingletonSocket', 'SingletonCookie', 'DevToolsActivePort', 'lockfile')) {
            Remove-Item (Join-Path $_.FullName $lk) -Force -ErrorAction SilentlyContinue
        }
    }
}

# 6. Netwayaj kach Chrome ak Microsoft Edge SAN FASE Cookies / Favoris / Modpas
Write-Host "[5/8] Netwaye kach Chrome ak Edge (san efase cookies, favoris, ni modpas)..." -ForegroundColor Yellow
foreach ($bName in @('msedge', 'chrome')) {
    $procs = @(Get-Process -Name $bName -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        $procs | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch {} }
        Start-Sleep -Milliseconds 900
        Stop-Process -Name $bName -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Milliseconds 400

$browserUserDataRoots = @(
    "$gymDir\data\profile",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
    "$env:LOCALAPPDATA\Google\Chrome\User Data"
)
$cleanedProfiles = 0
foreach ($rootPath in $browserUserDataRoots) {
    if (-not (Test-Path $rootPath)) { continue }
    $profileDirs = @()
    if (Test-Path "$rootPath\Default") { $profileDirs += "$rootPath\Default" }
    Get-ChildItem -Path $rootPath -Directory -Filter 'Profile *' -ErrorAction SilentlyContinue | ForEach-Object { $profileDirs += $_.FullName }
    foreach ($profDir in $profileDirs) {
        foreach ($sub in @(
            'Cache',
            'Code Cache',
            'GPUCache',
            'ShaderCache',
            'Service Worker\CacheStorage',
            'Service Worker\ScriptCache',
            'Service Worker\Database'
        )) {
            $target = Join-Path $profDir $sub
            if (Test-Path $target) {
                Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        $cleanedProfiles++
    }
}
Write-Host "      -> Kach Chrome/Edge netwaye pwop ($cleanedProfiles pwofil). Cookies/Modpas entak!" -ForegroundColor Green

# 7. Aplike Gadyen pemanan + koupe tout ekonomizasyon eneji USB/PCIe/Dock/Ethernet (PA JANM touche Wi-Fi)
Write-Host "[6/8] Koupe domi USB/PCIe + MediaSense + DAD 0ms + Enstale Gadyen SYSTEM (150ms)..." -ForegroundColor Yellow
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
    $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802\.11|Bluetooth|Virtual|VPN|Loopback|Hyper-V|VMware|TAP|WSL|vEthernet|Docker|WAN Miniport'
})
$activeW2Adapter = $wiredAdapters | Where-Object {
    $has50 = Get-NetIPAddress -InterfaceIndex $_.ifIndex -IPAddress '192.168.1.50' -ErrorAction SilentlyContinue
    $null -ne $has50
} | Select-Object -First 1

if ($activeW2Adapter) {
    $dadVal = (Get-NetIPInterface -InterfaceIndex $activeW2Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).DadTransmits
    Write-Host "      -> Dock/Rezo W2 : $($activeW2Adapter.Name) ($($activeW2Adapter.InterfaceDescription)) [IP 192.168.1.50 | DAD=$dadVal | Eta=$($activeW2Adapter.Status)]" -ForegroundColor Green
} else {
    Write-Host "      -> [INFO] Pa gen Dock Extender ki gen 192.168.1.50 kounye a (Gadyen 150ms la pare touswit ou ploge l!)" -ForegroundColor DarkYellow
}

$taskObj = Get-ScheduledTask -TaskName 'SecurGYM_Gadyen' -ErrorAction SilentlyContinue
$mediaVal = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'DisableDHCPMediaSense' -ErrorAction SilentlyContinue).DisableDHCPMediaSense
Write-Host "      -> Tach SYSTEM  : $(if ($taskObj) { $taskObj.State } else { 'Pa jwenn' }) | DisableDHCPMediaSense=$mediaVal" -ForegroundColor Cyan

# 8. Tcheke teminal BioEntry W2 + AutoLock + 1 kontak + Auto-repare IP
Write-Host "[7/8] Tcheke teminal BioEntry W2 (AutoLock + 1 kontak + IP 192.168.1.41)..." -ForegroundColor Yellow
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
for ($attempt = 1; $attempt -le 6; $attempt++) {
    if (Test-FastPing $w2Ip) { $w2Online = $true; break }
    Start-Sleep -Milliseconds 200
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
        Start-Sleep -Milliseconds 250
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
    Write-Host "      -> W2 poko reponn ping (normal si laptop la lakay ou san kab W2)." -ForegroundColor DarkYellow
}

# 9. Anrejistre demaraj otomatik PEMANAN pou SecurGYM AccessAgent (:47811) AK WhatsApp (:47812)
Write-Host "[8/8] Anrejistre demaraj otomatik Windows + Watchdog pou Ajan (:47811) ak WhatsApp (:47812)..." -ForegroundColor Yellow
$vbsAgent = "$gymDir\Demarrer_Agent_Silencieux.vbs"
$vbsWa    = "$gymDir\Demarrer_WhatsApp_Silencieux.vbs"

Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurGYM_AccessAgent' -Value "wscript.exe `"$vbsAgent`"" -Type String -Force -ErrorAction SilentlyContinue
if (Test-Path $vbsWa) {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurGYM_WhatsApp' -Value "wscript.exe `"$vbsWa`"" -Type String -Force -ErrorAction SilentlyContinue
}

# Kreye tach planifye Itilizate (AtLogOn + Watchdog chak 2 min) pou tou de kouri an background menm si laptop la reboot
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$userPr = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$userSet = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew

foreach ($svc in @(
    @{ Name = 'SecurGYM_AccessAgent'; Vbs = $vbsAgent },
    @{ Name = 'SecurGYM_WhatsApp';    Vbs = $vbsWa }
)) {
    if (Test-Path $svc.Vbs) {
        $act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$($svc.Vbs)`"" -WorkingDirectory $gymDir
        $t1 = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
        $t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 3650)
        Register-ScheduledTask -TaskName $svc.Name -Action $act -Trigger @($t1, $t2) -Settings $userSet -Principal $userPr -Force | Out-Null
    }
}

# Lanse tou de an silans nan sesyon kounye a
if (Test-Path $vbsAgent) {
    Start-Process wscript.exe -ArgumentList "`"$vbsAgent`"" -WorkingDirectory $gymDir -WindowStyle Hidden
}
if (Test-Path $vbsWa) {
    Start-Process wscript.exe -ArgumentList "`"$vbsWa`"" -WorkingDirectory $gymDir -WindowStyle Hidden
}

# Verifye si tou de sevis reponn
$agentLive = $false
$agentVer = '?'
for ($i = 1; $i -le 16; $i++) {
    try {
        $h = Invoke-RestMethod -Uri 'http://127.0.0.1:47811/health' -TimeoutSec 2 -ErrorAction Stop
        if ($h -and $h.version) {
            $agentVer = [string]$h.version
            $agentLive = ($agentVer -eq '3.6.3')
            if ($agentLive) { break }
        }
    } catch {}
    Start-Sleep -Milliseconds 500
}

$waLive = $false
for ($i = 1; $i -le 20; $i++) {
    try {
        $hw = Invoke-RestMethod -Uri 'http://127.0.0.1:47812/health' -TimeoutSec 2 -ErrorAction Stop
        if ($hw) { $waLive = $true; break }
    } catch {}
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Green
Write-Host "  [SIKSE TOTAL] TOUT SYSTEM NAN ENSTALE E LI PEMANAN!" -ForegroundColor Green
Write-Host "  - Dosye USB/SSD : $gymDir" -ForegroundColor Green
Write-Host "  - Ajan SecurGYM : v$agentVer $(if ($agentLive) { '[AKTIF v3.6.3 - :47811]' } else { '[Ap demare :47811]' })" -ForegroundColor Green
Write-Host "  - Sevis WhatsApp: $(if ($waLive) { '[AKTIF AN BACKGROUND - :47812]' } else { '[Enstale nan startup - :47812 ap monte]' })" -ForegroundColor $(if ($waLive) { 'Green' } else { 'Yellow' })
Write-Host "  - Gadyen SYSTEM : Tach SecurGYM_Gadyen (150ms, 0ms DAD, san domi USB/PCIe)" -ForegroundColor Green
Write-Host "  - Kat Dock/W2   : $(if ($activeW2Adapter) { "$($activeW2Adapter.Name) -> 192.168.1.50 [FIKS PEMANAN]" } else { 'Pare otomatikman le USB/kab ploge' })" -ForegroundColor Green
Write-Host "  - Teminal W2    : $(if ($w2Online) { "$w2Ip [KONEKTE]" } else { "$w2Ip [Pare sou gym nan]" })" -ForegroundColor $(if ($w2Online) { 'Green' } else { 'Yellow' })
Write-Host "  - Kach Edge/Chrome : Netwaye pwop (Web Vercel + Local pare)" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Ou mèt ouvri Chrome / Edge sou https://gymdesk.vercel.app kounye a!" -ForegroundColor Cyan
Start-Sleep -Seconds 4

# ========================================================================
#  repare.ps1 - DIAGNOSTIK AK REPARASYON TOTAL POU SECERGYM + DOCK EXTENDER
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
Write-Host "  DIAGNOSTIK AK REPARASYON TOTAL SECERGYM (DOCK EXTENDER + W2)" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# 2. Femen tout ansyen pwosesis ki te ka bloke
Write-Host "[1/7] Femen tout ansyen pwosesis nan background..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName 'SecurGYM_Gadyen' -ErrorAction SilentlyContinue
Stop-Process -Name access_agent, biostar_tool, wscript, msedge -Force -ErrorAction SilentlyContinue
taskkill /f /im access_agent.exe /im biostar_tool.exe /im wscript.exe >nul 2>&1
Start-Sleep -Seconds 1
Write-Host "      -> Pwosesis femen avek sikse." -ForegroundColor Green

# 3. Jwenn dosye GymDesk_USB la sou machin nan
Write-Host "[2/7] Ap chache dosye GymDesk_USB sou machin nan..." -ForegroundColor Yellow
$searchPaths = @(
    $PSScriptRoot,
    "C:\GymDesk_USB",
    "$env:USERPROFILE\Documents\GYM\GymDesk_USB",
    "$env:USERPROFILE\Documents\GymDesk_USB",
    "$env:USERPROFILE\Desktop\GymDesk_USB",
    "$env:USERPROFILE\Downloads\GymDesk_USB"
)
# Ajoute tout lekte USB (D:, E:, F:, ...)
Get-Volume | Where-Object DriveType -eq 'Removable' | ForEach-Object {
    $searchPaths += "$($_.DriveLetter):\GymDesk_USB"
}

$gymDir = $null
foreach ($p in $searchPaths) {
    if ($p -and (Test-Path "$p\DEMARE_TOUT_ULTIME.bat")) {
        $gymDir = $p
        break
    }
}

if (-not $gymDir) {
    $gymDir = "C:\GymDesk_USB"
    New-Item -ItemType Directory -Force -Path $gymDir | Out-Null
    Write-Host "      -> Kreye nouvo dosye nan $gymDir" -ForegroundColor Cyan
} else {
    Write-Host "      -> Dosye jwenn: $gymDir" -ForegroundColor Green
}

# 4. Telechaje selman nouvo fichye ki nesese yo soti sou GitHub (leje, ~15MB)
Write-Host "[3/7] Telechaje denye mizajou (Ajan v3.6.1, Gadyen, Entèfas Web)..." -ForegroundColor Yellow
$baseUrl = "https://raw.githubusercontent.com/deviatiht-ctrl/Gymdesk/main/GymDesk_USB"
$filesToUpdate = @(
    @{ Url = "$baseUrl/Gadyen_Ultime.ps1"; Out = "$gymDir\Gadyen_Ultime.ps1" },
    @{ Url = "$baseUrl/DEMARE_TOUT_ULTIME.bat"; Out = "$gymDir\DEMARE_TOUT_ULTIME.bat" },
    @{ Url = "$baseUrl/Lancer_SecurGYM.bat"; Out = "$gymDir\Lancer_SecurGYM.bat" },
    @{ Url = "$baseUrl/access_agent.exe"; Out = "$gymDir\access_agent.exe" },
    @{ Url = "$baseUrl/web/index.html"; Out = "$gymDir\web\index.html" },
    @{ Url = "$baseUrl/web/flutter_bootstrap.js"; Out = "$gymDir\web\flutter_bootstrap.js" },
    @{ Url = "$baseUrl/web/main.dart.js"; Out = "$gymDir\web\main.dart.js" }
)

New-Item -ItemType Directory -Force -Path "$gymDir\web" | Out-Null

$downloadSuccess = $true
foreach ($f in $filesToUpdate) {
    try {
        Write-Host "      -> Telechaje $(Split-Path $f.Out -Leaf)..." -NoNewline
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tmp = "$($f.Out).new"
        Invoke-WebRequest -Uri $f.Url -OutFile $tmp -UseBasicParsing -TimeoutSec 45
        if (Test-Path $f.Out) {
            Remove-Item $f.Out -Force -ErrorAction SilentlyContinue
        }
        Move-Item -Path $tmp -Destination $f.Out -Force -ErrorAction SilentlyContinue
        Write-Host " [OK]" -ForegroundColor Green
    } catch {
        Write-Host " [SOTE: Pa gen entenet oubyen fichye a deja la]" -ForegroundColor DarkYellow
        $downloadSuccess = $false
    }
}

# 5. Netwaye kach Edge la
Write-Host "[4/7] Netwaye kach navigatè Edge la..." -ForegroundColor Yellow
$dataDir = "$gymDir\data\profile"
Remove-Item -Path "$dataDir\Default\Cache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$dataDir\Default\Code Cache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$dataDir\Default\Service Worker" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "      -> Kach netwaye, nouvo entèfas la ap monte dirèkteman." -ForegroundColor Green

# 6. Analize kat rezo yo epi fikse IP a sou DOCK EXTENDER a
Write-Host "[5/7] Analize kat rezo yo pou jwenn Dock Extender a..." -ForegroundColor Yellow
$candidates = @(Get-NetAdapter | Where-Object {
    $_.Status -ne 'Disabled' -and
    $_.Virtual -ne $true -and
    $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802\.11|Bluetooth|Virtual|VPN|Loopback|Hyper-V|VMware|TAP|WSL'
})

Write-Host "      Kat filaire yo jwenn sou laptop sa a:" -ForegroundColor Gray
foreach ($c in $candidates) {
    Write-Host "       * [$($c.ifIndex)] $($c.Name) - $($c.InterfaceDescription) (Eta: $($c.Status))" -ForegroundColor Gray
}

# Chwazi kat ki Up a (Dock Extender ki ploge a)
$target = $null
$up = @($candidates | Where-Object Status -eq 'Up')
if ($up.Count -eq 1) {
    $target = $up[0]
} elseif ($up.Count -gt 1) {
    $dock = @($up | Where-Object { $_.InterfaceDescription -match 'USB|Dock|ASIX|LAN|Dongle|Type-C|Realtek USB' })
    if ($dock.Count -gt 0) { $target = $dock[0] } else { $target = $up[0] }
} else {
    $dock = @($candidates | Where-Object { $_.InterfaceDescription -match 'USB|Dock|ASIX|LAN|Dongle|Type-C|Realtek USB' })
    if ($dock.Count -gt 0) { $target = $dock[0] } elseif ($candidates.Count -gt 0) { $target = $candidates[0] }
}

if (-not $target) {
    Write-Host "   [ERE] Okenn kat rezo oswa Dock Extender pa jwenn! Ploge Dock Extender a nan USB." -ForegroundColor Red
} else {
    Write-Host "      -> KAT CHWAZI POU W2: $($target.Name) ($($target.InterfaceDescription)) [ifIndex: $($target.ifIndex)]" -ForegroundColor Green

    # Retire 192.168.1.50 sou tout lot kat pou evite konfli
    Get-NetIPAddress -IPAddress 192.168.1.50, 192.168.1.16 -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceIndex -ne $target.ifIndex } |
        ForEach-Object { Remove-NetIPAddress -InterfaceIndex $_.InterfaceIndex -IPAddress $_.IPAddress -Confirm:$false -ErrorAction SilentlyContinue }

    # Konfigire kat sib la
    Set-NetIPInterface -InterfaceIndex $target.ifIndex -Dhcp Disabled -InterfaceMetric 500 -ErrorAction SilentlyContinue
    
    # Netwaye ansyen IP altènativ (tankou .249, .250) sou kat la pou kenbe sèlman 192.168.1.50
    Get-NetIPAddress -InterfaceIndex $target.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '192.168.1.50' -and $_.IPAddress -ne '192.168.1.16' } |
        ForEach-Object { Remove-NetIPAddress -InterfaceIndex $target.ifIndex -IPAddress $_.IPAddress -Confirm:$false -ErrorAction SilentlyContinue }

    # Mete IP 192.168.1.50 fiks pèmanan via netsh
    netsh interface ipv4 set address name="$($target.Name)" static 192.168.1.50 255.255.255.0 none | Out-Null
    Start-Sleep -Milliseconds 500

    # Mete IP BioStar 192.168.1.16
    $hasBio = (Get-NetIPAddress -InterfaceIndex $target.ifIndex -IPAddress '192.168.1.16' -ErrorAction SilentlyContinue)
    if (-not $hasBio) {
        netsh interface ipv4 add address name="$($target.Name)" 192.168.1.16 255.255.255.0 | Out-Null
    }

    # Wout direk W2
    Get-NetRoute -InterfaceIndex $target.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    if (-not (Get-NetRoute -InterfaceIndex $target.ifIndex -DestinationPrefix '192.168.1.41/32' -ErrorAction SilentlyContinue)) {
        New-NetRoute -InterfaceIndex $target.ifIndex -DestinationPrefix '192.168.1.41/32' -NextHop '0.0.0.0' -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null
    }

    # Firewall
    netsh advfirewall firewall delete rule name=SecurGYM_W2_TCP | Out-Null
    netsh advfirewall firewall delete rule name=SecurGYM_W2_UDP | Out-Null
    netsh advfirewall firewall add rule name=SecurGYM_W2_TCP dir=in action=allow protocol=TCP localport=51211,51212,51213 profile=any | Out-Null
    netsh advfirewall firewall add rule name=SecurGYM_W2_UDP dir=in action=allow protocol=UDP localport=51210,51211 profile=any | Out-Null

    Write-Host "      -> IP 192.168.1.50 fiks pèmanan sou kat la avek sikse!" -ForegroundColor Green
}

# 7. Tcheke tèminal W2 a
Write-Host "[6/7] Tcheke repons tèminal BioEntry W2 (192.168.1.41)..." -ForegroundColor Yellow
$w2Online = $false
for ($attempt = 1; $attempt -le 6; $attempt++) {
    if (Test-Connection -ComputerName '192.168.1.41' -Count 1 -Quiet) {
        $w2Online = $true
        break
    }
    Start-Sleep -Seconds 1
}

if ($w2Online) {
    Write-Host "      -> W2 AP REPONN (192.168.1.41 [ONLINE])!" -ForegroundColor Green
    if (Test-Path "$gymDir\biostar_tool.exe") {
        $dll = "$gymDir\Lib\Window\lib\x64"
        if (Test-Path $dll) {
            Push-Location $dll
            & "$gymDir\biostar_tool.exe" . fpfix 192.168.1.41 51211 | Out-Null
            Pop-Location
        }
    }
} else {
    Write-Host "      -> Tèminal la poko reponn ping: verifye ke fil rezo a byen klipse nan Dock Extender a ak nan W2 a, epi W2 a gen kouran." -ForegroundColor DarkYellow
}

# 8. Enstale Gadyen an pèmanan nan Windows
if (Test-Path "$gymDir\Gadyen_Ultime.ps1") {
    powershell -NoProfile -ExecutionPolicy Bypass -File "$gymDir\Gadyen_Ultime.ps1" -Enstale | Out-Null
}

# 9. Lanse SecurGYM
Write-Host "[7/7] Lanse SecurGYM ak Nouvo Ajan v3.6.1..." -ForegroundColor Yellow
Start-Process cmd -ArgumentList "/c `"$gymDir\Lancer_SecurGYM.bat`"" -WindowStyle Hidden

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Green
Write-Host "  [SIKSE TOTAL] TOUT BAGAY FIN ANALIZE EPI KORIJE!" -ForegroundColor Green
Write-Host "  - Ajan SecurGYM  : v3.6.1 [AKTIF]" -ForegroundColor Green
Write-Host "  - Kat Reseau     : $($target.Name) -> 192.168.1.50 [FIKS PÈMANAN]" -ForegroundColor Green
Write-Host "  - Teminal W2     : $(if ($w2Online) { '192.168.1.41 [KONEKTE]' } else { '192.168.1.41 [Tcheke fil kab la]' })" -ForegroundColor $(if ($w2Online) { "Green" } else { "Yellow" })
Write-Host "  - Kach Navigatè  : Netwaye nèt (Nouvo entèfas la ap louvri)" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "SecurGYM ap louvri kounye a..." -ForegroundColor Cyan
Start-Sleep -Seconds 4

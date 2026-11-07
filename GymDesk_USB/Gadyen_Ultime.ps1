# Gadyen_Ultime.ps1 - kenbe koneksyon kab W2 a (BioEntry) fiks pou SecurGYM.
#  -Enstale    : kopye gadyen an nan C:\ProgramData\SecurGYM, aplike rezo a,
#                firewall, epi kreye tach SYSTEM "SecurGYM_Gadyen" (demaraj Windows).
#  -Siveye     : bouk background (tach la): re-aplike IP a SI L PA LA SELMAN (pa janm kase koneksyon aktif).
#  -Repare     : jwenn W2 a sou kab la, remete IP li fiks, fose l verifye
#                anprent yo li menm (san Server Matching), afiche konfigirasyon an.
#  -Dezenstale : retire tach la (IP yo rete).
# Kat Wi-Fi a PA janm touche: kab W2 a pa gen gateway ni DNS, metrik li wo,
# epi se selman yon wout /32 pou W2 a ki pase sou kab la -> entenet rete sou Wi-Fi.
param([switch]$Enstale, [switch]$Siveye, [switch]$Dezenstale, [switch]$Repare, [string]$ToolDir = $PSScriptRoot, [int]$IntervalMs = 5000)

$ErrorActionPreference = 'SilentlyContinue'
$Home2   = 'C:\ProgramData\SecurGYM'
$LogFile = Join-Path $Home2 'gadyen_ultime.log'
$EtaFile = Join-Path $Home2 'gadyen_eta.txt'
$CfgFile = Join-Path $Home2 'gadyen.json'
$TaskName = 'SecurGYM_Gadyen'
$PcIp = '192.168.1.50'
$BioStarIp = '192.168.1.16'
$Prefix = 24

New-Item -ItemType Directory -Force -Path $Home2 | Out-Null

function Log($msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
  Write-Host $line
  if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) {
    Move-Item $LogFile ($LogFile + '.1') -Force
  }
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Get-W2Ip {
  foreach ($f in @($CfgFile, (Join-Path $PSScriptRoot 'terminal.json'))) {
    if (Test-Path $f) {
      try { $j = Get-Content $f -Raw | ConvertFrom-Json; if ($j.ip) { return [string]$j.ip } } catch {}
    }
  }
  return '192.168.1.41'
}

# Kat kab (802.3) fizik: USB (ASIX...) oswa PCIe.
function Get-W2Adapters {
  $candidates = @(Get-NetAdapter | Where-Object {
    $_.Status -ne 'Disabled' -and
    $_.Virtual -ne $true -and
    $_.InterfaceDescription -notmatch 'Wi-?Fi|Wireless|WLAN|802\.11|Bluetooth|Virtual|VPN|Loopback|Hyper-V|VMware|TAP|WSL'
  })
  $up = @($candidates | Where-Object Status -eq 'Up')
  if ($up.Count -eq 1) { return $up }
  if ($up.Count -gt 1) {
    $dock = @($up | Where-Object { $_.InterfaceDescription -match 'USB|Dock|ASIX|LAN|Dongle|Type-C|Realtek USB' })
    if ($dock.Count -gt 0) { return @($dock[0]) }
    return @($up[0])
  }
  $dock = @($candidates | Where-Object { $_.InterfaceDescription -match 'USB|Dock|ASIX|LAN|Dongle|Type-C|Realtek USB' })
  if ($dock.Count -gt 0) { return @($dock[0]) }
  if ($candidates.Count -gt 0) { return @($candidates[0]) }
  return @()
}

function Set-W2Network([string]$w2) {
  $sel = @(Get-W2Adapters)
  if ($sel.Count -eq 0) {
    return $false
  }
  $target = $sel[0]
  $i = $target.ifIndex

  # Si kat la genyen 192.168.1.50 deja, PA KASE ANYEN, PA TOUCHE L!
  $targetHasIp = (Get-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -ErrorAction SilentlyContinue)
  if ($targetHasIp) {
    # Asire selman ke wout direk la toujou prezan
    if (-not (Get-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -ErrorAction SilentlyContinue)) {
      New-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -NextHop '0.0.0.0' -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null
    }
    return $false
  }

  # Yon IP pa ka sou 2 kat: retire 192.168.1.50/.16 sou TOUT lot kat yo.
  foreach ($ip in @($PcIp, $BioStarIp)) {
    Get-NetIPAddress -IPAddress $ip -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.InterfaceIndex -ne $i } |
      ForEach-Object { Remove-NetIPAddress -InterfaceIndex $_.InterfaceIndex -IPAddress $ip -Confirm:$false -ErrorAction SilentlyContinue }
  }
  Get-NetRoute -DestinationPrefix "$w2/32" -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceIndex -ne $i } |
    ForEach-Object { Remove-NetRoute -InterfaceIndex $_.InterfaceIndex -DestinationPrefix "$w2/32" -Confirm:$false -ErrorAction SilentlyContinue }

  # Konfigire kat la ak netsh (fiks pèmanan nan rejis Windows)
  netsh interface ipv4 set address name="$($target.Name)" static $PcIp 255.255.255.0 none | Out-Null
  Start-Sleep -Milliseconds 400
  netsh interface ipv4 add address name="$($target.Name)" $BioStarIp 255.255.255.0 | Out-Null

  # Asire pa gen wout default (gateway) sou kab W2 a pou entenet la rete sou Wi-Fi
  Get-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
  Set-DnsClientServerAddress -InterfaceIndex $i -ResetServerAddresses -ErrorAction SilentlyContinue
  Set-DnsClient -InterfaceIndex $i -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue

  # Wout direk pou W2 a
  if (-not (Get-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -ErrorAction SilentlyContinue)) {
    New-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -NextHop '0.0.0.0' -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null
  }

  $p = Get-NetConnectionProfile -InterfaceIndex $i -ErrorAction SilentlyContinue
  if ($p -and $p.NetworkCategory -ne 'Private') { Set-NetConnectionProfile -InterfaceIndex $i -NetworkCategory Private -ErrorAction SilentlyContinue }

  Log "Kat '$($target.Name)' ($($target.InterfaceDescription)): $PcIp/$Prefix fiks pèmanan pou W2 ($w2)."
  return $true
}

function Set-Firewall {
  foreach ($r in 'SecurGYM_W2_TCP', 'SecurGYM_W2_UDP') { netsh advfirewall firewall delete rule name=$r | Out-Null }
  netsh advfirewall firewall add rule name=SecurGYM_W2_TCP dir=in action=allow protocol=TCP localport=51211,51212,51213 profile=any | Out-Null
  netsh advfirewall firewall add rule name=SecurGYM_W2_UDP dir=in action=allow protocol=UDP localport=51210,51211 profile=any | Out-Null
}

function Write-Eta([string]$w2) {
  $up = Get-W2Adapters | Where-Object Status -eq 'Up' | Select-Object -First 1
  $ok = $false
  if ($up) { $ok = Test-Connection -ComputerName $w2 -Count 1 -Quiet }
  $nom = if ($up) { "$($up.Name) ($($up.InterfaceDescription))" } else { 'Okenn (ploge kab la nan USB)' }
  $txt = "=== ETA GADYEN SECERGYM ===`r`n" +
    "Dat     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n" +
    "Kat     : $nom`r`n" +
    "PC IP   : $PcIp/$Prefix`r`n" +
    "W2 IP   : $w2`r`n" +
    "Konekte : $(if ($ok) { 'WI (W2 sou liy, pare)' } else { 'NON (verifye kab la ak kouran)' })`r`n"
  Set-Content -Path $EtaFile -Value $txt -Encoding UTF8
}

if ($Dezenstale) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Log 'Tach gadyen an retire.'
  exit 0
}

$w2 = Get-W2Ip

if ($Enstale) {
  $src = $MyInvocation.MyCommand.Path
  $dst = Join-Path $Home2 'Gadyen_Ultime.ps1'
  if ($src -ne $dst) { Copy-Item $src $dst -Force }
  (@{ ip = $w2; port = 51211 } | ConvertTo-Json) | Set-Content -Path $CfgFile -Encoding UTF8
  Set-Firewall
  Set-W2Network $w2 | Out-Null
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dst`" -Siveye"
  $trg = New-ScheduledTaskTrigger -AtStartup
  $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  $pr = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Settings $set -Principal $pr -Force | Out-Null
  Stop-ScheduledTask -TaskName $TaskName
  Start-ScheduledTask -TaskName $TaskName
  Write-Eta $w2
  Log "Gadyen enstale: tach $TaskName (SYSTEM, demaraj Windows), W2 = $w2"
  Get-Content $EtaFile
  exit 0
}

if ($Repare) {
  $tool = Join-Path $ToolDir 'biostar_tool.exe'
  $dll = Join-Path $ToolDir 'Lib\Window\lib\x64'
  if (-not (Test-Path $tool)) { Write-Host "[ERE] biostar_tool.exe pa jwenn nan $ToolDir" -ForegroundColor Red; exit 1 }
  Push-Location $dll
  Write-Host "Recheche teminal W2 sou kab la (UDP broadcast)..."
  $found = & $tool $dll search | Where-Object { $_ -like "device`t*" }
  if (-not $found) {
    Write-Host '[ATANSYON] Okenn W2 pa reponn: verifye kab la ak kouran teminal la.' -ForegroundColor Yellow
  }
  foreach ($d in $found) {
    $f = $d -split "`t"
    Write-Host ("  W2 jwenn: id=" + $f[1] + "  IP=" + $f[3] + ":" + $f[4])
    if ($f[3] -ne $w2) {
      Write-Host "  -> IP a pa bon, mwen fikse l sou $w2 (san DHCP)..." -ForegroundColor Yellow
      & $tool $dll setip $f[1] $w2 255.255.255.0 0.0.0.0
      Log ("W2 " + $f[1] + ": IP " + $f[3] + " -> $w2")
      Start-Sleep -Seconds 5
    }
  }
  Write-Host "Fose W2 verifye anprent yo li menm + 1 kontak..."
  $r = & $tool $dll fpfix $w2 51211
  Write-Host ("  " + ($r -join ' '))
  if ($r -match 'fixed') { Log ("W2 fpfix: " + ($r -join ' ')) }
  Pop-Location
  Write-Eta $w2
  exit 0
}

if ($Siveye) {
  Log "Gadyen demare (veye W2), W2 = $w2"
  $tick = 0
  while ($true) {
    try {
      $upAdapters = @(Get-W2Adapters | Where-Object Status -eq 'Up')
      $upIdx = @($upAdapters | ForEach-Object { $_.ifIndex })
      if ($upIdx.Count -gt 0) {
        $hasIp = (Get-NetIPAddress -IPAddress $PcIp -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $upIdx -contains $_.InterfaceIndex })
        if (-not $hasIp) {
          if (Set-W2Network $w2) { Log 'Rezo W2 aplike sou nouvo pò USB konekte.' }
        }
      }
      if (($tick % 12) -eq 0) { Write-Eta $w2 }
    } catch { Log ('Ere: ' + $_.Exception.Message) }
    $tick++
    Start-Sleep -Seconds 5
  }
}

Write-Host 'Itilizasyon: Gadyen_Ultime.ps1 -Enstale | -Repare | -Siveye | -Dezenstale'

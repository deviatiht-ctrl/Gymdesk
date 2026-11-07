# Gadyen_Ultime.ps1 - kenbe koneksyon kab W2 a (BioEntry) fiks pou SecurGYM.
#  -Enstale    : kopye gadyen an nan C:\ProgramData\SecurGYM, aplike rezo a,
#                firewall, epi kreye tach SYSTEM "SecurGYM_Gadyen" (demaraj Windows).
#  -Siveye     : bouk background (tach la): re-aplike IP a si l disparet.
#  -Repare     : jwenn W2 a sou kab la, remete IP li fiks, fose l verifye
#                anprent yo li menm (san Server Matching), afiche konfigirasyon an.
#  -Dezenstale : retire tach la (IP yo rete).
# Kat Wi-Fi a PA janm touche: kab W2 a pa gen gateway ni DNS, metrik li wo,
# epi se selman yon wout /32 pou W2 a ki pase sou kab la -> entenet rete sou Wi-Fi.
param([switch]$Enstale, [switch]$Siveye, [switch]$Dezenstale, [switch]$Repare, [string]$ToolDir = $PSScriptRoot, [int]$IntervalMs = 2000)

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

# Kat kab (802.3) fizik: USB (ASIX...) oswa PCIe. Nou sote yon kat ki gen
# entenet pa DHCP sou yon LOT rezo (pa 192.168.1.x) pou pa kase yon kab routeur.
# Si yon kat konekte, se li selman nou konfigire; sinon nou prepare yo tout.
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
  $changed = $false
  $sel = @(Get-W2Adapters)
  if ($sel.Count -eq 0) {
    Log "Okenn kat rezo filaire/dock pa jwenn."
    return $false
  }
  $target = $sel[0]
  $i = $target.ifIndex

  # Yon IP pa ka sou 2 kat: retire 192.168.1.50/.16 sou TOUT lot kat yo.
  foreach ($ip in @($PcIp, $BioStarIp)) {
    Get-NetIPAddress -IPAddress $ip -AddressFamily IPv4 -PolicyStore PersistentStore -ErrorAction SilentlyContinue |
      Where-Object { $_.InterfaceIndex -ne $i } |
      ForEach-Object { Remove-NetIPAddress -InterfaceIndex $_.InterfaceIndex -IPAddress $ip -Confirm:$false -ErrorAction SilentlyContinue; $changed = $true }
    Get-NetIPAddress -IPAddress $ip -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
      Where-Object { $_.InterfaceIndex -ne $i } |
      ForEach-Object { Remove-NetIPAddress -InterfaceIndex $_.InterfaceIndex -IPAddress $ip -Confirm:$false -ErrorAction SilentlyContinue; $changed = $true }
  }
  Get-NetRoute -DestinationPrefix "$w2/32" -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceIndex -ne $i } |
    ForEach-Object { Remove-NetRoute -InterfaceIndex $_.InterfaceIndex -DestinationPrefix "$w2/32" -Confirm:$false -ErrorAction SilentlyContinue; $changed = $true }

  # Konfigire selman kat nou chwazi a (Dock oswa Ethernet aktif la)
  $ipif = Get-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4
  if ($ipif.Dhcp -ne 'Disabled') { Set-NetIPInterface -InterfaceIndex $i -Dhcp Disabled; $changed = $true }
  if ($ipif.InterfaceMetric -ne 500) { Set-NetIPInterface -InterfaceIndex $i -InterfaceMetric 500 }
  $have = @(Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -PolicyStore PersistentStore -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
  foreach ($old in $have) {
    if ($old -ne $PcIp -and $old -ne $BioStarIp) { Remove-NetIPAddress -InterfaceIndex $i -IPAddress $old -Confirm:$false -ErrorAction SilentlyContinue; $changed = $true }
  }
  if ($have -notcontains $PcIp) {
    New-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -PrefixLength $Prefix -ErrorAction SilentlyContinue | Out-Null; $changed = $true
  }

  if ($target.Status -eq 'Up') {
    $st = ''
    for ($wait = 0; $wait -lt 7; $wait++) {
      $st = (Get-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction SilentlyContinue).AddressState
      if ($st -eq 'Preferred') { break }
      Start-Sleep -Milliseconds 500
    }
    if ($st -eq 'Duplicate') {
      foreach ($alt in 250..245 | ForEach-Object { "192.168.1.$_" }) {
        if ($alt -eq $PcIp) { continue }
        if (Test-Connection -ComputerName $alt -Count 1 -Quiet) { continue }
        Remove-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $i -IPAddress $alt -PrefixLength $Prefix -ErrorAction SilentlyContinue | Out-Null
        Log ("IP $PcIp an konfli rezo (Duplicate) -> chanje sou $alt")
        $script:PcIp = $alt; $changed = $true
        break
      }
    }
  }

  if ($have -notcontains $BioStarIp) {
    New-NetIPAddress -InterfaceIndex $i -IPAddress $BioStarIp -PrefixLength $Prefix -SkipAsSource $true -ErrorAction SilentlyContinue | Out-Null; $changed = $true
  }
  Get-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
  Set-DnsClientServerAddress -InterfaceIndex $i -ResetServerAddresses -ErrorAction SilentlyContinue
  Set-DnsClient -InterfaceIndex $i -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue

  if (-not (Get-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -ErrorAction SilentlyContinue)) {
    New-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -NextHop '0.0.0.0' -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null; $changed = $true
  }
  $p = Get-NetConnectionProfile -InterfaceIndex $i -ErrorAction SilentlyContinue
  if ($p -and $p.NetworkCategory -ne 'Private') { Set-NetConnectionProfile -InterfaceIndex $i -NetworkCategory Private -ErrorAction SilentlyContinue }

  if ($changed) { Log ("Kat '" + $target.Name + "' (" + $target.InterfaceDescription + "): $PcIp/$Prefix + wout $w2/32, san gateway/DNS") }
  return $changed
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
  $txt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`n" +
    'Kab W2      : ' + $(if ($up) { $up.Name + ' (konekte)' } else { 'PA KONEKTE' }) + "`r`n" +
    "IP PC       : $PcIp (+ $BioStarIp BioStar)`r`n" +
    "Teminal W2  : $w2 -> " + $(if ($ok) { 'REPONN' } else { 'pa reponn' }) + "`r`n" +
    "Anprent yo verifye sou W2 a menm (dat fen abonman), menm si kab la dekonekte.`r`n"
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
  Write-Host "Fose W2 verifye anprent yo li menm + 1 kontak (kapte toujou limen, LFD etenn)..."
  $r = & $tool $dll fpfix $w2 51211
  Write-Host ("  " + ($r -join ' '))
  if ($r -match 'fixed') { Log ("W2 fpfix: " + ($r -join ' ')) }
  & $tool $dll netcfg $w2 51211 | ForEach-Object { Write-Host ("  " + $_) }
  Pop-Location
  Write-Eta $w2
  exit 0
}

if ($Siveye) {
  Log "Gadyen demare (chak $IntervalMs ms), W2 = $w2"
  $tick = 0
  while ($true) {
    try {
      # Kab la ka chanje pò (dock, adaptatè USB): IP a dwe sou yon kat ki KONEKTE.
      $upAdapters = @(Get-W2Adapters | Where-Object Status -eq 'Up')
      $upIdx = @($upAdapters | ForEach-Object { $_.ifIndex })
      $need = $upIdx.Count -gt 0 -and (
        -not (Get-NetIPAddress -IPAddress $PcIp -AddressFamily IPv4 | Where-Object { $upIdx -contains $_.InterfaceIndex }) -or
        -not (Get-NetRoute -DestinationPrefix "$w2/32" | Where-Object { $upIdx -contains $_.InterfaceIndex }))
      if ($need -or ($tick % 30) -eq 0) {
        if (Set-W2Network $w2) { Log 'Rezo W2 re-aplike.' }
      }
      if (($tick % 15) -eq 0) { Write-Eta $w2 }
    } catch { Log ('Ere: ' + $_.Exception.Message) }
    $tick++
    Start-Sleep -Milliseconds $IntervalMs
  }
}

Write-Host 'Itilizasyon: Gadyen_Ultime.ps1 -Enstale | -Repare | -Siveye | -Dezenstale'

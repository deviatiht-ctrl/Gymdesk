# Gadyen_Ultime.ps1 - kenbe koneksyon kab W2 a (BioEntry) PEMANAN + DETEKSYON ENSTANTANE (< 0.2s)
#  -Enstale    : kopye gadyen an nan C:\ProgramData\SecurGYM, koupe tout ekonomizasyon eneji USB/rezo,
#                aktive DisableDHCPMediaSense=1 ak DadTransmits=0 (0ms le kab reploge), aplike rezo a,
#                firewall, epi kreye tach SYSTEM "SecurGYM_Gadyen" (Startup + Logon + verifikasyon chak 2 min).
#  -Siveye     : bouk ultra-rapid (150ms) an .NET natif: detekte nenpot kab oswa dock extender ki ploge nan
#                nenpot po USB an mwens ke 0.2 segonn, san l pa janm kase yon koneksyon ki deja aktif.
#  -Repare     : jwenn W2 a sou kab la, remete IP li fiks, fose l verifye anprent yo li menm.
#  -Dezenstale : retire tach la (IP yo rete).
param([switch]$Enstale, [switch]$Siveye, [switch]$Dezenstale, [switch]$Repare, [string]$ToolDir = $PSScriptRoot, [int]$IntervalMs = 150)

$ErrorActionPreference = 'SilentlyContinue'
$Home2    = 'C:\ProgramData\SecurGYM'
$LogFile  = Join-Path $Home2 'gadyen_ultime.log'
$EtaFile  = Join-Path $Home2 'gadyen_eta.txt'
$CfgFile  = Join-Path $Home2 'gadyen.json'
$TaskName = 'SecurGYM_Gadyen'
$PcIp     = '192.168.1.50'
$BioStarIp = '192.168.1.16'
$Prefix   = 24
$DockRegex = 'USB|Dock|ASIX|AX88|RTL815|LAN|Dongle|Type-C|Realtek USB|DisplayLink|SMSC|Gigabit USB'
$SkipNicRegex = 'Wi-?Fi|Wireless|WLAN|802\.11|Bluetooth|Virtual|VPN|Loopback|Hyper-V|VMware|TAP|WSL|vEthernet|WAN Miniport'

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

# Koupe tout fom domi USB / ekonomizasyon eneji / Media Sense / DAD 3s sou Windows
function Disable-PowerSaving([object]$adapter) {
  # 1. USB Selective Suspend = Disabled (AC ak Batri sou tout plan eneji)
  foreach ($scheme in @('SCHEME_CURRENT', 'SCHEME_BALANCED', 'SCHEME_MIN', 'SCHEME_MAX')) {
    powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
    powercfg /setdcvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
  }
  powercfg /setactive SCHEME_CURRENT | Out-Null

  # 2. DHCP Media Sense = Disabled (kenbe IP 192.168.1.50 fiks nan memwa menm si kab la souke)
  $tcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
  Set-ItemProperty -Path $tcpKey -Name 'DisableDHCPMediaSense' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

  # 3. Koupe "Allow computer to turn off this device" sou tout USB Root Hubs, Dock Hubs, Host Controllers + USB NIC la
  $powerIds = New-Object 'System.Collections.Generic.List[string]'
  foreach ($usbDev in @(Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue)) {
    if ($usbDev.InstanceId -and ($usbDev.FriendlyName -match 'Hub|Controller|Extensible|Dock|Composite' -or $usbDev.Service -match 'USBHUB|USBXHCI' -or $usbDev.InstanceId -match 'ROOT_HUB')) {
      $powerIds.Add($usbDev.InstanceId)
    }
  }
  $pnp = if ($adapter) { $adapter.PnPDeviceID } else { $null }
  if ($pnp) {
    $powerIds.Add($pnp)
    # Remonte chenn paran USB a (eg. ASIX USB NIC -> Dock Internal Hub -> Root Hub -> Host Controller)
    $curId = $pnp
    for ($depth = 0; $depth -lt 4 -and $curId; $depth++) {
      $parentProp = Get-PnpDeviceProperty -InstanceId $curId -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue
      if ($parentProp -and $parentProp.Data -and $parentProp.Data -match '^(USB|PCI)\\') {
        $powerIds.Add([string]$parentProp.Data)
        $curId = [string]$parentProp.Data
      } else {
        break
      }
    }
  }

  Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSPower_DeviceEnable' -ErrorAction SilentlyContinue | Where-Object {
    if ($_.Enable -ne $true) { return $false }
    if ($_.InstanceName -match 'USB\\ROOT_HUB|ASIX|AX88|RTL815|VID_0B95|VID_0BDA&PID_815|VID_2357|VID_17E9') { return $true }
    foreach ($pidPrefix in $powerIds) {
      if ($_.InstanceName.StartsWith($pidPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
  } | ForEach-Object {
    $_ | Set-CimInstance -Property @{ Enable = $false } -ErrorAction SilentlyContinue
  }

  if ($adapter) {
    # 4. Registry NIC: PnPCapabilities=24 ak tout EEE/GreenEthernet=0 san redemare kat la
    if ($adapter.InterfaceGuid) {
      $guid = $adapter.InterfaceGuid.ToString()
      $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
      Get-ChildItem $classKey -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($props.NetCfgInstanceId -eq $guid) {
          Set-ItemProperty -Path $_.PSPath -Name 'PnPCapabilities' -Value 24 -Type DWord -Force -ErrorAction SilentlyContinue
          foreach ($eee in @('*EEE', 'EEE', 'EEELinkAdvertisement', '*GreenEthernet', 'GreenEthernet', 'EnableGreenEthernet', 'GigaLite', 'PowerSavingMode', 'PowerSave', '*SelectiveSuspend', 'SelectiveSuspend', 'AdvancedEEE', 'ULPMode')) {
            if ($null -ne $props.$eee) {
              Set-ItemProperty -Path $_.PSPath -Name $eee -Value '0' -Force -ErrorAction SilentlyContinue
            }
          }
        }
      }
    }
    Disable-NetAdapterPowerManagement -Name $adapter.Name -NoRestart -ErrorAction SilentlyContinue
    # 5. DadTransmits = 0 pou IP monte an 0ms (pa tann 3 segonn Tentative)
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Disabled -InterfaceMetric 500 -DadTransmits 0 -RouterDiscovery Disabled -ErrorAction SilentlyContinue
    netsh interface ipv4 set interface $adapter.ifIndex dadtransmits=0 | Out-Null
  }
}

# Kat kab (802.3) fizik: USB (ASIX...) oswa PCIe. Sote kat entegre ki gen internet pa DHCP sou lot rezo.
function Get-W2Adapters {
  $candidates = @(Get-NetAdapter | Where-Object {
    $_.Status -ne 'Disabled' -and
    $_.Virtual -ne $true -and
    $_.InterfaceDescription -notmatch $SkipNicRegex
  })
  $up = @($candidates | Where-Object Status -eq 'Up')
  if ($up.Count -eq 1) { return $up }
  if ($up.Count -gt 1) {
    $dock = @($up | Where-Object { $_.InterfaceDescription -match $DockRegex })
    if ($dock.Count -gt 0) { return @($dock[0]) }
    $noGw = @($up | Where-Object {
      $gw = @(Get-NetRoute -InterfaceIndex $_.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
      $gw.Count -eq 0
    })
    if ($noGw.Count -gt 0) { return @($noGw[0]) }
    return @($up[0])
  }
  $dock = @($candidates | Where-Object { $_.InterfaceDescription -match $DockRegex })
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

  # Si kat la genyen 192.168.1.50 deja, PA KASE KONEKSYON AN! Verifye wout ak DadTransmits selman.
  $targetHasIp = (Get-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -ErrorAction SilentlyContinue)
  if ($targetHasIp) {
    $ipif = Get-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipif -and $ipif.DadTransmits -ne 0) {
      Set-NetIPInterface -InterfaceIndex $i -AddressFamily IPv4 -DadTransmits 0 -RouterDiscovery Disabled -ErrorAction SilentlyContinue
      netsh interface ipv4 set interface $i dadtransmits=0 | Out-Null
    }
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

  # Netwaye nenpot ansyen IP (tankou APIPA 169.254.x.x oswa .249)
  Get-NetIPAddress -InterfaceIndex $i -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -ne $PcIp -and $_.IPAddress -ne $BioStarIp } |
    ForEach-Object { Remove-NetIPAddress -InterfaceIndex $i -IPAddress $_.IPAddress -Confirm:$false -ErrorAction SilentlyContinue }

  # Koup eneji + DadTransmits=0 + MediaSense=0 ANVAN mete IP pou IP a monte an 0ms
  Disable-PowerSaving $target

  # Konfigire IP fiks ak netsh
  netsh interface ipv4 set address name="$($target.Name)" static $PcIp 255.255.255.0 none | Out-Null
  netsh interface ipv4 add address name="$($target.Name)" $BioStarIp 255.255.255.0 | Out-Null

  # Fallback New-NetIPAddress si netsh pat pran
  if (-not (Get-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceIndex $i -IPAddress $PcIp -PrefixLength $Prefix -ErrorAction SilentlyContinue | Out-Null
  }

  # Asire pa gen wout default (gateway) ni DNS sou kab W2 a pou entenet la rete sou Wi-Fi
  Get-NetRoute -InterfaceIndex $i -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
  Set-DnsClientServerAddress -InterfaceIndex $i -ResetServerAddresses -ErrorAction SilentlyContinue
  Set-DnsClient -InterfaceIndex $i -RegisterThisConnectionsAddress $false -ErrorAction SilentlyContinue

  # Wout direk pou W2 a
  if (-not (Get-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -ErrorAction SilentlyContinue)) {
    New-NetRoute -InterfaceIndex $i -DestinationPrefix "$w2/32" -NextHop '0.0.0.0' -RouteMetric 1 -ErrorAction SilentlyContinue | Out-Null
  }

  $p = Get-NetConnectionProfile -InterfaceIndex $i -ErrorAction SilentlyContinue
  if ($p -and $p.NetworkCategory -ne 'Private') { Set-NetConnectionProfile -InterfaceIndex $i -NetworkCategory Private -ErrorAction SilentlyContinue }

  Log "Kat '$($target.Name)' ($($target.InterfaceDescription)): $PcIp/$Prefix fiks pemanan (0ms DAD, san sleep USB)."
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
  if ($up) {
    try {
      $ping = New-Object System.Net.NetworkInformation.Ping
      $rep = $ping.Send($w2, 150)
      $ok = ($rep -and $rep.Status -eq 'Success')
      $ping.Dispose()
    } catch {}
  }
  $nom = if ($up) { "$($up.Name) ($($up.InterfaceDescription))" } else { 'Okenn (ploge kab la nan USB)' }
  $txt = "=== ETA GADYEN SECERGYM ===`r`n" +
    "Dat     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n" +
    "Kat     : $nom`r`n" +
    "PC IP   : $PcIp/$Prefix`r`n" +
    "W2 IP   : $w2`r`n" +
    "Konekte : $(if ($ok) { 'WI (W2 sou liy, vites limye)' } else { 'NON (verifye kab la ak kouran)' })`r`n"
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
  if ($src -and ($src -ne $dst)) { Copy-Item $src $dst -Force }
  (@{ ip = $w2; port = 51211 } | ConvertTo-Json) | Set-Content -Path $CfgFile -Encoding UTF8
  Set-Firewall
  Disable-PowerSaving $null
  # Konfigire tout kat wired ki deja prezan (menm sa ki pa gen kab ploge ladan l kounye a)
  Get-NetAdapter | Where-Object {
    $_.Status -ne 'Disabled' -and $_.Virtual -ne $true -and
    $_.InterfaceDescription -notmatch $SkipNicRegex
  } | ForEach-Object { Disable-PowerSaving $_ }
  Set-W2Network $w2 | Out-Null

  # Femen nenpot ansyen enstans -Siveye pou nouvo vesyon an demare pwop
  Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'Gadyen_Ultime\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dst`" -Siveye"
  $trgStart = New-ScheduledTaskTrigger -AtStartup
  $trgLogon = New-ScheduledTaskTrigger -AtLogOn
  $trgWatch = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Days 3650)
  $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  $pr = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger @($trgStart, $trgLogon, $trgWatch) -Settings $set -Principal $pr -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  Write-Eta $w2
  Log "Gadyen enstale: tach $TaskName (SYSTEM, demaraj + logon + watchdog chak 2m), W2 = $w2"
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
  Log "Gadyen vites limye demare (verifikasyon .NET chak ${IntervalMs}ms), W2 = $w2"
  $tick = 0
  while ($true) {
    try {
      $wiredUp = @()
      foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($ni.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
            $ni.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback -and
            $ni.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Wireless80211 -and
            $ni.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Tunnel -and
            $ni.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Ppp -and
            $ni.Description -notmatch $SkipNicRegex) {
          $wiredUp += $ni
        }
      }

      if ($wiredUp.Count -gt 0) {
        # Chwazi kat sib la: Dock/USB an premye, oswa yon kat ki pa gen gateway routeur entenet
        $targetNi = $wiredUp | Where-Object { $_.Description -match $DockRegex } | Select-Object -First 1
        if (-not $targetNi) {
          $targetNi = $wiredUp | Where-Object {
            $props = $_.GetIPProperties()
            $extGw = @($props.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -notlike '192.168.1.*' -and $_.Address.ToString() -ne '0.0.0.0' })
            $extGw.Count -eq 0
          } | Select-Object -First 1
        }
        if ($targetNi) {
          $hasPcIp = $false
          foreach ($u in $targetNi.GetIPProperties().UnicastAddresses) {
            if ($u.Address.ToString() -eq $PcIp) { $hasPcIp = $true; break }
          }
          if (-not $hasPcIp) {
            if (Set-W2Network $w2) { Log "Rezo W2 ($($targetNi.Name)) aplike an vites limye!" }
          }
        }
      }
      if (($tick % 100) -eq 0) { Write-Eta $w2 }
    } catch { Log ('Ere: ' + $_.Exception.Message) }
    $tick++
    Start-Sleep -Milliseconds $IntervalMs
  }
}

Write-Host 'Itilizasyon: Gadyen_Ultime.ps1 -Enstale | -Repare | -Siveye | -Dezenstale'

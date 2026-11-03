# Ekspote_Tout_Manm_BioStar.ps1
# Pran TOUT itilizatè BioStar 2 yo (aktif + ekspire) pa API BioStar 2 a
# epi mete yo nan yon CSV sou Desktop la (ID, non, telefòn, dat kòmansman, dat fen).
# Lanse l sou laptop ki gen BioStar 2 a:
#   powershell -ExecutionPolicy Bypass -File .\Ekspote_Tout_Manm_BioStar.ps1
param(
  [string]$Server = '127.0.0.1',   # adrès sèvè BioStar 2 a (ex: 127.0.0.1 oswa 192.168.1.16)
  [int]$Port = 443,
  [string]$Login = 'admin'
)

$ErrorActionPreference = 'Stop'

# Sètifika BioStar 2 a se "self-signed": aksepte l pou koneksyon lokal sa a sèlman.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
if (-not ('BsTrustAll' -as [type])) {
  Add-Type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class BsTrustAll : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
}
"@
}
[Net.ServicePointManager]::CertificatePolicy = New-Object BsTrustAll

$base = "https://${Server}:$Port/api"
$sec = Read-Host "Modpas BioStar 2 pou '$Login'" -AsSecureString
$pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

Write-Host "Koneksyon ak BioStar 2 ($base)..."
$body = @{ User = @{ login_id = $Login; password = $pw } } | ConvertTo-Json
try {
  $resp = Invoke-WebRequest -Uri "$base/login" -Method Post -Body $body -ContentType 'application/json' -UseBasicParsing
} catch {
  Write-Host "[ERE] Koneksyon an echwe: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Verifye adrès la (-Server), port la (-Port) ak modpas la." -ForegroundColor Yellow
  exit 1
}
$session = $resp.Headers['bs-session-id']
if (-not $session) { Write-Host '[ERE] BioStar pa bay bs-session-id.' -ForegroundColor Red; exit 1 }
$headers = @{ 'bs-session-id' = $session }

function Fmt([object]$d) {
  if (-not $d) { return '' }
  try { return ([datetime]$d).ToString('yyyy-MM-dd HH:mm:ss') } catch { return [string]$d }
}

$all = New-Object System.Collections.ArrayList
$offset = 0
$limit = 500
$total = $null
do {
  $page = Invoke-RestMethod -Uri "$base/users?limit=$limit&offset=$offset" -Headers $headers -Method Get
  $rows = @($page.UserCollection.rows)
  if ($null -eq $total -and $page.UserCollection.total) { $total = [int]$page.UserCollection.total }
  foreach ($u in $rows) { if ($u) { [void]$all.Add($u) } }
  $offset += $rows.Count
  Write-Host ("  {0} / {1} itilizatè..." -f $all.Count, $(if ($total) { $total } else { '?' }))
} while ($rows.Count -gt 0 -and ($null -eq $total -or $all.Count -lt $total))

$today = (Get-Date).Date
$out = foreach ($u in $all) {
  $id = [string]$u.user_id
  $digits = ($([string]$u.phone) -replace '\D', '')
  $tel = if ($digits.Length -ge 8) { $digits.Substring($digits.Length - 8) }
         elseif ($id -match '^\d{8}$') { $id } else { '' }
  $exp = Fmt $u.expiry_datetime
  $expired = $false
  if ($exp) { try { $expired = ([datetime]$exp).Date -lt $today } catch {} }
  [pscustomobject]@{
    user_id         = $id
    name            = [string]$u.name
    telefon         = $tel
    phone           = [string]$u.phone
    email           = [string]$u.email
    user_group      = [string]$u.user_group_id.name
    start_datetime  = Fmt $u.start_datetime
    expiry_datetime = $exp
    eta             = $(if ($u.disabled -eq 'true' -or $u.disabled -eq $true) { 'dezaktive' } elseif ($expired) { 'ekspire' } else { 'aktif' })
  }
}

$file = Join-Path ([Environment]::GetFolderPath('Desktop')) ("BioStar_Tout_Manm_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmm'))
$out | Sort-Object { [int64]($(if ($_.user_id -match '^\d+$') { $_.user_id } else { 0 })) } |
  Export-Csv -Path $file -NoTypeInformation -Encoding UTF8

try { Invoke-RestMethod -Uri "$base/logout" -Headers $headers -Method Post | Out-Null } catch {}

$aktif = @($out | Where-Object eta -eq 'aktif').Count
Write-Host ''
Write-Host ("FINI: {0} itilizatè ({1} aktif, {2} ekspire/dezaktive)" -f $all.Count, $aktif, ($all.Count - $aktif)) -ForegroundColor Green
Write-Host "Fichye: $file" -ForegroundColor Green

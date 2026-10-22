param([Parameter(Mandatory=$true)][string]$Device, [string]$Output = 'artifacts/device-manifest.json')
$ErrorActionPreference = 'Stop'
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
function Read-Property([string]$Name) {
  $value = & $adb -s $Device shell getprop $Name
  if ($LASTEXITCODE -ne 0) { throw "Cannot read $Name" }
  return ($value -join "`n").Trim()
}
# Deliberately excludes device serial, account information and installed apps.
$manifest = [ordered]@{
  capturedAt = [DateTime]::UtcNow.ToString('o')
  manufacturer = Read-Property 'ro.product.manufacturer'
  model = Read-Property 'ro.product.model'
  soc = Read-Property 'ro.soc.model'
  android = Read-Property 'ro.build.version.release'
  api = Read-Property 'ro.build.version.sdk'
  securityPatch = Read-Property 'ro.build.version.security_patch'
  build = Read-Property 'ro.build.display.id'
  abi = Read-Property 'ro.product.cpu.abi'
  llamaRevision = (Get-Content (Join-Path $PSScriptRoot '../native/REVISION')).Trim()
}
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($Output))
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$manifest | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $Output
Write-Output "Device manifest saved to $Output"

param([Parameter(Mandatory)][string]$Apk, [switch]$RequireFastCpu, [string]$ExpectedPackage = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Apk))
try {
  $required = @('lib/arm64-v8a/libondevice_llm.so')
  if ($RequireFastCpu) { $required += 'lib/arm64-v8a/libondevice_llm_cpu_i8mm.so' }
  foreach ($entryName in $required) {
    if ($null -eq $archive.GetEntry($entryName)) {
      throw "Native APK verification failed: missing $entryName in $Apk"
    }
  }
  Write-Output "Native APK packaging verified: $($required -join ', ')"
} finally {
  $archive.Dispose()
}
if ($ExpectedPackage) {
  $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
  $aapt = Get-ChildItem (Join-Path $sdkRoot 'build-tools') -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
  if (-not $aapt) { throw 'Cannot verify APK identity: Android aapt is missing.' }
  $badging = @(& $aapt dump badging $Apk) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='([^']+)'") { throw 'Cannot read APK package identity.' }
  $actualPackage = $Matches[1]
  if ($actualPackage -ne $ExpectedPackage) { throw "Refusing APK: expected $ExpectedPackage, found $actualPackage." }
  Write-Output "APK identity verified: $actualPackage"
}

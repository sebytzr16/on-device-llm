param([string]$Device = 'emulator-5554')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
$properties = Join-Path (Get-Location) 'native/build.properties'
$previous = if (Test-Path -LiteralPath $properties) { [IO.File]::ReadAllBytes($properties) } else { $null }
$package = 'app.ondevicellm.ondevice_llm.smoke'
try {
  & "$PSScriptRoot/build-android.ps1" -Smoke
  if ($LASTEXITCODE -ne 0) { throw 'Release smoke build failed' }
  & $adb -s $Device install -r build/app/outputs/flutter-apk/app-release.apk
  if ($LASTEXITCODE -ne 0) { throw 'Release smoke install failed' }
  & $adb -s $Device logcat -c -b crash
  & $adb -s $Device shell am force-stop $package
  & $adb -s $Device shell am start -n "$package/app.ondevicellm.ondevice_llm.MainActivity"
  if ($LASTEXITCODE -ne 0) { throw 'Release smoke launch failed' }
  Start-Sleep -Seconds 8
  $processId = (& $adb -s $Device shell pidof $package).Trim()
  if (-not $processId) { throw 'Release smoke app exited during startup' }
  $crashes = & $adb -s $Device logcat -d -b crash | Select-String -SimpleMatch $package
  if ($crashes) { throw "Release smoke app crashed: $($crashes | Select-Object -First 3)" }
  Write-Output "RELEASE_STARTUP_OK pid=$processId"
} finally {
  if ($null -ne $previous) { [IO.File]::WriteAllBytes($properties, $previous) }
  else { Remove-Item -LiteralPath $properties -ErrorAction SilentlyContinue }
}
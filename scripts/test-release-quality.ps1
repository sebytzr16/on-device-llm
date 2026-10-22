param(
  [string]$Device = 'emulator-5554',
  [string]$ModelName = 'Qwen3.5-2B-IQ4_NL.gguf',
  [switch]$Recovery,
  [string]$Eval = '',
  [int]$TimeoutSeconds = 1200
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
$properties = Join-Path (Get-Location) 'native/build.properties'
$previous = if (Test-Path -LiteralPath $properties) { [IO.File]::ReadAllBytes($properties) } else { $null }
$package = 'app.ondevicellm.ondevice_llm.smoke'
if ($Recovery -and $Eval) { throw 'Choose Recovery or Eval for each run.' }
if ($Eval -and -not (Test-Path -LiteralPath $Eval)) { throw "Missing evaluation corpus: $Eval" }
if ($ModelName -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'ModelName must be a filename in the provisioned smoke sandbox.' }
& "$PSScriptRoot/build-native-variant.ps1" -CpuOnly
try {
  Set-Content -Encoding ascii -LiteralPath $properties "vulkan=OFF`nopencl=OFF`nkleidiai=OFF`nabis=arm64-v8a`nsmoke=true"
  dart scripts/prepare_release_registrant.dart
  if ($LASTEXITCODE -ne 0) { throw 'Release plugin registration failed' }
  $deviceModel = "/sdcard/Android/data/$package/files/$ModelName"
  $target = if ($Recovery) { 'tool/goal_recovery_smoke.dart' } elseif ($Eval) { 'tool/research_recipe_smoke.dart' } else { 'tool/quality_smoke.dart' }
  $deviceEval = "/sdcard/Android/data/$package/files/research-corpus.json"
  $runId = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
  flutter build apk --release --target-platform android-arm64 --no-pub --target $target "--dart-define=BENCH_MODEL=$deviceModel" "--dart-define=QUALITY_RUN_ID=$runId" "--dart-define=EVAL_FILE=$deviceEval"
  if ($LASTEXITCODE -ne 0) { throw 'Release quality build failed' }
  & "$PSScriptRoot/verify-native-apk.ps1" -Apk build/app/outputs/flutter-apk/app-release.apk -RequireFastCpu -ExpectedPackage $package
  New-Item -ItemType Directory -Force artifacts | Out-Null
  Copy-Item -LiteralPath build/app/outputs/flutter-apk/app-release.apk -Destination artifacts/quality-smoke-release.apk
  & $adb -s $Device install -r artifacts/quality-smoke-release.apk
  if ($LASTEXITCODE -ne 0) { throw 'Release quality install failed' }
  $localModel = Join-Path 'test-assets' $ModelName
  if (-not (Test-Path -LiteralPath $localModel)) { throw "Missing test model: $localModel" }
  & $adb -s $Device shell mkdir -p "/sdcard/Android/data/$package/files"
  & $adb -s $Device push $localModel $deviceModel
  if ($LASTEXITCODE -ne 0) { throw 'Release quality model provisioning failed' }
  if ($Eval) {
    & $adb -s $Device push $Eval $deviceEval
    if ($LASTEXITCODE -ne 0) { throw 'Research corpus provisioning failed' }
  }
  & $adb -s $Device shell am force-stop $package
  & $adb -s $Device logcat -c
  & $adb -s $Device shell am start --activity-clear-top --activity-single-top -n "$package/app.ondevicellm.ondevice_llm.MainActivity"
  if ($LASTEXITCODE -ne 0) { throw 'Release quality launch failed' }
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  $seen = 0
  $interrupted = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Seconds 5
    $lines = @(& $adb -s $Device logcat -d -s flutter:I '*:S')
    $quality = @($lines | Select-String -Pattern 'QUALITY_(TURN|PROGRESS|GOAL|OK|FAILED|RECOVERY_[A-Z_]+)' | ForEach-Object { $_.Line })
    if ($quality.Count -gt $seen) { $quality[$seen..($quality.Count - 1)]; $seen = $quality.Count }
    $lines | Set-Content -Encoding utf8 artifacts/release-quality.log
    if ($quality | Select-String -SimpleMatch 'QUALITY_FAILED') { throw 'Release research/Goal probe failed. See artifacts/release-quality.log.' }
    if ($Recovery -and -not $interrupted -and ($quality | Select-String -SimpleMatch 'QUALITY_RECOVERY_READY')) {
      & $adb -s $Device shell am force-stop $package
      & $adb -s $Device shell am start --activity-clear-top --activity-single-top -n "$package/app.ondevicellm.ondevice_llm.MainActivity"
      if ($LASTEXITCODE -ne 0) { throw 'Goal recovery relaunch failed.' }
      $interrupted = $true
      Write-Output 'QUALITY_PROCESS_RESTARTED'
      # am start returns before Android has necessarily spawned the new PID.
      # Re-enter the timed polling loop instead of checking that PID at once.
      continue
    }
    if ($quality | Select-String -SimpleMatch 'QUALITY_OK') { Write-Output 'RELEASE_QUALITY_OK'; return }
    $processId = & $adb -s $Device shell pidof $package
    if (-not $processId) { throw 'Release process exited before acceptance completed.' }
  }
  throw 'Release quality probe exceeded its deadline.'
} finally {
  if ($null -ne $previous) { [IO.File]::WriteAllBytes($properties, $previous) }
  else { Remove-Item -LiteralPath $properties -ErrorAction SilentlyContinue }
}

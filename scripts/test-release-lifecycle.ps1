param(
  [string]$Device = 'emulator-5554',
  [string]$ModelName = 'Qwen3-1.7B-Q4_0.gguf',
  [int]$Cycles = 10,
  [int]$Context = 4096
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
if ($Cycles -lt 2 -or $Cycles -gt 20) { throw 'Cycles must be 2 through 20.' }
if ($Context -lt 512 -or $Context -gt 1048576) { throw 'Context is outside model setting bounds.' }
if ($ModelName -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'ModelName must be a fixture filename.' }
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
$properties = Join-Path (Get-Location) 'native/build.properties'
$previous = if (Test-Path -LiteralPath $properties) { [IO.File]::ReadAllBytes($properties) } else { $null }
$package = 'app.ondevicellm.ondevice_llm.smoke'
$rows = [Collections.Generic.List[object]]::new()
New-Item -ItemType Directory -Force artifacts | Out-Null
try {
  & "$PSScriptRoot/build-native-variant.ps1" -CpuOnly
  & "$PSScriptRoot/build-native-variant.ps1" -Remove
  Set-Content -Encoding ascii -LiteralPath $properties "vulkan=OFF`nopencl=OFF`nkleidiai=OFF`nabis=arm64-v8a`nsmoke=true"
  dart scripts/prepare_release_registrant.dart
  if ($LASTEXITCODE -ne 0) { throw 'Release plugin registration failed.' }
  $deviceModel = "/sdcard/Android/data/$package/files/$ModelName"
  flutter build apk --release --target-platform android-arm64 --no-pub --target tool/window_lifecycle_smoke.dart "--dart-define=BENCH_MODEL=$deviceModel" "--dart-define=LIFECYCLE_CONTEXT=$Context"
  if ($LASTEXITCODE -ne 0) { throw 'Lifecycle build failed.' }
  & "$PSScriptRoot/verify-native-apk.ps1" -Apk build/app/outputs/flutter-apk/app-release.apk -RequireFastCpu -ExpectedPackage $package
  & $adb -s $Device install -r build/app/outputs/flutter-apk/app-release.apk
  if ($LASTEXITCODE -ne 0) { throw 'Lifecycle install failed.' }
  & $adb -s $Device shell mkdir -p "/sdcard/Android/data/$package/files"
  & $adb -s $Device push "test-assets/$ModelName" $deviceModel
  if ($LASTEXITCODE -ne 0) { throw 'Lifecycle model provisioning failed.' }
  & $adb -s $Device shell am force-stop $package
  & $adb -s $Device logcat -c -b crash
  for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
    & $adb -s $Device logcat -c
    & $adb -s $Device shell am start -n "$package/app.ondevicellm.ondevice_llm.MainActivity" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Lifecycle launch failed.' }
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    $ready = $null
    do {
      Start-Sleep -Seconds 2
      $lines = @(& $adb -s $Device logcat -d -s flutter:I '*:S')
      $lines | Set-Content -Encoding utf8 "artifacts/lifecycle-$cycle.log"
      if ($lines | Select-String -SimpleMatch 'LIFECYCLE_FAILED') { throw "Lifecycle generation failed at cycle $cycle." }
      $line = $lines | Where-Object { $_ -match 'LIFECYCLE_READY (.+)$' } | Select-Object -Last 1
      if ($line -and $line -match 'LIFECYCLE_READY (.+)$') { $ready = $Matches[1] | ConvertFrom-Json }
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    if (-not $ready) { throw "Lifecycle generation timed out at cycle $cycle." }
    & $adb -s $Device shell input keyevent KEYCODE_BACK
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
      Start-Sleep -Seconds 2
      $memory = (@(& $adb -s $Device shell dumpsys meminfo $package) -join "`n")
      $memory | Set-Content -Encoding utf8 "artifacts/lifecycle-$cycle-closed-memory.log"
      $closedRssKb = if ($memory -match 'TOTAL RSS:\s+(\d+)') { [long]$Matches[1] } elseif ($memory -match 'No process found') { 0 } else { throw 'Cannot read closed-process RSS.' }
    } while ($closedRssKb -gt 1536 * 1024 -and [DateTime]::UtcNow -lt $deadline)
    if ($closedRssKb -gt 1536 * 1024) { throw "Window retained model-sized memory at cycle $cycle." }
    $rows.Add([pscustomobject]@{cycle=$cycle;loadedRssBytes=$ready.rssBytes;closedRssBytes=$closedRssKb * 1024;effectiveSettings=$ready.effectiveSettings})
    $rows | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 artifacts/device-window-lifecycle-results.json
    Write-Output "LIFECYCLE_CYCLE_OK $cycle loadedMb=$([math]::Round($ready.rssBytes / 1MB)) closedMb=$([math]::Round($closedRssKb / 1024))"
    $crashes = @(& $adb -s $Device logcat -d -b crash) | Select-String -SimpleMatch $package
    if ($crashes) { throw 'Lifecycle process crashed.' }
  }
  $loadedGrowth = $rows[$rows.Count - 1].loadedRssBytes - $rows[0].loadedRssBytes
  $closedGrowth = $rows[$rows.Count - 1].closedRssBytes - $rows[0].closedRssBytes
  $contexts = @($rows | ForEach-Object { $_.effectiveSettings.contextSize } | Select-Object -Unique)
  if (($contexts.Count -eq 1 -and $loadedGrowth -gt 512MB) -or $closedGrowth -gt 384MB) { throw 'Close/reopen memory growth exceeded the regression bound.' }
  Write-Output "RELEASE_LIFECYCLE_OK cycles=$Cycles loadedGrowthMb=$([math]::Round($loadedGrowth / 1MB)) closedGrowthMb=$([math]::Round($closedGrowth / 1MB))"
} finally {
  if ($null -ne $previous) { [IO.File]::WriteAllBytes($properties, $previous) }
  else { Remove-Item -LiteralPath $properties -ErrorAction SilentlyContinue }
}

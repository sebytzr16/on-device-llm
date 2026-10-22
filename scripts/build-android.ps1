param([switch]$Vulkan, [switch]$OpenCL, [switch]$KleidiAI, [switch]$Debug, [switch]$Smoke)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
& "$PSScriptRoot/bootstrap.ps1" -Vulkan:$Vulkan -OpenCL:$OpenCL
$vulkanFlag = if ($Vulkan) { 'ON' } else { 'OFF' }
$kleidiaiFlag = if ($KleidiAI) { 'ON' } else { 'OFF' }
# Gradle always builds the CPU-only bridge; -OpenCL adds the prebuilt OpenCL variant (GPU-01).
& "$PSScriptRoot/build-native-variant.ps1" -CpuOnly -KleidiAI:$KleidiAI
& "$PSScriptRoot/build-native-variant.ps1" -Remove:(-not $OpenCL) -KleidiAI:$KleidiAI
$smokeLine = if ($Smoke) { "`nsmoke=true" } else { '' }
Set-Content -Encoding ascii native/build.properties "# Native build switches. Edited by scripts/build-android.ps1 and scripts/test-android.ps1.`nvulkan=$vulkanFlag`nopencl=OFF`nkleidiai=$kleidiaiFlag`nabis=arm64-v8a$smokeLine"
$mode = if ($Debug) { '--debug' } else { '--release' }
$identity = & "$PSScriptRoot/write-build-manifest.ps1" -IdentityOnly
if (-not $Debug) { dart scripts/prepare_release_registrant.dart; if ($LASTEXITCODE -ne 0) { throw 'Release plugin registration failed' } }
flutter build apk $mode --target-platform android-arm64 --no-pub "--dart-define=ODLLM_VERSION=$($identity.version)" "--dart-define=ODLLM_SOURCE=$($identity.sourceId)" "--dart-define=ODLLM_NATIVE=$($identity.nativeRevision)"
if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
$apkName = if ($Debug) { 'app-debug.apk' } else { 'app-release.apk' }
$expectedPackage = if ($Smoke) { 'app.ondevicellm.ondevice_llm.smoke' } else { 'app.ondevicellm.ondevice_llm' }
& "$PSScriptRoot/verify-native-apk.ps1" -Apk "build/app/outputs/flutter-apk/$apkName" -RequireFastCpu -ExpectedPackage $expectedPackage
& "$PSScriptRoot/write-build-manifest.ps1" -Apk "build/app/outputs/flutter-apk/$apkName" -SourceId $identity.sourceId
# Report which key signed the APK: the tester's (android/key.properties or the
# ODLLM_ANDROID_* variables) or the debug fallback.
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$apksigner = Get-ChildItem (Join-Path $sdkRoot 'build-tools') -Directory |
  Sort-Object Name -Descending |
  ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
  Where-Object { Test-Path -LiteralPath $_ } |
  Select-Object -First 1
$signer = $null
if ($apksigner) {
  # apksigner warns on stderr; Windows PowerShell would turn that into an error under 'Stop'.
  $ErrorActionPreference = 'Continue'
  $signer = @(& $apksigner verify --print-certs "build/app/outputs/flutter-apk/$apkName" 2>$null) | Where-Object { "$_" -match 'certificate DN:' } | Select-Object -First 1
  $ErrorActionPreference = 'Stop'
}
if (-not $signer) { Write-Output 'APK is in build/app/outputs/flutter-apk (signer not checked: apksigner missing).' }
elseif ($signer -match 'CN=Android Debug') { Write-Output "APK is in build/app/outputs/flutter-apk, signed with the DEBUG key ($($signer.Trim())). Add android/key.properties to sign it with your release key." }
else { Write-Output "APK is in build/app/outputs/flutter-apk, signed by $($signer.Trim())." }

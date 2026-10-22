param(
  [string]$Device = 'emulator-5554',
  [ValidateSet('cpu', 'vulkan', 'opencl', 'auto')][string]$Backend = 'cpu',
  [string]$Test = 'integration_test/native_smoke_test.dart',
  [string]$TestName = '',
  [string]$Model = '',
  [string]$Draft = '',
  [string]$Mmproj = '',
  # Photos and recordings for probes, copied to files/media next to the models.
  [string[]]$Media = @(),
  [string[]]$AuxiliaryModels = @(),
  # The installed app's voice pack (Whisper, VAD, Kokoro), copied to files/voice.
  [switch]$VoicePack,
  # Optional official Pocket export, provisioned only in the smoke sandbox.
  [string]$PocketExport = '',
  [string]$Threads = '4',
  [int]$Batch = 0,
  [int]$MicroBatch = 0,
  [string]$Arch = '',
  [switch]$KleidiAI,
  [switch]$NoPromptCache,
  [string[]]$ExtraDefines = @(),
  [ValidateSet('qwen', 'gemma', 'llama', 'phi', 'mistral', 'other')][string]$Family = 'qwen',
  [string]$Eval = '',
  [ValidateSet('off', 'auto', 'always', 'replay')][string]$EvalMode = 'always'
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
# A sleeping display drops the flutter test connection mid-run ("did not complete").
& $adb -s $Device shell 'svc power stayon usb; input keyevent KEYCODE_WAKEUP' | Out-Null
$abi = (& $adb -s $Device shell getprop ro.product.cpu.abi).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot read device ABI. Check adb devices.' }
$target = switch ($abi) { 'arm64-v8a' { 'android-arm64' } 'x86_64' { 'android-x64' } default { throw "Unsupported test ABI: $abi" } }
# auto = CPU + OpenCL. Vulkan is excluded until the Adreno shader failure is resolved.
$vulkan = if ($Backend -eq 'vulkan') { 'ON' } else { 'OFF' }
$opencl = if ($Backend -eq 'opencl' -or $Backend -eq 'auto') { 'ON' } else { 'OFF' }
& "$PSScriptRoot/bootstrap.ps1" -Vulkan:($vulkan -eq 'ON') -OpenCL:($opencl -eq 'ON')
# The OpenCL backend ships as a separate prebuilt library variant (GPU-01).
# Explicit -Arch benchmarks must load the Gradle library with that architecture.
& "$PSScriptRoot/build-native-variant.ps1" -CpuOnly -Remove:($abi -ne 'arm64-v8a' -or $Arch -ne '') -KleidiAI:$KleidiAI
& "$PSScriptRoot/build-native-variant.ps1" -Remove:($opencl -ne 'ON') -KleidiAI:$KleidiAI
$kleidiaiFlag = if ($KleidiAI) { 'ON' } else { 'OFF' }
$properties = Join-Path (Get-Location) 'native/build.properties'
$previous = if (Test-Path -LiteralPath $properties) { [IO.File]::ReadAllBytes($properties) } else { $null }
try {
  Set-Content -Encoding ascii -LiteralPath $properties "# Native test configuration (restored after this run).`nvulkan=$vulkan`nopencl=OFF`nkleidiai=$kleidiaiFlag`narch=$Arch`nabis=$abi`nsmoke=true"
  flutter build apk --debug --target-platform $target
  if ($LASTEXITCODE -ne 0) { throw 'Test build failed' }
  & "$PSScriptRoot/verify-native-apk.ps1" -Apk build/app/outputs/flutter-apk/app-debug.apk -ExpectedPackage 'app.ondevicellm.ondevice_llm.smoke'
  & $adb -s $Device install -r build/app/outputs/flutter-apk/app-debug.apk
  if ($LASTEXITCODE -ne 0) { throw 'APK installation failed; existing app data was preserved.' }
  New-Item -ItemType Directory -Force test-assets | Out-Null
  if (-not (Test-Path test-assets/smollm2.gguf)) {
    Invoke-WebRequest 'https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/09816acd5d99df7be770d85ea30822623dab342c/SmolLM2-135M-Instruct-Q4_K_M.gguf' -OutFile test-assets/smollm2.gguf
  }
  if ((Get-FileHash test-assets/smollm2.gguf -Algorithm SHA256).Hash.ToLower() -ne '2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d') { throw 'Smoke model checksum mismatch' }
  & $adb -s $Device push test-assets/smollm2.gguf /data/local/tmp/odllm-smoke.gguf
  if ($LASTEXITCODE -ne 0) { throw 'Test model push failed' }
  & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke mkdir -p files
  if ($LASTEXITCODE -ne 0) { throw 'Cannot access debug app sandbox' }
  & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp /data/local/tmp/odllm-smoke.gguf files/smollm2.gguf
  if ($LASTEXITCODE -ne 0) { throw 'Test model provisioning failed' }
  if ($Media.Count -gt 0) {
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke mkdir -p files/media
    foreach ($file in $Media) {
      if (-not (Test-Path -LiteralPath $file)) { throw "Media file not found: $file" }
      $mediaName = [IO.Path]::GetFileName($file)
      & $adb -s $Device push $file "/data/local/tmp/$mediaName"
      & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp "/data/local/tmp/$mediaName" "files/media/$mediaName"
      if ($LASTEXITCODE -ne 0) { throw "Media provisioning failed: $mediaName" }
    }
  }
  if ($VoicePack) {
    $from = '/sdcard/Android/data/app.ondevicellm.ondevice_llm/files/models'
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke test -f files/voice/silero_vad.onnx
    if ($LASTEXITCODE -ne 0) {
      & $adb -s $Device shell "rm -rf /data/local/tmp/voice && mkdir -p /data/local/tmp/voice && cp $from/whisper-base-* $from/silero_vad.onnx /data/local/tmp/voice/ && for k in kokoro-multi-lang-v1_0 kokoro-int8-multi-lang-v1_0; do if [ -f $from/`$k/.ready ]; then cp -r $from/`$k /data/local/tmp/voice/; fi; done && chmod -R a+rX /data/local/tmp/voice"
      if ($LASTEXITCODE -ne 0) { throw 'Voice pack not found in the installed app' }
      & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp -r /data/local/tmp/voice files/
      if ($LASTEXITCODE -ne 0) { throw 'Voice pack provisioning failed' }
      & $adb -s $Device shell rm -rf /data/local/tmp/voice
    }
    & $adb -s $Device shell pm grant app.ondevicellm.ondevice_llm.smoke android.permission.RECORD_AUDIO
  }
  $benchDefine = ''
  foreach ($file in $AuxiliaryModels) {
    $source = (Resolve-Path -LiteralPath $file).Path
    $modelName = [IO.Path]::GetFileName($source)
    if ($modelName -notmatch '^[A-Za-z0-9._-]+$') { throw 'Use a simple auxiliary model file name' }
    $expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    # The redirect runs on the phone: PowerShell 5.1 turns a native
    # command's stderr into a terminating error under Stop.
    $actual = (& $adb -s $Device shell "run-as app.ondevicellm.ondevice_llm.smoke sha256sum files/$modelName 2>/dev/null") -join ''
    if (-not $actual.StartsWith($expected)) {
      & $adb -s $Device push $source "/data/local/tmp/$modelName"
      if ($LASTEXITCODE -ne 0) { throw "Auxiliary model push failed: $modelName" }
      & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp "/data/local/tmp/$modelName" "files/$modelName"
      if ($LASTEXITCODE -ne 0) { throw "Auxiliary model provisioning failed: $modelName" }
      & $adb -s $Device shell rm "/data/local/tmp/$modelName"
      $actual = (& $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke sha256sum "files/$modelName") -join ''
      if (-not $actual.StartsWith($expected)) { throw "On-device model hash mismatch: $modelName" }
    }
  }
  if ($PocketExport) {
    $pocketPath = (Resolve-Path -LiteralPath $PocketExport).Path
    if (-not (Test-Path -LiteralPath (Join-Path $pocketPath 'lm_main.int8.onnx'))) { throw 'Pocket export is incomplete' }
    & $adb -s $Device push $pocketPath /data/local/tmp/odllm-pocket
    if ($LASTEXITCODE -ne 0) { throw 'Pocket export push failed' }
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke mkdir -p files/pocket
    & $adb -s $Device shell 'run-as app.ondevicellm.ondevice_llm.smoke cp -r /data/local/tmp/odllm-pocket/. files/pocket/'
    if ($LASTEXITCODE -ne 0) { throw 'Pocket export provisioning failed' }
    & $adb -s $Device shell rm -r /data/local/tmp/odllm-pocket
    $ExtraDefines += @('POCKET_DIR=/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/pocket', 'POCKET_REFERENCE=/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/pocket/test_wavs/bria.wav')
  }
  if ($Model) {
    if (-not (Test-Path -LiteralPath $Model)) { throw "Benchmark model not found: $Model" }
    $name = [IO.Path]::GetFileName($Model)
    $onDevice = "/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/$name"
    # Invoke test directly: adb strips the nested sh -c quoting, causing
    # the old probe to report existing files as missing and copy them again.
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke test -f "files/$name"
    if ($LASTEXITCODE -ne 0) {
      & $adb -s $Device push $Model "/data/local/tmp/$name"
      if ($LASTEXITCODE -ne 0) { throw 'Benchmark model push failed' }
      & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp "/data/local/tmp/$name" "files/$name"
      if ($LASTEXITCODE -ne 0) { throw 'Benchmark model provisioning failed' }
      & $adb -s $Device shell rm "/data/local/tmp/$name"
    }
    $benchDefine = "--dart-define=BENCH_MODEL=$onDevice"
  }
  # A second GGUF for the speculation pass of the ABI 6 drill (DRAFT_MODEL).
  $draftDefine = ''
  if ($Draft) {
    if (-not (Test-Path -LiteralPath $Draft)) { throw "Draft model not found: $Draft" }
    $draftName = [IO.Path]::GetFileName($Draft)
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke test -f "files/$draftName"
    if ($LASTEXITCODE -ne 0) {
      & $adb -s $Device push $Draft "/data/local/tmp/$draftName"
      if ($LASTEXITCODE -ne 0) { throw 'Draft model push failed' }
      & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp "/data/local/tmp/$draftName" "files/$draftName"
      if ($LASTEXITCODE -ne 0) { throw 'Draft model provisioning failed' }
      & $adb -s $Device shell rm "/data/local/tmp/$draftName"
    }
    $draftDefine = "--dart-define=DRAFT_MODEL=/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/$draftName"
  }
  # Vision projector for the vision cache test (MMPROJ).
  $mmprojDefine = ''
  if ($Mmproj) {
    if (-not (Test-Path -LiteralPath $Mmproj)) { throw "Projector not found: $Mmproj" }
    $mmprojName = [IO.Path]::GetFileName($Mmproj)
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke test -f "files/$mmprojName"
    if ($LASTEXITCODE -ne 0) {
      & $adb -s $Device push $Mmproj "/data/local/tmp/$mmprojName"
      if ($LASTEXITCODE -ne 0) { throw 'Projector push failed' }
      & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp "/data/local/tmp/$mmprojName" "files/$mmprojName"
      if ($LASTEXITCODE -ne 0) { throw 'Projector provisioning failed' }
      & $adb -s $Device shell rm "/data/local/tmp/$mmprojName"
    }
    $mmprojDefine = "--dart-define=MMPROJ=/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/$mmprojName"
  }
  $evalDefine = ''
  if ($Eval) {
    if (-not (Test-Path -LiteralPath $Eval)) { throw "Evaluation set not found: $Eval" }
    $evalName = [IO.Path]::GetFileName($Eval)
    & $adb -s $Device push $Eval "/data/local/tmp/$evalName"
    & $adb -s $Device shell run-as app.ondevicellm.ondevice_llm.smoke cp "/data/local/tmp/$evalName" "files/$evalName"
    if ($LASTEXITCODE -ne 0) { throw 'Evaluation set provisioning failed' }
    $evalDefine = "--dart-define=EVAL_FILE=/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/$evalName"
  }
  $expectFastCpu = ($abi -eq 'arm64-v8a' -and $Arch -eq '').ToString().ToLowerInvariant()
  $identity = & "$PSScriptRoot/write-build-manifest.ps1" -IdentityOnly
  $buildDefines = @("--dart-define=ODLLM_VERSION=$($identity.version)", "--dart-define=ODLLM_SOURCE=$($identity.sourceId)", "--dart-define=ODLLM_NATIVE=$($identity.nativeRevision)")
  $buildDefines += @($ExtraDefines | ForEach-Object { "--dart-define=$_" })
  $cacheEnabled = (-not $NoPromptCache).ToString().ToLowerInvariant()
  $testFilter = if ($TestName) { @('--plain-name', $TestName) } else { @() }
  flutter test $Test --no-uninstall -d $Device @testFilter @buildDefines "--dart-define=EXPECT_FAST_CPU=$expectFastCpu" "--dart-define=SMOKE_PROMPT_CACHE=$cacheEnabled" "--dart-define=SMOKE_BACKEND=$Backend" "--dart-define=SMOKE_MODEL=/data/user/0/app.ondevicellm.ondevice_llm.smoke/files/smollm2.gguf" $benchDefine $draftDefine "--dart-define=BENCH_THREADS=$Threads" "--dart-define=BENCH_BATCH=$Batch" "--dart-define=BENCH_UBATCH=$MicroBatch" "--dart-define=MODEL_FAMILY=$Family" "--dart-define=EVAL_MODE=$EvalMode" $evalDefine $mmprojDefine
  if ($LASTEXITCODE -ne 0) { throw 'Native inference test failed' }
  & "$PSScriptRoot/write-build-manifest.ps1" -Apk 'build/app/outputs/flutter-apk/app-debug.apk' -Models (@($Model, $Draft, $Mmproj) + $AuxiliaryModels + $Media + $(if ($PocketExport) { @(Get-ChildItem -LiteralPath $PocketExport -File | ForEach-Object FullName) } else { @() })) -Output 'artifacts/last-phone-probe-manifest.json' -SourceId $identity.sourceId -Backend $Backend -Threads $Threads
} finally {
  if ($null -ne $previous) { [IO.File]::WriteAllBytes($properties, $previous) }
  else { Remove-Item -LiteralPath $properties }
  # Preserve production plugin registration for the next release build.
  dart scripts/prepare_release_registrant.dart
  if ($LASTEXITCODE -ne 0) { throw 'Release plugin registration failed' }
}

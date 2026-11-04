# Windows PowerShell 5.1 release packaging. All paths are relative to the repo.
[CmdletBinding()]
param(
  [switch]$Cuda,
  [switch]$Vulkan,
  [switch]$All,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($All) { $Cuda = $true; $Vulkan = $true }

function Find-VcRuntime {
  $vcvars = @("${env:ProgramFiles}\Microsoft Visual Studio", "${env:ProgramFiles(x86)}\Microsoft Visual Studio") |
    Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Depth 5 -Filter vcvars64.bat -ErrorAction SilentlyContinue } |
    Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $vcvars) { throw 'VC++ Build Tools not found; cannot bundle the x64 runtime.' }
  $redist = Join-Path $vcvars.Directory.Parent.Parent.Parent.FullName 'VC\Redist\MSVC'
  $crt = Get-ChildItem -LiteralPath $redist -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Get-ChildItem -Path (Join-Path $_.FullName 'x64\Microsoft.VC*.CRT') -Directory } |
    Select-Object -First 1
  if (-not $crt) { throw "No x64 VC++ CRT redistributable found under $redist." }
  $files = @('msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'concrt140.dll') |
    ForEach-Object { Join-Path $crt.FullName $_ } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
  foreach ($required in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $crt.FullName $required))) { throw "VC++ redistributable is missing $required." }
  }
  # The Windows engines use OpenMP threads (native/CMakeLists.txt).
  $omp = Join-Path $crt.Parent.FullName 'Microsoft.VC*.OpenMP\vcomp140.dll' |
    Get-Item -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $omp) { throw "VC++ redistributable is missing vcomp140.dll." }
  return @($files) + $omp.FullName
}

function Find-Iscc {
  # Prefer a normal Inno Setup installation, then search PATH.
  # Per-user installs (winget --scope user) land in LOCALAPPDATA\Programs.
  foreach ($root in @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
    $installations = Get-ChildItem -LiteralPath $root -Directory -Filter 'Inno Setup*' -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending
    foreach ($installation in $installations) {
      $candidate = Join-Path $installation.FullName 'ISCC.exe'
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
  }
  $command = Get-Command ISCC.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }
  return $null
}

Push-Location -LiteralPath $projectRoot
try {
  $manifest = Get-Content -LiteralPath 'pubspec.yaml' -Raw
  $versionMatch = [regex]::Match($manifest, '(?m)^version:\s*[''"]?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+\d+)?)[''"]?\s*(?:#.*)?$')
  if (-not $versionMatch.Success) { throw 'Cannot read a supported version from pubspec.yaml.' }
  $version = $versionMatch.Groups[1].Value
  $numericVersion = ([regex]::Match($version, '^\d+\.\d+\.\d+')).Value
  $variant = 'cpu'
  if ($Cuda) { $variant = 'cuda' }
  if ($Vulkan) { $variant = 'vulkan' }
  if ($Cuda -and $Vulkan) { $variant = 'cuda-vulkan' }
  $baseName = "ondevice-llm-$version-windows-x64-$variant"
  if ($All) { $variant = 'all'; $baseName = "ondevice-llm-$version-windows-x64" }
  $outputDir = 'artifacts/windows'
  $zipPath = "$outputDir/$baseName.zip"
  $installerPath = "$outputDir/$baseName-setup.exe"
  $releaseDir = 'build/windows/x64/runner/Release'
  $iscc = Find-Iscc

  Write-Output "Version: $version ($variant)"
  Write-Output 'Plan: powershell -File scripts/build-windows-native.ps1'
  Write-Output 'Plan: powershell -File scripts/build-windows-native.ps1 -Compat'
  Write-Output 'Plan: powershell -File scripts/build-windows-native.ps1 -Avx512'
  if ($Cuda) { Write-Output 'Plan: powershell -File scripts/build-windows-native.ps1 -Cuda'; Write-Output 'Plan: powershell -File scripts/build-windows-native.ps1 -Cuda12' }
  if ($Vulkan) { Write-Output 'Plan: powershell -File scripts/build-windows-native.ps1 -Vulkan' }
  if (-not $Vulkan) { Write-Output 'Plan: exclude any stale Vulkan bridge' }
  Write-Output 'Plan: flutter build windows --release with ODLLM_VERSION/SOURCE/NATIVE defines'
  Write-Output "Plan: collect $releaseDir in a fresh build/windows-packaging bundle"
  Write-Output 'Plan: bundle the x64 Visual C++ runtime and tester README'
  if (-not $Cuda) { Write-Output 'Plan: exclude any CUDA bridge and runtime DLLs left by earlier builds' }
  Write-Output "Plan: ZIP -> $zipPath"
  if ($iscc) {
    Write-Output 'ISCC: found'
    Write-Output "Plan: installer -> $installerPath"
  } else {
    Write-Output 'ISCC: not found in Program Files, Program Files (x86), LOCALAPPDATA\Programs or PATH; installer will be skipped'
  }
  Write-Output 'Plan: print SHA-256 for each generated output'
  if ($DryRun) { return }
  $vcRuntime = @(Find-VcRuntime)

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-native.ps1
  if ($LASTEXITCODE -ne 0) { throw 'CPU native build failed.' }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-native.ps1 -Compat
  if ($LASTEXITCODE -ne 0) { throw 'Compat native build failed.' }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-native.ps1 -Avx512
  if ($LASTEXITCODE -ne 0) { throw 'AVX512 native build failed.' }
  if ($Cuda) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-native.ps1 -Cuda
    if ($LASTEXITCODE -ne 0) { throw 'CUDA native build failed.' }
    # CUDA 12 for drivers older than CUDA 13 needs and GTX 10-series/Volta.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-native.ps1 -Cuda12
    if ($LASTEXITCODE -ne 0) { throw 'CUDA 12 native build failed.' }
    # Pictures, videos and DiffusionGemma are CUDA builds, shipped with the CUDA component only.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-sd.ps1 -Cuda -CudaArch '75;86;89'
    if ($LASTEXITCODE -ne 0) { throw 'Image bridge build failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-diffusiongemma.ps1 -Cuda -CudaArch '75;86;89'
    if ($LASTEXITCODE -ne 0) { throw 'DiffusionGemma build failed.' }
  }
  if ($Vulkan) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/build-windows-native.ps1 -Vulkan
    if ($LASTEXITCODE -ne 0) { throw 'Vulkan native build failed.' }
  }
  # Same identity defines as the Android build, so About and logs name the
  # real version and source instead of the development defaults (P2-25).
  $identity = & "$PSScriptRoot/write-build-manifest.ps1" -IdentityOnly
  & flutter build windows --release "--dart-define=ODLLM_VERSION=$($identity.version)" "--dart-define=ODLLM_SOURCE=$($identity.sourceId)" "--dart-define=ODLLM_NATIVE=$($identity.nativeRevision)"
  if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows release build failed.' }
  foreach ($required in @('ondevice_llm.exe', 'ondevice_llm.dll', 'ondevice_llm_compat.dll', 'ondevice_llm_avx512.dll', 'flutter_windows.dll', 'data')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDir $required))) {
      throw "Release bundle is missing $required."
    }
  }
  # Every bridge variant must come from the same source: a stale CPU DLL
  # without helper batches made every CPU agent fail (owner, 2026-11-02).
  foreach ($bridge in Get-ChildItem -LiteralPath $releaseDir -Filter 'ondevice_llm*.dll') {
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($bridge.FullName))
    if (-not $text.Contains('od_side_open')) { throw "$($bridge.Name) is stale: it has no helper batches. Rebuild every native variant." }
  }

  # Never reuse a bundle: Release may contain stale CUDA files after a CPU build.
  $stageDir = Join-Path 'build/windows-packaging' ([guid]::NewGuid().ToString('N'))
  $bundleDir = Join-Path $stageDir 'bundle'
  New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
  $cudaPattern = '^(ondevice_llm_cuda(12)?|ondevice_sd|cudart64_\d+|cublas64_\d+|cublasLt64_\d+)\.dll$'
  foreach ($item in Get-ChildItem -LiteralPath $releaseDir -Force) {
    if (-not $Cuda -and -not $item.PSIsContainer -and $item.Name -match $cudaPattern) { continue }
    if (-not $Cuda -and $item.Name -eq 'diffusiongemma') { continue }
    if (-not $Vulkan -and $item.Name -eq 'ondevice_llm_vulkan.dll') { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $bundleDir -Recurse -Force
  }
  foreach ($runtime in $vcRuntime) {
    Copy-Item -LiteralPath $runtime -Destination $bundleDir -Force
  }
  # Release uses data/app.so. A kernel left by an earlier debug build must
  # not travel with the AOT application (or inflate the download).
  $debugKernel = Join-Path $bundleDir 'data/flutter_assets/kernel_blob.bin'
  if (Test-Path -LiteralPath $debugKernel -PathType Leaf) {
    Remove-Item -LiteralPath $debugKernel -Force
  }
  Copy-Item -LiteralPath 'docs/windows-testers.md' -Destination (Join-Path $bundleDir 'README.md')
  foreach ($script in @('install.ps1', 'install.cmd')) {
    Copy-Item -LiteralPath (Join-Path 'windows/installer' $script) -Destination $bundleDir
  }
  if ($Cuda) {
    foreach ($pattern in @('ondevice_llm_cuda.dll', 'cudart64_*.dll', 'cublas64_*.dll', 'cublasLt64_*.dll',
        'ondevice_llm_cuda12.dll', 'cudart64_12.dll', 'cublas64_12.dll', 'cublasLt64_12.dll')) {
      if (-not (Get-ChildItem -LiteralPath $bundleDir -File -Filter $pattern)) {
        throw "CUDA bundle is missing $pattern."
      }
    }
    foreach ($required in @('ondevice_sd.dll', 'diffusiongemma/dg_host.exe')) {
      if (-not (Test-Path -LiteralPath (Join-Path $bundleDir $required))) {
        throw "CUDA bundle is missing $required."
      }
    }
  }

  if ($Vulkan -and -not (Test-Path -LiteralPath (Join-Path $bundleDir 'ondevice_llm_vulkan.dll'))) {
    throw 'Vulkan bundle is missing ondevice_llm_vulkan.dll.'
  }

  & (Join-Path $PSScriptRoot 'write-engine-manifest.ps1') -Dir $bundleDir
  $engineManifest = Get-Content -LiteralPath (Join-Path $bundleDir 'engine-manifest.json') -Raw | ConvertFrom-Json
  $manifestDir = Join-Path $stageDir 'manifests'
  New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
  foreach ($selection in @('cpu', 'cuda', 'vulkan', 'cuda-vulkan')) {
    $selectedFiles = @($engineManifest.files | Where-Object {
      ($_.name -notmatch $cudaPattern -or $selection.Contains('cuda')) -and
      ($_.name -ne 'ondevice_llm_vulkan.dll' -or $selection.Contains('vulkan'))
    })
    $selectedManifest = [ordered]@{ version = 1; files = $selectedFiles } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $manifestDir "$selection.json"), $selectedManifest, (New-Object Text.UTF8Encoding($false)))
  }

  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  # ZipFile includes hidden files and avoids Compress-Archive's 2 GB file limit.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Join-Path $projectRoot $bundleDir), (Join-Path $projectRoot $zipPath),
    [System.IO.Compression.CompressionLevel]::Optimal, $false)
  $outputs = @($zipPath)
  if ($iscc) {
    $includeCuda = 0
    if ($Cuda) { $includeCuda = 1 }
    $includeVulkan = 0
    if ($Vulkan) { $includeVulkan = 1 }
    & $iscc "/DAppVersion=$version" "/DAppNumericVersion=$numericVersion" "/DIncludeCuda=$includeCuda" "/DIncludeVulkan=$includeVulkan" `
      "/DManifestDir=$(Join-Path $projectRoot $manifestDir)" "/DBundleDir=$(Join-Path $projectRoot $bundleDir)" "/DOutputDir=$(Join-Path $projectRoot $outputDir)" `
      "/DOutputBaseName=$baseName-setup" 'windows/installer/ondevice_llm.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
    if (-not (Test-Path -LiteralPath $installerPath)) { throw 'Inno Setup did not produce the expected installer.' }
    $outputs += $installerPath
  }
  Write-Output "Bundle retained for inspection: $bundleDir"
  foreach ($output in $outputs) {
    $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    "$hash  $([IO.Path]::GetFileName($output))" | Set-Content -LiteralPath "$output.sha256" -Encoding ascii
    Write-Output "SHA-256 $output $hash"
  }
} finally {
  Pop-Location
}

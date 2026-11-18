# Builds a signed engine pack for the in-app updater. Only the chat bridge
# DLLs travel: image bridges and CUDA runtime DLLs stay with the installer.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [string]$StageDir = 'native/out/windows-x64',
  [string]$OutDir = 'build/engine-pack'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

function FileSha256([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  $digest = [Security.Cryptography.SHA256]::Create()
  try { [BitConverter]::ToString($digest.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $digest.Dispose() }
}

Push-Location -LiteralPath $projectRoot
try {
  if ($Tag -notmatch '^engine-b\d+(-\d+)?$') {
    throw "Tag must look like engine-b12503 or engine-b12503-2, got '$Tag'."
  }
  $tagVersion = [regex]::Match($Tag, '^engine-(b\d+)(?:-(\d+))?$')
  $revision = if ($tagVersion.Groups[2].Success) { [int]$tagVersion.Groups[2].Value } else { 0 }
  $stage = (Resolve-Path -LiteralPath $StageDir).Path
  $out = Join-Path $projectRoot $OutDir
  New-Item -ItemType Directory -Path $out -Force | Out-Null

  # The engine pin and the bridge API have one definition each, in Dart.
  $versions = Get-Content -LiteralPath 'lib/core/platform/engine_versions.dart' -Raw
  $llamaTag = [regex]::Match($versions, "llamaCppTag\s*=\s*'([^']+)'").Groups[1].Value
  if (-not $llamaTag) { throw 'Cannot read llamaCppTag from lib/core/platform/engine_versions.dart.' }
  $bindings = Get-Content -LiteralPath 'lib/inference/ffi/llama_bindings.dart' -Raw
  $bridgeApiMatch = [regex]::Match($bindings, 'kEngineBridgeApi\s*=\s*(\d+)')
  if (-not $bridgeApiMatch.Success) { throw 'Cannot read kEngineBridgeApi from lib/inference/ffi/llama_bindings.dart.' }
  if ($tagVersion.Groups[1].Value -ne $llamaTag) { throw 'Tag build must match llamaCppTag.' }
  $bridgeApi = [int]$bridgeApiMatch.Groups[1].Value
  $pubspec = Get-Content -LiteralPath 'pubspec.yaml' -Raw
  $versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*[''"]?(\d+\.\d+\.\d+)')
  if (-not $versionMatch.Success) { throw 'Cannot read the app version from pubspec.yaml.' }
  $minApp = $versionMatch.Groups[1].Value

  # ondevice_llm* covers every chat bridge variant and nothing else: no
  # ondevice_sd*, no cudart/cublas runtime.
  $bridges = @(Get-ChildItem -LiteralPath $stage -File -Filter 'ondevice_llm*.dll' | Sort-Object Name)
  if ($bridges.Count -eq 0) { throw "No ondevice_llm*.dll in $stage; build the Windows bridges first." }

  $cudaMajor = $null
  $cudart = Get-ChildItem -LiteralPath $stage -File -Filter 'cudart64_*.dll' |
    ForEach-Object { [regex]::Match($_.Name, '^cudart64_(\d+)\.dll$') } |
    Where-Object { $_.Success } | Select-Object -First 1
  if ($cudart) { $cudaMajor = [int]$cudart.Groups[1].Value }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zipPath = Join-Path $out 'engine-pack-windows-x64.zip'
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($bridge in $bridges) {
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $bridge.FullName, $bridge.Name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally { $zip.Dispose() }

  $files = @($bridges | ForEach-Object {
    [ordered]@{ name = $_.Name; size = $_.Length; sha256 = (FileSha256 $_.FullName) }
  })
  $manifest = [ordered]@{
    version = 1
    engine = $llamaTag
    revision = $revision
    bridgeApi = $bridgeApi
    minApp = $minApp
    files = $files
    zipSha256 = (FileSha256 $zipPath)
  }
  if ($cudaMajor) { $manifest.cudaMajor = $cudaMajor }
  $manifestPath = Join-Path $out 'engine-pack-windows-x64.json'
  [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

  # The signature covers exactly the manifest bytes written above.
  $signaturePath = Join-Path $out 'engine-pack-windows-x64.json.sig'
  & dart run tool/sign_engine_pack.dart $manifestPath $signaturePath
  if ($LASTEXITCODE -ne 0) {
    throw 'Signing failed: set ODLLM_ENGINE_SIGNING_KEY to the file holding the maintainer''s Ed25519 seed.'
  }
  foreach ($output in @($zipPath, $manifestPath, $signaturePath)) {
    Write-Output "$((FileSha256 $output))  $([IO.Path]::GetFileName($output))"
  }
} finally {
  Pop-Location
}

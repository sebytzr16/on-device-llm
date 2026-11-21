# Builds a signed engine pack for the in-app updater. Only the chat bridge
# DLLs travel: image bridges and CUDA runtime DLLs stay with the installer.
# -Engine ik_llama packages the optional ik_llama.cpp bridge instead (tag
# ik-<commit>, CPU/AVX2/AVX-512 variants, no CUDA runtime); it is never part of
# the installer and is installed only when the user asks for that engine.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [ValidateSet('llama.cpp', 'ik_llama')][string]$Engine = 'llama.cpp',
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
  # One tag shape per engine kind, the same ones the app parses.
  if ($Engine -eq 'ik_llama') {
    $tagMatch = [regex]::Match($Tag, '^ik-([0-9a-f]{7,40})(?:-(\d+))?$')
    if (-not $tagMatch.Success) {
      throw "An ik_llama pack tag must look like ik-1a2b3c4 or ik-1a2b3c4-2, got '$Tag'."
    }
    $assetBase = 'ik-engine-pack-windows-x64'
    $engineValue = $tagMatch.Groups[1].Value
  } else {
    $tagMatch = [regex]::Match($Tag, '^engine-(b\d+)(?:-(\d+))?$')
    if (-not $tagMatch.Success) {
      throw "Tag must look like engine-b12503 or engine-b12503-2, got '$Tag'."
    }
    $assetBase = 'engine-pack-windows-x64'
    $engineValue = $tagMatch.Groups[1].Value
  }
  $revision = if ($tagMatch.Groups[2].Success) { [int]$tagMatch.Groups[2].Value } else { 0 }
  $stage = (Resolve-Path -LiteralPath $StageDir).Path
  if ($Engine -eq 'ik_llama') {
    # The default stage dir holds the bundled llama.cpp bridges: signing those
    # as an ik_llama pack would install DLLs whose capabilities are inverted.
    # An ik stage dir must be named explicitly. Each DLL needs its own
    # marker from scripts/build-ik-llama.ps1.
    if (-not $PSBoundParameters.ContainsKey('StageDir')) {
      throw 'An ik_llama pack needs an explicit -StageDir (build/native-windows/ik-llama).'
    }
    $llamaStage = [IO.Path]::GetFullPath((Join-Path $projectRoot 'native/out'))
    $rootWithSep = $llamaStage + [IO.Path]::DirectorySeparatorChar
    if ($stage.Equals($llamaStage, [StringComparison]::OrdinalIgnoreCase) -or
        $stage.StartsWith($rootWithSep, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to package $stage as ik_llama: that is the bundled llama.cpp stage dir."
    }
  }

  # The engine pin and the bridge API have one definition each, in Dart.
  $versions = Get-Content -LiteralPath 'lib/core/platform/engine_versions.dart' -Raw
  $llamaTag = [regex]::Match($versions, "llamaCppTag\s*=\s*'([^']+)'").Groups[1].Value
  if (-not $llamaTag) { throw 'Cannot read llamaCppTag from lib/core/platform/engine_versions.dart.' }
  if ($Engine -eq 'ik_llama') {
    $ikCommit = [regex]::Match($versions, "ikLlamaCommit\s*=\s*'([^']+)'").Groups[1].Value
    if ($ikCommit -cnotmatch '^[0-9a-f]{40}$' -or $ikCommit -match '^0+$') {
      throw 'Pin ikLlamaCommit in lib/core/platform/engine_versions.dart before publishing an ik_llama pack.'
    }
    if (-not $ikCommit.StartsWith($engineValue)) {
      throw 'Tag commit must match ikLlamaCommit.'
    }
    $engineValue = $ikCommit
  } elseif ($engineValue -ne $llamaTag) {
    throw 'Tag build must match llamaCppTag.'
  }
  # ondevice_llm* covers every chat bridge variant and nothing else: no
  # ondevice_sd*, no cudart/cublas runtime.
  $bridges = @(Get-ChildItem -LiteralPath $stage -File -Filter 'ondevice_llm*.dll' | Sort-Object Name)
  if ($bridges.Count -eq 0) { throw "No ondevice_llm*.dll in $stage; build the Windows bridges first." }

  $ikHashes = @{}
  if ($Engine -eq 'ik_llama') {
    foreach ($bridge in $bridges) {
      $markerPath = "$($bridge.FullName).commit.json"
      if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw "Missing ik_llama commit marker for $($bridge.Name). Rebuild this variant."
      }
      $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
      if ($marker.engine -cne 'ik_llama' -or $marker.commit -cne $ikCommit) {
        throw "$($bridge.Name) was staged for commit '$($marker.commit)', expected '$ikCommit'."
      }
      if ($marker.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
          $marker.sha256 -cne (FileSha256 $bridge.FullName)) {
        throw "$($bridge.Name) differs from its ik_llama commit marker. Rebuild this variant."
      }
      $ikHashes[$bridge.Name] = $marker.sha256
    }
  }

  $bindings = Get-Content -LiteralPath 'lib/inference/ffi/llama_bindings.dart' -Raw
  $bridgeApiMatch = [regex]::Match($bindings, 'kEngineBridgeApi\s*=\s*(\d+)')
  if (-not $bridgeApiMatch.Success) { throw 'Cannot read kEngineBridgeApi from lib/inference/ffi/llama_bindings.dart.' }
  $bridgeApi = [int]$bridgeApiMatch.Groups[1].Value
  $pubspec = Get-Content -LiteralPath 'pubspec.yaml' -Raw
  $versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*[''"]?(\d+\.\d+\.\d+)')
  if (-not $versionMatch.Success) { throw 'Cannot read the app version from pubspec.yaml.' }
  $minApp = $versionMatch.Groups[1].Value

  $out = Join-Path $projectRoot $OutDir
  New-Item -ItemType Directory -Path $out -Force | Out-Null
  # ik_llama packs are CPU-only: their bridge has no CUDA kernels, so they
  # never declare a CUDA runtime the loader would have to find.
  $cudaMajor = $null
  if ($Engine -eq 'llama.cpp') {
    $cudart = Get-ChildItem -LiteralPath $stage -File -Filter 'cudart64_*.dll' |
      ForEach-Object { [regex]::Match($_.Name, '^cudart64_(\d+)\.dll$') } |
      Where-Object { $_.Success } | Select-Object -First 1
    if ($cudart) { $cudaMajor = [int]$cudart.Groups[1].Value }
  }

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zipPath = Join-Path $out "$assetBase.zip"
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($bridge in $bridges) {
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $bridge.FullName, $bridge.Name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally { $zip.Dispose() }

  # Read the file metadata from the finished archive, so a concurrent stage
  # rebuild cannot change what the signed manifest says was packaged.
  $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $files = @(
      foreach ($entry in $archive.Entries) {
        $stream = $entry.Open()
        $digest = [Security.Cryptography.SHA256]::Create()
        try {
          $hash = [BitConverter]::ToString($digest.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        } finally {
          $stream.Dispose()
          $digest.Dispose()
        }
        if ($Engine -eq 'ik_llama' -and $hash -cne $ikHashes[$entry.Name]) {
          throw "$($entry.Name) changed while packaging. Rebuild the pack from a stable stage."
        }
        [ordered]@{ name = $entry.Name; size = $entry.Length; sha256 = $hash }
      }
    )
  } finally { $archive.Dispose() }
  $manifest = [ordered]@{
    version = 1
    kind = $Engine
    engine = $engineValue
    revision = $revision
    bridgeApi = $bridgeApi
    minApp = $minApp
    files = $files
    zipSha256 = (FileSha256 $zipPath)
  }
  if ($cudaMajor) { $manifest.cudaMajor = $cudaMajor }
  $manifestPath = Join-Path $out "$assetBase.json"
  [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

  # The signature covers exactly the manifest bytes written above.
  $signaturePath = Join-Path $out "$assetBase.json.sig"
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

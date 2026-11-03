[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Dir)
$ErrorActionPreference = 'Stop'
$folder = (Resolve-Path -LiteralPath $Dir).Path
function FileSha256([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  $digest = [Security.Cryptography.SHA256]::Create()
  try { [BitConverter]::ToString($digest.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $digest.Dispose() }
}
$files = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.dll' | Sort-Object Name | ForEach-Object {
  [ordered]@{ name = $_.Name; size = $_.Length; sha256 = (FileSha256 $_.FullName) }
})
$manifest = [ordered]@{ version = 1; files = $files }
$json = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $folder 'engine-manifest.json'), $json + "`n", (New-Object Text.UTF8Encoding($false)))

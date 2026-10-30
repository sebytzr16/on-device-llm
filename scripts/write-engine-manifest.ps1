[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Dir)
$ErrorActionPreference = 'Stop'
$folder = (Resolve-Path -LiteralPath $Dir).Path
$files = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.dll' | Sort-Object Name | ForEach-Object {
  [ordered]@{ name = $_.Name; size = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$manifest = [ordered]@{ version = 1; files = $files }
$json = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $folder 'engine-manifest.json'), $json + "`n", (New-Object Text.UTF8Encoding($false)))

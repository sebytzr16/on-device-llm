$ErrorActionPreference = 'Stop'
$REPO_ROOT = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $REPO_ROOT
# The commit the image, video and upscale models were tested with (2026-10-27).
$ref = '687915518efd69548965d24818f0d3bbbb903718'
$dest = Join-Path $REPO_ROOT 'native/stable-diffusion.cpp'
# git reports progress on stderr, which Stop would turn into a failure in PS 5.1.
$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $dest)) {
  git clone --filter=blob:none https://github.com/leejet/stable-diffusion.cpp $dest 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'stable-diffusion.cpp download failed' }
  git -C $dest checkout --detach $ref 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "checkout of $ref failed" }
}
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'apply-sd-patches.ps1')
Write-Output 'stable-diffusion.cpp ready. Run scripts/build-windows-sd.ps1 next.'

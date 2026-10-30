# Applies native/patches/stable-diffusion/*.patch to native/stable-diffusion.cpp once each.
# ltx-mask-f16.patch: LTX's padding mask became -Inf in F16 and CUDA flash
# attention returned NaN (a white video); see docs/ltx-gemma-cuda-nan-2026-10-28.md.
$root = Split-Path -Parent $PSScriptRoot
$sd = Join-Path $root 'native/stable-diffusion.cpp'
# The applied check reports on stderr, which Windows PowerShell 5.1 turns into a
# terminating error under 'Stop'; exit codes are checked instead.
$ErrorActionPreference = 'Continue'
foreach ($patch in Get-ChildItem -LiteralPath (Join-Path $root 'native/patches/stable-diffusion') -Filter '*.patch') {
  git -C $sd apply --reverse --check $patch.FullName 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { continue }
  git -C $sd apply $patch.FullName 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "$($patch.Name) does not apply to stable-diffusion.cpp" }
  Write-Output "Applied $($patch.Name)"
}

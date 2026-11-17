# Fails when a native binary contains AVX-512 (zmm register) code. Release
# builds must run on AVX2-only CPUs (GitHub issue #4: a host-tuned
# ondevice_sd.dll crashed Ryzen 6800H laptops with 0xC000001D). Only
# ondevice_llm_avx512.dll is allowed to carry AVX-512; the loader picks it
# only when Windows reports AVX-512F.
# Needs dumpbin (Visual Studio Build Tools); without it the check is skipped
# with a warning so a machine without the tools can still package.
param([Parameter(Mandatory)][string[]]$Path)
$ErrorActionPreference = 'Stop'
# powershell -File passes "a,b" as one string.
$Path = @($Path | ForEach-Object { $_ -split "," } | Where-Object { $_ })

$dumpbin = (Get-Command dumpbin.exe -ErrorAction SilentlyContinue).Source
if (-not $dumpbin) {
  $vsRoots = @("${env:ProgramFiles}\Microsoft Visual Studio", "${env:ProgramFiles(x86)}\Microsoft Visual Studio")
  $dumpbin = $vsRoots | Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Depth 9 -Filter dumpbin.exe -ErrorAction SilentlyContinue } |
    Where-Object { $_.FullName -match '\\Hostx64\\x64\\' } |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $dumpbin) {
  Write-Warning 'dumpbin.exe not found: AVX-512 check skipped.'
  return
}

$bad = @()
foreach ($file in $Path) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "No such file: $file" }
  # Disassemble only executable code; count instructions naming zmm registers.
  # First zmm line only; -List does not stop at one match on piped text.
  $hit = & $dumpbin /nologo /disasm:nobytes $file | Select-String -Pattern '\bzmm\d+\b' | Select-Object -First 1
  if ($hit) {
    $line = "$($hit.Line)".Trim(); if ($line.Length -gt 100) { $line = $line.Substring(0, 100) }; $bad += "$file ($line)"
  } else {
    Write-Output "No AVX-512 code: $(Split-Path -Leaf $file)"
  }
}
if ($bad.Count) { throw "AVX-512 instructions found (would crash AVX2-only CPUs):`n$($bad -join "`n")" }

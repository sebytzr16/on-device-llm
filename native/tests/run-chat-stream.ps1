# Reuse an existing Windows Ninja build's compiler settings and static libs.
param([string]$BuildDirectory = 'build/native-windows/x64-cuda')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $repo
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
$ninja = Get-Content -LiteralPath (Join-Path $build 'build.ninja')
function Build-Value([string]$name) {
    $line = $ninja | Where-Object { $_.StartsWith("  $name = ") } | Select-Object -First 1
    if (-not $line) { throw "No $name in the native Ninja build." }
    return $line.Substring("  $name = ".Length)
}
$out = Join-Path $repo 'build/bridge-chat-check'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$vsRoots = @("${env:ProgramFiles}\Microsoft Visual Studio", "${env:ProgramFiles(x86)}\Microsoft Visual Studio")
$vcvars = $vsRoots | Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Depth 5 -Filter vcvars64.bat -ErrorAction SilentlyContinue } |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $vcvars) { throw 'Visual Studio Build Tools are required.' }
$response = "$(Build-Value 'DEFINES') $(Build-Value 'FLAGS') $(Build-Value 'INCLUDES') " +
    "`"$repo/native/tests/chat_stream.cpp`" /Fe:`"$out/chat-stream-test.exe`" /Fo:`"$out/chat-stream-test.obj`" " +
    "/link $(Build-Value 'LINK_LIBRARIES')"
[IO.File]::WriteAllText("$out/chat-stream-test.rsp", $response)
$command = "@echo off`r`ncall `"$($vcvars.FullName)`" >nul`r`ncd /d `"$build`"`r`ncl @`"$out/chat-stream-test.rsp`"`r`n"
[IO.File]::WriteAllText("$out/build-chat-stream-test.cmd", $command)
& "$out/build-chat-stream-test.cmd"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$env:PATH = "$repo/native/out/windows-x64;" + $env:PATH
& "$out/chat-stream-test.exe"
exit $LASTEXITCODE

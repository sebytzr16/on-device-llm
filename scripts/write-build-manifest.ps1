param([string]$Apk = '', [string[]]$Models = @(), [string]$Output = 'artifacts/build-manifest.json', [switch]$IdentityOnly, [string]$SourceId = '', [string]$Backend = 'cpu', [int]$Threads = 0)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$head = (git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine source HEAD' }
$versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $repo 'pubspec.yaml')), '(?m)^version:\s*(\S+)')
$inputs = @('lib', 'scripts', 'test', 'integration_test', 'android', 'ios', 'native', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml')
$changed = @(git -C $repo -c core.safecrlf=false diff --name-only HEAD -- @inputs)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked source changes' }
$changed += @(git -C $repo ls-files --others --exclude-standard -- @inputs)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect new source files' }
$entries = @($changed | Sort-Object -Unique | ForEach-Object {
    $relative = $_
    $path = Join-Path $repo $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) { "$relative`:$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())" }
    else { "$relative`:deleted" }
})
# Windows PowerShell 5.1 has no [Convert]::ToHexString.
function Hex([byte[]]$bytes) { [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant() }
$sha = [Security.Cryptography.SHA256]::Create()
try { $signature = Hex($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($entries -join "`n")))) }
finally { $sha.Dispose() }
$identity = [ordered]@{
    sourceId = if ($SourceId) { $SourceId } else { $head.Substring(0,12) + '-' + $signature.Substring(0,12) }
    head = $head
    worktreeSha256 = $signature
    version = $versionMatch.Groups[1].Value
    nativeRevision = [IO.File]::ReadAllText((Join-Path $repo 'native/REVISION')).Trim()
    nativeAbi = 7
}
if ($IdentityOnly) { [pscustomobject]$identity; return }
$manifest = [ordered]@{schemaVersion=1; capturedAt=[DateTime]::UtcNow.ToString('o'); build=$identity; changedFiles=$entries; models=@()}
$toolchain = (flutter --version --machine) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Cannot record Flutter/Dart toolchain identity' }
$versions = $toolchain | ConvertFrom-Json
$manifest.toolchain = @{flutter=$versions.frameworkVersion; flutterRevision=$versions.frameworkRevision; dart=$versions.dartSdkVersion}
$manifest.target = @{platform='android'; abi='arm64-v8a'; backend=$Backend; threads=$Threads}
if ($Apk) {
    $apkPath = (Resolve-Path -LiteralPath $Apk).Path
    $manifest.apk = @{path=$apkPath; sha256=(Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($apkPath)
    try {
        $manifest.nativeLibraries = @($zip.Entries | Where-Object { $_.FullName -match '^lib/.*/libondevice_llm.*\.so$' } | ForEach-Object {
            $stream = $_.Open(); $digest = [Security.Cryptography.SHA256]::Create()
            try { @{entry=$_.FullName;sha256=Hex($digest.ComputeHash($stream))} }
            finally { $stream.Dispose(); $digest.Dispose() }
        })
    } finally { $zip.Dispose() }
}
$manifest.models = @($Models | Where-Object { $_ } | ForEach-Object {
    $file = Get-Item -LiteralPath $_
    @{name=$file.Name;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
# .NET resolves relative paths against the process directory, not the
# PowerShell location the caller set.
$target = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { [IO.Path]::GetFullPath((Join-Path $repo $Output)) }
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $target -Encoding utf8
Write-Output "Build manifest saved to $target"

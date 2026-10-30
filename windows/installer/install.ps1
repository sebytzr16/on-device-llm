# Installs or updates OnDevice LLM from an unpacked release ZIP for the
# current user (no administrator rights). Chats, settings and models live in
# %APPDATA%\com.ondevicellm and are never touched; only program files change.
# Run install.cmd, or: powershell -ExecutionPolicy Bypass -File install.ps1
param([string]$Target = (Join-Path $env:LOCALAPPDATA 'Programs\OnDevice LLM'))
$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $source 'ondevice_llm.exe'))) {
  throw "ondevice_llm.exe is not next to this script; unpack the whole ZIP first."
}
$running = Get-Process ondevice_llm -ErrorAction SilentlyContinue
if ($running) {
  Write-Output 'Closing OnDevice LLM so its files can be replaced...'
  $running | ForEach-Object { [void]$_.CloseMainWindow() }
  Start-Sleep -Seconds 3
  Get-Process ondevice_llm -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 1
}
New-Item -ItemType Directory -Path $Target -Force | Out-Null
# Copy over the old version; files the old version had are kept (no deletion).
robocopy $source $Target /E /NFL /NDL /NJH /NJS /NP /XF install.ps1 install.cmd | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copy failed (robocopy exit $LASTEXITCODE)." }
$exe = Join-Path $Target 'ondevice_llm.exe'
$shell = New-Object -ComObject WScript.Shell
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'OnDevice LLM.lnk'
$link = $shell.CreateShortcut($menu)
$link.TargetPath = $exe
$link.WorkingDirectory = $Target
$link.Save()
Write-Output "Installed to $Target (Start menu: OnDevice LLM)."

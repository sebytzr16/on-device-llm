# Says the speech-recognition probe's phrases from this computer's speakers,
# so integration_test/asr_probe_test.dart (and the voice probes that print
# the same line) can run without someone reading them aloud. Start it before
# the probe; it waits for each ASR: {"say": ...} line, speaks the phrase
# with a Windows voice and stops after -Count phrases.
# Under `flutter test` (scripts/test-android.ps1) the probe's lines reach
# only the computer, never logcat: pass -Log, the file that run's output
# goes to. Without it the phone's log is read (an app run with print).
param(
  [Parameter(Mandatory = $true)][string]$Device,
  [string]$Log = '',
  [int]$Count = 12,
  [string]$Voice = '',
  [int]$Rate = 0,
  # The probe says which phrase 1.5 s before its microphone opens; the
  # line takes about that long to reach this script and the voice to start.
  [int]$DelayMs = 0
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
if ($Voice) { $speaker.SelectVoice($Voice) }
$speaker.Rate = $Rate
# Warm the voice and the audio device up: the first phrase came late.
$speaker.Volume = 0
$speaker.Speak('ready')
$speaker.Volume = 100
$logcat = $null
$reader = $null
if ($Log) {
  # Read on from the file's end as the run writes it.
  while (-not (Test-Path $Log)) { Start-Sleep -Milliseconds 200 }
  $stream = [System.IO.File]::Open((Resolve-Path $Log), 'Open', 'Read', 'ReadWrite')
  $stream.Seek(0, 'End') | Out-Null
  $reader = New-Object System.IO.StreamReader($stream)
} else {
  $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
  $adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
  & $adb -s $Device logcat -c
  $info = New-Object System.Diagnostics.ProcessStartInfo
  $info.FileName = $adb
  $info.Arguments = "-s $Device logcat -v raw -s flutter:I"
  $info.RedirectStandardOutput = $true
  $info.UseShellExecute = $false
  $logcat = [System.Diagnostics.Process]::Start($info)
  $reader = $logcat.StandardOutput
}
$said = 0
try {
  while ($said -lt $Count -and -not ($logcat -and $logcat.HasExited)) {
    $line = $reader.ReadLine()
    if ($null -eq $line) {
      if ($Log) { Start-Sleep -Milliseconds 50; continue }
      break
    }
    $at = $line.IndexOf('ASR: {')
    if ($at -lt 0) { continue }
    $row = $line.Substring($at + 5) | ConvertFrom-Json
    if ($null -eq $row.say) { continue }
    Start-Sleep -Milliseconds $DelayMs
    # Written at once, so the log survives the script being stopped.
    [Console]::WriteLine("say $($row.say) [$($row.source)]: $($row.phrase)")
    [Console]::Out.Flush()
    $speaker.Speak($row.phrase)
    $said++
  }
} finally {
  if ($logcat -and -not $logcat.HasExited) { $logcat.Kill() }
  $reader.Dispose()
  $speaker.Dispose()
}
"said=$said"

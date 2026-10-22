# Two-turn research chat on the phone: a long web question, then a follow-up in
# the same chat. Prints the number of fatal signals in the crash buffer.
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb logcat -c -b crash
& $adb shell am force-stop app.ondevicellm.ondevice_llm
& $adb shell am start -n app.ondevicellm.ondevice_llm/.MainActivity | Out-Null
Start-Sleep 6
& $adb shell input tap 880 173          # new chat
Start-Sleep 2
& $adb shell input tap 465 2195         # composer
Start-Sleep 1
& $adb shell input text "What%sis%sthe%slatest%snews%sabout%sthe%sToronto%sBlue%sJays%sthis%sweek"
Start-Sleep 1
& $adb shell input tap 983 1270         # send (keyboard open)
Start-Sleep 130
& $adb shell input keyevent 4           # close keyboard if open
Start-Sleep 1
$first = (& $adb shell "logcat -d -b crash | grep -c 'Fatal signal'")
& $adb shell input tap 465 2195
Start-Sleep 1
& $adb shell input text "And%swhat%sabout%stheir%snext%sthree%sgames%sand%swho%sis%spitching"
Start-Sleep 1
& $adb shell input tap 983 1270
Start-Sleep 130
$second = (& $adb shell "logcat -d -b crash | grep -c 'Fatal signal'")
"fatals after turn 1: $first ; after turn 2: $second"

# UI/UX review — 2026-11-18

Merged from two review passes (9 Claude reviewers), plus a Codex (GPT-6) pass on 1.6.0.
✅ = re-checked in the code by hand. "Both" = found independently by both passes. Paths are
under `lib/` unless noted.

## Status on branch `ios-build-and-ui-fixes`

**Fixed:** Fix-first items 1-12 (except 6's Stop button during housekeeping, now hidden too);
on-device dictation flag; dictation leaking into another chat; one-tap deletes for voice
packs, embedding model, offline Wikipedia, knowledge collection and documents (swipe), goal
reports; delete races when the page closes mid-way; stale voice error banner.

**Still open, from Codex:** iOS has no `ondevice_llm/audio.decode16k` handler, so voice-memo
import into Knowledge fails (`knowledge/knowledge_media.dart:67`); resuming paused system
read-aloud takes the Kokoro path (`voice/voice_service.dart:684`); onboarding save-failure
Retry is a no-op (`onboarding_screen.dart:74`); searching an agent setting opens Tools, where
Agents only shows when the helper is on; the Cupertino transition ignores the app's Motion
setting. Everything under "iOS-specific gaps", "iPad", "Worth fixing next", "Desktop" and
"Small items" below is still open unless listed as fixed above.

## Fix first

| # | Issue | Where | Found by |
|---|---|---|---|
| 1 | ✅ **No swipe-back on iOS.** The custom spring page transition replaces Cupertino's and has no edge-swipe. | `core/theme/app_theme.dart:120-127`, `core/motion/spring_routes.dart:26-53` | Both |
| 2 | ✅ **iOS status bar unreadable** when app theme ≠ system theme: only `statusBarIconBrightness` (Android) is set, never `statusBarBrightness` (iOS). | `core/theme/app_theme.dart:52-59` | This |
| 3 | ✅ **Keyboard can't be dismissed in chat on iOS.** Multiline composer, no `keyboardDismissBehavior` / `onTapOutside` anywhere. | `features/chat/presentation/widgets/composer.dart:423`, `screens/chat_screen.dart:924` | This |
| 4 | **Conversation mode stuck on "Listening…"** after a recognizer error / permission denial / silence; orb tap does nothing. | `features/voice/conversation_screen.dart:958-998`, `voice_service.dart:163-186` | Both |
| 5 | **Chat screen crash** (`liveMessages.last` on empty list) when only superseded messages remain. | `features/chat/presentation/screens/chat_screen.dart:943, 999-1003` | Other |
| 6 | **Delete / undo / branch switch fire "answer finished"** — toast, haptics, Read aloud repeats last answer. | `features/chat/presentation/providers/chat_branches.dart:13,36,172` | Other |
| 7 | **Dictation keeps running after Send** and writes the sent text back into the composer; mic disabled meanwhile. | `features/chat/presentation/widgets/composer.dart:449-470` | Both |
| 8 | ✅ **One-tap permanent deletes:** "✓ Ready" voice-pack button (~290 MB), embedding-model chip, knowledge collection trash, offline Wikipedia (GBs), goal report, scheduled prompt, shortcut, preset. | `features/voice/voice_settings.dart:238`, `settings/.../knowledge_page.dart:143,618`, `zim/zim_tile.dart:79`, `goals/presentation/goal_history.dart:211`, `schedule_page.dart:174`, `shortcuts_page.dart:65`, `preset_sheet.dart:109` | Both |
| 9 | ✅ **"Reset to defaults" wipes remote connections + API keys,** language and theme; dialog doesn't say so. | `features/settings/.../settings_provider.dart:184` | Other |
| 10 | ✅ **Settings search opens the wrong editor** (Agents / max tokens → Custom instructions). | `settings_search_page.dart:164` | Other |
| 11 | ✅ **Onboarding license acknowledgement carries over** when switching to a model with a different license. | `features/onboarding/presentation/screens/onboarding_screen.dart:127` | Both |
| 12 | **Uncommitted onboarding change can overflow:** pinned license notice + checkbox push Download/Later off-screen in landscape iPhone or large Dynamic Type. Keep only the checkbox pinned, or make the actions area scroll. | `features/onboarding/presentation/widgets/onboarding_steps.dart:234-264` | Both |

## iOS-specific gaps (feature offered, nothing behind it)

- ✅ **Dictation always forced on-device** — `onDeviceOnly` ignored, `onDevice: true` hardcoded; languages without on-device support always fail. `features/voice/voice_service.dart:222, 314`
- ✅ **Natural voice (290 MB) offered on iOS but can never run** (no voice audio channel; `offlineVoiceReady` false). `voice_settings.dart:17-63`, `conversation_screen.dart:465, 1283`
- **Phone-action cards** (alarm, timer, event, reminder, message) offered on iOS; no channel in `AppDelegate.swift`, always fail. `chat_provider.dart:3264`, `chat_workspace.dart:92`
- **Scheduled prompts and Goal "Watch"** offered but no-op outside Android. `schedule/scheduled_prompt.dart:113-139`
- **Downloads die when the app backgrounds;** `keepScreenOn` is Android-only, no resume on foreground. `model_manager_provider.dart:1032`, `device_info.dart:188`
- **Read-aloud likely silent with the ring/silent switch on** — no iOS audio session category set (needs phone test). `voice_service.dart:473`
- **No French/Spanish on iOS:** no `CFBundleLocalizations`, `knownRegions` only en. `ios/Runner/Info.plist`, `project.pbxproj:248`
- **Launch screen always dark** (uncommitted storyboard change), even for light-theme users. `ios/Runner/Base.lproj/LaunchScreen.storyboard:22`
- "This phone" wording shown on iPad. `onboarding_steps.dart:156`

## iPad

- ✅ **Share sheet fails** without `sharePositionOrigin` in 5 places: `config_card_flow.dart:43`, `chat_screen_actions.dart:230`, `benchmark_dialog.dart:230`, `phone_actions.dart:640`, `knowledge_page.dart:551` (only `backup_page.dart:63` does it right). Both passes.
- No tablet layout / max content width; sheets span the full 1024-1366 px width and ignore the notch in landscape. `core/platform/form_factor.dart:25`, `spring_routes.dart:438`

## Worth fixing next

- Thinking/reasoning card never folds while streaming and never shows "Thought for X s"; vanishes in one frame at the end, scroll jumps. `chat_bubble.dart:662`, `reasoning_accordion.dart:47` (Both)
- Quick-action chips overwrite the typed draft. `chat_screen.dart:1112` (Both)
- Switching chats keeps the old scroll offset. `chat_screen.dart:634`
- Trashing the open chat leaves it open and writable. `conversations_sheet.dart:346`
- Long error banner can push the composer off-screen. `chat_screen_widgets.dart:120`
- Notice toast and jump-to-latest button overlap. `chat_screen.dart:1054` (Both)
- "Use model" doesn't turn off the remote; a failed local load also turns off the remote; changing hosted model mid-reply stops the server.
- Remote URL field: "Invalid URL" and Test use the saved URL, not the typed one.
- Paused/failed download can't be cancelled; "Remove from list" leaves a multi-GB partial file. `download_center.dart:14`, `hidden_library_models.dart:38`
- ZIM import: progress lost on leaving, a second import can corrupt the first, file copied twice on iOS.
- Hugging Face search: no loading state on result tap, double-open, stale spinner. `hf_search_page.dart:66`
- Memory "Scan saved chats" has no busy state, can run twice. `memory_page.dart:69`
- Benchmark dialog: back closes it while the run continues; no Cancel. `benchmark_dialog.dart:31`
- Goals Refine dialog buttons don't update when the objective is cleared. `goals_page.dart:436`
- Dollar amounts with operators render as TeX ("$100/month or $1,000/year"). `core/design/markdown_math.dart:25`
- Theme/accent change snaps (AppColors.lerp returns `this`); status bar stale after OS appearance change. `app_design.dart:199`, `app.dart:73` (Both)
- Combined text scale unclamped (OS × app up to 1.4); fixed 32-36 pt chips, code-block header, island pill, Mermaid header clip. `app.dart:98`, `composer.dart:355,536`, `code_block.dart:73`
- Sheets float ~34 pt above the keyboard (`viewPadding` vs `padding`). `core/design/app_sheet.dart:111,141`
- Mermaid diagrams capture chat scrolling; long labels overflow diamonds; VoiceOver reads raw source. `core/design/mermaid/`
- Every markdown table column fixed 140-280 px. `core/design/markdown_tables.dart:24`
- Source inspector `substring(0,10)` / hard `as String` casts can throw. `chat_bubble.dart:1439`
- Message source page refetches and flashes a spinner on rebuild. `message_source_page.dart:21`
- Streamed paragraphs keep stale colours after a mid-stream theme change. `streaming_markdown.dart:72`
- Library error card can't be dismissed. `models_screen.dart:458`

## Desktop (Windows)

- Conversation and "More settings" pages cover the custom title bar (can't drag/close window). `desktop/chat_pane.dart:978`, `inspector_panel.dart:219`
- Load-settings Save can double-pop and blank the window. `desktop/load_settings_dialog.dart:756`
- Ctrl+V swallowed while generating. `desktop/chat_pane.dart:766`
- Delete confirms then silently does nothing while generating. `desktop/sidebar.dart:395`
- Title bar / sidebar rows overflow at large text scale. `desktop/title_bar.dart:34`, `sidebar.dart:497`
- Export of a temporary chat asks for a format, then does nothing. `desktop/chat_tools.dart:23`

## Small items

- ~20 hardcoded English strings (voice errors, download "of", benchmark summary, "Auto (…)", "compare"/"model", "[Image omitted]", share body text, error messages); answer time always 24-hour.
- Text controllers disposed while dialogs are still closing: `memory_banner.dart:112`, `chat_screen_actions.dart:788`, `models_screen.dart:136`; never disposed: `overrides_page.dart:294`.
- `textFaint` (#636C7A) below WCAG AA on dark surfaces. `core/design/app_design.dart:51`
- Small/unlabeled tap targets: accent swatches, remove-attachment button.
- /compact dialog says "summarized" before saving; discarded summary gives no message.

## Checked and fine

All iOS permission strings present (mic, camera, speech, photos, local network, Bonjour); en/es/fr key parity; Reduce Motion honoured; controllers/tickers disposed in core/motion and most features; desktop-only plugins never reached on iOS; send double-tap guarded; composer SafeArea and keyboard resize work.

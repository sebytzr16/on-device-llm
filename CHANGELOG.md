# Changelog

## 1.8.0 - 2026-11-21

### Engine
- Groundwork for ik_llama.cpp as a second engine on Windows (signed packs, chosen per model); the pack itself ships in a later update
- Engine packs are checked again at every load: only files named in the signed manifest are used, a pack can never replace a newer signed build, bridge libraries load only from trusted folders, and a pack that fails twice is rolled back and set aside
- Load and Stop: Stop works at once while a model is still loading, the next Load waits for the old model to close, and a load that leaves an engine behind says so
- Engine updates: "Use the built-in engine" and "Remove" stay that way, an install interrupted by quitting or a failed check is only retried when you press Check now, Remove stays available after a rollback, and update errors are translated
- Pressing Stop twice during a load no longer leaves the stopped model in memory

### Android
- LiteRT-LM engine (issue #10): .litertlm models with streaming, Stop and photo input; settings show only what the engine supports, and helpers and hosting leave those models alone

### PC and phone
- Local server page: "Share documents with paired devices", off by default; the older pairing token never gets documents, and turning it off stops document use at the next search
- Downloads: speed and time left in the pop-up, preparing rows can be cancelled, no "NaN%" for an unknown size, and cancelling one image model no longer deletes a paused download's shared part
- Backup: a large archive is no longer read into memory on the phone (it goes through the share sheet), a dismissed share leaves no copy behind, and a restore checks the staged file first
- Changing the models folder no longer loses models when a later settings write fails
- Files of an unknown type are saved with a .bin name instead of failing
- Reading aloud resumes at the sentence where it stopped, also after switching voices; a broken ZIM file no longer closes the archive that is open; locked chat photos appear once you unlock
- Stopping the Local server releases its network name and answers waiting requests instead of leaving them hanging
- Memory estimate uses the last model scan instead of waiting for a reload

### Chat
- Drafts survive a crash: the newest saved draft comes back, and one unreadable attachment no longer empties the composer
- Undo after deleting turns refuses when the chat has changed, and a failed Edit puts the turns back and says why
- DOCX export tables open correctly in Word; a failed answer no longer breaks the next turn
- Goals: a chat set to "Stay local" refuses a goal, also on Continue, instead of running it without sources
- Memory notes reach continued and compared answers; web sources are kept on the first LiteRT turn; Send stays greyed out during a quick edit of the chat; the busy message names a model that is still loading

### Speed
- Optimize: one time limit for the whole run, a failed sample no longer stops it, your own settings come back afterwards, only measured settings are saved, and it never loads past the real memory budget
- Engines report benchmark and Optimize support separately, so a model can be speed-tested even when it cannot be auto-tuned
- Optimize puts back exactly the model that was loaded before the run, and its row no longer shows an outdated reason

### Security
- MCP: turning a server on uses the settings you reviewed, and saving the page keeps the servers that are already running
- Hosted workspaces: uploads belong to the device that sent them and expire, documents need the host's permission, and custom request headers are hidden by default
- Engine pack signatures, file hashes and revisions are re-checked on every load, and a rejected pack is never used

## 1.7.0 - 2026-11-18

### Engine
- llama.cpp b12503
- Engine updates on Windows: the app checks for signed engine packs once a day and installs them by itself (Ed25519-signed manifest, per-file SHA-256, a test load in a separate process). A pack is used from the next model load; if it fails twice, the app goes back to the built-in engine. Settings > Engine updates has an on/off switch, Check now, Use the built-in engine and Remove
- Regenerate on large models no longer re-reads the whole prompt: the prompt store spills to disk when RAM is short
- Issue #6: the first token may take up to 10 minutes while a long prompt is read (long chats with many tools stopped after 60 s on Android CPUs)
- Hardware > Check for engine updates reads the newest llama.cpp build correctly

### Android
- Issue #8 / PR #7: x86_64 build (one APK per ABI); the fast bridge is used only when every core supports AVX, AVX2, FMA, F16C and BMI2
- Dictation stops by itself after 2.5 s of quiet (6 s when nothing is said), keeps the last words, and the stop button closes the microphone at once

### PC and phone
- PR #9: iOS build path, UI/UX fixes and the last model loads at start
- Compare gives the chat model back when you leave it
- Ctrl+K and other shortcuts work right after renaming a chat
- Version arrows count by time; benchmark receipts use local time; Enter in "Edit question" sends again (Shift+Enter for a new line)
- Model settings for the loaded model no longer claim a wrong GPU layer count
- Chat titles use the language you wrote in; word sums count as local work
- Clearer MCP server errors (EN/FR/ES); "How this was made" shows "Generation speed"

## 1.6.0 - 2026-11-17

### First run
- Guided first run on PC and phone: one-time tips (with "Show tips again"), Get a model / Load the best fit from an empty chat, a best-fit badge in Discover, a Load + Optimize offer after a download, and a short tour of the chat tools
- Optimize is also in Settings and on Android

### Models
- Recommended can never end up empty: removed suggestions come back with "Show N removed models"
- Recommended leaves out models too large for this device (search and Discover still find them); the phone's "Remove from list" button is now a short "Hide"
- Tiny files read "< 1 MB" instead of "0 MB"
- Every model file (image/video, drafts, embeddings, projectors, speech, partial downloads) is shown as a model card on the phone and in the same row style as chat models on the PC, with readable names
- A file that another installed model also uses (the shared upscaler) no longer shows a model as "partially downloaded", and Delete no longer looks like it does nothing
- "Remove unused parts" says how much it freed, or that nothing was unused
- Auto context is the recommended default; it fits the context into memory and can be turned off for a hand-set length
- Model settings: Temperature and the other answer settings sit right under "Answers", above the speed test; the chat side panel offers the same context lengths (a 64K model no longer reads 32K)

### Memory estimate
- While a change is measured, the last plan stays on screen, dimmed, with "Recalculating…" (no more flicker to a wrong spill warning)
- Mixture-of-experts models show where the weights go: expert weights held in RAM, the part read from disk, and the context cache, with a split RAM bar
- Warns about a RAM shortage and weights paging from disk; the planner shrinks the context to 1024 like a real load

### Create
- Tidier model panel: one model card with its size, state and actions

### Engine and fixes
- Regenerate and questions right after loading a big model stop the warm-up within about a second, and the next question reuses the instructions it already read (memory notes now travel with the question on local models)
- Issue #4: the image engine picks the CUDA/AVX2/SSE4.2 build at run time, so it runs on CPUs without AVX-512
- Issue #5: Android credits memory-mapped weights, shrinks the context before refusing a load, and offers Load anyway
- Android GPU (OpenCL) memory is counted as RAM
- Sending or regenerating right after loading a big model no longer fails with "Load a model": the warm-up pass now gets time to stop instead of the model being dropped
- Audit fixes: safe project-file writes with Undo, image generation cancel, encrypted history/media/knowledge, upload quotas, a profile load race, translated remote results

## 1.5.0 - 2026-11-13

### Voice
- Listening: Parakeet Ultra (Moondream, from Parakeet TDT 0.6B v3); existing v3 files keep working until Ultra is downloaded
- Reading voice: Supertonic 3 (31 languages); a downloaded Supertonic 2 keeps working; laugh/breath/sigh tags never read aloud by other voices
- Live captions: optional Nemotron 3.5 streaming pack shows words while you speak (own worker isolate)
- Conversation: a model that can hear (Gemma 4 E2B/E4B audio projector) gets the recording with the transcript, for that answer only (setting to turn off)

### Engine
- FP8 (E4M3) KV cache on CUDA/CPU with q8_0 fallback and reason; MoE expert cache size/CPU share settings (off by default)
- Bonsai ternary models load on the CPU when the engine is Vulkan
- llama.cpp updated to b12342, retaining Bonsai ternary and host projector weights.

### Models
- Catalog lists Gemma 4 31B (dense, needs a ~24 GB card; fit badge says so on smaller PCs)
- Models "All" lists image/video models and every other model file; every row can be deleted (asks first; shared image files kept)
- Create's model list has a delete button on downloaded models
- Create recommends one picture and one video model for this graphics card (largest weights that stay on the card with 2 GB spare)

### Create
- Create starts on the fastest picture model, a downloaded one first

### Chat
- Chat pictures: answer images show at 240 px; tapping a sent picture opens a full-screen zoomable viewer with Save (decrypted copy via the save dialog), Close and Details
- Chat picture Save: file name gets an extension from the MIME type; the viewer closes and confirms where it saved

### Speed
- Optimize tries a matching draft on disk (same family, a third the size or less) with and without; a setup the engine refuses is skipped
- Optimize: on MoE models whose experts miss the card, also measures the fewest experts in RAM that fit (+2, +4); a draft model the user picked is measured with and without

### Chat (more)
- Chat can edit pictures: edit_image redraws the chat's latest picture with the selected picture model
- Source check also reads sentences the word check placed and flags ones their passage does not state

### Fixes
- Startup no longer stops at "Encrypted data could not be opened" when only the write-ahead log is unreadable (left by a killed process): if the database itself opens and passes its check, the log is moved to a dated `recovered-wal-…` folder beside it and the app starts; nothing is deleted
- Windows package no longer ships an unused plain `sqlite3.dll`

## 1.4.0 (2026-11-08)

### Agents

- Four-agent requests now always end with one complete answer: helpers run
  in parallel, the main model waits for all of them, then writes a final
  answer from their findings. An empty reply is retried once, and if it is
  still empty the app shows the findings it has.
- Helpers know today's date, recover when a model only returns tool calls,
  and fallback helpers start beside the other calls in the same round.
- Helper roles are neutral, a failed search is no longer reported as "web
  blocked", and identical DuckDuckGo requests are shared.
- Show live agent writing on the phone and keep agent details updated while open.
- Recognize requests for plain or specialized agents and start the requested
  batch even when the coordinator only promises to call them.
- Add an agent time limit in Settings > Tools > Agents, defaulting to Unlimited,
  with 90-second and 5-, 15-, 30- and 60-minute options. Stop remains available.
- Same-as-chat helpers run on the remote model when the chat is remote, and
  remote research turns can use helpers even with Tools off.

### Longer answers

- Answer tokens go up to 64,000 with a slider, or any value up to 1,048,576
  with Custom. The setting reaches settings, models, the inspector, presets
  and agents, and engines use the real limit.

### Desktop

- Create and Compare keep a history you can reopen.
- Models in "Available to download" can be removed from the list, and
  Restore brings them back. Benchmark receipts and download history rows can
  be deleted.
- Compare reloads changed settings, frees the first model before loading the
  second, and waits while a chat is busy.
- The server request log scrolls, and the image engine is released when idle.

### Security and server

- Phone pairing uses a one-time QR secret, a rotating code, and pinned
  self-signed TLS on the local network. Lockouts clear when the code expires.
- Server limits per IPv6 /64, bounded request bodies, capped tracked clients
  and workspace route caps.
- Model files another runtime is using cannot be deleted or moved.
- Repeated server activity snapshots are compacted, so long four-agent runs
  keep their reconnect history.

### Other

- 243 more strings are translated (English, French, Spanish), including the
  privacy and licence notices.
- Gemma native tool calls are parsed, and empty workspace answers are retried.

- Show live agent writing on the phone and keep agent details updated while open.
- Recognize requests for plain or specialized agents and start the requested
  batch even when the coordinator only promises to call them.
- Add an agent time limit in Settings > Tools > Agents, defaulting to Unlimited,
  with 90-second and 5-, 15-, 30- and 60-minute options. Stop remains available.
- Compact repeated server activity snapshots so long four-agent runs do not
  exhaust the reconnect history. Preserve approvals, results and completion
  events for both current and older clients.

## 1.3.0 (2026-11-03)

### Remote server workspace (Android and Windows)

- Connecting to an updated OnDevice LLM server moves chat model rounds,
  agents, web searches, server tools, calculator and attachment processing
  to the host. The phone can use this mode without a local model installed.
- Live server activity, agent replies, timings, sources and tool approvals
  appear on the phone. The answer retains the server tool trace.
- Phone actions are prepared on the server and remain cards you confirm
  on the phone; nothing is launched or scheduled without your tap.
- Selected files upload as raw bytes for host-side document extraction,
  OCR, passage selection and photo analysis, respecting the connection's
  document and vision sharing controls.
- Server jobs keep working across connection loss. Rejoining replays ordered
  events without repeating the work; Stop explicitly cancels the server job.
  Jobs remain available while hosting stays running; restarting the server
  ends them. Uploads and event retention have explicit resource limits.
- Vision remains lazy: text-only loads do not load the projector. The first
  photo prepares it, and later photo requests reuse the loaded projector.
- Existing OpenAI-compatible and hosted providers retain their inference API
  behavior; full remote execution requires an updated OnDevice LLM host.

### Fixes

- Generate the Windows engine manifest in minimal PowerShell environments
  using .NET SHA-256 without requiring the Get-FileHash module.
- Fix remote helper-agent turns failing with `Tool messages require tool_call_id`
  when a model emits a tool call without an ID. Missing IDs are assigned before
  calls are sent to clients or executed; existing IDs are preserved.

## 1.2.0 (2026-11-02)

Adds local agents: the chat model can work as a team.

### Local agents (new, Android and Windows)
- The chat model can split a task and hand parts of it to up to 4 agents
  that run side by side, then write one answer from all of their replies.
  The answer records how many times it asked the agents.
- Agents share one copy of the agent model; on Windows their jobs are
  batched together on the GPU.
- Pick the agent model ("Same as chat model" or a second model), how many
  run at once, thinking, tool rounds, instructions, input budget, context
  size and sampling in Settings > Tools > Agents.
- Agents can use the chat tools, including web search. Web access is asked
  once per chat, always allowed, or never allowed.
- Live agent cards on Windows and a small agent strip above the composer on
  the phone, with each task, its streamed reply, tokens/s and timings.
- The chosen agent model is always the one that runs.

### Engine
- Models and agents fill the GPU's VRAM first and only then spill into
  system RAM, on any GPU.
- The Logs page shows every model load (with the real GPU layer count),
  agent job, tool call, search and download.

### Chat and voice
- `/` command palette; `/compact` summarises older turns after you approve
  the summary.
- Model pages with the Hugging Face card, GGUF capabilities, files, load
  settings and the model's own sampling settings; a downloads center with
  history.
- Vision is a per-model switch, loaded with the first photo.
- Optional Supertonic 2 reading voice (English, French and Spanish).
- Dictation keeps listening across short pauses.
- Warm-grey light theme and redesigned desktop settings.
- Fixes for read-aloud on Windows, tool-call parsing for Qwen models and
  many smaller issues found in a full audit.

## 1.1.0 (2026-10-29)

Adds the Windows desktop app.

### Windows desktop (new)
- The same app on Windows 10 and 11 (64-bit), with a desktop layout,
  keyboard shortcuts, a tray icon and live logs. Installer and ZIP, no
  administrator rights needed.
- Engines for NVIDIA CUDA 13 and CUDA 12, Vulkan, AVX-512, AVX2 and older
  CPUs; the app picks the best one that works on your PC.
- Optimize for this PC: tries several setups and keeps the fastest one that
  gives the same answers. A memory estimate before loading shows what fits
  in VRAM and RAM.
- Large mixture-of-experts models (for example Qwen3.6 35B A3B) with experts
  in system RAM, multi-token prediction (MTP) and draft models.
- Hugging Face Discover, model Compare, and Create for images, short video
  and upscaling.
- Local server with OpenAI- and Anthropic-compatible endpoints, token
  protected, and phone pairing over your network.

### Engine
- llama.cpp updated to b11972.
- The whole model, output layer included, now fits on the GPU when it can,
  and sampling runs on the GPU, also with MTP.
- Faster first token on the desktop.

### Android
- Picking a remote connection turns Remote on with it.
- Many fixes from the desktop work that also apply to the phone (prompt
  reuse, tool progress, document fitting).

## 1.0.0 (2026-10-21)

First public release. Android only.

### Chat
- Local GGUF inference on a pinned llama.cpp through a small versioned C
  bridge, on the CPU with optional OpenCL. Answers stream with stop,
  continue, regenerate, edit and answer versions.
- Gemma 4 and Qwen models in a catalog pinned by revision and SHA-256, plus
  GGUF import and Hugging Face browsing.
- Each model's recommended sampling (model card, Hugging Face or GGUF
  metadata) is used by default. Settings layer from phone to model, preset,
  project, chat and turn, with an Effective settings page.
- Chats in SQLite with search, projects, archive and trash, Markdown/JSON
  export and temporary chats.
- Optional memory of facts you state, which you can edit and delete.

### Photos and documents
- Photo questions through Gemma 4 or a Qwen3.5 vision projector; photo turns
  stay in the prompt cache, so follow-up questions do not re-encode the image.
- On-device text recognition (OCR) for photos.
- Text from PDF, Word, Excel, PowerPoint, OpenDocument, EPUB, RTF, HTML,
  CSV and plain text; long files are cut to the passages matching the
  question.
- Knowledge collections searched by keyword and meaning (EmbeddingGemma 2),
  with cited passages.

### Web research
- DuckDuckGo search with page reading, Wikipedia for stable facts, a news
  desk from public RSS feeds and an optional offline Wikipedia (ZIM).
- Cited answers: each source opens to the exact passage. Every sentence is
  checked against the pages and unsupported statements are flagged. Dates
  are checked, and a follow-up re-reads earlier pages or searches again.
- Off by default.

### Voice
- Dictation and read-aloud.
- Conversation screen: Whisper or Parakeet speech recognition, a local or
  remote model and Kokoro speech, hands-free.

### Goals and actions
- Goals: clarifying questions, a step plan, research with sources and a
  report.
- Phone actions (timers, alarms, reminders, calendar events, message drafts,
  saved files) prepared as cards that need a tap.

### Connections
- Remote connections to your own server (LM Studio, Ollama, llama-server…)
  or hosted APIs (OpenAI-compatible, Anthropic, Gemini). The remote model
  decides when to search and keeps its server's own settings. Keys are kept
  in the Android keystore, and you can set per-model request limits.
- Device server: the phone serves its model to your network through an
  OpenAI-compatible endpoint.

### Interface
- English, French and Spanish.
- One motion system with spring animations, a status island with Undo
  toasts, haptics, dark and light themes and a Full/Subtle/Off motion
  setting.

### Known limits
See [Known limits](README.md#known-limits) in the README: no iOS release,
no background downloads, no encrypted backup, LoRA untested on hardware and
Gemini untested live.

## 0.1.1 (2026-10-11)

Internal test build installed on the development phone (release 8).

## 0.1.0 (2026-09-14)

Start of the project: pinned llama.cpp, Jinja chat templates and the
Android build.

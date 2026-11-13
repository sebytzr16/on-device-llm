# Changelog

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

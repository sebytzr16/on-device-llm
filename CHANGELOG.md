# Changelog

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

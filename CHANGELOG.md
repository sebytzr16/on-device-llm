# Changelog

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

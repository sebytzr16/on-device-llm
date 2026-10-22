# Contributing to OnDevice LLM

Thank you for helping make private, on-device intelligence real.

## Ground rules
- One logical change per PR.
- Bug fixes must include a failing test first.
- `flutter analyze` must be clean.
- Add tests for any new behavior.
- UI changes: include a screenshot or short recording.
- Performance changes: include before/after numbers.

## What we want
- Bug fixes with tests.
- New model catalog entries **with a verified sha256** and license.
- Additional chat templates (as data in `chat_template.dart`).
- Performance improvements with numbers.
- Documentation, especially build-path fixes.
- Accessibility improvements.

## What we decline
- Anything requiring a vendor API round-trip.
- Anything requiring a user account.
- Anything that phones home for analytics.
- Anything that hides or fakes model reasoning.
- Dependencies that duplicate an existing one without a strong argument.

## Dart-only PRs (no native toolchain needed)
Look for the `good-first-issue` label. Parser, scraper, DB, and UI work can
all be done and tested without building llama.cpp.

## Adding a model
1. Add an entry to `lib/features/models/domain/entities/model_catalog.dart`.
2. Compute the real sha256 of the GGUF and put it in `sha256`.
3. Confirm the model license permits redistribution and note it in the PR.

## Code style
- Feature-first folders. No `utils.dart` dumping grounds.
- Domain entities are immutable and Flutter-free.
- Notifiers own state; widgets consume it.
- Comments explain WHY, not WHAT.

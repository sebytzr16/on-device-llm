# Release review — 2026-11-03

Reviewed the October 31 handoff, November 1 owner plan (including November 2
follow-ups), November 2 agent web/settings and helper performance reports,
release checklist, and current changelog/source history.

## Scope

The October 30 fix plan explicitly records completion. The November feature
rounds and agent web/settings work are present in the current 1.2.0+5 source.
Earlier handoffs describe historical gaps and should not be treated as a fresh
implementation backlog without checking their later completion records.

This candidate adds the remote tool-call ID repair: the native parser can
report empty IDs, which previously passed through TextEngine.toolCallsOf into
server responses. A subsequent tool result then failed server validation.
Assign missing IDs at that boundary while preserving supplied IDs. Regression
tests exercise regular and streaming responses, multiple calls, and submission
of matching tool results on the following request.

Saved remote connection credentials already persist in secure storage on both
host and client. Routine VPN disconnection does not require token rotation.

## Outstanding work

- Full server-side workspace execution is missing: client tools and helper
  orchestration are still local in remote mode. See
  [implementation proposal](proposals/remote-workspace-execution.md) for the
  owner's requirement, code findings, protocol slices and acceptance checks.
- Owner checks: remote agents over Meshnet after updating the candidate,
  reconnecting with the saved connection after restarting the phone app,
  full README walkthrough, long dictation and voice listening in EN/FR/ES.
- Performance validation: near-full-VRAM agent sessions, long conversations,
  and controlled LM Studio comparisons. Earlier clean native benchmarks do
  not establish performance for every resident app state.
- Distribution: build/package platform candidates, check artifact hashes and
  installed native engine manifests, validate update/data preservation, and
  complete signing and GitHub release work. Android physical checks require
  access to the phone; none are claimed here.
- Optional separate feature: pinned TLS pairing, described in
  proposals/pairing-tls.md. The plan leaves implementation to an owner decision.
  Publisher-page research behavior is an existing policy decision, not a new
  missing feature.

## Validation

The focused server/protocol/remote/tool-loop suites passed 111 tests. Full
`flutter test --no-pub --timeout 60s`: **2019 passed, 13 skipped**. Full
`flutter analyze --no-pub`: **no issues**. The tests needed localhost access
outside the sandbox; sandboxed attempts failed at test-runner startup.
The Windows manifest script now computes SHA-256 through .NET, removing its
dependency on the Get-FileHash PowerShell module in minimal build environments.
Windows release candidate built successfully using the offline Flutter wrapper
and workspace-local TEMP/TMP (72.5 s on the final build). Output:
`build/windows/x64/runner/Release/ondevice_llm.exe`. The manifest script also
passed a known `abc` SHA-256 fixture under Windows PowerShell. No installer,
Android build or signed public release is claimed. The installed server is not
replaced or stopped by this review.

Git metadata is read-only for this workspace and no remote is configured in
the checkout. The owner confirmed sebytzr16/on-device-llm. The changed existing
files were checked against upstream main before preparing a review branch.

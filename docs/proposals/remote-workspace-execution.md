# Remote workspace execution

Owner requirement, 2026-11-03: a phone connected to the laptop server must use
the server for model inference, agents, web research, tools, document/data and
photo analysis. The phone displays activity and results live. This feature is
not implemented by the current inference API or the missing tool-ID fix.

## Current gap

`chat_provider.dart` creates ToolRunner on the client, even in remote mode.
Its helper callback calls helperRunnerProvider. HelperRunner resolves @chat
against the client's local loaded model; its localChat callback only gates
shared GPU placement. It does not route helpers to RemoteEngine. RemoteEngine
implements model inference, while DeviceModelServer exposes model endpoints
rather than the full chat/tool workflow. Therefore a remotely generated helper
request can still attempt local execution on the phone.

## Implementation slices

1. Add an authenticated server capability endpoint and versioned job protocol,
   separate from OpenAI-compatible model endpoints. Advertise supported tools,
   agents, media and analysis explicitly. Older/external servers retain their
   existing inference mode; full server execution must never silently fall
   back to phone inference or phone tools.
2. Extract the orchestration from the chat provider into a service usable by
   both local chat and server jobs. Run server ToolRunner, HelperRunner, model
   pool and cancellation under one job owner, with bounded resource admission.
   Preserve web/tool approvals and tool settings; the phone returns decisions
   to the job. Do not expose a general unrestricted command execution endpoint.
3. Upload selected photos/documents/data once using authenticated, bounded
   uploads. Pass server-owned file handles into the job, with explicit lifetime
   and cleanup. Do not send unrelated phone memory or library contents.
   Use the existing server vision model/projector and document retrieval path.
   Inventory actual data-analysis tools before advertising that capability.
4. Stream typed events with job ID, monotonic sequence, task/agent IDs and
   parent relationships: queued, started, tool started/completed, agent text,
   thinking where enabled, progress, approval requested, artifacts, final,
   failure and cancellation. Publish measured metrics only. Reuse the phone's
   existing HelperJobs/live panels rather than displaying agent prose as proof
   that an agent ran. Keep main text and per-agent output in distinct streams.
5. Persist resumable job state and bounded event history on the server. Rejoin
   by job ID and last event sequence after Meshnet interruption. Use request
   idempotency keys so reconnecting cannot duplicate agents or side effects.
   Define disconnect continuation and cancellation explicitly; distinguish
   reconnecting, queued, running, failed and finished on the phone.

## Required acceptance checks

- Phone without downloaded local models launches several agents; server logs
  and metrics demonstrate execution, while phone cards show live progress.
- Search/read requests originate on the server; approvals on the phone block
  execution until answered. Disabled web/tools remain disabled server-side.
- Uploaded photo/document analysis succeeds without local inference, preserves
  provenance, and refuses invalid/oversized uploads without partial execution.
- Stop cancels main inference, agents and tools; repeated stop is safe.
- Disconnect/rejoin restores running cards and final output without replaying
  tool side effects; server restart reports interrupted work truthfully.
- Wrong tokens, unknown jobs, unsupported tools and unavailable server models
  produce actionable errors. Concurrent jobs obey the host's resource limits.
- Loopback integration tests cover events, uploads, approvals, cancellation,
  replay/idempotency and remote settings; real Meshnet phone/server checks
  verify placement and presentation before publishing the feature.

This is the primary remaining feature before claiming complete remote
workstation behavior. The current patch candidate only fixes tool-call IDs.

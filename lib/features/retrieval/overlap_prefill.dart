import '../../inference/engine/llama_engine.dart';

/// Retrieval owns its result even when speculative prefill fails. Settle
/// priming before prompt fitting uses the chat engine (owner, 2026-11-01).
Future<T> overlapPrefill<T>({
  required Future<T> Function() retrieve,
  required Future<void> Function() prefill,
  required LlamaEngine engine,
}) async {
  final result = retrieve();
  final priming = Future<void>.sync(prefill).catchError((Object _) {});
  try {
    return await result;
  } finally {
    engine.cancelPriming();
    await priming;
  }
}

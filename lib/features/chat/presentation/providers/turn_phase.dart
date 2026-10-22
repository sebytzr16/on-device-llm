import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/shared_providers.dart';
import 'chat_provider.dart';

/// Where the answer in progress stands, for the send button and the island.
enum TurnPhase {
  /// Nothing is being answered.
  idle,

  /// Loading the model or researching: no measurable progress yet.
  preparing,

  /// The model is reading the prompt; [TurnActivity.progress] says how far.
  reading,

  /// Text (or reasoning) is streaming.
  writing,
}

typedef TurnActivity = ({TurnPhase phase, double? progress});

/// The phone engine's prompt-reading progress (null when not reading).
final prefillProgressProvider = NotifierProvider<PrefillProgress, double?>(
  PrefillProgress.new,
);

class PrefillProgress extends Notifier<double?> {
  @override
  double? build() {
    final engine = ref.watch(llamaEngineProvider);
    final changes = engine.prefillChanges.listen((value) => state = value);
    ref.onDispose(changes.cancel);
    return engine.prefillProgress;
  }
}

final turnPhaseProvider = Provider<TurnActivity>((ref) {
  final (busy, writing) = ref.watch(
    chatProvider.select(
      (s) =>
          (s.isGenerating, s.partialAnswer.isNotEmpty || s.reasoning != null),
    ),
  );
  if (!busy) return (phase: TurnPhase.idle, progress: null);
  if (writing) return (phase: TurnPhase.writing, progress: null);
  final read = ref.watch(prefillProgressProvider);
  if (read != null) return (phase: TurnPhase.reading, progress: read);
  return (phase: TurnPhase.preparing, progress: null);
});

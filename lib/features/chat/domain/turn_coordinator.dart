import 'package:dio/dio.dart';

enum TurnStage {
  preparing,
  researching,
  reading,
  writing,
  tools,
  saving,
  complete,
  stopped,
  failed,
}

sealed class GenerationEvent {
  final int turn;
  const GenerationEvent(this.turn);
}

class TextDelta extends GenerationEvent {
  final String text;
  const TextDelta(super.turn, this.text);
}

class GenerationEnded extends GenerationEvent {
  const GenerationEnded(super.turn);
}

/// A turn owns its cancellation and its stream. Late events from an ended
/// lease can never write into the next turn. Saved diagnostics contain phases
/// and counts only: no prompt, credentials, attachment paths or response text.
class TurnLease {
  final int id;
  final CancelToken retrieval = CancelToken();
  final void Function() _cancelEngines;
  final Stopwatch _clock = Stopwatch()..start();
  final List<Map<String, Object>> _events = [];
  bool cancelled = false, ended = false;
  TurnStage stage = TurnStage.preparing;
  int characters = 0;
  TurnLease._(this.id, this._cancelEngines) {
    _record();
  }

  void _record() {
    if (_events.length == 64) _events.removeAt(1);
    _events.add({
      'stage': stage.name,
      'elapsedMs': _clock.elapsedMilliseconds,
      'characters': characters,
    });
  }

  void transition(TurnStage next) {
    if (ended ||
        stage == next ||
        (cancelled &&
            next != TurnStage.saving &&
            next != TurnStage.stopped &&
            next != TurnStage.failed)) {
      return;
    }
    stage = next;
    _record();
  }

  void cancel() {
    if (ended || cancelled) return;
    cancelled = true;
    retrieval.cancel('Turn cancelled');
    _cancelEngines();
    transition(TurnStage.stopped);
  }

  List<Map<String, Object>> get trace => [
    for (final event in _events) Map.of(event),
  ];
}

class TurnCoordinator {
  TurnLease? active;
  int _sequence = 0;
  bool _disposed = false;
  TurnLease begin(void Function() cancelEngines) {
    if (_disposed) throw StateError('Turn coordinator is closed.');
    if (active != null) {
      throw StateError('Another turn still owns the session.');
    }
    return active = TurnLease._(++_sequence, cancelEngines);
  }

  bool owns(TurnLease lease) =>
      !_disposed && identical(active, lease) && !lease.ended;

  Stream<GenerationEvent> stream(
    TurnLease lease,
    Stream<String> Function() generate,
  ) async* {
    if (!owns(lease) || lease.cancelled) return;
    lease.transition(TurnStage.reading);
    await for (final text in generate()) {
      if (!owns(lease) || lease.cancelled) break;
      lease.characters += text.length;
      lease.transition(TurnStage.writing);
      yield TextDelta(lease.id, text);
    }
    if (owns(lease)) yield GenerationEnded(lease.id);
  }

  void release(TurnLease lease) {
    if (!identical(active, lease)) return;
    lease.retrieval.cancel('Turn ended');
    lease.ended = true;
    lease._clock.stop();
    active = null;
  }

  void dispose() {
    active?.cancel();
    if (active case final lease?) release(lease);
    _disposed = true;
  }
}

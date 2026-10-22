import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/turn_coordinator.dart';

void main() {
  test(
    'one owner, idempotent cancellation, and independent subsequent turn',
    () async {
      final coordinator = TurnCoordinator();
      var cancellations = 0;
      final first = coordinator.begin(() => cancellations++);
      expect(() => coordinator.begin(() {}), throwsStateError);
      first.cancel();
      first.cancel();
      expect(cancellations, 1);
      expect(first.retrieval.isCancelled, true);
      coordinator.release(first);
      final second = coordinator.begin(() => cancellations++);
      expect(second.cancelled, false);
      expect(
        await coordinator.stream(second, () => Stream.value('answer')).toList(),
        [isA<TextDelta>(), isA<GenerationEnded>()],
      );
      expect(second.characters, 6);
      coordinator.dispose();
      expect(cancellations, 2);
    },
  );
  test('events from a released lease cannot enter the next turn', () async {
    final coordinator = TurnCoordinator();
    final source = StreamController<String>();
    final first = coordinator.begin(() {});
    final events = <GenerationEvent>[];
    final subscription = coordinator
        .stream(first, () => source.stream)
        .listen(events.add);
    await Future<void>.delayed(Duration.zero);
    coordinator.release(first);
    final second = coordinator.begin(() {});
    source.add('late old answer');
    await source.close();
    await subscription.asFuture<void>();
    expect(events, isEmpty);
    expect(second.characters, 0);
    coordinator.dispose();
  });
  test('bounded lifecycle retains start and final outcome without text', () {
    final coordinator = TurnCoordinator();
    final turn = coordinator.begin(() {});
    for (var i = 0; i < 100; i++) {
      turn.transition(TurnStage.tools);
      turn.transition(TurnStage.reading);
    }
    turn.transition(TurnStage.saving);
    turn.transition(TurnStage.complete);
    expect(turn.trace.length, 64);
    expect(turn.trace.first['stage'], 'preparing');
    expect(turn.trace.last['stage'], 'complete');
    expect(
      turn.trace.every(
        (e) => e.keys.toSet().difference({
          'stage',
          'elapsedMs',
          'characters',
        }).isEmpty,
      ),
      true,
    );
    coordinator.release(turn);
    coordinator.dispose();
  });
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/utils/priority_work_queue.dart';
import 'package:ondevice_llm/core/utils/inference_admission.dart';
import 'package:ondevice_llm/features/retrieval/domain/primary_discovery.dart';

void main() {
  test(
    'background admission waits for reply and speech and remains cancellable',
    () async {
      final admission = InferenceAdmission();
      final reply = admission.hold(), speech = admission.hold();
      var ran = false, cancelled = false;
      final work = admission
          .background(cancelled: () => cancelled)
          .then((_) => ran = true);
      reply();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ran, isFalse);
      speech();
      await work;
      expect(ran, isTrue);
      final again = admission.hold();
      final abandoned = admission.background(cancelled: () => cancelled);
      cancelled = true;
      await expectLater(abandoned, throwsStateError);
      again();
      again();
      expect(admission.interactive, isFalse);
    },
  );
  test('a timed-out queued embedding never starts a native call', () async {
    final queue = PriorityWorkQueue();
    final gate = Completer<void>();
    final running = queue.submit(() => gate.future);
    var expired = false, calls = 0;
    final obsolete = queue.submit(
      () async => calls++,
      cancelled: () => expired,
    );
    await expectLater(
      obsolete.timeout(const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expired = true;
    gate.complete();
    await running;
    await expectLater(obsolete, throwsA(isA<StateError>()));
    expect(calls, 0);
  });
  test('missing product facts trigger a maker/manual pass', () {
    expect(
      PrimaryDiscovery.query(
        'Nikon Z30 weight and battery life',
        ['weight'],
        subject: ['Nikon', 'Z30'],
      ),
      'site:nikonusa.com Nikon Z30 weight specifications manual',
    );
    expect(
      PrimaryDiscovery.query(
        'Nikon Z30 compared with Canon R50 weight',
        ['weight'],
        subject: ['Nikon', 'Z30', 'Canon', 'R50'],
      ),
      isNull,
    );
    expect(
      PrimaryDiscovery.query(
        'Nikon stock news',
        ['earnings'],
        subject: ['Nikon'],
      ),
      isNull,
    );
  });
}

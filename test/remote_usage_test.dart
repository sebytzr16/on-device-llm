import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/inference/remote/remote_usage.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent initialization and admission admit only one request',
    () async {
      SharedPreferences.setMockInitialValues({});
      final usage = RemoteUsageLog();
      final results = await Future.wait(
        List.generate(20, (_) async {
          try {
            await usage.charge('p', 'm', const RemoteLimit(perDay: 1));
            return true;
          } on RemoteLimitReached {
            return false;
          }
        }),
      );
      expect(results.where((ok) => ok).length, 1);
      expect((await usage.counts('p', 'm')).day, 1);
    },
  );

  test(
    'caps above 5000 survive restart and rolling minute across midnight',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 10, 30, 23, 59, 59);
      final prefs = await SharedPreferences.getInstance();
      final usage = RemoteUsageLog(now: () => now, prefs: () async => prefs);
      for (var i = 0; i < 5001; i++) {
        await usage.charge(
          'p',
          'm',
          const RemoteLimit(perMinute: 5001, perDay: 6000),
        );
      }
      expect((await usage.counts('p', 'm')), (minute: 5001, day: 5001));
      await expectLater(
        usage.charge('p', 'm', const RemoteLimit(perMinute: 5001)),
        throwsA(isA<RemoteLimitReached>()),
      );
      await Future<void>.delayed(Duration.zero);
      final restored = RemoteUsageLog(now: () => now, prefs: () async => prefs);
      expect((await restored.counts('p', 'm')).day, 5001);
      now = DateTime(2026, 10, 31, 0, 0, 1);
      expect((await restored.counts('p', 'm')), (minute: 5001, day: 0));
      now = now.add(const Duration(minutes: 1));
      await restored.charge('p', 'm', const RemoteLimit(perMinute: 5001));
      expect((await restored.counts('p', 'm')), (minute: 1, day: 1));
    },
  );
  test(
    'daily cap above 5000 is enforceable independently of minute history',
    () async {
      var now = DateTime(2026, 10, 30, 12);
      final usage = RemoteUsageLog(now: () => now, prefs: () => null);
      for (var i = 0; i < 6000; i++) {
        await usage.charge('p', 'm', const RemoteLimit(perDay: 6000));
      }
      now = now.add(const Duration(minutes: 2));
      expect(await usage.counts('p', 'm'), (minute: 0, day: 6000));
      await expectLater(
        usage.charge('p', 'm', const RemoteLimit(perDay: 6000)),
        throwsA(isA<RemoteLimitReached>()),
      );
    },
  );

  test(
    'legacy timestamp history migrates into daily and minute counters',
    () async {
      final now = DateTime(2026, 10, 30, 12);
      SharedPreferences.setMockInitialValues({
        'remote_usage_v1': jsonEncode({
          'p|m': [
            now.millisecondsSinceEpoch,
            now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
          ],
        }),
      });
      final usage = RemoteUsageLog(now: () => now);
      expect(await usage.counts('p', 'm'), (minute: 1, day: 2));
      await usage.charge('p', 'm', const RemoteLimit(perDay: 3));
      await expectLater(
        usage.charge('p', 'm', const RemoteLimit(perDay: 3)),
        throwsA(isA<RemoteLimitReached>()),
      );
    },
  );
}

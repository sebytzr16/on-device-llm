import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/server_usage.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';

class _UsageHost extends DeviceHostingNotifier {
  @override
  DeviceHostingState build() =>
      const DeviceHostingState(running: true).withServed(
        ServedRequest(
          at: DateTime(2026),
          client: 'x',
          modelId: 'a',
          status: 200,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stopping the hosting provider clears all session usage', () async {
    final container = ProviderContainer(
      overrides: [deviceHostingProvider.overrideWith(_UsageHost.new)],
    );
    addTearDown(container.dispose);
    expect(container.read(deviceHostingProvider).usage.requests, 1);
    await container.read(deviceHostingProvider.notifier).stop();
    final usage = container.read(deviceHostingProvider).usage;
    expect(usage.requests, 0);
    expect(usage.clients, isEmpty);
    expect(usage.models, isEmpty);
    expect(usage.minutes, isEmpty);
  });
  test(
    'session totals, minute buckets, client and model aggregation survive log truncation',
    () {
      final now = DateTime(2026, 10, 22, 12);
      var state = const DeviceHostingState(running: true);
      for (var i = 0; i < 250; i++) {
        state = state.withServed(
          ServedRequest(
            at: now,
            client: '127.0.0.1',
            modelId: 'a',
            status: 200,
            completion: true,
            promptTokens: 10,
            completionTokens: 20,
            tokensPerSecond: 40,
            took: const Duration(seconds: 2),
          ),
        );
      }
      state = state.withServed(
        ServedRequest(
          at: now.subtract(const Duration(minutes: 29)),
          client: 'phone',
          modelId: 'b',
          status: 500,
        ),
      );
      final u = state.usage;
      expect(state.log.length, 200);
      expect(u.requests, 251);
      expect(u.errors, 1);
      expect(u.promptTokens, 2500);
      expect(u.completionTokens, 5000);
      expect(u.averageTps, 40);
      expect(u.averageMs, 2000);
      expect(u.clients['127.0.0.1']!.tokens, 7500);
      expect(u.clients['phone']!.requests, 1);
      expect(u.models['a']!.requests, 250);
      expect(u.models['b']!.requests, 1);
      expect(u.clients['127.0.0.1']!.lastSeen, now);
      expect(u.bars(now).first, 1);
      expect(u.bars(now).last, 250);
      expect(u.bars(now.add(const Duration(minutes: 30))), everyElement(0));
      expect(const DeviceHostingState().usage.requests, 0);
    },
  );
  test('old buckets prune and zero rates stay finite', () {
    final now = DateTime(2026);
    var u = const ServerUsage();
    for (var i = 0; i < 60; i++) {
      u = u.record(
        ServedRequest(
          at: now.add(Duration(minutes: i)),
          client: 'x',
          status: 400,
        ),
      );
    }
    expect(u.minutes.length, 30);
    expect(u.averageMs, 0);
    expect(u.averageTps, 0);
  });
}

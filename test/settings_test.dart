import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

void main() {
  test('settings defaults and JSON round-trip agree', () {
    const defaults = InferenceSettings();
    expect(InferenceSettings.fromJson({}).toJson(), defaults.toJson());
    final tuned = defaults.copyWith(
      temperature: 0,
      backend: GpuBackend.cpu,
      systemPrompt: 'Be concise.',
      thinkingModeEnabled: true,
    );
    expect(InferenceSettings.fromJson(tuned.toJson()).toJson(), tuned.toJson());
    expect(tuned.effectiveGpuLayers, 0);
  });
  test('invalid persisted settings cannot request unsafe allocations', () {
    final s = InferenceSettings.fromJson({
      'contextSize': -100,
      'maxTokens': 900000,
      'backend': 'future-npu',
      'kvCacheType': 'bad',
      'topP': double.nan,
      'temperature': 'hot',
      'webSearchEnabled': 'true',
    });
    expect(s.contextSize, InferenceSettings.minContext);
    expect(s.maxTokens, InferenceSettings.maxResponseTokens);
    expect(s.backend, GpuBackend.auto);
    expect(s.topP, .95);
    expect(s.temperature, .7);
    expect(s.webSearchEnabled, false);
  });
  test('context can be raised to a million tokens and read back', () {
    final s = InferenceSettings.fromJson({
      'contextSize': 1 << 20,
      'maxTokens': 32768,
      'thinkingBudgetTokens': 512,
      'batchThreads': 8,
      'promptCache': false,
      'researchTimeBudgetSeconds': 60,
      'evidencePassages': 12,
    });
    expect(s.contextSize, 1 << 20);
    expect(s.maxTokens, 32768);
    expect(s.thinkingBudgetTokens, 512);
    expect(s.effectiveBatchThreads, 8);
    expect(s.promptCache, false);
    expect(s.researchTimeBudgetSeconds, 60);
    expect(s.evidencePassages, 12);
    expect(InferenceSettings.fromJson(s.toJson()).toJson(), s.toJson());
  });
  test('remote server is off unless a usable URL is configured', () {
    expect(const InferenceSettings().usesRemote, false);
    expect(
      const InferenceSettings(
        remoteEnabled: true,
        remoteProfiles: [RemoteProfile(id: 'a', name: 'a', baseUrl: 'garbage')],
        remoteProfileId: 'a',
      ).usesRemote,
      false,
    );
    expect(
      const InferenceSettings(
        remoteEnabled: true,
        remoteProfiles: [
          RemoteProfile(id: 'a', name: 'a', baseUrl: 'http://10.0.0.5:1234'),
        ],
      ).usesRemote,
      true,
    );
  });
  test('settings saved with the removed Bing switch still load', () {
    // The second engine was removed on 2026-10-11; phones still store its key.
    final s = InferenceSettings.fromJson({
      'fallbackSearch': false,
      'searchAgain': false,
    });
    expect(s.searchAgain, false);
    expect(s.toJson(), isNot(contains('fallbackSearch')));
  });
}

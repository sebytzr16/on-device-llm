import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  for (final (window, maximum, reserve) in [
    (32768, 65536, 8192),
    (100, 65536, 99),
    (8192, 65536, 2048),
    (32768, 1000, 1000),
    (65536, 65536, 16384),
    (131072, 65536, 32768),
    (262144, 128000, 65536),
    (65536, 128000, 16384),
  ]) {
    test('window $window preserves generation limit $maximum', () {
      final settings = InferenceSettings(
        contextSize: window,
        maxTokens: maximum,
      );
      final native = LlamaEngine.generationConfig(settings: settings);
      expect(native['maxTokens'], maximum);
      expect(native['reservedTokens'], reserve);
      expect(native['reservedTokens'], settings.responseReserve(window));
    });
  }

  test('preview and generation reserve against the loaded context', () {
    const settings = InferenceSettings(contextSize: 131072, maxTokens: 65536);
    final native = LlamaEngine.generationConfig(
      settings: settings,
      contextSize: 8192,
    );
    expect(native['maxTokens'], 65536);
    expect(native['reservedTokens'], 2048);
  });

  test('agent settings retain their generation limit separately', () {
    final settings = const InferenceSettings().forAgent(answerTokens: 3000);
    final native = LlamaEngine.generationConfig(settings: settings);
    expect(native['maxTokens'], settings.maxTokens);
    expect(
      native['reservedTokens'],
      settings.responseReserve(settings.contextSize),
    );
  });
}

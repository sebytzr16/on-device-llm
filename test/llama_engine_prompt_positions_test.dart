import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  test('text turns use promptTokens and cachedPromptTokens as positions', () {
    final text = promptPositions({
      'promptTokens': 900,
      'cachedPromptTokens': 800,
    });
    expect(text.total, 900);
    expect(text.cached, 800);
  });

  test('photo turns report the tracked media prompt positions', () {
    final media = promptPositions({
      'promptTokens': 127,
      'mediaTokens': 127,
      'mediaPositions': 91,
      'cachedPromptTokens': 0,
    });
    expect(media.total, 127);
    expect(media.cached, 0);
  });

  test('legacy bridge falls back to mediaTokens for photo prompts', () {
    final legacy = promptPositions({
      'promptTokens': 0,
      'mediaTokens': 127,
      'cachedPromptTokens': 0,
    });
    expect(legacy.total, 127);
    expect(legacy.cached, 0);
  });

  test('cached positions stay within the rendered prompt', () {
    final stale = promptPositions({
      'promptTokens': 100,
      'cachedPromptTokens': 500,
    });
    expect(stale.total, 100);
    expect(stale.cached, 100);
    final missing = promptPositions({'cachedPromptTokens': -3});
    expect(missing.total, 0);
    expect(missing.cached, 0);
  });
}

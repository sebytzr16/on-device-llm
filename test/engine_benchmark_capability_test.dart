import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/engine/engine_descriptor.dart';

void main() {
  test('only llama.cpp offers the Benchmark, separately from Optimize', () {
    expect(llamaCppEngine.capabilities.benchmark, isTrue);
    expect(llamaCppEngine.capabilities.optimize, isTrue);
    expect(liteRtLmEngine.capabilities.benchmark, isFalse);
    expect(ikLlamaCppEngine.capabilities.benchmark, isFalse);
  });
}

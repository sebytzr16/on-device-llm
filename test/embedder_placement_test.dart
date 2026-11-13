import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  Map<String, Object?> config({
    required bool desktop,
    InferenceSettings? placement,
  }) => LlamaEngine.embedderConfig(
    desktop: desktop,
    contextSize: 2048,
    threads: 4,
    placement: placement,
  );

  test('Android keeps the embedding load on the CPU (E22)', () {
    final map = config(
      desktop: false,
      placement: const InferenceSettings(
        backend: GpuBackend.vulkan,
        nGpuLayers: 999,
      ),
    );
    expect(map['embedding'], true);
    expect(map['backend'], 'cpu');
    expect(map['nGpuLayers'], 0);
  });

  test('desktop embedding uses the chat model hardware policy (E22)', () {
    for (final backend in [
      GpuBackend.auto,
      GpuBackend.cuda,
      GpuBackend.vulkan,
    ]) {
      final settings = InferenceSettings(backend: backend, nGpuLayers: 12);
      final map = config(desktop: true, placement: settings);
      final chat =
          jsonDecode(LlamaEngine.loadConfig(settings: settings)) as Map;
      expect(map['backend'], chat['backend']);
      expect(map['nGpuLayers'], chat['nGpuLayers']);
      expect(map['backend'], backend.name);
      expect(map['nGpuLayers'], 12);
    }
  });

  test('desktop embedding stays on the CPU without a GPU choice (E22)', () {
    expect(
      config(
        desktop: true,
        placement: const InferenceSettings(backend: GpuBackend.cpu),
      )['backend'],
      'cpu',
    );
    expect(
      config(
        desktop: true,
        placement: const InferenceSettings(
          backend: GpuBackend.vulkan,
          nGpuLayers: 0,
        ),
      )['backend'],
      'cpu',
    );
    // No placement (a caller without a policy) keeps the previous CPU load.
    expect(config(desktop: true)['backend'], 'cpu');
    expect(config(desktop: true)['nGpuLayers'], 0);
  });
}

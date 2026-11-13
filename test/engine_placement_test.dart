import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  String select(InferenceSettings settings) {
    final choice = nativeLibraryChoice(
      LlamaEngine.loadConfig(settings: settings),
      windows: true,
    );
    return LlamaBindings.openWindowsLibrary<String>(
      preferred: choice.backend,
      cpuVariant: choice.cpuVariant,
      skipped: [],
      environment: const {},
      fileExists: (_) => true, // Both CUDA and Vulkan drivers are installed.
      hasAvx2: () => true,
      hasAvx512: () => true,
      open: (name) => name,
      gpuDeviceCount: (_) => 1,
    ).name;
  }

  test('explicit Vulkan estimate selects Vulkan with CUDA installed (E03)', () {
    expect(
      select(const InferenceSettings(backend: GpuBackend.vulkan)),
      'ondevice_llm_vulkan.dll',
    );
    expect(
      select(const InferenceSettings(backend: GpuBackend.cuda)),
      'ondevice_llm_cuda.dll',
    );
  });

  test(
    'CPU estimates honor the selected variant despite installed GPUs (E03)',
    () {
      for (final variant in ['compat', 'avx2', 'avx512']) {
        expect(
          select(
            InferenceSettings(backend: GpuBackend.cpu, cpuVariant: variant),
          ),
          variant == 'avx2' ? 'ondevice_llm.dll' : 'ondevice_llm_$variant.dll',
        );
      }
    },
  );

  test('automatic backend choice and non-Windows behavior are preserved', () {
    expect(nativeLibraryChoice('{}', windows: true), (
      backend: null,
      cpuVariant: 'auto',
    ));
    expect(
      nativeLibraryChoice(
        LlamaEngine.loadConfig(
          settings: const InferenceSettings(backend: GpuBackend.vulkan),
        ),
        windows: false,
      ).backend,
      isNull,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_tags.dart';
import 'package:ondevice_llm/inference/engine/ternary_backend.dart';

void main() {
  test(
    'a ternary model runs on the CPU on backends without ternary kernels',
    () {
      // Vulkan is the measured trap (0.06 tok/s); the others are the same
      // native patch without kernels.
      for (final backend in ['vulkan', 'opencl', 'metal', 'qnn']) {
        expect(
          ternaryNeedsCpu(backend: backend, ternary: true),
          isTrue,
          reason: backend,
        );
      }
      expect(ternaryNeedsCpu(backend: 'VULKAN', ternary: true), isTrue);
      expect(ternaryNeedsCpu(backend: ' vulkan ', ternary: true), isTrue);
      for (final backend in ['cuda', 'cpu']) {
        expect(
          ternaryNeedsCpu(backend: backend, ternary: true),
          isFalse,
          reason: backend,
        );
      }
      // Auto is resolved to the backend it picked before the check, so it
      // never moves a CUDA load to the CPU.
      expect(ternaryNeedsCpu(backend: 'auto', ternary: true), isFalse);
      expect(ternaryNeedsCpu(backend: 'vulkan', ternary: false), isFalse);
    },
  );

  test('ternary models are the Bonsai 2 catalog ids or file types 141-143', () {
    for (final id in [
      'bonsai2-9b-q2_0',
      'bonsai2-27b-ptq1_0',
      'bonsai2-2b-q2_0',
    ]) {
      expect(isTernaryModel(catalogId: id), isTrue, reason: id);
    }
    for (final type in [141, 142, 143]) {
      expect(isTernaryModel(fileType: type), isTrue, reason: '$type');
    }
    // An imported Bonsai 2 file has a local id: only its header says what
    // it is.
    expect(
      isTernaryModel(catalogId: 'local-0123456789', fileType: 143),
      isTrue,
    );
    expect(isTernaryModel(catalogId: 'qwen35-9b-q4km', fileType: 15), isFalse);
    expect(isTernaryModel(catalogId: 'local-0123456789'), isFalse);
    expect(isTernaryModel(), isFalse);
  });

  test('the models page shows no graphics-card fit for ternary on Vulkan', () {
    const memory = DeviceMemory(
      totalBytes: 32 * 1024 * 1024 * 1024,
      availableBytes: 24 * 1024 * 1024 * 1024,
      lowMemory: false,
    );
    const model = ModelInfo(
      id: 'bonsai2-27b-ptq1_0',
      displayName: 'Bonsai 2 27B',
      fileName: 'Ternary-Bonsai-2-27B-PTQ1_0.gguf',
      sizeBytes: 5946648928,
      family: ModelFamily.qwen,
      quantization: ModelQuantization.ptq1_0,
    );
    expect(modelFit(memory, model, backend: 'vulkan'), ModelFit.unknown);
    expect(modelFit(memory, model, backend: 'cuda'), ModelFit.fits);
    expect(modelFit(memory, model, backend: 'cpu'), ModelFit.fits);
    // An imported Bonsai says it is ternary through its header instead.
    const imported = ModelInfo(
      id: 'local-0123456789',
      displayName: 'Bonsai 2 27B',
      fileName: 'Ternary-Bonsai-2-27B-PTQ1_0.gguf',
      sizeBytes: 5946648928,
      family: ModelFamily.qwen,
      quantization: ModelQuantization.ptq1_0,
    );
    expect(
      modelFit(memory, imported, backend: 'vulkan', fileType: 142),
      ModelFit.unknown,
    );
    expect(modelFit(memory, imported, backend: 'vulkan'), ModelFit.fits);
  });
}

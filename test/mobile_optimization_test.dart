import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/optimize/optimize_setups.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  const cpu = InferenceSettings(
    backend: GpuBackend.cpu,
    cpuThreads: 6,
    batchSize: 512,
    microBatchSize: 512,
    nGpuLayers: 0,
  );
  test(
    'mobile sweep is small, clamps batches, and excludes drafts and MoE',
    () {
      final setups = pcOptimizationSetups(
        cpu,
        mobile: true,
        bigCoreCount: 6,
        userDraft: 'draft',
        cpuMoe: [1, 3],
      );
      expect(setups.length, lessThanOrEqualTo(7));
      expect(setups.map((s) => s.cpuThreads).toSet(), {4, 6});
      expect(setups.map((s) => s.batchSize).toSet(), {256, 512});
      expect(setups.any((s) => !s.flashAttention), isTrue);
      for (final s in setups) {
        expect(s.draftModelId, isEmpty);
        expect(s.speculationMode, 'off');
        expect(s.nCpuMoe, -1);
        expect(s.expertsUsed, -1);
        expect(s.nGpuLayers, 0);
        expect(s.effectiveMicroBatchSize, lessThanOrEqualTo(s.batchSize));
      }
      final big = pcOptimizationSetups(cpu, mobile: true, bigCoreCount: 2);
      expect(big.map((s) => s.cpuThreads).toSet(), {2, 4, 6});
    },
  );
  test('OpenCL tries CPU versus fitted GPU and MTP off versus auto', () {
    final setups = pcOptimizationSetups(
      cpu.copyWith(backend: GpuBackend.opencl, nGpuLayers: 17),
      mobile: true,
      bigCoreCount: 4,
      mtpHead: true,
    );
    expect(setups.map((s) => s.nGpuLayers).toSet(), {0, 17});
    expect(setups.map((s) => s.speculationMode).toSet(), {'off', 'auto'});
    expect(setups.every((s) => s.draftMaxTokens == cpu.draftMaxTokens), isTrue);
  });
  test('iOS sweep compares Metal and CPU with safe settings', () {
    final setups = pcOptimizationSetups(
      cpu.copyWith(
        backend: GpuBackend.metal,
        nGpuLayers: 24,
        kvCacheType: KvCacheType.q8_0,
        mtp: true,
      ),
      ios: true,
      bigCoreCount: 2,
      mtpHead: true,
      userDraft: 'draft',
      cpuMoe: [1, 3],
    );
    expect(setups.map((s) => s.nGpuLayers).toSet(), {0, 24});
    expect(setups.map((s) => s.cpuThreads).toSet(), {4, 6});
    for (final s in setups) {
      expect(s.speculationMode, 'off');
      expect(s.mtp, isFalse);
      expect(s.draftModelId, isEmpty);
      expect(s.nCpuMoe, -1);
      expect(s.flashAttention, isTrue);
    }
  });
  for (final backend in [GpuBackend.auto, GpuBackend.cpu, GpuBackend.opencl]) {
    test('mobile defaults respect the $backend backend and budget', () async {
      final tried = <InferenceSettings>[];
      final result = await pcOptimizationDefaults(
        mobile: true,
        current: cpu.copyWith(backend: backend),
        defaults: const InferenceSettings(),
        estimate: (s) async {
          tried.add(s);
          return {
            'layers': 24,
            'gpuLayers': s.nGpuLayers.clamp(0, 24),
            'ramNeedMb': 1024,
            'ramAvailableMb': 16000,
            'vramNeedMb': 1000,
            'vramFreeMb': 8000,
          };
        },
      );
      expect(result.backend, backend);
      expect(result.nGpuLayers, backend == GpuBackend.opencl ? 999 : 0);
      if (backend != GpuBackend.opencl) {
        expect(tried.every((s) => s.nGpuLayers == 0), isTrue);
      }
    });
  }
}

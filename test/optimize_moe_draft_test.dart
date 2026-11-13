import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/pc_optimization.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

// A 40-layer MoE model: each layer's experts kept on the card costs 300 MB,
// the rest 2000 MB; the card has 8000 MB free.
Map<String, dynamic> _moe(InferenceSettings s) {
  final onCpu = s.nCpuMoe < 0 ? 30 : s.nCpuMoe.clamp(0, 40);
  return {
    'layers': 40,
    'gpuLayers': 40,
    'gpuExpertsOnCpu': true,
    'ramNeedMb': 4096,
    'ramAvailableMb': 32768,
    'vramNeedMb': 2000 + (40 - onCpu) * 300,
    'vramFreeMb': 8000,
  };
}

void main() {
  final best = const InferenceSettings().copyWith(
    nGpuLayers: 999,
    backend: GpuBackend.cuda,
  );

  test('MoE placements start at the fewest experts in RAM that fit', () async {
    final n = await moeExpertPlacements(best, estimate: (s) async => _moe(s));
    // 2000 + (40 - n) * 300 + reserve <= 8000.
    final reserve = best.vramReserveMb;
    final fewest = 40 - ((8000 - 2000 - reserve) ~/ 300);
    expect(n, [fewest, fewest + 2, fewest + 4]);
  });

  test('no placements when every expert fits or on CPU', () async {
    expect(
      await moeExpertPlacements(
        best,
        estimate: (s) async => {..._moe(s), 'gpuExpertsOnCpu': false},
      ),
      isEmpty,
    );
    expect(
      await moeExpertPlacements(
        best.copyWith(backend: GpuBackend.cpu),
        estimate: (s) async => _moe(s),
      ),
      isEmpty,
    );
  });

  test('a picked draft model is measured with and without', () {
    final setups = pcOptimizationSetups(
      best,
      userDraft: 'small-draft',
      userSpeculationMode: 'draft',
      cpuMoe: const [12, 14],
    );
    expect(setups.first.draftModelId, best.draftModelId);
    expect(
      setups
          .where((s) => s.draftModelId == 'small-draft')
          .single
          .speculationMode,
      'draft',
    );
    expect(setups.map((s) => s.nCpuMoe), containsAll([12, 14]));
    expect(
      pcOptimizationSetups(
        best,
        userDraft: 'mtp:off',
      ).where((s) => s.draftModelId == 'mtp:off'),
      isEmpty,
    );
  });

  test('a matching draft on disk is the smallest same-family model', () {
    final big = desktopCatalog.firstWhere((m) => m.id == 'gemma4-26b-a4b-qat');
    final small = desktopCatalog.firstWhere((m) => m.id == 'gemma4-e4b-qat');
    final qwen = desktopCatalog.firstWhere((m) => m.id == 'qwen35-9b-q4km');
    ModelInfo on(ModelInfo m) =>
        m.copyWith(isDownloaded: true, localPath: 'x/${m.fileName}');
    expect(
      matchingDraftOnDisk(big, [on(big), on(small), on(qwen)])?.id,
      small.id,
    );
    expect(matchingDraftOnDisk(big, [on(big), small, on(qwen)]), isNull);
    expect(matchingDraftOnDisk(small, [on(big), on(small)]), isNull);
  });
}

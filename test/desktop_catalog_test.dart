import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';

void main() {
  test(
    'desktop models have pinned downloads and explicit text-only exceptions',
    () {
      // Owner, 2026-10-28: none of the small phone models on a laptop.
      expect(desktopCatalog.map((m) => m.id), [
        'diffusiongemma-26b-a4b-q4km',
        'qwen35-9b-q4km',
        'gemma4-e4b-qat',
        'gemma4-26b-a4b-qat',
        'bonsai2-9b-q2_0',
        'bonsai2-27b-ptq1_0',
      ]);
      for (final m in desktopCatalog) {
        expect(catalogMeta[m.id], isNotNull, reason: m.id);
        if (m.id == 'diffusiongemma-26b-a4b-q4km') {
          expect(
            visionProjectors[m.id],
            isNull,
            reason: 'DiffusionGemma is text only',
          );
          expect(catalogMeta[m.id]!.reasoning, isFalse);
        } else {
          expect(visionProjectors[m.id], isNotNull, reason: m.id);
        }
        expect(m.sha256, hasLength(64), reason: m.id);
        expect(m.downloadUrl, contains('/resolve/'), reason: m.id);
        expect(retiredCatalogIds, isNot(contains(m.id)));
      }
      expect(desktopCatalog.map((m) => m.fileName).toSet(), hasLength(6));
    },
  );

  test('the phone list is unchanged and shares Gemma 4 E4B', () {
    expect(bundledCatalog, contains(gemma4E4b));
    expect(bundledCatalog.map((m) => m.id), contains('qwen35-0.8b-q8_0'));
    expect(bundledCatalog.where((m) => m.id.startsWith('bonsai')), isEmpty);
    expect(
      bundledCatalog.map((m) => m.id),
      isNot(contains('diffusiongemma-26b-a4b-q4km')),
    );
  });
}

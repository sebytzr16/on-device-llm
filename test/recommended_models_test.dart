import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/recommended_models.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_tags.dart';

ModelInfo _m(String id, int gb) => ModelInfo(
  id: id,
  displayName: id,
  fileName: '$id.gguf',
  sizeBytes: gb * 1000000000,
  family: ModelFamily.other,
  quantization: ModelQuantization.q4_k_m,
);

void main() {
  test('fitting models first, bigger fits before smaller, too large last', () {
    final small = _m('small', 1);
    final mid = _m('mid', 5);
    final big = _m('big', 40);
    final tight = _m('tight', 7);
    ModelFit fit(ModelInfo m) => switch (m.id) {
      'big' => ModelFit.tooLarge,
      'tight' => ModelFit.tight,
      _ => ModelFit.fits,
    };
    final ranked = rankRecommended(
      [big, small, tight, mid],
      fit: fit,
      desktop: false,
    );
    expect(ranked.map((m) => m.id), ['mid', 'small', 'tight', 'big']);
  });

  test('unknown hardware keeps every model, ordered by size', () {
    final ranked = rankRecommended(
      [_m('a', 1), _m('b', 3)],
      fit: (_) => ModelFit.unknown,
      desktop: true,
    );
    expect(ranked.map((m) => m.id), ['b', 'a']);
  });
}

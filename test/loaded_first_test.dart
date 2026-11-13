import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_suggestions.dart';

ModelInfo _m(String id) => ModelInfo(
  id: id,
  displayName: id,
  fileName: '$id.gguf',
  sizeBytes: 1,
  family: ModelFamily.other,
  quantization: ModelQuantization.q4_k_m,
);

void main() {
  test('the loaded model moves first and the rest keep their order', () {
    final list = [_m('a'), _m('b'), _m('c'), _m('d')];
    expect(loadedFirst(list, 'c').map((m) => m.id), ['c', 'a', 'b', 'd']);
    expect(loadedFirst(list, null).map((m) => m.id), ['a', 'b', 'c', 'd']);
  });
}

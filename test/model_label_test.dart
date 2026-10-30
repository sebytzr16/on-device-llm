import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/retired_model_names.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const model = ModelInfo(
    id: 'local-0123456789abcdef0123',
    displayName: 'My Fine-tune Q4',
    fileName: 'local-0123456789abcdef0123.gguf',
    sizeBytes: 1,
    family: ModelFamily.qwen,
    quantization: ModelQuantization.unknown,
  );

  test('a model in the library shows its display name', () {
    expect(
      modelLabel(
        model.id,
        catalog: const [model],
        retired: const {},
        removed: 'Removed model',
      ),
      'My Fine-tune Q4',
    );
  });

  test('a deleted model keeps the name it had, never the hash id', () {
    expect(
      modelLabel(
        model.id,
        catalog: const [],
        retired: {model.id: 'My Fine-tune Q4'},
        removed: 'Removed model',
      ),
      'My Fine-tune Q4',
    );
    expect(
      modelLabel(
        'hf-0123456789abcdef',
        catalog: const [],
        retired: const {},
        removed: 'Removed model',
      ),
      'Removed model',
    );
  });

  test('remote answers and missing ids', () {
    expect(
      modelLabel(
        'remote:gpt-x',
        catalog: const [],
        retired: const {},
        removed: 'Removed model',
      ),
      'gpt-x · remote',
    );
    expect(
      modelLabel(
        null,
        catalog: const [],
        retired: const {},
        removed: 'Removed model',
        fallback: 'Loaded',
      ),
      'Loaded',
    );
  });

  test('remembered names persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(retiredModelNamesProvider.notifier);
    await notifier.remember(model.id, model.displayName);
    final again = ProviderContainer();
    addTearDown(again.dispose);
    again.read(retiredModelNamesProvider);
    await again.read(retiredModelNamesProvider.notifier).ready;
    expect(again.read(retiredModelNamesProvider)[model.id], 'My Fine-tune Q4');
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_suggestions.dart';
import 'package:ondevice_llm/features/models/presentation/providers/hidden_library_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('hidden ids leave "Available to download"', () {
    final all = availableLibraryModels(desktopCatalog, desktop: true);
    expect(all, isNotEmpty);
    final first = all.first.id;
    final rest = availableLibraryModels(
      desktopCatalog,
      desktop: true,
      hidden: {first},
    );
    expect(rest.map((m) => m.id), isNot(contains(first)));
    expect(rest.length, all.length - 1);
  });

  test('hide persists and restoreAll clears', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(hiddenLibraryModelsProvider.notifier);
    await notifier.hide('a');
    await notifier.hide('b');
    expect(container.read(hiddenLibraryModelsProvider), {'a', 'b'});

    final again = ProviderContainer();
    addTearDown(again.dispose);
    again.read(hiddenLibraryModelsProvider);
    await again.read(hiddenLibraryModelsProvider.notifier).ready;
    expect(again.read(hiddenLibraryModelsProvider), {'a', 'b'});

    await again.read(hiddenLibraryModelsProvider.notifier).restoreAll();
    expect(again.read(hiddenLibraryModelsProvider), isEmpty);
  });
}

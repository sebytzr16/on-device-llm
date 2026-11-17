import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/optimize/optimized_models_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'loads, deduplicates, and persists concurrent optimized model ids',
    () async {
      SharedPreferences.setMockInitialValues({
        'optimized_models_v1': ['old', 'old'],
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(await c.read(optimizedModelsProvider.future), {'old'});
      final store = c.read(optimizedModelsProvider.notifier);
      await Future.wait([
        store.markOptimized('a'),
        store.markOptimized('b'),
        store.markOptimized('a'),
      ]);
      expect(c.read(optimizedModelsProvider).requireValue, {'old', 'a', 'b'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('optimized_models_v1'), ['a', 'b', 'old']);
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      expect(await reopened.read(optimizedModelsProvider.future), {
        'old',
        'a',
        'b',
      });
      expect(
        () => reopened.read(optimizedModelsProvider).requireValue.add('x'),
        throwsUnsupportedError,
      );
    },
  );
}

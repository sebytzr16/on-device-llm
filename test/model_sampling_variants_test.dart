import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_sampling_variants_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'save, activate, modify, update, rename and delete preserve other settings',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final profiles = c.read(modelProfilesProvider.notifier);
      await profiles.ready;
      final variants = c.read(modelSamplingVariantsProvider.notifier);
      await variants.ready;
      await profiles.set('a', {
        'temperature': 0.2,
        'topP': 0.9,
        'systemPrompt': 'Brief',
        'contextSize': 8192,
      });
      await variants.save('a', 'Precise');
      expect(variants.of('a').selected!.values, {
        'temperature': 0.2,
        'topP': 0.9,
        'systemPrompt': 'Brief',
      });
      expect(variants.of('a').modified(profiles.of('a')), false);
      await profiles.setKey('a', 'temperature', 1.0);
      expect(variants.of('a').modified(profiles.of('a')), true);
      expect(variants.of('a').selected!.values['temperature'], 0.2);
      await variants.save('a', 'Creative');
      await profiles.setKey('a', 'minP', 0.1);
      await variants.activate('a', 'Precise');
      expect(profiles.of('a')['temperature'], 0.2);
      expect(profiles.of('a').containsKey('minP'), false);
      expect(profiles.of('a')['contextSize'], 8192);
      await profiles.setKey('a', 'temperature', 0.3);
      await variants.update('a', 'Precise');
      expect(variants.of('a').modified(profiles.of('a')), false);
      await variants.rename('a', 'Precise', 'Focused');
      expect(variants.of('a').active, 'Focused');
      await variants.delete('a', 'Focused');
      expect(variants.of('a').active, null);
      expect(profiles.of('a')['temperature'], 0.3);
      await variants.activate('a', null);
      expect(profiles.of('a'), {'contextSize': 8192});
    },
  );

  test('persists active variants independently for each model', () async {
    final c = ProviderContainer();
    final v = c.read(modelSamplingVariantsProvider.notifier);
    await v.save('a', 'Same', values: {'temperature': 0.2});
    await v.save('b', 'Same', values: {'temperature': 1.0});
    await v.activate('a', 'Same');
    expect(c.read(modelProfilesProvider)['b'], null);
    await v.activate('b', 'Same');
    await v.rename('a', 'Same', 'Other');
    await v.save('a', 'Other', values: {'temperature': 1.5});
    expect(v.of('a').variants.length, 1);
    c.dispose();
    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    final restored = reloaded.read(modelSamplingVariantsProvider.notifier);
    await restored.ready;
    expect(restored.of('a').active, 'Other');
    expect(restored.of('b').active, 'Same');
    expect(restored.of('b').selected!.values['temperature'], 1.0);
    await reloaded.read(modelProfilesProvider.notifier).ready;
    expect(reloaded.read(modelProfilesProvider)['a']!['temperature'], 0.2);
  });

  test('invalid stored variants fall back safely', () async {
    SharedPreferences.setMockInitialValues({
      'model_sampling_variants_v1': '{broken',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final v = c.read(modelSamplingVariantsProvider.notifier);
    await v.ready;
    expect(c.read(modelSamplingVariantsProvider), isEmpty);
  });
}

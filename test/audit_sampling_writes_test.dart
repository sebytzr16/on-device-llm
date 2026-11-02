import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_sampling_variants_provider.dart';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();
  var writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('model_sampling_variants_v1')) {
      writes++;
      if (writes == 1) throw StateError('Disk unavailable');
      if (writes == 2) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports failed writes and persists later changes (P2-30)', () async {
    SharedPreferences.setMockInitialValues({});
    final previousStore = SharedPreferencesStorePlatform.instance;
    final store = _FailingStore();
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previousStore);
    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousHandler);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final variants = container.read(modelSamplingVariantsProvider.notifier);
    await variants.save('a', 'First', values: {'temperature': 0.2});
    await variants.rename('a', 'First', 'Second');
    await variants.rename('a', 'Second', 'Saved');
    expect(errors, hasLength(2));
    expect(errors.first.exception.toString(), contains('Disk unavailable'));
    expect(store.writes, 3);
    final persisted = await store.getAll();
    final raw = persisted['flutter.model_sampling_variants_v1'] as String;
    expect(jsonDecode(raw)['a']['active'], 'Saved');
    expect(jsonDecode(raw)['a']['variants'][0]['name'], 'Saved');
  });
}

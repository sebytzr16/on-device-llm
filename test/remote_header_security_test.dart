import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/data/remote_key_store.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements RemoteKeyStore {
  final keys = <String, String>{};
  final headers = <String, Map<String, String>>{};

  @override
  Future<Map<String, String>> readAll() async => {...keys};

  @override
  Future<void> write(String profileId, String key) async {
    keys[profileId] = key;
  }

  @override
  Future<void> delete(String profileId) async {
    keys.remove(profileId);
  }

  @override
  Future<Map<String, Map<String, String>>> readAllHeaders() async => {
    for (final e in headers.entries) e.key: {...e.value},
  };

  @override
  Future<void> writeHeaders(
    String profileId,
    Map<String, String> values,
  ) async {
    if (values.isEmpty) {
      headers.remove(profileId);
    } else {
      headers[profileId] = {...values};
    }
  }

  @override
  Future<void> deleteHeaders(String profileId) async {
    headers.remove(profileId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('header values are kept out of the settings JSON', () {
    const profile = RemoteProfile(
      id: 'p',
      name: 'P',
      headers: {'Cookie': 'session-secret', 'X-Auth-Token': 'token'},
    );
    final json = jsonEncode(profile.toJson());
    expect(profile.toJson().containsKey('headers'), false);
    expect(json.contains('session-secret'), false);
    expect(json.contains('token'), false);
  });

  test('URL credentials, queries and fragments are rejected', () {
    const userInfo = RemoteProfile(
      id: 'p',
      name: 'P',
      baseUrl: 'https://user:pass@example.test/v1',
    );
    expect(userInfo.uri, isNull);
    expect(
      RemoteProfile.fromJson({
        'id': 'p',
        'baseUrl': 'https://user:pass@example.test/v1?api_key=secret',
      })!.baseUrl,
      '',
    );
    for (final url in [
      'https://user:pass@example.test/v1',
      'https://example.test/v1?api_key=secret',
      'https://example.test/v1#secret',
    ]) {
      expect(
        RemoteProfile.fromPairing(
          jsonEncode({'ondevice_llm': 'connection', 'url': url, 'key': 'k'}),
          id: 'p',
        ),
        isNull,
        reason: url,
      );
    }
  });

  test(
    'header values round-trip through the keystore, not preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = _MemoryStore();
      var container = ProviderContainer(
        overrides: [remoteKeyStoreProvider.overrideWithValue(store)],
      );
      await container.read(settingsProvider.notifier).ready;
      await container
          .read(settingsProvider.notifier)
          .update(
            const InferenceSettings(
              remoteProfiles: [
                RemoteProfile(
                  id: 'p',
                  name: 'P',
                  headers: {'Cookie': 'session-secret'},
                ),
              ],
            ),
          );
      expect(store.headers['p'], {'Cookie': 'session-secret'});
      final raw =
          (await SharedPreferences.getInstance()).getString(
            'inference_settings_v1',
          ) ??
          '';
      expect(raw.contains('session-secret'), false);
      container.dispose();

      container = ProviderContainer(
        overrides: [remoteKeyStoreProvider.overrideWithValue(store)],
      );
      await container.read(settingsProvider.notifier).ready;
      final loaded = container.read(settingsProvider);
      expect(loaded.remoteHeaders['p'], {'Cookie': 'session-secret'});
      expect(loaded.remoteProfiles.single.headers, {
        'Cookie': 'session-secret',
      });
      container.dispose();
    },
  );
}

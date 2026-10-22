import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/platform/device_info.dart';
import '../../../../data/network/web_search/duckduckgo_scraper.dart';
import '../../data/remote_key_store.dart';
import '../../domain/entities/inference_settings.dart';

const _kSettingsKey = 'inference_settings_v1';
const _kThinkingOffKey = 'thinking_off_2026_09_28';
const _kSamplingDefaultsKey = 'sampling_defaults_2026_10_04';

/// Where remote API keys live; tests swap in an in-memory store.
final remoteKeyStoreProvider = Provider<RemoteKeyStore>(
  (_) => SecureRemoteKeyStore(),
);

class SettingsNotifier extends Notifier<InferenceSettings> {
  SharedPreferences? _prefs;
  bool _loaded = false;
  InferenceSettings _defaults = const InferenceSettings();

  /// The device-adjusted defaults (the "This phone" layer of the cascade).
  InferenceSettings get defaults => _defaults;
  late Future<void> ready;
  Future<void> _writes = Future.value();
  bool _alive = true;

  @override
  InferenceSettings build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const InferenceSettings();
  }

  Future<void> _load() async {
    try {
      _defaults = InferenceSettings.forDevice(
        (await DeviceMemory.read())?.totalGb,
      );
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kSettingsKey);
      if (!_alive) return;
      // Review 2026-09-28: every model starts without thinking and
      // the Think pill turns it on per chat. A saved "on" is turned off
      // once; what the user picks afterwards stays.
      final migrate = _prefs!.getBool(_kThinkingOffKey) != true;
      // Request 2026-10-04: each model's recommended sampling now
      // applies unless the user chose otherwise. Legacy saves cannot tell
      // whether a value equal to a default was chosen. Preserve those keys;
      // the user can explicitly return them to recommended inheritance.
      final migrateSampling = _prefs!.getBool(_kSamplingDefaultsKey) != true;
      // Don't clobber state if the user already changed it during load.
      if (!_loaded) {
        var loaded = raw == null
            ? _defaults
            : InferenceSettings.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              );
        if (migrate && loaded.thinkingModeEnabled) {
          loaded = loaded.copyWith(thinkingModeEnabled: false);
          await _prefs!.setString(_kSettingsKey, jsonEncode(loaded.toJson()));
        }
        if (migrateSampling && raw != null) {
          loaded = migrateSamplingDefaults(loaded, _defaults);
          await _prefs!.setString(_kSettingsKey, jsonEncode(loaded.toJson()));
        }
        if (!_loaded) {
          state = loaded;
          DuckDuckGoScraper.preferredRegion = state.searchRegion;
        }
      }
      if (migrate) await _prefs!.setBool(_kThinkingOffKey, true);
      if (migrateSampling) await _prefs!.setBool(_kSamplingDefaultsKey, true);
    } catch (_) {
      if (_alive) {
        ref.read(settingsErrorProvider.notifier).state =
            'Saved settings could not be read. Defaults are active.';
      }
    }
    _loaded = true;
    await _loadKeys();
  }

  /// Keys come from the keystore after the plaintext settings; a keystore
  /// failure leaves the connections usable without their keys.
  Future<void> _loadKeys() async {
    try {
      final keys = await ref.read(remoteKeyStoreProvider).readAll();
      if (!_alive || keys.isEmpty) return;
      state = state.copyWith(remoteApiKeys: {...keys, ...state.remoteApiKeys});
    } catch (_) {
      if (_alive) {
        ref.read(settingsErrorProvider.notifier).state =
            'Saved API keys could not be read from the keystore.';
      }
    }
  }

  /// Stores one connection's key. An empty key removes it.
  Future<void> setRemoteApiKey(String profileId, String key) async {
    final keys = {...state.remoteApiKeys};
    if (key.trim().isEmpty) {
      keys.remove(profileId);
    } else {
      keys[profileId] = key.trim();
    }
    state = state.copyWith(remoteApiKeys: keys);
    _writes = _writes.then((_) async {
      try {
        final store = ref.read(remoteKeyStoreProvider);
        if (key.trim().isEmpty) {
          await store.delete(profileId);
        } else {
          await store.write(profileId, key.trim());
        }
      } catch (_) {
        if (_alive) {
          ref.read(settingsErrorProvider.notifier).state =
              'The API key is active for this session but could not be saved to the keystore.';
        }
      }
    });
    await _writes;
  }

  Future<void> update(InferenceSettings next) async {
    _loaded = true;
    // Keys never go through the JSON round trip: they are not written to
    // plaintext SharedPreferences, only to the keystore.
    final ids = {for (final p in next.remoteProfiles) p.id};
    final orphaned = [
      for (final id in state.remoteApiKeys.keys)
        if (!ids.contains(id)) id,
    ];
    state = InferenceSettings.fromJson(next.toJson()).copyWith(
      remoteApiKeys: {
        for (final e in next.remoteApiKeys.entries)
          if (ids.contains(e.key)) e.key: e.value,
      },
    );
    DuckDuckGoScraper.preferredRegion = state.searchRegion;
    final encoded = jsonEncode(state.toJson());
    _writes = _writes.then((_) async {
      try {
        _prefs ??= await SharedPreferences.getInstance();
        if (!await _prefs!.setString(_kSettingsKey, encoded)) {
          throw StateError('Write failed');
        }
        // A deleted connection takes its key with it.
        for (final id in orphaned) {
          try {
            await ref.read(remoteKeyStoreProvider).delete(id);
          } catch (_) {}
        }
        if (_alive) {
          ref.read(settingsErrorProvider.notifier).state = null;
          ref.read(settingsSavedAtProvider.notifier).state = DateTime.now();
        }
      } catch (_) {
        if (_alive) {
          ref.read(settingsErrorProvider.notifier).state =
              'Settings are active for this session but could not be saved.';
        }
      }
    });
    await _writes;
  }

  Future<void> reset() =>
      update(_defaults.copyWith(explicitOverrides: const {}));

  Future<void> followRecommended(Set<String> keys) {
    final json = state.toJson();
    final defaultsJson = _defaults.toJson();
    for (final key in keys) {
      json[key] = defaultsJson[key];
    }
    json['explicitOverrides'] = state.explicitOverrides
        .difference(keys)
        .toList();
    return update(
      InferenceSettings.fromJson(
        json,
      ).copyWith(remoteApiKeys: state.remoteApiKeys),
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, InferenceSettings>(
  SettingsNotifier.new,
);
final settingsErrorProvider = StateProvider<String?>((ref) => null);

/// When the settings were last written to the phone: settings pages flash
/// "Saved" (report: with no Save button, changes did not look saved).
final settingsSavedAtProvider = StateProvider<DateTime?>((ref) => null);

/// The one-time move off the pre-2026-10-04 defaults (see the settings
/// load). Values the user picked themselves are left alone.
InferenceSettings migrateSamplingDefaults(
  InferenceSettings saved,
  InferenceSettings defaults,
) => saved;

import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/platform/device_info.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../core/platform/desktop_preferences.dart';
import '../../../../data/network/web_search/duckduckgo_scraper.dart';
import '../../data/remote_key_store.dart';
import '../../domain/entities/inference_settings.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

const _kSettingsKey = 'inference_settings_v1';
const _kThinkingOffKey = 'thinking_off_2026_09_28';

/// Where remote API keys live; tests swap in an in-memory store.
final remoteKeyStoreProvider = Provider<RemoteKeyStore>(
  (_) => SecureRemoteKeyStore(),
);

class SettingsNotifier extends Notifier<InferenceSettings> {
  SharedPreferences? _prefs;
  bool _loaded = false;
  InferenceSettings _defaults = const InferenceSettings();
  Map<String, Map<String, String>> _storedHeaders = {};

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
      if (DesktopHost.active) {
        await ref.read(desktopPreferencesProvider.notifier).ready;
      }
      final raw = _prefs!.getString(_kSettingsKey);
      if (!_alive) return;
      // Review 2026-09-28: every model starts without thinking and
      // the Think pill turns it on per chat. A saved "on" is turned off
      // once; what the user picks afterwards stays.
      final migrate = _prefs!.getBool(_kThinkingOffKey) != true;
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
        if (!_loaded) {
          state = loaded;
          DuckDuckGoScraper.preferredRegion = state.searchRegion;
        }
      }
      if (migrate) await _prefs!.setBool(_kThinkingOffKey, true);
    } catch (_) {
      if (_alive) {
        ref.read(settingsErrorProvider.notifier).state = stringsFor(
          state.localeCode,
        ).settingsReadFailed;
      }
    }
    _loaded = true;
    await _loadKeys();
  }

  /// Credentials come from the keystore after the plaintext settings; a
  /// keystore failure leaves the connections usable without them.
  Future<void> _loadKeys() async {
    try {
      final store = ref.read(remoteKeyStoreProvider);
      final keys = await store.readAll();
      final headers = await store.readAllHeaders();
      if (!_alive) return;
      // Older builds wrote header values into the settings JSON; move them
      // to the keystore and remove that plaintext copy.
      final legacy = <String, Map<String, String>>{
        for (final p in state.remoteProfiles)
          if (!headers.containsKey(p.id) && p.headers.isNotEmpty)
            p.id: p.headers,
      };
      final merged = {...legacy, ...headers};
      state = state.copyWith(
        remoteApiKeys: {...keys, ...state.remoteApiKeys},
        remoteHeaders: merged,
        remoteProfiles: [
          for (final p in state.remoteProfiles)
            p.copyWith(headers: merged[p.id] ?? const {}),
        ],
      );
      _storedHeaders = {...headers};
      if (legacy.isEmpty) return;
      var stored = true;
      for (final e in legacy.entries) {
        try {
          await store.writeHeaders(e.key, e.value);
          _storedHeaders[e.key] = e.value;
        } catch (_) {
          stored = false;
        }
      }
      if (!stored) {
        if (_alive) {
          ref.read(settingsErrorProvider.notifier).state = stringsFor(
            state.localeCode,
          ).settingsKeySaveFailed;
        }
        return;
      }
      // Keep the plaintext copy until every value is safely stored.
      if (_prefs != null) {
        await _prefs!.setString(_kSettingsKey, jsonEncode(state.toJson()));
      }
    } catch (_) {
      if (_alive) {
        ref.read(settingsErrorProvider.notifier).state = stringsFor(
          state.localeCode,
        ).settingsKeysReadFailed;
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
          ref.read(settingsErrorProvider.notifier).state = stringsFor(
            state.localeCode,
          ).settingsKeySaveFailed;
        }
      }
    });
    await _writes;
  }

  Future<void> update(InferenceSettings next) async {
    _loaded = true;
    // Credentials never go through the JSON round trip: they are not written
    // to plaintext SharedPreferences, only to the keystore.
    final ids = {for (final p in next.remoteProfiles) p.id};
    final orphaned = {
      for (final id in state.remoteApiKeys.keys)
        if (!ids.contains(id)) id,
      for (final id in state.remoteHeaders.keys)
        if (!ids.contains(id)) id,
    };
    final headers = <String, Map<String, String>>{
      ...state.remoteHeaders,
      for (final p in next.remoteProfiles)
        if (p.headers.isNotEmpty) p.id: p.headers,
      ...next.remoteHeaders,
    }..removeWhere((id, value) => !ids.contains(id) || value.isEmpty);
    final sanitized = InferenceSettings.fromJson(next.toJson());
    state = sanitized.copyWith(
      remoteApiKeys: {
        for (final e in next.remoteApiKeys.entries)
          if (ids.contains(e.key)) e.key: e.value,
      },
      remoteHeaders: headers,
      remoteProfiles: [
        for (final p in sanitized.remoteProfiles)
          p.copyWith(headers: headers[p.id] ?? const {}),
      ],
    );
    DuckDuckGoScraper.preferredRegion = state.searchRegion;
    final encoded = jsonEncode(state.toJson());
    _writes = _writes.then((_) async {
      try {
        final store = ref.read(remoteKeyStoreProvider);
        // Store header values before rewriting the settings without them, so
        // a keystore failure leaves the previous file intact.
        for (final e in headers.entries) {
          if (_sameHeaders(_storedHeaders[e.key], e.value)) continue;
          await store.writeHeaders(e.key, e.value);
          _storedHeaders[e.key] = e.value;
        }
        for (final id in _storedHeaders.keys.toList()) {
          if (headers.containsKey(id)) continue;
          await store.deleteHeaders(id);
          _storedHeaders.remove(id);
        }
        _prefs ??= await SharedPreferences.getInstance();
        if (!await _prefs!.setString(_kSettingsKey, encoded)) {
          throw StateError('Write failed');
        }
        // A deleted connection takes its key and header values with it.
        for (final id in orphaned) {
          try {
            await store.delete(id);
          } catch (e, st) {
            quietFailure('settings_provider:224', e, st);
          }
          try {
            await store.deleteHeaders(id);
          } catch (e, st) {
            quietFailure('settings_provider:227', e, st);
          }
        }
        if (_alive) {
          ref.read(settingsErrorProvider.notifier).state = null;
          ref.read(settingsSavedAtProvider.notifier).state = DateTime.now();
        }
      } catch (_) {
        if (_alive) {
          ref.read(settingsErrorProvider.notifier).state = stringsFor(
            state.localeCode,
          ).settingsSaveFailed;
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
      InferenceSettings.fromJson(json).copyWith(
        remoteApiKeys: state.remoteApiKeys,
        remoteHeaders: state.remoteHeaders,
      ),
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

bool _sameHeaders(Map<String, String>? a, Map<String, String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

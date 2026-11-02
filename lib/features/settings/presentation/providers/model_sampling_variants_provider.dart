import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/prefs_rescue.dart';
import '../../domain/model_sampling_keys.dart';
import '../../domain/settings_scope.dart';
import 'model_profiles_provider.dart';

const _key = 'model_sampling_variants_v1';

Map<String, dynamic> modelSamplingValues(Map<String, dynamic> profile) => {
  for (final e in SettingsResolver.sanitize(profile).entries)
    if (desktopSamplingKeys.contains(e.key)) e.key: e.value,
};

class ModelSamplingVariant {
  final String name;
  final Map<String, dynamic> values;
  ModelSamplingVariant(this.name, Map<String, dynamic> values)
    : values = Map.unmodifiable(modelSamplingValues(values));
}

class ModelSamplingVariants {
  final List<ModelSamplingVariant> variants;
  final String? active;
  const ModelSamplingVariants({this.variants = const [], this.active});

  ModelSamplingVariant? get selected =>
      variants.where((v) => v.name == active).firstOrNull;

  bool modified(Map<String, dynamic> profile) =>
      selected != null &&
      !mapEquals(selected!.values, modelSamplingValues(profile));
}

class ModelSamplingVariantsNotifier
    extends Notifier<Map<String, ModelSamplingVariants>> {
  late Future<void> ready;
  SharedPreferences? _prefs;
  Future<void> _writes = Future.value();
  bool _alive = true;

  @override
  Map<String, ModelSamplingVariants> build() {
    ref.onDispose(() => _alive = false);
    ready = _load();
    return {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map;
      final next = <String, ModelSamplingVariants>{};
      for (final e in data.entries) {
        final entry = e.value as Map;
        final variants = <ModelSamplingVariant>[];
        for (final v in entry['variants'] as List) {
          final name = (v['name'] as String).trim();
          if (name.isEmpty || variants.any((x) => x.name == name)) continue;
          variants.add(
            ModelSamplingVariant(
              name,
              Map<String, dynamic>.from(v['values'] as Map),
            ),
          );
        }
        final active = entry['active'] as String?;
        next[e.key as String] = ModelSamplingVariants(
          variants: List.unmodifiable(variants),
          active: variants.any((v) => v.name == active) ? active : null,
        );
      }
      if (_alive) state = next;
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _key);
    }
  }

  ModelSamplingVariants of(String id) =>
      state[id] ?? const ModelSamplingVariants();

  Future<void> _put(String id, ModelSamplingVariants value) async {
    state = {...state, id: value};
    final raw = jsonEncode({
      for (final e in state.entries)
        e.key: {
          'active': e.value.active,
          'variants': [
            for (final v in e.value.variants)
              {'name': v.name, 'values': v.values},
          ],
        },
    });
    _writes = _writes
        .then((_) async {
          _prefs ??= await SharedPreferences.getInstance();
          if (!await _prefs!.setString(_key, raw)) {
            throw StateError('Could not save model sampling variants');
          }
        })
        .catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'model sampling variants',
              context: ErrorDescription('while saving model sampling variants'),
            ),
          );
        });
    await _writes;
  }

  Future<void> save(
    String id,
    String name, {
    Map<String, dynamic>? values,
  }) async {
    await ready;
    await ref.read(modelProfilesProvider.notifier).ready;
    name = name.trim();
    if (name.isEmpty || of(id).variants.any((v) => v.name == name)) return;
    await _put(
      id,
      ModelSamplingVariants(
        variants: List.unmodifiable([
          ...of(id).variants,
          ModelSamplingVariant(
            name,
            values ?? ref.read(modelProfilesProvider.notifier).of(id),
          ),
        ]),
        active: name,
      ),
    );
  }

  Future<void> activate(String id, String? name) async {
    await ready;
    final profiles = ref.read(modelProfilesProvider.notifier);
    await profiles.ready;
    final value = of(id);
    final variant = value.variants.where((v) => v.name == name).firstOrNull;
    if (name != null && variant == null) return;
    await profiles.set(id, {
      for (final e in profiles.of(id).entries)
        if (!desktopSamplingKeys.contains(e.key)) e.key: e.value,
      ...?variant?.values,
    });
    await _put(
      id,
      ModelSamplingVariants(variants: value.variants, active: name),
    );
  }

  Future<void> rename(String id, String name, String next) async {
    await ready;
    next = next.trim();
    final value = of(id);
    if (next.isEmpty || value.variants.any((v) => v.name == next)) return;
    await _put(
      id,
      ModelSamplingVariants(
        variants: List.unmodifiable([
          for (final v in value.variants)
            v.name == name ? ModelSamplingVariant(next, v.values) : v,
        ]),
        active: value.active == name ? next : value.active,
      ),
    );
  }

  Future<void> update(
    String id,
    String name, {
    Map<String, dynamic>? values,
  }) async {
    await ready;
    final profiles = ref.read(modelProfilesProvider.notifier);
    await profiles.ready;
    final value = of(id);
    await _put(
      id,
      ModelSamplingVariants(
        variants: List.unmodifiable([
          for (final v in value.variants)
            v.name == name
                ? ModelSamplingVariant(name, values ?? profiles.of(id))
                : v,
        ]),
        active: value.active,
      ),
    );
  }

  Future<void> delete(String id, String name) async {
    await ready;
    final value = of(id);
    await _put(
      id,
      ModelSamplingVariants(
        variants: List.unmodifiable(
          value.variants.where((v) => v.name != name),
        ),
        active: value.active == name ? null : value.active,
      ),
    );
  }
}

final modelSamplingVariantsProvider =
    NotifierProvider<
      ModelSamplingVariantsNotifier,
      Map<String, ModelSamplingVariants>
    >(ModelSamplingVariantsNotifier.new);

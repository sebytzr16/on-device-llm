import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  test('every load setting has a typed editor and reload rule', () {
    final keys = SettingSpec.all.map((s) => s.key).toSet();
    expect(keys.length, SettingSpec.all.length);
    expect(InferenceSettings.loadTimeKeys.difference(keys), isEmpty);
    final defaults = const InferenceSettings().toJson();
    for (final spec in SettingSpec.all) {
      expect(defaults.containsKey(spec.key), true, reason: spec.key);
      expect(spec.coerce(defaults[spec.key]), isNotNull, reason: spec.key);
    }
  });
  test('a LiteRT profile offers only the controls the runtime honours', () {
    // LiteRT-LM's sampler takes temperature, topK and topP: llama.cpp's
    // Min-P, Typical-P, penalties, seed and stop sequences are ignored there
    // and must not be offered for a .litertlm model.
    for (final key in [
      'minP',
      'typicalP',
      'presencePenalty',
      'seed',
      'stopSequences',
    ]) {
      expect(SettingSpec.byKey(key)!.availableForLiteRt, isFalse, reason: key);
    }
    for (final key in ['temperature', 'topK', 'topP', 'maxTokens']) {
      expect(SettingSpec.byKey(key)!.availableForLiteRt, isTrue, reason: key);
    }
    // The backend is a per-model choice, not a global setting, but it is the
    // one hardware control a LiteRT model keeps.
    final backend = SettingSpec.byKey('liteRtBackend')!;
    expect(backend.modelOnly, isTrue);
    expect(backend.availableForLiteRt, isTrue);
    expect(
      SettingSpec.visible.map((s) => s.key),
      isNot(contains('liteRtBackend')),
    );
  });
  test('global model reset preserves privacy and session credentials', () {
    const current = InferenceSettings(
      memoryEnabled: true,
      voiceOnDeviceOnly: true,
      remoteApiKeys: {'test': 'private'},
      temperature: 1.8,
    );
    final value = SettingsResolver.editGlobal(current, {
      'temperature': 0.3,
      'memoryEnabled': false,
      'remoteApiKeys': {},
    }, resetMissingTo: const InferenceSettings());
    expect(value.temperature, .3);
    expect(value.memoryEnabled, true);
    expect(value.voiceOnDeviceOnly, true);
    expect(value.remoteApiKeys, {'test': 'private'});
  });
  test('global reset leaves settings the page does not expose alone', () {
    const current = InferenceSettings(
      temperature: 1.7,
      webMode: WebMode.always,
      explicitOverrides: {'temperature', 'webMode'},
    );
    final value = SettingsResolver.editGlobal(
      current,
      {'maxTokens': 2048},
      resetMissingTo: const InferenceSettings(),
      // What the global page exposes: not per-model sampling.
      resets: (spec) => spec.available && !spec.perModel,
    );
    expect(value.maxTokens, 2048);
    // Hidden per-model sampling keeps its value and explicit marker.
    expect(value.temperature, 1.7);
    expect(value.explicitOverrides, contains('temperature'));
    // A setting the page does expose is reset to the default.
    expect(value.webMode, WebMode.off);
    expect(value.explicitOverrides, isNot(contains('webMode')));
  });

  test('project defaults have their own origin and chat can opt out', () {
    final project = SettingsResolver.resolve(
      global: const InferenceSettings(knowledgeCollection: 'global'),
      project: {'knowledgeCollection': 'project', 'memoryEnabled': true},
    );
    expect(project.effective.knowledgeCollection, 'project');
    expect(project.originOf('knowledgeCollection'), 'project');
    expect(project.effective.memoryEnabled, false);
    final chat = SettingsResolver.resolve(
      global: const InferenceSettings(),
      project: {'knowledgeCollection': 'project'},
      chat: {'knowledgeCollection': ''},
    );
    expect(chat.effective.knowledgeCollection, '');
    expect(chat.originOf('knowledgeCollection'), 'chat');
  });
  test(
    'untrusted nonfinite override numbers are rejected without throwing',
    () {
      expect(SettingSpec.byKey('temperature')!.coerce(double.nan), isNull);
      expect(SettingSpec.byKey('topK')!.coerce(double.infinity), isNull);
      expect(SettingSpec.byKey('temperature')!.coerce('NaN'), isNull);
    },
  );
}

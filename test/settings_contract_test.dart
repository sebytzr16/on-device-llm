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

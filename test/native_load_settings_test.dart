import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  const values = <String, dynamic>{
    'useMmap': false,
    'useMlock': true,
    'mainGpu': 1,
    'splitMode': 'row',
    'offloadKv': false,
    'swaFull': true,
    'nCpuMoe': 4,
    'expertsUsed': 4,
    'draftGpuLayers': 99,
    'keepTokens': 16,
    'contextOverflow': 'shift',
    'logitBias': {'42': -3.5},
  };
  test('native settings persist and reach load and estimate configuration', () {
    DesktopHost.active = true;
    addTearDown(() => DesktopHost.active = false);
    final s = InferenceSettings.fromJson(values);
    final copied = s.copyWith(
      useMmap: false,
      useMlock: true,
      mainGpu: 1,
      splitMode: 'row',
      offloadKv: false,
      swaFull: true,
      nCpuMoe: 4,
      expertsUsed: 4,
      draftGpuLayers: 99,
      keepTokens: 16,
      contextOverflow: 'shift',
      logitBias: {'42': -3.5},
    );
    final config = jsonDecode(LlamaEngine.loadConfig(settings: copied)) as Map;
    for (final e in values.entries) {
      expect(s.toJson()[e.key], e.value, reason: e.key);
      expect(copied.explicitOverrides, contains(e.key));
      if (const {
        'keepTokens',
        'contextOverflow',
        'logitBias',
      }.contains(e.key)) {
        expect(config.containsKey(e.key), isFalse, reason: e.key);
      } else {
        expect(config[e.key], e.value, reason: e.key);
      }
    }
    expect(SettingsResolver.sanitize(values), values);
  });
  test('native settings keep legacy defaults and validate untrusted data', () {
    final s = InferenceSettings.fromJson({});
    expect(s.useMmap, true);
    expect(s.useMlock, false);
    expect(s.mainGpu, 0);
    expect(s.splitMode, 'layer');
    expect(s.offloadKv, true);
    expect(s.swaFull, false);
    expect(s.nCpuMoe, -1);
    expect(s.expertsUsed, -1);
    expect(s.draftGpuLayers, 0);
    expect(s.keepTokens, 0);
    expect(s.contextOverflow, 'trim');
    expect(s.logitBias, isEmpty);
    final bad = InferenceSettings.fromJson({
      'splitMode': 'bad',
      'contextOverflow': 'bad',
      'nCpuMoe': -9,
      'expertsUsed': -9,
      'draftGpuLayers': -3,
      'keepTokens': -5,
      'logitBias': {'-1': 2, 'bad': 1, '1': double.nan, '42': 2},
    });
    expect(bad.splitMode, 'layer');
    expect(bad.contextOverflow, 'trim');
    expect(bad.nCpuMoe, -1);
    expect(bad.expertsUsed, -1);
    expect(bad.draftGpuLayers, 0);
    expect(bad.keepTokens, 0);
    expect(bad.logitBias, {'42': 2.0});
    expect(SettingSpec.byKey('logitBias')!.coerce('{"42":-1}'), {'42': -1.0});
    expect(SettingSpec.byKey('logitBias')!.coerce('{'), isNull);
  });
  test('desktop settings are hidden from phone editors', () {
    addTearDown(() => DesktopHost.active = false);
    DesktopHost.active = false;
    expect(
      SettingSpec.visible
          .map((s) => s.key)
          .toSet()
          .intersection(values.keys.toSet()),
      isEmpty,
    );
    DesktopHost.active = true;
    expect(SettingSpec.visible.map((s) => s.key), containsAll(values.keys));
    for (final key in values.keys.take(7)) {
      expect(SettingSpec.byKey(key)!.reloadRequired, isTrue, reason: key);
    }
  });
}

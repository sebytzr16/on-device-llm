import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/tools/presentation/tools_quick_panel.dart';

void main() {
  test('memory recall and phone actions are switches that persist', () {
    const s = InferenceSettings();
    expect(s.toolMemory, isTrue);
    expect(s.toolActions, isTrue);
    final off = s.copyWith(toolMemory: false, toolActions: false);
    final back = InferenceSettings.fromJson(off.toJson());
    expect(back.toolMemory, isFalse);
    expect(back.toolActions, isFalse);
    for (final key in ['toolMemory', 'toolActions']) {
      expect(SettingSpec.all.any((spec) => spec.key == key), isTrue);
    }
  });

  test('the web tool switch is the globe switch', () {
    const s = InferenceSettings();
    expect(webModeFor(s, false), WebMode.off);
    expect(webModeFor(s.copyWith(webMode: WebMode.off), true), WebMode.auto);
    expect(
      webModeFor(s.copyWith(webMode: WebMode.always), true),
      WebMode.always,
    );
  });
}

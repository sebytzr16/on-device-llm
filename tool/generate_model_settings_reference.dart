import 'dart:io';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';

void main() {
  final defaults = const InferenceSettings().toJson();
  String cell(Object? value) =>
      '$value'.replaceAll('|', '\\|').replaceAll('\n', ' ');
  final out = StringBuffer(
    '# Model settings contract\n\nGenerated from `SettingSpec.all` by `dart run tool/generate_model_settings_reference.dart`.\n\nThe global inference editor, model/preset/chat editors, override validation and this reference use the same registry. Privacy, appearance, voice and remote credentials have separate global controls and cannot be changed by a model/preset/chat override.\n\nCascade: app defaults → phone defaults → the model’s recommended sampling (its model card, Hugging Face `generation_config.json`, the GGUF’s `general.sampling.*` keys) → user → model → preset → project → chat → turn. Project instructions join the system prompt; project knowledge defaults can be overridden by the chat.\n\n| Key | Label | Type | Default | Bounds/choices | Reload |\n| --- | --- | --- | --- | --- | --- |\n',
  );
  for (final spec in SettingSpec.all) {
    final limits = spec.options.isNotEmpty
        ? spec.options.join(', ')
        : spec.min == null
        ? ''
        : '${spec.min} … ${spec.max}';
    out.writeln(
      '| `${spec.key}` | ${cell(spec.label)} | ${spec.kind.name} | ${cell(defaults[spec.key])} | ${cell(limits)} | ${spec.reloadRequired ? 'yes' : 'no'} |',
    );
  }
  File('docs/model-settings-reference.md').writeAsStringSync(out.toString());
}

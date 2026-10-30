import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/logging/developer_logs.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

void main() {
  test('phone effective settings reject desktop values from every layer', () {
    DesktopHost.active = false;
    addTearDown(() => DesktopHost.active = false);
    const overrides = <String, dynamic>{
      'cpuVariant': 'compat',
      'vramReserveMb': 4096,
      'mtp': true,
      'chatTemplate': 'custom',
      'promptStoreMb': 1024,
      'useMmap': false,
      'useMlock': true,
      'mainGpu': 2,
      'splitMode': 'row',
      'offloadKv': false,
      'swaFull': true,
      'nCpuMoe': 4,
      'expertsUsed': 4,
      'projectorDevice': 'cpu',
      'draftGpuLayers': 10,
      'keepTokens': 16,
      'contextOverflow': 'shift',
      'logitBias': {'42': -3},
      'draftMinP': 0.5,
      'temperature': 0.2,
    };
    expect(SettingsResolver.sanitize(overrides), {'temperature': 0.2});
    final saved = InferenceSettings.fromJson(overrides);
    final defaults = const InferenceSettings().toJson();
    final resolved = SettingsResolver.resolve(
      global: saved,
      deviceDefaults: saved,
      recommended: overrides,
      recommendedThinking: overrides,
      model: overrides,
      preset: overrides,
      project: overrides,
      chat: overrides,
      turn: overrides,
    );
    final json = resolved.effective.toJson();
    for (final spec in SettingSpec.all.where((s) => s.desktopOnly)) {
      expect(overrides, contains(spec.key), reason: spec.key);
      expect(json[spec.key], defaults[spec.key], reason: spec.key);
      expect(resolved.originOf(spec.key), SettingsLayer.idDefault);
      expect(resolved.requested.containsKey(spec.key), isFalse);
    }
    expect(resolved.effective.temperature, 0.2);
    DesktopHost.active = true;
    expect(SettingsResolver.sanitize(overrides), overrides);
    expect(SettingsResolver.resolve(global: saved).effective.mtp, isTrue);
    expect(
      SettingsResolver.resolve(global: saved).effective.promptStoreMb,
      1024,
    );
  });

  test('generation-only settings do not change load identity', () {
    const settings = InferenceSettings();
    final changed = settings.copyWith(
      keepTokens: 16,
      contextOverflow: 'shift',
      logitBias: {'42': -3},
    );
    expect(
      LlamaEngine.loadConfig(settings: changed),
      LlamaEngine.loadConfig(settings: settings),
    );
    expect(changed.toJson()['keepTokens'], 16);
    expect(changed.toJson()['contextOverflow'], 'shift');
    expect(changed.toJson()['logitBias'], {'42': -3.0});
    expect(
      LlamaEngine.loadConfig(settings: settings.copyWith(contextSize: 2048)),
      isNot(LlamaEngine.loadConfig(settings: settings)),
    );
  });

  test(
    'load errors keep native messages and explain unknown architectures',
    () {
      const message = 'Cannot load this GGUF. It may be incomplete.';
      expect(modelLoadErrorMessage(StateError(message)), message);
      expect(
        ModelLoadException(
          modelLoadErrorMessage(StateError(message)),
        ).toString(),
        message,
      );
      expect(modelLoadErrorMessage(const ModelLoadException(message)), message);
      for (final message in [
        'unknown model architecture: lfm3',
        'Unsupported model architecture lfm3',
        'Unknown architecture: lfm3',
      ]) {
        expect(
          modelLoadErrorMessage(message),
          'The engine does not support this model yet.',
        );
      }
    },
  );

  test(
    'ring stays ordered, read-only and notifies once per multiline record',
    () {
      final buffer = DeveloperLogBuffer();
      addTearDown(buffer.dispose);
      var notifications = 0;
      buffer.addListener(() => notifications++);
      for (var i = 0; i < 2005; i++) {
        buffer.record(LogRecord(Level.INFO, '$i', 'test'));
      }
      expect(
        buffer.entries.map((e) => e.message),
        List.generate(2000, (i) => '${i + 5}'),
      );
      final paused = List.of(buffer.entries);
      buffer.record(LogRecord(Level.WARNING, 'one\ntwo\nthree', 'test'));
      expect(notifications, 2006);
      expect(buffer.entries.length, 2000);
      expect(buffer.entries.first.message, '8');
      expect(buffer.entries.last.message, 'three');
      expect(() => buffer.entries.clear(), throwsUnsupportedError);
      buffer.clear();
      expect(buffer.entries, isEmpty);
      expect(paused.first.message, '5');
      buffer.record(LogRecord(Level.INFO, 'new', 'test'));
      expect(buffer.entries.single.message, 'new');
    },
  );

  test('Riverpod publishes changes while the ring mutates in place', () {
    developerLogBuffer.clear();
    addTearDown(developerLogBuffer.clear);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var updates = 0;
    final subscription = container.listen(
      developerLogsProvider,
      (_, _) => updates++,
    );
    addTearDown(subscription.close);
    developerLogBuffer.record(LogRecord(Level.INFO, 'new', 'test'));
    expect(updates, 1);
    expect(container.read(developerLogsProvider).single.message, 'new');
    developerLogBuffer.clear();
    expect(updates, 2);
    expect(container.read(developerLogsProvider), isEmpty);
  });
}

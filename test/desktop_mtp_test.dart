import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/load_settings_dialog.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/presentation/setting_labels.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'advanced_pages_2_test.dart' show TestSettings, TestModels, testModel;

class _Engine extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> adapterInfo(String path) async => {'keys': {}};

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => {'layers': 24, 'contextTrain': 4096};
}

void main() {
  test(
    'MTP import preserves same-name files of different size or hash',
    () async {
      final dir = await Directory.systemTemp.createTemp('mtp-import-');
      addTearDown(() => dir.delete(recursive: true));
      final destination = await Directory('${dir.path}/models').create();
      final source = File('${dir.path}/head.gguf');
      await source.writeAsString('first');
      final first = await importMtpHead(
        source.path,
        destination.path,
        'mtp-head.gguf',
      );
      expect(
        await importMtpHead(source.path, destination.path, 'mtp-head.gguf'),
        first,
      );
      await source.writeAsString('other'); // same size, different hash
      final second = await importMtpHead(
        source.path,
        destination.path,
        'mtp-head.gguf',
      );
      expect(second, isNot(first));
      expect(await File(first).readAsString(), 'first');
      expect(await File(second).readAsString(), 'other');
      await source.writeAsString('larger head');
      final third = await importMtpHead(
        source.path,
        destination.path,
        'mtp-head.gguf',
      );
      expect(third, isNot(first));
      expect(third, isNot(second));
    },
  );

  setUp(() => DesktopHost.active = true);
  tearDown(() => DesktopHost.active = false);
  test('MTP defaults off, persists and reaches the native load config', () {
    expect(const InferenceSettings().mtp, isFalse);
    expect(InferenceSettings.fromJson({}).mtp, isFalse);
    final chosen = const InferenceSettings().copyWith(mtp: true);
    final saved = InferenceSettings.fromJson(chosen.toJson());
    expect(saved.mtp, isTrue);
    expect(saved.explicitOverrides, contains('mtp'));
    expect(SettingSpec.byKey('mtp')!.reloadRequired, isTrue);
    expect(
      SettingSpec.byKey('mtp')!.labelIn(AppLocalizationsEn()),
      AppLocalizationsEn().desktopMtpLabel,
    );
    final resolved = SettingsResolver.resolve(
      global: saved,
      model: {'mtp': false},
    );
    expect(resolved.effective.mtp, isFalse);
    expect(resolved.reloadKeys, contains('mtp'));
    expect(jsonDecode(LlamaEngine.loadConfig(settings: saved))['mtp'], isTrue);
    expect(
      jsonDecode(LlamaEngine.loadConfig(settings: resolved.effective))['mtp'],
      isFalse,
    );
  });

  test('MTP head files are recognised by name, hub prefix or not', () {
    // Built with the host's separator: on Linux a backslash is part of the name.
    expect(isMtpHeadFile(p.join('m', 'mtp-gemma-4-E4B-it-Q8_0.gguf')), isTrue);
    expect(isMtpHeadFile('/m/0123456789abcdef-MTP-gemma.gguf'), isTrue);
    expect(isMtpHeadFile('/m/gemma-4-E4B-mtp.gguf'), isFalse);
    expect(isMtpHeadFile('/m/mtp-notes.txt'), isFalse);
  });

  testWidgets('MTP switch saves, reopens and resets with the model profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        llamaEngineProvider.overrideWithValue(_Engine()),
        llamaEstimatorProvider.overrideWithValue(_Engine()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelProfilesProvider.notifier).ready;
    await container.read(modelProfilesProvider.notifier).set('test', {
      'nGpuLayers': 64,
    });
    final t = AppLocalizationsEn();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDesktopLoadSettings(context, testModel),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    final toggle = find.byKey(const Key('desktop-mtp'));
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        toggle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    await open();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.byKey(const Key('desktop-mtp-head')), findsOneWidget);
    expect(find.text(t.desktopMtpHeadAutoNone), findsOneWidget);
    expect(find.text(t.desktopMtpHeadTokens), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(container.read(modelProfilesProvider)['test']?['mtp'], isTrue);
    // Every layer stays "all" (999), so the engine may move the projector.
    expect(container.read(modelProfilesProvider)['test']?['nGpuLayers'], 999);
    await open();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(find.text(t.desktopLoadSettingsReset));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(
      container.read(modelProfilesProvider)['test'],
      isNot(contains('mtp')),
    );
  });
}

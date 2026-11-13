import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/load_settings_dialog.dart';
import 'package:ondevice_llm/desktop/pc_optimization.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestSettings, TestModels, testModel;

class _Engine extends LlamaEngine {
  final bool supported;
  final requests = <({String mode, String? draft})>[];
  _Engine(this.supported);

  @override
  Future<Map<String, dynamic>> probe() async => {
    if (supported) 'supportsDFlash': true,
  };

  @override
  Future<Map<String, dynamic>> adapterInfo(String path) async => {'keys': {}};

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    requests.add((mode: settings.speculationMode, draft: draftModelPath));
    return {'layers': 24, 'contextTrain': 4096};
  }
}

class _Models extends TestModels {
  @override
  Future<String?> draftPathFor(ModelInfo info, String draftModelId) async =>
      draftModelId == 'draft' ? 'draft.gguf' : null;
}

void main() {
  setUp(() => DesktopHost.active = true);
  tearDown(() => DesktopHost.active = false);

  for (final mode in ['off', 'mtp', 'draft', 'dflash']) {
    test(
      '$mode survives profile resolution and reaches load/estimate JSON',
      () {
        final profile = SettingsResolver.sanitize({
          'speculationMode': mode,
          'draftModelId': 'draft:local.gguf',
        });
        final settings = InferenceSettings.fromJson(
          profile,
        ).copyWith(mtp: true);
        expect(settings.copyWith().toJson()['speculationMode'], mode);
        expect(settings.explicitOverrides, contains('speculationMode'));
        expect(SettingSpec.byKey('speculationMode')!.reloadRequired, isTrue);
        final config =
            jsonDecode(
                  LlamaEngine.loadConfig(
                    settings: settings,
                    draftModelPath: 'local.gguf',
                  ),
                )
                as Map;
        expect(config['speculationMode'], mode);
        expect(config['draftModel'], mode == 'off' ? '' : 'local.gguf');
        expect(config['mtp'], mode == 'mtp');
      },
    );
  }

  test(
    'legacy profiles retain Auto and malformed modes cannot reach native',
    () {
      expect(const InferenceSettings().speculationMode, 'auto');
      expect(InferenceSettings.fromJson({'mtp': true}).speculationMode, 'auto');
      expect(
        InferenceSettings.fromJson({
          'speculationMode': 'bogus',
        }).speculationMode,
        'auto',
      );
      DesktopHost.active = false;
      expect(SettingsResolver.sanitize({'speculationMode': 'dflash'}), isEmpty);
    },
  );

  test('profile sanitization preserves long Windows draft paths', () {
    final path = 'draft:C:/${List.filled(40, 'models').join('/')}/draft.gguf';
    expect(path.length, greaterThan(200));
    final profile = SettingsResolver.sanitize({'draftModelId': path});
    expect(InferenceSettings.fromJson(profile).draftModelId, path);
  });

  test('helpers disable an inherited explicit draft mode', () {
    const settings = InferenceSettings(
      speculationMode: 'dflash',
      draftModelId: 'draft:local.gguf',
    );
    expect(settings.forAgent().speculationMode, 'off');
    expect(settings.forAgent().draftModelId, isEmpty);
    final setups = pcOptimizationSetups(settings, mtpHead: true);
    expect(setups[1].speculationMode, 'off');
    expect(pcOptimizationKeys, contains('speculationMode'));
  });

  test(
    'DFlash identity comes from the GGUF architecture, including fork files',
    () async {
      final dir = await Directory.systemTemp.createTemp('draft-metadata-');
      addTearDown(() => dir.delete(recursive: true));
      for (final arch in ['dflash', 'dflash-draft', 'qwen35']) {
        final out = BytesBuilder();
        void u32(int n) => out.add(
          (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List(),
        );
        void u64(int n) => out.add(
          (ByteData(8)..setUint64(0, n, Endian.little)).buffer.asUint8List(),
        );
        void string(String value) {
          final bytes = utf8.encode(value);
          u64(bytes.length);
          out.add(bytes);
        }

        out.add(ascii.encode('GGUF'));
        u32(3);
        u64(0);
        u64(1);
        string('general.architecture');
        u32(8);
        string(arch);
        final file = File('${dir.path}/$arch.gguf');
        await file.writeAsBytes(out.takeBytes());
        final metadata = await GgufMetadata.inspect(file.path);
        expect(metadata.isDFlash, arch != 'qwen35');
        expect(metadata.isMtpOnly, isFalse);
      }
    },
  );

  test(
    'external draft paths resolve and reject the target or a missing file',
    () async {
      final dir = await Directory.systemTemp.createTemp('draft-selection-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File(
        '${dir.path}/draft.gguf',
      ).writeAsString('fixture');
      final container = ProviderContainer(
        overrides: [modelManagerProvider.overrideWith(TestModels.new)],
      );
      addTearDown(container.dispose);
      final manager = container.read(modelManagerProvider.notifier);
      expect(
        await manager.draftPathFor(testModel, 'draft:${file.path}'),
        file.path,
      );
      expect(await manager.draftPathFor(testModel, 'draft:test.gguf'), isNull);
      expect(
        await manager.draftPathFor(testModel, 'draft:missing.gguf'),
        isNull,
      );
    },
  );

  test('native validation codes have translated user messages', () {
    addTearDown(() => appLanguageCode = '');
    for (final lang in ['en', 'fr', 'es']) {
      appLanguageCode = lang;
      final t = stringsFor(lang);
      expect(modelLoadErrorMessage('OD_DFLASH_FORMAT'), t.desktopDFlashConvert);
      expect(modelLoadErrorMessage('OD_SPEC_MODE'), t.desktopDraftModeMismatch);
      expect(
        modelLoadErrorMessage('OD_DFLASH_UNAVAILABLE'),
        t.desktopDFlashUnavailable,
      );
      expect(
        modelLoadErrorMessage('OD_DFLASH_METADATA'),
        t.desktopDFlashInvalid,
      );
    }
  });

  for (final supported in [false, true]) {
    testWidgets(
      'desktop drafts reach estimates; DFlash capability=$supported',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        // Speculation settings are desktop-only (setting_specs).
        DesktopHost.active = true;
        addTearDown(() => DesktopHost.active = false);
        tester.view.physicalSize = const Size(1400, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final engine = _Engine(supported);
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(TestSettings.new),
            modelManagerProvider.overrideWith(_Models.new),
            llamaEngineProvider.overrideWithValue(engine),
            llamaEstimatorProvider.overrideWithValue(engine),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: DesktopTheme.of(AccentChoice.amber, dark: true),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        showDesktopLoadSettings(context, testModel),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final selector = find.byKey(const Key('desktop-speculation-mode'));
        await tester.scrollUntilVisible(
          selector,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Changes re-measure after a 350 ms debounce.
        Future<void> settle() async {
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
        }

        DropdownButton<String> mode() =>
            tester.widget<DropdownButton<String>>(selector);
        expect(
          mode().items!.singleWhere((i) => i.value == 'dflash').enabled,
          supported,
        );
        mode().onChanged!('draft');
        await settle();
        final picker = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('desktop-draft-model-mtp:off')),
        );
        picker.onChanged!('draft');
        await settle();
        expect(engine.requests.last, (mode: 'draft', draft: 'draft.gguf'));
        mode().onChanged!('off');
        await settle();
        expect(engine.requests.last, (mode: 'off', draft: null));
        if (supported) {
          mode().onChanged!('dflash');
          await settle();
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byKey(const Key('desktop-draft-model-mtp:off')),
              )
              .onChanged!('draft');
          await settle();
          expect(engine.requests.last, (mode: 'dflash', draft: 'draft.gguf'));
        }
        await tester.tap(find.text(AppLocalizationsEn().save));
        await tester.pumpAndSettle();
        expect(
          container.read(modelProfilesProvider)['test']?['speculationMode'],
          supported ? 'dflash' : 'off',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

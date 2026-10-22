import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/advanced_pages_2.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/effective_settings_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/overrides_page.dart';
import 'package:ondevice_llm/features/tools/presentation/tools_quick_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testModel = ModelInfo(
  id: 'test',
  displayName: 'Test Model',
  fileName: 'test.gguf',
  sizeBytes: 100,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'test.gguf',
);
const draftModel = ModelInfo(
  id: 'draft',
  displayName: 'Draft Model',
  fileName: 'draft.gguf',
  sizeBytes: 50,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q8_0,
  isDownloaded: true,
  localPath: 'draft.gguf',
);

class TestSettings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings();
  }

  @override
  Future<void> update(InferenceSettings next) async {
    state = next;
  }
}

class GbnfSettings extends TestSettings {
  @override
  InferenceSettings build() =>
      super.build().copyWith(responseFormat: ResponseFormat.gbnf);
}

class TestModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(
      catalog: [testModel, draftModel],
      loadedModelId: 'test',
    );
  }
}

Widget harness(Widget home, {ThemeData? theme}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(TestSettings.new),
    modelManagerProvider.overrideWith(TestModels.new),
  ],
  child: MaterialApp(theme: theme ?? AppTheme.dark, home: home),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sampling extras: seed, stop sequences and the sampler order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(const SamplingExtrasPage()));
    await tester.pump();
    expect(find.text('Random every answer'), findsOneWidget);
    expect(find.byKey(const Key('seed-row')), findsOneWidget);
    await tester.tap(find.byKey(const Key('stop-sequences-row')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '###\nEND');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('"###", "END"'), findsOneWidget);
    final order = find.byKey(const Key('sampler-order'));
    expect(order, findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Top-K'), findsOneWidget);
  });

  testWidgets('memory/RoPE page renders cache, RoPE and draft controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(const MemoryRopePage()));
    await tester.pump();
    expect(find.text('Same as K'), findsOneWidget);
    expect(find.text('Model default'), findsOneWidget);
    // YaRN rows appear only once YaRN is chosen.
    expect(find.text('YaRN original context'), findsNothing);
  });

  testWidgets('structured output page reports a missing grammar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(GbnfSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const StructuredOutputPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('GBNF grammar'), findsWidgets);
    expect(find.textContaining('No grammar set'), findsOneWidget);
    expect(find.byKey(const Key('grammar-row')), findsOneWidget);
  });

  testWidgets('tools page explains gates and toggles the switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(const ToolsPage()));
    await tester.pump();
    expect(find.textContaining('Needs web research on'), findsOneWidget);
    expect(find.textContaining('Needs a knowledge collection'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tools-enabled')));
    await tester.pump();
    final s = tester.widget<SwitchListTile>(
      find.byKey(const Key('tools-enabled')),
    );
    expect(s.value, isTrue);
  });

  testWidgets('tools quick panel toggles tools from the composer sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: SingleChildScrollView(child: ToolsQuickPanel())),
      ),
    );
    await tester.pump();
    // Off by default: only the master switch shows.
    expect(find.byKey(const Key('quick-tools-enabled')), findsOneWidget);
    expect(find.byKey(const Key('quick-tool-web')), findsNothing);
    await tester.tap(find.byKey(const Key('quick-tools-enabled')));
    await tester.pump();
    expect(find.byKey(const Key('quick-tool-calculator')), findsOneWidget);
    expect(find.byKey(const Key('quick-tool-web')), findsOneWidget);
    expect(find.textContaining('Web research is off'), findsOneWidget);
    expect(find.textContaining('No knowledge collection'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-tool-calculator')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('quick-tool-calculator')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.text('Required'));
    await tester.pump();
    expect(find.textContaining('Required: a tool is called'), findsOneWidget);
    // The same settings the Tools page reads.
    await tester.tap(find.byKey(const Key('quick-tools-enabled')));
    await tester.pump();
    expect(find.byKey(const Key('quick-tool-web')), findsNothing);
  });

  testWidgets('overrides page sets and clears a scope value', (tester) async {
    tester.view.physicalSize = const Size(412, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      harness(
        OverridesPage(
          title: 'Profile',
          scopeLabel: 'Model profile',
          overrides: const {},
          inherited: const InferenceSettings(),
          onChanged: (o) async => saved.add(o),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Model profile · 0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('override-temperature')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0.2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.last, {'temperature': 0.2});
    expect(find.text('Customized · 0.20'), findsOneWidget);
    // Boolean picker.
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-thinkingModeEnabled')),
      600,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('override-thinkingModeEnabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('On'));
    await tester.pumpAndSettle();
    expect(saved.last, {'temperature': 0.2, 'thinkingModeEnabled': true});
    // Clear one.
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-temperature')),
      -600,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('override-temperature')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(saved.last, {'thinkingModeEnabled': true});
  });

  testWidgets('effective settings page lists layers and origins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(const EffectiveSettingsPage()));
    await tester.pump();
    expect(find.text('Your settings'), findsOneWidget);
    expect(find.text('Test Model profile'), findsOneWidget);
    expect(find.textContaining('Nothing is overridden'), findsOneWidget);
    expect(find.byKey(const Key('effective-temperature')), findsOneWidget);
  });

  testWidgets('appearance page renders in light theme with an accent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const AppearancePage(),
        theme: AppTheme.of(AccentChoice.violet, dark: false),
      ),
    );
    await tester.pump();
    expect(find.text('Accent colour'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accent-teal')));
    await tester.pump();
    final palette = AppTheme.palette(AccentChoice.teal, dark: false);
    expect(palette.isDark, isFalse);
    expect(
      palette.accent,
      isNot(AppTheme.palette(AccentChoice.amber, dark: false).accent),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/presets/domain/preset.dart';
import 'package:ondevice_llm/features/presets/presentation/preset_sheet.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/advanced_pages_2.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/effective_settings_page.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/inference_contract_page.dart';
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
  Future<void> update(
    InferenceSettings next, {
    bool requirePersistence = false,
  }) async {
    state = next;
  }
}

class GbnfSettings extends TestSettings {
  @override
  InferenceSettings build() =>
      super.build().copyWith(responseFormat: ResponseFormat.gbnf);
}

/// The user's own settings have web research on; a preset or chat can still
/// keep it Off (the cascade cases the confirmation must resolve).
class WebAutoSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(webMode: WebMode.auto);
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
    expect(find.textContaining('Same switch as the globe'), findsOneWidget);
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
    expect(find.textContaining('Same switch as the globe'), findsOneWidget);
    expect(find.textContaining('No knowledge collection'), findsOneWidget);
    // Recall shows only with Memory on.
    expect(find.byKey(const Key('quick-tool-recall')), findsNothing);
    expect(find.byKey(const Key('quick-tool-actions')), findsOneWidget);
    // Web follows the globe: off by default; on asks the globe's question
    // before this chat's text can leave the device (audit 2026-11-20 P1-4).
    SwitchListTile row(String key) =>
        tester.widget<SwitchListTile>(find.byKey(Key(key)));
    expect(row('quick-tool-web').value, isFalse);
    await tester.tap(find.byKey(const Key('quick-tool-web')));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    expect(row('quick-tool-web').value, isFalse);
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(row('quick-tool-web').value, isTrue);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ToolsQuickPanel)),
    );
    expect(container.read(chatOverridesProvider)['webMode'], 'auto');
    // The tool was already on, so only the mode changed: the chat override
    // holds what changed while the cascade still offers the tool.
    expect(container.read(effectiveSettingsProvider).effective.toolWeb, isTrue);
    // Off saves toolWeb off as well, like the global Tools switch, instead of
    // forcing the tool back on for a later turn (audit 2026-11-20 P2-3).
    await tester.tap(find.byKey(const Key('quick-tool-web')));
    await tester.pumpAndSettle();
    expect(row('quick-tool-web').value, isFalse);
    expect(container.read(chatOverridesProvider)['webMode'], 'off');
    expect(container.read(chatOverridesProvider)['toolWeb'], isFalse);
    await tester.tap(find.byKey(const Key('quick-tool-actions')));
    await tester.pump();
    expect(row('quick-tool-actions').value, isFalse);
    // The helper switch is here too, off until turned on for this chat.
    expect(row('quick-tool-helper').value, isFalse);
    await tester.ensureVisible(find.byKey(const Key('quick-tool-helper')));
    await tester.tap(find.byKey(const Key('quick-tool-helper')));
    await tester.pump();
    expect(row('quick-tool-helper').value, isTrue);
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

  testWidgets('tools page asks before turning web research on', (tester) async {
    tester.view.physicalSize = const Size(412, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.dark, home: const ToolsPage()),
      ),
    );
    await tester.pump();
    // Off to on sends text to the web: the same informed confirmation the
    // Web research row asks for (audit 2026-11-20 P1-4). The row is found by
    // its label, so a silent flip fails here like on the old code.
    final web = find.text('search_web · read_url · find_in_page');
    await tester.ensureVisible(web);
    await tester.pumpAndSettle();
    await tester.tap(web);
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    // Web stays off while the question is open; the row's stored tool
    // choice (default on) is not written by the question itself.
    expect(container.read(settingsProvider).webSearchEnabled, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webSearchEnabled, isFalse);
    await tester.tap(web);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webSearchEnabled, isTrue);
    expect(container.read(settingsProvider).toolWeb, isTrue);
    // Off must not force the stored tool choice back on.
    await tester.tap(web);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webSearchEnabled, isFalse);
    expect(container.read(settingsProvider).toolWeb, isFalse);
  });

  testWidgets('global model settings leave sampling to each model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    // A stored per-model choice: this page must neither list nor reset it.
    await container
        .read(settingsProvider.notifier)
        .update(container.read(settingsProvider).copyWith(temperature: 1.7));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const InferenceContractPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-maxTokens')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    // The answer limit is a real app-wide default; sampling is not (the
    // resolver drops it from the global layer), so the page must not list
    // it (audit 2026-11-20 P1-2).
    expect(find.byKey(const Key('override-maxTokens')), findsOneWidget);
    expect(find.byKey(const Key('override-temperature')), findsNothing);
    expect(find.byKey(const Key('override-stopSequences')), findsNothing);
    // Saving an unrelated setting leaves the hidden value and its marker
    // alone (audit 2026-11-20 P2-2).
    await tester.ensureVisible(find.byKey(const Key('override-maxTokens')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('override-maxTokens')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = container.read(settingsProvider);
    expect(saved.temperature, 1.7);
    expect(saved.explicitOverrides, contains('temperature'));
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
          change: (o) => SettingsChange(chat: o),
          onChanged: (o) async => saved.add(o),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Model profile · 0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-temperature')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('override-temperature')));
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-thinkingModeEnabled')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const Key('override-thinkingModeEnabled')),
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

  testWidgets('overrides ask before turning web research on', (tester) async {
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
          change: (o) => SettingsChange(chat: o),
          onChanged: (o) async => saved.add(o),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-webMode')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('override-webMode')));
    await tester.pumpAndSettle();
    // Off to Auto sends the user's text off the device: the same informed
    // question the main switch asks, before anything is saved
    // (audit 2026-11-20 P1-4).
    await tester.tap(find.byKey(const Key('override-webMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('auto'));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    await tester.tap(find.byKey(const Key('override-webMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('auto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(saved.last, {'webMode': 'auto'});
  });

  testWidgets('clearing a scope does not reset web research to on silently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(WebAutoSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          // This page is open on a chat whose saved overrides are the Off it
          // shows; the shared gate resolves the same cascade the send path
          // uses, so the setup has to carry that layer too.
          chatOverridesProvider.overrideWith((ref) => {'webMode': 'off'}),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: OverridesPage(
            title: 'Profile',
            scopeLabel: 'Chat',
            overrides: const {'webMode': 'off'},
            inherited: const InferenceSettings(webMode: WebMode.auto),
            change: (o) => SettingsChange(chat: o),
            onChanged: (o) async => saved.add(o),
          ),
        ),
      ),
    );
    await tester.pump();
    // The scope is Off over an Auto layer: returning it to inherited turns
    // web research on, so Clear all asks first (audit 2026-11-20 P1-4).
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(saved.last, isEmpty);
  });

  testWidgets('a preset override over its typed Off asks before web turns on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <Map<String, dynamic>>[];
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(WebAutoSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    final presets = container.read(presetsProvider.notifier);
    await presets.ready;
    const local = Preset(
      id: '',
      name: 'Local',
      emoji: '🔒',
      systemPrompt: '',
      webMode: WebMode.off,
    );
    final preset = await presets.create(local);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: OverridesPage(
            title: 'Local',
            scopeLabel: 'Preset',
            overrides: const {},
            // The layers below say Auto; the preset's own Off wins.
            inherited: const InferenceSettings(webMode: WebMode.auto),
            change: (o) =>
                SettingsChange(preset: preset.copyWith(overrides: o)),
            onChanged: (o) async => saved.add(o),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('override-webMode')),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // Global Auto sits under the preset's typed Off, so an override of Auto
    // is the Off → Auto step the main switch asks about; comparing against
    // the global value alone used to skip the question (audit 2026-11-20
    // P1-4).
    await tester.tap(find.byKey(const Key('override-webMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('auto'));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });

  testWidgets('deleting the active Off preset asks before web is revealed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(WebAutoSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    final presets = container.read(presetsProvider.notifier);
    await presets.ready;
    final local = await presets.create(
      const Preset(
        id: '',
        name: 'Local',
        emoji: '🔒',
        systemPrompt: '',
        webMode: WebMode.off,
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPresetSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The active preset keeps web research Off over the user's Auto: removing
    // it would reveal Auto, so it asks first (audit 2026-11-20 P1-4).
    await tester.tap(
      find.descendant(
        of: find.byKey(Key('preset-${local.id}')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    expect(
      container.read(presetsProvider).presets.any((p) => p.id == local.id),
      isTrue,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      container.read(presetsProvider).presets.any((p) => p.id == local.id),
      isTrue,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(Key('preset-${local.id}')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(
      container.read(presetsProvider).presets.any((p) => p.id == local.id),
      isFalse,
    );
    expect(container.read(presetsProvider).activeId, Preset.general.id);
  });

  testWidgets('activating a preset that turns web research on asks first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    final presets = container.read(presetsProvider.notifier);
    await presets.ready;
    final web = await presets.create(
      const Preset(
        id: '',
        name: 'Web',
        emoji: '🌐',
        systemPrompt: '',
        webMode: WebMode.auto,
      ),
    );
    await presets.activate(Preset.general.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPresetSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The preset's web mode becomes the next message's: ask the globe
    // button's question first (audit 2026-11-20 P1-4).
    await tester.tap(find.byKey(Key('preset-${web.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Enable web search?'), findsOneWidget);
    expect(container.read(presetsProvider).activeId, Preset.general.id);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(presetsProvider).activeId, Preset.general.id);
    await tester.tap(find.byKey(Key('preset-${web.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(container.read(presetsProvider).activeId, web.id);
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

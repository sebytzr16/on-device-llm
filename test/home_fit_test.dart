import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/attachments/presentation/attachment_picker.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_title.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/presentation/tools_quick_panel.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tester's phone (1080 x 2340 at 450 dpi) in logical pixels.
const _phone = Size(384, 832);

class _ToolsOn extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(toolsEnabled: true);
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class _NoModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: []);
  }
}

Future<void> _font(String family, String file) async {
  final bytes = await File('assets/fonts/$file').readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

Future<void> _pump(WidgetTester tester, Widget home, Locale locale) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 32, bottom: 16);
  tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 16);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_ToolsOn.new),
        modelManagerProvider.overrideWith(_NoModels.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (_, child) =>
            MotionScope(choice: MotionChoice.off, child: child!),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _font('Fraunces', 'Fraunces.ttf');
    await _font('Inter', 'Inter.ttf');
    await _font('JetBrainsMono', 'JetBrainsMono.ttf');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the header shows all of "OnDevice LLM" at full size', (
    tester,
  ) async {
    await _pump(
      tester,
      Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: () {}, icon: const Icon(Icons.menu)),
          title: const ChatTitle(subtitle: 'Qwen3.5 0.8B'),
          actions: [
            IconButton(
              key: const Key('first-action'),
              onPressed: () {},
              icon: const Icon(Icons.record_voice_over_outlined),
            ),
            IconButton(onPressed: () {}, icon: const Icon(Icons.edit_square)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
          ],
        ),
      ),
      const Locale('en'),
    );
    final box = find.byKey(const Key('app-title'));
    final name = find.descendant(of: box, matching: find.byType(RichText));
    expect(find.text('OnDevice LLM', findRichText: true), findsOneWidget);
    // Not scaled down: the name fits beside the actions at 21 pt.
    expect(
      tester.getSize(name).width,
      lessThanOrEqualTo(tester.getSize(box).width),
    );
    expect(
      tester.getRect(box).right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('first-action'))).left,
      ),
    );
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('the + sheet fits without scrolling ($locale, tools on)', (
      tester,
    ) async {
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => pickAttachments(
                context,
                more: [
                  AttachTile(
                    key: const Key('attach-goal'),
                    icon: Icons.flag_outlined,
                    label: AppLocalizations.of(context).attachGoalShort,
                    onTap: Navigator.pop,
                  ),
                ],
                below: const [ToolsQuickPanel()],
              ),
              child: const Text('+'),
            ),
          ),
        ),
        locale,
      );
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-tool-documents')), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, 0);
      for (final key in ['attach-camera', 'attach-gallery', 'attach-file']) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

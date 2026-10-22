import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_page.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/schedule/schedule_page.dart';
import 'package:ondevice_llm/features/schedule/scheduled_prompt.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/shortcuts/presentation/shortcuts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings;
import 'device_hosting_page_test.dart' show RunningHost;

/// TalkBack and large-text checks for the pages added on 2026-09-23:
/// every tap target at least 48×48 dp with a label, and text contrast.
Future<void> checkGuidelines(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

Widget app(Widget home, {bool hosting = false, double scale = 1}) =>
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        if (hosting) deviceHostingProvider.overrideWith(RunningHost.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('scheduled prompts', (tester) async {
    await tester.pumpWidget(
      app(
        SchedulePage(
          load: () async => const [
            ScheduledPrompt(
              id: 1,
              prompt: 'Top news in Canada?',
              hour: 8,
              minute: 0,
            ),
          ],
          save: (_) async {},
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await checkGuidelines(tester);
  });

  testWidgets('prompt shortcuts', (tester) async {
    await tester.pumpWidget(app(const ShortcutsPage()));
    await tester.pumpAndSettle();
    await checkGuidelines(tester);
  });

  testWidgets('device server dashboard, at 200% text', (tester) async {
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(const DeviceHostingPage(), hosting: true, scale: 2),
    );
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'no overflow at 200%');
    await checkGuidelines(tester);
  });

  testWidgets('version switcher on an edited question', (tester) async {
    final old = ChatMessage(
      id: 'old',
      role: ChatRole.user,
      content: 'Earlier question',
      timestamp: DateTime.utc(2026),
      status: 'superseded:branch-a:complete',
    );
    final current = ChatMessage(
      id: 'current',
      role: ChatRole.user,
      content: 'Current question',
      timestamp: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: ChatBubble(
            message: current,
            versions: [old, current],
            onRestoreVersion: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The bubble's selectable text is a long-press target the platform
    // owns; the switcher's own targets are checked directly.
    for (final tip in [
      'Previous version',
      'Next version',
      'Choose question version',
    ]) {
      final size = tester.getSize(find.byTooltip(tip));
      expect(size.width, greaterThanOrEqualTo(48), reason: tip);
      expect(size.height, greaterThanOrEqualTo(48), reason: tip);
    }
  });
}

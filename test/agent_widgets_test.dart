import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/helper/agent_web_approval_card.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/advanced_pages_2.dart';
import 'package:ondevice_llm/features/settings/presentation/widgets/settings_widgets.dart';

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(agentThinking: true, agentMaxConcurrent: 4);
  }

  @override
  Future<void> update(InferenceSettings value) async => state = value;
}

void main() {
  for (final desktop in [false, true]) {
    testWidgets('Agents settings edit and reset on desktop=$desktop', (
      tester,
    ) async {
      DesktopHost.active = desktop;
      addTearDown(() => DesktopHost.active = false);
      tester.view.physicalSize = Size(desktop ? 1100 : 430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [settingsProvider.overrideWith(_Settings.new)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SingleChildScrollView(child: AgentsSettingsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agents'), findsOneWidget);
      expect(find.text('Max answer tokens'), findsOneWidget);
      final slider = tester
          .widgetList<SettingSlider>(find.byType(SettingSlider))
          .first;
      slider.onChanged(2);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).agentMaxConcurrent, 2);
      await tester.ensureVisible(find.byKey(const Key('agents-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agents-reset')));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).agentMaxConcurrent, 3);
      expect(container.read(settingsProvider).agentThinking, false);
      expect(tester.takeException(), isNull);
    });
  }

  for (final allow in [true, false]) {
    testWidgets('approval card sends explicit ${allow ? 'allow' : 'deny'}', (
      tester,
    ) async {
      bool? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AgentWebApprovalCard(onAnswer: (value) => answer = value),
          ),
        ),
      );
      await tester.tap(
        find.byKey(Key(allow ? 'agent-web-allow' : 'agent-web-deny')),
      );
      expect(answer, allow);
      expect(tester.takeException(), isNull);
    });
  }
}

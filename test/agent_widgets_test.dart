import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/helper/agent_web_approval_card.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
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

class _RemoteSettings extends _Settings {
  @override
  InferenceSettings build() => super.build().copyWith(
    toolHelper: true,
    helperModelId: '',
    remoteEnabled: true,
    remoteProfiles: [
      const RemoteProfile(
        id: 'api',
        name: 'API',
        providerId: 'custom',
        baseUrl: 'https://example.org/v1',
        model: 'remote-model',
      ),
    ],
    remoteProfileId: 'api',
  );
}

class _EmptyModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState();
  }
}

class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
}

void main() {
  testWidgets('remote helper picker offers Same as chat with no downloads', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_RemoteSettings.new),
        modelManagerProvider.overrideWith(_EmptyModels.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ToolsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menu = find.byKey(const Key('tool-helper-model-menu'));
    expect(menu, findsOneWidget);
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tool-helper-model-chat')));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).helperModelId, '@chat');
    expect(tester.takeException(), isNull);
  });
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
      final timeout = tester
          .widgetList<SettingDropdown<int>>(find.byType(SettingDropdown<int>))
          .singleWhere((widget) => widget.label == 'Agent time limit');
      expect(timeout.value, 0);
      expect(timeout.labelOf(0), 'Unlimited');
      expect(timeout.items, containsAll([0, 90, 300, 900, 1800, 3600]));
      timeout.onChanged(900);
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).agentTimeoutSeconds, 900);
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
      expect(container.read(settingsProvider).agentTimeoutSeconds, 0);
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

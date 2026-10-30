import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/inspector_panel.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/domain/model_recommendations.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_recommendations_provider.dart';
import 'package:ondevice_llm/features/retrieval/domain/subject_terms.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';
import 'package:ondevice_llm/inference/engine/turn_budget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../advanced_pages_2_test.dart' show TestModels, TestSettings;

class DesktopTestChat extends ChatNotifier {
  final sent = <String>[];
  final sentAttachments = <List<Attachment>>[];
  bool accepts = true;
  int cancellations = 0;

  @override
  ChatState build() => const ChatState();

  // Keep the real setChatOverrides: a new chat persists in its provider
  // without opening a database or loading the inference bridge.
  void show(ChatState next) => state = next;

  @override
  void cancel() {
    cancellations++;
    state = state.copyWith(isGenerating: false);
  }

  @override
  Future<bool> send(
    String input, {
    bool insertUser = true,
    ChatMessage? resume,
    List<Attachment> attachments = const [],
    ModelInfo? compareWith,
    String? reuseSourcesJson,
    String? parentId,
    Map<String, dynamic> turnOverrides = const {},
    String? extraSystem,
    bool forceResearch = false,
    bool isolated = false,
    String? promptOverride,
    List<SearchResult>? answerSources,
    bool learn = true,
    SubjectTerms? subject,
    String subjectAllowed = '',
    TurnBudget? budget,
    bool localOnly = false,
    bool spoken = false,
  }) async {
    sent.add(input);
    sentAttachments.add(attachments);
    return accepts;
  }
}

class _Voice extends VoiceNotifier {
  @override
  VoiceState build() => const VoiceState();
}

class _Recommendations extends ModelRecommendationsNotifier {
  @override
  Map<String, ModelRecommendation> build() => const {
    'test': ModelRecommendation(
      values: {'temperature': 0.65, 'topP': 0.85, 'minP': 0.04, 'topK': 30},
    ),
  };
}

Future<ProviderContainer> mountDesktopChat(
  WidgetTester tester,
  Widget child, {
  bool shell = false,
}) async {
  final previousDesktop = DesktopHost.active;
  final previousInspector = desktopInspectorOpen.value;
  DesktopHost.active = true;
  desktopInspectorOpen.value = false;
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    DesktopHost.active = previousDesktop;
    desktopInspectorOpen.value = previousInspector;
    tester.view.reset();
  });
  final container = ProviderContainer(
    overrides: [
      chatProvider.overrideWith(DesktopTestChat.new),
      modelManagerProvider.overrideWith(TestModels.new),
      settingsProvider.overrideWith(TestSettings.new),
      voiceProvider.overrideWith(_Voice.new),
      modelRecommendationsProvider.overrideWith(_Recommendations.new),
      currentProjectProvider.overrideWithValue(null),
      chatsProvider.overrideWith((ref) => Stream.value([])),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: DesktopTheme.of(AccentChoice.amber, dark: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: shell ? child : Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/composer.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/share/reader_actions.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_widgets_test.dart' show TestModels, TestSettings;

void main() {
  testWidgets('quick actions follow the attachment kind and send at once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final sent = <String>[];
    var attachments = const [
      Attachment(
        id: 'p',
        kind: AttachmentKind.image,
        name: 'p.png',
        mime: 'image/png',
        path: '/nowhere/p.png',
        sizeBytes: 1,
      ),
    ];
    Widget build() => ProviderScope(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            busy: false,
            canSend: true,
            onSend: () => sent.add('send:${controller.text}'),
            onStop: () {},
            attachments: attachments,
            onQuickPrompt: (t) => sent.add('quick:$t'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build());
    await tester.pump();
    expect(find.byKey(const Key('quick-actions')), findsOneWidget);
    expect(find.byKey(const Key('quick-Describe')), findsOneWidget);
    expect(find.byKey(const Key('quick-Summarise')), findsNothing);
    await tester.tap(find.byKey(const Key('quick-Describe')));
    expect(sent, ['quick:Describe this photo in detail.']);

    // A document gets document actions; the send button is live with an
    // attachment even when the text is empty.
    attachments = const [
      Attachment(
        id: 'd',
        kind: AttachmentKind.document,
        name: 'd.txt',
        mime: 'text/plain',
        path: '/nowhere/d.txt',
        sizeBytes: 1,
        text: 'hello',
      ),
    ];
    await tester.pumpWidget(build());
    await tester.pump();
    expect(find.byKey(const Key('quick-Summarise')), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-stop')));
    expect(sent.last, 'send:');
  });

  test('reader mode recognises one shared link', () {
    expect(
      ReaderActions.linkIn('Big news today\nhttps://example.com/story'),
      'https://example.com/story',
    );
    expect(ReaderActions.linkIn('https://a.example https://b.example'), isNull);
    expect(
      ReaderActions.linkIn('Is https://a.example still up to date?'),
      isNull,
      reason: 'a question around a link is the user writing',
    );
    expect(ReaderActions.linkIn('no link'), isNull);
  });

  testWidgets('the globe asks every time it leaves Local, not once per run', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
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
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: ChatComposer(
              controller: controller,
              busy: false,
              canSend: true,
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final dialog = find.text('Enable web search?');
    // Local → Auto asks, then Auto → Always and Always → Local do not.
    await tester.tap(find.byKey(const Key('web-pill')));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webMode, WebMode.auto);
    for (final expected in [WebMode.always, WebMode.off]) {
      await tester.tap(find.byKey(const Key('web-pill')));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).webMode, expected);
    }
    // Going Local again in the same run is a new Off → Auto step: the old
    // once-per-run flag let it through without asking (audit 2026-11-20
    // P1-4).
    await tester.tap(find.byKey(const Key('web-pill')));
    await tester.pumpAndSettle();
    expect(dialog, findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).webMode, WebMode.off);
  });

  testWidgets('a shared link offers reader actions, only with web on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = TextEditingController(
      text: 'Big news today\nhttps://example.com/story',
    );
    addTearDown(controller.dispose);
    final sent = <String>[];
    Widget build(Type settings) => ProviderScope(
      // A new scope per settings: overrides cannot change on a live one.
      key: ValueKey(settings),
      overrides: [
        settingsProvider.overrideWith(
          settings == WebSettings ? WebSettings.new : TestSettings.new,
        ),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            busy: false,
            canSend: true,
            onSend: () {},
            onStop: () {},
            onQuickPrompt: sent.add,
          ),
        ),
      ),
    );
    await tester.pumpWidget(build(TestSettings));
    await tester.pump();
    expect(find.byKey(const Key('reader-actions')), findsOneWidget);
    await tester.tap(find.text('Summarize article'));
    await tester.pump();
    expect(sent, isEmpty, reason: 'web research is off');
    expect(find.textContaining('needs web research'), findsOneWidget);
    await tester.pumpWidget(build(WebSettings));
    await tester.pump();
    await tester.tap(find.text('Key points'));
    expect(sent.single, contains('https://example.com/story'));
    expect(
      sent.single,
      startsWith('Read this article and list its key points'),
    );
  });

  testWidgets('leaving the screen stops the mic and drops a late transcript', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final voice = FakeVoice();
    final controller = TextEditingController();
    // The chat screen owns this controller and disposes it on the way out.
    Widget build() => ProviderScope(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        voiceProvider.overrideWith(() => voice),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ChatComposer(
            controller: controller,
            busy: false,
            canSend: true,
            onSend: () {},
            onStop: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(build());
    await tester.pump();
    await tester.tap(find.byKey(const Key('dictate')));
    await tester.pump();
    expect(voice.said, isNotNull, reason: 'dictation started');
    expect(voice.stops, 0);

    // The screen goes away while the recognizer keeps listening.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();
    expect(
      voice.stops,
      1,
      reason: 'the mic must not stay open (review 2026-11-20)',
    );
    controller.dispose();

    // A transcript that arrives afterwards is dropped instead of being typed
    // into the disposed field.
    expect(() => voice.said!('hello'), returnsNormally);
  });
}

/// Records the callbacks and stops; it never opens a microphone.
class FakeVoice extends VoiceNotifier {
  int stops = 0;
  ValueChanged<String>? said;
  @override
  VoiceState build() => const VoiceState();
  @override
  Future<void> listen({
    required ValueChanged<String> onText,
    ValueChanged<String>? onFinal,
    bool onDeviceOnly = true,
    String? localeId,
  }) async {
    said = onText;
    state = state.copyWith(listening: true);
  }

  @override
  Future<void> stop() async {
    stops++;
    state = state.copyWith(listening: false);
  }
}

class WebSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(webMode: WebMode.auto);
}

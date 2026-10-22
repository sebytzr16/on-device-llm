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
}

class WebSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(webMode: WebMode.auto);
}

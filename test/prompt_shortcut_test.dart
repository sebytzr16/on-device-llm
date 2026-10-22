import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/features/shortcuts/domain/prompt_shortcut.dart';
import 'package:ondevice_llm/features/shortcuts/presentation/shortcuts_page.dart';
import 'package:ondevice_llm/features/shortcuts/prompt_shortcuts_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final locale in ['en', 'fr', 'es']) {
    testWidgets('shortcut helper stays complete in $locale at larger text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            locale: Locale(locale),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MotionScope(
              choice: MotionChoice.off,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
            ),
            home: const ShortcutsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shortcut-add')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AlertDialog));
      final helper = find.text(context.l10n.shortcutPromptHelp('{input}'));
      expect(
        tester.renderObject<RenderParagraph>(helper).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  const all = PromptShortcut.builtIns;

  test('a shortcut expands with the text after the command', () {
    final (s, prompt) = PromptShortcut.apply('/summarize The long text.', all)!;
    expect(s.name, 'summarize');
    expect(prompt, startsWith('Summarize the following'));
    expect(prompt, endsWith('\n\nThe long text.'));
    // Multi-line text after the command is kept whole.
    expect(
      PromptShortcut.apply('/fix line one\nline two', all)!.$2,
      endsWith('line one\nline two'),
    );
  });

  test('/translate takes a language code or name first', () {
    expect(
      PromptShortcut.apply('/translate fr Good morning', all)!.$2,
      'Translate the following into French. Reply with the translation only.\n\nGood morning',
    );
    expect(
      PromptShortcut.apply('/translate Spanish Good morning', all)!.$2,
      contains('into Spanish'),
    );
    // No language: the default, and the first word stays in the text.
    final plain = PromptShortcut.apply('/translate Bonjour à tous', all)!.$2;
    expect(plain, contains('into English'));
    expect(plain, endsWith('Bonjour à tous'));
  });

  test('built-in prompts speak the app language', () {
    expect(
      PromptShortcut.apply('/summarize Le texte.', all, lang: 'fr')!.$2,
      startsWith('Résume le texte suivant'),
    );
    expect(
      PromptShortcut.apply('/translate en Bonjour', all, lang: 'fr')!.$2,
      startsWith('Traduis le texte suivant en anglais.'),
    );
    expect(
      PromptShortcut.apply('/translate francés Hola', all, lang: 'es')!.$2,
      'Traduce el siguiente texto al francés. Responde solo con la traducción.\n\nHola',
    );
    // English names still work from a Spanish phone; no arg → default.
    expect(
      PromptShortcut.apply('/translate German Hola', all, lang: 'es')!.$2,
      contains('al alemán'),
    );
    expect(
      PromptShortcut.apply('/translate Hola amigos', all, lang: 'es')!.$2,
      contains('al inglés'),
    );
    // The user's own shortcuts are sent as written.
    const own = PromptShortcut(
      name: 'tldr',
      description: '',
      template: 'TL;DR: {input}',
    );
    expect(
      PromptShortcut.apply('/tldr x', const [own], lang: 'fr')!.$2,
      'TL;DR: x',
    );
  });

  test('messages that only look like commands go out as typed', () {
    expect(PromptShortcut.apply('/etc/hosts is a file', all), isNull);
    expect(PromptShortcut.apply('/unknown do it', all), isNull);
    expect(PromptShortcut.apply('summarize this', all), isNull);
  });

  test('suggestions follow the command word only', () {
    expect(
      PromptShortcut.suggestions('/s', all).map((s) => s.name),
      containsAll(['summarize', 'shorter']),
    );
    expect(PromptShortcut.suggestions('/', all), hasLength(all.length));
    expect(PromptShortcut.suggestions('/summarize now', all), isEmpty);
    expect(PromptShortcut.suggestions('hello', all), isEmpty);
  });

  test('a template without {input} gets the text appended', () {
    const s = PromptShortcut(
      name: 'haiku',
      description: '',
      template: 'Write a haiku about:',
    );
    expect(s.expand('autumn rain'), 'Write a haiku about:\n\nautumn rain');
    expect(s.expand(''), 'Write a haiku about:');
  });

  test(
    'own shortcuts persist, replace a built-in, and come off again',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(promptShortcutsProvider.notifier);
      await n.ready;
      await n.put(
        const PromptShortcut(
          name: 'summarize',
          description: 'Mine',
          template: 'TL;DR: {input}',
        ),
      );
      await n.put(
        const PromptShortcut(
          name: 'eli5',
          description: '',
          template: '{input}',
        ),
      );
      var list = container.read(promptShortcutsProvider);
      expect(
        list.where((s) => s.name == 'summarize').single.template,
        'TL;DR: {input}',
      );
      expect(list.any((s) => s.name == 'eli5'), true);
      // A fresh container reads them back.
      final again = ProviderContainer();
      addTearDown(again.dispose);
      await again.read(promptShortcutsProvider.notifier).ready;
      expect(
        again.read(promptShortcutsProvider).any((s) => s.name == 'eli5'),
        true,
      );
      await n.remove('summarize');
      list = container.read(promptShortcutsProvider);
      expect(list.where((s) => s.name == 'summarize').single.builtIn, true);
      expect(
        PromptShortcut.fromJson({'name': 'Bad Name', 'template': 'x'}),
        isNull,
      );
    },
  );

  testWidgets('the settings page adds a shortcut', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const ShortcutsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('/summarize'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shortcut-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shortcut-name')), 'Bad Name');
    await tester.pump();
    expect(find.textContaining('Lower-case letters'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('shortcut-name')), 'tldr');
    await tester.enterText(
      find.byKey(const Key('shortcut-template')),
      'TL;DR of: {input}',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('/tldr'), findsOneWidget);
  });
}

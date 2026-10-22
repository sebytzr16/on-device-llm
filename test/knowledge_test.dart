import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/export/chat_document.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings;

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

class KnowledgeSettings extends TestSettings {
  @override
  InferenceSettings build() =>
      super.build().copyWith(knowledgeCollection: 'Manuals');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'imports split into passages and retrieval ranks the right document',
    () async {
      final store = KnowledgeStore(db);
      final boiler = await store.import(
        collection: 'Manuals',
        name: 'boiler.txt',
        bytes: bytes(
          'Boiler manual.\n${'The pressure gauge should read between one and two bar when cold. ' * 30}'
          '\nTo reset the boiler after a lockout, hold the reset button for five seconds.\n'
          '${'Annual service is required to keep the warranty. ' * 30}',
        ),
      );
      await store.import(
        collection: 'Manuals',
        name: 'dishwasher.md',
        bytes: bytes(
          '# Dishwasher\n${'Rinse aid improves drying performance on glassware. ' * 40}',
        ),
      );
      await store.import(
        collection: 'Other',
        name: 'unrelated.txt',
        bytes: bytes(
          'Reset instructions for a completely different boiler model. ' * 20,
        ),
      );
      expect(boiler.chunkCount, greaterThan(1));
      expect(await store.collections(), ['Manuals', 'Other']);

      final hits = await store.search(
        'Manuals',
        'how do I reset the boiler after lockout',
      );
      expect(hits, isNotEmpty);
      expect(hits.first.title, 'boiler.txt');
      expect(hits.first.url, startsWith('knowledge://'));
      expect(hits.first.pageText, contains('hold the reset button'));
      // Other collections are never consulted.
      expect(hits.any((h) => h.title == 'unrelated.txt'), false);
      // Nothing matching → nothing returned (no padding with random passages).
      expect(
        await store.search('Manuals', 'zebra migration patterns'),
        isEmpty,
      );

      await store.remove(boiler.id);
      expect((await store.docsIn('Manuals')).map((d) => d.name), [
        'dishwasher.md',
      ]);
      await store.removeCollection('Manuals');
      expect(await store.collections(), ['Other']);
    },
  );

  test(
    'selected chat text becomes searchable without reasoning or older branches',
    () async {
      final now = DateTime(2026, 9, 23);
      final messages = [
        ChatMessage(
          id: 'q',
          role: ChatRole.user,
          content: 'How does the solar inverter work?',
          timestamp: now,
        ),
        ChatMessage(
          id: 'a',
          role: ChatRole.assistant,
          content:
              'The solar inverter converts direct current into alternating current.',
          reasoning: 'private analysis token',
          timestamp: now,
        ),
        ChatMessage(
          id: 'old',
          role: ChatRole.assistant,
          content: 'obsolete branch secret',
          status: 'superseded',
          timestamp: now,
        ),
        ChatMessage(
          id: 'other',
          role: ChatRole.user,
          content: 'unselected confidential question',
          timestamp: now,
        ),
      ];
      final document = ChatDocument.select(
        messages: messages,
        selectedIds: {'q', 'a', 'old'},
        title: 'Solar notes',
      );
      expect(document.text, isNot(contains('private analysis token')));
      expect(document.text, isNot(contains('obsolete branch secret')));
      expect(
        document.text,
        isNot(contains('unselected confidential question')),
      );
      final store = KnowledgeStore(db);
      final saved = await store.import(
        collection: 'Research',
        name: 'Solar notes.txt',
        bytes: bytes(document.text),
      );
      final hits = await store.search(
        'Research',
        'solar inverter direct current',
      );
      expect(hits.single.pageText, contains('converts direct current'));
      await store.remove(saved.id);
      expect(await store.docsIn('Research'), isEmpty);
    },
  );

  test('knowledge passages reach the model as cited sources', () async {
    SharedPreferences.setMockInitialValues({});
    final engine = TestEngine();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(KnowledgeSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(knowledgeStoreProvider)
        .import(
          collection: 'Manuals',
          name: 'boiler.txt',
          bytes: bytes(
            'To reset the boiler after a lockout, hold the reset button for five seconds. ' *
                5,
          ),
        );
    final notifier = container.read(chatProvider.notifier);
    await notifier.send('How do I reset the boiler?');
    final prompt = engine.receivedMessages!.last['content'] as String;
    expect(prompt, contains('[1] boiler.txt — knowledge://'));
    expect(prompt, contains('hold the reset button'));
    expect(prompt, contains('cite its source number'));
    // The stub answer cites nothing, so the grounding check speaks last.
    expect(
      container.read(chatProvider).notice,
      contains('cites none of the 1 supplied source'),
    );
    final rows = await db.getMessages(container.read(chatProvider).chatId!);
    final sources = jsonDecode(rows.last.sourcesJson) as List;
    expect(sources.single['url'], startsWith('knowledge://'));
    expect(sources.single['retrievalStatus'], 'page_read');
  });
}

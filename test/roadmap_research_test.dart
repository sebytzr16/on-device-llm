import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/context_use.dart';
import 'package:ondevice_llm/features/chat/domain/research_recipes.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/data/network/web_search/instant_answers.dart';
import 'chat_test.dart' as harness;

class _WindowEngine extends harness.TestEngine {
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {
    'fits':
        messages.fold(0, (n, m) => n + (m['content'] as String).length) < 5000,
  };
}

void main() {
  test('independent gold questions cover every research recipe', () {
    final gold =
        jsonDecode(File('eval/research_recipes_gold.json').readAsStringSync())
            as Map;
    final questions = (gold['questions'] as List).cast<Map>();
    final covered = <String>{};
    for (final item in questions) {
      final q = item['q'] as String;
      expect(ResearchRecipe.forQuestion(q).id, item['recipe'], reason: q);
      covered.add(item['recipe'] as String);
      if (item['unanswerable'] != true) {
        expect(item['requiredFacts'], isNotEmpty);
        for (final url in item['referenceSources'] as List) {
          expect(Uri.parse(url as String).scheme, 'https');
        }
      }
    }
    expect(covered.length, 11);
    expect(questions.where((q) => q['unanswerable'] == true).length, 2);
  });
  test('instant weather does not replace units or far-future research', () {
    final now = DateTime(2026, 9, 28);
    expect(
      InstantAnswers.wantsForecast('Weather in Toronto tomorrow', now: now),
      isTrue,
    );
    for (final q in [
      'Which temperature unit does Toronto weather use in metric mode?',
      'What will the exact temperature in Toronto be on 1 January 2031?',
      'Weather in Toronto on 3 October 2026',
      'What was the temperature in Toronto yesterday?',
    ]) {
      expect(InstantAnswers.wantsForecast(q, now: now), isFalse, reason: q);
    }
    expect(
      ResearchRecipe.forQuestion(
        'In news coverage, on what date did WHO first characterize COVID-19 as a pandemic?',
      ).instructions,
      contains('search_web'),
    );
  });
  test(
    'all source recipes route primary sources without trusting lookalike hosts',
    () {
      final fixtures = [
        (
          'Measles vaccine health information',
          'health',
          'https://www.who.int/health-topics/measles',
        ),
        (
          'Ontario age of majority law',
          'law',
          'https://www.ontario.ca/laws/statute/90a07',
        ),
        (
          'SEC annual earnings Form 10-K',
          'finance',
          'https://www.sec.gov/answers/form10k.htm',
        ),
        (
          'Weather forecast in Toronto',
          'weather',
          'https://weather.gc.ca/city/pages/on-143_metric_e.html',
        ),
        (
          'Biography of Marie Curie',
          'biography',
          'https://en.wikipedia.org/wiki/Marie_Curie',
        ),
        (
          'Scientific paper Attention Is All You Need',
          'science',
          'https://arxiv.org/abs/1706.03762',
        ),
        (
          'Nikon Z30 camera specifications',
          'product',
          'https://www.nikonusa.com/p/z-30/1737/overview',
        ),
        (
          'PostgreSQL default port',
          'software',
          'https://www.postgresql.org/docs/current/runtime-config-connection.html',
        ),
        (
          'Canadian passport travel requirements',
          'travel',
          'https://travel.gc.ca/travelling/documents/passport',
        ),
        ('FIFA world cup match rules', 'sports', 'https://www.fifa.com/legal'),
      ];
      for (final (q, id, url) in fixtures) {
        final recipe = ResearchRecipe.forQuestion(q);
        expect(recipe.id, id, reason: q);
        expect(recipe.prefers(url, q), isTrue, reason: q);
        final host = Uri.parse(url).host;
        expect(recipe.prefers('https://$host.evil.example/fake', q), isFalse);
        expect(
          recipe.prefers(
            'https://${host.replaceAll('.', '-')}.example/fake',
            q,
          ),
          isFalse,
        );
      }
      expect(
        ResearchRecipe.forQuestion('Latest news').instructions,
        contains('search_news'),
      );
      final software = ResearchRecipe.forQuestion('llama.cpp library');
      expect(
        software.prefers(
          'https://github.com/ggml-org/llama.cpp/blob/main/README.md',
          'llama.cpp',
        ),
        isTrue,
      );
      expect(
        software.prefers('https://github.com/stranger/fake', 'llama.cpp'),
        isFalse,
      );
    },
  );

  test('primary ranking preserves relevance and bounds promotion', () {
    final recipe = ResearchRecipe.forQuestion('Nikon Z30 sensor resolution');
    final rows = [
      ('https://review.example/z30', 'Nikon Z30 sensor resolution'),
      ('https://nikonusa.com/support', 'Shipping and returns'),
      (
        'https://nikonusa.com/z30',
        'Nikon Z30 sensor resolution specifications',
      ),
      for (var i = 0; i < 4; i++)
        ('https://example.com/$i', 'Nikon Z30 sensor resolution'),
      ('https://nikonusa.com/late', 'Nikon Z30 sensor resolution'),
    ];
    final ordered = recipe.order(
      rows,
      'Nikon Z30 sensor resolution',
      urlOf: (r) => r.$1,
      textOf: (r) => r.$2,
    );
    expect(ordered.first.$1, 'https://nikonusa.com/z30');
    expect(ordered[1], rows.first);
    expect(ordered.last, rows.last);
  });

  test('maker pages lead for the products the recipe knows by name', () {
    for (final q in [
      'Fujifilm X-T5 battery life',
      'DJI Mini 4 Pro specs',
      'Panasonic Lumix S5 II weight',
    ]) {
      expect(ResearchRecipe.forQuestion(q).id, 'product', reason: q);
    }
    // Names that also mean something else do not make a product question.
    for (final q in ['Is this canon in Star Wars?', 'Myths of Mount Olympus']) {
      expect(ResearchRecipe.forQuestion(q).id, isNot('product'), reason: q);
    }
    const q = 'Fujifilm X-T5 battery life';
    final recipe = ResearchRecipe.forQuestion(q);
    final rows = [
      ('https://review.example/x-t5', 'Fujifilm X-T5 battery life tested'),
      (
        'https://www.fujifilm-x.com/en-us/products/cameras/x-t5/specifications/',
        'Fujifilm X-T5 specifications: battery life',
      ),
    ];
    final ordered = recipe.order(
      rows,
      q,
      urlOf: (r) => r.$1,
      textOf: (r) => r.$2,
    );
    expect(ordered.first, rows.last);
    // A look-alike host is not the maker.
    expect(
      recipe.prefers('https://fujifilm-x.com.deals.example/x-t5', q),
      isFalse,
    );
  });

  test('source recipes recognize French and Spanish topics', () {
    for (final (q, id) in [
      ('La santé et le vaccin', 'health'),
      ('La ley en Ontario', 'law'),
      ('Prévisions météo à Toronto', 'weather'),
      ('Noticias de Canadá', 'news'),
      ('Biografía de Marie Curie', 'biography'),
      ('Comprar una cámara Sony', 'product'),
    ]) {
      expect(ResearchRecipe.forQuestion(q).id, id, reason: q);
    }
  });

  test('context fitting keeps the current user and complete tool tail', () {
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': 'instructions'},
      {'role': 'user', 'content': 'old'},
      {'role': 'assistant', 'content': 'old answer'},
      {'role': 'user', 'content': 'current'},
      {'role': 'assistant', 'content': 'tool call'},
      {'role': 'tool', 'content': 'evidence'},
    ];
    expect(ContextUse.omitOldestExchange(messages), 2);
    expect(messages.map((m) => m['content']), [
      'instructions',
      'current',
      'tool call',
      'evidence',
    ]);
    expect(ContextUse.omitOldestExchange(messages), 0);
  });

  test('context fitting can keep the last exchanges', () {
    List<Map<String, Object>> chat() => [
      {'role': 'system', 'content': 'instructions'},
      for (var i = 1; i <= 3; i++) ...[
        {'role': 'user', 'content': 'q$i'},
        {'role': 'assistant', 'content': 'a$i'},
      ],
      {'role': 'user', 'content': 'current'},
    ];
    final messages = chat();
    expect(ContextUse.earlierExchanges(messages), 3);
    expect(ContextUse.omitOldestExchange(messages, keep: 1), 2);
    expect(ContextUse.omitOldestExchange(messages, keep: 1), 2);
    expect(ContextUse.omitOldestExchange(messages, keep: 1), 0);
    expect(messages.map((m) => m['content']), [
      'instructions',
      'q3',
      'a3',
      'current',
    ]);
    expect(ContextUse.omitOldestExchange(messages), 2);
  });

  test(
    'isolated and context-limit omissions are distinguishable and bounded',
    () {
      final turns = [
        for (var i = 0; i < 150; i++)
          ChatMessage(
            id: '$i',
            role: ChatRole.user,
            content: 'message $i',
            timestamp: DateTime(2026),
          ),
      ];
      final audit = ContextUse.capture(
        available: turns,
        requested: turns.skip(148).toList(),
        omitted: 1,
        instructions: 'x' * 7000,
        sources: const [],
        isolated: true,
      );
      expect(audit['includedMessages'], 1);
      expect(audit['omittedMessages'], 149);
      expect(audit['earlierEntriesHidden'], 50);
      expect(audit['turns'], hasLength(100));
      final rows = (audit['turns'] as List).cast<Map>();
      expect(rows.first['reason'], 'isolated');
      expect(rows[98]['reason'], 'context_limit');
      expect(rows.last['included'], isTrue);
      expect((audit['instructions'] as String).length, 6001);
    },
  );

  test(
    'new research evidence survives older conversation context and its audit persists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = _WindowEngine();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          llamaEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(harness.WebTestSettings.new),
          modelManagerProvider.overrideWith(harness.TestModels.new),
          duckDuckGoScraperProvider.overrideWithValue(harness.TestSearch()),
          webPageReaderProvider.overrideWithValue(harness.TestReader()),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await db.upsertChat(
        ChatsCompanion.insert(
          id: 'history',
          title: 'History',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      for (var i = 0; i < 2; i++) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'old-$i',
            chatId: 'history',
            role: i == 0 ? 'user' : 'assistant',
            content: 'old context ' * 600,
            timestamp: DateTime(2026),
            sequence: i,
          ),
        );
      }
      final chat = container.read(chatProvider.notifier);
      await chat.openChat('history');
      expect(await chat.send('Search the latest Flutter version'), isTrue);
      final state = container.read(chatProvider);
      expect(state.error, isNull);
      expect(engine.receivedMessages, hasLength(2));
      expect(
        (engine.receivedMessages!.last['content'] as String),
        contains('Verified page evidence'),
      );
      expect(state.metrics['trimmedMessages'], 2);
      final saved = (await db.getMessages('history')).last;
      final run = TurnRun.decode(saved.runJson)!;
      final audit = run.metrics['contextAudit'] as Map;
      expect(audit['includedMessages'], 1);
      expect(audit['omittedMessages'], 2);
      expect(run.metrics['evidenceAudit'], isA<Map>());
      expect(jsonDecode(saved.sourcesJson), isNotEmpty);
      expect(await db.getMessages('history'), hasLength(4));
    },
  );
}

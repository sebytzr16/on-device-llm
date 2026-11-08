import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/domain/tool_result_cut.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestModels, TestSettings, testModel;

/// Counts every previewPrompt call. Tokens are exactly one per four content
/// characters, so the chars-per-token estimate fitToolResults derives from a
/// full preview equals the isolated per-exchange previews the old code made:
/// the messages kept here are the ones those would have kept.
class _CountingEngine extends TestEngine {
  _CountingEngine({required this.contextSize, this.reservedTokens = 0});

  final int contextSize;
  final int reservedTokens;

  int calls = 0;
  final previewedCounts = <int>[];

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    calls++;
    previewedCounts.add(messages.length);
    final chars = messages.fold<int>(
      0,
      (n, m) => n + (m['content'] as String).length,
    );
    final prompt = chars ~/ 4;
    final available = contextSize - reservedTokens - prompt;
    return {
      'fits': available >= 0,
      'promptTokens': prompt,
      'contextSize': contextSize,
      'reservedTokens': reservedTokens,
      'availableTokens': available,
    };
  }
}

Map<String, Object> msg(String role, String content) => {
  'role': role,
  'content': content,
};

/// [len] characters, distinct per [tag]; always a multiple of 4 so the fake's
/// token count and the estimate in fitToolResults are exact.
String filled(String tag, int len) => tag + 'x' * (len - tag.length);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, AppDatabase)> mount(_CountingEngine engine) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    container.read(chatProvider);
    return (container, db);
  }

  test('a prompt that fits previews once and keeps every message', () async {
    final engine = _CountingEngine(contextSize: 2000, reservedTokens: 200);
    final (container, db) = await mount(engine);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final messages = [
      msg('system', filled('s', 100)),
      msg('user', filled('q', 400)),
      msg('tool', filled('t', 400)),
    ];
    final toolMessages = [messages[2]];
    final result = await container
        .read(chatProvider.notifier)
        .fitToolResults(
          engine,
          messages,
          toolMessages,
          container.read(settingsProvider),
          testModel,
        );
    expect(result, isNull);
    expect(engine.calls, 1);
    expect(engine.previewedCounts, [3]);
    expect(messages.map((m) => m['content']), [
      filled('s', 100),
      filled('q', 400),
      filled('t', 400),
    ]);
  });

  test(
    'dropping several exchanges costs one measure and one confirm preview',
    () async {
      final engine = _CountingEngine(contextSize: 2000, reservedTokens: 200);
      final (container, db) = await mount(engine);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final messages = [
        msg('system', filled('s', 100)),
        for (var i = 1; i <= 4; i++) ...[
          msg('user', filled('u$i', 1000)),
          msg('assistant', filled('a$i', 1000)),
        ],
        msg('user', filled('q', 1000)),
        msg('assistant', filled('c', 1000)),
        msg('tool', filled('t', 400)),
      ];
      final toolMessages = [messages.last];
      final result = await container
          .read(chatProvider.notifier)
          .fitToolResults(
            engine,
            messages,
            toolMessages,
            container.read(settingsProvider),
            testModel,
          );
      // 10500 chars = 2625 tokens against 1800 usable: the two oldest
      // exchanges (500 tokens each) cover the 825-token deficit in one round,
      // then a single preview confirms the fit — not one full re-render per
      // dropped message (audit N23).
      expect(result, isNull);
      expect(engine.calls, 2);
      expect(engine.previewedCounts, [12, 8]);
      expect(messages.length, 8);
      expect(messages.first['role'], 'system');
      expect(messages[1]['content'], filled('u3', 1000));
      expect(messages.last['role'], 'tool');
      expect(messages.last['content'], filled('t', 400));
    },
  );

  test(
    'a tool result too large to drop is cut once, confirmed by one preview',
    () async {
      final engine = _CountingEngine(contextSize: 1000);
      final (container, db) = await mount(engine);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final original = filled('t', 7000);
      final messages = [
        msg('system', filled('s', 100)),
        msg('user', filled('q', 100)),
        msg('tool', original),
      ];
      final toolMessages = [messages[2]];
      final result = await container
          .read(chatProvider.notifier)
          .fitToolResults(
            engine,
            messages,
            toolMessages,
            container.read(settingsProvider),
            testModel,
          );
      final marker = stringsFor(
        container.read(settingsProvider).localeCode,
      ).toolCutMiddleMarker;
      final expected = cutMiddle(
        original,
        original.runes.length ~/ 2,
        marker: marker,
      );
      // 7200 chars = 1800 tokens against 1000: nothing can be dropped (the
      // last user turn is the only exchange), so the result is halved once
      // and the second preview confirms the fit.
      expect(result, isNotNull);
      expect(result, contains('1 cut'));
      expect(engine.calls, 2);
      expect(engine.previewedCounts, [3, 3]);
      expect(messages.length, 3);
      expect(messages[0]['content'], filled('s', 100));
      expect(messages[1]['content'], filled('q', 100));
      expect(messages[2]['content'], expected);
      expect(toolMessages.single['content'], expected);
    },
  );
}

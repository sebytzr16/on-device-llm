// The chat path end to end on a real model (the tester's Gemma 4 E2B):
// multi-turn memory, a long attached document, small talk speed, code,
// phone-action cards and live web answers with known facts. Nothing is
// mocked except the settings and model list. Prints one QUALITY: JSON line
// per turn with the time, metrics and answer. Run through
// scripts/test-android.ps1 -Model <gguf> -Family gemma
// -Test integration_test/app_quality_probe_test.dart on a phone online.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _family = String.fromEnvironment('MODEL_FAMILY', defaultValue: 'gemma');

final _model = ModelInfo(
  id: 'quality',
  displayName: 'Quality probe model',
  fileName: _modelPath.split('/').last,
  sizeBytes: 0,
  family: ModelFamily.values.byName(_family),
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: _modelPath,
);

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      webMode: WebMode.auto,
      contextSize: 8192,
      maxTokens: 512,
      temperature: 0,
      thinkingModeEnabled: false,
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [_model], loadedModelId: null);
  }

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
  }) async {
    await ref
        .read(llamaEngineProvider)
        .loadModel(
          modelPath: info.localPath!,
          settings: ref.read(settingsProvider),
        );
    state = state.copyWith(loadedModelId: info.id);
  }
}

/// A long house manual with one fact buried in the middle.
String _manual() {
  final b = StringBuffer('Lakeview Apartment — house manual\n\n');
  const filler = [
    'Recycling goes in the blue bins behind building C; glass is collected on Mondays.',
    'Quiet hours run from 10 pm to 7 am on weekdays and until 9 am on weekends.',
    'Guests may use the rooftop terrace until 11 pm if they sign the logbook.',
    'Bicycles must be stored in the basement room, never in the hallways.',
    'The laundry room machines take tokens sold by the concierge for 2 euros each.',
  ];
  for (var i = 0; i < 40; i++) {
    b.writeln('Section ${i + 1}. ${filler[i % filler.length]}');
    if (i == 22) {
      b.writeln(
        'Section 23b. The Wi-Fi network is LakeviewGuest and its password '
        'is heron-4471. The router is in the hallway cupboard.',
      );
    }
  }
  return b.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('chat quality: memory, documents, actions, web', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Quality probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    expect(await File(_modelPath).exists(), true);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = LlamaEngine(
      cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_Settings.new),
        modelManagerProvider.overrideWith(_Models.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      engine.dispose();
      await db.close();
    });
    final failures = <String>[];

    Future<String> turn(
      String probe,
      String q, {
      List<Attachment> attachments = const [],
      List<Pattern> expectAll = const [],
      bool wantSources = false,
      bool noSources = false,
      bool wantAction = false,
    }) async {
      final n = container.read(chatProvider.notifier);
      final clock = Stopwatch()..start();
      final ok = await n.send(q, attachments: attachments);
      clock.stop();
      final s = container.read(chatProvider);
      final answer = s.messages.last;
      final sources = jsonDecode(answer.sourcesJson) as List;
      final run = TurnRun.decode(answer.runJson);
      final actions = PhoneActions.fromTrace(run?.toolTrace ?? const []);
      final text = answer.content;
      final missing = [
        for (final p in expectAll)
          if (!text.toLowerCase().contains(p is String ? p.toLowerCase() : p))
            '$p',
      ];
      final problems = [
        if (!ok || s.error != null) 'error: ${s.error}',
        if (missing.isNotEmpty) 'missing: ${missing.join(', ')}',
        if (wantSources && sources.isEmpty) 'no sources',
        if (noSources && sources.isNotEmpty) 'searched needlessly',
        if (wantAction && actions.isEmpty) 'no action card',
      ];
      if (problems.isNotEmpty) failures.add('$probe: ${problems.join('; ')}');
      // ignore: avoid_print
      print(
        'QUALITY: ${jsonEncode({
          'probe': probe,
          'family': _family,
          'question': q,
          'pass': problems.isEmpty,
          'problems': problems,
          'seconds': clock.elapsed.inMilliseconds / 1000,
          'notice': s.notice,
          'sources': [for (final src in sources) src['url']],
          'actions': [for (final a in actions) a.toJson()],
          'metrics': {for (final e in s.metrics.entries)
            if (e.value is num || e.value is String) e.key: e.value},
          'answer': text,
        })}',
      );
      return text;
    }

    final n = container.read(chatProvider.notifier);

    // 1. Small talk: no search, no tools, fast.
    n.newChat();
    await turn('small-talk', 'Hi! How are you today?', noSources: true);

    // 2. Multi-turn memory across four turns.
    n.newChat();
    await turn(
      'memory-1',
      'My name is Lina. I am planning a trip to Lisbon in May with my '
          'sister Marta, and our budget is 1,200 euros.',
      noSources: true,
    );
    await turn(
      'memory-2',
      'Suggest three neighbourhoods to stay in, one line each.',
    );
    await turn(
      'memory-3',
      'Remind me: what is my name, who am I travelling with, where, when, '
          'and what is our budget?',
      expectAll: ['Lina', 'Marta', 'Lisbon', 'May', '1,200'],
      noSources: true,
    );

    // 3. A long document with one buried fact, then a follow-up.
    n.newChat();
    final manual = _manual();
    await turn(
      'document-1',
      'What is the Wi-Fi password in this manual?',
      attachments: [
        Attachment(
          id: 'manual',
          kind: AttachmentKind.document,
          name: 'house-manual.txt',
          mime: 'text/plain',
          path: '${(await getApplicationCacheDirectory()).path}/manual.txt',
          sizeBytes: manual.length,
          text: manual,
        ),
      ],
      expectAll: ['heron-4471'],
    );
    await turn(
      'document-2',
      'And when is glass collected, and where is the router?',
      expectAll: ['Monday', 'cupboard'],
    );

    // 4. Code.
    n.newChat();
    await turn(
      'code',
      'Write a Python function is_palindrome(s) that ignores case, spaces '
          'and punctuation. Code only.',
      expectAll: ['def is_palindrome', 'lower'],
      noSources: true,
    );

    // 5. Phone actions: a card, no web search.
    n.newChat();
    await turn(
      'action-reminder',
      'Remind me tomorrow at 9 am to call the dentist.',
      wantAction: true,
      noSources: true,
    );
    n.newChat();
    await turn(
      'action-timer',
      'Set a timer for 12 minutes for the pasta.',
      wantAction: true,
      noSources: true,
    );

    // 6. Live web: facts that do not change.
    n.newChat();
    await turn(
      'web-who',
      'When did the WHO declare COVID-19 a pandemic?',
      expectAll: ['11', 'March', '2020'],
      wantSources: true,
    );
    n.newChat();
    await turn(
      'web-z30',
      'How much does the Nikon Z30 weigh with battery?',
      expectAll: ['405'],
      wantSources: true,
    );
    // Follow-up that depends on the previous turn's subject.
    await turn(
      'web-followup',
      'And how many shots does its battery last?',
      expectAll: ['330'],
    );
    n.newChat();
    await turn(
      'web-fr',
      'Quelle est la hauteur de la tour Eiffel ?',
      expectAll: ['330'],
      wantSources: true,
    );

    // ignore: avoid_print
    print('QUALITY-SUMMARY: ${jsonEncode({'failures': failures})}');
    // The report is the deliverable; only a broken pipeline fails the run.
    expect(
      failures.where((f) => f.contains('error:')),
      isEmpty,
      reason: failures.join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 40)));
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

import 'chat_test.dart' show TestModels, TestSettings, TestSearch, TestReader;

const _nikon = 'Nikon Z30 sensor resolution is 20.9 MP';
const _sony = 'Sony ZV-E10 sensor resolution is 24.2 MP';

class _GoalRemoteSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    remoteEnabled: true,
    webMode: WebMode.auto,
    remoteProfileId: 'fixture',
    remoteProfiles: const [
      RemoteProfile(
        id: 'fixture',
        name: 'Camera fixture',
        providerId: 'gemini',
        baseUrl: 'https://example.com',
        model: 'fixture-model',
      ),
    ],
  );
}

class _CameraSearch extends TestSearch {
  @override
  Future<List<SearchResult>> search(
    String query, {
    int limit = 5,
    CancelToken? cancelToken,
    String localeCode = '',
    String? dateFilter,
    String? region,
  }) async {
    queries.add(query);
    calls++;
    final sony = query.toLowerCase().contains('sony');
    return [
      SearchResult(
        title: '${sony ? 'Sony ZV-E10' : 'Nikon Z30'} sensor specifications',
        url: 'https://example.com/${sony ? 'sony' : 'nikon'}',
        snippet: '${sony ? _sony : _nikon}.',
        rank: 1,
      ),
    ];
  }
}

class _CameraReader extends TestReader {
  @override
  Future<WebPage> read(
    Uri uri, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 12),
    String language = 'en-US,en;q=0.9',
  }) async => WebPage(
    title: 'Camera specifications',
    text:
        '${List.filled(250, 'Navigation and marketing information.\n').join()}\n${uri.path.contains('sony') ? _sony : _nikon}.',
    finalUri: uri,
    fetchedAt: DateTime(2026, 9, 27),
  );
}

class _GoalRemoteEngine extends RemoteEngine {
  final phases = <String, List<Map<String, Object>>>{};
  int oversizedReviews = 0;

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    final result = await super.previewPrompt(
      messages: messages,
      fallbackTemplate: fallbackTemplate,
      settings: settings,
      assistantPrefix: assistantPrefix,
      tools: tools,
    );
    if (messages.first['content'].toString().startsWith(
      'You review research',
    )) {
      // Exercise prompt fitting with a smaller available reviewer window.
      const window = 8192;
      final reserve = settings.maxTokens.clamp(0, window ~/ 2);
      final prompt = result['promptTokens'] as int;
      final fits = prompt + reserve <= window;
      if (!fits) oversizedReviews++;
      return {
        ...result,
        'contextSize': window,
        'reservedTokens': reserve,
        'fits': fits,
      };
    }
    return result;
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    final system = messages.first['content'].toString();
    final prompt = messages.last['content'].toString();
    metrics = {'promptTokens': (prompt.length / 3.5).ceil(), 'tokens': 100};
    if (system.startsWith('Help the user clarify')) {
      phases['questions'] = messages;
      yield '{"questions":[{"question":"What will you use the camera for?","options":["Cooking videos","Travel photos"]}]}';
    } else if (system.startsWith('You plan research')) {
      phases['plan'] = messages;
      yield jsonEncode({
        'steps': [
          'What are the Nikon Z30 sensor specifications?',
          'What are the Sony ZV-E10 sensor specifications?',
        ],
      });
    } else if (system.startsWith('You review research')) {
      phases['review'] = messages;
      final preview = await previewPrompt(
        messages: messages,
        fallbackTemplate: fallbackTemplate,
        settings: settings,
      );
      expect(
        preview['fits'],
        isTrue,
        reason: 'Oversized evidence must be fitted before generation',
      );
      expect(prompt, contains('20.9 MP'));
      expect(prompt, contains('24.2 MP'));
      yield jsonEncode({
        'satisfied': false,
        'missing': ['Exhaustive laboratory tests'],
        'criteria': [
          {
            'id': 'C1',
            'satisfied': true,
            'steps': [1, 2],
            'quotes': [
              {'step': 1, 'quote': '$_nikon [1].'},
              {'step': 2, 'quote': '$_sony [2].'},
            ],
            'evidence': [
              {'source': 1, 'quote': '$_nikon.'},
              {'source': 2, 'quote': '$_sony.'},
            ],
            'explanation':
                'These facts support a sensor comparison and a recommendation based on resolution.',
          },
        ],
      });
    } else if (prompt.contains('search-engine queries')) {
      yield prompt.contains('Sony')
          ? 'Sony ZV-E10 sensor specifications'
          : 'Nikon Z30 sensor specifications';
    } else if (prompt.startsWith('Write the final report') ||
        prompt.contains('This report for the goal below')) {
      phases['report'] = messages;
      yield '$_nikon [1]. $_sony [2]. For the requested comparison, choose Sony ZV-E10 if sensor resolution is your priority; Nikon Z30 has the lower resolution [1, 2].';
    } else {
      final sony = prompt.contains('Question: What are the Sony');
      phases[sony ? 'sony' : 'nikon'] = messages;
      yield '${List.filled(300, 'Additional context about the camera.\n').join()}${sony ? _sony : _nikon} [1].';
    }
  }
}

void main() {
  test(
    'camera Goal asks, resumes, researches both models, fits evidence and completes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final engine = _GoalRemoteEngine();
      final search = _CameraSearch();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          remoteEngineProvider.overrideWithValue(engine),
          settingsProvider.overrideWith(_GoalRemoteSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          duckDuckGoScraperProvider.overrideWithValue(search),
          webPageReaderProvider.overrideWithValue(_CameraReader()),
        ],
      );
      addTearDown(() async {
        container.dispose();
        engine.dispose();
        await db.close();
      });
      final notifier = container.read(goalProvider.notifier);
      await notifier.start(
        const GoalSpec(
          objective:
              'Compare Nikon Z30 to Sony ZV-E10: specification differences, where each is better, and a recommendation',
          successCriteria: 'Compare sensor resolutions and recommend one',
          specialization: GoalSpecialization.product,
          maxSteps: null,
          maxDuration: null,
          maxTokens: null,
          maxToolCalls: null,
        ),
      );
      expect(container.read(goalProvider)!.awaitingInputSince, isNotNull);
      expect(search.calls, 0);
      await notifier.answerClarifications({'Q1': 'Cooking videos'});
      final result = container.read(goalProvider)!;
      expect(result.error, isNull);
      expect(result.status, GoalStatus.completed);
      expect(result.tasks, hasLength(2));
      expect(result.reviews, 1);
      expect(result.sources, hasLength(2));
      expect(result.report, contains('choose Sony ZV-E10'));
      expect(result.reportChecks.where((c) => c.fixable), isEmpty);
      expect(engine.oversizedReviews, greaterThan(0));
      for (final phase in ['plan', 'nikon', 'sony', 'review', 'report']) {
        expect(
          engine.phases[phase].toString(),
          contains('Cooking videos'),
          reason: phase,
        );
      }
      await notifier.refine(
        result.spec.copyWith(
          searchGuidance:
              'Focus the searches and report on sensor resolution for cooking videos.',
        ),
        run: true,
      );
      final refined = container.read(goalProvider)!;
      expect(refined.status, GoalStatus.completed);
      expect(refined.error, isNull);
      expect(refined.tasks, hasLength(4));
      expect(refined.sources, hasLength(2));
      for (final phase in ['plan', 'nikon', 'sony', 'review', 'report']) {
        expect(
          engine.phases[phase].toString(),
          contains('Focus the searches and report'),
          reason: phase,
        );
      }
    },
  );
}

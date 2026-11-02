import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/helper/helper_request.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/tools/domain/tool_aliases.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

ToolRunner _runner({Future<String> Function(String, String)? helper}) =>
    ToolRunner(
      scraper: DuckDuckGoScraper(),
      reader: WebPageReader(),
      settings: const InferenceSettings(),
      helper: helper,
    );

ToolCall _call(String args) =>
    ToolCall(id: '1', name: 'ask_helper', arguments: args);

void main() {
  test(
    'explicit sub-agent requests survive greetings and have a bounded fallback',
    () {
      for (final input in [
        'Hi, use the sub-agent to write a title',
        'Use the helper',
        'Utilise le sub-agent',
        'Usa el subagente',
      ]) {
        expect(HelperRequest.wanted(input), isTrue, reason: input);
        expect(RetrievalPlan.smallTalk(input), isFalse, reason: input);
        final call = HelperRequest.fallback(
          input,
          offered: true,
          round: 0,
          lastRound: false,
        )!;
        expect(call.name, 'ask_helper');
        expect(call.args['input'], input);
        expect(
          HelperRequest.fallback(
            input,
            offered: false,
            round: 0,
            lastRound: false,
          ),
          isNull,
        );
        expect(
          HelperRequest.fallback(
            input,
            offered: true,
            round: 1,
            lastRound: false,
          ),
          isNull,
        );
        expect(
          HelperRequest.fallback(
            input,
            offered: true,
            round: 0,
            lastRound: true,
          ),
          isNull,
        );
      }
      for (final input in [
        "Don't use the helper",
        'How do I use the sub-agent?',
        'hi',
      ]) {
        expect(HelperRequest.wanted(input), isFalse);
      }
    },
  );

  test(
    'helper aliases are recognized by both protocols and dispatch correctly',
    () async {
      for (final alias in [
        'helper',
        'sub-agent',
        'ask_sub_agent',
        'functions.ask_helper',
      ]) {
        expect(ToolAliases.known(alias), isTrue);
        final result =
            await _runner(helper: (task, input) async => '$task: $input').run(
              ToolCall(
                id: '1',
                name: alias,
                arguments: '{"prompt":"Title","context":"Notes"}',
              ),
            );
        expect(result.ok, isTrue);
        expect(ToolRunner.helperReplyText(result.output), 'Title: Notes');
      }
    },
  );

  test('the helper switch is off by default and persists', () {
    const s = InferenceSettings();
    expect(s.toolHelper, isFalse);
    expect(s.helperModelId, isEmpty);
    final on = InferenceSettings.fromJson(
      s.copyWith(toolHelper: true, helperModelId: 'lfm-1.7b').toJson(),
    );
    expect(on.toolHelper, isTrue);
    expect(on.helperModelId, 'lfm-1.7b');
    for (final key in ['toolHelper', 'helperModelId']) {
      expect(SettingSpec.all.any((spec) => spec.key == key), isTrue);
    }
  });

  test('ask_helper is offered only with a helper', () {
    expect(_runner().specs().any((s) => s.name == 'ask_helper'), isFalse);
    final runner = _runner(helper: (_, _) async => '');
    expect(runner.specs().any((s) => s.name == 'ask_helper'), isTrue);
  });

  test('ask_helper passes the task and input and marks the reply', () async {
    String? task, input;
    final runner = _runner(
      helper: (t, i) async {
        task = t;
        input = i;
        return '- one\n- two';
      },
    );
    final result = await runner.run(
      _call('{"task": "List the points", "input": "${'x' * 20000}"}'),
    );
    expect(result.ok, isTrue);
    expect(task, 'List the points');
    expect(input!.length, ToolRunner.maxHelperInputChars);
    expect(result.output, startsWith(ToolRunner.helperPrefix));
    expect(ToolRunner.helperReplyText(result.output), '- one\n- two');
  });

  test('ask_helper refuses a page this turn did not read', () async {
    var called = false;
    final runner = _runner(
      helper: (_, _) async {
        called = true;
        return 'x';
      },
    );
    final result = await runner.run(
      _call('{"task": "Summarise", "url": "https://example.com/a"}'),
    );
    expect(result.ok, isFalse);
    expect(called, isFalse);
  });

  test('a helper failure is an error result, not a crash', () async {
    final runner = _runner(
      helper: (_, _) async => throw StateError('helper model not downloaded'),
    );
    final result = await runner.run(_call('{"task": "Summarise"}'));
    expect(result.ok, isFalse);
    expect(result.output, contains('not downloaded'));
  });
}

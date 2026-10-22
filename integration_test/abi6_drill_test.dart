// Bridge ABI 6 on a real model (roadmap P0 §3): structured output (JSON,
// JSON schema, GBNF), stop sequences, one native tool call under
// Tool use = Required, and draft-model speculation when a second GGUF is
// given. Run through scripts/test-android.ps1 -Model <gguf>
// -Test integration_test/abi6_drill_test.dart [-Backend opencl]; add
// --dart-define=DRAFT_MODEL=<on-device path> for the speculation pass.
// Prints one DRILL: JSON line per check.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('ABI 6 drill on a real model', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('ABI 6 drill'))),
    );
    const modelPath = String.fromEnvironment('BENCH_MODEL');
    const draftPath = String.fromEnvironment('DRAFT_MODEL');
    const backendName = String.fromEnvironment(
      'SMOKE_BACKEND',
      defaultValue: 'cpu',
    );
    expect(modelPath, isNotEmpty, reason: 'Pass -Model to test-android.ps1');
    expect(await File(modelPath).exists(), true);
    final engine = LlamaEngine(
      cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
    );
    addTearDown(engine.dispose);
    final base = InferenceSettings(
      backend: GpuBackend.values.byName(backendName),
      contextSize: 4096,
      maxTokens: 160,
      temperature: 0,
      thinkingModeEnabled: false,
    );
    await engine.loadModel(modelPath: modelPath, settings: base);
    void report(String check, Map<String, Object?> data) {
      // ignore: avoid_print
      print('DRILL: ${jsonEncode({'check': check, ...data})}');
    }

    Future<String> ask(
      String user,
      InferenceSettings s, {
      List<ToolSpec> tools = const [],
      String toolChoice = 'auto',
    }) => engine
        .generate(
          messages: [
            {'role': 'system', 'content': 'You are a precise assistant.'},
            {'role': 'user', 'content': user},
          ],
          fallbackTemplate: '',
          settings: s,
          tools: tools,
          toolChoice: toolChoice,
        )
        .join();

    // 1. JSON object.
    var text = await ask(
      'Describe a fictional person as a JSON object with keys name and age.',
      base.copyWith(responseFormat: ResponseFormat.json),
    );
    Object? parsed;
    try {
      parsed = jsonDecode(text.trim());
    } catch (_) {}
    report('json', {
      'valid': parsed is Map,
      'finish': engine.metrics['finishReason'],
      'sample': text.length > 120 ? text.substring(0, 120) : text,
    });
    expect(parsed, isA<Map>(), reason: 'JSON mode produced: $text');

    // 2. JSON schema: the keys and types are forced, not suggested.
    const schema =
        '{"type":"object","properties":{"city":{"type":"string"},"population":{"type":"integer"},"coastal":{"type":"boolean"}},"required":["city","population","coastal"],"additionalProperties":false}';
    text = await ask(
      'Give facts about Lisbon.',
      base.copyWith(
        responseFormat: ResponseFormat.jsonSchema,
        jsonSchema: schema,
      ),
    );
    Map? obj;
    try {
      obj = jsonDecode(text.trim()) as Map?;
    } catch (_) {}
    report('json_schema', {
      'valid': obj != null,
      'keys': obj?.keys.toList(),
      'sample': text.length > 120 ? text.substring(0, 120) : text,
    });
    expect(obj, isNotNull, reason: 'Schema mode produced: $text');
    expect(obj!['city'], isA<String>());
    expect(obj['population'], isA<int>());
    expect(obj['coastal'], isA<bool>());

    // 3. GBNF: only two spellings are legal.
    text = await ask(
      'Is water wet? Answer with one word.',
      base.copyWith(
        responseFormat: ResponseFormat.gbnf,
        grammar: 'root ::= "yes" | "no"',
      ),
    );
    report('gbnf', {'text': text});
    expect(['yes', 'no'], contains(text.trim()));

    // 4. Stop sequence: counting stops before "4"; the hold-back must not
    //    leak the stop text.
    text = await ask(
      'Count from 1 to 10, one number per line, digits only.',
      base.copyWith(stopSequences: const ['4']),
    );
    report('stop', {'text': text, 'finish': engine.metrics['finishReason']});
    expect(text, isNot(contains('4')));
    expect(engine.metrics['finishReason'], 'stop');

    // 5. Native tool call under Required: the template's tool-call grammar
    //    engages only on generated text (the bug fixed on 2026-09-19 fired
    //    it on the system prompt's own <tool_call> example).
    final supportsTools = engine.metrics['supportsTools'] == true;
    const calculator = ToolSpec(
      name: 'calculator',
      description: 'Evaluates an arithmetic expression exactly.',
      parameters: {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string', 'description': 'e.g. 17*23'},
        },
        'required': ['expression'],
      },
    );
    if (supportsTools) {
      text = await ask(
        'What is 17 multiplied by 23? Use the calculator.',
        base,
        tools: const [calculator],
        toolChoice: 'required',
      );
      final calls = TextEngine.toolCallsOf(engine.metrics);
      report('tool_call_required', {
        'format': engine.metrics['toolFormat'],
        'calls': [for (final c in calls) c.toJson()],
        'text': text.length > 160 ? text.substring(0, 160) : text,
      });
      expect(calls, isNotEmpty, reason: 'No tool call parsed from: $text');
      expect(calls.first.name, 'calculator');
      expect('${calls.first.args['expression']}', contains('17'));
      // Auto: a plain greeting must not be forced into a call, and — the
      // 2026-09-19 regression — must not abort on the prompt's example.
      text = await ask('hi', base, tools: const [calculator]);
      report('tool_call_auto_greeting', {
        'calls': TextEngine.toolCallsOf(engine.metrics).length,
        'text': text.length > 120 ? text.substring(0, 120) : text,
      });
      expect(text.trim(), isNotEmpty);
    } else {
      report('tool_call_required', {'skipped': 'template has no tool format'});
    }

    // 6. Draft-model speculation, when a second model is supplied.
    if (draftPath.isNotEmpty && await File(draftPath).exists()) {
      final comparison = base.copyWith(maxTokens: 120, promptCache: false);
      await engine.unload();
      await engine.loadModel(modelPath: modelPath, settings: comparison);
      final plain = Stopwatch()..start();
      final reference = await ask(
        'List the planets of the solar system in order, one per line.',
        comparison,
      );
      plain.stop();
      final plainTps = engine.metrics['tokensPerSecond'];
      final repeated = await ask(
        'List the planets of the solar system in order, one per line.',
        comparison,
      );
      await engine.loadModel(
        modelPath: modelPath,
        settings: comparison.copyWith(draftMaxTokens: 6),
        draftModelPath: draftPath,
      );
      final spec = Stopwatch()..start();
      final drafted = await ask(
        'List the planets of the solar system in order, one per line.',
        comparison.copyWith(draftMaxTokens: 6),
      );
      spec.stop();
      final m = engine.metrics;
      report('speculation', {
        'draft': m['draftModel'],
        'proposed': m['draftProposed'],
        'accepted': m['draftAccepted'],
        'rounds': m['draftRounds'],
        'disabled': m['draftDisabled'],
        'replays': m['draftReplays'],
        'speedup': m['draftSpeedup'],
        'plainTps': plainTps,
        'draftedTps': m['tokensPerSecond'],
        'plainMs': plain.elapsedMilliseconds,
        'draftedMs': spec.elapsedMilliseconds,
        'sameText': reference.trim() == drafted.trim(),
        'plainRepeatMatches': reference.trim() == repeated.trim(),
        'reference': reference,
        'drafted': drafted,
      });
      expect(drafted.trim(), isNotEmpty);
    } else {
      report('speculation', {'skipped': 'no DRAFT_MODEL'});
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}

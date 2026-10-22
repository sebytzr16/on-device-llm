import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/presets/domain/preset.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/tools/calculator.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/tools/tool_runner.dart';

void main() {
  group('calculator', () {
    test('arithmetic, precedence and functions', () {
      expect(Calculator.evaluate('1 + 2 * 3'), 7);
      expect(Calculator.evaluate('(1 + 2) * 3'), 9);
      expect(Calculator.evaluate('2 ^ 3 ^ 2'), 512);
      expect(Calculator.evaluate('-4 + 10 % 3'), -3);
      expect(Calculator.evaluate('sqrt(16) + abs(-2)'), 6);
      expect(Calculator.evaluate('max(1, 5, 3) - min(2, 0)'), 5);
      expect(Calculator.evaluate('round(2.5) + floor(2.9)'), 5);
      expect(Calculator.evaluate('log10(1000)'), closeTo(3, 1e-9));
      expect(Calculator.evaluate('2 × 3 ÷ 4'), 1.5);
      expect(Calculator.evaluate('1,200 * 1.07^5'), closeTo(1683.06, 0.01));
      expect(Calculator.evaluate('pi * e'), closeTo(8.5397, 1e-3));
    });
    test('rejects unsafe or malformed input', () {
      expect(() => Calculator.evaluate('1 / 0'), throwsFormatException);
      expect(() => Calculator.evaluate('foo(1)'), throwsFormatException);
      expect(() => Calculator.evaluate('1 +'), throwsFormatException);
      expect(() => Calculator.evaluate('import os'), throwsFormatException);
      expect(() => Calculator.evaluate('(1 + 2'), throwsFormatException);
    });
    test('formats results the way people write them', () {
      expect(Calculator.format(7), '7');
      expect(Calculator.format(1.5), '1.5');
      expect(Calculator.format(1 / 3), '0.3333333333');
    });
  });

  group('text tool protocol', () {
    test('parses a fenced tool block and strips it', () {
      const answer =
          'Let me check.\n```tool\n{"name": "search_web", "arguments": {"query": "qwen 3.5 release"}}\n```';
      final calls = TextToolProtocol.parse(answer, counter: 1);
      expect(calls, hasLength(1));
      expect(calls.first.name, 'search_web');
      expect(calls.first.args['query'], 'qwen 3.5 release');
      expect(calls.first.id, 'call_1');
      expect(TextToolProtocol.strip(answer), 'Let me check.');
    });
    test('ignores prose and non-tool JSON', () {
      expect(TextToolProtocol.parse('Just an answer.', counter: 1), isEmpty);
      expect(
        TextToolProtocol.parse('```json\n{"answer": 1}\n```', counter: 1),
        isEmpty,
      );
    });
    test('instructions list every tool', () {
      final text = TextToolProtocol.instructions(const [
        ToolSpec(name: 'calculator', description: 'Math.', parameters: {}),
      ]);
      expect(text, contains('calculator'));
      expect(text, contains('```tool'));
      expect(text, isNot(contains('MUST be a tool call')));
      expect(
        TextToolProtocol.instructions(const [
          ToolSpec(name: 'calculator', description: 'Math.', parameters: {}),
        ], required: true),
        contains('MUST be a tool call'),
      );
    });
  });

  test('decode threads drop to four when layers run on a GPU', () {
    const cpu = InferenceSettings(backend: GpuBackend.cpu);
    const gpu = InferenceSettings(backend: GpuBackend.opencl);
    const gpuNoLayers = InferenceSettings(
      backend: GpuBackend.opencl,
      nGpuLayers: 0,
    );
    expect(gpu.effectiveThreads, lessThanOrEqualTo(cpu.effectiveThreads));
    expect(gpu.effectiveThreads, lessThanOrEqualTo(4));
    expect(gpuNoLayers.effectiveThreads, cpu.effectiveThreads);
    // An explicit count always wins.
    expect(gpu.copyWith(cpuThreads: 6).effectiveThreads, 6);
    // Prefill keeps every core either way.
    expect(
      gpu.effectiveBatchThreads,
      greaterThanOrEqualTo(gpu.effectiveThreads),
    );
  });

  group('settings cascade', () {
    test('layers resolve in order and record their origin', () {
      final r = SettingsResolver.resolve(
        global: const InferenceSettings(temperature: 0.9, maxTokens: 512),
        model: const {'temperature': 0.2, 'contextSize': 8192},
        preset: const {'temperature': 0.5, 'thinkingModeEnabled': true},
        chat: const {'maxTokens': 2048},
        turn: const {'webMode': 'always'},
      );
      expect(r.effective.temperature, 0.5);
      expect(r.originOf('temperature'), SettingsLayer.idPreset);
      expect(r.effective.contextSize, 8192);
      expect(r.originOf('contextSize'), SettingsLayer.idModel);
      expect(r.effective.maxTokens, 2048);
      expect(r.originOf('maxTokens'), SettingsLayer.idChat);
      expect(r.effective.webMode, WebMode.always);
      expect(r.originOf('webMode'), SettingsLayer.idTurn);
      expect(r.effective.thinkingModeEnabled, isTrue);
      expect(r.originOf('topP'), SettingsLayer.idDefault);
      expect(r.reloadKeys, ['contextSize']);
      expect(r.requested['temperature']!.map((e) => e.$1), [
        SettingsLayer.idGlobal,
        SettingsLayer.idModel,
        SettingsLayer.idPreset,
      ]);
    });
    test('unknown and privacy keys in a layer are ignored', () {
      final r = SettingsResolver.resolve(
        global: const InferenceSettings(),
        chat: const {
          'remoteEnabled': true,
          'memoryEnabled': true,
          'nonsense': 1,
          'temperature': 'hot',
          'topK': 999,
        },
      );
      expect(r.effective.remoteEnabled, isFalse);
      expect(r.effective.memoryEnabled, isFalse);
      expect(r.originOf('temperature'), SettingsLayer.idDefault);
      // Out-of-range values are clamped by the spec, not dropped.
      expect(r.effective.topK, 200);
    });
    test('the API key survives resolution without being persisted', () {
      final r = SettingsResolver.resolve(
        global: const InferenceSettings(
          remoteProfiles: [RemoteProfile(id: 'a', name: 'a')],
          remoteApiKeys: {'a': 'secret'},
        ),
        chat: const {'temperature': 0.1},
      );
      expect(r.effective.remoteApiKey, 'secret');
      expect(r.effective.toJson().containsKey('remoteApiKey'), isFalse);
      expect(r.effective.toJson().containsKey('remoteApiKeys'), isFalse);
    });
    test('presets expose typed fields and generic overrides as one layer', () {
      const p = Preset(
        id: 'x',
        name: 'x',
        emoji: '',
        systemPrompt: '',
        temperature: 0.3,
        thinking: false,
        overrides: {'maxTokens': 256, 'temperature': 0.4},
      );
      final o = p.toOverrides();
      expect(o['temperature'], 0.4);
      expect(o['thinkingModeEnabled'], false);
      expect(o['maxTokens'], 256);
      final round = Preset.fromJson(p.toJson());
      expect(round.overrides['maxTokens'], 256);
      expect(p.apply(const InferenceSettings()).maxTokens, 256);
    });
    test('every spec key exists in the settings JSON', () {
      final json = const InferenceSettings().toJson();
      expect(
        SettingSpec.all.map((s) => s.key).toSet().length,
        SettingSpec.all.length,
        reason: 'Every setting must have one canonical scope registration.',
      );
      for (final spec in SettingSpec.all) {
        expect(json.containsKey(spec.key), isTrue, reason: spec.key);
      }
    });
  });

  group('inference settings (ABI 6 controls)', () {
    test('round-trips the new controls and clamps them', () {
      const s = InferenceSettings(
        seed: 42,
        stopSequences: ['###', 'END'],
        presencePenalty: 0.5,
        frequencyPenalty: 0.25,
        repeatLastN: 128,
        typicalP: 0.9,
        xtcProbability: 0.3,
        dryMultiplier: 0.8,
        samplerOrder: ['temperature', 'top_k'],
        vCacheType: KvCacheType.q8_0,
        ropeScaling: RopeScaling.yarn,
        yarnOrigCtx: 32768,
        responseFormat: ResponseFormat.jsonSchema,
        jsonSchema: '{"type":"object"}',
        toolsEnabled: true,
        toolChoice: ToolChoice.required,
        draftModelId: 'qwen35-0.8b-iq4nl',
        themeChoice: ThemeChoice.light,
        accent: AccentChoice.violet,
        textScale: 1.2,
      );
      final r = InferenceSettings.fromJson(s.toJson());
      expect(r.seed, 42);
      expect(r.stopSequences, ['###', 'END']);
      expect(r.presencePenalty, 0.5);
      expect(r.frequencyPenalty, 0.25);
      expect(r.repeatLastN, 128);
      expect(r.typicalP, 0.9);
      expect(r.xtcProbability, 0.3);
      expect(r.dryMultiplier, 0.8);
      // A partial order is completed with the missing samplers, in default order.
      expect(r.samplerOrder.take(2), ['temperature', 'top_k']);
      expect(r.samplerOrder.toSet(), InferenceSettings.samplerNames.toSet());
      expect(r.vCacheType, KvCacheType.q8_0);
      expect(r.effectiveVCacheType, KvCacheType.q8_0);
      expect(r.ropeScaling, RopeScaling.yarn);
      expect(r.yarnOrigCtx, 32768);
      expect(r.responseFormat, ResponseFormat.jsonSchema);
      expect(r.toJson()['responseFormat'], 'json_schema');
      expect(r.structuredOutput, isTrue);
      expect(r.toolsEnabled, isTrue);
      expect(r.toolChoice, ToolChoice.required);
      expect(r.toJson()['toolChoice'], 'required');
      expect(
        InferenceSettings.fromJson(const {'toolChoice': 'weird'}).toolChoice,
        ToolChoice.auto,
      );
      expect(r.draftModelId, 'qwen35-0.8b-iq4nl');
      expect(r.themeChoice, ThemeChoice.light);
      expect(r.accent, AccentChoice.violet);
      expect(r.textScale, 1.2);
      expect(const InferenceSettings().vCacheType, isNull);
      expect(
        InferenceSettings.fromJson(const {
          'stopSequences': ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'],
          'textScale': 9,
          'responseFormat': 'weird',
        }).stopSequences.length,
        InferenceSettings.maxStopSequences,
      );
      expect(InferenceSettings.fromJson(const {'textScale': 9}).textScale, 1.4);
      expect(
        InferenceSettings.fromJson(const {
          'responseFormat': 'weird',
        }).responseFormat,
        ResponseFormat.text,
      );
    });
  });
}

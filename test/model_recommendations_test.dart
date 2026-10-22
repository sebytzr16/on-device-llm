import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/domain/model_recommendations.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_recommendations_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';

// Request 2026-10-04: every model starts with the sampling its makers
// recommend; anything the user sets stays on top.
ModelInfo _model(String file, {String id = 'm'}) => ModelInfo(
  id: id,
  displayName: file.replaceAll('.gguf', ''),
  fileName: file,
  sizeBytes: 1,
  family: ModelFamily.other,
  quantization: ModelQuantization.unknown,
  license: '',
);

void main() {
  group('sources', () {
    test('GGUF sampling keys become settings, top-k off as 0', () {
      final r = ModelRecommendations.fromGguf({
        'general.sampling.temp': 1.0,
        'general.sampling.top_k': 64,
        'general.sampling.top_p': 0.95,
      });
      expect(r.values, {'temperature': 1.0, 'topK': 64, 'topP': 0.95});
      expect(r.sources, [ModelRecommendations.sourceFile]);
      expect(
        ModelRecommendations.fromGguf({'general.sampling.top_k': -1}).values,
        {'topK': 0},
      );
    });

    test('generation_config: greedy ignored, bad values dropped', () {
      expect(
        ModelRecommendations.fromGenerationConfig({
          'do_sample': false,
          'temperature': 0.6,
        }).isEmpty,
        isTrue,
      );
      final r = ModelRecommendations.fromGenerationConfig({
        'temperature': 0.6,
        'top_p': 0.9,
        'repetition_penalty': 0.5,
        'bos_token_id': 1,
      });
      expect(r.values, {'temperature': 0.6, 'topP': 0.9});
    });

    test('repository of a download link', () {
      expect(
        ModelRecommendations.repoOf(
          'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/abc/x.gguf',
        ),
        'unsloth/gemma-4-E2B-it-GGUF',
      );
      expect(ModelRecommendations.repoOf('https://example.com/a/b/c'), isNull);
      expect(ModelRecommendations.repoOf(null), isNull);
    });

    test('model card table matches the families', () {
      expect(
        ModelRecommendations.builtIn('Qwen3.5-0.8B-Q8_0.gguf').values,
        containsPair('presencePenalty', 1.5),
      );
      expect(
        ModelRecommendations.builtIn('Qwen3-1.7B-Q4_K_M.gguf').values,
        containsPair('topP', 0.8),
      );
      expect(
        ModelRecommendations.builtIn(
          'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
        ).values,
        containsPair('topK', 64),
      );
      expect(ModelRecommendations.builtIn('mystery-7b.gguf').isEmpty, isTrue);
    });

    test('a file overrides the card, except for split thinking cards', () {
      final gemma = recommendationFor(_model('gemma-4-E2B-it.gguf'), {
        'm': const ModelRecommendation(
          values: {'topP': 0.9},
          sources: [ModelRecommendations.sourceFile, 'checked'],
        ),
      });
      expect(gemma.values['topP'], 0.9);
      expect(gemma.values['topK'], 64);
      expect(gemma.sources, isNot(contains('checked')));
      // Qwen3's file carries its thinking values; without thinking the
      // card's non-thinking ones must win.
      final qwen = recommendationFor(_model('Qwen3-1.7B.gguf'), {
        'm': const ModelRecommendation(
          values: {'temperature': 0.6, 'topP': 0.95},
          sources: [ModelRecommendations.sourceFile],
        ),
      });
      expect(qwen.values['temperature'], 0.7);
      expect(qwen.thinking['temperature'], 0.6);
    });
  });

  group('cascade', () {
    const rec = {'temperature': 1.0, 'topK': 64, 'repetitionPenalty': 1.0};

    test('recommended values beat app defaults, not the user', () {
      var r = SettingsResolver.resolve(
        global: const InferenceSettings(),
        recommended: rec,
      );
      expect(r.effective.temperature, 1.0);
      expect(r.effective.topK, 64);
      expect(r.originOf('temperature'), SettingsLayer.idRecommended);
      expect(r.overriddenKeys, isEmpty);
      r = SettingsResolver.resolve(
        global: const InferenceSettings(temperature: 0.3),
        recommended: rec,
      );
      expect(r.effective.temperature, 0.3);
      expect(r.effective.topK, 64);
      r = SettingsResolver.resolve(
        global: const InferenceSettings(),
        recommended: rec,
        model: {'topK': 20},
      );
      expect(r.effective.topK, 20);
    });

    test('thinking values apply only while thinking is on', () {
      const thinking = {'temperature': 0.6};
      var r = SettingsResolver.resolve(
        global: const InferenceSettings(),
        recommended: rec,
        recommendedThinking: thinking,
      );
      expect(r.effective.temperature, 1.0);
      r = SettingsResolver.resolve(
        global: const InferenceSettings(),
        recommended: rec,
        recommendedThinking: thinking,
        chat: {'thinkingModeEnabled': true},
      );
      expect(r.effective.temperature, 0.6);
      expect(r.effective.topK, 64);
    });

    test(
      'saved legacy choices are preserved even when they matched defaults',
      () {
        const big = InferenceSettings(contextSize: 8192);
        final moved = migrateSamplingDefaults(
          const InferenceSettings(repetitionPenalty: 1.1, contextSize: 4096),
          big,
        );
        expect(moved.repetitionPenalty, 1.1);
        expect(moved.contextSize, 4096);
        final kept = migrateSamplingDefaults(
          const InferenceSettings(repetitionPenalty: 1.3, contextSize: 16384),
          big,
        );
        expect(kept.repetitionPenalty, 1.3);
        expect(kept.contextSize, 16384);
        expect(
          migrateSamplingDefaults(
            const InferenceSettings(contextSize: 4096),
            const InferenceSettings(contextSize: 4096),
          ).contextSize,
          4096,
        );
      },
    );

    test('device defaults scale the context with memory', () {
      expect(InferenceSettings.forDevice(4).contextSize, 2048);
      expect(InferenceSettings.forDevice(8).contextSize, 4096);
      expect(InferenceSettings.forDevice(12).contextSize, 8192);
      expect(const InferenceSettings().repetitionPenalty, 1.0);
    });
  });
}

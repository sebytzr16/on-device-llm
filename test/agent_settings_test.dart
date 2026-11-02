import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/helper/helper_request.dart';

void main() {
  test(
    'agent settings round trip, inherit sampling and reset independently',
    () {
      final settings =
          const InferenceSettings(
            topP: .8,
            minP: .1,
            topK: 37,
            repetitionPenalty: 1.2,
          ).copyWith(
            agentMaxTokens: 3000,
            agentTemperature: .6,
            agentContextSize: 16384,
            agentMaxConcurrent: 4,
            agentThinking: true,
            agentToolRounds: 5,
            agentWebAccess: AgentWebAccess.never,
            agentInstructions: 'Compare carefully.',
            agentInputBudget: 12000,
          );
      final restored = InferenceSettings.fromJson(settings.toJson());
      expect(restored.toJson(), settings.toJson());
      final generation = restored.forAgent();
      expect(generation.maxTokens, 3000);
      expect(generation.contextSize, 16384);
      expect(generation.temperature, .6);
      expect(generation.topP, .8);
      expect(generation.minP, .1);
      expect(generation.topK, 37);
      expect(generation.repetitionPenalty, 1.2);
      expect(generation.thinkingModeEnabled, true);
      final overridden = settings
          .copyWith(
            agentTopP: .7,
            agentMinP: .2,
            agentTopK: 10,
            agentRepeatPenalty: 1.1,
          )
          .forAgent();
      expect(overridden.topP, .7);
      expect(overridden.minP, .2);
      expect(overridden.topK, 10);
      expect(overridden.repetitionPenalty, 1.1);
      final reset = settings.resetAgents();
      for (final entry in const InferenceSettings().toJson().entries.where(
        (e) => e.key.startsWith('agent'),
      )) {
        expect(reset.toJson()[entry.key], entry.value, reason: entry.key);
      }
      expect(reset.topK, 37);
    },
  );

  test('untrusted agent settings clamp; small contexts leave prompt space', () {
    final s = InferenceSettings.fromJson({
      'agentMaxTokens': 99999,
      'agentTemperature': double.nan,
      'agentContextSize': -1,
      'agentMaxConcurrent': 20,
      'agentToolRounds': -3,
      'agentInputBudget': -20,
      'agentWebAccess': 'unknown',
    });
    expect(s.agentMaxTokens, 4096);
    expect(s.agentTemperature, .3);
    expect(s.agentContextSize, 512);
    expect(s.agentMaxConcurrent, 4);
    expect(s.agentToolRounds, 1);
    expect(s.agentInputBudget, 256);
    expect(s.agentWebAccess, AgentWebAccess.askOnce);
    expect(s.forAgent().maxTokens, lessThan(s.agentContextSize));
    expect(s.copyWith(agentMaxTokens: 1).agentMaxTokens, 64);
    for (final budget in [256, 4800, 12000]) {
      final content = HelperRequest.content(
        'Summarise',
        'long input ' * 9000,
        budget: budget,
      );
      expect(content.length, lessThanOrEqualTo(budget));
    }
  });
}

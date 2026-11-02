import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_suggestions.dart';

void main() {
  testWidgets(
    'suggestions use the existing catalog identities and exclude other picks',
    (tester) async {
      final picks = suggestedModels([], desktop: true);
      expect(picks.map((m) => m.id), [
        'qwen35-0.8b-q8_0',
        'qwen35-4b-iq4nl',
        'qwen35-9b-q4km',
        'gemma4-e2b-qat',
        'gemma4-e4b-qat',
        'lfm3-1.7b-q8',
        'qwen36-35b-a3b-q4km',
      ]);
      expect(
        picks.every((m) => [...bundledCatalog, ...desktopCatalog].contains(m)),
        isTrue,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [for (final m in picks) Text(m.displayName)],
            ),
          ),
        ),
      );
      expect(find.text('Qwen3.5 2B'), findsNothing);
      expect(find.text('Gemma 4 E4B'), findsOneWidget);
      const large = ModelInfo(
        id: 'hf-qwen35',
        displayName: 'Qwen3.5 35B',
        fileName: '35b.gguf',
        sizeBytes: 1,
        family: ModelFamily.qwen,
        quantization: ModelQuantization.q4_k_m,
      );
      expect(
        suggestedModels([], desktop: false).map((m) => m.id),
        isNot(contains(qwen36_35b.id)),
      );
      expect(modelSuggestionRank(large, desktop: false), isNull);
      expect(modelSuggestionRank(large, desktop: true), 6);
    },
  );
}

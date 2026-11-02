import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_brand.dart';

void main() {
  testWidgets('bundled brands render and unknown names get a letter', (
    tester,
  ) async {
    final names = [
      'unsloth/gemma-4',
      'Qwen/Qwen3.5',
      'nvidia/Nemotron',
      'ibm/granite',
      'meta-llama/Llama',
      'mistralai/Mistral',
      'microsoft/Phi-4',
      'LiquidAI/LFM3',
      'deepseek-ai/DeepSeek',
      'openai/gpt-oss',
      'HuggingFaceTB/SmolLM',
    ];
    expect(names.map(modelBrand).toSet(), hasLength(11));
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final name in names) ModelBrandIcon(name),
            const ModelBrandIcon('other/Zebra'),
          ],
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsAtLeastNWidgets(11));
    expect(find.text('Z'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

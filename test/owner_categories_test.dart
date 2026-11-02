import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_categories.dart';

void main() {
  for (final chips in [true, false]) {
    testWidgets('all model categories can be selected (chips: $chips)', (
      tester,
    ) async {
      ModelCategory? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ModelCategoryFilters(
                chips: chips,
                selected: selected,
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );
      for (final category in ModelCategory.values) {
        if (!chips) {
          // The phone keeps them behind one drop-down.
          await tester.tap(find.byKey(const ValueKey('model-category-menu')));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(ValueKey('model-category-${category.name}')),
        );
        await tester.pumpAndSettle();
        expect(selected, category);
      }
      expect(modelCategory('gemma-mtp.gguf'), ModelCategory.draft);
      expect(modelCategory('mmproj.gguf'), ModelCategory.projector);
      expect(modelCategory('embeddinggemma.gguf'), ModelCategory.embedding);
      expect(modelCategory('qwen-reranker.gguf'), ModelCategory.reranker);
      expect(modelCategory('kokoro.onnx'), ModelCategory.speech);
      expect(modelCategory('vae.safetensors'), ModelCategory.image);
      expect(modelCategory('qwen.gguf'), ModelCategory.llm);
    });
  }
}

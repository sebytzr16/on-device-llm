import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_capabilities.dart';

void main() {
  test('metadata and HF hints combine without assuming missing facts', () {
    final facts = ModelCapabilities.derive(
      metadata: const GgufMetadata(
        version: 3,
        tensorCount: 1,
        nextnPredictLayers: 1,
        supportsTools: true,
        supportsThinking: true,
        contextLength: 32768,
      ),
      tags: ['image-text-to-text', 'feature-extraction'],
    );
    expect([
      facts.tools,
      facts.thinking,
      facts.vision,
      facts.draft,
      facts.embedding,
    ], everyElement(isTrue));
    expect(facts.contextLength, 32768);
    expect(ModelCapabilities.derive().tools, isFalse);
  });
  testWidgets(
    'HF badges expose tools vision thinking draft embedding and context',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ModelCapabilityBadges(
                tags: [
                  'tool-use',
                  'vision',
                  'thinking',
                  'mtp',
                  'feature-extraction',
                ],
                contextLength: 8192,
              ),
            ),
          ),
        ),
      );
      for (final label in [
        'Tools',
        'Vision',
        'Thinking',
        'MTP / draft ready',
        'Embedding',
        '8192 tokens of context',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );
}

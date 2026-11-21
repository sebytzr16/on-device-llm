import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
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
  test('a LiteRT model badges vision only once the runtime probed it', () {
    final model = liteRtCatalog.first;
    // Its tags and file name say nothing until the runtime read the file:
    // no badge, not the "every LiteRT model sees" guess.
    expect(ModelCapabilities.derive(model: model).vision, isFalse);
    expect(
      ModelCapabilities.derive(model: model, liteRtVision: false).vision,
      isFalse,
    );
    expect(
      ModelCapabilities.derive(model: model, liteRtVision: true).vision,
      isTrue,
    );
  });
  testWidgets('HF badges show capabilities without a duplicate context chip', (
    tester,
  ) async {
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
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(tester.widget<Text>(find.text(label)).style?.fontFamily, 'Inter');
    }
    expect(find.text('8192 tokens of context'), findsNothing);
  });
}

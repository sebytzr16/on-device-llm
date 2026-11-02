import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/features/models/presentation/providers/hf_repository_provider.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/hf_model_card.dart';

void main() {
  test('YAML front matter is stripped with CRLF and BOM', () {
    expect(
      HuggingFace.stripFrontMatter(
        '\uFEFF---\r\nlicense: mit\r\n---\r\n# Card',
      ),
      '# Card',
    );
    expect(HuggingFace.stripFrontMatter('# Plain'), '# Plain');
  });
  testWidgets('card renders Markdown and metadata without network images', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hfReadmeProvider(('org/model', 'abc1234')).overrideWith(
            (ref) async =>
                '# Offline card\n![image](https://example.com/image.png)\n**Weights**',
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HfModelCard(
                files: HfRepoFiles(
                  repo: 'org/model',
                  revision: 'abc1234',
                  license: 'MIT',
                  files: [],
                  contextLength: 8192,
                  parameterCount: 4000000000,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline card'), findsOneWidget);
    expect(find.textContaining('8192'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_card.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_capabilities.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('clicking a downloaded model opens files metadata and profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        modelMetadataProvider('local.gguf').overrideWith(
          (ref) async => const GgufMetadata(
            version: 3,
            tensorCount: 1,
            architecture: 'qwen35',
            contextLength: 8192,
          ),
        ),
        modelDeviceMemoryProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await container.read(modelProfilesProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelCard(
                model: ModelInfo(
                  id: 'local',
                  displayName: 'Local Qwen',
                  fileName: 'local-Q4_K_M.gguf',
                  sizeBytes: 1000,
                  family: ModelFamily.qwen,
                  quantization: ModelQuantization.q4_k_m,
                  isDownloaded: true,
                  localPath: 'local.gguf',
                  license: 'Apache-2.0',
                  downloadUrl:
                      'https://huggingface.co/Qwen/Qwen3.5/resolve/main/local.gguf',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Local Qwen'));
    await tester.pumpAndSettle();
    expect(find.text('Model details'), findsOneWidget);
    expect(find.text('qwen35'), findsOneWidget);
    expect(find.text('Apache-2.0'), findsOneWidget);
    expect(find.text('Qwen/Qwen3.5'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Uses recommended defaults'), findsOneWidget);
  });
}

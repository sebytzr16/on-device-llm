import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/model_speed_results_provider.dart';
import 'package:ondevice_llm/desktop/model_speed_section.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/optimize/benchmark_receipt.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestModels, testModel;

/// Holds the draft lookup open so Start can be pressed again while the first
/// press is still setting up.
class SlowDraftModels extends TestModels {
  final gate = Completer<void>();
  int draftCalls = 0;

  @override
  Future<String?> draftPathFor(ModelInfo info, String draftModelId) async {
    draftCalls++;
    await gate.future;
    return null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        llamaEngineProvider.overrideWithValue(TestEngine()),
        modelManagerProvider.overrideWith(SlowDraftModels.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ModelSpeedSection(
                model: testModel,
                settings: InferenceSettings(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  Finder start() => find.ancestor(
    of: find.text('Speed test'),
    matching: find.byWidgetPredicate((w) => w is OutlinedButton),
  );

  testWidgets('a second Start press cannot begin a second speed test', (
    tester,
  ) async {
    final container = await show(tester);
    final models =
        container.read(modelManagerProvider.notifier) as SlowDraftModels;
    expect(tester.widget<OutlinedButton>(start()).onPressed, isNotNull);

    await tester.tap(start());
    await tester.pump();
    expect(models.draftCalls, 1);
    // The whole setup runs inside the first press: the button is busy at once,
    // not only once the draft file resolved.
    expect(container.read(sessionBusyProvider), isTrue);
    expect(tester.widget<OutlinedButton>(start()).onPressed, isNull);

    await tester.tap(start(), warnIfMissed: false);
    await tester.pump();
    expect(models.draftCalls, 1);
  });

  testWidgets('closing the page during the draft lookup starts no benchmark', (
    tester,
  ) async {
    final container = await show(tester);
    final models =
        container.read(modelManagerProvider.notifier) as SlowDraftModels;
    await tester.tap(start());
    await tester.pump();
    expect(models.draftCalls, 1);
    expect(container.read(sessionBusyProvider), isTrue);

    // The page closes while the lookup is still pending.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump();
    // The lookup resolves only after the page is gone.
    models.gate.complete();
    await tester.pumpAndSettle();

    // No run and no measured result, and the flag is released for the next
    // screen instead of staying busy for the rest of the session.
    expect(container.read(sessionBusyProvider), isFalse);
    expect(container.read(benchmarkReceiptsProvider), isEmpty);
    expect(container.read(modelSpeedResultsProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/widgets/stop_load_button.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';

/// Counts what the phone's loading rows send, without an engine.
class _Stops extends ModelManagerNotifier {
  int stops = 0;

  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState();
  }

  @override
  void stopLoad() => stops++;
}

void main() {
  testWidgets('a loading row stops the load through the one Stop action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [modelManagerProvider.overrideWith(_Stops.new)],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: StopLoadButton())),
        ),
      ),
    );
    // The phone rows reuse the desktop control, tooltip and word (OR-02).
    expect(find.byTooltip('Stop loading'), findsOneWidget);
    await tester.tap(find.byType(StopLoadButton));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StopLoadButton)),
      listen: false,
    );
    expect((container.read(modelManagerProvider.notifier) as _Stops).stops, 1);
  });
}

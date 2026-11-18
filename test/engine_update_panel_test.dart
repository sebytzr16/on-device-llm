import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_update_controller.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_update_panel.dart';

class _Fixed extends EngineUpdateController {
  _Fixed(this.view);
  final EngineUpdateView view;
  int updates = 0;

  @override
  EngineUpdateView build() => view;

  @override
  Future<void> update() async => updates++;
}

Future<_Fixed> _pump(WidgetTester tester, EngineUpdateView view) async {
  final fixed = _Fixed(view);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [engineUpdateProvider.overrideWith(() => fixed)],
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: EngineUpdatePanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixed;
}

void main() {
  testWidgets('built-in engine shows no remove or built-in rows', (
    tester,
  ) async {
    await _pump(tester, const EngineUpdateView());
    expect(find.textContaining('built in'), findsOneWidget);
    expect(find.byKey(const Key('engine-update-use-built-in')), findsNothing);
    expect(find.byKey(const Key('engine-update-remove')), findsNothing);
    expect(find.byKey(const Key('engine-update-install')), findsNothing);
  });

  testWidgets('an available pack offers Install with its size', (tester) async {
    final fixed = await _pump(
      tester,
      const EngineUpdateView(
        phase: EngineUpdatePhase.available,
        latest: 'engine-b12600',
        total: 50 * 1024 * 1024,
      ),
    );
    expect(find.textContaining('engine-b12600'), findsOneWidget);
    expect(find.textContaining('(50 MB)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('engine-update-install')));
    expect(fixed.updates, 1);
  });

  testWidgets('a pack in use offers the way back and removal', (tester) async {
    await _pump(
      tester,
      const EngineUpdateView(
        phase: EngineUpdatePhase.ready,
        installed: 'engine-b12600',
        reverted: true,
      ),
    );
    expect(find.byKey(const Key('engine-update-use-built-in')), findsOneWidget);
    expect(find.byKey(const Key('engine-update-remove')), findsOneWidget);
    expect(find.textContaining('next load'), findsOneWidget);
    expect(
      find.textContaining('built-in engine is in use again'),
      findsWidgets,
    );
  });

  testWidgets('downloading shows progress', (tester) async {
    await _pump(
      tester,
      const EngineUpdateView(
        phase: EngineUpdatePhase.downloading,
        latest: 'engine-b12600',
        received: 25,
        total: 100,
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('25%'), findsOneWidget);
  });
}

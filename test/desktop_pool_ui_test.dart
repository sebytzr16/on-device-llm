import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/platform/desktop_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/model_speed_results_provider.dart';
import 'package:ondevice_llm/desktop/models_page.dart';
import 'package:ondevice_llm/desktop/server_page.dart';
import 'package:ondevice_llm/features/benchmark/benchmark.dart';
import 'package:ondevice_llm/features/hosting/model_pool.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:ondevice_llm/features/hosting/presentation/pool_options_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

import 'advanced_pages_2_test.dart' show TestModels;

class _Host extends DeviceHostingNotifier {
  final ejected = <String>[];
  bool failEject = false;

  @override
  DeviceHostingState build() => DeviceHostingState(
    running: true,
    endpoint: 'http://localhost:8787/v1/',
    modelId: 'test',
    pooled: [
      PooledModel(
        id: 'draft',
        loading: true,
        busy: false,
        lastUsed: DateTime(2026, 10, 22, 12),
      ),
    ],
  );

  void showStates() => state = state.copyWith(
    pooled: [
      PooledModel(
        id: 'draft',
        loading: false,
        busy: true,
        lastUsed: DateTime(2026, 10, 22, 12),
      ),
    ],
  );

  void showIdle() => state = state.copyWith(
    pooled: [
      PooledModel(
        id: 'draft',
        loading: false,
        busy: false,
        lastUsed: DateTime(2026, 10, 22, 12),
      ),
    ],
  );

  @override
  Future<void> unloadPooled(String id) async {
    ejected.add(id);
    if (failEject) throw StateError('Still answering');
    state = state.copyWith(pooled: []);
  }
}

class _Options extends PoolOptionsNotifier {
  @override
  PoolOptions build() => const PoolOptions();

  @override
  Future<void> set(PoolOptions options) async => state = options;
}

class _Speeds extends ModelSpeedResults {
  @override
  Map<String, ModelSpeedResult> build() => {
    'draft': ModelSpeedResult(
      modelId: 'draft',
      shape: 'test',
      timestamp: DateTime(2026, 10, 22),
      samples: const [
        BenchmarkSample(
          prefillMs: 100,
          decodeTps: 42,
          peakRssMb: 100,
          promptTokens: 10,
          generated: 20,
        ),
      ],
    ),
  };
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'desktop_advanced': true}),
  );
  Future<ProviderContainer> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        deviceHostingProvider.overrideWith(_Host.new),
        poolOptionsProvider.overrideWith(_Options.new),
        modelManagerProvider.overrideWith(TestModels.new),
        modelSpeedResultsProvider.overrideWith(_Speeds.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(desktopPreferencesProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('server options update while running and bound the stepper', (
    tester,
  ) async {
    final container = await show(tester, const DesktopServerPage());
    await tester.tap(find.byKey(const Key('desktop-pool-jit')));
    await tester.pump();
    expect(container.read(poolOptionsProvider).jit, isTrue);
    expect(find.byKey(const Key('desktop-pool-copy-draft')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-pool-increase')));
    await tester.pump();
    expect(container.read(poolOptionsProvider).maxLoaded, 3);
    await tester.tap(find.byKey(const Key('desktop-pool-idle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never').last);
    await tester.pumpAndSettle();
    expect(container.read(poolOptionsProvider).idleUnload, isNull);
  });

  testWidgets('pin toggle updates options, tooltip and semantics', (
    tester,
  ) async {
    final container = await show(tester, const DesktopServerPage());
    final semantics = tester.ensureSemantics();
    final pin = find.byKey(const Key('desktop-pool-pin-draft'));
    expect(find.byTooltip('Pin model'), findsOneWidget);
    expect(
      tester.getSemantics(pin),
      matchesSemantics(
        label: 'Pin model',
        tooltip: 'Pin model',
        hasFocusAction: true,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasToggledState: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(pin);
    await tester.pump();
    expect(container.read(poolOptionsProvider).pinned, {'draft'});
    expect(find.byTooltip('Unpin model'), findsOneWidget);
    expect(
      find.descendant(of: pin, matching: find.byIcon(Icons.push_pin_rounded)),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(pin),
      matchesSemantics(
        label: 'Unpin model',
        tooltip: 'Unpin model',
        hasFocusAction: true,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(pin);
    await tester.pump();
    expect(container.read(poolOptionsProvider).pinned, isEmpty);
    expect(find.byTooltip('Pin model'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('server shows pool states and eject errors', (tester) async {
    final container = await show(tester, const DesktopServerPage());
    final host = container.read(deviceHostingProvider.notifier) as _Host;
    expect(find.text('Draft Model'), findsOneWidget);
    expect(find.text('Loading'), findsOneWidget);
    expect(find.textContaining('Last used'), findsOneWidget);
    host.showStates();
    await tester.pump();
    expect(find.text('Answering'), findsOneWidget);
    host.showIdle();
    await tester.pump();
    expect(find.text('Idle'), findsOneWidget);
    host.failEject = true;
    await tester.tap(find.byKey(const Key('desktop-pool-eject-draft')));
    await tester.pump();
    expect(host.ejected, ['draft']);
    expect(find.textContaining('Still answering'), findsOneWidget);
    host.failEject = false;
    await tester.tap(find.byKey(const Key('desktop-pool-eject-draft')));
    await tester.pump();
    expect(host.ejected, ['draft', 'draft']);
    expect(find.text('Draft Model'), findsNothing);
  });

  testWidgets(
    'models mark primary and pooled rows serving and show saved speed',
    (tester) async {
      await show(tester, const DesktopModelsPage());
      expect(find.text('SERVING'), findsNWidgets(2));
      expect(find.textContaining('42 tok/s'), findsOneWidget);
    },
  );
}

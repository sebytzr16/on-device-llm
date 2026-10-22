import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_page.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:ondevice_llm/features/hosting/presentation/qr_view.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings;

class RunningHost extends DeviceHostingNotifier {
  @override
  DeviceHostingState build() =>
      DeviceHostingState(
        running: true,
        endpoint: 'http://192.168.1.5:8787/v1/',
        token: 'abcdefghijklmnopqrstuvwxyz012345',
        modelId: 'test',
        startedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        activeClient: '192.168.1.9',
        liveTokens: 64,
        power: const DevicePower(level: 18, charging: false, thermalStatus: 2),
      ).withServed(
        ServedRequest(
          at: DateTime(2026, 9, 23, 10, 4, 5),
          client: '192.168.1.9',
          status: 200,
          stream: true,
          completion: true,
          promptTokens: 812,
          completionTokens: 240,
          tokensPerSecond: 27.5,
          took: const Duration(seconds: 12),
        ),
      );
}

/// Records the models loaded from the page.
class SwitchingModels extends TestModels {
  static final loaded = <String>[];

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
  }) async {
    loaded.add(info.id);
    state = state.copyWith(loadedModelId: info.id);
  }
}

Widget harness({bool running = false}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(TestSettings.new),
    modelManagerProvider.overrideWith(TestModels.new),
    if (running) deviceHostingProvider.overrideWith(RunningHost.new),
  ],
  child: MaterialApp(theme: AppTheme.dark, home: const DeviceHostingPage()),
);

void main() {
  testWidgets('setup: the port is checked as it is typed', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pump();
    expect(find.text('Test Model'), findsOneWidget);
    expect(find.text('Start server'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '80');
    await tester.pump();
    expect(find.text('Ports below 1024 are reserved on Android.'), findsOne);
    final start = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Start server'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('running: live numbers, QR pairing and a masked token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(running: true));
    await tester.pump();
    expect(find.textContaining('Answering 192.168.1.9 · 64 tokens'), findsOne);
    expect(find.text('27.5 tok/s'), findsOneWidget);
    expect(find.text('812'), findsOneWidget);
    expect(find.text('18%'), findsOneWidget);
    expect(find.text('moderate'), findsOneWidget);
    // The pairing code holds the token: hidden until asked for.
    expect(find.byType(QrView), findsNothing);
    await tester.tap(find.byKey(const Key('show-qr')));
    await tester.pump();
    expect(find.byType(QrView), findsOneWidget);
    expect(find.text('•••••••• 2345'), findsOneWidget);
    await tester.tap(find.byTooltip('Show token'));
    await tester.pump();
    expect(find.text('abcdefghijklmnopqrstuvwxyz012345'), findsOneWidget);
    expect(find.textContaining('10:04:05 · 192.168.1.9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup: the model row picks and loads another model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(384, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SwitchingModels.loaded.clear();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(SwitchingModels.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (_, child) =>
              MotionScope(choice: MotionChoice.off, child: child!),
          home: const DeviceHostingPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Choose a model to serve.'), findsNothing);
    await tester.tap(find.byKey(const Key('host-model')));
    await tester.pumpAndSettle();
    expect(find.text('Model to serve'), findsOneWidget);
    expect(find.byKey(const Key('host-model-test')), findsOneWidget);
    expect(find.byKey(const Key('host-model-manage')), findsOneWidget);
    await tester.tap(find.byKey(const Key('host-model-draft')));
    await tester.pumpAndSettle();
    expect(SwitchingModels.loaded, ['draft']);
    expect(find.text('Draft Model'), findsOneWidget);
    expect(find.text('Start server'), findsOneWidget);
  });

  testWidgets('running: the model cannot change mid-answer', (tester) async {
    tester.view.physicalSize = const Size(384, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(running: true));
    await tester.pump();
    final row = tester.widget<ListTile>(find.byKey(const Key('host-model')));
    expect(row.onTap, isNull);
  });
}

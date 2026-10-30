import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/platform/desktop_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:ondevice_llm/core/logging/developer_logs.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/logs_page.dart';
import 'package:ondevice_llm/desktop/server_page.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

import 'advanced_pages_2_test.dart' show TestModels;

class FakeDesktopHost extends DeviceHostingNotifier {
  int starts = 0;
  int stops = 0;
  int regenerations = 0;
  int? lastPort;
  static const token = 'abcdefghijklmnopqrstuvwxyz012345';
  @override
  DeviceHostingState build() => const DeviceHostingState();
  @override
  Future<void> start({required int port, bool lan = true}) async {
    starts++;
    lastPort = port;
    state = DeviceHostingState(
      running: true,
      endpoint: 'http://localhost:$port/v1/',
      token: token,
      modelId: 'test',
    );
  }

  @override
  Future<void> stop({String? reason}) async {
    stops++;
    state = const DeviceHostingState();
  }

  @override
  Future<void> regenerateToken() async {
    regenerations++;
    await stop();
  }

  void serve() => state = state.withServed(
    ServedRequest(
      at: DateTime(2026),
      client: 'localhost',
      status: 200,
      method: 'POST',
      path: DeviceModelServer.completionsPath,
      completion: true,
      promptTokens: 12,
      completionTokens: 7,
      took: const Duration(milliseconds: 42),
    ),
  );
}

Widget harness(Widget page, {ProviderContainer? container}) {
  final app = MaterialApp(
    theme: DesktopTheme.of(AccentChoice.amber, dark: true),
    home: Scaffold(body: page),
  );
  return container != null
      ? UncontrolledProviderScope(container: container, child: app)
      : ProviderScope(child: app);
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({'desktop_advanced': true}),
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => developerLogBuffer.clear());
  tearDown(() => developerLogBuffer.clear());

  Future<ProviderContainer> server(
    WidgetTester tester, {
    double width = 1300,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        deviceHostingProvider.overrideWith(FakeDesktopHost.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(desktopPreferencesProvider.notifier).ready;
    await tester.pumpWidget(
      harness(const DesktopServerPage(), container: container),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('server starts only on demand, validates port, and stops', (
    tester,
  ) async {
    final container = await server(tester);
    final host =
        container.read(deviceHostingProvider.notifier) as FakeDesktopHost;
    expect(host.starts, 0);
    await tester.enterText(find.byKey(const Key('server-port')), '65536');
    await tester.pump();
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    final start = find.ancestor(
      of: find.text('Start server'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(start).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('server-port')), '9191');
    await tester.pump();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(host.starts, 1);
    expect(host.lastPort, 9191);
    expect(find.text('http://localhost:9191/v1/'), findsOneWidget);
    expect(find.text('0.0.0.0:9191'), findsOneWidget);
    await tester.tap(find.text('Stop server'));
    await tester.pumpAndSettle();
    expect(host.stops, 1);
    expect(find.text('Stopped'), findsOneWidget);
  });

  testWidgets(
    'server masks, reveals, copies and regenerates token; requests update live',
    (tester) async {
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final container = await server(tester);
      final host =
          container.read(deviceHostingProvider.notifier) as FakeDesktopHost;
      await tester.tap(find.text('Start server'));
      await tester.pumpAndSettle();
      expect(find.text(FakeDesktopHost.token), findsNothing);
      await tester.tap(find.text('Reveal token'));
      await tester.pump();
      expect(find.text(FakeDesktopHost.token), findsOneWidget);
      await tester.tap(find.text('Hide token'));
      await tester.pump();
      expect(find.text(FakeDesktopHost.token), findsNothing);
      // Bind address, URL, token, then curl each have a copy control.
      await tester.tap(find.byTooltip('Copy').at(2));
      await tester.pump();
      expect(clipboard.last, FakeDesktopHost.token);
      host.serve();
      await tester.pump();
      expect(
        find.textContaining('POST /v1/chat/completions · 200 · 42 ms · 12 / 7'),
        findsOneWidget,
      );
      expect(
        find.text(
          'GET  /v1/models\nPOST /v1/chat/completions\n'
          'POST /v1/embeddings\nPOST /v1/rerank\nPOST /v1/messages',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Regenerate token'));
      await tester.pumpAndSettle();
      expect(host.regenerations, 1);
      expect(host.stops, 1);
      expect(find.text('Stopped'), findsOneWidget);
    },
  );

  testWidgets('server fits a narrow desktop panel', (tester) async {
    await server(tester, width: 600);
    expect(tester.takeException(), isNull);
  });

  test('request ring keeps the newest 200 entries', () {
    var state = const DeviceHostingState();
    for (var i = 0; i < 205; i++) {
      state = state.withServed(
        ServedRequest(at: DateTime(2026), client: '', status: 200, path: '/$i'),
      );
    }
    expect(state.log.length, 200);
    expect(state.log.first.path, '/204');
    expect(state.log.last.path, '/5');
  });

  test(
    'logger buffer bounds lines and exposes errors, timestamps and levels',
    () {
      final buffer = DeveloperLogBuffer();
      addTearDown(buffer.dispose);
      for (var i = 0; i < 2005; i++) {
        buffer.record(LogRecord(Level.INFO, 'line $i', 'engine'));
      }
      expect(buffer.entries.length, 2000);
      expect(buffer.entries.first.message, 'line 5');
      final record = LogRecord(Level.SEVERE, 'failed', 'engine', 'detail');
      buffer.record(record);
      expect(buffer.entries.last.message, 'detail');
      expect(buffer.entries.last.level, Level.SEVERE);
      expect(buffer.entries.last.time, record.time);
      expect(buffer.entries.last.tag, 'engine');
      buffer.clear();
      expect(buffer.entries, isEmpty);
    },
  );

  testWidgets('logs filter, pause, resume, copy visible entries and clear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    developerLogBuffer.record(LogRecord(Level.INFO, 'ready', 'engine'));
    developerLogBuffer.record(LogRecord(Level.SEVERE, 'failed', 'voice'));
    await tester.pumpWidget(harness(const DesktopLogsPage()));
    await tester.pumpAndSettle();
    expect(find.textContaining('engine: ready'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('logs-filter')), 'voice');
    await tester.pump();
    expect(find.textContaining('engine: ready'), findsNothing);
    await tester.tap(find.text('Copy all'));
    await tester.pump();
    expect(copied.last, contains('voice: failed'));
    expect(copied.last, isNot(contains('ready')));
    await tester.enterText(find.byKey(const Key('logs-filter')), '');
    await tester.tap(find.byKey(const Key('logs-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('engine: ready'), findsNothing);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    developerLogBuffer.record(LogRecord(Level.SEVERE, 'later', 'engine'));
    await tester.pump();
    expect(find.textContaining('engine: later'), findsNothing);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(find.textContaining('engine: later'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('No matching log entries.'), findsOneWidget);
    expect(developerLogBuffer.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logs follow new lines and pause holds the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var i = 0; i < 80; i++) {
      developerLogBuffer.record(LogRecord(Level.INFO, 'line $i', 'engine'));
    }
    await tester.pumpWidget(harness(const DesktopLogsPage()));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final scroll = list.controller!;
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    developerLogBuffer.record(LogRecord(Level.INFO, 'new line', 'engine'));
    await tester.pumpAndSettle();
    expect(scroll.offset, offset);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(scroll.position.minScrollExtent, 1));
  });
}

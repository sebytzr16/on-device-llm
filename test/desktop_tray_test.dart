import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/motion/spring_controls.dart';
import 'package:ondevice_llm/desktop/tray.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final t = lookupAppLocalizations(const Locale('en'));
  final calls = <MethodCall>[];

  List<DesktopTrayItem> menu({
    bool running = false,
    bool busy = false,
    bool canStart = true,
  }) => desktopTrayMenu(
    t,
    running: running,
    busy: busy,
    canStart: canStart,
    servedId: 'a',
    servedName: 'Alpha',
    models: [(id: 'a', name: 'Alpha'), (id: 'b', name: 'Beta')],
  );

  Future<void> select(String id) => messenger.handlePlatformMessage(
    DesktopTrayController.channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('selected', id)),
    (_) {},
  );

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(DesktopTrayController.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (_) async => null,
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(DesktopTrayController.channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
  });

  test('close policy covers all settings and server states', () {
    for (final serving in [false, true]) {
      for (final always in [false, true]) {
        final settings = DesktopTraySettings(
          whenServing: serving,
          always: always,
        );
        expect(settings.hidesOnClose(false), always);
        expect(settings.hidesOnClose(true), always || serving);
      }
    }
    expect(const DesktopTraySettings().hidesOnClose(false), false);
    expect(const DesktopTraySettings().hidesOnClose(true), true);
  });

  test('running and stopped menus reflect served model and availability', () {
    final running = menu(running: true);
    expect(running.map((i) => i.id), [
      'open',
      'status',
      'stop',
      'models',
      'quit',
    ]);
    expect(running[1].enabled, false);
    expect(running[1].label, 'Server: running on Alpha');
    expect(running[3].children!.map((i) => i.checked), [true, false]);
    final stopped = menu(canStart: false);
    expect(stopped[1].label, 'Server: stopped');
    expect(stopped[2].id, 'start');
    expect(stopped[2].enabled, false);
    expect(stopped[3].children!.every((i) => !i.checked), true);
    expect(menu(busy: true)[2].enabled, false);
    expect(menu(busy: true)[3].enabled, false);
    expect(menu(busy: true)[4].enabled, false);
    final empty = desktopTrayMenu(
      t,
      running: false,
      busy: false,
      canStart: false,
      servedId: null,
      servedName: '',
      models: [],
    );
    expect(empty[3].enabled, false);
  });

  test(
    'fake channel receives native menu and selected ids dispatch actions',
    () async {
      final actions = <String>[];
      final tray = DesktopTrayController(
        action: (id) async => actions.add(id),
        close: () async {},
        onError: (e, s) => fail('$e'),
      );
      addTearDown(tray.dispose);
      await tray.start();
      await tray.update(
        visible: true,
        tooltip: t.desktopTrayTooltip,
        items: menu(),
      );
      final payload = calls.single.arguments as Map;
      expect(payload['visible'], true);
      expect(payload['tooltip'], 'OnDevice LLM');
      final items = payload['items'] as List;
      expect(items[2], containsPair('id', 'start'));
      expect((items[3] as Map)['children'], hasLength(2));
      for (final id in [
        'open',
        'start',
        'model:b',
        'status',
        'bogus',
        'models',
        'quit',
      ]) {
        await select(id);
      }
      expect(actions, ['open', 'start', 'model:b', 'quit']);
      await tray.update(
        visible: true,
        tooltip: t.desktopTrayTooltipServing('Alpha'),
        items: menu(running: true),
      );
      await select('stop');
      expect(actions.last, 'stop');
      await tray.update(visible: true, tooltip: '', items: menu(busy: true));
      await select('start');
      await select('model:a');
      expect(actions.last, 'stop');
    },
  );

  test('close and tray actions cannot overlap', () async {
    final gate = Completer<void>();
    var closes = 0;
    final tray = DesktopTrayController(
      action: (_) => gate.future,
      close: () async => closes++,
      onError: (e, s) => fail('$e'),
    );
    addTearDown(tray.dispose);
    await tray.update(visible: true, tooltip: '', items: menu());
    final action = tray.dispatch('start');
    tray.onWindowClose();
    expect(closes, 0);
    gate.complete();
    await action;
    tray.onWindowClose();
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
  });

  test('failed native update can be retried before hiding', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(DesktopTrayController.channel, (
      _,
    ) async {
      if (++attempts == 1) throw PlatformException(code: 'tray');
      return null;
    });
    final tray = DesktopTrayController(
      action: (_) async {},
      close: () async {},
      onError: (e, s) => fail('$e'),
    );
    addTearDown(tray.dispose);
    await expectLater(
      tray.update(visible: true, tooltip: '', items: menu()),
      throwsA(isA<PlatformException>()),
    );
    await tray.update(visible: true, tooltip: '', items: menu());
    expect(attempts, 2);
  });

  test(
    'tray preferences and once-only notice survive a new container',
    () async {
      final container = ProviderContainer();
      final notifier = container.read(desktopTraySettingsProvider.notifier);
      await notifier.ready;
      await notifier.update(whenServing: false, always: true, notified: true);
      container.dispose();
      final next = ProviderContainer();
      addTearDown(next.dispose);
      await next.read(desktopTraySettingsProvider.notifier).ready;
      final settings = next.read(desktopTraySettingsProvider);
      expect(settings.whenServing, false);
      expect(settings.always, true);
      expect(settings.notified, true);
    },
  );

  testWidgets('settings switches persist both tray choices', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(desktopTraySettingsProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DesktopTraySettingsPanel()),
        ),
      ),
    );
    expect(find.text(t.desktopTrayWhenServing), findsOneWidget);
    await tester.tap(find.byType(SpringSwitch).at(1));
    await tester.pumpAndSettle();
    expect(container.read(desktopTraySettingsProvider).always, true);
  });
}

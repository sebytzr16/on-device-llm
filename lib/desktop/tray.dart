import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../core/l10n/l10n.dart';
import '../core/motion/spring_controls.dart';
import '../core/platform/desktop_host.dart';
import '../features/hosting/presentation/device_hosting_provider.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';

class DesktopTraySettings {
  final bool whenServing;
  final bool always;
  final bool notified;
  const DesktopTraySettings({
    this.whenServing = true,
    this.always = false,
    this.notified = false,
  });

  bool hidesOnClose(bool running) => always || (whenServing && running);
}

final desktopTraySettingsProvider =
    NotifierProvider<DesktopTraySettingsNotifier, DesktopTraySettings>(
      DesktopTraySettingsNotifier.new,
    );

class DesktopTraySettingsNotifier extends Notifier<DesktopTraySettings> {
  late Future<void> ready;
  Future<void> _writes = Future.value();
  bool _alive = true;
  @override
  DesktopTraySettings build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!_alive) return;
      state = DesktopTraySettings(
        whenServing: prefs.getBool('desktopTrayWhenServing') ?? true,
        always: prefs.getBool('desktopTrayAlways') ?? false,
        notified: prefs.getBool('desktopTrayNotified') ?? false,
      );
    });
    return const DesktopTraySettings();
  }

  Future<void> update({bool? whenServing, bool? always, bool? notified}) async {
    await ready;
    if (!_alive) return;
    final next = DesktopTraySettings(
      whenServing: whenServing ?? state.whenServing,
      always: always ?? state.always,
      notified: notified ?? state.notified,
    );
    state = next;
    _writes = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('desktopTrayWhenServing', next.whenServing);
      await prefs.setBool('desktopTrayAlways', next.always);
      await prefs.setBool('desktopTrayNotified', next.notified);
    });
    await _writes;
  }
}

class DesktopTraySettingsPanel extends ConsumerWidget {
  const DesktopTraySettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(desktopTraySettingsProvider);
    final notifier = ref.read(desktopTraySettingsProvider.notifier);
    return Column(
      children: [
        ListTile(
          title: Text(context.l10n.desktopTrayWhenServing),
          trailing: SpringSwitch(
            value: settings.whenServing,
            onChanged: (value) => notifier.update(whenServing: value),
          ),
        ),
        ListTile(
          title: Text(context.l10n.desktopTrayAlways),
          trailing: SpringSwitch(
            value: settings.always,
            onChanged: (value) => notifier.update(always: value),
          ),
        ),
      ],
    );
  }
}

class DesktopTrayItem {
  final String id;
  final String label;
  final bool enabled;
  final bool checked;
  final List<DesktopTrayItem>? children;
  const DesktopTrayItem(
    this.id,
    this.label, {
    this.enabled = true,
    this.checked = false,
    this.children,
  });

  Map<String, Object> toMap() => {
    'id': id,
    'label': label,
    'enabled': enabled,
    'checked': checked,
    if (children != null) 'children': children!.map((e) => e.toMap()).toList(),
  };
}

List<DesktopTrayItem> desktopTrayMenu(
  AppLocalizations t, {
  required bool running,
  required bool busy,
  required bool canStart,
  required String? servedId,
  required String servedName,
  required List<({String id, String name})> models,
}) => [
  DesktopTrayItem('open', t.desktopTrayOpen),
  DesktopTrayItem(
    'status',
    running ? t.desktopTrayRunning(servedName) : t.desktopTrayStopped,
    enabled: false,
  ),
  DesktopTrayItem(
    running ? 'stop' : 'start',
    running ? t.desktopTrayStop : t.desktopTrayStart,
    enabled: !busy && (running || canStart),
  ),
  DesktopTrayItem(
    'models',
    t.desktopTrayServeModel,
    enabled: !busy && models.isNotEmpty,
    children: [
      for (final model in models)
        DesktopTrayItem(
          'model:${model.id}',
          model.name,
          enabled: !busy,
          checked: running && servedId == model.id,
        ),
    ],
  ),
  DesktopTrayItem('quit', t.desktopTrayQuit, enabled: !busy),
];

/// Owns channel dispatch and serializes actions against close and model loading.
class DesktopTrayController with WindowListener {
  static const channel = MethodChannel('ondevice_llm/tray');
  final Future<void> Function(String) action;
  final Future<void> Function() close;
  final void Function(Object, StackTrace) onError;
  List<DesktopTrayItem> _items = [];
  bool _acting = false;
  bool _disposed = false;
  String? _lastUpdate;
  Future<void> _writes = Future.value();

  DesktopTrayController({
    required this.action,
    required this.close,
    required this.onError,
  });

  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'selected' && call.arguments is String) {
        await dispatch(call.arguments as String);
      }
    });
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  Future<void> dispatch(String id) async {
    bool enabled(List<DesktopTrayItem> items) => items.any(
      (item) =>
          item.enabled &&
          ((item.id == id && item.children == null) ||
              (item.children != null && enabled(item.children!))),
    );
    if (_disposed || _acting || !enabled(_items)) return;
    _acting = true;
    try {
      await action(id);
    } catch (error, stack) {
      onError(error, stack);
    } finally {
      _acting = false;
    }
  }

  Future<void> update({
    required bool visible,
    required String tooltip,
    required List<DesktopTrayItem> items,
  }) {
    _items = items;
    final data = {
      'visible': visible,
      'tooltip': tooltip,
      'items': items.map((e) => e.toMap()).toList(),
    };
    final encoded = jsonEncode(data);
    if (_lastUpdate == encoded) return _writes;
    _lastUpdate = encoded;
    _writes = _writes
        .catchError((Object _) {})
        .then((_) async {
          if (!_disposed) await channel.invokeMethod<void>('update', data);
        })
        .catchError((Object error, StackTrace stack) {
          _lastUpdate = null;
          Error.throwWithStackTrace(error, stack);
        });
    return _writes;
  }

  @override
  void onWindowClose() {
    if (_acting || _disposed) return;
    _acting = true;
    unawaited(close().catchError(onError).whenComplete(() => _acting = false));
  }

  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    channel.setMethodCallHandler(null);
  }
}

class DesktopTrayHost extends ConsumerStatefulWidget {
  final Widget child;
  const DesktopTrayHost({super.key, required this.child});
  @override
  ConsumerState<DesktopTrayHost> createState() => _DesktopTrayHostState();
}

class _DesktopTrayHostState extends ConsumerState<DesktopTrayHost> {
  DesktopTrayController? _tray;
  int _port = 8787;
  bool _lan = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    if (!DesktopHost.active) return;
    _tray = DesktopTrayController(
      action: _action,
      close: _close,
      onError: _error,
    );
    unawaited(_tray!.start().catchError(_error));
  }

  void _error(Object error, StackTrace stack) {
    Logger('desktop.tray').warning('Tray action failed', error, stack);
    if (!mounted) return;
    unawaited(_open());
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.desktopTrayActionFailed)),
    );
  }

  Future<void> _open() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    _hidden = false;
    await _sync();
  }

  Future<void> _quit() async {
    await ref.read(deviceHostingProvider.notifier).stop();
    await DesktopTrayController.channel.invokeMethod<void>('update', {
      'visible': false,
      'tooltip': '',
      'items': <Object>[],
    });
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _close() async {
    final notifier = ref.read(desktopTraySettingsProvider.notifier);
    await notifier.ready;
    if (!mounted) return;
    final settings = ref.read(desktopTraySettingsProvider);
    if (!settings.hidesOnClose(ref.read(deviceHostingProvider).running)) {
      await _quit();
      return;
    }
    // Confirm the icon exists before hiding the only way back to the window.
    _hidden = true;
    await _sync();
    await windowManager.hide();
    if (!settings.notified && mounted) {
      await DesktopTrayController.channel.invokeMethod<void>(
        'balloon',
        context.l10n.desktopTrayStillRunning,
      );
      await notifier.update(notified: true);
    }
  }

  Future<void> _action(String id) async {
    final hosting = ref.read(deviceHostingProvider.notifier);
    switch (id) {
      case 'open':
        await _open();
      case 'quit':
        await _quit();
      case 'stop':
        await hosting.stop();
      case 'start':
        await hosting.start(port: _port, lan: _lan);
      default:
        if (!id.startsWith('model:')) return;
        final model = ref
            .read(modelManagerProvider)
            .catalog
            .where((m) => m.id == id.substring(6) && m.isDownloaded)
            .firstOrNull;
        if (model == null) return;
        if (ref.read(deviceHostingProvider).modelId == model.id &&
            ref.read(deviceHostingProvider).running) {
          return;
        }
        await hosting.stop();
        await ref.read(modelManagerProvider.notifier).loadModel(model);
        if (!mounted) {
          return;
        }
        await hosting.start(port: _port, lan: _lan);
    }
    if (mounted && ref.read(deviceHostingProvider).error != null) {
      throw StateError(ref.read(deviceHostingProvider).error!);
    }
  }

  Future<void> _sync() async {
    if (!mounted || _tray == null) return;
    final t = context.l10n;
    final host = ref.read(deviceHostingProvider);
    final models = ref.read(modelManagerProvider);
    final settings = ref.read(desktopTraySettingsProvider);
    if (host.running && host.endpoint != null) {
      _port = Uri.parse(host.endpoint!).port;
      _lan = host.pairCode != null;
    }
    final servedName =
        models.catalog
            .where((m) => m.id == host.modelId)
            .firstOrNull
            ?.displayName ??
        host.modelId ??
        '';
    await _tray!.update(
      visible: _hidden || settings.hidesOnClose(host.running),
      tooltip: host.running
          ? t.desktopTrayTooltipServing(servedName)
          : t.desktopTrayTooltip,
      items: desktopTrayMenu(
        t,
        running: host.running,
        busy: host.starting || models.isLoadingModel,
        canStart: models.loadedModel != null,
        servedId: host.modelId,
        servedName: servedName,
        models: [
          for (final m in models.catalog)
            if (m.isDownloaded) (id: m.id, name: m.displayName),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tray != null) {
      ref.watch(
        deviceHostingProvider.select(
          (h) => (h.running, h.starting, h.modelId, h.endpoint),
        ),
      );
      ref.watch(
        modelManagerProvider.select(
          (m) => (m.catalog, m.loadedModelId, m.isLoadingModel),
        ),
      );
      ref.watch(desktopTraySettingsProvider);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_sync().catchError(_error)),
      );
    }
    return widget.child;
  }

  @override
  void dispose() {
    _tray?.dispose();
    super.dispose();
  }
}

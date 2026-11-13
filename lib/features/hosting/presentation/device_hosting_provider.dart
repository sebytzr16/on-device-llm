import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/platform/desktop_host.dart';
import '../../../core/l10n/l10n.dart';
import '../../settings/presentation/providers/settings_provider.dart';
import '../../../core/platform/device_info.dart';
import '../../../core/providers/shared_providers.dart';
import '../../../features/models/domain/entities/model_info.dart';
import '../../../inference/engine/llama_engine.dart';
import '../../../data/storage/model_storage.dart';
import '../../models/domain/entities/model_catalog.dart';
import '../../../features/models/presentation/providers/model_manager_provider.dart';
import '../device_model_server.dart';
import '../served_vector_engine.dart';
import '../server_usage.dart';
import '../host_discovery.dart';
import '../model_pool.dart';
import '../pairing_code.dart';
import '../hosting_tls.dart';
import '../paired_devices.dart';
import 'pool_options_provider.dart';
import 'hosted_workspace.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// When the server stops itself to protect the phone. Off (null) by default
/// for the battery; the thermal guard is always on at "severe".
class HostingGuards {
  /// Stop below this battery level unless charging; null = never.
  final int? minBattery;

  /// Stop at or above this Android thermal status (3 = severe).
  final int maxThermal;
  const HostingGuards({this.minBattery = 20, this.maxThermal = 3});
}

class DeviceHostingState {
  final List<PairedDevice> pairedDevices;
  final bool legacyTokenEnabled;
  final ServerUsage usage;
  final bool running;
  final bool starting;
  final String? endpoint;
  final String? token;

  /// Six digits a nearby device trades for its own credential (LAN only).
  final String? pairCode;
  final String? pairingSecret, hostId;
  final String? fingerprint;

  /// When the current code and QR secret rotate.
  final DateTime? pairExpiresAt;
  final String? modelId;

  /// Whether the served model has its own runtime (desktop, once the chat
  /// loaded another model) instead of sharing the chat's.
  final bool ownEngine;

  /// Desktop: the extra models the server holds besides [modelId].
  final List<PooledModel> pooled;
  final String? activeClient;
  final String? error;

  /// Why the server stopped itself (battery, heat), shown once stopped.
  final String? stoppedReason;
  final DateTime? startedAt;

  /// Pieces streamed so far for the request being answered.
  final int liveTokens;

  /// Most recent first, at most [DeviceHostingNotifier.logSize].
  final List<ServedRequest> log;
  final int answered, refused, failed;
  final int promptTokens, completionTokens;
  final Set<String> clients;
  final DevicePower? power;
  const DeviceHostingState({
    this.pairedDevices = const [],
    this.legacyTokenEnabled = true,
    this.usage = const ServerUsage(),
    this.running = false,
    this.starting = false,
    this.endpoint,
    this.token,
    this.pairCode,
    this.pairingSecret,
    this.hostId,
    this.fingerprint,
    this.pairExpiresAt,
    this.modelId,
    this.ownEngine = false,
    this.pooled = const [],
    this.activeClient,
    this.error,
    this.stoppedReason,
    this.startedAt,
    this.liveTokens = 0,
    this.log = const [],
    this.answered = 0,
    this.refused = 0,
    this.failed = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.clients = const {},
    this.power,
  });

  /// Average generation speed over the answered requests that reported one.
  double get averageTokensPerSecond {
    final rates = [
      for (final r in log)
        if (r.ok && r.completion && r.tokensPerSecond > 0) r.tokensPerSecond,
    ];
    return rates.isEmpty ? 0 : rates.reduce((a, b) => a + b) / rates.length;
  }

  /// What another OnDevice LLM app pastes (or scans) to connect: the
  /// Remote server page's "Paste connection" reads exactly this.
  String? get pairing =>
      endpoint == null || pairingSecret == null || hostId == null
      ? null
      : PairingQr(
          endpoint!,
          hostId!,
          pairingSecret!,
          fingerprint: fingerprint,
        ).encode();

  /// This state with one more request in the counters and the log. A
  /// refusal (bad token, busy, bad request) is not a failure of the phone.
  DeviceHostingState withServed(ServedRequest r) {
    const refusedCodes = {
      HttpStatus.unauthorized,
      HttpStatus.notFound,
      HttpStatus.tooManyRequests,
      HttpStatus.badRequest,
    };
    final wasRefused = refusedCodes.contains(r.status);
    return copyWith(
      usage: usage.record(r),
      log: [r, ...log.take(DeviceHostingNotifier.logSize - 1)],
      // A model listing is not an answer.
      answered: answered + (r.ok && r.completion ? 1 : 0),
      refused: refused + (wasRefused ? 1 : 0),
      failed: failed + (!r.ok && !wasRefused ? 1 : 0),
      promptTokens: promptTokens + r.promptTokens,
      completionTokens: completionTokens + r.completionTokens,
      // Only clients that got past the token count as connected devices.
      clients: r.status == HttpStatus.unauthorized
          ? clients
          : {...clients, r.client},
    );
  }

  DeviceHostingState copyWith({
    List<PairedDevice>? pairedDevices,
    bool? legacyTokenEnabled,
    ServerUsage? usage,
    bool? running,
    bool? starting,
    bool? ownEngine,
    List<PooledModel>? pooled,
    String? activeClient,
    bool clearClient = false,
    bool clearPairCode = false,
    String? pairCode,
    String? pairingSecret,
    String? hostId,
    DateTime? pairExpiresAt,
    String? error,
    int? liveTokens,
    List<ServedRequest>? log,
    int? answered,
    int? refused,
    int? failed,
    int? promptTokens,
    int? completionTokens,
    Set<String>? clients,
    DevicePower? power,
  }) => DeviceHostingState(
    pairedDevices: pairedDevices ?? this.pairedDevices,
    legacyTokenEnabled: legacyTokenEnabled ?? this.legacyTokenEnabled,
    usage: usage ?? this.usage,
    running: running ?? this.running,
    starting: starting ?? this.starting,
    endpoint: endpoint,
    token: token,
    pairCode: clearPairCode ? null : pairCode ?? this.pairCode,
    pairingSecret: pairingSecret ?? this.pairingSecret,
    hostId: hostId ?? this.hostId,
    fingerprint: fingerprint,
    pairExpiresAt: clearPairCode ? null : pairExpiresAt ?? this.pairExpiresAt,
    modelId: modelId,
    ownEngine: ownEngine ?? this.ownEngine,
    pooled: pooled ?? this.pooled,
    activeClient: clearClient ? null : activeClient ?? this.activeClient,
    error:
        error ??
        (pairCode != null &&
                ['en', 'fr', 'es'].any(
                  (locale) => this.error == stringsFor(locale).hostPairLocked,
                )
            ? null
            : this.error),
    stoppedReason: stoppedReason,
    startedAt: startedAt,
    liveTokens: liveTokens ?? this.liveTokens,
    log: log ?? this.log,
    answered: answered ?? this.answered,
    refused: refused ?? this.refused,
    failed: failed ?? this.failed,
    promptTokens: promptTokens ?? this.promptTokens,
    completionTokens: completionTokens ?? this.completionTokens,
    clients: clients ?? this.clients,
    power: power ?? this.power,
  );
}

class DeviceHostingNotifier extends Notifier<DeviceHostingState> {
  static const _tokenKey = 'device_host_access_token';
  static const _secure = FlutterSecureStorage();
  static const logSize = 200;

  /// How often battery and heat are checked while serving.
  static Duration powerInterval = const Duration(seconds: 30);

  DeviceModelServer? _server;
  ModelPool? _pool;
  // True while the served model moves to its own runtime: requests wait.
  bool _moving = false;
  Timer? _powerTimer;
  int _lifecycle = 0;
  bool _alive = true;
  HostingGuards guards = const HostingGuards();

  @override
  DeviceHostingState build() {
    ref.onDispose(() {
      _alive = false;
      _lifecycle++;
      _powerTimer?.cancel();
      final server = _server;
      _server = null;
      final pool = _pool;
      _pool = null;
      unawaited(_closeRuntimes(server, pool));
      if (server != null) {
        if (HostDiscovery.canAdvertise) {
          unawaited(HostDiscovery.stop().catchError((Object _) {}));
        }
        unawaited(DevicePower.keepScreenOn(false));
      }
    });
    return const DeviceHostingState();
  }

  static Future<void> _closeRuntimes(
    DeviceModelServer? server,
    ModelPool? pool,
  ) async {
    try {
      await server?.stop();
    } finally {
      await pool?.close();
    }
  }

  Future<String> readAccessToken() async {
    var token = await _secure.read(key: _tokenKey);
    if (token != null && token.length >= 32) return token;
    final random = Random.secure();
    token = base64UrlEncode(
      Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))),
    );
    await _secure.write(key: _tokenKey, value: token);
    return token;
  }

  /// [lan] false listens on this computer only (the desktop's default).
  Future<void> start({required int port, bool lan = true}) async {
    if (_server != null || state.starting) return;
    final lifecycle = ++_lifecycle;
    DeviceModelServer? startingServer;
    state = const DeviceHostingState(starting: true);
    try {
      if (port < 1 || port > 65535) {
        throw const FormatException('Port must be between 1 and 65535.');
      }
      final model = ref.read(modelManagerProvider).loadedModel;
      final engine = ref.read(llamaEngineProvider);
      if (model == null || !engine.isLoaded || engine.isBusy) {
        throw StateError('Load a local model and wait for it to become idle.');
      }
      final token = await readAccessToken();
      if (!_alive || lifecycle != _lifecycle) return;
      final devices = await PairedDevices.load();
      if (!_alive || lifecycle != _lifecycle) return;
      final localToken = PairingCode.secret();
      final pairCode = lan ? PairingCode.generate() : null;
      final manager = ref.read(modelManagerProvider.notifier);
      final pool = DesktopHost.active ? _newPool(model, lifecycle) : null;
      _pool = pool;
      final vectorFiles = <String, String>{};
      for (final entry in {
        embeddingModel.id: embeddingModel.fileName,
        'qwen3-reranker-0.6b-q8': supportCheckModel.fileName,
      }.entries) {
        final file = await ModelStorage.modelFile(entry.value);
        if (await file.exists()) vectorFiles[entry.key] = file.path;
      }
      final server = DeviceModelServer(
        engine: engine,
        settings: () => manager.servedSettings(model),
        modelId: model.id,
        fallbackTemplate: model.family.fallbackTemplate,
        accessToken: token,
        localAccessToken: localToken,
        pairedDevices: devices,
        onDevicesChanged: () {
          if (_alive && lifecycle == _lifecycle) {
            state = state.copyWith(
              pairedDevices: devices.devices,
              legacyTokenEnabled: devices.legacyEnabled,
            );
          }
        },
        workspace: hostedWorkspace(
          ref: ref,
          port: () => _server!.port!,
          token: localToken,
          primaryModel: model.id,
          hostSettings: () => manager.servedSettings(model),
          vision: (id) => ref.read(modelManagerProvider).vision.contains(id),
        ),
        pairCode: pairCode,
        onPairingChanged: () {
          final current = _server;
          if (!_alive || lifecycle != _lifecycle || current == null) return;
          state = state.copyWith(
            pairCode: current.pairingLocked ? null : current.pairCode,
            clearPairCode: current.pairingLocked,
            pairingSecret: current.pairingSecret,
            hostId: current.hostId,
            pairExpiresAt: current.pairExpiresAt,
          );
        },
        onPairingUnavailable: (locked) {
          if (!_alive || lifecycle != _lifecycle) return;
          final t = stringsFor(ref.read(settingsProvider).localeCode);
          state = state.copyWith(
            clearPairCode: true,
            error: locked ? t.hostPairLocked : t.hostPairExpired,
          );
        },
        router: pool,
        // The vector worker is independent: CPU on Android, the chat's GPU
        // policy on the desktop (audit E22).
        vectors: LocalServedVectorEngine(
          (id) => vectorFiles[id],
          availableModels: () => {
            for (final id in vectorFiles.keys)
              id: id == embeddingModel.id ? 'embedding' : 'rerank',
          },
          placement: () => ref.read(settingsProvider),
        ),
        hasProjector: (id) =>
            ref.read(modelManagerProvider).vision.contains(id),
        prepareMedia: (id, target) async {
          if (target is! LlamaEngine) return;
          final mediaModel = ref
              .read(modelManagerProvider)
              .catalog
              .where((candidate) => candidate.id == id)
              .firstOrNull;
          if (mediaModel == null) {
            throw StateError('The server model is no longer installed.');
          }
          await manager.loadServed(mediaModel, target, vision: true);
        },
        isAvailable: () {
          final e = _server?.engine ?? engine;
          // Sharing the chat's runtime: only while it holds this model
          // (not while the chat loads another or the same one back).
          final chat = ref.read(modelManagerProvider);
          final chatHolds =
              !chat.isLoadingModel && chat.loadedModelId == model.id;
          return !_moving &&
              (state.ownEngine || chatHolds) &&
              (e is! LlamaEngine || (e.isLoaded && !e.isBusy));
        },
        onSessionChange: (client) {
          if (_server == null || lifecycle != _lifecycle) return;
          state = client == null
              ? state.copyWith(clearClient: true, liveTokens: 0)
              : state.copyWith(activeClient: client, liveTokens: 0);
        },
        onProgress: (pieces) {
          // Every eighth piece is plenty for a counter on screen.
          if (_server != null && lifecycle == _lifecycle && pieces % 8 == 0) {
            state = state.copyWith(liveTokens: pieces);
          }
        },
        onServed: record,
      );
      startingServer = server;
      final tls = lan ? await HostingTls.load() : null;
      if (!_alive || lifecycle != _lifecycle) return;
      await server.start(
        address: lan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
        port: port,
        tls: tls,
      );
      if (!_alive || lifecycle != _lifecycle) {
        await server.stop();
        return;
      }
      _server = server;
      final host = lan ? await _localAddress() : '127.0.0.1';
      if (lan && host != null && HostDiscovery.canAdvertise) {
        try {
          await HostDiscovery.advertise(server.port!, address: host);
        } catch (_) {
          /* Manual pairing still works. */
        }
      }
      if (!_alive || lifecycle != _lifecycle) {
        await server.stop();
        return;
      }
      state = DeviceHostingState(
        running: true,
        endpoint: endpointFor(
          host,
          server.tlsPort ?? server.port!,
          ref.read(settingsProvider).localeCode,
          tls: lan,
        ),
        token: token,
        pairedDevices: devices.devices,
        legacyTokenEnabled: devices.legacyEnabled,
        fingerprint: tls?.fingerprint,
        pairCode: server.pairCode,
        pairingSecret: lan ? server.pairingSecret : null,
        hostId: lan ? server.hostId : null,
        pairExpiresAt: pairCode == null ? null : server.pairExpiresAt,
        modelId: model.id,
        startedAt: DateTime.now(),
      );
      // The desktop keeps both models loaded rather than refusing the
      // chat another one.
      if (DesktopHost.active) {
        ref.read(engineHandoffProvider.notifier).state = (next) =>
            _handoff(next, lifecycle);
      }
      unawaited(DevicePower.keepScreenOn(true));
      _powerTimer = Timer.periodic(powerInterval, (_) => checkPower());
      unawaited(checkPower());
    } catch (error) {
      await startingServer?.stop();
      if (_alive && lifecycle == _lifecycle) {
        _server = null;
        final pool = _pool;
        _pool = null;
        unawaited(pool?.close());
        if (HostDiscovery.canAdvertise) {
          try {
            await HostDiscovery.stop();
          } catch (e, st) {
            quietFailure('device_hosting_provider:471', e, st);
          }
        }
        state = DeviceHostingState(error: _message(error));
      }
    }
  }

  void record(ServedRequest r) {
    if (_server != null) state = state.withServed(r);
  }

  /// Reads battery and heat; stops the server when a guard trips.
  Future<void> checkPower() async {
    final power = await DevicePower.read();
    if (_server == null || power == null) return;
    state = state.copyWith(power: power);
    final reason = stopReason(power, guards);
    if (reason != null) await stop(reason: reason);
  }

  /// Why the server should stop itself with this battery and heat, if so.
  static String? stopReason(DevicePower power, HostingGuards guards) {
    final low = guards.minBattery;
    if (low != null &&
        !power.charging &&
        power.level >= 0 &&
        power.level < low) {
      return 'Stopped: battery below $low% and not charging.';
    }
    if (power.thermalStatus >= guards.maxThermal) {
      return 'Stopped: the phone is too hot (${power.thermalLabel}).';
    }
    return null;
  }

  ModelPool _newPool(ModelInfo primary, int lifecycle) {
    late final ModelPool pool;
    pool = ModelPool(
      primary: primary.id,
      installed: () => ref.read(modelManagerProvider).catalog,
      load: (m, e) => ref.read(modelManagerProvider.notifier).loadServed(m, e),
      settingsOf: (m) =>
          ref.read(modelManagerProvider.notifier).servedSettings(m),
      newEngine: ref.read(engineFactoryProvider),
      options: () => ref.read(poolOptionsProvider),
      chatReserved: () => ref.read(sessionBusyProvider),
      chatEngineFor: (id) {
        final chat = ref.read(modelManagerProvider);
        final engine = ref.read(llamaEngineProvider);
        return !chat.isLoadingModel &&
                chat.loadedModelId == id &&
                engine.isLoaded
            ? engine
            : null;
      },
      onChange: () {
        if (_alive && _pool == pool && lifecycle == _lifecycle) {
          state = state.copyWith(pooled: pool.loaded);
        }
      },
    );
    return pool;
  }

  /// Unloads one of the server's extra models (the server page's eject).
  Future<void> unloadPooled(String id) async => _pool?.unload(id);

  /// Called before the chat's runtime takes [next] ('' = ejected): keeps
  /// one copy of every model the server holds.
  Future<void> _handoff(String next, int lifecycle) async {
    if (_server == null || lifecycle != _lifecycle) return;
    final pool = _pool;
    if (pool != null) {
      // A routed answer on the chat's runtime finishes first.
      final clock = Stopwatch()..start();
      while (pool.usingChat && clock.elapsed < moveWait) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (pool.usingChat) {
        throw StateError(
          'The local server is still answering a request. Try again when it finishes.',
        );
      }
      // The chat's copy will answer the server's requests for it.
      if (next.isNotEmpty && pool.holds(next)) await pool.unload(next);
    }
    if (!state.ownEngine) return _moveToOwnEngine(next, lifecycle);
    if (next == state.modelId) return _rejoinChat(lifecycle);
  }

  /// The chat is loading the served model again: the server goes back to
  /// sharing the chat's runtime and frees its own copy.
  Future<void> _rejoinChat(int lifecycle) async {
    final server = _server;
    if (server == null || lifecycle != _lifecycle || !state.ownEngine) return;
    _moving = true;
    try {
      final clock = Stopwatch()..start();
      while (server.busy && clock.elapsed < moveWait) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (server.busy) {
        throw StateError(
          'The local server is still answering a request. Try again when it finishes.',
        );
      }
      final own = ref.read(serverEngineProvider);
      server.useEngine(ref.read(llamaEngineProvider));
      state = state.copyWith(ownEngine: false);
      try {
        await own.unload();
      } catch (_) {
        /* The next load on this engine replaces it. */
      }
    } finally {
      _moving = false;
    }
  }

  /// Moves the served model off the chat's runtime before [nextModelId]
  /// replaces it there: waits for the answer in progress, frees the chat's
  /// copy, then loads the served model on [serverEngineProvider]. If that
  /// fails the server stops (the chat's choice wins) and says why.
  Future<void> _moveToOwnEngine(String nextModelId, int lifecycle) async {
    final server = _server;
    final served = state.modelId;
    if (server == null ||
        lifecycle != _lifecycle ||
        state.ownEngine ||
        served == null ||
        served == nextModelId) {
      return;
    }
    _moving = true;
    try {
      final clock = Stopwatch()..start();
      while (server.busy && clock.elapsed < moveWait) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (server.busy) {
        throw StateError(
          'The local server is still answering a request. Try again when it finishes.',
        );
      }
      final model = ref
          .read(modelManagerProvider)
          .catalog
          .where((m) => m.id == served)
          .firstOrNull;
      final own = ref.read(serverEngineProvider);
      await ref.read(llamaEngineProvider).unload();
      try {
        if (model == null) throw StateError('$served is no longer installed.');
        await ref.read(modelManagerProvider.notifier).loadServed(model, own);
      } catch (e) {
        await stop(
          reason:
              "Stopped: $served could not stay loaded next to the chat's model (${_message(e)}).",
        );
        return;
      }
      if (_server != server || lifecycle != _lifecycle) {
        await own.unload();
        return;
      }
      server.useEngine(own);
      state = state.copyWith(ownEngine: true);
    } finally {
      _moving = false;
    }
  }

  String _message(Object error) => switch (error) {
    HostingTlsException() => stringsFor(
      ref.read(settingsProvider).localeCode,
    ).hostTlsIdentityError,
    StateError(:final message) => message,
    FormatException(:final message) => message,
    _ => '$error',
  };

  /// How long a model switch waits for the server's answer in progress.
  static Duration moveWait = const Duration(minutes: 2);

  Future<void> stop({String? reason}) async {
    final lifecycle = ++_lifecycle;
    _powerTimer?.cancel();
    _powerTimer = null;
    final server = _server;
    _server = null;
    final pool = _pool;
    _pool = null;
    final own = state.ownEngine ? ref.read(serverEngineProvider) : null;
    if (_alive) {
      state = DeviceHostingState(stoppedReason: reason);
      ref.read(engineHandoffProvider.notifier).state = null;
    }
    if (HostDiscovery.canAdvertise) {
      try {
        await HostDiscovery.stop();
      } catch (_) {
        /* Server stop must proceed. */
      }
    }
    await _closeRuntimes(server, pool);
    if (server != null) unawaited(DevicePower.keepScreenOn(false));
    // The served model's own copy is only there for the server. A cancelled
    // answer keeps the engine busy for a moment, and unload refuses a busy
    // engine, so wait for it to wind down first. A server started meanwhile
    // may have moved its model to this engine again; that model stays. On
    // dispose the engine's own provider frees it.
    if (own != null) {
      final clock = Stopwatch()..start();
      while (own.isBusy && clock.elapsed < moveWait) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (lifecycle != _lifecycle && (!_alive || state.ownEngine || _moving)) {
        return;
      }
      try {
        await own.unload();
      } catch (_) {
        /* Still busy after the wait; the next load on this engine replaces it. */
      }
    }
  }

  Future<void> revokeDevice(String id) async {
    final server = _server;
    if (server == null) return;
    await server.revokeDevice(id);
    if (_alive && _server == server) {
      state = state.copyWith(
        pairedDevices: server.pairedDevices.devices,
        legacyTokenEnabled: server.pairedDevices.legacyEnabled,
      );
    }
  }

  Future<void> resetHostIdentity() async {
    await stop();
    final devices = await PairedDevices.load();
    for (final device in devices.devices) {
      await devices.revoke(device.id);
    }
    // The shared token was trusted under the old identity: replace it too.
    await _secure.delete(key: _tokenKey);
    await HostingTls.reset();
    await devices.allowNewLegacyToken();
    if (_alive) {
      state = const DeviceHostingState();
    }
  }

  Future<void> regenerateToken() async {
    await stop();
    await _secure.delete(key: _tokenKey);
    await (await PairedDevices.load()).allowNewLegacyToken();
    state = const DeviceHostingState();
  }

  /// The address another device on the same network can reach. The first
  /// interface is often mobile data (rmnet, 192.0.0.2 on the S25+), which
  /// no other device can connect to; Wi-Fi and private LAN ranges win.
  static Future<String?> _localAddress() async {
    final candidates = <(int, String)>[];
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      final name = interface.name.toLowerCase();
      for (final address in interface.addresses) {
        if (address.isLoopback || address.isLinkLocal) continue;
        candidates.add((
          rankAddress(name, address.rawAddress),
          address.address,
        ));
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return candidates.first.$2;
  }

  /// A missing address stays a display placeholder, never an mDNS input.
  static String endpointFor(
    String? address,
    int port,
    String localeCode, {
    bool tls = false,
  }) =>
      '${tls ? 'https' : 'http'}://${address ?? stringsFor(localeCode).hostAddressPlaceholder}:$port/v1/';

  /// Higher is better: Wi-Fi/Ethernet/hotspot interfaces, then private LAN
  /// ranges; mobile-data and carrier (192.0.0.0/24, 100.64/10) last.
  static int rankAddress(String interface, List<int> b) {
    var score = 0;
    if (RegExp(
      r'^(wlan|eth|en|ap|swlan|softap|rndis|wl|wi-?fi)',
    ).hasMatch(interface)) {
      score += 10;
    }
    // Windows: VPN, virtual switch and Wi-Fi Direct adapters carry private
    // addresses no phone on the Wi-Fi can reach (NordLynx is 10.5.0.2).
    if (RegExp(
      r'nordlynx|openvpn|wireguard|tailscale|zerotier|vpn|vethernet|hyper-v|'
      r'vmware|virtualbox|vbox|tap-|bluetooth|local area connection\*',
    ).hasMatch(interface)) {
      score -= 20;
    }
    if (RegExp(
      r'^(rmnet|ccmni|pdp|v4-rmnet|clat|dummy|tun)',
    ).hasMatch(interface)) {
      score -= 10;
    }
    final private =
        b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
    if (private) score += 5;
    if (b[0] == 192 && b[1] == 0 && b[2] == 0) score -= 5;
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) score -= 3;
    return score;
  }
}

final deviceHostingProvider =
    NotifierProvider<DeviceHostingNotifier, DeviceHostingState>(
      DeviceHostingNotifier.new,
    );

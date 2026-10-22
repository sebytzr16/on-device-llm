import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/platform/device_info.dart';
import '../../../core/providers/shared_providers.dart';
import '../../../features/models/domain/entities/model_info.dart';
import '../../../features/models/presentation/providers/model_manager_provider.dart';
import '../../../features/settings/presentation/providers/settings_provider.dart';
import '../device_model_server.dart';
import '../host_discovery.dart';

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
  final bool running;
  final bool starting;
  final String? endpoint;
  final String? token;
  final String? modelId;
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
    this.running = false,
    this.starting = false,
    this.endpoint,
    this.token,
    this.modelId,
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
  String? get pairing => endpoint == null || token == null
      ? null
      : jsonEncode({
          'ondevice_llm': 'connection',
          'url': endpoint,
          'model': modelId ?? '',
          'key': token,
        });

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
    bool? running,
    bool? starting,
    String? activeClient,
    bool clearClient = false,
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
    running: running ?? this.running,
    starting: starting ?? this.starting,
    endpoint: endpoint,
    token: token,
    modelId: modelId,
    activeClient: clearClient ? null : activeClient ?? this.activeClient,
    error: error,
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
  static const logSize = 30;

  /// How often battery and heat are checked while serving.
  static Duration powerInterval = const Duration(seconds: 30);

  DeviceModelServer? _server;
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
      if (server != null) {
        if (HostDiscovery.supported) {
          unawaited(HostDiscovery.stop().catchError((Object _) {}));
        }
        unawaited(server.stop());
        unawaited(DevicePower.keepScreenOn(false));
      }
    });
    return const DeviceHostingState();
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

  Future<void> start({required int port}) async {
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
      final server = DeviceModelServer(
        engine: engine,
        settings: () => ref.read(settingsProvider),
        modelId: model.id,
        fallbackTemplate: model.family.fallbackTemplate,
        accessToken: token,
        isAvailable: () => engine.isLoaded && !engine.isBusy,
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
      await server.start(address: InternetAddress.anyIPv4, port: port);
      if (!_alive || lifecycle != _lifecycle) {
        await server.stop();
        return;
      }
      _server = server;
      if (HostDiscovery.supported) {
        try {
          await HostDiscovery.advertise(server.port!);
        } catch (_) {
          /* Manual pairing still works. */
        }
      }
      final host = await _localAddress();
      if (!_alive || lifecycle != _lifecycle) {
        await server.stop();
        return;
      }
      state = DeviceHostingState(
        running: true,
        endpoint: 'http://$host:${server.port}/v1/',
        token: token,
        modelId: model.id,
        startedAt: DateTime.now(),
      );
      unawaited(DevicePower.keepScreenOn(true));
      _powerTimer = Timer.periodic(powerInterval, (_) => checkPower());
      unawaited(checkPower());
    } catch (error) {
      await startingServer?.stop();
      if (_alive && lifecycle == _lifecycle) {
        _server = null;
        if (HostDiscovery.supported) {
          try {
            await HostDiscovery.stop();
          } catch (_) {}
        }
        state = DeviceHostingState(error: error.toString());
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

  Future<void> stop({String? reason}) async {
    _lifecycle++;
    _powerTimer?.cancel();
    _powerTimer = null;
    final server = _server;
    _server = null;
    if (_alive) state = DeviceHostingState(stoppedReason: reason);
    if (HostDiscovery.supported) {
      try {
        await HostDiscovery.stop();
      } catch (_) {
        /* Server stop must proceed. */
      }
    }
    await server?.stop();
    if (server != null) unawaited(DevicePower.keepScreenOn(false));
  }

  Future<void> regenerateToken() async {
    await stop();
    await _secure.delete(key: _tokenKey);
    state = const DeviceHostingState();
  }

  /// The address another device on the same network can reach. The first
  /// interface is often mobile data (rmnet, 192.0.0.2 on the S25+), which
  /// no other device can connect to; Wi-Fi and private LAN ranges win.
  static Future<String> _localAddress() async {
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
    if (candidates.isEmpty) return '<phone-ip>';
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return candidates.first.$2;
  }

  /// Higher is better: Wi-Fi/Ethernet/hotspot interfaces, then private LAN
  /// ranges; mobile-data and carrier (192.0.0.0/24, 100.64/10) last.
  static int rankAddress(String interface, List<int> b) {
    var score = 0;
    if (RegExp(
      r'^(wlan|eth|en|ap|swlan|softap|rndis|wl)',
    ).hasMatch(interface)) {
      score += 10;
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

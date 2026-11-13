import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../inference/engine/text_engine.dart';
import '../tools/domain/tool_spec.dart';
import '../settings/domain/entities/inference_settings.dart';
import 'pairing_code.dart';
import 'paired_devices.dart';
import 'hosting_tls.dart';
import 'request_queue.dart';
import 'workspace_api.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// One request the device server answered (or refused), for the live
/// dashboard on the hosting page.
class ServedRequest {
  final DateTime at;
  final String client;

  /// Trusted workspace origin for client aggregation; [client] remains the
  /// actual socket peer in the request log.
  final String? attributedClient;

  /// The model a completion asked for ('' for other requests).
  final String modelId;
  final String method, path;

  /// HTTP status sent (200 for a completed or streamed answer).
  final int status;
  final bool stream;

  /// A chat completion (not a model listing or a refusal before one).
  final bool completion;
  final int promptTokens, completionTokens;
  final double tokensPerSecond;
  final Duration took;

  /// Why the request was refused or failed, when it was.
  final String? error;
  const ServedRequest({
    required this.at,
    required this.client,
    this.attributedClient,
    required this.status,
    this.modelId = '',
    this.method = '',
    this.path = '',
    this.stream = false,
    this.completion = false,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.tokensPerSecond = 0,
    this.took = Duration.zero,
    this.error,
  });

  bool get ok => status == HttpStatus.ok && error == null;
}

/// Why a routed model cannot answer right now: the HTTP status and message
/// the client gets (429 when every runtime that could is busy).
class RouteRefusal implements Exception {
  final int status;
  final String message;
  const RouteRefusal(this.status, this.message);
  @override
  String toString() => message;
}

/// Desktop: the other models the server answers with, picked by a
/// request's `model`. The primary model never goes through it.
abstract class ServedModelRouter {
  /// Ids `/v1/models` lists besides the primary one.
  List<String> get ids;

  /// A runtime holding [id] for one request, loading it first when needed;
  /// null when [id] is not a model this router serves. Throws
  /// [RouteRefusal] when it cannot answer now.
  Future<TextEngine?> acquire(String id);

  /// Gives back what [acquire] handed out for [id].
  void release(String id);
  InferenceSettings settingsFor(String id);
  String templateFor(String id);

  /// Stops every routed answer in progress.
  void cancelAll();
}

/// An independent embedding/rerank runtime. It never borrows the chat engine.
abstract class ServedVectorEngine {
  Map<String, String> get models => const {};

  /// Exact counts before inference, including tokenizer special tokens.
  /// Null means the runtime cannot guarantee that it will not truncate.
  Future<({List<int> counts, int limit})?> tokenCounts(
    String model,
    List<String> input,
  ) async => null;
  Future<List<List<double>>> embed(String model, List<String> input, int dims);
  Future<List<double>> rerank(
    String model,
    String query,
    List<String> documents,
  );
  void dispose() {}
}

/// Optional capability: consumes the prompt verbatim without a chat template.
/// The current llama bridge's od_begin exposes only chat generation.
/// Engines without this capability return 501 from /v1/completions; use
/// /v1/chat/completions instead.
abstract interface class RawCompletionEngine {
  Stream<String> generateRaw({
    required String prompt,
    required InferenceSettings settings,
  });
}

/// Opt-in OpenAI-compatible endpoint for the model loaded on this device.
class DeviceModelServer {
  static const modelsPath = '/v1/models';
  static const completionsPath = '/v1/chat/completions';
  static const rawCompletionsPath = '/v1/completions';
  static const responsesPath = '/v1/responses';
  static const embeddingsPath = '/v1/embeddings';
  static const rerankPath = '/v1/rerank';
  static const messagesPath = '/v1/messages';
  static const pairPath = '/v1/pair';
  TextEngine _engine;
  final InferenceSettings Function() settings;
  final String modelId;
  final String fallbackTemplate;
  final String accessToken;
  final String? localAccessToken;
  final PairedDevices pairedDevices;
  final void Function()? onDevicesChanged;

  /// Traded for a device credential at [pairPath] by a device that found this
  /// server nearby; null turns pairing off.
  String? pairCode;
  late PairingSession _pairing = PairingSession(lifetime: pairingLifetime);
  final Duration pairingLifetime;
  final String hostId = PairingCode.secret();
  String pairingSecret = PairingCode.secret();
  Timer? _pairTimer;
  bool _pairLocked = false;
  String? _expiredCode, _expiredSecret;
  final void Function()? onPairingChanged;

  void _armPairingExpiry() {
    _pairTimer?.cancel();
    if (pairCode == null || _server == null) return;
    _pairTimer = Timer(_pairing.expiresAt.difference(DateTime.now()), () {
      _rotatePairing(expired: true);
    });
  }

  void _rotatePairing({bool expired = false}) {
    if (expired) {
      // QR redemption must not bypass a typed-code lockout. Expiry does.
      _pairLocked = false;
      _expiredCode = pairCode;
      _expiredSecret = pairingSecret;
    }
    final oldCode = pairCode;
    do {
      pairCode = PairingCode.generate();
    } while (pairCode == oldCode);
    pairingSecret = PairingCode.secret();
    _pairing = PairingSession(
      lifetime: pairingLifetime,
      failures: expired ? 0 : _pairing.failures,
    );
    _armPairingExpiry();
    onPairingChanged?.call();
  }

  /// When [pairCode] stops being accepted.
  DateTime get pairExpiresAt => _pairing.expiresAt;
  bool get pairingLocked => _pairLocked;
  final void Function(bool locked)? onPairingUnavailable;
  final bool Function()? isAvailable;

  /// Answers requests for models other than [modelId]; null serves only it.
  final ServedModelRouter? router;
  final ServedVectorEngine? vectors;
  final WorkspaceApi? workspace;
  final bool Function(String model)? hasProjector;
  final Future<void> Function(String model, TextEngine engine)? prepareMedia;
  final void Function(String? client)? onSessionChange;

  /// Called once per request with what happened to it.
  final void Function(ServedRequest request)? onServed;

  /// Called while an answer streams with the pieces generated so far.
  final void Function(int pieces)? onProgress;
  HttpServer? _server, _tlsServer;
  HostingTls? _tls;
  int? get tlsPort => _tlsServer?.port;
  final Set<Directory> _imageDirectories = {};
  bool _busy = false;
  RequestQueue _queue = RequestQueue();
  final Duration bodyTimeout, generationTimeout;
  final Map<String, List<DateTime>> _clientRequests = {};
  final Map<String, int> _clientConnections = {};
  int _connections = 0;
  final _pairAdmission = _Admission(maxGlobal: 8, maxClient: 4, rate: 20);
  final _controlAdmission = _Admission(maxGlobal: 8, maxClient: 4, rate: 60);
  static const maxClientConnections = 8;
  static const maxConnections = 16;

  DeviceModelServer({
    required this._engine,
    required this.settings,
    required this.modelId,
    required this.fallbackTemplate,
    required this.accessToken,
    this.localAccessToken,
    PairedDevices? pairedDevices,
    this.onDevicesChanged,
    this.pairCode,
    this.onPairingUnavailable,
    this.onPairingChanged,
    this.pairingLifetime = const Duration(minutes: 10),
    this.isAvailable,
    this.router,
    this.vectors,
    this.workspace,
    this.hasProjector,
    this.prepareMedia,
    this.onSessionChange,
    this.onServed,
    this.onProgress,
    this.bodyTimeout = const Duration(seconds: 15),
    this.generationTimeout = const Duration(minutes: 10),
  }) // A named parameter cannot be private, so no initializing formal.
    // ignore: prefer_initializing_formals
    : pairedDevices = pairedDevices ?? PairedDevices(save: (_) async {}) {
    if (accessToken.length < 32) {
      throw ArgumentError.value(
        accessToken.length,
        'accessToken',
        'Use at least 32 random characters.',
      );
    }
  }

  TextEngine get engine => _engine;

  /// Whether a request holds the primary model's engine right now.
  bool get busy => _busy;

  /// Moves serving to [engine] (the same model on another runtime). Only
  /// while no request holds the old one.
  void useEngine(TextEngine engine) {
    if (_busy) throw StateError('A request is still being answered.');
    _engine = engine;
  }

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  InternetAddress? get address => _server?.address;

  /// HTTP for loopback/discovery plus an optional pinned TLS listener.
  /// Every request from an address
  /// outside [allowedClient] is refused before the token is even checked.
  Future<void> start({
    InternetAddress? address,
    int port = 0,
    HostingTls? tls,
  }) async {
    if (_server != null) throw StateError('Server is already running.');
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    try {
      if (tls != null) {
        final tlsPort = port == 0 ? 0 : (port == 65535 ? 65534 : port + 1);
        try {
          _tlsServer = await HttpServer.bindSecure(
            address ?? InternetAddress.loopbackIPv4,
            tlsPort,
            tls.context,
          );
        } on SocketException {
          if (tlsPort == 0) rethrow;
          _tlsServer = await HttpServer.bindSecure(
            address ?? InternetAddress.loopbackIPv4,
            0,
            tls.context,
          );
        }
        _tls = tls;
        unawaited(_serve(_tlsServer!));
      }
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
    _queue = RequestQueue();
    _server = server;
    _armPairingExpiry();
    unawaited(_serve(server));
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handle(request));
      }
    } catch (_) {
      // Socket shutdown ends the server loop.
    } finally {
      if (identical(_server, server)) {
        _server = null;
        _pairTimer?.cancel();
      }
    }
  }

  Future<void> stop() async {
    _pairTimer?.cancel();
    final server = _server;
    _server = null;
    _queue.close();
    await workspace?.dispose();
    await server?.close(force: true);
    await _tlsServer?.close(force: true);
    _tlsServer = null;
    _tls = null;
    if (_busy) engine.cancel();
    router?.cancelAll();
    vectors?.dispose();
    for (final directory in _imageDirectories.toList()) {
      await _removeImageDirectory(directory);
    }
    onSessionChange?.call(null);
  }

  Future<void> _removeImageDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      _imageDirectories.remove(directory);
    } on FileSystemException {
      // Retain failed cleanup for a retry when the server stops.
    }
  }

  /// Whether [a] can only be a device on this network or a VPN peer:
  /// loopback, private LAN (10/8, 172.16/12, 192.168/16), link-local,
  /// 100.64/10 (Tailscale and other overlay VPNs; carrier NAT keeps
  /// subscribers apart) and IPv6 unique-local fc00::/7 or link-local.
  /// A public address never reaches the model, even with the token.
  static bool allowedClient(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal) return true;
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
    }
    if (a.type == InternetAddressType.IPv6) {
      // IPv4-mapped (::ffff:a.b.c.d): judge the IPv4 address.
      final mapped =
          b.take(10).every((x) => x == 0) && b[10] == 0xff && b[11] == 0xff;
      if (mapped) {
        return allowedClient(
          InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))),
        );
      }
      return (b[0] & 0xfe) == 0xfc || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
    }
    return false;
  }

  /// Authenticated LAN traffic must use the active TLS listener.
  static bool requiresApiTls(
    InternetAddress remote,
    int? localPort,
    int? tlsPort,
  ) => tlsPort != null && localPort != tlsPort && !remote.isLoopback;

  /// Identity used for client rate and connection budgets.
  static String clientLimitKey(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv6) {
      if (bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff) {
        return InternetAddress.fromRawAddress(
          Uint8List.fromList(bytes.sublist(12)),
        ).address;
      }
      // Privacy addresses and rotated hosts on the same subnet share a budget.
      return '${bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}/64';
    }
    return address.address;
  }

  bool _allowRequest(String key) {
    final now = DateTime.now();
    const window = Duration(minutes: 1);
    _clientRequests.removeWhere(
      (_, times) => times.every((t) => now.difference(t) >= window),
    );
    final recent = _clientRequests.putIfAbsent(key, () => []);
    recent.removeWhere((t) => now.difference(t) >= window);
    if (recent.length >= 20) return false;
    recent.add(now);
    return true;
  }

  static String _prompt(Object? value) {
    if (value is String) return value;
    if (value is List && value.length == 1 && value.single is String) {
      return value.single as String;
    }
    throw const FormatException(
      'prompt must be a string or an array of one string.',
    );
  }

  static Map _responsesBody(Map body) {
    // A deliberately small adapter; reject features that require Responses
    // state or item semantics rather than silently ignoring them.
    for (final key in ['previous_response_id', 'conversation', 'tools']) {
      if (body[key] != null) {
        throw FormatException(
          '$key is unsupported by this stateless Responses adapter.',
        );
      }
    }
    final input = body['input'];
    final messages = input is String
        ? [
            {'role': 'user', 'content': input},
          ]
        : input is List
        ? input
        : throw const FormatException('input must be text or chat messages.');
    if (body['instructions'] != null && body['instructions'] is! String) {
      throw const FormatException('instructions must be a string.');
    }
    return {
      ...body,
      'messages': [
        if (body['instructions'] is String)
          {'role': 'system', 'content': body['instructions']},
        ...messages,
      ],
      if (body.containsKey('max_output_tokens'))
        'max_tokens': body['max_output_tokens'],
    };
  }

  static Map<String, Object?> _response(
    String id,
    String model,
    String text,
    String finish,
    _Usage usage,
  ) => {
    'id': id,
    'object': 'response',
    'model': model,
    'status': finish == 'length' ? 'incomplete' : 'completed',
    'incomplete_details': finish == 'length'
        ? {'reason': 'max_output_tokens'}
        : null,
    'output_text': text,
    'output': [
      {
        'id': '$id-message',
        'type': 'message',
        'role': 'assistant',
        'status': finish == 'length' ? 'incomplete' : 'completed',
        'content': [
          {'type': 'output_text', 'text': text, 'annotations': <Object>[]},
        ],
      },
    ],
    'usage': {
      'input_tokens': usage.hasPrompt ? usage.prompt : null,
      'output_tokens': usage.hasCompletion ? usage.completion : null,
      'total_tokens': usage.hasPrompt && usage.hasCompletion
          ? usage.prompt + usage.completion
          : null,
    },
  };

  static String _base64Vector(List<double> vector) {
    final bytes = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      bytes.setFloat32(i * 4, vector[i], Endian.little);
    }
    return base64Encode(bytes.buffer.asUint8List());
  }

  static InferenceSettings samplingForRequest(
    Map body,
    InferenceSettings current,
  ) {
    double? number(String key, double low, double high) {
      if (!body.containsKey(key)) return null;
      final value = body[key];
      if (value is! num || !value.isFinite || value < low || value > high) {
        throw FormatException('$key must be a number between $low and $high.');
      }
      return value.toDouble();
    }

    int? integer(String key, int low, int high) {
      if (!body.containsKey(key)) return null;
      final value = body[key];
      if (value is! int || value < low || value > high) {
        throw FormatException(
          '$key must be an integer between $low and $high.',
        );
      }
      return value;
    }

    final maxTokens = integer('max_tokens', 1, 0x7fffffff);
    final maxCompletion = integer('max_completion_tokens', 1, 0x7fffffff);
    if (maxTokens != null &&
        maxCompletion != null &&
        maxTokens != maxCompletion) {
      throw const FormatException(
        'max_tokens and max_completion_tokens must agree when both are supplied.',
      );
    }
    List<String>? stop;
    if (body.containsKey('stop') && body['stop'] != null) {
      final value = body['stop'];
      if (value is String && value.isNotEmpty) {
        stop = [value];
      } else if (value is List &&
          value.length <= 4 &&
          value.every((s) => s is String && s.isNotEmpty)) {
        stop = value.cast<String>();
      } else {
        throw const FormatException(
          'stop must be a nonempty string or an array of up to four nonempty strings.',
        );
      }
    } else if (body.containsKey('stop')) {
      stop = [];
    }
    final streamOptions = body['stream_options'];
    if (streamOptions != null &&
        (streamOptions is! Map ||
            (streamOptions.containsKey('include_usage') &&
                streamOptions['include_usage'] is! bool))) {
      throw const FormatException(
        'stream_options.include_usage must be a boolean.',
      );
    }
    // All these fields have native sampler paths (bridge build_sampler and
    // od_begin). Explicitly reject multi-candidate requests: one sequence.
    final n = integer('n', 1, 0x7fffffff);
    if (n != null && n != 1) {
      throw const FormatException('n other than 1 is unsupported.');
    }
    final repetition = number('repeat_penalty', 0, 2);
    if (repetition == 0) {
      throw const FormatException(
        'repeat_penalty must be greater than 0 and at most 2.',
      );
    }
    return current.copyWith(
      temperature: number('temperature', 0, 2),
      topP: number('top_p', 0, 1),
      topK: integer('top_k', 0, 0x7fffffff),
      minP: number('min_p', 0, 1),
      seed: integer('seed', 0, 0xffffffff),
      stopSequences: stop,
      presencePenalty: number('presence_penalty', -2, 2),
      frequencyPenalty: number('frequency_penalty', -2, 2),
      repetitionPenalty: repetition,
      maxTokens: maxCompletion ?? maxTokens,
    );
  }

  static InferenceSettings _responseFormat(
    Map body,
    InferenceSettings current,
  ) {
    if (!body.containsKey('response_format')) return current;
    final format = body['response_format'];
    if (format is! Map || format['type'] is! String) {
      throw const FormatException(
        'response_format must be an object with a type.',
      );
    }
    switch (format['type']) {
      case 'text':
        return current.copyWith(
          responseFormat: ResponseFormat.text,
          jsonSchema: '',
          grammar: '',
        );
      case 'json_object':
        return current.copyWith(
          responseFormat: ResponseFormat.json,
          jsonSchema: '',
          grammar: '',
        );
      case 'json_schema':
        final spec = format['json_schema'];
        if (spec is! Map ||
            spec['name'] is! String ||
            !RegExp(
              r'^[a-zA-Z0-9_-]{1,64}$',
            ).hasMatch(spec['name'] as String) ||
            spec['schema'] is! Map ||
            (spec.containsKey('strict') && spec['strict'] is! bool)) {
          throw const FormatException(
            'response_format.json_schema requires a name, a schema object and an optional boolean strict.',
          );
        }
        return current.copyWith(
          responseFormat: ResponseFormat.jsonSchema,
          jsonSchema: jsonEncode(spec['schema']),
          grammar: '',
        );
      default:
        throw const FormatException(
          'response_format.type must be text, json_object or json_schema.',
        );
    }
  }

  static List<ToolSpec> _tools(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length > 64) {
      throw const FormatException(
        'tools must be an array of at most 64 functions.',
      );
    }
    final names = <String>{};
    return [for (final entry in value) _tool(entry, names)];
  }

  static Map<String, Object?> _anthropicBody(Map body) {
    final source = body['messages'];
    if (source is! List) {
      throw const FormatException('messages must be an array.');
    }
    final messages = <Map<String, Object?>>[];
    String textBlocks(Object? value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is List) {
        return value
            .map((block) {
              if (block is! Map ||
                  block['type'] != 'text' ||
                  block['text'] is! String) {
                throw const FormatException('Expected text blocks.');
              }
              return block['text'] as String;
            })
            .join('\n');
      }
      throw const FormatException('Expected text or text blocks.');
    }

    if (body['system'] != null) {
      messages.add({'role': 'system', 'content': textBlocks(body['system'])});
    }
    for (final item in source) {
      if (item is! Map || !const {'user', 'assistant'}.contains(item['role'])) {
        throw const FormatException('Invalid Anthropic message role.');
      }
      final content = item['content'];
      if (content is String) {
        messages.add({'role': item['role'], 'content': content});
      } else if (content is List) {
        final text = StringBuffer();
        final calls = <Map<String, Object>>[];
        final images = <Map<String, Object>>[];
        for (final block in content) {
          if (block is! Map) {
            throw const FormatException('Invalid content block.');
          }
          switch (block['type']) {
            case 'text':
              if (block['text'] is! String) {
                throw const FormatException('Invalid text block.');
              }
              text.write(block['text']);
            case 'thinking':
            case 'redacted_thinking':
              break;
            case 'image':
              final source = block['source'];
              if (source is! Map ||
                  source['type'] != 'base64' ||
                  source['media_type'] is! String ||
                  source['data'] is! String) {
                throw const FormatException('Invalid image block.');
              }
              images.add({
                'type': 'image_url',
                'image_url': {
                  'url':
                      'data:${source['media_type']};base64,${source['data']}',
                },
              });
            case 'tool_use':
              if (item['role'] != 'assistant' ||
                  block['id'] is! String ||
                  block['name'] is! String ||
                  block['input'] is! Map) {
                throw const FormatException('Invalid tool_use block.');
              }
              calls.add({
                'id': block['id'] as String,
                'type': 'function',
                'function': {
                  'name': block['name'],
                  'arguments': jsonEncode(block['input']),
                },
              });
            case 'tool_result':
              if (item['role'] != 'user' || block['tool_use_id'] is! String) {
                throw const FormatException('Invalid tool_result block.');
              }
              messages.add({
                'role': 'tool',
                'tool_call_id': block['tool_use_id'],
                'content': textBlocks(block['content']),
              });
            default:
              throw const FormatException('Unsupported content block.');
          }
        }
        if (text.isNotEmpty || calls.isNotEmpty || images.isNotEmpty) {
          messages.add({
            'role': item['role'],
            'content': images.isEmpty
                ? text.toString()
                : [
                    if (text.isNotEmpty)
                      {'type': 'text', 'text': text.toString()},
                    ...images,
                  ],
            if (calls.isNotEmpty) 'tool_calls': calls,
          });
        }
      } else {
        throw const FormatException('Invalid message content.');
      }
    }
    final tools = body['tools'];
    if (tools != null && tools is! List) {
      throw const FormatException('tools must be an array.');
    }
    return {
      'model': body['model'],
      'messages': messages,
      for (final key in [
        'max_tokens',
        'max_completion_tokens',
        'temperature',
        'top_p',
        'top_k',
        'min_p',
        'seed',
        'presence_penalty',
        'frequency_penalty',
        'repeat_penalty',
      ])
        if (body.containsKey(key)) key: body[key],
      if (body.containsKey('stop_sequences')) 'stop': body['stop_sequences'],
      'stream': body['stream'],
      if (tools != null)
        'tools': [
          for (final t in tools)
            if (t is Map)
              {
                'type': 'function',
                'function': {
                  'name': t['name'],
                  'description': t['description'] ?? '',
                  'parameters': t['input_schema'] ?? {'type': 'object'},
                },
              }
            else
              t,
        ],
      if (body['tool_choice'] != null)
        'tool_choice': switch (body['tool_choice']) {
          {'type': 'auto'} => 'auto',
          {'type': 'any'} => 'required',
          {'type': 'none'} => 'none',
          {'type': 'tool', 'name': final String name} => {
            'type': 'function',
            'function': {'name': name},
          },
          _ => body['tool_choice'],
        },
    };
  }

  static void _event(IOSink response, String name, Object data) {
    response.write('event: $name\ndata: ${jsonEncode(data)}\n\n');
  }

  static ToolSpec _tool(Object? entry, Set<String> names) {
    if (entry is! Map ||
        entry['type'] != 'function' ||
        entry['function'] is! Map) {
      throw const FormatException('tools entries must be functions.');
    }
    final function = entry['function'] as Map;
    final name = function['name'];
    final parameters =
        function['parameters'] ?? <String, Object>{'type': 'object'};
    if (name is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(name) ||
        !names.add(name) ||
        (function['description'] != null &&
            function['description'] is! String) ||
        parameters is! Map ||
        parameters['type'] != 'object') {
      throw const FormatException(
        'tools require unique names, descriptions and object parameters.',
      );
    }
    return ToolSpec(
      name: name,
      description: function['description'] as String? ?? '',
      parameters: Map<String, dynamic>.from(parameters),
    );
  }

  static String _toolChoice(Object? value, List<ToolSpec> tools) {
    if (value == null) return 'auto';
    if (value is String && const {'auto', 'none', 'required'}.contains(value)) {
      if (value == 'required' && tools.isEmpty) {
        throw const FormatException('tool_choice requires tools.');
      }
      return value;
    }
    if (value is Map &&
        value['type'] == 'function' &&
        value['function'] is Map) {
      final name = (value['function'] as Map)['name'];
      if (name is String && tools.any((t) => t.name == name)) return name;
    }
    throw const FormatException(
      'tool_choice must name a supplied function or be auto, none or required.',
    );
  }

  static Future<List<Map<String, Object>>> decodeWorkspaceMessages(
    Object? source, {
    required bool vision,
    required List<File> images,
    required Directory imageDirectory,
  }) async => _messages(
    source,
    vision: vision,
    images: images,
    imageDirectory: imageDirectory,
  );

  static Future<List<Map<String, Object>>> _messages(
    Object? source, {
    required bool vision,
    required List<File> images,
    Directory? imageDirectory,
  }) async {
    if (source is! List || source.isEmpty || source.length > 64) {
      throw const FormatException('Expected 1 to 64 messages.');
    }
    final results = <Map<String, Object>>[];
    for (final item in source) {
      results.add(
        await _message(
          item,
          vision: vision,
          images: images,
          imageDirectory: imageDirectory,
        ),
      );
    }
    return results;
  }

  static Future<Map<String, Object>> _message(
    Object? item, {
    required bool vision,
    required List<File> images,
    Directory? imageDirectory,
  }) async {
    if (item is! Map ||
        item['role'] is! String ||
        !const {'system', 'user', 'assistant', 'tool'}.contains(item['role'])) {
      throw const FormatException('Invalid message role.');
    }
    final role = item['role'] as String;
    final content = item['content'];
    if (content is! String &&
        !(role == 'assistant' && content == null) &&
        !(role == 'user' && content is List)) {
      throw const FormatException('Message content must be text.');
    }
    final message = <String, Object>{
      'role': role,
      'content': content is String ? content : '',
    };
    if (content is List) {
      final rendered = StringBuffer();
      final paths = <String>[];
      for (final part in content) {
        if (part is! Map) throw const FormatException('Invalid content part.');
        if (part['type'] == 'text' && part['text'] is String) {
          rendered.write(part['text']);
        } else if (part['type'] == 'image_url' && part['image_url'] is Map) {
          if (!vision) {
            throw const FormatException('This model has no image projector.');
          }
          final url = (part['image_url'] as Map)['url'];
          if (url is! String || !url.startsWith('data:image/')) {
            throw const FormatException('Only image data URLs are supported.');
          }
          final match = RegExp(
            r'^data:image/(png|jpeg|webp);base64,(.+)$',
            dotAll: true,
          ).firstMatch(url);
          if (match == null) {
            throw const FormatException('Invalid image data URL.');
          }
          late final List<int> bytes;
          try {
            bytes = base64Decode(match.group(2)!);
          } on FormatException {
            throw const FormatException('Invalid image base64 data.');
          }
          if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
            throw const FormatException('Image data must be at most 8 MB.');
          }
          if (imageDirectory == null) {
            throw StateError('Image decoding requires a private directory.');
          }
          final file = File(
            '${imageDirectory.path}${Platform.pathSeparator}${images.length}.${match.group(1)}',
          );
          await file.writeAsBytes(bytes);
          images.add(file);
          paths.add(file.path);
          rendered.write(TextEngine.mediaMarker);
        } else {
          throw const FormatException('Unsupported content part.');
        }
      }
      message['content'] = rendered.toString();
      if (paths.isNotEmpty) message['images'] = paths;
    }
    if (role == 'tool') {
      if (item['tool_call_id'] is! String ||
          (item['tool_call_id'] as String).isEmpty) {
        throw const FormatException('Tool messages require tool_call_id.');
      }
      message['tool_call_id'] = item['tool_call_id'] as String;
      if (item['name'] is String) message['name'] = item['name'] as String;
    }
    if (item['tool_calls'] != null) {
      if (role != 'assistant' || item['tool_calls'] is! List) {
        throw const FormatException(
          'Only assistant messages may have tool_calls.',
        );
      }
      message['tool_calls'] = [
        for (final call in item['tool_calls'] as List) _historyCall(call),
      ];
    }
    return message;
  }

  static Map<String, String> _historyCall(Object? call) {
    if (call is! Map ||
        call['id'] is! String ||
        call['type'] != 'function' ||
        call['function'] is! Map ||
        (call['function'] as Map)['name'] is! String ||
        (call['function'] as Map)['arguments'] is! String) {
      throw const FormatException('Invalid assistant tool_calls entry.');
    }
    return {
      'id': call['id'] as String,
      'name': (call['function'] as Map)['name'] as String,
      'arguments': (call['function'] as Map)['arguments'] as String,
    };
  }

  Future<void> _handle(HttpRequest request) async {
    final queue = _queue;
    final response = request.response;
    IOSink output = response;
    Socket? socket;
    final abandoned = Completer<void>();
    var headersSent = false;
    void writeHeaders(int code, String type) {
      if (headersSent || socket == null) return;
      headersSent = true;
      socket.write(
        'HTTP/1.1 $code ${code == 200 ? "OK" : "Error"}\r\n'
        'Content-Type: $type\r\nConnection: close\r\n'
        'Cache-Control: no-cache\r\nAccess-Control-Allow-Origin: *\r\n\r\n',
      );
    }

    // Key authentication, no cookie credentials: explicitly allow browser clients.
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Authorization, Content-Type, X-API-Key, X-Pairing-Mode, Anthropic-Version, Anthropic-Beta',
    );
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final client =
        request.connectionInfo?.remoteAddress.address ?? 'Unknown client';
    final attributedClient = workspace?.completionClient(request);
    String? connectionKey;
    _Admission? reservedLane;
    String? laneKey;
    var streaming = false, wantsStream = false, completion = false;
    // Whether this request holds an engine (released in the outer finally).
    var claimed = false;
    TextEngine? active;
    void disconnected() {
      if (!abandoned.isCompleted) abandoned.complete();
      if (claimed) active?.cancel();
    }

    // The routed model this request holds, when not the primary one.
    String? routed;
    String? queueKey;
    final images = <File>[];
    Directory? imageDirectory;
    var requested = '';
    void release() {
      if (!claimed) return;
      claimed = false;
      if (routed == null) {
        _busy = false;
      } else {
        router?.release(routed);
      }
    }

    var status = HttpStatus.ok;
    String? error;
    Map<String, Object>? pairingRefusal;
    var usage = const _Usage();
    void refuse(int code, String message) {
      status = code;
      error = message;
      final body = <String, Object>{
        'error': {
          'message': message,
          'type': code == HttpStatus.badRequest
              ? 'invalid_request_error'
              : 'server_error',
          'param': code == HttpStatus.badRequest
              ? RegExp(r'^[a-z_]+').stringMatch(message)
              : null,
          'code': null,
        },
      };
      if (socket == null && request.uri.path == pairPath) {
        // HttpResponse otherwise drains unread input before sending headers.
        // Detach below so a slow rejected peer receives the refusal immediately.
        pairingRefusal = body;
      } else if (socket == null) {
        _json(response, code, body);
      } else {
        writeHeaders(code, 'application/json; charset=utf-8');
        output.write(jsonEncode(body));
      }
    }

    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !allowedClient(remote)) {
        refuse(
          HttpStatus.forbidden,
          'Only devices on the local network or a VPN may connect.',
        );
        return;
      }
      if (request.method == 'OPTIONS') {
        status = response.statusCode = HttpStatus.noContent;
        return;
      }
      // Public bootstrap only: the UI must confirm this pin out of band.
      // Never send the code or bearer token here.
      if (request.uri.path == '/v1/pairing-tls' &&
          _tls != null &&
          request.method == 'GET') {
        _json(response, HttpStatus.ok, {
          'port': tlsPort!,
          'fingerprint': _tls!.fingerprint,
        });
        return;
      }
      if (request.uri.path == pairPath) {
        if (_tls != null && request.connectionInfo?.localPort != tlsPort) {
          refuse(HttpStatus.upgradeRequired, 'Pairing requires pinned HTTPS.');
          return;
        }
        final key = clientLimitKey(remote);
        if (!_pairAdmission.acquire(key)) {
          response.persistentConnection = false;
          refuse(HttpStatus.tooManyRequests, 'Pairing request limit reached.');
          return;
        }
        reservedLane = _pairAdmission;
        laneKey = key;
        await _pair(request, response, refuse);
        return;
      }
      String? authenticate(String token) {
        final device = pairedDevices.principal(token);
        if (device != null) return device;
        if (pairedDevices.legacyEnabled && _sameToken(token, accessToken)) {
          return 'legacy';
        }
        if (remote.isLoopback == true &&
            localAccessToken != null &&
            _sameToken(token, localAccessToken!)) {
          return 'local';
        }
        return null;
      }

      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      final bearer = auth != null && auth.startsWith('Bearer ')
          ? authenticate(auth.substring(7))
          : null;
      final apiKey = request.headers.value('x-api-key');
      final principal =
          bearer ??
          (request.uri.path == messagesPath && apiKey != null
              ? authenticate(apiKey)
              : null);
      if (principal == null) {
        refuse(HttpStatus.unauthorized, 'A valid access token is required.');
        return;
      }
      if (requiresApiTls(remote, request.connectionInfo?.localPort, tlsPort)) {
        refuse(
          HttpStatus.upgradeRequired,
          'Authenticated API requests from the network require HTTPS. '
          'Use the TLS port $tlsPort.',
        );
        return;
      }
      final limitKey = clientLimitKey(remote);
      final control =
          workspace != null &&
          request.method == 'POST' &&
          RegExp(
            r'^/v1/workspace/jobs/[^/]+/(approval|cancel)$',
          ).hasMatch(request.uri.path);
      if (control) {
        if (!_controlAdmission.acquire(limitKey)) {
          response.persistentConnection = false;
          refuse(
            HttpStatus.tooManyRequests,
            'Workspace control limit reached.',
          );
          return;
        }
        reservedLane = _controlAdmission;
        laneKey = limitKey;
        await workspace!.handle(request, principal: principal);
        return;
      }
      if (!_allowRequest(limitKey)) {
        response.persistentConnection = false;
        refuse(
          HttpStatus.tooManyRequests,
          'Client request limit reached. Retry in a minute.',
        );
        return;
      }
      // Reserve before any body is read or workspace handler is entered.
      // Model selection is inside JSON, so this bounds readers and parsed
      // requests waiting on every model queue, without a slow body owning it.
      if (_connections >= maxConnections ||
          (_clientConnections[limitKey] ?? 0) >= maxClientConnections) {
        response.persistentConnection = false;
        refuse(HttpStatus.tooManyRequests, 'Server connection limit reached.');
        return;
      }
      _connections++;
      _clientConnections[limitKey] = (_clientConnections[limitKey] ?? 0) + 1;
      connectionKey = limitKey;
      if (workspace != null &&
          request.uri.path.startsWith('${WorkspaceApi.root}/')) {
        await workspace!.handle(request, principal: principal);
        return;
      }
      if (request.method == 'GET' && request.uri.path == modelsPath) {
        _json(response, HttpStatus.ok, {
          'object': 'list',
          'data': [
            for (final id in {modelId, ...?router?.ids})
              {
                'id': id,
                'object': 'model',
                'owned_by': 'device',
                'type': 'chat',
              },
            for (final entry
                in (vectors?.models ?? const <String, String>{}).entries)
              {
                'id': entry.key,
                'object': 'model',
                'owned_by': 'device-vector',
                'type': entry.value,
              },
          ],
        });
        return;
      }
      if (request.method == 'POST' &&
          (request.uri.path == embeddingsPath ||
              request.uri.path == rerankPath)) {
        await _vector(request, response, refuse);
        return;
      }
      final anthropic = request.uri.path == messagesPath;
      final raw = request.uri.path == rawCompletionsPath;
      final responses = request.uri.path == responsesPath;
      if (request.method != 'POST' ||
          (!anthropic &&
              !raw &&
              !responses &&
              request.uri.path != completionsPath)) {
        refuse(HttpStatus.notFound, 'Endpoint not found.');
        return;
      }
      // Slow request bodies cannot monopolize the model. Claim only after
      // the bounded read, and recheck availability after that await.
      final bodyText = await readBody(request, bodyTimeout);
      final decoded = jsonDecode(bodyText);
      final body = decoded is Map
          ? anthropic
                ? _anthropicBody(decoded)
                : responses
                ? _responsesBody(decoded)
                : decoded
          : decoded;
      if (body is! Map) throw const FormatException('Expected a JSON object.');
      final tools = _tools(body['tools']);
      final toolChoice = _toolChoice(body['tool_choice'], tools);
      final selectedTools =
          const {'auto', 'none', 'required'}.contains(toolChoice)
          ? tools
          : tools.where((tool) => tool.name == toolChoice).toList();
      final bridgeChoice = selectedTools.isEmpty || toolChoice == 'none'
          ? 'none'
          : selectedTools.length == 1 && toolChoice == selectedTools.single.name
          ? 'required'
          : toolChoice;
      final model = body['model'] ?? modelId;
      if (model is! String) {
        throw const FormatException('model must be a string.');
      }
      requested = model;
      // Detach before queuing so both queued and non-streaming peers can
      // abandon work. Headers wait until the status is known.
      response.headers.chunkedTransferEncoding = false;
      response.persistentConnection = false;
      final detached = await response.detachSocket(writeHeaders: false);
      socket = detached;
      output = detached;
      detached.listen(
        (_) {},
        onDone: disconnected,
        onError: (Object _) => disconnected(),
        cancelOnError: true,
      );
      await queue.acquire(model, abandoned: abandoned.future);
      queueKey = model;
      if (abandoned.isCompleted) {
        throw const RouteRefusal(499, 'Client disconnected.');
      }
      if (_server == null) throw const RouteRefusal(503, 'The server stopped.');
      if (model == modelId) {
        if (_busy || isAvailable?.call() == false) {
          refuse(
            HttpStatus.tooManyRequests,
            'The model is answering another request.',
          );
          return;
        }
        _busy = true;
        claimed = true;
        active = _engine;
      } else {
        final engine = await router?.acquire(model);
        if (engine == null) {
          throw const FormatException('Requested model is not loaded.');
        }
        routed = model;
        claimed = true;
        active = engine;
        if (_server == null) {
          throw const RouteRefusal(
            HttpStatus.serviceUnavailable,
            'The server stopped.',
          );
        }
      }
      final engine = active;
      final prompt = raw ? _prompt(body['prompt']) : null;
      if (!raw && (hasProjector?.call(model) ?? false)) {
        imageDirectory = await Directory.systemTemp.createTemp('desktopServe-');
        _imageDirectories.add(imageDirectory);
        if (_server == null) {
          throw const RouteRefusal(
            HttpStatus.serviceUnavailable,
            'The server stopped.',
          );
        }
      }
      final messages = raw
          ? <Map<String, Object>>[]
          : await _messages(
              body['messages'],
              vision: hasProjector?.call(model) ?? false,
              images: images,
              imageDirectory: imageDirectory,
            );
      if (images.isNotEmpty && engine.metrics['supportsVision'] != true) {
        await prepareMedia?.call(model, engine);
      }
      if (body['stream'] != null && body['stream'] is! bool) {
        throw const FormatException('stream must be a boolean.');
      }
      wantsStream = body['stream'] == true;
      final streamOptions = body['stream_options'];
      final includeUsage =
          streamOptions is Map && streamOptions['include_usage'] == true;
      final current = routed == null ? settings() : router!.settingsFor(model);
      final template = routed == null
          ? fallbackTemplate
          : router!.templateFor(model);
      final effective = samplingForRequest(
        body,
        _responseFormat(body, current),
      );
      if (raw && engine is! RawCompletionEngine) {
        throw const RouteRefusal(
          501,
          'Raw completions are unsupported by this engine. '
          'Use /v1/chat/completions instead.',
        );
      }
      if (abandoned.isCompleted) {
        throw const RouteRefusal(499, 'Client disconnected.');
      }
      completion = true;
      var generating = true;
      void cancelIfGenerating() {
        if (generating) engine.cancel();
      }

      onSessionChange?.call(client);
      if (wantsStream) {
        writeHeaders(HttpStatus.ok, 'text/event-stream; charset=utf-8');
      }
      unawaited(
        output.done.then<void>(
          (_) => cancelIfGenerating(),
          onError: (Object _, StackTrace _) => cancelIfGenerating(),
        ),
      );
      streaming = wantsStream;
      final id = 'device-${DateTime.now().microsecondsSinceEpoch}';
      if (anthropic && wantsStream) {
        _event(output, 'message_start', {
          'type': 'message_start',
          'message': {
            'id': id,
            'type': 'message',
            'role': 'assistant',
            'model': model,
            'content': [],
            'stop_reason': null,
            'usage': {'input_tokens': 0, 'output_tokens': 0},
          },
        });
        _event(output, 'content_block_start', {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        });
      }
      Map<String, Object?> chunk(Map<String, Object> delta, {String? finish}) =>
          {
            'id': id,
            'object': raw ? 'text_completion' : 'chat.completion.chunk',
            'model': model,
            'choices': [
              {
                'index': 0,
                if (raw) 'text': delta['content'] ?? '' else 'delta': delta,
                'finish_reason': finish,
              },
            ],
          };
      try {
        final result = StringBuffer();
        var pieces = 0;
        var timedOut = false;
        final timer = Timer(generationTimeout, () {
          timedOut = true;
          engine.cancel();
        });
        try {
          await for (final piece
              in raw
                  ? (engine as RawCompletionEngine).generateRaw(
                      prompt: prompt!,
                      settings: effective,
                    )
                  : engine.generate(
                      messages: messages,
                      fallbackTemplate: template,
                      settings: effective,
                      tools: selectedTools,
                      toolChoice: bridgeChoice,
                    )) {
            if (timedOut) {
              throw TimeoutException('Generation deadline reached.');
            }
            pieces++;
            onProgress?.call(pieces);
            if (wantsStream) {
              if (responses) {
                result.write(piece);
                _event(output, 'response.output_text.delta', {
                  'type': 'response.output_text.delta',
                  'response_id': id,
                  'item_id': '$id-message',
                  'output_index': 0,
                  'content_index': 0,
                  'delta': piece,
                });
              } else if (anthropic) {
                _event(output, 'content_block_delta', {
                  'type': 'content_block_delta',
                  'index': 0,
                  'delta': {'type': 'text_delta', 'text': piece},
                });
              } else {
                output.write(
                  'data: ${jsonEncode(chunk({'content': piece}))}\n\n',
                );
              }
              await output.flush();
            } else {
              result.write(piece);
            }
          }
          if (timedOut) throw TimeoutException('Generation deadline reached.');
        } finally {
          timer.cancel();
        }
        if (!wantsStream) {
          writeHeaders(HttpStatus.ok, 'application/json; charset=utf-8');
        }
        usage = _Usage.from(engine.metrics);
        final calls = TextEngine.toolCallsOf(engine.metrics);
        final finish = engine.metrics['finishReason'] == 'length'
            ? 'length'
            : calls.isNotEmpty
            ? 'tool_calls'
            : 'stop';
        final stopReason = finish == 'length'
            ? 'max_tokens'
            : calls.isNotEmpty
            ? 'tool_use'
            : 'end_turn';
        if (responses) {
          final answer = _response(id, model, result.toString(), finish, usage);
          if (wantsStream) {
            _event(output, 'response.completed', {
              'type': 'response.completed',
              'response': answer,
            });
          } else {
            output.write(jsonEncode(answer));
          }
        } else if (anthropic && wantsStream) {
          _event(output, 'content_block_stop', {
            'type': 'content_block_stop',
            'index': 0,
          });
          for (var i = 0; i < calls.length; i++) {
            final index = i + 1;
            _event(output, 'content_block_start', {
              'type': 'content_block_start',
              'index': index,
              'content_block': {
                'type': 'tool_use',
                'id': calls[i].id,
                'name': calls[i].name,
                'input': {},
              },
            });
            _event(output, 'content_block_delta', {
              'type': 'content_block_delta',
              'index': index,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': calls[i].arguments,
              },
            });
            _event(output, 'content_block_stop', {
              'type': 'content_block_stop',
              'index': index,
            });
          }
          _event(output, 'message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': stopReason, 'stop_sequence': null},
            'usage': {
              'output_tokens': usage.hasCompletion ? usage.completion : null,
            },
          });
          _event(output, 'message_stop', {'type': 'message_stop'});
        } else if (wantsStream) {
          for (var i = 0; i < calls.length; i++) {
            output.write(
              'data: ${jsonEncode(chunk({
                'tool_calls': [
                  {
                    'index': i,
                    'id': calls[i].id,
                    'type': 'function',
                    'function': {'name': calls[i].name, 'arguments': calls[i].arguments},
                  },
                ],
              }))}\n\n',
            );
          }
          output.write(
            'data: ${jsonEncode(chunk(const {}, finish: finish))}\n\n',
          );
          // OpenAI's shape: a last chunk with no choices and the usage,
          // only when the client asked for it.
          if (includeUsage) {
            output.write(
              'data: ${jsonEncode({'id': id, 'object': 'chat.completion.chunk', 'model': model, 'choices': const <Object>[], 'usage': usage.toJson()})}\n\n',
            );
          }
          output.write('data: [DONE]\n\n');
        } else if (anthropic) {
          output.write(
            jsonEncode({
              'id': id,
              'type': 'message',
              'role': 'assistant',
              'model': model,
              'content': [
                if (result.isNotEmpty)
                  {'type': 'text', 'text': result.toString()},
                for (final c in calls)
                  {
                    'type': 'tool_use',
                    'id': c.id,
                    'name': c.name,
                    'input': jsonDecode(c.jsonArguments),
                  },
              ],
              'stop_reason': stopReason,
              'stop_sequence': null,
              'usage': {
                'input_tokens': usage.hasPrompt ? usage.prompt : null,
                'output_tokens': usage.hasCompletion ? usage.completion : null,
              },
            }),
          );
        } else {
          output.write(
            jsonEncode({
              'id': id,
              'object': raw ? 'text_completion' : 'chat.completion',
              'model': model,
              'choices': [
                {
                  'index': 0,
                  if (raw)
                    'text': result.toString()
                  else
                    'message': {
                      'role': 'assistant',
                      'content': result.toString(),
                      if (calls.isNotEmpty)
                        'tool_calls': [
                          for (final c in calls)
                            {
                              'id': c.id,
                              'type': 'function',
                              'function': {
                                'name': c.name,
                                'arguments': c.arguments,
                              },
                            },
                        ],
                    },
                  'finish_reason': finish,
                },
              ],
              'usage': usage.toJson(),
            }),
          );
        }
      } finally {
        generating = false;
        release();
        onSessionChange?.call(null);
      }
    } on RouteRefusal catch (e) {
      if (streaming) {
        error = e.message;
      } else {
        refuse(e.status, e.message);
      }
    } on TimeoutException catch (e) {
      if (claimed) active?.cancel();
      if (!streaming) {
        refuse(HttpStatus.requestTimeout, e.message ?? 'Request timed out.');
      } else {
        error = 'Request timed out.';
      }
    } on FormatException catch (e) {
      if (!streaming) {
        refuse(HttpStatus.badRequest, e.message);
      } else {
        error = e.message;
        active?.cancel();
      }
    } catch (_) {
      if (claimed) active?.cancel();
      if (!streaming) {
        refuse(HttpStatus.internalServerError, 'Request failed.');
      } else {
        error = 'Stream interrupted.';
      }
    } finally {
      if (pairingRefusal != null) {
        try {
          socket = await response.detachSocket(writeHeaders: false);
          output = socket;
          writeHeaders(status, 'application/json; charset=utf-8');
          output.write(jsonEncode(pairingRefusal));
          await output.flush();
        } catch (_) {
          // A disconnected pairing peer has nothing left to receive.
        }
      }
      if (streaming && error != null) {
        try {
          final failure = {
            'error': {'message': error, 'type': 'server_error', 'code': null},
          };
          if (request.uri.path == messagesPath ||
              request.uri.path == responsesPath) {
            _event(output, 'error', {'type': 'error', ...failure});
          } else {
            output.write('data: ${jsonEncode(failure)}\n\ndata: [DONE]\n\n');
          }
          await output.flush();
        } catch (_) {
          /* Peer already disconnected. */
        }
      }
      release();
      if (queueKey != null) queue.release(queueKey);
      for (final file in images) {
        try {
          await file.delete();
        } catch (e, st) {
          quietFailure('device_model_server:1699', e, st);
        }
      }
      if (imageDirectory != null) await _removeImageDirectory(imageDirectory);
      try {
        await output.close();
      } catch (e, st) {
        quietFailure('device_model_server:1704', e, st);
      }
      socket?.destroy();
      if (laneKey != null) reservedLane!.release(laneKey);
      if (connectionKey != null) {
        _connections--;
        final remaining = _clientConnections[connectionKey]! - 1;
        if (remaining == 0) {
          _clientConnections.remove(connectionKey);
        } else {
          _clientConnections[connectionKey] = remaining;
        }
      }
      onServed?.call(
        ServedRequest(
          at: started,
          method: request.method,
          path: request.uri.path,
          client: client,
          attributedClient: attributedClient,
          modelId: requested,
          status: status,
          stream: wantsStream,
          completion: completion,
          promptTokens: usage.prompt,
          completionTokens: usage.completion,
          tokensPerSecond: usage.tokensPerSecond,
          took: clock.elapsed,
          error: error,
        ),
      );
    }
  }

  Future<void> _vector(
    HttpRequest request,
    HttpResponse response,
    void Function(int, String) refuse,
  ) async {
    if (vectors == null) {
      refuse(
        HttpStatus.serviceUnavailable,
        'Embedding hosting unavailable: no independent vector runtime is configured. '
        'A downloaded model and exact tokenizer/context-limit support are required.',
      );
      return;
    }
    final queue = _queue;
    var acquired = false;
    try {
      final body = jsonDecode(await readBody(request, bodyTimeout));
      await queue.acquire('__vectors');
      acquired = true;
      if (body is! Map || body['model'] is! String) {
        throw const FormatException('model must be a string.');
      }
      final model = body['model'] as String;
      if (request.uri.path == embeddingsPath) {
        final input = body['input'];
        final texts = input is String
            ? [input]
            : input is List &&
                  input.isNotEmpty &&
                  input.length <= 64 &&
                  input.every((e) => e is String)
            ? input.cast<String>()
            : throw const FormatException(
                'input must be text or an array of texts.',
              );
        final dims = body['dimensions'] == null
            ? 0
            : body['dimensions'] is int && (body['dimensions'] as int) > 0
            ? body['dimensions'] as int
            : throw const FormatException(
                'dimensions must be a positive integer.',
              );
        final encoding = body['encoding_format'] ?? 'float';
        if (encoding != 'float' && encoding != 'base64') {
          throw const FormatException(
            'encoding_format must be float or base64.',
          );
        }
        if (vectors!.models.isNotEmpty &&
            vectors!.models[model] != 'embedding') {
          throw const FormatException(
            'model must name an available embedding model.',
          );
        }
        final measured = await vectors!.tokenCounts(model, texts);
        if (measured == null || measured.counts.length != texts.length) {
          throw const RouteRefusal(
            503,
            'Embedding hosting unavailable: the vector runtime does not expose exact '
            'token counts and a context limit. Refusing to silently truncate input.',
          );
        }
        for (var i = 0; i < measured.counts.length; i++) {
          if (measured.counts[i] > measured.limit) {
            throw FormatException(
              'input[$i] has ${measured.counts[i]} tokens; '
              'the model limit is ${measured.limit} tokens.',
            );
          }
        }
        final rows = await vectors!.embed(model, texts, dims);
        if (rows.length != texts.length) {
          throw StateError('Embedding count mismatch.');
        }
        if (dims > 0 && rows.any((row) => row.length != dims)) {
          throw const FormatException(
            'dimensions exceeds the model embedding width.',
          );
        }
        _json(response, HttpStatus.ok, {
          'object': 'list',
          'model': model,
          'data': [
            for (var i = 0; i < rows.length; i++)
              {
                'object': 'embedding',
                'index': i,
                'embedding': encoding == 'base64'
                    ? _base64Vector(rows[i])
                    : rows[i],
              },
          ],
          'usage': {
            'prompt_tokens': measured.counts.fold<int>(0, (a, b) => a + b),
            'total_tokens': measured.counts.fold<int>(0, (a, b) => a + b),
          },
        });
      } else {
        final query = body['query'];
        final docs = body['documents'];
        if (query is! String ||
            docs is! List ||
            docs.isEmpty ||
            docs.length > 64 ||
            !docs.every((e) => e is String)) {
          throw const FormatException('query and documents must be text.');
        }
        final documents = docs.cast<String>();
        final scores = await vectors!.rerank(model, query, documents);
        if (scores.length != documents.length) {
          throw StateError('Rerank count mismatch.');
        }
        final order = List<int>.generate(scores.length, (i) => i)
          ..sort((a, b) => scores[b].compareTo(scores[a]));
        _json(response, HttpStatus.ok, {
          'model': model,
          'results': [
            for (final i in order)
              {
                'index': i,
                'relevance_score': scores[i],
                if (body['return_documents'] == true)
                  'document': {'text': documents[i]},
              },
          ],
        });
      }
    } on FormatException catch (e) {
      refuse(HttpStatus.badRequest, e.message);
    } on RouteRefusal catch (e) {
      refuse(e.status, e.message);
    } catch (_) {
      refuse(HttpStatus.serviceUnavailable, 'Embedding model is unavailable.');
    } finally {
      if (acquired) queue.release('__vectors');
    }
  }

  static Future<String> readBody(
    Stream<List<int>> request,
    Duration timeout, {
    int maxBytes = 24 * 1024 * 1024,
  }) async {
    final limitMessage = maxBytes == 24 * 1024 * 1024
        ? 'Request is larger than 24 MB.'
        : 'Request is larger than $maxBytes bytes.';
    if (request is HttpRequest && request.contentLength > maxBytes) {
      throw FormatException(limitMessage);
    }
    final bytes = BytesBuilder(copy: false);
    final iterator = StreamIterator(request);
    final clock = Stopwatch()..start();
    try {
      while (true) {
        final left = timeout - clock.elapsed;
        if (left <= Duration.zero) {
          throw TimeoutException('Request body deadline reached.');
        }
        if (!await iterator.moveNext().timeout(left)) break;
        if (iterator.current.length > maxBytes - bytes.length) {
          throw FormatException(limitMessage);
        }
        bytes.add(iterator.current);
      }
    } finally {
      await iterator.cancel();
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<void> _pair(
    HttpRequest request,
    HttpResponse response,
    void Function(int code, String message) refuse,
  ) async {
    if (request.method != 'POST' || pairCode == null) {
      refuse(HttpStatus.notFound, 'Endpoint not found.');
      return;
    }
    if (_pairing.expired) _rotatePairing(expired: true);
    // QR clients explicitly opt into the bounded QR lane during typed lockout.
    if (_pairLocked && request.headers.value('X-Pairing-Mode') != 'qr') {
      response.persistentConnection = false;
      refuse(
        HttpStatus.tooManyRequests,
        'Too many wrong pairing codes. Wait for the code to expire.',
      );
      return;
    }
    final body = jsonDecode(
      await readBody(request, bodyTimeout, maxBytes: 4096),
    );
    // Snapshot only after the asynchronous read: expiry may rotate meanwhile.
    if (_pairing.expired) _rotatePairing(expired: true);
    final session = _pairing;
    final code = pairCode!;
    final qr = body is Map && body.containsKey('secret');
    final given = body is Map ? PairingCode.normalize('${body['code']}') : '';
    if (body is Map &&
        ((qr && body['secret'] == _expiredSecret) ||
            (!qr && given == _expiredCode))) {
      refuse(
        HttpStatus.gone,
        'Pairing expired. Scan the new QR or enter the new code.',
      );
      return;
    }
    if (!qr && (_pairLocked || !session.reserve())) {
      _pairLocked = true;
      onPairingUnavailable?.call(true);
      refuse(
        HttpStatus.tooManyRequests,
        'Too many wrong pairing codes. Wait for the code to expire.',
      );
      return;
    }
    final valid = qr
        ? body['secret'] is String &&
              body['hostId'] == hostId &&
              _sameToken(body['secret'] as String, pairingSecret)
        : _sameToken(given, code);
    if (!valid) {
      if (!qr && session.locked) {
        _pairLocked = true;
        onPairingUnavailable?.call(true);
      }
      refuse(HttpStatus.unauthorized, 'Wrong pairing code or secret.');
      return;
    }
    if (!identical(session, _pairing) || !session.accept(reserved: !qr)) {
      refuse(
        HttpStatus.gone,
        'Pairing expired or already used. Scan the new QR.',
      );
      return;
    }
    _rotatePairing();
    final token = await pairedDevices.issue(
      request.connectionInfo?.remoteAddress.address ?? hostId,
    );
    onDevicesChanged?.call();
    _json(response, HttpStatus.ok, {
      'key': token,
      'model': modelId,
      'hostId': hostId,
    });
  }

  Future<void> revokeDevice(String id) async {
    await pairedDevices.revoke(id);
    await workspace?.revokePrincipal(id);
    onDevicesChanged?.call();
  }

  static bool _sameToken(String provided, String expected) {
    return PairedDevices.sameToken(provided, expected);
  }

  static void _json(
    HttpResponse response,
    int status,
    Map<String, Object> body,
  ) {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}

/// Measured tokenizer usage. Missing metrics are null on the wire.
class _Usage {
  final int prompt, completion;
  final double tokensPerSecond;
  final bool hasPrompt, hasCompletion;
  const _Usage({
    this.prompt = 0,
    this.completion = 0,
    this.tokensPerSecond = 0,
    this.hasPrompt = false,
    this.hasCompletion = false,
  });

  factory _Usage.from(Map<String, dynamic> m) => _Usage(
    prompt: (m['promptTokens'] as num?)?.toInt() ?? 0,
    completion: (m['tokens'] as num?)?.toInt() ?? 0,
    hasPrompt: m['promptTokens'] is num,
    hasCompletion: m['tokens'] is num,
    tokensPerSecond: (m['tokensPerSecond'] as num?)?.toDouble() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'prompt_tokens': hasPrompt ? prompt : null,
    'completion_tokens': hasCompletion ? completion : null,
    'total_tokens': hasPrompt && hasCompletion ? prompt + completion : null,
  };
}

/// Independent bounded budgets keep public pairing and authenticated controls
/// usable without allowing either lane to create unlimited body readers.
class _Admission {
  final int maxGlobal, maxClient, rate;
  final Map<String, List<DateTime>> _requests = {};
  final Map<String, int> _clients = {};
  int _active = 0;
  _Admission({
    required this.maxGlobal,
    required this.maxClient,
    required this.rate,
  });

  bool acquire(String key) {
    final now = DateTime.now();
    const window = Duration(minutes: 1);
    _requests.removeWhere(
      (_, times) => times.every((t) => now.difference(t) >= window),
    );
    final times = _requests.putIfAbsent(key, () => []);
    times.removeWhere((t) => now.difference(t) >= window);
    if (times.length >= rate) return false;
    times.add(now);
    if (_active >= maxGlobal || (_clients[key] ?? 0) >= maxClient) return false;
    _active++;
    _clients[key] = (_clients[key] ?? 0) + 1;
    return true;
  }

  void release(String key) {
    _active--;
    final remaining = _clients[key]! - 1;
    if (remaining == 0) {
      _clients.remove(key);
    } else {
      _clients[key] = remaining;
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../inference/engine/text_engine.dart';
import '../settings/domain/entities/inference_settings.dart';

/// One request the device server answered (or refused), for the live
/// dashboard on the hosting page.
class ServedRequest {
  final DateTime at;
  final String client;

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
    required this.status,
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

/// Opt-in OpenAI-compatible endpoint for the model loaded on this device.
class DeviceModelServer {
  final TextEngine engine;
  final InferenceSettings Function() settings;
  final String modelId;
  final String fallbackTemplate;
  final String accessToken;
  final bool Function()? isAvailable;
  final void Function(String? client)? onSessionChange;

  /// Called once per request with what happened to it.
  final void Function(ServedRequest request)? onServed;

  /// Called while an answer streams with the pieces generated so far.
  final void Function(int pieces)? onProgress;
  HttpServer? _server;
  bool _busy = false;
  final Duration bodyTimeout, generationTimeout;
  final Map<String, List<DateTime>> _clientRequests = {};

  DeviceModelServer({
    required this.engine,
    required this.settings,
    required this.modelId,
    required this.fallbackTemplate,
    required this.accessToken,
    this.isAvailable,
    this.onSessionChange,
    this.onServed,
    this.onProgress,
    this.bodyTimeout = const Duration(seconds: 15),
    this.generationTimeout = const Duration(minutes: 10),
  }) {
    if (accessToken.length < 32) {
      throw ArgumentError.value(
        accessToken.length,
        'accessToken',
        'Use at least 32 random characters.',
      );
    }
  }

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  InternetAddress? get address => _server?.address;

  /// Plain HTTP on the local network only: every request from an address
  /// outside [allowedClient] is refused before the token is even checked.
  Future<void> start({InternetAddress? address, int port = 0}) async {
    if (_server != null) throw StateError('Server is already running.');
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _server = server;
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
      if (identical(_server, server)) _server = null;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    if (_busy) engine.cancel();
    onSessionChange?.call(null);
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

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final started = DateTime.now();
    final clock = Stopwatch()..start();
    final client =
        request.connectionInfo?.remoteAddress.address ?? 'Unknown client';
    var streaming = false, wantsStream = false, completion = false;
    // Whether this request holds the engine (released in the outer finally).
    var claimed = false;
    var status = HttpStatus.ok;
    String? error;
    var usage = const _Usage();
    void refuse(int code, String message) {
      status = code;
      error = message;
      _json(response, code, {
        'error': {'message': message},
      });
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
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth == null ||
          !auth.startsWith('Bearer ') ||
          !_sameToken(auth.substring(7), accessToken)) {
        refuse(HttpStatus.unauthorized, 'A valid access token is required.');
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/v1/models') {
        _json(response, HttpStatus.ok, {
          'object': 'list',
          'data': [
            {'id': modelId, 'object': 'model', 'owned_by': 'device'},
          ],
        });
        return;
      }
      if (request.method != 'POST' ||
          request.uri.path != '/v1/chat/completions') {
        refuse(HttpStatus.notFound, 'Endpoint not found.');
        return;
      }
      if (_busy || isAvailable?.call() == false) {
        refuse(
          HttpStatus.tooManyRequests,
          'The model is answering another request.',
        );
        return;
      }
      final now = DateTime.now();
      _clientRequests.removeWhere(
        (_, times) =>
            times.every((t) => now.difference(t) >= const Duration(minutes: 1)),
      );
      final recent = _clientRequests.putIfAbsent(client, () => []);
      recent.removeWhere(
        (t) => now.difference(t) >= const Duration(minutes: 1),
      );
      if (recent.length >= 20) {
        refuse(
          HttpStatus.tooManyRequests,
          'Client request limit reached. Retry in a minute.',
        );
        return;
      }
      recent.add(now);
      // Slow request bodies cannot monopolize the model. Claim only after
      // the bounded read, and recheck availability after that await.
      final bodyText = await _body(request, bodyTimeout);
      if (_busy || isAvailable?.call() == false) {
        refuse(
          HttpStatus.tooManyRequests,
          'The model is answering another request.',
        );
        return;
      }
      _busy = true;
      claimed = true;
      final body = jsonDecode(bodyText);
      if (body is! Map ||
          body['messages'] is! List ||
          (body['messages'] as List).length > 64) {
        throw const FormatException('Expected at most 64 messages.');
      }
      if (body['model'] != null && body['model'] != modelId) {
        throw const FormatException('Requested model is not loaded.');
      }
      if (body['tools'] is List && (body['tools'] as List).isNotEmpty) {
        throw const FormatException(
          'Tool calling is not supported by this device server.',
        );
      }
      if (body['stream'] != null && body['stream'] is! bool) {
        throw const FormatException('stream must be a boolean.');
      }
      wantsStream = body['stream'] == true;
      final streamOptions = body['stream_options'];
      final includeUsage =
          streamOptions is Map && streamOptions['include_usage'] == true;
      final messages = <Map<String, Object>>[];
      for (final item in body['messages'] as List) {
        if (item is! Map ||
            item['role'] is! String ||
            item['content'] is! String ||
            !const {
              'system',
              'user',
              'assistant',
            }.contains(item['role'] as String)) {
          throw const FormatException(
            'Only text system, user and assistant messages are supported.',
          );
        }
        messages.add({
          'role': item['role'] as String,
          'content': item['content'] as String,
        });
      }
      if (messages.isEmpty) {
        throw const FormatException('At least one message is required.');
      }
      final current = settings();
      final temperature = (body['temperature'] as num?)?.toDouble();
      final maxTokens = (body['max_tokens'] as num?)?.toInt();
      final effective = current.copyWith(
        temperature: temperature?.clamp(0.0, 2.0),
        maxTokens: maxTokens?.clamp(1, current.contextSize),
      );
      completion = true;
      var generating = true;
      unawaited(
        response.done.then<void>(
          (_) {
            if (generating) engine.cancel();
          },
          onError: (Object _, StackTrace _) {
            if (generating) engine.cancel();
          },
        ),
      );
      onSessionChange?.call(client);
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = wantsStream
          ? ContentType('text', 'event-stream', charset: 'utf-8')
          : ContentType.json;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      streaming = wantsStream;
      final id = 'device-${DateTime.now().microsecondsSinceEpoch}';
      Map<String, Object?> chunk(Map<String, Object> delta, {String? finish}) =>
          {
            'id': id,
            'object': 'chat.completion.chunk',
            'model': modelId,
            'choices': [
              {'index': 0, 'delta': delta, 'finish_reason': finish},
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
          await for (final piece in engine.generate(
            messages: messages,
            fallbackTemplate: fallbackTemplate,
            settings: effective,
          )) {
            if (timedOut) {
              throw TimeoutException('Generation deadline reached.');
            }
            pieces++;
            onProgress?.call(pieces);
            if (wantsStream) {
              response.write(
                'data: ${jsonEncode(chunk({'content': piece}))}\n\n',
              );
              await response.flush();
            } else {
              result.write(piece);
            }
          }
          if (timedOut) throw TimeoutException('Generation deadline reached.');
        } finally {
          timer.cancel();
        }
        usage = _Usage.from(engine.metrics, fallbackTokens: pieces);
        if (wantsStream) {
          response.write(
            'data: ${jsonEncode(chunk(const {}, finish: 'stop'))}\n\n',
          );
          // OpenAI's shape: a last chunk with no choices and the usage,
          // only when the client asked for it.
          if (includeUsage) {
            response.write(
              'data: ${jsonEncode({'id': id, 'object': 'chat.completion.chunk', 'model': modelId, 'choices': const <Object>[], 'usage': usage.toJson()})}\n\n',
            );
          }
          response.write('data: [DONE]\n\n');
        } else {
          response.write(
            jsonEncode({
              'id': id,
              'object': 'chat.completion',
              'model': modelId,
              'choices': [
                {
                  'index': 0,
                  'message': {
                    'role': 'assistant',
                    'content': result.toString(),
                  },
                  'finish_reason': 'stop',
                },
              ],
              'usage': usage.toJson(),
            }),
          );
        }
      } finally {
        generating = false;
        _busy = false;
        onSessionChange?.call(null);
      }
    } on TimeoutException catch (e) {
      if (claimed) engine.cancel();
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
        engine.cancel();
      }
    } catch (_) {
      if (claimed) engine.cancel();
      if (!streaming) {
        refuse(HttpStatus.internalServerError, 'Request failed.');
      } else {
        error = 'Stream interrupted.';
      }
    } finally {
      // A request refused after claiming (bad body) releases the engine.
      if (claimed) _busy = false;
      try {
        await response.close();
      } catch (_) {}
      onServed?.call(
        ServedRequest(
          at: started,
          client: client,
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

  static Future<String> _body(HttpRequest request, Duration timeout) async {
    const maxBytes = 1024 * 1024;
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
        bytes.add(iterator.current);
        if (bytes.length > maxBytes) {
          throw const FormatException('Request is larger than 1 MB.');
        }
      }
    } finally {
      await iterator.cancel();
    }
    return utf8.decode(bytes.takeBytes());
  }

  static bool _sameToken(String provided, String expected) {
    final a = utf8.encode(provided);
    final b = utf8.encode(expected);
    var difference = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      difference |= (i < a.length ? a[i] : 0) ^ b[i];
    }
    return difference == 0;
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

/// Token counts of one answer, from the engine's metrics (the pieces
/// streamed when the engine reports none).
class _Usage {
  final int prompt, completion;
  final double tokensPerSecond;
  const _Usage({
    this.prompt = 0,
    this.completion = 0,
    this.tokensPerSecond = 0,
  });

  factory _Usage.from(Map<String, dynamic> m, {required int fallbackTokens}) =>
      _Usage(
        prompt: (m['promptTokens'] as num?)?.toInt() ?? 0,
        completion: (m['tokens'] as num?)?.toInt() ?? fallbackTokens,
        tokensPerSecond: (m['tokensPerSecond'] as num?)?.toDouble() ?? 0,
      );

  Map<String, Object> toJson() => {
    'prompt_tokens': prompt,
    'completion_tokens': completion,
    'total_tokens': prompt + completion,
  };
}

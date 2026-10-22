import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/errors/exceptions.dart';
import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/tools/domain/tool_spec.dart';
import '../engine/text_engine.dart';
import 'remote_provider.dart';
import 'remote_usage.dart';

/// A model the remote provider offers.
class RemoteModel {
  final String id;
  final String? displayName;
  final Set<String> capabilities;
  final String? owner;

  /// Context window when the provider reports it (Anthropic, Gemini).
  final int? contextWindow;
  const RemoteModel(
    this.id, {
    this.displayName,
    this.capabilities = const {},
    this.owner,
    this.contextWindow,
  });

  bool supports(String capability) => capabilities.any(
    (value) => value.toLowerCase().contains(capability.toLowerCase()),
  );
}

class RemoteServerReport {
  final List<RemoteModel> models;
  final String health;
  final List<String> tools;
  const RemoteServerReport({
    required this.models,
    required this.health,
    required this.tools,
  });

  String get summary {
    final base =
        'Connected · ${models.length} model${models.length == 1 ? '' : 's'}';
    // Hosted APIs are not probed for health or server tools.
    if (health == 'n/a') return base;
    return '$base · health $health'
        '${tools.isEmpty ? ' · no server tools advertised' : ' · ${tools.length} server tool${tools.length == 1 ? '' : 's'} detected'}';
  }
}

/// Chat client for the connection the user selected in Settings > Remote:
/// an OpenAI-compatible server (LM Studio, Ollama, llama-server, vLLM or a
/// hosted API with the same shape), the Anthropic Messages API or the
/// Google Gemini API. Opt-in only: the app never contacts it unless
/// [InferenceSettings.remoteEnabled] is on and a profile has a URL.
///
/// Every protocol streams and relays content deltas. Reasoning
/// (`reasoning_content`/`reasoning` on OpenAI-style servers, `thinking`
/// blocks on Anthropic, `thought` parts on Gemini) is re-emitted inside
/// `<think>` tags so the rest of the app treats it like on-device thinking.
class RemoteEngine implements TextEngine {
  final Dio _dio;
  final RemoteUsageLog usage;
  CancelToken? _cancel;
  @override
  Map<String, dynamic> metrics = const {};

  /// Gemini attaches a thought signature to function calls that must be
  /// echoed with the call on the next request; kept by call id.
  final _geminiSignatures = <String, String>{};

  /// Gemini models that rejected `thinkingConfig` this session, and the
  /// thinking levels each model rejected.
  final _geminiNoThinkingConfig = <String>{};

  /// Gemini models that rejected presence and frequency penalties this
  /// session ("Penalty is not enabled for this model": Gemini 3.5 Flash-Lite,
  /// tester, 2026-10-09).
  final _geminiNoPenalty = <String>{};
  final _geminiNoLevel = <String, Set<String>>{};

  /// What OpenAI-style servers refused this session, per connection and
  /// model: optional fields they reject by name (`max_tokens` stands for
  /// "wants `max_completion_tokens`"), and `reasoning_effort` values they
  /// replaced with one they list as supported.
  final _openAiDropped = <String, Set<String>>{};
  final _openAiEffort = <String, Map<String, String>>{};

  /// Claude models that rejected `output_config.effort`, and those that
  /// take a fixed thinking budget instead of adaptive thinking.
  final _anthropicNoEffort = <String>{};
  final _anthropicNoAdaptive = <String>{};

  /// Claude needs `max_tokens`; with the server's own settings it asks for
  /// this much and steps down to what a model says is its maximum.
  static const anthropicServerCeiling = 32000;
  final _anthropicCeiling = <String, int>{};

  /// Connections and models that refused function calling this session
  /// (an Ollama or LM Studio model without tool support): their turns
  /// fall back to the app's own search planning ([acceptsTools]).
  static final _noTools = <String>{};

  /// The context each connection's model reports, by [_windowKey]: the
  /// listing's window on hosted APIs, the loaded context on LM Studio and
  /// llama-server. Used when the profile keeps the server's own settings.
  static final _windows = <String, int>{};
  static final _windowAsked = <String>{};

  static String _windowKey(InferenceSettings s) =>
      '${s.activeRemoteProfile?.id}|${s.remoteModel.trim().toLowerCase()}';

  /// Whether this connection's model can take function declarations: the
  /// remote model then plans its own searches (decision 2026-10-18).
  /// Gemma on the Gemini API has no function calling.
  static bool acceptsTools(InferenceSettings s) {
    final profile = s.activeRemoteProfile;
    if (profile == null) return false;
    if (profile.provider.protocol == RemoteProtocol.gemini &&
        geminiBasic(s.remoteModel)) {
      return false;
    }
    return !_noTools.contains(_windowKey(s));
  }

  /// Records the context window a listing reported for [models].
  static void _rememberWindows(InferenceSettings s, List<RemoteModel> models) {
    final id = s.activeRemoteProfile?.id;
    for (final m in models) {
      final w = m.contextWindow;
      if (w != null && w > 0) _windows['$id|${m.id.toLowerCase()}'] = w;
    }
  }

  /// Learns the model's context once per session when the profile keeps
  /// the server's own settings. LM Studio reports the context it loaded
  /// the model with, llama-server its `n_ctx`; hosted APIs answer from
  /// their model listing. A failure leaves the phone's setting in charge.
  Future<void> learnWindow(InferenceSettings s) async {
    final profile = s.activeRemoteProfile;
    final base = s.remoteUri;
    if (profile == null || base == null || !profile.serverSettings) return;
    final key = _windowKey(s);
    if (_windows.containsKey(key) || !_windowAsked.add(key)) return;
    final options = Options(
      headers: _headers(s),
      receiveTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
    );
    final id = profile.provider.id;
    final model = s.remoteModel.trim();
    if (id == 'lmstudio' || id == 'custom') {
      try {
        final res = await _dio.getUri<dynamic>(
          profile.provider.serverEndpoint(base, 'api/v0/models'),
          options: options,
        );
        final list = _json(res.data)['data'];
        if (list is List) {
          for (final m in list) {
            if (m is! Map || m['loaded_context_length'] is! num) continue;
            if (model.isNotEmpty && m['id'] != model) continue;
            _windows[key] = (m['loaded_context_length'] as num).toInt();
            return;
          }
        }
      } catch (_) {
        // Not LM Studio; try the next way.
      }
    }
    if (id == 'llamacpp' || id == 'custom') {
      try {
        final res = await _dio.getUri<dynamic>(
          profile.provider.serverEndpoint(base, 'props'),
          options: options,
        );
        final settings = _json(res.data)['default_generation_settings'];
        final n = settings is Map ? settings['n_ctx'] : null;
        if (n is num && n > 0) {
          _windows[key] = n.toInt();
          return;
        }
      } catch (_) {
        // Not llama-server.
      }
    }
    if (!profile.provider.selfHosted && profile.provider.listsModels) {
      try {
        await listModels(s);
      } catch (_) {
        // The phone's setting stays in charge.
      }
    }
  }

  RemoteEngine({Dio? dio, RemoteUsageLog? usage})
    : usage = usage ?? RemoteUsageLog(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              // Long answers stream for minutes; the per-chunk gap is what
              // should time out, not the whole response.
              receiveTimeout: const Duration(seconds: 120),
            ),
          );

  /// `{base}/v1/{path}` for an OpenAI-compatible server (see
  /// [RemoteProvider.endpoint] for provider-specific roots).
  static Uri endpoint(Uri base, String path) =>
      RemoteProvider.custom.endpoint(base, path);

  static Uri serverEndpoint(Uri base, String path) =>
      RemoteProvider.custom.serverEndpoint(base, path);

  static Map<String, String> _headers(InferenceSettings s) {
    final profile = s.activeRemoteProfile;
    final provider = s.remoteProvider;
    return {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream, application/json',
      ...?profile?.headers,
      ...provider.authHeaders(s.remoteApiKey),
    };
  }

  static InferenceException _explain(Object e, Uri base) {
    if (e is RemoteLimitReached) return InferenceException(e.message);
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final detail = _errorMessage(body);
      if (_terminalQuota.hasMatch(detail)) return InferenceException(detail);
      if (status == 401 || status == 403) {
        return InferenceException(
          'The server rejected the API key (HTTP $status)${detail.isEmpty ? '.' : ': $detail'}',
        );
      }
      if (status == 404) {
        return InferenceException(
          'No API at ${base.host}${base.hasPort ? ':${base.port}' : ''}${base.path} (HTTP 404)${detail.isEmpty ? '. Check the URL, the model ID and that the server is started.' : ': $detail'}',
        );
      }
      if (status == 429) {
        return InferenceException(
          'The provider is rate-limiting this key (HTTP 429)${detail.isEmpty ? '. Wait a moment or set a request cap in the connection settings.' : ': $detail'}',
        );
      }
      if (status != null) {
        return InferenceException(
          'Server error HTTP $status${detail.isEmpty ? '' : ': $detail'}',
        );
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        return InferenceException(
          'Cannot reach ${base.host}${base.hasPort ? ':${base.port}' : ''}. Is the server running and the VPN/LAN connected?',
        );
      }
      if (e.type == DioExceptionType.cancel) {
        return const InferenceException('Cancelled');
      }
    }
    return InferenceException('Remote server: $e');
  }

  // Exhausted daily/credit quotas cannot be repaired by dropping sampling or
  // thinking fields. Ordinary per-minute rate limits still use bounded retries.
  static final _terminalQuota = RegExp(
    r'(?:not enough|insufficient|exhausted|depleted|no remaining)\s+(?:quota|credits)'
    r'|(?:quota|credits)(?:\s+\w+){0,3}\s+(?:exhausted|depleted)'
    r'|insufficient_quota'
    // Gemini names the quota "GenerateRequestsPerDayPerProjectPerModel".
    r'|(?:daily|per[-_ ]?day).{0,80}(?:quota|limit)'
    r'|(?:quota|limit).{0,80}(?:daily|per[-_ ]?day)',
    caseSensitive: false,
  );

  /// The human part of an error body, whichever provider shape it uses.
  static String _errorMessage(Object? body) {
    Object? data = body;
    if (data is ResponseBody) return '';
    if (data is String) {
      final text = data;
      try {
        data = jsonDecode(text);
      } catch (_) {
        return text.length > 200 ? text.substring(0, 200) : text.trim();
      }
    }
    if (data is Map) {
      final err = data['error'];
      final msg = err is Map
          ? err['message']
          : err is String
          ? err
          : null;
      if (msg is String && msg.isNotEmpty) {
        return msg.length > 200 ? msg.substring(0, 200) : msg;
      }
    }
    return '';
  }

  static Map<String, dynamic> _json(Object? data) {
    final v = data is String ? jsonDecode(data) : data;
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  /// Models the connection offers, for the settings picker.
  Future<List<RemoteModel>> listModels(InferenceSettings s) async {
    final models = await _listModels(s);
    _rememberWindows(s, models);
    return models;
  }

  Future<List<RemoteModel>> _listModels(InferenceSettings s) async {
    final base = s.remoteUri;
    if (base == null) throw const InferenceException('Set a server URL.');
    final provider = s.remoteProvider;
    if (!provider.listsModels) return const [];
    try {
      switch (provider.protocol) {
        case RemoteProtocol.openai:
          final res = await _dio.getUri<dynamic>(
            provider.endpoint(base, 'models'),
            options: Options(headers: _headers(s)),
          );
          final data = res.data is String
              ? jsonDecode(res.data as String)
              : res.data;
          final list = (data is Map ? data['data'] : data) as List? ?? const [];
          return [
            for (final m in list)
              if (m is Map && m['id'] is String)
                RemoteModel(
                  m['id'] as String,
                  displayName: m['name'] is String ? m['name'] as String : null,
                  capabilities: {
                    for (final value in switch (m['capabilities']) {
                      final List values => values,
                      _ => const [],
                    })
                      if (value is String) value,
                  },
                  owner: m['owned_by'] is String
                      ? m['owned_by'] as String
                      : null,
                  contextWindow: (m['context_length'] as num?)?.toInt(),
                ),
          ];
        case RemoteProtocol.anthropic:
          final res = await _dio.getUri<dynamic>(
            provider
                .endpoint(base, 'models')
                .replace(queryParameters: {'limit': '1000'}),
            options: Options(headers: _headers(s)),
          );
          final list = _json(res.data)['data'] as List? ?? const [];
          return [
            for (final m in list)
              if (m is Map && m['id'] is String)
                RemoteModel(
                  m['id'] as String,
                  displayName: m['display_name'] as String?,
                  contextWindow: (m['max_input_tokens'] as num?)?.toInt(),
                  capabilities: _anthropicCapabilities(m['capabilities']),
                ),
          ];
        case RemoteProtocol.gemini:
          final res = await _dio.getUri<dynamic>(
            provider
                .endpoint(base, 'models')
                .replace(queryParameters: {'pageSize': '1000'}),
            options: Options(headers: _headers(s)),
          );
          final list = _json(res.data)['models'] as List? ?? const [];
          return [
            for (final m in list)
              if (m is Map &&
                  m['name'] is String &&
                  ((m['supportedGenerationMethods'] as List?)?.contains(
                        'generateContent',
                      ) ??
                      true))
                RemoteModel(
                  (m['name'] as String).replaceFirst('models/', ''),
                  displayName: m['displayName'] as String?,
                  contextWindow: (m['inputTokenLimit'] as num?)?.toInt(),
                ),
          ];
      }
    } catch (e) {
      throw _explain(e, base);
    }
  }

  /// Leaves of Anthropic's capability tree that are supported.
  static Set<String> _anthropicCapabilities(Object? tree) {
    final out = <String>{};
    void walk(String path, Object? node) {
      if (node is! Map) return;
      if (node['supported'] == true && path.isNotEmpty) out.add(path);
      for (final e in node.entries) {
        if (e.key == 'supported') continue;
        walk(path.isEmpty ? '${e.key}' : '$path.${e.key}', e.value);
      }
    }

    walk('', tree);
    return out;
  }

  /// Connectivity and best-effort capability discovery. Model listing is
  /// the only required call; `/health` and `/tools` are probed on self-hosted
  /// servers only (hosted APIs have neither). Detected tools are
  /// informational and are never executed here.
  Future<RemoteServerReport> probe(InferenceSettings s) async {
    final base = s.remoteUri;
    if (base == null) throw const InferenceException('Set a server URL.');
    final provider = s.remoteProvider;
    final models = await listModels(s);
    if (!provider.selfHosted) {
      return RemoteServerReport(models: models, health: 'n/a', tools: const []);
    }
    var health = 'unknown';
    final tools = <String>[];
    try {
      final response = await _dio.getUri<dynamic>(
        provider.serverEndpoint(base, 'health'),
        options: Options(headers: _headers(s), validateStatus: (_) => true),
      );
      if ((response.statusCode ?? 0) >= 200 &&
          (response.statusCode ?? 0) < 300) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        health = data is Map && data['status'] != null
            ? '${data['status']}'
            : 'ok';
      } else {
        health = 'not advertised';
      }
    } catch (_) {
      health = 'not advertised';
    }
    try {
      final response = await _dio.getUri<dynamic>(
        provider.serverEndpoint(base, 'tools'),
        options: Options(headers: _headers(s), validateStatus: (_) => true),
      );
      if ((response.statusCode ?? 0) >= 200 &&
          (response.statusCode ?? 0) < 300) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final values = data is List
            ? data
            : data is Map && data['data'] is List
            ? data['data'] as List
            : data is Map && data['tools'] is List
            ? data['tools'] as List
            : const [];
        for (final value in values) {
          final name = value is String
              ? value
              : value is Map
              ? value['name'] ?? value['id']
              : null;
          if (name is String && name.isNotEmpty) tools.add(name);
        }
      }
    } catch (_) {
      // Optional endpoint.
    }
    return RemoteServerReport(models: models, health: health, tools: tools);
  }

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    // The server tokenizes; ~3.5 characters per token is close enough to
    // keep web evidence inside the user's context setting.
    final chars =
        messages.fold<int>(
          0,
          (n, m) => n + ((m['content'] as String?) ?? '').length,
        ) +
        tools.fold<int>(0, (n, t) => n + jsonEncode(t.toJson()).length);
    // Servers bill roughly a thousand tokens per image tile.
    final images = messages.fold<int>(
      0,
      (n, m) => n + ((m['images'] as List?)?.length ?? 0),
    );
    final count = (chars / 3.5).ceil() + 8 * messages.length + 1000 * images;
    await learnWindow(settings);
    final window = contextFor(settings);
    final reserve = settings.responseReserve(window);
    return {
      'promptTokens': count,
      'contextSize': window,
      'reservedTokens': reserve,
      'availableTokens': window - reserve - count,
      'fits': count + reserve <= window,
      'estimated': true,
    };
  }

  /// The context a remote turn is budgeted against. The phone's context
  /// setting (4K by default) was also capping hosted models that take 128K
  /// to 1M tokens, so web evidence and tool results were cut to a phone's
  /// size; hosted providers get at least 32K. A self-hosted server runs with
  /// the context it was loaded with, which the user's setting describes.
  ///
  /// A profile that keeps the server's own settings is budgeted against the
  /// window the server reported ([learnWindow]), when it reported one.
  static int contextFor(InferenceSettings settings) {
    final profile = settings.activeRemoteProfile;
    final known = profile != null && profile.serverSettings
        ? _windows[_windowKey(settings)]
        : null;
    if (known != null) return known;
    final provider = profile?.provider;
    final hosted = provider != null && !provider.selfHosted;
    return hosted ? max(settings.contextSize, 32768) : settings.contextSize;
  }

  static String _mediaType(String path) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
  }

  /// OpenAI content: text plus `image_url` data URLs for attached photos;
  /// the local marker text is dropped since the server places images itself.
  static Future<List<Map<String, Object>>> openAiMessages(
    List<Map<String, Object>> messages,
  ) async {
    final out = <Map<String, Object>>[];
    for (final m in messages) {
      final images = (m['images'] as List?)?.cast<String>() ?? const [];
      final text = ((m['content'] as String?) ?? '')
          .replaceAll(TextEngine.mediaMarker, '')
          .trim();
      // Tool traffic in the OpenAI shape: calls on assistant turns, results
      // as `tool` turns referencing the call id.
      if (m['tool_calls'] is List) {
        out.add({
          'role': 'assistant',
          'content': text,
          'tool_calls': [
            for (final c in m['tool_calls'] as List)
              if (c is Map)
                {
                  'id': c['id'] ?? '',
                  'type': 'function',
                  'function': {
                    'name': c['name'] ?? '',
                    'arguments': c['arguments'] is String
                        ? c['arguments']
                        : jsonEncode(c['arguments'] ?? const {}),
                  },
                },
          ],
        });
        continue;
      }
      if (m['role'] == 'tool') {
        out.add({
          'role': 'tool',
          'tool_call_id': m['tool_call_id'] ?? '',
          'content': text,
        });
        continue;
      }
      if (images.isEmpty) {
        out.add({'role': m['role']!, 'content': text});
        continue;
      }
      final parts = <Map<String, Object>>[];
      for (final path in images) {
        final bytes = await File(path).readAsBytes();
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${_mediaType(path)};base64,${base64Encode(bytes)}',
          },
        });
      }
      if (text.isNotEmpty) parts.add({'type': 'text', 'text': text});
      out.add({'role': m['role']!, 'content': parts});
    }
    return out;
  }

  static Map<String, dynamic> _argsOf(Object? arguments) {
    if (arguments is Map) return Map<String, dynamic>.from(arguments);
    if (arguments is String) {
      try {
        final v = jsonDecode(arguments);
        if (v is Map) return Map<String, dynamic>.from(v);
      } catch (_) {}
    }
    return const {};
  }

  /// Anthropic shape: system text goes in `system`; tool calls are
  /// `tool_use` blocks on assistant turns and results are `tool_result`
  /// blocks on the following user turn. Consecutive same-role turns are
  /// merged, which is what the API expects for several results at once.
  static Future<({String system, List<Map<String, Object>> messages})>
  anthropicMessages(List<Map<String, Object>> messages) async {
    final system = StringBuffer();
    final out = <Map<String, Object>>[];
    void add(String role, List<Map<String, Object>> blocks) {
      if (blocks.isEmpty) return;
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['content'] as List<Map<String, Object>>).addAll(blocks);
      } else {
        out.add({'role': role, 'content': blocks});
      }
    }

    for (final m in messages) {
      final text = ((m['content'] as String?) ?? '')
          .replaceAll(TextEngine.mediaMarker, '')
          .trim();
      final role = m['role'] as String? ?? 'user';
      if (role == 'system') {
        if (text.isNotEmpty) system.writeln(text);
        continue;
      }
      if (m['tool_calls'] is List) {
        add('assistant', [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          for (final c in m['tool_calls'] as List)
            if (c is Map)
              {
                'type': 'tool_use',
                'id': '${c['id'] ?? ''}',
                'name': '${c['name'] ?? ''}',
                'input': _argsOf(c['arguments']),
              },
        ]);
        continue;
      }
      if (role == 'tool') {
        add('user', [
          {
            'type': 'tool_result',
            'tool_use_id': '${m['tool_call_id'] ?? ''}',
            'content': text,
          },
        ]);
        continue;
      }
      final blocks = <Map<String, Object>>[];
      for (final path in (m['images'] as List?)?.cast<String>() ?? const []) {
        blocks.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': _mediaType(path),
            'data': base64Encode(await File(path).readAsBytes()),
          },
        });
      }
      if (text.isNotEmpty || blocks.isEmpty) {
        blocks.add({'type': 'text', 'text': text.isEmpty ? '…' : text});
      }
      add(role == 'assistant' ? 'assistant' : 'user', blocks);
    }
    return (system: system.toString().trim(), messages: out);
  }

  /// Gemini shape: `contents` with `user`/`model` roles, function calls as
  /// `functionCall` parts and results as `functionResponse` parts.
  Future<({String system, List<Map<String, Object>> contents})> geminiContents(
    List<Map<String, Object>> messages,
  ) async {
    final system = StringBuffer();
    final out = <Map<String, Object>>[];
    // Results need the function name; the call that produced each id is
    // earlier in the same list.
    final names = <String, String>{};
    void add(String role, List<Map<String, Object>> parts) {
      if (parts.isEmpty) return;
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['parts'] as List<Map<String, Object>>).addAll(parts);
      } else {
        out.add({'role': role, 'parts': parts});
      }
    }

    for (final m in messages) {
      final text = ((m['content'] as String?) ?? '')
          .replaceAll(TextEngine.mediaMarker, '')
          .trim();
      final role = m['role'] as String? ?? 'user';
      if (role == 'system') {
        if (text.isNotEmpty) system.writeln(text);
        continue;
      }
      if (m['tool_calls'] is List) {
        final parts = <Map<String, Object>>[
          if (text.isNotEmpty) {'text': text},
        ];
        for (final c in m['tool_calls'] as List) {
          if (c is! Map) continue;
          final id = '${c['id'] ?? ''}';
          final name = '${c['name'] ?? ''}';
          names[id] = name;
          parts.add({
            'functionCall': {'name': name, 'args': _argsOf(c['arguments'])},
            // Without the signature the model produced, Gemini 3 rejects
            // the history; the documented bypass keeps older turns usable.
            'thoughtSignature':
                _geminiSignatures[id] ?? 'skip_thought_signature_validator',
          });
        }
        add('model', parts);
        continue;
      }
      if (role == 'tool') {
        final id = '${m['tool_call_id'] ?? ''}';
        add('user', [
          {
            'functionResponse': {
              'name': '${m['name'] ?? names[id] ?? ''}',
              'response': {'result': text},
            },
          },
        ]);
        continue;
      }
      final parts = <Map<String, Object>>[];
      for (final path in (m['images'] as List?)?.cast<String>() ?? const []) {
        parts.add({
          'inlineData': {
            'mimeType': _mediaType(path),
            'data': base64Encode(await File(path).readAsBytes()),
          },
        });
      }
      if (text.isNotEmpty || parts.isEmpty) {
        parts.add({'text': text.isEmpty ? '…' : text});
      }
      add(role == 'assistant' ? 'model' : 'user', parts);
    }
    return (system: system.toString().trim(), contents: out);
  }

  /// Anthropic and Gemini no longer accept an assistant prefill, so a
  /// resumed answer becomes an instruction to continue it.
  static Map<String, Object> _continueTurn(String prefix) => {
    'role': 'user',
    'content':
        'Continue the following answer exactly where it stops, without repeating any of it:\n\n$prefix',
  };

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) {
    final base = settings.remoteUri;
    final profile = settings.activeRemoteProfile;
    if (base == null || profile == null) {
      return Stream.error(const InferenceException('Set a server URL.'));
    }
    final provider = profile.provider;
    final cancel = CancelToken();
    _cancel = cancel;
    final controller = StreamController<String>(onCancel: cancel.cancel);
    final started = DateTime.now();
    DateTime? first, last;
    var tokens = 0;
    int? promptTokens, completionTokens;
    var inThink = false, contentSeen = false;
    // Streamed tool calls arrive as fragments keyed by index.
    final calls = <int, Map<String, String>>{};
    String? finish;
    metrics = {
      'backend': 'Remote · ${provider.name} · ${base.host}',
      'remote': true,
      'provider': provider.id,
      'supportsThinking': true,
      'supportsTools': true,
      'contextSize': contextFor(settings),
    };
    void done() {
      final seconds = first != null && last != null && tokens > 1
          ? last!.difference(first!).inMicroseconds / 1e6
          : 0.0;
      metrics = {
        ...metrics,
        'tokens': completionTokens ?? tokens,
        'promptTokens': promptTokens,
        'firstTokenMs': first?.difference(started).inMilliseconds ?? 0,
        'tokensPerSecond': seconds > 0
            ? ((completionTokens ?? tokens) - 1) / seconds
            : 0,
        'contextUsed': (promptTokens ?? 0) + (completionTokens ?? tokens),
        'finishReason': switch (finish) {
          'stop' || 'end_turn' || 'STOP' || 'stop_sequence' => 'eog',
          'length' || 'max_tokens' || 'MAX_TOKENS' => 'length',
          'tool_calls' || 'tool_use' => 'tool_calls',
          _ => finish ?? '',
        },
        'toolCalls': [
          for (final i in calls.keys.toList()..sort())
            {
              'id': calls[i]!['id'] ?? '',
              'name': calls[i]!['name'] ?? '',
              'arguments': calls[i]!['arguments'] ?? '{}',
            },
        ],
      };
    }

    void emitThink(String reasoning) {
      if (reasoning.isEmpty || contentSeen) return;
      if (!inThink) {
        controller.add('<think>');
        inThink = true;
      }
      controller.add(reasoning);
    }

    void emitContent(String content) {
      if (content.isEmpty) return;
      if (inThink) {
        controller.add('</think>');
        inThink = false;
      }
      contentSeen = true;
      controller.add(content);
    }

    void tick() {
      tokens++;
      last = DateTime.now();
      first ??= last;
    }

    Future<void> run() async {
      try {
        await usage.charge(
          profile.id,
          profile.model,
          profile.limit,
          label:
              '${profile.model.trim().isEmpty ? 'the default model' : profile.model.trim()} on ${profile.label}',
        );
        final Uri uri;
        final Map<String, Object?> body;
        switch (provider.protocol) {
          case RemoteProtocol.openai:
            uri = provider.endpoint(base, 'chat/completions');
            body = await _openAiBody(
              messages,
              settings,
              assistantPrefix,
              tools,
              toolChoice,
            );
          case RemoteProtocol.anthropic:
            uri = provider.endpoint(base, 'messages');
            body = await _anthropicBody(
              messages,
              settings,
              assistantPrefix,
              tools,
            );
          case RemoteProtocol.gemini:
            final model = settings.remoteModel.trim().isEmpty
                ? 'gemini-3.6-flash'
                : settings.remoteModel.trim();
            uri = provider
                .endpoint(base, 'models/$model:streamGenerateContent')
                .replace(queryParameters: {'alt': 'sse'});
            body = await _geminiBody(
              messages,
              settings,
              assistantPrefix,
              tools,
              toolChoice,
            );
        }
        Future<Response<ResponseBody>> post(Map<String, Object?> payload) =>
            _dio.postUri<ResponseBody>(
              uri,
              data: jsonEncode(payload),
              cancelToken: cancel,
              options: Options(
                headers: _headers(settings),
                responseType: ResponseType.stream,
                receiveTimeout: Duration(
                  seconds: settings.remoteIdleTimeoutSeconds,
                ),
                validateStatus: (s) => s != null && s < 400,
              ),
            );
        Response<ResponseBody> res;
        var refusals = 0;
        var busy = 0;
        while (true) {
          try {
            res = await post(body);
            break;
          } on DioException catch (e) {
            final status = e.response?.statusCode;
            await _withBody(e);
            final detail = _errorMessage(e.response?.data);
            if (_terminalQuota.hasMatch(detail)) rethrow;
            // A busy or rate-limited provider (Gemini's free tier allows a
            // few requests a minute, and a searching turn sends one per
            // round): wait as asked, at most twice, then say so (audit
            // 2026-10-20: Gemini turns failed "most of the time").
            final wait = retryDelay(status, e.response?.headers, busy);
            if (wait != null && !cancel.isCancelled) {
              busy++;
              await Future<void>.delayed(wait);
              if (cancel.isCancelled) rethrow;
              continue;
            }
            // A model that refuses an optional field or value (a thinking
            // level, an effort, a sampler the API does not know) says so
            // with a 400 or 422; step down, remember it for the session,
            // send again.
            if ((status != 400 && status != 422) || ++refusals > 4) rethrow;
            final error = '${e.response?.data ?? ''}';
            final changed = switch (provider.protocol) {
              RemoteProtocol.openai => _openAiRefused(body, error, settings),
              RemoteProtocol.anthropic => _anthropicRefused(
                body,
                error,
                settings,
              ),
              RemoteProtocol.gemini => _geminiRefused(body, error, settings),
            };
            if (!changed) rethrow;
          }
        }
        // Anthropic block index → kind, so deltas know where they belong.
        final blockKinds = <int, String>{};
        final blockSlots = <int, int>{};
        var pending = '';
        await for (final text in res.data!.stream.cast<List<int>>().transform(
          const Utf8Decoder(allowMalformed: true),
        )) {
          // Utf8Decoder is stateful across transport chunks, so a multibyte
          // character split by TCP is not replaced with U+FFFD.
          pending += text;
          while (true) {
            final nl = pending.indexOf('\n');
            if (nl < 0) break;
            final line = pending.substring(0, nl).trim();
            pending = pending.substring(nl + 1);
            if (!line.startsWith('data:')) continue;
            final payload = line.substring(5).trim();
            if (payload == '[DONE]') continue;
            final Map<String, dynamic> json;
            try {
              json = jsonDecode(payload) as Map<String, dynamic>;
            } catch (_) {
              continue;
            }
            switch (provider.protocol) {
              case RemoteProtocol.openai:
                final u = json['usage'];
                if (u is Map) {
                  promptTokens = (u['prompt_tokens'] as num?)?.toInt();
                  completionTokens = (u['completion_tokens'] as num?)?.toInt();
                }
                final choices = json['choices'];
                if (choices is! List || choices.isEmpty) continue;
                final choice = choices.first as Map;
                if (choice['finish_reason'] is String) {
                  finish = choice['finish_reason'] as String;
                }
                final delta = choice['delta'];
                if (delta is! Map) continue;
                if (delta['tool_calls'] is List) {
                  for (final c in delta['tool_calls'] as List) {
                    if (c is! Map) continue;
                    final index = (c['index'] as num?)?.toInt() ?? calls.length;
                    final slot = calls.putIfAbsent(index, () => {});
                    if (c['id'] is String && (c['id'] as String).isNotEmpty) {
                      slot['id'] = c['id'] as String;
                    }
                    final fn = c['function'];
                    if (fn is Map) {
                      if (fn['name'] is String &&
                          (fn['name'] as String).isNotEmpty) {
                        slot['name'] =
                            (slot['name'] ?? '') + (fn['name'] as String);
                      }
                      if (fn['arguments'] is String) {
                        slot['arguments'] =
                            (slot['arguments'] ?? '') +
                            (fn['arguments'] as String);
                      }
                    }
                  }
                }
                final reasoning =
                    (delta['reasoning_content'] ?? delta['reasoning'])
                        as String?;
                final content = delta['content'] as String?;
                if (reasoning != null) emitThink(reasoning);
                if (content != null) emitContent(content);
                if ((reasoning?.isNotEmpty ?? false) ||
                    (content?.isNotEmpty ?? false)) {
                  tick();
                }
              case RemoteProtocol.anthropic:
                switch (json['type']) {
                  case 'error':
                    final err = json['error'];
                    throw InferenceException(
                      'Anthropic: ${err is Map ? err['message'] ?? err : err}',
                    );
                  case 'message_start':
                    final u = (json['message'] as Map?)?['usage'];
                    if (u is Map) {
                      promptTokens = (u['input_tokens'] as num?)?.toInt();
                    }
                  case 'content_block_start':
                    final index = (json['index'] as num?)?.toInt() ?? 0;
                    final block = json['content_block'];
                    if (block is! Map) continue;
                    final kind = '${block['type']}';
                    blockKinds[index] = kind;
                    if (kind == 'tool_use') {
                      final slot = calls.length;
                      blockSlots[index] = slot;
                      calls[slot] = {
                        'id': '${block['id'] ?? ''}',
                        'name': '${block['name'] ?? ''}',
                        'arguments': '',
                      };
                    }
                  case 'content_block_delta':
                    final index = (json['index'] as num?)?.toInt() ?? 0;
                    final delta = json['delta'];
                    if (delta is! Map) continue;
                    switch (delta['type']) {
                      case 'text_delta':
                        emitContent('${delta['text'] ?? ''}');
                        tick();
                      case 'thinking_delta':
                        emitThink('${delta['thinking'] ?? ''}');
                        tick();
                      case 'input_json_delta':
                        final slot = blockSlots[index];
                        if (slot != null) {
                          calls[slot]!['arguments'] =
                              '${calls[slot]!['arguments'] ?? ''}${delta['partial_json'] ?? ''}';
                        }
                    }
                  case 'message_delta':
                    final delta = json['delta'];
                    if (delta is Map && delta['stop_reason'] is String) {
                      finish = delta['stop_reason'] as String;
                      if (finish == 'refusal') {
                        emitContent(
                          '\n\n[The provider declined to answer this request.]',
                        );
                      }
                    }
                    final u = json['usage'];
                    if (u is Map) {
                      completionTokens = (u['output_tokens'] as num?)?.toInt();
                    }
                }
              case RemoteProtocol.gemini:
                if (json['error'] is Map) {
                  throw InferenceException(
                    'Gemini: ${(json['error'] as Map)['message'] ?? json['error']}',
                  );
                }
                final u = json['usageMetadata'];
                if (u is Map) {
                  promptTokens = (u['promptTokenCount'] as num?)?.toInt();
                  final answer = (u['candidatesTokenCount'] as num?)?.toInt();
                  final thoughts = (u['thoughtsTokenCount'] as num?)?.toInt();
                  if (answer != null) {
                    completionTokens = answer + (thoughts ?? 0);
                  }
                }
                final candidates = json['candidates'];
                if (candidates is! List || candidates.isEmpty) {
                  final feedback = json['promptFeedback'];
                  if (feedback is Map && feedback['blockReason'] != null) {
                    throw InferenceException(
                      'Gemini blocked the prompt (${feedback['blockReason']}).',
                    );
                  }
                  continue;
                }
                final candidate = candidates.first as Map;
                if (candidate['finishReason'] is String) {
                  finish = candidate['finishReason'] as String;
                }
                final parts = (candidate['content'] as Map?)?['parts'];
                if (parts is! List) continue;
                for (final part in parts) {
                  if (part is! Map) continue;
                  if (part['functionCall'] is Map) {
                    final fc = part['functionCall'] as Map;
                    final id =
                        'call_${calls.length}_${Random().nextInt(1 << 30).toRadixString(36)}';
                    calls[calls.length] = {
                      'id': id,
                      'name': '${fc['name'] ?? ''}',
                      'arguments': jsonEncode(fc['args'] ?? const {}),
                    };
                    if (part['thoughtSignature'] is String) {
                      _geminiSignatures[id] =
                          part['thoughtSignature'] as String;
                    }
                    finish = 'tool_calls';
                    continue;
                  }
                  final text = part['text'];
                  if (text is! String || text.isEmpty) continue;
                  if (part['thought'] == true) {
                    emitThink(text);
                  } else {
                    emitContent(text);
                  }
                  tick();
                }
            }
          }
        }
        if (inThink) controller.add('</think>');
        if (calls.isNotEmpty &&
            finish != 'tool_calls' &&
            finish != 'tool_use') {
          finish = 'tool_calls';
        }
        done();
      } catch (e) {
        done();
        if (!cancel.isCancelled) {
          controller.addError(
            e is InferenceException ? e : _explain(await _withBody(e), base),
          );
        }
      } finally {
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  /// How long to wait before sending again after a [status] that says the
  /// provider is busy (429, 500, 502, 503, 504), on the [tried]th retry;
  /// null to give up. A `Retry-After` of more than 30 s is not waited for.
  static Duration? retryDelay(int? status, Headers? headers, int tried) {
    if (tried >= 2) return null;
    if (status != 429 && (status == null || status < 500 || status > 504)) {
      return null;
    }
    final after = int.tryParse(headers?.value('retry-after')?.trim() ?? '');
    if (after != null) {
      return after <= 30 ? Duration(seconds: max(1, after)) : null;
    }
    return status == 429
        ? Duration(seconds: tried == 0 ? 5 : 12)
        : Duration(seconds: tried == 0 ? 2 : 5);
  }

  /// A streamed request's error body arrives as a stream; the provider's
  /// message (Gemini's "Developer instruction is not enabled…", a 500's
  /// explanation) is read so the notice can show it.
  static Future<Object> _withBody(Object e) async {
    if (e is! DioException || e.response?.data is! ResponseBody) return e;
    try {
      final body = e.response!.data as ResponseBody;
      final text = await body.stream
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 5));
      e.response!.data = text;
    } catch (_) {}
    return e;
  }

  /// Where OpenAI-style refusals are remembered: the connection and model.
  static String _openAiKey(InferenceSettings settings) =>
      '${settings.activeRemoteProfile?.id ?? ''}|'
      '${settings.remoteModel.trim().toLowerCase()}';

  /// The Think pill as `reasoning_effort` (review 2026-09-28): Off
  /// asks for none, which servers without it refuse with the values they
  /// take (see [_openAiRefused]).
  static String _openAiEffortOf(ThinkingLevel level) => switch (level) {
    ThinkingLevel.off => 'none',
    ThinkingLevel.low => 'low',
    ThinkingLevel.medium => 'medium',
    ThinkingLevel.high => 'high',
  };

  /// Effort values to try, best first, when [wanted] is refused.
  static const _effortLadder = {
    'none': ['minimal', 'low'],
    'minimal': ['low'],
    'low': ['medium', 'high'],
    'medium': ['high', 'low'],
    'high': ['medium'],
  };

  /// Optional fields an OpenAI-style server may refuse by name. OpenAI
  /// itself rejects the llama.cpp samplers and `chat_template_kwargs`, and
  /// its reasoning models reject `temperature` and `top_p`.
  static const _openAiOptional = [
    'reasoning_effort',
    'chat_template_kwargs',
    'top_k',
    'min_p',
    'repeat_penalty',
    'presence_penalty',
    'frequency_penalty',
    'seed',
    'stream_options',
    'temperature',
    'top_p',
  ];

  /// Learns from an OpenAI-style 400/422: fields the error names are
  /// dropped, a refused effort value is replaced by the nearest value the
  /// error lists (or dropped), `max_tokens` becomes `max_completion_tokens`
  /// when asked. An error that names nothing known drops the effort, the
  /// one field most servers never had to accept. Returns whether [body]
  /// changed.
  bool _openAiRefused(
    Map<String, Object?> body,
    String error,
    InferenceSettings settings,
  ) {
    final key = _openAiKey(settings);
    final text = error.toLowerCase().replaceAll('_', '');
    bool names(String field) =>
        RegExp('\\b${field.replaceAll('_', '')}\\b').hasMatch(text);
    final dropped = _openAiDropped.putIfAbsent(key, () => {});
    var changed = false;
    if (body.containsKey('max_tokens') &&
        names('max_tokens') &&
        text.contains('maxcompletiontokens')) {
      body['max_completion_tokens'] = body.remove('max_tokens');
      dropped.add('max_tokens');
      changed = true;
    }
    final effort = body['reasoning_effort'];
    var effortHandled = false;
    if (effort is String && names('reasoning_effort')) {
      effortHandled = true;
      final listed = [
        for (final v in _effortLadder[effort] ?? const <String>[])
          if (RegExp('\\b$v\\b').hasMatch(text)) v,
      ];
      if (listed.isNotEmpty) {
        final wanted = _openAiEffortOf(settings.thinkingLevel);
        _openAiEffort.putIfAbsent(key, () => {})[wanted] = listed.first;
        body['reasoning_effort'] = listed.first;
      } else {
        body.remove('reasoning_effort');
        dropped.add('reasoning_effort');
      }
      changed = true;
    }
    for (final field in _openAiOptional) {
      if (field == 'reasoning_effort' && effortHandled) continue;
      if (body.containsKey(field) && names(field)) {
        body.remove(field);
        dropped.add(field);
        changed = true;
      }
    }
    if (!changed &&
        body.containsKey('tools') &&
        RegExp(r'\btools?\b|function').hasMatch(text)) {
      // A model without tool support (Ollama: "does not support tools").
      _noTools.add(_windowKey(settings));
      body
        ..remove('tools')
        ..remove('tool_choice');
      return true;
    }
    if (!changed && effort is String) {
      body.remove('reasoning_effort');
      dropped.add('reasoning_effort');
      changed = true;
    }
    return changed;
  }

  Future<Map<String, Object?>> _openAiBody(
    List<Map<String, Object>> messages,
    InferenceSettings settings,
    String assistantPrefix,
    List<ToolSpec> tools,
    String toolChoice,
  ) async {
    final key = _openAiKey(settings);
    final dropped = _openAiDropped[key] ?? const <String>{};
    final wanted = _openAiEffortOf(settings.thinkingLevel);
    return {
      ..._openAiFields(
        await openAiMessages(messages),
        settings,
        assistantPrefix,
        tools,
        toolChoice,
      ),
      'reasoning_effort': _openAiEffort[key]?[wanted] ?? wanted,
      if (dropped.contains('max_tokens') && !settings.serverSampling)
        'max_completion_tokens': settings.outputCeiling,
    }..removeWhere((k, v) => v == null || dropped.contains(k));
  }

  Map<String, Object?> _openAiFields(
    List<Map<String, Object>> converted,
    InferenceSettings settings,
    String assistantPrefix,
    List<ToolSpec> tools,
    String toolChoice,
  ) => {
    // The server has its own template; a resumed answer becomes an
    // assistant turn it is asked to continue.
    'model': settings.remoteModel.trim().isEmpty
        ? null
        : settings.remoteModel.trim(),
    'messages': [
      ...converted,
      if (assistantPrefix.isNotEmpty)
        {'role': 'assistant', 'content': assistantPrefix},
    ],
    'stream': true,
    'stream_options': {'include_usage': true},
    // The server's own settings: its loaded model config decides sampling
    // and length (LM Studio, llama-server, a hosted model's defaults).
    if (!settings.serverSampling) ...{
      'temperature': settings.temperature,
      'top_p': settings.topP,
      'max_tokens': settings.outputCeiling,
      if (settings.repetitionPenalty > 1)
        'repeat_penalty': settings.repetitionPenalty,
      if (settings.topK > 0) 'top_k': settings.topK,
      if (settings.minP > 0) 'min_p': settings.minP,
      if (settings.presencePenalty != 0)
        'presence_penalty': settings.presencePenalty,
      if (settings.frequencyPenalty != 0)
        'frequency_penalty': settings.frequencyPenalty,
    },
    if (settings.seed > 0) 'seed': settings.seed,
    if (settings.stopSequences.isNotEmpty) 'stop': settings.stopSequences,
    // LM Studio rejects `json_object` (only `json_schema` or `text`); a
    // schema for any object means the same everywhere.
    if (settings.responseFormat == ResponseFormat.json)
      'response_format': {
        'type': 'json_schema',
        'json_schema': {
          'name': 'answer',
          'schema': {'type': 'object'},
        },
      },
    if (settings.responseFormat == ResponseFormat.jsonSchema &&
        settings.jsonSchema.trim().isNotEmpty)
      'response_format': {
        'type': 'json_schema',
        'json_schema': {
          'name': 'answer',
          'schema': _schemaOrNull(settings.jsonSchema) ?? const {},
        },
      },
    if (settings.responseFormat == ResponseFormat.gbnf &&
        settings.grammar.trim().isNotEmpty)
      'grammar': settings.grammar,
    if (tools.isNotEmpty) 'tools': [for (final t in tools) t.toOpenAi()],
    if (tools.isNotEmpty)
      'tool_choice': toolChoice == 'required' ? 'required' : 'auto',
    // llama-server / LM Studio honour this for Qwen3-style models.
    if (!settings.thinkingModeEnabled)
      'chat_template_kwargs': {'enable_thinking': false},
  };

  /// The Think pill as Claude's `output_config.effort`: Low and Medium
  /// lower it; High is the API's default, and Off sends no thinking.
  static String? _anthropicEffortOf(ThinkingLevel level) => switch (level) {
    ThinkingLevel.low => 'low',
    ThinkingLevel.medium => 'medium',
    _ => null,
  };

  /// The fixed budget for models without adaptive thinking (at least the
  /// API's minimum of 1024 tokens).
  static int _anthropicBudget(InferenceSettings s) => max(
    1024,
    s.thinkingBudgetTokens > 0
        ? s.thinkingBudgetTokens
        : ThinkingLevel.high.budget,
  );

  /// Learns from a Claude 400: a model without the effort setting loses
  /// it, one without adaptive thinking gets a fixed budget. Returns whether
  /// [body] changed.
  bool _anthropicRefused(
    Map<String, Object?> body,
    String error,
    InferenceSettings settings,
  ) {
    final text = error.toLowerCase();
    final key = '${body['model']}'.toLowerCase();
    // "max_tokens: 32000 > 8192, which is the maximum allowed": the
    // model's own ceiling, kept for the session.
    final most = RegExp(r'max_tokens:\s*\d+\s*>\s*(\d+)').firstMatch(text);
    if (most != null && body['max_tokens'] is int) {
      final allowed = int.parse(most.group(1)!);
      if (allowed > 0 && allowed < (body['max_tokens'] as int)) {
        _anthropicCeiling[key] = allowed;
        body['max_tokens'] = allowed;
        return true;
      }
    }
    final config = body['output_config'];
    if (config is Map &&
        config.containsKey('effort') &&
        text.contains('effort')) {
      _anthropicNoEffort.add(key);
      config.remove('effort');
      if (config.isEmpty) body.remove('output_config');
      return true;
    }
    final thinking = body['thinking'];
    if (thinking is Map &&
        thinking['type'] == 'adaptive' &&
        text.contains('adaptive')) {
      _anthropicNoAdaptive.add(key);
      final budget = _anthropicBudget(settings);
      body['thinking'] = {'type': 'enabled', 'budget_tokens': budget};
      body['max_tokens'] = max(
        settings.outputCeiling,
        settings.maxTokens + budget,
      );
      return true;
    }
    return false;
  }

  /// Messages API body. Sampling knobs are omitted: the current Claude
  /// models reject `temperature`/`top_p`/`top_k`. Thinking mode maps to
  /// adaptive thinking with a readable summary and the level to the effort
  /// setting; off leaves the model's default (its reasoning is then simply
  /// not shown). Forced tool choice stays `auto` because the newest models
  /// reject `any`.
  Future<Map<String, Object?>> _anthropicBody(
    List<Map<String, Object>> messages,
    InferenceSettings settings,
    String assistantPrefix,
    List<ToolSpec> tools,
  ) async {
    final converted = await anthropicMessages([
      ...messages,
      if (assistantPrefix.isNotEmpty) _continueTurn(assistantPrefix),
    ]);
    final schema = settings.responseFormat == ResponseFormat.jsonSchema
        ? _schemaOrNull(settings.jsonSchema)
        : null;
    final model = settings.remoteModel.trim().isEmpty
        ? 'claude-opus-5'
        : settings.remoteModel.trim();
    final key = model.toLowerCase();
    final fixed =
        settings.thinkingModeEnabled && _anthropicNoAdaptive.contains(key);
    final effort = _anthropicNoEffort.contains(key)
        ? null
        : _anthropicEffortOf(settings.thinkingLevel);
    final ceiling = settings.serverSampling
        ? _anthropicCeiling[key] ?? anthropicServerCeiling
        : settings.outputCeiling;
    return {
      'model': model,
      'max_tokens': fixed
          ? max(ceiling, settings.maxTokens + _anthropicBudget(settings))
          : ceiling,
      'stream': true,
      if (converted.system.isNotEmpty) 'system': converted.system,
      'messages': converted.messages,
      if (settings.stopSequences.isNotEmpty)
        'stop_sequences': settings.stopSequences,
      if (settings.thinkingModeEnabled)
        'thinking': fixed
            ? {'type': 'enabled', 'budget_tokens': _anthropicBudget(settings)}
            : {'type': 'adaptive', 'display': 'summarized'},
      if (schema != null || effort != null)
        'output_config': {
          if (schema != null)
            'format': {'type': 'json_schema', 'schema': schema},
          'effort': ?effort,
        },
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parameters,
            },
        ],
      if (tools.isNotEmpty) 'tool_choice': {'type': 'auto'},
    };
  }

  /// Gemma models served by the Gemini API accept neither a developer
  /// instruction, nor function calling or JSON schemas; the request is
  /// reduced to what they take (system text folded into the first user
  /// turn). Thinking config is still sent — Gemma 4 thinks by default and
  /// took ~10 s of reasoning per weather answer without a budget of 0 —
  /// and dropped after the first 400 that names it.
  static bool geminiBasic(String model) =>
      model.trim().toLowerCase().startsWith('gemma');

  /// Gemini body. Function declarations use `parametersJsonSchema`, which
  /// takes the same JSON Schema as everyone else.
  Future<Map<String, Object?>> _geminiBody(
    List<Map<String, Object>> messages,
    InferenceSettings settings,
    String assistantPrefix,
    List<ToolSpec> tools,
    String toolChoice,
  ) async {
    final basic = geminiBasic(settings.remoteModel);
    final penalties = !_geminiNoPenalty.contains(
      settings.remoteModel.trim().toLowerCase(),
    );
    final converted = await geminiContents([
      ...messages,
      if (assistantPrefix.isNotEmpty) _continueTurn(assistantPrefix),
    ]);
    if (basic && converted.system.isNotEmpty) {
      final first = converted.contents.firstOrNull;
      final parts = first?['parts'] as List<Map<String, Object>>?;
      if (first != null && first['role'] == 'user' && parts != null) {
        final text = parts.lastWhere(
          (p) => p.containsKey('text'),
          orElse: () => {'text': ''},
        );
        parts.remove(text);
        parts.add({'text': '${converted.system}\n\n${text['text']}'.trim()});
      }
    }
    if (basic) tools = const [];
    final schema =
        settings.responseFormat == ResponseFormat.jsonSchema && !basic
        ? _schemaOrNull(settings.jsonSchema)
        : null;
    return {
      'contents': converted.contents,
      if (converted.system.isNotEmpty && !basic)
        'systemInstruction': {
          'parts': [
            {'text': converted.system},
          ],
        },
      'generationConfig': {
        // The server's own settings: the model's default temperature,
        // sampling and output length.
        if (!settings.serverSampling) ...{
          'temperature': settings.temperature,
          'topP': settings.topP,
          if (settings.topK > 0) 'topK': settings.topK,
          'maxOutputTokens': settings.outputCeiling,
        },
        if (settings.stopSequences.isNotEmpty)
          'stopSequences': settings.stopSequences.take(5).toList(),
        if (settings.seed > 0) 'seed': settings.seed,
        if (settings.presencePenalty != 0 &&
            !basic &&
            penalties &&
            !settings.serverSampling)
          'presencePenalty': settings.presencePenalty,
        if (settings.frequencyPenalty != 0 &&
            !basic &&
            penalties &&
            !settings.serverSampling)
          'frequencyPenalty': settings.frequencyPenalty,
        if ((settings.responseFormat == ResponseFormat.json && !basic) ||
            schema != null)
          'responseMimeType': 'application/json',
        'responseJsonSchema': ?schema,
        if (!_geminiNoThinkingConfig.contains(
          settings.remoteModel.trim().toLowerCase(),
        ))
          'thinkingConfig': ?_geminiThinking(settings),
      },
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final t in tools)
                {
                  'name': t.name,
                  'description': t.description,
                  'parametersJsonSchema': t.parameters,
                },
            ],
          },
        ],
      if (tools.isNotEmpty)
        'toolConfig': {
          'functionCallingConfig': {
            'mode': toolChoice == 'required' ? 'ANY' : 'AUTO',
          },
        },
    };
  }

  /// Gemini thinks by default; the Think pill maps to the knob each family
  /// has. Gemini 3 takes a level (Off is the lowest: "minimal" on Flash,
  /// "low" on Pro). 2.5 and Gemma take a budget: Off is 0, except on 2.5
  /// Pro, which cannot turn thinking off and gets its minimum of 128; an
  /// unlimited budget is left to the model. So a short answer is not
  /// preceded by a long silent reasoning pass.
  Map<String, Object>? _geminiThinking(InferenceSettings settings) {
    final model = settings.remoteModel.trim().toLowerCase();
    final level = settings.thinkingLevel;
    final on = level != ThinkingLevel.off;
    if (model.startsWith('gemini-3')) {
      final wanted = switch (level) {
        ThinkingLevel.off => model.contains('flash') ? 'minimal' : 'low',
        ThinkingLevel.low => 'low',
        ThinkingLevel.medium => 'medium',
        ThinkingLevel.high => 'high',
      };
      final refused = _geminiNoLevel[model] ?? const <String>{};
      String? chosen = wanted;
      while (chosen != null && refused.contains(chosen)) {
        chosen = _geminiNextLevel[chosen];
      }
      return {if (on) 'includeThoughts': true, 'thinkingLevel': ?chosen};
    }
    if (model.contains('2.5') || model.startsWith('gemma')) {
      final budget = !on
          ? (model.contains('2.5-pro') ? 128 : 0)
          : settings.thinkingBudgetTokens > 0
          ? settings.thinkingBudgetTokens.clamp(
              model.contains('lite') ? 512 : 128,
              24576,
            )
          : null;
      return {if (on) 'includeThoughts': true, 'thinkingBudget': ?budget};
    }
    return on ? {'includeThoughts': true} : null;
  }

  /// The level to ask for when a Gemini model refuses one.
  static const _geminiNextLevel = {'minimal': 'low', 'medium': 'high'};

  /// Learns from a Gemini 400 that names thinking: a refused level steps
  /// to the next one, anything else drops the thinking config. Returns
  /// whether [body] changed.
  bool _geminiRefused(
    Map<String, Object?> body,
    String error,
    InferenceSettings settings,
  ) {
    final config = body['generationConfig'];
    // A model without penalties: they go, for the rest of the session.
    if (config is Map &&
        error.toLowerCase().contains('penalty') &&
        (config.containsKey('presencePenalty') ||
            config.containsKey('frequencyPenalty'))) {
      _geminiNoPenalty.add(settings.remoteModel.trim().toLowerCase());
      config
        ..remove('presencePenalty')
        ..remove('frequencyPenalty');
      return true;
    }
    if (config is! Map ||
        !config.containsKey('thinkingConfig') ||
        !error.toLowerCase().contains('thinking')) {
      return false;
    }
    final model = settings.remoteModel.trim().toLowerCase();
    final thinking = config['thinkingConfig'];
    final level = thinking is Map ? thinking['thinkingLevel'] : null;
    final next = _geminiNextLevel[level];
    if (thinking is Map && level is String && next != null) {
      _geminiNoLevel.putIfAbsent(model, () => {}).add(level);
      thinking['thinkingLevel'] = next;
    } else {
      _geminiNoThinkingConfig.add(model);
      config.remove('thinkingConfig');
    }
    return true;
  }

  static Map<String, dynamic>? _schemaOrNull(String text) {
    try {
      final v = jsonDecode(text);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void cancel() => _cancel?.cancel('Stopped by user');

  void dispose() {
    cancel();
    _dio.close(force: true);
  }
}

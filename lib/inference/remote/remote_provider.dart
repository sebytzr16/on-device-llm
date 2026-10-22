import 'dart:convert';

/// Wire protocol a remote provider speaks.
enum RemoteProtocol {
  /// `POST {root}/chat/completions` — LM Studio, Ollama, llama-server, vLLM
  /// and every hosted API that copies OpenAI's shape.
  openai,

  /// Anthropic Messages API (`POST /v1/messages`).
  anthropic,

  /// Google Gemini API (`POST /v1beta/models/{model}:streamGenerateContent`).
  gemini,
}

/// How the API key travels.
enum RemoteAuth { bearer, anthropicKey, googleKey, azureKey }

/// A known server or hosted API: its protocol, default URL and where the key
/// goes. Self-hosted entries have no default URL (the phone cannot reach
/// `localhost`), only a hint with the usual port.
class RemoteProvider {
  final String id;
  final String name;
  final RemoteProtocol protocol;
  final RemoteAuth auth;

  /// Prefilled base URL for hosted APIs; empty for self-hosted servers.
  final String defaultBaseUrl;

  /// Example URL shown as a hint when [defaultBaseUrl] is empty.
  final String urlHint;

  /// Path segment the API version lives under, appended to the base URL when
  /// it is not already there (`/v1` for most, `/v1beta` for Gemini, `/api`
  /// for Open WebUI, none for Perplexity).
  final String versionPath;
  final bool selfHosted;

  /// The provider has a model-listing endpoint the picker can query.
  final bool listsModels;

  /// Where to create an API key; opened in the system browser on request.
  final String? keysUrl;
  final String? note;

  const RemoteProvider({
    required this.id,
    required this.name,
    this.protocol = RemoteProtocol.openai,
    this.auth = RemoteAuth.bearer,
    this.defaultBaseUrl = '',
    this.urlHint = '',
    this.versionPath = '/v1',
    this.selfHosted = false,
    this.listsModels = true,
    this.keysUrl,
    this.note,
  });

  /// Hosted APIs reject anonymous calls; a home server usually has no key.
  bool get requiresKey => !selfHosted;

  static const custom = RemoteProvider(
    id: 'custom',
    name: 'Custom (OpenAI-compatible)',
    urlHint: 'https://host:port',
    selfHosted: true,
    note: 'Any server that implements /v1/chat/completions.',
  );

  static const all = <RemoteProvider>[
    // Self-hosted servers — the original use case.
    RemoteProvider(
      id: 'lmstudio',
      name: 'LM Studio',
      urlHint: 'http://192.168.1.20:1234',
      selfHosted: true,
      note:
          'Enable the local server in LM Studio (Developer tab) and allow LAN access.',
    ),
    RemoteProvider(
      id: 'ollama',
      name: 'Ollama',
      urlHint: 'http://192.168.1.20:11434',
      selfHosted: true,
      note: 'Set OLLAMA_HOST=0.0.0.0 so the phone can reach it over the LAN.',
    ),
    RemoteProvider(
      id: 'llamacpp',
      name: 'llama-server (llama.cpp)',
      urlHint: 'http://192.168.1.20:8080',
      selfHosted: true,
      note: 'Start with --host 0.0.0.0; --api-key adds a bearer key.',
    ),
    RemoteProvider(
      id: 'vllm',
      name: 'vLLM',
      urlHint: 'http://192.168.1.20:8000',
      selfHosted: true,
    ),
    RemoteProvider(
      id: 'sglang',
      name: 'SGLang',
      urlHint: 'http://192.168.1.20:30000',
      selfHosted: true,
    ),
    RemoteProvider(
      id: 'jan',
      name: 'Jan',
      urlHint: 'http://192.168.1.20:1337',
      selfHosted: true,
    ),
    RemoteProvider(
      id: 'koboldcpp',
      name: 'KoboldCpp',
      urlHint: 'http://192.168.1.20:5001',
      selfHosted: true,
    ),
    RemoteProvider(
      id: 'textgenwebui',
      name: 'text-generation-webui',
      urlHint: 'http://192.168.1.20:5000',
      selfHosted: true,
      note: 'Start with --api --listen.',
    ),
    RemoteProvider(
      id: 'tabbyapi',
      name: 'TabbyAPI',
      urlHint: 'http://192.168.1.20:5000',
      selfHosted: true,
    ),
    RemoteProvider(
      id: 'localai',
      name: 'LocalAI',
      urlHint: 'http://192.168.1.20:8080',
      selfHosted: true,
    ),
    RemoteProvider(
      id: 'litellm',
      name: 'LiteLLM proxy',
      urlHint: 'http://192.168.1.20:4000',
      selfHosted: true,
      note:
          'A proxy in front of any provider; the key is the proxy\'s virtual key.',
    ),
    RemoteProvider(
      id: 'openwebui',
      name: 'Open WebUI',
      urlHint: 'http://192.168.1.20:3000',
      versionPath: '/api',
      selfHosted: true,
      note: 'Create an API key under Settings > Account in Open WebUI.',
    ),
    custom,
    // Hosted, OpenAI-compatible.
    RemoteProvider(
      id: 'openai',
      name: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com',
      keysUrl: 'https://platform.openai.com/api-keys',
    ),
    RemoteProvider(
      id: 'openrouter',
      name: 'OpenRouter',
      defaultBaseUrl: 'https://openrouter.ai/api',
      keysUrl: 'https://openrouter.ai/keys',
      note: 'One key for hundreds of models; model IDs look like vendor/model.',
    ),
    RemoteProvider(
      id: 'groq',
      name: 'Groq',
      defaultBaseUrl: 'https://api.groq.com/openai',
      keysUrl: 'https://console.groq.com/keys',
    ),
    RemoteProvider(
      id: 'mistral',
      name: 'Mistral',
      defaultBaseUrl: 'https://api.mistral.ai',
      keysUrl: 'https://console.mistral.ai/api-keys',
    ),
    RemoteProvider(
      id: 'deepseek',
      name: 'DeepSeek',
      defaultBaseUrl: 'https://api.deepseek.com',
      keysUrl: 'https://platform.deepseek.com/api_keys',
    ),
    RemoteProvider(
      id: 'together',
      name: 'Together AI',
      defaultBaseUrl: 'https://api.together.xyz',
      keysUrl: 'https://api.together.ai/settings/api-keys',
    ),
    RemoteProvider(
      id: 'xai',
      name: 'xAI (Grok)',
      defaultBaseUrl: 'https://api.x.ai',
      keysUrl: 'https://console.x.ai',
    ),
    RemoteProvider(
      id: 'fireworks',
      name: 'Fireworks AI',
      defaultBaseUrl: 'https://api.fireworks.ai/inference',
      keysUrl: 'https://fireworks.ai/account/api-keys',
    ),
    RemoteProvider(
      id: 'perplexity',
      name: 'Perplexity',
      defaultBaseUrl: 'https://api.perplexity.ai',
      versionPath: '',
      listsModels: false,
      keysUrl: 'https://www.perplexity.ai/settings/api',
      note: 'No model list endpoint: type the model ID (e.g. sonar-pro).',
    ),
    RemoteProvider(
      id: 'cerebras',
      name: 'Cerebras',
      defaultBaseUrl: 'https://api.cerebras.ai',
      keysUrl: 'https://cloud.cerebras.ai',
    ),
    RemoteProvider(
      id: 'sambanova',
      name: 'SambaNova',
      defaultBaseUrl: 'https://api.sambanova.ai',
      keysUrl: 'https://cloud.sambanova.ai/apis',
    ),
    RemoteProvider(
      id: 'huggingface',
      name: 'Hugging Face',
      defaultBaseUrl: 'https://router.huggingface.co',
      keysUrl: 'https://huggingface.co/settings/tokens',
      note:
          'Inference Providers router; use a token with inference permission.',
    ),
    RemoteProvider(
      id: 'nvidia',
      name: 'NVIDIA NIM',
      defaultBaseUrl: 'https://integrate.api.nvidia.com',
      keysUrl: 'https://build.nvidia.com',
    ),
    RemoteProvider(
      id: 'cohere',
      name: 'Cohere',
      defaultBaseUrl: 'https://api.cohere.ai/compatibility',
      keysUrl: 'https://dashboard.cohere.com/api-keys',
    ),
    RemoteProvider(
      id: 'moonshot',
      name: 'Moonshot (Kimi)',
      defaultBaseUrl: 'https://api.moonshot.ai',
      keysUrl: 'https://platform.moonshot.ai',
    ),
    RemoteProvider(
      id: 'dashscope',
      name: 'Alibaba Model Studio (Qwen)',
      defaultBaseUrl: 'https://dashscope-intl.aliyuncs.com/compatible-mode',
      keysUrl: 'https://modelstudio.console.alibabacloud.com',
    ),
    RemoteProvider(
      id: 'zhipu',
      name: 'Z.ai / Zhipu (GLM)',
      defaultBaseUrl: 'https://api.z.ai/api/paas/v4',
      versionPath: '/v4',
      keysUrl: 'https://z.ai/manage-apikey/apikey-list',
    ),
    RemoteProvider(
      id: 'azure',
      name: 'Azure OpenAI',
      auth: RemoteAuth.azureKey,
      defaultBaseUrl: 'https://YOUR-RESOURCE.openai.azure.com/openai',
      keysUrl: 'https://portal.azure.com',
      note:
          'Replace YOUR-RESOURCE with the resource name. Uses the v1 API; the model is the deployment name.',
    ),
    // Native protocols.
    RemoteProvider(
      id: 'anthropic',
      name: 'Anthropic (Claude)',
      protocol: RemoteProtocol.anthropic,
      auth: RemoteAuth.anthropicKey,
      defaultBaseUrl: 'https://api.anthropic.com',
      keysUrl: 'https://console.anthropic.com/settings/keys',
      note:
          'Native Messages API. Temperature and top-p are not sent (the current models reject them); thinking mode maps to adaptive thinking.',
    ),
    RemoteProvider(
      id: 'gemini',
      name: 'Google AI Studio (Gemini)',
      protocol: RemoteProtocol.gemini,
      auth: RemoteAuth.googleKey,
      defaultBaseUrl: 'https://generativelanguage.googleapis.com',
      versionPath: '/v1beta',
      keysUrl: 'https://aistudio.google.com/apikey',
      note:
          'Key from Google AI Studio. Gemini and Gemma models over the Gemini API, with thought summaries and function calling.',
    ),
  ];

  static RemoteProvider byId(String id) =>
      all.where((p) => p.id == id).firstOrNull ?? custom;

  static Iterable<RemoteProvider> get selfHostedOnes =>
      all.where((p) => p.selfHosted);
  static Iterable<RemoteProvider> get hostedOnes =>
      all.where((p) => !p.selfHosted);

  /// Best guess for a URL saved before providers existed.
  static RemoteProvider guess(Uri? uri) {
    if (uri == null) return custom;
    return switch (uri.port) {
      1234 => byId('lmstudio'),
      11434 => byId('ollama'),
      8080 => byId('llamacpp'),
      8000 => byId('vllm'),
      _ => custom,
    };
  }

  static final _versioned = RegExp(r'/v\d+[a-z]*$');

  /// The API root for this provider: the base URL with [versionPath] added
  /// unless the user already typed a versioned path. Accepts
  /// `http://host:1234`, `http://host:1234/v1` and `http://host:1234/v1/`.
  String apiRoot(Uri base) {
    final root = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (versionPath.isEmpty) return root;
    if (root.endsWith(versionPath)) return root;
    if (_versioned.hasMatch(root)) return root;
    return '$root$versionPath';
  }

  /// `{root}/{path}` on the base URL, query and fragment dropped.
  Uri endpoint(Uri base, String path) => base.replace(
    path: '${apiRoot(base)}/${path.replaceFirst(RegExp(r'^/+'), '')}',
    query: null,
    fragment: null,
  );

  /// A path next to the API root (llama-server's `/health`, `/tools`).
  Uri serverEndpoint(Uri base, String path) {
    var root = apiRoot(base);
    if (versionPath.isNotEmpty && root.endsWith(versionPath)) {
      root = root.substring(0, root.length - versionPath.length);
    }
    return base.replace(
      path: '$root/${path.replaceFirst(RegExp(r'^/+'), '')}',
      query: null,
      fragment: null,
    );
  }

  /// Request headers carrying [apiKey] the way this provider expects.
  Map<String, String> authHeaders(String apiKey) {
    final key = apiKey.trim();
    return switch (auth) {
      RemoteAuth.bearer => {if (key.isNotEmpty) 'Authorization': 'Bearer $key'},
      RemoteAuth.anthropicKey => {
        if (key.isNotEmpty) 'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      RemoteAuth.googleKey => {if (key.isNotEmpty) 'x-goog-api-key': key},
      RemoteAuth.azureKey => {if (key.isNotEmpty) 'api-key': key},
    };
  }
}

/// Request caps for one model on one connection; 0 means no cap.
class RemoteLimit {
  final int perMinute;
  final int perDay;
  const RemoteLimit({this.perMinute = 0, this.perDay = 0});

  bool get isEmpty => perMinute <= 0 && perDay <= 0;

  Map<String, dynamic> toJson() => {'perMinute': perMinute, 'perDay': perDay};

  static RemoteLimit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int n(Object? v) =>
        v is num && v.isFinite ? v.toInt().clamp(0, 1000000) : 0;
    final l = RemoteLimit(
      perMinute: n(raw['perMinute']),
      perDay: n(raw['perDay']),
    );
    return l.isEmpty ? null : l;
  }
}

/// One saved connection: a provider plus the user's URL, model and extra
/// headers. The API key is not part of it — it lives in the platform
/// keystore, keyed by [id], and is attached in memory only.
class RemoteProfile {
  static const maxHeaders = 16;

  final String id;
  final String name;
  final String providerId;
  final String baseUrl;
  final String model;

  /// Extra request headers, e.g. `HTTP-Referer` for OpenRouter or
  /// `OpenAI-Organization`. Never used for the API key.
  final Map<String, String> headers;

  /// Request caps by model id ('' is the server default model), enforced by
  /// the engine before each request so a hosted quota is not burned.
  final Map<String, RemoteLimit> limits;
  final bool shareMemory, learnMemory;

  /// The connection's own settings for chat answers: its model's
  /// temperature, sampling, answer length and context (Gemini's defaults,
  /// the config LM Studio loaded the model with…) instead of the phone's
  /// presets. On unless the user turns it off (decision 2026-10-18).
  final bool serverSettings;

  const RemoteProfile({
    required this.id,
    required this.name,
    this.providerId = 'custom',
    this.baseUrl = '',
    this.model = '',
    this.headers = const {},
    this.limits = const {},
    this.shareMemory = false,
    this.learnMemory = false,
    this.serverSettings = true,
  });

  /// The cap for the selected model.
  RemoteLimit get limit => limits[model.trim()] ?? const RemoteLimit();

  RemoteProvider get provider => RemoteProvider.byId(providerId);

  /// The base URL when it is a usable http(s) address.
  Uri? get uri {
    final u = Uri.tryParse(baseUrl.trim());
    if (u == null || !['http', 'https'].contains(u.scheme) || u.host.isEmpty) {
      return null;
    }
    return u;
  }

  String get label => name.trim().isEmpty ? provider.name : name.trim();

  RemoteProfile copyWith({
    String? name,
    String? providerId,
    String? baseUrl,
    String? model,
    Map<String, String>? headers,
    Map<String, RemoteLimit>? limits,
    bool? shareMemory,
    bool? learnMemory,
    bool? serverSettings,
  }) => RemoteProfile(
    id: id,
    name: name ?? this.name,
    providerId: providerId ?? this.providerId,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    headers: headers ?? this.headers,
    limits: limits ?? this.limits,
    shareMemory: shareMemory ?? this.shareMemory,
    learnMemory: learnMemory ?? this.learnMemory,
    serverSettings: serverSettings ?? this.serverSettings,
  );

  /// The profile with [limit] applied to the selected model.
  RemoteProfile withLimit(RemoteLimit limit) {
    final next = {...limits};
    if (limit.isEmpty) {
      next.remove(model.trim());
    } else {
      next[model.trim()] = limit;
    }
    return copyWith(limits: next);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'providerId': providerId,
    'baseUrl': baseUrl,
    'model': model,
    'shareMemory': shareMemory,
    'learnMemory': learnMemory,
    'serverSettings': serverSettings,
    if (headers.isNotEmpty) 'headers': headers,
    if (limits.isNotEmpty)
      'limits': {for (final e in limits.entries) e.key: e.value.toJson()},
  };

  static String _text(Object? v, int limit) =>
      v is String ? v.substring(0, v.length.clamp(0, limit)) : '';

  /// A connection another phone shared from "Use this device as a server"
  /// (copied text or its QR code): the profile and its access key, or null
  /// when [text] is not such a connection or its URL is not http(s).
  static (RemoteProfile, String)? fromPairing(
    String text, {
    required String id,
  }) {
    Object? raw;
    try {
      raw = jsonDecode(text.trim());
    } on FormatException {
      return null;
    }
    if (raw is! Map || raw['ondevice_llm'] != 'connection') return null;
    final url = _text(raw['url'], 2000).trim().replaceFirst(RegExp(r'/+$'), '');
    final profile = RemoteProfile(
      id: id,
      name: '',
      providerId: RemoteProvider.custom.id,
      baseUrl: url,
      model: _text(raw['model'], 200).trim(),
    );
    final uri = profile.uri;
    if (uri == null) return null;
    return (
      profile.copyWith(name: 'Phone at ${uri.host}'),
      _text(raw['key'], 512).trim(),
    );
  }

  static RemoteProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _text(raw['id'], 64);
    if (id.isEmpty) return null;
    final headers = <String, String>{};
    if (raw['headers'] is Map) {
      for (final e in (raw['headers'] as Map).entries.take(maxHeaders)) {
        final k = _text(e.key, 100).trim();
        final v = _text(e.value, 1000);
        if (k.isNotEmpty && !_reserved(k)) headers[k] = v;
      }
    }
    final limits = <String, RemoteLimit>{};
    if (raw['limits'] is Map) {
      for (final e in (raw['limits'] as Map).entries.take(64)) {
        final l = RemoteLimit.fromJson(e.value);
        if (e.key is String && l != null) limits[_text(e.key, 200)] = l;
      }
    }
    return RemoteProfile(
      id: id,
      name: _text(raw['name'], 80),
      providerId: RemoteProvider.byId(_text(raw['providerId'], 40)).id,
      baseUrl: _text(raw['baseUrl'], 2000),
      model: _text(raw['model'], 200),
      headers: headers,
      limits: limits,
      shareMemory: raw['shareMemory'] == true,
      learnMemory: raw['learnMemory'] == true,
      serverSettings: raw['serverSettings'] != false,
    );
  }

  /// Headers the engine sets itself; a stray one in the extras is dropped so
  /// a saved profile cannot smuggle a key into plaintext settings.
  static bool _reserved(String name) => const {
    'authorization',
    'x-api-key',
    'x-goog-api-key',
    'api-key',
    'content-type',
    'accept',
    'anthropic-version',
  }.contains(name.toLowerCase());

  /// Parses "Name: value" lines from the settings field.
  static Map<String, String> parseHeaders(String text) {
    final out = <String, String>{};
    for (final line in text.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final k = line.substring(0, i).trim();
      final v = line.substring(i + 1).trim();
      if (k.isEmpty || _reserved(k) || out.length >= maxHeaders) continue;
      out[k] = v;
    }
    return out;
  }

  static String formatHeaders(Map<String, String> headers) =>
      [for (final e in headers.entries) '${e.key}: ${e.value}'].join('\n');
}

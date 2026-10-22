import '../../settings/domain/entities/inference_settings.dart';

/// A named way of using the assistant (FX-03): a system prompt plus optional
/// overrides for temperature, thinking and web mode. Built-ins ship with the
/// app; the user's own are stored beside the settings.
class Preset {
  final String id;
  final String name;
  final String emoji;
  final String systemPrompt;

  /// Null keeps the global setting.
  final double? temperature;
  final bool? thinking;
  final WebMode? webMode;

  /// Any other setting overrides (keys of [InferenceSettings.toJson]),
  /// edited through the same override editor as model profiles and chats.
  final Map<String, dynamic> overrides;
  final bool builtIn;

  const Preset({
    required this.id,
    required this.name,
    required this.emoji,
    required this.systemPrompt,
    this.temperature,
    this.thinking,
    this.webMode,
    this.overrides = const {},
    this.builtIn = false,
  });

  /// The neutral preset: nothing added, nothing overridden.
  static const general = Preset(
    id: 'general',
    name: 'General',
    emoji: '💬',
    systemPrompt: '',
    builtIn: true,
  );

  static const builtIns = <Preset>[
    general,
    Preset(
      id: 'concise',
      name: 'Concise',
      emoji: '⚡',
      systemPrompt:
          'Answer in as few words as the question allows. No preamble, no restating the question, no closing remarks. Use a list only when there are several distinct items.',
      temperature: 0.3,
      thinking: false,
      builtIn: true,
    ),
    Preset(
      id: 'translator',
      name: 'Translator',
      emoji: '🌐',
      systemPrompt:
          'You are a translator. Detect the language of the user\'s text and translate it into English; if the text is already English, translate it into the language the user names, or ask which one. Output only the translation, preserving tone, formatting and names. Add a one-line note only for genuinely ambiguous terms.',
      temperature: 0.2,
      thinking: false,
      builtIn: true,
    ),
    Preset(
      id: 'code-reviewer',
      name: 'Code reviewer',
      emoji: '🧑‍💻',
      systemPrompt:
          'You are a senior engineer reviewing code. Point out bugs, security problems and unclear parts first, then style. Quote the exact lines you mean, propose the fix as code, and say when the code is fine. Do not rewrite what you were not asked to change.',
      temperature: 0.2,
      builtIn: true,
    ),
    Preset(
      id: 'editor',
      name: 'Writing editor',
      emoji: '✍️',
      systemPrompt:
          'You are an editor. Improve the user\'s text for clarity, flow and correctness while keeping their voice and meaning. Return the edited text first, then a short list of the substantive changes. Do not add content the author did not write.',
      temperature: 0.5,
      builtIn: true,
    ),
    Preset(
      id: 'tutor',
      name: 'Tutor',
      emoji: '🎓',
      systemPrompt:
          'You are a patient tutor. Explain one idea at a time, check understanding with a short question before moving on, and prefer worked examples over definitions. When the user tries an exercise, give hints before answers.',
      temperature: 0.7,
      builtIn: true,
    ),
    Preset(
      id: 'summariser',
      name: 'Summariser',
      emoji: '📝',
      systemPrompt:
          'Summarise whatever the user provides. Start with a one-sentence takeaway, then the key points as a list, then anything the reader must act on. Keep every number, name and date exactly as in the source. Do not add opinions.',
      temperature: 0.3,
      thinking: false,
      builtIn: true,
    ),
    Preset(
      id: 'brainstorm',
      name: 'Brainstorm',
      emoji: '💡',
      systemPrompt:
          'Generate many distinct ideas quickly. Give at least ten, one line each, ranging from safe to unusual; group them if there are natural themes. No judging until asked.',
      temperature: 1.0,
      builtIn: true,
    ),
  ];

  Preset copyWith({
    String? name,
    String? emoji,
    String? systemPrompt,
    double? temperature,
    bool clearTemperature = false,
    bool? thinking,
    bool clearThinking = false,
    WebMode? webMode,
    bool clearWebMode = false,
    Map<String, dynamic>? overrides,
  }) => Preset(
    id: id,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    temperature: clearTemperature ? null : temperature ?? this.temperature,
    thinking: clearThinking ? null : thinking ?? this.thinking,
    webMode: clearWebMode ? null : webMode ?? this.webMode,
    overrides: overrides ?? this.overrides,
    builtIn: builtIn,
  );

  /// The preset as a settings layer: its typed fields first, then any
  /// generic overrides (which win when both name the same key).
  Map<String, dynamic> toOverrides() => {
    if (temperature != null) 'temperature': temperature,
    if (thinking != null) 'thinkingModeEnabled': thinking,
    if (webMode != null) 'webMode': webMode!.name,
    ...overrides,
  };

  /// The global settings with this preset's overrides applied.
  InferenceSettings apply(InferenceSettings s) => InferenceSettings.fromJson({
    ...s.toJson(),
    ...toOverrides(),
  }).copyWith(remoteApiKeys: s.remoteApiKeys);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'systemPrompt': systemPrompt,
    if (temperature != null) 'temperature': temperature,
    if (thinking != null) 'thinking': thinking,
    if (webMode != null) 'webMode': webMode!.name,
    if (overrides.isNotEmpty) 'overrides': overrides,
  };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
    id: j['id'] as String,
    name: (j['name'] as String? ?? 'Preset').trim(),
    emoji: (j['emoji'] as String? ?? '✨').trim(),
    systemPrompt: j['systemPrompt'] as String? ?? '',
    temperature: (j['temperature'] as num?)?.toDouble().clamp(0, 2),
    thinking: j['thinking'] as bool?,
    webMode: WebMode.values.where((m) => m.name == j['webMode']).firstOrNull,
    overrides: j['overrides'] is Map
        ? Map<String, dynamic>.from(j['overrides'] as Map)
        : const {},
  );
}

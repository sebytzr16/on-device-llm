import 'prompt_shortcut_i18n.dart';

/// A saved prompt the composer expands from `/name`: `/summarize <text>`
/// sends the summarize prompt with the text in it. Built-ins cover the
/// everyday rewrites; the user adds their own under Settings > Shortcuts.
class PromptShortcut {
  /// What follows the slash: lower-case letters, digits and dashes.
  final String name;

  /// Shown in the suggestion row and the settings list.
  final String description;

  /// The prompt. `{input}` is replaced by what follows the command (the
  /// text is appended after a blank line when the template has no
  /// `{input}`); `{arg}` takes the first word after the command, e.g. the
  /// language of /translate, or [defaultArg] when none is given.
  final String template;
  final String defaultArg;
  final bool builtIn;

  /// The language the template is written in: /translate names its
  /// target language in it ("anglais" in French).
  final String lang;

  const PromptShortcut({
    required this.name,
    required this.description,
    required this.template,
    this.defaultArg = '',
    this.builtIn = false,
    this.lang = 'en',
  });

  static final validName = RegExp(r'^[a-z0-9][a-z0-9-]{0,23}$');

  /// This shortcut in the app's language [lang] ('en', 'fr', 'es'): a
  /// built-in gets its translated prompt and description; the user's own
  /// are sent as written.
  PromptShortcut localized(String lang) {
    if (!builtIn) return this;
    final t = PromptShortcutI18n.of(name, lang);
    if (t == null) return this;
    return PromptShortcut(
      name: name,
      description: t.$2,
      template: t.$1,
      defaultArg: t.$3.isEmpty ? defaultArg : t.$3,
      builtIn: true,
      lang: lang,
    );
  }

  static const builtIns = <PromptShortcut>[
    PromptShortcut(
      name: 'summarize',
      description: 'Summarize the text in a few bullet points',
      template:
          'Summarize the following in 3 to 5 short bullet points, keeping names, numbers and dates exact.\n\n{input}',
      builtIn: true,
    ),
    PromptShortcut(
      name: 'translate',
      description: 'Translate — /translate fr <text>',
      template:
          'Translate the following into {arg}. Reply with the translation only.\n\n{input}',
      defaultArg: 'English',
      builtIn: true,
    ),
    PromptShortcut(
      name: 'fix',
      description: 'Fix spelling and grammar, keep the meaning',
      template:
          'Correct the spelling, grammar and punctuation of the following. Keep its meaning, tone and language. Reply with the corrected text only.\n\n{input}',
      builtIn: true,
    ),
    PromptShortcut(
      name: 'shorter',
      description: 'Rewrite the text shorter',
      template:
          'Rewrite the following to about half its length without losing any fact. Reply with the rewrite only.\n\n{input}',
      builtIn: true,
    ),
    PromptShortcut(
      name: 'explain',
      description: 'Explain simply, for a newcomer',
      template:
          'Explain the following in plain language for someone new to the topic, with one concrete example.\n\n{input}',
      builtIn: true,
    ),
    PromptShortcut(
      name: 'email',
      description: 'Turn notes into a clear email',
      template:
          'Write a clear, polite email from these notes. Keep it short and end with the next step.\n\n{input}',
      builtIn: true,
    ),
    PromptShortcut(
      name: 'code-review',
      description: 'Review code for bugs and improvements',
      template:
          'Review this code. List real bugs first (with the line and a fix), then clear improvements. Do not restate the code.\n\n{input}',
      builtIn: true,
    ),
  ];

  /// The prompt for "/name rest" with this shortcut.
  String expand(String rest) {
    var input = rest.trim();
    var arg = defaultArg;
    if (template.contains('{arg}') && input.isNotEmpty) {
      final space = input.indexOf(RegExp(r'\s'));
      final first = space < 0 ? input : input.substring(0, space);
      final names =
          PromptShortcutI18n.languageNames[lang] ??
          PromptShortcutI18n.languageNames['en']!;
      final language = names[first.toLowerCase()];
      // A bare code or a language name (in any of the app's languages) is
      // the argument; any other first word is already the text.
      String? named;
      if (first.length > 2) {
        for (final table in PromptShortcutI18n.languageNames.values) {
          for (final e in table.entries) {
            if (e.value.toLowerCase() == first.toLowerCase()) {
              named = names[e.key];
            }
          }
        }
      }
      if (language != null || named != null) {
        arg = language ?? named!;
        input = space < 0 ? '' : input.substring(space).trim();
      }
    }
    final body = template.replaceAll('{arg}', arg);
    if (body.contains('{input}')) {
      return body.replaceAll('{input}', input).trim();
    }
    return input.isEmpty ? body.trim() : '${body.trim()}\n\n$input';
  }

  /// The shortcut a message invokes and the expanded prompt, or null when
  /// the message is not "/name …" for a known shortcut (a message that
  /// merely starts with a slash, like "/etc/hosts is…", goes out as typed).
  static (PromptShortcut, String)? apply(
    String message,
    List<PromptShortcut> shortcuts, {
    String lang = 'en',
  }) {
    final m = RegExp(
      r'^/([a-z0-9-]+)(?:\s+([\s\S]*))?$',
    ).firstMatch(message.trimLeft());
    if (m == null) return null;
    final name = m[1]!;
    final shortcut = shortcuts.where((s) => s.name == name).firstOrNull;
    if (shortcut == null) return null;
    final local = shortcut.localized(lang);
    return (local, local.expand(m[2] ?? ''));
  }

  /// Shortcuts whose name starts with what is typed after the slash, while
  /// the command word is still being typed ("/sum" → summarize).
  static List<PromptShortcut> suggestions(
    String typed,
    List<PromptShortcut> shortcuts,
  ) {
    final m = RegExp(r'^/([a-z0-9-]*)$').firstMatch(typed);
    if (m == null) return const [];
    return [
      for (final s in shortcuts)
        if (s.name.startsWith(m[1]!)) s,
    ];
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'template': template,
    if (defaultArg.isNotEmpty) 'defaultArg': defaultArg,
  };

  static PromptShortcut? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final template = raw['template'];
    if (name is! String || !validName.hasMatch(name)) return null;
    if (template is! String || template.trim().isEmpty) return null;
    return PromptShortcut(
      name: name,
      description: raw['description'] is String
          ? raw['description'] as String
          : '',
      template: template.length > 4000 ? template.substring(0, 4000) : template,
      defaultArg: raw['defaultArg'] is String
          ? raw['defaultArg'] as String
          : '',
    );
  }
}

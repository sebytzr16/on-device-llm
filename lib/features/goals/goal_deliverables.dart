import '../tools/phone_actions.dart';
import 'goal_runner.dart';

/// What a goal asks to have made besides its report: a file, a calendar
/// event, a reminder, an alarm, a timer or a message draft (audit G3/G5,
/// 2026-10-08). The research phases do not research these; the delivery
/// phase prepares them, and a goal whose deliverable could not be prepared
/// is not complete.
enum GoalDeliverableKind { file, event, reminder, alarm, timer, message }

class GoalDeliverable {
  final GoalDeliverableKind kind;

  /// For a file: md, txt, csv, html or json.
  final String format;
  const GoalDeliverable(this.kind, {this.format = ''});

  /// The phone action kind that fulfils it.
  String get actionKind => switch (kind) {
    GoalDeliverableKind.file => 'save_file',
    GoalDeliverableKind.event => 'create_event',
    GoalDeliverableKind.reminder => 'set_reminder',
    GoalDeliverableKind.alarm => 'set_alarm',
    GoalDeliverableKind.timer => 'set_timer',
    GoalDeliverableKind.message => 'draft_message',
  };

  @override
  bool operator ==(Object other) =>
      other is GoalDeliverable && other.kind == kind && other.format == format;

  @override
  int get hashCode => Object.hash(kind, format);

  @override
  String toString() =>
      kind == GoalDeliverableKind.file ? 'file ($format)' : kind.name;
}

abstract final class GoalDeliverables {
  // A verb that makes something, then (within a few words) a file noun:
  // "prepare a text file", "save it as a CSV file", "write the answer to a
  // document", "export the table as a spreadsheet". "The file size" or "a
  // PDF document reader" alone asks for nothing.
  static final _fileRequest = RegExp(
    r'(?<![\p{L}\p{N}])(?:prepare|create|make|write|produce|generate|save|export|put|give me|send me|deliver|compile|draft|'
    r'prépare[rz]?|crée[rz]?|créer|fai[st]|faire|écri[st]|écrire|rédige[rz]?|enregistre[rz]?|exporte[rz]?|génère[rz]?|générer|mets|mettre|donne[- ]moi|'
    r'prepara[r]?|crea[r]?|haz|hacer|escribe|escribir|redacta[r]?|guarda[r]?|exporta[r]?|genera[r]?|pon|poner|dame)'
    r'(?![\p{L}\p{N}])[^.?!\n]{0,60}?(?<![\p{L}\p{N}])'
    r'(?:(?:text|txt|markdown|md|csv|html|json)\s+(?:file|document)|file|document|spreadsheet|\.(?:txt|md|csv|html|json)|'
    r'fichier|document|tableur|feuille de calcul|'
    r'archivo|fichero|documento|hoja de c[áa]lculo)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  // "as a CSV", "in Markdown", "to JSON" after an export verb.
  static final _formatRequest = RegExp(
    r'(?<![\p{L}\p{N}])(?:save|export|write|put|enregistre[rz]?|exporte[rz]?|guarda[r]?|exporta[r]?)(?![\p{L}\p{N}])[^.?!\n]{0,40}?(?:as|to|in|into|en|como|au format|en formato)\s+(?:a |an |un |une |una )?(?:csv|json|markdown|html|txt)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final _csv = RegExp(
    r'(?<![\p{L}\p{N}])(?:csv|spreadsheet|tableur|feuille de calcul|hoja de c[áa]lculo|excel)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _json = RegExp(r'\bjson\b', caseSensitive: false);
  static final _html = RegExp(r'\bhtml\b|web page', caseSensitive: false);
  static final _markdown = RegExp(r'\b(?:markdown|md)\b', caseSensitive: false);
  static final _text = RegExp(
    r'(?<![\p{L}\p{N}])(?:text|txt|plain|texte|texto)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final _event = RegExp(
    r'(?<![\p{L}\p{N}])(?:calendar|agenda|event|appointment|meeting|calendrier|événement|evenement|rendez-vous|réunion|calendario|evento|cita|reunión)s?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _reminder = RegExp(
    r'(?<![\p{L}\p{N}])(?:remind|reminder|rappel|rappelle|recordatorio|recuérdame|recuerdame)s?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _alarm = RegExp(
    r'(?<![\p{L}\p{N}])(?:alarm|wake me|alarme|réveil|réveille|alarma|despiértame|despiertame)s?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _timer = RegExp(
    r'(?<![\p{L}\p{N}])(?:timer|countdown|minuteur|chrono|temporizador)s?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );
  static final _message = RegExp(
    r'(?<![\p{L}\p{N}])(?:e-?mail|mail|message|text him|text her|text them|sms|texto|courriel|mensaje|correo)s?(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  /// The deliverables [objective] asks for, at most one of each kind.
  static List<GoalDeliverable> of(String objective) {
    final out = <GoalDeliverable>[];
    final file =
        _fileRequest.firstMatch(objective) ??
        _formatRequest.firstMatch(objective);
    if (file != null) {
      // The format may follow the noun: "un archivo JSON", "a file in CSV".
      final after = objective
          .substring(file.end, (file.end + 24).clamp(0, objective.length))
          .split(RegExp(r'[.,;!?\n]|\s(?:and|then|et|puis|y|luego)\s'))
          .first;
      final around = '${file[0]}$after';
      out.add(
        GoalDeliverable(GoalDeliverableKind.file, format: _format(around)),
      );
    }
    // The other kinds are commands the chat already recognises ("add it
    // to my calendar", "remind me", "draft an email"); a goal about the
    // best calendar app asks for none.
    final rest = file == null
        ? objective
        : objective.replaceRange(file.start, file.end, ' ');
    if (PhoneActions.wanted(rest)) {
      for (final (pattern, kind) in [
        (_reminder, GoalDeliverableKind.reminder),
        (_event, GoalDeliverableKind.event),
        (_alarm, GoalDeliverableKind.alarm),
        (_timer, GoalDeliverableKind.timer),
        (_message, GoalDeliverableKind.message),
      ]) {
        if (pattern.hasMatch(rest)) out.add(GoalDeliverable(kind));
      }
    }
    return out;
  }

  static String _format(String request) {
    if (_csv.hasMatch(request)) return 'csv';
    if (_json.hasMatch(request)) return 'json';
    if (_html.hasMatch(request)) return 'html';
    if (_markdown.hasMatch(request)) return 'md';
    if (_text.hasMatch(request)) return 'txt';
    return 'md';
  }

  // A planned question about making the deliverable rather than about the
  // world: "Prepare a text file with the weight", "How to save the answer
  // as a file". The web cannot answer these (audit G4/G5: the planner
  // researched "prepare the file" as a public-web task).
  static final _deliverableQuestion = RegExp(
    r'^(?:how (?:do i |to |can i )?)?(?:prepare|create|make|write|produce|generate|save|export|draft|format|compile|put)\s(?:[^?]{0,40}?\s)?(?:file|document|spreadsheet|csv|calendar|event|reminder|alarm|timer|e-?mail|message)\b',
    caseSensitive: false,
  );

  static bool isDeliverableQuestion(String question) =>
      _deliverableQuestion.hasMatch(question.trim());

  /// The objective without the part asking for the deliverable: what the
  /// research is about ("Find the Nikon Z30 weight, and prepare a text
  /// file with the answer" → "Find the Nikon Z30 weight").
  static String researchPart(String objective) {
    final file =
        _fileRequest.firstMatch(objective) ??
        _formatRequest.firstMatch(objective);
    if (file == null) return objective.trim();
    // The whole clause around the request goes: from the comma or "and"
    // before it to the end of its sentence.
    final before = objective.substring(0, file.start);
    final clause = RegExp(
      r'(?:[,;]\s*(?:and\s+|et\s+|y\s+|then\s+|puis\s+|luego\s+)?|\s+(?:and|then|et|puis|y|luego)\s+|^)\s*(?:please\s+|also\s+)?$',
      caseSensitive: false,
    ).firstMatch(before);
    final start = clause?.start ?? file.start;
    var end = objective.indexOf(RegExp(r'[.?!\n]'), file.end);
    if (end < 0) end = objective.length;
    final kept = '${objective.substring(0, start)}${objective.substring(end)}'
        .replaceAllMapped(RegExp(r'\s+([.?!,;])'), (m) => m[1]!)
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return kept.replaceAll(RegExp(r'^[.?!,;\s]+'), '').isEmpty
        ? objective.trim()
        : kept;
  }

  /// The requested file made from the complete report and its source list
  /// (never rewritten by the model, so nothing at the report's end can be
  /// lost), or null when it cannot be (too long).
  static PhoneAction? reportFile(
    String objective,
    String report,
    List<GoalSource> sources, {
    required String format,
  }) {
    final name = fileName(objective);
    final String content;
    switch (format) {
      case 'csv':
        final table = csvOf(report);
        content = table ?? withSources(report, sources);
        format = table == null ? 'md' : 'csv';
      case 'json':
        content = _jsonOf(objective, report, sources);
      case 'html':
        content = _htmlOf(objective, withSources(report, sources));
      case 'txt':
        content = withSources(_plain(report), sources);
      default:
        content = withSources(report, sources);
    }
    final action = PhoneAction('save_file', {
      'name': name,
      'format': format,
      'content': content,
    });
    return action.problem == null ? action : null;
  }

  // The request at the start of an objective ("Find the", "Busca el").
  static final _request = RegExp(
    r'^(?:(?:please|can you|could you|peux-tu|pouvez-vous|puedes)\s+)?'
    r'(?:find(?: out)?|look up|search(?: for)?|research|get|check|tell me|give me|show me|compare|list|'
    r'what (?:is|are)|how (?:much|many)|trouve|cherche|recherche|donne-moi|compare|quel(?:le)?s? (?:est|sont)|'
    r'busca|encuentra|investiga|dime|compara|cu[aá]l(?:es)? (?:es|son))\s+'
    r'(?:(?:the|a|an|le|la|les|l|un|une|des|du|el|los|las|una|unos)\s+)?',
    caseSensitive: false,
  );

  // Where the subject ends and its qualifiers begin.
  static final _qualifier = RegExp(
    r'\s(?:including|with|without|from|for|in|on|and|cite|citing|avec|sans|pour|dans|et|con|sin|para|en|y)\s',
    caseSensitive: false,
  );

  /// A short file name: the objective's subject, without the request
  /// before it or the qualifiers after it.
  static String fileName(String objective) {
    var text = researchPart(objective).split(RegExp(r'[.?!\n]')).first;
    text = text.replaceFirst(_request, '');
    final cut = _qualifier.firstMatch(text);
    if (cut != null && text.substring(0, cut.start).split(' ').length >= 2) {
      text = text.substring(0, cut.start);
    }
    final words = text
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s-]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(7)
        .join(' ');
    return words.isEmpty ? 'goal report' : words;
  }

  static String withSources(String report, List<GoalSource> sources) {
    if (sources.isEmpty) return report.trim();
    final b = StringBuffer('${report.trim()}\n\nSources\n');
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      final seen = s.retrievedAt == null
          ? ''
          : ' (read ${s.retrievedAt!.toIso8601String().substring(0, 10)})';
      b.writeln('[${i + 1}] ${s.title} — ${s.url}$seen');
    }
    return b.toString().trimRight();
  }

  /// Markdown made readable as plain text: headings, emphasis and table
  /// rules dropped, the words and citations kept.
  static String _plain(String markdown) => markdown
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m[1]!)
      .replaceAllMapped(
        RegExp(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])'),
        (m) => m[1]!,
      )
      .replaceAll(RegExp(r'^\|?\s*:?-{3,}.*$\n?', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'^\|(.*)\|\s*$', multiLine: true),
        (m) => m[1]!.split('|').map((c) => c.trim()).join('  ·  '),
      )
      .trim();

  /// The report's first Markdown table as CSV, or null when it has none.
  static String? csvOf(String report) {
    final rows = <List<String>>[];
    for (final line in report.split('\n')) {
      final l = line.trim();
      if (l.startsWith('|') && l.endsWith('|') && l.length > 1) {
        if (RegExp(r'^\|[\s:|-]+\|$').hasMatch(l)) continue;
        rows.add([
          for (final c in l.substring(1, l.length - 1).split('|')) c.trim(),
        ]);
      } else if (rows.isNotEmpty) {
        break;
      }
    }
    if (rows.length < 2) return null;
    String cell(String c) {
      final v = c.replaceAll(RegExp(r'\*\*|__'), '');
      return v.contains(RegExp(r'[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    }

    return rows.map((r) => r.map(cell).join(',')).join('\n');
  }

  static String _jsonOf(
    String objective,
    String report,
    List<GoalSource> sources,
  ) {
    String q(String s) =>
        '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', '').replaceAll('\t', r'\t')}"';
    final list = [
      for (var i = 0; i < sources.length; i++)
        '    {"n": ${i + 1}, "title": ${q(sources[i].title)}, "url": ${q(sources[i].url)}}',
    ];
    return '{\n  "goal": ${q(objective)},\n  "report": ${q(report.trim())},\n'
        '  "sources": [\n${list.join(',\n')}\n  ]\n}';
  }

  static String _htmlOf(String objective, String markdown) {
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final body = StringBuffer();
    var list = false;
    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      final bullet = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
      if (bullet == null && list) {
        body.writeln('</ul>');
        list = false;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        final n = heading[1]!.length;
        body.writeln('<h$n>${esc(heading[2]!)}</h$n>');
      } else if (bullet != null) {
        if (!list) body.writeln('<ul>');
        list = true;
        body.writeln('<li>${esc(bullet[1]!)}</li>');
      } else if (line.trim().isNotEmpty) {
        body.writeln('<p>${esc(line)}</p>');
      }
    }
    if (list) body.writeln('</ul>');
    return '<!doctype html>\n<html><head><meta charset="utf-8">'
        '<title>${esc(objective)}</title></head><body>\n$body</body></html>';
  }

  /// A [GoalProgress.missing] entry for a deliverable left out, read back
  /// by [parseMissing] so the page can say it in the user's language.
  /// [reason]: stopped, budget, unreadable, tooLong, none, or
  /// `invalid: <problem>`.
  static String missingEntry(GoalDeliverable w, String reason) =>
      '$_prefix${w.kind.name}:${w.format}:$reason';

  static const _prefix = 'deliverable:';

  static bool isMissingEntry(String line) => line.startsWith(_prefix);

  static (GoalDeliverable, String)? parseMissing(String line) {
    if (!isMissingEntry(line)) return null;
    final parts = line.substring(_prefix.length).split(':');
    if (parts.length < 3) return null;
    final kind = GoalDeliverableKind.values.asNameMap()[parts[0]];
    if (kind == null) return null;
    return (
      GoalDeliverable(kind, format: parts[1]),
      parts.sublist(2).join(':'),
    );
  }

  /// What a delivery left out: each wanted deliverable no prepared action
  /// fulfils, with the reason for its kind ([reasons] by action kind) or
  /// "none" (the model proposed nothing for it).
  static List<String> missing(
    List<GoalDeliverable> wanted,
    List<PhoneAction> prepared, {
    Map<String, String> reasons = const {},
  }) => [
    for (final w in wanted)
      if (!prepared.any((a) => a.kind == w.actionKind))
        missingEntry(w, reasons[w.actionKind] ?? 'none'),
  ];
}

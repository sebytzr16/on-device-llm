import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'domain/tool_spec.dart';

/// Things the assistant prepares on the phone (tester, 2026-10-07): a
/// calendar event, a reminder, an alarm, a timer, a message draft or a file.
/// The model only prepares them; each one is a card under the answer, and
/// the user's tap opens the phone's own app (Calendar, Clock, Messages,
/// email) with everything filled in, where they confirm, save or send.
/// Nothing is sent, saved or scheduled without that tap.
enum PhoneActionProblemCode {
  missingField,
  invalidDate,
  invalidNumber,
  invalidField,
  tooLarge,
  unknownAction,
}

class PhoneActionProblem {
  final PhoneActionProblemCode code;
  final String message;
  const PhoneActionProblem(this.code, this.message);
}

class PhoneAction {
  /// One of [PhoneActions.kinds].
  final String kind;
  final Map<String, dynamic> args;
  const PhoneAction(this.kind, this.args);

  /// [key]'s text; a placeholder in place of nothing ("None", "null") is
  /// empty: LM Studio's Gemma 4 E4B set a timer named "None" (remote
  /// sweep, 2026-10-21).
  String _s(String key) {
    final v = '${args[key] ?? ''}'.trim();
    return _placeholder.hasMatch(v) ? '' : v;
  }

  static final _placeholder = RegExp(
    r'^(?:none|null|nil|undefined|n/?a)$',
    caseSensitive: false,
  );

  String get title => switch (kind) {
    'create_event' => _s('title'),
    'set_reminder' => _s('text'),
    'set_alarm' => _s('label').isEmpty ? _s('time') : _s('label'),
    'set_timer' => _s('label'),
    'draft_message' => _s('to'),
    'save_file' => fileName,
    _ => '',
  };

  /// One line for the card: when, how long, to whom.
  String get detail => switch (kind) {
    'create_event' => [
      _when(start),
      if (_s('location').isNotEmpty) _s('location'),
    ].where((e) => e.isNotEmpty).join(' · '),
    'set_reminder' => _when(start),
    'set_alarm' => [
      _s('time'),
      if (_days.isNotEmpty) _days.join(', '),
    ].join(' · '),
    'set_timer' => _duration(timerSeconds ?? 0),
    'draft_message' => _s('body'),
    'save_file' => '${_s('content').length} characters',
    _ => '',
  };

  /// Event and reminder start, read as local time.
  DateTime? get start => _date(
    _s(kind == 'set_reminder' ? 'when' : 'start'),
    allDay: kind == 'create_event' && args['all_day'] == true,
  );

  DateTime? get end => _date(_s('end'), allDay: args['all_day'] == true);

  /// Dart's ISO parser normalizes February 31 and overflowing clocks.
  /// Validate the civil components before converting an offset to an instant.
  static DateTime? _date(String raw, {bool allDay = false}) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:\d{2})?)?$',
    ).firstMatch(raw);
    if (m == null || (!allDay && m[4] == null)) return null;
    final y = int.parse(m[1]!),
        month = int.parse(m[2]!),
        day = int.parse(m[3]!);
    final h = int.parse(m[4] ?? '0'),
        min = int.parse(m[5] ?? '0'),
        sec = int.parse(m[6] ?? '0');
    if (y < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(y, month + 1, 0).day ||
        h > 23 ||
        min > 59 ||
        sec > 59) {
      return null;
    }
    if (allDay && (h != 0 || min != 0 || sec != 0 || m[8] != null)) return null;
    final offset = m[8];
    if (offset != null && offset != 'Z') {
      final oh = int.parse(offset.substring(1, 3)),
          om = int.parse(offset.substring(4));
      if (oh > 14 || om > 59 || (oh == 14 && om != 0)) {
        return null;
      }
    }
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  int? get timerSeconds {
    final s = num.tryParse(_s('seconds'));
    final m = num.tryParse(_s('minutes'));
    // Small models send an empty or null unit next to the one they meant.
    if ((_s('seconds').isNotEmpty && (s == null || !s.isFinite || s < 0)) ||
        (_s('minutes').isNotEmpty && (m == null || !m.isFinite || m < 0))) {
      return null;
    }
    final total = (s ?? 0) + (m ?? 0) * 60;
    return total.isFinite && total >= 0.5 && total <= 86400
        ? total.round()
        : null;
  }

  (int, int)? get alarmTime {
    final m = RegExp(r'^(\d{1,2})[:h.](\d{2})$').firstMatch(_s('time'));
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    return h < 24 && min < 60 ? (h, min) : null;
  }

  List<String> get _days {
    final v = args['days'];
    return v is List ? [for (final d in v) '$d'] : const [];
  }

  /// The file name, safe for any file system, with an allowed extension.
  String get fileName {
    var name = _s('name')
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.isEmpty) name = 'note';
    final ext = p.extension(name).toLowerCase();
    if (!PhoneActions.fileTypes.contains(ext)) {
      final format = _s('format').toLowerCase().replaceAll('.', '');
      name =
          '$name.${PhoneActions.fileTypes.contains('.$format') ? format : 'md'}';
    }
    return name.length > 80 ? name.substring(name.length - 80) : name;
  }

  /// Why the model's arguments cannot work, or null.
  String? get problem => validationProblem?.message;

  PhoneActionProblem? get validationProblem {
    switch (kind) {
      case 'create_event':
        if (_s('title').isEmpty) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.missingField,
            'Missing "title".',
          );
        }
        if (args.containsKey('all_day') && args['all_day'] is! bool) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidField,
            '"all_day" must be true or false.',
          );
        }
        if (start == null) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidDate,
            '"start" must be a valid date-time (or date for an all-day event).',
          );
        }
        if (args.containsKey('end') && end == null) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidDate,
            '"end" must be a valid date-time (or date for an all-day event).',
          );
        }
        if (end != null && !end!.isAfter(start!)) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidDate,
            '"end" must be after "start".',
          );
        }
      case 'set_reminder':
        if (_s('text').isEmpty) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.missingField,
            'Missing "text".',
          );
        }
        if (start == null) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidDate,
            '"when" must be a local date-time like 2026-10-08T09:00.',
          );
        }
      case 'set_alarm':
        if (alarmTime == null) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidDate,
            '"time" must be 24-hour HH:MM.',
          );
        }
      case 'set_timer':
        final s = timerSeconds;
        if (s == null || s > 24 * 3600) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.invalidNumber,
            'Give "minutes" or "seconds" (at most 24 hours).',
          );
        }
      case 'draft_message':
        if (_s('body').isEmpty) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.missingField,
            'Missing "body".',
          );
        }
      case 'save_file':
        if (_s('content').isEmpty) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.missingField,
            'Missing "content".',
          );
        }
        if (_s('content').length > PhoneActions.maxFileChars) {
          return const PhoneActionProblem(
            PhoneActionProblemCode.tooLarge,
            'The file is too long (at most ${PhoneActions.maxFileChars} characters).',
          );
        }
      default:
        return const PhoneActionProblem(
          PhoneActionProblemCode.unknownAction,
          'Unknown action.',
        );
    }
    return null;
  }

  /// What goes to the platform: the intent and its extras.
  Map<String, Object?> toPlatform() => switch (kind) {
    'create_event' => {
      'kind': 'event',
      'title': _s('title'),
      'begin': _eventTime(start!).millisecondsSinceEpoch,
      'end': _eventTime(
        end ??
            (args['all_day'] == true
                ? DateTime(start!.year, start!.month, start!.day + 1)
                : start!.add(const Duration(hours: 1))),
      ).millisecondsSinceEpoch,
      'location': _s('location'),
      'description': _s('notes'),
      'allDay': args['all_day'] == true,
    },
    'set_reminder' => {
      'kind': 'event',
      'title': _s('text'),
      'begin': start!.millisecondsSinceEpoch,
      'end': start!.add(const Duration(minutes: 15)).millisecondsSinceEpoch,
      'location': '',
      'description': '',
      'allDay': false,
    },
    'set_alarm' => {
      'kind': 'alarm',
      'hour': alarmTime!.$1,
      'minute': alarmTime!.$2,
      'label': _s('label'),
      'days': [
        for (final d in _days)
          if (_weekday(d) != null) _weekday(d)!,
      ],
    },
    'set_timer' => {
      'kind': 'timer',
      'seconds': timerSeconds,
      'label': _s('label'),
    },
    'draft_message' => {
      'kind': 'message',
      'channel': _s('channel').toLowerCase(),
      'to': _s('to'),
      'subject': _s('subject'),
      'body': _s('body'),
    },
    _ => const {},
  };

  /// Calendar.SUNDAY = 1 … SATURDAY = 7 (what AlarmClock expects).
  static int? _weekday(String d) {
    final t = d.trim().toLowerCase();
    const names = {
      'sun': 1, 'dim': 1, 'dom': 1, //
      'mon': 2, 'lun': 2,
      'tue': 3, 'mar': 3,
      'wed': 4, 'mer': 4, 'mié': 4, 'mie': 4,
      'thu': 5, 'jeu': 5, 'jue': 5,
      'fri': 6, 'ven': 6, 'vie': 6,
      'sat': 7, 'sam': 7, 'sáb': 7, 'sab': 7,
    };
    return t.length < 3 ? null : names[t.substring(0, 3)];
  }

  static String _when(DateTime? d) {
    if (d == null) return '';
    d = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _duration(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    return [
      if (h > 0) '$h h',
      if (m > 0) '$m min',
      if (s > 0) '$s s',
    ].join(' ');
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'args': args};

  static PhoneAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    final args = raw['args'];
    if (kind is! String || args is! Map) return null;
    if (args.keys.any((k) => k is! String)) return null;
    final a = PhoneAction(kind, Map<String, dynamic>.from(args));
    return a.problem == null ? a : null;
  }

  DateTime _eventTime(DateTime d) =>
      args['all_day'] == true ? DateTime.utc(d.year, d.month, d.day) : d;
}

abstract final class PhoneActions {
  static const _channel = MethodChannel('ondevice_llm/phone_actions');
  static const kinds = {
    'create_event',
    'set_reminder',
    'set_alarm',
    'set_timer',
    'draft_message',
    'save_file',
  };
  static const fileTypes = {'.md', '.txt', '.csv', '.html', '.json'};
  static const maxFileChars = 60000;

  /// The message asks for something to be done on the phone: offered the
  /// action tools only then (they cost prompt tokens).
  static bool wanted(String input) => _wanted.hasMatch(input);

  /// [input] asks for the action outright ("Set a timer for five
  /// minutes"), not how to do one ("How do I set an alarm?"): the first
  /// round must prepare its card (phone, 2026-10-08: Gemma 4 E2B answered
  /// "I will set a timer for five minutes now" and called nothing).
  static bool command(String input) =>
      wanted(input) && !_howTo.hasMatch(input.trim());

  /// The set_timer arguments for a plain timer request ("Set a timer for
  /// five minutes", "minuteur de 10 minutes", "temporizador de 30
  /// segundos"), or null: the app prepares it when the phone's small model
  /// writes chat instead of the call (Qwen3.5 0.8B, phone probe round 4,
  /// 2026-10-18: emoji, then a closing `</tool_call>` with no call).
  static Map<String, num>? plainTimer(String input) {
    final t = input.toLowerCase();
    // "An hour and a half" is not one plain duration.
    if (!_timerWord.hasMatch(t) || RegExp(r'half|demi|media').hasMatch(t)) {
      return null;
    }
    final found = _duration.allMatches(t).toList();
    if (found.length != 1) return null;
    final m = found.single;
    final n =
        num.tryParse(m[1]!.replaceAll(',', '.')) ?? _numberWords[m[1]!] ?? 0;
    if (n <= 0) return null;
    final unit = m[2]!;
    if (unit.startsWith('s')) return {'seconds': n};
    if (unit.startsWith('h')) return {'minutes': n * 60};
    return {'minutes': n};
  }

  static final _timerWord = RegExp(
    r'\b(?:timer|countdown|minuteur|chrono|compte à rebours|temporizador|cronómetro)\b',
    unicode: true,
  );
  static final _duration = RegExp(
    r'\b(\d+(?:[.,]\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty|forty-five|forty five|sixty|ninety)[\s-]*(seconds?|secs?|minutes?|mins?|hours?|hrs?|secondes?|heures?|segundos?|minutos?|horas?)\b',
  );
  static const _numberWords = <String, num>{
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'fifteen': 15,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'forty-five': 45,
    'forty five': 45,
    'sixty': 60,
    'ninety': 90,
  };

  static final _howTo = RegExp(
    r"^[¿¡\s]*(?:how|what|why|when|where|which|who|is|are|does|do|did|can i|could i|should|comment|pourquoi|quand|où|quel(?:le)?s?|est-ce|c[óo]mo|qu[ée]|por qu[ée]|cu[áa]ndo|d[óo]nde|cu[áa]l)(?![\p{L}\p{N}'’])",
    caseSensitive: false,
    unicode: true,
  );

  static final _wanted = RegExp(
    // "Remind me what my name is" asks about the chat, not for a reminder.
    // Commands only, never a bare noun: "the best calendar app" or "who
    // invented the alarm clock" is a question, and keeps its web search.
    // English
    r'(?<![\p{L}\p{N}])(?:remind me(?![\s:,]+(?:what|who|whom|whose|where|which|how|why|of|again|my|our)(?![\p{L}\p{N}]))|wake me|(?:set|add|create|make|start|put|schedule|book|plan) (?:\S+ ){0,3}?(?:alarm|timer|reminder|event|appointment|meeting|countdown)s?\b|(?:to|in|on|into) my (?:calendar|agenda|schedule|diary)|text (?:him|her|them|my|to)\b|send (?:a |an )?(?:text|message|sms|email|e-mail|mail)\b|draft (?:a |an )?(?:message|text|email|e-mail|mail|reply)\b|write (?:a |an )?(?:message|text|email|e-mail|mail) to\b|email (?:him|her|them|my)\b|save (?:it|this|that|the \w+)? ?(?:as|to|in|into) (?:a |an )?(?:file|note|document|csv|markdown)\b|make (?:a |me a |an )(?:file|note|document|csv)\b|create (?:a |an )?(?:file|note|document|csv)\b|export (?:it|this|that)\b'
    // French
    r'|rappelle[- ]moi(?![\s:,]+(?:qui|quoi|quel|quelle|quels|quelles|comment|pourquoi|où|ce qu|mon|ma|mes|notre|nos)(?![\p{L}\p{N}]))|réveille[- ]moi|(?:mets|met|mettre|règle|régler|programme|programmer|ajoute|ajouter|crée|créer|lance|lancer|planifie|planifier) (?:\S+ ){0,3}?(?:alarme|réveil|minuteur|rappel|chrono|rendez-vous|événement|réunion)s?\b|(?:à|dans) mon (?:agenda|calendrier)|envoie (?:un |une )?(?:sms|texto|message|e-?mail|courriel)\b|écris (?:un |une )?(?:message|sms|e-?mail|courriel) à|(?:rédige|prépare) (?:un |une )?(?:brouillon|message|e-?mail|courriel|sms)\b|enregistre (?:le |la |ça |cela )?(?:dans|comme|en) (?:un |une )?(?:fichier|note|document)\b|crée (?:un |une )?(?:fichier|note|document)\b'
    // Spanish
    r'|recuérdame(?![\s:,]+(?:qué|quién|quiénes|cuál|cuáles|cómo|dónde|por qué|mi|mis|nuestro|nuestra)(?![\p{L}\p{N}]))|despiértame|(?:pon|ponme|poner|programa|programar|añade|añadir|crea|crear|inicia|iniciar|agenda|agendar) (?:\S+ ){0,3}?(?:alarma|temporizador|recordatorio|cita|evento|reunión)s?\b|(?:a|en) mi (?:calendario|agenda)|envía (?:un |una )?(?:sms|mensaje|correo|e-?mail)\b|escribe (?:un |una )?(?:mensaje|correo|e-?mail) a\b|(?:redacta|prepara) (?:un |una )?(?:borrador|mensaje|correo|e-?mail)\b|guarda (?:lo |la |esto )?(?:en|como) (?:un |una )?(?:archivo|nota|documento)\b|crea (?:un |una )?(?:archivo|nota|documento)\b)',
    caseSensitive: false,
    unicode: true,
  );

  static const _prepared =
      'Prepared. The user sees a button under your answer and confirms it in '
      'the phone\'s own app: say what you prepared and that they can tap to '
      'confirm. Do not say it is already done.';

  static List<ToolSpec> specs() => const [
    ToolSpec(
      name: 'create_event',
      description:
          'Prepare a calendar event the user confirms in their Calendar app. Use the date and local time in the system prompt to turn "tomorrow at 3" into an exact date-time.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'start': {
            'type': 'string',
            'description': 'Local date-time, e.g. 2026-10-08T15:00',
          },
          'end': {'type': 'string', 'description': 'Optional, after start'},
          'location': {'type': 'string'},
          'notes': {'type': 'string'},
          'all_day': {'type': 'boolean'},
        },
        'required': ['title', 'start'],
      },
    ),
    ToolSpec(
      name: 'set_reminder',
      description:
          'Prepare a reminder at a date and time (a calendar entry with an alert) that the user confirms.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'What to remember'},
          'when': {
            'type': 'string',
            'description': 'Local date-time, e.g. 2026-10-08T09:00',
          },
        },
        'required': ['text', 'when'],
      },
    ),
    ToolSpec(
      name: 'set_alarm',
      description:
          'Prepare an alarm in the Clock app at a 24-hour time, optionally repeating on weekdays.',
      parameters: {
        'type': 'object',
        'properties': {
          'time': {'type': 'string', 'description': '24-hour HH:MM'},
          'label': {'type': 'string'},
          'days': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'e.g. ["mon","tue"]; empty for once',
          },
        },
        'required': ['time'],
      },
    ),
    ToolSpec(
      name: 'set_timer',
      description: 'Prepare a countdown timer in the Clock app.',
      parameters: {
        'type': 'object',
        'properties': {
          'minutes': {'type': 'number'},
          'seconds': {'type': 'number'},
          'label': {'type': 'string'},
        },
      },
    ),
    ToolSpec(
      name: 'draft_message',
      description:
          'Prepare a text message or email draft; the user reviews it and taps Send in their own app. Write the whole message in "body".',
      parameters: {
        'type': 'object',
        'properties': {
          'channel': {
            'type': 'string',
            'enum': ['sms', 'email', 'any'],
          },
          'to': {
            'type': 'string',
            'description': 'Phone number or email address if the user gave one',
          },
          'subject': {'type': 'string'},
          'body': {'type': 'string'},
        },
        'required': ['body'],
      },
    ),
    ToolSpec(
      name: 'save_file',
      description:
          'Save text as a file the user can open or share: a note, a list, a document (Markdown), a table (CSV) or a web page (HTML). Put the complete content in "content".',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'File name'},
          'format': {
            'type': 'string',
            'enum': ['md', 'txt', 'csv', 'html', 'json'],
          },
          'content': {'type': 'string'},
        },
        'required': ['name', 'content'],
      },
    ),
  ];

  /// The tool result for a call: prepared, or what to fix.
  static String prepare(ToolCall call) {
    final action = PhoneAction(call.name, call.args);
    final problem = action.problem;
    if (problem != null) throw FormatException(problem);
    final detail = action.detail;
    return '$_prepared (${action.kind}: ${action.title}'
        '${detail.isEmpty || action.kind == 'save_file' ? '' : ' · ${detail.length > 80 ? '${detail.substring(0, 80)}…' : detail}'})';
  }

  /// A cheap look before decoding a stored run: did it call an action?
  static bool mayHave(String? runJson) =>
      runJson != null && kinds.any((k) => runJson.contains('"$k"'));

  /// The actions a stored answer prepared (its tool trace).
  static List<PhoneAction> fromTrace(List<Map<String, dynamic>> trace) => [
    for (final t in trace)
      if (t['ok'] == true && t['call'] is Map)
        ?_fromCall(Map<String, dynamic>.from(t['call'] as Map)),
  ];

  static PhoneAction? _fromCall(Map<String, dynamic> call) {
    final c = ToolCall.fromJson(call);
    if (!kinds.contains(c.name)) return null;
    final a = PhoneAction(c.name, c.args);
    return a.problem == null ? a : null;
  }

  /// Where made files are kept.
  static Future<Directory> filesDir() async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'made'),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes a save_file action and returns the file.
  static Future<File> writeFile(PhoneAction a) async {
    final file = File(p.join((await filesDir()).path, a.fileName));
    await file.writeAsString('${a.args['content']}', encoding: utf8);
    return file;
  }

  /// Opens the phone's app for [a] (or the share sheet for a file). False
  /// when no app on the phone can do it.
  static Future<bool> launch(PhoneAction a) async {
    if (a.kind == 'save_file') {
      final file = await writeFile(a);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: a.fileName),
      );
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('launch', a.toPlatform()) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

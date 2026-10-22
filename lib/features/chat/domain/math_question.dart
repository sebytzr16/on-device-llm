import '../../tools/calculator.dart';

/// Simple arithmetic asked in words or digits ("what is fifteen plus
/// twenty-seven?", "now double that"), worked out by the app: Qwen3.5 0.8B
/// answered 15 + 27 with "17" and doubled it to "24" (conversation probe,
/// 2026-10-18). Only a question that is nothing but the sum is taken, so
/// "iPhone 15 Plus" or "2024-2025" never are.
abstract final class MathQuestion {
  /// The note for the model, or null when [input] is not plain arithmetic.
  /// [earlier] are the chat's earlier questions, oldest first: "double
  /// that" works on the sum just before it.
  static String? note(String input, {List<String> earlier = const []}) {
    final e = expression(input, earlier: earlier);
    if (e == null) return null;
    try {
      final v = Calculator.evaluate(e);
      final result = Calculator.format(v);
      return 'Worked out exactly by the app: ${_show(e)} = $result. '
          'The answer is $result.';
    } on FormatException {
      return null;
    }
  }

  /// The answer to say aloud ("42 times 2 is 84."), in [input]'s language,
  /// or null when [input] is not plain arithmetic. On a spoken phone turn
  /// it replaces the model's: given the result, Qwen3.5 0.8B still added
  /// "You are from the UK… Your name is James" (phone probe round 3,
  /// 2026-10-18).
  static String? spoken(String input, {List<String> earlier = const []}) {
    final e = expression(input, earlier: earlier);
    if (e == null) return null;
    try {
      final result = Calculator.format(Calculator.evaluate(e));
      final lang = _french.hasMatch(input.toLowerCase())
          ? 'fr'
          : _spanish.hasMatch(input.toLowerCase())
          ? 'es'
          : 'en';
      final w = _said[lang]!;
      var said = e
          .replaceAllMapped(
            RegExp(r'sqrt\(\s*([^)]+?)\s*\)'),
            (m) => '${w['sqrt']} ${m[1]}',
          )
          .replaceAll(RegExp(r'\^\s*2\b'), w['^2']!)
          .replaceAll('^', w['^']!)
          .replaceAll('*', w['*']!)
          .replaceAll('/', w['/']!)
          .replaceAll('+', w['+']!)
          .replaceAllMapped(
            RegExp(r'\((-[\d.]+)\)'),
            (m) => '${w['-']} ${m[1]!.substring(1)}',
          )
          .replaceAll(RegExp(r'(?<=\s)-(?=\s)'), w['-']!)
          .replaceAll(RegExp(r'[()]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (lang == 'fr') said = said.replaceAll(RegExp(r'(?<=\d)\.(?=\d)'), ',');
      final shown = result.startsWith('-')
          ? '${w['-']} ${result.substring(1)}'
          : lang == 'fr'
          ? result.replaceAll('.', ',')
          : result;
      return '$said ${w['is']} $shown.';
    } on FormatException {
      return null;
    }
  }

  static final _french = RegExp(
    r'\b(?:combien|fait|font|fois|moins|divisé|calcule|ça|cela|égal|racine)\b',
    unicode: true,
  );
  static final _spanish = RegExp(
    r'(?:cuánto|cuanto|más|menos|\bpor\b|dividido|calcula|\beso\b|\besto\b)',
    unicode: true,
  );

  static const _said = {
    'en': {
      '+': 'plus',
      '-': 'minus',
      '*': 'times',
      '/': 'divided by',
      '^2': 'squared',
      '^': 'to the power of',
      'sqrt': 'the square root of',
      'is': 'is',
    },
    'fr': {
      '+': 'plus',
      '-': 'moins',
      '*': 'fois',
      '/': 'divisé par',
      '^2': 'au carré',
      '^': 'puissance',
      'sqrt': 'la racine carrée de',
      'is': 'égale',
    },
    'es': {
      '+': 'más',
      '-': 'menos',
      '*': 'por',
      '/': 'dividido entre',
      '^2': 'al cuadrado',
      '^': 'elevado a',
      'sqrt': 'la raíz cuadrada de',
      'is': 'es',
    },
  };

  /// The expression [input] asks for, or null.
  static String? expression(String input, {List<String> earlier = const []}) {
    // "That" is the sum asked just before, when that one was a sum too.
    String? previous;
    for (final q in earlier) {
      previous = _parse(q, previous);
    }
    return _parse(input, previous);
  }

  static String? _parse(String input, String? previous) {
    var t = ' ${_words(input)} ';
    // Operations on the previous result.
    if (previous != null && _back.hasMatch(t)) {
      final p = _value(previous);
      for (final (pattern, make) in _onPrevious) {
        final m = pattern.firstMatch(t);
        if (m != null) {
          t = t.replaceRange(m.start, m.end, ' ${make(p, m)} ');
          break;
        }
      }
    }
    for (final (pattern, op) in _operators) {
      t = t.replaceAll(pattern, ' $op ');
    }
    t = t.replaceAllMapped(
      RegExp(r'\bsquare root of\s*(\(?[\d.]+\)?)'),
      (m) => ' sqrt(${m[1]}) ',
    );
    t = t.replaceAllMapped(
      RegExp(r'([\d.)]+)\s*percent of\s*([\d.(]+)'),
      (m) => ' ${m[1]} / 100 * ${m[2]} ',
    );
    final sum = _sum.firstMatch(t);
    if (sum == null) return null;
    final rest = (t.substring(0, sum.start) + t.substring(sum.end))
        .split(RegExp(r'[\s?!.,]+'))
        .where((w) => w.isNotEmpty);
    if (rest.any((w) => !_filler.contains(w))) return null;
    return sum[0]!.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// [expression]'s result as a number, so a chained question reads
  /// "42 × 2" rather than "(15 + 27) × 2"; bracketed when it cannot be
  /// worked out.
  static String _value(String expression) {
    try {
      final v = Calculator.evaluate(expression);
      final shown = Calculator.format(v);
      return v < 0 ? '($shown)' : shown;
    } on FormatException {
      return '($expression)';
    }
  }

  static String _show(String e) =>
      e.replaceAll('*', '×').replaceAll('/', '÷').replaceAll(' ^ ', '^');

  /// Lower case, number words as digits, hyphens and commas in numbers
  /// gone; a hyphen that is not spaced stays (a range or a date).
  static String _words(String input) {
    final t = input
        .toLowerCase()
        .replaceAll(RegExp(r'(?<=\d),(?=\d{3}\b)'), '')
        .replaceAll(RegExp(r'(?<=[a-z])-(?=[a-z])'), ' ')
        .replaceAll(RegExp(r'[?!,;:¿¡]|\.(?!\d)'), ' ');
    final out = <String>[];
    num? value;
    num group = 0;
    void flush() {
      if (value != null) out.add('${value! + group}');
      value = null;
      group = 0;
    }

    for (final w in t.split(RegExp(r'\s+'))) {
      final small = _units[w] ?? _tens[w];
      if (small != null) {
        value ??= 0;
        group += small;
      } else if (w == 'hundred' && value != null) {
        group = (group == 0 ? 1 : group) * 100;
      } else if (w == 'hundred' && value == null) {
        // "a hundred" / "hundred"
        if (out.isNotEmpty && out.last == 'a') out.removeLast();
        value = 0;
        group = 100;
      } else if ((w == 'thousand' || w == 'million') && value != null) {
        final scale = w == 'thousand' ? 1000 : 1000000;
        value = value! + (group == 0 ? 1 : group) * scale;
        group = 0;
      } else if (w == 'and' && value != null) {
        continue;
      } else {
        flush();
        out.add(w);
      }
    }
    flush();
    return out.join(' ');
  }

  static const _units = {
    'zero': 0,
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
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };
  static const _tens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  static final _back = RegExp(
    r'\b(?:that|it|this|the result|the answer|ça|cela|le résultat|eso|esto|el resultado)\b',
  );

  static final _onPrevious = <(RegExp, String Function(String, RegExpMatch))>[
    (
      RegExp(r'\b(?:double|twice)\s+(?:that|it|this|the result|the answer)\b'),
      (p, _) => '$p * 2',
    ),
    (
      RegExp(r'\btriple\s+(?:that|it|this|the result|the answer)\b'),
      (p, _) => '$p * 3',
    ),
    (
      RegExp(
        r'\bhalf (?:of )?(?:that|it|this|the result|the answer)\b|\bhalve (?:that|it|this)\b',
      ),
      (p, _) => '$p / 2',
    ),
    (
      RegExp(
        r'\bsquare (?:that|it|this|the result)\b|\b(?:that|it|this) squared\b',
      ),
      (p, _) => '$p ^ 2',
    ),
    (
      RegExp(
        r'\b(?:add|plus)\s+([\d.]+)\s+(?:to (?:that|it|this|the result))?',
      ),
      (p, m) => '$p + ${m[1]}',
    ),
    (
      RegExp(
        r'\b(?:subtract|take away|minus)\s+([\d.]+)(?:\s+from (?:that|it|this|the result))?',
      ),
      (p, m) => '$p - ${m[1]}',
    ),
    (
      RegExp(
        r'\b(?:multiply|multiplied)\s+(?:that|it|this|the result)\s+by\s+([\d.]+)',
      ),
      (p, m) => '$p * ${m[1]}',
    ),
    (
      RegExp(
        r'\b(?:divide|divided)\s+(?:that|it|this|the result)\s+by\s+([\d.]+)',
      ),
      (p, m) => '$p / ${m[1]}',
    ),
    (
      RegExp(
        r'\b(?:that|it|this|the result)\s+(?:times|multiplied by)\s+([\d.]+)',
      ),
      (p, m) => '$p * ${m[1]}',
    ),
    (
      RegExp(r'\b(?:that|it|this|the result)\s+(?:divided by|over)\s+([\d.]+)'),
      (p, m) => '$p / ${m[1]}',
    ),
    (
      RegExp(r'\b(?:that|it|this|the result)\s+(?:plus)\s+([\d.]+)'),
      (p, m) => '$p + ${m[1]}',
    ),
    (
      RegExp(r'\b(?:that|it|this|the result)\s+(?:minus)\s+([\d.]+)'),
      (p, m) => '$p - ${m[1]}',
    ),
  ];

  static final _operators = <(RegExp, String)>[
    (RegExp(r'\b(?:to the power of|raised to)\b'), '^'),
    (
      RegExp(
        r'\bmultiplied by\b|\btimes\b|(?<=\d)\s+x\s+(?=\d)|\bfois\b|(?<=\d)\s+por\s+(?=\d)',
      ),
      '*',
    ),
    (
      RegExp(
        r'\bdivided by\b|\bdivisé par\b|\bdividido (?:entre|por)\b|(?<=\d)\s+over\s+(?=\d)',
      ),
      '/',
    ),
    (RegExp(r'\bplus\b|\bmás\b|\bmas\b'), '+'),
    (RegExp(r'\bminus\b|\bmoins\b|\bmenos\b|(?<=\d)\s+-\s+(?=[\d(])'), '-'),
    (RegExp(r'(?<=[\d)])\s+squared\b'), '^ 2'),
    (RegExp(r'(?<=[\d)])\s+cubed\b'), '^ 3'),
  ];

  /// Numbers joined by operators, with brackets and functions.
  static final _sum = RegExp(
    r'(?:sqrt\()?\(*\s*\d+(?:\.\d+)?\s*\)*(?:\s*[-+*/^]\s*(?:sqrt\()?\(*\s*\d+(?:\.\d+)?\s*\)*)+|sqrt\(\s*[\d.]+\s*\)',
  );

  /// Words a plain sum may come with.
  static const _filler = {
    'what',
    'whats',
    "what's",
    'is',
    'are',
    'how',
    'much',
    'calculate',
    'compute',
    'work',
    'out',
    'please',
    'can',
    'could',
    'you',
    'tell',
    'me',
    'equals',
    'equal',
    'the',
    'answer',
    'to',
    'of',
    'now',
    'and',
    'then',
    'so',
    'ok',
    'okay',
    'hey',
    'quick',
    'question',
    'result',
    'sum',
    'combien',
    'font',
    'fait',
    'égal',
    'calcule',
    'cuánto',
    'cuanto',
    'es',
    'son',
    'calcula',
    'wait',
    'um',
    'uh',
    'right',
    'do',
    'does',
    'make',
    // "Thanks. What is two plus two?" (phone probe round 5, 2026-10-18).
    'thanks',
    'thank',
    'great',
    'cool',
    'nice',
    'alright',
    'perfect',
    'merci',
    'gracias',
  };
}

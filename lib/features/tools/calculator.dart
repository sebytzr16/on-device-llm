import 'dart:math' as math;

/// A small arithmetic evaluator for the `calculator` tool: numbers, + - * /
/// % ^, parentheses, unary minus, the usual functions and the constants pi
/// and e. Nothing is executed; the expression is parsed to a value.
class Calculator {
  static const _functions = {
    'sqrt',
    'abs',
    'round',
    'floor',
    'ceil',
    'ln',
    'log',
    'log10',
    'log2',
    'exp',
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'min',
    'max',
    'pow',
  };

  /// Evaluates [expression]; throws [FormatException] with a readable reason.
  static double evaluate(String expression) {
    final tokens = _tokenize(expression);
    if (tokens.isEmpty) throw const FormatException('Empty expression.');
    final parser = _Parser(tokens);
    final v = parser.parseExpression();
    if (parser.index != tokens.length) {
      throw FormatException('Unexpected "${tokens[parser.index]}".');
    }
    if (v.isNaN) throw const FormatException('The result is undefined.');
    if (v.isInfinite) throw const FormatException('Division by zero.');
    return v;
  }

  /// A value as a person would write it: integers without ".0", otherwise
  /// up to 10 significant digits without trailing zeros.
  static String format(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    var s = v.toStringAsPrecision(10);
    if (s.contains('e')) return s;
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  static List<String> _tokenize(String s) {
    final out = <String>[];
    var i = 0;
    // Unicode operators people paste from documents.
    s = s.replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-');
    // Thousands separators ("1,200,000") go; argument commas stay.
    final grouped = RegExp(r'(\d),(\d{3})(?!\d)');
    while (grouped.hasMatch(s)) {
      s = s.replaceAllMapped(grouped, (m) => '${m[1]}${m[2]}');
    }
    while (i < s.length) {
      final c = s[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (RegExp(r'[0-9.]').hasMatch(c)) {
        final m = RegExp(
          r'[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?',
        ).matchAsPrefix(s, i);
        if (m == null) {
          throw FormatException('Bad number at "${s.substring(i)}".');
        }
        out.add(m.group(0)!);
        i = m.end;
        continue;
      }
      if (RegExp(r'[a-zA-Z_]').hasMatch(c)) {
        final m = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*').matchAsPrefix(s, i)!;
        out.add(m.group(0)!.toLowerCase());
        i = m.end;
        continue;
      }
      if ('+-*/%^(),'.contains(c)) {
        out.add(c);
        i++;
        continue;
      }
      throw FormatException('Unknown character "$c".');
    }
    return out;
  }
}

class _Parser {
  final List<String> t;
  int index = 0;
  _Parser(this.t);

  String? get peek => index < t.length ? t[index] : null;
  String next() => t[index++];

  double parseExpression() {
    var v = parseTerm();
    while (peek == '+' || peek == '-') {
      final op = next();
      final r = parseTerm();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double parseTerm() {
    var v = parseFactor();
    while (peek == '*' || peek == '/' || peek == '%') {
      final op = next();
      final r = parseFactor();
      v = switch (op) {
        '*' => v * r,
        '/' => r == 0 ? double.infinity : v / r,
        _ => r == 0 ? double.nan : v % r,
      };
    }
    return v;
  }

  double parseFactor() {
    final base = parseUnary();
    if (peek == '^') {
      next();
      // Right-associative: 2^3^2 = 2^9.
      return math.pow(base, parseFactor()).toDouble();
    }
    return base;
  }

  double parseUnary() {
    if (peek == '-') {
      next();
      return -parseUnary();
    }
    if (peek == '+') {
      next();
      return parseUnary();
    }
    return parsePrimary();
  }

  double parsePrimary() {
    final tok = peek;
    if (tok == null) throw const FormatException('Expression ends early.');
    if (tok == '(') {
      next();
      final v = parseExpression();
      if (peek != ')') throw const FormatException('Missing ")".');
      next();
      return v;
    }
    final n = double.tryParse(tok);
    if (n != null) {
      next();
      return n;
    }
    if (tok == 'pi') {
      next();
      return math.pi;
    }
    if (tok == 'e') {
      next();
      return math.e;
    }
    if (Calculator._functions.contains(tok)) {
      next();
      if (peek != '(') throw FormatException('$tok needs parentheses.');
      next();
      final args = <double>[parseExpression()];
      while (peek == ',') {
        next();
        args.add(parseExpression());
      }
      if (peek != ')') throw const FormatException('Missing ")".');
      next();
      return _apply(tok, args);
    }
    throw FormatException('Unknown name "$tok".');
  }

  static double _apply(String f, List<double> a) {
    double one() {
      if (a.length != 1) throw FormatException('$f takes one argument.');
      return a.first;
    }

    double two(int i) {
      if (a.length != 2) throw FormatException('$f takes two arguments.');
      return a[i];
    }

    return switch (f) {
      'sqrt' => math.sqrt(one()),
      'abs' => one().abs(),
      'round' => one().roundToDouble(),
      'floor' => one().floorToDouble(),
      'ceil' => one().ceilToDouble(),
      'ln' => math.log(one()),
      'log' || 'log10' => math.log(one()) / math.ln10,
      'log2' => math.log(one()) / math.ln2,
      'exp' => math.exp(one()),
      'sin' => math.sin(one()),
      'cos' => math.cos(one()),
      'tan' => math.tan(one()),
      'asin' => math.asin(one()),
      'acos' => math.acos(one()),
      'atan' => math.atan(one()),
      'min' => a.reduce(math.min),
      'max' => a.reduce(math.max),
      'pow' => math.pow(two(0), two(1)).toDouble(),
      _ => throw FormatException('Unknown function $f.'),
    };
  }
}

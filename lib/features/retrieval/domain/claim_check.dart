import 'dart:typed_data';

import 'evidence.dart';
import 'claim_passages.dart';

/// What the sentence-level check found for one answer sentence.
enum ClaimStatus {
  /// An identified passage matches the words, figures and qualifiers.
  supported,

  /// Related evidence exists, but no passage establishes the proposition.
  uncertain,

  /// A related passage explicitly disagrees with the claim.
  conflicting,

  /// No source is about what the sentence says (words and meaning both
  /// far): it most likely came from the model's memory.
  offSource,

  /// Names or years that no source contains, in a sentence that is
  /// otherwise on topic ("built for the 1900 Olympic Games").
  novelDetails,
}

class ClaimVerdict {
  final String sentence;
  final ClaimStatus status;

  /// Source (0-based) that shares most words, when one shares enough.
  final int? source;
  final double share;
  final double? cosine;
  final List<String> details;
  final String? span;
  final ClaimConflict? conflict;

  /// The source-check model's P(yes) that [span] states the sentence,
  /// when it was asked.
  final double? support;
  const ClaimVerdict(
    this.sentence,
    this.status, {
    this.source,
    this.share = 0,
    this.cosine,
    this.details = const [],
    this.span,
    this.conflict,
    this.support,
  });

  Map<String, dynamic> toJson() => {
    'sentence': sentence,
    'status': status.name,
    'source': ?source,
    'share': double.parse(share.toStringAsFixed(2)),
    'cosine': ?(cosine == null
        ? null
        : double.parse(cosine!.toStringAsFixed(3))),
    if (details.isNotEmpty) 'details': details,
    'span': ?span,
    'conflict': ?conflict?.name,
    'support': ?(support == null
        ? null
        : double.parse(support!.toStringAsFixed(3))),
  };
}

/// Sentence-level check of an answer written from sources (the chosen design,
/// 2026-10-07). Mechanical, not a truth test: embeddings measure topic, not
/// entailment (measured with EmbeddingGemma 2: a false "best season is
/// midsummer" scored 0.81 against the aurora passage, the true paraphrase
/// 0.82), so meaning is used only to tell on-topic sentences from ones no
/// source talks about (<= 0.6 for unrelated passages, >= 0.73 related).
/// Names and years absent from every source are flagged on their own.
class ClaimCheck {
  // A sentence starts with a capital: "405 g/14.3 oz. with battery…" is
  // one sentence (app quality probe, 2026-10-19).
  static final _sentence = RegExp(
    r'(?<=[.!?])\s+(?=[\p{Lu}*"“(¿¡])',
    unicode: true,
  );
  static final _marker = RegExp(r'\[\d+(?:\s*,\s*\d+)*\]');
  // "The provided sources do not contain information about…" says what the
  // pages lack, nothing about the world; the notice quoted it as "not
  // backed by the sources" (app quality probe, 2026-10-19).
  static final _sourcesLack = RegExp(
    r"(?:sources?|pages?|search results?|results?|articles?|provided (?:information|text|context)|documents?)\s+(?:i (?:found|read)\s+)?(?:do(?:es)?\s*n[o']t|did\s*n[o']t|don['’]t|doesn['’]t)\s+(?:seem to\s+)?(?:contain|include|mention|say|provide|state|give|list|specify|cover|have)|^(?:i (?:could ?n['’]?o?t|can(?:no|['’])t|was unable to) find|there is no (?:information|mention))|sources? ne (?:contien|mentionn|pr[ée]cis|donn|dis|indiqu|pr[ée]sent)|fuentes? no (?:contien|mencion|incluy|dic|indic|especific|proporcion)",
    caseSensitive: false,
  );

  /// The answer says the pages lack what was asked ("The provided source
  /// does not contain information about…").
  static bool saysSourcesLack(String answer) =>
      _sourcesLack.hasMatch(answer.replaceAll(RegExp(r'[*_`]'), '').trim());

  // Advice to the user ("You should check your preferred retailer…") and a
  // summary of the results ("The search results indicate that pricing is
  // specific to regions") state no fact a page could back; with no figure
  // in them they are left out (the tester's phone chat, 2026-10-19).
  static final _noClaim = RegExp(
    r"^(?:you (?:should|can|could|may|might|will want|['’]ll want|need to)|i (?:would )?(?:recommend|suggest)|(?:please )?(?:check|consider|visit|contact)\b|(?:it(?:['’]s| is) (?:best|a good idea|worth|recommended))|(?:the )?(?:search )?(?:results?|sources?|pages?) (?:indicate|suggest|show|say|mention|note)|vous (?:devriez|pouvez)|je (?:vous )?(?:recommande|conseille|sugg[èe]re)|(?:v[ée]rifiez|consultez)\b|(?:les )?(?:r[ée]sultats|sources) (?:indiquent|montrent|sugg[èe]rent)|deber[íi]as|(?:te|le) recomiendo|(?:consulta|verifica)\b|(?:los )?(?:resultados|fuentes) (?:indican|muestran|sugieren))",
    caseSensitive: false,
  );
  static final _digit = RegExp(r'\d');
  // A bold line ("**DOJ List Shows Unreliability [3]**") is a heading and a
  // bold lead ("**The Defense:** Acton's brother…") a label: the model's
  // own summary words. The news probe (2026-10-20) flagged "Unreliability",
  // "Defense" and "Briefing" as names no source mentions on every briefing.
  static final _boldLine = RegExp(
    r'^\*\*[^*]+\*\*\s*(?:\[\d+(?:\s*,\s*\d+)*\])?\s*:?\s*$',
  );
  static final _boldLabel = RegExp(r'^\*\*[^*]{1,60}?(?::\*\*|\*\*\s*:)\s*');
  // An exclamation ("Blue is such a fantastic color… vibrant! 💙") or a
  // question back ("Would you like me to look…?") is talk, not a fact
  // (the tester's phone chat, 2026-10-19).
  static final _talk = RegExp(r'[!?¡¿][^\p{L}\d]*$', unicode: true);

  // Currency codes are units, not names ("$3,265 CAD" where the page has
  // "$3,265").
  static const _currencies = {
    'cad',
    'usd',
    'eur',
    'gbp',
    'aud',
    'nzd',
    'jpy',
    'chf',
    'cny',
    'inr',
    'mxn',
    'sek',
    'nok',
    'dkk',
    'krw',
    'brl',
    'hkd',
    'sgd',
    'zar',
  };
  static final _capital = RegExp(
    r"(?<![\p{L}\d'’-])\p{Lu}[\p{L}’'-]{2,}",
    unicode: true,
  );
  static final _year = RegExp(r'\b(1[5-9]\d\d|20\d\d)\b');

  /// Fewest content words a sentence needs before it is checked.
  static const minWords = 4;

  /// Share of a sentence's content words one source must hold.
  static const supportShare = 0.5;

  /// Below this cosine to every passage a sentence is off-source.
  static const offTopicCosine = 0.65;

  /// The checkable sentences of [answer]: prose only (no code, tables,
  /// headings), citation markers and emphasis removed.
  static List<String> sentences(String answer) {
    final out = <String>[];
    var code = false;
    for (final line in answer.split('\n')) {
      final t = line.trimLeft();
      if (t.startsWith('```')) {
        code = !code;
        continue;
      }
      if (code || t.startsWith('|') || t.startsWith('#') || t.isEmpty) {
        continue;
      }
      final item = t.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s+'), '');
      if (_boldLine.hasMatch(item)) continue;
      final prose = item.replaceFirst(_boldLabel, '');
      for (final s in prose.split(_sentence)) {
        final clean = s
            .replaceAll(_marker, '')
            .replaceAll(RegExp(r'[*_`]'), '')
            .trim();
        // A lead-in ("Voici d'autres détails pertinents :") states nothing
        // (app quality probe, 2026-10-19).
        if (clean.endsWith(':') || _sourcesLack.hasMatch(clean)) continue;
        if ((_noClaim.hasMatch(clean) || _talk.hasMatch(clean)) &&
            !_digit.hasMatch(clean)) {
          continue;
        }
        if (EvidenceRanker.terms(clean).toSet().length >= minWords) {
          out.add(clean);
        }
      }
    }
    return out;
  }

  // How sources write what an answer spells out (a spoken answer says
  // "October 5" and "24 degrees Celsius" where the page has "Oct 5" and
  // "24°C"; conversation probe 2026-10-07).
  static final Map<String, RegExp> _shortForm = {
    for (final (name, short) in const [
      ('january', 'jan'),
      ('february', 'feb'),
      ('march', 'mar'),
      ('april', 'apr'),
      ('june', 'jun'),
      ('july', 'jul'),
      ('august', 'aug'),
      ('september', 'sept?'),
      ('october', 'oct'),
      ('november', 'nov'),
      ('december', 'dec'),
      ('monday', 'mon'),
      ('tuesday', 'tue|tues'),
      ('thursday', 'thu|thur|thurs'),
      ('friday', 'fri'),
    ])
      name: RegExp('(?<![a-z])(?:$short)\\.?(?![a-z])'),
    'celsius': RegExp(r'°\s*c(?![a-z])|\d\s*c(?![a-z])'),
    'fahrenheit': RegExp(r'°\s*f(?![a-z])|\d\s*f(?![a-z])'),
  };

  /// Names (capitalised words not opening the sentence or a clause) and
  /// years in [sentence] that appear in none of [sources].
  static List<String> novelDetails(String sentence, List<String> sources) {
    final haystack = sources.join('\n').toLowerCase();
    final out = <String>{};
    for (final m in _capital.allMatches(sentence)) {
      final before = sentence.substring(0, m.start).trimRight();
      if (before.isEmpty || RegExp(r'[.:;!?(\-–—"“]$').hasMatch(before)) {
        continue;
      }
      // "Eiffel's" is Eiffel (support-check tests, 2026-10-18).
      final word = m[0]!
          .replaceAll(RegExp(r"[’']s$"), '')
          .replaceAll(RegExp(r"[’'-]+$"), '');
      if (haystack.contains(word.toLowerCase())) continue;
      if (_currencies.contains(word.toLowerCase())) continue;
      final short = _shortForm[word.toLowerCase()];
      if (short != null && short.hasMatch(haystack)) continue;
      out.add(word);
    }
    for (final m in _year.allMatches(sentence)) {
      if (!haystack.contains(m[0]!)) out.add(m[0]!);
    }
    return out.toList();
  }

  /// Lexical verdicts; [cosines] (one per sentence: best cosine to any
  /// source passage, null when unknown) adds the meaning check.
  static List<ClaimVerdict> check(
    List<String> sentences,
    List<String> sources, {
    List<double?>? cosines,
  }) {
    final bags = [for (final s in sources) EvidenceRanker.terms(s).toSet()];
    final prepared = ClaimPassages.prepare(sources);
    final out = <ClaimVerdict>[];
    for (var i = 0; i < sentences.length; i++) {
      final s = sentences[i];
      final words = EvidenceRanker.terms(s).toSet();
      int? best;
      var share = 0.0;
      for (var k = 0; k < bags.length; k++) {
        final v = words.isEmpty
            ? 0.0
            : words.intersection(bags[k]).length / words.length;
        if (v > share) {
          share = v;
          best = k;
        }
      }
      final cosine = cosines == null || i >= cosines.length ? null : cosines[i];
      final details = novelDetails(s, sources);
      final match = ClaimPassages.best(s, prepared);
      final ClaimStatus status;
      if (match?.conflict != null) {
        status = ClaimStatus.conflicting;
      } else if (details.isNotEmpty) {
        status = ClaimStatus.novelDetails;
      } else if (match?.states == true) {
        status = ClaimStatus.supported;
      } else if (share < 0.25 && (cosine == null || cosine < offTopicCosine)) {
        // Far in meaning, or (without vectors) barely a word in common.
        status = ClaimStatus.offSource;
      } else {
        status = ClaimStatus.uncertain;
      }
      out.add(
        ClaimVerdict(
          s,
          status,
          source: match?.source ?? (share >= supportShare ? best : null),
          share: share,
          cosine: cosine,
          details: details,
          span: match?.span,
          conflict: match?.conflict,
        ),
      );
    }
    return out;
  }

  /// Best cosine of [sentence] to any of [passages].
  static double best(Float32List sentence, List<Float32List> passages) {
    var top = -1.0;
    for (final p in passages) {
      var dot = 0.0;
      final n = p.length < sentence.length ? p.length : sentence.length;
      for (var i = 0; i < n; i++) {
        dot += sentence[i] * p[i];
      }
      if (dot > top) top = dot;
    }
    return top;
  }
}

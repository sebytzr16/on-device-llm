import '../retrieval/domain/evidence.dart';
import '../retrieval/domain/evidence_audit.dart';
import '../retrieval/domain/subject_terms.dart';
import 'goal_specialization.dart';

/// What the checker found wrong with a research step or the report.
enum GoalCheckKind {
  /// Names a neighbouring model or version instead of the goal's subject.
  drift,

  /// About something else entirely: drift and none of the goal's names.
  offTarget,

  /// The step had no sources: the answer can only come from memory.
  noSources,

  /// Sources were given but nothing is cited.
  noCitations,

  /// Citation numbers with no such source.
  badCitations,

  /// Figures that appear in no source (or, for the report, no finding).
  figures,
  unsupportedClaims,

  /// Figures no source states that were left out of the text, with the
  /// sentence or table cell holding them; the rest was kept. A note, not a
  /// problem left to fix.
  droppedFigures,

  /// The model asked the user for sources or information: a goal runs on
  /// its own.
  askedUser,

  /// The model's reasoning ran on into the answer and was removed (a small
  /// model whose thinking budget ran out kept "thinking aloud").
  leak,

  /// The step was researched a second time after a failed check.
  retried,

  /// The report was rewritten once to fix what the checker found.
  revised,
}

class GoalCheck {
  final GoalCheckKind kind;

  /// Names, numbers or figures the check is about.
  final String detail;
  const GoalCheck(this.kind, [this.detail = '']);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (detail.isNotEmpty) 'detail': detail,
  };

  static GoalCheck? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = GoalCheckKind.values.asNameMap()[j['kind']];
    return kind == null ? null : GoalCheck(kind, j['detail'] as String? ?? '');
  }

  static List<GoalCheck> listFromJson(Object? j) => [
    if (j is List)
      for (final e in j) ?GoalCheck.fromJson(e),
  ];

  /// Problems that make a step's findings unusable for the report. Figures
  /// no source states are not among them: they are left out of the
  /// findings ([GoalChecker.findings]) and the step's other facts stay (one
  /// unsupported number used to drop a whole step of the tester's camera
  /// Goal, 2026-09-28).
  bool get excludes => const {
    GoalCheckKind.offTarget,
    GoalCheckKind.drift,
    GoalCheckKind.noSources,
    GoalCheckKind.noCitations,
    GoalCheckKind.badCitations,
    GoalCheckKind.askedUser,
  }.contains(kind);

  /// Problems worth one rewrite of the report.
  bool get fixable => const {
    GoalCheckKind.noSources,
    GoalCheckKind.drift,
    GoalCheckKind.badCitations,
    GoalCheckKind.noCitations,
    GoalCheckKind.figures,
    GoalCheckKind.unsupportedClaims,
    GoalCheckKind.askedUser,
    GoalCheckKind.leak,
  }.contains(kind);

  @override
  bool operator ==(Object other) =>
      other is GoalCheck && other.kind == kind && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);
}

/// The rules every phase of a goal runs under — the guardrails small
/// models need to stay on the goal. Seen on the tester's phone (2026-09-24,
/// Nikon Z30 vs Sony ZV-E10, several models): steps researched the "ZV-E10
/// II" and the report mixed the two; a step asked the user to "provide
/// sources"; the planner asked "which options are worth comparing" of two
/// named cameras; the report claimed prices "are very similar" after the
/// price step found nothing, and cited nothing at all.
///
/// The rules are short on purpose: a small model follows five plain lines
/// better than twenty. They are written for the model (English; the model
/// is told to write in the goal's language).
class GoalRules {
  /// The user's own rules, one per line (bullets and numbering dropped).
  static List<String> userLines(String rules) => [
    for (final line in rules.split(RegExp(r'[\n;]')))
      if (line
          .trim()
          .replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), '')
          .isNotEmpty)
        line.trim().replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), ''),
  ];

  static final _continuation = RegExp(
    r'^(?:including|incl\.?|especially|such as|like|e\.g\.|i\.e\.|with|without|which|that|where|y compris|notamment|comme|avec|sans|incluyendo|como|con|sin)\b',
    caseSensitive: false,
  );

  /// Success criteria as separate requirements: one per line or ";", and a
  /// single line listing three or more short items with commas is split
  /// into them ("Specifications, in what one is better, best use cases"
  /// was one requirement, so the review could only call all of it met or
  /// none, and "not covered" could not say which part was missing). A
  /// line whose parts read as one requirement ("price, including tax")
  /// stays whole.
  static List<String> criteriaLines(String criteria) {
    final lines = userLines(criteria);
    if (lines.length != 1 || RegExp(r'\d,\d').hasMatch(lines.single)) {
      return lines;
    }
    final parts = [
      for (final p in lines.single.split(','))
        p
            .trim()
            .replaceFirst(
              RegExp(r'^(?:and|or|et|ou|y|o)\s+', caseSensitive: false),
              '',
            )
            .replaceFirst(RegExp(r'[.]+$'), '')
            .trim(),
    ];
    int words(String s) => s.split(RegExp(r'\s+')).length;
    if (parts.length < 3 ||
        parts.any((p) => p.isEmpty || words(p) > 12) ||
        parts.skip(1).any(_continuation.hasMatch)) {
      return lines;
    }
    return [for (final p in parts) '${p[0].toUpperCase()}${p.substring(1)}'];
  }

  /// The rules block for a phase. [phase] words the evidence rule for
  /// planning (no sources yet), a step, or the report.
  static String block({
    required List<String> terms,
    required String userRules,
    required String today,
    GoalSpecialization kind = GoalSpecialization.general,
    GoalRulePhase phase = GoalRulePhase.step,
  }) {
    final b = StringBuffer('Rules for this goal (follow every one):\n');
    var n = 0;
    void rule(String text) => b.writeln('${++n}. $text');
    if (terms.isNotEmpty) {
      rule(
        'The goal is about exactly: ${terms.map((t) => '"$t"').join(', ')}. '
        'Write these names exactly as given. Never replace them with a similar '
        'name: not a newer or older model, not another generation (such as a '
        '"II" or "Mark II" version), not a different number, product, person '
        'or place.',
      );
    }
    switch (phase) {
      case GoalRulePhase.plan:
        rule(
          'Each question must name the subject exactly and ask one thing a '
          'web search can answer. When the goal already names what to compare, '
          'do not ask which options exist: ask about each named option.',
        );
      case GoalRulePhase.step:
        rule(
          'Use only facts the sources state, each with its source number like '
          '[2]. Nothing from memory.',
        );
        rule(
          'Ignore any source about something else (another model, version or '
          'product). If the sources do not answer, say in one sentence what '
          'is missing. Never ask the user for sources or information.',
        );
      case GoalRulePhase.report:
        rule(
          'Use only the findings, keeping their citations exactly as written '
          'like [3]. A step marked NOT ESTABLISHED gives no facts: say it is '
          'unknown; never guess or generalise over it.',
        );
    }
    rule(
      'Copy numbers, dates, prices and units exactly as the source gives '
      'them. When sources disagree, give both with their citations.',
    );
    rule(
      'No filler, no advice the goal did not ask for; do not repeat these '
      'rules or describe the sources and how they were retrieved.',
    );
    if (kind == GoalSpecialization.product && phase != GoalRulePhase.plan) {
      rule(
        'Every specification, price and rating belongs to the product the '
        'source names; never move a figure from one product to another.',
      );
    }
    final own = userLines(userRules);
    if (own.isNotEmpty) {
      b.writeln('Rules from the user (they come first when rules conflict):');
      for (final r in own) {
        b.writeln('- $r');
      }
    }
    b.write('Today is $today.');
    return b.toString();
  }
}

enum GoalRulePhase { plan, step, report }

/// Mechanical checks of what the model wrote: the parts of the rules a
/// program can verify. Checked answers are also cleaned of the chatter
/// small models add (meta talk about the sources, requests to the user).
class GoalChecker {
  static final _asksUser = RegExp(
    r'''(?:please|kindly)\s+(?:provide|share|send|give|clarify|specify|let me know)|(?:could|can|would) you (?:please )?(?:provide|share|clarify|specify|send)|if you (?:have|can provide|could provide|can share)|provide (?:additional|more|other|specific) (?:sources|information|details|data)|let me know if you''',
    caseSensitive: false,
  );

  /// Sentences about the prompt instead of the subject: "The sources are
  /// untrusted text", "They were retrieved on 2026-09-24 at 18:50 UTC",
  /// "Note on sources:", "the structured data provided".
  static final _meta = RegExp(
    r'''untrusted (?:text|sources)|(?:were|was) retrieved (?:on|at)|retrieval (?:time|date)s?|note on sources|structured data (?:provided|used)|(?:provided|given|available) (?:structured )?(?:source material|search results) (?:do|does)|as an ai''',
    caseSensitive: false,
  );

  static final _citation = RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]');

  static Set<int> citations(String text) => {
    for (final m in _citation.allMatches(text))
      for (final n in m[1]!.split(',')) int.parse(n.trim()),
  };

  /// Lines where a small model reasons aloud instead of answering, or
  /// echoes the prompt: "Wait, I need to check…", "Thinking Process:",
  /// "Constraint Checklist", "**Question:** …", "[1] Title — https://…
  /// (read 2026-…)" (all seen in Qwen3.5 0.8B goal runs on the phone).
  static final _leakLine = RegExp(
    r'''^\s*(?:[*_#>\-]\s*)*(?:\*\*)?(?:wait[,.!]|hmm[,.]|let me |let's (?:check|see|look|re-?read|verify)|i need to |i should |i must |i will (?:now )?(?:check|extract|look|verify|write)|okay[,.] (?:so|let|i)|ok[,.] (?:so|let|i)|first,? i |thinking process|constraint checklist|confidence score|self-correction|double-check|drafting|re-?reading|analy[sz]e the (?:request|question|sources|goal)|the user (?:wants|asks|is asking)|the prompt (?:says|asks|provides))''',
    caseSensitive: false,
  );
  static final _echoLine = RegExp(
    r'''^\s*(?:\*\*)?(?:question|goal|success criteria|rules for this goal)(?:\*\*)?\s*:|^\s*\[\d+\]\s.{3,200}\s[—-]\s+https?://\S+\s+\((?:read|search snippet|news story)''',
    caseSensitive: false,
  );
  static final _answerLabel = RegExp(
    r'^\s*(?:\*\*)?(?:final )?answer(?:\*\*)?\s*:\s*(?:\*\*)?\s*',
    caseSensitive: false,
  );

  /// Whether [text] has reasoning or prompt echo that [clean] removes.
  static bool leaked(String text) => text
      .split('\n')
      .any((l) => _leakLine.hasMatch(l) || _echoLine.hasMatch(l));

  /// [text] without reasoning run on into the answer, prompt echoes, meta
  /// talk about the sources, requests to the user, and leftover tool calls.
  static String clean(String text) {
    final lines = <String>[];
    // A block of reasoning ends at the first blank line or heading.
    var inLeak = false;
    for (final raw in text.split('\n')) {
      var line = raw;
      // Reasoning runs on for a few lines; a prompt echo is one line.
      if (_leakLine.hasMatch(line)) {
        inLeak = true;
        continue;
      }
      if (_echoLine.hasMatch(line)) continue;
      if (inLeak) {
        final boundary =
            line.trim().isEmpty ||
            _answerLabel.hasMatch(line) ||
            RegExp(r'^\s*(?:#|\||[-*] \*\*)').hasMatch(line);
        if (!boundary) continue;
        inLeak = false;
      }
      line = line.replaceFirst(_answerLabel, '');
      final sentences = line.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z\[(])'));
      final kept = [
        for (final s in sentences)
          if (!_meta.hasMatch(s) && !_asksUser.hasMatch(s)) s,
      ];
      if (kept.isEmpty && line.trim().isNotEmpty) continue;
      lines.add(kept.join(' '));
    }
    return lines
        .join('\n')
        .replaceAll(
          RegExp(
            r'''<(function|invoke)\s+name\s*=[\s\S]*?(?:</\1>|$)|<function=[\s\S]*?(?:</function>|$)''',
          ),
          '',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Checks of one research step's answer.
  static List<GoalCheck> step(
    String answer, {
    required SubjectTerms subject,
    required String allowed,
    required List<String> evidence,
    required int sources,
    bool requireSources = true,
  }) {
    final out = <GoalCheck>[];
    if (sources == 0 && requireSources) {
      out.add(const GoalCheck(GoalCheckKind.noSources));
    }
    final drift = subject.drift(answer, allowed: allowed);
    if (drift.isNotEmpty) {
      out.add(
        GoalCheck(
          subject.mentionsAny(answer)
              ? GoalCheckKind.drift
              : GoalCheckKind.offTarget,
          drift.take(4).join(', '),
        ),
      );
    }
    if (sources > 0) {
      final cited = citations(answer);
      if (cited.isEmpty) {
        out.add(const GoalCheck(GoalCheckKind.noCitations));
      }
      final audit = EvidenceAudit.check(answer, evidence);
      if (audit.unsupportedClaims.isNotEmpty) {
        out.add(
          GoalCheck(
            GoalCheckKind.unsupportedClaims,
            audit.unsupportedClaims.join(', '),
          ),
        );
      }
      if (audit.invalidCitations.isNotEmpty) {
        out.add(
          GoalCheck(
            GoalCheckKind.badCitations,
            audit.invalidCitations.join(', '),
          ),
        );
      }
      final figures = EvidenceRanker.unsupportedFigures(answer, evidence);
      final missing = {...figures, ...audit.unsupportedFigures};
      if (missing.isNotEmpty) {
        out.add(GoalCheck(GoalCheckKind.figures, missing.take(5).join(', ')));
      }
    }
    if (_asksUser.hasMatch(answer)) {
      out.add(const GoalCheck(GoalCheckKind.askedUser));
    }
    return out;
  }

  /// Sentence or claim units, as [EvidenceAudit] cuts them: a citation after
  /// the full stop stays with its claim.
  static final _units = RegExp(r'(?<=[.!?])\s+(?=[\p{L}*])', unicode: true);

  /// [answer] without the figures no source states: a table cell holding
  /// one is emptied ("—"), a sentence holding one is left out; the rest
  /// stays. A cited claim (a table row is one) is checked against the
  /// sources it cites, as [EvidenceAudit] does, an uncited one against all
  /// of them. For a report, [findings] is what it was written from: a
  /// figure must be there too, and an uncited claim is checked against the
  /// findings only. Returns the text and the figures left out.
  static (String, List<String>) withoutUnsupported(
    String answer,
    List<String> evidence, {
    String? findings,
  }) {
    final removed = <String>{};
    List<String> unsupported(String unit, Set<int> refs) {
      final text = unit.replaceAll(_citation, ' ');
      final cited = [
        for (final n in refs)
          if (n > 0 && n <= evidence.length) evidence[n - 1],
      ];
      return {
        if (findings == null || cited.isNotEmpty)
          ...EvidenceRanker.unsupportedFigures(
            text,
            cited.isEmpty ? evidence : cited,
          ),
        if (findings != null)
          ...EvidenceRanker.unsupportedFigures(text, [findings]),
      }.toList();
    }

    final out = <String>[];
    for (final line in answer.split('\n')) {
      if (line.trim().startsWith('|')) {
        final cells = line.split('|');
        final row = citations(line);
        var changed = false;
        for (var i = 0; i < cells.length; i++) {
          final bad = unsupported(cells[i], row);
          if (bad.isEmpty) continue;
          removed.addAll(bad);
          cells[i] = ' — ';
          changed = true;
        }
        out.add(changed ? cells.join('|') : line);
        continue;
      }
      final kept = <String>[];
      for (final unit in line.split(_units)) {
        final bad = unsupported(unit, citations(unit));
        if (bad.isEmpty) {
          kept.add(unit);
        } else {
          removed.addAll(bad);
        }
      }
      if (kept.isEmpty && line.trim().isNotEmpty) continue;
      out.add(kept.join(' '));
    }
    return (
      out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim(),
      removed.toList(),
    );
  }

  /// A research step's answer made usable, and its checks: figures no
  /// source states are left out first ([withoutUnsupported]; not for a
  /// math goal, whose figures are computed), so the step keeps its other
  /// facts, and what was left out is the `droppedFigures` note.
  static (String, List<GoalCheck>) findings(
    String answer, {
    required SubjectTerms subject,
    required String allowed,
    required List<String> evidence,
    bool requireSources = true,
    bool dropUnsupported = true,
  }) {
    final (text, removed) = dropUnsupported && evidence.isNotEmpty
        ? withoutUnsupported(answer, evidence)
        : (answer, const <String>[]);
    final checks = step(
      text,
      subject: subject,
      allowed: allowed,
      evidence: evidence,
      sources: evidence.length,
      requireSources: requireSources,
    );
    return (
      text,
      [
        ...checks,
        if (removed.isNotEmpty)
          GoalCheck(GoalCheckKind.droppedFigures, removed.take(5).join(', ')),
      ],
    );
  }

  /// Checks of the report against the findings it was written from.
  static List<GoalCheck> report(
    String report, {
    required SubjectTerms subject,
    required String allowed,
    required String findings,
    required int sources,
    List<String> evidence = const [],
  }) {
    final out = <GoalCheck>[];
    final drift = subject.drift(report, allowed: allowed);
    if (drift.isNotEmpty) {
      out.add(GoalCheck(GoalCheckKind.drift, drift.take(4).join(', ')));
    }
    final cited = citations(report);
    if (sources > 0 && cited.isEmpty) {
      out.add(const GoalCheck(GoalCheckKind.noCitations));
    }
    final bogus = cited.where((n) => n < 1 || n > sources).toList()..sort();
    if (bogus.isNotEmpty) {
      out.add(GoalCheck(GoalCheckKind.badCitations, bogus.join(', ')));
    }
    final figures = EvidenceRanker.unsupportedFigures(report, [findings]);
    final citedFigures = evidence.isEmpty
        ? const <String>[]
        : EvidenceAudit.check(report, evidence).unsupportedFigures;
    if (evidence.isNotEmpty) {
      final claims = EvidenceAudit.check(report, evidence).unsupportedClaims;
      if (claims.isNotEmpty) {
        out.add(GoalCheck(GoalCheckKind.unsupportedClaims, claims.join(', ')));
      }
    }
    final missing = {...figures, ...citedFigures};
    if (missing.isNotEmpty) {
      out.add(GoalCheck(GoalCheckKind.figures, missing.take(6).join(', ')));
    }
    if (_asksUser.hasMatch(report)) {
      out.add(const GoalCheck(GoalCheckKind.askedUser));
    }
    return out;
  }

  /// What a second attempt must fix, for the model.
  static String fixes(List<GoalCheck> checks, SubjectTerms subject) {
    final names = subject.terms.map((t) => '"$t"').join(', ');
    final b = StringBuffer();
    for (final c in checks) {
      final line = switch (c.kind) {
        GoalCheckKind.drift || GoalCheckKind.offTarget =>
          'It named ${c.detail}, which is not what the goal asks about. '
              'Write only about $names; leave out anything about ${c.detail}.',
        GoalCheckKind.noCitations =>
          'It cited nothing. Put the source number like [2] after every fact.',
        GoalCheckKind.noSources =>
          'No evidence was retrieved. Do not claim facts from memory; state what could not be established.',
        GoalCheckKind.badCitations =>
          'It cited source numbers that do not exist (${c.detail}). Use only '
              'the numbers listed.',
        GoalCheckKind.figures =>
          'These figures appear in no source: ${c.detail}. Remove them or '
              'correct them from the sources.',
        GoalCheckKind.unsupportedClaims =>
          'These product features are not supported with the same meaning and polarity by the cited passages: ${c.detail}. Remove them or explicitly say they are unverified. Do not infer a feature from its absence.',
        GoalCheckKind.droppedFigures =>
          'These figures appear in no source and were cut, with their '
              'sentences: ${c.detail}. Take every number from the sources, '
              'exactly as written.',
        GoalCheckKind.askedUser =>
          'It asked the user for information. Never do that: say what is '
              'missing instead.',
        GoalCheckKind.leak =>
          'It wrote its reasoning or repeated the instructions instead of '
              'the answer. Write only the final text: no "Wait", no "I need '
              'to", no checklist.',
        _ => null,
      };
      if (line != null) b.writeln('- $line');
    }
    return b.toString().trim();
  }
}

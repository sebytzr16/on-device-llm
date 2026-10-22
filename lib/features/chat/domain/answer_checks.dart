import 'dart:convert';

import '../../../core/errors/exceptions.dart';
import '../../../core/l10n/l10n.dart';
import '../../../data/network/web_search/search_models.dart';
import '../../../data/network/web_search/wikipedia_client.dart';
import '../../retrieval/domain/evidence.dart';
import '../../retrieval/domain/evidence_audit.dart';
import '../../settings/domain/entities/inference_settings.dart';
import 'about_user.dart';
import 'math_question.dart';
import 'retrieval_plan.dart';

/// Checks on a finished answer and the notices they raise: citations,
/// unsupported figures, structured output, spoken action talk.
class AnswerChecks {
  const AnswerChecks._();

  /// Whether [input] gets the Wikipedia check above: a factual question
  /// about a subject ("What is the capital of Australia?", "Where was
  /// Marie Curie born?"), with web search on, answered on the phone. Not a
  /// question about the user ("What is my favourite colour?") or a sum,
  /// which the chat itself answers.
  ///
  /// The question must name its subject (a capitalised name or a model
  /// code) and ask for a fact, not advice or an opinion: "What are some
  /// good books to read?", "What is the best way to learn guitar?" and
  /// "What is a closure in JavaScript?" were answered from the "Book",
  /// "Guitar" and "JavaScript" articles with the source-only rules
  /// (audit 2026-10-20).
  static bool wikipediaFactCheck(
    String input, {
    required bool webOn,
    required bool remote,
  }) =>
      webOn &&
      !remote &&
      RetrievalPlan.encyclopedic(input) &&
      (WikipediaClient.subjectName(input) != null ||
          WikipediaClient.productName(input) != null) &&
      !notAFact.hasMatch(input) &&
      !AboutUser.asks(input) &&
      !RetrievalPlan.aboutAssistant(input) &&
      MathQuestion.expression(input) == null &&
      !_personalWord.hasMatch(input);

  /// Advice, opinions, comparisons, explanations and coding questions:
  /// answered by the model, not from one article.
  static final notAFact = RegExp(
    r'(?<![\p{L}])(?:(?:in|using|with) (?:python|javascript|typescript|java|dart|flutter|kotlin|swift|rust|go|c\+\+|c#|sql|react|linux|bash|excel)|closures?|functions?|variables?|loops?|arrays?|tuples?|methods?|errors?|exceptions?|syntax|code|commands?|best|better|good|great|some|any|recommend\w*|should|tips?|ideas?|ways?|difference|differences|vs\.?|versus|compare\w*|explain\w*|why|you|your|yours|pros|cons|benefits?|advantages?|example|examples|meilleure?s?|conseils?|pourquoi|diff[ée]rence|tu|vous|ton|ta|votre|mejor(?:es)?|consejos?|por qu[ée]|diferencia|t[úu]|usted|tus?)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );

  /// Whether a spoken answer after a prepared phone action narrates the
  /// card's steps (tapping, confirming), says it is done before the card
  /// is tapped, or runs past two sentences: models make those up.
  static bool actionTalk(String answer) =>
      _cardStep.hasMatch(answer) ||
      _claimsDone.hasMatch(answer) ||
      RegExp(r'[.!?](?:\s|$)').allMatches(answer.trim()).length > 2;

  // A follow-up that asks for a fact ("how many shots…", "when…"), not
  // advice ("any tip for a rainy day there?"), EN/FR/ES.
  static final asksFact = RegExp(
    r"^(?:(?:and|but|so|et|mais|y|pero)\s+)?(?:how (?:many|much|long|big|heavy|old|far|tall|fast)|what(?:'s|’s| is| are| was| were)|when|where|which|who|combien|quand|o[ùu]|quel(?:le)?s?|qui|cu[áa]nt[oa]s?|cu[áa]ndo|d[óo]nde|cu[áa]l(?:es)?|qui[ée]n)(?![\p{L}])",
    caseSensitive: false,
    unicode: true,
  );

  static final _claimsDone = RegExp(
    r"\bI(?:'ve|’ve| have) (?:set|started|created|scheduled|added)\b|"
    r"\bj['’]ai (?:r[ée]gl[ée]|lanc[ée]|cr[ée][ée]|programm[ée]|ajout[ée])\b|"
    r"\bhe (?:puesto|configurado|creado|programado|a[ñn]adido)\b",
    caseSensitive: false,
    unicode: true,
  );

  static final _cardStep = RegExp(
    r'(?<![\p{L}])(?:tap(?:ped|ping|s)?|click(?:ed)?|press(?:ed)?|confirm(?:ed|s)?|touche[zr]?|appuie[zr]?|confirm[ée]|toca(?:r|ste)?|pulsa(?:r|ste)?|confirma(?:r|do|ste)?)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );

  static final _personalWord = RegExp(
    // Letter boundaries, not \b: "Les Misérables" is not "mis".
    r'(?<![\p{L}\p{N}])(?:my|mine|me|I|mon|ma|mes|mi|mis)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final refusal = RegExp(
    r"(can(?:no|')t|cannot|unable to|do not have|don't have|no) (?:the )?(?:ability to |access to |real[- ]time |direct |live )?(?:access|browse|search|connect to|reach|retrieve)[^.]{0,40}(?:internet|web|online|websites|urls?|links?|real[- ]time|live data|current (?:events|information|data))",
    caseSensitive: false,
  );

  /// Post-answer grounding check (roadmap §7.7): citations are mechanically
  /// verifiable, claim support is not. Returns a notice, or null if fine.
  static String? groundingNotice(
    String answer,
    int sourceCount, [
    AppLocalizations? t,
  ]) {
    t ??= AppLocalizationsEn();
    if (refusal.hasMatch(answer)) return t.noticeRefusal(sourceCount);
    // Accept [1], [1][2] and [1, 3, 4] (Gemma's habit).
    final cited = <int>{
      for (final m in RegExp(r'\[(\d+(?:\s*,\s*\d+)*)\]').allMatches(answer))
        for (final n in m.group(1)!.split(',')) int.parse(n.trim()),
    };
    if (cited.isEmpty) {
      return t.noticeNoCitations(sourceCount);
    }
    final bogus = cited.where((n) => n < 1 || n > sourceCount).toList();
    if (bogus.isNotEmpty) {
      return t.noticeBogusCitations(bogus.join(', '), sourceCount);
    }
    return null;
  }

  /// Figures in the answer that no supplied passage contains: the model may
  /// have recalled them from training instead of the sources.
  static String? figureNotice(
    String answer,
    List<SearchResult> sources, [
    AppLocalizations? t,
  ]) {
    t ??= AppLocalizationsEn();
    // The model sees each page's dates and today's date: "unveiled around
    // July 2026" took its year from them, and the notice called 2026 not
    // found in the sources (the tester's phone chat, 2026-10-19).
    String dates(SearchResult s) => [
      for (final d in [s.publishedAt, s.updatedAt, s.fetchedAt])
        if (d != null) '${d.toLocal().year}',
    ].join(' ');
    final missing = EvidenceRanker.unsupportedFigures(answer, [
      for (final s in sources) ...[
        s.title,
        s.snippet,
        s.pageText ?? '',
        dates(s),
      ],
      '${DateTime.now().year}',
    ]);
    final audit = EvidenceAudit.check(answer, [
      for (final s in sources)
        '${s.title}\n${s.snippet}\n${s.pageText ?? ''}\n${dates(s)}',
    ]);
    if (audit.unsupportedClaims.isNotEmpty) {
      return '${t.unverifiedFeatures}: ${audit.unsupportedClaims.take(4).join(', ')}';
    }
    String list(Iterable<String> figures) => figures.take(4).join(', ');
    String more(Iterable<String> figures) =>
        figures.length > 4 ? t!.noticeAndMore(figures.length - 4) : '';
    if (missing.isNotEmpty) {
      return t.noticeFigures(list(missing), more(missing));
    }
    // A figure another source has is mis-cited, not unfounded: the Z30's
    // "20.9 MP" cited to a comparison page while Wikipedia gave it (phone,
    // 2026-10-04) was reported as "not found in the sources".
    final miscited = audit.unsupportedFigures;
    if (miscited.isEmpty) return null;
    return t.noticeFiguresMiscited(list(miscited), more(miscited));
  }

  /// Maps a search failure to what the user should know and can do.
  static String searchFailureNotice(Object e, [AppLocalizations? t]) {
    t ??= AppLocalizationsEn();
    return switch (e) {
      SearchChallengeException() => t.searchChallenge,
      SearchCooldownException(:final until) => t.searchCooldown(
        until.difference(DateTime.now()).inSeconds.clamp(1, 60),
      ),
      SearchRateLimitException() => t.searchRateLimit,
      SearchMarkupException() => t.searchMarkup,
      _ => t.searchUnavailable,
    };
  }

  /// Structured output (roadmap P2): a JSON answer that does not parse is
  /// reported, with the likely cause when the token cap cut it.
  static String? structuredOutputProblem(
    String answer,
    InferenceSettings s, {
    bool truncated = false,
    AppLocalizations? t,
  }) {
    t ??= AppLocalizationsEn();
    if (s.responseFormat == ResponseFormat.gbnf) {
      return truncated ? t.outputGrammarCut : null;
    }
    try {
      final v = jsonDecode(answer.trim());
      if (s.responseFormat == ResponseFormat.jsonSchema && v is! Map) {
        return t.outputSchemaMismatch;
      }
      return null;
    } catch (_) {
      return truncated ? t.outputJsonCut(s.maxTokens) : t.outputNotJson;
    }
  }
}

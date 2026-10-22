part of 'chat_provider.dart';

/// One turn of [ChatNotifier.send]: what was asked, and what its steps
/// share, from the settings to the saved answer.
class _Turn {
  _Turn(
    this.input, {
    required this.db,
    required this.localEngine,
    required this.lease,
    required this.insertUser,
    required this.resume,
    required this.attachments,
    required this.compareWith,
    required this.reuseSourcesJson,
    required this.parentId,
    required this.turnOverrides,
    required this.extraSystem,
    required this.forceResearch,
    required this.isolated,
    required this.promptOverride,
    required this.answerSources,
    required this.learn,
    required this.subject,
    required this.subjectAllowed,
    required this.budget,
    required this.localOnly,
    required this.spoken,
  }) : engine = localEngine,
       assistantId = resume?.id ?? const Uuid().v4(),
       askedInContext = input;

  // What was asked: [ChatNotifier.send]'s arguments.
  final String input;
  final bool insertUser;
  final ChatMessage? resume;
  final List<Attachment> attachments;
  final ModelInfo? compareWith;
  final String? reuseSourcesJson, parentId;
  final Map<String, dynamic> turnOverrides;
  final String? extraSystem;
  final bool forceResearch, isolated;
  final String? promptOverride;
  final List<SearchResult>? answerSources;
  final bool learn;
  final SubjectTerms? subject;
  final String subjectAllowed;
  final TurnBudget? budget;
  final bool localOnly, spoken;

  final AppDatabase db;
  final TextEngine localEngine;
  final TurnLease lease;

  /// The engine that answers: the phone's, until the settings pick a
  /// remote connection.
  TextEngine engine;
  ModelInfo? model;
  InferenceSettings? settings;
  ResolvedSettings? resolved;

  /// Why the battery saver lightened this turn, if it did.
  String? saverReason;

  /// The remote model plans this turn's research itself.
  var remoteBrain = false;

  // Where the answer is saved.
  String? chatId, modelId, answerParent;

  /// The question's id: notes learned from it point there.
  String? sourceMessageId;
  int sequence = 0;
  final String assistantId;
  var placeholderSaved = false;
  Future<void> pendingWrite = Future.value();

  /// The question was saved ([ChatNotifier.send] returns it).
  var accepted = false;
  String? failure;

  // The answer as it streams in.
  final answer = StringBuffer(), thinking = StringBuffer();
  final tail = AnswerTail();
  ThinkingStreamParser? parser;
  StreamSubscription<String>? answerSub, thinkSub;
  Timer? repaint, checkpoint, deadline;

  void clearAnswer() {
    answer.clear();
    tail.clear();
  }

  /// The finished answer rewritten (cleaned, cited, the app's own words).
  void replaceAnswer(String text) {
    answer
      ..clear()
      ..write(text);
  }

  /// A parser for the next generation round, feeding the same buffers.
  void newParser() {
    final next = ThinkingStreamParser();
    answerSub = next.answerStream.listen((piece) {
      answer.write(piece);
      tail.add(piece);
    });
    thinkSub = next.thinkingStream.listen(thinking.write);
    parser = next;
  }

  // What the answer rests on.
  List<SearchResult> sources = [];
  List<SearchResult> sponsored = [];
  List<SearchResult> displayedSources() => [...sources, ...sponsored];

  /// Each source as the answer checks read it: title, snippet, page.
  List<String> sourceTexts() => [
    for (final s in sources) '${s.title}\n${s.snippet}\n${s.pageText ?? ''}',
  ];

  /// The search queries this turn ran (Goals show them per step).
  List<String>? searchQueries;

  /// The question as understood with its chat (for the source dates), and
  /// whether the turn was a news briefing (its stories carry their times).
  String askedInContext;
  var newsAnswer = false;

  /// Model-driven research that ended its first round without a tool call:
  /// the answer rests on nothing read this turn, and the notice says so.
  var researchSkipped = false;
  ToolRunner? runner;

  /// Whether this turn's engine can see photos.
  var vision = false;

  /// Facts given to the model this turn (Memory on); new ones are learned
  /// from the exchange after the answer.
  var memoryFacts = const <String>[];
  var usedMemoryNotes = '';

  /// The app's own spoken answer on a phone turn: plain arithmetic, or
  /// the name the user gave.
  String? appAnswer;

  /// What the user said before a question about themself, for the phone
  /// model's answer ([AboutUser.ownFacts]).
  List<String>? aboutUser;

  // Checks on the answer.
  var matchedCitations = false;

  /// A follow-up answered from pages read earlier, with web search on:
  /// when they lack the answer, the turn searches.
  var searchIfLacking = false;

  /// The model copied its prompt again when asked a second time.
  var echoStopped = false;
  var claims = const <ClaimVerdict>[];

  // What the turn cost and what the model was given.
  Map<String, dynamic>? metrics;
  var promptTokens = 0, generatedTokens = 0, generationRounds = 0;
  var contextAvailable = const <ChatMessage>[];
  var contextRequested = const <ChatMessage>[];
  var contextInstructions = '';
  var summarizedIds = <String>{};
  String? documentCut;
  var nativeOmitted = 0;

  /// [fitted]: the older turns the app left out to fit the context.
  Map<String, dynamic> contextAudit(int fitted) => ContextUse.capture(
    available: contextAvailable,
    requested: contextRequested,
    omitted: fitted + nativeOmitted,
    instructions: contextInstructions,
    sources: sources,
    isolated: isolated,
    documentNotice: documentCut,
    summarizedIds: summarizedIds,
  );

  /// PERF-01: wall time per research stage, reported with the metrics.
  final stages = <String, int>{};
  final stageClock = Stopwatch()..start();
  void stage(String name) {
    stages[name] = stageClock.elapsedMilliseconds;
    stageClock.reset();
  }
}

/// [ChatNotifier._prepareTurn]: the saved question and the active preset.
typedef _Asked = ({ChatMessage user, Preset preset});

/// [ChatNotifier._planRetrieval]: what the turn looks up, and why.
typedef _Planned = ({
  RetrievalPlan plan,
  String contextual,
  String? previousQuestion,
  bool selfQuestion,
  bool recalledTurn,
  bool followUpSearch,
});

/// [ChatNotifier._lookUp]: the plan as run, the shared system prompt and
/// what the web gave.
typedef _Found = ({
  RetrievalPlan plan,
  ({String system, String notes, String researchNotes, List<String> facts})
  shared,
  bool timely,
  bool researchTurn,
  List<String> queries,
  NewsIntent? newsIntent,
  bool newsTurn,
});

/// [ChatNotifier._assemblePrompt]: what the model is given, and the sum
/// the app worked out, if any ([ChatNotifier._addTurnNotes]).
typedef _Prompt = ({
  List<Map<String, Object>> messages,
  List<ToolSpec> tools,
  bool nativeTools,
  bool researchTurn,
  String? sum,
});

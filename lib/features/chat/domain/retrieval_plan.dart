import '../../tools/phone_actions.dart';
import 'web_terms.dart';

/// Decides, from the user's message alone, whether and how the web is used
/// (roadmap WEB-01). Pasted URLs are read directly; an explicit request to
/// search or a timeliness hint triggers discovery; otherwise nothing leaves the
/// device. The plan never overrides the global web toggle.
enum RetrievalMode { none, search, readUrls }

class RetrievalPlan {
  final RetrievalMode mode;

  /// Distinct http(s) URLs to read in order, at most [maxUrls].
  final List<Uri> urls;

  /// The question with the URLs removed; used as the search query and kept
  /// intact in the prompt.
  final String query;

  /// True when the message looks like it needs current information, even if
  /// the web is off — the chat then tells the user facts are unverified.
  final bool wantsWeb;
  const RetrievalPlan({
    required this.mode,
    required this.urls,
    required this.query,
    required this.wantsWeb,
  });

  static const maxUrls = 3;

  /// A factual question about a subject ("Who was Marie Curie?", "How tall
  /// is the Eiffel Tower?", "¿Cuándo nació Frida Kahlo?"): what an offline
  /// encyclopedia answers when web search is off. Requests, writing tasks
  /// and phone actions are not.
  static bool encyclopedic(String input) {
    final t = input.trim().toLowerCase().replaceFirst(RegExp(r'^[¿¡\s]+'), '');
    if (t.length < 8 || smallTalk(input) || PhoneActions.wanted(input)) {
      return false;
    }
    return _factual.hasMatch(t);
  }

  static final _factual = RegExp(
    r"^(who (is|was|were|are|invented|founded|wrote|painted|discovered)(?![\p{L}\p{N}])|"
    r"what (is|was|are|were) (the |an? )?\p{L}|when (was|is|did|were)(?![\p{L}\p{N}])|"
    r"where (is|was|are|were|did)(?![\p{L}\p{N}])|how (tall|old|big|long|high|deep|far|many|much|large|heavy|wide)(?![\p{L}\p{N}])|"
    r"tell me about(?![\p{L}\p{N}])|"
    r"qui (est|était|a (inventé|fondé|écrit|peint|découvert))(?![\p{L}\p{N}])|qu'est-ce que(?![\p{L}\p{N}])|"
    r"quand (est|a|était|fut)(?![\p{L}\p{N}])|où (est|se trouve|était)(?![\p{L}\p{N}])|"
    r"quel(le)?s? (est|était|sont) (la |le |les |l')?\p{L}|combien (de|mesure|pèse)(?![\p{L}\p{N}])|"
    r"quién (es|era|fue|inventó|fundó|escribió|pintó|descubrió)(?![\p{L}\p{N}])|qué es(?![\p{L}\p{N}])|"
    r"cuándo (fue|es|nació|murió|se)(?![\p{L}\p{N}])|dónde (está|estaba|se encuentra|nació)(?![\p{L}\p{N}])|"
    r"cuál (es|era|fue)(?![\p{L}\p{N}])|cuánto (mide|pesa)(?![\p{L}\p{N}]))",
    unicode: true,
  );

  /// Greetings, thanks and one-line chit-chat: never worth a search, and not
  /// worth asking the model's judge either (a 1.7B judge answered "yes" to
  /// "hi" and read eight pages, report 2026-09-19). Anything with a
  /// question mark, a number or a URL is left to the judge.
  static bool smallTalk(String input) {
    final t = input.trim();
    if (t.isEmpty) return true;
    // Before the question-mark rule: a recognizer writes "Hi?" and "how are
    // you doing?", which are still greetings.
    if (_greeting.hasMatch(t)) return true;
    if (_url.hasMatch(t) || RegExp(r'[?\d]').hasMatch(t)) return false;
    // A lone word ("thanks", "cool", "bitcoin") is not a question; two
    // words ("python version") can be, so they go on to the judge.
    return !t.contains(RegExp(r'\s'));
  }

  /// A specification of a named product: a model code ("Z30", "S25",
  /// "a7iv", "Qwen3.5") or a capitalised name with its number ("iPhone
  /// 17", "Pixel 9") together with a property that has one right value
  /// (weight, battery life, sensor size, price, release date…). A small
  /// model answers these from memory and gets the figures wrong, so Auto
  /// searches them (report 2026-10-04: "Nikon Z30 weight and battery
  /// life" was answered unsourced). Writing and work on supplied text are
  /// left alone.
  static bool productSpec(String input) {
    final t = input.trim();
    if (!_modelCode.hasMatch(t) || !_specWord.hasMatch(t)) return false;
    if (_writing.hasMatch(t) || t.contains('```') || t.length > 600) {
      return false;
    }
    return !_localVerb.hasMatch(t);
  }

  /// A how-to ("how do I boil an egg", "comment faire une omelette",
  /// "¿cómo se cambia una rueda?"): searched whenever the web is on, since
  /// the 0.8B got the egg steps wrong from memory (tester, 2026-10-19).
  /// Questions about the assistant and phone actions stay unsearched.
  static bool howTo(String input) {
    final t = input.trim();
    if (!_howToAsk.hasMatch(t) || t.length > 600 || t.contains('```')) {
      return false;
    }
    return !PhoneActions.wanted(t) && !aboutAssistant(t);
  }

  static final _howToAsk = RegExp(
    r"^[¿¡\s]*(?:(?:and|so|ok(?:ay)?|but|et|alors|y|pues)[,\s]+)?(?:how (?:do|can|should|would) (?:i|we|you|one) (?!(?:feel|say|spell|pronounce|do|think|know|remember|like|mean|rate|rewrite|tell|respond|reply|answer|handle|approach|deal|phrase|word|write|explain|describe|improve|interpret|ask|apologi[sz]e|convince|talk|react)\b)\p{L}|how to \p{L}|what(?:'s| is| are) the (?:steps|best way) to |steps? (?:to|for) |comment (?:faire|on fait|on |puis-je|est-ce qu'on|est-ce que je|je peux|dois-je|faut-il)|quelles sont les [ée]tapes|[ée]tapes pour|c[óo]mo (?:se |hago|puedo|debo|preparo|hacer|hay que)|pasos para)",
    caseSensitive: false,
    unicode: true,
  );

  static final _modelCode = RegExp(
    r"(?<![\p{L}\p{N}])(?:\p{L}[\p{L}\-]*\d+(?:\.\d+)?[\p{L}\d\-]*|\p{Ll}?\p{Lu}\p{L}+ (?:\p{Lu}{0,3})\d{1,4}(?:\.\d+)?)(?![\p{L}\p{N}])",
    unicode: true,
  );

  static final _specWord = RegExp(
    r"(?<![\p{L}\p{N}])(?:weigh(?:t|s)?|battery(?: life)?|dimensions?|sensor(?: size)?|megapixels?|resolution|specs?|specifications?|price|cost|release date|launch date|screen size|display size|storage|ram|processor|chipset|cpu|gpu|lens mount|top speed|horsepower|range|fuel economy|mpg|capacity|parameters?|context (?:length|window)|refresh rate|charging speed|waterproof|ip\d\d|warranty|poids|p[èe]se|batterie|autonomie|taille|capteur|m[ée]gapixels?|r[ée]solution|caract[ée]ristiques|fiche technique|prix|co[ûu]te?|date de sortie|[ée]cran|stockage|processeur|monture|puissance|consommation|capacit[ée]|param[èe]tres|garantie|peso|pesa|bater[íi]a|autonom[íi]a|dimensiones|tama[ñn]o|megap[íi]xeles|resoluci[óo]n|especificaciones|ficha t[ée]cnica|precio|cuesta|fecha de lanzamiento|pantalla|almacenamiento|procesador|montura|potencia|consumo|capacidad|par[áa]metros|garant[íi]a)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  /// Greetings and acknowledgements that never justify an Always-mode search.
  /// Unlike [smallTalk], a lone topic word is not treated as a greeting.
  static bool greetingOnly(String input) => _greeting.hasMatch(input.trim());

  /// A question about the assistant's own abilities to go online — "are
  /// you able to do online searches?", "do you have internet access?",
  /// "peux-tu chercher sur internet ?" — with nothing to look up in it. The
  /// model answers it about itself; searching the words gave a page about
  /// web search in general (report 2026-10-07, Conversation). After
  /// an earlier question ([afterQuestion]) a polite "can you search
  /// online?" asks to look that subject up, so it is not about the
  /// assistant.
  static bool aboutAssistant(String input, {bool afterQuestion = false}) {
    final t = input.trim().toLowerCase();
    if (t.length > 120 || _url.hasMatch(t)) return false;
    final m = _selfOpener.firstMatch(t);
    if (m == null || (afterQuestion && m.namedGroup('ask') != null)) {
      return false;
    }
    final words = _word
        .allMatches(t.substring(m.end))
        .map((w) => w.group(0)!)
        .toList();
    return words.any(_selfWeb.contains) &&
        words.every((w) => _selfWeb.contains(w) || _selfFiller.contains(w));
  }

  static final _selfOpener = RegExp(
    r"^[¿¡\s]*(?:(?:hey|hi|so|and|also|ok(?:ay)?|um+|uh+|well|btw|tell me|alors|et|dis(?:-moi)?|oye|y|entonces|bueno)[,\s]+)*"
    r"(?:(?<ask>(?:can|could|will|would) you|(?:est-ce que )?tu peux|peux-tu|pourrais-tu|(?:est-ce que )?vous pouvez|pouvez-vous|puedes|podr[íi]as)|"
    r"are you (?:able|capable|allowed|connected|online)|do you (?:have|know how|support|use|get)|is it possible for you|have you got|"
    r"(?:est-ce que )?tu (?:sais|as)|sais-tu|as-tu|es-tu (?:capable|connect[ée]e?)|(?:est-ce que )?vous avez|avez-vous|"
    r"sabes|tienes|eres capaz|est[áa]s conectad[oa])(?![\p{L}\p{N}])",
    unicode: true,
  );

  // What going online is called, in the three languages.
  static const _selfWeb = {
    'online', 'internet', 'web', 'search', 'searches', 'searching', //
    'browse', 'browsing', 'google', 'googling', 'websites', 'net',
    'recherche', 'recherches', 'chercher', 'rechercher', 'ligne',
    'buscar', 'búsqueda', 'búsquedas', 'busquedas', 'navegar', 'línea',
    'linea',
  };

  // Words a capability question carries besides that: no subject.
  static const _selfFiller = {
    'do', 'perform', 'make', 'run', 'use', 'access', 'go', 'get', 'have', //
    'connect', 'connected', 'to', 'on', 'a', 'an', 'the', 'any', 'some',
    'able', 'capable', 'of', 'things', 'stuff', 'look', 'up', 'too',
    'also', 'as', 'well', 'right', 'now', 'in', 'general', 'real-time',
    'realtime', 'real', 'time', 'live', 'current', 'information', 'info',
    'data', 'you', 'be', 'and', 'or', 'connection', 'yourself', 'pages',
    'read', 'sites', 'faire', 'des', 'de', 'la', 'le', 'les', 'sur', 'en',
    'aller', 'accès', 'acces', 'à', 'avoir', 'une', 'un', 'connexion',
    'connecté', 'connectée', 'aussi', 'hacer', 'el', 'las', 'los', 'una',
    'ir', 'acceso', 'tener', 'conexión', 'conexion', 'también', 'tambien',
    'información', 'informacion', 'datos', 'tiempo', 'actual',
  };

  /// Work on text the user supplies — writing, rewriting, translating,
  /// explaining or fixing code, summarising pasted material — needs no
  /// facts from the web, so Auto mode skips the model's yes/no judge (a
  /// two-second model call on the phone) for it. Anything with timely or
  /// explicit-search wording or a link never counts as local.
  static bool localTask(String input) {
    final t = input.trim();
    if (_url.hasMatch(t) || _asksForWeb(t)) return false;
    if (PhoneActions.wanted(t)) return true;
    if (timeSensitive(t)) return false;
    // A code fence or a long pasted block is the material to work on.
    if (t.contains('```') || t.length > 600) return true;
    return _localVerb.hasMatch(t);
  }

  /// Whether a message could need a tool: a search, a page, the user's
  /// documents or the calculator (review 2026-09-28, #2: on the
  /// phone, about 700 tokens of tool descriptions on every message delayed
  /// the first word). False for small talk, work on supplied text, and
  /// general requests with nothing to look up or work out: no link, no
  /// timely or search wording, no name, model number or year, no sum.
  /// With [documents] (the user's collection is searched through a tool)
  /// any other message may be about them.
  static bool mayNeedTools(String input, {bool documents = false}) {
    final t = input.trim();
    if (smallTalk(t) || aboutAssistant(t)) return false;
    if (_url.hasMatch(t) || timeSensitive(t) || _asksForWeb(t)) return true;
    if (localTask(t)) return false;
    return documents ||
        _arithmetic.hasMatch(t) ||
        _wordSum.hasMatch(t) ||
        _modelNumber.hasMatch(t) ||
        _year.hasMatch(t) ||
        _named(t);
  }

  // A sum in words: "six times seven", "cinq fois sept", "seis por siete".
  static const _numberWord =
      r'(?:\d+(?:[.,]\d+)?|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|z[ée]ro|un|une|deux|trois|quatre|cinq|sept|huit|neuf|dix|onze|douze|vingt|trente|cent|mille|cero|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|veinte|treinta|cien|mil)';
  static final _wordSum = RegExp(
    '(?<![\\p{L}\\p{N}])$_numberWord\\s+(?:times|plus|minus|divided by|multiplied by|x|fois|moins|divis[ée] par|multipli[ée] par|por|m[áa]s|menos|dividido (?:por|entre)|multiplicado por)\\s+$_numberWord(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  // Figures to work out: "15% of 240", "3 x 4", "how much is 12 … 7".
  static final _arithmetic = RegExp(
    r'\d\s*[+*/×÷^=]\s*\d|\d\s*%|\d\s+[x-]\s+\d|\b(?:calculate|compute|convert|how (?:much|many)|percent(?:age)?|average|sum of|square root|calcule[rz]?|convertis|combien|pourcentage|moyenne|calcula|convierte|cu[áa]nt[oa]s?|porcentaje|promedio)\b[^\n]*\d|\d[^\n]*\b(?:percent|times|divided|plus|minus|squared|pour ?cent|fois|por ciento|veces)\b',
    caseSensitive: false,
    unicode: true,
  );

  // Letters then digits: a model or part number ("Z30", "ZV-E10", "RTX
  // 4090" is caught by its name). "3rd", "10am" and "4k" start with digits.
  static final _modelNumber = RegExp(
    r'(?<![\p{L}\p{N}])\p{L}+-?\d+\p{L}*(?![\p{L}\p{N}])',
    unicode: true,
  );
  static final _year = RegExp(r'(?<!\d)(?:1[6-9]|20)\d\d(?!\d)');
  static final _word = RegExp(r"\p{L}[\p{L}'’-]*", unicode: true);
  static final _sentenceStart = RegExp(r'(?:^|[.!?:;\n"“«¿¡(*#-])\s*$');

  // A capitalised word inside a sentence names something specific to look
  // up ("compare the Nikon and the Sony"). Sentence starts, "I" and its
  // contractions do not count; an all-lowercase message has none.
  static bool _named(String t) {
    for (final m in _word.allMatches(t)) {
      final w = m[0]!;
      final first = w.substring(0, 1);
      if (first == first.toLowerCase() ||
          RegExp(r"^I(?:['’]\w+)?$").hasMatch(w)) {
        continue;
      }
      if (_sentenceStart.hasMatch(t.substring(0, m.start))) continue;
      return true;
    }
    return false;
  }

  // Verbs that act on supplied text. "Explain", "summarise", "make me",
  // "tell me" are how knowledge questions are asked too, so they are not
  // here: those still go to the judge.
  static final _localVerb = RegExp(
    r'^(please |can you |could you |pls )?(write|rewrite|draft|compose|translate|paraphrase|proofread|fix|debug|refactor|improve|shorten|expand|simplify|correct|format|convert|brainstorm|outline|rephrase|reword|edit|review|proof-?read|[ée]cris|r[ée][ée]cris|r[ée]dige|traduis|traduire|corrige|reformule|escribe|reescribe|redacta|traduce|traducir|reformula|revisa|mejora|acorta)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  // One greeting or courtesy, as people type or a speech recognizer writes
  // it ("Hi?", "hey there", "how's it going").
  static const _greetingPart =
      r"(?:hi|hello|hey|hiya|yo|howdy|greetings|good (?:morning|afternoon|evening|night|day)|thanks?(?: you)?(?: (?:so much|a lot|very much))?|thank you|ty|ok(?:ay)?|cool|nice|great|bye|goodbye|see you(?: later)?|how are you(?: doing)?(?: today)?|how(?:'s| is) it going|how are things|how have you been|how(?:'s| is| was) your (?:day|night|evening|morning|week|weekend)(?: going| been)?|what'?s up|whats up|sup|nice to meet you|salut|bonjour|bonsoir|bonne nuit|bonne journ[ée]e|merci(?: beaucoup)?|au revoir|[àa] bient[ôo]t|(?:comment )?[çc]a va(?: bien)?|comment allez-vous|coucou|hola|buen(?:os|as) (?:d[íi]as|tardes|noches)|(?:muchas )?gracias|adi[óo]s|hasta luego|qu[ée] tal(?: est[áa]s)?|c[óo]mo est[áa]s|c[óo]mo va)";

  // Words that may follow a greeting without making it a question: "how
  // are you doing tonight?" is not news of the night (phone, 2026-10-08:
  // it searched and explained the phrase).
  static const _greetingTail =
      r"(?:there|everyone|all|friend|buddy|mate|again|assistant|claude|mon ami|amigo|a todos|today|tonight|so far|this (?:morning|afternoon|evening|week)|aujourd['’]hui|ce soir|ce matin|hoy|esta noche|esta ma[ñn]ana)";

  // One or more greetings ("hi there, how are you doing?"), with any
  // punctuation a recognizer adds, including a question mark.
  static final _greeting = RegExp(
    '^[¡¿\\s]*$_greetingPart(?:[\\s,!.?¡¿]+(?:$_greetingPart|$_greetingTail))*[\\s!.,?¡¿]*\$',
    caseSensitive: false,
    unicode: true,
  );

  static final _url = RegExp(r'https?://[^\s<>"\)\]]+', caseSensitive: false);
  // Time-sensitive wording, or any mention of going online: in Auto mode a
  // false positive costs a slower answer; a false negative makes the model
  // deny it can browse, which is worse (report, Gemma 4, 2026-09-15).
  static final _timely = RegExp(
    r'\b(latest|current(?:ly)?|today|tonight|yesterday|news|recent(?:ly)?|price|prices|weather|score|scores|update[sd]?|as of|right now|nowadays|this (?:year|week|month|weekend)|last night|upcoming|next (?:total |solar |lunar )*eclipse|(?:who|which company|what company) (?:makes|made|manufactures|designs|designed|produces|builds|owns)|(?:what|which) (?:gpu|cpu|chip|chipset|processor|soc|modem) (?:is|does|do|comes)|next (?:[a-z]+ )?(?:elections?|game|match|race|launch|release|season|episode)|(?:cost|costs|worth) now|who is|what is the (?:newest|best|top)|population|how many people (?:live|are living)|inhabitants|202[4-9]|20[3-9]\d)\b',
    caseSensitive: false,
  );

  /// Wording about something that changes over time (versions, prices,
  /// office holders…), as opposed to a pasted link or a request to search.
  ///
  /// Writing work ("write a story about a new car", "traduis ce texte")
  /// is time-sensitive only with a real time marker ("write about the
  /// latest Flutter release"); an explicit request still searches.
  ///
  /// A concept question ("explain price elasticity", "what's the difference
  /// between weather and climate") needs a real time marker as well, and
  /// planning for today ("a workout for today") is not one.
  static bool timeSensitive(String input) {
    final t = input.trim();
    if (_writing.hasMatch(t) && !_strongTime.hasMatch(t)) return false;
    final probe = t.replaceAll(_personalTime, ' ').replaceAll(_updateVerb, ' ');
    final hit =
        _timely.hasMatch(probe) ||
        _timelyIntl.hasMatch(probe) ||
        WebTerms.timely.hasMatch(probe);
    if (!hit) return false;
    return !_concept.hasMatch(t) || _strongTime.hasMatch(probe);
  }

  // How something works or what it means: general knowledge.
  static final _concept = RegExp(
    r"^[¿¡\s]*(?:please |can you |could you )?(?:explain|define|describe|what(?:['’]s| is| are) the difference|difference between|how (?:does|do) .{1,60}? work|why (?:do|does)|what (?:does|do) .{1,40}? mean|what is an? |explique|d[ée]finis|d[ée]cris|quelle est la diff[ée]rence|diff[ée]rence entre|comment (?:fonctionne|marche)|pourquoi (?:les|le|la|l['’])|qu['’]est-ce (?:que|qu['’])|explica|define|describe|cu[áa]l es la diferencia|diferencia entre|c[óo]mo funciona|por qu[ée] (?:los|las|el|la)|qu[ée] es (?:un|una|el|la) )",
    caseSensitive: false,
    unicode: true,
  );

  // Markers that make even a concept question about the present.
  static final _strongTime = RegExp(
    r"(?<![\p{L}\p{N}])(?:today|tonight|right now|latest|current(?:ly)?|this (?:week|month|year)|news|202[4-9]|20[3-9]\d|aujourd['’]hui|ce soir|en ce moment|actuel(?:le)?(?:ment)?|derni[èe]re?s?|nouvelles|actualit[ée]s?|hoy|esta noche|ahora mismo|actual(?:mente)?|[úu]ltim[oa]s?|noticias)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  // Planning the user's own day is not a question about the world.
  static final _personalTime = RegExp(
    // "I'm tired today" is about the user's day, not the news (audit
    // 2026-10-20); another marker ("weather") still searches.
    r"(?:(?:for|pour|para) (?:today|tonight|tomorrow|aujourd['’]hui|ce soir|demain|hoy|esta noche|ma[ñn]ana)|(?:cook|eat|make|wear|do|watch|read|play|listen to|prepare|bake) (?:today|tonight|tomorrow)|\b(?:I(?:['’]m| am| feel| felt| was| had| have| did| went| worked)|my day)\b[^.?!\n]{0,40}?\b(?:today|tonight|yesterday|this (?:morning|evening|week))|\bje (?:suis|me sens|[ée]tais)\b[^.?!\n]{0,40}?aujourd['’]hui|\b(?:estoy|me siento)\b[^.?!\n]{0,40}?\bhoy)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  // "Update my resume": the verb, not a news update.
  static final _updateVerb = RegExp(
    r"\bupdate (?:my|the|this|your|our|a|an|these|those|it)\b",
    caseSensitive: false,
  );

  static bool _asksForWeb(String input) =>
      _explicit.hasMatch(input) ||
      _explicitIntl.hasMatch(input) ||
      WebTerms.explicit.hasMatch(input);

  // Openers of writing work on the user's own material.
  static final _writing = RegExp(
    r'^(?:please |can you |could you |pls |peux-tu |pourrais-tu |puedes |podr[íi]as )?(?:write|rewrite|draft|compose|translate|paraphrase|proofread|rephrase|reword|brainstorm|outline|[ée]cris|r[ée][ée]cris|r[ée]dige|traduis|reformule|escribe|reescribe|redacta|traduce|reformula)(?![\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  // French and Spanish. `\b` is ASCII-only in Dart, so accented words are
  // bounded by Unicode letter lookarounds.
  static final _timelyIntl = RegExp(
    r"(?<![\p{L}\p{N}])(derni[èe]res?|actuellement|aujourd'?hui|hier|ce soir|en ce moment|cette (?:ann[ée]e|semaine)|actualit[ée]s?|nouvelles|prix|m[ée]t[ée]o|r[ée]sultats? du match|qui est|prochaines? (?:[ée]lections?|match|partie|course)|co[ûu]te(?:nt)? (?:maintenant|actuellement)|maintenant\s*\?|[úu]ltim[oa]s?|actualmente|hoy|ayer|esta (?:noche|semana)|este a[ñn]o|ahora mismo|anoche|pr[óo]xim[oa]s? (?:elecciones|elecci[óo]n|partido|carrera)|cuesta(?:n)? ahora|ahora cuesta(?:n)?|noticias|precios?|clima|el tiempo en|marcador|resultado del partido|qui[ée]n es|habitants|combien de personnes vivent|poblaci[óo]n|habitantes|cu[áa]ntas personas viven)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  static final _explicitIntl = RegExp(
    r"(?<![\p{L}\p{N}])(cherche|chercher|recherche|rechercher|v[ée]rifie|v[ée]rifier|sur internet|en ligne|sur le web|sources?|site web|busca|buscar|b[úu]scalo|investiga|verifica|comprueba|en internet|en l[íi]nea|en la web|fuentes?|p[áa]gina web)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  /// A message that continues the previous exchange instead of asking
  /// afresh: "tell me more", "what about the second one", "why?", a short
  /// question built on a pronoun. Such a message is a bad search query on
  /// its own, and the pages already read in the chat often answer it.
  static bool looksLikeFollowUp(String input) {
    final t = input.trim();
    if (t.isEmpty || _url.hasMatch(t)) return false;
    if (referencedItem(t) != null) return true;
    if (_followUpLead.hasMatch(t)) return true;
    final words = t.split(RegExp(r'\s+'));
    if (words.length > 12) return false;
    // "What is its price in Canada?" names a place, not its subject:
    // possessive and object pronouns always point back.
    if (_backReference.hasMatch(t)) return true;
    // A named subject makes it a question of its own ("is it true that
    // Carney called an election?" still names what it is about).
    final named = words
        .skip(1)
        .any(
          (w) =>
              RegExp(r'^\p{Lu}\p{Ll}+', unicode: true).hasMatch(w) && w != 'I',
        );
    if (named) return false;
    // "Which one is cheaper?", "and the battery life?": short and built on
    // a comparison or a bare "and".
    if (words.length <= 8 && _shortReference.hasMatch(t)) return true;
    return _pronoun.hasMatch(t);
  }

  // Openers that only make sense after an answer. "why" counts alone or
  // as "why is that": "why did Rome fall?" is a question of its own.
  static final _followUpLead = RegExp(
    r"^(?:and |but |so |ok(?:ay)? |then |also )?(?:what about|how about|tell me more|more (?:about|on|details|info)|any more|elaborate|expand on|go on|continue|keep going|why(?=\s*[?!.]*$)|why is that|why so|how come|explain (?:that|this|it|more|why)|what does (?:it|that|this) mean|details(?: on| about)?|and then|what else|say more|dig deeper|go deeper|in more detail|summari[sz]e (?:it|that|this|them)|what did (?:it|they|he|she) say|what happened (?:next|then|after))(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  static final _backReference = RegExp(
    r"(?<![\p{L}\p{N}'])(its|their|theirs|them|his|him|hers|the latter|the former|the other one|both of them|each of them|ça|cela|celui-ci|celle-ci|ceux-ci|eso|esto|aquello)(?![\p{L}\p{N}'])",
    caseSensitive: false,
    unicode: true,
  );

  static final _shortReference = RegExp(
    r"^(?:and|but|or|et|y|o)\s|(?<![\p{L}\p{N}])(which one|which ones|the one|this one|that one|the same|both|either|neither|cheaper|more expensive|better|worse|bigger|smaller|lighter|heavier|faster|slower|newer|older|instead|compared|vs\.?|versus)(?![\p{L}\p{N}])",
    caseSensitive: false,
    unicode: true,
  );

  /// What a chain of follow-ups is about: the last earlier question, and
  /// while that one was itself a follow-up, the ones before it (oldest
  /// first, at most three). Null when there is no earlier question.
  static String? conversationTopic(List<String> earlierQuestions) {
    final chain = <String>[];
    for (final q in earlierQuestions.reversed) {
      if (q.trim().isEmpty) continue;
      chain.insert(0, q);
      if (chain.length == 3 || !looksLikeFollowUp(q)) break;
    }
    return chain.isEmpty ? null : chain.join(' ');
  }

  static final _pronoun = RegExp(
    r"\b(it|its|it's|that|this|those|these|they|them|their|theirs|he|him|his|she|her|hers|there|such)\b",
    caseSensitive: false,
  );

  static const _ordinals = {
    'first': 1,
    '1st': 1,
    'second': 2,
    '2nd': 2,
    'third': 3,
    '3rd': 3,
    'fourth': 4,
    '4th': 4,
    'fifth': 5,
    '5th': 5,
    'sixth': 6,
    '6th': 6,
    'seventh': 7,
    '7th': 7,
    'eighth': 8,
    '8th': 8,
    'ninth': 9,
    '9th': 9,
    'tenth': 10,
    '10th': 10,
    'last': -1,
  };

  /// The story, source or point a follow-up points at, 1-based ("the
  /// second story" → 2, "source 4" / "[4]" → 4), -1 for "the last one", or
  /// null when it names none.
  static int? referencedItem(String input) {
    final t = input.toLowerCase();
    final cited = RegExp(r'\[(\d{1,2})\]').firstMatch(t);
    if (cited != null) return int.parse(cited.group(1)!);
    final numbered = RegExp(
      r'\b(?:story|item|source|number|point|headline|article|link|result|no\.?)\s*#?(\d{1,2})\b',
    ).firstMatch(t);
    if (numbered != null) return int.parse(numbered.group(1)!);
    final ordinal = RegExp(
      r'\b(first|1st|second|2nd|third|3rd|fourth|4th|fifth|5th|sixth|6th|seventh|7th|eighth|8th|ninth|9th|tenth|10th|last)\s+(?:one|story|item|source|point|headline|article|link|result|news|thing|option|bullet)\b',
    ).firstMatch(t);
    if (ordinal != null) return _ordinals[ordinal.group(1)!];
    return null;
  }

  /// "Where I live", "near me": the place the user named earlier in the
  /// chat ("I live in Denver"), so the search is not about wherever the
  /// result page thinks the phone is (it said Vaughan, conversation probe
  /// 2026-10-18). [earlier] are the user's earlier messages, oldest first.
  static String withUserPlace(String query, List<String> earlier) {
    if (!_myPlace.hasMatch(query)) return query;
    String? place;
    for (final m in earlier) {
      for (final hit in _livesIn.allMatches(m)) {
        place = hit.group(1)!.trim();
      }
    }
    if (place == null) return query;
    return query
        .replaceAll(_myPlace, ' in $place ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r' ([?!.,])'), (m) => m[1]!)
        .trim();
  }

  static final _myPlace = RegExp(
    r"(?<![\p{L}])(?:where I (?:live|am|'m|am living|'m living|stay)|near me|around me|around here|in my (?:city|town|area|region)|my (?:city|town|area)|o[ùu] j'habite|o[ùu] je (?:vis|suis)|chez moi|pr[èe]s de chez moi|donde vivo|donde estoy|en mi ciudad|cerca de m[íi])(?![\p{L}])",
    caseSensitive: false,
    unicode: true,
  );

  static final _livesIn = RegExp(
    r"(?<![\p{L}])(?:I live in|I['’]m living in|I am living in|I['’]m from|I am from|I['’]m based in|I am based in|I['’]m in|I am in|[Mm]y (?:city|town|home) is|[Jj]['’]habite (?:à|a|en|au)|[Jj]e vis (?:à|a|en|au)|[Jj]e suis (?:à|de)|[Vv]ivo en|[Ss]oy de|[Ee]stoy en)\s+(\p{Lu}[\p{L}'’-]*(?:\s+(?:(?:de|del|la|le|sur|upon)\s+)?\p{Lu}[\p{L}'’-]*)*)",
    unicode: true,
  );

  /// A search query for a follow-up that only points at its subject: the
  /// previous question's content words lead ("how old is he?" after "who is
  /// Mark Carney" searches "Mark Carney old"). Questions that name their
  /// own subject, or are long, are left as they are.
  ///
  /// When the previous question asked for one thing ("what is the capital
  /// of Canada?") the names its answer brought in lead: "how many people
  /// live there?" is about Ottawa (the 0.8B searched Canada's population,
  /// conversation probe 2026-10-18).
  static String withContext(
    String input,
    String? previousQuestion, {
    String? previousAnswer,
  }) {
    if (previousQuestion == null || previousQuestion.trim().isEmpty) {
      return input;
    }
    if (!looksLikeFollowUp(input)) return input;
    final named = previousAnswer == null
        ? const <String>[]
        : answerNames(previousQuestion, previousAnswer);
    final before = [...named, ...keywords(previousQuestion).split(' ').take(7)];
    final now = keywords(
      input.replaceAll(_followUpLead, ' ').replaceAll(_pronoun, ' '),
    ).split(' ');
    final seen = <String>{};
    final words = <String>[
      for (final w in [...before, ...now])
        if (w.isNotEmpty && seen.add(w.toLowerCase())) w,
    ];
    return words.take(12).join(' ');
  }

  /// The names [answer]'s first sentence adds to [question] when the
  /// question asked for one thing (a capital, a leader, an author…), at
  /// most four; none otherwise.
  static List<String> answerNames(String question, String answer) {
    if (!_asksForOne.hasMatch(question)) return const [];
    final asked = {
      for (final w in question.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        w.toLowerCase(),
    };
    final first = answer
        .replaceAll(RegExp(r'[*_#`]|\[\d{1,2}\]'), '')
        .trim()
        .split(RegExp(r'(?<=[.!?])\s+|\n'))
        .first;
    final names = <String>[];
    for (final raw in first.split(RegExp(r'\s+'))) {
      final w = raw.replaceAll(
        RegExp(r"^[^\p{L}]+|(?:['’]s)?[^\p{L}\p{N}]*$", unicode: true),
        '',
      );
      if (w.isEmpty || !RegExp(r'^\p{Lu}', unicode: true).hasMatch(w)) {
        continue;
      }
      final low = w.toLowerCase();
      if (_notNames.contains(low) || asked.contains(low)) continue;
      if (!names.contains(w)) names.add(w);
    }
    return names.take(4).toList();
  }

  static final _asksForOne = RegExp(
    r"\b(?:what|which|who)(?:['’]s|\s+is|\s+was|\s+are|\s+were)\s+the\s+\p{L}|\bwho (?:wrote|founded|invented|directed|painted|discovered|won|owns|runs|leads|sang)\b|\b(?:quelle?|qui) est (?:la|le|l['’])|\b(?:cu[áa]l|qui[ée]n) es (?:la|el)\b",
    caseSensitive: false,
    unicode: true,
  );

  static const _notNames = {
    'it',
    'its',
    'the',
    'this',
    'that',
    'these',
    'those',
    'yes',
    'no',
    'sure',
    'i',
    'a',
    'an',
    'there',
    'here',
    'he',
    'she',
    'they',
    'we',
    'you',
    'today',
    'currently',
    'according',
    'based',
    'as',
    'in',
    'on',
    'at',
    'of',
    'for',
    'well',
    'so',
    'okay',
    'ok',
    'le',
    'la',
    'les',
    'el',
    'los',
    'las',
    'c',
    'est',
    'es',
    'il',
    'elle',
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  };

  /// DuckDuckGo's date window: news-like wording needs the last month;
  /// other time-sensitive questions use the last year.
  static String? searchDateFilter(String input) {
    if (_newsLike.hasMatch(input)) return 'm';
    return timeSensitive(input) ? 'y' : null;
  }

  static final _newsLike = RegExp(
    r'\b(news|today|this week)\b',
    caseSensitive: false,
  );

  /// The question's content words as a bare search query, for a second try
  /// when the question as typed found nothing: question words, politeness
  /// and the explicit "search for" wrapper go, order is kept, at most eight
  /// words.
  static String keywords(String input) {
    final words = input
        .replaceAll(_url, ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s.\-]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 || RegExp(r'\d').hasMatch(w))
        .where((w) => !_queryNoise.contains(w.toLowerCase()))
        .toList();
    return words.take(8).join(' ');
  }

  static const _queryNoise = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'do',
    'does',
    'did',
    'can',
    'could',
    'would',
    'should',
    'will',
    'what',
    'which',
    'who',
    'whom',
    'when',
    'where',
    'why',
    'how',
    'me',
    'my',
    'i',
    'you',
    'your',
    'we',
    'our',
    'it',
    'its',
    'this',
    'that',
    'these',
    'those',
    'of',
    'for',
    'to',
    'in',
    'on',
    'at',
    'by',
    'with',
    'about',
    'from',
    'and',
    'or',
    'please',
    'tell',
    'find',
    'out',
    'search',
    'look',
    'up',
    'google',
    'know',
    'want',
    'like',
    'need',
    'give',
    'get',
    'some',
    'any',
    'there',
    'currently',
  };

  // Explicit asks that should work without a timeliness keyword.
  static final _explicit = RegExp(
    r'\b(look\s*(?:it\s*)?up|look for|google|search|browse|find out|check(?! (?:my|this|the|our|your) (?:grammar|spelling|code|math|work|answer|essay|text|writing|homework))|verify|research|online|on the internet|on the web|internet|website|websites|web page|sources?|cite|citations?)\b',
    caseSensitive: false,
  );

  /// [always] researches every message (WebMode.always); pasted links still
  /// win over search.
  static RetrievalPlan of(
    String input, {
    required bool webEnabled,
    bool always = false,
  }) {
    final seen = <String>{};
    final urls = <Uri>[];
    for (final m in _url.allMatches(input)) {
      var raw = m.group(0)!;
      // Trailing punctuation is almost never part of a pasted link.
      raw = raw.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
      final uri = Uri.tryParse(raw);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty) continue;
      if (seen.add(uri.toString()) && urls.length < maxUrls) urls.add(uri);
    }
    final query = input
        .replaceAll(_url, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final wantsWeb =
        always ||
        urls.isNotEmpty ||
        _asksForWeb(input) ||
        // "Remind me tomorrow at 9", "set an alarm for today": the date is
        // for the phone action, not a sign of news to look up.
        // "Hi! How are you today?" is a greeting, not news of the day.
        ((timeSensitive(input) || productSpec(input) || howTo(input)) &&
            !PhoneActions.wanted(input) &&
            !smallTalk(input));
    if (!webEnabled || !wantsWeb) {
      return RetrievalPlan(
        mode: RetrievalMode.none,
        urls: const [],
        query: query,
        wantsWeb: wantsWeb,
      );
    }
    return RetrievalPlan(
      mode: urls.isNotEmpty ? RetrievalMode.readUrls : RetrievalMode.search,
      urls: urls,
      query: query.isEmpty ? input.trim() : query,
      wantsWeb: true,
    );
  }
}

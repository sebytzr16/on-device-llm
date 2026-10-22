import '../../memory/domain/memory_statements.dart';

/// A question about the user themself ("what's my name?", "which city do I
/// live in?"): Qwen3.5 0.8B answered "My name is Robin" and "I lived in
/// Denver" although the spoken style says whose facts they are
/// (conversation probe, 2026-10-18). A note next to the question, like the
/// worked-out sums, keeps the roles straight.
abstract final class AboutUser {
  /// No example answers: Qwen3.5 0.8B spoke the examples' wording back
  /// with the earlier facts filled in, whatever was asked ("Your name is
  /// Robin. You live in Denver", phone probe round 3, 2026-10-18).
  static const note =
      'This asks about the user. What they said earlier is theirs: speak '
      'of it as "you" and "your", never "I" or "my". Answer only what this '
      'question asks.';

  /// The answer to "what's my name?" from what the user said in this chat
  /// ([said], oldest first): "Your name is Robin.", in the question's
  /// language, or null. On a spoken phone turn it replaces the model's:
  /// with the note, Qwen3.5 0.8B still answered "My name is Robin"
  /// (phone probe round 4, 2026-10-18).
  static String? spokenName(String input, List<String> said) {
    final q = input.trim();
    if (q.split(RegExp(r'\s+')).length > 9) return null;
    final lang = _nameQuestionEn.hasMatch(q)
        ? 'en'
        : _nameQuestionFr.hasMatch(q)
        ? 'fr'
        : _nameQuestionEs.hasMatch(q)
        ? 'es'
        : null;
    if (lang == null) return null;
    String? name;
    for (final s in said.reversed) {
      final m = _gaveName.firstMatch(s);
      if (m != null && !_notAName.contains(m[1]!.toLowerCase())) {
        name = m[1]!;
        break;
      }
    }
    if (name == null) return null;
    name = name[0].toUpperCase() + name.substring(1);
    return switch (lang) {
      'fr' => 'Tu t’appelles $name.',
      'es' => 'Te llamas $name.',
      _ => 'Your name is $name.',
    };
  }

  /// [answer] to a question about the user, with the user's facts given
  /// back as theirs: in a sentence that names something they said ([said]:
  /// "Milo", "Denver", "cats"), "I have", "I live", "my" become "you
  /// have", "you live", "your". With the note, Qwen3.5 0.8B still answered
  /// "The two cats I have are Milo and Luna" (phone probe round 5,
  /// 2026-10-18). English only; a sentence with a negation ("I don't have
  /// your cats' names") is left as written.
  static String ownFacts(String answer, List<String> said) {
    Iterable<String> words(String s) =>
        _word.allMatches(s).map((m) => m[0]!.toLowerCase());
    final theirs = {for (final s in said) ...words(s)}..removeAll(_common);
    if (theirs.isEmpty) return answer;
    return answer.splitMapJoin(
      RegExp(r'[^.!?\n]+[.!?]*'),
      onMatch: (m) {
        final s = m[0]!;
        if (_negation.hasMatch(s) || !words(s).any(theirs.contains)) {
          return s;
        }
        return s.replaceAllMapped(_mine, (w) {
          final flipped = _yours[w[0]!.toLowerCase()]!;
          final first = s.substring(0, w.start).trim().isEmpty;
          return first
              ? flipped[0].toUpperCase() + flipped.substring(1)
              : flipped;
        });
      },
      onNonMatch: (s) => s,
    );
  }

  static final _word = RegExp(r'\p{L}{4,}', unicode: true);
  static final _negation = RegExp(
    r"\b(?:not|no|never|don['’]t|doesn['’]t|didn['’]t|can['’]t|cannot|haven['’]t|won['’]t)\b",
    caseSensitive: false,
  );
  static final _mine = RegExp(
    r"\b(?:I have|I['’]ve|I own|I lived?|I['’]m from|I am from|I['’]m called|I am called|my|mine)\b",
    caseSensitive: false,
  );
  static const _yours = {
    'i have': 'you have',
    "i've": "you've",
    'i’ve': 'you’ve',
    'i own': 'you own',
    'i live': 'you live',
    'i lived': 'you lived',
    "i'm from": "you're from",
    'i’m from': 'you’re from',
    'i am from': 'you are from',
    "i'm called": "you're called",
    'i’m called': 'you’re called',
    'i am called': 'you are called',
    'my': 'your',
    'mine': 'yours',
  };

  /// Words too common to say the sentence is about the user's facts.
  static const _common = {
    'what',
    'that',
    'this',
    'these',
    'those',
    'have',
    'with',
    'from',
    'your',
    'they',
    'them',
    'there',
    'their',
    'about',
    'which',
    'where',
    'when',
    'live',
    'lived',
    'like',
    'just',
    'name',
    'called',
    'many',
    'much',
    'some',
    'been',
    'were',
    'would',
    'could',
    'should',
    'know',
    'remember',
    'tell',
    'does',
    'into',
    'also',
    'very',
    'here',
    'hello',
    'thanks',
    'thank',
    'okay',
    'well',
    'today',
    'want',
    'need',
    'please',
  };

  /// The answer to "what's my favourite colour?" or "what is my dog's
  /// name?" from what the user said in this chat ("my favourite colour is
  /// green, by the way"): "Your favourite colour is green.", or null.
  /// English only. Qwen3.5 0.8B answered "No one really knows your
  /// personal favorite color anymore!" (phone probe round 5, 2026-10-18).
  static String? spokenFact(String input, List<String> said) {
    final q = _factQuestion.firstMatch(input.trim());
    if (q == null) return null;
    final key = q[1]!.trim();
    String norm(String s) => s
        .toLowerCase()
        .replaceAll('favorite', 'favourite')
        .replaceAll('color', 'colour')
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final s in said.reversed) {
      for (final m in _gaveFact.allMatches(s)) {
        if (norm(m[1]!) != norm(key)) continue;
        final value = m[2]!.trim();
        if (value.isEmpty || value.split(' ').length > 4) continue;
        return 'Your $key is $value.';
      }
    }
    return null;
  }

  /// "Your cats are Milo and Luna." for "What are my cats called?" when
  /// the user said "I have two cats, Milo and Luna.", or null. On a spoken
  /// phone turn it replaces the model's: Qwen3.5 0.8B answered "Your name
  /// is Milo, and I also have a cat named Luna." (Conversation probe round
  /// 9, 2026-10-18). English only.
  static String? spokenNames(String input, List<String> said) {
    final q = _namesQuestion.firstMatch(input.trim());
    if (q == null) return null;
    final noun = (q[1] ?? q[2])!;
    String one(String s) => s.toLowerCase().replaceAll(RegExp(r's$'), '');
    for (final s in said.reversed) {
      for (final m in _gaveNames.allMatches(s)) {
        if (one(m[1]!) != one(noun)) continue;
        final names = m[2]!.replaceAll(RegExp(r',? and '), ' and ');
        final verb = names.contains(' and ') || names.contains(', ')
            ? 'are'
            : 'is';
        return 'Your ${noun.toLowerCase()} $verb $names.';
      }
    }
    return null;
  }

  static final _namesQuestion = RegExp(
    "$_lead"
    r"(?:what are my (\p{L}+?)(?:['’]s?)? (?:called|named|names)"
    r"|what are the names of my (\p{L}+))\s*[?.!]*$",
    caseSensitive: false,
    unicode: true,
  );
  static final _gaveNames = RegExp(
    r"\b[Ii] (?:have|own|got) (?:[Aa]n?|[Oo]ne|[Tt]wo|[Tt]hree|[Ff]our|"
    r"[Ff]ive|\d+) (\p{L}+),? (?:called |named )?"
    r"(\p{Lu}\p{L}*(?:(?:, |,? and )\p{Lu}\p{L}*)*)",
    unicode: true,
  );

  static final _factQuestion = RegExp(
    "$_lead(?:what(?:'s|’s| is| was)|do you (?:know|remember)) my ((?:[\\p{L}]+(?:'s|’s)? )?(?:favou?rite )?[\\p{L}]+(?: [\\p{L}]+)?)\\s*[?.!]*\$",
    caseSensitive: false,
    unicode: true,
  );
  static final _gaveFact = RegExp(
    r"\bmy ((?:\p{L}+(?:'s|’s)? )?(?:favou?rite )?\p{L}+(?: \p{L}+)?) is ([\p{L}\p{N}' -]+?)(?=\s*(?:[,.;!?]|\band\b|\bby the way\b|$))",
    caseSensitive: false,
    unicode: true,
  );

  static const _lead = r"^(?:(?:and|so|ok(?:ay)?|hey|now|then|et|y)[,\s]+)*";
  static final _nameQuestionEn = RegExp(
    "$_lead(?:what(?:'s|’s| is) my name|do you (?:know|remember) my name|what am I called|who am I)\\s*[?.!]*\$",
    caseSensitive: false,
  );
  static final _nameQuestionFr = RegExp(
    "$_lead(?:comment (?:est-ce que )?je m['’]appelle|quel est mon (?:nom|prénom)|c['’]est quoi mon (?:nom|prénom)|tu (?:connais|te souviens de) mon (?:nom|prénom))\\s*[?.!]*\$",
    caseSensitive: false,
    unicode: true,
  );
  static final _nameQuestionEs = RegExp(
    "$_lead¿?(?:c[óo]mo me llamo|cu[áa]l es mi nombre|(?:sabes|recuerdas) (?:c[óo]mo me llamo|mi nombre))\\s*[?.!]*\$",
    caseSensitive: false,
    unicode: true,
  );

  /// The reply to an introduction that asks nothing ("Hi, my name is
  /// Robin and I live in Denver."): "Nice to meet you, Robin. How
  /// can I help?", in its language, or null. On a spoken phone turn it
  /// replaces the model's: Qwen3.5 0.8B answered "It sounds like you are
  /// from the area known as "The Big Hole"" (phone probe round 7,
  /// 2026-10-18). The user's words stay in the chat for later turns.
  static String? spokenIntro(String input) {
    final q = input.trim();
    if (q.contains('?') || q.split(RegExp(r'\s+')).length > 16) return null;
    if (_request.hasMatch(q) || _problemStatement.hasMatch(q)) return null;
    final m = _gaveName.firstMatch(q);
    if (m == null || _notAName.contains(m[1]!.toLowerCase())) return null;
    final how = m[0]!.toLowerCase();
    if (how.startsWith('call')) return null;
    final name = m[1]![0].toUpperCase() + m[1]!.substring(1);
    if (how.startsWith('je') || how.startsWith('mon')) {
      return 'Bonjour $name ! Que puis-je faire pour toi ?';
    }
    if (how.startsWith('me') || how.startsWith('mi')) {
      return '¡Hola, $name! ¿En qué puedo ayudarte?';
    }
    return 'Nice to meet you, $name. How can I help?';
  }

  /// The reply to a message that only tells something about the user
  /// ("My favourite colour is blue."): "Got it: your favourite colour is
  /// blue. I'll remember that.", in its language, or null. Every sentence
  /// must state such a fact; a message that asks something too goes to
  /// the model with [statedNote]. On a spoken phone turn it replaces the
  /// model's: Qwen3.5 0.8B answered "I am not a person…" to a favourite
  /// colour (Conversation probe round 11; tester, 2026-10-19).
  static String? spokenNoted(String input, {required bool remembered}) {
    final facts = _statedOnly(input);
    if (facts == null) return null;
    final q = input.trim();
    if (_french.hasMatch(q)) {
      return remembered ? 'C’est noté, je m’en souviendrai.' : 'C’est noté.';
    }
    if (_spanish.hasMatch(q)) {
      return remembered ? 'Anotado, lo recordaré.' : 'Anotado.';
    }
    final said = facts.map(_yourFact).join(' and ');
    return 'Got it: $said.${remembered ? ' I’ll remember that.' : ''}';
  }

  /// A short acknowledgement only for facts alone. Requests and problem
  /// reports must receive an answer without a forced preamble.
  static String? statedNote(String input, {required bool remembered}) {
    final facts = _statedOnly(input);
    if (facts == null) return null;
    final kept = remembered ? ' It is now saved in your memory notes.' : '';
    final told =
        'The user just told you about themself: ${facts.join('; ')}.$kept';
    return '$told Acknowledge it in one short sentence, as theirs.';
  }

  /// The facts of a message whose every sentence states one; null when it
  /// asks or requests anything, or states nothing.
  static List<String>? _statedOnly(String input) {
    final q = input.trim();
    if (q.split(RegExp(r'\s+')).length > 25 ||
        q.contains('?') ||
        q.contains('¿') ||
        _request.hasMatch(q) ||
        _problemStatement.hasMatch(q)) {
      return null;
    }
    final facts = <String>[];
    for (final clause in MemoryStatements.clauses(q)) {
      if (clause.replaceAll(_noWords, '').isEmpty) continue;
      if (_greetingOnly.hasMatch(clause)) continue;
      final found = MemoryStatements.extract(clause);
      if (found.isEmpty) return null;
      facts.addAll(found);
    }
    return facts.isEmpty ? null : facts;
  }

  /// "The user's favourite colour is blue" → "your favourite colour is
  /// blue"; "The user lives in Denver" → "you live in Denver".
  static String _yourFact(String fact) {
    final f = fact.trim();
    if (f.startsWith("The user's ")) return 'your ${f.substring(11)}';
    if (f.startsWith('The user is ')) return 'you are ${f.substring(12)}';
    if (f.startsWith('The user has ')) return 'you have ${f.substring(13)}';
    final verb = RegExp(r'^The user (\p{L}+?)s\b', unicode: true).firstMatch(f);
    if (verb != null) return 'you ${verb[1]}${f.substring(verb.end)}';
    return f.replaceFirst('The user', 'you');
  }

  static final _noWords = RegExp(r'[\s\p{P}\p{S}]+', unicode: true);
  static final _greetingOnly = RegExp(
    r'^(?:hi|hello|hey|ok(?:ay)?|so|well|bonjour|salut|hola)[\s\p{P}]*$',
    caseSensitive: false,
    unicode: true,
  );
  static final _french = RegExp(
    r"^[\p{P}\s]*(?:(?:bonjour|salut|au fait|d['’]ailleurs|et)[\p{P}\s]+)?(?:je\b|j['’]|mon\b|ma\b|mes\b|moi\b)",
    caseSensitive: false,
    unicode: true,
  );
  static final _spanish = RegExp(
    r'^[\p{P}\s]*(?:(?:hola|por cierto|y)[\p{P}\s]+)?(?:soy|vivo|tengo|mi|mis|me llamo|hablo|prefiero|trabajo|uso|utilizo|yo)\b',
    caseSensitive: false,
    unicode: true,
  );

  /// The reply to "What can you do?" in its language, or null. On a
  /// spoken phone turn it replaces the model's: Qwen3.5 0.8B answered "I
  /// have a large collection of text data in English, so I can read
  /// articles and books for you!" (phone probe round 7, 2026-10-18).
  static String? spokenAbilities(String input, {required bool web}) {
    final q = input.trim();
    // "Can you search online?": the 0.8B answered from its training ("I
    // don't have access to the internet") with web search on, and the
    // reverse with it off (phone probe round 8, 2026-10-18).
    if (_webEn.hasMatch(q)) {
      return web
          ? 'Yes. When a question needs it, I look it up on the web and '
                'show the sources.'
          : 'Not right now: web search is off. You can turn it on in '
                'Settings.';
    }
    if (_webFr.hasMatch(q)) {
      return web
          ? 'Oui. Quand une question le demande, je cherche sur le web et '
                'je montre les sources.'
          : 'Pas pour le moment : la recherche web est désactivée dans les '
                'réglages.';
    }
    if (_webEs.hasMatch(q)) {
      return web
          ? 'Sí. Cuando una pregunta lo necesita, busco en la web y muestro '
                'las fuentes.'
          : 'Ahora no: la búsqueda web está desactivada en los ajustes.';
    }
    if (_abilitiesEn.hasMatch(q)) {
      return web
          ? 'I can answer questions, look up news, weather and prices on '
                'the web, work out sums, and set timers, alarms, reminders '
                'and calendar events. What would you like?'
          : 'I can answer questions from what I know, work out sums, and '
                'set timers, alarms, reminders and calendar events. Web '
                'search is off; you can turn it on in Settings.';
    }
    if (_abilitiesFr.hasMatch(q)) {
      return web
          ? 'Je peux répondre à tes questions, chercher l’actualité, la '
                'météo et les prix sur le web, faire des calculs, et régler '
                'des minuteurs, des alarmes, des rappels et des événements. '
                'Que veux-tu faire ?'
          : 'Je peux répondre à tes questions avec ce que je sais, faire '
                'des calculs, et régler des minuteurs, des alarmes, des '
                'rappels et des événements. La recherche web est désactivée '
                'dans les réglages.';
    }
    if (_abilitiesEs.hasMatch(q)) {
      return web
          ? 'Puedo responder preguntas, buscar noticias, el tiempo y precios '
                'en la web, hacer cálculos, y poner temporizadores, alarmas, '
                'recordatorios y eventos. ¿Qué te gustaría?'
          : 'Puedo responder preguntas con lo que sé, hacer cálculos, y '
                'poner temporizadores, alarmas, recordatorios y eventos. La '
                'búsqueda web está desactivada en los ajustes.';
    }
    return null;
  }

  static final _abilitiesEn = RegExp(
    "$_lead(?:what (?:can|could) you (?:do|help (?:me )?with)|what are you "
    "(?:able|capable) (?:to do|of)|what do you do)(?: for me)?\\s*[?.!]*\$",
    caseSensitive: false,
  );
  static final _abilitiesFr = RegExp(
    "$_lead(?:qu['’]est-ce que tu (?:peux|sais) faire|que (?:peux|sais)-tu "
    "faire|tu (?:peux|sais) faire quoi|que pouvez-vous faire)(?: pour moi)?"
    "\\s*[?.!]*\$",
    caseSensitive: false,
  );
  static final _abilitiesEs = RegExp(
    "$_lead¿?(?:qu[ée] (?:puedes|sabes) hacer|en qu[ée] (?:me )?puedes "
    "ayudar(?:me)?)(?: por m[íi])?\\s*[?.!]*\$",
    caseSensitive: false,
  );

  static final _webEn = RegExp(
    "$_lead(?:(?:can|could) you (?:search|look (?:things |it )?up|go|browse)"
    "(?: on| the)? (?:online|the web|the internet|web|internet)"
    "|(?:are you able to|can you|could you) (?:do|make) (?:an? )?"
    "(?:online|web|internet) searche?s?"
    "|(?:do|can) you (?:have|get) (?:access to )?(?:the )?"
    "(?:internet|web)(?: access)?"
    "|(?:are you|is it) (?:connected to|on) the internet"
    "|(?:can|do) you (?:search|use) (?:google|the internet|the web))"
    "\\s*[?.!]*\$",
    caseSensitive: false,
  );
  static final _webFr = RegExp(
    "$_lead(?:(?:est-ce que )?(?:tu peux|peux-tu|pouvez-vous) (?:chercher|"
    "faire des recherches|rechercher) (?:sur (?:le web|internet)|en ligne)"
    "|(?:as-tu|tu as) (?:accès à )?internet)\\s*[?.!]*\$",
    caseSensitive: false,
  );
  static final _webEs = RegExp(
    "$_lead¿?(?:(?:puedes|podr[íi]as) (?:buscar|hacer b[úu]squedas) "
    "(?:en (?:la web|internet)|en l[íi]nea)"
    "|tienes (?:acceso a )?internet)\\s*[?.!]*\$",
    caseSensitive: false,
    unicode: true,
  );

  /// The reply to a greeting alone ("Hi!", "Bonjour", "Hola, buenos
  /// días"), in its language, or null. On a spoken phone turn it replaces
  /// the model's: Qwen3.5 0.8B answered "Hola" with a paragraph about the
  /// word (phone probe round 8, 2026-10-18).
  /// A greeting that asks how the assistant is ("Hi, how are you?") gets
  /// "I'm well, thanks" first.
  static String? spokenGreeting(String input) {
    final q = input.trim();
    // Thanks alone: "You are welcome! I'm doing well and ready to help."
    // (phone probe round 8, 2026-10-18).
    if (_thanksEn.hasMatch(q)) return "You're welcome!";
    if (_thanksFr.hasMatch(q)) return 'De rien !';
    if (_thanksEs.hasMatch(q)) return '¡De nada!';
    final en = _greetEn.firstMatch(q);
    if (en != null) {
      return en[1] != null
          ? "I'm well, thanks. How can I help?"
          : 'Hi! How can I help?';
    }
    final fr = _greetFr.firstMatch(q);
    if (fr != null) {
      return fr[1] != null
          ? 'Ça va bien, merci ! Que puis-je faire pour toi ?'
          : 'Bonjour ! Que puis-je faire pour toi ?';
    }
    final es = _greetEs.firstMatch(q);
    if (es != null) {
      return es[1] != null
          ? '¡Muy bien, gracias! ¿En qué puedo ayudarte?'
          : '¡Hola! ¿En qué puedo ayudarte?';
    }
    return null;
  }

  static final _thanksEn = RegExp(
    r"^(?:ok(?:ay)?[,\s]+)?(?:thanks|thank you)(?: (?:so|very) much)?"
    r"(?:[,!\s]+that(?:'s| is| was)? (?:helps?|helpful|great))?\s*[.!]*$",
    caseSensitive: false,
  );
  static final _thanksFr = RegExp(
    r"^merci(?: beaucoup| bien)?\s*[.!]*$",
    caseSensitive: false,
  );
  static final _thanksEs = RegExp(
    r"^(?:muchas )?gracias(?: mil)?\s*[.!]*$",
    caseSensitive: false,
  );
  static final _greetEn = RegExp(
    r"^(?:hi|hello|hey|hiya|good (?:morning|afternoon|evening))"
    r"(?:[,!\s]+(?:there|again|friend))?(?:[,!\s]+"
    r"(how are you(?: doing)?(?: today)?|how(?:'s|’s| is) it going))?"
    r"\s*[?.!]*$",
    caseSensitive: false,
  );
  static final _greetFr = RegExp(
    r"^(?:bonjour|salut|bonsoir|coucou)(?:[,!\s]+(ça va|comment ça va|"
    r"comment vas-tu|comment allez-vous))?\s*[?.!]*$",
    caseSensitive: false,
    unicode: true,
  );
  static final _greetEs = RegExp(
    r"^¡?(?:hola|buenos d[íi]as|buenas tardes|buenas noches|buenas)"
    r"(?:[,!\s]+(?:buenos d[íi]as|buenas tardes|buenas noches))?"
    r"(?:[,!\s]+¿?(qu[ée] tal|c[óo]mo est[áa]s))?\s*[?.!]*$",
    caseSensitive: false,
    unicode: true,
  );

  /// Words that make an introduction a request too.
  static final _request = RegExp(
    r"(?<![\p{L}])(?:can you|could you|please|tell me|help me|ask|want|need|"
    r"would like|what|how|why|when|where|who|which|peux-tu|pourrais-tu|"
    r"s'il te pla[iî]t|dis-moi|veux|voudrais|besoin|puedes|podr[íi]as|"
    r"por favor|dime|quiero|necesito|help (?:me|us|with)|"
    // "I fix cars", "je répare des vélos", "yo escribo": what the user
    // does, not a request (audit, 2026-10-20).
    r"(?<!\b(?:i|we|je|j['’]|nous|yo) )(?:fix|write|explain|corrige|"
    r"r[ée]pare|[ée]cris|explique|arregla|escribe|explica)|"
    r"show me|aide-moi|aidez-moi|pourquoi|"
    r"comment|ay[úu]dame|por qu[ée]|c[óo]mo)(?![\p{L}])",
    caseSensitive: false,
    unicode: true,
  );

  static final _problemStatement = RegExp(
    r"\b(?:get|getting|receive|receiving|have|having|hit|seeing) (?:this |an? |the )?(?:error|exception|problem)\b"
    r"|\b(?:crash(?:es|ing)?|fails?|failing|broken|not working)\b"
    r"|\b(?:j['’](?:ai|obtiens)|je (?:reçois|rencontre)) (?:une? |cette? )?(?:erreur|probl[èe]me)\b"
    // "Ma plante", "une plante" is a plant; "l'appli plante" a crash.
    r"|(?<!\b(?:ma|ta|sa|une|la|les|mes|tes|ses|cette|des|de) )\bplante\b"
    r"|\bne fonctionne pas\b"
    r"|\b(?:recibo|tengo|veo|aparece|sale) (?:un[oa]? |est[ea] |el |la )?(?:error|problema|fallo)\b"
    r"|\b(?:falla|no funciona)\b",
    caseSensitive: false,
    unicode: true,
  );

  /// "My name is Robin", "je m'appelle Léa", "me llamo Ana".
  static final _gaveName = RegExp(
    r"\b(?:my name is|my name['’]s|call me|je m['’]appelle|mon (?:nom|prénom) est|me llamo|mi nombre es)\s+(\p{L}[\p{L}'’-]*)",
    caseSensitive: false,
    unicode: true,
  );
  static const _notAName = {'not', 'a', 'an', 'the', 'pas', 'un', 'une', 'no'};

  /// Whether [input] asks about the user's own facts.
  ///
  /// A request is not one: "My name is Robin, can you help me write a
  /// cover letter?" had its "My name…" turned into "Your name…" (audit
  /// 2026-10-20). Each sentence is judged alone, so "I have two cats. What
  /// food is best for them?" is not one either.
  static bool asks(String input) {
    final t = input.trim();
    if (_advice.hasMatch(t) || _task.hasMatch(t)) return false;
    if (_always.hasMatch(t)) return true;
    for (final s in t.split(RegExp(r'(?<=[.!?])\s+'))) {
      final q = s.trim();
      if (_asksPetName(q)) return true;
      if ((_opener.hasMatch(q) || q.endsWith('?')) && _personal.hasMatch(q)) {
        return true;
      }
    }
    return false;
  }

  /// A task for the assistant, EN/FR/ES.
  static final _task = RegExp(
    r"\b(?:can|could|would|will) you (?!(?:please )?(?:remember|recall|remind|tell me (?:my|what|where|who|how|if|whether|which)|say (?:my|what|who)))"
    r"|\bhelp me\b|^(?:please )?(?:write|draft|compose|rewrite|translate|summari[sz]e|fix|create|make|generate|give me)\b"
    r"|\b(?:write|draft|compose) (?:me |a |an |my )"
    r"|\b(?:peux-tu|pouvez-vous|pourrais-tu|pourriez-vous) (?!(?:me )?(?:rappeler|dire (?:mon|ma|mes|qui|o[ùu]|comment)))|\baide-moi\b|\b[ée]cri(?:s|vez)(?:-moi)?\b|\bayúdame\b|\b(?:puedes|podrías) (?!(?:recordarme|decirme (?:mi|mis|qui[ée]n|d[óo]nde|c[óo]mo)))|\bescr[íi]be(?:me)?\b",
    caseSensitive: false,
    unicode: true,
  );

  /// Questions that can only be about the user.
  static final _always = RegExp(
    r"\b(?:who am I|where am I from|what(?:'s|’s| is) my name|what did I (?:just )?(?:say|tell you)|do you (?:know|remember) (?:where I|who I|what I))\b"
    r"|comment je m['’]appelle|qui suis-je|o[ùu] (?:est-ce que )?j['’]habite"
    r"|c[óo]mo me llamo|qui[ée]n soy|d[óo]nde vivo",
    caseSensitive: false,
    unicode: true,
  );

  static final _opener = RegExp(
    r"^(?:(?:and|so|ok(?:ay)?|now|then|hey|et|y)[,\s]+)?(?:what|what's|whats|which|where|who|how many|how old|how much|do you|tell me|remind me|quel(?:le)?s?|o[ùu]|combien|comment|cu[áa]l(?:es)?|d[óo]nde|cu[áa]nt[oa]s?|c[óo]mo|¿)",
    caseSensitive: false,
    unicode: true,
  );

  static final _personal = RegExp(
    r"\bmy (?:name|age|birthday|job|work|city|town|country|home|address|wife|husband|partner|girlfriend|boyfriend|kids?|children|sons?|daughters?|brothers?|sisters?|mother|father|mom|mum|dad|parents|favou?rite)\b"
    r"|\b(?:do|did) I (?:live|work|have|own|like|love|study)\b"
    r"|\bam I from\b"
    r"|\b(?:mon (?:nom|âge|mari|travail)|ma (?:ville|femme|fille)|mes enfants)\b"
    r"|\b(?:mi (?:nombre|edad|ciudad|esposa|esposo|trabajo)|mis hijos)\b",
    caseSensitive: false,
    unicode: true,
  );

  /// Possession alone does not make a pet or object question personal.
  /// Names the user gave remain a genuine recall question.
  static bool _asksPetName(String input) {
    final names = _namesQuestion.firstMatch(input);
    if (names != null && _petNoun.hasMatch((names[1] ?? names[2])!)) {
      return true;
    }
    final question = input.replaceFirst(_recallPrefix, 'What is ');
    final fact = _factQuestion.firstMatch(question);
    return (fact != null && _petNameKey.hasMatch(fact[1]!)) ||
        _petNameOther.hasMatch(input);
  }

  static final _petNoun = RegExp(
    r'^(?:cats?|dogs?|pets?)$',
    caseSensitive: false,
  );
  static final _petNameKey = RegExp(
    r"^(?:cats?|dogs?|pets?)(?:['’]s?)? names?$",
    caseSensitive: false,
  );
  static final _recallPrefix = RegExp(
    r'^(?:(?:can|could) you (?:please )?)?(?:tell|remind) me (?:of )?',
    caseSensitive: false,
  );
  static final _petNameOther = RegExp(
    r"^(?:quel est le nom de|quels sont les noms de|comment s['’]appelle(?:nt)?) (?:mon|ma|mes) (?:chats?|chattes?|chiens?|chiennes?)\s*[?.!]*$"
    r"|^¿?(?:cu[áa]l es el nombre de|cu[áa]les son los nombres de|c[óo]mo se llaman?) (?:mi|mis) (?:gatos?|gatas?|perros?|perras?|mascotas?)\s*[?.!]*$",
    caseSensitive: false,
    unicode: true,
  );

  /// Advice about the user's things is not a question about them.
  static final _advice = RegExp(
    r"\b(?:should|could|can|would|shall) (?:I|my|we)\b|\bhow (?:do|can|should|could) I\b|\bwhat (?:to|should)\b",
    caseSensitive: false,
  );
}

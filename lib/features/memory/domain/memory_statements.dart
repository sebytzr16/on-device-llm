/// Recognizes explicit personal declarations without sending them to a model.
/// The predicates supply the meaning; quoted, hypothetical and temporary
/// clauses are not evidence about the user's current life.
class MemoryStatements {
  static final _greeting = RegExp(
    r'^(?:(?:hi|hello|hey)(?: there| everyone| folks)?|good (?:morning|afternoon|evening)|bonjour|bonsoir|salut|hola|buenos días|buenas tardes|buenas noches)[\s,:!–—-]+',
    caseSensitive: false,
  );
  static final _intro = RegExp(
    r'^(?:by the way|btw|for context|just so you know|just to let you know|as for me|pour information|au fait|d[’\x27]ailleurs|por cierto|and|also|et|y)[,:\s]+',
    caseSensitive: false,
  );
  // "My favourite colour is green, by the way.": the aside is not part of
  // the value (Conversation probe, 2026-10-20, saved "green, by the way").
  static final _outro = RegExp(
    r'[,\s]+(?:by the way|btw|anyway|au fait|d[’\x27]ailleurs|por cierto)(?=[\s.!;]*$)',
    caseSensitive: false,
  );
  static final _fictionRequest = RegExp(
    r'^(?:(?:example|sample|quote|translation|roleplay|scenario)\s*:|(?:please\s+)?(?:pretend|role[- ]?play|imagine|suppose|translate|write (?:me )?(?:a|an|the) (?:story|script|example)|here (?:is|are) (?:a |an |some )?(?:quote|example|sample)|let[’\x27]s (?:pretend|role[- ]?play))\b)|\b(?:in this (?:story|roleplay|scenario)|my character|as a fictional character|just kidding|only joking|that was a joke)\b',
    caseSensitive: false,
  );
  static final _unsafe = RegExp(
    r"\b(?:not|never|no longer|don['’]?t|doesn['’]?t|isn['’]?t|aren['’]?t|wasn['’]?t|weren['’]?t|can['’]?t|won['’]?t|haven['’]?t|used to|formerly|previously|if|unless|would|might|maybe|perhaps|wish|hope to|want to (?:be|become)|plan to|going to (?:be|become)|pretending|joking|kidding|actually a joke|right now|at the moment|today|tonight|tomorrow|yesterday|this (?:morning|afternoon|evening|week|weekend|month)|next (?:week|month|year)|for (?:a|one) day|in (?:a|the) (?:game|video game|dream|story|simulation)|ne .+ pas|ne .+ plus|jamais|si|peut-être|voudrais|aujourd’hui|aujourd'hui|demain|maintenant|no|nunca|antes|quizás|quisiera|hoy|mañana|ahora)\b",
    caseSensitive: false,
  );
  static final _question = RegExp(
    r'^(?:what|who|where|when|why|how|which|can|could|would|should|do|does|did|am|are|is|any (?:tips|ideas|suggestions)|ideas|tell me|explain|show me|give me|please|quel|quelle|quels|quelles|comment|pourquoi|est-ce|qué|cuál|cómo|por qué)\b',
    caseSensitive: false,
  );
  static final _passingState = RegExp(
    r"^(?:i (?:am|feel|need|want|am feeling)|i['’]m|je suis|soy|estoy)\s+(?:very\s+)?(?:tired|hungry|thirsty|sad|happy|angry|bored|excited|cold|hot|sleepy|upset|worried|a summary|help|to\b|fatigué|fatiguée|content|triste|cansado|cansada|feliz)\b",
    caseSensitive: false,
  );
  static final _personal = RegExp(
    r"^(?:i\b|i['’]m\b|im\b|my\b|we\b|our\b|call me\b|you can call me\b|je\b|j['’]|mon\b|ma\b|mes\b|moi\b|appelez-moi\b|tu peux m['’]appeler\b|yo\b|soy\b|trabajo\b|vivo\b|resido\b|hablo\b|prefiero\b|tengo\b|uso\b|utilizo\b|me llamo\b|mi\b|mis\b|puedes llamarme\b)",
    caseSensitive: false,
  );
  static final _thirdParty = RegExp(
    r"^(?:my|mon|ma|mi)\s+(friend|wife|husband|partner|mother|father|mom|mum|dad|brother|sister|son|daughter|boss|colleague|coworker|neighbor|ami|amie|mère|père|frère|sœur|amigo|amiga|madre|padre|hermano|hermana)\b",
    caseSensitive: false,
  );

  /// Broad vocabulary only disambiguates bare "I am a …" identities.
  /// Explicit employment predicates support unfamiliar job titles too.
  static const occupations = {
    'chef',
    'cook',
    'baker',
    'barista',
    'bartender',
    'server',
    'waiter',
    'waitress',
    'butcher',
    'farmer',
    'gardener',
    'florist',
    'nurse',
    'doctor',
    'physician',
    'surgeon',
    'dentist',
    'pharmacist',
    'veterinarian',
    'paramedic',
    'midwife',
    'physiotherapist',
    'therapist',
    'psychologist',
    'psychiatrist',
    'dietitian',
    'nutritionist',
    'teacher',
    'professor',
    'lecturer',
    'tutor',
    'researcher',
    'scientist',
    'engineer',
    'developer',
    'programmer',
    'architect',
    'designer',
    'illustrator',
    'artist',
    'photographer',
    'videographer',
    'filmmaker',
    'editor',
    'writer',
    'author',
    'journalist',
    'translator',
    'interpreter',
    'librarian',
    'accountant',
    'bookkeeper',
    'auditor',
    'lawyer',
    'attorney',
    'paralegal',
    'consultant',
    'analyst',
    'manager',
    'receptionist',
    'administrator',
    'secretary',
    'recruiter',
    'salesperson',
    'retailer',
    'entrepreneur',
    'mechanic',
    'electrician',
    'plumber',
    'carpenter',
    'welder',
    'technician',
    'machinist',
    'builder',
    'roofer',
    'painter',
    'driver',
    'chauffeur',
    'pilot',
    'sailor',
    'firefighter',
    'police officer',
    'security guard',
    'social worker',
    'support worker',
    'flight attendant',
    'software engineer',
    'software developer',
    'web developer',
    'data scientist',
    'data analyst',
    'project manager',
    'product manager',
    'graphic designer',
    'interior designer',
    'registered nurse',
    'nurse practitioner',
    'head chef',
    'executive chef',
    'sous chef',
    'pastry chef',
    'professional chef',
    'line cook',
    'cuisinier',
    'cuisinière',
    'pâtissier',
    'pâtissière',
    'boulanger',
    'boulangère',
    'serveur',
    'serveuse',
    'infirmier',
    'infirmière',
    'médecin',
    'enseignant',
    'enseignante',
    'professeur',
    'ingénieur',
    'ingénieure',
    'développeur',
    'développeuse',
    'comptable',
    'avocat',
    'avocate',
    'mécanicien',
    'électricien',
    'plombier',
    'photographe',
    'architecte',
    'cocinero',
    'cocinera',
    'panadero',
    'panadera',
    'camarero',
    'camarera',
    'enfermero',
    'enfermera',
    'médico',
    'médica',
    'maestro',
    'maestra',
    'profesor',
    'profesora',
    'ingeniero',
    'ingeniera',
    'programador',
    'programadora',
    'diseñador',
    'diseñadora',
    'contador',
    'contadora',
    'abogado',
    'abogada',
    'mecánico',
    'electricista',
    'fontanero',
    'fotógrafo',
    'fotógrafa',
    'veterinario',
    'veterinaria',
  };

  static RegExp _pattern(String body) =>
      RegExp(body, caseSensitive: false, unicode: true);
  static final _employment = _pattern(
    r"^(?:i (?:work|am (?:currently )?(?:working|employed)) as|i['’]m (?:working|employed) as|my (?:job|profession|occupation|career) is|je travaille comme|mon (?:métier|emploi) est|trabajo (?:como|de)|mi (?:profesión|trabajo) es)\s+(?:(?:a|an|un|une|una)\s+)?(.+)$",
  );
  static final _employmentSuffix = _pattern(
    r"^(?:i work|i am working|i['’]m working) (in|at|for) (.+?) as (?:a |an )?(.+)$",
  );
  static final _identity = _pattern(
    r"^(?:i am|i['’]m|im|je suis|soy|yo soy)\s+(?:(?:currently|also)\s+)*(?:(?:a|an|un|une|una)\s+)?(.+)$",
  );
  static final _name = _pattern(
    r"^(?:my (?:full )?name is|call me|you can call me|i go by|je m['’]appelle|mon (?:prénom|nom) est|appelez-moi|tu peux m['’]appeler|me llamo|mi nombre es|puedes llamarme)\s+(.+)$",
  );
  static final _home = _pattern(
    r"^(?:i live in|my home is in|i am based in|i['’]m based in|j['’]habite (?:à|a|en)|je vis (?:à|en)|vivo en|resido en)\s+(.+)$",
  );
  static final _origin = _pattern(
    r"^(?:i am from|i['’]m from|je viens de|soy de)\s+(.+)$",
  );
  static final _language = _pattern(r'^(?:i speak|je parle|hablo)\s+(.+)$');
  static final _preference = _pattern(
    r'^(?:i prefer|je préfère|prefiero)\s+(.+)$',
  );
  static final _allergy = _pattern(
    r"^(?:i am allergic to|i['’]m allergic to|je suis allergique (?:à|aux)|soy alérgic[oa] (?:a|al))\s+(.+)$",
  );
  static final _diet = _pattern(
    r"^(?:i (?:am|follow|eat)|i['’]m|je suis|soy)\s+(?:(?:a|an|un|une|una)\s+)?(vegan|vegetarian|pescatarian|végétarien|végétarienne|végétalien|végétalienne|vegetariano|vegetariana|vegano|vegana|(?:a )?(?:vegan|vegetarian|ketogenic|gluten-free|dairy-free) diet)$",
  );
  static final _own = _pattern(
    r"^(?:i own|je possède|soy dueño de|soy dueña de)\s+(.+)$",
  );
  static final _use = _pattern(r"^(?:i use|j['’]utilise|uso|utilizo)\s+(.+)$");
  static final _family = _pattern(
    r"^(?:i have|j['’]ai|tengo)\s+((?:(?:a|an|one|two|three|four|five|un|une|deux|trois|uno|una|dos|tres|\d+)\s+)?(?:children|kids|sons|daughters|child|son|daughter|dog|dogs|cat|cats|pet|pets|enfant|enfants|chien|chiens|chat|chats|hijo|hijos|hija|hijas|perro|perros|gato|gatos)(?:\s+(?:named|called|qui s['’]appelle|llamado|llamada)\s+.+|,\s*.+)?)$",
  );
  // "two cats, Milo and Luna": after a comma, only names (Conversation
  // probe, 2026-10-20: the 0.8B answered "You are talking about two cats").
  static final _namesAfterComma = RegExp(
    r"^[^,]+,\s*\p{Lu}[\p{L}'’-]*(?:(?:,\s*|,?\s+(?:and|et|y)\s+)\p{Lu}[\p{L}'’-]*)*$",
    unicode: true,
  );
  static final _petName = _pattern(
    r"^my (dog|cat|pet)(?: is (?:called|named)|['’]s name is)\s+(.+)$",
  );
  static final _favourite = _pattern(
    r"^my (favou?rite (?:colou?r|food|language|sport|hobby|book|music|animal)) is\s+(.+)$",
  );

  /// "Ma couleur préférée est le bleu", "Mi color favorito es el azul":
  /// saved with the English name of the favourite.
  static final _favouriteFr = _pattern(
    r"^(?:ma|mon) (couleur|nourriture|plat|langue|sport|loisir|livre|musique|animal) pr[ée]f[ée]r[ée]e? (?:est|c['’]est)\s+(?:(?:le|la|les)\s+|l['’])?(.+)$",
  );
  static final _favouriteEs = _pattern(
    r"^mi (color|comida|plato|idioma|deporte|pasatiempo|libro|m[úu]sica|animal) favorit[oa] es\s+(?:(?:el|la|los|las)\s+)?(.+)$",
  );
  static const _favouriteNames = {
    'couleur': 'colour',
    'nourriture': 'food',
    'plat': 'food',
    'langue': 'language',
    'loisir': 'hobby',
    'livre': 'book',
    'musique': 'music',
    'color': 'colour',
    'comida': 'food',
    'plato': 'food',
    'idioma': 'language',
    'deporte': 'sport',
    'pasatiempo': 'hobby',
    'libro': 'book',
    'música': 'music',
    'musica': 'music',
  };
  static final _relationship = _pattern(
    r"^(?:i am|i['’]m)\s+(married|single|divorced|widowed)$",
  );
  static final _project = _pattern(
    r"^(?:i am|i['’]m|im)\s+(?:currently\s+)?(building|developing|working on)\s+(.+)$",
  );

  // Active projects remain useful beyond a single turn. Only remove time
  // qualifiers from a clear project declaration, not from passing states.
  static String _projectContext(String text) => text.replaceAllMapped(
    _pattern(
      r"(?:i am|i['’]m|im)\s+(?:currently\s+)?(?:building|developing|working on)\s+[^.!?;\n]+",
    ),
    (m) => m[0]!.replaceAll(_pattern(r'\s+(?:at the moment|right now)\b'), ''),
  );

  static String _clean(String clause) {
    var text = clause.trim().replaceAll(RegExp(r'\s+'), ' ');
    text = text
        .replaceFirst(_greeting, '')
        .replaceFirst(_intro, '')
        .replaceFirst(_outro, '');
    return text.trim();
  }

  static String _unquoteValue(String value) =>
      value.trim().replaceAll(RegExp(r'''^["“”‘’']+|["“”‘’']+$'''), '').trim();

  static String _maskQuotes(String message) => message
      .replaceAll(RegExp(r'^\s*>.*$', multiLine: true), ' ')
      .replaceAll(RegExp(r'```.*?```|`[^`]*`', dotAll: true), ' ')
      .replaceAll(
        RegExp(
          r"'(?:I(?:['’]m| am| work)|My |Je suis|Soy )[^'\n]*'",
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAllMapped(RegExp(r'"[^"]*"|“[^”]*”|‘[^’]*’', dotAll: true), (m) {
        // A quoted value such as "Sam" is fine; a quoted persona is not.
        return RegExp(
              r"\b(?:i|i['’]m|my|je|mon|ma|soy|mi|me llamo)\b",
              caseSensitive: false,
            ).hasMatch(m[0]!)
            ? ' '
            : m[0]!;
      });

  /// Sentences and independent clauses, retaining question punctuation.
  static List<String> clauses(String message) {
    // Preserve periods inside names/places, rather than saving "Dr" or "St"
    // as the whole value. Restore them before matching a declaration.
    final text = _projectContext(_maskQuotes(message)).replaceAllMapped(
      RegExp(r'\b(?:Mr|Mrs|Ms|Dr|Prof|St|Jr|Sr|Mt|[A-Z])\.(?=\s+[A-Z])'),
      (m) => m[0]!.replaceAll('.', '\uF000'),
    );
    final parts = [
      for (final m in RegExp(
        r'.+?(?:[.!?;]+(?=\s|$)|\n|$)',
        dotAll: true,
      ).allMatches(text))
        if (m[0]!.trim().isNotEmpty) _clean(m[0]!.replaceAll('\uF000', '.')),
    ];
    final independent = [
      for (final part in parts)
        // A hypothetical or temporary context also applies to clauses inside
        // that sentence. Do not turn the second clause into a real persona.
        if (_unsafe.hasMatch(part))
          part
        else
          ...part
              .replaceAllMapped(
                _pattern(
                  // ", and so please look up…": a request after the fact
                  // (the tester's phone chat, 2026-10-19).
                  r',\s*(?:(?:and|but|also|so|then|et|y|mais|pero|alors|donc|entonces|as[ií] que)\s+)?(?:(?:so|then|alors|donc|entonces|as[ií] que)\s+)?(?=(?:what|who|how|why|where|which|can|could|any\b|ideas|i\b|i[’\x27]m|my\b|je\b|j[’\x27]|mon\b|ma\b|soy\b|mi\b|vivo\b|please\b|look\b|find\b|search\b|show\b|tell\b|give\b|check\b|help\b|recommend\b|suggest\b|s[’\x27]il\b|peux\b|pourrais\b|cherche\b|trouve\b|dis-moi\b|montre\b|por favor\b|busca\b|dime\b|puedes\b|podr[ií]as\b|muestra\b))|\s+(?:and|but|et|y|mais|pero)\s+(?=(?:i\b|i[’\x27]m|my\b|je\b|j[’\x27]|mon\b|ma\b|soy\b|mi\b|vivo\b))',
                ),
                (_) => '\n',
              )
              .split('\n')
              .map(_clean),
    ];
    // A comma-separated adjective shares its explicit first-person subject:
    // "I'm a nurse, allergic to peanuts". Never inherit across a sentence.
    return [
      for (final part in independent)
        if (_pattern(r"^(?:i am|i['’]m)\b").hasMatch(part) &&
            !_unsafe.hasMatch(part))
          ...part
              .splitMapJoin(
                RegExp(
                  r',\s*(?=(?:allergic to|based in)\b)',
                  caseSensitive: false,
                ),
                onMatch: (_) => '\nI am ',
              )
              .split('\n')
        else
          part,
    ];
  }

  static bool _safe(String clause) =>
      !clause.endsWith('?') &&
      !clause.startsWith('>') &&
      !_question.hasMatch(clause) &&
      !_passingState.hasMatch(clause) &&
      !_unsafe.hasMatch(clause);

  static String _bare(String clause) =>
      clause.replaceFirst(RegExp(r'[.!;]+$'), '').trim();

  /// Evidence used to ground model-generated notes. Never ground a current
  /// persona in a question, a denial, a roleplay, or somebody else's job.
  static String groundingSource(String message, {String fact = ''}) {
    if (_fictionRequest.hasMatch(_clean(message))) return '';
    if (fact.isNotEmpty && _retracted(fact, clauses(message))) return '';
    return [
      for (final clause in clauses(message))
        if (_safe(clause) &&
            _personal.hasMatch(clause) &&
            (_thirdParty.firstMatch(clause) == null ||
                fact.toLowerCase().contains(
                  _thirdParty.firstMatch(clause)![1]!.toLowerCase(),
                )))
          _bare(clause),
    ].join('\n');
  }

  static bool relationMatches(String fact, String source) {
    final text = fact.toLowerCase();
    // A model must not turn a positive declaration into a denial, or save a
    // quoted persona/question. Manual notes do not go through this guard.
    if (!_pattern(r"^(?:the )?user(?:['’]s)?\b").hasMatch(text) ||
        !_safe(text)) {
      return false;
    }
    final statements = clauses(source).where(_safe).map(_bare).toList();
    bool has(RegExp predicate) => statements.any(predicate.hasMatch);
    if (RegExp(r'\bowns?\b').hasMatch(text) && !has(_own)) return false;
    if (RegExp(r'\buses?\b').hasMatch(text) && !has(_use)) return false;
    if (RegExp(r'\b(?:has|have)\b').hasMatch(text) &&
        !has(_pattern(r"^(?:i have|j['’]ai|tengo|my\b)"))) {
      return false;
    }
    if (text.contains('allergic') && !has(_allergy)) return false;
    final job = _pattern(
      r'^(?:the )?user (?:is|works as) (?:a|an) (.+)$',
    ).firstMatch(text);
    if (job != null &&
        occupations.any((o) => job[1] == o || job[1]!.startsWith('$o '))) {
      return statements.any(
        (s) =>
            _employment.hasMatch(s) ||
            _employmentSuffix.hasMatch(s) ||
            _job(_identity.firstMatch(s)?[1] ?? '') != null,
      );
    }
    return true;
  }

  static bool _value(String value, {int words = 12}) =>
      value.isNotEmpty &&
      value.length <= 140 &&
      value.split(' ').length <= words &&
      !RegExp(
        r'https?://|[{}<>?!;]|\b(?:you|someone|something|anything|whatever|it|them|this|that|tomorrow|later|only|just|fear|dream|imaginary|fictional|secret|unknown)\b',
        caseSensitive: false,
      ).hasMatch(value);

  static String? _job(String raw, {bool explicitEmployment = false}) {
    var value = raw
        .replaceFirst(
          RegExp(r'\s+(?:by profession|for a living)$', caseSensitive: false),
          '',
        )
        .trim();
    if (!_value(
          value.replaceAll(_pattern(r'\bit\b'), 'information technology'),
          words: 12,
        ) ||
        _pattern(
          r'^(?:to\b|happy\b|sad\b|tired\b|hungry\b|angry\b|joke\b|prank\b|secret\b|unknown\b)',
        ).hasMatch(value)) {
      return null;
    }
    final rawRole = value
        .split(RegExp(r'\s+(?:in|at|for|dans|à|en|a)\s+', caseSensitive: false))
        .first;
    final role = rawRole.toLowerCase().replaceFirst(
      _pattern(r'^self taught\b'),
      'self-taught',
    );
    final baseRole = role
        .replaceFirst(
          _pattern(
            r'^(?:self[- ]taught|certified|experienced|freelance|independent|professional)\s+',
          ),
          '',
        )
        .replaceFirst(
          _pattern(
            r'^(?:it|information technology|computer|electronics|network|support)\s+(?=technician$)',
          ),
          '',
        );
    if (!explicitEmployment && !occupations.contains(baseRole)) return null;
    value =
        '${role.replaceAll(_pattern(r'\bit\b'), 'IT')}${value.substring(rawRole.length)}';
    return 'The user is a $value';
  }

  static String? _fact(String clause) {
    final project = _project.firstMatch(clause);
    if (project != null &&
        _value(project[2]!, words: 18) &&
        _pattern(
          r'\b(?:apps?|applications?|software|websites?|projects?)\b',
        ).hasMatch(project[2]!)) {
      return 'The user is ${project[1]} ${project[2]}';
    }
    var match = _employment.firstMatch(clause);
    if (match != null) return _job(match[1]!, explicitEmployment: true);
    match = _employmentSuffix.firstMatch(clause);
    if (match != null && _value(match[2]!)) {
      final job = _job(match[3]!, explicitEmployment: true);
      if (job != null) return '$job ${match[1]} ${match[2]}';
    }
    match = _name.firstMatch(clause);
    if (match != null) {
      final value = _unquoteValue(match[1]!);
      if (_value(value, words: 5) &&
          RegExp(
            r"^[\p{L}][\p{L}\p{M} .\-'’]*$",
            unicode: true,
          ).hasMatch(value)) {
        return "The user's name is $value";
      }
    }
    match = _allergy.firstMatch(clause);
    if (match != null && _value(match[1]!)) {
      return 'The user is allergic to ${match[1]}';
    }
    match = _diet.firstMatch(clause);
    if (match != null) {
      return 'The user follows a ${match[1]} diet'.replaceAll(
        ' diet diet',
        ' diet',
      );
    }
    match = _home.firstMatch(clause);
    if (match != null && _value(match[1]!)) {
      return 'The user lives in ${match[1]}';
    }
    match = _origin.firstMatch(clause);
    if (match != null && _value(match[1]!)) {
      return 'The user is from ${match[1]}';
    }
    match = _language.firstMatch(clause);
    if (match != null && _value(match[1]!)) {
      return 'The user speaks ${match[1]}';
    }
    match = _preference.firstMatch(clause);
    if (match != null &&
        _value(match[1]!) &&
        !RegExp(
          r'^(?:you|to (?:find|search|buy|go|visit|take|plan))\b',
          caseSensitive: false,
        ).hasMatch(match[1]!)) {
      return 'The user prefers ${match[1]}';
    }
    match = _own.firstMatch(clause);
    if (match != null && _value(match[1]!)) return 'The user owns ${match[1]}';
    match = _use.firstMatch(clause);
    if (match != null && _value(match[1]!)) return 'The user uses ${match[1]}';
    match = _family.firstMatch(clause);
    if (match != null &&
        _value(match[1]!) &&
        (!match[1]!.contains(',') || _namesAfterComma.hasMatch(match[1]!))) {
      return 'The user has ${match[1]}';
    }
    match = _petName.firstMatch(clause);
    if (match != null && _value(match[2]!, words: 4)) {
      return "The user's ${match[1]} is named ${_unquoteValue(match[2]!)}";
    }
    match = _favourite.firstMatch(clause);
    if (match != null && _value(match[2]!)) {
      return "The user's ${match[1]} is ${match[2]}";
    }
    match = _favouriteFr.firstMatch(clause) ?? _favouriteEs.firstMatch(clause);
    if (match != null && _value(match[2]!)) {
      final name = match[1]!.toLowerCase();
      return "The user's favourite ${_favouriteNames[name] ?? name} is "
          '${match[2]}';
    }
    match = _relationship.firstMatch(clause);
    if (match != null) return 'The user is ${match[1]}';
    match = _identity.firstMatch(clause);
    if (match != null) return _job(match[1]!);
    return null;
  }

  static List<String> extract(String message) {
    if (_fictionRequest.hasMatch(_clean(message))) return const [];
    final result = <String>[];
    final statements = clauses(message);
    for (final clause in statements) {
      if (!_safe(clause)) continue;
      final fact = _fact(_bare(clause));
      if (fact != null && !_retracted(fact, statements)) result.add(fact);
    }
    return result;
  }

  static bool _retracted(String fact, List<String> statements) {
    final words = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(fact.toLowerCase())
        .map((m) => m[0]!)
        .where(
          (w) =>
              w.length >= 2 &&
              !{
                'user',
                'name',
                'named',
                'lives',
                'speaks',
                'prefers',
                'owns',
                'uses',
                'diet',
                'allergic',
                'follows',
                'the',
                'is',
                'in',
                'to',
                'as',
                'has',
              }.contains(w),
        )
        .toSet();
    return statements.any((raw) {
      final s = raw.replaceFirst(
        _pattern(r'^(?:actually|correction|sorry|no)[,:\s]+'),
        '',
      );
      return _thirdParty.firstMatch(s) == null &&
          _personal.hasMatch(s) &&
          RegExp(
            r"\b(?:not|no longer|never|don['’]t|ne .+ pas|nunca|no)\b",
            caseSensitive: false,
          ).hasMatch(s) &&
          words.any(
            (w) => RegExp(
              '\\b${RegExp.escape(w)}\\b',
              caseSensitive: false,
            ).hasMatch(s),
          );
    });
  }

  static bool retracts(String fact, String message) =>
      !_fictionRequest.hasMatch(_clean(message)) &&
      _retracted(fact, clauses(message));

  static bool needsModel(String message) {
    if (_fictionRequest.hasMatch(_clean(message))) return false;
    return clauses(
      message,
    ).any((c) => _safe(c) && _personal.hasMatch(c) && _fact(_bare(c)) == null);
  }
}

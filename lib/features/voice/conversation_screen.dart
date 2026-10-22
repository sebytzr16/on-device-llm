import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../../core/motion/motion.dart';
import '../chat/domain/entities/chat_message.dart';
import '../chat/domain/entities/turn_run.dart';
import '../chat/domain/retrieval_plan.dart';
import '../chat/presentation/providers/chat_model_pins.dart';
import '../chat/presentation/providers/chat_provider.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../settings/presentation/providers/settings_provider.dart';
import '../tools/phone_actions.dart';
import '../tools/presentation/phone_action_cards.dart';
import 'conversation_model.dart';
import 'sherpa_voice.dart';
import 'voice_models.dart';
import 'voice_models_provider.dart';
import 'voice_pipeline.dart';
import 'voice_service.dart';

part 'conversation_widgets.dart';
part 'conversation_wave.dart';

enum ConversationPhase { starting, idle, listening, thinking, speaking }

/// Conversation mode (tester, 2026-10-07): a full-screen, hands-free voice
/// chat. The remote connection answers when one is on (tester, 2026-10-18),
/// otherwise a model on the phone (Qwen3.5 0.8B); Whisper listens the whole time
/// (echo-cancelled), Kokoro speaks each sentence as soon as it is written,
/// and talking over the answer interrupts it. The turns are saved as a
/// normal chat. Without the on-device voice, the system recognizer and
/// voice take turns instead.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key});

  /// True while the screen is open (the chat screen then does not read
  /// answers aloud itself).
  static var open = false;

  /// Reading sizes of the Conversation screen: larger than chat so the
  /// answer reads from arm's length.
  static const answerFontSize = 22.0;
  static const captionFontSize = 18.0;

  /// How the model is asked to answer when its words are spoken.
  static const spokenStyle =
      'The user is talking with you by voice and hears your answer read '
      'aloud. Answer in one to three short spoken sentences in plain words, '
      'in the language the user speaks. No markdown, lists, tables, code, '
      'links or emoji. Say numbers, dates and units the '
      'way people say them. What the user tells you about themself is '
      'theirs, never yours. For facts that change (news, prices, weather, '
      'scores, people in office), use only the web results given with the '
      'question; without them, say you could not check. Answer only the '
      'latest question; give the answer itself right away, never a promise '
      'to answer in a moment. If the request is unclear, ask one short '
      'question.';

  /// [spokenStyle] for a remote model, which searches by itself (the
  /// remote brain): changing facts are looked up, never guessed.
  static const spokenStyleRemote =
      'The user is talking with you by voice and hears your answer read '
      'aloud. Answer in one to three short spoken sentences in plain words, '
      'in the language the user speaks. No markdown, lists, tables, code, '
      'links, citation numbers or emoji. Say numbers, dates and units the '
      'way people say them. For facts that change (news, prices, weather, '
      'scores, people in office), search first and answer from what you '
      'found; never guess them. Use what the user told you earlier in the '
      'conversation. Answer only the latest question; give the answer '
      'itself right away, never a promise to answer in a moment or a '
      'question about whether to look further. If the request is unclear, '
      'ask one short question.';

  /// [style] asking for the answer length the tester chose ([most]
  /// sentences, 0: as long as the question needs; Settings › Voice).
  static String styled(String style, int most) {
    const short = 'Answer in one to three short spoken sentences';
    if (most > 0 && most <= 3) return style;
    return style.replaceFirst(
      short,
      most == 0
          ? 'Answer as fully as the question needs, in short spoken sentences'
          : 'Answer in at most $most short spoken sentences',
    );
  }

  /// [turnSettings] with room for the chosen length.
  static Map<String, Object> turnSettingsFor(int most) => {
    ...turnSettings,
    'maxTokens': most == 0
        ? maxAnswerTokens * 3
        : math.max(maxAnswerTokens, most * 60),
  };

  /// A spoken turn never reasons first, not even before an answer from web
  /// pages: Gemma 4 E2B thought for 600 to 750 tokens there, half a minute
  /// of silence on the phone (conversation probe, 2026-10-07).
  static const turnSettings = {
    'thinkingModeEnabled': false,
    'thinkOnSearch': false,
    'maxTokens': maxAnswerTokens,
  };

  /// A spoken answer's length cap: about a minute of speech, and the
  /// answer is spoken only once it is complete (tester, 2026-10-09).
  static const maxAnswerTokens = 300;

  /// An answer held by talking over it stays held after a segment that was
  /// noise or echo while the next words are being heard: playing it would
  /// rest the microphone, which throws those words away (tester, 2026-10-09:
  /// "how old is Justin Bieber" was lost and the weather answer went on).
  /// The words being heard decide when they end. Held past [maxHold], it
  /// plays again anyway: steady sound taken as speech must not stall it.
  static bool keepsHolding({
    required bool holding,
    required bool hearing,
    required Duration heldFor,
  }) => holding && hearing && heldFor < maxHold;

  static const maxHold = Duration(seconds: 10);

  /// [text] repeats what was [said]: most of its words (three or more), or,
  /// for a word or two heard while the answer was playing, all of them
  /// (an echoed "Yes." must not become the next question).
  ///
  /// A correction is never echo, however many words it shares (audit C5,
  /// 2026-10-08): it starts with "no", "non", "actually"… that the answer
  /// did not say, or names a number the answer did not.
  static bool echoOf(
    String text,
    List<String> said, {
    required bool duringSpeech,
  }) {
    final words = _words(text);
    if (words.isEmpty || said.isEmpty) return false;
    final known = _words(said.join(' ')).toSet();
    if (_correcting.contains(words.first) && !known.contains(words.first)) {
      return false;
    }
    if (words.any((w) => _isNumber(w) && !known.contains(w))) return false;
    final shared = words.where(known.contains).length;
    if (words.length < 3) return duringSpeech && shared == words.length;
    if (duringSpeech) return shared / words.length >= 0.7;
    // After the voice stopped, a follow-up shares most of its words with
    // the answer ("What about tomorrow in Toronto?" after "Today in
    // Toronto…") and was dropped as echo (tester, 2026-10-09: "the voice
    // understanding got worse"). Only the answer's own words in their
    // order are echo then.
    final spoken = ' ${_words(said.join(' ')).join(' ')} ';
    return spoken.contains(' ${words.join(' ')} ');
  }

  /// How a correction starts, in English, French and Spanish.
  static const _correcting = {
    'no',
    'nope',
    'nah',
    'not',
    'actually',
    'wait',
    'instead',
    'rather',
    'non',
    'pas',
    'attends',
    'plutôt',
    'plutot',
    'enfin',
    'espera',
    'mejor',
    'mas',
    'más',
    'tampoco',
  };

  /// Number words (not "one", "un", "uno": also articles and pronouns).
  static const _numberWords = {
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'fifteen',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'hundred',
    'thousand',
    'half',
    'quarter',
    'deux',
    'trois',
    'quatre',
    'cinq',
    'sept',
    'huit',
    'neuf',
    'dix',
    'onze',
    'douze',
    'quinze',
    'vingt',
    'trente',
    'quarante',
    'cinquante',
    'soixante',
    'cent',
    'mille',
    'demi',
    'demie',
    'quart',
    'dos',
    'tres',
    'cuatro',
    'cinco',
    'seis',
    'siete',
    'ocho',
    'nueve',
    'diez',
    'doce',
    'quince',
    'veinte',
    'treinta',
    'cuarenta',
    'cincuenta',
    'sesenta',
    'cien',
    'ciento',
    'mil',
    'medio',
    'media',
    'cuarto',
  };

  static bool _isNumber(String w) =>
      _numberWords.contains(w) || RegExp(r'^\d').hasMatch(w);

  static List<String> _words(String text) => RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  var _phase = ConversationPhase.starting;
  var _muted = false;
  var _natural = false;

  /// The answer plays on the call path and can be talked over
  /// (`InferenceSettings.talkOver`).
  var _talkOver = false;

  /// The model answering (catalog id), once prepared.
  String? _modelId;

  /// The remote connection answers ([ConversationModel.usesRemote]), named
  /// [_remoteName] in the top bar.
  var _remote = false;
  String? _remoteName;

  /// The question being answered, asked again on the phone when the
  /// remote connection fails.
  var _question = '';
  Timer? _wake;

  /// What the user is saying now (running caption), before it is sent.
  var _userCaption = '';

  /// The sentence being spoken (highlighted in the answer), or a notice
  /// while the model loads.
  var _assistantCaption = '';

  /// The whole exchange, scrollable: the user's words and the answers.
  final _lines = <_Line>[];
  final _scroll = ScrollController();

  /// The transcript follows new words unless the user scrolled up to read.
  var _follow = true;

  /// The question goes to the web first (the status says so).
  var _lookingUp = false;
  String? _notice;

  /// What the last answer prepared (an alarm, an event…), to confirm.
  var _actions = const <PhoneAction>[];

  /// What the wave follows: the microphone, or the answer while it plays.
  var _micLevel = 0.0;
  var _envelope = const <double>[];
  final _playClock = Stopwatch();
  var _playing = false;

  WhisperListener? _ears;
  KokoroSpeaker? _mouth;
  final _stream = SentenceStream();

  /// Our turn is being answered (the chat may also be busy with another).
  var _turn = false;

  /// Sentences set aside when speech was heard over the answer; spoken
  /// again if it was only noise or the answer's own echo.
  List<String>? _held;
  final _heldFor = Stopwatch();

  /// What the assistant said lately, to recognise its own echo.
  final _recent = <String>[];
  var _closed = false;

  /// When the voice last went quiet: the room's echo lingers a moment.
  DateTime? _lastPlayedAt;

  /// Looks at the answer again when the model pauses (audit C3): a finished
  /// sentence at the end of the text goes then.
  Timer? _settle;

  /// The latest question: an older one still waiting gives way (audit C6).
  var _askSeq = 0;

  /// The app went to the background with the microphone on.
  var _away = false;

  /// Keeps the speech workers loaded while this screen is open.
  void Function()? _lease;

  @override
  void initState() {
    super.initState();
    ConversationScreen.open = true;
    // Kept for dispose, where ref can no longer be used (Riverpod 3: the
    // read threw there, and the answer went on in the chat after End).
    _chat = ref.read(chatProvider.notifier);
    _voice = ref.read(voiceProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  /// Out of sight (Home, the lock screen, another app): the answer stops
  /// and the microphone closes; it listens again on return (audit C7).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_away) return;
      _away = true;
      if (_answering || (_mouth?.busy ?? false)) _stopAnswer();
      if (_natural) {
        unawaited(_ears?.stop());
        _micLevel = 0;
      } else {
        unawaited(_voice.stop());
      }
      _set(() => _phase = ConversationPhase.idle);
    } else if (state == AppLifecycleState.resumed && _away) {
      _away = false;
      if (_muted) return;
      if (_natural) {
        unawaited(
          _ears?.start().then((ok) {
            if (ok) _set(() => _phase = ConversationPhase.listening);
          }),
        );
      } else {
        _listenSystem();
      }
    }
  }

  late final ChatNotifier _chat;
  late final VoiceNotifier _voice;

  /// End (the button, the X or back): silence and stop the answer at once,
  /// not after the page has slid away.
  void _end() {
    _stopAll();
    unawaited(_chat.nameChatLater());
    unawaited(Navigator.of(context).maybePop());
  }

  void _stopAll() {
    _held = null;
    _wake?.cancel();
    _settle?.cancel();
    unawaited(_mouth?.stop());
    // Ending the conversation ends its answer too: it must not go on
    // writing (and being read aloud) in the chat underneath.
    if (_turn) _chat.cancel();
    _turn = false;
    unawaited(_voice.stop());
    unawaited(_voice.stopSpeaking());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAll();
    _closed = true;
    _scroll.dispose();
    ConversationScreen.open = false;
    _ears?.dispose();
    _lease?.call();
    if (_natural) unawaited(VoiceAudioChannel.conversation(false));
    super.dispose();
  }

  void _set(VoidCallback f) {
    if (!_closed && mounted) setState(f);
  }

  Future<void> _start() async {
    final l10n = context.l10n;
    await _prepareModel(l10n);
    if (_closed) return;
    final settings = ref.read(settingsProvider);
    final packs = ref.read(voiceModelsProvider);
    _natural =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        settings.naturalVoice &&
        packs.canListen &&
        packs.canSpeak;
    if (!_natural) {
      if (!packs.canListen || !packs.canSpeak) {
        _set(() => _notice ??= l10n.convNeedsVoice);
      }
      _set(() => _phase = ConversationPhase.idle);
      _listenSystem();
      return;
    }
    final sherpa = ref.read(sherpaVoiceProvider);
    // Kokoro and Whisper stay loaded while the conversation is open.
    _lease = sherpa.lease();
    final kokoro = ref.read(voiceProvider.notifier).kokoroVoice();
    // Load Kokoro while the user says the first sentence.
    unawaited(
      sherpa.warmSpeaking(kokoro).catchError((Object e) {
        Logger('voice').warning('Kokoro did not load', e);
      }),
    );
    _talkOver = settings.talkOver;
    await VoiceAudioChannel.conversation(true, call: _talkOver);
    _mouth = KokoroSpeaker(voice: sherpa, kokoro: kokoro)
      ..onPlaying = _onPlaying
      ..onAudio = (a) {
        // Each sentence's level from its own start: the voice no longer
        // pauses between sentences to reset it.
        _envelope = speechEnvelope(a);
        _playClock
          ..reset()
          ..start();
      }
      ..onSentence = (s) {
        _remember(s);
        _set(() {
          _assistantCaption = s;
          _phase = ConversationPhase.speaking;
        });
      }
      ..onIdle = _afterSpeaking
      ..onError = (e) => Logger('voice').warning('Kokoro failed', e);
    _ears = WhisperListener(
      voice: sherpa,
      language: voiceLanguage(settings.localeCode),
      onLevel: (v) => _micLevel = v,
      onSpeechStart: _onSpeechStart,
      onPartial: (t) => _set(() => _userCaption = t),
      onFinal: _onHeard,
      onDropped: _onNothingHeard,
    );
    if (!await _ears!.start()) {
      _set(() {
        _notice = l10n.convMicDenied;
        _phase = ConversationPhase.idle;
        _muted = true;
      });
      return;
    }
    _set(() => _phase = ConversationPhase.listening);
  }

  /// The conversation model (loaded now so the first answer does not wait
  /// for it), with a notice when the one that should answer is missing.
  Future<void> _prepareModel(AppLocalizations l10n) async {
    final models = ref.read(modelManagerProvider);
    final settings = ref.read(settingsProvider);
    final chosen = settings.conversationModelId;
    if (ConversationModel.usesRemote(chosen, settings)) {
      // Nothing to load on the phone: the remote model answers.
      _set(() {
        _remote = true;
        _remoteName = ConversationModel.remoteName(settings);
        _notice = null;
      });
      _modelId = null;
      return;
    }
    _set(() {
      _remote = false;
      _remoteName = null;
    });
    final model = ConversationModel.pick(
      chosen,
      models.catalog,
      loadedId: models.loadedModelId,
    );
    if (model == null) {
      _set(() => _notice = l10n.convNoModel);
      return;
    }
    final missing = ConversationModel.missing(chosen, models.catalog);
    _set(
      () => _notice = missing == null
          ? null
          : l10n.convModelMissing(missing.displayName),
    );
    await _loadOnPhone(model.id, l10n);
  }

  /// Loads [id] for Conversation (nothing when it is already loaded).
  Future<void> _loadOnPhone(String id, AppLocalizations l10n) async {
    final models = ref.read(modelManagerProvider);
    final model = models.catalog.where((m) => m.id == id).firstOrNull;
    if (model == null) return;
    _modelId = model.id;
    if (models.loadedModelId == model.id) return;
    _set(() => _assistantCaption = l10n.convLoadingModel(model.displayName));
    try {
      await ref
          .read(modelManagerProvider.notifier)
          .loadModel(model, forChat: true);
    } catch (e) {
      _set(() => _notice = '$e');
    }
    _set(() => _assistantCaption = '');
  }

  /// Another model picked from the top bar: loaded between turns.
  Future<void> _pickModel() async {
    final l10n = context.l10n;
    if (!await showConversationModelPicker(context, ref) || _closed) return;
    if (_turn) return; // loaded at the start of the next conversation
    await _prepareModel(l10n);
  }

  // ---- Natural voice: Whisper + Kokoro --------------------------------

  /// Full-quality sound has no echo canceller: the microphone rests while
  /// a sentence plays, and listens again a moment after (the room's echo).
  void _onPlaying(bool playing) {
    _playing = playing;
    if (!playing) _lastPlayedAt = DateTime.now();
    if (_talkOver) return;
    _wake?.cancel();
    if (playing) {
      _ears?.resting = true;
    } else {
      _wake = Timer(const Duration(milliseconds: 300), () {
        _ears?.resting = false;
      });
    }
  }

  /// The loudness the wave shows now (0…1 RMS).
  double _levelNow() {
    if (!_playing) return _muted ? 0 : _micLevel;
    final i = _playClock.elapsedMilliseconds ~/ 32;
    return i < _envelope.length ? _envelope[i] : 0;
  }

  void _onSpeechStart() {
    if (_closed) return;
    // Talking over the answer: it stops at once; if what was heard turns
    // out to be noise or our own echo, it picks up where it stopped.
    final mouth = _mouth;
    if (mouth != null && mouth.busy && _held == null) {
      _held = const [];
      _heldFor
        ..reset()
        ..start();
      unawaited(
        mouth.interrupt().then((rest) {
          if (_held != null) _held = [...rest, ..._held!];
        }),
      );
    }
    _set(() {
      _userCaption = '';
      if (_phase == ConversationPhase.speaking) {
        _phase = ConversationPhase.listening;
      }
    });
  }

  void _onNothingHeard() {
    if (ConversationScreen.keepsHolding(
      holding: _held != null,
      hearing: _ears?.hearing ?? false,
      heldFor: _heldFor.elapsed,
    )) {
      return;
    }
    if (_userCaption.isNotEmpty) _set(() => _userCaption = '');
    final held = _held;
    _held = null;
    if (held == null || _closed) return;
    if (held.isNotEmpty) {
      _mouth?.add(held.join('\n'));
      _set(() => _phase = ConversationPhase.speaking);
    } else {
      _afterSpeaking();
    }
  }

  void _onHeard(String text) {
    if (_closed || _muted) return;
    if (_isEcho(text)) return _onNothingHeard();
    _held = null;
    unawaited(_mouth?.stop());
    unawaited(_ask(text));
  }

  /// Most of the words were just said by the assistant: the speaker leaking
  /// into the microphone, not the user.
  bool _isEcho(String text) => ConversationScreen.echoOf(
    text,
    _recent,
    duringSpeech:
        _held != null ||
        _playing ||
        (_lastPlayedAt != null &&
            DateTime.now().difference(_lastPlayedAt!) <
                const Duration(milliseconds: 1500)),
  );

  void _remember(String sentence) {
    _recent.add(sentence);
    while (_recent.length > 6) {
      _recent.removeAt(0);
    }
  }

  /// One spoken sentence or more from the streamed answer.
  void _say(String chunk) {
    final text = VoiceNotifier.speakable(chunk);
    if (text.isEmpty) return;
    if (_natural) {
      if (_held != null) {
        _held = [..._held!, ...KokoroSpeaker.sentences(text)];
      } else {
        _mouth?.add(text);
      }
    }
  }

  void _afterSpeaking() {
    if (_closed || _held != null) return;
    if (_turn || ref.read(chatProvider).isGenerating) return;
    // Heard to the end: the chat's title is written now, not over the voice.
    unawaited(_chat.nameChatLater());
    _set(() {
      _phase = _muted ? ConversationPhase.idle : ConversationPhase.listening;
    });
  }

  // ---- A turn ---------------------------------------------------------

  Future<void> _ask(String text) async {
    final chat = ref.read(chatProvider.notifier);
    final seq = ++_askSeq;
    // The answer being replaced: its end must not be spoken.
    _turn = false;
    _settle?.cancel();
    if (ref.read(chatProvider).isGenerating) {
      chat.cancel();
      // The cancelled answer is saved as it stands; wait for it to settle.
      for (var i = 0; i < 50 && ref.read(chatProvider).isGenerating; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
    // Closed, or a newer question came while this one waited.
    if (_closed || seq != _askSeq) return;
    _stream.reset();
    _recent.clear();
    _turn = true;
    _answered = false;
    _set(() {
      if (_lines.isNotEmpty && !_lines.last.user && _lines.last.text.isEmpty) {
        _lines.removeLast();
      }
      _lines
        ..add(_Line(true, text))
        ..add(const _Line(false, ''));
      _userCaption = '';
      _assistantCaption = '';
      _actions = const [];
      _phase = ConversationPhase.thinking;
      _follow = true;
      final settings = ref.read(settingsProvider);
      // A remote model decides itself; the status says so once it searches.
      _lookingUp =
          !_remote &&
          settings.webSearchEnabled &&
          !RetrievalPlan.aboutAssistant(
            text,
            afterQuestion: _lines.length > 2,
          ) &&
          RetrievalPlan.of(
            text,
            webEnabled: true,
            always: settings.webMode == WebMode.always,
          ).wantsWeb;
    });
    AppHaptics.press();
    _question = text;
    final most = ref.read(settingsProvider).spokenSentences;
    final accepted = await chat.send(
      text,
      extraSystem: ConversationScreen.styled(
        _remote
            ? ConversationScreen.spokenStyleRemote
            : ConversationScreen.spokenStyle,
        most,
      ),
      localOnly: !_remote,
      spoken: true,
      turnOverrides: ConversationScreen.turnSettingsFor(most),
    );
    if (!accepted && _turn) _finishTurn();
  }

  /// The remote connection failed (offline, the laptop asleep, a key
  /// refused): the 0.8B on the phone answers the same question, and the
  /// rest of the conversation stays on the phone.
  Future<void> _answerOnPhone(String error) async {
    final l10n = context.l10n;
    final models = ref.read(modelManagerProvider);
    final local = ConversationModel.pick(
      ConversationModel.defaultId,
      models.catalog,
      loadedId: models.loadedModelId,
    );
    final question = _question;
    final most = ref.read(settingsProvider).spokenSentences;
    if (local == null || question.isEmpty) {
      _set(() => _notice = error);
      _finishTurn();
      return;
    }
    final seq = _askSeq;
    _set(() {
      _remote = false;
      _remoteName = null;
      _notice = l10n.convRemoteFailed(error);
      _phase = ConversationPhase.thinking;
    });
    await _loadOnPhone(local.id, l10n);
    // Closed, or the user asked something else meanwhile.
    if (_closed || seq != _askSeq) return;
    _stream.reset();
    _turn = true;
    _answered = false;
    final accepted = await ref
        .read(chatProvider.notifier)
        .send(
          question,
          insertUser: false,
          extraSystem: ConversationScreen.styled(
            ConversationScreen.spokenStyle,
            most,
          ),
          localOnly: true,
          spoken: true,
          turnOverrides: ConversationScreen.turnSettingsFor(most),
        );
    if (!accepted && _turn) _finishTurn();
  }

  /// "Using search_web…": the remote model is looking something up.
  bool _searching(String? notice) {
    if (notice == null) return false;
    final using = context.l10n.noticeUsingTool('', '').replaceAll('…', '');
    return notice.startsWith(using) &&
        RegExp(r'search|read_url|find_in_page').hasMatch(notice);
  }

  void _onChat(ChatState? before, ChatState now) {
    if (!_turn || _closed) return;
    final saved = now.messages.lastOrNull;
    if (now.isGenerating &&
        !_answered &&
        saved != null &&
        saved.role == ChatRole.assistant &&
        saved.id != before?.messages.lastOrNull?.id) {
      // The answer is saved; the turn goes on to name the chat or learn
      // from it. Its last sentence is spoken now, not after that (it was
      // held back about two seconds on a first exchange).
      _answerSaved(now, saved);
      return;
    }
    if (_remote &&
        now.isGenerating &&
        !_lookingUp &&
        now.notice != before?.notice &&
        _searching(now.notice)) {
      _set(() => _lookingUp = true);
    }
    if (now.isGenerating) {
      if (_answered) return;
      // Spoken only once the answer is complete: Kokoro reading while the
      // model wrote shared the cores with it and paused about two seconds
      // at every comma and stop (tester, 2026-10-09). The words show as
      // they come.
      _showAnswer(now.partialAnswer);
      return;
    }
    if (before?.isGenerating != true) return;
    final last = now.messages.lastOrNull;
    if (now.error != null) {
      if (_remote && !_answered) {
        unawaited(_answerOnPhone(now.error!));
        return;
      }
      _set(() => _notice = now.error);
    } else if (!_answered && last != null && last.role == ChatRole.assistant) {
      _answerSaved(now, last);
    }
    _finishTurn();
  }

  /// This turn's answer has been spoken to the end or handed to the voice.
  var _answered = false;

  /// The saved answer (citations and checks applied) gives the rest.
  void _answerSaved(ChatState now, ChatMessage last) {
    _answered = true;
    _settle?.cancel();
    if (PhoneActions.mayHave(last.runJson)) {
      final actions = PhoneActions.fromTrace(
        TurnRun.decode(last.runJson)?.toolTrace ?? const [],
      );
      _set(() => _actions = actions);
    }
    final rest = _stream.take(last.content, flush: true);
    if (rest.trim().isNotEmpty) _say(rest);
    _showAnswer(last.content);
    if (!_natural) {
      unawaited(
        ref.read(voiceProvider.notifier).speak(last.content, id: last.id),
      );
      _set(() => _phase = ConversationPhase.speaking);
    }
    final chatId = now.chatId;
    if (chatId != null &&
        _modelId != null &&
        ref.read(modelManagerProvider).loadedModelId == _modelId) {
      unawaited(
        ref.read(chatModelPinsProvider.notifier).set(chatId, _modelId!),
      );
    }
  }

  /// The answer so far, as it is spoken, in the transcript.
  void _showAnswer(String answer) {
    if (_lines.isEmpty || _lines.last.user) return;
    final text = VoiceNotifier.speakable(answer).trim();
    if (text == _lines.last.text) return;
    _set(() => _lines.last = _Line(false, text));
  }

  void _finishTurn() {
    _turn = false;
    if (_natural) {
      if (!(_mouth?.busy ?? false)) _afterSpeaking();
    } else if (!ref.read(voiceProvider).speaking) {
      _set(() => _phase = ConversationPhase.idle);
    }
  }

  // ---- System voice fallback -------------------------------------------

  void _listenSystem() {
    if (_closed || _muted || _natural) return;
    if (ref.read(chatProvider).isGenerating) return;
    _set(() {
      _phase = ConversationPhase.listening;
      _userCaption = '';
    });
    unawaited(
      ref
          .read(voiceProvider.notifier)
          .listen(
            onDeviceOnly: ref.read(settingsProvider).voiceOnDeviceOnly,
            onText: (t) => _set(() => _userCaption = t),
            onFinal: (t) {
              if (_closed) return;
              if (t.trim().isEmpty) {
                _set(() => _phase = ConversationPhase.idle);
                return;
              }
              unawaited(_ask(t));
            },
          ),
    );
  }

  // ---- Controls -------------------------------------------------------

  bool get _answering =>
      _phase == ConversationPhase.speaking ||
      _phase == ConversationPhase.thinking;

  /// The orb: interrupts an answer, or (re)starts listening.
  void _tapOrb() {
    AppHaptics.tick();
    if (_answering) return _stopAnswer();
    if (_muted) {
      unawaited(_toggleMute());
      return;
    }
    if (!_natural && _phase == ConversationPhase.idle) _listenSystem();
  }

  /// Stop answer (the button or a tap on the wave): silence, stop writing,
  /// and listen for the next question.
  void _stopAnswer() {
    {
      _held = null;
      _settle?.cancel();
      unawaited(_mouth?.stop());
      unawaited(ref.read(voiceProvider.notifier).stopSpeaking());
      if (ref.read(chatProvider).isGenerating) {
        ref.read(chatProvider.notifier).cancel();
      }
      _turn = false;
      _set(() {
        // Stopped before the first word: no empty answer stays behind.
        if (_lines.isNotEmpty &&
            !_lines.last.user &&
            _lines.last.text.isEmpty) {
          _lines.removeLast();
        }
        _phase = ConversationPhase.idle;
      });
      if (!_natural) _listenSystem();
      if (_natural && !_muted) {
        _set(() => _phase = ConversationPhase.listening);
      }
    }
  }

  Future<void> _toggleMute() async {
    AppHaptics.tick();
    final mute = !_muted;
    _set(() => _muted = mute);
    if (_natural) {
      if (mute) {
        await _ears?.stop();
        _micLevel = 0;
        if (_phase == ConversationPhase.listening) {
          _set(() => _phase = ConversationPhase.idle);
        }
      } else {
        final ok = await _ears?.start() ?? false;
        if (!ok) {
          if (mounted) {
            final denied = context.l10n.convMicDenied;
            _set(() {
              _muted = true;
              _notice = denied;
            });
          }
          return;
        }
        if (_phase == ConversationPhase.idle) {
          _set(() => _phase = ConversationPhase.listening);
        }
      }
    } else {
      if (mute) {
        await ref.read(voiceProvider.notifier).stop();
        _set(() => _phase = ConversationPhase.idle);
      } else {
        _listenSystem();
      }
    }
  }

  /// The exchange so far: the user's words in a soft bubble, the answers
  /// as large text with the sentence being spoken lit up. It follows new
  /// words unless the user scrolled up to read.
  Widget _transcript(BuildContext context) {
    final c = context.colors;
    final lines = [
      ..._lines,
      if (_userCaption.isNotEmpty) _Line(true, _userCaption, live: true),
    ];
    if (_follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients || _closed) return;
        final end = _scroll.position.maxScrollExtent;
        if (_scroll.offset < end - 1) {
          unawaited(
            _scroll.glideTo(end, context.motion, duration: AppMotion.track),
          );
        }
      });
    }
    final answerStyle = context.text.body.copyWith(
      color: c.text,
      fontSize: ConversationScreen.answerFontSize,
      height: 1.45,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification && n.dragDetails != null) {
          _follow = n.metrics.pixels >= n.metrics.maxScrollExtent - 32;
        } else if (n is ScrollEndNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 32) {
          _follow = true;
        }
        return false;
      },
      child: ShaderMask(
        // The top lines fade out under the wave.
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
          stops: [0, 0.08],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          key: const Key('conversation-transcript'),
          controller: _scroll,
          padding: const EdgeInsets.only(
            top: AppDesign.lg,
            bottom: AppDesign.md,
          ),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final line = lines[i];
            if (line.user) {
              return Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(
                    left: AppDesign.xl * 2,
                    top: AppDesign.md,
                    bottom: AppDesign.md,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.lg,
                    vertical: AppDesign.md,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    line.text,
                    key: line.live
                        ? const Key('conversation-user-caption')
                        : null,
                    style: context.text.body.copyWith(
                      color: line.live ? c.textMuted : c.text,
                      fontSize: ConversationScreen.captionFontSize,
                      height: 1.35,
                      fontStyle: line.live ? FontStyle.italic : null,
                    ),
                  ),
                ),
              );
            }
            final last = i == _lines.length - 1;
            if (line.text.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
                child: Text(
                  '…',
                  style: answerStyle.copyWith(color: c.textFaint),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
              child: Text.rich(
                _spoken(
                  line.text,
                  last && _phase == ConversationPhase.speaking
                      ? _assistantCaption
                      : '',
                  answerStyle,
                  c,
                ),
                key: last ? const Key('conversation-assistant-caption') : null,
              ),
            );
          },
        ),
      ),
    );
  }

  /// [text] with the sentence being spoken in full colour and the rest a
  /// little quieter; all of it plain once the answer has been said.
  static TextSpan _spoken(
    String text,
    String now,
    TextStyle style,
    AppColors c,
  ) {
    final at = now.isEmpty ? -1 : text.indexOf(now.trim());
    if (at < 0) return TextSpan(text: text, style: style);
    final end = at + now.trim().length;
    final quiet = style.copyWith(color: c.textMuted);
    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, at), style: quiet),
        TextSpan(text: text.substring(at, end), style: style),
        TextSpan(text: text.substring(end), style: quiet),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    ref.listen(chatProvider, _onChat);
    // System voice: when the answer has been read, listen again.
    ref.listen(voiceProvider.select((v) => v.speaking), (was, now) {
      if (!_natural && was == true && !now && !_turn) _listenSystem();
    });
    final packs = ref.watch(voiceModelsProvider);
    final modelName = _remote
        ? _remoteName
        : ref
              .watch(modelManagerProvider.select((m) => m.catalog))
              .where((m) => m.id == _modelId)
              .firstOrNull
              ?.displayName;
    final status = switch (_phase) {
      ConversationPhase.starting => '',
      ConversationPhase.idle => _muted ? t.convPaused : t.convHint,
      ConversationPhase.listening => t.convListening,
      ConversationPhase.thinking =>
        _lookingUp ? t.convLookingUp : t.convThinking,
      ConversationPhase.speaking =>
        _natural && !_talkOver ? t.convSpeakingTap : t.convSpeaking,
    };
    final downloading = VoiceModels.packs.any(
      (p) =>
          packs.of(p).status != VoicePackStatus.missing &&
          packs.of(p).status != VoicePackStatus.ready,
    );
    return Scaffold(
      key: const Key('conversation-screen'),
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.conversationTitle, style: context.text.headline),
            if (modelName != null)
              Text(
                modelName,
                key: const Key('conversation-model-name'),
                style: context.text.label.copyWith(color: c.textMuted),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('conversation-model-pick'),
            tooltip: t.convModelTitle,
            icon: const Icon(Icons.tune),
            onPressed: _pickModel,
          ),
          const SizedBox(width: AppDesign.xs),
        ],
        leading: IconButton(
          key: const Key('conversation-close'),
          tooltip: t.convEnd,
          iconSize: 26,
          icon: const Icon(Icons.close),
          onPressed: _end,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
          child: Column(
            children: [
              if (_notice != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDesign.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_notice!, style: context.text.bodyMuted),
                        if (!_natural &&
                            (!packs.canListen || !packs.canSpeak)) ...[
                          const SizedBox(height: AppDesign.sm),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              key: const Key('conversation-get-voice'),
                              onPressed: downloading
                                  ? null
                                  : () {
                                      final n = ref.read(
                                        voiceModelsProvider.notifier,
                                      );
                                      unawaited(() async {
                                        for (final p in VoiceModels.packs) {
                                          if (!packs.of(p).isReady) {
                                            await n.download(p);
                                          }
                                        }
                                      }());
                                    },
                              icon: downloading
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_outlined),
                              label: Text(t.voiceDownloadBoth),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final talk = _lines.isNotEmpty || _userCaption.isNotEmpty;
                    return Column(
                      children: [
                        AnimatedContainer(
                          duration: context.motion.fade(AppMotion.glide),
                          curve: AppMotion.ease,
                          height: talk
                              ? math.min(150, box.maxHeight * 0.3)
                              : box.maxHeight,
                          alignment: Alignment.center,
                          child: GestureDetector(
                            key: const Key('conversation-orb'),
                            onTap: _tapOrb,
                            child: _Wave(
                              phase: _phase,
                              level: _levelNow,
                              muted: _muted,
                            ),
                          ),
                        ),
                        if (talk) Expanded(child: _transcript(context)),
                      ],
                    );
                  },
                ),
              ),
              if (_lines.isEmpty && _userCaption.isEmpty)
                _Caption(
                  key: const Key('conversation-assistant-caption'),
                  text: _assistantCaption,
                  maxLines: 3,
                  style: context.text.body.copyWith(
                    color: c.textMuted,
                    fontSize: ConversationScreen.captionFontSize,
                    height: 1.4,
                  ),
                ),
              if (_actions.isNotEmpty) ...[
                const SizedBox(height: AppDesign.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: PhoneActionCards(actions: _actions),
                  ),
                ),
              ],
              const SizedBox(height: AppDesign.lg),
              Text(
                status,
                style: context.text.body.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              const SizedBox(height: AppDesign.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BigButton(
                    label: _muted ? t.convUnmute : t.convMute,
                    child: IconButton.filledTonal(
                      key: const Key('conversation-mute'),
                      tooltip: _muted ? t.convUnmute : t.convMute,
                      iconSize: 28,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(_BigButton.size),
                      ),
                      onPressed: _phase == ConversationPhase.starting
                          ? null
                          : _toggleMute,
                      icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                    ),
                  ),
                  const SizedBox(width: AppDesign.md),
                  _BigButton(
                    label: t.convStopAnswer,
                    child: IconButton.filledTonal(
                      key: const Key('conversation-stop'),
                      tooltip: t.convStopAnswer,
                      iconSize: 30,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(_BigButton.size),
                      ),
                      onPressed: _answering
                          ? () {
                              AppHaptics.tick();
                              _stopAnswer();
                            }
                          : null,
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ),
                  const SizedBox(width: AppDesign.md),
                  _BigButton(
                    label: t.convEnd,
                    child: IconButton.filled(
                      key: const Key('conversation-end'),
                      tooltip: t.convEnd,
                      iconSize: 30,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(_BigButton.size),
                        backgroundColor: c.danger,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _end,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesign.lg),
            ],
          ),
        ),
      ),
    );
  }
}

extension on VoicePackState {
  bool get isReady => status == VoicePackStatus.ready;
}

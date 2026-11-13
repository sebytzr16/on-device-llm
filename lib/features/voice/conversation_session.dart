import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/l10n/l10n.dart';
import '../../core/motion/haptics.dart';
import '../../inference/engine/diffusiongemma_engine.dart';
import '../../inference/engine/llama_engine.dart';
import '../chat/domain/entities/chat_message.dart';
import '../chat/domain/entities/turn_run.dart';
import '../chat/domain/retrieval_plan.dart';
import '../chat/presentation/providers/chat_provider.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../tools/phone_actions.dart';
import 'conversation_model.dart';
import 'desktop_voice_policy.dart';
import 'sherpa_voice.dart';
import 'utterance_audio.dart';
import 'voice_models_provider.dart';
import 'voice_pipeline.dart';
import 'voice_service.dart';

/// What the Conversation screen shows: starting, idle, listening, thinking or
/// speaking.
enum ConversationPhase { starting, idle, listening, thinking, speaking }

/// One line of the transcript.
class ConversationLine {
  final bool user;
  final String text;

  /// The user is still saying it (a running caption).
  final bool live;
  const ConversationLine(this.user, this.text, {this.live = false});
}

/// The Riverpod wiring the screen supplies to [ConversationSession]: current
/// state and the notifiers it calls. The session holds no `Ref` itself, so it
/// stays a plain Dart class the screen composes (audit A27).
abstract class ConversationWiring {
  ChatState get chatState;
  ChatNotifier get chat;
  VoiceState get voiceState;
  VoiceNotifier get voice;
  InferenceSettings get settings;
  VoiceModelsState get packs;
  SherpaVoice get sherpa;
  ModelManagerState get models;
  ModelManagerNotifier get modelManager;

  /// The chat engine on this device: [LlamaEngine.supportsAudio] says whether
  /// the loaded model can hear a recording. Null (the default) means the
  /// wiring exposes none: the conversation stays text-only.
  LlamaEngine? get engine => null;

  /// Whether the screen is still mounted (`context.l10n` needs it).
  bool get mounted;

  /// The screen's strings, read from its context.
  AppLocalizations get l10n;

  /// Names [modelId] as the answering model of [chatId].
  Future<void> pinModel(String chatId, String modelId);
}

/// The voice session of the Conversation screen: microphone lifecycle,
/// playback, the system-voice fallback and turn ownership. The screen keeps
/// the widgets and the Riverpod wiring ([ConversationWiring]) and calls this;
/// an explicit turn token ([generation]) keeps a stale turn from writing after
/// a newer one started (audit A27).
class ConversationSession {
  ConversationSession({
    required this.wiring,
    required bool listen,
    required this.changed,
  }) : _listen = listen,
       _muted = !listen;

  final ConversationWiring wiring;

  /// Rebuilds the screen after a state change.
  final VoidCallback changed;

  /// Whether the microphone opens by itself (the screen's `listen` flag).
  final bool _listen;

  // ---- The spoken turn's shape (shared with ConversationScreen) ---------

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

  /// Added to the spoken instructions when the utterance's recording rides
  /// with the question: the model hears what was really said.
  static const heardAudioPrompt =
      "The user's spoken words are attached as audio. The transcript above "
      'was written by speech recognition and can contain mistakes; when they '
      'differ, trust the audio.';

  /// The recognizer's 16 kHz samples; 30 s is the most that is sent.
  static const utteranceRate = 16000;
  static const maxUtteranceSamples = 30 * utteranceRate;

  /// Whether this spoken turn carries the recording itself: only when the
  /// loaded model on this device can hear audio, the setting allows it and
  /// the utterance is not longer than [maxUtteranceSamples].
  static bool sendsUtterance({
    required bool hearsAudio,
    required bool enabled,
    required bool remote,
    required int samples,
  }) =>
      !remote &&
      enabled &&
      hearsAudio &&
      samples > 0 &&
      samples <= maxUtteranceSamples;

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
    'maxTokens': maxAnswerTokens,
  };

  /// A spoken answer's length cap: about a minute of speech.
  static const maxAnswerTokens = 300;

  /// Windows must confirm the current capture stream has system AEC.
  /// Preserve the existing call-path behavior on Android.
  static bool canTalkOver({
    required bool requested,
    required TargetPlatform platform,
    required bool aecActive,
  }) => requested && (platform != TargetPlatform.windows || aecActive);

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

  // ---- State ----------------------------------------------------------

  var _phase = ConversationPhase.starting;
  var _muted = false;
  var _natural = false;

  /// The answer plays on the call path and can be talked over
  /// (`InferenceSettings.talkOver`).
  var _talkOver = false;
  var _aecActive = false;
  var _playGeneration = 0;
  Timer? _aecCheck;

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

  /// The current turn's utterance recording, deleted after the turn (and on
  /// close): it is sent with the prompt, never saved with the chat.
  String? _utterancePath;

  /// What the user is saying now (running caption), before it is sent.
  var _userCaption = '';

  /// The sentence being spoken (highlighted in the answer), or a notice
  /// while the model loads.
  var _assistantCaption = '';

  /// The whole exchange, scrollable: the user's words and the answers.
  final _lines = <ConversationLine>[];

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

  /// Full text sent to Kokoro for the current answer (natural voice), for
  /// fallback to system voice if synthesis fails.
  String _spokenText = '';
  List<String> _spokenSentences = const [];
  int _spokenSentenceIndex = 0;

  /// The latest turn started: a continuation captures it and gives way once
  /// a newer turn began.
  var _generation = 0;

  /// The turn whose answer may write now (0: none). A newer question, a stop
  /// or End clears it, so a stale turn cannot write any more.
  var _turnToken = 0;

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

  /// The app went to the background with the microphone on.
  var _away = false;

  /// Keeps the speech workers loaded while this screen is open.
  void Function()? _lease;

  // ---- Reads for the screen -------------------------------------------

  ConversationPhase get phase => _phase;
  bool get muted => _muted;
  bool get natural => _natural;
  List<ConversationLine> get lines => _lines;
  String get userCaption => _userCaption;
  String get assistantCaption => _assistantCaption;
  String? get notice => _notice;
  List<PhoneAction> get actions => _actions;
  bool get lookingUp => _lookingUp;
  bool get remote => _remote;
  String? get remoteName => _remoteName;
  String? get modelId => _modelId;
  bool get follow => _follow;
  set follow(bool value) => _follow = value;
  bool get closed => _closed;

  /// Our turn is being answered (the chat may also be busy with another).
  bool get turn => _turnToken != 0;

  bool get answering =>
      _phase == ConversationPhase.speaking ||
      _phase == ConversationPhase.thinking;

  /// The answer can be talked over and the capture stream has system AEC.
  bool get canTalkOverNow => canTalkOver(
    requested: _talkOver,
    platform: defaultTargetPlatform,
    aecActive: _aecActive,
  );

  /// The latest turn's token ([generation]): an older one gives way.
  int get generation => _generation;

  /// The loudness the wave shows now (0…1 RMS).
  double levelNow() {
    if (!_playing) return _muted ? 0 : _micLevel;
    final i = _playClock.elapsedMilliseconds ~/ 32;
    return i < _envelope.length ? _envelope[i] : 0;
  }

  void _set(VoidCallback change) {
    if (_closed) return;
    change();
    changed();
  }

  // ---- Lifecycle ------------------------------------------------------

  Future<void> start() async {
    final l10n = wiring.l10n;
    await prepareModel(l10n);
    if (_closed) return;
    final settings = wiring.settings;
    final packs = wiring.packs;
    _natural = offlineVoiceReady(
      enabled: settings.naturalVoice,
      installed:
          packs.canListen && packs.canSpeakWith(wiring.settings.readingVoice),
    );
    if (!_natural) {
      if (!packs.canListen ||
          !packs.canSpeakWith(wiring.settings.readingVoice)) {
        _set(() => _notice ??= l10n.convNeedsVoice);
      }
      _set(() {
        _phase = ConversationPhase.idle;
        if (!_listen) _muted = true;
      });
      if (_listen) listenSystem();
      return;
    }
    final sherpa = wiring.sherpa;
    // Kokoro and Whisper stay loaded while the conversation is open.
    _lease = sherpa.lease();
    final kokoro = wiring.voice.kokoroVoice();
    // Load Kokoro while the user says the first sentence.
    unawaited(
      sherpa.warmSpeaking(kokoro).catchError((Object e) {
        Logger('voice').warning('Kokoro did not load', e);
      }),
    );
    _talkOver = settings.talkOver;
    await VoiceAudioChannel.conversation(true, call: _talkOver);
    if (_closed || _away) {
      await VoiceAudioChannel.conversation(false);
      return;
    }
    _mouth = KokoroSpeaker(voice: sherpa, kokoro: kokoro)
      ..speed = settings.readingSpeed.clamp(0.6, 1.6)
      ..onPlaying = _onPlaying
      ..onAudio = (a) {
        // Each sentence's level from its own start: the voice no longer
        // pauses between sentences to reset it.
        _envelope = speechEnvelope(a);
        _playClock
          ..reset()
          ..start();
      }
      ..onSentence = (s, _) {
        _remember(s);
        if (_spokenSentenceIndex < _spokenSentences.length &&
            _spokenSentences[_spokenSentenceIndex] == s) {
          _spokenSentenceIndex++;
        }
        _set(() {
          _assistantCaption = s;
          _phase = ConversationPhase.speaking;
        });
      }
      ..onIdle = _afterSpeaking
      ..onError = (e) {
        if (_closed) return;
        Logger('voice').warning('Kokoro failed', e);
        // Fall back to system voice for the remaining sentences.
        final remaining = _spokenSentenceIndex < _spokenSentences.length
            ? _spokenSentences.skip(_spokenSentenceIndex).join(' ')
            : '';
        if (remaining.isNotEmpty) {
          _set(() => _notice = l10n.convSynthesisFailed);
          unawaited(wiring.voice.speak(remaining, id: '_fallback'));
        } else {
          _set(() => _notice = l10n.convSynthesisFailed);
        }
        _afterSpeaking();
      };
    _ears = WhisperListener(
      voice: sherpa,
      language: voiceLanguage(settings.localeCode),
      onLevel: (v) => _micLevel = v,
      onSpeechStart: _onSpeechStart,
      onPartial: (t) => _set(() => _userCaption = t),
      onFinalUtterance: _onHeard,
      onDropped: _onNothingHeard,
      onError: (e) {
        if (!_closed) {
          _set(() => _notice = 'Dictation failed: $e');
        }
      },
    );
    if (!_listen) {
      _set(() {
        _phase = ConversationPhase.idle;
        _muted = true;
      });
      return;
    }
    bool micStarted;
    try {
      micStarted = await _ears!.start();
    } on PlatformException catch (e) {
      micStarted = false;
      if (e.code == 'microphone_denied') {
        _set(() => _notice = l10n.desktopVoiceMicPrivacy);
      }
    }
    if (_closed || _away || _muted) {
      await _ears?.stop();
      return;
    }
    if (!micStarted) {
      _set(() {
        _notice ??= l10n.convMicDenied;
        _phase = ConversationPhase.idle;
        _muted = true;
      });
      return;
    }
    _set(() => _phase = ConversationPhase.listening);
  }

  /// Out of sight (Home, the lock screen, another app): the answer stops
  /// and the microphone closes; it listens again on return (audit C7).
  void didChangeLifecycle(AppLifecycleState state) {
    if (_closed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_away) return;
      _away = true;
      if (answering || (_mouth?.busy ?? false)) stopAnswer();
      if (_natural) {
        unawaited(_ears?.stop());
        unawaited(VoiceAudioChannel.conversation(false));
        _micLevel = 0;
      } else {
        unawaited(wiring.voice.stop());
      }
      _set(() => _phase = ConversationPhase.idle);
    } else if (state == AppLifecycleState.resumed && _away) {
      _away = false;
      if (_muted) return;
      if (_natural) {
        unawaited(_resumeNatural());
      } else {
        listenSystem();
      }
    }
  }

  Future<void> _resumeNatural() async {
    await VoiceAudioChannel.conversation(true, call: _talkOver);
    if (_closed || _away) {
      await VoiceAudioChannel.conversation(false);
      return;
    }
    if (_muted) return;
    final ok = await _ears?.start() ?? false;
    if (_closed || _away || _muted) {
      await _ears?.stop();
      return;
    }
    if (ok) _set(() => _phase = ConversationPhase.listening);
  }

  /// The conversation model (loaded now so the first answer does not wait
  /// for it), with a notice when the one that should answer is missing.
  Future<void> prepareModel(AppLocalizations l10n) async {
    final models = wiring.models;
    final settings = wiring.settings;
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
    final models = wiring.models;
    final model = models.catalog.where((m) => m.id == id).firstOrNull;
    if (model == null) return;
    _modelId = model.id;
    if (models.loadedModelId == model.id) return;
    _set(() => _assistantCaption = l10n.convLoadingModel(model.displayName));
    // A model whose projector is on disk is loaded with it, so a projector
    // that hears (Gemma 4 E2B/E4B) can take the utterance's recording. A
    // text-only model is loaded as before.
    final hears =
        wiring.settings.conversationHearsAudio &&
        models.vision.contains(model.id);
    try {
      await wiring.modelManager.loadModel(model, forChat: true, vision: hears);
    } catch (e) {
      _set(() => _notice = '$e');
    }
    _set(() => _assistantCaption = '');
  }

  /// End (the button, the X or back): silence and stop the answer at once,
  /// not after the page has slid away.
  void end() {
    _closed = true;
    _stopAll();
    unawaited(wiring.chat.nameChatLater());
  }

  void _stopAll() {
    _aecCheck?.cancel();
    ++_playGeneration;
    unawaited(_ears?.stop());
    if (_natural) unawaited(VoiceAudioChannel.conversation(false));
    _held = null;
    _wake?.cancel();
    _settle?.cancel();
    unawaited(_dropUtterance(_utterancePath));
    unawaited(_mouth?.stop());
    // Ending the conversation ends its answer too: it must not go on
    // writing (and being read aloud) in the chat underneath.
    if (turn) wiring.chat.cancel();
    _turnToken = 0;
    _spokenText = '';
    _spokenSentences = const [];
    _spokenSentenceIndex = 0;
    unawaited(wiring.voice.stop());
    unawaited(wiring.voice.stopSpeaking());
  }

  void dispose() {
    _stopAll();
    _closed = true;
    _ears?.dispose();
    _lease?.call();
    if (_natural) unawaited(VoiceAudioChannel.conversation(false));
  }

  // ---- Natural voice: Whisper + Kokoro --------------------------------

  /// Without verified Windows AEC (or the Android call path), rest the mic
  /// while audio plays and briefly afterwards for the room's echo.
  void _onPlaying(bool playing) {
    final generation = ++_playGeneration;
    _aecCheck?.cancel();
    _playing = playing;
    if (!playing) _lastPlayedAt = DateTime.now();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _aecActive = false;
      if (playing && _talkOver) {
        Future<void> checkAec() async {
          final active = await VoiceAudioChannel.aecActive();
          if (_closed || generation != _playGeneration) return;
          _set(() => _aecActive = active);
          _ears?.resting = !canTalkOverNow;
          // Recheck failures/device or effect changes during long answers.
          _aecCheck = Timer(const Duration(milliseconds: 250), checkAec);
        }

        unawaited(checkAec());
      }
    }
    if (canTalkOverNow) return;
    _wake?.cancel();
    if (playing) {
      _ears?.resting = true;
    } else {
      _wake = Timer(const Duration(milliseconds: 300), () {
        _ears?.resting = false;
      });
    }
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
    if (keepsHolding(
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

  void _onHeard(String text, Float32List samples) {
    if (_closed || _muted) return;
    if (_isEcho(text)) return _onNothingHeard();
    _held = null;
    unawaited(_mouth?.stop());
    unawaited(_ask(text, samples));
  }

  /// Most of the words were just said by the assistant: the speaker leaking
  /// into the microphone, not the user.
  bool _isEcho(String text) => echoOf(
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
    final t = stringsFor(wiring.settings.localeCode);
    final text = VoiceNotifier.speakableForTts(
      chunk,
      codeOmitted: t.voiceCodeOmitted,
    );
    if (text.isEmpty) return;
    if (_natural) {
      _spokenText += text;
      _spokenSentences = KokoroSpeaker.sentences(_spokenText);
      _spokenSentenceIndex = 0;
      if (_held != null) {
        _held = [..._held!, ...KokoroSpeaker.sentences(text)];
      } else {
        _mouth?.add(text);
      }
    }
  }

  void _afterSpeaking() {
    if (_closed || _held != null) return;
    if (turn || wiring.chatState.isGenerating) return;
    // Heard to the end: the chat's title is written now, not over the voice.
    unawaited(wiring.chat.nameChatLater());
    _set(() {
      _phase = _muted ? ConversationPhase.idle : ConversationPhase.listening;
    });
  }

  // ---- A turn ---------------------------------------------------------

  Future<void> _ask(String text, [Float32List? utterance]) async {
    final chat = wiring.chat;
    final turn = ++_generation;
    // The answer being replaced: its end must not be spoken.
    _turnToken = 0;
    _settle?.cancel();
    if (wiring.chatState.isGenerating) {
      chat.cancel();
      // The cancelled answer is saved as it stands; wait for it to settle.
      for (var i = 0; i < 50 && wiring.chatState.isGenerating; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
    // Closed, or a newer question came while this one waited.
    if (_closed || turn != _generation) return;
    _stream.reset();
    _recent.clear();
    _spokenText = '';
    _spokenSentences = const [];
    _spokenSentenceIndex = 0;
    _turnToken = turn;
    _answered = false;
    _set(() {
      if (_lines.isNotEmpty && !_lines.last.user && _lines.last.text.isEmpty) {
        _lines.removeLast();
      }
      _lines
        ..add(ConversationLine(true, text))
        ..add(const ConversationLine(false, ''));
      _userCaption = '';
      _assistantCaption = '';
      _actions = const [];
      _phase = ConversationPhase.thinking;
      _follow = true;
      final settings = wiring.settings;
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
    final most = wiring.settings.spokenSentences;
    final audio = await _keepUtterance(utterance);
    if (_closed || turn != _generation) {
      await _dropUtterance(audio);
      return;
    }
    final style = styled(_remote ? spokenStyleRemote : spokenStyle, most);
    try {
      final accepted = await chat.send(
        text,
        audioPath: audio,
        extraSystem: audio == null ? style : '$style $heardAudioPrompt',
        localOnly: !_remote,
        spoken: true,
        turnOverrides: turnSettingsFor(most),
      );
      if (!accepted && _turnToken == turn) _finishTurn();
    } finally {
      await _dropUtterance(audio);
    }
  }

  /// Writes [samples] to the app's temp directory as a WAV for this turn,
  /// when the model can hear it; null otherwise (text-only, unchanged).
  Future<String?> _keepUtterance(Float32List? samples) async {
    if (samples == null) return null;
    final modelId = _modelId;
    // The recording belongs to the loaded chat model: another model loaded
    // meanwhile, or the diffusion engine, cannot use it.
    if (modelId == null ||
        modelId == diffusionGemmaModelId ||
        wiring.models.loadedModelId != modelId) {
      return null;
    }
    final settings = wiring.settings;
    if (!sendsUtterance(
      hearsAudio: wiring.engine?.supportsAudio ?? false,
      enabled: settings.conversationHearsAudio,
      remote: _remote,
      samples: samples.length,
    )) {
      return null;
    }
    String? path;
    try {
      final dir = await getTemporaryDirectory();
      path = p.join(dir.path, 'utterance-${const Uuid().v4()}.wav');
      await writeWav16(samples, utteranceRate, path);
      _utterancePath = path;
      return path;
    } catch (e) {
      // The turn still goes ahead with the transcript alone.
      Logger('voice').warning('Could not write the utterance recording', e);
      if (path != null) await _dropUtterance(path);
      return null;
    }
  }

  /// Deletes a recording written for a turn ([writeWav16]); never saved.
  Future<void> _dropUtterance(String? path) async {
    if (path == null) return;
    if (_utterancePath == path) _utterancePath = null;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      Logger('voice').warning('Could not delete the utterance recording', e);
    }
  }

  /// The remote connection failed (offline, the laptop asleep, a key
  /// refused): the 0.8B on the phone answers the same question, and the
  /// rest of the conversation stays on the phone.
  Future<void> _answerOnPhone(String error) async {
    final l10n = wiring.l10n;
    final models = wiring.models;
    final local = ConversationModel.pick(
      ConversationModel.defaultId,
      models.catalog,
      loadedId: models.loadedModelId,
    );
    final question = _question;
    final most = wiring.settings.spokenSentences;
    if (local == null || question.isEmpty) {
      _set(() => _notice = error);
      _finishTurn();
      return;
    }
    final turn = _generation;
    _set(() {
      _remote = false;
      _remoteName = null;
      _notice = l10n.convRemoteFailed(error);
      _phase = ConversationPhase.thinking;
    });
    await _loadOnPhone(local.id, l10n);
    // Closed, or the user asked something else meanwhile.
    if (_closed || turn != _generation) return;
    _stream.reset();
    _spokenText = '';
    _spokenSentences = const [];
    _spokenSentenceIndex = 0;
    _turnToken = turn;
    _answered = false;
    final accepted = await wiring.chat.send(
      question,
      insertUser: false,
      extraSystem: styled(spokenStyle, most),
      localOnly: true,
      spoken: true,
      turnOverrides: turnSettingsFor(most),
    );
    if (!accepted && _turnToken == turn) _finishTurn();
  }

  /// "Using search_web…": the remote model is looking something up.
  bool _searching(String? notice) {
    if (notice == null) return false;
    final using = wiring.l10n.noticeUsingTool('', '').replaceAll('…', '');
    return notice.startsWith(using) &&
        RegExp(r'search|read_url|find_in_page').hasMatch(notice);
  }

  /// The chat changed: the answer is shown and spoken as it is written.
  void onChat(ChatState? before, ChatState now) {
    if (!turn || _closed) return;
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
      _showAnswer(now.partialAnswer);
      // Each finished sentence is spoken while the model writes the next
      // (owner 2026-11-01). On 2026-10-09 a slow model shared the cores
      // with Kokoro and the voice paused at commas, so speech waited for
      // the whole answer; LFM3 (47 tok/s) and the 0.8B now finish well
      // ahead of the voice. Not while a lookup runs: its words are notes.
      if (_natural && !_lookingUp) {
        final done = _stream.take(now.partialAnswer);
        if (done.trim().isNotEmpty) _say(done);
      }
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
      unawaited(wiring.voice.speak(last.content, id: last.id));
      _set(() => _phase = ConversationPhase.speaking);
    }
    final chatId = now.chatId;
    if (chatId != null &&
        _modelId != null &&
        wiring.models.loadedModelId == _modelId) {
      unawaited(wiring.pinModel(chatId, _modelId!));
    }
  }

  /// The answer so far, as it is spoken, in the transcript.
  void _showAnswer(String answer) {
    if (_lines.isEmpty || _lines.last.user) return;
    final t = stringsFor(wiring.settings.localeCode);
    final text = VoiceNotifier.speakable(
      answer,
      codeOmitted: t.voiceCodeOmitted,
    ).trim();
    if (text == _lines.last.text) return;
    _set(() => _lines.last = ConversationLine(false, text));
  }

  void _finishTurn() {
    _turnToken = 0;
    _spokenText = '';
    _spokenSentences = const [];
    _spokenSentenceIndex = 0;
    if (_natural) {
      if (!(_mouth?.busy ?? false)) _afterSpeaking();
    } else if (!wiring.voiceState.speaking) {
      _set(() => _phase = ConversationPhase.idle);
    }
  }

  // ---- System voice fallback ------------------------------------------

  void listenSystem() {
    if (_closed || _muted || _natural) return;
    if (wiring.chatState.isGenerating) return;
    _set(() {
      _phase = ConversationPhase.listening;
      _userCaption = '';
    });
    unawaited(
      wiring.voice.listen(
        onDeviceOnly: wiring.settings.voiceOnDeviceOnly,
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

  /// The orb: interrupts an answer, or (re)starts listening.
  void tapOrb() {
    AppHaptics.tick();
    if (answering) return stopAnswer();
    if (_muted) {
      unawaited(toggleMute());
      return;
    }
    if (!_natural && _phase == ConversationPhase.idle) listenSystem();
  }

  /// Stop answer (the button or a tap on the wave): silence, stop writing,
  /// and listen for the next question.
  void stopAnswer() {
    {
      _held = null;
      _settle?.cancel();
      unawaited(_mouth?.stop());
      unawaited(wiring.voice.stopSpeaking());
      if (wiring.chatState.isGenerating) {
        wiring.chat.cancel();
      }
      _turnToken = 0;
      _spokenText = '';
      _spokenSentences = const [];
      _spokenSentenceIndex = 0;
      _set(() {
        // Stopped before the first word: no empty answer stays behind.
        if (_lines.isNotEmpty &&
            !_lines.last.user &&
            _lines.last.text.isEmpty) {
          _lines.removeLast();
        }
        _phase = ConversationPhase.idle;
      });
      if (!_natural) listenSystem();
      if (_natural && !_muted) {
        _set(() => _phase = ConversationPhase.listening);
      }
    }
  }

  Future<void> toggleMute() async {
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
          if (wiring.mounted) {
            final denied = wiring.l10n.convMicDenied;
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
        await wiring.voice.stop();
        _set(() => _phase = ConversationPhase.idle);
      } else {
        listenSystem();
      }
    }
  }
}

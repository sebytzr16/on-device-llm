import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import '../../core/utils/inference_admission.dart';

import 'sherpa_voice.dart';
import 'voice_models.dart';

final _log = Logger('voice');

/// The language the voice uses: the app language when set, else the
/// phone's, limited to the three the app speaks.
String voiceLanguage(String localeCode) {
  final code = localeCode.isNotEmpty
      ? localeCode
      : PlatformDispatcher.instance.locale.languageCode;
  return const {'en', 'fr', 'es'}.contains(code) ? code : 'en';
}

/// Microphone → Silero VAD → Whisper. Emits the level for the orb, the
/// start of speech (for barge-in), running captions while the user talks
/// and the final text when they pause.
class WhisperListener {
  final SherpaVoice voice;
  final String language;
  final void Function(double level)? onLevel;
  final void Function()? onSpeechStart;
  final void Function(String text)? onPartial;
  final void Function(String text)? onFinal;

  /// A detected utterance that held no words (noise, an echo, a cough).
  final void Function()? onDropped;

  /// Pause that ends an utterance.
  final double endSilence;
  WhisperListener({
    required this.voice,
    required this.language,
    this.onLevel,
    this.onSpeechStart,
    this.onPartial,
    this.onFinal,
    this.onDropped,
    this.endSilence = 0.7,
  });

  SpeechDetector? _vad;
  StreamSubscription<Float32List>? _frames;
  final _speech = <Float32List>[];
  final _preroll = ListQueue<Float32List>();
  var _inSpeech = false, _partialBusy = false, _framesSincePartial = 0;
  var _epoch = 0;

  /// Bumped by [stop] and [discard]: a transcription from before is not
  /// delivered (audit C6).
  var _session = 0;
  Future<void> _finals = Future<void>.value();

  /// Frames kept from before speech is detected (VAD needs 250 ms of
  /// speech before it reports it, and a soft first sound may start before
  /// that): 0.5 s.
  static const prerollFrames = 16;

  /// A running caption every ~1.3 s of new speech.
  static const partialEveryFrames = 40;

  /// Speech that goes on this long is sent as it stands (Whisper reads 30 s
  /// at most): 28 s of 32 ms frames.
  static const maxSpeechFrames = 875;

  /// A running caption reads the last 12 s at most, so it stays quick.
  static const captionFrames = 375;

  bool get running => _frames != null;

  /// Speech is being heard now: a segment has started and not yet ended.
  bool get hearing => _inSpeech;

  /// While the answer plays on the media path (no echo canceller), what
  /// the microphone hears is that answer: it only moves the orb.
  bool get resting => _resting;
  var _resting = false;
  set resting(bool on) {
    if (on == _resting) return;
    _resting = on;
    // A sentence already heard is still transcribed (no epoch change).
    _vad?.reset();
    _speech.clear();
    _preroll.clear();
    _inSpeech = false;
  }

  /// False when the models are missing or the microphone was refused.
  Future<bool> start() async {
    if (running) return true;
    final paths = await VoiceModels.listeningPaths();
    if (paths == null) return false;
    _vad ??= SpeechDetector.create(paths.vad, minSilence: endSilence);
    unawaited(
      voice.warmListening(language).catchError((Object e) {
        _log.warning('Whisper did not load', e);
      }),
    );
    _frames = VoiceAudioChannel.frames().listen(_onFrame);
    if (!await VoiceAudioChannel.startMic()) {
      await stop();
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    _epoch++;
    _session++;
    await _frames?.cancel();
    _frames = null;
    try {
      await VoiceAudioChannel.stopMic();
    } catch (_) {}
    _vad?.reset();
    _speech.clear();
    _preroll.clear();
    _inSpeech = false;
  }

  /// Drops what was heard so far (the assistant's own echo, a cancelled
  /// turn).
  void discard() {
    _epoch++;
    _session++;
    _vad?.reset();
    _speech.clear();
    _inSpeech = false;
  }

  void dispose() {
    unawaited(stop());
    _vad?.dispose();
    _vad = null;
  }

  void _onFrame(Float32List frame) {
    final vad = _vad;
    if (vad == null) return;
    onLevel?.call(VoiceAudioChannel.level(frame));
    if (_resting) return;
    final finished = vad.accept(frame);
    if (vad.speaking && !_inSpeech) {
      _inSpeech = true;
      _speech
        ..clear()
        ..addAll(_preroll);
      _framesSincePartial = 0;
      onSpeechStart?.call();
    }
    if (_inSpeech) {
      _speech.add(frame);
      if (++_framesSincePartial >= partialEveryFrames &&
          !_partialBusy &&
          onPartial != null) {
        _framesSincePartial = 0;
        _partial();
      }
    } else {
      _preroll.add(frame);
      while (_preroll.length > prerollFrames) {
        _preroll.removeFirst();
      }
    }
    for (final segment in finished) {
      final heard = heardAudio(segment, _speech);
      _inSpeech = false;
      _speech.clear();
      _send(heard);
    }
    if (_inSpeech && _speech.length >= maxSpeechFrames) {
      // No pause for 28 s: what was said goes now, and listening goes on.
      final heard = _join(_speech);
      vad.reset();
      _inSpeech = false;
      _speech.clear();
      _send(heard);
    }
  }

  void _send(Float32List heard) {
    ++_epoch;
    final session = _session;
    _finals = _finals.then((_) => _final(heard, session));
  }

  void _partial() {
    final samples = _join(
      _speech.length > captionFrames
          ? _speech.sublist(_speech.length - captionFrames)
          : _speech,
    );
    final epoch = _epoch;
    _partialBusy = true;
    voice
        .transcribe(samples, language: language)
        .then((heard) {
          final text = cleanTranscript(heard?.text ?? '');
          if (epoch == _epoch && text.isNotEmpty) onPartial?.call(text);
        })
        .catchError((Object e) {
          _log.warning('Caption failed', e);
        })
        .whenComplete(() => _partialBusy = false);
  }

  Future<void> _final(Float32List samples, int session) async {
    // Shorter than 0.4 s: a cough or a click.
    var text = '';
    if (samples.length >= 6400) {
      try {
        final heard = await voice.transcribe(samples, language: language);
        text = cleanTranscript(heard?.text ?? '');
      } catch (e) {
        _log.warning('Transcription failed', e);
      }
    }
    if (!running || session != _session) return;
    if (text.isNotEmpty) {
      onFinal?.call(text);
    } else {
      onDropped?.call();
    }
  }

  /// What Whisper reads for a finished [segment]: what the microphone
  /// heard ([speech], from just before the first word to the pause after
  /// the last). The detector's own segment is cut tight, and Whisper then
  /// drops the last word ("Hi, how are you" was heard as "Hi, where are" on
  /// the phone). A blip under 0.4 s keeps its segment (it is checked as
  /// noise), and so does speech past Whisper's 30 s window.
  @visibleForTesting
  static Float32List heardAudio(Float32List segment, List<Float32List> speech) {
    if (segment.length < 6400 || speech.isEmpty) return segment;
    final all = _join(speech);
    return all.length <= 29 * 16000 ? all : segment;
  }

  static Float32List _join(List<Float32List> frames) {
    final out = Float32List(frames.fold(0, (a, f) => a + f.length));
    var at = 0;
    for (final f in frames) {
      out.setAll(at, f);
      at += f.length;
    }
    return out;
  }

  /// Whisper's known inventions on noise or silence (subtitle credits,
  /// "thank you for watching"), and bracketed sound tags.
  static String cleanTranscript(String text) {
    // A tag cut off by the end of a running caption ("[Music") too.
    var t = text
        .replaceAll(RegExp(r'\[[^\]]*(\]|$)|\([^)]*(\)|$)|♪+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = _collapseRepeats(t);
    final lower = t.toLowerCase().replaceAll(RegExp(r'[.!?,]'), '').trim();
    const invented = [
      'thank you for watching',
      'thanks for watching',
      'please subscribe',
      'sous-titres réalisés par',
      'sous-titrage',
      'merci d\'avoir regardé',
      'subtítulos realizados por',
      'gracias por ver',
      'amara.org',
    ];
    if (invented.any(lower.contains)) return '';
    if (RegExp(r'^[\s.…,!?-]*$').hasMatch(t)) t = '';
    return t;
  }

  /// Whisper's runaway loops on noise ("Okay, okay, okay…" seventeen times
  /// on the phone): a word or a phrase of up to four repeated four times or
  /// more is said once; a short text that was mostly such a loop is dropped.
  static String _collapseRepeats(String text) {
    final words = text.split(' ');
    String key(String w) =>
        w.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    var longest = 0;
    for (var n = 1; n <= 4; n++) {
      for (var i = 0; i + 2 * n <= words.length; i++) {
        var runs = 1;
        bool same(int a, int b) {
          for (var j = 0; j < n; j++) {
            if (key(words[a + j]) != key(words[b + j])) return false;
          }
          return true;
        }

        while (i + (runs + 1) * n <= words.length && same(i, i + runs * n)) {
          runs++;
        }
        if (runs >= 4) {
          longest = runs > longest ? runs : longest;
          // Keep the last copy (its punctuation ends the phrase).
          words.removeRange(i, i + (runs - 1) * n);
        }
      }
    }
    final out = words.join(' ');
    if (longest >= 6 && words.length <= 4) return '';
    return out;
  }
}

/// Kokoro read-out: sentences are synthesized one at a time, at most two
/// ahead of the one playing, and each is handed to the player before the
/// one playing ends, so speech has no gaps.
///
/// Audit C2/C4 (2026-10-08): a stop drops everything not yet synthesized
/// (the call already running cannot be cancelled, so it finishes unheard),
/// and the next answer starts as soon as that call is done.
class KokoroSpeaker {
  final SherpaVoice voice;
  KokoroVoice kokoro;
  double speed;

  /// A sentence started playing (for captions and read-aloud position).
  void Function(String sentence)? onSentence;

  /// Sound is coming out (true) or stopped (false): false only at a real
  /// gap between sentences or at the end.
  void Function(bool playing)? onPlaying;

  /// The sentence about to play, for a level that follows the voice.
  void Function(SpeechAudio audio)? onAudio;

  /// Everything queued has been spoken (not called after [stop]).
  void Function()? onIdle;
  void Function(Object error)? onError;
  KokoroSpeaker({required this.voice, required this.kokoro, this.speed = 1.0});

  final _queue = <String>[];
  void Function()? _interactiveLease;

  void _releaseAdmission() {
    _interactiveLease?.call();
    _interactiveLease = null;
  }

  /// Longest first piece of an answer: Kokoro reads it while the model is
  /// still writing, which slows both (phone, 2026-10-07: 72 characters took
  /// 2.6 s, and the voice began only after the text was done).
  static const firstMax = 44;

  /// Longest later piece: Kokoro is barely faster than speech on the
  /// phone, so the next piece must not take much longer to synthesize than
  /// the one playing takes to hear (tester, 2026-10-09: two seconds of
  /// silence at commas and stops with 220).
  static const pieceMax = 90;

  /// Pieces synthesized ahead of the one playing, at most.
  static const maxAhead = 2;

  /// Taken off the queue but not yet heard to the end: being synthesized,
  /// waiting, or playing.
  final _inFlight = <String>[];
  var _epoch = 0;

  /// The epoch of the loop that plays, or null.
  int? _runFor;

  bool get busy => _runFor == _epoch || _queue.isNotEmpty || _ahead.isNotEmpty;

  /// Stops at once and returns what was not heard to the end (the sentence
  /// cut off first), for a resume after a false interruption.
  Future<List<String>> interrupt() async {
    final rest = [..._inFlight, ..._queue];
    await stop();
    return rest;
  }

  void add(String text) {
    final parts = sentences(text, max: pieceMax);
    // The first words of an answer are cut short (at a comma) so the voice
    // starts sooner: Kokoro takes about as long as the speech on a phone.
    if (_runFor != _epoch &&
        _queue.isEmpty &&
        _ahead.isEmpty &&
        parts.isNotEmpty) {
      parts.replaceRange(0, 1, sentences(parts.first, max: firstMax));
    }
    _queue.addAll(parts);
    if (parts.isNotEmpty) {
      _interactiveLease ??= InferenceAdmission.shared.hold();
    }
    _fill();
    _wake?.complete();
    _wake = null;
    if (_runFor != _epoch && (_queue.isNotEmpty || _ahead.isNotEmpty)) {
      unawaited(_run());
    }
  }

  /// Pieces given to the synthesizer, in order, not yet to the player.
  final _ahead = <_Piece>[];

  /// The synthesizer's queue: one FFI call at a time.
  Future<void> _chain = Future.value();

  /// Wakes the loop while it waits for a piece to end.
  Completer<void>? _wake;

  void _fill() {
    while (_ahead.length < maxAhead && _queue.isNotEmpty) {
      _ahead.add(_synth(_queue.removeAt(0)));
    }
  }

  Future<void> stop() async {
    _epoch++;
    _queue.clear();
    _inFlight.clear();
    _ahead.clear();
    _releaseAdmission();
    _wake?.complete();
    _wake = null;
    // Silent from now on: the microphone need not wait for the player.
    if (_sounding) {
      _sounding = false;
      onPlaying?.call(false);
    }
    try {
      await VoiceAudioChannel.stopPlayback();
    } catch (_) {}
  }

  /// Sound is coming out (between onPlaying true and false).
  var _sounding = false;

  _Piece _synth(String text) {
    final piece = _Piece(text, _epoch);
    _inFlight.add(text);
    final before = _chain;
    final done = Completer<void>();
    _chain = done.future;
    piece.synthesized = () async {
      await before;
      try {
        // A stopped answer's pieces are dropped without a call.
        if (piece.gen == _epoch) {
          piece.audio = await voice.synthesize(
            text,
            voice: kokoro,
            speed: speed,
          );
        }
      } catch (e) {
        if (piece.gen == _epoch) onError?.call(e);
      } finally {
        piece.ready = true;
        done.complete();
      }
    }();
    return piece;
  }

  /// Hands [piece] to the player; [_Piece.heard] is set when it ends.
  void _play(_Piece piece) {
    piece.played = VoiceAudioChannel.play(piece.audio!).then(
      (heard) => piece.heard = heard,
      onError: (Object e) {
        piece.heard = false;
        onError?.call(e);
      },
    );
  }

  void _starts(_Piece piece) {
    onSentence?.call(piece.text);
    onAudio?.call(piece.audio!);
    if (!_sounding) {
      _sounding = true;
      onPlaying?.call(true);
    }
  }

  Future<void> _run() async {
    final epoch = _epoch;
    _runFor = epoch;
    _Piece? playing, next;
    try {
      while (epoch == _epoch) {
        _fill();
        if (playing != null && playing.heard != null) {
          final heard = playing.heard!;
          _inFlight.remove(playing.text);
          playing = next;
          next = null;
          if (!heard) break;
          if (playing != null) {
            _starts(playing);
          } else if (_sounding) {
            _sounding = false;
            onPlaying?.call(false);
          }
          continue;
        }
        if (next == null && _ahead.isNotEmpty && _ahead.first.ready) {
          final piece = _ahead.removeAt(0);
          if (piece.audio == null) {
            _inFlight.remove(piece.text);
            continue;
          }
          _play(piece);
          if (playing == null) {
            playing = piece;
            _starts(piece);
          } else {
            next = piece; // queued at the player: no gap
          }
          continue;
        }
        final waits = <Future<void>>[
          if (playing != null) playing.played!,
          if (next == null && _ahead.isNotEmpty) _ahead.first.synthesized,
        ];
        if (waits.isEmpty) break;
        waits.add((_wake ??= Completer<void>()).future);
        await Future.any(waits);
      }
    } catch (e) {
      // A failing listener ends this answer's speech; the lease below must
      // still be released or background indexing waits forever.
      if (epoch == _epoch) {
        _queue.clear();
        _ahead.clear();
        _inFlight.clear();
      }
      onError?.call(e);
    } finally {
      if (_runFor == epoch) _runFor = null;
    }
    if (epoch == _epoch) {
      if (_sounding) {
        _sounding = false;
        onPlaying?.call(false);
      }
      if (_queue.isNotEmpty || _ahead.isNotEmpty) {
        unawaited(_run());
      } else {
        _releaseAdmission();
        onIdle?.call();
      }
    }
  }

  static final _dangling = RegExp(
    r'(?:^|\s)(?:a|an|the|of|to|in|on|at|for|by|with|from|and|or|but|is|are|'
    r'was|were|be|that|this|its|my|your|their|our|his|her|un|une|le|la|les|'
    r'de|des|du|et|ou|en|el|los|las|y|o|del|que)$',
    caseSensitive: false,
  );

  // A sentence ends at a stop, unless a lowercase word follows ("the U.S.
  // is", "e.g. this"): those read on without a pause.
  static final _pieceEnd = RegExp(
    r'(?<=[!?…;:])\s+|(?<=\.)\s+(?!\p{Ll})|\n+',
    unicode: true,
  );

  /// Speakable pieces: sentences, long ones cut at a comma or space so the
  /// first audio is not held back by a 400-character sentence.
  static List<String> sentences(String text, {int max = 220}) {
    final out = <String>[];
    for (final raw in text.split(_pieceEnd)) {
      var s = raw.trim();
      while (s.length > max) {
        final comma = s.lastIndexOf(', ', max);
        var space = s.lastIndexOf(' ', max);
        // Not right after "a", "the", "of"…: the piece would sound cut off.
        var word = space;
        while (word > max ~/ 3 && _dangling.hasMatch(s.substring(0, word))) {
          word = s.lastIndexOf(' ', word - 1);
        }
        if (word >= max ~/ 3) space = word;
        final (int end, int next) = comma >= max ~/ 3
            ? (comma + 1, comma + 2)
            : space >= max ~/ 3
            ? (space, space + 1)
            : (max, max);
        out.add(s.substring(0, end).trim());
        s = s.substring(next).trim();
      }
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s)) out.add(s);
    }
    return out;
  }
}

/// A sentence on its way to the speaker.
class _Piece {
  final String text;

  /// The [KokoroSpeaker] epoch it belongs to: stale after a stop.
  final int gen;
  _Piece(this.text, this.gen);

  SpeechAudio? audio;
  var ready = false;
  late final Future<void> synthesized;

  /// Set once handed to the player; [heard] when it ended.
  Future<void>? played;
  bool? heard;
}

/// Loudness of [audio] every [step] (0…1 RMS), to animate while it plays.
List<double> speechEnvelope(
  SpeechAudio audio, {
  Duration step = const Duration(milliseconds: 32),
}) {
  final n = (audio.sampleRate * step.inMicroseconds / 1e6).round();
  if (n <= 0) return const [];
  return [
    for (var at = 0; at < audio.pcm.length; at += n)
      () {
        final end = at + n < audio.pcm.length ? at + n : audio.pcm.length;
        var sum = 0.0;
        for (var i = at; i < end; i++) {
          final v = audio.pcm[i] / 32768.0;
          sum += v * v;
        }
        return math.sqrt(sum / (end - at));
      }(),
  ];
}

/// Splits a growing answer into the sentences that are finished, and
/// keeps its own cursor of what was handed to the voice.
///
/// The cursor belongs to speech (audit C1, 2026-10-08): when the saved
/// answer differs from the streamed one (citations added, Markdown cleaned,
/// a figure corrected), what was already spoken is found again by its
/// letters and digits, so nothing is repeated and no word is cut in half.
class SentenceStream {
  /// Shortest first clause spoken on its own (shorter ones wait for more).
  static const firstClauseMin = 20;

  /// Longest wait for the first words when no stop or comma comes: then
  /// whole words go (audit C3).
  static const firstMaxWait = Duration(milliseconds: 700);

  final DateTime Function() _clock;
  SentenceStream({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  var consumed = 0;

  /// What was taken, exactly as it was in the text then.
  var _taken = '';
  DateTime? _firstSeen;

  // A finished sentence: its stop and the start of the next word, which
  // must not be lowercase ("the U.S. is" goes on).
  static final _end = RegExp(
    r'[!?…](?=\s)|\.(?=\s+[^\s\p{Ll}])|\n',
    unicode: true,
  );

  // The text ends on a stop (closing quotes and citations may follow).
  static final _endsDone = RegExp(
    r'''[.!?…]["'”’»)\]]*(?:\s*\[\d+(?:\s*,\s*\d+)*\])?\s*$''',
  );

  // "U.S." or "e.g." at the very end: the sentence may go on.
  // "3." may be "3.14" still being written.
  static final _endsAbbrev = RegExp(
    r'(?:(?:^|\s)(?:\p{L}\.){2,}|\d\.)\s*$',
    unicode: true,
  );

  /// Complete sentences of [text] after [consumed]; with [flush] the rest.
  ///
  /// [settled]: the model has paused, so a sentence ending the text is
  /// finished too. A text that no longer starts with what was taken is
  /// lined up with it again; one that was replaced (a tool round's words
  /// moved out of the answer) starts over.
  String take(String text, {bool flush = false, bool settled = false}) {
    if (consumed > 0 && !text.startsWith(_taken)) _realign(text);
    final rest = text.substring(consumed);
    if (flush) return _advance(text, rest.length);
    if (consumed == 0 && rest.trim().isNotEmpty) _firstSeen ??= _clock();
    var end = _end.allMatches(rest).lastOrNull?.end ?? 0;
    if (settled &&
        _endsDone.hasMatch(rest) &&
        !_endsAbbrev.hasMatch(rest.trimRight())) {
      end = rest.length;
    }
    // The answer's first clause goes as soon as its comma is written: the
    // voice starts on it while the rest of the sentence is generated.
    if (end == 0 && consumed == 0) {
      end =
          RegExp(r',(?=\s)')
              .allMatches(rest)
              .where((m) => m.start >= firstClauseMin)
              .firstOrNull
              ?.end ??
          0;
      if (end == 0 &&
          _firstSeen != null &&
          _clock().difference(_firstSeen!) >= firstMaxWait) {
        end = _wholeWords(rest);
      }
    }
    if (end == 0) return '';
    return _advance(text, end);
  }

  String _advance(String text, int end) {
    final out = text.substring(consumed, consumed + end);
    consumed += end;
    _taken = text.substring(0, consumed);
    return out;
  }

  /// The words of a first clause that has no stop yet: all but the last
  /// (it may still be growing), and not ending on "the", "of"… At least
  /// five words, or nothing.
  static int _wholeWords(String rest) {
    var end = rest.trimRight().lastIndexOf(RegExp(r'\s'));
    while (end > 0 &&
        KokoroSpeaker._dangling.hasMatch(rest.substring(0, end))) {
      end = rest.substring(0, end).trimRight().lastIndexOf(RegExp(r'\s'));
    }
    if (end <= 0) return 0;
    final words = rest.substring(0, end).trim().split(RegExp(r'\s+'));
    if (words.length < 5 || end < firstClauseMin) return 0;
    return end;
  }

  // Citation markers ("[1]", "[1, 5]"): not words of the answer.
  static final _cite = RegExp(r'\[\d+(?:\s*,\s*\d+)*\]');
  static final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _words = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// The letters and digits of [text], lowercased, and where each is.
  static (String, List<int>) _letters(String text) {
    final skip = List<bool>.filled(text.length, false);
    for (final m in _cite.allMatches(text)) {
      for (var i = m.start; i < m.end; i++) {
        skip[i] = true;
      }
    }
    final out = StringBuffer();
    final at = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (skip[i] || !_alnum.hasMatch(text[i])) continue;
      out.write(text[i].toLowerCase());
      at.add(i);
    }
    return (out.toString(), at);
  }

  /// Finds in [text] where the spoken part ends.
  void _realign(String text) {
    final (spoken, _) = _letters(_taken);
    final (now, at) = _letters(text);
    var cut = -1;
    if (spoken.isNotEmpty && now.startsWith(spoken)) {
      cut = at[spoken.length - 1] + 1;
    } else if (_sameStart(_taken, text)) {
      // The same answer with a changed word (a corrected figure) in what
      // was spoken: as many sentences on.
      final said =
          _end.allMatches(_taken).length + (_endsDone.hasMatch(_taken) ? 1 : 0);
      final ends = _end.allMatches(text).toList();
      cut = said == 0
          ? 0
          : said <= ends.length
          ? ends[said - 1].end
          : text.length;
    }
    if (cut < 0) {
      reset(); // replaced: start over
      return;
    }
    // What closed the spoken sentence: its stop, quotes, a citation.
    final tail = RegExp(
      r'''^(?:\s*\[\d+(?:\s*,\s*\d+)*\]|[*_~)\]"'”’».,;:!?…])*''',
    ).firstMatch(text.substring(cut));
    consumed = cut + (tail?.end ?? 0);
    _taken = text.substring(0, consumed);
  }

  /// Both start with the same three words.
  static bool _sameStart(String a, String b) {
    List<String> head(String t) => _words
        .allMatches(t.toLowerCase())
        .take(3)
        .map((m) => m.group(0)!)
        .toList();
    final x = head(a), y = head(b);
    return x.length == 3 && y.length == 3 && x.join(' ') == y.join(' ');
  }

  void reset() {
    consumed = 0;
    _taken = '';
    _firstSeen = null;
  }
}

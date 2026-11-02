import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueChanged, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/l10n/l10n.dart';
import '../../core/platform/desktop_host.dart';
import '../../core/utils/inference_admission.dart';
import '../settings/presentation/providers/settings_provider.dart';
import 'desktop_voice_policy.dart';
import 'offline_dictation.dart';
import 'sherpa_voice.dart';
import 'voice_models.dart';
import 'voice_models_provider.dart';
import 'voice_pipeline.dart';

/// Dictation and read-aloud (FX-01). With the on-device voice installed
/// (2026-10-07) Whisper listens and Kokoro speaks, all on the phone; else
/// verified offline platform voices. Android dictation always uses the
/// dedicated on-device recognizer; unverified system voices fail closed.
class VoiceState {
  final bool listening, speaking, available, paused;
  final String partial;
  final String? error;

  /// Id of the message being read, for the bubble's speaker icon.
  final String? speakingId;
  const VoiceState({
    this.listening = false,
    this.speaking = false,
    this.paused = false,
    this.available = true,
    this.partial = '',
    this.error,
    this.speakingId,
  });
  VoiceState copyWith({
    bool? listening,
    bool? speaking,
    bool? paused,
    bool? available,
    String? partial,
    String? error,
    bool clearError = false,
    String? speakingId,
    bool clearSpeakingId = false,
  }) => VoiceState(
    listening: listening ?? this.listening,
    speaking: speaking ?? this.speaking,
    paused: paused ?? this.paused,
    available: available ?? this.available,
    partial: partial ?? this.partial,
    error: clearError ? null : error ?? this.error,
    speakingId: clearSpeakingId ? null : speakingId ?? this.speakingId,
  );
}

class VoiceNotifier extends Notifier<VoiceState> {
  SpeechToText? _stt;
  FlutterTts? _tts;

  /// True while a system-voice speak() is pending. flutter_tts on Windows
  /// answers the pending speak() inside stop() without a null check, so a
  /// stop() with nothing playing crashed the PC app (owner, 2026-11-01).
  bool _ttsBusy = false;
  bool _sttReady = false, _alive = true, _usingOffline = false;
  OfflineDictation? _offline;
  String _spokenText = '';
  int _position = 0, _chunkStart = 0, _speechEpoch = 0;
  double _rate = 0.5;
  KokoroSpeaker? _kokoro;
  WhisperListener? _whisper;
  Timer? _whisperIdle;

  /// Ends the Whisper dictation with everything heard (set while it runs).
  void Function()? _whisperDone;
  int _listenEpoch = 0;

  /// Kokoro read-out: the sentences and the one playing, for pause/resume.
  List<String> _sentences = const [];
  int _sentence = 0;

  /// Bounded utterances preserve every character and break at sentences.
  static List<String> chunks(String text, {int limit = 3000}) {
    if (limit < 32) throw ArgumentError.value(limit, 'limit');
    final out = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + limit).clamp(0, text.length);
      if (end < text.length) {
        final segment = text.substring(start, end);
        final boundaries = RegExp(r'[.!?]\s|\n').allMatches(segment).toList();
        if (boundaries.isNotEmpty && boundaries.last.end > limit ~/ 2) {
          end = start + boundaries.last.end;
        } else {
          final space = segment.lastIndexOf(' ');
          if (space > limit ~/ 2) end = start + space + 1;
        }
        if (end > start &&
            text.codeUnitAt(end - 1) >= 0xD800 &&
            text.codeUnitAt(end - 1) <= 0xDBFF) {
          end--;
        }
      }
      out.add(text.substring(start, end));
      start = end;
    }
    return out;
  }

  @override
  VoiceState build() {
    // Queued sentences carry the old engine's speaker/language IDs. Stop them
    // before a newly selected engine can receive them (owner, 2026-11-02).
    ref.listen(
      settingsProvider.select((s) => s.readingVoice),
      (_, _) => unawaited(stopSpeaking()),
    );
    ref.onDispose(() {
      _alive = false;
      _whisperIdle?.cancel();
      _whisper?.dispose();
      unawaited(_kokoro?.stop());
      unawaited(_offline?.dispose());
      _stt?.cancel();
      unawaited(_stopTts());
    });
    return const VoiceState();
  }

  /// Markdown → speakable text: no code fences, links become their label,
  /// emphasis and headings lose their markers, citations disappear.
  static String speakable(String markdown) => markdown
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' code omitted. ')
      .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
      // With the space before it: "today [1]." must not read "today .".
      .replaceAll(RegExp(r'\s*\[\d+(?:\s*,\s*\d+)*\]'), '')
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'[*_~]{1,3}'), '')
      .replaceAll(RegExp(r'\|'), ', ')
      // "Bonne journée! 😊": not something to read out.
      .replaceAll(
        RegExp(
          r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
          unicode: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();

  Future<bool> _initStt() async {
    if (_sttReady) return true;
    _stt ??= SpeechToText();
    try {
      _sttReady = await _stt!.initialize(
        onError: (e) {
          if (!_alive) return;
          state = state.copyWith(
            listening: false,
            error: _speechError(e.errorMsg),
          );
        },
        onStatus: (s) {
          if (!_alive) return;
          if (s == 'done' || s == 'notListening') {
            state = state.copyWith(listening: false);
          }
        },
      );
    } catch (e) {
      _sttReady = false;
      state = state.copyWith(
        available: false,
        error: 'Dictation unavailable: $e',
      );
    }
    if (!_sttReady) state = state.copyWith(available: false);
    return _sttReady;
  }

  static String _explain(String code) => switch (code) {
    'offline_unavailable' =>
      'On-device dictation is unavailable. Install an offline speech service and language pack. No network recognizer was started.',
    'offline_recognition_failed' =>
      'On-device dictation failed. Check the offline language pack in the phone\'s speech settings. No network recognizer was started.',
    'error_no_match' => 'No speech recognised.',
    'error_speech_timeout' => 'No speech heard.',
    'error_permission' ||
    'error_audio' => 'Microphone permission is needed for dictation.',
    'error_language_unavailable' || 'error_language_not_supported' =>
      'On-device recognition has no language pack installed. Install one in the phone\'s speech settings, or allow the network recognizer.',
    'error_network' => 'The recognizer needs a network and none is available.',
    _ => 'Dictation error ($code).',
  };

  String _speechError(String code) {
    if (DesktopHost.active &&
        RegExp(
          'permission|denied|audio',
          caseSensitive: false,
        ).hasMatch(code)) {
      return stringsFor(
        ref.read(settingsProvider).localeCode,
      ).desktopVoiceMicPrivacy;
    }
    return _explain(code);
  }

  /// Starts dictation; [onText] receives the running transcript, [onFinal]
  /// the last words when the session ends.
  Future<void> listen({
    required ValueChanged<String> onText,
    ValueChanged<String>? onFinal,
    bool onDeviceOnly = true,
    String? localeId,
  }) async {
    if (state.listening) return stop();
    final epoch = ++_listenEpoch;
    if (_naturalListening()) {
      try {
        if (await _listenWhisper(onText, onFinal)) return;
      } on PlatformException catch (e) {
        if (e.code == 'microphone_denied') {
          state = state.copyWith(
            listening: false,
            error: stringsFor(
              ref.read(settingsProvider).localeCode,
            ).desktopVoiceMicPrivacy,
          );
          return;
        }
        rethrow;
      }
    }
    if (!_alive || epoch != _listenEpoch) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _usingOffline = true;
      _offline ??= OfflineDictation();
      state = state.copyWith(
        listening: true,
        available: true,
        partial: '',
        clearError: true,
      );
      try {
        await _offline!.listen(
          localeId: localeId,
          onResult: (text, isFinal) {
            if (!_alive || epoch != _listenEpoch) return;
            state = state.copyWith(partial: text, listening: !isFinal);
            onText(text);
            if (isFinal) onFinal?.call(text);
          },
          onError: (code) {
            if (!_alive) return;
            state = state.copyWith(
              listening: false,
              error: code == 'cancelled' ? null : _explain(code),
              clearError: code == 'cancelled',
            );
          },
        );
      } on PlatformException catch (e) {
        if (_alive) {
          state = state.copyWith(
            listening: false,
            error: e.code == 'cancelled' ? null : _explain(e.code),
            clearError: e.code == 'cancelled',
          );
        }
      } on MissingPluginException {
        if (_alive) {
          state = state.copyWith(
            listening: false,
            error: _explain('offline_unavailable'),
          );
        }
      }
      return;
    }
    if (!_alive || epoch != _listenEpoch) return;
    _usingOffline = false;
    if (DesktopHost.active && await VoiceAudioChannel.micPrivacyDenied()) {
      state = state.copyWith(
        listening: false,
        error: stringsFor(
          ref.read(settingsProvider).localeCode,
        ).desktopVoiceMicPrivacy,
      );
      return;
    }
    if (!await _initStt() || !_alive || epoch != _listenEpoch) return;
    state = state.copyWith(listening: true, partial: '', clearError: true);
    try {
      await _stt!.listen(
        onResult: (r) {
          if (!_alive) return;
          state = state.copyWith(partial: r.recognizedWords);
          onText(r.recognizedWords);
          if (r.finalResult) {
            onFinal?.call(r.recognizedWords);
            state = state.copyWith(listening: false);
          }
        },
        listenOptions: SpeechListenOptions(
          onDevice: true,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 4),
          localeId: localeId,
        ),
      );
    } catch (e) {
      state = state.copyWith(listening: false, error: 'Dictation failed: $e');
    }
  }

  bool _naturalListening() => offlineVoiceReady(
    enabled: ref.read(settingsProvider).naturalVoice,
    installed: ref.read(voiceModelsProvider).canListen,
  );

  bool _naturalSpeaking() => offlineVoiceReady(
    enabled: ref.read(settingsProvider).naturalVoice,
    installed: ref
        .read(voiceModelsProvider)
        .canSpeakWith(ref.read(settingsProvider).readingVoice),
  );

  /// The voice for the app language and the chosen speaker.
  KokoroVoice kokoroVoice() {
    final s = ref.read(settingsProvider);
    if (s.readingVoice == VoiceModels.supertonic.id) {
      return KokoroVoice(
        s.supertonicSid,
        voiceLanguage(s.localeCode),
        'Supertonic 2',
      );
    }
    return KokoroVoice.forLanguage(
      voiceLanguage(s.localeCode),
      sid: s.kokoroSid < 0 ? null : s.kokoroSid,
    );
  }

  /// Dictation through Whisper: captions while speaking, each sentence
  /// added when the user pauses, and listening goes on across pauses until
  /// the user stops (or 20 s of silence). One pause used to end it, so a
  /// long prompt kept only its first sentences. False when the microphone
  /// could not start.
  Future<bool> _listenWhisper(
    ValueChanged<String> onText,
    ValueChanged<String>? onFinal,
  ) async {
    final voice = ref.read(sherpaVoiceProvider);
    _whisper?.dispose();
    var heard = false;
    final said = <String>[];
    String withSaid(String text) =>
        [...said, if (text.isNotEmpty) text].join(' ');
    void idle(Duration after) {
      _whisperIdle?.cancel();
      _whisperIdle = Timer(after, () {
        if (_alive && state.listening) unawaited(stop());
      });
    }

    late final WhisperListener listener;
    listener = _whisper = WhisperListener(
      voice: voice,
      language: voiceLanguage(ref.read(settingsProvider).localeCode),
      endSilence: 1.0,
      captionAll: true,
      onSpeechStart: () {
        heard = true;
        _whisperIdle?.cancel();
      },
      onPartial: (text) {
        if (!_alive) return;
        final all = withSaid(text);
        state = state.copyWith(partial: all);
        onText(all);
      },
      onFinal: (text) {
        if (!_alive) return;
        said.add(text);
        final all = withSaid('');
        state = state.copyWith(partial: all);
        onText(all);
        if (identical(_whisper, listener)) idle(const Duration(seconds: 20));
      },
    );
    _whisperDone = () {
      final all = withSaid('');
      if (all.isNotEmpty) onText(all);
      onFinal?.call(all);
    };
    state = state.copyWith(
      listening: true,
      available: true,
      partial: '',
      clearError: true,
    );
    if (!await listener.start()) {
      _whisper = null;
      listener.dispose();
      if (_alive) state = state.copyWith(listening: false);
      return false;
    }
    if (!_alive || !identical(_whisper, listener)) {
      await listener.stop();
      return true;
    }
    // Nothing said within 8 s ends the session like the system recognizer.
    _whisperIdle?.cancel();
    _whisperIdle = Timer(const Duration(seconds: 8), () {
      if (!heard && _alive && state.listening) {
        unawaited(_stopWhisper());
        state = state.copyWith(
          listening: false,
          error: _explain('error_speech_timeout'),
        );
      }
    });
    return true;
  }

  /// Stops the Whisper dictation; the sentence being said is still
  /// transcribed and kept.
  Future<void> _stopWhisper() async {
    _whisperIdle?.cancel();
    final w = _whisper;
    final done = _whisperDone;
    _whisper = null;
    _whisperDone = null;
    if (_alive && w != null) state = state.copyWith(listening: false);
    await w?.finish();
    w?.dispose();
    if (_alive) done?.call();
  }

  Future<void> stop() async {
    _listenEpoch++;
    if (_whisper != null) {
      await _stopWhisper();
      if (_alive) state = state.copyWith(listening: false);
      return;
    }
    try {
      if (_usingOffline) {
        await _offline?.stop();
      } else {
        await _stt?.stop();
      }
    } on PlatformException catch (e) {
      if (_alive) {
        state = state.copyWith(error: 'Could not stop dictation: ${e.message}');
      }
    } finally {
      if (_alive) state = state.copyWith(listening: false);
    }
  }

  Future<void> _initTts() async {
    if (_tts != null) return;
    _tts = FlutterTts();
    await _tts!.awaitSpeakCompletion(true);
    _tts!.setProgressHandler((text, start, end, word) {
      if (_alive && state.speaking) {
        _position = (_chunkStart + end).clamp(0, _spokenText.length);
      }
    });
    _tts!.setErrorHandler((e) {
      if (!_alive) return;
      state = state.copyWith(
        speaking: false,
        clearSpeakingId: true,
        error: 'Read-aloud failed: $e',
      );
    });
  }

  /// Reads [markdown] aloud; tapping the same message again stops it.
  Future<void> speak(String markdown, {String? id, double? rate}) async {
    await _initTts();
    if (state.speaking && (id == null || id == state.speakingId)) {
      return pauseSpeaking();
    }
    if (state.paused && id == state.speakingId) return resumeSpeaking();
    final text = speakable(markdown);
    if (text.isEmpty) return;
    _speechEpoch++;
    await _stopTts();
    await _kokoro?.stop();
    _rate = rate ?? 0.5 * ref.read(settingsProvider).readingSpeed;
    if (_naturalSpeaking()) {
      _spokenText = text;
      _sentences = KokoroSpeaker.sentences(text);
      _sentence = 0;
      state = state.copyWith(
        speaking: true,
        paused: false,
        speakingId: id,
        clearError: true,
      );
      _readKokoro();
      return;
    }
    _spokenText = text;
    _position = 0;
    _rate = rate ?? 0.5 * ref.read(settingsProvider).readingSpeed;
    state = state.copyWith(
      speaking: true,
      paused: false,
      speakingId: id,
      clearError: true,
    );
    await _read();
  }

  /// Android voices may stream from the network: pick one flutter_tts
  /// reports as local ("0"). Windows voices (SAPI/OneCore) are all local.
  Future<bool> _selectOfflineVoice() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final voices = await _tts!.getVoices;
    if (voices is! List) return false;
    final lang = voiceLanguage(ref.read(settingsProvider).localeCode);
    for (final voice in voices) {
      if (voice is! Map ||
          !(voice['network_required'] == '0' ||
              voice['network_required'] == false) ||
          voice['name'] is! String ||
          voice['locale'] is! String) {
        continue;
      }
      final locale = voice['locale'] as String;
      if (locale.split(RegExp('[-_]')).first != lang) continue;
      await _tts!.setVoice({'name': voice['name'] as String, 'locale': locale});
      return true;
    }
    return false;
  }

  Future<void> _read() async {
    final epoch = ++_speechEpoch;
    final release = InferenceAdmission.shared.hold();
    try {
      if (!await _selectOfflineVoice()) {
        if (_alive && epoch == _speechEpoch) {
          state = state.copyWith(
            speaking: false,
            clearSpeakingId: true,
            error: stringsFor(
              ref.read(settingsProvider).localeCode,
            ).voiceOfflineUnavailable,
          );
        }
        return;
      }
      if (!_alive || epoch != _speechEpoch) return;
      await _tts!.setSpeechRate(_rate);
      for (final chunk in chunks(_spokenText.substring(_position))) {
        if (!_alive || epoch != _speechEpoch) return;
        _chunkStart = _position;
        _ttsBusy = true;
        try {
          await _tts!.speak(chunk);
        } finally {
          _ttsBusy = false;
        }
        if (!_alive || epoch != _speechEpoch) return;
        _position = _chunkStart + chunk.length;
      }
      if (_alive && epoch == _speechEpoch) {
        state = state.copyWith(
          speaking: false,
          paused: false,
          clearSpeakingId: true,
        );
      }
    } catch (e) {
      if (!_alive || epoch != _speechEpoch) return;
      state = state.copyWith(
        speaking: false,
        clearSpeakingId: true,
        error: 'Read-aloud failed: $e',
      );
    } finally {
      release();
    }
  }

  /// Kokoro from sentence [_sentence]; falls back to the system voice when
  /// synthesis fails.
  void _readKokoro() {
    final epoch = _speechEpoch;
    final speaker = _kokoro ??= KokoroSpeaker(
      voice: ref.read(sherpaVoiceProvider),
      kokoro: kokoroVoice(),
    );
    speaker
      ..kokoro = kokoroVoice()
      ..speed = (_rate / 0.5).clamp(0.6, 1.6)
      ..onSentence = (s) {
        if (epoch != _speechEpoch) return;
        final at = _sentences.indexOf(s, _sentence);
        if (at >= 0) _sentence = at;
      }
      ..onIdle = () {
        if (!_alive || epoch != _speechEpoch) return;
        state = state.copyWith(
          speaking: false,
          paused: false,
          clearSpeakingId: true,
        );
      }
      ..onError = (e) {
        if (!_alive || epoch != _speechEpoch) return;
        // The system voice takes over from the start of the sentence.
        _speechEpoch++;
        unawaited(speaker.stop());
        final from = _sentences.skip(_sentence).join(' ');
        _sentences = const [];
        _spokenText = from;
        _position = 0;
        unawaited(_initTts().then((_) => _read()));
      };
    speaker.add(_sentences.skip(_sentence).join('\n'));
  }

  Future<void> _stopTts() async {
    if (!_ttsBusy) return;
    _ttsBusy = false;
    await _tts?.stop();
  }

  Future<void> pauseSpeaking() async {
    _speechEpoch++;
    state = state.copyWith(speaking: false, paused: true);
    await _stopTts();
    await _kokoro?.stop();
  }

  Future<void> resumeSpeaking() async {
    if (!state.paused || _spokenText.isEmpty) return;
    state = state.copyWith(speaking: true, paused: false);
    if (_sentences.isNotEmpty) {
      _speechEpoch++;
      _readKokoro();
      return;
    }
    await _read();
  }

  Future<void> stopSpeaking() async {
    _speechEpoch++;
    _spokenText = '';
    _position = 0;
    _sentences = const [];
    await _stopTts();
    await _kokoro?.stop();
    if (_alive) {
      state = state.copyWith(
        speaking: false,
        paused: false,
        clearSpeakingId: true,
      );
    }
  }
}

final voiceProvider = NotifierProvider<VoiceNotifier, VoiceState>(
  VoiceNotifier.new,
);

/// The sherpa-onnx engines (Kokoro, Whisper), shared by read-aloud,
/// dictation and the conversation screen.
final sherpaVoiceProvider = Provider<SherpaVoice>((ref) {
  final voice = SherpaVoice();
  ref.onDispose(voice.dispose);
  // A pack deleted or being downloaded again: its worker must not go on
  // with the old files.
  ref.listen(voiceModelsProvider, (before, now) {
    for (final pack in VoiceModels.all) {
      final was = before?.of(pack).status == VoicePackStatus.ready;
      final isReady = now.of(pack).status == VoicePackStatus.ready;
      // Gone, or Parakeet just arrived: the listener picks again.
      if ((was && !isReady) ||
          (!was && isReady && pack.id == VoiceModels.parakeet.id)) {
        voice.releasePack(speaking: pack.unpackTo != null);
      }
    }
  });
  voice.readingVoice = ref.read(settingsProvider).readingVoice;
  ref.listen(
    settingsProvider.select((s) => s.readingVoice),
    (_, id) => voice.readingVoice = id,
  );
  voice.listeningModel = ref.read(settingsProvider).listeningModel;
  ref.listen(
    settingsProvider.select((s) => s.listeningModel),
    (_, id) => voice.listeningModel = id,
  );
  return voice;
});

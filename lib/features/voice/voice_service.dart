import 'dart:async';
import '../../core/utils/inference_admission.dart';

import 'package:flutter/foundation.dart'
    show ValueChanged, TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import '../settings/presentation/providers/settings_provider.dart';
import 'offline_dictation.dart';
import 'sherpa_voice.dart';
import 'voice_models.dart';
import 'voice_models_provider.dart';
import 'voice_pipeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictation and read-aloud (FX-01). With the on-device voice installed
/// (2026-10-07) Whisper listens and Kokoro speaks, all on the phone; else
/// the platform's own engines: the Android speech recognizer (on-device when
/// the setting says so) and the system text-to-speech. Android strict mode
/// uses a dedicated recognizer; network-enabled dictation and TTS follow the
/// system engine's behavior.
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
  bool _sttReady = false, _alive = true, _usingOffline = false;
  OfflineDictation? _offline;
  String _spokenText = '';
  int _position = 0, _chunkStart = 0, _speechEpoch = 0;
  double _rate = 0.5;
  KokoroSpeaker? _kokoro;
  WhisperListener? _whisper;
  Timer? _whisperIdle;
  bool _usingWhisper = false;

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
    ref.onDispose(() {
      _alive = false;
      _whisperIdle?.cancel();
      _whisper?.dispose();
      unawaited(_kokoro?.stop());
      unawaited(_offline?.dispose());
      _stt?.cancel();
      _tts?.stop();
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
          state = state.copyWith(listening: false, error: _explain(e.errorMsg));
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

  /// Starts dictation; [onText] receives the running transcript, [onFinal]
  /// the last words when the session ends.
  Future<void> listen({
    required ValueChanged<String> onText,
    ValueChanged<String>? onFinal,
    bool onDeviceOnly = true,
    String? localeId,
  }) async {
    if (state.listening) return stop();
    if (_naturalListening()) {
      if (await _listenWhisper(onText, onFinal)) return;
    }
    if (onDeviceOnly &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
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
            if (!_alive) return;
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
    _usingOffline = false;
    if (!await _initStt() || !_alive) return;
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
          onDevice: onDeviceOnly,
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

  bool _naturalListening() =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      ref.read(settingsProvider).naturalVoice &&
      ref.read(voiceModelsProvider).canListen;

  bool _naturalSpeaking() =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      ref.read(settingsProvider).naturalVoice &&
      ref.read(voiceModelsProvider).canSpeak;

  /// The voice for the app language and the chosen speaker.
  KokoroVoice kokoroVoice() {
    final s = ref.read(settingsProvider);
    return KokoroVoice.forLanguage(
      voiceLanguage(s.localeCode),
      sid: s.kokoroSid < 0 ? null : s.kokoroSid,
    );
  }

  /// One utterance through Whisper: captions while speaking, the text when
  /// the user pauses. False when the microphone could not start.
  Future<bool> _listenWhisper(
    ValueChanged<String> onText,
    ValueChanged<String>? onFinal,
  ) async {
    final voice = ref.read(sherpaVoiceProvider);
    _whisper?.dispose();
    var heard = false;
    final listener = _whisper = WhisperListener(
      voice: voice,
      language: voiceLanguage(ref.read(settingsProvider).localeCode),
      onSpeechStart: () => heard = true,
      onPartial: (text) {
        if (!_alive) return;
        state = state.copyWith(partial: text);
        onText(text);
      },
      onFinal: (text) {
        if (!_alive) return;
        _whisperIdle?.cancel();
        state = state.copyWith(partial: text, listening: false);
        onText(text);
        onFinal?.call(text);
        unawaited(_stopWhisper());
      },
    );
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
    _usingWhisper = true;
    // Nothing said within 8 s ends the session like the system recognizer.
    _whisperIdle?.cancel();
    _whisperIdle = Timer(const Duration(seconds: 8), () {
      if (!heard && _alive && state.listening) {
        unawaited(_stopWhisper());
        state = state.copyWith(
          listening: false,
          error: _explain('error_speech_timeout'),
        );
        onFinal?.call('');
      }
    });
    return true;
  }

  Future<void> _stopWhisper() async {
    _whisperIdle?.cancel();
    _usingWhisper = false;
    final w = _whisper;
    _whisper = null;
    await w?.stop();
    w?.dispose();
  }

  Future<void> stop() async {
    if (_usingWhisper) {
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
  Future<void> speak(String markdown, {String? id, double rate = 0.5}) async {
    await _initTts();
    if (state.speaking && (id == null || id == state.speakingId)) {
      return pauseSpeaking();
    }
    if (state.paused && id == state.speakingId) return resumeSpeaking();
    final text = speakable(markdown);
    if (text.isEmpty) return;
    _speechEpoch++;
    await _tts!.stop();
    await _kokoro?.stop();
    _rate = rate;
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
    _rate = rate;
    state = state.copyWith(
      speaking: true,
      paused: false,
      speakingId: id,
      clearError: true,
    );
    await _read();
  }

  Future<void> _read() async {
    final epoch = ++_speechEpoch;
    final release = InferenceAdmission.shared.hold();
    try {
      await _tts!.setSpeechRate(_rate);
      for (final chunk in chunks(_spokenText.substring(_position))) {
        if (!_alive || epoch != _speechEpoch) return;
        _chunkStart = _position;
        await _tts!.speak(chunk);
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

  Future<void> pauseSpeaking() async {
    _speechEpoch++;
    state = state.copyWith(speaking: false, paused: true);
    await _tts?.stop();
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
    await _tts?.stop();
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
        voice.releasePack(speaking: pack.id == VoiceModels.speaking.id);
      }
    }
  });
  voice.listeningModel = ref.read(settingsProvider).listeningModel;
  ref.listen(
    settingsProvider.select((s) => s.listeningModel),
    (_, id) => voice.listeningModel = id,
  );
  return voice;
});

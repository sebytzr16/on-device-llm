import 'dart:async';
import '../../core/utils/inference_admission.dart';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice_models.dart';

/// Synthesized speech: 16-bit mono PCM.
class SpeechAudio {
  final Int16List pcm;
  final int sampleRate;
  const SpeechAudio(this.pcm, this.sampleRate);
  Duration get duration =>
      Duration(microseconds: pcm.length * 1000000 ~/ math.max(1, sampleRate));
}

/// What Whisper heard.
class Heard {
  final String text, language;
  const Heard(this.text, this.language);
}

/// A background isolate holding one sherpa-onnx model; requests are
/// answered in order. sherpa-onnx calls are synchronous FFI, so each model
/// gets its own isolate: speaking never waits for listening.
@visibleForTesting
class SherpaWorker {
  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _receive;
  final Map<int, Completer<Map<Object?, Object?>>> _pending;
  var _next = 0;
  SherpaWorker._(this._isolate, this._send, this._receive, this._pending);

  @visibleForTesting
  Isolate get isolate => _isolate;

  /// The worker answers on the port it was started with: first its own
  /// port, then one reply per request.
  static Future<SherpaWorker> spawn(void Function(SendPort) entry) async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    final pending = <int, Completer<Map<Object?, Object?>>>{};
    receive.listen((m) {
      if (m is SendPort) {
        if (!ready.isCompleted) ready.complete(m);
      } else if (m is Map) {
        pending.remove(m['id'])?.complete(m);
      }
    });
    final isolate = await Isolate.spawn(entry, receive.sendPort);
    final send = await ready.future.timeout(const Duration(seconds: 20));
    return SherpaWorker._(isolate, send, receive, pending);
  }

  /// A request is being answered.
  bool get busy => _pending.isNotEmpty;

  Future<Map<Object?, Object?>> call(Map<String, Object?> request) {
    final id = _next++;
    final done = Completer<Map<Object?, Object?>>();
    _pending[id] = done;
    _send.send({...request, 'id': id});
    return done.future;
  }

  /// The worker frees its model and exits by itself once the requests
  /// already sent are done. It is not killed: a native call cannot be
  /// interrupted, and a kill landing as that call returns would skip the
  /// free, leaving Kokoro or Whisper in memory until the app closes.
  void dispose() {
    _send.send({'cmd': 'close'});
    for (final p in _pending.values) {
      p.complete({'error': 'closed'});
    }
    _pending.clear();
    _receive.close();
  }
}

/// Runs [handle] for each request in a worker isolate; [close] frees the
/// models when the app asks, after which the isolate has no open port and
/// exits.
@visibleForTesting
void serveSherpaWorker(
  SendPort boot,
  Map<String, Object?> Function(Map<Object?, Object?>) handle,
  void Function() close,
) {
  final inbox = ReceivePort();
  boot.send(inbox.sendPort);
  inbox.listen((m) {
    if (m is! Map) return;
    if (m['cmd'] == 'close') {
      try {
        close();
      } finally {
        inbox.close();
      }
      return;
    }
    Map<String, Object?> out;
    try {
      out = handle(m);
    } catch (e) {
      out = {'error': '$e'};
    }
    boot.send({...out, 'id': m['id']});
  });
}

/// Kokoro-82M: one engine per espeak language, only one kept loaded.
void _mouthMain(SendPort boot) {
  sherpa.initBindings();
  String? lang;
  sherpa.OfflineTts? tts;
  serveSherpaWorker(
    boot,
    (m) {
      final want = m['lang'] as String;
      if (tts == null || lang != want) {
        tts?.free();
        tts = null;
        tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              kokoro: sherpa.OfflineTtsKokoroModelConfig(
                model: m['model'] as String,
                voices: m['voices'] as String,
                tokens: m['tokens'] as String,
                dataDir: m['dataDir'] as String,
                lexicon: m['lexicon'] as String,
                lang: want,
              ),
              numThreads: m['threads'] as int,
              provider: m['provider'] as String? ?? 'cpu',
              debug: false,
            ),
          ),
        );
        lang = want;
      }
      if (m['cmd'] == 'warm') return const {};
      final audio = tts!.generateWithConfig(
        text: m['text'] as String,
        config: sherpa.OfflineTtsGenerationConfig(
          sid: m['sid'] as int,
          speed: (m['speed'] as num).toDouble(),
        ),
      );
      final pcm = Int16List(audio.samples.length);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = (audio.samples[i].clamp(-1.0, 1.0) * 32767).round();
      }
      return {
        'pcm': TransferableTypedData.fromList([pcm]),
        'rate': audio.sampleRate,
      };
    },
    () {
      tts?.free();
      tts = null;
    },
  );
}

/// Whisper base or Parakeet: one recognizer, a new stream per utterance.
void _earsMain(SendPort boot) {
  sherpa.initBindings();
  sherpa.OfflineRecognizer? recognizer;
  String? loaded;
  serveSherpaWorker(
    boot,
    (m) {
      final joiner = m['joiner'] as String?;
      // Parakeet finds the language itself: one recognizer for all.
      final want = joiner != null
          ? 'parakeet:${m['encoder']}'
          : '${m['encoder']}:${m['language']}';
      if (recognizer == null || loaded != want) {
        recognizer?.free();
        recognizer = null;
        recognizer = sherpa.OfflineRecognizer(
          sherpa.OfflineRecognizerConfig(
            model: joiner != null
                ? sherpa.OfflineModelConfig(
                    transducer: sherpa.OfflineTransducerModelConfig(
                      encoder: m['encoder'] as String,
                      decoder: m['decoder'] as String,
                      joiner: joiner,
                    ),
                    tokens: m['tokens'] as String,
                    modelType: 'nemo_transducer',
                    numThreads: m['threads'] as int,
                    debug: false,
                  )
                : sherpa.OfflineModelConfig(
                    whisper: sherpa.OfflineWhisperModelConfig(
                      encoder: m['encoder'] as String,
                      decoder: m['decoder'] as String,
                      language: m['language'] as String,
                      task: 'transcribe',
                    ),
                    tokens: m['tokens'] as String,
                    numThreads: m['threads'] as int,
                    debug: false,
                  ),
          ),
        );
        loaded = want;
      }
      if (m['cmd'] == 'warm') return const {};
      final samples = (m['samples'] as TransferableTypedData)
          .materialize()
          .asFloat32List();
      final stream = recognizer!.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: 16000);
        recognizer!.decode(stream);
        final r = recognizer!.getResult(stream);
        return {'text': r.text.trim(), 'lang': r.lang};
      } finally {
        stream.free();
      }
    },
    () {
      recognizer?.free();
      recognizer = null;
    },
  );
}

/// The on-device voice through sherpa-onnx. Workers start on first use and
/// stay while a [lease] is held (the conversation screen), or until they
/// have been idle for [idleRelease]; a voice pack deleted or replaced frees
/// the worker using it ([releasePack]) (audit C8, 2026-10-08).
class SherpaVoice {
  SherpaWorker? _mouth, _ears;
  Future<SherpaWorker>? _mouthStart, _earsStart;
  SpeakingPaths? _speaking;
  ListeningPaths? _listening;

  /// Bumped when a worker is freed: one still starting is not kept.
  var _mouthGen = 0, _earsGen = 0;

  /// Unused this long and not leased, both workers are freed (Kokoro and
  /// Whisper hold a few hundred MB).
  static const idleRelease = Duration(minutes: 3);
  var _leases = 0;
  Timer? _idle;

  /// Threads per model: Kokoro and Whisper rarely run at once.
  final int threads;

  /// ONNX Runtime execution provider for Kokoro ('cpu', 'xnnpack', 'nnapi').
  final String speakProvider;

  /// Kokoro's threads: with 2 it was slower than speech while the model
  /// wrote, a pause at every comma and stop (tester, 2026-10-09).
  final int speakThreads;
  SherpaVoice({
    this.threads = 4,
    this.speakThreads = 4,
    this.speakProvider = 'cpu',
  });

  static Future<bool> canSpeak() => VoiceModels.isReady(VoiceModels.speaking);
  static Future<bool> canListen() async =>
      await VoiceModels.isReady(VoiceModels.listening) ||
      await VoiceModels.isReady(VoiceModels.parakeet);

  Future<SherpaWorker> _mouthWorker() async {
    _idle?.cancel();
    if (_mouth != null) return _mouth!;
    final gen = _mouthGen;
    final start = _mouthStart ??= SherpaWorker.spawn(_mouthMain);
    final worker = await start;
    if (gen != _mouthGen) {
      worker.dispose();
      return _mouthWorker();
    }
    return _mouth = worker;
  }

  Future<SherpaWorker> _earsWorker() async {
    _idle?.cancel();
    if (_ears != null) return _ears!;
    final gen = _earsGen;
    final start = _earsStart ??= SherpaWorker.spawn(_earsMain);
    final worker = await start;
    if (gen != _earsGen) {
      worker.dispose();
      return _earsWorker();
    }
    return _ears = worker;
  }

  /// Keeps the workers loaded until the returned function is called.
  void Function() lease() {
    _leases++;
    _idle?.cancel();
    var done = false;
    return () {
      if (done) return;
      done = true;
      _leases--;
      _touch();
    };
  }

  /// Starts the idle countdown after a request.
  void _touch() {
    _idle?.cancel();
    if (_leases > 0 || (_mouth == null && _ears == null)) return;
    _idle = Timer(idleRelease, () {
      if (_leases > 0 || (_mouth?.busy ?? false) || (_ears?.busy ?? false)) {
        return _touch();
      }
      releasePack(speaking: true);
      releasePack(speaking: false);
    });
  }

  /// Frees the worker of the speaking (Kokoro) or listening (Whisper)
  /// pack, and forgets its paths: its files were deleted or are being
  /// replaced. The next request starts a fresh one.
  void releasePack({required bool speaking}) {
    if (speaking) {
      _mouthGen++;
      _mouth?.dispose();
      _mouth = null;
      _mouthStart = null;
      _speaking = null;
    } else {
      _earsGen++;
      _ears?.dispose();
      _ears = null;
      _earsStart = null;
      _listening = null;
    }
  }

  Future<Map<String, Object?>?> _speakRequest(KokoroVoice voice) async {
    final paths = _speaking ??= await VoiceModels.speakingPaths();
    if (paths == null) return null;
    return {
      'model': paths.model,
      'voices': paths.voices,
      'tokens': paths.tokens,
      'dataDir': paths.dataDir,
      'lexicon': paths.lexiconFor(voice.lang),
      'lang': voice.lang,
      'threads': speakThreads,
      'provider': speakProvider,
    };
  }

  /// [InferenceSettings.listeningModel]; a change frees the listening
  /// worker so the next utterance loads the other model.
  String get listeningModel => _listeningModel;
  var _listeningModel = '';
  set listeningModel(String id) {
    if (id == _listeningModel) return;
    _listeningModel = id;
    releasePack(speaking: false);
  }

  Future<Map<String, Object?>?> _listenRequest(String language) async {
    final paths = _listening ??= await VoiceModels.listeningPaths(
      preferred: _listeningModel,
    );
    if (paths == null) return null;
    return {
      'encoder': paths.encoder,
      'decoder': paths.decoder,
      'tokens': paths.tokens,
      'joiner': paths.joiner,
      'language': language,
      'threads': threads,
    };
  }

  /// Loads Kokoro for [voice] ahead of the first sentence.
  Future<void> warmSpeaking(KokoroVoice voice) async {
    final release = InferenceAdmission.shared.hold();
    try {
      final request = await _speakRequest(voice);
      if (request == null) return;
      await (await _mouthWorker()).call({...request, 'cmd': 'warm'});
      _touch();
    } finally {
      release();
    }
  }

  Future<void> warmListening(String language) async {
    final release = InferenceAdmission.shared.hold();
    try {
      final request = await _listenRequest(language);
      if (request == null) return;
      await (await _earsWorker()).call({...request, 'cmd': 'warm'});
      _touch();
    } finally {
      release();
    }
  }

  /// Speech for [text]; null when Kokoro is not installed.
  Future<SpeechAudio?> synthesize(
    String text, {
    required KokoroVoice voice,
    double speed = 1.0,
  }) async {
    final release = InferenceAdmission.shared.hold();
    try {
      final request = await _speakRequest(voice);
      if (request == null || text.trim().isEmpty) return null;
      final r = await (await _mouthWorker()).call({
        ...request,
        'cmd': 'speak',
        'text': text,
        'sid': voice.sid,
        'speed': speed,
      });
      _touch();
      if (r['error'] != null) throw StateError('${r['error']}');
      final pcm = (r['pcm'] as TransferableTypedData)
          .materialize()
          .asInt16List();
      return SpeechAudio(pcm, r['rate'] as int);
    } finally {
      release();
    }
  }

  /// The shortest clip the recognizer is given (0.1 s at 16 kHz): sherpa's
  /// offline decoder dereferenced null on an empty one (ASR probe,
  /// 2026-10-18), and speech is at least 0.25 s.
  static const minSamples = 1600;

  /// Whisper on 16 kHz mono samples. [language] '' detects it.
  Future<Heard?> transcribe(Float32List samples, {String language = ''}) async {
    final release = InferenceAdmission.shared.hold();
    try {
      final request = await _listenRequest(language);
      if (request == null || samples.length < minSamples) return null;
      final r = await (await _earsWorker()).call({
        ...request,
        'cmd': 'transcribe',
        'samples': TransferableTypedData.fromList([samples]),
      });
      _touch();
      if (r['error'] != null) throw StateError('${r['error']}');
      return Heard(r['text'] as String? ?? '', r['lang'] as String? ?? '');
    } finally {
      release();
    }
  }

  void dispose() {
    _idle?.cancel();
    releasePack(speaking: true);
    releasePack(speaking: false);
  }
}

/// Silero voice-activity detection on the UI isolate: one 32 ms window
/// costs well under a millisecond, and keeping it here means the end of a
/// sentence is noticed even while Whisper or Kokoro is busy.
class SpeechDetector {
  static var _bound = false;
  final sherpa.VoiceActivityDetector _vad;
  SpeechDetector._(this._vad);

  /// [minSilence]: pause that ends a turn; [minSpeech]: shortest sound
  /// taken as speech (also the barge-in threshold).
  static SpeechDetector create(
    String model, {
    double threshold = 0.5,
    double minSilence = 0.7,
    double minSpeech = 0.25,
    double maxSpeech = 28,
  }) {
    if (!_bound) {
      sherpa.initBindings();
      _bound = true;
    }
    return SpeechDetector._(
      sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: model,
            threshold: threshold,
            minSilenceDuration: minSilence,
            minSpeechDuration: minSpeech,
            maxSpeechDuration: maxSpeech,
          ),
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 40,
      ),
    );
  }

  /// Feeds one window; returns finished utterances (16 kHz samples).
  List<Float32List> accept(Float32List samples) {
    _vad.acceptWaveform(samples);
    final out = <Float32List>[];
    while (!_vad.isEmpty()) {
      out.add(_vad.front().samples);
      _vad.pop();
    }
    return out;
  }

  /// True while speech is going on.
  bool get speaking => _vad.isDetected();

  void reset() => _vad.clear();
  void dispose() => _vad.free();
}

/// The Kotlin side ([VoiceAudio.kt]): microphone frames in, PCM out.
class VoiceAudioChannel {
  static const _channel = MethodChannel('ondevice_llm/voice_audio');
  static const _mic = EventChannel('ondevice_llm/voice_audio/mic');

  /// 512-sample frames at 16 kHz as floats in [-1, 1].
  static Stream<Float32List> frames() => _mic.receiveBroadcastStream().map((e) {
    // Read through ByteData: the channel's bytes can start at an odd
    // offset, where an Int16List view throws.
    final bytes = e as Uint8List;
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.lengthInBytes ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getInt16(2 * i, Endian.little) / 32768.0;
    }
    return out;
  });

  /// False when the microphone permission was refused.
  static Future<bool> startMic() async =>
      await _channel.invokeMethod<bool>('startMic') ?? false;
  static Future<void> stopMic() => _channel.invokeMethod<void>('stopMic');

  /// Completes when heard (true) or cut short by [stopPlayback] (false).
  static Future<bool> play(SpeechAudio audio) async =>
      await _channel.invokeMethod<bool>('play', {
        'pcm': audio.pcm.buffer.asUint8List(
          audio.pcm.offsetInBytes,
          audio.pcm.lengthInBytes,
        ),
        'rate': audio.sampleRate,
      }) ??
      false;
  static Future<void> stopPlayback() =>
      _channel.invokeMethod<void>('stopPlayback');

  /// [call]: the call audio path with the loudspeaker, so the echo canceller
  /// removes the assistant's voice from the microphone, at phone-call
  /// quality. Otherwise playback stays on the full-quality media path.
  static Future<void> conversation(bool on, {bool call = true}) =>
      _channel.invokeMethod<void>('conversation', {'on': on, 'call': call});

  /// Root-mean-square level of a frame, 0…1, for the orb.
  static double level(Float32List frame) {
    if (frame.isEmpty) return 0;
    var sum = 0.0;
    for (final v in frame) {
      sum += v * v;
    }
    return math.sqrt(sum / frame.length).clamp(0.0, 1.0);
  }
}

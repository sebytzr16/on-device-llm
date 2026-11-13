import '../../core/utils/memory_admission.dart';
import '../../data/storage/gguf_metadata.dart';
import '../../data/storage/model_file_leases.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/tools/domain/tool_spec.dart';
import 'text_engine.dart';
import '../../core/l10n/l10n.dart';
import '../../core/platform/child_process_job.dart';

const diffusionGemmaModelId = 'diffusiongemma-26b-a4b-q4km';

/// The load controls the DiffusionGemma host honours: the rest of a model
/// profile is fixed by its own engine, and the load settings UI disables it
/// for this model instead of saving values the host would ignore (E23).
const diffusionGemmaLoadKeys = {
  'contextSize',
  'nGpuLayers',
  'cpuThreads',
  'batchThreads',
  'microBatchSize',
  'seed',
};

/// Whether dg_host honours the load control [key] (audit E23).
bool diffusionGemmaHonoursLoad(String key) =>
    diffusionGemmaLoadKeys.contains(key);

/// Accept arbitrary pipe chunks, UTF-8 characters and escaped multiline content.
Stream<Map<String, dynamic>> diffusionJsonLines(Stream<List<int>> bytes) =>
    bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => Map<String, dynamic>.from(jsonDecode(line) as Map));

/// A separate process isolates the draft llama.cpp ABI and its CUDA DLLs.
class DiffusionGemmaEngine implements TextEngine {
  DiffusionGemmaEngine({
    String? executable,
    this.denoisingSteps = 48,
    this.ubatch = 512,
  }) : executable =
           executable ??
           p.join(
             p.dirname(Platform.resolvedExecutable),
             'diffusiongemma',
             'dg_host.exe',
           );

  final String executable;
  final int denoisingSteps, ubatch;
  Process? _process;
  String? _modelPath;

  /// The launch arguments the running host was started with: a changed load
  /// setting reloads it instead of keeping the old process (audit E23).
  String? _config;
  Completer<void>? _ready;
  StreamController<Map<String, dynamic>>? _turn;
  StreamSubscription<Map<String, dynamic>>? _output;
  StreamSubscription<String>? _errors;
  String _diagnostics = '';
  Timer? _cancelDeadline;
  final _canvas = StreamController<Map<String, dynamic>>.broadcast();

  /// Revisable snapshots for desktop UI. `text` events on generate are committed.
  Stream<Map<String, dynamic>> get canvasChanges => _canvas.stream;

  @override
  Map<String, dynamic> metrics = {
    'backend': 'DiffusionGemma CUDA / CPU experts',
    'supportsVision': false,
    'supportsTools': false,
    'supportsReasoning': false,
    'contextSize': 4096,
  };

  /// The dg_host command line: the load settings it can honour (context, GPU
  /// layers, threads, seed and micro-batch) and the model's own diffusion
  /// flags. Everything else in a profile stays fixed here.
  @visibleForTesting
  List<String> launchArgs(String modelPath, InferenceSettings settings) {
    final batch = settings.microBatchSize > 0
        ? settings.microBatchSize
        : ubatch;
    return [
      '-m',
      modelPath,
      '-ngl',
      '${settings.nGpuLayers}',
      '-ot',
      'exps=CPU',
      '-c',
      '${settings.contextSize}',
      '-b',
      '$batch',
      '-ub',
      '$batch',
      '-t',
      '${settings.effectiveThreads}',
      '-tb',
      '${settings.effectiveBatchThreads}',
      // 0 means a fresh random seed for every answer: the host's default.
      if (settings.seed > 0) ...['-s', '${settings.seed}'],
      '--diffusion-eb',
      'on',
      '--diffusion-eb-max-steps',
      '$denoisingSteps',
      '--diffusion-kv-cache',
      'on',
      '--diffusion-gpu-sampling',
      'on',
      '--diffusion-gpu-sample-reduce',
      'on',
    ];
  }

  Future<void> loadModel(String modelPath, {InferenceSettings? settings}) =>
      MemoryAdmission.shared.run(
        () => _loadAdmitted(modelPath, settings ?? const InferenceSettings()),
      );

  Future<void> _loadAdmitted(
    String modelPath,
    InferenceSettings settings,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('DiffusionGemma requires Windows desktop.');
    }
    final args = launchArgs(modelPath, settings);
    final config = args.join('\n');
    if (_modelPath == modelPath &&
        _config == config &&
        _process != null &&
        _ready?.isCompleted == true) {
      return;
    }
    dispose();
    // The host ships with the installer's NVIDIA GPU component only.
    if (!await File(executable).exists()) {
      throw StateError(appStrings.dgNeedsGpu);
    }
    // Do not map an incomplete download into llama.cpp. Downloads finish
    // by renaming the .part file, so a readable GGUF with no .part beside
    // it is whole; any quantization is accepted (P3-17).
    if (await File('$modelPath.part').exists()) {
      throw StateError(appStrings.dgIncomplete);
    }
    try {
      final meta = await GgufMetadata.inspect(modelPath);
      if (meta.tensorCount == 0) throw const FormatException('no tensors');
    } catch (_) {
      throw StateError(appStrings.dgUnreadable);
    }
    final ready = _ready = Completer<void>();
    _diagnostics = '';
    final lease = ModelFileLeases.instance.acquire([
      modelPath,
    ], owner: 'DiffusionGemma');
    late Process process;
    try {
      process = await Process.start(
        executable,
        args,
        workingDirectory: p.dirname(p.absolute(executable)),
      );
      ChildProcessJob.adopt(process);
    } catch (_) {
      lease.release();
      rethrow;
    }
    unawaited(process.exitCode.whenComplete(lease.release));
    _process = process;
    _modelPath = modelPath;
    _config = config;
    _errors = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((text) {
          _diagnostics += text;
          if (_diagnostics.length > 8192) {
            _diagnostics = _diagnostics.substring(_diagnostics.length - 8192);
          }
        });
    _output = diffusionJsonLines(process.stdout).listen(
      (event) {
        if (event['ready'] == true) {
          metrics = {...metrics, ...event};
          if (!ready.isCompleted) ready.complete();
        } else if (!ready.isCompleted && event['error'] != null) {
          ready.completeError(StateError('${event['error']}'));
        } else {
          _turn?.add(event);
          if (event['done'] == true) {
            _cancelDeadline?.cancel();
            final turn = _turn;
            _turn = null;
            unawaited(turn?.close());
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
        _turn?.addError(error, stack);
        dispose();
      },
    );
    unawaited(
      process.exitCode.then((code) {
        if (_process != process) return;
        final error = StateError(
          'DiffusionGemma host exited ($code). $_diagnostics',
        );
        if (!ready.isCompleted) ready.completeError(error);
        _turn?.addError(error);
        dispose();
      }),
    );
    try {
      await ready.future.timeout(const Duration(minutes: 5));
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    if (_process == null) throw StateError(appStrings.dgLoadFirst);
    if (_turn != null) {
      throw StateError('A DiffusionGemma turn is already running.');
    }
    if (tools.isNotEmpty ||
        messages.any((m) => m.containsKey('images') || m['role'] == 'tool')) {
      throw UnsupportedError(appStrings.dgTextOnly);
    }
    // The host templates the whole history for every request: there is no
    // partial-answer continuation to hand it (audit E23).
    if (assistantPrefix.isNotEmpty) {
      throw UnsupportedError(appStrings.dgNoContinuation);
    }
    final turn = _turn = StreamController<Map<String, dynamic>>();
    String committed = '';
    _process!.stdin.writeln(
      jsonEncode({
        'messages': messages
            .map((m) => {'role': m['role'], 'content': m['content']})
            .toList(),
        'maxTokens': settings.maxTokens,
        'temperature': settings.temperature,
      }),
    );
    try {
      await for (final event in turn.stream) {
        if (event['error'] != null) throw StateError('${event['error']}');
        if (event['event'] == 'progress') {
          metrics = {
            ...metrics,
            'diffusionBlock': event['block'],
            'diffusionStep': event['step'],
          };
          if (!_canvas.isClosed) {
            _canvas.add({...event, 'committed': committed});
          }
        }
        if (event['event'] == 'block' || event['done'] == true) {
          final text = event['text'] as String? ?? '';
          if (!text.startsWith(committed)) {
            // A host older than P3-17 hides everything once a thought
            // channel opens after visible text; keep what was shown.
            if (!committed.startsWith(text)) {
              throw const FormatException('Host revised a committed block.');
            }
          } else {
            if (text.length > committed.length) {
              yield text.substring(committed.length);
            }
            committed = text;
          }
        }
        if (event['done'] == true) {
          metrics = {...metrics, ...?event['stats'] as Map<String, dynamic>?};
        }
      }
    } finally {
      if (_turn == turn) cancel();
      if (!_canvas.isClosed) _canvas.add({'done': true});
    }
  }

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async {
    if (_process == null) throw StateError(appStrings.dgLoadFirst);
    if (_turn != null) {
      throw StateError('A DiffusionGemma request is already running.');
    }
    final turn = _turn = StreamController<Map<String, dynamic>>();
    _process!.stdin.writeln(
      jsonEncode({
        'preview': true,
        'messages': messages
            .map((m) => {'role': m['role'], 'content': m['content']})
            .toList(),
        'maxTokens': settings.maxTokens,
      }),
    );
    try {
      final result = await turn.stream.last.timeout(
        const Duration(seconds: 30),
      );
      if (result['error'] != null) throw StateError('${result['error']}');
      return result;
    } on TimeoutException {
      dispose();
      rethrow;
    }
  }

  @override
  void cancel() {
    // Stop while the 17 GB model is still loading: end the host now rather
    // than leave chat waiting up to the load timeout.
    if (_process != null && _ready?.isCompleted == false) {
      dispose();
      return;
    }
    if (_turn == null) return;
    metrics = {...metrics, 'finishReason': 'cancelled'};
    _process?.stdin.writeln('{"cancel":true}');
    _cancelDeadline?.cancel();
    // A wedged CUDA call must not leave Stop hanging indefinitely.
    _cancelDeadline = Timer(const Duration(seconds: 15), dispose);
  }

  void dispose() {
    _cancelDeadline?.cancel();
    final process = _process;
    _process = null;
    _modelPath = null;
    _config = null;
    process?.kill();
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('DiffusionGemma loading was stopped.'));
    }
    unawaited(_output?.cancel());
    unawaited(_errors?.cancel());
    final turn = _turn;
    _turn = null;
    unawaited(turn?.close());
  }

  /// Ends the engine for good: the host and the canvas stream (P3-17).
  void close() {
    dispose();
    unawaited(_canvas.close());
  }
}

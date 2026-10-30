import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/tools/domain/tool_spec.dart';
import 'text_engine.dart';

const diffusionGemmaModelId = 'diffusiongemma-26b-a4b-q4km';

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

  Future<void> loadModel(String modelPath) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('DiffusionGemma requires Windows desktop.');
    }
    if (_modelPath == modelPath &&
        _process != null &&
        _ready?.isCompleted == true) {
      return;
    }
    dispose();
    // The host ships with the installer's NVIDIA GPU component only.
    if (!await File(executable).exists()) {
      throw StateError(
        'DiffusionGemma needs an NVIDIA GPU and the installer\'s GPU (CUDA) component.',
      );
    }
    // Do not map an incomplete download into llama.cpp.
    if (await File(modelPath).length() != 16806810208) {
      throw StateError(
        'DiffusionGemma download is incomplete (expected 16,806,810,208 bytes).',
      );
    }
    final ready = _ready = Completer<void>();
    _diagnostics = '';
    final process = await Process.start(executable, [
      '-m',
      modelPath,
      '-ngl',
      '999',
      '-ot',
      'exps=CPU',
      '-c',
      '4096',
      '-b',
      '$ubatch',
      '-ub',
      '$ubatch',
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
    ], workingDirectory: p.dirname(p.absolute(executable)));
    _process = process;
    _modelPath = modelPath;
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
    if (_process == null) throw StateError('Load DiffusionGemma first.');
    if (_turn != null) {
      throw StateError('A DiffusionGemma turn is already running.');
    }
    if (tools.isNotEmpty ||
        messages.any((m) => m.containsKey('images') || m['role'] == 'tool')) {
      throw UnsupportedError('DiffusionGemma supports text chat only.');
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
          _canvas.add({...event, 'committed': committed});
        }
        if (event['event'] == 'block' || event['done'] == true) {
          final text = event['text'] as String? ?? '';
          if (!text.startsWith(committed)) {
            throw const FormatException('Host revised a committed block.');
          }
          if (text.length > committed.length) {
            yield text.substring(committed.length);
          }
          committed = text;
        }
        if (event['done'] == true) {
          metrics = {...metrics, ...?event['stats'] as Map<String, dynamic>?};
        }
      }
    } finally {
      if (_turn == turn) cancel();
      _canvas.add({'done': true});
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
    if (_process == null) throw StateError('Load DiffusionGemma first.');
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
}

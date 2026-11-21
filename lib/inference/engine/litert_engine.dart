import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../core/l10n/l10n.dart';
import '../../core/storage/native_media_lease.dart';
import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/tools/domain/tool_spec.dart';
import 'llama_engine.dart' show ThinkingTagNormalizer;
import 'text_engine.dart';

class LiteRtEngine implements TextEngine {
  LiteRtEngine({
    this._methods = const MethodChannel('ondevice_llm/litert'),
    this._tokens = const EventChannel('ondevice_llm/litert/tokens'),
  });

  final MethodChannel _methods;
  final EventChannel _tokens;
  ({String path, LiteRtBackend backend, bool vision})? _loaded;
  _LiteRtRequest? _request;
  int _nextId = 0;
  Map<String, dynamic> _info = const {};

  @override
  Map<String, dynamic> metrics = const {};

  bool get isLoaded => _loaded != null;

  bool holdsLoad(String path, LiteRtBackend backend, {required bool vision}) =>
      _loaded == (path: path, backend: backend, vision: vision);

  Future<void> loadModel(
    String path, {
    required LiteRtBackend backend,
    required bool vision,
  }) async {
    await _stop();
    _loaded = null;
    _info = metrics = const {};
    final info = await _methods.invokeMapMethod<String, dynamic>('load', {
      'path': path,
      'backend': backend.name,
      'vision': vision,
    });
    _loaded = (path: path, backend: backend, vision: vision);
    _info = {
      'contextSize': null,
      'tokensPerSecond': null,
      'firstTokenMs': null,
      'finishReason': null,
      'toolCalls': const [],
      'supportsVision': vision,
      'supportsAudio': false,
      'supportsThinking': true,
      'supportsTools': false,
      ...?info,
    };
    metrics = _info;
  }

  Future<void> unload() async {
    await _stop();
    if (!isLoaded) return;
    try {
      await _methods.invokeMethod<void>('unload');
    } finally {
      _loaded = null;
      _info = metrics = const {};
    }
  }

  void dispose() {
    unawaited(unload().catchError((Object _) {}));
  }

  @override
  void cancel() => unawaited(_stop());

  Future<void> _stop() => _stopRequest(_request);

  /// Stops [request] once: marks it cancelled, closes its events so a pending
  /// `await for` in the generator ends, and waits for the host to hear the
  /// cancel. It only touches [request], so an old stream's cancel never
  /// stops the turn that replaced it.
  Future<void> _stopRequest(_LiteRtRequest? request) async {
    if (request == null) return;
    if (!request.finished) {
      _markStopped(request);
      unawaited(request.events.close());
    }
    await request.stopping;
  }

  /// Marks [request] cancelled and asks the host to stop it, once: the
  /// runtime keeps generating until it hears the cancel.
  void _markStopped(_LiteRtRequest request) {
    if (request.finished) return;
    request.finished = true;
    metrics = {...metrics, 'finishReason': 'cancelled'};
    if (request.started) request.stopping = _cancelNative(request.id);
  }

  Future<void> _cancelNative(int id) async {
    try {
      await _methods.invokeMethod<void>('cancel', {'id': id});
    } on PlatformException {
      // The host can disappear when the activity closes.
    } on MissingPluginException {
      // The host detached before cancellation arrived.
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
  }) {
    // A generator only notices that its consumer detached when it next yields,
    // and a Stop during the prefill yields nothing. Hand the detach to the
    // request here, so the host hears the cancel before the first token and
    // the stream still completes.
    _LiteRtRequest? request;
    StreamSubscription<String>? subscription;
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        subscription =
            _generate(
              messages: messages,
              fallbackTemplate: fallbackTemplate,
              settings: settings,
              assistantPrefix: assistantPrefix,
              tools: tools,
              toolChoice: toolChoice,
              onRequest: (started) => request = started,
            ).listen(
              controller.add,
              onError: (Object error, StackTrace stack) =>
                  controller.addError(error, stack),
              onDone: () => unawaited(controller.close()),
            );
      },
      onCancel: () async {
        await _stopRequest(request);
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<String> _generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    required void Function(_LiteRtRequest request) onRequest,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    if (!isLoaded) {
      throw StateError(stringsFor(settings.localeCode).liteRtNotLoaded);
    }
    if (_request != null) {
      throw StateError(stringsFor(settings.localeCode).liteRtBusy);
    }
    final request = _request = _LiteRtRequest(++_nextId);
    onRequest(request);
    metrics = _info;
    NativeMediaLease? media;
    StreamSubscription<dynamic>? subscription;
    var thinking = false;
    try {
      media = await NativeMediaLease.open(messages);
      if (request.finished) return;
      subscription = _tokens.receiveBroadcastStream().listen(
        (event) {
          if (!request.finished && event is Map && event['id'] == request.id) {
            request.events.add(Map<Object?, Object?>.from(event));
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!request.finished) request.events.addError(error, stack);
        },
      );
      request.started = true;
      await _methods.invokeMethod<void>('generate', {
        'id': request.id,
        'messages': media.messages,
        'temperature': settings.temperature,
        'topK': settings.topK,
        'topP': settings.topP,
        'maxTokens': settings.maxTokens,
        'thinking': settings.thinkingModeEnabled,
        'thinkingBudget': settings.thinkingBudgetTokens,
        'assistantPrefix': assistantPrefix,
        // Constrained decoding: the host holds the reply to JSON when the
        // turn asks for it (a Goal's planner retry), and to the schema when
        // one is set. GBNF is llama.cpp's own and stays off.
        'responseFormat':
            settings.responseFormat == ResponseFormat.json ||
                settings.responseFormat == ResponseFormat.jsonSchema
            ? 'json'
            : 'text',
        'jsonSchema': settings.responseFormat == ResponseFormat.jsonSchema
            ? settings.jsonSchema
            : '',
      });
      await for (final event in request.events.stream) {
        if (request.finished) break;
        final type = event['type'];
        if (type == 'error') {
          request.finished = true;
          metrics = {...metrics, 'finishReason': 'error'};
          throw PlatformException(
            code: 'litert_generate',
            message: event['message'] as String?,
          );
        }
        if (type == 'done') {
          request.finished = true;
          final stats = event['metrics'];
          if (stats is Map && stats['contextSize'] is int) {
            _info = {..._info, 'contextSize': stats['contextSize']};
          }
          metrics = {
            ..._info,
            if (stats is Map) ...Map<String, dynamic>.from(stats),
            'finishReason': event['finishReason'] ?? 'eog',
            'toolCalls': const [],
          };
          break;
        }
        final value = event['text'];
        if (value is! String || value.isEmpty) continue;
        if (type == 'thought') {
          if (!thinking) yield ThinkingTagNormalizer.openTag;
          thinking = true;
        } else if (type == 'text') {
          if (thinking) yield ThinkingTagNormalizer.closeTag;
          thinking = false;
        } else {
          continue;
        }
        yield value;
      }
      if (thinking) yield ThinkingTagNormalizer.closeTag;
    } catch (_) {
      await _stop();
      metrics = {...metrics, 'finishReason': 'error'};
      rethrow;
    } finally {
      try {
        await _stop();
        await subscription?.cancel();
        unawaited(request.events.close());
        await media?.dispose();
      } finally {
        _request = null;
      }
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
    final prompt = [
      for (final message in messages) _previewLine(message),
      if (assistantPrefix.isNotEmpty) 'assistant: $assistantPrefix',
    ].join('\n\n');
    final promptTokens = (prompt.runes.length + 3) ~/ 4;
    final contextSize = _info['contextSize'] as int?;
    final reserved = _reservedTokens(settings, contextSize);
    final available = contextSize == null ? null : contextSize - reserved;
    return {
      'prompt': prompt,
      'promptTokens': promptTokens,
      'contextSize': contextSize,
      'reservedTokens': reserved,
      'availableTokens': available,
      // The host reports the model's context when it loads; until then the
      // fit cannot be judged, and must not claim the prompt fits.
      'fits': available == null ? null : promptTokens <= available,
    };
  }

  /// The output allowance the host holds back for this turn: the answer plus
  /// the reasoning it reserves (`LiteRtLm.generate` resolves the app's
  /// unlimited reasoning, zero, against the window it knows).
  int _reservedTokens(InferenceSettings settings, int? contextSize) {
    if (!settings.thinkingModeEnabled) return settings.maxTokens;
    final budget = settings.thinkingBudgetTokens;
    final thinking = budget > 0
        ? budget
        : contextSize == null
        ? settings.maxTokens
        : max(1, (contextSize - settings.maxTokens) ~/ 2);
    return settings.maxTokens + thinking;
  }

  String _previewLine(Map<String, Object> message) {
    final text = (message['content'] as String? ?? '').replaceAll(
      TextEngine.mediaMarker,
      '[image]',
    );
    return '${message['role']}: $text';
  }
}

class _LiteRtRequest {
  _LiteRtRequest(this.id);

  final int id;

  /// The request's events, fed from the token channel and closed when the
  /// request is stopped or finishes.
  late final events = StreamController<Map<Object?, Object?>>();
  bool started = false;
  bool finished = false;
  Future<void>? stopping;
}

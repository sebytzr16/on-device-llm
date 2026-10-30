import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../ffi/sd_bindings.dart';

/// Frames from a generation: one for a picture, several for a video, each
/// packed RGBA of [width] × [height].
class SdResult {
  final Uint8List rgba;
  final int width, height, frames, fps;
  const SdResult(
    this.rgba,
    this.width,
    this.height, {
    this.frames = 1,
    this.fps = 0,
  });

  int get frameBytes => width * height * 4;
  Uint8List frame(int i) =>
      Uint8List.sublistView(rgba, i * frameBytes, (i + 1) * frameBytes);

  /// The middle [w]×[h] of the first frame (no larger than this picture).
  SdResult cropCentre(int w, int h) {
    if (w >= width && h >= height) return this;
    w = w.clamp(1, width);
    h = h.clamp(1, height);
    final x0 = (width - w) ~/ 2, y0 = (height - h) ~/ 2;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final from = ((y0 + y) * width + x0) * 4;
      out.setRange(y * w * 4, (y + 1) * w * 4, rgba, from);
    }
    return SdResult(out, w, h);
  }
}

/// Image and video generation with ondevice_sd.dll. Loading and generating
/// take minutes, so they run on a worker isolate; progress arrives through a
/// listener callback owned by this isolate, and [cancel] sets the bridge's
/// atomic flag from here while the worker is busy.
class SdEngine {
  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _replies;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  int _ctx = 0;
  String? _loadedKey;
  SdBindings? _cancelBindings;

  bool get isLoaded => _loadedKey != null;
  String? get loadedKey => _loadedKey;

  Future<void> _start() async {
    if (_worker != null) return;
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      // A String is the worker failing to open the DLL; null is its exit
      // (onExit), e.g. a crash. Either way nothing pending will be answered.
      if (message == null || message is String) {
        final reason = message as String? ?? 'The image engine stopped';
        if (!ready.isCompleted) ready.completeError(StateError(reason));
        if (identical(_replies, replies)) _stopped(reason);
        return;
      }
      final [id as int, ok as bool, payload] = message as List<Object?>;
      final c = _pending.remove(id);
      if (c == null) return;
      ok ? c.complete(payload) : c.completeError(StateError(payload as String));
    });
    _replies = replies;
    _isolate = await Isolate.spawn(
      _main,
      replies.sendPort,
      onExit: replies.sendPort,
    );
    _worker = await ready.future;
  }

  /// The worker is gone: fail every waiting call so the next one starts a
  /// fresh worker instead of waiting forever.
  void _stopped(String reason) {
    _replies?.close();
    _replies = null;
    _isolate = null;
    _worker = null;
    _ctx = 0;
    _loadedKey = null;
    final error = StateError(reason);
    for (final c in _pending.values) {
      c.completeError(error);
    }
    _pending.clear();
  }

  Future<Object?> _call(String op, List<Object?> args) async {
    await _start();
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _worker!.send([id, op, ...args]);
    return c.future;
  }

  /// Loads a model. [key] names what is loaded, so loading the same model
  /// again is a no-op.
  Future<void> load({
    required String key,
    String modelPath = '',
    String vaePath = '',
    Map<String, Object> settings = const {},
  }) async {
    if (_loadedKey == key) return;
    _loadedKey = null;
    _ctx =
        await _call('load', [modelPath, vaePath, jsonEncode(settings)]) as int;
    _loadedKey = key;
  }

  /// A picture, or a video when [video] is true. [request] is the bridge's
  /// JSON request (prompt, width, height, steps, cfgScale, seed, frames…).
  /// [init] is an optional RGBA starting picture for a video.
  Future<SdResult> generate(
    Map<String, Object> request, {
    bool video = false,
    SdResult? init,
    void Function(int step, int total)? onProgress,
  }) async {
    if (!isLoaded) throw StateError('No model loaded');
    final progress = onProgress == null
        ? null
        : NativeCallable<SdProgressFn>.listener(
            (int step, int total, Pointer<Void> _) => onProgress(step, total),
          );
    try {
      final reply =
          await _call(video ? 'video' : 'image', [
                jsonEncode(request),
                progress?.nativeFunction.address ?? 0,
                init == null
                    ? null
                    : TransferableTypedData.fromList([init.rgba]),
                init?.width ?? 0,
                init?.height ?? 0,
              ])
              as List<Object?>;
      final [
        data as TransferableTypedData,
        w as int,
        h as int,
        n as int,
        fps as int,
      ] = reply;
      return SdResult(
        data.materialize().asUint8List(),
        w,
        h,
        frames: n,
        fps: fps,
      );
    } finally {
      progress?.close();
    }
  }

  /// Writes a video's frames to an MJPG .avi at [path].
  Future<void> saveVideo(String path, SdResult video) async {
    await _call('save', [
      path,
      TransferableTypedData.fromList([video.rgba]),
      video.width,
      video.height,
      video.frames,
      video.fps,
    ]);
  }

  /// Enlarges a picture with the ESRGAN model at [modelPath] (Full HD to
  /// 4K with [factor] 2). Needs no diffusion model loaded.
  Future<SdResult> upscale(
    String modelPath,
    SdResult picture, {
    int factor = 2,
  }) async {
    final [data as TransferableTypedData, w as int, h as int] =
        await _call('upscale', [
              modelPath,
              TransferableTypedData.fromList([picture.frame(0)]),
              picture.width,
              picture.height,
              factor,
            ])
            as List<Object?>;
    return SdResult(data.materialize().asUint8List(), w, h);
  }

  /// Stops the running generation; it then fails with "Generation cancelled".
  void cancel() {
    if (_ctx == 0) return;
    (_cancelBindings ??= SdBindings()).cancel(Pointer<Void>.fromAddress(_ctx));
  }

  /// Frees the model and stops the worker. Call [cancel] first if busy.
  Future<void> dispose() async {
    if (_worker != null) {
      try {
        await _call('destroy', const []);
      } catch (_) {}
    }
    _isolate?.kill();
    _replies?.close();
    for (final c in _pending.values) {
      c.completeError(StateError('Image engine closed'));
    }
    _pending.clear();
    _isolate = null;
    _worker = null;
    _ctx = 0;
    _loadedKey = null;
  }
}

// ---------------------------------------------------------------------------
// Worker isolate
// ---------------------------------------------------------------------------

void _main(SendPort replies) {
  // Opened before reporting ready: an old or incomplete DLL (wrong bridge
  // version, missing CUDA runtime) must fail the call, not hang it.
  final SdBindings b;
  try {
    b = SdBindings();
  } catch (e) {
    replies.send('Could not open the image engine: $e');
    return;
  }
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  var ctx = nullptr.cast<Void>();

  String lastError(String fallback) {
    final msg = ctx == nullptr ? '' : b.error(ctx).toDartString();
    return msg.isEmpty ? fallback : msg;
  }

  requests.listen((message) {
    final m = message as List<Object?>;
    final id = m[0] as int;
    try {
      replies.send([
        id,
        true,
        _run(b, () => ctx, (c) => ctx = c, m, lastError),
      ]);
    } catch (e) {
      replies.send([id, false, e is StateError ? e.message : '$e']);
    }
    if (m[1] == 'destroy') requests.close();
  });
}

Object? _run(
  SdBindings b,
  Pointer<Void> Function() ctx,
  void Function(Pointer<Void>) setCtx,
  List<Object?> m,
  String Function(String) lastError,
) {
  void ensureCtx() {
    if (ctx() != nullptr) return;
    final opts = '{}'.toNativeUtf8();
    setCtx(b.create(opts));
    malloc.free(opts);
    if (ctx() == nullptr) {
      throw StateError('Could not create the image engine');
    }
  }

  switch (m[1]) {
    case 'load':
      ensureCtx();
      return using((arena) {
        final ok = b.load(
          ctx(),
          (m[2] as String).toNativeUtf8(allocator: arena),
          (m[3] as String).toNativeUtf8(allocator: arena),
          ''.toNativeUtf8(allocator: arena),
          (m[4] as String).toNativeUtf8(allocator: arena),
        );
        if (ok == 0) throw StateError(lastError('Could not load the model'));
        return ctx().address;
      });
    case 'image' || 'video':
      final video = m[1] == 'video';
      return using((arena) {
        final request = (m[2] as String).toNativeUtf8(allocator: arena);
        final cb = Pointer<NativeFunction<SdProgressFn>>.fromAddress(
          m[3] as int,
        );
        final out = arena<Int32>(4);
        Pointer<Uint8> init = nullptr;
        if (m[4] case final TransferableTypedData data) {
          final bytes = data.materialize().asUint8List();
          init = arena<Uint8>(bytes.length);
          init.asTypedList(bytes.length).setAll(0, bytes);
        }
        final pixels = video
            ? b.txt2vid(
                ctx(),
                request,
                init,
                m[5] as int,
                m[6] as int,
                cb,
                nullptr,
                out,
                out + 1,
                out + 2,
                out + 3,
              )
            : b.txt2img(ctx(), request, cb, nullptr, out, out + 1);
        if (pixels == nullptr) {
          throw StateError(lastError('Generation failed'));
        }
        try {
          final frames = video ? out[2] : 1;
          final bytes = out[0] * out[1] * 4 * frames;
          return [
            TransferableTypedData.fromList([pixels.asTypedList(bytes)]),
            out[0],
            out[1],
            frames,
            video ? out[3] : 0,
          ];
        } finally {
          b.freeImage(pixels);
        }
      });
    case 'save':
      return using((arena) {
        final bytes = (m[3] as TransferableTypedData)
            .materialize()
            .asUint8List();
        final rgba = arena<Uint8>(bytes.length);
        rgba.asTypedList(bytes.length).setAll(0, bytes);
        final ok = b.saveVideo(
          (m[2] as String).toNativeUtf8(allocator: arena),
          rgba,
          m[4] as int,
          m[5] as int,
          m[6] as int,
          m[7] as int,
        );
        if (ok == 0) throw StateError('Could not save the video');
        return null;
      });
    case 'upscale':
      ensureCtx();
      return using((arena) {
        final bytes = (m[3] as TransferableTypedData)
            .materialize()
            .asUint8List();
        final rgba = arena<Uint8>(bytes.length);
        rgba.asTypedList(bytes.length).setAll(0, bytes);
        final out = arena<Int32>(2);
        final pixels = b.upscale(
          ctx(),
          (m[2] as String).toNativeUtf8(allocator: arena),
          rgba,
          m[4] as int,
          m[5] as int,
          m[6] as int,
          out,
          out + 1,
        );
        if (pixels == nullptr) {
          throw StateError(lastError('Could not upscale the picture'));
        }
        try {
          return [
            TransferableTypedData.fromList([
              pixels.asTypedList(out[0] * out[1] * 4),
            ]),
            out[0],
            out[1],
          ];
        } finally {
          b.freeImage(pixels);
        }
      });
    case 'destroy':
      if (ctx() != nullptr) b.destroy(ctx());
      setCtx(nullptr);
      return null;
  }
  throw StateError('Unknown image engine call ${m[1]}');
}

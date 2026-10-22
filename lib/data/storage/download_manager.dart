import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/errors/exceptions.dart';
import '../../core/platform/device_info.dart';
import 'model_storage.dart';
import 'system_downloads.dart';

enum DownloadStatus {
  idle,
  queued,
  downloading,
  paused,
  verifying,
  completed,
  failed,
}

class DownloadProgress {
  final String modelId;
  final DownloadStatus status;
  final int received, total;
  final double? bytesPerSecond;
  final String? error;
  const DownloadProgress({
    required this.modelId,
    required this.status,
    this.received = 0,
    this.total = 0,
    this.bytesPerSecond,
    this.error,
  });
  double get fraction => total > 0 ? (received / total).clamp(0, 1) : 0;
}

class DownloadManager {
  final Dio _dio;
  final Future<File> Function(String) _resolve;
  final Map<String, CancelToken> _tokens = {};
  final Map<String, Completer<void>> _finished = {};
  final Map<String, StreamController<DownloadProgress>> _controllers = {};
  bool _disposed = false;
  final Set<String> _active = {};
  final List<({String id, CancelToken token, Completer<bool> ready})> _queue =
      [];
  final Map<String, int> _remaining = {};
  final Future<DeviceStorage?> Function() _storage;
  final SystemDownloads? _system;
  final Duration pollInterval;
  DownloadManager({
    Dio? dio,
    Future<File> Function(String)? resolve,
    Future<DeviceStorage?> Function()? storage,
    SystemDownloads? system,
    this.pollInterval = const Duration(milliseconds: 700),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _resolve = resolve ?? ModelStorage.modelFile,
       _storage = storage ?? DeviceStorage.read,
       _system = system ?? (resolve == null ? SystemDownloads.platform : null);

  Future<bool> _admit(String id, CancelToken token) {
    if (_active.length < 2) {
      _active.add(id);
      return Future.value(true);
    }
    final ready = Completer<bool>();
    _queue.add((id: id, token: token, ready: ready));
    _emit(DownloadProgress(modelId: id, status: DownloadStatus.queued));
    return ready.future;
  }

  void _release(String id) {
    _active.remove(id);
    _remaining.remove(id);
    while (!_disposed && _active.length < 2 && _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (next.token.isCancelled) {
        next.ready.complete(false);
        continue;
      }
      _active.add(next.id);
      next.ready.complete(true);
    }
  }

  Future<Response<ResponseBody>> _fetch(
    String url,
    CancelToken token,
    int existing,
  ) async {
    for (var attempt = 0; ; attempt++) {
      if (token.isCancelled) throw token.cancelError!;
      try {
        return await _dio.get<ResponseBody>(
          url,
          cancelToken: token,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Accept-Encoding': 'identity',
              if (existing > 0) 'Range': 'bytes=$existing-',
            },
            validateStatus: (s) => s == 200 || s == 206,
          ),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        final transient =
            const {408, 429, 500, 502, 503, 504}.contains(status) ||
            const {
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError,
            }.contains(e.type);
        if (!transient || attempt >= 2 || token.isCancelled) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }

  Stream<DownloadProgress> progressStream(String id) =>
      (_controllers[id] ??= StreamController<DownloadProgress>.broadcast(
        sync: true,
      )).stream;
  void _emit(DownloadProgress p) {
    if (!_disposed) _controllers[p.modelId]?.add(p);
  }

  Future<void> download({
    required String modelId,
    required String url,
    required String fileName,
    required String expectedSha256,
    required int expectedSize,
  }) async {
    if (_disposed) throw StateError('Downloader is closed');
    if (_tokens.containsKey(modelId)) return;
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256) ||
        expectedSize <= 8) {
      throw const DownloadException(
        'Verified checksum and file size are required.',
      );
    }
    final token = CancelToken();
    _tokens[modelId] = token;
    final finished = Completer<void>();
    _finished[modelId] = finished;
    var received = 0;
    try {
      if (!await _admit(modelId, token) || token.isCancelled) {
        throw token.cancelError!;
      }
      final file = await _resolve(fileName);
      final part = File('${file.path}.part');
      var existing = await part.exists() ? await part.length() : 0;
      if (existing > expectedSize) {
        await part.delete();
        existing = 0;
      }
      received = existing;
      // OS staging bytes already occupy disk after a restart. Reserve only
      // the remainder rather than requiring room for a second full copy.
      if (existing == 0 && _system != null) {
        final prior = await _system.query(modelId);
        if (prior.status != 'failed') received = prior.received;
      }
      final requiredBytes = (expectedSize - received).clamp(0, expectedSize);
      final capacity = await _storage();
      final reserved = _remaining.values.fold(0, (a, b) => a + b);
      if (requiredBytes > 0 &&
          capacity != null &&
          capacity.availableBytes <
              requiredBytes + reserved + 128 * 1024 * 1024) {
        throw const DownloadException(
          'Not enough free storage for this download and the active queue.',
        );
      }
      _remaining[modelId] = requiredBytes;
      if (existing == 0 && _system != null) {
        await _system.enqueue(
          id: modelId,
          url: url,
          fileName: fileName,
          sha256: expectedSha256,
          size: expectedSize,
        );
        // Enqueue can complete after Pause: remove the newly created job too.
        if (token.isCancelled && !_disposed) await _system.cancel(modelId);
        var previous = 0;
        final clock = Stopwatch()..start();
        while (true) {
          if (token.isCancelled) throw token.cancelError!;
          final progress = await _system.query(modelId);
          received = progress.received;
          _remaining[modelId] = (expectedSize - received).clamp(
            0,
            expectedSize,
          );
          if (received > expectedSize) {
            await _system.cancel(modelId);
            throw const DownloadException(
              'Download exceeds its verified size.',
            );
          }
          if (progress.status == 'failed') {
            throw DownloadException(
              progress.error ?? 'System download failed.',
            );
          }
          if (progress.status == 'complete') {
            if (token.isCancelled) throw token.cancelError!;
            await _system.stage(modelId);
            break;
          }
          _emit(
            DownloadProgress(
              modelId: modelId,
              status: progress.status == 'waiting'
                  ? DownloadStatus.queued
                  : DownloadStatus.downloading,
              received: received,
              total: expectedSize,
              bytesPerSecond: clock.elapsedMilliseconds > 0
                  ? (received - previous).clamp(0, expectedSize) *
                        1000 /
                        clock.elapsedMilliseconds
                  : null,
            ),
          );
          previous = received;
          clock.reset();
          await Future<void>.delayed(pollInterval);
        }
      } else if (existing < expectedSize) {
        _emit(
          DownloadProgress(
            modelId: modelId,
            status: DownloadStatus.downloading,
            received: received,
            total: expectedSize,
          ),
        );
        final response = await _fetch(url, token, existing);
        if (response.statusCode == 206) {
          final range = response.headers.value('content-range') ?? '';
          final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
          if (match == null ||
              int.parse(match[1]!) != existing ||
              int.parse(match[3]!) != expectedSize ||
              int.parse(match[2]!) != expectedSize - 1) {
            await response.data!.stream.listen(null).cancel();
            throw const DownloadException(
              'Server returned an invalid resume range.',
            );
          }
        } else {
          existing = 0;
          received = 0;
        }
        final sink = part.openWrite(
          mode: existing > 0 ? FileMode.append : FileMode.write,
        );
        final watch = Stopwatch()..start();
        var lastBytes = received;
        try {
          await for (final chunk in response.data!.stream) {
            if (token.isCancelled) throw token.cancelError!;
            received += chunk.length;
            _remaining[modelId] = (expectedSize - received).clamp(
              0,
              expectedSize,
            );
            if (received > expectedSize) {
              throw const DownloadException(
                'Download is larger than its verified size.',
              );
            }
            sink.add(chunk);
            if (watch.elapsedMilliseconds >= 300) {
              await sink.flush();
              _emit(
                DownloadProgress(
                  modelId: modelId,
                  status: DownloadStatus.downloading,
                  received: received,
                  total: expectedSize,
                  bytesPerSecond:
                      (received - lastBytes) * 1000 / watch.elapsedMilliseconds,
                ),
              );
              lastBytes = received;
              watch.reset();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
      if (token.isCancelled) throw token.cancelError!;
      if (await part.length() != expectedSize) {
        throw const DownloadException(
          'Incomplete download. Tap Resume to continue.',
        );
      }
      _emit(
        DownloadProgress(
          modelId: modelId,
          status: DownloadStatus.verifying,
          received: expectedSize,
          total: expectedSize,
        ),
      );
      String actual;
      try {
        actual = await ModelStorage.validateAndHash(part.path);
      } on FormatException {
        await part.delete();
        rethrow;
      }
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        await part.delete();
        throw const ChecksumMismatchException(
          'SHA-256 mismatch. Partial file removed; retry the download.',
        );
      }
      if (token.isCancelled) throw token.cancelError!;
      if (await file.exists()) {
        throw const DownloadException(
          'A model already exists at this path. Remove it before replacing.',
        );
      }
      await ModelStorage.excludeFromICloud(part);
      await part.rename(file.path);
      _emit(
        DownloadProgress(
          modelId: modelId,
          status: DownloadStatus.completed,
          received: expectedSize,
          total: expectedSize,
        ),
      );
    } catch (e) {
      final paused = e is DioException && CancelToken.isCancel(e);
      _emit(
        DownloadProgress(
          modelId: modelId,
          status: paused ? DownloadStatus.paused : DownloadStatus.failed,
          received: received,
          total: expectedSize,
          error: paused ? null : '$e',
        ),
      );
      rethrow;
    } finally {
      _tokens.remove(modelId);
      _release(modelId);
      _finished.remove(modelId);
      finished.complete();
    }
  }

  Future<void> pause(String id) async {
    final finished = _finished[id];
    _tokens[id]?.cancel('Paused');
    final at = _queue.indexWhere((entry) => entry.id == id);
    if (at >= 0) _queue.removeAt(at).ready.complete(false);
    await _system?.cancel(id);
    await finished?.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final t in _tokens.values) {
      t.cancel();
    }
    for (final entry in _queue) {
      entry.ready.complete(false);
    }
    _queue.clear();
    _dio.close(force: true);
    for (final c in _controllers.values) {
      // A synchronous progress listener can dispose its owner. Closing while
      // add() is dispatching would throw; finish that dispatch before closing.
      unawaited(Future<void>.microtask(c.close));
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import '../../core/errors/exceptions.dart';
import '../../core/platform/device_info.dart';
import '../../features/models/domain/entities/model_info.dart';
import 'download_history.dart';
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

final _log = Logger('downloads');

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

/// Internal holder for an in-flight download to a specific destination.
/// Allows callers for the same file to join the same transfer.
class _DestinationDownload {
  final int expectedSize;
  final String expectedSha256;
  final Completer<void> completer;
  _DestinationDownload(this.expectedSize, this.expectedSha256)
    : completer = Completer<void>() {
    // Owners can fail without joiners. Observe the error here while preserving
    // it on the future for callers that do join.
    completer.future.ignore();
  }
  Future<void> get future => completer.future;
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
  final Map<String, List<String>> _systemIds = {};

  /// Maps canonical destination path to the in-flight download holder.
  /// Allows multiple callers for the same file to join the same transfer.
  final Map<String, _DestinationDownload> _destinationFutures = {};
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
       _storage = storage ?? ModelStorage.availableStorage,
       _system = system ?? (resolve == null ? SystemDownloads.platform : null);

  Future<bool> _admit(String id, CancelToken token) {
    if (_active.length < 2) {
      _active.add(id);
      return Future.value(true);
    }
    final ready = Completer<bool>();
    _queue.add((id: id, token: token, ready: ready));
    _emit(DownloadProgress(modelId: id, status: DownloadStatus.queued));
    // Pause/dispose may have happened while destination paths were resolving,
    // before there was a queue entry for them to wake.
    if ((token.isCancelled || _disposed) && !ready.isCompleted) {
      _queue.removeWhere((entry) => identical(entry.ready, ready));
      ready.complete(false);
    }
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
    await downloadFiles(
      modelId: modelId,
      files: [
        ModelDownloadPart(
          fileName: fileName,
          downloadUrl: url,
          sha256: expectedSha256,
          sizeBytes: expectedSize,
        ),
      ],
    );
  }

  Future<void> downloadFiles({
    required String modelId,
    required List<ModelDownloadPart> files,
  }) async {
    if (_disposed) throw StateError('Downloader is closed');
    if (_tokens.containsKey(modelId)) return;
    if (files.isEmpty ||
        files.any(
          (f) =>
              !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(f.sha256) ||
              f.sizeBytes <= 8,
        ) ||
        files.map((f) => f.fileName).toSet().length != files.length) {
      throw const DownloadException(
        'Verified checksum and file size are required.',
      );
    }
    final token = CancelToken();
    _tokens[modelId] = token;
    _systemIds[modelId] = [
      for (var i = 0; i < files.length; i++)
        _systemId(modelId, i, files.length),
    ];
    final finished = Completer<void>();
    _finished[modelId] = finished;
    final total = files.fold(0, (sum, f) => sum + f.sizeBytes);
    var received = 0;
    final started = DateTime.now();
    final attempt = '$modelId:${started.microsecondsSinceEpoch}';
    var result = 'interrupted';
    // The history is a record, never a gate: a slow or failing store must
    // not hold up or fail the transfer.
    void history() => unawaited(
      DownloadHistory.put(
        DownloadRecord(
          attempt: attempt,
          modelId: modelId,
          name: files.first.fileName,
          result: result,
          size: total,
          date: started,
        ),
      ).catchError((_) {}),
    );

    final destinations = <File>[];
    final destKeys = <String>[];
    final destinationDownloads = <_DestinationDownload>[];
    Object? failure;
    StackTrace? failureStack;
    try {
      final first = await _resolve(files.first.fileName);
      for (var i = 0; i < files.length; i++) {
        final file = files.length == 1
            ? first
            : File(p.join(first.parent.path, files[i].fileName));
        destinations.add(file);
        destKeys.add(p.canonicalize(file.absolute.path));
      }

      // Claim a whole batch atomically, before admission. Overlapping batches
      // wait without holding a slot or a subset of locks (which could deadlock).
      // After joining, verify every file, including this batch's unique parts.
      while (true) {
        final joined = <Future<void>>[];
        for (var i = 0; i < files.length; i++) {
          final existing = _destinationFutures[destKeys[i]];
          if (existing == null) continue;
          final f = files[i];
          if (existing.expectedSize != f.sizeBytes ||
              existing.expectedSha256.toLowerCase() != f.sha256.toLowerCase()) {
            throw DownloadException(
              'Conflicting download for "${destKeys[i]}": another transfer '
              'expects different size or SHA-256.',
            );
          }
          joined.add(existing.future);
        }
        if (joined.isEmpty) break;
        await Future.any<void>([
          Future.wait(joined).then((_) {}),
          token.whenCancel.then((error) => throw error),
        ]);
        if (token.isCancelled) throw token.cancelError!;
      }
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final holder = _DestinationDownload(f.sizeBytes, f.sha256);
        _destinationFutures[destKeys[i]] = holder;
        destinationDownloads.add(holder);
      }
      history();
      _log.info(
        'Download $modelId: ${files.length} file(s), '
        '${(total / 1048576).round()} MB',
      );
      if (!await _admit(modelId, token) || token.isCancelled) {
        throw token.cancelError!;
      }
      final complete = <bool>[];
      final missing = <int>[];
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final file = destinations[i];
        final exists = await file.exists();
        if (exists) {
          // Hashing a finished multi-GB file takes minutes: say so.
          _emit(
            DownloadProgress(
              modelId: modelId,
              status: DownloadStatus.verifying,
              received: total,
              total: total,
            ),
          );
        }
        if (exists &&
            (await file.length() != f.sizeBytes ||
                (await ModelStorage.validateAndHash(file.path)).toLowerCase() !=
                    f.sha256.toLowerCase())) {
          throw const DownloadException(
            'An unverified model already exists at this path. Remove it before replacing.',
          );
        }
        if (exists) await dropStalePart(file);
        complete.add(exists);
        var staged = 0;
        if (!exists) {
          final part = File('${file.path}.part');
          if (await part.exists()) staged = await part.length();
          if (staged > f.sizeBytes) staged = 0;
          if (staged == 0 && _system != null) {
            final prior = await _system.query(
              _systemId(modelId, i, files.length),
            );
            if (prior.status != 'failed') {
              staged = prior.received.clamp(0, f.sizeBytes);
            }
          }
        }
        missing.add(exists ? 0 : f.sizeBytes - staged);
      }
      final requiredBytes = missing.fold(0, (sum, n) => sum + n);
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
      for (var i = 0; i < files.length; i++) {
        if (token.isCancelled) throw token.cancelError!;
        final f = files[i];
        if (!complete[i]) {
          final base = received;
          final systemId = _systemId(modelId, i, files.length);
          await _downloadPart(
            modelId: modelId,
            systemId: systemId,
            token: token,
            url: f.downloadUrl,
            fileName: f.fileName,
            file: destinations[i],
            expectedSha256: f.sha256,
            expectedSize: f.sizeBytes,
            remainingAfter: missing.skip(i + 1).fold(0, (sum, n) => sum + n),
            emit: (p) {
              received = base + p.received;
              _emit(
                DownloadProgress(
                  modelId: modelId,
                  status: p.status,
                  received: received,
                  total: total,
                  bytesPerSecond: p.bytesPerSecond,
                ),
              );
            },
          );
        }
        // Streaming emits at intervals; verification accounts for the full part.
        received = files.take(i + 1).fold(0, (sum, f) => sum + f.sizeBytes);
      }
      if (token.isCancelled) throw token.cancelError!;
      result = 'completed';
      _log.info(
        'Download $modelId finished in '
        '${DateTime.now().difference(started).inSeconds} s',
      );
      _emit(
        DownloadProgress(
          modelId: modelId,
          status: DownloadStatus.completed,
          received: total,
          total: total,
        ),
      );
    } catch (e, stack) {
      failure = e;
      failureStack = stack;
      final paused = e is DioException && CancelToken.isCancel(e);
      result = paused ? 'paused' : 'failed';
      paused
          ? _log.info('Download $modelId paused')
          : _log.warning('Download $modelId failed: $e');
      _emit(
        DownloadProgress(
          modelId: modelId,
          status: paused ? DownloadStatus.paused : DownloadStatus.failed,
          received: received,
          total: total,
          error: paused ? null : '$e',
        ),
      );
      rethrow;
    } finally {
      for (var i = 0; i < destinationDownloads.length; i++) {
        final holder = destinationDownloads[i];
        _destinationFutures.remove(destKeys[i]);
        if (failure == null) {
          holder.completer.complete();
        } else {
          holder.completer.completeError(failure, failureStack);
        }
      }
      history();
      _tokens.remove(modelId);
      _systemIds.remove(modelId);
      _release(modelId);
      _finished.remove(modelId);
      finished.complete();
    }
  }

  /// A verified [file] makes any `.part` beside it dead weight (an earlier
  /// attempt left it, often gigabytes). Best effort: a locked part stays.
  static Future<void> dropStalePart(File file) async {
    final part = File('${file.path}.part');
    try {
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      // Another writer still holds it; the next verified run removes it.
    }
  }

  static String _systemId(String id, int index, int count) =>
      count == 1 ? id : '$id:part:${index + 1}';

  Future<void> _downloadPart({
    required String modelId,
    required String systemId,
    required CancelToken token,
    required String url,
    required String fileName,
    required File file,
    required String expectedSha256,
    required int expectedSize,
    required int remainingAfter,
    required void Function(DownloadProgress) emit,
  }) async {
    var received = 0;
    final part = File('${file.path}.part');
    var existing = await part.exists() ? await part.length() : 0;
    if (existing > expectedSize) {
      await part.delete();
      existing = 0;
    }
    received = existing;
    if (existing > 0 && _system != null) {
      // A pause may have preserved its prefix just before the process died.
      // Remove the redundant OS writer before resuming the independent part.
      await _system.cancel(systemId);
    }
    // OS staging bytes already occupy disk after a restart. Reserve only
    // the remainder rather than requiring room for a second full copy.
    if (existing == 0 && _system != null) {
      final prior = await _system.query(systemId);
      if (prior.status != 'failed') received = prior.received;
    }
    if (existing == 0 && _system != null) {
      await _system.enqueue(
        id: systemId,
        url: url,
        fileName: fileName,
        sha256: expectedSha256,
        size: expectedSize,
      );
      // Enqueue can complete after Pause: remove the newly created job too.
      if (token.isCancelled && !_disposed) await _system.pause(systemId);
      var previous = 0;
      final clock = Stopwatch()..start();
      while (true) {
        if (token.isCancelled) throw token.cancelError!;
        final progress = await _system.query(systemId);
        received = progress.received;
        _remaining[modelId] =
            remainingAfter + (expectedSize - received).clamp(0, expectedSize);
        if (received > expectedSize) {
          await _system.cancel(systemId);
          throw const DownloadException('Download exceeds its verified size.');
        }
        if (progress.status == 'failed') {
          throw DownloadException(progress.error ?? 'System download failed.');
        }
        if (progress.status == 'complete') {
          if (token.isCancelled) throw token.cancelError!;
          await _system.stage(systemId);
          break;
        }
        emit(
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
      emit(
        DownloadProgress(
          modelId: modelId,
          status: DownloadStatus.downloading,
          received: received,
          total: expectedSize,
        ),
      );
      Response<ResponseBody> response;
      try {
        response = await _fetch(url, token, existing);
      } on DioException catch (e) {
        // 416: the partial file is not a prefix the server can continue
        // (a re-uploaded asset). Start over rather than fail every retry.
        if (existing == 0 || e.response?.statusCode != 416) rethrow;
        await part.delete();
        existing = 0;
        received = 0;
        response = await _fetch(url, token, existing);
      }
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
          _remaining[modelId] =
              remainingAfter + (expectedSize - received).clamp(0, expectedSize);
          if (received > expectedSize) {
            throw const DownloadException(
              'Download is larger than its verified size.',
            );
          }
          sink.add(chunk);
          if (watch.elapsedMilliseconds >= 300) {
            await sink.flush();
            emit(
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
    emit(
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
  }

  Future<void> pause(String id) async {
    final finished = _finished[id];
    _tokens[id]?.cancel('Paused');
    final at = _queue.indexWhere((entry) => entry.id == id);
    if (at >= 0) _queue.removeAt(at).ready.complete(false);
    for (final systemId in _systemIds[id] ?? [id]) {
      await _system?.pause(systemId);
    }
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

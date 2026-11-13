import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/storage/device_encryption.dart';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/domain/entities/inference_settings.dart';
import '../../features/hosting/pinned_dio.dart';

/// The phone performs transport/presentation only. Every reconnect reuses the
/// server's job and event cursor, never another model or tool invocation.
class WorkspaceClient {
  static const _jobsKey = 'workspace_jobs_v1';
  static const _capabilitiesKey = 'workspace_capabilities_v1';
  final Dio dio;
  final _pinnedClients = PinnedDioClients();
  Dio _client(InferenceSettings settings) => _pinnedClients.forEndpoint(
    dio,
    settings.remoteUri,
    settings.activeRemoteProfile?.fingerprint,
  );
  WorkspaceClient({Dio? dio})
    : dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));

  static Map<String, dynamic> _store(SharedPreferences prefs, String key) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString(key) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _remember(
    SharedPreferences prefs,
    String store,
    String key,
    Object? value,
  ) {
    final entries = _store(prefs, store);
    if (value == null) {
      entries.remove(key);
    } else {
      entries[key] = value;
    }
    while (entries.length > 128) {
      entries.remove(entries.keys.first);
    }
    return prefs.setString(store, jsonEncode(entries)).then((_) {});
  }

  static Uri endpoint(InferenceSettings settings, String path) {
    final uri = settings.remoteUri;
    if (uri == null) throw StateError('The remote server address is missing.');
    return uri.resolve('/v1/workspace/$path');
  }

  Options options(InferenceSettings settings, {bool stream = false}) => Options(
    headers: {'Authorization': 'Bearer ${settings.remoteApiKey}'},
    responseType: stream ? ResponseType.stream : ResponseType.json,
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  );

  Future<bool> supported(InferenceSettings settings) async {
    if (!settings.usesRemote || settings.remoteProvider.id != 'custom') {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = settings.remoteBaseUrl;
    try {
      final response = await _client(settings).getUri(
        endpoint(settings, 'capabilities'),
        options: options(settings)..receiveTimeout = const Duration(seconds: 5),
      );
      final supported =
          response.data is Map &&
          response.data['version'] == 1 &&
          response.data['capabilities'] is List &&
          (response.data['capabilities'] as List).contains('server_execution');
      if (supported) await _remember(prefs, _capabilitiesKey, key, true);
      return supported;
    } on DioException catch (error) {
      if (isTlsFailure(error)) rethrow;
      if (const [404, 405, 501].contains(error.response?.statusCode)) {
        await _remember(prefs, _capabilitiesKey, key, null);
        return false;
      }
      if (_store(prefs, _capabilitiesKey)[key] == true ||
          const [401, 403].contains(error.response?.statusCode)) {
        rethrow;
      }
      // Other OpenAI-compatible servers do not implement this extension.
      return false;
    }
  }

  Future<String> upload(
    InferenceSettings settings,
    String path,
    String name, {
    CancelToken? cancel,
  }) async {
    final file = File(path);
    final bytes = await DeviceEncryption.instance.read(file);
    final size = bytes.length;
    final response = await _client(settings).postUri(
      endpoint(settings, 'uploads').replace(queryParameters: {'name': name}),
      data: Stream.value(bytes),
      options: options(settings)
        ..headers!.addAll({
          'Content-Type': 'application/octet-stream',
          'Content-Length': size,
        }),
      cancelToken: cancel,
    );
    return response.data['uploadId'] as String;
  }

  Future<void> run({
    required InferenceSettings settings,
    required String requestId,
    required List<Map<String, Object>> messages,
    required void Function(Map<String, dynamic>) event,
    required Future<bool> Function(String description, String approvalId)
    approve,
    CancelToken? cancel,
    List<Map<String, Object>> uploads = const [],
    bool webOnly = false,
    bool phoneActions = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entryId = '${settings.remoteBaseUrl}:$requestId';
    var jobId = _store(prefs, _jobsKey)[entryId] as String?;
    final body = {
      'requestId': requestId,
      'model': settings.remoteModel,
      'messages': messages,
      'webOnly': webOnly,
      'phoneActions': phoneActions,
      'settings': {
        for (final entry in settings.toJson().entries)
          if (entry.key.startsWith('agent') ||
              const {
                'toolsEnabled',
                'toolHelper',
                'helperModelId',
                'toolWeb',
                'toolCalculator',
                'toolDocuments',
                'webSearchEnabled',
                'webMode',
                'toolMaxRounds',
                'toolActions',
              }.contains(entry.key))
            entry.key: entry.value,
        'toolWeb': settings.toolWeb && settings.remoteWebResearch,
        'webSearchEnabled':
            settings.webSearchEnabled && settings.remoteWebResearch,
        'webMode': settings.remoteWebResearch
            ? settings.webMode.name
            : WebMode.off.name,
      },
      'uploads': uploads,
    };
    var sequence = 0;
    var terminal = false;
    final answered = <String, bool>{};
    try {
      while (!terminal && cancel?.isCancelled != true) {
        try {
          if (jobId == null) {
            final response = await _client(settings).postUri(
              endpoint(settings, 'jobs'),
              data: body,
              options: options(settings),
              cancelToken: cancel,
            );
            jobId = response.data['jobId'] as String;
            await _remember(prefs, _jobsKey, entryId, jobId);
          }
          final status = await _client(settings).getUri(
            endpoint(settings, 'jobs/$jobId'),
            options: options(settings),
            cancelToken: cancel,
          );
          final pendingApprovals = (status.data['pendingApprovals'] as List)
              .cast<String>();
          final snapshotSequence = status.data['sequence'] as int;
          final response = await _client(settings).getUri(
            endpoint(settings, 'jobs/$jobId/events?after=$sequence&compact=1'),
            options: options(settings, stream: true),
            cancelToken: cancel,
          );
          final lines = (response.data as ResponseBody).stream
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter());
          await for (final line in lines) {
            if (!line.startsWith('data: ')) continue;
            final received = Map<String, dynamic>.from(
              jsonDecode(line.substring(6)) as Map,
            );
            final next = received['sequence'] as int;
            if (next <= sequence) continue;
            if (next != sequence + 1 || received['jobId'] != jobId) {
              throw StateError('Invalid server activity sequence.');
            }
            final type = received['type'];
            if (type == 'checkpoint') {
              final through = (received['data'] as Map)['through'];
              if (through is! int || through < next) {
                throw StateError('Invalid server activity checkpoint.');
              }
              sequence = through;
              continue;
            }
            if (type == 'approval' &&
                (next > snapshotSequence ||
                    pendingApprovals.contains(
                      (received['data'] as Map)['id'],
                    ))) {
              final data = received['data'] as Map;
              final id = data['id'] as String;
              final allow = answered[id] ??= await approve(
                data['description'] as String,
                id,
              );
              await _client(settings).postUri(
                endpoint(settings, 'jobs/$jobId/approval'),
                data: {'id': id, 'allow': allow},
                options: options(settings)
                  ..validateStatus = (code) => code == 200 || code == 409,
                cancelToken: cancel,
              );
            }
            event(received);
            sequence = next;
            terminal = const ['done', 'failed', 'cancelled'].contains(type);
            if (terminal) break;
          }
          if (!terminal) {
            throw const SocketException('Server activity stream interrupted.');
          }
        } on DioException catch (error) {
          if (isTlsFailure(error)) rethrow;
          if (cancel?.isCancelled == true) break;
          if (error.response != null &&
              !const [
                408,
                429,
                500,
                502,
                503,
                504,
              ].contains(error.response?.statusCode)) {
            rethrow;
          }
          event({
            'type': 'reconnecting',
            'data': {'jobId': jobId},
          });
          await Future.any([
            Future<void>.delayed(const Duration(seconds: 2)),
            if (cancel != null) cancel.whenCancel.then((_) {}),
          ]);
        } on SocketException {
          event({
            'type': 'reconnecting',
            'data': {'jobId': jobId},
          });
          await Future.any([
            Future<void>.delayed(const Duration(seconds: 2)),
            if (cancel != null) cancel.whenCancel.then((_) {}),
          ]);
        }
      }
    } finally {
      if (cancel?.isCancelled == true && jobId != null && !terminal) {
        // A separate request remains usable after the streaming request's
        // token is cancelled. Losing connectivity alone does not enter here.
        for (var attempt = 0; ; attempt++) {
          try {
            await _client(settings).postUri(
              endpoint(settings, 'jobs/$jobId/cancel'),
              options: options(settings),
            );
            break;
          } on DioException catch (error) {
            final code = error.response?.statusCode;
            if (isTlsFailure(error) ||
                attempt >= 2 ||
                (code != null &&
                    !const [408, 429, 500, 502, 503, 504].contains(code))) {
              rethrow;
            }
            await Future<void>.delayed(
              Duration(milliseconds: 200 * (attempt + 1)),
            );
          }
        }
      }
      if (terminal || cancel?.isCancelled == true) {
        await _remember(prefs, _jobsKey, entryId, null);
      }
    }
  }

  Future<bool> hasRetainedJob(
    InferenceSettings settings,
    String requestId,
  ) async => _store(
    await SharedPreferences.getInstance(),
    _jobsKey,
  ).containsKey('${settings.remoteBaseUrl}:$requestId');

  void dispose() {
    dio.close(force: true);
    _pinnedClients.close();
  }
}

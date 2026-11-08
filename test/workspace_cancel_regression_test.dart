import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:ondevice_llm/inference/remote/workspace_client.dart';

class _CancelAdapter implements HttpClientAdapter {
  final CancelToken cancel;
  final bool permanent;
  int attempts = 0;
  _CancelAdapter(this.cancel, this.permanent);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object data = {'jobId': 'job'};
    var status = 200;
    if (options.path.endsWith('/cancel')) {
      attempts++;
      status = permanent || attempts < 2 ? 503 : 200;
      data = {'cancelled': status == 200};
    } else if (options.path.contains('/events')) {
      cancel.cancel();
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    } else if (options.method == 'GET') {
      data = {'pendingApprovals': [], 'sequence': 0};
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final permanent in [false, true]) {
    test(
      'CR-03: cancellation retries and surfaces permanent failure=$permanent',
      () async {
        SharedPreferences.setMockInitialValues({});
        final cancel = CancelToken();
        final adapter = _CancelAdapter(cancel, permanent);
        final client = WorkspaceClient(dio: Dio()..httpClientAdapter = adapter);
        addTearDown(client.dispose);
        final settings = const InferenceSettings(
          remoteEnabled: true,
          remoteProfileId: 'host',
          remoteProfiles: [
            RemoteProfile(
              id: 'host',
              name: 'Host',
              baseUrl: 'http://127.0.0.1:1234/v1/',
              model: 'test',
            ),
          ],
        );
        final run = client.run(
          settings: settings,
          requestId: 'cancel-test',
          messages: [],
          event: (_) {},
          approve: (_, _) async => false,
          cancel: cancel,
        );
        if (permanent) {
          await expectLater(run, throwsA(isA<DioException>()));
          expect(await client.hasRetainedJob(settings, 'cancel-test'), isTrue);
        } else {
          await run;
          expect(await client.hasRetainedJob(settings, 'cancel-test'), isFalse);
        }
        expect(adapter.attempts, greaterThanOrEqualTo(2));
      },
    );
  }
}

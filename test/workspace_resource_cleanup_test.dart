import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/presentation/hosted_workspace.dart';
import 'package:ondevice_llm/features/hosting/workspace_api.dart';
import 'package:ondevice_llm/features/hosting/workspace_jobs.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_model_server_test.dart' show FakeEngine;

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  late DeviceModelServer server;
  late HttpClient client;

  Future<void> start(WorkspaceApi api) async {
    SharedPreferences.setMockInitialValues({});
    server = DeviceModelServer(
      engine: FakeEngine(),
      settings: () => const InferenceSettings(),
      modelId: 'test',
      fallbackTemplate: '',
      accessToken: token,
      workspace: api,
    );
    await server.start();
    client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
    });
  }

  Future<Map<String, dynamic>> post(String path, Object body) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/workspace/$path'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    expect(response.statusCode, 202);
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  }

  final imageMessages = [
    {
      'role': 'user',
      'content': [
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,iVBORw=='},
        },
      ],
    },
  ];

  for (final fail in [false, true]) {
    test('M07: workspace images are private and cleaned after '
        '${fail ? 'decode failure' : 'success'}', () async {
      late WorkspaceApi api;
      final images = <File>[];
      api = WorkspaceApi(
        capabilities: const [],
        run: (job, input) async {
          await api.decodeMessages(
            job,
            fail
                ? [
                    ...imageMessages,
                    {'role': 'invalid', 'content': 'bad'},
                  ]
                : input['messages'],
            vision: true,
            images: images,
          );
          expect(await images.single.exists(), isTrue);
        },
      );
      await start(api);
      final result = await post('jobs', {
        'requestId': 'image',
        'messages': imageMessages,
      });
      final job = api.jobs[result['jobId'] as String]!;
      await job.execution;
      final image = images.single;
      expect(image.parent.path, isNot(Directory.systemTemp.path));
      expect(
        image.parent.uri.pathSegments.where((s) => s.isNotEmpty).last,
        startsWith('desktopServe-'),
      );
      expect(await image.exists(), isFalse);
      expect(await image.parent.exists(), isFalse);
      final events = await job.events().toList();
      expect(events.last['type'], fail ? 'failed' : 'done');
    });
  }

  test(
    'M07: concurrent jobs have separate directories; stop cleans both',
    () async {
      late WorkspaceApi api;
      final images = <File>[];
      final decoded = <Completer<void>>[];
      api = WorkspaceApi(
        capabilities: const [],
        run: (job, input) async {
          final done = Completer<void>();
          decoded.add(done);
          final files = <File>[];
          try {
            await api.decodeMessages(
              job,
              input['messages'],
              vision: true,
              images: files,
            );
            images.add(files.single);
          } finally {
            done.complete();
          }
          await job.cancel.whenCancel;
        },
      );
      await start(api);
      for (var i = 0; i < 2; i++) {
        await post('jobs', {'requestId': '$i', 'messages': imageMessages});
      }
      // Decoding now awaits the private directory and file writes, so the
      // accepted response can arrive before a job's image is on disk.
      expect(decoded, hasLength(2));
      await Future.wait(decoded.map((done) => done.future));
      expect(images, hasLength(2));
      expect(images[0].parent.path, isNot(images[1].parent.path));
      for (final image in images) {
        expect(await image.exists(), isTrue);
        expect(image.parent.path, isNot(Directory.systemTemp.path));
      }
      await server.stop();
      for (final image in images) {
        expect(await image.exists(), isFalse);
        expect(await image.parent.exists(), isFalse);
      }
    },
  );

  test(
    'M08: hosted setup failure releases all acquired upload references',
    () async {
      final provider = Provider<WorkspaceApi>(
        (ref) => hostedWorkspace(
          ref: ref,
          port: () => server.port!,
          token: token,
          primaryModel: 'test',
          hostSettings: () => throw StateError('Setup failed'),
          vision: (_) => false,
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final api = container.read(provider);
      await start(api);
      final request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/v1/workspace/uploads?name=test.txt',
        ),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.contentLength = 4;
      request.add(utf8.encode('test'));
      final response = await request.close();
      expect(response.statusCode, 201);
      final uploadId =
          (jsonDecode(await utf8.decoder.bind(response).join())
                  as Map)['uploadId']
              as String;
      final file = api.uploads[uploadId]!.file;
      // A second owner keeps the file available so a leaked job reference is
      // observable when that owner releases it below.
      api.uploads.acquire(uploadId);
      final result = await post('jobs', {
        'requestId': 'setup-failure',
        'uploads': [
          {'uploadId': uploadId, 'message': 0},
          {'uploadId': uploadId, 'message': 0},
        ],
      });
      final WorkspaceJob job = api.jobs[result['jobId'] as String]!;
      await job.execution;
      expect((await job.events().toList()).last['type'], 'failed');
      expect(await file.exists(), isTrue);
      await api.uploads.release(uploadId);
      expect(api.uploads[uploadId], isNull);
      expect(await file.exists(), isFalse);
      expect(await file.parent.exists(), isFalse);
    },
  );
}

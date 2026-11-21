import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/engine_versions.dart';
import 'package:ondevice_llm/desktop/engine_files.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_pack.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_updater.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_update_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _releasesApi =
    'https://api.github.com/repos/sebytzr16/on-device-llm/releases?per_page=30';
const _assetRoot =
    'https://github.com/sebytzr16/on-device-llm/releases/download/';
const _manifestName = 'engine-pack-windows-x64.json';
const _signatureName = 'engine-pack-windows-x64.json.sig';
const _zipName = 'engine-pack-windows-x64.zip';
const _cpuDll = 'ondevice_llm.dll';
const _cudaDll = 'ondevice_llm_cuda.dll';

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// The test key pairs are deterministic; the app key stays the placeholder.
Future<({SimpleKeyPair keyPair, String publicKey})> _testKey([
  int offset = 7,
]) async {
  final seed = List<int>.generate(32, (i) => i + offset);
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final public = await keyPair.extractPublicKey();
  return (keyPair: keyPair, publicKey: base64.encode(public.bytes));
}

Uint8List _zipOf(Map<String, List<int>> contents) {
  final archive = Archive();
  for (final entry in contents.entries) {
    archive.add(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// A release as the updater sees it: signed manifest, signature and zip, plus
/// the asset URLs that serve them.
class _FakeRelease {
  _FakeRelease(this.tag, this.manifestBytes, this.signature, this.zip);

  final String tag;
  final Uint8List manifestBytes;
  final Uint8List signature;
  final Uint8List zip;

  String url(String asset) => '$_assetRoot$tag/$asset';

  Map<String, dynamic> get releaseJson => {
    'tag_name': tag,
    'assets': [
      {
        'name': _manifestName,
        'size': manifestBytes.length,
        'browser_download_url': url(_manifestName),
      },
      {
        'name': _signatureName,
        'size': signature.length,
        'browser_download_url': url(_signatureName),
      },
      {
        'name': _zipName,
        'size': zip.length,
        'browser_download_url': url(_zipName),
      },
    ],
  };

  Map<String, List<int>> get routes => {
    url(_manifestName): manifestBytes,
    url(_signatureName): signature,
    url(_zipName): zip,
  };
}

Future<_FakeRelease> _release(
  SimpleKeyPair keyPair, {
  String tag = 'engine-b12510',
  String? engine,
  int? revision,
  int bridgeApi = kEngineBridgeApi,
  String minApp = '1.0.0',
  int? cudaMajor = 12,
  Map<String, List<int>>? contents,
  List<Map<String, dynamic>>? manifestFiles,
  String? zipSha256,
}) async {
  final files =
      contents ??
      {
        _cpuDll: utf8.encode('cpu bridge $tag'),
        _cudaDll: utf8.encode('cuda bridge $tag'),
      };
  final zip = _zipOf(files);
  final manifest = <String, dynamic>{
    'version': 1,
    'engine': engine ?? tag.substring(7).split('-').first,
    'revision': revision ?? enginePackVersion(tag)!.revision,
    'bridgeApi': bridgeApi,
    'minApp': minApp,
    'cudaMajor': ?cudaMajor,
    'files':
        manifestFiles ??
        [
          for (final entry in files.entries)
            {
              'name': entry.key,
              'size': entry.value.length,
              'sha256': _sha(entry.value),
            },
        ],
    'zipSha256': zipSha256 ?? _sha(zip),
  };
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
  final signature = Uint8List.fromList(
    (await Ed25519().sign(bytes, keyPair: keyPair)).bytes,
  );
  return _FakeRelease(tag, bytes, signature, zip);
}

/// Offline stand-in for GitHub: URL to body, and every request it received.
class _Server {
  _Server(this.routes);

  final Map<String, List<int>> routes;
  final List<({Uri url, String? range})> requests = [];

  void add(_FakeRelease release) => routes.addAll(release.routes);

  Future<EngineHttpResponse> fetch(Uri uri, {String? range}) async {
    requests.add((url: uri, range: range));
    final body = routes[uri.toString()];
    if (body == null) return const EngineHttpResponse(404);
    return EngineHttpResponse(200, body: Stream.value(body));
  }

  int get apiRequests =>
      requests.where((r) => r.url.path.endsWith('/releases')).length;

  /// Puts the release list on the one endpoint the updater may call.
  void publish(List<Map<String, dynamic>> releases) {
    routes[_releasesApi] = utf8.encode(jsonEncode(releases));
  }
}

void main() {
  test('smoke child arguments, crash, malformed output and timeout', () async {
    const dll = r'C:\engine pack\ondevice_llm.dll';
    expect(
      await enginePackSmoke(
        dll,
        runProcess: (exe, args) async {
          expect(exe, Platform.resolvedExecutable);
          expect(args, ['--engine-smoke', dll]);
          return ProcessResult(1, 0, '{"ok":true}\n', '');
        },
      ),
      isTrue,
    );
    for (final result in [
      ProcessResult(1, -1073741819, '', ''),
      ProcessResult(1, 1, '{"ok":true}', ''),
      ProcessResult(1, 0, '{"ok":false}', ''),
      ProcessResult(1, 0, 'invalid', ''),
    ]) {
      expect(
        await enginePackSmoke(dll, runProcess: (_, _) async => result),
        isFalse,
      );
    }
    expect(
      await enginePackSmoke(
        dll,
        runProcess: (_, _) => Completer<ProcessResult>().future,
        timeout: const Duration(milliseconds: 1),
      ),
      isFalse,
    );
  });

  test(
    'smoke timeout kills and reaps the child while draining both pipes',
    () async {
      final process = _SmokeProcess();
      final result = await enginePackSmoke(
        r'C:\pack\ondevice_llm.dll',
        timeout: const Duration(milliseconds: 1),
        startProcess: (exe, args) async {
          expect(exe, Platform.resolvedExecutable);
          expect(args, ['--engine-smoke', r'C:\pack\ondevice_llm.dll']);
          return process;
        },
      );
      expect(result, isFalse);
      expect(process.killed, isTrue);
      expect(process.exited.isCompleted, isTrue);
      expect(process.out.isClosed, isTrue);
      expect(process.err.isClosed, isTrue);
    },
  );

  for (final stuck in ['exit', 'stdout', 'stderr']) {
    test('smoke bounds cleanup with stuck $stuck', () async {
      final process = _SmokeProcess()..reapOnKill = false;
      if (stuck != 'exit') process.exited.complete(0);
      if (stuck != 'stdout') unawaited(process.out.close());
      if (stuck != 'stderr') unawaited(process.err.close());
      expect(
        await enginePackSmoke(
          'bridge.dll',
          timeout: const Duration(milliseconds: 1),
          cleanupTimeout: const Duration(milliseconds: 10),
          startProcess: (_, _) async => process,
        ).timeout(const Duration(seconds: 1)),
        isFalse,
      );
      expect(process.killed, stuck == 'exit');
      if (!process.exited.isCompleted) process.exited.complete(1);
      await process.out.close();
      await process.err.close();
    });
  }

  test(
    'smoke start drains large output from both pipes before succeeding',
    () async {
      final process = _SmokeProcess();
      final pending = enginePackSmoke(
        'bridge.dll',
        startProcess: (_, _) async => process,
      );
      await Future<void>.delayed(Duration.zero);
      process.out.add(utf8.encode('{"ok":true}'));
      process.err.add(List.filled(128 * 1024, 120));
      process.exited.complete(0);
      await process.out.close();
      await process.err.close();
      expect(await pending, isTrue);
      expect(process.killed, isFalse);
    },
  );

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('engine_updater_test');
  });

  tearDown(() async {
    LlamaBindings.enginePack = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  EngineUpdater updater(
    _Server server, {
    required String publicKey,
    DateTime Function()? clock,
    Future<bool> Function(String path)? openSmoke,
    String appVersion = '1.6.0+9',
  }) => EngineUpdater(
    root: root,
    fetch: server.fetch,
    clock: clock,
    appVersion: appVersion,
    signingPublicKey: publicKey,
    openSmoke: openSmoke ?? (_) async => true,
  );

  Future<EngineUpdater> installed(
    _Server server, {
    required String publicKey,
  }) async {
    final up = updater(server, publicKey: publicKey);
    final check = await up.check();
    expect(check.state, EngineCheckState.available);
    expect((await up.download()).state, EngineDownloadState.done);
    expect(await up.activate(tag: check.tag), isTrue);
    return up;
  }

  group('manifest', () {
    test('parses and verifies a signed manifest', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final manifest = EnginePackManifest.parse(release.manifestBytes);
      expect(manifest.engine, 'b12510');
      expect(manifest.bridgeApi, kEngineBridgeApi);
      expect(manifest.minApp, '1.0.0');
      expect(manifest.cudaMajor, 12);
      expect(manifest.files.map((f) => f.name), [_cpuDll, _cudaDll]);
      expect(
        await verifySignature(
          release.manifestBytes,
          release.signature,
          publicKey: key.publicKey,
        ),
        isTrue,
      );
    });

    test('revision is signed and defaults to zero only when absent', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair, tag: 'engine-b12510-2');
      expect(EnginePackManifest.parse(release.manifestBytes).revision, 2);
      final legacy = jsonDecode(utf8.decode(release.manifestBytes)) as Map;
      legacy.remove('revision');
      expect(
        EnginePackManifest.parse(utf8.encode(jsonEncode(legacy))).revision,
        0,
      );
    });

    test('rejects malformed manifests', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final valid =
          jsonDecode(utf8.decode(release.manifestBytes))
              as Map<String, dynamic>;
      Map<String, dynamic> withChange(Map<String, dynamic> change) => {
        ...valid,
        ...change,
      };

      List<int> bytesOf(Map<String, dynamic> value) =>
          utf8.encode(jsonEncode(value));

      final upper = _cpuDll.toUpperCase();
      final malformed = <Map<String, dynamic>>[
        withChange({'version': 2}),
        withChange({'engine': 'v12510'}),
        withChange({'bridgeApi': 0}),
        for (final revision in [-1, 1.5, '2', null, true])
          withChange({'revision': revision}),
        withChange({'minApp': '1.0'}),
        withChange({'cudaMajor': 0}),
        withChange({'zipSha256': 'not-a-hash'}),
        withChange({'files': const []}),
        withChange({
          'files': [
            {
              'name': 'sub/$_cpuDll',
              'size': 1,
              'sha256': _sha([1]),
            },
          ],
        }),
        withChange({
          'files': [
            {
              'name': '..$_cpuDll',
              'size': 1,
              'sha256': _sha([1]),
            },
          ],
        }),
        withChange({
          'files': [
            {
              'name': _cpuDll,
              'size': 1,
              'sha256': _sha([1]),
            },
            {
              'name': upper,
              'size': 2,
              'sha256': _sha([2]),
            },
          ],
        }),
      ];
      for (final value in malformed) {
        expect(
          () => EnginePackManifest.parse(bytesOf(value)),
          throwsFormatException,
          reason: '$value',
        );
      }
      expect(
        () => EnginePackManifest.parse(utf8.encode('not json')),
        throwsFormatException,
      );
    });

    test('rejects a bad signature and a wrong-length one', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final tampered = Uint8List.fromList(release.signature);
      tampered[10] ^= 0xff;
      expect(
        await verifySignature(
          release.manifestBytes,
          tampered,
          publicKey: key.publicKey,
        ),
        isFalse,
      );
      expect(
        await verifySignature(
          release.manifestBytes,
          Uint8List(10),
          publicKey: key.publicKey,
        ),
        isFalse,
      );
      final other = await _testKey(8);
      expect(
        await verifySignature(
          release.manifestBytes,
          release.signature,
          publicKey: other.publicKey,
        ),
        isFalse,
      );
    });

    test('the placeholder key never verifies anything', () async {
      const placeholder = 'REPLACE_WITH_OWNER_PUBLIC_KEY';
      final key = await _testKey();
      final release = await _release(key.keyPair);
      expect(
        await verifySignature(
          release.manifestBytes,
          release.signature,
          publicKey: placeholder,
        ),
        isFalse,
      );
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = updater(server, publicKey: placeholder);
      expect((await up.check()).state, EngineCheckState.upToDate);
    });

    test('the compiled-in key is a real 32-byte key that rejects test '
        'signatures', () async {
      expect(base64.decode(kEngineSigningPublicKey), hasLength(32));
      final key = await _testKey();
      final release = await _release(key.keyPair);
      expect(
        await verifySignature(release.manifestBytes, release.signature),
        isFalse,
      );
    });

    test('compatible checks the bridge API and minApp', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair, minApp: '1.6.0');
      final manifest = EnginePackManifest.parse(release.manifestBytes);
      expect(
        manifest.compatible(appVersion: '1.6.0+9', bridgeApi: kEngineBridgeApi),
        isTrue,
      );
      expect(
        manifest.compatible(appVersion: '1.6.1', bridgeApi: kEngineBridgeApi),
        isTrue,
      );
      expect(
        manifest.compatible(appVersion: '1.5.9', bridgeApi: kEngineBridgeApi),
        isFalse,
      );
      expect(
        manifest.compatible(
          appVersion: '1.6.0',
          bridgeApi: kEngineBridgeApi + 1,
        ),
        isFalse,
      );
      expect(
        manifest.compatible(
          appVersion: 'not a version',
          bridgeApi: kEngineBridgeApi,
        ),
        isFalse,
      );
    });

    test('engine tags order by build number, then revision', () {
      expect(enginePackVersion('engine-b12510')?.build, 12510);
      expect(enginePackVersion('engine-b12510')?.revision, 0);
      expect(enginePackVersion('engine-b12510-2')?.revision, 2);
      expect(enginePackVersion('engine-notes'), isNull);
      expect(
        compareEnginePackVersions('engine-b12510', 'engine-b12505'),
        greaterThan(0),
      );
      expect(
        compareEnginePackVersions('engine-b12510-2', 'engine-b12510'),
        greaterThan(0),
      );
      expect(compareEnginePackVersions('engine-b12510', 'engine-b12510'), 0);
    });
  });

  group('check', () {
    test('picks the newest engine pack after the bundled tag', () async {
      final key = await _testKey();
      final older = await _release(key.keyPair, tag: 'engine-b12505');
      final newest = await _release(key.keyPair, tag: 'engine-b12510');
      final revision = await _release(key.keyPair, tag: 'engine-b12510-2');
      final server = _Server({});
      for (final release in [older, newest, revision]) {
        server.add(release);
      }
      server.publish([
        older.releaseJson,
        revision.releaseJson,
        newest.releaseJson,
        {'tag_name': 'engine-notes', 'assets': const []},
        {'tag_name': 'v1.6.0', 'assets': const []},
      ]);
      final up = updater(server, publicKey: key.publicKey);
      final result = await up.check();
      expect(result.state, EngineCheckState.available);
      expect(result.tag, 'engine-b12510-2');
      expect(result.size, revision.zip.length);
    });

    test('offers nothing older than the bundled engine', () async {
      final key = await _testKey();
      final bundled = llamaBuildNumber(EnginePins.llamaCppTag)!;
      final old = await _release(
        key.keyPair,
        tag: 'engine-b${bundled - 1}',
        engine: 'b${bundled - 1}',
      );
      final server = _Server({});
      server.add(old);
      server.publish([old.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).state, EngineCheckState.upToDate);
    });

    test('a revision of the bundled build is newer than the bundle', () async {
      final key = await _testKey();
      final release = await _release(
        key.keyPair,
        tag: 'engine-${EnginePins.llamaCppTag}-1',
      );
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).state, EngineCheckState.available);
    });

    test('checks at most once a day unless forced', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      var now = DateTime.utc(2026, 11, 18, 12);
      final up = updater(server, publicKey: key.publicKey, clock: () => now);
      expect((await up.check()).state, EngineCheckState.available);
      expect(server.apiRequests, 1);
      expect((await up.check()).state, EngineCheckState.upToDate);
      expect(server.apiRequests, 1);
      now = now.add(const Duration(hours: 25));
      expect((await up.check()).state, EngineCheckState.available);
      expect(server.apiRequests, 2);
      expect((await up.check(force: true)).state, EngineCheckState.available);
      expect(server.apiRequests, 3);
    });

    test('an unreachable GitHub reports offline', () async {
      var attempts = 0;
      final up = EngineUpdater(
        root: root,
        signingPublicKey: 'unused',
        fetch: (uri, {range}) async {
          attempts++;
          throw const SocketException('no network');
        },
        openSmoke: (_) async => true,
      );
      final result = await up.check();
      expect(result.state, EngineCheckState.offline);
      expect(result.message, contains('no network'));
      await up.check();
      expect(attempts, 1);
      await up.check(force: true);
      expect(attempts, 2);
    });

    test('a release whose asset URL is not on GitHub is ignored', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({});
      server.add(release);
      final json = release.releaseJson;
      (json['assets'] as List)
              .where((asset) => (asset as Map)['name'] == _zipName)
              .first['browser_download_url'] =
          'https://example.com/$_zipName';
      server.publish([json]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).state, EngineCheckState.upToDate);
      expect(server.requests.any((r) => r.url.host == 'example.com'), isFalse);
    });

    test('a pack that needs a newer app is skipped', () async {
      final key = await _testKey();
      final future = await _release(key.keyPair, minApp: '9.0.0');
      final server = _Server({});
      server.add(future);
      server.publish([future.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).state, EngineCheckState.upToDate);
    });

    test('a pack for another bridge API is skipped', () async {
      final key = await _testKey();
      final wrong = await _release(
        key.keyPair,
        bridgeApi: kEngineBridgeApi + 1,
      );
      final server = _Server({});
      server.add(wrong);
      server.publish([wrong.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).state, EngineCheckState.upToDate);
    });
  });

  group('download', () {
    test('installs a verified pack and activates it', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      final check = await up.check();
      expect(check.state, EngineCheckState.available);
      expect(check.tag, release.tag);

      final result = await up.download();
      expect(result.state, EngineDownloadState.done);
      expect(await up.activate(), isTrue);
      final active = up.activePackDir();
      expect(active, p.join(root.path, release.tag));
      expect(
        File(p.join(active!, _cpuDll)).readAsBytesSync(),
        utf8.encode('cpu bridge ${release.tag}'),
      );
    });

    test('rejects a zip that does not match the signed hash', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair, zipSha256: 'a' * 64);
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      expect((await up.download()).state, EngineDownloadState.error);
      expect(
        Directory(p.join(root.path, 'staging', release.tag)).existsSync(),
        isFalse,
      );
    });

    test('rejects a file that does not match the manifest hash', () async {
      final key = await _testKey();
      final contents = {_cpuDll: utf8.encode('tampered bridge')};
      final release = await _release(
        key.keyPair,
        contents: contents,
        manifestFiles: [
          {
            'name': _cpuDll,
            'size': contents[_cpuDll]!.length,
            'sha256': 'b' * 64,
          },
        ],
      );
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      expect((await up.download()).state, EngineDownloadState.error);
      expect(
        Directory(p.join(root.path, 'staging', release.tag)).existsSync(),
        isFalse,
      );
    });

    test('rejects path traversal entries', () async {
      final key = await _testKey();
      final contents = {
        _cpuDll: utf8.encode('cpu bridge'),
        '../evil.dll': utf8.encode('escape'),
      };
      final release = await _release(
        key.keyPair,
        contents: contents,
        manifestFiles: [
          {
            'name': _cpuDll,
            'size': contents[_cpuDll]!.length,
            'sha256': _sha(contents[_cpuDll]!),
          },
        ],
      );
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      expect((await up.download()).state, EngineDownloadState.error);
      expect(File(p.join(root.path, 'evil.dll')).existsSync(), isFalse);
      expect(
        Directory(p.join(root.path, 'staging', release.tag)).existsSync(),
        isFalse,
      );
    });

    test('rejects a file the manifest does not list', () async {
      final key = await _testKey();
      final contents = {
        _cpuDll: utf8.encode('cpu bridge'),
        _cudaDll: utf8.encode('surprise'),
      };
      final release = await _release(
        key.keyPair,
        contents: contents,
        manifestFiles: [
          {
            'name': _cpuDll,
            'size': contents[_cpuDll]!.length,
            'sha256': _sha(contents[_cpuDll]!),
          },
        ],
      );
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      expect((await up.download()).state, EngineDownloadState.error);
      expect(
        Directory(p.join(root.path, 'staging', release.tag)).existsSync(),
        isFalse,
      );
    });

    test(
      'GPU smoke failures are unavailable without blacklisting the pack',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        final up = updater(
          server,
          publicKey: key.publicKey,
          openSmoke: (path) async {
            if (p.basename(path) == _cudaDll) {
              throw StateError('missing CUDA runtime');
            }
            return true;
          },
        );
        await up.check();
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        final files = EnginePackFiles(root.path);
        expect(files.unavailableFiles, [_cudaDll]);
        final state =
            jsonDecode(File(p.join(root.path, 'state.json')).readAsStringSync())
                as Map;
        expect(state['badTags'], isNot(contains(release.tag)));
        final opened = <String>[];
        final skipped = <String>[];
        final selected = LlamaBindings.openWindowsLibrary<String>(
          skipped: skipped,
          preferred: 'cuda',
          packDir: up.activePackDir(),
          unavailablePackFiles: files.unavailableFiles,
          hasAvx2: () => true,
          environment: const {},
          fileExists: (_) => true,
          gpuDeviceCount: (_) => 1,
          open: (name) {
            opened.add(name);
            return name;
          },
        );
        expect(selected.name, LlamaBindings.windowsBridgePath(_cudaDll));
        expect(opened, [LlamaBindings.windowsBridgePath(_cudaDll)]);
        expect(skipped, contains(contains('unavailable')));
        final cpuFallback = LlamaBindings.openWindowsLibrary<String>(
          skipped: [],
          packDir: up.activePackDir(),
          unavailablePackFiles: files.unavailableFiles,
          hasAvx2: () => true,
          hasAvx512: () => false,
          environment: const {},
          fileExists: (_) => true,
          gpuDeviceCount: (_) => 1,
          open: (name) {
            if (LlamaBindings.windowsGpuOf(name) != null) {
              throw StateError('No usable bundled GPU runtime');
            }
            return name;
          },
        );
        expect(cpuFallback.name, endsWith(_cpuDll));
        expect(cpuFallback.name, startsWith(up.activePackDir()!));
      },
    );

    test('GPU-only pack cannot replace a working CPU bridge', () async {
      final key = await _testKey();
      final release = await _release(
        key.keyPair,
        contents: {
          _cudaDll: [1],
        },
      );
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      expect((await up.download()).state, EngineDownloadState.error);
      expect(await up.activate(), isFalse);
    });

    test('a failing smoke test marks the tag bad for good', () async {
      final key = await _testKey();
      final newest = await _release(key.keyPair, tag: 'engine-b12510');
      final older = await _release(key.keyPair, tag: 'engine-b12505');
      final server = _Server({});
      for (final release in [newest, older]) {
        server.add(release);
      }
      server.publish([newest.releaseJson, older.releaseJson]);
      final up = updater(
        server,
        publicKey: key.publicKey,
        openSmoke: (_) async => false,
      );
      expect((await up.check()).tag, newest.tag);
      expect((await up.download()).state, EngineDownloadState.error);
      expect(
        Directory(p.join(root.path, 'staging', newest.tag)).existsSync(),
        isFalse,
      );
      // The next check skips the bad pack and offers the one before it.
      expect((await up.check(force: true)).tag, older.tag);
    });

    test('resumes a partial download with a Range request', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final half = release.zip.length ~/ 2;
      final ranges = <String?>[];
      var first = true;
      final up = EngineUpdater(
        root: root,
        appVersion: '1.6.0+9',
        signingPublicKey: key.publicKey,
        openSmoke: (_) async => true,
        fetch: (uri, {range}) async {
          final text = uri.toString();
          if (text == _releasesApi) {
            return EngineHttpResponse(
              200,
              body: Stream.value(
                utf8.encode(jsonEncode([release.releaseJson])),
              ),
            );
          }
          if (text.endsWith('.json')) {
            return EngineHttpResponse(
              200,
              body: Stream.value(release.manifestBytes),
            );
          }
          if (text.endsWith('.sig')) {
            return EngineHttpResponse(
              200,
              body: Stream.value(release.signature),
            );
          }
          ranges.add(range);
          if (first) {
            first = false;
            final controller = StreamController<List<int>>();
            controller.add(release.zip.sublist(0, half));
            controller.addError(const SocketException('connection lost'));
            unawaited(controller.close());
            return EngineHttpResponse(200, body: controller.stream);
          }
          final start = int.tryParse(range ?? '') ?? 0;
          return EngineHttpResponse(
            206,
            body: Stream.value(release.zip.sublist(start)),
          );
        },
      );
      await up.check();
      expect((await up.download()).state, EngineDownloadState.error);
      expect((await up.download()).state, EngineDownloadState.done);
      expect(ranges, [null, '$half']);
      expect(await up.activate(), isTrue);
      expect(up.activePackDir(), isNotNull);
    });
  });

  group('security regressions', () {
    test('retagging a signed pack cannot raise its revision', () async {
      final key = await _testKey();
      final current = await _release(key.keyPair, tag: 'engine-b12510-2');
      final old = await _release(
        key.keyPair,
        tag: 'engine-b12510',
        revision: 0,
      );
      final retagged = _FakeRelease(
        'engine-b12510-99',
        old.manifestBytes,
        old.signature,
        old.zip,
      );
      final server = _Server({})
        ..add(current)
        ..add(retagged)
        ..publish([current.releaseJson]);
      final up = await installed(server, publicKey: key.publicKey);
      server.publish([retagged.releaseJson]);
      expect((await up.check(force: true)).state, EngineCheckState.upToDate);
      expect(up.activePackDir(), p.join(root.path, current.tag));
    });

    test('signature covers exact bytes including whitespace', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      expect(
        await verifySignature(
          [...release.manifestBytes, 32],
          release.signature,
          publicKey: key.publicKey,
        ),
        isFalse,
      );
    });

    test('prerelease app does not satisfy a stable minimum', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair, minApp: '1.6.0');
      final manifest = EnginePackManifest.parse(release.manifestBytes);
      expect(
        manifest.compatible(
          appVersion: '1.6.0-rc.1',
          bridgeApi: kEngineBridgeApi,
        ),
        isFalse,
      );
      expect(
        manifest.compatible(
          appVersion: '1.6.0+10',
          bridgeApi: kEngineBridgeApi,
        ),
        isTrue,
      );
    });

    test('partial staging cannot be activated', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      await Directory(
        p.join(root.path, 'staging', release.tag),
      ).create(recursive: true);
      expect(await up.activate(), isFalse);
      expect(await up.activate(tag: release.tag), isFalse);
      expect(up.activePackDir(), isNull);
    });

    test('staged DLL changes after smoke prevent activation', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      expect((await up.download()).state, EngineDownloadState.done);
      await File(
        p.join(root.path, 'staging', release.tag, _cpuDll),
      ).writeAsString('changed');
      expect(await up.activate(), isFalse);
      expect(up.activePackDir(), isNull);
      expect(
        Directory(p.join(root.path, 'staging', release.tag)).existsSync(),
        isFalse,
      );
    });

    for (final host in [
      'release-assets.githubusercontent.com',
      'evil.example',
      'githubusercontent.com.evil.example',
      'githubusercontent.com',
    ]) {
      test('redirect host $host is checked before fetching', () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        final requested = <Uri>[];
        final up = EngineUpdater(
          root: root,
          appVersion: '1.6.0',
          signingPublicKey: key.publicKey,
          fetch: (uri, {range}) async {
            requested.add(uri);
            if (uri.host == 'github.com') {
              return EngineHttpResponse(
                302,
                location: 'https://$host${uri.path}',
              );
            }
            if (uri.host.endsWith('.githubusercontent.com')) {
              return server.fetch(Uri.parse('https://github.com${uri.path}'));
            }
            return server.fetch(uri, range: range);
          },
        );
        final result = await up.check();
        if (host == 'release-assets.githubusercontent.com') {
          expect(result.state, EngineCheckState.available);
          expect(requested.any((uri) => uri.host == host), isTrue);
        } else {
          expect(result.state, EngineCheckState.error);
          expect(requested.any((uri) => uri.host == host), isFalse);
        }
      });
    }
  });

  group('engine folders', () {
    test(
      'activation rejects a download below the current revision floor',
      () async {
        final key = await _testKey();
        final older = await _release(key.keyPair, tag: 'engine-b12510');
        final newer = await _release(key.keyPair, tag: 'engine-b12511');
        final server = _Server({})
          ..add(older)
          ..add(newer)
          ..publish([older.releaseJson]);
        final stale = updater(server, publicKey: key.publicKey);
        expect((await stale.check()).tag, older.tag);
        expect((await stale.download()).state, EngineDownloadState.done);
        server.publish([newer.releaseJson]);
        final current = updater(server, publicKey: key.publicKey);
        expect((await current.check(force: true)).tag, newer.tag);
        expect((await current.download()).state, EngineDownloadState.done);
        expect(await current.activate(), isTrue);

        // The marker itself carries the floor, even before state.json mirrors it.
        final state = File(p.join(root.path, 'state.json'));
        final data = jsonDecode(state.readAsStringSync()) as Map;
        data.remove('verifiedTag');
        state.writeAsStringSync(jsonEncode(data));
        expect(await stale.activate(), isFalse);
        expect(current.verifiedPackDir(), p.join(root.path, newer.tag));
        await current.useBundled();
        server.publish([older.releaseJson]);
        expect(
          (await current.check(force: true)).state,
          EngineCheckState.upToDate,
        );
      },
    );

    test(
      'startup retries a stranded legacy restore and quarantines the target',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        await installed(server, publicKey: key.publicKey);
        final target = p.join(root.path, release.tag);
        final aside = Directory(target).renameSync('$target.legacy');
        final obstruction = File(target)
          ..writeAsStringSync('blocks the rename');
        await updater(server, publicKey: key.publicKey).prepare();
        expect(aside.existsSync(), isTrue);
        obstruction.deleteSync();

        Directory(target).createSync();
        File(p.join(target, _cpuDll)).writeAsStringSync('failed promotion');
        final restarted = updater(server, publicKey: key.publicKey);
        await restarted.prepare();
        expect(restarted.verifiedPackDir(), target);
        expect(aside.existsSync(), isFalse);
        expect(
          root.listSync().map((entry) => p.basename(entry.path)),
          isNot(contains(startsWith('${release.tag}.broken.'))),
        );
      },
    );

    test(
      'a leftover legacy aside with a delete marker does not block activation',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        final up = updater(server, publicKey: key.publicKey);
        expect((await up.check()).state, EngineCheckState.available);
        expect((await up.download()).state, EngineDownloadState.done);
        // A successful promotion left its old pack aside because the cleanup
        // rename failed: the marker says the aside is garbage, not a restore.
        final target = p.join(root.path, release.tag);
        final aside = Directory('$target.legacy')..createSync();
        File(p.join(aside.path, _cpuDll)).writeAsStringSync('old pack');
        final marker = File('${aside.path}.delete-on-start')
          ..writeAsStringSync('');
        expect(await up.activate(), isTrue);
        expect(up.activePackDir(), target);
        expect(aside.existsSync(), isFalse);
        expect(marker.existsSync(), isFalse);
      },
    );

    test(
      'an aside from the same promotion nonce does not block activation',
      () async {
        final key = await _testKey();
        final older = await _release(key.keyPair, tag: 'engine-b12505');
        final newer = await _release(key.keyPair, tag: 'engine-b12510');
        final server = _Server({})
          ..add(older)
          ..add(newer)
          ..publish([older.releaseJson]);
        final up = updater(server, publicKey: key.publicKey);
        expect((await up.check()).state, EngineCheckState.available);
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        final active =
            jsonDecode(
                  File(p.join(root.path, 'active.json')).readAsStringSync(),
                )
                as Map;
        final promotion = active['promotion'] as String;
        // The same nonce in the aside and in active.json means the promotion
        // that produced the active pack finished; the aside is disposable.
        final aside = Directory(p.join(root.path, '${newer.tag}.legacy'))
          ..createSync();
        File(
          p.join(aside.path, installedMetaName),
        ).writeAsStringSync(jsonEncode({'promotion': promotion}));
        server.publish([newer.releaseJson]);
        expect((await up.check(force: true)).state, EngineCheckState.available);
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        expect(up.activePackDir(), p.join(root.path, newer.tag));
        expect(aside.existsSync(), isFalse);
      },
    );

    test('useBundled keeps the pack folder and drops the marker', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = await installed(server, publicKey: key.publicKey);
      final packDir = p.join(root.path, release.tag);
      expect(up.activePackDir(), packDir);
      await up.useBundled();
      expect(up.activePackDir(), isNull);
      expect(File(p.join(root.path, 'active.json')).existsSync(), isFalse);
      expect(Directory(packDir).existsSync(), isTrue);
    });

    test('activate keeps the active pack and one previous one', () async {
      final key = await _testKey();
      final older = await _release(key.keyPair, tag: 'engine-b12505');
      final newer = await _release(key.keyPair, tag: 'engine-b12510');
      final server = _Server({});
      for (final release in [older, newer]) {
        server.add(release);
      }
      // Install and activate the older pack first.
      server.publish([older.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.check();
      await up.download();
      expect(await up.activate(), isTrue);
      // Then the newer one; the older stays as the fallback.
      server.publish([newer.releaseJson]);
      await up.check(force: true);
      await up.download();
      expect(await up.activate(), isTrue);
      expect(up.activePackDir(), p.join(root.path, newer.tag));
      expect(Directory(p.join(root.path, older.tag)).existsSync(), isTrue);

      // A third pack prunes the older one.
      final newest = await _release(key.keyPair, tag: 'engine-b12511');
      server.add(newest);
      server.publish([newest.releaseJson]);
      await up.check(force: true);
      await up.download();
      expect(await up.activate(), isTrue);
      expect(Directory(p.join(root.path, older.tag)).existsSync(), isFalse);
      expect(Directory(p.join(root.path, newer.tag)).existsSync(), isTrue);
    });

    test(
      'removeAll defers deletion until startup and keeps the bad list',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({});
        server.add(release);
        server.publish([release.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        final stateFile = File(p.join(root.path, 'state.json'));
        final savedState = jsonDecode(await stateFile.readAsString()) as Map;
        savedState['badTags'] = ['engine-b12500'];
        await stateFile.writeAsString(jsonEncode(savedState));
        final staged = Directory(p.join(root.path, 'staging', 'engine-b12520'));
        await staged.create(recursive: true);
        await File(p.join(staged.path, _cpuDll)).writeAsString('staged');
        await up.removeAll();
        expect(staged.existsSync(), isTrue);
        expect(up.activePackDir(), isNull);
        expect(Directory(p.join(root.path, release.tag)).existsSync(), isTrue);
        expect(
          File(
            p.join(root.path, '${release.tag}.delete-on-start'),
          ).existsSync(),
          isTrue,
        );
        // Preparing the same running updater must not delete mapped libraries.
        await up.prepare();
        expect(Directory(p.join(root.path, release.tag)).existsSync(), isTrue);
        await updater(server, publicKey: key.publicKey).prepare();
        expect(Directory(p.join(root.path, release.tag)).existsSync(), isFalse);
        expect(
          File(
            p.join(root.path, '${release.tag}.delete-on-start'),
          ).existsSync(),
          isFalse,
        );
        expect(Directory(p.join(root.path, 'staging')).existsSync(), isFalse);
        expect(File(p.join(root.path, 'active.json')).existsSync(), isFalse);
        expect(stateFile.existsSync(), isTrue);
        expect((jsonDecode(await stateFile.readAsString()) as Map)['badTags'], [
          'engine-b12500',
        ]);
      },
    );

    test('choice key follows installs and switching to built-in', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      await up.prepare();
      final bundled = nativeLibraryChoiceKey(
        backend: 'cpu',
        cpuVariant: 'avx2',
      );
      await up.check();
      await up.download();
      await up.activate();
      final packed = nativeLibraryChoiceKey(backend: 'cpu', cpuVariant: 'avx2');
      expect(packed, isNot(bundled));
      expect(packed.$4, up.activePackDir());
      await up.useBundled();
      expect(
        nativeLibraryChoiceKey(backend: 'cpu', cpuVariant: 'avx2'),
        bundled,
      );
    });

    test(
      'bridge initialization never acknowledges model load success',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        final guard = EnginePackLoadGuard(EnginePackFiles(root.path));
        // Probe-only bindings do not start a model attempt.
        expect(up.activePackDir(), isNotNull);
        guard.beforeOpen();
        guard.beforeOpen(); // Trying another variant is still the same attempt.
        guard.selected = true;
        guard.beforeModelLoad();
        expect(up.activePackDir(), isNotNull);
        // A retry using the same bindings is a second unfinished model load.
        guard.beforeModelLoad();
        expect(up.activePackDir(), isNull);
        guard.modelLoadSucceeded();
        expect(up.activePackDir(), isNotNull);
        guard.beforeModelLoad();
        expect(up.activePackDir(), isNotNull);
        // A bundled fallback must never acknowledge a failed pack attempt.
        final fallback = EnginePackLoadGuard(EnginePackFiles(root.path));
        fallback.beforeOpen();
        fallback.modelLoadSucceeded();
        expect(up.activePackDir(), isNull);
      },
    );

    test('removal errors leave the controller showing built-in', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      await installed(server, publicKey: key.publicKey);
      final failing = _RemovalErrorUpdater(root);
      final container = ProviderContainer(
        overrides: [engineUpdaterProvider.overrideWithValue(failing)],
      );
      addTearDown(container.dispose);
      final controller = container.read(engineUpdateProvider.notifier);
      await controller.removeAll();
      final view = container.read(engineUpdateProvider);
      expect(view.installed, isNull);
      expect(view.phase, EngineUpdatePhase.error);
      expect(view.message, contains('cleanup denied'));
      expect(failing.activePackDir(), isNull);
    });

    test('an unwritable engines folder refuses the pack for that load', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final up = await installed(server, publicKey: key.publicKey);
      expect(up.activePackDir(), isNotNull);
      // The crash marker file cannot be written: a folder squats on its name.
      final stateFile = File(p.join(root.path, 'state.json'));
      await stateFile.delete();
      await Directory(stateFile.path).create();
      expect(up.markLoadStarted(), isFalse);
      // A load whose attempt cannot be counted must not run the pack unguarded.
      final guard = EnginePackLoadGuard(EnginePackFiles(root.path));
      expect(guard.beforeOpen, throwsStateError);
      // The pack itself is untouched and still the active one.
      expect(up.activePackDir(), isNotNull);
    });

    test('a failed switch to built-in shows the error in the panel', () async {
      final failing = _BundledErrorUpdater(root);
      final container = ProviderContainer(
        overrides: [engineUpdaterProvider.overrideWithValue(failing)],
      );
      addTearDown(container.dispose);
      final controller = container.read(engineUpdateProvider.notifier);
      await controller.useBundled();
      final view = container.read(engineUpdateProvider);
      expect(view.phase, EngineUpdatePhase.error);
      expect(view.message, contains('marker denied'));
    });

    test(
      'closing the panel during a refresh touches no notifier state',
      () async {
        // Auto-update on: the refresh is followed by a check, which must not
        // read the disposed notifier either.
        SharedPreferences.setMockInitialValues({});
        final slow = _SlowPrepareUpdater(root);
        final container = ProviderContainer(
          overrides: [engineUpdaterProvider.overrideWithValue(slow)],
        );
        final started = container.read(engineUpdateProvider.notifier).start();
        await Future<void>.delayed(Duration.zero);
        container.dispose();
        slow.gate.complete();
        await expectLater(started, completes);
      },
    );

    test('a pack that cannot be activated leaves the panel usable', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({})
        ..add(release)
        ..publish([release.releaseJson]);
      final failing = _ActivateErrorUpdater(root, server, key.publicKey);
      final container = ProviderContainer(
        overrides: [engineUpdaterProvider.overrideWithValue(failing)],
      );
      addTearDown(container.dispose);
      final controller = container.read(engineUpdateProvider.notifier);
      await controller.checkNow();
      expect(
        container.read(engineUpdateProvider).phase,
        EngineUpdatePhase.available,
      );
      await controller.update();
      final view = container.read(engineUpdateProvider);
      expect(view.phase, EngineUpdatePhase.error);
      expect(view.busy, isFalse);
      expect(view.message, contains('engines folder is read-only'));
      expect(view.installed, isNull);
    });

    test(
      'an installed pack loads even when the build has no release version',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair, minApp: '9.0.0');
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        // Installed by a build that satisfies minApp...
        final up = updater(
          server,
          publicKey: key.publicKey,
          appVersion: '9.0.0+1',
        );
        expect((await up.check()).state, EngineCheckState.available);
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        // ...then loaded by a development build with the fallback version. The
        // signature and DLL hashes still gate the load; minApp is install-only.
        final files = EnginePackFiles(
          root.path,
          signingPublicKey: key.publicKey,
          appVersion: '0.1.1+2',
        );
        await files.prepare();
        expect(files.verifiedPackDir(), p.join(root.path, release.tag));
        // Another bridge API is still refused at load time.
        final other = EnginePackFiles(
          root.path,
          signingPublicKey: key.publicKey,
          appVersion: '0.1.1+2',
          bridgeApi: kEngineBridgeApi + 1,
        );
        await other.prepare();
        expect(other.verifiedPackDir(), isNull);
      },
    );

    test(
      'a pack from an earlier build is re-offered, never silently dropped',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        final dir = p.join(root.path, release.tag);
        // Earlier builds wrote only the marker, no copied manifest/signature.
        File(p.join(dir, installedManifestName)).deleteSync();
        File(p.join(dir, installedSignatureName)).deleteSync();

        expect(up.activePackDir(), isNotNull);
        await up.prepare();
        expect(up.verifiedPackDir(), isNull);
        expect(up.needsMigration, isTrue);
        expect(up.unverifiedNotice, isTrue);
        // The folder is kept and the same tag is offered for a signed reinstall.
        expect(Directory(dir).existsSync(), isTrue);
        final check = await up.check(force: true);
        expect(check.state, EngineCheckState.available);
        expect(check.tag, release.tag);
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        expect(up.verifiedPackDir(), dir);
        expect(up.needsMigration, isFalse);
        expect(up.unverifiedNotice, isFalse);
      },
    );

    test(
      'two isolates record crash attempts without sharing a temp file',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        await installed(server, publicKey: key.publicKey);
        final path = root.path;
        // The two real writers are the model-load isolate's crash guard and the
        // UI isolate. Concurrent read-modify-write cycles must be serialised by
        // the lock file, or a crash attempt is lost.
        for (var round = 0; round < 2; round++) {
          final results = await Future.wait([
            for (var i = 0; i < 3; i++)
              Isolate.run(() => _recordCrashAttempt(path)),
          ]);
          expect(results, everyElement(isTrue), reason: 'round $round');
        }
        final state =
            jsonDecode(File(p.join(path, 'state.json')).readAsStringSync())
                as Map;
        // Six attempts, no lost update: the crash guard sees every load.
        expect(state['crashCount'], 6);
      },
    );

    test(
      'an unverified pack keeps the revision floor of its last install',
      () async {
        final key = await _testKey();
        final newest = await _release(key.keyPair, tag: 'engine-b12510-3');
        final older = await _release(key.keyPair, tag: 'engine-b12510-1');
        final server = _Server({})
          ..add(newest)
          ..add(older)
          ..publish([newest.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        final dir = p.join(root.path, newest.tag);
        // The pack stops verifying (a tampered or half-removed install).
        File(p.join(dir, installedManifestName)).deleteSync();
        File(p.join(dir, installedSignatureName)).deleteSync();
        await up.prepare();
        expect(up.verifiedPackDir(), isNull);
        expect(up.activePackDir(), isNotNull);

        // An older signed release must not roll the install back...
        server.publish([older.releaseJson]);
        expect((await up.check(force: true)).state, EngineCheckState.upToDate);
        // ...while the same tag and revision may be reinstalled from its signed
        // release, which is what migration needs.
        server.publish([newest.releaseJson]);
        final reinstall = await up.check(force: true);
        expect(reinstall.state, EngineCheckState.available);
        expect(reinstall.tag, newest.tag);
      },
    );

    test(
      'prepare hashes an unchanged pack once and re-hashes any change',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        await installed(server, publicKey: key.publicKey);
        final dir = p.join(root.path, release.tag);
        final files = EnginePackFiles(
          root.path,
          signingPublicKey: key.publicKey,
        );
        await files.prepare();
        expect(files.verifiedPackDir(), dir);
        expect(files.contentHashRuns, 1);
        // An unchanged folder is not read again on the next load (P2-2); the
        // native open still hashes the bridge it maps.
        await files.prepare();
        expect(files.verifiedPackDir(), dir);
        expect(files.contentHashRuns, 1);
        // Same size, different bytes, new modification time: re-hashed and
        // refused.
        final dll = File(p.join(dir, _cpuDll));
        final bytes = dll.readAsBytesSync();
        bytes[0] ^= 0xFF;
        dll.writeAsBytesSync(bytes);
        dll.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
        await files.prepare();
        expect(files.contentHashRuns, 2);
        expect(files.verifiedPackDir(), isNull);
      },
    );

    test(
      'a legacy install sets the revision floor before it is reinstalled',
      () async {
        final key = await _testKey();
        final newest = await _release(key.keyPair, tag: 'engine-b12510');
        final older = await _release(key.keyPair, tag: 'engine-b12509');
        final server = _Server({})
          ..add(newest)
          ..add(older)
          ..publish([newest.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        final dir = p.join(root.path, newest.tag);
        // An earlier build wrote no signed floor into state.json and copied no
        // manifest into the folder.
        final stateFile = File(p.join(root.path, 'state.json'));
        final state = jsonDecode(stateFile.readAsStringSync()) as Map;
        state.remove('verifiedTag');
        stateFile.writeAsStringSync(jsonEncode(state));
        File(p.join(dir, installedManifestName)).deleteSync();
        File(p.join(dir, installedSignatureName)).deleteSync();
        await up.prepare();
        expect(up.needsMigration, isTrue);
        // engine-b12510 is still installed: an older signed release must not
        // be installed over it while its reinstall is pending (P3-3).
        server.publish([older.releaseJson]);
        expect((await up.check(force: true)).state, EngineCheckState.upToDate);
        // Its own tag stays reinstallable.
        server.publish([newest.releaseJson]);
        final reinstall = await up.check(force: true);
        expect(reinstall.state, EngineCheckState.available);
        expect(reinstall.tag, newest.tag);
      },
    );

    test(
      'a legacy install is only replaced after the signed pack is promoted',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair, tag: 'engine-b12510');
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        final dir = p.join(root.path, release.tag);
        final legacyBytes = utf8.encode('legacy bridge bytes');
        File(p.join(dir, _cpuDll)).writeAsBytesSync(legacyBytes);
        File(p.join(dir, installedManifestName)).deleteSync();
        File(p.join(dir, installedSignatureName)).deleteSync();
        await up.prepare();
        expect(up.needsMigration, isTrue);
        expect((await up.check(force: true)).tag, release.tag);
        expect((await up.download()).state, EngineDownloadState.done);

        // The marker cannot be switched: the legacy folder must survive, and
        // the moved-aside copy is put back.
        final marker = File(p.join(root.path, 'active.json'));
        marker.deleteSync();
        Directory(marker.path).createSync();
        await expectLater(up.activate(), throwsA(isA<FileSystemException>()));
        expect(File(p.join(dir, _cpuDll)).readAsBytesSync(), legacyBytes);
        expect(Directory('$dir.legacy').existsSync(), isFalse);
        // The half-promoted folder is moved aside, never deleted first, and
        // removed once the legacy install is back (P3-1).
        expect(Directory('$dir.broken').existsSync(), isFalse);
        expect(up.needsMigration, isTrue);

        // With the marker writable again the replacement is promoted first and
        // the legacy folder is deleted only afterwards.
        Directory(marker.path).deleteSync();
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        expect(
          File(p.join(dir, _cpuDll)).readAsBytesSync(),
          utf8.encode('cpu bridge ${release.tag}'),
        );
        expect(Directory('$dir.legacy').existsSync(), isFalse);
        expect(up.needsMigration, isFalse);
        expect(up.verifiedPackDir(), dir);
      },
    );

    test(
      'a failed restore puts the half-promoted pack aside for the next start',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({})
          ..add(release)
          ..publish([release.releaseJson]);
        await installed(server, publicKey: key.publicKey);
        // A restore that cannot delete the half-promoted folder in place moves
        // it to `<tag>.broken` and schedules it (P3-1).
        final broken = Directory(p.join(root.path, '${release.tag}.broken'))
          ..createSync();
        File(p.join(broken.path, _cpuDll)).writeAsStringSync('half removed');
        final scheduled = File('${broken.path}$deleteOnStartSuffix')
          ..writeAsStringSync('');
        await updater(server, publicKey: key.publicKey).prepare();
        expect(broken.existsSync(), isFalse);
        expect(scheduled.existsSync(), isFalse);
        expect(Directory(p.join(root.path, release.tag)).existsSync(), isTrue);
      },
    );

    test('two unfinished loads revert to the bundled engine', () async {
      final key = await _testKey();
      final release = await _release(key.keyPair);
      final server = _Server({});
      server.add(release);
      server.publish([release.releaseJson]);
      final up = await installed(server, publicKey: key.publicKey);
      expect(up.activePackDir(), isNotNull);
      expect(up.revertedNotice, isFalse);

      up.markLoadStarted();
      up.markLoadSucceeded();
      expect(up.activePackDir(), isNotNull);

      up.markLoadStarted();
      expect(up.activePackDir(), isNotNull);
      up.markLoadStarted();
      expect(up.activePackDir(), isNull);
      expect(up.revertedNotice, isTrue);
      up.acknowledgeRevert();
      expect(up.revertedNotice, isFalse);
      expect(up.activePackDir(), isNull);
    });

    test(
      'a valid active.json without its folder falls back to bundled',
      () async {
        final key = await _testKey();
        final release = await _release(key.keyPair);
        final server = _Server({});
        server.add(release);
        server.publish([release.releaseJson]);
        final up = await installed(server, publicKey: key.publicKey);
        await Directory(p.join(root.path, release.tag)).delete(recursive: true);
        expect(up.activePackDir(), isNull);
      },
    );
  });

  group('loader', () {
    const pack = r'C:\engines\engine-b12510';

    test('prefers the pack DLL and skips its damage check', () {
      final skipped = <String>[];
      final opened = <String>[];
      final selected = LlamaBindings.openWindowsLibrary<String>(
        skipped: skipped,
        preferred: 'cpu',
        cpuVariant: 'avx2',
        hasAvx2: () => true,
        hasAvx512: () => false,
        environment: const {},
        packDir: pack,
        fileExists: (path) => path == '$pack\\$_cpuDll',
        checkEngineFiles: (_) => const [
          EngineFileResult(_cpuDll, EngineFileStatus.changed),
        ],
        open: (name) {
          opened.add(name);
          return name;
        },
        gpuDeviceCount: (_) => 0,
      );
      expect(selected.name, '$pack\\$_cpuDll');
      expect(opened, ['$pack\\$_cpuDll']);
      expect(skipped.any((s) => s.contains('changed')), isFalse);
    });

    test('falls back to the bundled DLL when the pack copy fails', () {
      final skipped = <String>[];
      final opened = <String>[];
      final selected = LlamaBindings.openWindowsLibrary<String>(
        skipped: skipped,
        preferred: 'cpu',
        cpuVariant: 'avx2',
        hasAvx2: () => true,
        hasAvx512: () => false,
        environment: const {},
        packDir: pack,
        fileExists: (path) => path == '$pack\\$_cpuDll',
        checkEngineFiles: (_) => const [],
        open: (name) {
          opened.add(name);
          if (name.startsWith(pack)) throw StateError('bad pack copy');
          return name;
        },
        gpuDeviceCount: (_) => 0,
      );
      expect(selected.name, LlamaBindings.windowsBridgePath(_cpuDll));
      expect(opened, [
        '$pack\\$_cpuDll',
        LlamaBindings.windowsBridgePath(_cpuDll),
      ]);
      expect(skipped.join('\n'), contains('engine pack copy failed'));
    });

    test('a damaged bundled DLL is still skipped without a pack copy', () {
      final skipped = <String>[];
      final opened = <String>[];
      final selected = LlamaBindings.openWindowsLibrary<String>(
        skipped: skipped,
        preferred: 'cpu',
        cpuVariant: 'avx2',
        hasAvx2: () => true,
        hasAvx512: () => false,
        environment: const {},
        packDir: pack,
        fileExists: (_) => false,
        checkEngineFiles: (name) => name == _cpuDll
            ? const [EngineFileResult(_cpuDll, EngineFileStatus.missing)]
            : const [],
        open: (name) {
          opened.add(name);
          return name;
        },
        gpuDeviceCount: (_) => 0,
      );
      expect(
        selected.name,
        LlamaBindings.windowsBridgePath('ondevice_llm_compat.dll'),
      );
      expect(opened, [
        LlamaBindings.windowsBridgePath('ondevice_llm_compat.dll'),
      ]);
      expect(skipped.join('\n'), contains('missing'));
    });

    test('a full pack path still names its backend and CPU variant', () {
      expect(
        LlamaBindings.windowsGpuOf('$pack\\ondevice_llm_cuda12.dll'),
        'cuda',
      );
      expect(
        LlamaBindings.windowsGpuOf('$pack\\ondevice_llm_vulkan.dll'),
        'vulkan',
      );
      expect(LlamaBindings.windowsGpuOf('$pack\\$_cpuDll'), isNull);
      expect(LlamaBindings.windowsCpuOf('$pack\\$_cpuDll'), 'avx2');
      expect(
        LlamaBindings.windowsCpuOf('$pack\\ondevice_llm_avx512.dll'),
        'avx512',
      );
      expect(
        LlamaBindings.windowsCpuOf('$pack\\ondevice_llm_compat.dll'),
        'compat',
      );
    });

    test('a pack file outside the signed manifest is never opened', () {
      final listed = _ListedPack(pack, {_cpuDll: 'a' * 64});
      expect(LlamaBindings.packBridgeSha256(listed, pack, _cpuDll), 'a' * 64);
      // Exactly what a file added to a verified folder after the shape check
      // sees: no digest, so the open refuses it instead of mapping it
      // unverified (P1-1).
      expect(
        () => LlamaBindings.packBridgeSha256(listed, pack, _cudaDll),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('signed manifest'),
          ),
        ),
      );
      // Without a pack the loader is on the bundled path and passes no digest.
      expect(
        () => LlamaBindings.packBridgeSha256(null, pack, _cpuDll),
        throwsStateError,
      );
    });
  });
}

/// A pack loader whose signed manifest lists exactly [files], so the loader
/// gate can be tested without a real signed release.
class _ListedPack implements EnginePackLoader {
  _ListedPack(this.dir, this.files);

  final String dir;
  final Map<String, String> files;

  @override
  String? get rootPath => dir;

  @override
  int? get cudaMajor => null;

  @override
  List<String> get unavailableFiles => const [];

  @override
  String? activePackDir() => dir;

  @override
  String? verifiedPackDir() => dir;

  @override
  String? expectedFileSha256(String dir, String name) =>
      files[name.toLowerCase()];

  @override
  bool markLoadStarted() => true;

  @override
  void markLoadSucceeded() {}
}

/// Runs in a throwaway isolate: records one crash attempt through the real
/// loader, so the test covers the per-isolate state temp file (P3-2).
bool _recordCrashAttempt(String root) =>
    EnginePackFiles(root).markLoadStarted();

class _RemovalErrorUpdater extends EngineUpdater {
  _RemovalErrorUpdater(Directory root) : super(root: root);

  @override
  Future<void> removeAll() async {
    await super.removeAll();
    throw const FileSystemException('cleanup denied');
  }
}

/// Reads normally; deleting the active marker fails (read-only engines folder).
class _BundledErrorUpdater extends EngineUpdater {
  _BundledErrorUpdater(Directory root) : super(root: root);

  @override
  Future<void> useBundled() async {
    throw const FileSystemException('marker denied');
  }
}

/// Holds the first prepare open, so the panel can be closed mid-refresh.
class _SlowPrepareUpdater extends EngineUpdater {
  _SlowPrepareUpdater(Directory root) : super(root: root);

  final gate = Completer<void>();

  // A pending revert notice makes the refresh read state after its last
  // await, where a disposed notifier must not be touched.
  @override
  bool get revertedNotice => true;

  @override
  Future<void> prepare() async {
    await gate.future;
    await super.prepare();
  }
}

/// Reads and downloads normally; the engines folder rejects the new pack.
class _ActivateErrorUpdater extends EngineUpdater {
  _ActivateErrorUpdater(Directory root, _Server server, String publicKey)
    : super(
        root: root,
        fetch: server.fetch,
        appVersion: '1.6.0+9',
        signingPublicKey: publicKey,
        openSmoke: _accept,
      );

  static Future<bool> _accept(String path) async => true;

  @override
  Future<bool> activate({String? tag}) async =>
      throw const FileSystemException('engines folder is read-only');
}

class _SmokeProcess implements Process {
  final exited = Completer<int>();
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  bool killed = false;
  bool reapOnKill = true;
  @override
  int get pid => 42;
  @override
  Future<int> get exitCode => exited.future;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!reapOnKill) return true;
    Timer(const Duration(milliseconds: 10), () async {
      exited.complete(1);
      await out.close();
      await err.close();
    });
    return true;
  }
}

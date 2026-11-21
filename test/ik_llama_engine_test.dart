import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/engine_versions.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_pack.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_update_controller.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_update_panel.dart';
import 'package:ondevice_llm/desktop/engine_updater/engine_updater.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/models/presentation/screens/model_details_page.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/inference/engine/engine_descriptor.dart';
import 'package:ondevice_llm/inference/engine/engine_registry.dart';
import 'package:ondevice_llm/inference/engine/engine_registry_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _releasesApi =
    'https://api.github.com/repos/sebytzr16/on-device-llm/releases?per_page=30';
const _assetRoot =
    'https://github.com/sebytzr16/on-device-llm/releases/download/';
const _assetBase = 'ik-engine-pack-windows-x64';
const _cpuDll = 'ondevice_llm.dll';

ModelInfo model(String name) => ModelInfo(
  id: 'mini',
  displayName: 'Model',
  fileName: name,
  sizeBytes: 0,
  family: ModelFamily.other,
  quantization: ModelQuantization.unknown,
);

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

Future<({SimpleKeyPair keyPair, String publicKey})> _testKey() async {
  final seed = List<int>.generate(32, (i) => i + 3);
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

/// One signed ik_llama.cpp pack as the updater sees it on GitHub.
class _Pack {
  _Pack(this.tag, this.manifest, this.signature, this.zip);

  final String tag;
  final Uint8List manifest;
  final Uint8List signature;
  final Uint8List zip;

  String _url(String asset) => '$_assetRoot$tag/$asset';

  Map<String, dynamic> get releaseJson => {
    'tag_name': tag,
    'assets': [
      for (final name in [
        '$_assetBase.json',
        '$_assetBase.json.sig',
        '$_assetBase.zip',
      ])
        {'name': name, 'size': 1, 'browser_download_url': _url(name)},
    ],
  };

  Map<String, List<int>> get routes => {
    _url('$_assetBase.json'): manifest,
    _url('$_assetBase.json.sig'): signature,
    _url('$_assetBase.zip'): zip,
  };
}

/// A commit tag that is guaranteed not to be the compiled pin.
String _otherCommitTag() {
  final pin = EnginePins.ikLlamaTag;
  final last = pin.substring(pin.length - 1);
  return '${pin.substring(0, pin.length - 1)}${last == 'f' ? 'e' : 'f'}';
}

Future<_Pack> _pack(
  SimpleKeyPair keyPair, {
  String? tag,
  String? engine,
  Object? kind = 'ik_llama',
  int? revision,
  String zipSha256Override = '',
  Map<String, List<int>>? contents,
}) async {
  // Never hard-code the pin: the fixture follows the compiled constant, so a
  // real pin keeps working, and a second commit comes from an explicit tag.
  final packTag = tag ?? EnginePins.ikLlamaTag;
  final tagCommit = EnginePackKind.ikLlama.parseTag(packTag)!.engine;
  final fullCommit = EnginePins.ikLlamaCommit.startsWith(tagCommit)
      ? EnginePins.ikLlamaCommit
      : tagCommit.padRight(40, '0');
  final files = contents ?? {_cpuDll: utf8.encode('ik bridge $packTag')};
  final zip = _zipOf(files);
  final manifest = <String, dynamic>{
    'version': 1,
    'kind': kind,
    'engine': engine ?? fullCommit,
    'revision':
        revision ?? EnginePackKind.ikLlama.parseTag(packTag)?.revision ?? 0,
    'bridgeApi': kEngineBridgeApi,
    'minApp': '1.0.0',
    'files': [
      for (final entry in files.entries)
        {
          'name': entry.key,
          'size': entry.value.length,
          'sha256': _sha(entry.value),
        },
    ],
    'zipSha256': zipSha256Override.isEmpty ? _sha(zip) : zipSha256Override,
  };
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
  final signature = Uint8List.fromList(
    (await Ed25519().sign(bytes, keyPair: keyPair)).bytes,
  );
  return _Pack(packTag, bytes, signature, zip);
}

/// Offline stand-in for the releases API and its assets.
class _Server {
  final Map<String, List<int>> routes = {};

  void add(_Pack pack) => routes.addAll(pack.routes);

  void publish(List<Map<String, dynamic>> releases) {
    routes[_releasesApi] = utf8.encode(jsonEncode(releases));
  }

  Future<EngineHttpResponse> fetch(Uri uri, {String? range}) async {
    final body = routes[uri.toString()];
    if (body == null) return const EngineHttpResponse(404);
    return EngineHttpResponse(200, body: Stream.value(body));
  }
}

/// Answers the ik install press with a fixed result, so the Settings row can
/// be tested without GitHub or a real pack.
class _FixedIkController extends EngineUpdateController {
  _FixedIkController(this.result, {EngineUpdateView? view})
    : view = view ?? const EngineUpdateView();
  final EngineCheckResult result;
  final EngineUpdateView view;
  int installs = 0;

  @override
  EngineUpdateView build() => view;

  @override
  Future<EngineCheckResult> checkIkEnginePack({bool install = false}) async {
    installs++;
    return result;
  }
}

/// Details-page provider stub: opening the real manager would open the app
/// database in a widget test.
class _EmptyModels extends ModelManagerNotifier {
  _EmptyModels(this.catalogModel);
  final ModelInfo catalogModel;

  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [catalogModel]);
  }
}

Future<void> _pumpPanel(
  WidgetTester tester,
  _FixedIkController controller, {
  required bool ikAvailable,
  EngineUpdater? ikUpdater,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineUpdateProvider.overrideWith(() => controller),
        ikEngineAvailableProvider.overrideWithValue(ikAvailable),
        if (ikUpdater != null)
          ikEngineUpdaterProvider.overrideWithValue(ikUpdater),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: EngineUpdatePanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ik_llama_test');
  });

  tearDown(() async {
    LlamaBindings.ikEnginePack = null;
    LlamaBindings.enginePack = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('descriptor', () {
    test('is Windows-only, signed-pack and never the format default', () {
      final windows = EngineRegistry(platform: 'windows');
      final android = EngineRegistry(platform: 'android');

      expect(ikLlamaCppEngine.id, 'ik_llama');
      expect(ikLlamaCppEngine.distribution, EngineDistribution.signedPack);
      expect(ikLlamaCppEngine.platforms, {'windows'});
      expect(windows.resolve(model('m.gguf')), llamaCppEngine);
      expect(android.resolve(model('m.gguf')), llamaCppEngine);
      expect(android.isAvailable(ikLlamaCppEngine), isFalse);
    });

    test('declares the capabilities the bridge really has with it', () {
      final caps = ikLlamaCppEngine.capabilities;

      expect(
        caps.streaming && caps.cancel && caps.tools && caps.grammar,
        isTrue,
      );
      expect(caps.vision || caps.hosting || caps.optimize, isFalse);
      expect(caps.helpers, EngineHelperMode.unavailable);
      expect(caps.loadKeys, isNot(contains('speculationMode')));
      expect(caps.loadKeys, isNot(contains('mtp')));
      expect(caps.loadKeys, isNot(contains('visionEnabled')));
      expect(caps.samplingKeys, isNot(contains('xtcProbability')));
    });
  });

  group('registry', () {
    test('resolves ik_llama only when its pack is installed and chosen', () {
      final installed = EngineRegistry(
        platform: 'windows',
        installedPacks: {ikLlamaEngineId},
      );
      final missing = EngineRegistry(platform: 'windows');

      expect(installed.isAvailable(ikLlamaCppEngine), isTrue);
      // Available, but still not the default for a GGUF.
      expect(installed.resolve(model('m.gguf')), llamaCppEngine);
      expect(
        installed.resolve(model('m.gguf'), overrideId: ikLlamaEngineId),
        ikLlamaCppEngine,
      );
      // Missing pack: the stale choice falls back to llama.cpp.
      expect(missing.isAvailable(ikLlamaCppEngine), isFalse);
      expect(
        missing.resolve(model('m.gguf'), overrideId: ikLlamaEngineId),
        llamaCppEngine,
      );
    });

    test('capability-based unused-settings note covers ik_llama', () {
      final caps = ikLlamaCppEngine.capabilities;

      expect(SettingSpec.byKey('temperature')!.usedBy(caps), isTrue);
      expect(SettingSpec.byKey('contextSize')!.usedBy(caps), isTrue);
      expect(SettingSpec.byKey('toolsEnabled')!.usedBy(caps), isTrue);
      expect(SettingSpec.byKey('speculationMode')!.usedBy(caps), isFalse);
      expect(SettingSpec.byKey('visionEnabled')!.usedBy(caps), isFalse);
      expect(SettingSpec.byKey('xtcProbability')!.usedBy(caps), isFalse);
      expect(SettingSpec.byKey('nCpuMoe')!.usedBy(caps), isFalse);
      expect(SettingSpec.byKey('helperModelId')!.usedBy(caps), isFalse);
    });

    test('the provider feeds installed packs into availability', () async {
      final container = ProviderContainer(
        overrides: [
          enginePlatformProvider.overrideWithValue('windows'),
          installedEnginePacksProvider.overrideWith(
            (ref) => const <String>{ikLlamaEngineId},
          ),
        ],
      );
      addTearDown(container.dispose);
      final registry = container.read(engineRegistryProvider);
      final gguf = model('m.gguf');

      expect(registry.isAvailable(ikLlamaCppEngine), isTrue);
      expect(registry.resolve(gguf), llamaCppEngine);
      await container.read(engineOverridesProvider.notifier).ready;
      await container
          .read(engineOverridesProvider.notifier)
          .set(gguf.id, ikLlamaEngineId);
      expect(
        container.read(engineRegistryProvider).resolve(gguf),
        ikLlamaCppEngine,
      );
    });

    test('an installed pack without a choice keeps llama.cpp loaded', () {
      final container = ProviderContainer(
        overrides: [
          enginePlatformProvider.overrideWithValue('windows'),
          installedEnginePacksProvider.overrideWith(
            (ref) => const <String>{ikLlamaEngineId},
          ),
        ],
      );
      addTearDown(container.dispose);
      final registry = container.read(engineRegistryProvider);
      expect(registry.descriptorFor(model('m.gguf')).id, llamaCppEngineId);
    });
  });

  group('pack kind', () {
    test('tags, asset names and folders are kind-specific', () {
      expect(
        EnginePackKind.llamaCpp.manifestAsset,
        'engine-pack-windows-x64.json',
      );
      expect(
        EnginePackKind.ikLlama.manifestAsset,
        'ik-engine-pack-windows-x64.json',
      );
      expect(EnginePackKind.ikLlama.folder, 'ik_llama');
      expect(EnginePackKind.ikLlama.parseTag('ik-0123abc-2'), (
        engine: '0123abc',
        revision: 2,
      ));
      expect(EnginePackKind.ikLlama.parseTag('engine-b12503'), isNull);
      expect(EnginePackKind.llamaCpp.parseTag('ik-0123abc'), isNull);
      expect(
        EnginePackKind.ikLlama.compareTags('ik-0123abc-2', 'ik-0123abc'),
        greaterThan(0),
      );
    });

    test('a manifest of the wrong kind is rejected', () {
      Uint8List withKind(Object? kind) => Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'kind': kind,
            'engine': kind == null ? 'b9000' : '0123abc'.padRight(40, '0'),
            'bridgeApi': 1,
            'minApp': '1.0.0',
            'files': [
              {'name': _cpuDll, 'size': 1, 'sha256': 'a' * 64},
            ],
            'zipSha256': 'b' * 64,
          }),
        ),
      );

      expect(
        EnginePackManifest.parse(withKind('ik_llama')).kind,
        EnginePackKind.ikLlama,
      );
      expect(
        EnginePackManifest.parse(withKind(null)).kind,
        EnginePackKind.llamaCpp,
      );
      expect(
        () => EnginePackManifest.parse(withKind('some-other-engine')),
        throwsFormatException,
      );
    });

    test('an ik manifest requires a full commit', () {
      Uint8List engine(String value) => Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'kind': 'ik_llama',
            'engine': value,
            'bridgeApi': 1,
            'minApp': '1.0.0',
            'files': [
              {'name': _cpuDll, 'size': 1, 'sha256': 'a' * 64},
            ],
            'zipSha256': 'b' * 64,
          }),
        ),
      );

      final commit = '0123abc'.padRight(40, '0');
      expect(EnginePackManifest.parse(engine(commit)).engine, commit);
      expect(
        () => EnginePackManifest.parse(engine('0123abc')),
        throwsFormatException,
      );
      expect(
        () => EnginePackManifest.parse(engine('b12503')),
        throwsFormatException,
      );
    });
  });

  group('updater', () {
    EngineUpdater updater(
      _Server server, {
      required String publicKey,
      String? pinnedTag,
    }) => EngineUpdater(
      kind: EnginePackKind.ikLlama,
      root: root,
      fetch: server.fetch,
      appVersion: '1.6.0+9',
      signingPublicKey: publicKey,
      pinnedTag: pinnedTag,
      openSmoke: (_) async => true,
    );

    test(
      'installs an ik pack in its own folder and leaves llama.cpp alone',
      () async {
        final key = await _testKey();
        final pack = await _pack(key.keyPair);
        final server = _Server()
          ..add(pack)
          ..publish([pack.releaseJson]);
        final up = updater(server, publicKey: key.publicKey);

        expect((await up.check()).state, EngineCheckState.available);
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);
        expect(up.activePackDir(), endsWith(p.join('ik_llama', pack.tag)));
        expect(
          Directory(p.join(root.path, 'ik_llama', pack.tag)).existsSync(),
          isTrue,
        );
        // The llama.cpp updater must not see the ik pack as installed.
        expect(EnginePackFiles(root.path).activePackDir(), isNull);
        expect(
          EnginePackFiles(
            p.join(root.path, EnginePackKind.ikLlama.folder),
            kind: EnginePackKind.ikLlama,
          ).activePackDir(),
          up.activePackDir(),
        );
      },
    );

    test('ignores tags from another commit and the wrong kind', () async {
      final key = await _testKey();
      final otherCommit = await _pack(key.keyPair, tag: _otherCommitTag());
      final wrongKind = await _pack(
        key.keyPair,
        tag: EnginePins.ikLlamaTag,
        kind: 'llama.cpp',
        engine: 'b9999',
      );
      final server = _Server()
        ..add(otherCommit)
        ..add(wrongKind)
        ..publish([otherCommit.releaseJson, wrongKind.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);

      expect((await up.check()).state, EngineCheckState.upToDate);
      expect(up.activePackDir(), isNull);
    });

    test(
      'a pin bump rejects the installed commit and offers the new pack',
      () async {
        final key = await _testKey();
        final oldCommit = 'f' * 40;
        final newCommit = '0123456'.padRight(40, '0');
        final oldPack = await _pack(key.keyPair, tag: 'ik-$oldCommit');
        final server = _Server()
          ..add(oldPack)
          ..publish([oldPack.releaseJson]);
        final old = updater(
          server,
          publicKey: key.publicKey,
          pinnedTag: oldPack.tag,
        );
        expect((await old.check()).state, EngineCheckState.available);
        expect((await old.download()).state, EngineDownloadState.done);
        expect(await old.activate(), isTrue);
        expect(old.verifiedPackDir(), isNotNull);

        final next = await _pack(key.keyPair, tag: 'ik-$newCommit');
        server
          ..add(next)
          ..publish([next.releaseJson]);
        final bumped = updater(
          server,
          publicKey: key.publicKey,
          pinnedTag: next.tag,
        );
        await bumped.prepare();
        expect(bumped.verifiedPackDir(), isNull);
        expect((await bumped.check(force: true)).tag, next.tag);
      },
    );

    test(
      'a matching tag prefix cannot substitute for the signed full pin',
      () async {
        final key = await _testKey();
        final commit = EnginePins.llamaCppCommit;
        final prefix = commit.substring(0, 7);
        final wrong = await _pack(
          key.keyPair,
          tag: 'ik-$prefix-2',
          engine: prefix.padRight(40, '0'),
        );
        final correct = await _pack(key.keyPair, tag: 'ik-$commit');
        final server = _Server()
          ..add(wrong)
          ..add(correct)
          ..publish([wrong.releaseJson, correct.releaseJson]);
        final up = updater(
          server,
          publicKey: key.publicKey,
          pinnedTag: correct.tag,
        );
        expect((await up.check()).tag, correct.tag);
      },
    );

    test('revision ordering wins over commit prefix length', () async {
      final key = await _testKey();
      final commit = EnginePins.ikLlamaCommit;
      final short = await _pack(key.keyPair, tag: '${EnginePins.ikLlamaTag}-9');
      final long = await _pack(key.keyPair, tag: 'ik-$commit-1');
      final server = _Server()
        ..add(short)
        ..add(long)
        ..publish([long.releaseJson, short.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).tag, short.tag);
      expect((await up.download()).state, EngineDownloadState.done);
      expect(await up.activate(), isTrue);
      server.publish([long.releaseJson]);
      expect((await up.check(force: true)).state, EngineCheckState.upToDate);
    });

    test('compareTags is a consistent total order across commit prefixes', () {
      const kind = EnginePackKind.ikLlama;
      const pin = '0123456789abcdef0123456789abcdef01234567';
      const short = 'ik-0123456-9';
      final long = 'ik-$pin-1';
      // Same pinned commit named by a short and the full prefix: revision 9
      // outranks revision 1 even though the shorter string sorts differently.
      expect(kind.compareTags(short, long, pin: pin), greaterThan(0));
      expect(kind.compareTags(long, short, pin: pin), lessThan(0));
      expect(kind.compareTags(short, short, pin: pin), 0);
      // Different commits sharing a prefix are never "the same commit": the
      // comparator stays antisymmetric and transitive without a pin.
      const a = 'ik-0123456-9';
      const b = 'ik-01234567-1';
      const c = 'ik-012345678-1';
      for (final pair in [
        [a, b],
        [b, c],
        [a, c],
      ]) {
        final forward = kind.compareTags(pair[0], pair[1]);
        final backward = kind.compareTags(pair[1], pair[0]);
        expect(forward.sign, -backward.sign, reason: '${pair[0]} / ${pair[1]}');
      }
      expect(kind.compareTags(a, b), lessThan(0));
      expect(kind.compareTags(b, c), lessThan(0));
      expect(kind.compareTags(a, c), lessThan(0));
    });

    test(
      'installed verification rejects changed DLLs and an unsigned manifest',
      () async {
        final key = await _testKey();
        final pack = await _pack(key.keyPair);
        final server = _Server()
          ..add(pack)
          ..publish([pack.releaseJson]);
        final up = updater(server, publicKey: key.publicKey);
        expect((await up.check()).tag, pack.tag);
        expect((await up.download()).state, EngineDownloadState.done);
        expect(await up.activate(), isTrue);

        // A new worker has no trusted in-memory state until it checks the signature.
        final dir = up.activePackDir()!;
        final files = EnginePackFiles(
          p.dirname(dir),
          kind: EnginePackKind.ikLlama,
          signingPublicKey: key.publicKey,
          appVersion: '1.6.0+9',
        );
        expect(files.verifiedPackDir(), isNull);
        await files.prepare();
        expect(files.verifiedPackDir(), dir);

        final extra = File(p.join(dir, 'unsigned.dll'))
          ..writeAsStringSync('extra');
        expect(files.verifiedPackDir(), isNull);
        extra.deleteSync();
        expect(files.verifiedPackDir(), dir);

        final changed = utf8.encode('replacement bridge');
        File(p.join(dir, _cpuDll)).writeAsBytesSync(changed);
        expect(files.verifiedPackDir(), isNull);
        final forged = jsonDecode(utf8.decode(pack.manifest)) as Map;
        forged['files'] = [
          {'name': _cpuDll, 'size': changed.length, 'sha256': _sha(changed)},
        ];
        File(
          p.join(dir, installedManifestName),
        ).writeAsStringSync(jsonEncode(forged));
        expect(files.verifiedPackDir(), isNull);
        await files.prepare();
        expect(files.verifiedPackDir(), isNull);
        expect((await up.check(force: true)).tag, pack.tag);
      },
    );

    test('a re-signed manifest still rejects a changed DLL', () async {
      final key = await _testKey();
      final pack = await _pack(key.keyPair);
      final server = _Server()
        ..add(pack)
        ..publish([pack.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);
      expect((await up.check()).tag, pack.tag);
      expect((await up.download()).state, EngineDownloadState.done);
      expect(await up.activate(), isTrue);
      final dir = up.activePackDir()!;

      // Same-size content change: only the DLL hash can catch it.
      final original = File(p.join(dir, _cpuDll)).readAsBytesSync();
      File(
        p.join(dir, _cpuDll),
      ).writeAsBytesSync(List<int>.filled(original.length, 0x41));
      // Re-sign the original manifest with the test key, so the signature is
      // valid but the listed DLL hash no longer matches.
      final signature = Uint8List.fromList(
        (await Ed25519().sign(pack.manifest, keyPair: key.keyPair)).bytes,
      );
      File(p.join(dir, installedManifestName)).writeAsBytesSync(pack.manifest);
      File(p.join(dir, installedSignatureName)).writeAsBytesSync(signature);

      final files = EnginePackFiles(
        p.dirname(dir),
        kind: EnginePackKind.ikLlama,
        signingPublicKey: key.publicKey,
        appVersion: '1.6.0+9',
      );
      await files.prepare();
      expect(files.verifiedPackDir(), isNull);
    });

    test(
      'crash guard restores the previous verified pack and offers a newer revision',
      () async {
        final key = await _testKey();
        final tag = EnginePins.ikLlamaTag;
        final previous = await _pack(key.keyPair, tag: '$tag-1');
        final failed = await _pack(key.keyPair, tag: '$tag-2');
        final newer = await _pack(key.keyPair, tag: '$tag-3');
        final server = _Server()
          ..add(previous)
          ..add(failed)
          ..add(newer);
        var now = DateTime.utc(2026, 11, 20);
        EngineUpdater makeUpdater() => EngineUpdater(
          kind: EnginePackKind.ikLlama,
          root: root,
          fetch: server.fetch,
          appVersion: '1.6.0+9',
          signingPublicKey: key.publicKey,
          openSmoke: (_) async => true,
          clock: () => now,
        );
        final up = makeUpdater();

        Future<void> install(EngineUpdater updater, _Pack pack) async {
          server.publish([pack.releaseJson]);
          expect((await updater.check(force: true)).tag, pack.tag);
          expect((await updater.download()).state, EngineDownloadState.done);
          expect(await updater.activate(), isTrue);
        }

        // A model load that never finishes, through the real guard the loader
        // uses (one count per load, not one per manual state write).
        void unfinishedLoad() {
          final guard = EnginePackLoadGuard(LlamaBindings.ikEnginePack!);
          guard.selected = true;
          guard.beforeModelLoad();
        }

        await install(up, previous);
        await install(up, failed);
        unfinishedLoad();
        unfinishedLoad();

        final marker = File(p.join(root.path, 'ik_llama', 'active.json'));
        final before = marker.readAsStringSync();
        final racing = EnginePackFiles(
          p.dirname(marker.path),
          kind: EnginePackKind.ikLlama,
          signingPublicKey: key.publicKey,
          beforeCrashRollback: marker.deleteSync,
        );
        await racing.prepare();
        expect(racing.verifiedPackDir(), isNull);
        expect(marker.existsSync(), isFalse);
        marker.writeAsStringSync(before);

        final restarted = makeUpdater();
        await restarted.prepare();
        expect(restarted.verifiedPackDir(), endsWith(previous.tag));
        expect(restarted.revertedNotice, isTrue);
        now = now.add(const Duration(days: 2));
        server.publish([previous.releaseJson, failed.releaseJson]);
        expect((await restarted.check()).state, EngineCheckState.upToDate);
        await install(restarted, newer);
        expect(restarted.verifiedPackDir(), endsWith(newer.tag));
        unfinishedLoad();
        unfinishedLoad();
        expect(restarted.verifiedPackDir(), endsWith(previous.tag));
      },
    );

    test('rejects a zip that does not match its signed checksum', () async {
      final key = await _testKey();
      final pack = await _pack(key.keyPair, zipSha256Override: 'c' * 64);
      final server = _Server()
        ..add(pack)
        ..publish([pack.releaseJson]);
      final up = updater(server, publicKey: key.publicKey);

      expect((await up.check()).state, EngineCheckState.available);
      expect((await up.download()).state, EngineDownloadState.error);
      expect(up.activePackDir(), isNull);
    });
  });

  group('pin', () {
    test('only a real commit counts as the pin', () {
      expect(EnginePins.isPinnedCommit('0' * 40), isFalse);
      expect(EnginePins.isPinnedCommit(EnginePins.llamaCppCommit), isTrue);
      expect(
        EnginePins.ikLlamaPinned,
        EnginePins.isPinnedCommit(EnginePins.ikLlamaCommit),
      );
    });

    test('the packager refuses the default llama.cpp stage dir', () {
      final script = File('scripts/package-engine-pack.ps1').readAsStringSync();
      final build = File('scripts/build-ik-llama.ps1').readAsStringSync();

      // Explicit -StageDir plus a marker from the ik build script: DLLs from
      // native/out/windows-x64 can never be signed as an ik pack.
      expect(script, contains("PSBoundParameters.ContainsKey('StageDir')"));
      expect(script, contains('.commit.json'));
      expect(script, contains('bundled llama.cpp stage dir'));
      expect(build, contains('.commit.json'));
    });
  });

  group('controller', () {
    test(
      'an ik pack installed in its folder is published to the registry',
      () async {
        final key = await _testKey();
        final pack = await _pack(key.keyPair);
        final server = _Server()
          ..add(pack)
          ..publish([pack.releaseJson]);
        final ik = EngineUpdater(
          kind: EnginePackKind.ikLlama,
          root: root,
          fetch: server.fetch,
          appVersion: '1.6.0+9',
          signingPublicKey: key.publicKey,
          openSmoke: (_) async => true,
        );
        expect((await ik.check(force: true)).state, EngineCheckState.available);
        expect((await ik.download()).state, EngineDownloadState.done);
        expect(await ik.activate(), isTrue);

        final container = ProviderContainer(
          overrides: [
            ikEngineAvailableProvider.overrideWithValue(true),
            ikEngineUpdaterProvider.overrideWithValue(ik),
            engineUpdaterProvider.overrideWithValue(EngineUpdater(root: root)),
          ],
        );
        addTearDown(container.dispose);
        await container.read(engineUpdateProvider.notifier).checkIkEnginePack();

        // The folder join is the controller's: the set must contain ik_llama
        // (its own folder) and not llama.cpp (the default engines root).
        expect(
          container.read(installedEnginePacksProvider),
          contains(ikLlamaEngineId),
        );
        expect(
          container.read(installedEnginePacksProvider),
          isNot(contains(llamaCppEngineId)),
        );
      },
    );

    test('an unpinned ik pack check returns the reason, not silence', () async {
      final container = ProviderContainer(
        overrides: [
          ikEngineAvailableProvider.overrideWithValue(false),
          engineUpdaterProvider.overrideWithValue(EngineUpdater(root: root)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(engineUpdateProvider.notifier)
          .checkIkEnginePack(install: true);
      expect(result.state, EngineCheckState.error);
      expect(result.message, contains('pinned'));
    });

    test(
      'an unverified installed pack is reported, not silently swapped',
      () async {
        final key = await _testKey();
        final pack = await _pack(key.keyPair);
        final server = _Server()
          ..add(pack)
          ..publish([pack.releaseJson]);
        final ik = EngineUpdater(
          kind: EnginePackKind.ikLlama,
          root: root,
          fetch: server.fetch,
          appVersion: '1.6.0+9',
          signingPublicKey: key.publicKey,
          openSmoke: (_) async => true,
        );
        expect((await ik.check(force: true)).state, EngineCheckState.available);
        expect((await ik.download()).state, EngineDownloadState.done);
        expect(await ik.activate(), isTrue);
        final dir = ik.activePackDir()!;
        // A pack installed by an earlier build has only the marker.
        File(p.join(dir, installedManifestName)).deleteSync();
        File(p.join(dir, installedSignatureName)).deleteSync();

        final container = ProviderContainer(
          overrides: [
            ikEngineAvailableProvider.overrideWithValue(true),
            ikEngineUpdaterProvider.overrideWithValue(ik),
            engineUpdaterProvider.overrideWithValue(EngineUpdater(root: root)),
          ],
        );
        addTearDown(container.dispose);
        await container.read(engineUpdateProvider.notifier).checkIkEnginePack();
        final view = container.read(engineUpdateProvider);
        expect(view.unverified, isTrue);
        expect(view.installed, isNull);
        expect(
          container.read(installedEnginePacksProvider),
          isNot(contains(ikLlamaEngineId)),
        );
      },
    );

    test('a reverted ik pack stops being offered to the registry', () async {
      final key = await _testKey();
      final pack = await _pack(key.keyPair);
      final server = _Server()
        ..add(pack)
        ..publish([pack.releaseJson]);
      final ik = EngineUpdater(
        kind: EnginePackKind.ikLlama,
        root: root,
        fetch: server.fetch,
        appVersion: '1.6.0+9',
        signingPublicKey: key.publicKey,
        openSmoke: (_) async => true,
      );
      await ik.check(force: true);
      await ik.download();
      expect(await ik.activate(), isTrue);

      final container = ProviderContainer(
        overrides: [
          ikEngineAvailableProvider.overrideWithValue(true),
          ikEngineUpdaterProvider.overrideWithValue(ik),
          engineUpdaterProvider.overrideWithValue(EngineUpdater(root: root)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(engineUpdateProvider.notifier).checkIkEnginePack();
      expect(
        container.read(installedEnginePacksProvider),
        contains(ikLlamaEngineId),
      );

      // Two unfinished loads trip the crash guard: the pack can no longer
      // open, so the next load failure must drop it from the registry.
      ik.markLoadStarted();
      ik.markLoadStarted();
      expect(ik.activePackDir(), isNull);
      await container.read(engineUpdateProvider.notifier).noteIkLoadFailure();
      expect(
        container.read(installedEnginePacksProvider),
        isNot(contains(ikLlamaEngineId)),
      );
    });
  });

  group('settings row', () {
    testWidgets('stays hidden until the pin is real', (tester) async {
      await _pumpPanel(
        tester,
        _FixedIkController(const EngineCheckResult(EngineCheckState.upToDate)),
        ikAvailable: false,
      );
      expect(find.byKey(const Key('engine-update-ik')), findsNothing);
    });

    testWidgets('installs on press and shows the returned error', (
      tester,
    ) async {
      final controller = _FixedIkController(
        const EngineCheckResult(
          EngineCheckState.error,
          message: 'The ik_llama.cpp pack download failed.',
        ),
      );
      await _pumpPanel(tester, controller, ikAvailable: true);
      expect(find.byKey(const Key('engine-update-ik')), findsOneWidget);

      await tester.tap(find.byKey(const Key('engine-update-ik')));
      await tester.pumpAndSettle();

      expect(controller.installs, 1);
      expect(
        find.text('The ik_llama.cpp pack download failed.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the verified ik pack the controller reports', (
      tester,
    ) async {
      // The row has no state of its own: an install from anywhere (startup,
      // another window's refresh) must show up without a click (P3 re-review).
      final controller = _FixedIkController(
        const EngineCheckResult(EngineCheckState.upToDate),
        view: const EngineUpdateView(ikInstalled: 'ik-1234567'),
      );
      await _pumpPanel(tester, controller, ikAvailable: true);

      expect(controller.installs, 0);
      expect(find.text('Installed pack: ik-1234567'), findsOneWidget);
    });

    testWidgets('shows the ik reinstall notice from the controller', (
      tester,
    ) async {
      final controller = _FixedIkController(
        const EngineCheckResult(EngineCheckState.upToDate),
        view: const EngineUpdateView(ikUnverified: true),
      );
      await _pumpPanel(tester, controller, ikAvailable: true);

      expect(find.textContaining('could not be verified'), findsOneWidget);
    });
  });

  group('model details', () {
    test('offers the optional engine only when the app knows its build', () {
      final installed = EngineRegistry(
        platform: 'windows',
        installedPacks: {ikLlamaEngineId},
      );
      final gguf = model('m.gguf');

      expect(
        offerableEngines(
          installed,
          gguf,
          optionalEngines: false,
        ).map((e) => e.id),
        [llamaCppEngineId],
      );
      expect(
        offerableEngines(
          installed,
          gguf,
          optionalEngines: true,
        ).map((e) => e.id),
        [llamaCppEngineId, ikLlamaEngineId],
      );
    });

    test('a model engine choice survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer(
        overrides: [enginePlatformProvider.overrideWithValue('windows')],
      );
      addTearDown(first.dispose);
      await first.read(engineOverridesProvider.notifier).ready;
      await first
          .read(engineOverridesProvider.notifier)
          .set('mini', ikLlamaEngineId);

      final second = ProviderContainer(
        overrides: [
          enginePlatformProvider.overrideWithValue('windows'),
          installedEnginePacksProvider.overrideWith(
            (ref) => const <String>{ikLlamaEngineId},
          ),
        ],
      );
      addTearDown(second.dispose);
      await second.read(engineOverridesProvider.notifier).ready;

      expect(second.read(engineOverridesProvider), {'mini': ikLlamaEngineId});
      expect(
        second.read(engineRegistryProvider).descriptorFor(model('m.gguf')),
        ikLlamaCppEngine,
      );
    });

    testWidgets('the install hint sits on the disabled engine entry', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final gguf = model('m.gguf');
      final container = ProviderContainer(
        overrides: [
          enginePlatformProvider.overrideWithValue('windows'),
          ikEngineAvailableProvider.overrideWithValue(true),
          modelManagerProvider.overrideWith(() => _EmptyModels(gguf)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(modelProfilesProvider.notifier).ready;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ModelDetailsPage(model: gguf),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-engine')), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Install in Settings → Engines'), findsOneWidget);
    });
  });

  group('loading', () {
    test(
      'a signed pack is opened only after preparation and counts once',
      () async {
        if (!Platform.isWindows) return;
        final key = await _testKey();
        const compat = 'ondevice_llm_compat.dll';
        final contents = {
          _cpuDll: utf8.encode('not a PE'),
          compat: utf8.encode('not a PE either'),
        };
        final pack = await _pack(key.keyPair, contents: contents);
        final packRoot = p.join(root.path, EnginePackKind.ikLlama.folder);
        final dir = Directory(p.join(packRoot, pack.tag))
          ..createSync(recursive: true);
        for (final entry in contents.entries) {
          File(p.join(dir.path, entry.key)).writeAsBytesSync(entry.value);
        }
        File(
          p.join(dir.path, installedManifestName),
        ).writeAsBytesSync(pack.manifest);
        File(
          p.join(dir.path, installedSignatureName),
        ).writeAsBytesSync(pack.signature);
        // The marker an activation leaves behind.
        File(p.join(packRoot, 'active.json')).writeAsStringSync(
          jsonEncode({
            'tag': pack.tag,
            'dir': dir.path,
            'cudaMajor': null,
            'unavailableFiles': const <String>[],
          }),
        );
        int crashCount() {
          final file = File(p.join(packRoot, 'state.json'));
          if (!file.existsSync()) return 0;
          final state = jsonDecode(file.readAsStringSync());
          return state is Map ? (state['crashCount'] as num?)?.toInt() ?? 0 : 0;
        }

        final files = EnginePackFiles(
          packRoot,
          kind: EnginePackKind.ikLlama,
          signingPublicKey: key.publicKey,
          appVersion: '1.6.0+9',
        );
        LlamaBindings.ikEnginePack = files;
        // Not prepared in this isolate: the signature and the DLL hashes are
        // unknown, so the loader must refuse the pack before opening anything.
        expect(
          () => LlamaBindings(engineId: ikLlamaEngineId, modelLoad: true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('OD_IK_LOAD_FAILED'),
            ),
          ),
        );
        expect(crashCount(), 0);

        // The real preparation gate (signature + every DLL hash, off the calling
        // isolate) makes the same folder loadable; the compat probe and the
        // bridge attempt are one model load, so exactly one attempt is counted.
        await files.prepare();
        expect(files.verifiedPackDir(), dir.path);
        expect(
          () => LlamaBindings(engineId: ikLlamaEngineId, modelLoad: true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('OD_IK_LOAD_FAILED'),
            ),
          ),
        );
        expect(crashCount(), 1);

        // A probe/control binding must never count as an unfinished load.
        expect(
          () => LlamaBindings(engineId: ikLlamaEngineId),
          throwsA(isA<StateError>()),
        );
        expect(crashCount(), 1);
      },
    );

    test('a pack DLL changed after preparation is refused at the open', () async {
      if (!Platform.isWindows) return;
      final key = await _testKey();
      final pack = await _pack(key.keyPair);
      final packRoot = p.join(root.path, EnginePackKind.ikLlama.folder);
      final dir = Directory(p.join(packRoot, pack.tag))
        ..createSync(recursive: true);
      final original = utf8.encode('ik bridge ${pack.tag}');
      File(p.join(dir.path, _cpuDll)).writeAsBytesSync(original);
      File(
        p.join(dir.path, 'ondevice_llm_compat.dll'),
      ).writeAsBytesSync(original);
      final forged = jsonDecode(utf8.decode(pack.manifest)) as Map;
      final bridge = {
        'name': _cpuDll,
        'size': original.length,
        'sha256': _sha(original),
      };
      final compat = {
        'name': 'ondevice_llm_compat.dll',
        'size': original.length,
        'sha256': _sha(original),
      };
      forged['files'] = [bridge, compat];
      final bytes = utf8.encode(jsonEncode(forged));
      File(p.join(dir.path, installedManifestName)).writeAsBytesSync(bytes);
      File(p.join(dir.path, installedSignatureName)).writeAsBytesSync(
        (await Ed25519().sign(bytes, keyPair: key.keyPair)).bytes,
      );
      File(p.join(packRoot, 'active.json')).writeAsStringSync(
        jsonEncode({
          'tag': pack.tag,
          'dir': dir.path,
          'cudaMajor': null,
          'unavailableFiles': const <String>[],
        }),
      );
      final files = EnginePackFiles(
        packRoot,
        kind: EnginePackKind.ikLlama,
        signingPublicKey: key.publicKey,
      );
      await files.prepare();
      expect(files.verifiedPackDir(), dir.path);

      // Same size, different bytes: only the hash taken at the open can see it.
      File(
        p.join(dir.path, 'ondevice_llm_compat.dll'),
      ).writeAsBytesSync(List<int>.filled(original.length, 0x42));
      expect(
        () => LlamaBindings(engineId: ikLlamaEngineId, modelLoad: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('OD_IK_LOAD_FAILED'),
          ),
        ),
      );
    });

    test('a pack-only engine never opens the bundled llama.cpp DLLs', () {
      final opened = <String>[];
      expect(
        () => LlamaBindings.openWindowsLibrary<String>(
          skipped: [],
          environment: const {},
          fileExists: (_) => true,
          hasAvx2: () => true,
          hasAvx512: () => false,
          cpuVariant: 'auto',
          allowBundledFallback: false,
          open: (name) {
            opened.add(name);
            return name;
          },
          gpuDeviceCount: (_) => 1,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No usable CPU bridge'),
          ),
        ),
      );
      expect(opened, isEmpty);
    });

    test('a failed pack copy never falls back to a bundled DLL name', () {
      final opened = <String>[];
      final packDir = p.join(root.path, 'ik_llama', 'ik-abc1234');
      expect(
        () => LlamaBindings.openWindowsLibrary<String>(
          skipped: [],
          environment: const {},
          fileExists: (path) => path.startsWith(packDir),
          hasAvx2: () => true,
          hasAvx512: () => false,
          cpuVariant: 'auto',
          packDir: packDir,
          allowBundledFallback: false,
          open: (name) {
            opened.add(name);
            throw StateError('the pack copy is damaged');
          },
          gpuDeviceCount: (_) => 1,
        ),
        throwsA(isA<StateError>()),
      );
      expect(opened, isNotEmpty);
      expect(opened.every((name) => name.startsWith(packDir)), isTrue);
    });

    test('the worker config carries the engine and the key follows it', () {
      final config = LlamaEngine.loadConfig(
        settings: const InferenceSettings(),
        engineId: ikLlamaEngineId,
      );
      expect((jsonDecode(config) as Map)['engine'], ikLlamaEngineId);
      expect(
        (jsonDecode(LlamaEngine.loadConfig(settings: const InferenceSettings()))
            as Map)['engine'],
        llamaCppEngineId,
      );
      expect(
        nativeLibraryChoice(config, windows: true).engine,
        ikLlamaEngineId,
      );
      expect(
        nativeLibraryChoiceKey(
          backend: 'cpu',
          cpuVariant: 'auto',
          engine: ikLlamaEngineId,
        ),
        isNot(nativeLibraryChoiceKey(backend: 'cpu', cpuVariant: 'auto')),
      );
    });

    test('unsupported profile keys never reach another engine', () {
      const settings = InferenceSettings(nCpuMoe: 8, swaFull: true);
      final ik =
          jsonDecode(
                LlamaEngine.loadConfig(
                  settings: settings,
                  engineId: ikLlamaEngineId,
                ),
              )
              as Map;
      final llama =
          jsonDecode(LlamaEngine.loadConfig(settings: settings)) as Map;

      expect(ik['contextSize'], llama['contextSize']);
      expect(ik.containsKey('nCpuMoe'), isFalse);
      expect(ik.containsKey('moeCacheSizeMb'), isFalse);
      expect(ik.containsKey('swaFull'), isFalse);
      expect(ik.containsKey('speculationMode'), isFalse);
      expect(llama['nCpuMoe'], 8);
      expect(llama['swaFull'], isTrue);
    });

    test('a failed ik load resolves to the localized error', () {
      final message = modelLoadErrorMessage(
        StateError('OD_IK_LOAD_FAILED: no usable bridge'),
      );
      expect(message, isNotEmpty);
      expect(message.contains('OD_IK_LOAD_FAILED'), isFalse);
      expect(message.contains('ik_llama.cpp'), isTrue);
    });
  });
}

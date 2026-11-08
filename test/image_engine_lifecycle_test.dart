import 'package:ondevice_llm/desktop/history_store.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/image_gen_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/inference/engine/sd_engine.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() => const ModelManagerState();
}

const _request = ImageGenRequest(
  prompt: 'cat',
  negativePrompt: '',
  width: 1,
  height: 1,
  steps: 1,
  seed: 1,
  frames: 1,
  cfgScale: 1,
);

class _Engine extends SdEngine {
  _Engine({required super.invoke});
  int releases = 0;
  Completer<void>? releaseGate;
  @override
  Future<void> dispose() async {
    releases++;
    await releaseGate?.future;
    await super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  late bool previousDesktop;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('image-lifecycle-');
    previousPaths = PathProviderPlatform.instance;
    previousDesktop = DesktopHost.active;
    PathProviderPlatform.instance = _Paths(root.path);
    DesktopHost.active = false;
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    DesktopHost.active = previousDesktop;
    await root.delete(recursive: true);
  });

  ProviderContainer containerFor(SdEngine engine) => ProviderContainer(
    overrides: [
      desktopImageEngineProvider.overrideWithValue(engine),
      modelManagerProvider.overrideWith(_Models.new),
    ],
  );

  test(
    'leaving during generation waits, keeps frames, and reloads next time',
    () async {
      final pending = Completer<Object?>();
      var loads = 0;
      var generations = 0;
      final engine = _Engine(
        invoke: (op, _) async {
          if (op == 'load') {
            loads++;
            return 123;
          }
          if (++generations == 1) return pending.future;
          return [
            TransferableTypedData.fromList([
              Uint8List.fromList([0, 255, 0, 255]),
            ]),
            1,
            1,
            1,
            0,
          ];
        },
      );
      final container = containerFor(engine);
      try {
        final notifier = container.read(desktopImageGenProvider.notifier);
        notifier.pageEntered();
        final job = notifier.generate(_request);
        while (!engine.isLoaded) {
          await Future<void>.delayed(Duration.zero);
        }
        notifier.pageLeft();
        expect(engine.releases, 0);
        pending.complete([
          TransferableTypedData.fromList([
            Uint8List.fromList([255, 0, 0, 255]),
          ]),
          1,
          1,
          1,
          0,
        ]);
        await job;
        await Future<void>.delayed(Duration.zero);
        expect(engine.releases, 1);
        expect(engine.isLoaded, isFalse);
        final result = container.read(desktopImageGenProvider).result;
        final frame = container.read(desktopImageGenProvider).frames.single;
        expect(result!.rgba, [255, 0, 0, 255]);
        expect(frame.width, 1);
        notifier.pageEntered();
        expect(
          identical(
            container.read(desktopImageGenProvider).frames.single,
            frame,
          ),
          isTrue,
        );
        await notifier.generate(_request);
        expect(loads, 2);
        expect(engine.isLoaded, isTrue);
        expect(container.read(desktopImageGenProvider).result!.rgba, [
          0,
          255,
          0,
          255,
        ]);
        final store = await container.read(creationHistoryStoreProvider.future);
        final saved = await store.list();
        expect(saved, hasLength(2));
        await notifier.showHistory(saved.last);
        expect(
          container.read(desktopImageGenProvider).historyEntry?.id,
          saved.last.id,
        );
        expect(container.read(desktopImageGenProvider).frames.single.width, 1);
        await notifier.deleteHistory(saved.last);
        expect(container.read(desktopImageGenProvider).result, isNull);
        expect((await store.list()).length, 1);
      } finally {
        container.dispose();
        await engine.dispose();
      }
    },
  );

  test(
    'video history is saved before page-leave release and survives release',
    () async {
      final saving = Completer<void>();
      final permitSave = Completer<void>();
      late _Engine engine;
      engine = _Engine(
        invoke: (op, args) async {
          if (op == 'load') return 123;
          if (op == 'save') {
            expect(engine.releases, 0);
            expect(args.last, 42);
            saving.complete();
            await permitSave.future;
            await File(args.first as String).writeAsBytes([1, 2, 3]);
            return true;
          }
          return [
            TransferableTypedData.fromList([
              Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]),
            ]),
            1,
            1,
            2,
            16,
            42,
          ];
        },
      );
      final container = containerFor(engine);
      try {
        final notifier = container.read(desktopImageGenProvider.notifier);
        notifier.pageEntered();
        notifier.selectModel(
          imageGenCatalog.firstWhere((m) => m.kind == ImageGenKind.video),
        );
        final job = notifier.generate(_request);
        await saving.future;
        notifier.pageLeft();
        expect(engine.releases, 0);
        permitSave.complete();
        await job;
        await Future<void>.delayed(Duration.zero);
        expect(engine.releases, 1);
        expect(engine.isLoaded, false);
        final store = await container.read(creationHistoryStoreProvider.future);
        final item = (await store.list()).single;
        expect(item.data['kind'], 'video');
        expect(await store.media(item).readAsBytes(), [1, 2, 3]);
        expect(
          container.read(desktopImageGenProvider).historyEntry?.id,
          item.id,
        );
      } finally {
        container.dispose();
        await engine.dispose();
      }
    },
  );

  testWidgets('a new job waits for native release to finish', (tester) async {
    var loads = 0;
    final engine = _Engine(
      invoke: (op, _) async {
        if (op == 'load') {
          loads++;
          return 123;
        }
        throw StateError('Generation failed');
      },
    );
    final container = containerFor(engine);
    final notifier = container.read(desktopImageGenProvider.notifier);
    notifier.pageEntered();
    unawaited(notifier.generate(_request));
    await tester.pump();
    engine.releaseGate = Completer<void>();
    notifier.pageLeft();
    await tester.pump();
    notifier.pageEntered();
    unawaited(notifier.generate(_request));
    await tester.pump();
    expect(loads, 1);
    engine.releaseGate!.complete();
    await tester.pump();
    expect(loads, 2);
    expect(engine.isLoaded, isTrue);
    container.dispose();
    await tester.pump();
  });

  testWidgets(
    'idle timeout releases a loaded model after a failed job, never during one',
    (tester) async {
      final pending = Completer<Object?>();
      final engine = _Engine(
        invoke: (op, _) async => op == 'load' ? 123 : pending.future,
      );
      final container = containerFor(engine);
      final notifier = container.read(desktopImageGenProvider.notifier);
      notifier.pageEntered();
      unawaited(notifier.generate(_request));
      await tester.pump();
      expect(engine.isLoaded, isTrue);
      await tester.pump(const Duration(minutes: 3));
      expect(engine.releases, 0);
      pending.completeError(StateError('Generation failed'));
      await tester.pump();
      await tester.pump(const Duration(minutes: 1, seconds: 59));
      expect(engine.releases, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(engine.releases, 1);
      expect(engine.isLoaded, isFalse);
      container.dispose();
      await tester.pump();
    },
  );
}

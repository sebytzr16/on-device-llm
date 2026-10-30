import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/storage/model_folders.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp, original, target;
  late SharedPreferences preferences;
  late ModelFolders folders;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('model-folders-test-');
    original = await Directory(p.join(temp.path, 'default')).create();
    target = Directory(p.join(temp.path, 'selected'));
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    folders = ModelFolders(original, preferences, (_) async => 1 << 40);
  });
  tearDown(() async => temp.delete(recursive: true));

  test(
    'leave keeps absolute models and filename companions available after restart',
    () async {
      final model = await File(
        p.join(original.path, 'model.gguf'),
      ).writeAsString('model');
      final companion = await File(
        p.join(original.path, 'projector.gguf'),
      ).writeAsString('vision');
      final voice = await Directory(p.join(original.path, 'voice')).create();
      await folders.change(
        target,
        move: false,
        updatePaths: (_) async => fail('must preserve paths'),
      );
      folders = ModelFolders(original, preferences, (_) async => 1 << 40);
      expect(folders.current.path, target.path);
      expect((await folders.resolve('projector.gguf')).path, companion.path);
      expect(await folders.resolvePath('voice'), voice.path);
      expect(await model.readAsString(), 'model');
      expect(
        (await folders.resolve('new.gguf')).path,
        p.join(target.path, 'new.gguf'),
      );
      await folders.change(original, move: false, updatePaths: (_) async {});
      expect(folders.current.path, original.path);
    },
  );

  test(
    'move copies bytes and nested files before changing catalog paths',
    () async {
      final model = await File(
        p.join(original.path, 'model.gguf'),
      ).writeAsBytes(List.filled(200000, 7));
      final nested = File(p.join(original.path, 'voice', 'tokens.txt'));
      await nested.parent.create();
      await nested.writeAsString('tokens');
      final progress = <double>[];
      Map<String, String>? updated;
      await folders.change(
        target,
        move: true,
        onProgress: progress.add,
        updatePaths: (paths) async {
          updated = paths;
          expect(await model.exists(), isTrue);
          expect(await File(paths[model.path]!).length(), 200000);
        },
      );
      expect(updated![model.path], p.join(target.path, 'model.gguf'));
      expect(await model.exists(), isFalse);
      expect(
        await File(p.join(target.path, 'voice', 'tokens.txt')).readAsString(),
        'tokens',
      );
      expect(progress.last, 1);
      expect(folders.current.path, target.path);
    },
  );

  test(
    'catalog failure rolls back copies and preserves originals and preference',
    () async {
      final file = await File(
        p.join(original.path, 'model.gguf'),
      ).writeAsString('model');
      await expectLater(
        folders.change(
          target,
          move: true,
          updatePaths: (_) async => throw StateError('db failed'),
        ),
        throwsStateError,
      );
      expect(await file.exists(), isTrue);
      expect(folders.current.path, original.path);
      expect(await target.list().toList(), isEmpty);
    },
  );

  test(
    'space, writability and conflicting file failures preserve source data',
    () async {
      final file = await File(
        p.join(original.path, 'model.gguf'),
      ).writeAsString('model');
      folders = ModelFolders(original, preferences, (_) async => 0);
      await expectLater(
        folders.change(target, move: true, updatePaths: (_) async {}),
        throwsA(
          isA<ModelFolderException>().having(
            (e) => e.reason,
            'reason',
            ModelFolderFailure.insufficientSpace,
          ),
        ),
      );
      final blocked = await File(
        p.join(temp.path, 'not-a-directory'),
      ).writeAsString('file');
      await expectLater(
        folders.change(
          Directory(blocked.path),
          move: false,
          updatePaths: (_) async {},
        ),
        throwsA(
          isA<ModelFolderException>().having(
            (e) => e.reason,
            'reason',
            ModelFolderFailure.notWritable,
          ),
        ),
      );
      await File(p.join(target.path, 'model.gguf')).writeAsString('keep');
      await expectLater(
        folders.change(target, move: true, updatePaths: (_) async {}),
        throwsA(
          isA<ModelFolderException>().having(
            (e) => e.reason,
            'reason',
            ModelFolderFailure.conflict,
          ),
        ),
      );
      expect(await file.readAsString(), 'model');
      expect(
        await File(p.join(target.path, 'model.gguf')).readAsString(),
        'keep',
      );
    },
  );

  test(
    'moving after leave gathers the old root and can reset to default',
    () async {
      await File(p.join(original.path, 'old.gguf')).writeAsString('old');
      await folders.change(target, move: false, updatePaths: (_) async {});
      await File(p.join(target.path, 'new.gguf')).writeAsString('new');
      await folders.change(original, move: true, updatePaths: (_) async {});
      expect(
        await File(p.join(original.path, 'old.gguf')).readAsString(),
        'old',
      );
      expect(
        await File(p.join(original.path, 'new.gguf')).readAsString(),
        'new',
      );
      expect(folders.current.path, original.path);
    },
  );
}

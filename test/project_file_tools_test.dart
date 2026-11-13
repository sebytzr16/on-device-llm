import 'package:ondevice_llm/features/tools/tool_runner.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/data/network/web_search/duckduckgo_scraper.dart';
import 'package:ondevice_llm/data/network/web_search/web_page_reader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:ondevice_llm/features/tools/project_file_tools.dart';
import 'package:ondevice_llm/features/tools/file_approval.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/features/chat/domain/conversation_workspace.dart';

void main() {
  late Directory temp, root;
  late ProjectFileTools tools;
  late List<FileChange> changes;
  ToolCall call(String name, Map<String, Object?> args) =>
      ToolCall(id: '1', name: name, arguments: jsonEncode(args));
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('project_files_');
    root = await Directory(p.join(temp.path, 'project')).create();
    changes = [];
    tools = ProjectFileTools(
      folder: root.path,
      backupDirectory: () async => Directory(p.join(temp.path, 'backups')),
      permitted: () => true,
      approve: (change) async {
        changes.add(change);
        return true;
      },
    );
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('confines parent, absolute, device, UNC, ADS and new paths', () async {
    for (final path in [
      '../escape',
      'new/../../escape',
      '/tmp/x',
      r'C:\x',
      r'C:x',
      r'\\server\share\x',
      r'\\?\C:\x',
      r'\\.\NUL',
      'x:stream',
      'CON',
      r'CONIN$',
      'NUL .txt',
      'a/NUL.txt',
    ]) {
      expect(
        await tools.run(call('write_file', {'path': path, 'content': 'x'})),
        isA<ToolResult>().having((r) => r.ok, path, false),
      );
    }
    expect(changes, isEmpty);
    expect(
      (await tools.run(
        call('write_file', {'path': 'new/child.txt', 'content': 'yes'}),
      )).ok,
      true,
    );
    expect(
      await File(p.join(root.path, 'new/child.txt')).readAsString(),
      'yes',
    );
  });
  test('refuses symlink or junction escape, including new children', () async {
    final outside = await Directory(p.join(temp.path, 'outside')).create();
    final link = p.join(root.path, 'link');
    var created = false;
    try {
      await Link(link).create(outside.path);
      created = true;
    } on FileSystemException {
      if (Platform.isWindows) {
        final result = await Process.run('cmd', [
          '/c',
          'mklink',
          '/J',
          link,
          outside.path,
        ]);
        created = result.exitCode == 0;
      }
    }
    if (!created) {
      markTestSkipped('Host cannot create links or junctions');
      return;
    }
    try {
      await File(p.join(outside.path, 'secret')).writeAsString('secret');
      for (final name in ['read_file', 'write_file']) {
        final result = await tools.run(
          call(name, {'path': 'link/secret', 'content': 'bad'}),
        );
        expect(result.ok, false);
      }
      expect(
        (await tools.run(
          call('write_file', {'path': 'link/new/child', 'content': 'bad'}),
        )).ok,
        false,
      );
      expect(
        await File(p.join(outside.path, 'secret')).readAsString(),
        'secret',
      );
    } finally {
      // Remove junction itself before recursive fixture cleanup.
      if (await FileSystemEntity.type(link, followLinks: false) ==
          FileSystemEntityType.link) {
        await Link(link).delete();
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'rmdir', link]);
      }
    }
  });
  test('protects .git and refuses binary and oversized reads', () async {
    await Directory(p.join(root.path, '.git')).create();
    expect(
      (await tools.run(
        call('write_file', {'path': '.git/config', 'content': 'bad'}),
      )).ok,
      false,
    );
    await File(p.join(root.path, 'binary')).writeAsBytes([0, 1, 2]);
    expect(
      (await tools.run(call('read_file', {'path': 'binary'}))).output,
      contains('Binary'),
    );
    await File(
      p.join(root.path, 'large'),
    ).writeAsString('a\n' * (ProjectFileTools.maxBytes));
    expect((await tools.run(call('read_file', {'path': 'large'}))).ok, false);
    expect(
      (await tools.run(
        call('read_file', {
          'path': 'large',
          'start_line': 140000,
          'end_line': 140001,
        }),
      )).output,
      'a\na',
    );
  });
  test(
    'edit requires one exact occurrence, including overlapping matches',
    () async {
      final f = File(p.join(root.path, 'a'));
      for (final content in ['missing', 'old old', 'aaa']) {
        await f.writeAsString(content);
        final result = await tools.run(
          call('edit_file', {
            'path': 'a',
            'old_text': content == 'aaa' ? 'aa' : 'old',
            'new_text': 'new',
          }),
        );
        expect(result.ok, false);
      }
      expect(changes, isEmpty);
      await f.writeAsString('one\r\nold\r\n');
      expect(
        (await tools.run(
          call('edit_file', {
            'path': 'a',
            'old_text': 'old',
            'new_text': 'new',
          }),
        )).ok,
        true,
      );
      expect(await f.readAsString(), 'one\r\nnew\r\n');
      await changes.single.undo!();
      expect(await f.readAsString(), 'one\r\nold\r\n');
    },
  );
  test('approval precedes backup and write; rejection never writes', () async {
    final gate = Completer<bool>();
    final requested = Completer<void>();
    tools = ProjectFileTools(
      folder: root.path,
      backupDirectory: () async => Directory(p.join(temp.path, 'backups')),
      permitted: () => true,
      approve: (_) {
        requested.complete();
        return gate.future;
      },
    );
    final f = File(p.join(root.path, 'a'));
    await f.writeAsString('before');
    final result = tools.run(
      call('write_file', {'path': 'a', 'content': 'after'}),
    );
    await requested.future;
    expect(await f.readAsString(), 'before');
    expect(await Directory(p.join(temp.path, 'backups')).exists(), false);
    gate.complete(false);
    expect((await result).output, 'The user rejected this change');
    expect(await f.readAsString(), 'before');
  });
  test('rechecks changed files after approval', () async {
    final f = File(p.join(root.path, 'a'));
    await f.writeAsString('before');
    tools = ProjectFileTools(
      folder: root.path,
      backupDirectory: () async => Directory(p.join(temp.path, 'backups')),
      permitted: () => true,
      approve: (_) async {
        await f.writeAsString('other edit');
        return true;
      },
    );
    expect(
      (await tools.run(
        call('write_file', {'path': 'a', 'content': 'after'}),
      )).ok,
      false,
    );
    expect(await f.readAsString(), 'other edit');
  });
  test(
    'undo restores overwrite, refuses subsequent edits and removes creation',
    () async {
      final f = File(p.join(root.path, 'a'));
      await f.writeAsString('before');
      await tools.run(call('write_file', {'path': 'a', 'content': 'after'}));
      expect(await Directory(p.join(temp.path, 'backups')).list().length, 1);
      await f.writeAsString('manual');
      await expectLater(changes.last.undo!(), throwsStateError);
      await f.writeAsString('after');
      await changes.last.undo!();
      expect(await f.readAsString(), 'before');
      await tools.run(
        call('write_file', {'path': 'new', 'content': 'created'}),
      );
      await changes.last.undo!();
      expect(await File(p.join(root.path, 'new')).exists(), false);
    },
  );
  test(
    'listing glob and literal/regex search are bounded and skip .git',
    () async {
      await File(p.join(root.path, 'a.dart')).writeAsString('a.b\naxb');
      await File(p.join(root.path, 'b.txt')).writeAsString('other');
      expect(
        (await tools.run(call('list_files', {'glob': '**/*.dart'}))).output,
        contains('a.dart'),
      );
      expect(
        (await tools.run(call('list_files', {'glob': '**/*.dart'}))).output,
        isNot(contains('b.txt')),
      );
      expect(
        (await tools.run(
          call('search_files', {'pattern': 'a.b', 'regex': false}),
        )).output,
        contains('a.dart:1: a.b'),
      );
      expect(
        (await tools.run(
          call('search_files', {'pattern': 'a.b', 'regex': false}),
        )).output,
        isNot(contains('axb')),
      );
      expect(
        (await tools.run(call('search_files', {'pattern': 'a.b'}))).output,
        contains('a.dart:2: axb'),
      );
    },
  );
  test('allow edits is scoped to the chat and folder', () async {
    final gate = FileApproval((_) {});
    final first = FileChange('a', null, 'x');
    final answer = gate.request('chat', root.path, first, null);
    gate.answer(gate.changes.single, true, allowChat: true);
    expect(await answer, true);
    expect(
      await gate.request('chat', root.path, FileChange('b', null, 'y'), null),
      true,
    );
    final pending = gate.request(
      'other',
      root.path,
      FileChange('a', null, 'z'),
      null,
    );
    gate.answer(gate.changes.last, false);
    expect(await pending, false);
    gate.dispose();
  });
  test(
    'ToolRunner reserves project names and enforces web-only availability',
    () async {
      var externalCalled = false;
      tools = ProjectFileTools(
        folder: root.path,
        backupDirectory: () async => Directory(p.join(temp.path, 'backups')),
        permitted: () => true,
        approve: (_) async => false,
      );
      final runner = ToolRunner(
        scraper: DuckDuckGoScraper(),
        reader: WebPageReader(),
        settings: const InferenceSettings(),
        projectFiles: tools,
        externalTools: [
          ProjectFileTools.specs.firstWhere((s) => s.name == 'write_file'),
        ],
        externalRun: (call) async {
          externalCalled = true;
          return ToolResult(
            call: call,
            output: 'external',
            ok: true,
            elapsedMs: 0,
          );
        },
      );
      expect(runner.specs().where((s) => s.name == 'write_file'), hasLength(1));
      expect(
        (await runner.run(
          call('write_file', {'path': 'a', 'content': 'x'}),
        )).output,
        'The user rejected this change',
      );
      expect(externalCalled, false);
      expect(await File(p.join(root.path, 'a')).exists(), false);
      final web = ToolRunner(
        scraper: DuckDuckGoScraper(),
        reader: WebPageReader(),
        settings: const InferenceSettings(),
        projectFiles: tools,
        webOnly: true,
      );
      expect(web.specs().any((s) => s.name == 'write_file'), false);
      expect(
        (await web.run(call('write_file', {'path': 'a', 'content': 'x'}))).ok,
        false,
      );
      final unattached = ToolRunner(
        scraper: DuckDuckGoScraper(),
        reader: WebPageReader(),
        settings: const InferenceSettings(),
      );
      expect(unattached.specs().any((s) => s.name == 'read_file'), false);
    },
  );
  test('search caps matches and terminates pathological regex', () async {
    await File(p.join(root.path, 'many')).writeAsString('match\n' * 300);
    final result = await tools.run(call('search_files', {'pattern': 'match'}));
    expect(result.ok, true);
    expect(result.output, contains('[200 match limit]'));
    await File(p.join(root.path, 'many')).writeAsString('${'a' * 12000}!');
    final timeout = await tools.run(
      call('search_files', {'pattern': r'(a+)+$'}),
    );
    expect(timeout.ok, false);
    expect(timeout.output, contains('time limit'));
  });
  test(
    'original backup preserves BOM bytes and undo survives revoked tools',
    () async {
      var permitted = true;
      tools = ProjectFileTools(
        folder: root.path,
        backupDirectory: () async => Directory(p.join(temp.path, 'backups')),
        permitted: () => permitted,
        approve: (change) async {
          changes.add(change);
          return true;
        },
      );
      final f = File(p.join(root.path, 'bom'));
      final original = [239, 187, 191, ...utf8.encode('before\r\n')];
      await f.writeAsBytes(original);
      expect(
        (await tools.run(
          call('write_file', {'path': 'bom', 'content': 'after'}),
        )).ok,
        true,
      );
      permitted = false;
      await changes.single.undo!();
      expect(await f.readAsBytes(), original);
    },
  );
  test('approval cancellation and persisted folder decision', () async {
    final gate = FileApproval((_) {});
    final cancel = CancelToken();
    final pending = gate.request(
      'chat',
      root.path,
      FileChange('a', null, 'x'),
      cancel,
    );
    cancel.cancel();
    expect(await pending, false);
    expect(gate.changes.single.change.answer.isCompleted, true);
    expect(
      await gate.request(
        'stored',
        root.path,
        FileChange('a', null, 'x'),
        null,
        read: () async => true,
      ),
      true,
    );
    var saved = false;
    final saving = gate.request(
      'save',
      root.path,
      FileChange('a', null, 'x'),
      null,
      save: () async {
        saved = true;
      },
    );
    gate.answer(gate.changes.last, true, allowChat: true);
    expect(await saving, true);
    expect(saved, true);
    gate.dispose();
  });
  testWidgets('chat shows diff, approval buttons and applied Undo action', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final gate = container.read(fileApprovalProvider);
    final change = FileChange('code.dart', 'before', 'after');
    final pending = gate.request('chat', root.path, change, null);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FileChangesPanel(chatId: 'chat')),
        ),
      ),
    );
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Allow edits in this chat'), findsOneWidget);
    await tester.tap(find.text('Change diff'));
    await tester.pumpAndSettle();
    expect(find.textContaining('- before'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(await pending, true);
    change.applied = true;
    change.undo = () async {
      change.undone = true;
      gate.refresh();
    };
    gate.refresh();
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(change.undone, true);
    expect(find.text('Change undone'), findsOneWidget);
  });
  test(
    'workspace migrates missing folder and persists folder in backup metadata',
    () async {
      SharedPreferences.setMockInitialValues({
        ConversationWorkspaceNotifier.key: jsonEncode({
          'projects': [
            {'id': 'old', 'name': 'Old'},
          ],
        }),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(conversationWorkspaceProvider.notifier);
      await notifier.ready;
      expect(
        container.read(conversationWorkspaceProvider).projects.single.folder,
        isNull,
      );
      await notifier.saveProject(id: 'old', name: 'Old', folder: root.path);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(ConversationWorkspaceNotifier.key)!,
        )['projects'][0]['folder'],
        root.path,
      );
      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      await restored.read(conversationWorkspaceProvider.notifier).ready;
      expect(
        restored.read(conversationWorkspaceProvider).projects.single.folder,
        root.path,
      );
    },
  );
}

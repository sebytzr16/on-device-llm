import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
import 'package:ondevice_llm/features/hosting/pairing_code.dart';
import 'package:ondevice_llm/features/hosting/server_usage.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';

import 'local_backup_service_test.dart' show BackupPaths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M-02: a pin on plain HTTP is a typed pairing failure', () async {
    await expectLater(
      PairingCode.redeem(
        'http://127.0.0.1:1/v1/',
        '123456',
        fingerprint: 'a' * 64,
      ),
      throwsA(isA<PairingException>()),
    );
  });

  test('CR-07: truncation never exposes a reserved device name', () {
    final long = '${'x' * 20}CON.${'y' * 73}';
    final name = PhoneAction('save_file', {
      'name': long,
      'content': 'x',
    }).fileName;
    expect(name.toUpperCase().startsWith('CON.'), isFalse);
    expect(name.endsWith('.md'), isTrue);
  });

  test('CR-05: two saves at once never share a path', () async {
    final root = await Directory.systemTemp.createTemp('cr05-');
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = BackupPaths(root.path, root.path);
    try {
      final files = await Future.wait([
        for (var i = 0; i < 4; i++)
          PhoneActions.writeFile(
            PhoneAction('save_file', {'name': 'same.md', 'content': '$i'}),
          ),
      ]);
      final names = files.map((f) => p.basename(f.path)).toSet();
      expect(names.length, 4);
      final contents = {for (final f in files) await f.readAsString()};
      expect(contents, {'0', '1', '2', '3'});
    } finally {
      PathProviderPlatform.instance = paths;
      await root.delete(recursive: true);
    }
  });

  test('M13: device names and trailing dots never reach the file system', () {
    String name(String n) =>
        PhoneAction('save_file', {'name': n, 'content': 'x'}).fileName;
    expect(name('CON.md'), '_CON.md');
    expect(name('nul'), '_nul.md');
    expect(name('com1.txt'), '_com1.txt');
    expect(name('notes...'), 'notes.md');
    expect(name('console notes.md'), 'console notes.md');
  });

  test('M08: per-client usage keeps only the most recent clients', () {
    var usage = const ServerUsage();
    final start = DateTime(2026, 11, 7);
    for (var i = 0; i < ServerUsage.maxClients + 40; i++) {
      usage = usage.record(
        ServedRequest(
          at: start.add(Duration(seconds: i)),
          client: '10.0.0.$i',
          status: 401,
        ),
      );
    }
    expect(usage.clients.length, ServerUsage.maxClients);
    expect(usage.requests, ServerUsage.maxClients + 40);
    expect(usage.clients.containsKey('10.0.0.0'), isFalse);
    expect(
      usage.clients.containsKey('10.0.0.${ServerUsage.maxClients + 39}'),
      isTrue,
    );
  });
}

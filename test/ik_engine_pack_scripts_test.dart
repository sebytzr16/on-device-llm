import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'ik packaging checks the full pin and hash of each staged variant',
    () async {
      final fixture = await Directory.systemTemp.createTemp('ik-package-test-');
      addTearDown(() => fixture.delete(recursive: true));

      File fixtureFile(String path) {
        final file = File(p.join(fixture.path, path));
        file.parent.createSync(recursive: true);
        return file;
      }

      const commit = '0123456789012345678901234567890123456789';
      const staleCommit = '0123456aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const avx2 = 'ondevice_llm.dll';
      const compat = 'ondevice_llm_compat.dll';
      final packager = fixtureFile('scripts/package-engine-pack.ps1');
      File('scripts/package-engine-pack.ps1').copySync(packager.path);
      fixtureFile('lib/core/platform/engine_versions.dart').writeAsStringSync(
        "const llamaCppTag = 'b12503';\nconst ikLlamaCommit = '$commit';",
      );
      fixtureFile(
        'lib/inference/ffi/llama_bindings.dart',
      ).writeAsStringSync('const kEngineBridgeApi = 1;');
      fixtureFile('pubspec.yaml').writeAsStringSync('version: 1.0.0');
      final harness = fixtureFile('package-test.ps1')
        ..writeAsStringSync(r"""
function dart {
  [IO.File]::WriteAllBytes($args[3], [byte[]]::new(64))
  $global:LASTEXITCODE = 0
}
& (Join-Path $PSScriptRoot 'scripts/package-engine-pack.ps1') `
  -Engine ik_llama -Tag ik-0123456-3 -StageDir stage -OutDir packs
""");

      void stage(
        String variant,
        String pin, {
        bool changeAfterMarking = false,
      }) {
        final dll = fixtureFile('stage/$variant')..writeAsStringSync(variant);
        fixtureFile('stage/$variant.commit.json').writeAsStringSync(
          jsonEncode({
            'engine': 'ik_llama',
            'commit': pin,
            'sha256': sha256.convert(dll.readAsBytesSync()).toString(),
          }),
        );
        if (changeAfterMarking) dll.writeAsStringSync('different binary');
      }

      Future<ProcessResult> package() => Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        harness.path,
      ], workingDirectory: fixture.path);

      stage(avx2, commit);
      stage(compat, staleCommit);
      final stale = await package();
      expect(stale.exitCode, isNot(0));
      expect(stale.stderr, contains('$compat was staged for commit'));
      expect(Directory(p.join(fixture.path, 'packs')).existsSync(), isFalse);

      stage(compat, commit, changeAfterMarking: true);
      final changed = await package();
      expect(changed.exitCode, isNot(0));
      expect(
        changed.stderr,
        contains('$compat differs from its ik_llama commit marker'),
      );

      stage(compat, commit);
      final valid = await package();
      expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
      final manifest =
          jsonDecode(
                File(
                  p.join(
                    fixture.path,
                    'packs',
                    'ik-engine-pack-windows-x64.json',
                  ),
                ).readAsStringSync(),
              )
              as Map;
      expect(manifest['engine'], commit);
      expect(manifest['revision'], 3);
      expect((manifest['files'] as List).map((entry) => entry['name']), [
        avx2,
        compat,
      ]);
    },
    skip: !Platform.isWindows,
  );
}

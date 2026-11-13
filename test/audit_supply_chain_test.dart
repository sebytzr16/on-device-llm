import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('S19: supply-chain inputs are locked and reviewed', () {
    test('Gradle wrapper pins the distribution checksum', () {
      const wrapperPath = 'android/gradle/wrapper/gradle-wrapper.properties';
      final wrapper = _read(wrapperPath);
      expect(wrapper, contains('gradle-9.1.0-all.zip'));
      final checksum = RegExp(
        r'^distributionSha256Sum=[0-9A-Fa-f]{64}$',
        multiLine: true,
      );
      expect(checksum.hasMatch(wrapper), isTrue);
      // A TODO placeholder would leave the download unverified again.
      expect(wrapper, isNot(contains('TODO')));
    });

    test('CI rejects a pubspec.lock change after pub get', () {
      final ci = _read('.github/workflows/ci.yml');
      final pubGet = ci.indexOf('flutter pub get');
      final lockCheck = ci.indexOf('git diff --exit-code pubspec.lock');
      expect(pubGet, greaterThanOrEqualTo(0));
      expect(lockCheck, greaterThan(pubGet));
    });

    test('supply-chain documentation records SBOM and advisory review', () {
      final doc = File('docs/supply-chain.md');
      expect(doc.existsSync(), isTrue);
      final text = doc.readAsStringSync();
      expect(text, contains('SBOM'));
      expect(text, contains('advisory'));
      expect(text, contains('pubspec.lock'));
      expect(text, contains('distributionSha256Sum'));
    });
  });

  group('S21: Windows packaging can sign and verify release binaries', () {
    test('packaging supports optional signing and -RequireSignature', () {
      final script = _read('scripts/package-windows.ps1');
      expect(script, contains(r'[switch]$RequireSignature'));
      expect(script, contains(r'$env:ODL_SIGN_CERT'));
      expect(script, contains('Invoke-SignFile'));
      expect(script, contains('verify /pa'));
      expect(script, contains('ondevice_llm.exe'));
      expect(script, contains('diffusiongemma/dg_host.exe'));
    });

    test('missing signature configuration fails before archiving', () {
      final script = _read('scripts/package-windows.ps1');
      final requirement = script.indexOf(
        '-RequireSignature requires ODL_SIGN_CERT',
      );
      final archive = script.indexOf('CreateFromDirectory');
      expect(requirement, greaterThanOrEqualTo(0));
      expect(archive, greaterThan(requirement));
    });

    test('signing happens before the engine manifest hashes the bundle', () {
      final script = _read('scripts/package-windows.ps1');
      final sign = script.indexOf(r'$signFiles = @(');
      final manifest = script.indexOf('write-engine-manifest.ps1');
      expect(sign, greaterThanOrEqualTo(0));
      expect(manifest, greaterThan(sign));
    });

    test('packaging docs describe the enforced signing stage', () {
      final doc = _read('docs/windows-packaging.md');
      expect(doc, contains('ODL_SIGN_CERT'));
      expect(doc, contains('-RequireSignature'));
      expect(doc, contains('signtool verify /pa'));
    });
  });
}

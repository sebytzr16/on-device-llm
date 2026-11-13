import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/model_licences.dart';

void main() {
  test('the licence page credits NVIDIA for Parakeet, once', () async {
    registerModelLicences();
    registerModelLicences();
    final entries = await LicenseRegistry.licenses.toList();
    final parakeet = entries
        .where((e) => e.packages.contains('Parakeet TDT 0.6B v3'))
        .toList();
    expect(parakeet, hasLength(1));
    final text = parakeet.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('by NVIDIA'));
    expect(text, contains('CC BY 4.0'));
  });

  test('the licence page credits Moondream for Parakeet Ultra', () async {
    registerModelLicences();
    final entries = await LicenseRegistry.licenses.toList();
    final ultra = entries
        .where((e) => e.packages.contains('Parakeet Ultra'))
        .toList();
    expect(ultra, hasLength(1));
    final text = ultra.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('by Moondream'));
    expect(text, contains('CC BY 4.0'));
    expect(text, contains('parakeet-tdt-0.6b-v3'));
  });

  test('the licence page names Supertonic 3 and both licences', () async {
    registerModelLicences();
    final entries = await LicenseRegistry.licenses.toList();
    final supertonic = entries
        .where((e) => e.packages.contains('Supertonic 3'))
        .toList();
    expect(supertonic, hasLength(1));
    final text = supertonic.single.paragraphs.map((p) => p.text).join(' ');
    expect(text, contains('OpenRAIL-M (weights), MIT (code)'));
    expect(text, contains('https://huggingface.co/Supertone/supertonic-3'));
  });
}

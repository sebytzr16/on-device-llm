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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';

void main() {
  test('reference markers go, code indexes stay (P2-53)', () {
    String strip(String s) => EvidenceRanker.stripReferenceMarkers(s);
    expect(
      strip('Paris is the capital.[5] It is old[a].'),
      'Paris is the capital. It is old.',
    );
    expect(strip('Read `arr[0]` first.'), 'Read `arr[0]` first.');
    expect(strip('```\nx = arr[0]\n```'), '```\nx = arr[0]\n```');
    expect(strip('let first = items[1];'), 'let first = items[1];');
    expect(
      strip('Use m[i][j] and arr[0].name here'),
      'Use m[i][j] and arr[0].name here',
    );
    expect(strip('Set x[1] = 2 to start'), 'Set x[1] = 2 to start');
  });
}

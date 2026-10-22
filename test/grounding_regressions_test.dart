import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/claim_check.dart';
import 'package:ondevice_llm/features/retrieval/domain/citation_match.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';
import 'package:ondevice_llm/features/retrieval/semantic_rerank.dart';

void main() {
  final cases = <(String, String)>[
    (
      'The Nikon Z30 camera is weather sealed and provides weather protection.',
      'The Nikon Z30 camera is not weather sealed and does not provide weather protection.',
    ),
    (
      'The Nikon Z30 weighs 405 g without the battery.',
      'Nikon Z30\nWeight: 405 g with the battery; 350 g without the battery.',
    ),
    ('The Nikon Z30 camera weighs 405 kg.', 'Nikon Z30 camera weighs 405 g.'),
    ('The monthly rent is \$1,450.10.', 'The monthly rent is \$1,450.'),
    ('The chamber temperature is 24°C.', 'The chamber temperature is 24°F.'),
    ('The chamber temperature is -24°C.', 'The chamber temperature is 24°C.'),
    (
      'The chamber temperature is 24 degrees Celsius.',
      'The chamber temperature is 24 degrees Fahrenheit.',
    ),
    (
      'The Nikon Z30 camera costs CA\$899.',
      'The Nikon Z30 camera costs US\$899.',
    ),
    ('The Nikon Z30 camera weighs 405 g.', 'Nikon Z50 camera weighs 405 g.'),
    (
      'The Nikon Z30 camera weighs 405 g.',
      'Nikon Z30 and Nikon Z50 comparison\nThe Nikon Z50 camera weighs 405 g.',
    ),
    (
      'The Nikon Z30 camera weighs 405 g and provides weather protection.',
      'The Nikon Z30 camera weighs 405 g.',
    ),
    (
      'The opening ceremony takes place on October 5, 2026.',
      'The opening ceremony takes place on October 6, 2026.',
    ),
    (
      'Le boîtier Nikon Z30 est étanche aux intempéries.',
      "Le boîtier Nikon Z30 n'est pas étanche aux intempéries.",
    ),
    (
      'La cámara Nikon Z30 tiene protección contra la lluvia.',
      'La cámara Nikon Z30 no tiene protección contra la lluvia.',
    ),
  ];
  for (final (claim, source) in cases) {
    test('does not ground: $claim', () {
      expect(CitationMatch.attach(claim, [source]), claim);
      expect(
        ClaimCheck.check([claim], [source], cosines: [0.99]).single.status,
        isNot(ClaimStatus.supported),
      );
    });
  }
  test('similarity alone never establishes support', () {
    expect(
      ClaimCheck.check(
        ['The best season for aurora viewing is midsummer.'],
        ['Auroras are visible in dark winter skies.'],
        cosines: [0.82],
      ).single.status,
      isNot(ClaimStatus.supported),
    );
  });
  test('genuine support cites the passage with the right qualifier', () {
    const claim = 'The Nikon Z30 weighs 350 g without the battery.';
    const source =
        'Nikon Z30\nWeight: 405 g with the battery; 350 g without the battery.';
    expect(CitationMatch.attach(claim, [source]), contains('[1]'));
    expect(
      ClaimCheck.check([claim], [source]).single.status,
      ClaimStatus.supported,
    );
  });
  test('fused rank, including semantic promotion, survives trimming', () {
    final a = EvidenceChunk(
      sourceIndex: 0,
      ordinal: 0,
      text: 'lexical',
      score: 9,
    );
    final b = EvidenceChunk(
      sourceIndex: 1,
      ordinal: 0,
      text: 'answer',
      score: .01,
    );
    final distractors = [
      for (var i = 0; i < 2; i++)
        EvidenceChunk(
          sourceIndex: i + 2,
          ordinal: 0,
          text: 'distractor',
          score: 8 - i.toDouble(),
        ),
    ];
    final order = SemanticRerank.fuse([a, ...distractors, b], {b: .95, a: .1});
    expect(
      order.map((c) => c.score).toList(),
      orderedEquals(
        order.map((c) => c.score).toList()..sort((x, y) => y.compareTo(x)),
      ),
    );
    final fitted = SemanticRerank.select(order, perSource: 1, maxChunks: 4);
    while (fitted.length > 2) {
      final weakest = fitted.reduce((x, y) => x.score < y.score ? x : y);
      fitted.remove(weakest);
    }
    expect(
      fitted.any((c) => c.text == 'answer'),
      isTrue,
      reason: 'the semantic promotion survives a two-passage context budget',
    );
  });

  test('an abbreviation does not end a claim, and hedges are no words', () {
    // App quality probe, 2026-10-19: "405 g/14.3 oz. with battery" was cut
    // at "oz." and "approximately" was missing from the page's "Approx.".
    const answer =
        'The Nikon Z30 weighs approximately **405 g/14.3 oz. with battery '
        'and memory card but without body cap** [1].';
    final sentences = ClaimCheck.sentences(answer);
    expect(sentences, hasLength(1));
    expect(
      ClaimCheck.sentences(
        "La tour mesure 330 mètres [1].\n\nVoici d'autres détails pertinents :",
      ),
      ['La tour mesure 330 mètres .'],
    );
    final verdicts = ClaimCheck.check(sentences, [
      'Nikon Z30 specifications\nWeight Approx. 405 g/14.3 oz. with battery '
          'and memory card but without body cap; approx. 350 g/12.4 oz. '
          '(camera body only)',
    ]);
    expect(verdicts.single.status, ClaimStatus.supported);
  });

  test('bold headings and labels are the model\'s words, not claims', () {
    // News probe, 2026-10-20: "Unreliability", "Defense" and "Briefing"
    // were flagged as names no source mentions on every briefing.
    const answer =
        "**Canada's Latest News Briefing (Oct 20, 2026)**\n\n"
        '**DOJ List Shows Unreliability [3]**\n'
        '- **The Defense:** Acton\'s brother spoke to Reuters [2].\n'
        '- **Outlook**: Rates hold at 2.25 percent [1].';
    final sentences = ClaimCheck.sentences(answer);
    expect(sentences, hasLength(2));
    expect(sentences.first, startsWith("Acton's brother"));
    expect(sentences.last, startsWith('Rates hold'));
    // The sentence after a label is still checked.
    expect(ClaimCheck.novelDetails(sentences.first, ['A brother spoke.']), [
      'Reuters',
    ]);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';

void main() {
  test('coverage: every question term seen in the pages read', () {
    const q = 'default TCP port for PostgreSQL';
    expect(
      EvidenceRanker.covers(q, [
        'PostgreSQL listens on TCP port 5432 by default.',
      ]),
      true,
    );
    expect(
      EvidenceRanker.covers(q, [
        'PostgreSQL is a database.',
        'TCP ports explained.',
      ]),
      false,
    );
    expect(
      EvidenceRanker.covers(q, [
        'PostgreSQL is a database.',
        'The default port is 5432 over TCP.',
      ]),
      true,
    );
    // One-term questions never count as covered.
    expect(EvidenceRanker.covers('PostgreSQL', ['PostgreSQL']), false);
  });

  test('ranking keeps accented and CJK query terms', () {
    expect(
      EvidenceRanker.terms('Québec énergie'),
      containsAll(['québec', 'énergie']),
    );
    final ranked = EvidenceRanker.rank('東京 天気', [
      EvidenceChunk(sourceIndex: 0, ordinal: 0, text: '大阪の交通情報'),
      EvidenceChunk(sourceIndex: 1, ordinal: 0, text: '東京の天気予報'),
    ]);
    expect(ranked.first.sourceIndex, 1);
  });

  test('chunks merge blocks to ~1400 chars and split oversized blocks', () {
    final lines = List.generate(30, (i) => 'Block $i ${'x' * 200}');
    final chunks = EvidenceRanker.chunk(lines.join('\n'), sourceIndex: 0);
    expect(chunks.length, greaterThan(3));
    expect(chunks.every((c) => c.text.length <= EvidenceRanker.maxChars), true);
    expect(chunks.first.text, startsWith('Block 0'));
    expect(
      chunks.map((c) => c.ordinal),
      List.generate(chunks.length, (i) => i),
    );
    final huge = EvidenceRanker.chunk(
      ('A sentence about nothing. ' * 200).trim(),
      sourceIndex: 1,
    );
    expect(huge.length, greaterThan(2));
    expect(huge.every((c) => c.text.length <= EvidenceRanker.maxChars), true);
  });

  test('body-only fact outranks the intro and the snippet-like opening', () {
    const page = '''
Welcome to the Adreno developer portal. Navigation. Home. Products.
The Adreno 830 GPU ships in the Snapdragon 8 Elite platform.
It supports OpenCL 3.0 and Vulkan 1.3 with subgroup operations.
The maximum single OpenCL allocation on the Adreno 830 is 1 GiB.
Contact us. Privacy. Terms of use.''';
    final chunks = [
      for (final line in page.trim().split('\n'))
        ...EvidenceRanker.chunk(line, sourceIndex: 0),
    ];
    // Re-number so each line is its own passage for this test.
    for (var i = 0; i < chunks.length; i++) {
      chunks[i] = EvidenceChunk(
        sourceIndex: 0,
        ordinal: i,
        text: chunks[i].text,
      );
    }
    final ranked = EvidenceRanker.rank(
      'What is the maximum OpenCL allocation on the Adreno 830?',
      chunks,
    );
    expect(ranked.first.text, contains('1 GiB'));
    expect(ranked.first.score, greaterThan(ranked.last.score));
  });

  test('per-source cap keeps diversity and duplicates are dropped', () {
    final a = List.generate(
      6,
      (i) => EvidenceChunk(
        sourceIndex: 0,
        ordinal: i,
        text: 'llama.cpp OpenCL Adreno kernels passage $i',
      ),
    );
    final b = [
      EvidenceChunk(sourceIndex: 1, ordinal: 0, text: 'OpenCL on Adreno'),
      EvidenceChunk(
        sourceIndex: 1,
        ordinal: 1,
        text: 'llama.cpp  opencl adreno KERNELS passage 0',
      ),
    ];
    final ranked = EvidenceRanker.rank('opencl adreno', [...a, ...b]);
    expect(
      ranked.where((c) => c.sourceIndex == 0).length,
      lessThanOrEqualTo(3),
    );
    expect(ranked.any((c) => c.sourceIndex == 1), true);
    expect(
      ranked.where((c) => c.text.toLowerCase().contains('passage 0')).length,
      1,
      reason: 'syndicated duplicate kept once',
    );
  });

  test('a query matching nothing falls back to reading order', () {
    final chunks = [
      EvidenceChunk(sourceIndex: 0, ordinal: 1, text: 'second'),
      EvidenceChunk(sourceIndex: 0, ordinal: 0, text: 'first'),
    ];
    final ranked = EvidenceRanker.rank('zzz', chunks);
    expect(ranked.map((c) => c.text), ['first', 'second']);
    expect(EvidenceRanker.excerpt(ranked, 0), 'first\n[…]\nsecond');
  });

  test('reference markers are stripped so they cannot become citations', () {
    final chunks = EvidenceRanker.chunk(
      'Adreno was announced in 2008.[5] It replaced Imageon.[citation needed] See[a] note.',
      sourceIndex: 0,
    );
    expect(
      chunks.single.text,
      'Adreno was announced in 2008. It replaced Imageon. See note.',
    );
  });

  test(
    'stemming matches inflections; figures are favoured for figure asks',
    () {
      expect(EvidenceRanker.stem('versions'), 'version');
      expect(EvidenceRanker.stem('released'), EvidenceRanker.stem('release'));
      expect(EvidenceRanker.stem('releases'), EvidenceRanker.stem('release'));
      expect(EvidenceRanker.stem('updated'), EvidenceRanker.stem('updates'));
      expect(EvidenceRanker.stem('cities'), 'city');
      expect(EvidenceRanker.stem('flutter'), 'flutter');
      expect(EvidenceRanker.stem('3.47.4'), '3.47.4');
      final chunks = [
        EvidenceChunk(
          sourceIndex: 0,
          ordinal: 0,
          text: 'Flutter releases happen on a regular schedule of versions.',
        ),
        EvidenceChunk(
          sourceIndex: 0,
          ordinal: 1,
          text: 'The latest Flutter version released is 3.47.4.',
        ),
      ];
      final ranked = EvidenceRanker.rank(
        'What is the latest Flutter version?',
        chunks,
      );
      expect(ranked.first.text, contains('3.47.4'));
    },
  );

  test('planner queries widen the match and titles boost their pages', () {
    // A passage that only matches the model's rewritten query still scores.
    final widened = EvidenceRanker.rank(
      'Which graphics chip is in the Snapdragon 8 Elite?',
      [
        EvidenceChunk(
          sourceIndex: 0,
          ordinal: 0,
          text: 'Adreno 830 details and specifications.',
        ),
        EvidenceChunk(
          sourceIndex: 1,
          ordinal: 0,
          text: 'Generic phone hardware overview.',
        ),
      ],
      extraQueries: ['Adreno 830'],
    );
    expect(widened.first.sourceIndex, 0);
    expect(widened.first.score, greaterThan(0));
    expect(widened.last.score, 0);
    // Same passage on two pages: the page whose title names the subject wins.
    final boosted = EvidenceRanker.rank(
      'Snapdragon 8 Elite GPU',
      [
        EvidenceChunk(sourceIndex: 0, ordinal: 0, text: 'The GPU is Adreno.'),
        EvidenceChunk(sourceIndex: 1, ordinal: 0, text: 'The GPU is Adreno.'),
      ],
      titles: {1: 'Snapdragon 8 Elite GPU review'},
    );
    expect(boosted.first.sourceIndex, 1);
    expect(boosted.length, 1, reason: 'duplicate text is kept once');
  });

  test('results are reordered by title match and video/social hosts sink', () {
    final ordered = EvidenceRanker.rankResults<(String, String, String)>(
      'latest stable Flutter version',
      [
        ('Flutter tutorial video', 'https://www.youtube.com/watch?v=1', ''),
        ('Random blog', 'https://example.com/blog', 'about cooking'),
        (
          'Flutter release notes: latest stable version',
          'https://docs.flutter.dev/release/whats-new',
          'The latest stable Flutter version',
        ),
      ],
      titleOf: (r) => r.$1,
      urlOf: (r) => r.$2,
      snippetOf: (r) => r.$3,
    );
    expect(ordered.first.$2, contains('docs.flutter.dev'));
    expect(ordered.last.$2, contains('youtube'));
  });

  test('timely questions prefer dated recent results and reference hosts', () {
    final now = DateTime.utc(2026, 9, 19);
    expect(
      EvidenceRanker.snippetDate('Mar 4, 2025 — Flutter 3.29 is out', now: now),
      DateTime.utc(2025, 3, 4),
    );
    expect(
      EvidenceRanker.snippetDate('4 March 2025 · release notes', now: now),
      DateTime.utc(2025, 3, 4),
    );
    expect(
      EvidenceRanker.snippetDate('2025-03-04: notes', now: now),
      DateTime.utc(2025, 3, 4),
    );
    expect(EvidenceRanker.snippetDate('Dec 1, 2099 — soon', now: now), isNull);
    expect(EvidenceRanker.snippetDate('no date here', now: now), isNull);
    final ordered = EvidenceRanker.rankResults<(String, String, String)>(
      'latest stable Flutter version',
      [
        (
          'Flutter latest stable version',
          'https://example.com/old',
          'Jan 3, 2020 — The latest stable Flutter version is 1.12',
        ),
        (
          'Flutter latest stable version',
          'https://example.com/new',
          'Sep 11, 2026 — The latest stable Flutter version is 3.47',
        ),
      ],
      titleOf: (r) => r.$1,
      urlOf: (r) => r.$2,
      snippetOf: (r) => r.$3,
      recent: true,
      now: now,
    );
    expect(ordered.first.$2, endsWith('/new'));
    // Same two results, no timeliness: the engine's order stands.
    final plain = EvidenceRanker.rankResults<(String, String, String)>(
      'latest stable Flutter version',
      [
        (
          'Flutter latest stable version',
          'https://example.com/old',
          'Jan 3, 2020 — 1.12',
        ),
        (
          'Flutter latest stable version',
          'https://example.com/new',
          'Sep 11, 2026 — 3.47',
        ),
      ],
      titleOf: (r) => r.$1,
      urlOf: (r) => r.$2,
      snippetOf: (r) => r.$3,
      now: now,
    );
    expect(plain.first.$2, endsWith('/old'));
    // The reference-host lead is small: it settles near-ties further down
    // the list, never the engine's top results.
    final reference = EvidenceRanker.rankResults<(String, String, String)>(
      'GGUF file format',
      [
        ('GGUF file format', 'https://a.example/1', 'GGUF file format'),
        ('GGUF file format', 'https://b.example/2', 'GGUF file format'),
        ('GGUF file format', 'https://c.example/3', 'GGUF file format'),
        ('GGUF file format', 'https://someblog.com/gguf', 'GGUF file format'),
        (
          'GGUF file format',
          'https://en.wikipedia.org/wiki/GGUF',
          'GGUF file format',
        ),
      ],
      titleOf: (r) => r.$1,
      urlOf: (r) => r.$2,
      snippetOf: (r) => r.$3,
    );
    expect(reference.first.$2, contains('a.example'));
    expect(reference[2].$2, contains('wikipedia'));
    expect(reference.last.$2, contains('someblog'));
  });

  test('how-to questions favour passages that read as steps', () {
    expect(
      EvidenceRanker.looksLikeSteps(
        '1. Open Settings\n2. Tap Storage\n3. Clear cache',
      ),
      true,
    );
    expect(
      EvidenceRanker.looksLikeSteps(
        r'$ git reset --soft HEAD~1'
        '\n'
        r'$ git status',
      ),
      true,
    );
    expect(
      EvidenceRanker.looksLikeSteps(
        'Git is a version control system created in 2005.',
      ),
      false,
    );
    final ranked = EvidenceRanker.rank(
      'How do I undo the last git commit but keep the changes?',
      [
        EvidenceChunk(
          sourceIndex: 0,
          ordinal: 0,
          text:
              'Undo the last git commit and keep changes: people often ask this about git commit history.',
        ),
        EvidenceChunk(
          sourceIndex: 0,
          ordinal: 1,
          text:
              'To undo the last git commit and keep the changes:\n1. Run git reset --soft HEAD~1\n2. Check git status',
        ),
      ],
    );
    expect(ranked.first.ordinal, 1);
  });

  test('figures absent from every source are reported', () {
    const sources = [
      'Flutter 3.47.4 was released on 2026-09-11 [1].',
      'Snippet: Dart 3.11 ships alongside.',
    ];
    expect(
      EvidenceRanker.unsupportedFigures(
        'The latest stable is 3.47.4 (11 September 2026) [1]. Dart 3.11 [2].',
        sources,
      ),
      isEmpty,
    );
    expect(
      EvidenceRanker.unsupportedFigures(
        'Flutter 3.48.0 came out in 2027 with 45% faster builds, priced at \$1,299 [1].',
        sources,
      ),
      ['3.48.0', '2027', '45', '1299'],
    );
    // Prefix of a fuller version in the evidence, list numbering, small
    // counts and citation markers are not figures.
    expect(
      EvidenceRanker.unsupportedFigures(
        '1. Flutter 3.47 is current [3].\n2. Two of 3 sources agree; 12 pages.',
        sources,
      ),
      isEmpty,
    );
  });

  test('a small figure with a unit is checked: rounding is caught', () {
    const sources = [
      'The Z30 yields an effective 20.9-megapixel still image. It weighs 405 g with battery and has 8 GB of buffer.',
    ];
    expect(
      EvidenceRanker.unsupportedFigures(
        'The Z30 has a 21 MP sensor and weighs 405 g [1]; 8 GB buffer, 5 stops of stabilisation.',
        sources,
      ),
      ['21', '5'],
    );
    expect(
      EvidenceRanker.unsupportedFigures(
        'The Z30 has a 20.9 MP sensor [1]. Two of 3 reviews agree on 12 weeks of battery tests.',
        sources,
      ),
      isEmpty,
    );
  });
}

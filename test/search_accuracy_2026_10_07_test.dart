import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_embedder.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_media.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';
import 'package:ondevice_llm/features/retrieval/claim_check_runner.dart';
import 'package:ondevice_llm/features/retrieval/domain/citation_match.dart';
import 'package:ondevice_llm/features/retrieval/domain/claim_check.dart';
import 'package:ondevice_llm/features/retrieval/domain/evidence.dart';
import 'package:ondevice_llm/features/retrieval/semantic_rerank.dart';
import 'package:ondevice_llm/l10n/app_localizations_en.dart';

/// Vectors chosen by hand: every text containing a key word maps to that
/// word's axis, so "meaning" is fully controlled by the test.
class AxisEmbedder extends TextEmbedder {
  final List<String> axes;
  int passages = 0;
  AxisEmbedder(this.axes);
  @override
  String get modelId => 'axis';
  Float32List _v(String text) {
    final v = Float32List(axes.length + 1);
    final lower = text.toLowerCase();
    var hit = false;
    for (var i = 0; i < axes.length; i++) {
      if (lower.contains(axes[i])) {
        v[i] = 1;
        hit = true;
        break;
      }
    }
    if (!hit) v[axes.length] = 1;
    return v;
  }

  @override
  Future<List<Float32List>?> embedQueries(List<String> texts) async => [
    for (final t in texts) _v(t),
  ];
  @override
  Future<List<Float32List>?> embedDocuments(List<String> texts) async {
    passages += texts.length;
    return [for (final t in texts) _v(t)];
  }
}

EvidenceChunk chunk(int source, int ordinal, String text) =>
    EvidenceChunk(sourceIndex: source, ordinal: ordinal, text: text);

void main() {
  group('SemanticRerank', () {
    test('meaning promotes a passage that answers in other words', () async {
      // Reciprocal rank fusion lifts a passage the words ranked just below
      // the cut; it does not overturn a clear lexical winner.
      final chunks = [
        chunk(
          0,
          0,
          'Northern lights tours, northern lights photos, northern lights shop.',
        ),
        chunk(
          1,
          0,
          'Northern lights hotel deals and northern lights packages.',
        ),
        chunk(
          2,
          0,
          'See the northern lights from our lodge with northern lights alerts.',
        ),
        chunk(3, 0, 'Northern lights jewellery inspired by the lights.'),
        chunk(
          4,
          0,
          'Aurora season in Tromso runs from September to March, when nights are dark.',
        ),
      ];
      final lexical = EvidenceRanker.rank('when to see the northern lights', [
        for (final c in chunks) chunk(c.sourceIndex, c.ordinal, c.text),
      ], maxChunks: 3);
      expect([for (final c in lexical) c.sourceIndex], isNot(contains(4)));
      // The query and the season passage share the "season" axis.
      final embedder = AxisEmbedder(['season']);
      final ranked = await SemanticRerank.rank(
        'when to see the northern lights (season)',
        chunks,
        embedder: embedder,
        maxChunks: 3,
      );
      expect([for (final c in ranked) c.sourceIndex], contains(4));
    });

    test('no embedder keeps the lexical selection', () async {
      final chunks = [
        chunk(0, 0, 'The boiler reset button is under the front cover.'),
        chunk(1, 0, 'Unrelated text about gardening and roses.'),
      ];
      final ranked = await SemanticRerank.rank(
        'boiler reset button',
        chunks,
        embedder: null,
        maxChunks: 1,
      );
      expect(ranked.single.sourceIndex, 0);
    });

    test('select keeps at most perSource passages of one page', () {
      final order = [chunk(0, 0, 'a'), chunk(0, 1, 'b'), chunk(1, 0, 'c')];
      final out = SemanticRerank.select(order, perSource: 1, maxChunks: 3);
      expect([for (final c in out) c.sourceIndex], [0, 1]);
    });

    test('passage vectors are cached for the claim check', () async {
      final embedder = AxisEmbedder(['tower']);
      await SemanticRerank.passageVector(embedder, 'The tower is tall.');
      await SemanticRerank.passageVector(embedder, 'The tower is tall.');
      expect(embedder.passages, 1);
    });

    test(
      'sentence trimming keeps the sentences closest to the question',
      () async {
        final embedder = AxisEmbedder(['tower']);
        final chunks = [
          chunk(
            0,
            0,
            'Paris is busy. The tower opened in 1889. Cafés line the '
            'river. Tickets cost more in summer.',
          ),
          chunk(1, 0, 'Short page. Two lines.'),
        ];
        expect(
          await SemanticRerank.trimSentences(
            'tower',
            chunks,
            embedder: embedder,
          ),
          same(chunks),
          reason: 'off unless the experiment sets a share',
        );
        SemanticRerank.trimShare = 0.25;
        addTearDown(() => SemanticRerank.trimShare = null);
        final out = await SemanticRerank.trimSentences(
          'tower',
          chunks,
          embedder: embedder,
        );
        expect(out.first.text, '… The tower opened in 1889. …');
        expect(out.last.text, chunks.last.text, reason: 'under four sentences');
        expect(SemanticRerank.lastTrim?['trimmed'], 1);
      },
    );
  });

  group('ClaimCheck', () {
    const source =
        'The Eiffel Tower was completed in 1889 for the World\'s Fair in Paris. '
        'Designed by the company of Gustave Eiffel, it was the tallest '
        'man-made structure until the Chrysler Building was finished in 1930.';

    test('names and years no source has are flagged', () {
      final verdicts = ClaimCheck.check(
        ClaimCheck.sentences(
          'The Eiffel Tower was completed in 1889 for the fair in Paris [1]. '
          'The tower was then repainted for the 1900 Olympic Games in Paris.',
        ),
        [source],
      );
      expect(verdicts.first.status, ClaimStatus.supported);
      expect(verdicts.last.status, ClaimStatus.novelDetails);
      expect(verdicts.last.details, containsAll(['1900', 'Olympic']));
    });

    test('spelled-out months and units match the short forms', () {
      const page = 'Rome today: heavy rain, high 24°C. Plaque unveiled Oct 5.';
      expect(
        ClaimCheck.novelDetails(
          'Today in Rome it rains, with a high of 24 degrees Celsius.',
          [page],
        ),
        isEmpty,
      );
      expect(
        ClaimCheck.novelDetails('It was unveiled on October 5.', [page]),
        isEmpty,
      );
      expect(
        ClaimCheck.novelDetails('It was unveiled on November 5.', [page]),
        ['November'],
      );
    });

    test('a sentence no source talks about is off-source', () {
      final verdicts = ClaimCheck.check(
        ClaimCheck.sentences(
          'Bananas ripen faster beside apples in a paper bag.',
        ),
        [source],
      );
      expect(verdicts.single.status, ClaimStatus.offSource);
    });

    test('meaning identifies a topic without asserting support', () {
      final sentences = ClaimCheck.sentences(
        'Visitors climbing the iron landmark enjoy wide views over the city.',
      );
      expect(
        ClaimCheck.check(sentences, [source]).single.status,
        ClaimStatus.offSource,
      );
      expect(
        ClaimCheck.check(sentences, [source], cosines: [0.78]).single.status,
        ClaimStatus.uncertain,
      );
    });

    test('code, tables and headings are not checked', () {
      expect(
        ClaimCheck.sentences(
          '# Eiffel Tower facts and figures\n'
          '| Height | 330 m in Paris |\n'
          '```\nprint("Gustave Eiffel built this tower")\n```',
        ),
        isEmpty,
      );
    });

    test('runner turns flagged sentences into a notice', () async {
      final verdicts = await ClaimCheckRunner.run(
        'The tower was repainted for the 1900 Olympic Games in Paris.',
        [
          const SearchResult(
            title: 'Eiffel Tower',
            url: 'https://en.wikipedia.org/wiki/Eiffel_Tower',
            snippet: '',
            source: 'Wikipedia',
            rank: 1,
            pageText: source,
          ),
        ],
      );
      final notice = ClaimCheckRunner.notice(verdicts, AppLocalizationsEn());
      expect(notice, contains('1900'));
      expect(notice, contains('Not backed by the sources'));
    });
  });

  test(
    'citation fill cites the uncited sentences of a partly cited answer',
    () {
      const sources = [
        'The Eiffel Tower is 330 metres tall and stands in Paris.',
        'The Louvre is the most visited art museum in the world.',
      ];
      const answer =
          'The Eiffel Tower is 330 metres tall [1]. '
          'The Louvre is the most visited art museum in the world.';
      expect(CitationMatch.attach(answer, sources), answer);
      expect(
        CitationMatch.attach(answer, sources, fill: true),
        'The Eiffel Tower is 330 metres tall [1]. '
        'The Louvre is the most visited art museum in the world [2].',
      );
    },
  );

  group('KnowledgeMedia', () {
    test('a WAV splits into fixed segments', () async {
      final pcm = Uint8List(16000 * 2 * 3); // 3 s of silence at 16 kHz
      final dir = await Directory.systemTemp.createTemp('wav');
      final wav = File('${dir.path}/a.wav')
        ..writeAsBytesSync(KnowledgeMedia.wavBytes(pcm, 16000));
      final (data, rate) = KnowledgeMedia.wavPcm(wav.readAsBytesSync())!;
      expect(rate, 16000);
      expect(data.length, pcm.length);
      expect(KnowledgeMedia.mimeFor('memo.m4a'), 'audio/mp4');
      expect(KnowledgeMedia.isImage('IMG_1.HEIC'), isTrue);
      await dir.delete(recursive: true);
    });

    test('voice notes import as one passage per minute', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final dir = await Directory.systemTemp.createTemp('kn');
      addTearDown(() => dir.delete(recursive: true));
      final store = KnowledgeStore(db, null, () async => dir);
      final doc = await store.import(
        collection: 'Home',
        name: 'dentist.m4a',
        bytes: Uint8List.fromList(utf8.encode('fake audio')),
        audioSeconds: (_) async => 150,
        transcribe: (_) async => 'Dentist on Tuesday at nine.',
      );
      expect(doc.mime, 'audio/mp4');
      expect(doc.chunkCount, 3);
      final hits = await store.search('Home', 'dentist Tuesday');
      expect(hits.single.pageText, contains('Dentist on Tuesday'));
    });

    test('photos import with their recognised text', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final dir = await Directory.systemTemp.createTemp('kn');
      addTearDown(() => dir.delete(recursive: true));
      final store = KnowledgeStore(db, null, () async => dir);
      final doc = await store.import(
        collection: 'Home',
        name: 'receipt.jpg',
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
        ocr: (_) async => 'TRATTORIA ROMA total 42.50',
      );
      expect(doc.mime, 'image/jpeg');
      final hits = await store.search('Home', 'trattoria receipt');
      expect(hits.single.pageText, contains('Photo: receipt.jpg'));
    });
  });
}

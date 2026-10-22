import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_embedder.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_store.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// A stand-in for the embedding model: a bag of canonical words hashed into
/// 64 dimensions, with a synonym table so "restart the heater" lands near
/// "reset the boiler" the way a real model would.
class FakeEmbedder extends TextEmbedder {
  static const synonyms = {
    'restart': 'reset',
    'reboot': 'reset',
    'heater': 'boiler',
    'furnace': 'boiler',
    'stuck': 'lockout',
    'jammed': 'lockout',
    'blocked': 'lockout',
  };
  final String id;
  int calls = 0;
  bool available = true;
  FakeEmbedder([this.id = 'fake-v1']);

  @override
  String get modelId => id;

  Float32List _vector(String text) {
    final v = Float32List(64);
    for (final raw in text.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      if (raw.length < 3) continue;
      final w = synonyms[raw] ?? raw;
      // Stopwords carry no meaning here.
      if (const {'the', 'and', 'for', 'after', 'when', 'with'}.contains(w)) {
        continue;
      }
      v[w.hashCode.abs() % 64] += 1;
    }
    final norm = sqrt(v.fold(0.0, (s, x) => s + x * x));
    if (norm > 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] /= norm;
      }
    }
    return v;
  }

  Future<List<Float32List>?> _embed(List<String> texts) async {
    calls++;
    if (!available) return null;
    return [for (final t in texts) _vector(t)];
  }

  @override
  Future<List<Float32List>?> embedDocuments(List<String> texts) =>
      _embed(texts);
  @override
  Future<List<Float32List>?> embedQueries(List<String> texts) => _embed(texts);
}

const boilerText =
    'Boiler manual.\n'
    'To reset the boiler after a lockout, hold the reset button for five seconds.\n'
    'The pressure gauge should read between one and two bar when cold.\n';
const dishwasherText =
    '# Dishwasher\nRinse aid improves drying performance on glassware.\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container(FakeEmbedder embedder) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        textEmbedderProvider.overrideWithValue(embedder),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('vectors round-trip through the blob column', () {
    final v = Float32List.fromList([0.25, -1.5, 3.0]);
    final back = Uint8List.fromList(
      KnowledgeStore.encodeVector(v),
    ).buffer.asFloat32List();
    expect(back, v);
    expect(KnowledgeStore.dot(v, v), closeTo(11.3125, 1e-6));
    expect(
      KnowledgeStore.dotBytes(v, KnowledgeStore.encodeVector(v)),
      closeTo(11.3125, 1e-6),
    );
  });

  test('reciprocal rank fusion prefers passages both rankings agree on', () {
    final order = KnowledgeStore.fuse([
      ['a', 'b', 'c'],
      ['c', 'd', 'a'],
    ]);
    // a: 1/61 + 1/63; c: 1/63 + 1/61 — tie broken by insertion (a first).
    expect(order.take(2), ['a', 'c']);
    expect(order, containsAll(['b', 'd']));
    expect(order.length, 4);
  });

  test(
    'indexing embeds every passage once and search finds paraphrases',
    () async {
      final embedder = FakeEmbedder();
      final c = container(embedder);
      final store = c.read(knowledgeStoreProvider);
      await store.import(
        collection: 'Manuals',
        name: 'boiler.txt',
        bytes: bytes(boilerText * 20),
      );
      await store.import(
        collection: 'Manuals',
        name: 'dishwasher.md',
        bytes: bytes(dishwasherText * 40),
      );
      const query = 'restart heater stuck';
      // Lexical only: no shared word, nothing found.
      expect(await KnowledgeStore(db).search('Manuals', query), isEmpty);
      // Before indexing the embedder is never consulted for a query.
      expect(await store.search('Manuals', query), isEmpty);
      expect(embedder.calls, 0);

      final indexer = c.read(knowledgeIndexerProvider.notifier);
      await indexer.index('Manuals');
      final state = c.read(knowledgeIndexerProvider);
      expect(state.running, false);
      expect(state.error, isNull);
      expect(state.done, state.total);
      final total = (await store.docsIn(
        'Manuals',
      )).fold(0, (n, d) => n + d.chunkCount);
      expect(state.done, total);
      final counts = await db.knowledgeIndexedCounts('fake-v1');
      expect(counts.values.fold(0, (a, b) => a + b), total);
      // A second run has nothing to do.
      final callsAfterIndex = embedder.calls;
      await indexer.index('Manuals');
      expect(embedder.calls, callsAfterIndex);
      expect(c.read(knowledgeIndexerProvider).total, 0);

      final hits = await store.search('Manuals', query);
      expect(hits, isNotEmpty);
      expect(hits.first.title, 'boiler.txt');
      expect(hits.first.pageText, contains('hold the reset button'));
      expect(embedder.calls, callsAfterIndex + 1);

      // Both signals: a lexical hit joins the semantic one.
      final mixed = await store.search('Manuals', 'rinse aid for glassware');
      expect(mixed.first.title, 'dishwasher.md');

      // A new embedding model invalidates the old vectors.
      final v2 = FakeEmbedder('fake-v2');
      final c2 = container(v2);
      expect(
        await db.countUnindexedKnowledgeChunks('Manuals', 'fake-v2'),
        total,
      );
      await c2.read(knowledgeIndexerProvider.notifier).index('Manuals');
      expect(await db.countUnindexedKnowledgeChunks('Manuals', 'fake-v2'), 0);
      expect(await db.knowledgeIndexedCounts('fake-v1'), isEmpty);

      // Deleting a document takes its vectors with it.
      final boiler = (await store.docsIn(
        'Manuals',
      )).firstWhere((d) => d.name == 'boiler.txt');
      await store.remove(boiler.id);
      expect(
        (await db.knowledgeIndexedCounts('fake-v2')).containsKey(boiler.id),
        false,
      );
    },
  );

  test('a missing embedding model degrades to lexical retrieval', () async {
    final embedder = FakeEmbedder()..available = false;
    final c = container(embedder);
    final store = c.read(knowledgeStoreProvider);
    await store.import(
      collection: 'Manuals',
      name: 'boiler.txt',
      bytes: bytes(boilerText * 20),
    );
    await c.read(knowledgeIndexerProvider.notifier).index('Manuals');
    expect(c.read(knowledgeIndexerProvider).error, contains('not downloaded'));
    expect(
      await db.countUnindexedKnowledgeChunks('Manuals', 'fake-v1'),
      greaterThan(0),
    );
    final hits = await store.search('Manuals', 'reset the boiler');
    expect(hits.single.title, 'boiler.txt');
  });

  test('indexing can be stopped and resumed where it left off', () async {
    final embedder = FakeEmbedder();
    final c = container(embedder);
    final store = c.read(knowledgeStoreProvider);
    await store.import(
      collection: 'Manuals',
      name: 'boiler.txt',
      bytes: bytes(boilerText * 60),
    );
    final total = (await store.docsIn('Manuals')).single.chunkCount;
    expect(total, greaterThan(KnowledgeIndexer.batch));
    final indexer = c.read(knowledgeIndexerProvider.notifier);
    final run = indexer.index('Manuals');
    indexer.cancel();
    await run;
    final done = c.read(knowledgeIndexerProvider).done;
    expect(done, lessThan(total));
    await indexer.index('Manuals');
    expect(await db.countUnindexedKnowledgeChunks('Manuals', 'fake-v1'), 0);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/zim/zim_archive.dart';
import 'package:ondevice_llm/features/zim/zim_wikipedia.dart';
import 'package:ondevice_llm/features/retrieval/domain/wikipedia_sources.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';

void main() {
  test(
    'changing officeholders prefer live evidence and label the offline fallback',
    () async {
      const old = SearchResult(
        title: 'Mayville',
        url: 'zim://Mayville',
        snippet: 'Mayor Alex',
        pageText: 'Mayor Alex',
        rank: 0,
        archiveDate: '2025-01-01',
        archiveId: 'old',
      );
      const fresh = SearchResult(
        title: 'Mayville',
        url: 'https://example.com/Mayville',
        snippet: 'Mayor Bob',
        pageText: 'Mayor Bob',
        rank: 0,
      );
      var offlineReads = 0;
      final live = await WikipediaSources.lookup(
        onlineAllowed: true,
        timely: true,
        online: () async => fresh,
        offline: () async {
          offlineReads++;
          return old;
        },
      );
      expect(live?.pageText, 'Mayor Bob');
      expect(offlineReads, 0);
      final saved = await WikipediaSources.lookup(
        onlineAllowed: false,
        timely: true,
        online: () async => throw StateError('network must stay off'),
        offline: () async => old,
      );
      expect(saved?.pageText, 'Mayor Alex');
      expect(saved?.stale, isTrue);
      expect(saved?.archiveDate, '2025-01-01');
    },
  );
  for (final path in [
    'test/fixtures/zim/libzim-modern.zim',
    'test/fixtures/zim/kiwix-wikibooks.zim',
  ]) {
    test('reads upstream archive $path', () async {
      final zim = await ZimArchive.open(path);
      addTearDown(zim.close);
      expect(zim.titleCount, greaterThan(0));
      ZimEntry? article;
      for (var i = 0; i < zim.titleCount; i++) {
        final e = await zim.entryByTitleIndex(i);
        if (e.isArticle) {
          article = e;
          break;
        }
      }
      expect(article, isNotNull);
      expect((await zim.content(article!)).isNotEmpty, isTrue);
      expect((await zim.findByTitle(article.title))?.index, article.index);
      await Future.wait([
        zim.metadata('Date'),
        zim.metadata('Language'),
        zim.metadata('Title'),
      ]);
    });
  }
  test(
    'modern listing uses its own length without a legacy title table',
    () async {
      final dir = await Directory.systemTemp.createTemp('modern-zim-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/modern.zim');
      await file.writeAsBytes(_modernZim());
      final zim = await ZimArchive.open(file.path);
      addTearDown(zim.close);
      expect(zim.titleCount, 1);
      expect((await zim.findByTitle('Eiffel Tower'))?.title, 'Eiffel Tower');
      expect(await zim.findByTitle('Missing'), isNull);
      expect(() => zim.entry(999), throwsRangeError);
      expect(() => zim.entryByTitleIndex(1), throwsRangeError);
    },
  );
  test(
    'concurrent articles, metadata and search finish before close',
    () async {
      final zim = await ZimArchive.open('test/fixtures/zim/mini.zim');
      final reads = [for (var i = 0; i < 8; i++) zim.entry(i % zim.entryCount)];
      final metadata = zim.metadata('Title');
      final article = zim.findByTitle('Paris');
      final closing = zim.close();
      expect((await Future.wait(reads)).length, 8);
      expect(await metadata, 'Wikipedia test');
      expect((await article)?.title, 'Paris');
      await closing;
      expect(() => zim.metadata('Title'), throwsStateError);
      await zim.close();
    },
  );
  test('snapshot age and language are distinct from read time', () {
    final source = ZimWikipedia.toResult(
      'Officeholder',
      '<p>The officeholder was Alex on the archive date. This long article describes the fictional city and its elected leaders.</p>',
      'Fixture',
      archiveDate: '2025-01-01',
      archiveId: 'fixture-archive-uuid',
      language: 'eng',
    )!;
    expect(source.coverage, 'archive_snapshot');
    expect(source.archiveDate, '2025-01-01');
    expect(
      source.withRank(1).withPage(text: 'excerpt').archiveId,
      'fixture-archive-uuid',
    );
    expect(
      source.withRank(1).withPage(text: 'excerpt').archiveDate,
      '2025-01-01',
    );
  });
  test('truncated header returns a useful format error', () async {
    final dir = await Directory.systemTemp.createTemp('cut-zim-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/cut.zim');
    await file.writeAsBytes(_modernZim().sublist(0, 20));
    expect(() => ZimArchive.open(file.path), throwsFormatException);
  });
}

Uint8List _modernZim() {
  Uint8List u32(int n) =>
      (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List();
  Uint8List u64(int n) =>
      (ByteData(8)..setUint64(0, n, Endian.little)).buffer.asUint8List();
  Uint8List entry(int mime, String ns, String url, String title, int blob) {
    final h = ByteData(16)
      ..setUint16(0, mime, Endian.little)
      ..setUint8(3, ns.codeUnitAt(0))
      ..setUint32(12, blob, Endian.little);
    return Uint8List.fromList([
      ...h.buffer.asUint8List(),
      ...utf8.encode(url),
      0,
      ...utf8.encode(title),
      0,
    ]);
  }

  final mime = utf8.encode('text/html\x00application/octet-stream\x00\x00');
  final a = entry(0, 'C', 'Eiffel_Tower', 'Eiffel Tower', 0);
  final x = entry(1, 'X', 'listing/titleOrdered/v1', '', 1);
  final html = utf8.encode(
    '<html><body><p>The Eiffel Tower in Paris is 330 metres tall.</p></body></html>',
  );
  final listing = u32(0);
  final cluster = [
    1,
    ...u32(12),
    ...u32(12 + html.length),
    ...u32(12 + html.length + listing.length),
    ...html,
    ...listing,
  ];
  final aPos = 80 + mime.length;
  final xPos = aPos + a.length;
  final urlPos = xPos + x.length;
  final clusterPtr = urlPos + 16;
  final clusterPos = clusterPtr + 8;
  final checksumPos = clusterPos + cluster.length;
  final header = ByteData(80)
    ..setUint32(0, 72173914, Endian.little)
    ..setUint16(4, 6, Endian.little)
    ..setUint16(6, 3, Endian.little)
    ..setUint32(24, 2, Endian.little)
    ..setUint32(28, 1, Endian.little)
    ..setUint64(32, urlPos, Endian.little)
    ..setUint64(48, clusterPtr, Endian.little)
    ..setUint64(56, 80, Endian.little)
    ..setUint32(68, 0xffffffff, Endian.little)
    ..setUint64(72, checksumPos, Endian.little);
  final body = [
    ...header.buffer.asUint8List(),
    ...mime,
    ...a,
    ...x,
    ...u64(aPos),
    ...u64(xPos),
    ...u64(clusterPos),
    ...cluster,
  ];
  return Uint8List.fromList([...body, ...md5.convert(body).bytes]);
}

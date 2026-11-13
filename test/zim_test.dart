import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ondevice_llm/features/zim/zstd.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/zim/zim_archive.dart';
import 'package:ondevice_llm/features/zim/zim_wikipedia.dart';

// test/fixtures/zim/mini.zim: four articles in a zstd cluster, metadata in
// a stored cluster with 64-bit offsets, and a redirect.
void main() {
  const path = 'test/fixtures/zim/mini.zim';

  test('reads header, metadata and articles', () async {
    final zim = await ZimArchive.open(path);
    addTearDown(zim.close);
    expect(zim.entryCount, 7);
    expect(await zim.metadata('Title'), 'Wikipedia test');
    expect(await zim.metadata('Language'), 'eng');
    expect(await zim.metadata('Creator'), isNull);
    final main = await zim.entry(zim.mainPage);
    expect(main.title, 'Eiffel Tower');
    final e = await zim.findByTitle('Paris');
    expect(e, isNotNull);
    expect(String.fromCharCodes(await zim.content(e!)), contains('2,102,650'));
    expect(await zim.findByTitle('London'), isNull);
  });

  test('ZIM XZ output is bounded by actual bytes', () async {
    final source = await File(path).readAsBytes();
    final header = ByteData.sublistView(source);
    final table = header.getUint64(48, Endian.little);
    final start = header.getUint64(table, Endian.little);
    final end = header.getUint64(table + 8, Endian.little);
    final expanded = Zstd.decode(Uint8List.sublistView(source, start + 1, end));
    final compressed = await File('test/fixtures/zim/cluster.xz').readAsBytes();
    final replacement = [4, ...compressed];
    final bytes = Uint8List.fromList([
      ...source.take(start),
      ...replacement,
      ...source.skip(end),
    ]);
    final changed = ByteData.sublistView(bytes);
    final delta = replacement.length - (end - start);
    changed.setUint64(table + 8, end + delta, Endian.little);
    changed.setUint64(
      72,
      header.getUint64(72, Endian.little) + delta,
      Endian.little,
    );
    final dir = await Directory.systemTemp.createTemp('zim-xz-limit-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/bounded.zim').writeAsBytes(bytes);
    final valid = await ZimArchive.open(file.path);
    try {
      expect(
        await valid.content(await valid.entry(valid.mainPage)),
        expanded.sublist(
          ByteData.sublistView(expanded).getUint32(0, Endian.little),
          ByteData.sublistView(expanded).getUint32(4, Endian.little),
        ),
      );
    } finally {
      await valid.close();
    }
    final zim = await ZimArchive.open(
      file.path,
      clusterByteLimit: expanded.length - 1,
    );
    addTearDown(zim.close);
    final entry = await zim.entry(zim.mainPage);
    await expectLater(
      zim.content(entry),
      throwsA(predicate((error) => error.toString().contains('safety limit'))),
    );
  });

  test('ZIM cluster cache is bounded by bytes', () async {
    final zim = await ZimArchive.open(path, cacheByteLimit: 128);
    addTearDown(zim.close);
    final entry = await zim.entry(zim.mainPage);
    await zim.content(entry);
    expect(zim.cachedClusterBytes, lessThanOrEqualTo(128));
    await zim.metadata('Title');
    expect(zim.cachedClusterBytes, lessThanOrEqualTo(128));
  });

  test('follows redirects', () async {
    final zim = await ZimArchive.open(path);
    addTearDown(zim.close);
    final e = await zim.findByTitle('Tour Eiffel');
    expect(e?.title, 'Eiffel Tower');
    expect(e?.isArticle, isTrue);
  });

  test('rejects other files', () async {
    expect(await ZimWikipedia.isZim(path), isTrue);
    expect(await ZimWikipedia.isZim('pubspec.yaml'), isFalse);
    expect(() => ZimArchive.open('pubspec.yaml'), throwsFormatException);
  });

  test('candidates come from the question', () {
    final c = ZimWikipedia.candidates('how tall is the eiffel tower?');
    expect(c, contains('Eiffel Tower'));
    expect(c.indexOf('Eiffel Tower'), lessThan(c.indexOf('Tower')));
    expect(ZimWikipedia.candidates('Nikon Z30 weight').first, 'Nikon Z30');
  });

  test('looks up the article on the subject', () async {
    final wiki = ZimWikipedia(path);
    addTearDown(wiki.close);
    final r = await wiki.lookup('How tall is the Eiffel Tower?');
    expect(r?.title, 'Eiffel Tower — Wikipedia (offline)');
    expect(r?.pageText, contains('330 metres'));
    expect(r?.pageText, isNot(contains('<p>')));
    expect(r?.source, 'Wikipedia test');
    expect(
      (await wiki.lookup('nikon z30 weight'))?.pageText,
      contains('405 g'),
    );
    // A disambiguation page and a missing subject give nothing.
    expect(await wiki.lookup('What is Mercury?'), isNull);
    expect(await wiki.lookup('Who won the 2022 World Cup?'), isNull);
  });

  group('ZIM checksum verification (S24)', () {
    const path = 'test/fixtures/zim/mini.zim';

    test('validates MD5 checksum on open', () async {
      // The fixture should pass checksum verification
      final zim = await ZimArchive.open(path);
      addTearDown(zim.close);
      expect(zim.entryCount, 7);
    });

    test('an absent (all-zero) checksum does not block normal reads', () async {
      final source = await File(
        'test/fixtures/zim/libzim-modern.zim',
      ).readAsBytes();
      final checksumPos = ByteData.sublistView(
        source,
      ).getUint64(72, Endian.little);
      final noChecksum = Uint8List.fromList(source);
      noChecksum.fillRange(checksumPos, checksumPos + 16, 0);
      final dir = await Directory.systemTemp.createTemp('zim-no-checksum-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File(
        '${dir.path}/no-checksum.zim',
      ).writeAsBytes(noChecksum);
      final zim = await ZimArchive.open(file.path);
      addTearDown(zim.close);
      expect(zim.entryCount, greaterThan(0));
      expect(zim.titleCount, greaterThan(0));
    });

    test('rejects corrupted ZIM with mismatched checksum (S24)', () async {
      final source = await File(path).readAsBytes();
      // Corrupt one byte in the content (before checksum)
      final corrupted = Uint8List.fromList(source);
      corrupted[100] ^= 0xff; // Flip bits at offset 100
      // Recalculate and update the checksum to match corrupted content
      final checksumPos = ByteData.sublistView(
        corrupted,
      ).getUint64(72, Endian.little);
      final content = corrupted.sublist(0, checksumPos);
      final newChecksum = md5.convert(content).bytes;
      for (var i = 0; i < 16; i++) {
        corrupted[checksumPos + i] = newChecksum[i];
      }
      final dir = await Directory.systemTemp.createTemp('zim-checksum-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File(
        '${dir.path}/corrupted.zim',
      ).writeAsBytes(corrupted);
      // Should open successfully since checksum now matches corrupted content
      final zim = await ZimArchive.open(file.path);
      addTearDown(zim.close);
      expect(zim.entryCount, 7);

      // Now corrupt again WITHOUT updating checksum - should fail
      final doubleCorrupted = Uint8List.fromList(corrupted);
      doubleCorrupted[101] ^= 0xff; // Flip another bit
      final file2 = await File(
        '${dir.path}/corrupted2.zim',
      ).writeAsBytes(doubleCorrupted);
      await expectLater(
        ZimArchive.open(file2.path),
        throwsA(
          predicate((error) => error.toString().contains('checksum mismatch')),
        ),
      );
    });

    test('rejects truncated checksum', () async {
      final source = await File(path).readAsBytes();
      // Truncate the file before the checksum
      final checksumPos = ByteData.sublistView(
        source,
      ).getUint64(72, Endian.little);
      final truncated = source.sublist(
        0,
        checksumPos + 8,
      ); // Only half the checksum
      final dir = await Directory.systemTemp.createTemp('zim-truncated-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File(
        '${dir.path}/truncated.zim',
      ).writeAsBytes(truncated);
      await expectLater(
        ZimArchive.open(file.path),
        throwsA(
          predicate((error) => error.toString().contains('truncated checksum')),
        ),
      );
    });
  });
}

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
}

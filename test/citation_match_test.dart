import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/citation_match.dart';

void main() {
  const sources = [
    'WHO Director-General declared COVID-19 a pandemic on 11 March 2020 '
        'at a media briefing in Geneva.',
    'The Nikon Z30 weighs 405 g with battery and memory card; the body '
        'alone weighs 350 g.',
  ];

  test('uncited sentences get the source holding their words and figures', () {
    final cited = CitationMatch.attach(
      'The WHO declared COVID-19 a pandemic on 11 March 2020. '
      'The Nikon Z30 body weighs 350 g.',
      sources,
    );
    expect(
      cited,
      'The WHO declared COVID-19 a pandemic on 11 March 2020 [1]. '
      'The Nikon Z30 body weighs 350 g [2].',
    );
  });

  test('an abbreviation inside a sentence does not end it', () {
    expect(
      CitationMatch.attach(
        'The Nintendo Switch 2 price in the U.S. is 449.99 dollars.',
        ['Nintendo Switch 2 price in the U.S. is 449.99 dollars at launch.'],
      ),
      'The Nintendo Switch 2 price in the U.S. is 449.99 dollars [1].',
    );
  });

  test('a figure no source has leaves the sentence uncited', () {
    expect(
      CitationMatch.attach('The Nikon Z30 body weighs 390 g.', sources),
      'The Nikon Z30 body weighs 390 g.',
    );
  });

  test('cited answers, tables, code and small talk are left alone', () {
    const already = 'The WHO declared a pandemic in 2020 [1].';
    expect(CitationMatch.attach(already, sources), already);
    const table = '| Camera | Weight |\n|---|---|\n| Nikon Z30 body | 350 g |';
    expect(CitationMatch.attach(table, sources), table);
    expect(CitationMatch.attach('Sure!', sources), 'Sure!');
    expect(
      CitationMatch.attach('- **Weight:** the Nikon Z30 body weighs 350 g', [
        sources[1],
      ]),
      '- **Weight:** the Nikon Z30 body weighs 350 g [1]',
    );
  });

  test('a source line ending in a semicolon is read, not a crash', () {
    // An SEC page read on the phone (D1 benchmark, finance-sec-10k) threw
    // "No element" here and failed the whole send.
    expect(
      CitationMatch.attach('The Form 10-K is filed once a year.', [
        'Form 10-K;\nThe Form 10-K is filed once a year with the SEC;\n;',
      ]),
      'The Form 10-K is filed once a year [1].',
    );
  });
}

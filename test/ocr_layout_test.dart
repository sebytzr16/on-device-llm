import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/ocr_layout.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';

OcrLine line(String text, double left, double top, {double? right}) => OcrLine(
  text,
  left: left,
  top: top,
  right: right ?? left + text.length * 10,
  bottom: top + 20,
);

void main() {
  test('a receipt amount joins the label on its row', () {
    // ML Kit's order: the labels block, then the amounts block.
    final text = OcrLayout.paired([
      line('Berghotel', 100, 0),
      line('2xLatte Macchiato', 20, 100),
      line('1xChässpätzli', 20, 140),
      line('Total : CHF', 20, 200),
      line('9.00', 400, 101),
      line('18.50 CHF', 380, 139),
      line('54.50', 400, 203),
    ]);
    expect(
      text,
      'Berghotel\n'
      '2xLatte Macchiato  9.00\n'
      '1xChässpätzli  18.50 CHF\n'
      'Total : CHF  54.50',
    );
  });

  test('two columns of prose are not interleaved', () {
    final lines = [
      line('The first column starts here and', 0, 0),
      line('goes on to its second line.', 0, 30),
      line('The second column is next to it', 400, 0),
      line('and has 2 lines as well.', 400, 30),
    ];
    expect(OcrLayout.paired(lines), lines.map((l) => l.text).join('\n'));
  });

  test('an amount with nothing to its left stays where it is', () {
    expect(
      OcrLayout.paired([line('Opening hours', 0, 0), line('9-17', 0, 40)]),
      'Opening hours\n9-17',
    );
  });

  test('tilted text is left as ML Kit read it', () {
    expect(
      OcrLayout.paired([
        const OcrLine(
          'Total',
          left: 0,
          top: 0,
          right: 50,
          bottom: 20,
          angle: 14,
        ),
      ]),
      isNull,
    );
  });

  test('a reading with line boxes uses the paired text', () {
    final reading = OcrReading.fromJson({
      'text': 'Total : CHF\n54.50',
      'confidence': 0.8,
      'lines': [
        {
          'text': 'Total : CHF',
          'left': 0,
          'top': 0,
          'right': 110,
          'bottom': 20,
        },
        {'text': '54.50', 'left': 300, 'top': 2, 'right': 350, 'bottom': 22},
      ],
    });
    expect(reading.text, 'Total : CHF  54.50');
    expect(reading.confidence, 0.8);
    // An older reply without boxes keeps ML Kit's text.
    expect(OcrReading.fromJson({'text': 'a\nb'}).text, 'a\nb');
  });
}

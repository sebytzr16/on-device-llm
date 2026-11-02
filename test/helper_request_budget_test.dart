import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/helper/helper_request.dart';

void main() {
  test('short task and context are preserved', () {
    expect(
      HelperRequest.content('Summarize', 'A short page.'),
      'Summarize\n\n---\nA short page.',
    );
    expect(HelperRequest.content('Only a task', ''), 'Only a task');
  });

  test(
    'combined budget keeps the head and a relevant passage with a cut marker',
    () {
      final input =
          'Page title\n${'filler ' * 1800}'
          'Battery warranty covers replacement for five years.\n${'other ' * 1500}';
      final result = HelperRequest.content(
        'Extract battery warranty terms',
        input,
      );
      expect(result.length, lessThanOrEqualTo(HelperRequest.contentBudget));
      expect(result, contains('Page title'));
      expect(result, contains('Battery warranty covers replacement'));
      expect(result, contains('[Excerpt cut to helper budget]'));
    },
  );

  test(
    'dense scripts get half the budget, unmatched pages keep a full tail',
    () {
      final cjk = HelperRequest.content('総括', '漢字' * 3000);
      expect(cjk.length, lessThanOrEqualTo(HelperRequest.contentBudget ~/ 2));
      final page = HelperRequest.content(
        'Extract nothing relevant',
        'Head\n${'x' * 9000}THE END',
      );
      expect(page, endsWith('THE END'));
      expect(page.length, greaterThan(HelperRequest.contentBudget - 100));
    },
  );

  test('oversized tasks and Unicode context also fit the combined budget', () {
    for (final input in ['', '😀' * 6000, 'a' * 4800]) {
      final result = HelperRequest.content('😀task ' * 2000, input);
      expect(result.length, lessThanOrEqualTo(HelperRequest.contentBudget));
      expect(utf8.decode(utf8.encode(result)), result);
      expect(result, contains('[Excerpt cut to helper budget]'));
    }
  });
}

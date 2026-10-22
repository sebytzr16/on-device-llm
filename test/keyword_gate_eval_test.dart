import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/retrieval_plan.dart';
import 'package:ondevice_llm/features/retrieval/domain/news_intent.dart';
import 'package:ondevice_llm/features/tools/domain/tool_aliases.dart';

/// Scores the keyword gates against `eval/keyword_cases.json` and prints
/// every miss, so a change to a word list is judged by numbers. The floors
/// are the measured baseline: a change may raise them, never lower them.
void main() {
  final cases =
      jsonDecode(File('eval/keyword_cases.json').readAsStringSync()) as Map;

  ({int tp, int fp, int fn, int tn, List<String> misses}) score(
    List cases,
    String label,
    bool Function(String) predict,
  ) {
    var tp = 0, fp = 0, fn = 0, tn = 0;
    final misses = <String>[];
    for (final c in cases.cast<Map>()) {
      final want = c[label] as bool, got = predict(c['text'] as String);
      if (want && got) tp++;
      if (!want && got) fp++;
      if (want && !got) fn++;
      if (!want && !got) tn++;
      if (want != got) {
        misses.add('${want ? 'MISSED' : 'FALSE+'} [${c['lang']}] ${c['text']}');
      }
    }
    return (tp: tp, fp: fp, fn: fn, tn: tn, misses: misses);
  }

  String report(
    String name,
    ({int tp, int fp, int fn, int tn, List<String> misses}) s,
  ) {
    final total = s.tp + s.fp + s.fn + s.tn;
    final precision = s.tp + s.fp == 0 ? 1.0 : s.tp / (s.tp + s.fp);
    final recall = s.tp + s.fn == 0 ? 1.0 : s.tp / (s.tp + s.fn);
    return 'KEYWORD $name: accuracy ${((s.tp + s.tn) / total * 100).toStringAsFixed(1)}% '
        '(${s.tp + s.tn}/$total) precision ${(precision * 100).toStringAsFixed(0)}% '
        'recall ${(recall * 100).toStringAsFixed(0)}%\n  ${s.misses.join('\n  ')}';
  }

  test('web gate: searches when it should, stays quiet otherwise', () {
    final all = cases['web'] as List;
    for (final lang in ['en', 'fr', 'es']) {
      final s = score(
        all.where((c) => c['lang'] == lang).toList(),
        'web',
        (t) => RetrievalPlan.of(t, webEnabled: true).wantsWeb,
      );
      // ignore: avoid_print
      print(report('web/$lang', s));
    }
    final s = score(
      all,
      'web',
      (t) => RetrievalPlan.of(t, webEnabled: true).wantsWeb,
    );
    expect(s.fp, lessThanOrEqualTo(_floors['webFalsePositives']!));
    expect(s.tp + s.tn, greaterThanOrEqualTo(_floors['webCorrect']!));
  });

  test('web gate on the held-out set (never tuned against)', () {
    final s = score(
      cases['web_holdout'] as List,
      'web',
      (t) => RetrievalPlan.of(t, webEnabled: true).wantsWeb,
    );
    // ignore: avoid_print
    print(report('web/holdout', s));
    expect(s.fp, lessThanOrEqualTo(_floors['holdoutFalsePositives']!));
    expect(s.tp + s.tn, greaterThanOrEqualTo(_floors['holdoutCorrect']!));
  });

  test('web gate on the second held-out set (never tuned against)', () {
    final s = score(
      cases['web_holdout2'] as List,
      'web',
      (t) => RetrievalPlan.of(t, webEnabled: true).wantsWeb,
    );
    // ignore: avoid_print
    print(report('web/holdout2', s));
    expect(s.fp, lessThanOrEqualTo(_floors['holdout2FalsePositives']!));
    expect(s.tp + s.tn, greaterThanOrEqualTo(_floors['holdout2Correct']!));
  });

  test('web gate stays quiet on trap-word general questions', () {
    final s = score(
      cases['web_negatives'] as List,
      'web',
      (t) => RetrievalPlan.of(t, webEnabled: true).wantsWeb,
    );
    // ignore: avoid_print
    print(report('web/negatives', s));
    expect(s.fp, lessThanOrEqualTo(_floors['negativesFalsePositives']!));
  });

  test('web gate on questions sent to the web by hand in phone tests', () {
    final s = score(
      cases['web_phone_misses'] as List,
      'web',
      (t) => RetrievalPlan.of(t, webEnabled: true).wantsWeb,
    );
    // ignore: avoid_print
    print(report('web/phone-misses', s));
    expect(s.tp + s.tn, greaterThanOrEqualTo(_floors['phoneMissesCorrect']!));
  });

  test('news intent: briefings and topics, not news-shaped tasks', () {
    final s = score(
      cases['news'] as List,
      'news',
      (t) => NewsIntent.of(t) != null,
    );
    // ignore: avoid_print
    print(report('news', s));
    expect(s.tp + s.tn, greaterThanOrEqualTo(_floors['newsCorrect']!));
  });

  test('tool aliases map what models call our tools', () {
    var right = 0;
    final misses = <String>[];
    for (final c in (cases['tools'] as List).cast<Map>()) {
      final got = ToolAliases.name(c['name'] as String);
      if (got == c['tool']) {
        right++;
      } else {
        misses.add('${c['name']} → $got (want ${c['tool']})');
      }
    }
    // ignore: avoid_print
    print(
      'KEYWORD tools: $right/${(cases['tools'] as List).length}\n  ${misses.join('\n  ')}',
    );
    expect(right, greaterThanOrEqualTo(_floors['toolsCorrect']!));
  });
}

const _floors = {
  // 2026-09-24: the Search-the-web log from the tester's phone (how old /
  // birthday of a public figure) plus paraphrases in EN/FR/ES.
  'phoneMissesCorrect': 12,
  // 2026-09-24, after the category lists (web_terms.dart) and the concept /
  // personal-time guards. Tuned set: 96/96.
  'webCorrect': 96,
  'webFalsePositives': 0,
  // First held-out set: 26/36 before the lists; its misses were visible
  // while they were written, so 36/36 is no longer an unbiased estimate.
  'holdoutCorrect': 36,
  'holdoutFalsePositives': 0,
  // Second held-out set, written before the lists and never tuned: 42/42.
  'holdout2Correct': 42,
  'holdout2FalsePositives': 0,
  // Trap-word general questions that must not search: 0/50 searched.
  'negativesFalsePositives': 0,
  'newsCorrect': 30,
  'toolsCorrect': 33,
};

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/retrieval/claim_check_runner.dart';
import 'package:ondevice_llm/features/retrieval/domain/claim_check.dart';
import 'package:ondevice_llm/features/retrieval/support_check.dart';
import 'package:ondevice_llm/l10n/app_localizations_en.dart';

class _Judge implements SupportJudge {
  _Judge(this.answer, {this.fails = false});
  final double Function(String claim, String passage) answer;
  final bool fails;
  final asked = <({String claim, String passage})>[];

  @override
  Future<List<double>?> judge(
    List<({String claim, String passage})> pairs, {
    required bool Function() expired,
  }) async {
    if (fails) throw StateError('native failure');
    asked.addAll(pairs);
    return [for (final p in pairs) answer(p.claim, p.passage)];
  }
}

const _text =
    'The Eiffel Tower was completed in 1889 for the World\'s Fair in Paris. '
    'Designed by the company of Gustave Eiffel, it was the tallest '
    'man-made structure until the Chrysler Building was finished in 1930.';

const _sources = [
  SearchResult(
    title: 'Eiffel Tower',
    url: 'https://en.wikipedia.org/wiki/Eiffel_Tower',
    snippet: '',
    source: 'Wikipedia',
    rank: 1,
    pageText: _text,
  ),
];

void main() {
  test('yes and no logits become the probability of yes', () {
    expect(SupportCheck.probability({'yes': 0, 'no': 0}), closeTo(0.5, 1e-9));
    expect(SupportCheck.probability({'yes': 4, 'no': -1}), greaterThan(0.99));
    expect(SupportCheck.probability({'yes': -3, 'no': 2}), lessThan(0.01));
    expect(SupportCheck.probability({'0': 2}), greaterThan(0.85));
    expect(SupportCheck.probability({}), 0);
  });

  test('the closest passage of each source is offered, best first', () {
    final w = SupportCheck.windows(
      'It stayed the tallest man-made structure until 1930.',
      [
        const SearchResult(
          title: 'Louvre',
          url: 'https://example.org/louvre',
          snippet: 'The Louvre is a museum in Paris.',
          source: 'Example',
          rank: 1,
        ),
        _sources.first,
      ],
    );
    expect(w.first.source, 1);
    expect(w.first.passage, contains('tallest'));
    expect(w.first.passage.length, lessThanOrEqualTo(SupportCheck.maxPassage));
  });

  test('a paraphrase the model confirms is no longer flagged', () async {
    const answer = 'Gustave Eiffel\'s firm drew up its plans.';
    final plain = await ClaimCheckRunner.run(answer, _sources);
    expect(plain.single.status, isNot(ClaimStatus.supported));
    final judge = _Judge((_, _) => 0.93);
    final verdicts = await ClaimCheckRunner.run(answer, _sources, judge: judge);
    expect(judge.asked, isNotEmpty);
    expect(verdicts.single.status, ClaimStatus.supported);
    expect(verdicts.single.support, closeTo(0.93, 1e-9));
    expect(verdicts.single.source, 0);
    expect(ClaimCheckRunner.notice(verdicts, AppLocalizationsEn()), isNull);
  });

  test('an unsure judgement leaves the flag and records its score', () async {
    const answer = 'Gustave Eiffel\'s firm drew up its plans.';
    final plain = await ClaimCheckRunner.run(answer, _sources);
    final verdicts = await ClaimCheckRunner.run(
      answer,
      _sources,
      judge: _Judge((_, _) => 0.55),
    );
    expect(verdicts.single.status, plain.single.status);
    expect(verdicts.single.support, closeTo(0.55, 1e-9));
  });

  test('a possessive name is the name the sources have', () {
    expect(
      ClaimCheck.novelDetails("It was the work of Gustave Eiffel's firm.", [
        _text,
      ]),
      isEmpty,
    );
  });

  test('names the sources lack are never sent to the model', () async {
    final judge = _Judge((_, _) => 0.99);
    final verdicts = await ClaimCheckRunner.run(
      'The tower was repainted for the 1900 Olympic Games in Paris.',
      _sources,
      judge: judge,
    );
    expect(verdicts.single.status, ClaimStatus.novelDetails);
    expect(judge.asked, isEmpty);
  });

  test('a failing model keeps the word check verdicts', () async {
    const answer = 'Gustave Eiffel\'s firm drew up its plans.';
    final plain = await ClaimCheckRunner.run(answer, _sources);
    final verdicts = await ClaimCheckRunner.run(
      answer,
      _sources,
      judge: _Judge((_, _) => 1, fails: true),
    );
    expect(verdicts.single.status, plain.single.status);
    expect(verdicts.single.support, isNull);
  });

  test('the source-check model is pinned', () {
    expect(supportCheckModel.downloadUrl, contains('/resolve/'));
    expect(
      supportCheckModel.downloadUrl,
      matches(RegExp(r'/resolve/[0-9a-f]{40}/')),
    );
    expect(supportCheckModel.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(supportCheckModel.sizeBytes, greaterThan(500 * 1024 * 1024));
  });
}

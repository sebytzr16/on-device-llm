import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/settings/domain/battery_saver.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/presentation/setting_labels.dart';
import 'package:ondevice_llm/features/chat/domain/answer_checks.dart';

void main() {
  test('chat notices follow the Settings language', () {
    final fr = stringsFor('fr'), es = stringsFor('es');
    expect(
      AnswerChecks.groundingNotice('Le ciel est bleu.', 2, fr),
      contains('aucune des 2 sources'),
    );
    expect(
      AnswerChecks.searchFailureNotice(const SearchChallengeException('x'), es),
      startsWith('DuckDuckGo pidió'),
    );
    expect(BatterySaver.notice('battery 18%', fr), contains('batterie 18 %'));
    expect(BatterySaver.notice('phone hot: severe', es), contains('caliente'));
    expect(fr.noticeTrimmed(1), startsWith('1 message antérieur a été omis'));
  });

  test('a figure another source has is mis-cited, not unfounded', () {
    // Phone, 2026-10-04: the Z30 table row cited a comparison page for
    // "20.9 MP"; only the Wikipedia article (source 2 here) had it.
    SearchResult s(String text, int rank) => SearchResult(
      title: 'source $rank',
      url: 'https://s$rank.test/',
      snippet: '',
      rank: rank,
      pageText: text,
    );
    final sources = [
      s('Nikon Z30 vs Sony ZV-E10: 21MP vs 24.2MP sensors.', 1),
      s('The camera yields an effective 20.9-megapixel still image.', 2),
    ];
    final miscited = AnswerChecks.figureNotice(
      '| Sensor | 20.9 MP [1] | 24.2 MP [1] |',
      sources,
    );
    expect(miscited, startsWith('Not in the source cited for them: 20.9.'));
    expect(
      AnswerChecks.figureNotice('| Sensor | 26.1 MP [1] |', sources),
      startsWith('Not found in the sources: 26.1.'),
    );
    expect(
      AnswerChecks.figureNotice('| Sensor | 20.9 MP [2] |', sources),
      isNull,
    );
  });

  test('English stays the default and unknown languages fall back to it', () {
    expect(stringsFor('de').noticeSearching, 'Searching DuckDuckGo…');
    expect(
      BatterySaver.notice('battery 18%'),
      'Battery saver (battery 18%): no thinking, answers up to '
      '${BatterySaver.maxTokens} tokens, fewer pages read.',
    );
  });

  test('every overridable setting has a label in each language', () {
    for (final code in ['en', 'fr', 'es']) {
      final t = stringsFor(code);
      for (final spec in SettingSpec.all) {
        expect(spec.labelIn(t), isNotEmpty);
        if (code == 'en') expect(spec.labelIn(t), spec.label);
      }
      for (final g in SettingSpec.groups) {
        expect(settingGroupLabel(g, t), isNotEmpty);
      }
    }
    expect(
      SettingSpec.all.first.labelIn(stringsFor('fr')),
      isNot('Custom instructions'),
    );
  });
}

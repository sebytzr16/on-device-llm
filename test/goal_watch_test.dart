import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/search_models.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/goal_watch.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_watch_provider.dart';
import 'package:ondevice_llm/features/schedule/scheduled_prompt.dart';
import 'package:ondevice_llm/features/tools/phone_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Audit 2026-10-08 G2: a watch has its own baseline, last result, schedule
// and change rule.
SearchResult _r(String url, String snippet, {String title = ''}) =>
    SearchResult(
      title: title.isEmpty ? url : title,
      url: url,
      snippet: snippet,
      rank: 0,
    );

void main() {
  test('figures: money, units and percentages, not bare years', () {
    expect(
      GoalWatches.figures(
        'In 2026 the Switch 2 costs \$499.99 (was \$449.99), weighs 534 g, '
        'and 12 stores list it; 23% off at 3 shops.',
      ),
      ['\$499.99', '\$449.99', '534 g', '23%'],
    );
  });

  test('a new page and a changed figure are changes; the same page is not', () {
    final before = GoalWatches.snapshot([
      _r('https://shop.example/switch2?ref=1', 'Price \$449.99'),
      _r('https://news.example/a', 'Launch news'),
    ], DateTime(2026, 10, 8, 9));
    final now = GoalWatches.snapshot([
      _r('https://shop.example/switch2/', 'Price \$499.99'),
      _r('https://news.example/a', 'Launch news'),
      _r('https://news.example/b', 'Price rise announced'),
    ], DateTime(2026, 10, 9, 9));
    final change = GoalWatches.diff(before, now);
    expect(change.fresh.map((i) => i.url), ['https://news.example/b']);
    expect(change.figures.single.before, ['\$449.99']);
    expect(change.figures.single.after, ['\$499.99']);

    final same = GoalWatches.diff(now, now);
    expect(same.isEmpty, isTrue);
  });

  test('two articles on one path are two pages (audit 05a-5)', () {
    expect(
      GoalWatches.pageKey('https://news.example/item?id=1'),
      isNot(GoalWatches.pageKey('https://news.example/item?id=2')),
    );
    // Tracking parameters and the scheme still do not make a new page.
    expect(
      GoalWatches.pageKey('https://www.news.example/item/?id=1&utm_source=x'),
      GoalWatches.pageKey('http://news.example/item?id=1'),
    );
    // The runner and the daily watches count the same pages.
    for (final url in [
      'https://www.news.example/item/?id=1&utm_source=x',
      'http://news.example/item?id=2',
      'https://example.com',
    ]) {
      expect(GoalRunner.pageKey(url), GoalWatches.pageKey(url));
    }
  });

  test('a page seen in an earlier check is not new again', () {
    final w0 = GoalWatch(
      id: 1,
      objective: 'Switch 2 price',
      query: 'Switch 2 price',
      hour: 9,
      minute: 0,
      createdAt: DateTime(2026, 10, 7),
    );
    final w1 = w0.checked(
      GoalWatches.snapshot([
        _r('https://a.example', 'x'),
      ], DateTime(2026, 10, 7)),
    );
    expect(w1.lastChange, isNull); // the baseline
    final w2 = w1.checked(
      GoalWatches.snapshot([
        _r('https://b.example', 'y'),
      ], DateTime(2026, 10, 8)),
    );
    expect(w2.lastChange!.fresh.single.url, 'https://b.example');
    final w3 = w2.checked(
      GoalWatches.snapshot([
        _r('https://a.example', 'x'),
      ], DateTime(2026, 10, 9)),
    );
    expect(w3.lastChange!.isEmpty, isTrue);
    // And it survives saving.
    final back = GoalWatches.decode(GoalWatches.encode([w3])).single;
    expect(back.seen, containsAll(['a.example', 'b.example']));
    expect(back.lastCheckedAt, DateTime(2026, 10, 9));
  });

  test('a page saved before the key kept its query is not new', () {
    // A watch upgraded from a build whose keys were host/path (audit 05a-5)
    // must not report a page it already saw as a new result once.
    final change = GoalWatches.diff(
      GoalWatches.snapshot([
        _r('https://news.example/b', 'older result'),
      ], DateTime(2026, 11, 20, 9)),
      GoalWatches.snapshot([
        _r('https://news.example/item?id=1', 'Price \$499.99'),
      ], DateTime(2026, 11, 20, 10)),
      ['news.example/item', 'news.example/b'],
    );
    expect(change.fresh, isEmpty);
    // A page that key does not name is still new.
    final other = GoalWatches.diff(
      GoalWatches.snapshot(const [], DateTime(2026, 11, 20, 9)),
      GoalWatches.snapshot([
        _r('https://news.example/new?id=7', 'Just listed'),
      ], DateTime(2026, 11, 20, 10)),
      ['news.example/item'],
    );
    expect(other.fresh.single.url, 'https://news.example/new?id=7');
  });

  test('due once the scheduled time has passed since the last check', () {
    final w = GoalWatch(
      id: 1,
      objective: 'x',
      query: 'x',
      hour: 9,
      minute: 0,
      createdAt: DateTime(2026, 10, 7),
      lastCheckedAt: DateTime(2026, 10, 8, 9, 30),
    );
    expect(w.dueAt(DateTime(2026, 10, 8, 23)), isFalse);
    expect(w.dueAt(DateTime(2026, 10, 9, 8, 59)), isFalse);
    expect(w.dueAt(DateTime(2026, 10, 9, 9, 1)), isTrue);
  });

  test('watching takes a baseline; a check compares with it', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(goalWatchProvider.notifier);
    var snippet = 'Price \$449.99';
    n.searchOverride = (_) async => [
      _r('https://shop.example/switch2', snippet),
    ];
    await n.watch(
      'Find the Switch 2 price and save it as a CSV',
      const ScheduledPrompt(id: 7, prompt: 'p', hour: 9, minute: 0),
    );
    // The first check runs in the background.
    for (var i = 0; i < 20 && n.isChecking(7); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final w = container.read(goalWatchProvider).single;
    expect(w.query, 'Find the Switch 2 price');
    expect(w.last!.items.single.figures, ['\$449.99']);
    snippet = 'Price \$499.99';
    await n.check(7);
    final after = container.read(goalWatchProvider).single;
    expect(after.lastChange!.figures.single.after, ['\$499.99']);
    final saved = (await SharedPreferences.getInstance()).getString(
      'goal_watches_v1',
    )!;
    expect(jsonDecode(saved), hasLength(1));
  });

  test('an opened action is recorded and saved with the goal', () {
    final goal = GoalProgress(
      spec: const GoalSpec(objective: 'Remind me', successCriteria: ''),
      status: GoalStatus.completed,
      steps: 1,
      startedAt: DateTime(2026, 10, 8),
      actions: const [
        PhoneAction('set_timer', {'minutes': 5}),
      ],
      actionOutcomes: {
        0: GoalActionOutcome(opened: true, at: DateTime(2026, 10, 8, 21, 40)),
      },
    );
    final back = GoalNotifier.decode(
      jsonDecode(jsonEncode(GoalNotifier.encode(goal))) as Map<String, dynamic>,
    );
    expect(back.actionOutcomes[0]!.opened, isTrue);
    expect(back.actionOutcomes[0]!.at, DateTime(2026, 10, 8, 21, 40));
    // New actions start without outcomes.
    expect(goal.copyWith(actions: const []).actionOutcomes, isEmpty);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/tips/tips_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore({this.writeResult = true, this.writeThrows = false})
    : super.empty();

  final bool writeResult;
  final bool writeThrows;
  int writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'tips_enabled_v1' || key == 'tips_seen_v1') {
      writes++;
      if (writeThrows) throw StateError('Storage full');
      return writeResult;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesStorePlatform previousStore;
  setUp(() {
    TipsNotifier.showInTests = true;
    previousStore = SharedPreferencesStorePlatform.instance;
  });
  tearDown(() {
    SharedPreferencesStorePlatform.instance = previousStore;
  });

  Future<TipsNotifier> notifierFor(ProviderContainer container) async {
    final notifier = container.read(tipsProvider.notifier);
    await notifier.loaded;
    return notifier;
  }

  group('TipsState', () {
    test('default shouldShow returns true for unseen tip', () {
      const state = TipsState();
      expect(state.shouldShow('any.id'), isTrue);
    });

    test('shouldShow returns false when disabled', () {
      const state = TipsState(enabled: false);
      expect(state.shouldShow('any.id'), isFalse);
    });

    test('shouldShow returns false when already seen', () {
      const state = TipsState(seen: {'tip.id'});
      expect(state.shouldShow('tip.id'), isFalse);
    });

    test('shouldShow returns false when another tip is showing', () {
      const state = TipsState(showing: 'other.id');
      expect(state.shouldShow('tip.id'), isFalse);
    });

    test('shouldShow returns true when same tip is showing', () {
      const state = TipsState(showing: 'tip.id');
      expect(state.shouldShow('tip.id'), isTrue);
    });
  });

  group('TipsNotifier', () {
    test('claim allows first tip, blocks second different tip', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      expect(notifier.claim('tip.a'), isTrue);
      expect(notifier.claim('tip.b'), isFalse);
      expect(container.read(tipsProvider).showing, 'tip.a');
    });

    test('dismiss persists and survives fresh container', () async {
      SharedPreferences.setMockInitialValues({});
      {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = await notifierFor(container);

        notifier.claim('tip.x');
        await notifier.dismiss('tip.x');

        expect(container.read(tipsProvider).seen, contains('tip.x'));
        expect(container.read(tipsProvider).showing, isNull);
      }
      // Fresh container - data should persist
      {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await notifierFor(container);

        expect(container.read(tipsProvider).seen, contains('tip.x'));
      }
    });

    test('dismissAll marks multiple tips as seen', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      await notifier.dismissAll(['tip.1', 'tip.2', 'tip.3']);

      expect(
        container.read(tipsProvider).seen,
        containsAll(['tip.1', 'tip.2', 'tip.3']),
      );
    });

    test(
      'setEnabled(false) hides everything and nextIn returns null',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = await notifierFor(container);

        await notifier.setEnabled(false);

        expect(container.read(tipsProvider).enabled, isFalse);
        expect(notifier.nextIn(['tip.a', 'tip.b']), isNull);
        expect(notifier.claim('tip.a'), isFalse);
      },
    );

    test('resetAll brings tips back', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      await notifier.dismissAll(['tip.a', 'tip.b']);
      await notifier.setEnabled(false);
      await notifier.resetAll();

      final state = container.read(tipsProvider);
      expect(state.enabled, isTrue);
      expect(state.seen, isEmpty);
      expect(state.showing, isNull);
      expect(notifier.nextIn(['tip.a', 'tip.b']), 'tip.a');
    });

    test('nextIn returns first unseen tip in order', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      await notifier.dismiss('tip.b');
      expect(notifier.nextIn(['tip.a', 'tip.b', 'tip.c']), 'tip.a');

      await notifier.dismiss('tip.a');
      expect(notifier.nextIn(['tip.a', 'tip.b', 'tip.c']), 'tip.c');

      await notifier.dismiss('tip.c');
      expect(notifier.nextIn(['tip.a', 'tip.b', 'tip.c']), isNull);
    });

    test('persistence failure does not revert state', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _FailingStore(writeResult: false);
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      await notifier.dismiss('tip.fail');

      expect(container.read(tipsProvider).seen, contains('tip.fail'));
      expect(store, isNotNull);
    });

    test('dismiss and release free the slot for the next tip', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      expect(notifier.claim('tip.a'), isTrue);
      await notifier.dismiss('tip.a');
      expect(container.read(tipsProvider).showing, isNull);
      expect(notifier.claim('tip.b'), isTrue);
      notifier.release('tip.b');
      expect(container.read(tipsProvider).showing, isNull);
      expect(container.read(tipsProvider).seen, isNot(contains('tip.b')));
      expect(notifier.claim('tip.b'), isTrue);
    });

    test('persistence exception does not revert state', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FailingStore(
        writeThrows: true,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      await notifier.dismiss('tip.exc');

      expect(container.read(tipsProvider).seen, contains('tip.exc'));
    });
  });
}

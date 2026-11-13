import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/first_launch_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _key = 'onboarding_done_v1';

/// A prefs store whose writes of the onboarding flag can fail.
class _WriteStore extends InMemorySharedPreferencesStore {
  _WriteStore({this.writeResult = true, this.writeThrows = false})
    : super.empty();

  final bool writeResult;
  final bool writeThrows;
  int writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith(_key)) {
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
    previousStore = SharedPreferencesStorePlatform.instance;
  });
  tearDown(() {
    SharedPreferencesStorePlatform.instance = previousStore;
  });

  Future<OnboardingNotifier> notifierFor(ProviderContainer container) async {
    await container.read(onboardingDoneProvider.future);
    return container.read(onboardingDoneProvider.notifier);
  }

  group('OnboardingNotifier', () {
    test('complete() returns true and persists on success', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      final result = await notifier.complete();

      expect(result, isTrue);
      expect(container.read(onboardingDoneProvider).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_key), isTrue);
    });

    test(
      'complete() returns false and reverts state on write failure',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = _WriteStore(writeResult: false);
        SharedPreferencesStorePlatform.instance = store;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = await notifierFor(container);

        final result = await notifier.complete();

        expect(result, isFalse);
        expect(container.read(onboardingDoneProvider).value, isFalse);
        expect(store.writes, 1);
      },
    );

    test('complete() returns false and reverts state on exception', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _WriteStore(writeThrows: true);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      final result = await notifier.complete();

      expect(result, isFalse);
      expect(container.read(onboardingDoneProvider).value, isFalse);
    });
  });
}

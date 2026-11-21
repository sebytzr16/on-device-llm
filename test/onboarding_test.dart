import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/providers/first_launch_provider.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/onboarding/presentation/screens/onboarding_screen.dart';
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

/// The first onboarding write fails, the retry succeeds.
class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore() : super.empty();

  int writes = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith(_key)) {
      writes++;
      if (writes == 1) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

/// Onboarding only needs the catalog and the device memory to build.
class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState();
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

    test(
      'a failed write never publishes true, so the screen can offer Retry',
      () async {
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = _WriteStore(
          writeResult: false,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = await notifierFor(container);
        final seen = <bool?>[];
        container.listen(
          onboardingDoneProvider,
          (_, next) => seen.add(next.value),
          fireImmediately: true,
        );

        final result = await notifier.complete();

        expect(result, isFalse);
        // The app root watches this provider and unmounts onboarding on true:
        // a transient true would drop the user at step 0 (audit 08d-1).
        expect(seen, isNot(contains(true)));
        expect(container.read(onboardingDoneProvider).value, isFalse);
      },
    );

    test('completeForSession() finishes without another write', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _WriteStore(writeResult: false);
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = await notifierFor(container);

      notifier.completeForSession();

      expect(container.read(onboardingDoneProvider).value, isTrue);
      expect(store.writes, 0);
    });
  });

  group('OnboardingScreen', () {
    Future<void> pump(WidgetTester tester, ProviderContainer container) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Retry writes the flag again after the first write failed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = _FlakyStore();
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer(
        overrides: [
          modelManagerProvider.overrideWith(_Models.new),
          deviceMemoryProvider.overrideWith(
            (ref) async => const DeviceMemory(
              totalBytes: 8 << 30,
              availableBytes: 8 << 30,
              lowMemory: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pump(tester, container);

      // Skip finishes onboarding; the first write fails and offers Retry.
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(store.writes, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // The retry reached storage, so onboarding stays done (audit 08d-1).
      expect(store.writes, 2);
      expect(find.text('Retry'), findsNothing);
      expect(container.read(onboardingDoneProvider).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_key), isTrue);
    });

    testWidgets('"Continue for this session" leaves onboarding for this run', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final store = _WriteStore(writeResult: false);
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer(
        overrides: [
          modelManagerProvider.overrideWith(_Models.new),
          deviceMemoryProvider.overrideWith(
            (ref) async => const DeviceMemory(
              totalBytes: 8 << 30,
              availableBytes: 8 << 30,
              lowMemory: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await pump(tester, container);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue for this session'));
      await tester.pumpAndSettle();

      // The screen is gone for this run, and nothing was persisted. The legacy
      // prefs API caches a value before the store confirms it, so the flag is
      // read from the store: that is what the next start loads.
      expect(container.read(onboardingDoneProvider).value, isTrue);
      expect((await store.getAll()).containsKey('flutter.$_key'), isFalse);
      expect(store.writes, 1);
    });
  });
}

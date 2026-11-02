import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/remote_profile_page.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      remoteProfiles: [
        RemoteProfile(
          id: 'remote',
          name: 'Remote',
          model: 'a',
          limits: {
            'a': RemoteLimit(perMinute: 5, perDay: 50),
            'b': RemoteLimit(perMinute: 9, perDay: 90),
          },
        ),
      ],
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

void main() {
  testWidgets('switching models loads and saves their own limits (P1-22)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(_Settings.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const RemoteProfilePage(profileId: 'remote'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final minute = find.byKey(const Key('remote-limit-minute'));
    final day = find.byKey(const Key('remote-limit-day'));
    final model = find.byKey(const Key('remote-model'));
    String text(Finder finder) =>
        tester.widget<TextField>(finder).controller!.text;
    await tester.enterText(minute, '7');
    await tester.enterText(model, 'b');
    expect(text(minute), '9');
    expect(text(day), '90');
    await tester.enterText(day, '100');
    await tester.enterText(model, 'uncapped');
    expect(text(minute), isEmpty);
    expect(text(day), isEmpty);
    await tester.pump();
    await tester.tap(find.byKey(const Key('remote-save')));
    await tester.pumpAndSettle();
    var profile = container.read(settingsProvider).remoteProfiles.single;
    expect(profile.model, 'uncapped');
    expect(profile.limit.isEmpty, isTrue);
    expect(profile.limitFor('a').perMinute, 7);
    expect(profile.limitFor('b').perDay, 100);
    await tester.enterText(model, 'a');
    expect(text(minute), '7');
    expect(text(day), '50');
    await tester.enterText(minute, '8');
    await tester.pump();
    await tester.tap(find.byKey(const Key('remote-save')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(find.byKey(const Key('remote-save'))).onPressed,
      isNull,
    );
    await tester.enterText(model, 'b');
    await tester.pump();
    await tester.tap(find.byKey(const Key('remote-save')));
    await tester.pumpAndSettle();
    profile = container.read(settingsProvider).remoteProfiles.single;
    expect(profile.limit.perMinute, 9);
    expect(profile.limit.perDay, 100);
    expect(profile.limitFor('a').perMinute, 8);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/screens/remote_server_page.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _home = RemoteProfile(
  id: 'home',
  providerId: 'custom',
  name: 'Home PC',
  baseUrl: 'http://10.0.0.187:8787',
);
const _laptop = RemoteProfile(
  id: 'laptop',
  providerId: 'custom',
  name: 'Laptop',
  baseUrl: 'http://10.0.0.188:8787',
);

class _Settings extends SettingsNotifier {
  @override
  InferenceSettings build() {
    ready = Future.value();
    return const InferenceSettings(
      remoteProfiles: [_home, _laptop],
      remoteProfileId: 'home',
    );
  }

  @override
  Future<void> update(InferenceSettings next) async => state = next;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // D-12 (2026-10-29): picking a connection here left Remote off, so the
  // chat still said no model was loaded.
  testWidgets('picking a connection turns Remote on with it', (tester) async {
    tester.view.physicalSize = const Size(412, 3000);
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
          home: const RemoteServerPage(),
        ),
      ),
    );
    await tester.pump();
    expect(container.read(settingsProvider).remoteEnabled, isFalse);
    await tester.tap(find.byKey(const Key('remote-profile-laptop')));
    await tester.pump();
    final s = container.read(settingsProvider);
    expect(s.remoteEnabled, isTrue);
    expect(s.remoteProfileId, 'laptop');
    expect(s.usesRemote, isTrue);
  });
}

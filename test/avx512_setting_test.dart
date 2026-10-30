import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/desktop/cpu_variant_setting.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'advanced_pages_2_test.dart' show TestSettings;

void main() {
  tearDown(() => DesktopHost.active = false);
  testWidgets('desktop selector shows detection and persists a choice', (
    tester,
  ) async {
    DesktopHost.active = true;
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(TestSettings.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CpuVariantSetting(
              hasAvx2: () => true,
              hasAvx512: () => false,
            ),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('AVX512 unavailable, AVX2 usable'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AVX512').last);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).cpuVariant, 'avx512');
  });
  testWidgets('phone hides desktop selector without probing Windows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: CpuVariantSetting())),
      ),
    );
    expect(find.byType(DropdownButton<String>), findsNothing);
  });
}

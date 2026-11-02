import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/platform/desktop_preferences.dart';
import 'package:ondevice_llm/desktop/advanced_toggle.dart';

void main() {
  testWidgets('sidebar collapse animates and survives provider recreation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(desktopPreferencesProvider.notifier).ready;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: DesktopSidebarSection(child: Text('Navigation child')),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Navigation child'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Navigation child'), findsNothing);
    expect(find.byType(AnimatedSize), findsOneWidget);
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    await fresh.read(desktopPreferencesProvider.notifier).ready;
    expect(fresh.read(desktopPreferencesProvider).sidebarCollapsed, isTrue);
    await tester.tap(find.byKey(const Key('sidebar-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Navigation child'), findsOneWidget);
  });
}

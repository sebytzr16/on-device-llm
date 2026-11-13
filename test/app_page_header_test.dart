import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/app_design.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';

void main() {
  testWidgets('page header actions sit at the far right', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: AppPageHeader(
            title: 'Models',
            subtitle: 'Short',
            actions: [SizedBox(key: Key('action'), width: 120, height: 32)],
          ),
        ),
      ),
    );
    final right = tester.getTopRight(find.byKey(const Key('action'))).dx;
    expect(right, closeTo(1400, 1));
  });
}

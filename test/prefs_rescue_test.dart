import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/storage/prefs_rescue.dart';
import 'package:ondevice_llm/features/shortcuts/domain/prompt_shortcut.dart';
import 'package:ondevice_llm/features/shortcuts/prompt_shortcuts_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('an unreadable shortcut store is kept aside before a save', () async {
    SharedPreferences.setMockInitialValues({
      'prompt_shortcuts_v1': '[{"name": "mine", broken',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(promptShortcutsProvider);
    await container.read(promptShortcutsProvider.notifier).ready;
    await container
        .read(promptShortcutsProvider.notifier)
        .put(
          const PromptShortcut(
            name: 'new',
            description: 'd',
            template: 'x {input}',
          ),
        );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(PrefsRescue.rescueKey('prompt_shortcuts_v1')),
      '[{"name": "mine", broken',
    );
    expect(prefs.getString('prompt_shortcuts_v1'), contains('new'));
  });
}

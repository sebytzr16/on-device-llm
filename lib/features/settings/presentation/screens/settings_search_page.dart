import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/l10n/l10n.dart';
import '../../domain/setting_specs.dart';
import '../../domain/entities/inference_settings.dart';
import '../providers/settings_provider.dart';
import '../setting_labels.dart';
import 'advanced_pages.dart';
import 'advanced_pages_2.dart';
import 'memory_page.dart';
import 'knowledge_page.dart';
import '../../../../core/design/app_design.dart';
import '../../../settings/presentation/widgets/settings_widgets.dart';
import '../../../../core/design/app_dialog.dart';

class SettingsSearchPage extends ConsumerStatefulWidget {
  const SettingsSearchPage({super.key});
  @override
  ConsumerState<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends ConsumerState<SettingsSearchPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final q = _query.trim().toLowerCase();
    bool hit(String text) => q.isEmpty || text.toLowerCase().contains(q);
    final matches = SettingSpec.all.where(
      (spec) => hit(
        '${spec.label} ${spec.labelIn(t)} ${spec.key} ${spec.group} '
        '${spec.hint}',
      ),
    );
    // Main-page switches are not overridable specs; they are found here and
    // flipped in place.
    final switches = [
      (
        t.autoTitlesSetting,
        t.autoTitlesHint,
        s.autoTitles,
        (bool v) => s.copyWith(autoTitles: v),
      ),
      (
        t.readAloudSetting,
        t.readAloudHint,
        s.readAloud,
        (bool v) => s.copyWith(readAloud: v),
      ),
      (
        t.batterySaver,
        '',
        s.batterySaver,
        (bool v) => s.copyWith(batterySaver: v),
      ),
    ].where((e) => q.isNotEmpty && hit('${e.$1} ${e.$2}'));
    return Scaffold(
      appBar: AppBar(title: Text(t.settingsSearch)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDesign.lg),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.settingsSearch,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text(t.settingsFaster),
                  onPressed: () => notifier.update(
                    s.copyWith(maxTokens: 768, thinkingModeEnabled: false),
                  ),
                ),
                ActionChip(
                  label: Text(t.settingsDetailed),
                  onPressed: () => notifier.update(
                    s.copyWith(
                      maxTokens: 4096,
                      thinkingModeEnabled: true,
                      thinkingBudgetTokens: ThinkingLevel.medium.budget,
                    ),
                  ),
                ),
                ActionChip(
                  label: Text(t.settingsLessMemory),
                  onPressed: () => notifier.update(
                    s.copyWith(
                      contextSize: 2048,
                      kvCacheType: KvCacheType.q8_0,
                      imageMaxTokens: 512,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_query.isEmpty ||
              'memory mémoire memoria'.contains(_query.toLowerCase()))
            SettingsRow(
              title: Text(t.memory),
              leading: const Icon(Icons.psychology_outlined),
              onTap: () => _open(const MemoryPage()),
            ),
          if (_query.isEmpty ||
              'knowledge documents documents documentos'.contains(
                _query.toLowerCase(),
              ))
            SettingsRow(
              title: Text(t.knowledgeLibrary),
              leading: const Icon(Icons.menu_book),
              onTap: () => _open(const KnowledgePage()),
            ),
          for (final e in switches)
            SwitchListTile(
              title: Text(e.$1),
              subtitle: e.$2.isEmpty ? null : Text(e.$2),
              value: e.$3,
              onChanged: (v) => notifier.update(e.$4(v)),
            ),
          for (final spec in matches)
            SettingsRow(
              title: Text(spec.labelIn(t)),
              subtitle: Text(spec.group),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _setting(spec),
            ),
        ],
      ),
    );
  }

  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  Future<void> _setting(SettingSpec spec) async {
    final page = switch (spec.group) {
      SettingSpec.groupGeneration => const SamplingPage(),
      SettingSpec.groupReasoning ||
      SettingSpec.groupWeb => const ReasoningSearchPage(),
      SettingSpec.groupTools => const ToolsPage(),
      SettingSpec.groupOutput => const StructuredOutputPage(),
      SettingSpec.groupContext => const ContextBatchPage(),
      SettingSpec.groupHardware => const HardwarePage(),
      _ => null,
    };
    if (page != null) {
      _open(page);
      return;
    }
    final s = ref.read(settingsProvider);
    final value = await promptText(
      context,
      title: context.l10n.customInstructions,
      initial: s.systemPrompt,
      confirmLabel: context.l10n.save,
      minLines: 4,
      maxLines: 10,
      allowEmpty: true,
      selectAll: false,
    );
    if (value != null && mounted) {
      await ref
          .read(settingsProvider.notifier)
          .update(ref.read(settingsProvider).copyWith(systemPrompt: value));
    }
  }
}

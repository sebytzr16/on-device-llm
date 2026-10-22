import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../inference/remote/remote_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_widgets.dart';
import 'remote_profile_page.dart';
import 'scan_connection_page.dart';
import '../../../hosting/host_discovery.dart';
import '../../../hosting/presentation/nearby_hosts_page.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// Settings > Remote: saved connections to servers the user runs (LM Studio,
/// Ollama, llama-server…) or to hosted APIs (OpenAI, Anthropic, Gemini,
/// OpenRouter…), one of which is active. Off by default.
class RemoteServerPage extends ConsumerWidget {
  const RemoteServerPage({super.key});
  Future<void> _nearby(BuildContext context, WidgetRef ref) async {
    final host = await Navigator.of(context).push<DiscoveredHost>(
      MaterialPageRoute(builder: (_) => const NearbyHostsPage()),
    );
    if (host == null || !context.mounted) return;
    final settings = ref.read(settingsProvider);
    if (settings.remoteProfiles.length >= 32) return;
    final profile = RemoteProfile(
      id: const Uuid().v4(),
      providerId: 'custom',
      name: host.name,
      baseUrl: host.endpoint,
    );
    await ref
        .read(settingsProvider.notifier)
        .update(
          settings.copyWith(
            remoteProfiles: [...settings.remoteProfiles, profile],
            remoteProfileId: settings.remoteProfiles.isEmpty
                ? profile.id
                : settings.remoteProfileId,
          ),
        );
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RemoteProfilePage(profileId: profile.id),
        ),
      );
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final provider = await showMorphSheet<RemoteProvider>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProviderSheet(),
    );
    if (provider == null || !context.mounted) return;
    final s = ref.read(settingsProvider);
    if (s.remoteProfiles.length >= 32) return;
    final profile = RemoteProfile(
      id: const Uuid().v4(),
      name: provider.name,
      providerId: provider.id,
      baseUrl: provider.defaultBaseUrl,
    );
    await ref
        .read(settingsProvider.notifier)
        .update(
          s.copyWith(
            remoteProfiles: [...s.remoteProfiles, profile],
            remoteProfileId: s.remoteProfiles.isEmpty
                ? profile.id
                : s.remoteProfileId,
          ),
        );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteProfilePage(profileId: profile.id),
      ),
    );
  }

  /// Adds the connection another phone copied from "Use this device as a
  /// server" (text or its QR code) and makes it the active one.
  Future<void> _paste(BuildContext context, WidgetRef ref) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    await _addPairing(context, ref, text);
  }

  /// Scans the other phone's pairing QR code, asks for a name, and adds the
  /// connection: nothing to type but the name.
  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ScanConnectionPage(
          accept: (t) => RemoteProfile.fromPairing(t, id: 'probe') != null,
        ),
      ),
    );
    if (text == null || !context.mounted) return;
    await _addPairing(context, ref, text, askName: true);
  }

  Future<void> _addPairing(
    BuildContext context,
    WidgetRef ref,
    String text, {
    bool askName = false,
  }) async {
    final pairing = RemoteProfile.fromPairing(text, id: const Uuid().v4());
    if (pairing == null) {
      showIslandToast(context, context.l10n.remotePasteNone);
      return;
    }
    var (profile, key) = pairing;
    if (askName) {
      final name = await _askName(context, profile.label);
      if (name == null || !context.mounted) return;
      profile = profile.copyWith(name: name);
    }
    final n = ref.read(settingsProvider.notifier);
    final s = ref.read(settingsProvider);
    if (s.remoteProfiles.length >= 32) return;
    await n.update(
      s.copyWith(
        remoteProfiles: [...s.remoteProfiles, profile],
        remoteProfileId: profile.id,
      ),
    );
    if (key.isNotEmpty) await n.setRemoteApiKey(profile.id, key);
    if (context.mounted) {
      showIslandToast(context, context.l10n.remotePasted(profile.label));
    }
  }

  /// The name for a scanned connection; null when cancelled.
  Future<String?> _askName(BuildContext context, String suggested) async {
    final name = await promptText(
      context,
      title: context.l10n.remoteNameConnection,
      initial: suggested,
      hint: context.l10n.remoteNameHint,
      confirmLabel: context.l10n.commonSave,
      maxLength: 80,
      allowEmpty: true,
      fieldKey: const Key('scan-name'),
      confirmKey: const Key('scan-name-save'),
    );
    final trimmed = name?.trim();
    if (trimmed == null) return null;
    return trimmed.isEmpty ? suggested : trimmed;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    final active = s.activeRemoteProfile;
    final full = s.remoteProfiles.length >= 32;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.remoteServer),
        actions: const [SavedIndicator()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.lg,
            AppDesign.sm,
            AppDesign.lg,
            AppDesign.xxl,
          ),
          children: [
            const SettingsNote(
              'Point the app at a server you run yourself — LM Studio, Ollama or llama-server on a PC at home over your LAN or a VPN — or at a hosted API with your own key. Your messages and any web evidence are sent to that connection instead of being answered on the phone.',
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: AppDesign.md),
            SettingsGroup(
              children: [
                SettingsSwitchRow(
                  secondary: const Icon(Icons.dns_outlined),
                  key: const Key('remote-enabled'),
                  title: Text(context.l10n.uiRemoteServerPageUseRemoteServer),
                  subtitle: Text(
                    s.usesRemote
                        ? context.l10n.remoteUsingSummary(
                            active!.label,
                            s.remoteUri!.host,
                          )
                        : s.remoteEnabled
                        ? active == null
                              ? context.l10n.remoteNeedsConnection
                              : context.l10n.remoteNeedsUrl
                        : context.l10n.remoteRowOff,
                  ),
                  value: s.remoteEnabled,
                  onChanged: (v) => n.update(s.copyWith(remoteEnabled: v)),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionConnections,
              children: [
                if (s.remoteProfiles.isEmpty)
                  SettingsRow(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text(
                      context.l10n.uiRemoteServerPageNoConnectionsYet,
                    ),
                    subtitle: Text(
                      context.l10n.uiRemoteServerPageAddOneToChooseAProvider,
                    ),
                  ),
                for (final p in s.remoteProfiles)
                  RadioListTile<String>(
                    key: Key('remote-profile-${p.id}'),
                    value: p.id,
                    // ignore: deprecated_member_use
                    groupValue: active?.id,
                    // ignore: deprecated_member_use
                    onChanged: (id) =>
                        n.update(s.copyWith(remoteProfileId: id ?? p.id)),
                    title: Text(p.label),
                    subtitle: Text(
                      [
                        // The provider only when the name does not say it.
                        if (p.label != p.provider.name) p.provider.name,
                        if (p.uri != null) p.uri!.host,
                        if (p.model.trim().isNotEmpty) p.model.trim(),
                        if (p.uri == null) context.l10n.remoteNoUrl,
                        if (p.provider.requiresKey &&
                            (s.remoteApiKeys[p.id] ?? '').isEmpty)
                          context.l10n.remoteNoKey,
                      ].join(' · '),
                    ),
                    secondary: IconButton(
                      key: Key('remote-profile-edit-${p.id}'),
                      tooltip: context.l10n.uiRemoteServerPageEditConnection,
                      icon: const Icon(Icons.tune),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RemoteProfilePage(profileId: p.id),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDesign.lg,
                    AppDesign.sm,
                    AppDesign.lg,
                    AppDesign.md,
                  ),
                  // Add is the main action; scanning and pasting are two
                  // equal ways to bring in another phone's connection.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (HostDiscovery.supported)
                        OutlinedButton.icon(
                          onPressed: full ? null : () => _nearby(context, ref),
                          icon: const Icon(Icons.radar),
                          label: Text(context.l10n.nearbyHosts),
                        ),
                      FilledButton.tonalIcon(
                        key: const Key('remote-add'),
                        onPressed: full ? null : () => _add(context, ref),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.l10n.remoteAdd),
                      ),
                      const SizedBox(height: AppDesign.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('remote-scan'),
                              onPressed: full
                                  ? null
                                  : () => _scan(context, ref),
                              icon: const Icon(Icons.qr_code_scanner, size: 18),
                              label: Text(
                                context.l10n.remoteScanShort,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppDesign.sm),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const Key('remote-paste'),
                              onPressed: full
                                  ? null
                                  : () => _paste(context, ref),
                              icon: const Icon(Icons.content_paste, size: 18),
                              label: Text(
                                context.l10n.remotePasteShort,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              label: context.l10n.sectionCapabilities,
              children: [
                if (active != null) ...[
                  SettingsSwitchRow(
                    secondary: const Icon(Icons.ios_share_rounded),
                    key: const Key('remote-share-memory'),
                    title: Text(context.l10n.remoteShareMemory),
                    subtitle: Text(context.l10n.remoteShareMemoryHint),
                    value: active.shareMemory,
                    onChanged: (v) => n.update(
                      s.copyWith(
                        remoteProfiles: [
                          for (final p in s.remoteProfiles)
                            p.id == active.id
                                ? p.copyWith(
                                    shareMemory: v,
                                    learnMemory: v && p.learnMemory,
                                  )
                                : p,
                        ],
                      ),
                    ),
                  ),
                  SettingsSwitchRow(
                    secondary: const Icon(Icons.school_outlined),
                    key: const Key('remote-learn-memory'),
                    title: Text(context.l10n.remoteLearnMemory),
                    subtitle: Text(context.l10n.remoteLearnMemoryHint),
                    value: active.learnMemory,
                    onChanged: active.shareMemory
                        ? (v) => n.update(
                            s.copyWith(
                              remoteProfiles: [
                                for (final p in s.remoteProfiles)
                                  p.id == active.id
                                      ? p.copyWith(learnMemory: v)
                                      : p,
                              ],
                            ),
                          )
                        : null,
                  ),
                  SettingsSwitchRow(
                    secondary: const Icon(Icons.settings_suggest_outlined),
                    key: const Key('remote-server-settings'),
                    title: Text(context.l10n.remoteServerSettings),
                    subtitle: Text(context.l10n.remoteServerSettingsHint),
                    value: active.serverSettings,
                    onChanged: (v) => n.update(
                      s.copyWith(
                        remoteProfiles: [
                          for (final p in s.remoteProfiles)
                            p.id == active.id
                                ? p.copyWith(serverSettings: v)
                                : p,
                        ],
                      ),
                    ),
                  ),
                ],
                SettingsSwitchRow(
                  secondary: const Icon(Icons.travel_explore_rounded),
                  key: const Key('remote-web-research'),
                  title: Text(context.l10n.uiRemoteServerPageWebResearch),
                  subtitle: Text(
                    context
                        .l10n
                        .uiRemoteServerPageTheAppSearchesDuckDuckGoAndReads,
                  ),
                  value: s.remoteWebResearch,
                  onChanged: (v) => n.update(s.copyWith(remoteWebResearch: v)),
                ),
                SettingsSwitchRow(
                  secondary: const Icon(Icons.image_outlined),
                  key: const Key('remote-vision'),
                  title: Text(
                    context.l10n.uiRemoteServerPageImageUnderstanding,
                  ),
                  subtitle: Text(
                    context.l10n.uiRemoteServerPageSendAttachedImagesToTheModel,
                  ),
                  value: s.remoteVision,
                  onChanged: (v) => n.update(s.copyWith(remoteVision: v)),
                ),
                SettingsSwitchRow(
                  secondary: const Icon(Icons.description_outlined),
                  key: const Key('remote-documents'),
                  title: Text(
                    context.l10n.uiRemoteServerPageDocumentUnderstanding,
                  ),
                  subtitle: Text(
                    context
                        .l10n
                        .uiRemoteServerPageExtractDocumentsSafelyOnThePhone,
                  ),
                  value: s.remoteDocuments,
                  onChanged: (v) => n.update(s.copyWith(remoteDocuments: v)),
                ),
                SettingSlider(
                  label: context.l10n.uiRemoteServerPageStreamingIdleTimeout,
                  hint: context
                      .l10n
                      .uiRemoteServerPageHowLongToWaitBetweenResponse,
                  value: s.remoteIdleTimeoutSeconds.toDouble(),
                  min: 15,
                  max: 600,
                  divisions: 39,
                  display: '${s.remoteIdleTimeoutSeconds} s',
                  onChanged: (v) =>
                      n.update(s.copyWith(remoteIdleTimeoutSeconds: v.round())),
                ),
              ],
            ),
            const SettingsNote(
              'Sampling, max tokens and thinking mode apply to remote chats too (Anthropic ignores sampling). Context size is the app’s fitting budget; set it no higher than the selected model’s real context window.',
            ),
            SettingsNote(
              'API keys are stored in the Android keystore, never in the settings file or exports, and are only ever sent to the connection they belong to. Over the internet use HTTPS or a VPN.',
              icon: Icons.lock_outline,
              tone: c.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Picker for a new connection's provider, grouped by where it runs.
class _ProviderSheet extends StatelessWidget {
  const _ProviderSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.lg,
        AppDesign.md,
        AppDesign.lg,
        AppDesign.xs,
      ),
      child: Text(
        text,
        style: context.text.label.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: .4,
          color: c.textMuted,
        ),
      ),
    );
    Widget tile(RemoteProvider p) => SettingsRow(
      key: Key('remote-provider-${p.id}'),
      dense: true,
      leading: Icon(switch (p.protocol) {
        RemoteProtocol.openai =>
          p.selfHosted ? Icons.computer_outlined : Icons.cloud_outlined,
        RemoteProtocol.anthropic => Icons.auto_awesome_outlined,
        RemoteProtocol.gemini => Icons.auto_awesome_outlined,
      }, size: 20),
      title: Text(p.name),
      subtitle: p.note == null ? null : Text(p.note!),
      onTap: () => Navigator.of(context).pop(p),
    );
    final hosted = RemoteProvider.hostedOnes.toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      maxChildSize: .95,
      builder: (context, controller) => AppSheet(
        title: context.l10n.uiRemoteServerPageChooseAProvider,
        scrollable: false,
        children: [
          ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              header('ON YOUR OWN HARDWARE'),
              for (final p in RemoteProvider.selfHostedOnes) tile(p),
              header('HOSTED APIS (YOUR KEY)'),
              for (final p in hosted) tile(p),
              const SizedBox(height: AppDesign.xl),
            ],
          ),
        ],
      ),
    );
  }
}

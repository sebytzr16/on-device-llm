import 'dart:async';

import '../../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../core/utils/external_links.dart';
import '../../../../inference/remote/remote_engine.dart';
import '../../../../inference/remote/remote_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// Settings > Remote server > one connection: provider, name, URL, API key,
/// model, request caps and extra headers. Typed fields are saved with the
/// Save button (the bar under the page while something is unsaved), with
/// the keyboard's Done key, and when the user leaves the page; the key
/// goes to the keystore, everything else to the settings file.
class RemoteProfilePage extends ConsumerStatefulWidget {
  final String profileId;
  const RemoteProfilePage({super.key, required this.profileId});

  @override
  ConsumerState<RemoteProfilePage> createState() => _RemoteProfilePageState();
}

class _RemoteProfilePageState extends ConsumerState<RemoteProfilePage> {
  late final TextEditingController _name, _url, _key, _model, _headers;
  late final TextEditingController _perMinute, _perDay;
  List<RemoteModel>? _models;
  RemoteServerReport? _report;
  String? _probe;
  bool _probing = false, _showKey = false;
  ({int minute, int day})? _counts;

  RemoteProfile? get _profile => ref
      .read(settingsProvider)
      .remoteProfiles
      .where((p) => p.id == widget.profileId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    final p = _profile ?? RemoteProfile(id: widget.profileId, name: '');
    _name = TextEditingController(text: p.name);
    _url = TextEditingController(text: p.baseUrl);
    _key = TextEditingController(
      text: ref.read(settingsProvider).remoteApiKeys[p.id] ?? '',
    );
    _model = TextEditingController(text: p.model);
    _headers = TextEditingController(
      text: RemoteProfile.formatHeaders(p.headers),
    );
    _perMinute = TextEditingController(
      text: p.limit.perMinute > 0 ? '${p.limit.perMinute}' : '',
    );
    _perDay = TextEditingController(
      text: p.limit.perDay > 0 ? '${p.limit.perDay}' : '',
    );
    for (final c in [
      _name,
      _url,
      _key,
      _model,
      _headers,
      _perMinute,
      _perDay,
    ]) {
      c.addListener(_onEdit);
    }
    _refreshCounts();
  }

  bool _lastDirty = false;
  void _onEdit() {
    final dirty = _dirty;
    if (dirty != _lastDirty && mounted) setState(() => _lastDirty = dirty);
  }

  /// Whether a typed field differs from the stored connection.
  bool get _dirty {
    final p = _profile;
    if (p == null) return false;
    int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    return _name.text.trim() != p.name ||
        _url.text.trim() != p.baseUrl ||
        _model.text.trim() != p.model ||
        RemoteProfile.formatHeaders(
              RemoteProfile.parseHeaders(_headers.text),
            ) !=
            RemoteProfile.formatHeaders(p.headers) ||
        n(_perMinute) !=
            (p.limits[_model.text.trim()] ?? const RemoteLimit()).perMinute ||
        n(_perDay) !=
            (p.limits[_model.text.trim()] ?? const RemoteLimit()).perDay ||
        _key.text.trim() !=
            (ref.read(settingsProvider).remoteApiKeys[p.id] ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _url,
      _key,
      _model,
      _headers,
      _perMinute,
      _perDay,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshCounts() async {
    if (!mounted) return;
    final p = _profile;
    if (p == null) return;
    final counts = await ref
        .read(remoteEngineProvider)
        .usage
        .counts(p.id, p.model);
    if (mounted) setState(() => _counts = counts);
  }

  /// Writes the text fields into the profile (and the key into the
  /// keystore when it changed).
  Future<void> _save({String? providerId, bool announce = false}) async {
    final toast = islandToastFor(context);
    final saved = context.l10n.savedNotice;
    final s = ref.read(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final current = _profile;
    if (current == null) return;
    var next = current.copyWith(
      name: _name.text.trim(),
      providerId: providerId,
      baseUrl: _url.text.trim(),
      model: _model.text.trim(),
      headers: RemoteProfile.parseHeaders(_headers.text),
    );
    next = next.withLimit(
      RemoteLimit(
        perMinute: int.tryParse(_perMinute.text.trim()) ?? 0,
        perDay: int.tryParse(_perDay.text.trim()) ?? 0,
      ),
    );
    await n.update(
      s.copyWith(
        remoteProfiles: [
          for (final p in s.remoteProfiles) p.id == next.id ? next : p,
        ],
      ),
    );
    final key = _key.text.trim();
    if (key != (s.remoteApiKeys[next.id] ?? '')) {
      await n.setRemoteApiKey(next.id, key);
    }
    if (announce) {
      toast(saved, tone: IslandTone.done);
    }
    if (!mounted) return;
    setState(() => _lastDirty = _dirty);
    await _refreshCounts();
  }

  Future<void> _changeProvider(RemoteProvider provider) async {
    final current = _profile;
    if (current == null || provider.id == current.providerId) return;
    // A URL the user never edited follows the provider's default.
    final untouched =
        _url.text.trim().isEmpty ||
        _url.text.trim() == current.provider.defaultBaseUrl;
    if (untouched) _url.text = provider.defaultBaseUrl;
    if (_name.text.trim().isEmpty ||
        _name.text.trim() == current.provider.name) {
      _name.text = provider.name;
    }
    setState(() {
      _models = null;
      _report = null;
      _probe = null;
    });
    await _save(providerId: provider.id);
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _probing = true;
      _probe = null;
      _report = null;
    });
    try {
      // Probe the connection being edited even when another one is active.
      final s = ref.read(settingsProvider);
      final probeSettings = s.copyWith(remoteProfileId: widget.profileId);
      final report = await ref.read(remoteEngineProvider).probe(probeSettings);
      final models = report.models;
      if (!mounted) return;
      final provider = _profile?.provider ?? RemoteProvider.custom;
      setState(() {
        _models = models;
        _report = report;
        _probe = !provider.listsModels
            ? context.l10n.remoteConnectedNoList
            : models.isEmpty
            ? provider.selfHosted
                  ? context.l10n.remoteConnectedServerNoModels
                  : context.l10n.remoteConnectedNoModels
            : report.summary;
        if (_model.text.trim().isEmpty && models.isNotEmpty) {
          _model.text = models.first.id;
        }
      });
      await _save();
    } catch (e) {
      if (mounted) {
        setState(
          () => _probe = '$e'.replaceFirst(RegExp(r'^\w+Exception: '), ''),
        );
      }
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _delete() async {
    final p = _profile;
    if (p == null) return;
    final ok = await confirmAction(
      context,
      title: context.l10n.uiRemoteProfilePageDeleteConnection,
      message: context.l10n.remoteDeleteHint(p.label),
      confirmLabel: context.l10n.uiRemoteProfilePageDelete,
      destructive: true,
      confirmKey: const Key('remote-delete-confirm'),
    );
    if (!ok || !mounted) return;
    final s = ref.read(settingsProvider);
    final rest = [
      for (final x in s.remoteProfiles)
        if (x.id != p.id) x,
    ];
    await ref
        .read(settingsProvider.notifier)
        .update(
          s.copyWith(
            remoteProfiles: rest,
            remoteProfileId: s.remoteProfileId == p.id
                ? (rest.firstOrNull?.id ?? '')
                : s.remoteProfileId,
          ),
        );
    await ref.read(remoteEngineProvider).usage.forget(p.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final p = s.remoteProfiles
        .where((p) => p.id == widget.profileId)
        .firstOrNull;
    final c = context.colors;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.uiRemoteProfilePageConnection)),
        body: Center(
          child: Text(context.l10n.uiRemoteProfilePageThisConnectionWasRemoved),
        ),
      );
    }
    final provider = p.provider;
    final ok = _report != null;
    final selectable = _models?.where((m) => m.id.isNotEmpty).toList();
    final selected = selectable
        ?.where((m) => m.id == _model.text.trim())
        .firstOrNull;
    final limit = p.limit;
    final dirty = _dirty;
    return PopScope(
      // Leaving the page keeps what was typed (the old page dropped every
      // field whose keyboard Done key was not pressed).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _dirty) unawaited(_save());
      },
      child: Scaffold(
        bottomNavigationBar: UnsavedChangesBar(
          visible: dirty,
          onSave: () => _save(announce: true),
        ),
        appBar: AppBar(
          title: Text(p.label),
          actions: [
            TextButton(
              key: const Key('remote-save'),
              onPressed: dirty ? () => _save(announce: true) : null,
              child: Text(context.l10n.commonSave),
            ),
            IconButton(
              key: const Key('remote-delete'),
              tooltip: context.l10n.uiRemoteProfilePageDeleteConnection2,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
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
              SettingsGroup(
                children: [
                  SettingDropdown<String>(
                    icon: Icons.cloud_outlined,
                    label: context.l10n.uiRemoteProfilePageProvider,
                    hint: provider.selfHosted
                        ? context.l10n.remoteOwnServer
                        : context.l10n.remoteHostedBilling,
                    value: provider.id,
                    items: [for (final x in RemoteProvider.all) x.id],
                    labelOf: (id) => RemoteProvider.byId(id).name,
                    onChanged: (id) => _changeProvider(RemoteProvider.byId(id)),
                  ),
                  if (provider.note != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppDesign.lg,
                        0,
                        AppDesign.lg,
                        AppDesign.sm,
                      ),
                      child: Text(provider.note!, style: context.text.small),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDesign.lg,
                      AppDesign.sm,
                      AppDesign.lg,
                      AppDesign.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('remote-name'),
                          controller: _name,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: context.l10n.uiRemoteProfilePageName,
                            hintText: provider.name,
                            helperText: context.l10n.remoteNameHelp,
                          ),
                          onEditingComplete: _save,
                        ),
                        const SizedBox(height: AppDesign.md),
                        TextField(
                          key: const Key('remote-url'),
                          controller: _url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText:
                                context.l10n.uiRemoteProfilePageServerURL,
                            hintText: provider.defaultBaseUrl.isEmpty
                                ? provider.urlHint
                                : provider.defaultBaseUrl,
                            helperText: provider.selfHosted
                                ? context.l10n.remoteOwnUrlHelp(
                                    provider.versionPath,
                                  )
                                : context.l10n.remoteHostedUrlHelp(
                                    provider.name,
                                  ),
                            helperMaxLines: 2,
                            errorText:
                                _url.text.trim().isNotEmpty && p.uri == null
                                ? context.l10n.remoteInvalidUrl
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                          onEditingComplete: _save,
                        ),
                        const SizedBox(height: AppDesign.md),
                        TextField(
                          key: const Key('remote-key'),
                          controller: _key,
                          obscureText: !_showKey,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            labelText: provider.requiresKey
                                ? context.l10n.remoteApiKey
                                : context.l10n.remoteApiKeyOptional,
                            helperText: provider.requiresKey
                                ? context.l10n.remoteKeyHostedHelp(
                                    provider.name,
                                  )
                                : context.l10n.remoteKeySelfHelp,
                            helperMaxLines: 2,
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: const Key('remote-key-visibility'),
                                  tooltip: _showKey
                                      ? context.l10n.remoteHideKey
                                      : context.l10n.remoteShowKey,
                                  icon: Icon(
                                    _showKey
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () =>
                                      setState(() => _showKey = !_showKey),
                                ),
                                if (provider.keysUrl != null)
                                  IconButton(
                                    key: const Key('remote-key-link'),
                                    tooltip: context
                                        .l10n
                                        .uiRemoteProfilePageGetAKeyInTheBrowser,
                                    icon: const Icon(Icons.open_in_new),
                                    onPressed: () =>
                                        openExternalLink(provider.keysUrl!),
                                  ),
                              ],
                            ),
                          ),
                          onEditingComplete: _save,
                        ),
                        const SizedBox(height: AppDesign.md),
                        TextField(
                          key: const Key('remote-model'),
                          controller: _model,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: context.l10n.uiRemoteProfilePageModel,
                            hintText: switch (provider.protocol) {
                              RemoteProtocol.anthropic => 'claude-opus-5',
                              RemoteProtocol.gemini => 'gemini-3.6-flash',
                              RemoteProtocol.openai =>
                                provider.selfHosted
                                    ? context.l10n.remoteServerDefaultModel
                                    : context.l10n.remoteModelId,
                            },
                            helperText: provider.listsModels
                                ? context.l10n.remoteModelListHelp
                                : context.l10n.remoteModelManualHelp,
                            helperMaxLines: 2,
                            suffixIcon: selectable == null || selectable.isEmpty
                                ? null
                                : PopupMenuButton<String>(
                                    key: const Key('remote-model-picker'),
                                    tooltip: context
                                        .l10n
                                        .uiRemoteProfilePageModelsOnTheServer,
                                    icon: const Icon(Icons.arrow_drop_down),
                                    onSelected: (id) {
                                      setState(() => _model.text = id);
                                      _save();
                                    },
                                    itemBuilder: (_) => [
                                      for (final m in selectable)
                                        PopupMenuItem(
                                          value: m.id,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                m.id,
                                                style: context.text.mono,
                                              ),
                                              if (m.displayName != null &&
                                                  m.displayName != m.id)
                                                Text(
                                                  '${m.displayName}${m.contextWindow == null ? '' : ' · ${_k(m.contextWindow!)} ctx'}',
                                                  style: context.text.caption,
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          onEditingComplete: _save,
                        ),
                        const SizedBox(height: AppDesign.md),
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              key: const Key('remote-test'),
                              onPressed: _probing || p.uri == null
                                  ? null
                                  : _test,
                              icon: _probing
                                  ? const SizedBox.square(
                                      dimension: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync, size: 16),
                              label: Text(
                                provider.listsModels
                                    ? context.l10n.remoteTestList
                                    : context.l10n.remoteTestConnection,
                              ),
                            ),
                            const SizedBox(width: AppDesign.md),
                            if (_probe != null)
                              Expanded(
                                child: Text(
                                  _probe!,
                                  style: context.text.mono.copyWith(
                                    color: ok ? c.success : c.warning,
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
              if (_report != null) ...[
                SettingsSection(label: context.l10n.remoteCapabilities),
                Builder(
                  builder: (context) {
                    final capabilities = selected == null
                        ? null
                        : (selected.capabilities.toList()..sort());
                    final tools = _report!.tools;
                    final toolsText = provider.selfHosted
                        ? context.l10n.remoteToolsDetected(
                            tools.isEmpty
                                ? context.l10n.remoteNoTools
                                : tools.join(', '),
                          )
                        : '';
                    return SettingsNote(
                      capabilities != null && capabilities.isNotEmpty
                          ? context.l10n.remoteAdvertises(
                              selected!.id,
                              capabilities.join(', '),
                              selected.contextWindow == null
                                  ? ''
                                  : context.l10n.remoteContextWindow(
                                      _k(selected.contextWindow!),
                                    ),
                              toolsText,
                            )
                          : selected?.contextWindow != null
                          ? context.l10n.remoteContextOnly(
                              selected!.id,
                              _k(selected.contextWindow!),
                              toolsText,
                            )
                          : context.l10n.remoteNoCapabilities(toolsText),
                      icon: Icons.fact_check_outlined,
                    );
                  },
                ),
              ],
              SettingsSection(
                label: context.l10n.remoteRequestLimits,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDesign.lg,
                      AppDesign.md,
                      AppDesign.lg,
                      AppDesign.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          context.l10n.remoteCapsHint(
                            p.model.trim().isEmpty
                                ? context.l10n.remoteDefaultModel
                                : p.model.trim(),
                          ),
                          style: context.text.small,
                        ),
                        const SizedBox(height: AppDesign.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('remote-limit-minute'),
                                controller: _perMinute,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: context
                                      .l10n
                                      .uiRemoteProfilePageRequestsPerMinute,
                                  hintText:
                                      context.l10n.uiRemoteProfilePageNone,
                                ),
                                onEditingComplete: _save,
                              ),
                            ),
                            const SizedBox(width: AppDesign.md),
                            Expanded(
                              child: TextField(
                                key: const Key('remote-limit-day'),
                                controller: _perDay,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: context
                                      .l10n
                                      .uiRemoteProfilePageRequestsPerDay,
                                  hintText:
                                      context.l10n.uiRemoteProfilePageNone,
                                ),
                                onEditingComplete: _save,
                              ),
                            ),
                          ],
                        ),
                        if (_counts != null) ...[
                          const SizedBox(height: AppDesign.sm),
                          Text(
                            context.l10n.remoteUsed(
                              '${_counts!.minute}${limit.perMinute > 0 ? ' / ${limit.perMinute}' : ''}',
                              '${_counts!.day}${limit.perDay > 0 ? ' / ${limit.perDay}' : ''}',
                            ),
                            style: context.text.mono.copyWith(
                              color:
                                  (limit.perMinute > 0 &&
                                          _counts!.minute >= limit.perMinute) ||
                                      (limit.perDay > 0 &&
                                          _counts!.day >= limit.perDay)
                                  ? c.warning
                                  : c.textMuted,
                            ),
                          ),
                        ],
                        if (p.limits.length > 1) ...[
                          const SizedBox(height: AppDesign.sm),
                          Text(
                            context.l10n.remoteOtherCaps(
                              [
                                for (final e in p.limits.entries)
                                  if (e.key != p.model.trim())
                                    '${e.key.isEmpty ? context.l10n.remoteDefaultModel : e.key} (${_limitText(e.value)})',
                              ].join(', '),
                            ),
                            style: context.text.small,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SettingsSection(
                label: context.l10n.remoteAdvanced,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDesign.lg,
                      AppDesign.md,
                      AppDesign.lg,
                      AppDesign.md,
                    ),
                    child: TextField(
                      key: const Key('remote-headers'),
                      controller: _headers,
                      maxLines: 4,
                      minLines: 2,
                      autocorrect: false,
                      style: context.text.mono,
                      decoration: InputDecoration(
                        labelText: context.l10n.uiRemoteProfilePageExtraHeaders,
                        hintText:
                            'HTTP-Referer: https://example.app\nX-Title: My app',
                        helperText: context.l10n.remoteExtraHeadersHelp,
                        helperMaxLines: 3,
                        alignLabelWithHint: true,
                      ),
                      onEditingComplete: _save,
                      onTapOutside: (_) => _save(),
                    ),
                  ),
                ],
              ),
              SettingsNote(switch (provider.protocol) {
                RemoteProtocol.anthropic => context.l10n.remoteAnthropicNote,
                RemoteProtocol.gemini => context.l10n.remoteGeminiNote,
                RemoteProtocol.openai =>
                  provider.selfHosted
                      ? context.l10n.remoteSelfHostedNote
                      : context.l10n.remoteHostedNote(provider.name),
              }, icon: Icons.lock_outline),
            ],
          ),
        ),
      ),
    );
  }

  static String _k(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M'
      : n >= 1000
      ? '${(n / 1000).round()}k'
      : '$n';

  static String _limitText(RemoteLimit l) => [
    if (l.perMinute > 0) '${l.perMinute}/min',
    if (l.perDay > 0) '${l.perDay}/day',
  ].join(', ');
}

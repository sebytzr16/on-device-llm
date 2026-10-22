import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app.dart';
import '../../../core/design/app_design.dart';
import '../../../core/design/app_sheet.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/motion/motion.dart';
import '../../models/presentation/providers/model_manager_provider.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../device_model_server.dart';
import 'device_hosting_provider.dart';
import 'qr_view.dart';
import '../../../core/island/status_island.dart';

class DeviceHostingPage extends ConsumerStatefulWidget {
  const DeviceHostingPage({super.key});

  @override
  ConsumerState<DeviceHostingPage> createState() => _DeviceHostingPageState();
}

class _DeviceHostingPageState extends ConsumerState<DeviceHostingPage> {
  final _port = TextEditingController(text: '$defaultPort');
  bool _showToken = false, _showQr = false;

  static const defaultPort = 8787;
  static const _portKey = 'hosting_port_v1';

  /// The port as stored; the field used to reset to 8787 on every visit.
  int _savedPort = defaultPort;

  Future<void> _loadPort() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_portKey);
    if (saved == null || !mounted) return;
    setState(() {
      _savedPort = saved;
      _port.text = '$saved';
    });
  }

  Future<void> _savePort({bool announce = false}) async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || _portError != null) return;
    final toast = islandToastFor(context);
    final saved = context.l10n.savedNotice;
    await (await SharedPreferences.getInstance()).setInt(_portKey, port);
    if (mounted) setState(() => _savedPort = port);
    if (announce) {
      toast(saved, tone: IslandTone.done);
    }
  }

  bool get _portDirty => int.tryParse(_port.text.trim()) != _savedPort;

  /// Ticks the uptime once a second while the server runs.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _port.addListener(() => setState(() {}));
    unawaited(_loadPort());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(deviceHostingProvider).running) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _port.dispose();
    super.dispose();
  }

  String? get _portError {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      return context.l10n.hostPortRange;
    }
    if (port < 1024) return context.l10n.hostPortReserved;
    return null;
  }

  /// A model is loading for the server (and the server restarting).
  bool _switching = false;

  /// The downloaded models in a sheet; the one picked is loaded, and a
  /// running server restarts on the same port to serve it (tester,
  /// 2026-10-20: the loaded model could not be changed here).
  Future<void> _chooseModel() async {
    final models = ref.read(modelManagerProvider);
    final local = models.catalog.where((m) => m.isDownloaded).toList();
    final picked = await showMorphSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => AppSheet(
        title: sheet.l10n.hostPickModel,
        meta: sheet.l10n.hostPickHint,
        children: [
          for (final m in local)
            ListTile(
              key: Key('host-model-${m.id}'),
              leading: Icon(
                m.id == models.loadedModelId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(m.displayName),
              subtitle: Text(
                '${m.quantization.name.toUpperCase()} · ${m.sizeLabel}',
              ),
              onTap: () => Navigator.pop(sheet, m.id),
            ),
          ListTile(
            key: const Key('host-model-manage'),
            leading: const Icon(Icons.download_outlined),
            title: Text(sheet.l10n.hostManageModels),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(sheet, ''),
          ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == models.loadedModelId) return;
    if (picked.isEmpty) {
      unawaited(Navigator.pushNamed(context, AppRoutes.models));
      return;
    }
    final info = local.firstWhere((m) => m.id == picked);
    final hosting = ref.read(deviceHostingProvider.notifier);
    final wasRunning = ref.read(deviceHostingProvider).running;
    final toast = islandToastFor(context);
    setState(() => _switching = true);
    try {
      if (wasRunning) await hosting.stop();
      await ref.read(modelManagerProvider.notifier).loadModel(info);
      if (wasRunning) await hosting.start(port: _savedPort);
    } catch (e) {
      toast('$e', tone: IslandTone.error);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// What is (or will be) served; a tap picks another model.
  Widget _modelRow(
    BuildContext context, {
    String? modelName,
    bool busy = false,
  }) {
    final c = context.colors;
    return SettingsSection(
      label: context.l10n.hostModel,
      children: [
        SettingsRow(
          key: const Key('host-model'),
          leading: Icon(
            modelName == null ? Icons.memory_outlined : Icons.memory,
            color: modelName == null ? c.textFaint : c.accent,
          ),
          title: Text(modelName ?? context.l10n.hostNoModel),
          subtitle: Text(
            _switching
                ? context.l10n.loadingModel
                : modelName == null
                ? context.l10n.hostLoadFirst
                : context.l10n.hostModelHint,
          ),
          trailing: _switching
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  context.l10n.hostChangeModel,
                  style: context.text.label.copyWith(
                    color: busy ? c.textFaint : c.accent,
                  ),
                ),
          onTap: _switching || busy ? null : _chooseModel,
        ),
      ],
    );
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showIslandToast(
      context,
      context.l10n.hostCopied(label),
      tone: IslandTone.done,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceHostingProvider);
    final model = ref.watch(modelManagerProvider).loadedModel;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.hostTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDesign.lg,
            AppDesign.sm,
            AppDesign.lg,
            AppDesign.xxl,
          ),
          children: state.running
              ? _running(context, state)
              : _setup(context, state, modelName: model?.displayName),
        ),
      ),
    );
  }

  List<Widget> _setup(
    BuildContext context,
    DeviceHostingState state, {
    String? modelName,
  }) {
    final c = context.colors;
    final controller = ref.read(deviceHostingProvider.notifier);
    final canStart =
        !state.starting &&
        !_switching &&
        modelName != null &&
        _portError == null;
    return [
      if (state.stoppedReason != null)
        SettingsNote(
          state.stoppedReason!,
          icon: Icons.power_settings_new,
          tone: c.warning,
        ),
      if (state.error != null)
        SettingsNote(state.error!, icon: Icons.error_outline, tone: c.danger),
      _modelRow(context, modelName: modelName),
      SettingsSection(
        label: context.l10n.hostConnection,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppDesign.lg),
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.l10n.hostPort,
                helperText: context.l10n.hostPortHint,
                errorText: _portError,
                suffixIcon: _portDirty && _portError == null
                    ? IconButton(
                        key: const Key('host-port-save'),
                        tooltip: context.l10n.commonSave,
                        icon: const Icon(Icons.check),
                        onPressed: () => _savePort(announce: true),
                      )
                    : null,
              ),
              onSubmitted: (_) => _savePort(announce: true),
            ),
          ),
          SettingsRow(
            leading: const Icon(Icons.lan_outlined),
            title: Text(context.l10n.hostLocalOnly),
            subtitle: Text(context.l10n.hostLocalOnlyHint),
          ),
        ],
      ),
      const SizedBox(height: AppDesign.lg),
      FilledButton.icon(
        onPressed: canStart
            ? () {
                unawaited(_savePort());
                controller.start(port: int.parse(_port.text.trim()));
              }
            : null,
        icon: const Icon(Icons.play_arrow),
        label: Text(
          state.starting ? context.l10n.hostStarting : context.l10n.hostStart,
        ),
      ),
      SettingsSection(
        label: context.l10n.hostToken,
        children: [
          SettingsRow(
            leading: const Icon(Icons.autorenew),
            title: Text(context.l10n.hostRotate),
            subtitle: Text(context.l10n.hostRotateHint),
            onTap: () async {
              await controller.regenerateToken();
              if (context.mounted) {
                showIslandToast(context, context.l10n.hostRotated);
              }
            },
          ),
        ],
      ),
    ];
  }

  List<Widget> _running(BuildContext context, DeviceHostingState state) {
    final c = context.colors;
    final controller = ref.read(deviceHostingProvider.notifier);
    final token = state.token ?? '';
    final uptime = state.startedAt == null
        ? Duration.zero
        : DateTime.now().difference(state.startedAt!);
    return [
      // Status: what is served, for how long, and the stop button.
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppDesign.lg),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: state.activeClient == null ? c.success : c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppDesign.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.activeClient == null
                          ? context.l10n.hostWaiting
                          : '${context.l10n.hostAnswering(state.activeClient!)}'
                                '${state.liveTokens > 0 ? ' · ${state.liveTokens} ${context.l10n.goalTokensWord}' : ''}',
                      style: context.text.title,
                    ),
                    Text(
                      '${state.modelId ?? ''} · ${context.l10n.hostUp(_duration(uptime))}',
                      style: context.text.mono.copyWith(color: c.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: controller.stop,
                child: Text(context.l10n.goalStop),
              ),
            ],
          ),
        ),
      ),
      _modelRow(
        context,
        modelName: ref.watch(modelManagerProvider).loadedModel?.displayName,
        busy: state.activeClient != null,
      ),
      SettingsSection(label: context.l10n.hostLive),
      Wrap(
        spacing: AppDesign.sm,
        runSpacing: AppDesign.sm,
        children: [
          _Stat(context.l10n.hostAnswered, '${state.answered}'),
          _Stat(context.l10n.hostRefused, '${state.refused}'),
          if (state.failed > 0)
            _Stat(context.l10n.hostFailed, '${state.failed}', c.danger),
          _Stat(context.l10n.hostTokensIn, _count(state.promptTokens)),
          _Stat(context.l10n.hostTokensOut, _count(state.completionTokens)),
          _Stat(
            context.l10n.hostAvgSpeed,
            state.averageTokensPerSecond == 0
                ? '—'
                : '${state.averageTokensPerSecond.toStringAsFixed(1)} tok/s',
          ),
          _Stat(context.l10n.hostDevices, '${state.clients.length}'),
          if (state.power != null) ...[
            _Stat(
              context.l10n.hostBattery,
              '${state.power!.level}%${state.power!.charging ? ' ⚡' : ''}',
              !state.power!.charging && state.power!.level < 30
                  ? c.warning
                  : null,
            ),
            _Stat(
              context.l10n.hostHeat,
              state.power!.thermalLabel,
              state.power!.thermalStatus >= 2 ? c.warning : null,
            ),
          ],
        ],
      ),
      const SizedBox(height: AppDesign.sm),
      SettingsGroup(
        children: [
          SettingsRow(
            leading: const Icon(Icons.battery_alert_outlined),
            title: Text(context.l10n.hostLowBattery),
            subtitle: Text(context.l10n.hostLowBatteryHint),
            trailing: DropdownButton<int?>(
              value: controller.guards.minBattery,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.commonOff),
                ),
                for (final v in const [10, 20, 30, 50])
                  DropdownMenuItem(value: v, child: Text('$v%')),
              ],
              onChanged: (v) => setState(
                () => controller.guards = HostingGuards(
                  minBattery: v,
                  maxThermal: controller.guards.maxThermal,
                ),
              ),
            ),
          ),
        ],
      ),
      SettingsSection(
        label: context.l10n.hostConnect,
        children: [
          _CopyRow(
            icon: Icons.link_rounded,
            context.l10n.hostServerUrl,
            state.endpoint ?? '',
            _copy,
          ),
          _CopyRow(
            icon: Icons.badge_outlined,
            context.l10n.hostModelId,
            state.modelId ?? '',
            _copy,
          ),
          _CopyRow(
            icon: Icons.key_outlined,
            context.l10n.hostToken,
            token,
            _copy,
            shown: _showToken
                ? token
                : '•••••••• ${token.length > 4 ? token.substring(token.length - 4) : ''}',
            trailing: IconButton(
              tooltip: _showToken
                  ? context.l10n.hostHideToken
                  : context.l10n.hostShowToken,
              icon: Icon(
                _showToken
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
          ),
        ],
      ),
      if (state.pairing != null) ...[
        const SizedBox(height: AppDesign.lg),
        // The code carries the access token: shown only on request, since
        // the screen stays on while serving.
        Center(
          child: _showQr
              ? GestureDetector(
                  onTap: () => setState(() => _showQr = false),
                  child: QrView(state.pairing!),
                )
              : FilledButton.tonalIcon(
                  key: const Key('show-qr'),
                  onPressed: () => setState(() => _showQr = true),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(context.l10n.hostShowQr),
                ),
        ),
        const SizedBox(height: AppDesign.md),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => _copy(context.l10n.hostConnection, state.pairing!),
            icon: const Icon(Icons.link),
            label: Text(context.l10n.hostCopyConnection),
          ),
        ),
        const SizedBox(height: AppDesign.sm),
        Text(
          context.l10n.hostPairHint,
          style: context.text.bodyMuted,
          textAlign: TextAlign.center,
        ),
      ],
      SettingsSection(label: context.l10n.hostRecent),
      if (state.log.isEmpty)
        Text(context.l10n.hostNoneYet, style: context.text.bodyMuted)
      else
        SettingsGroup(children: [for (final r in state.log) _RequestRow(r)]),
    ];
  }

  static String _count(int n) =>
      n >= 10000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  static String _duration(Duration d) {
    if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
    if (d.inMinutes > 0) return '${d.inMinutes} min ${d.inSeconds % 60} s';
    return '${d.inSeconds} s';
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color? tone;
  const _Stat(this.label, this.value, [this.tone]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.md,
        vertical: AppDesign.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: context.text.monoStrong.copyWith(color: tone ?? c.text),
          ),
          // textMuted: textFaint on the raised surface is below 4.5:1.
          Text(label, style: context.text.label.copyWith(color: c.textMuted)),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  final String label, value;
  final String? shown;
  final Widget? trailing;
  final void Function(String label, String value) onCopy;
  final IconData? icon;
  const _CopyRow(
    this.label,
    this.value,
    this.onCopy, {
    this.shown,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => SettingsRow(
    leading: icon == null ? null : Icon(icon),
    title: Text(label),
    subtitle: Text(shown ?? value, style: context.text.mono),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?trailing,
        IconButton(
          tooltip: context.l10n.hostCopy(label),
          icon: const Icon(Icons.copy_outlined),
          onPressed: value.isEmpty ? null : () => onCopy(label, value),
        ),
      ],
    ),
  );
}

class _RequestRow extends StatelessWidget {
  final ServedRequest r;
  const _RequestRow(this.r);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = r.at;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    final detail = r.ok
        ? '${context.l10n.hostInOut(r.promptTokens, r.completionTokens)}'
              '${r.tokensPerSecond > 0 ? ' · ${r.tokensPerSecond.toStringAsFixed(1)} tok/s' : ''}'
              ' · ${(r.took.inMilliseconds / 1000).toStringAsFixed(1)} s'
              '${r.stream ? ' · stream' : ''}'
        : '${r.status} · ${r.error ?? context.l10n.hostFailed}';
    return SettingsRow(
      dense: true,
      leading: Icon(
        r.ok ? Icons.check_circle_outline : Icons.block,
        size: 18,
        color: r.ok ? c.success : c.warning,
      ),
      title: Text('$time · ${r.client}', style: context.text.mono),
      subtitle: Text(detail, style: context.text.bodyMuted),
    );
  }
}

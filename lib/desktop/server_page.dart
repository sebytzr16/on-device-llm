import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../features/hosting/device_model_server.dart';
import '../features/hosting/model_pool.dart';
import '../features/hosting/pairing_code.dart';
import '../features/hosting/presentation/device_hosting_provider.dart';
import '../features/hosting/presentation/pool_options_provider.dart';
import '../features/hosting/presentation/qr_view.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import 'developer_widgets.dart';
import '../core/platform/desktop_preferences.dart';
import 'lan_check.dart';
import 'server_usage_card.dart';

class DesktopServerPage extends ConsumerStatefulWidget {
  const DesktopServerPage({super.key});
  @override
  ConsumerState<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends ConsumerState<DesktopServerPage> {
  final _port = TextEditingController(text: '8787');
  bool _reveal = false;
  bool _changingToken = false;
  // Off: only apps on this computer can reach the server.
  bool _lan = false;
  String? _actionError;
  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  Future<void> _regenerate() async {
    setState(() {
      _changingToken = true;
      _reveal = false;
      _actionError = null;
    });
    try {
      await ref.read(deviceHostingProvider.notifier).regenerateToken();
    } catch (e) {
      if (mounted) setState(() => _actionError = '$e');
    } finally {
      if (mounted) setState(() => _changingToken = false);
    }
  }

  Future<void> _unloadPooled(String id) async {
    setState(() => _actionError = null);
    try {
      await ref.read(deviceHostingProvider.notifier).unloadPooled(id);
    } catch (e) {
      if (mounted) setState(() => _actionError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final advanced = ref.watch(desktopPreferencesProvider).advanced;
    final host = ref.watch(deviceHostingProvider);
    final models = ref.watch(modelManagerProvider);
    final poolOptions = ref.watch(poolOptionsProvider);
    final port = int.tryParse(_port.text);
    final valid = port != null && port >= 1 && port <= 65535;
    final busy = host.starting || _changingToken;
    final hasModel = models.loadedModel != null && !models.isLoadingModel;
    final endpoint = host.endpoint;
    final base = endpoint ?? 'http://localhost:${valid ? port : 8787}/v1/';
    final origin = Uri.parse(base).resolve('/').toString();
    // Use a shell variable so the example never reveals the access token.
    final curl =
        'curl "${origin.substring(0, origin.length - 1)}${DeviceModelServer.modelsPath}" -H "Authorization: Bearer \$TOKEN"';
    Widget value(
      String label,
      String text, {
      bool copy = false,
      String? copyValue,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.small),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: SelectableText(text, style: context.text.mono)),
              if (copy)
                IconButton(
                  tooltip: t.desktopServerCopy,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: copyValue ?? text)),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                ),
            ],
          ),
        ],
      ),
    );
    // The name people know, then the id API clients send as "model".
    final modelLabel = {
      ?models.loadedModel?.displayName,
      ?(host.modelId ?? models.loadedModelId),
    }.join(' · ');
    final controls = DeveloperCard(
      title: t.desktopServerStatus,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: host.running
                    ? context.colors.success
                    : host.starting
                    ? context.colors.accent
                    : context.colors.textFaint,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              host.starting
                  ? t.desktopServerStarting
                  : host.running
                  ? t.desktopServerRunning
                  : t.desktopServerStopped,
              style: context.text.title.copyWith(
                color: host.running
                    ? context.colors.success
                    : context.colors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('server-port'),
          controller: _port,
          enabled: !host.running && !busy,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t.desktopServerPort,
            errorText: valid ? null : t.desktopServerInvalidPort,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.desktopServerLan, style: context.text.body),
                  Text(t.desktopServerLanHint, style: context.text.small),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              key: const Key('server-lan'),
              value: host.running ? Uri.parse(base).host != '127.0.0.1' : _lan,
              onChanged: host.running || busy
                  ? null
                  : (v) => setState(() => _lan = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.row),
        Align(
          alignment: Alignment.centerLeft,
          child: DeveloperButton(
            primary: !host.running,
            icon: host.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
            label: host.running ? t.desktopServerStop : t.desktopServerStart,
            onPressed: busy || (!host.running && (!valid || !hasModel))
                ? null
                : () {
                    final notifier = ref.read(deviceHostingProvider.notifier);
                    if (host.running) {
                      unawaited(notifier.stop());
                    } else {
                      unawaited(notifier.start(port: port!, lan: _lan));
                    }
                  },
          ),
        ),
        if (!host.running && !hasModel) ...[
          const SizedBox(height: 10),
          Text(t.desktopServerNeedsModel, style: context.text.small),
        ],
        const SizedBox(height: AppSpace.section),
        if (host.running) ...[
          value(
            t.desktopServerBind,
            host.running
                ? '${Uri.parse(base).host == '127.0.0.1' ? '127.0.0.1' : '0.0.0.0'}:${Uri.parse(base).port}'
                : '—',
            copy: host.running,
          ),
          value(t.desktopServerUrl, endpoint ?? '—', copy: endpoint != null),
        ],
        value(
          t.desktopServerModel,
          modelLabel.isEmpty ? t.desktopServerNoModel : modelLabel,
        ),
      ],
    );
    final tlsError = t.hostTlsIdentityError;
    final showResetIdentity =
        (host.error == tlsError) || (_actionError == tlsError);
    if (host.error != null || _actionError != null) {
      controls.children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _actionError ?? host.error!,
              style: context.text.small.copyWith(color: context.colors.danger),
            ),
            if (showResetIdentity)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await confirmAction(
                      context,
                      title: t.hostResetIdentity,
                      message: t.hostResetIdentityConfirm,
                      confirmLabel: t.hostResetIdentity,
                      destructive: true,
                    );
                    if (confirmed && context.mounted) {
                      await ref
                          .read(deviceHostingProvider.notifier)
                          .resetHostIdentity();
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(t.hostResetIdentity),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.danger,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (host.stoppedReason != null) {
      controls.children.add(
        Text(host.stoppedReason!, style: context.text.small),
      );
    }
    void setPool(PoolOptions next) =>
        unawaited(ref.read(poolOptionsProvider.notifier).set(next));
    final ids = <String>{
      ?(host.modelId ?? models.loadedModelId),
      if (poolOptions.jit)
        for (final model in models.catalog)
          if (model.isDownloaded) model.id,
    };
    final pool = DeveloperCard(
      title: t.desktopPoolModels,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.desktopPoolJit, style: context.text.body),
                  Text(t.desktopPoolJitHint, style: context.text.small),
                ],
              ),
            ),
            Switch(
              key: const Key('desktop-pool-jit'),
              value: poolOptions.jit,
              onChanged: (value) => setPool(poolOptions.copyWith(jit: value)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                t.desktopPoolMaxLoaded(poolOptions.maxLoaded),
                style: context.text.body,
              ),
            ),
            IconButton(
              key: const Key('desktop-pool-decrease'),
              tooltip: t.desktopPoolDecrease,
              onPressed: poolOptions.maxLoaded > 1
                  ? () => setPool(
                      poolOptions.copyWith(
                        maxLoaded: poolOptions.maxLoaded - 1,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Text('${poolOptions.maxLoaded}', style: context.text.mono),
            IconButton(
              key: const Key('desktop-pool-increase'),
              tooltip: t.desktopPoolIncrease,
              onPressed: poolOptions.maxLoaded < 8
                  ? () => setPool(
                      poolOptions.copyWith(
                        maxLoaded: poolOptions.maxLoaded + 1,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(t.desktopPoolIdleUnload, style: context.text.body),
            ),
            DropdownButton<int?>(
              key: const Key('desktop-pool-idle'),
              value: poolOptions.idleUnload?.inMinutes,
              items: [
                for (final minutes in [5, 10, 30, 60])
                  DropdownMenuItem<int?>(
                    value: minutes,
                    child: Text(t.desktopPoolMinutes(minutes)),
                  ),
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(t.desktopPoolNever),
                ),
              ],
              onChanged: (minutes) => setPool(
                poolOptions.copyWith(
                  idleUnload: minutes == null
                      ? null
                      : Duration(minutes: minutes),
                  keepLoaded: minutes == null,
                ),
              ),
            ),
          ],
        ),
        if (host.pooled.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(t.desktopPoolLoaded, style: context.text.small),
          for (final pooled in host.pooled)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      models.catalog
                              .where((m) => m.id == pooled.id)
                              .map((m) => m.displayName)
                              .firstOrNull ??
                          pooled.id,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.body,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.accent.withValues(alpha: 0.12),
                      borderRadius: AppDesign.radius(AppDesign.rSm),
                    ),
                    child: Text(
                      pooled.loading
                          ? t.desktopPoolLoading
                          : pooled.busy
                          ? t.desktopPoolAnswering
                          : t.desktopPoolIdle,
                      style: context.text.small.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    t.desktopPoolLastUsed(
                      MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay.fromDateTime(pooled.lastUsed.toLocal()),
                      ),
                    ),
                    style: context.text.small,
                  ),
                  MergeSemantics(
                    key: Key('desktop-pool-pin-${pooled.id}'),
                    child: Semantics(
                      label: poolOptions.pinned.contains(pooled.id)
                          ? t.poolPinUnpin
                          : t.poolPinPin,
                      toggled: poolOptions.pinned.contains(pooled.id),
                      child: IconButton(
                        tooltip: poolOptions.pinned.contains(pooled.id)
                            ? t.poolPinUnpin
                            : t.poolPinPin,
                        onPressed: () => unawaited(
                          ref
                              .read(poolOptionsProvider.notifier)
                              .togglePinned(pooled.id),
                        ),
                        icon: Icon(
                          poolOptions.pinned.contains(pooled.id)
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 18,
                          color: poolOptions.pinned.contains(pooled.id)
                              ? context.colors.accent
                              : null,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('desktop-pool-eject-${pooled.id}'),
                    tooltip: t.desktopPoolEject,
                    onPressed: () => _unloadPooled(pooled.id),
                    icon: const Icon(Icons.eject_rounded, size: 18),
                  ),
                ],
              ),
            ),
        ],
        if (ids.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(t.desktopPoolClientIds, style: context.text.small),
          for (final id in ids)
            Row(
              children: [
                Expanded(child: SelectableText(id, style: context.text.mono)),
                IconButton(
                  key: Key('desktop-pool-copy-$id'),
                  tooltip: t.desktopServerCopy,
                  onPressed: () => Clipboard.setData(ClipboardData(text: id)),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                ),
              ],
            ),
        ],
      ],
    );
    final paired = DeveloperCard(
      title: t.hostPairedDevices,
      children: [
        if (host.legacyTokenEnabled)
          ListTile(
            title: Text(t.hostLegacyDevices),
            subtitle: Text(t.hostLegacyDevicesHint),
            trailing: TextButton(
              onPressed: () => ref
                  .read(deviceHostingProvider.notifier)
                  .revokeDevice('legacy'),
              child: Text(t.hostRevokeDevice),
            ),
          ),
        for (final device in host.pairedDevices)
          ListTile(
            title: Text(device.name),
            subtitle: Text(device.pairedAt.toLocal().toString()),
            trailing: TextButton(
              onPressed: () => ref
                  .read(deviceHostingProvider.notifier)
                  .revokeDevice(device.id),
              child: Text(t.hostRevokeDevice),
            ),
          ),
      ],
    );
    final api = DeveloperCard(
      title: t.desktopServerEndpoints,
      children: [
        SelectableText(
          'GET  ${DeviceModelServer.modelsPath}\n'
          'POST ${DeviceModelServer.completionsPath}\n'
          'POST ${DeviceModelServer.embeddingsPath}\n'
          'POST ${DeviceModelServer.rerankPath}\n'
          'POST ${DeviceModelServer.messagesPath}',
          style: context.text.mono,
        ),
        const SizedBox(height: AppSpace.section),
        value(
          t.desktopServerToken,
          host.token == null
              ? '—'
              : _reveal
              ? host.token!
              : '••••••••••••••••',
          copy: host.token != null,
          copyValue: host.token,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DeveloperButton(
              label: _reveal ? t.desktopServerHide : t.desktopServerReveal,
              onPressed: host.token == null
                  ? null
                  : () => setState(() => _reveal = !_reveal),
            ),
            DeveloperButton(
              label: t.desktopServerRegenerate,
              onPressed: busy ? null : _regenerate,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.row),
        Text(t.desktopServerRegenerateHint, style: context.text.small),
        const SizedBox(height: AppSpace.section),
        value(t.desktopServerCurl, curl, copy: true),
      ],
    );
    final lanOn = host.running ? Uri.parse(base).host != '127.0.0.1' : _lan;
    final pair = DeveloperCard(
      title: t.desktopServerPair,
      children: [
        if (lanOn && host.running && host.pairing != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QrView(host.pairing!, size: 196),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.desktopServerPairHint, style: context.text.body),
                    const SizedBox(height: 16),
                    value(
                      t.desktopServerAddress,
                      Uri.parse(base).authority,
                      copy: true,
                    ),
                    if (host.pairCode case final code?) ...[
                      Text(t.hostPairCode, style: context.text.small),
                      const SizedBox(height: 6),
                      SelectableText(
                        '${code.substring(0, 3)} ${code.substring(3)}',
                        key: const Key('server-pair-code'),
                        style: context.text.mono.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                          color: context.colors.accent,
                        ),
                      ),
                      if (host.pairExpiresAt case final until?)
                        Text(
                          t.hostPairValidUntil(
                            TimeOfDay.fromDateTime(until).format(context),
                          ),
                          style: context.text.small,
                        ),
                      if (host.fingerprint case final fingerprint?) ...[
                        const SizedBox(height: 12),
                        value(
                          t.hostPairFingerprint,
                          PairingCode.shortFingerprint(fingerprint),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          )
        else
          Text(t.desktopServerPairOff, style: context.text.small),
        if (Platform.isWindows && lanOn) ...[
          const SizedBox(height: AppSpace.section),
          const _NetworkCheck(),
        ],
      ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.desktopPage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeveloperPageHeader(
            title: t.desktopServerTitle,
            subtitle: t.desktopServerHint,
          ),
          if (!advanced)
            controls
          else
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: controls),
                        const SizedBox(width: 20),
                        Expanded(child: api),
                      ],
                    )
                  : Column(
                      children: [
                        controls,
                        const SizedBox(height: AppSpace.section),
                        api,
                      ],
                    ),
            ),
          const SizedBox(height: AppSpace.section),
          if (advanced) pool,
          const SizedBox(height: AppSpace.section),
          pair,
          const SizedBox(height: AppSpace.section),
          if (host.running) paired,
          const SizedBox(height: AppSpace.section),
          if (advanced) ServerUsageCard(usage: host.usage),
          const SizedBox(height: AppSpace.section),
          if (advanced)
            DeveloperCard(
              title: t.desktopServerRequests,
              children: [
                Text(t.desktopServerRequestColumns, style: context.text.small),
                const SizedBox(height: 12),
                if (host.log.isEmpty)
                  Text(t.desktopServerNoRequests, style: context.text.mono),
                // A fixed-height box with its own scroll bar, so a long log
                // does not push the page down (owner, 2026-11-08).
                if (host.log.isNotEmpty) _RequestLog(log: host.log),
              ],
            ),
        ],
      ),
    );
  }
}

class _RequestLog extends StatefulWidget {
  final List<ServedRequest> log;
  const _RequestLog({required this.log});
  @override
  State<_RequestLog> createState() => _RequestLogState();
}

class _RequestLogState extends State<_RequestLog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scroll,
          shrinkWrap: true,
          padding: const EdgeInsets.only(right: 16),
          itemCount: log.length,
          itemBuilder: (context, i) {
            final r = log[i];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: SelectableText(
                '${r.at.toIso8601String()}  ${r.method} ${r.path} · ${r.status} · ${r.took.inMilliseconds} ms'
                '${r.completion ? ' · ${r.promptTokens} / ${r.completionTokens}' : ''}',
                style: context.text.mono,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// What on this PC may stop a phone from reaching the server, with the fix
/// next to each finding.
class _NetworkCheck extends ConsumerStatefulWidget {
  const _NetworkCheck();
  @override
  ConsumerState<_NetworkCheck> createState() => _NetworkCheckState();
}

class _NetworkCheckState extends ConsumerState<_NetworkCheck> {
  bool _fixing = false;

  Future<void> _allow(LanCheck check) async {
    setState(() => _fixing = true);
    try {
      await LanCheck.allowInFirewall(public: check.onPublic);
    } finally {
      if (mounted) {
        setState(() => _fixing = false);
        ref.invalidate(lanCheckProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final check = ref.watch(lanCheckProvider);
    Widget finding(bool ok, String text, [Widget? action]) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              size: 16,
              color: ok ? c.success : c.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: context.text.body),
                if (action != null) ...[
                  const SizedBox(height: AppSpace.row),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.desktopLanTitle, style: context.text.small),
        const SizedBox(height: 10),
        ...switch (check) {
          AsyncData(:final value) => [
            for (final name in value.publicNetworks)
              finding(
                false,
                t.desktopLanPublic(name),
                DeveloperButton(
                  icon: Icons.open_in_new_rounded,
                  label: t.desktopLanOpenSettings,
                  onPressed: () => launchUrl(
                    Uri.parse(
                      RegExp('wi-?fi|wlan', caseSensitive: false).hasMatch(name)
                          ? 'ms-settings:network-wifi'
                          : 'ms-settings:network-ethernet',
                    ),
                  ),
                ),
              ),
            if (value.firewall == true)
              finding(true, t.desktopLanFirewallOk)
            else
              finding(
                false,
                value.firewall == false
                    ? t.desktopLanBlocked
                    : t.desktopLanNoRule,
                DeveloperButton(
                  icon: Icons.shield_outlined,
                  label: t.desktopLanAllow,
                  onPressed: _fixing ? null : () => _allow(value),
                ),
              ),
            if (value.vpns.isNotEmpty)
              finding(false, t.desktopLanVpn(value.vpns.join(', '))),
            if (value.clear) finding(true, t.desktopLanClear),
          ],
          AsyncError() => [finding(false, t.desktopLanNoRule)],
          _ => [Text(t.desktopLanChecking, style: context.text.small)],
        },
        DeveloperButton(
          icon: Icons.refresh_rounded,
          label: t.desktopLanRecheck,
          onPressed: check.isLoading
              ? null
              : () => ref.invalidate(lanCheckProvider),
        ),
      ],
    );
  }
}

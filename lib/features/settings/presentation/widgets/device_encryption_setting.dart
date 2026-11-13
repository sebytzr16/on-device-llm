import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/storage/device_encryption.dart';
import 'settings_widgets.dart';

class DeviceEncryptionSetting extends StatefulWidget {
  const DeviceEncryptionSetting({super.key});
  @override
  State<DeviceEncryptionSetting> createState() =>
      _DeviceEncryptionSettingState();
}

class _DeviceEncryptionSettingState extends State<DeviceEncryptionSetting> {
  bool _enabled = false;
  bool _busy = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final enabled = await DeviceEncryption.instance.enabled();
      if (mounted) {
        setState(() {
          _enabled = enabled;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(bool value) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await DeviceEncryption.instance.setEnabled(value);
      // Owner 2026-11-12: the switch "did nothing" because the migration is
      // silent. Say what changed once it has finished.
      if (mounted) {
        showIslandToast(
          context,
          value
              ? context.l10n.deviceEncryptionDoneOn
              : context.l10n.deviceEncryptionDoneOff,
          tone: IslandTone.done,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        SettingsSwitchRow(
          key: const Key('device-encryption'),
          secondary: const Icon(Icons.enhanced_encryption_outlined),
          title: Text(context.l10n.deviceEncryptionTitle),
          subtitle: Text(
            _busy
                ? context.l10n.deviceEncryptionWorking
                : context.l10n.deviceEncryptionHint,
          ),
          value: _enabled,
          onChanged: _busy ? null : _change,
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text(context.l10n.deviceEncryptionFailed),
          ),
        if (_failed)
          TextButton(
            onPressed: _busy ? null : () => _change(_enabled),
            child: Text(context.l10n.deviceEncryptionRetry),
          ),
      ],
    );
  }
}

/// Above all routes on phone and desktop; swallowed cache/read errors still
/// produce a clear recovery explanation without exposing key/platform details.
class EncryptionRecoveryNotice extends StatelessWidget {
  const EncryptionRecoveryNotice({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DeviceEncryption.instance.recovery,
    builder: (context, failed, _) => failed
        ? Positioned(
            left: AppSpace.md,
            right: AppSpace.md,
            bottom: AppSpace.md,
            child: SafeArea(
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: AppDesign.radius(AppDesign.rMd),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(
                    context.l10n.deviceEncryptionRecovery,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink(),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import 'developer_widgets.dart';
import 'engine_files.dart';

class EngineFilesPanel extends StatefulWidget {
  final EngineFiles Function()? read;
  const EngineFilesPanel({super.key, this.read});

  @override
  State<EngineFilesPanel> createState() => _EngineFilesPanelState();
}

class _EngineFilesPanelState extends State<EngineFilesPanel> {
  final _results = <EngineFileResult>[];
  StreamSubscription<EngineFileResult>? _subscription;
  EngineFiles? _engine;
  bool _busy = false;

  Future<void> _verify() async {
    final engine = (widget.read ?? EngineFiles.besideExecutable)();
    setState(() {
      _engine = engine;
      _results.clear();
      _busy = engine.state == EngineManifestState.ready;
    });
    if (!_busy) return;
    _subscription = engine.verify().listen(
      (result) {
        if (mounted) setState(() => _results.add(result));
      },
      onDone: () {
        if (mounted) {
          setState(() => _busy = false);
        }
      },
      onError: (Object _) {
        if (mounted) {
          setState(() {
            _engine = EngineFiles(
              engine.directory,
              EngineManifestState.malformed,
              const [],
            );
            _busy = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final failures = _results
        .where((r) => r.status != EngineFileStatus.ok)
        .map((r) => r.name)
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DeveloperButton(
          label: t.engineFilesVerify,
          onPressed: _busy ? null : _verify,
          icon: Icons.fact_check_outlined,
        ),
        if (_busy) ...[
          LinearProgressIndicator(
            value: _results.length / _engine!.files.length,
          ),
          Text(
            t.engineFilesProgress(_results.length, _engine!.files.length),
            style: context.text.small,
          ),
        ],
        if (_engine?.state == EngineManifestState.unverified)
          Text(t.engineFilesUnverified, style: context.text.bodyMuted),
        if (_engine?.state == EngineManifestState.malformed)
          Text(t.engineFilesMalformed, style: context.text.bodyMuted),
        for (final result in _results)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${result.name}: ${switch (result.status) {
                EngineFileStatus.ok => t.engineFilesOk,
                EngineFileStatus.missing => t.engineFilesMissing,
                EngineFileStatus.wrongSize => t.engineFilesWrongSize,
                EngineFileStatus.changed => t.engineFilesChanged,
                EngineFileStatus.unreadable => t.engineFilesUnreadable,
              }}',
              style: context.text.mono,
            ),
          ),
        if (failures.isNotEmpty)
          Text(
            t.engineFilesRepair(failures),
            style: context.text.body.copyWith(color: context.colors.warning),
          ),
      ],
    );
  }
}

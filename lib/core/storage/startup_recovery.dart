import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../design/app_dialog.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../../features/settings/domain/entities/inference_settings.dart';
import 'startup_database_files.dart';
import 'device_encryption.dart';

/// Mounted before database initialization, including migration and repair.
class StartupRecoveryApp extends StatefulWidget {
  const StartupRecoveryApp({
    super.key,
    required this.initialize,
    this.exportDatabase,
    this.resetDatabase,
  });
  final Future<Widget> Function() initialize;
  final Future<void> Function(BuildContext)? exportDatabase;
  final Future<void> Function()? resetDatabase;

  @override
  State<StartupRecoveryApp> createState() => _StartupRecoveryAppState();
}

class _StartupRecoveryAppState extends State<StartupRecoveryApp> {
  Widget? _app;
  Object? _error;
  StackTrace? _stack;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final app = await widget.initialize();
      if (mounted) setState(() => _app = app);
    } catch (error, stack) {
      if (mounted)
        setState(() {
          _error = error;
          _stack = stack;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error, stack) {
      if (mounted)
        setState(() {
          _error = error;
          _stack = stack;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_app != null) return _app!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.of(AccentChoice.amber, dark: false),
      darkTheme: AppTheme.of(AccentChoice.amber, dark: true),
      home: Builder(
        builder: (context) {
          final t = context.l10n;
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_busy) const CircularProgressIndicator(),
                        if (_error != null) ...[
                          Text(
                            t.startupFailedTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error is EncryptionRecovery
                                ? t.deviceEncryptionRecovery
                                : t.startupFailedBody,
                          ),
                          const SizedBox(height: 16),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: SingleChildScrollView(
                              child: SelectableText('$_error\n\n$_stack'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(
                                        () => Clipboard.setData(
                                          ClipboardData(
                                            text: '$_error\n$_stack',
                                          ),
                                        ),
                                      ),
                                child: Text(t.startupCopyDetails),
                              ),
                              FilledButton(
                                onPressed: _busy ? null : _start,
                                child: Text(t.startupRetry),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _action(() async {
                                        if (widget.exportDatabase
                                            case final exportFiles?) {
                                          await exportFiles(context);
                                        } else {
                                          final file =
                                              await StartupDatabaseFiles()
                                                  .exportFiles();
                                          if (!context.mounted) return;
                                          final box =
                                              context.findRenderObject()
                                                  as RenderBox?;
                                          await SharePlus.instance.share(
                                            ShareParams(
                                              files: [XFile(file.path)],
                                              sharePositionOrigin: box == null
                                                  ? null
                                                  : box.localToGlobal(
                                                          Offset.zero,
                                                        ) &
                                                        box.size,
                                            ),
                                          );
                                        }
                                      }),
                                child: Text(t.startupExport),
                              ),
                              OutlinedButton(
                                onPressed: _busy || _error is EncryptionRecovery
                                    ? null
                                    : () async {
                                        // Ask first: the busy spinner only
                                        // runs while the reset itself does.
                                        final approved = await confirmAction(
                                          context,
                                          title: t.startupResetTitle,
                                          message: t.startupResetBody,
                                          confirmLabel: t.reset,
                                          destructive: true,
                                        );
                                        if (!approved || !mounted) return;
                                        var reset = false;
                                        await _action(() async {
                                          await (widget.resetDatabase ??
                                              StartupDatabaseFiles().reset)();
                                          reset = true;
                                        });
                                        if (reset && mounted) await _start();
                                      },
                                child: Text(t.reset),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

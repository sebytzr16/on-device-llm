import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../attachments/domain/scan_options.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/design/app_design.dart';

class ScanSettingsPage extends StatefulWidget {
  const ScanSettingsPage({super.key});
  @override
  State<ScanSettingsPage> createState() => _ScanSettingsPageState();
}

class _ScanSettingsPageState extends State<ScanSettingsPage> {
  ScanOptions? _options;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await ScanOptions.read();
      if (mounted) setState(() => _options = options);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save(ScanOptions value) async {
    setState(() => _options = value);
    try {
      await value.save();
      if (mounted && identical(_options, value)) {
        setState(() => _error = null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n, options = _options;
    return Scaffold(
      appBar: AppBar(title: Text(t.scanSettings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDesign.lg),
          children: [
            SettingsNote(
              t.scanQualityHint,
              icon: Icons.document_scanner_outlined,
            ),
            if (_error != null) Text(_error!),
            if (options == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (options != null) ...[
              SettingsGroup(
                children: [
                  SettingsRow(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(t.scanPageLimit),
                    subtitle: Text(t.scanLongHint),
                    trailing: DropdownButton<int>(
                      value: options.maxScannedPages,
                      items: [
                        for (final limit in ScanOptions.pageLimits)
                          DropdownMenuItem(value: limit, child: Text('$limit')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _save(
                            ScanOptions(
                              language: options.language,
                              maxScannedPages: value,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (Platform.isIOS)
                SettingsGroup(
                  children: [
                    SettingsRow(
                      leading: const Icon(Icons.translate_rounded),
                      title: Text(t.scanLanguage),
                      trailing: DropdownButton<String>(
                        value: options.language,
                        items: [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text(t.searchRegionAutomatic),
                          ),
                          const DropdownMenuItem(
                            value: 'en',
                            child: Text('English'),
                          ),
                          const DropdownMenuItem(
                            value: 'fr',
                            child: Text('Français'),
                          ),
                          const DropdownMenuItem(
                            value: 'es',
                            child: Text('Español'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _save(
                              ScanOptions(
                                language: value,
                                maxScannedPages: options.maxScannedPages,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                )
              else
                SettingsNote(t.scanLatinHint, icon: Icons.language),
            ],
          ],
        ),
      ),
    );
  }
}

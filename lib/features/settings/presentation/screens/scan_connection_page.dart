import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';

/// Camera view that reads the pairing QR code another phone shows under
/// "Use this device as a server". Pops with the code's text once [accept]
/// says it is a connection; other codes only show a hint. Decoding runs on
/// the phone (ML Kit's bundled model); nothing is uploaded.
class ScanConnectionPage extends StatefulWidget {
  final bool Function(String text) accept;
  const ScanConnectionPage({super.key, required this.accept});

  @override
  State<ScanConnectionPage> createState() => _ScanConnectionPageState();
}

class _ScanConnectionPageState extends State<ScanConnectionPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false, _wrongCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue;
      if (text == null) continue;
      if (widget.accept(text)) {
        _done = true;
        Navigator.of(context).pop(text);
        return;
      }
    }
    if (!_wrongCode) setState(() => _wrongCode = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.remoteScanQr)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppDesign.xl),
                child: Text(
                  t.remoteScanNoCamera(
                    error.errorDetails?.message ?? error.errorCode.name,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // A square guide so the user knows where to aim.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.accent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: AppDesign.lg,
            right: AppDesign.lg,
            bottom: AppDesign.xxl,
            child: Container(
              padding: const EdgeInsets.all(AppDesign.md),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _wrongCode ? t.remoteScanInvalid : t.remoteScanHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import '../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// A QR code drawn on the device (no service, no image file). Always dark
/// modules on white with a quiet zone, whatever the app theme, so phone
/// cameras read it.
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView(this.data, {super.key, this.size = 220});

  // The hosting page rebuilds every second (uptime); encode once per data.
  static String? _lastData;
  static QrImage? _lastImage;

  static QrImage _image(String data) {
    if (data != _lastData || _lastImage == null) {
      _lastImage = QrImage(
        QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
      _lastData = data;
    }
    return _lastImage!;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image(data);
    return Semantics(
      label: context.l10n.uiQrViewQRCodeWithTheConnectionDetails,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size / 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final QrImage image;
  _QrPainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = Colors.black;
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) {
          // A hair of overlap so no seams show between modules.
          path.addRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3),
          );
        }
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

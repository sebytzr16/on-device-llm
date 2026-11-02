import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';

enum ModelBrand {
  google,
  qwen,
  nvidia,
  ibm,
  meta,
  mistral,
  microsoft,
  liquid,
  deepseek,
  openai,
  huggingFace,
  unknown,
}

ModelBrand modelBrand(String name) {
  final value = name.toLowerCase();
  final org = value.split('/').first;
  const publishers = {
    'google': ModelBrand.google,
    'qwen': ModelBrand.qwen,
    'alibaba': ModelBrand.qwen,
    'nvidia': ModelBrand.nvidia,
    'ibm': ModelBrand.ibm,
    'ibm-granite': ModelBrand.ibm,
    'meta-llama': ModelBrand.meta,
    'mistralai': ModelBrand.mistral,
    'microsoft': ModelBrand.microsoft,
    'liquidai': ModelBrand.liquid,
    'deepseek-ai': ModelBrand.deepseek,
    'openai': ModelBrand.openai,
    'huggingfacetb': ModelBrand.huggingFace,
  };
  if (publishers[org] case final brand?) return brand;
  if (value.contains('deepseek')) return ModelBrand.deepseek;
  for (final entry in const {
    ModelBrand.google: ['gemma', 'google/'],
    ModelBrand.qwen: ['qwen', 'alibaba'],
    ModelBrand.nvidia: ['nvidia', 'nemotron'],
    ModelBrand.ibm: ['granite', 'ibm/'],
    ModelBrand.meta: ['llama', 'meta-llama'],
    ModelBrand.mistral: ['mistral', 'mixtral', 'ministral'],
    ModelBrand.microsoft: ['microsoft', 'phi-'],
    ModelBrand.liquid: ['liquid', 'lfm'],
    ModelBrand.deepseek: ['deepseek'],
    ModelBrand.openai: ['openai', 'gpt-oss'],
    ModelBrand.huggingFace: ['huggingface', 'smollm'],
  }.entries) {
    if (entry.value.any(value.contains)) return entry.key;
  }
  return ModelBrand.unknown;
}

/// Bundled monochrome vector marks. No image loader or network requests.
class ModelBrandIcon extends StatelessWidget {
  final String name;
  final double size;
  const ModelBrandIcon(this.name, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final brand = modelBrand(name);
    if (brand != ModelBrand.unknown) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _BrandPainter(brand, context.colors.text)),
      );
    }
    final letter = name.split('/').last.trim();
    final hue = name.codeUnits.fold<int>(0, (a, b) => a + b) % 360;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(0.18, hue.toDouble(), 0.65, 0.5).toColor(),
        borderRadius: AppDesign.radius(AppDesign.rSm),
      ),
      child: Text(
        letter.isEmpty ? '?' : letter.characters.first.toUpperCase(),
        style: context.text.label.copyWith(color: context.colors.text),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  final ModelBrand brand;
  final Color color;
  _BrandPainter(this.brand, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, stroke);
    }

    switch (brand) {
      case ModelBrand.google:
        canvas.drawArc(
          const Rect.fromLTWH(3, 3, 18, 18),
          0.7,
          5.4,
          false,
          stroke..strokeWidth = 3.5,
        );
        line(const [Offset(13, 12), Offset(21, 12), Offset(21, 17)]);
      case ModelBrand.microsoft:
        for (final x in [3.0, 13.0]) {
          for (final y in [3.0, 13.0]) {
            canvas.drawRect(Rect.fromLTWH(x, y, 8, 8), fill);
          }
        }
      case ModelBrand.meta:
        canvas.drawPath(
          Path()
            ..moveTo(12, 12)
            ..cubicTo(3, -4, -3, 22, 6, 19)
            ..cubicTo(12, 17, 13, 1, 18, 5)
            ..cubicTo(28, 14, 21, 27, 12, 12),
          stroke,
        );
      case ModelBrand.mistral:
        for (var row = 0; row < 5; row++) {
          for (var col = 0; col < 5; col++) {
            if (col == 0 ||
                col == 4 ||
                (row < 3 && (col == row || col == 4 - row))) {
              canvas.drawRect(
                Rect.fromLTWH(2 + col * 4.0, 2 + row * 4.0, 4, 4),
                fill,
              );
            }
          }
        }
      case ModelBrand.ibm:
        for (var y = 4.0; y < 22; y += 3) {
          canvas.drawRect(Rect.fromLTWH(2, y, 4, 1.5), fill);
          canvas.drawRect(
            Rect.fromLTWH(8, y, y == 4 || y == 19 ? 5 : 6, 1.5),
            fill,
          );
          canvas.drawRect(Rect.fromLTWH(16, y, 2, 1.5), fill);
          canvas.drawRect(Rect.fromLTWH(21, y, 2, 1.5), fill);
          if (y < 13) canvas.drawRect(Rect.fromLTWH(18, y, 3, 1.5), fill);
        }
      case ModelBrand.qwen:
        line(const [
          Offset(12, 2),
          Offset(21, 8),
          Offset(19, 19),
          Offset(8, 22),
          Offset(2, 12),
          Offset(12, 2),
          Offset(16, 14),
          Offset(5, 8),
          Offset(19, 19),
        ]);
      case ModelBrand.nvidia:
        canvas.drawPath(
          Path()
            ..moveTo(2, 12)
            ..quadraticBezierTo(12, 0, 22, 10)
            ..lineTo(22, 19)
            ..quadraticBezierTo(8, 25, 5, 13)
            ..quadraticBezierTo(14, 5, 18, 13)
            ..quadraticBezierTo(12, 20, 10, 13),
          stroke,
        );
      case ModelBrand.liquid:
        canvas.drawPath(
          Path()
            ..moveTo(5, 3)
            ..lineTo(5, 20)
            ..lineTo(21, 20),
          stroke..strokeWidth = 3,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10, 4)
            ..quadraticBezierTo(22, 8, 11, 13)
            ..quadraticBezierTo(21, 14, 20, 17),
          stroke,
        );
      case ModelBrand.deepseek:
        canvas.drawPath(
          Path()
            ..moveTo(2, 10)
            ..quadraticBezierTo(10, 2, 17, 11)
            ..lineTo(23, 6)
            ..lineTo(21, 15)
            ..quadraticBezierTo(10, 25, 2, 10)
            ..close(),
          fill,
        );
      case ModelBrand.openai:
        for (var i = 0; i < 6; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * 1.04719755);
          canvas.drawPath(
            Path()
              ..moveTo(-2, -2)
              ..lineTo(-2, -9)
              ..quadraticBezierTo(6, -12, 8, -4)
              ..lineTo(3, 2),
            stroke,
          );
          canvas.restore();
        }
      case ModelBrand.huggingFace:
        canvas.drawCircle(const Offset(12, 10), 7, stroke);
        canvas.drawCircle(const Offset(9, 8), 1, fill);
        canvas.drawCircle(const Offset(15, 8), 1, fill);
        canvas.drawArc(const Rect.fromLTWH(8, 8, 8, 7), 0, 3.14, false, stroke);
        line(const [Offset(2, 13), Offset(5, 20), Offset(9, 18)]);
        line(const [Offset(22, 13), Offset(19, 20), Offset(15, 18)]);
      case ModelBrand.unknown:
        break;
    }
  }

  @override
  bool shouldRepaint(_BrandPainter old) =>
      old.brand != brand || old.color != color;
}

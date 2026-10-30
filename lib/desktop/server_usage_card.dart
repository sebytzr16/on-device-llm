import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../features/hosting/server_usage.dart';
import 'developer_widgets.dart';

class ServerUsageCard extends StatefulWidget {
  final ServerUsage usage;
  const ServerUsageCard({super.key, required this.usage});
  @override
  State<ServerUsageCard> createState() => _ServerUsageCardState();
}

class _ServerUsageCardState extends State<ServerUsageCard> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n, u = widget.usage;
    Widget group(String label, Map<String, UsageGroup> groups) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.label),
        for (final e in groups.entries)
          Text(
            t.desktopUsageGroup(
              e.key,
              e.value.requests,
              e.value.tokens,
              e.value.lastSeen!.toLocal().toString(),
            ),
            style: context.text.small,
          ),
      ],
    );
    return DeveloperCard(
      title: t.desktopUsageTitle,
      children: [
        Text(t.desktopUsageRate, style: context.text.small),
        const SizedBox(height: 8),
        Semantics(
          label: t.desktopUsageRate,
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: CustomPaint(
              painter: _Bars(u.bars(DateTime.now()), context.colors.accent),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          t.desktopUsageTotals(
            u.requests,
            u.errors,
            u.promptTokens,
            u.completionTokens,
            u.averageTps.toStringAsFixed(1),
            (u.averageMs / 1000).toStringAsFixed(2),
          ),
          style: context.text.small,
        ),
        const SizedBox(height: 12),
        group(t.desktopUsageClients, u.clients),
        const SizedBox(height: 12),
        group(t.desktopUsageModels, u.models),
      ],
    );
  }
}

class _Bars extends CustomPainter {
  final List<int> values;
  final Color color;
  _Bars(this.values, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final max = values.fold(1, math.max);
    final width = size.width / values.length;
    final paint = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final height = size.height * values[i] / max;
      canvas.drawRect(
        Rect.fromLTWH(
          i * width,
          size.height - height,
          math.max(1, width - 2),
          height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Bars oldDelegate) => true;
}

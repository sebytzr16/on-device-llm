import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import 'device_info.dart';

/// Profile-only frame samples; the callback and file are absent by default.
class FrameTimingLog {
  static const enabled = bool.fromEnvironment('FRAME_LOG');

  final List<FrameTiming> _samples = [];
  DateTime _last = DateTime.now();
  Future<void> _pending = Future.value();
  double _hz = 0;

  Future<void> start() async {
    if (!enabled) return;
    _hz = await DeviceDisplay.refreshRate();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    _samples.addAll(timings);
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(seconds: 5)) return;
    _last = now;
    final batch = List<FrameTiming>.of(_samples);
    _samples.clear();
    _pending = _pending.then((_) => _write(batch, now));
  }

  Future<void> _write(List<FrameTiming> batch, DateTime now) async {
    if (batch.isEmpty) return;
    _hz = await DeviceDisplay.refreshRate();
    final budget = _hz > 0 ? 1000 / _hz : 0.0;
    final build =
        batch.map((f) => f.buildDuration.inMicroseconds / 1000).toList()
          ..sort();
    final raster =
        batch.map((f) => f.rasterDuration.inMicroseconds / 1000).toList()
          ..sort();
    double percentile(List<double> values, double p) =>
        values[((values.length - 1) * p).ceil()];
    final over = budget <= 0
        ? 0
        : batch
              .where(
                (f) =>
                    (f.buildDuration + f.rasterDuration).inMicroseconds / 1000 >
                    budget,
              )
              .length;
    final directory = await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}frame_timings.log',
    );
    await file.writeAsString(
      '${now.toIso8601String()} hz=${_hz.toStringAsFixed(1)} n=${batch.length} budgetMs=${budget.toStringAsFixed(2)} '
      'buildMs=${percentile(build, .5).toStringAsFixed(2)}/${percentile(build, .9).toStringAsFixed(2)}/${percentile(build, .99).toStringAsFixed(2)} '
      'rasterMs=${percentile(raster, .5).toStringAsFixed(2)}/${percentile(raster, .9).toStringAsFixed(2)}/${percentile(raster, .99).toStringAsFixed(2)} '
      'overBudget=${(100 * over / batch.length).toStringAsFixed(1)}%\n',
      mode: FileMode.append,
    );
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/device/thermal.dart';

void main() {
  test('reads readable, interesting zones and skips the rest', () async {
    final root = await Directory.systemTemp.createTemp('thermal');
    addTearDown(() => root.delete(recursive: true));
    Future<void> zone(String n, String type, String temp) async {
      final d = Directory('${root.path}/thermal_zone$n')..createSync();
      File('${d.path}/type').writeAsStringSync('$type\n');
      File('${d.path}/temp').writeAsStringSync('$temp\n');
    }

    await zone('0', 'cpu-0-0', '41200');
    await zone('1', 'gpu', '38000');
    await zone('2', 'battery', '31');
    await zone('3', 'pm8550_tz', '35000'); // uninteresting
    await zone('4', 'cpu-1-0', 'unreadable');
    await zone('5', 'skin', '999000'); // out of range
    Directory('${root.path}/thermal_zone6').createSync(); // no files
    expect(ThermalState.read(root: root.path), {
      'cpu-0-0': 41.2,
      'gpu': 38.0,
      'battery': 31.0,
    });
    expect(
      ThermalState.summary({'cpu-0-0': 41.2, 'gpu': 38.0}),
      'cpu-0-0 41.2°C · gpu 38.0°C',
    );
    expect(ThermalState.read(root: '${root.path}/nowhere'), isEmpty);
  });
}

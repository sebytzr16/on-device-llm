import 'dart:io';

/// Readable thermal zones, for benchmark records (B5). Android exposes
/// `/sys/class/thermal/thermal_zone*/{type,temp}`; which ones a normal app
/// may read varies by vendor, so unreadable zones are skipped silently and
/// the result may be empty. Temperatures are in °C.
class ThermalState {
  static const root = '/sys/class/thermal';

  /// Zone types worth recording: CPU/GPU clusters, the SoC, skin and battery.
  static final _interesting = RegExp(
    r'cpu|gpu|soc|skin|batt|tsens|mtktscpu|ap_therm|xo_therm',
    caseSensitive: false,
  );

  /// `{zoneType: °C}` for readable zones whose type looks like a CPU, GPU,
  /// SoC, skin or battery sensor. Sorted by type. Never throws.
  static Map<String, double> read({String root = root, int limit = 12}) {
    final out = <String, double>{};
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) return out;
      final zones = dir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final zone in zones) {
        if (out.length >= limit) break;
        try {
          final type = File('${zone.path}/type').readAsStringSync().trim();
          if (type.isEmpty || !_interesting.hasMatch(type)) continue;
          final raw = File('${zone.path}/temp').readAsStringSync().trim();
          final value = double.tryParse(raw);
          if (value == null) continue;
          // Millidegrees on most kernels; a few report plain degrees.
          final celsius = value.abs() >= 1000 ? value / 1000 : value;
          if (celsius < -40 || celsius > 150) continue;
          out[type] = double.parse(celsius.toStringAsFixed(1));
        } catch (_) {
          // Zone not readable by this app: skip it.
        }
      }
    } catch (_) {}
    return out;
  }

  /// One-line summary such as `cpu-0 41.2°C · gpu 38.0°C`, or `` when empty.
  static String summary(Map<String, double> zones, {int max = 4}) => zones
      .entries
      .take(max)
      .map((e) => '${e.key} ${e.value.toStringAsFixed(1)}°C')
      .join(' · ');
}

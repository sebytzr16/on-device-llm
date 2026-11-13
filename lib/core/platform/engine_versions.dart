import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Engine pins and runtime facts shown on Settings -> Hardware. Pure helpers
/// (no widgets) so they can be tested without a device.
abstract final class EnginePins {
  /// llama.cpp tag and commit pinned in native/REVISION and
  /// scripts/bootstrap.ps1. Keep in step with them (a test checks this).
  static const llamaCppTag = 'b12342';
  static const llamaCppCommit = '0fb8f157702702f33f4e018de8701b2569a1bc28';

  /// stable-diffusion.cpp commit pinned in scripts/fetch-stable-diffusion.ps1.
  static const sdCommit = '687915518efd69548965d24818f0d3bbbb903718';
}

/// "b12342" -> 12342; null when the tag is not a llama.cpp build tag.
int? llamaBuildNumber(String? tag) {
  final m = RegExp(r'^b(\d+)$').firstMatch((tag ?? '').trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

String _pretty(String key) => switch (key) {
  'cuda' => 'CUDA',
  'vulkan' => 'Vulkan',
  'opencl' => 'OpenCL',
  'metal' => 'Metal',
  'qnn' => 'QNN',
  'cpu' => 'CPU',
  _ => key.toUpperCase(),
};

String? _known(String? raw) {
  final v = (raw ?? '').toLowerCase();
  for (final k in const ['cuda', 'vulkan', 'opencl', 'metal', 'qnn']) {
    if (v.contains(k)) return k;
  }
  return null;
}

/// Backend actually in use: the loaded bridge library first, then the
/// selected backend, then the one the native probe detected.
/// [selected] is the settings name ('auto', 'cpu', 'cuda', ...).
String resolveBackendLabel({
  String? library,
  required String selected,
  Map<String, dynamic>? hardware,
  String unknown = 'Unknown',
}) {
  if (library != null && library.isNotEmpty) {
    final file = library.split(RegExp(r'[\\/]')).last;
    final k =
        _known(file) ?? (file.toLowerCase().contains('cpu') ? 'cpu' : null);
    if (k != null) return '${_pretty(k)} ($file)';
  }
  final sel = selected.toLowerCase();
  if (sel != 'auto' && sel.isNotEmpty) return _pretty(sel);
  final fromInfo = hardware?['backend'];
  if (fromInfo is String && fromInfo.isNotEmpty) {
    final k = _known(fromInfo);
    return k != null ? _pretty(k) : fromInfo;
  }
  final devices = (hardware?['devices'] as List?)?.whereType<Map>() ?? const [];
  for (final d in devices) {
    if (d['type'] == 'gpu' || d['type'] == 'igpu') {
      final raw = d['backend']?.toString() ?? '';
      final k = _known(raw);
      if (k != null) return _pretty(k);
      if (raw.isNotEmpty) return raw;
    }
  }
  if (devices.any((d) => d['type'] == 'cpu')) return 'CPU';
  return unknown;
}

/// Major version from bundled DLL names next to the executable:
/// cudart64_12.dll -> '12', cublas64_13.dll -> '13'. Null when none found.
String? cudaRuntimeFromFileNames(Iterable<String> names) {
  for (final prefix in const ['cudart64_', 'cublas64_']) {
    final re = RegExp('^$prefix(\\d+)\\.dll\$', caseSensitive: false);
    for (final n in names) {
      final m = re.firstMatch(n.split(RegExp(r'[\\/]')).last);
      if (m != null) return m.group(1);
    }
  }
  return null;
}

/// Minimum Windows driver for a CUDA runtime major version (NVIDIA CUDA
/// release notes); null for versions this table does not know.
String? minDriverForCudaMajor(String major) => switch (major) {
  '11' => '452.39',
  '12' => '527.41',
  '13' => '580.65',
  _ => null,
};

/// True when [driver] >= [required]; null when either cannot be parsed.
bool? driverSupports(String? driver, String? required) {
  if (driver == null || required == null) return null;
  List<int>? parse(String v) {
    final out = <int>[];
    for (final p in v.trim().split('.')) {
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }

  final a = parse(driver), b = parse(required);
  if (a == null || b == null) return null;
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return true;
}

/// Driver version from `nvidia-smi` output (first line), or null.
String? parseNvidiaSmiDriver(String output) {
  final line = output
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  return RegExp(r'^\d+(\.\d+)+$').hasMatch(line) ? line : null;
}

/// Runtime facts gathered once for the Hardware page. Never throws.
class EngineRuntimeInfo {
  final String? cudaRuntimeMajor;
  final String? driverVersion;
  const EngineRuntimeInfo({this.cudaRuntimeMajor, this.driverVersion});

  static Future<EngineRuntimeInfo> probe({
    Directory? exeDir,
    Future<ProcessResult> Function(String, List<String>)? run,
  }) async {
    String? cuda, driver;
    try {
      final dir = exeDir ?? File(Platform.resolvedExecutable).parent;
      final names = dir.existsSync()
          ? dir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last)
          : const <String>[];
      cuda = cudaRuntimeFromFileNames(names);
    } catch (_) {}
    try {
      final exec = run ?? ((c, a) => Process.run(c, a));
      final r = await exec('nvidia-smi', [
        '--query-gpu=driver_version',
        '--format=csv,noheader',
      ]).timeout(const Duration(seconds: 3));
      if (r.exitCode == 0) driver = parseNvidiaSmiDriver('${r.stdout}');
    } catch (_) {}
    return EngineRuntimeInfo(cudaRuntimeMajor: cuda, driverVersion: driver);
  }
}

enum EngineUpdateState { upToDate, newer, unknown, offline }

class EngineUpdateItem {
  final String name;
  final EngineUpdateState state;
  final String? latest;
  final String bundled;
  const EngineUpdateItem(this.name, this.state, this.latest, this.bundled);
}

/// One manual check against GitHub's releases API. [fetch] returns the JSON
/// body for a URL (throws when offline); a fake can be injected in tests.
class EngineUpdateChecker {
  final Future<String> Function(Uri) fetch;
  EngineUpdateChecker({Future<String> Function(Uri)? fetch})
    : fetch = fetch ?? _dioFetch;

  static Future<String> _dioFetch(Uri uri) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.plain,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'OnDeviceLLM engine-update-check',
        },
      ),
    );
    try {
      final r = await dio.getUri<String>(uri);
      return r.data ?? '';
    } finally {
      dio.close();
    }
  }

  Future<String?> _latestTag(String repo) async {
    final body = await fetch(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
    ).timeout(const Duration(seconds: 10));
    final j = jsonDecode(body);
    final tag = j is Map ? j['tag_name'] : null;
    return tag is String && tag.isNotEmpty ? tag : null;
  }

  Future<List<EngineUpdateItem>> check() async {
    final out = <EngineUpdateItem>[];
    const llamaBundled = EnginePins.llamaCppTag;
    try {
      final tag = await _latestTag('ggml-org/llama.cpp');
      final a = llamaBuildNumber(tag), b = llamaBuildNumber(llamaBundled);
      out.add(
        EngineUpdateItem(
          'llama.cpp',
          tag == null || a == null || b == null
              ? EngineUpdateState.unknown
              : (a > b ? EngineUpdateState.newer : EngineUpdateState.upToDate),
          tag,
          llamaBundled,
        ),
      );
    } catch (_) {
      out.add(
        const EngineUpdateItem(
          'llama.cpp',
          EngineUpdateState.offline,
          null,
          llamaBundled,
        ),
      );
    }
    // stable-diffusion.cpp release tags look like "master-514-6879155"; the
    // pin is a commit, so compare by its short sha.
    final sdShort = EnginePins.sdCommit.substring(0, 7);
    try {
      final tag = await _latestTag('leejet/stable-diffusion.cpp');
      out.add(
        EngineUpdateItem(
          'stable-diffusion.cpp',
          tag == null
              ? EngineUpdateState.unknown
              : (tag.contains(sdShort)
                    ? EngineUpdateState.upToDate
                    : EngineUpdateState.newer),
          tag,
          sdShort,
        ),
      );
    } catch (_) {
      out.add(
        EngineUpdateItem(
          'stable-diffusion.cpp',
          EngineUpdateState.offline,
          null,
          sdShort,
        ),
      );
    }
    return out;
  }
}

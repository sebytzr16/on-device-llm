import 'package:dio/dio.dart';

import '../../core/platform/build_identity.dart';

/// What the manual update check found. [failed] is a response the app could
/// not use; [offline] is a network it could not reach at all.
enum UpdateStatus { checking, upToDate, available, offline, failed }

/// The latest public release reduced to what Settings > About shows: the
/// version, plain-text notes and the download page.
class UpdateRelease {
  final String version;
  final String notes;
  final String pageUrl;

  const UpdateRelease({
    required this.version,
    required this.notes,
    required this.pageUrl,
  });
}

/// One outcome of a check, including the running version so the screen can
/// show it without reading the build constants again.
class UpdateCheck {
  final UpdateStatus status;
  final String currentVersion;
  final UpdateRelease? release;

  const UpdateCheck({
    required this.status,
    required this.currentVersion,
    this.release,
  });

  const UpdateCheck.checking(String currentVersion)
    : this(status: UpdateStatus.checking, currentVersion: currentVersion);
}

/// The manual "Check for updates" request (owner request, 2026-11-08).
///
/// One GET to the public GitHub Releases API, only when the user asks: there
/// is no automatic or scheduled call. It sends no account, device or usage
/// identifier, only a generic `OnDeviceLLM` User-Agent.
class UpdateChecker {
  static const endpoint =
      'https://api.github.com/repos/sebytzr16/on-device-llm/releases/latest';
  static const userAgent = 'OnDeviceLLM';
  static const _timeout = Duration(seconds: 10);

  final Dio? _dio;
  final String? _currentVersion;

  UpdateChecker({Dio? dio, String? currentVersion})
    : _dio = dio,
      _currentVersion = currentVersion;

  String get currentVersion => _currentVersion ?? BuildIdentity.version;

  /// Performs the one request. A [Dio] given to the constructor is reused and
  /// left open; the default client is closed after the call.
  Future<UpdateCheck> check({CancelToken? cancelToken}) async {
    final current = currentVersion;
    final dio =
        _dio ??
        Dio(BaseOptions(connectTimeout: _timeout, receiveTimeout: _timeout));
    try {
      final res = await dio.get<Object?>(
        endpoint,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          headers: const {
            'User-Agent': userAgent,
            'Accept': 'application/vnd.github+json',
          },
        ),
      );
      final data = res.data;
      if (data is! Map) {
        return UpdateCheck(
          status: UpdateStatus.failed,
          currentVersion: current,
        );
      }
      final tag = data['tag_name'];
      final pageUrl = data['html_url'];
      final body = data['body'];
      if (tag is! String || pageUrl is! String) {
        return UpdateCheck(
          status: UpdateStatus.failed,
          currentVersion: current,
        );
      }
      final version = normalizeVersion(tag);
      final page = Uri.tryParse(pageUrl.trim());
      if (version.isEmpty ||
          _Version.tryParse(version) == null ||
          _Version.tryParse(current) == null ||
          page == null ||
          // Only the project's own release page is ever opened.
          page.scheme != 'https' ||
          page.host != 'github.com') {
        return UpdateCheck(
          status: UpdateStatus.failed,
          currentVersion: current,
        );
      }
      final newer = compareVersions(current, version) < 0;
      if (!newer) {
        return UpdateCheck(
          status: UpdateStatus.upToDate,
          currentVersion: current,
        );
      }
      return UpdateCheck(
        status: UpdateStatus.available,
        currentVersion: current,
        release: UpdateRelease(
          version: version,
          notes: plainReleaseNotes(body is String ? body : ''),
          pageUrl: page.toString(),
        ),
      );
    } on DioException catch (e) {
      return UpdateCheck(
        status: _isOffline(e) ? UpdateStatus.offline : UpdateStatus.failed,
        currentVersion: current,
      );
    } on FormatException {
      return UpdateCheck(status: UpdateStatus.failed, currentVersion: current);
    } finally {
      if (_dio == null) dio.close();
    }
  }

  static bool _isOffline(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    _ => false,
  };

  /// GitHub tags carry a leading `v`; the running version does not.
  static String normalizeVersion(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    return text.trim();
  }

  /// Compares two versions, including the build number (`1.3.0+6`).
  /// Returns a negative number when [latest] is newer than [current], zero
  /// when they are the same, and a positive number when [latest] is older.
  static int compareVersions(String current, String latest) {
    final a = _Version.tryParse(current);
    final b = _Version.tryParse(latest);
    if (a == null || b == null) return 0;
    return a.compareTo(b);
  }

  /// Whether [latest] is a newer release than [current].
  static bool isNewer(String current, String latest) =>
      compareVersions(current, latest) < 0;

  /// Release notes are shown as plain text; Markdown and HTML image markup
  /// would otherwise appear as raw syntax.
  static String plainReleaseNotes(String body) => body
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAll(RegExp(r'!\[[^\]]*\]\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class _Version {
  final int major;
  final int minor;
  final int patch;
  final List<String> prerelease;
  final int build;

  const _Version({
    required this.major,
    required this.minor,
    required this.patch,
    required this.prerelease,
    required this.build,
  });

  static _Version? tryParse(String raw) {
    var text = UpdateChecker.normalizeVersion(raw);
    if (text.isEmpty) return null;
    String? buildText;
    final plus = text.indexOf('+');
    if (plus >= 0) {
      buildText = text.substring(plus + 1);
      text = text.substring(0, plus);
    }
    String? prereleaseText;
    final dash = text.indexOf('-');
    if (dash >= 0) {
      prereleaseText = text.substring(dash + 1);
      text = text.substring(0, dash);
    }
    final numbers = <int>[];
    for (final part in text.split('.')) {
      final match = RegExp(r'^\d+').firstMatch(part);
      if (match == null) return null;
      numbers.add(int.tryParse(match.group(0)!) ?? 0);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return _Version(
      major: numbers[0],
      minor: numbers[1],
      patch: numbers[2],
      prerelease: prereleaseText == null || prereleaseText.isEmpty
          ? const []
          : prereleaseText.split('.'),
      build: _leadingInt(buildText ?? ''),
    );
  }

  int compareTo(_Version other) {
    final core = major.compareTo(other.major);
    if (core != 0) return core;
    final feature = minor.compareTo(other.minor);
    if (feature != 0) return feature;
    final fix = patch.compareTo(other.patch);
    if (fix != 0) return fix;
    final pre = _comparePrerelease(other);
    if (pre != 0) return pre;
    return build.compareTo(other.build);
  }

  int _comparePrerelease(_Version other) {
    if (prerelease.isEmpty && other.prerelease.isEmpty) return 0;
    if (prerelease.isEmpty) return 1;
    if (other.prerelease.isEmpty) return -1;
    final length = prerelease.length < other.prerelease.length
        ? prerelease.length
        : other.prerelease.length;
    for (var i = 0; i < length; i++) {
      final a = prerelease[i];
      final b = other.prerelease[i];
      final an = int.tryParse(a);
      final bn = int.tryParse(b);
      final compared = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
          ? -1
          : bn != null
          ? 1
          : a.compareTo(b);
      if (compared != 0) return compared;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }

  static int _leadingInt(String text) {
    final match = RegExp(r'^\d+').firstMatch(text);
    return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
  }
}

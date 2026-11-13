import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/features/updates/presentation/update_check_tile.dart';
import 'package:ondevice_llm/features/updates/update_checker.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, Object?> data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

Map<String, Object?> _release({
  String tag = 'v1.4.0+8',
  String body =
      '## Changes\n\n- Faster startup\n\n'
      '![screenshot](https://example.test/a.png)\n\n'
      '<img src="https://example.test/b.png">\n',
  String url = 'https://github.com/sebytzr16/on-device-llm/releases/tag/v1.4.0',
}) => {'tag_name': tag, 'body': body, 'html_url': url};

UpdateChecker _checker(_Adapter adapter, {String current = '1.4.0+7'}) =>
    UpdateChecker(
      dio: Dio()..httpClientAdapter = adapter,
      currentVersion: current,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('version comparison', () {
    test('build numbers decide between the same release', () {
      expect(UpdateChecker.isNewer('1.3.0+6', '1.3.0+7'), isTrue);
      expect(UpdateChecker.isNewer('1.3.0+7', '1.3.0+6'), isFalse);
      expect(UpdateChecker.compareVersions('1.3.0+6', '1.3.0+6'), 0);
      expect(UpdateChecker.compareVersions('1.3.0+6', '1.3.0'), 1);
      expect(UpdateChecker.isNewer('1.3.0+6', '1.3.0'), isFalse);
    });

    test('a newer release wins over a large build number', () {
      expect(UpdateChecker.isNewer('1.3.0+99', '1.4.0+0'), isTrue);
      expect(UpdateChecker.isNewer('1.2.9', '1.3.0'), isTrue);
      expect(UpdateChecker.isNewer('1.4.0', '1.4.1'), isTrue);
    });

    test('a leading v is ignored', () {
      expect(UpdateChecker.normalizeVersion(' v1.4.0+7 '), '1.4.0+7');
      expect(UpdateChecker.compareVersions('v1.4.0+7', '1.4.0+7'), 0);
    });

    test('a prerelease sorts before the release', () {
      expect(UpdateChecker.isNewer('1.4.0', '1.4.0-beta.2'), isFalse);
      expect(UpdateChecker.isNewer('1.4.0-beta.2', '1.4.0'), isTrue);
    });
  });

  group('checking', () {
    test(
      'one GET to the public endpoint carries a generic User-Agent',
      () async {
        final adapter = _Adapter((_) => _json(_release()));
        final result = await _checker(adapter).check();

        expect(result.status, UpdateStatus.available);
        expect(adapter.requests, hasLength(1));
        final request = adapter.requests.single;
        expect(request.method, 'GET');
        expect(request.uri.toString(), UpdateChecker.endpoint);
        expect(request.headers['User-Agent'], 'OnDeviceLLM');
        final names = request.headers.keys.map((k) => k.toLowerCase());
        expect(names, isNot(contains('authorization')));
        expect(names, isNot(contains('cookie')));
      },
    );

    test('a newer tag is available with plain notes and the page', () async {
      final result = await _checker(_Adapter((_) => _json(_release()))).check();

      expect(result.status, UpdateStatus.available);
      expect(result.currentVersion, '1.4.0+7');
      expect(result.release!.version, '1.4.0+8');
      expect(result.release!.pageUrl, contains('/releases/tag/v1.4.0'));
      expect(result.release!.notes, contains('Faster startup'));
      expect(result.release!.notes, isNot(contains('![')));
      expect(result.release!.notes, isNot(contains('<img')));
    });

    test('the same or an older release is up to date', () async {
      final same = await _checker(
        _Adapter((_) => _json(_release(tag: 'v1.4.0+7'))),
      ).check();
      expect(same.status, UpdateStatus.upToDate);
      expect(same.release, isNull);

      final older = await _checker(
        _Adapter((_) => _json(_release(tag: 'v1.3.0+9'))),
      ).check();
      expect(older.status, UpdateStatus.upToDate);
    });

    test('a connection error is offline, not a crash', () async {
      final adapter = _Adapter(
        (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      final result = await _checker(adapter).check();
      expect(result.status, UpdateStatus.offline);
      expect(result.release, isNull);
    });

    test('a bad response fails cleanly', () async {
      final adapter = _Adapter(
        (_) => ResponseBody.fromString(
          'not a release',
          500,
          headers: {
            'content-type': ['text/plain'],
          },
        ),
      );
      final result = await _checker(adapter).check();
      expect(result.status, UpdateStatus.failed);
    });

    test('a release without a tag or page is refused', () async {
      final noTag = await _checker(
        _Adapter(
          (_) => _json(const {'body': 'Notes', 'html_url': 'https://x.test'}),
        ),
      ).check();
      expect(noTag.status, UpdateStatus.failed);

      final badPage = await _checker(
        _Adapter((_) => _json(_release(url: 'not a url'))),
      ).check();
      expect(badPage.status, UpdateStatus.failed);
    });

    test('Markdown images are removed from release notes', () {
      final notes = UpdateChecker.plainReleaseNotes(
        'Fixed.\n\n![shot](https://x.test/a.png)\n\n'
        '<img src="b.png">\n\nDone.',
      );
      expect(notes, contains('Fixed.'));
      expect(notes, contains('Done.'));
      expect(notes, isNot(contains('![')));
      expect(notes, isNot(contains('<img')));
    });
  });

  group('tile', () {
    testWidgets('no request until the user taps, then the states render', (
      tester,
    ) async {
      final pending = Completer<ResponseBody>();
      final adapter = _Adapter((_) => pending.future);
      final checker = _checker(adapter);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: UpdateCheckTile(checker: checker)),
        ),
      );

      expect(adapter.requests, isEmpty);
      expect(find.text('Check for updates'), findsOneWidget);

      await tester.tap(find.byKey(const Key('check-for-updates')));
      await tester.pump();
      // Dio dispatches on real async work.
      for (var i = 0; i < 50 && adapter.requests.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('Checking for updates…'), findsOneWidget);
      expect(adapter.requests, hasLength(1));
      expect(find.text('Checking for updates…'), findsOneWidget);

      pending.complete(_json(_release(tag: 'v1.4.0+8')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 1.4.0+8 is available.'), findsOneWidget);
      expect(find.textContaining('Faster startup'), findsOneWidget);
      expect(find.text('Open release page'), findsOneWidget);
    });
  });
}

import 'dart:convert';

import 'package:dio/dio.dart';

import 'search_models.dart';

/// Structured answers DuckDuckGo serves without a key, for questions where
/// reading web pages is the slow, fragile way (weather pages are scripts
/// and paywalls). Same privacy contract as search: only DuckDuckGo is
/// contacted, only when web research is on, only for the place the user
/// named — never the phone's location.
class InstantAnswers {
  final Dio _dio;
  final Duration timeout;

  InstantAnswers({Dio? dio, this.timeout = const Duration(seconds: 4)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36',
              },
            ),
          );

  static const forecastEndpoint = 'https://duckduckgo.com/js/spice/forecast';

  static final _weather = RegExp(
    r'\b(weather|forecast|temperature|temp|how (?:hot|cold|warm|chilly)|rain(?:ing|y)?|snow(?:ing)?|sunny|humid(?:ity)?|windy|météo|temps qu.il fait|quel temps)\b',
    caseSensitive: false,
  );
  static const _placeStop = {
    'today',
    'tonight',
    'tomorrow',
    'now',
    'right',
    'this',
    'the',
    'a',
    'week',
    'weekend',
    'morning',
    'afternoon',
    'evening',
    'and',
    'or',
    'like',
    'going',
    'be',
    'is',
    'it',
    'please',
    'currently',
    'later',
    'next',
    'at',
    'on',
    'for',
    'in',
    'of',
    'à',
    'aujourd',
    'demain',
    'ce',
    'cette',
  };

  /// Whether [question] is about the weather at all.
  static bool isWeather(String question) => _weather.hasMatch(question);

  /// A current forecast must not substitute for a question about units,
  /// historical observations, or a date beyond the forecast horizon.
  static bool wantsForecast(String question, {DateTime? now}) {
    if (!_weather.hasMatch(question)) return false;
    final q = question.toLowerCase();
    if (RegExp(
      r'\b(unit|units|metric|celsius|fahrenheit|define|definition|meaning|history|historical|average|climate|next month|next year|last year|last month|yesterday|unité|unidades)\b',
    ).hasMatch(q)) {
      return false;
    }
    final today = now ?? DateTime.now();
    for (final year in RegExp(r'\b(?:19|20)\d{2}\b').allMatches(q)) {
      if (int.parse(year.group(0)!) != today.year) return false;
    }
    // Explicit calendar dates need the normal research route. The instant
    // response contains current conditions and cannot verify a named date.
    if (RegExp(
      r'\b(?:\d{1,2}[/-]\d{1,2}|\d{1,2}\s+(?:january|february|march|april|may|june|july|august|september|october|november|december)|(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2})\b',
    ).hasMatch(q)) {
      return false;
    }
    return true;
  }

  /// The place a weather question names, or null when it is not a weather
  /// question or names no place (the app never guesses the user's location).
  static String? weatherPlace(String question) {
    final q = question.trim();
    if (!_weather.hasMatch(q)) return null;
    String? take(Iterable<String> words) {
      final out = <String>[];
      for (final raw in words) {
        final w = raw.replaceAll(RegExp('[?!.;:\'"’“”]+\$'), '');
        if (w.isEmpty ||
            _placeStop.contains(w.toLowerCase()) ||
            _weather.hasMatch(w)) {
          break;
        }
        out.add(w);
        if (out.length == 4) break;
      }
      return out.isEmpty ? null : out.join(' ');
    }

    // "in Toronto", "for Toronto, Ontario", "à Paris"
    final after = RegExp(
      r'\b(?:in|for|at|à|a|en)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(q);
    if (after != null) {
      final place = take(after.group(1)!.split(RegExp(r'\s+')));
      if (place != null) return _tidy(place);
    }
    // "Toronto weather", "météo Paris"
    final before = RegExp(
      r'^(?:what.s the |the |quelle est la )?(.+?)\s+(?:weather|forecast|temperature)\b',
      caseSensitive: false,
    ).firstMatch(q);
    if (before != null) {
      // The place is whatever sits right before "weather": walk back from
      // it until a stop word, then restore the order.
      final words = before.group(1)!.split(RegExp(r'\s+'));
      final tail = take(words.reversed.take(3));
      if (tail != null) {
        return _tidy(tail.split(' ').reversed.join(' '));
      }
    }
    final afterWord = RegExp(
      r'\b(?:météo|weather|forecast)\s+(?:de |d.|pour |à )?(.+)$',
      caseSensitive: false,
    ).firstMatch(q);
    if (afterWord != null) {
      final place = take(afterWord.group(1)!.split(RegExp(r'\s+')));
      if (place != null) return _tidy(place);
    }
    return null;
  }

  static String _tidy(String place) => place
      .split(RegExp(r'\s+'))
      .map(
        (w) => w.length > 1 && w == w.toLowerCase()
            ? '${w[0].toUpperCase()}${w.substring(1)}'
            : w,
      )
      .join(' ')
      .replaceAll(RegExp(r',\s*$'), '');

  /// Current conditions and the forecast for [place] as one evidence
  /// source, or null when DuckDuckGo has nothing for it.
  Future<SearchResult?> weather(
    String place, {
    String language = 'en',
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio
          .get<String>(
            '$forecastEndpoint/${Uri.encodeComponent(place)}/$language',
            cancelToken: cancelToken,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(timeout);
      final text = parseForecast(res.data ?? '', requested: place);
      if (text == null) return null;
      return SearchResult(
        title: 'Weather for $place (DuckDuckGo, Apple WeatherKit data)',
        url:
            'https://duckduckgo.com/?q=${Uri.encodeQueryComponent('weather $place')}',
        snippet: text.split('\n').first,
        source: 'duckduckgo.com',
        rank: 1,
        pageText: text,
        finalUrl:
            'https://duckduckgo.com/?q=${Uri.encodeQueryComponent('weather $place')}',
        fetchedAt: DateTime.now(),
        publishedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// The JSONP forecast as readable lines a model can quote: now, today,
  /// then the next days. Rejects a reply for a different place (the
  /// endpoint falls back to a default city for unknown names).
  static String? parseForecast(String body, {required String requested}) {
    final open = body.indexOf('(');
    final close = body.lastIndexOf(')');
    if (open < 0 || close <= open) return null;
    final Map<String, dynamic> j;
    try {
      final v = jsonDecode(body.substring(open + 1, close));
      if (v is! Map) return null;
      j = Map<String, dynamic>.from(v);
    } catch (_) {
      return null;
    }
    final location = '${j['location'] ?? ''}';
    final head = requested.split(RegExp(r'[,\s]+')).first.toLowerCase();
    if (location.isEmpty || !location.toLowerCase().contains(head)) {
      return null;
    }
    final now = j['currentWeather'];
    final days = (j['forecastDaily'] as Map?)?['days'];
    if (now is! Map) return null;
    String c(Object? v) =>
        v is num ? '${v.round()} °C (${(v * 9 / 5 + 32).round()} °F)' : '?';
    String pct(Object? v) => v is num ? '${(v * 100).round()}%' : '?';
    String kmh(Object? v) => v is num ? '${v.round()} km/h' : '?';
    String cond(Object? v) => '$v'
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .toLowerCase();
    final asOf = DateTime.tryParse('${now['asOf'] ?? ''}')?.toUtc();
    // Each day starts at the place's midnight, given in UTC: Paris's
    // October 8 starts at 2026-10-07T22:00Z. Its UTC date was printed, so
    // every Paris day was labelled a day early and "Today" was yesterday
    // (phone, 2026-10-08). The offset is read from that midnight.
    final starts = [
      if (days is List)
        for (final d in days)
          if (d is Map) DateTime.tryParse('${d['forecastStart'] ?? ''}'),
    ];
    final firstStart = starts.whereType<DateTime>().firstOrNull?.toUtc();
    Duration? offset;
    if (firstStart != null) {
      var minutes = -(firstStart.hour * 60 + firstStart.minute);
      if (minutes < -12 * 60) minutes += 24 * 60;
      offset = Duration(minutes: minutes);
    }
    DateTime local(DateTime t) => t.toUtc().add(offset ?? Duration.zero);
    String day(DateTime t) => local(t).toIso8601String().substring(0, 10);
    String hm(DateTime t) => local(t).toIso8601String().substring(11, 16);
    final b = StringBuffer();
    b.writeln(
      'Current weather in $location${asOf == null
          ? ''
          : offset == null
          ? ' as of ${asOf.toIso8601String().substring(0, 16)} UTC'
          : ' as of ${hm(asOf)} local time on ${day(asOf)}'}: '
      '${cond(now['conditionCode'])}, ${c(now['temperature'])}, feels like ${c(now['temperatureApparent'])}, '
      'humidity ${pct(now['humidity'])}, wind ${kmh(now['windSpeed'])} with gusts to ${kmh(now['windGust'])}'
      '${now['uvIndex'] is num ? ', UV index ${now['uvIndex']}' : ''}.',
    );
    if (days is List) {
      final today = asOf == null || offset == null
          ? null
          : DateTime.utc(local(asOf).year, local(asOf).month, local(asOf).day);
      var i = 0;
      for (final d in days) {
        if (d is! Map || i == 4) continue;
        final start = DateTime.tryParse('${d['forecastStart'] ?? ''}');
        final date = start == null
            ? null
            : DateTime.utc(
                local(start).year,
                local(start).month,
                local(start).day,
              );
        final ahead = today == null || date == null
            ? i
            : date.difference(today).inHours ~/ 24;
        // A day already over at the place is not "today".
        if (ahead < 0) continue;
        final label = ahead == 0
            ? 'Today'
            : ahead == 1
            ? 'Tomorrow'
            : date == null
            ? 'Day ${ahead + 1}'
            : const [
                'Monday',
                'Tuesday',
                'Wednesday',
                'Thursday',
                'Friday',
                'Saturday',
                'Sunday',
              ][date.weekday - 1];
        b.writeln(
          '$label${start == null ? '' : ' (${day(start)})'}: '
          '${cond(d['conditionCode'])}, high ${c(d['temperatureMax'])}, low ${c(d['temperatureMin'])}, '
          'chance of precipitation ${pct(d['precipitationChance'])}'
          '${d['precipitationAmount'] is num && (d['precipitationAmount'] as num) > 0 ? ' (${(d['precipitationAmount'] as num).toStringAsFixed(1)} mm)' : ''}'
          '${d['snowfallAmount'] is num && (d['snowfallAmount'] as num) > 0 ? ', snow ${(d['snowfallAmount'] as num).toStringAsFixed(1)} cm' : ''}'
          '${offset != null && DateTime.tryParse('${d['sunrise']}') != null && DateTime.tryParse('${d['sunset']}') != null ? ', sunrise ${hm(DateTime.parse('${d['sunrise']}'))} sunset ${hm(DateTime.parse('${d['sunset']}'))} local time' : ''}.',
        );
        i++;
      }
    }
    final alerts = (j['weatherAlerts'] as Map?)?['alerts'];
    if (alerts is List && alerts.isNotEmpty) {
      b.writeln(
        'Weather alerts: ${alerts.map((a) => a is Map ? (a['description'] ?? a['summary'] ?? a['name'] ?? '') : '').where((s) => '$s'.isNotEmpty).join('; ')}.',
      );
    }
    b.write('Source: DuckDuckGo weather, data by Apple WeatherKit.');
    return b.toString();
  }

  void dispose() => _dio.close(force: true);
}

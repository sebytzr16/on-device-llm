import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/web_search/instant_answers.dart';

class _Adapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  RequestOptions? last;
  _Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final body = File('test/fixtures/ddg_forecast_toronto.js').readAsStringSync();

  test('weather questions name their place; others do not', () {
    expect(
      InstantAnswers.weatherPlace(
        "Can you please tell me what's the weather like today in Toronto?",
      ),
      'Toronto',
    );
    expect(
      InstantAnswers.weatherPlace('weather in new york city'),
      'New York City',
    );
    expect(InstantAnswers.weatherPlace('Toronto weather'), 'Toronto');
    expect(
      InstantAnswers.weatherPlace(
        'Is it going to rain tomorrow in Paris, France?',
      ),
      'Paris, France',
    );
    expect(InstantAnswers.weatherPlace('météo à Lyon'), 'Lyon');
    expect(
      InstantAnswers.weatherPlace('How hot is it in Phoenix right now'),
      'Phoenix',
    );
    // No place: the app never guesses where the phone is.
    expect(InstantAnswers.weatherPlace("What's the weather today?"), isNull);
    // Not weather at all.
    expect(
      InstantAnswers.weatherPlace('What is the capital of Canada?'),
      isNull,
    );
    expect(InstantAnswers.weatherPlace('Write a poem about rain'), isNotNull);
  });

  test('days are labelled by the date at the place, not in UTC', () {
    // Paris (UTC+2), 07:23 local on October 8: its days start at 22:00 UTC
    // the evening before (phone, 2026-10-08: "Today (2026-10-07)").
    String dayJson(String start, String code, num max) =>
        '{"forecastStart": "$start", "conditionCode": "$code", "temperatureMax": $max, "temperatureMin": 9, "precipitationChance": 0.6}';
    final paris =
        'cb({"location": "Paris, France", "timezone": "Europe/Paris", '
        '"currentWeather": {"asOf": "2026-10-08T05:23:00Z", "conditionCode": "MostlyClear", "temperature": 12, "temperatureApparent": 6, "humidity": 0.79, "windSpeed": 19, "windGust": 39, "uvIndex": 0}, '
        '"forecastDaily": {"days": ['
        '${dayJson('2026-10-06T22:00:00Z', 'Rain', 15)}, '
        '${dayJson('2026-10-07T22:00:00Z', 'Drizzle', 17)}, '
        '${dayJson('2026-10-08T22:00:00Z', 'Cloudy', 18)}, '
        '${dayJson('2026-10-09T22:00:00Z', 'Clear', 19)}]}})';
    final text = InstantAnswers.parseForecast(paris, requested: 'Paris')!;
    expect(text, contains('as of 07:23 local time on 2026-10-08:'));
    // No UTC clock times: "sunrise 11:23 … UTC" was read as the current
    // time in Toronto (Conversation, 2026-10-08).
    expect(text, isNot(contains('UTC')));
    expect(text, contains('Today (2026-10-08): drizzle, high 17 °C'));
    expect(text, contains('Tomorrow (2026-10-09): cloudy, high 18 °C'));
    expect(text, contains('Saturday (2026-10-10): clear'));
    // October 7 is over in Paris: not listed.
    expect(text, isNot(contains('2026-10-07')));
    expect(text, isNot(contains('rain')));
  });

  test('the forecast JSONP becomes quotable lines', () {
    final text = InstantAnswers.parseForecast(body, requested: 'Toronto')!;
    expect(text, startsWith('Current weather in Toronto, Canada'));
    expect(text, contains('cloudy, 21 °C (69 °F), feels like 19 °C'));
    expect(text, contains('humidity 52%'));
    expect(text, contains('Today (2026-09-20): mostly cloudy, high 22 °C'));
    expect(text, contains('Tomorrow'));
    expect(text, contains('Apple WeatherKit'));
    expect(text, isNot(contains('UTC')));
    expect(text, isNot(contains('sunrise ?')));
    // A reply for another place is rejected (the endpoint has a fallback city).
    expect(
      InstantAnswers.parseForecast(body, requested: 'Nowhereville'),
      isNull,
    );
    expect(
      InstantAnswers.parseForecast('garbage', requested: 'Toronto'),
      isNull,
    );
  });

  test(
    'weather() calls DuckDuckGo only and returns one evidence source',
    () async {
      final adapter = _Adapter((_) => ResponseBody.fromString(body, 200));
      final answers = InstantAnswers(dio: Dio()..httpClientAdapter = adapter);
      final result = await answers.weather('Toronto');
      expect(
        adapter.last!.uri.toString(),
        'https://duckduckgo.com/js/spice/forecast/Toronto/en',
      );
      expect(result!.source, 'duckduckgo.com');
      expect(result.pageText, contains('Current weather in Toronto'));
      expect(result.rank, 1);
      final failing = InstantAnswers(
        dio: Dio()
          ..httpClientAdapter = _Adapter(
            (_) => throw DioException(requestOptions: RequestOptions()),
          ),
      );
      expect(await failing.weather('Toronto'), isNull);
    },
  );
}

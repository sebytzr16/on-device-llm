import 'device_model_server.dart';

class UsageGroup {
  final int requests, tokens;
  final DateTime? lastSeen;
  const UsageGroup({this.requests = 0, this.tokens = 0, this.lastSeen});
  UsageGroup add(ServedRequest r) => UsageGroup(
    requests: requests + 1,
    tokens: tokens + r.promptTokens + r.completionTokens,
    lastSeen: lastSeen == null || r.at.isAfter(lastSeen!) ? r.at : lastSeen,
  );
}

/// Session totals are independent of the bounded request log.
class ServerUsage {
  final int requests, errors, promptTokens, completionTokens, answers;
  final double answerMs, rateSum;
  final int rates;
  final Map<String, UsageGroup> clients, models;
  final Map<int, int> minutes;
  const ServerUsage({
    this.requests = 0,
    this.errors = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.answers = 0,
    this.answerMs = 0,
    this.rateSum = 0,
    this.rates = 0,
    this.clients = const {},
    this.models = const {},
    this.minutes = const {},
  });
  double get averageTps => rates == 0 ? 0 : rateSum / rates;
  double get averageMs => answers == 0 ? 0 : answerMs / answers;
  List<int> bars(DateTime now) {
    final minute = now.millisecondsSinceEpoch ~/ 60000;
    return [for (var i = minute - 29; i <= minute; i++) minutes[i] ?? 0];
  }

  ServerUsage record(ServedRequest r) {
    final minute = r.at.millisecondsSinceEpoch ~/ 60000;
    final newest = minutes.keys.fold(minute, (a, b) => a > b ? a : b);
    final answer = r.ok && r.completion;
    final rate = answer && r.tokensPerSecond > 0;
    return ServerUsage(
      requests: requests + 1,
      errors: errors + (r.ok ? 0 : 1),
      promptTokens: promptTokens + r.promptTokens,
      completionTokens: completionTokens + r.completionTokens,
      answers: answers + (answer ? 1 : 0),
      answerMs: answerMs + (answer ? r.took.inMicroseconds / 1000 : 0),
      rates: rates + (rate ? 1 : 0),
      rateSum: rateSum + (rate ? r.tokensPerSecond : 0),
      clients: Map.unmodifiable({
        ...clients,
        r.client: (clients[r.client] ?? const UsageGroup()).add(r),
      }),
      models: Map.unmodifiable({
        ...models,
        if (r.modelId.isNotEmpty)
          r.modelId: (models[r.modelId] ?? const UsageGroup()).add(r),
      }),
      minutes: Map.unmodifiable({
        for (final e in minutes.entries)
          if (e.key > newest - 30) e.key: e.value,
        if (minute > newest - 30) minute: (minutes[minute] ?? 0) + 1,
      }),
    );
  }
}

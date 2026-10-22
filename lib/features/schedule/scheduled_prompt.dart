import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// A prompt offered once a day at a set time: a notification the user taps
/// to ask it (a chat) or review a goal. A watched goal's alarm also runs a
/// bounded background fetch/diff, and alerts only on meaningful changes.
class ScheduledPrompt {
  final int id;
  final String title;
  final String prompt;

  /// 'chat' asks the prompt in a new chat; 'goal' opens Goals with it.
  final String kind;
  final int hour, minute;
  final bool enabled;
  const ScheduledPrompt({
    required this.id,
    required this.prompt,
    required this.hour,
    required this.minute,
    this.title = '',
    this.kind = 'chat',
    this.enabled = true,
  });

  bool get isGoal => kind == 'goal';

  String get time =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ScheduledPrompt copyWith({
    String? title,
    String? prompt,
    String? kind,
    int? hour,
    int? minute,
    bool? enabled,
  }) => ScheduledPrompt(
    id: id,
    title: title ?? this.title,
    prompt: prompt ?? this.prompt,
    kind: kind ?? this.kind,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'prompt': prompt,
    'kind': kind,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
  };

  static ScheduledPrompt? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], prompt = raw['prompt'];
    final hour = raw['hour'], minute = raw['minute'];
    if (id is! int || prompt is! String || prompt.trim().isEmpty) return null;
    if (hour is! int || hour < 0 || hour > 23) return null;
    if (minute is! int || minute < 0 || minute > 59) return null;
    return ScheduledPrompt(
      id: id,
      prompt: prompt,
      hour: hour,
      minute: minute,
      title: raw['title'] is String ? raw['title'] as String : '',
      kind: raw['kind'] == 'goal' ? 'goal' : 'chat',
      enabled: raw['enabled'] != false,
    );
  }

  static List<ScheduledPrompt> decodeList(String json) {
    final raw = jsonDecode(json);
    if (raw is! List) throw const FormatException('Expected a schedule list.');
    return [
      for (final entry in raw)
        fromJson(entry) ??
            (throw const FormatException('Invalid scheduled prompt.')),
    ];
  }

  /// The next time this fires after [now] (today if still ahead, else
  /// tomorrow), for "next at" labels.
  DateTime nextAfter(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// A fresh id that no item in [items] uses (alarm and notification ids).
  static int freshId(List<ScheduledPrompt> items) {
    var id = 1;
    while (items.any((p) => p.id == id)) {
      id++;
    }
    return id;
  }
}

/// The platform side (ScheduledPrompts.kt): it owns the list so the daily
/// alarms can be set again after a reboot.
class ScheduleStore {
  static const _channel = MethodChannel('ondevice_llm/schedule');

  static Future<List<ScheduledPrompt>> list() async {
    if (!Platform.isAndroid) return const [];
    return ScheduledPrompt.decodeList(
      await _channel.invokeMethod<String>('list') ?? '[]',
    );
  }

  static Future<void> save(List<ScheduledPrompt> items) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>(
      'save',
      jsonEncode([for (final p in items) p.toJson()]),
    );
  }

  /// Asks for notification permission where Android requires it; true when
  /// notifications can already be shown.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true;
    }
  }
}

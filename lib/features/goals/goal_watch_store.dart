import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/device_encryption.dart';
import 'goal_watch.dart';

/// Native compare-and-set still owns concurrency between foreground/headless.
abstract final class GoalWatchStore {
  static const key = 'goal_watches_v1';
  static const channel = MethodChannel('ondevice_llm/schedule');

  static Future<List<GoalWatch>> decode(String raw) async => GoalWatches.decode(
    jsonEncode(await DeviceEncryption.instance.decodeWatches(raw)),
  );

  static Future<List<GoalWatch>> list() async {
    if (Platform.isAndroid) {
      return decode(await channel.invokeMethod<String>('watchList') ?? '[]');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return GoalWatches.decode(
      await DeviceEncryption.instance.readGoal(key, allowUnavailable: false) ??
          '[]',
    );
  }

  static Future<bool> put(GoalWatch watch, {GoalWatch? expected}) async {
    final value = jsonEncode(watch.toJson());
    final old = expected == null ? null : jsonEncode(expected.toJson());
    if (Platform.isAndroid) {
      final raw = await channel.invokeMethod<String>('watchList') ?? '[]';
      final current = await decode(raw);
      final found = current.where((w) => w.id == watch.id).firstOrNull;
      if (old != null && (found == null || jsonEncode(found.toJson()) != old)) {
        return false;
      }
      final source = (jsonDecode(raw) as List)
          .cast<Map>()
          .where((row) => row['id'] == watch.id)
          .firstOrNull;
      final encoded = await DeviceEncryption.instance.encodeText(value);
      final row = encoded == value
          ? watch.toJson()
          : {'id': watch.id, 'encrypted': encoded};
      return await channel.invokeMethod<bool>('watchPut', {
            'id': watch.id,
            'value': jsonEncode(row),
            if (old != null && source != null) 'expected': jsonEncode(source),
          }) ??
          false;
    }
    final current = await list();
    final found = current.where((w) => w.id == watch.id).firstOrNull;
    if (old != null && (found == null || jsonEncode(found.toJson()) != old)) {
      return false;
    }
    return DeviceEncryption.instance.writeGoal(
      key,
      GoalWatches.encode([watch, ...current.where((w) => w.id != watch.id)]),
    );
  }

  static Future<void> remove(int id) async {
    if (Platform.isAndroid) {
      await list(); // Authenticate before removing an unavailable watch.
      await channel.invokeMethod<void>('watchRemove', id);
      return;
    }
    final current = await list();
    await DeviceEncryption.instance.writeGoal(
      key,
      GoalWatches.encode(current.where((w) => w.id != id).toList()),
    );
  }

  static Future<void> enqueue() async {
    if (Platform.isAndroid) await channel.invokeMethod<void>('watchEnqueue');
  }
}

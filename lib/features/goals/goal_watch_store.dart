import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'goal_watch.dart';

/// Atomic per-watch writes let a headless check and the foreground app
/// share results without restoring a removed watch or losing a newer edit.
abstract final class GoalWatchStore {
  static const key = 'goal_watches_v1';
  static const channel = MethodChannel('ondevice_llm/schedule');

  static Future<List<GoalWatch>> list() async {
    if (Platform.isAndroid) {
      return GoalWatches.decode(
        await channel.invokeMethod<String>('watchList') ?? '[]',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return GoalWatches.decode(prefs.getString(key) ?? '[]');
  }

  static Future<bool> put(GoalWatch watch, {GoalWatch? expected}) async {
    final value = jsonEncode(watch.toJson());
    final old = expected == null ? null : jsonEncode(expected.toJson());
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('watchPut', {
            'id': watch.id,
            'value': value,
            'expected': ?old,
          }) ??
          false;
    }
    final current = await list();
    final found = current.where((w) => w.id == watch.id).firstOrNull;
    if (old != null && (found == null || jsonEncode(found.toJson()) != old)) {
      return false;
    }
    return (await SharedPreferences.getInstance()).setString(
      key,
      GoalWatches.encode([watch, ...current.where((w) => w.id != watch.id)]),
    );
  }

  static Future<void> remove(int id) async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('watchRemove', id);
      return;
    }
    final current = await list();
    await (await SharedPreferences.getInstance()).setString(
      key,
      GoalWatches.encode(current.where((w) => w.id != id).toList()),
    );
  }

  static Future<void> enqueue() async {
    if (Platform.isAndroid) {
      await channel.invokeMethod<void>('watchEnqueue');
    }
  }
}

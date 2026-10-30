import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_tuner.dart';

String benchmarkOutputHash(String output) =>
    sha256.convert(utf8.encode(output)).toString();

class BenchmarkReceipt {
  final Map<String, dynamic> json;
  const BenchmarkReceipt(this.json);

  static Map<String, dynamic> statistics(List<Map<String, dynamic>> rounds) {
    double mid(String key) =>
        tuneMedian(rounds.map((r) => (r[key] as num?)?.toDouble() ?? 0));
    final rates =
        rounds
            .map((r) => (r['tokensPerSecond'] as num?)?.toDouble() ?? 0)
            .toList()
          ..sort();
    return {
      'medianTokensPerSecond': mid('tokensPerSecond'),
      'spreadTokensPerSecond': rates.isEmpty ? 0 : rates.last - rates.first,
      'medianTtftMs': mid('firstTokenMs'),
      'medianPromptTokensPerSecond': mid('promptTokensPerSecond'),
      'medianDraftAcceptance': rounds.any((r) => r['draftAcceptance'] != null)
          ? mid('draftAcceptance')
          : null,
      'rounds': rounds,
    };
  }
}

class BenchmarkReceipts extends Notifier<List<BenchmarkReceipt>> {
  static const storageKey = 'desktop_tune_receipts_v1';
  late Future<void> ready;
  Future<void> _writes = Future.value();
  bool _alive = true;

  @override
  List<BenchmarkReceipt> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      try {
        final values = jsonDecode(prefs.getString(storageKey) ?? '[]') as List;
        if (_alive) {
          state = [
            for (final v in values)
              BenchmarkReceipt(Map<String, dynamic>.from(v as Map)),
          ];
        }
      } catch (_) {
        // An unreadable receipt history must not prevent measuring again.
      }
    });
    return const [];
  }

  Future<void> save(BenchmarkReceipt receipt) async {
    await ready;
    if (!_alive) return;
    state = List.unmodifiable([...state, receipt]);
    final encoded = jsonEncode(state.map((r) => r.json).toList());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final saved = await (await SharedPreferences.getInstance()).setString(
        storageKey,
        encoded,
      );
      if (!saved) throw StateError('receipt persistence');
    });
    await _writes;
  }
}

final benchmarkReceiptsProvider =
    NotifierProvider<BenchmarkReceipts, List<BenchmarkReceipt>>(
      BenchmarkReceipts.new,
    );

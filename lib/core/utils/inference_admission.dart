import 'dart:async';

/// Shared admission for deferred native work in the app isolate. Reply,
/// recognition and speech may overlap; indexing waits until all release
/// ownership. Already running FFI keeps its owner until it returns.
class InferenceAdmission {
  static final shared = InferenceAdmission();
  final _owners = <Object>{};
  Completer<void>? _quiet;
  bool get interactive => _owners.isNotEmpty;

  void Function() hold() {
    final owner = Object();
    _owners.add(owner);
    return () {
      if (!_owners.remove(owner)) return;
      if (_owners.isEmpty) {
        _quiet?.complete();
        _quiet = null;
      }
    };
  }

  Future<void> background({required bool Function() cancelled}) async {
    while (interactive) {
      if (cancelled()) throw StateError('Deferred work cancelled');
      _quiet ??= Completer<void>();
      // Cancellation must work even when speech never becomes quiet.
      await Future.any([
        _quiet!.future,
        Future<void>.delayed(const Duration(milliseconds: 100)),
      ]);
    }
    if (cancelled()) throw StateError('Deferred work cancelled');
  }
}

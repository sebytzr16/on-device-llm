import 'package:logging/logging.dart';

final _log = Logger('Quiet');

/// Records a failure that is deliberately tolerated (C1, audit 2026-11-11):
/// fine level only, so field failures are diagnosable with developer logs on
/// without adding noise or user-visible errors.
void quietFailure(String where, Object error, [StackTrace? stack]) =>
    _log.fine('$where: ${error.runtimeType}: $error', null, stack);

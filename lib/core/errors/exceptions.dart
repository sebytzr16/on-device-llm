sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class ModelLoadException extends AppException {
  const ModelLoadException(super.message);
}

/// The model does not fit in the memory free right now, even with a small
/// context. [message] is localized and shown as is.
class NotEnoughMemoryException extends AppException {
  const NotEnoughMemoryException(super.message);

  @override
  String toString() => message;
}

class InferenceException extends AppException {
  const InferenceException(super.message);
}

/// HTTP 429 from the search provider; [retryAfter] honours Retry-After.
class SearchRateLimitException extends AppException {
  final Duration? retryAfter;
  const SearchRateLimitException(super.message, {this.retryAfter});
}

/// The provider answered with a bot check instead of results (HTTP 202/403
/// or the anomaly page). Not an empty result set.
class SearchChallengeException extends AppException {
  const SearchChallengeException(super.message);
}

/// A 2xx page that contains neither results nor the provider's own
/// "no results" marker: the markup changed, the parser needs updating.
class SearchMarkupException extends AppException {
  const SearchMarkupException(super.message);
}

/// Search is paused after a challenge so the app does not hammer the
/// provider; [until] is when it will try again.
class SearchCooldownException extends AppException {
  final DateTime until;
  const SearchCooldownException(super.message, this.until);
}

class SearchHttpException extends AppException {
  const SearchHttpException(super.message);
}

class DownloadException extends AppException {
  const DownloadException(super.message);
}

class ChecksumMismatchException extends AppException {
  const ChecksumMismatchException(super.message);
}

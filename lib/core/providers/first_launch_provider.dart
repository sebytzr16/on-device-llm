import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingDone = 'onboarding_done_v1';

/// True until the user finishes or skips onboarding. Persisted locally.
class OnboardingNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDone) ?? false;
  }

  /// Completes onboarding with explicit finishing state and checked persistence.
  /// Returns true if persisted successfully, false if the write failed.
  /// The caller should offer retry or continue-for-this-session on false.
  ///
  /// The app root watches this provider and replaces the onboarding screen the
  /// moment it turns true, so it is only published after the write succeeded:
  /// a transient true would unmount the screen before it can offer Retry
  /// (audit 08d-1).
  Future<bool> complete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setBool(_kOnboardingDone, true);
      if (!ok) return false;
      state = const AsyncData(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Continue for this session": finishes onboarding for this run only, when
  /// the write keeps failing. Nothing is persisted, so the next start asks
  /// again (audit 08d-1).
  void completeForSession() => state = const AsyncData(true);
}

final onboardingDoneProvider = AsyncNotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

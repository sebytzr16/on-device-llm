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
  Future<bool> complete() async {
    state = const AsyncData(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setBool(_kOnboardingDone, true);
      if (!ok) {
        state = const AsyncData(false);
        return false;
      }
      return true;
    } catch (_) {
      state = const AsyncData(false);
      return false;
    }
  }
}

final onboardingDoneProvider = AsyncNotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

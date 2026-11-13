import 'package:flutter/material.dart';
import 'features/settings/presentation/widgets/device_encryption_setting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/island/status_island.dart';
import 'core/motion/motion.dart';
import 'core/providers/first_launch_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/l10n/l10n.dart';
import 'core/design/text_scaler.dart';
import 'features/settings/domain/entities/inference_settings.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/chat/presentation/screens/chat_screen.dart';
import 'features/models/presentation/screens/models_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/voice/voice_models_provider.dart';

/// Named routes. Chat is the home screen; the rest are pushed on top of it.
abstract final class AppRoutes {
  static const chat = '/';
  static const models = '/models';
  static const settings = '/settings';
}

/// Leaving a page must never bring the keyboard back on its own. Flutter
/// hands focus back to whatever text field the page below remembered (the
/// chat composer, a settings field), and on Android that reopens the IME.
/// A dialog, sheet or menu returns to the field only when the keyboard was
/// up as it opened: closing the sources or a message's details after
/// reading opened the keyboard (owner's phone, 2026-11-01).
class KeyboardGuard extends NavigatorObserver {
  final _typing = Expando<bool>();

  static bool get _keyboardUp => WidgetsBinding
      .instance
      .platformDispatcher
      .views
      .any((view) => view.viewInsets.bottom > 0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _typing[route] = _keyboardUp;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute && _typing[route] == true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    });
  }
}

class OnDeviceLlmApp extends ConsumerWidget {
  const OnDeviceLlmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(onboardingDoneProvider);
    // Started with the app so an interrupted voice download resumes; listen
    // (not watch) so download progress does not rebuild the app.
    ref.listen(voiceModelsProvider, (_, _) {});
    final localeCode = ref.watch(settingsProvider.select((s) => s.localeCode));
    appLanguageCode = localeCode;
    final themeChoice = ref.watch(
      settingsProvider.select((s) => s.themeChoice),
    );
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    final textScale = ref.watch(settingsProvider.select((s) => s.textScale));
    final motion = ref.watch(settingsProvider.select((s) => s.motion));
    AppHaptics.enabled = motion != MotionChoice.off;
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final dark = switch (themeChoice) {
      ThemeChoice.dark => true,
      ThemeChoice.light => false,
      ThemeChoice.system => platformDark,
    };
    SystemChrome.setSystemUIOverlayStyle(
      AppTheme.overlayFor(AppTheme.palette(accent, dark: dark)),
    );
    return MaterialApp(
      title: 'OnDevice LLM',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeCode.isEmpty ? null : Locale(localeCode),
      theme: AppTheme.of(accent, dark: false),
      darkTheme: AppTheme.of(accent, dark: true),
      themeMode: switch (themeChoice) {
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.system => ThemeMode.system,
      },
      // The app's text size multiplies the platform's accessibility scaler,
      // preserving nonlinear scaling behavior at different font sizes.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: ComposedTextScaler(
            MediaQuery.of(context).textScaler,
            textScale,
          ),
        ),
        // The status island floats above every page, sheet and dialog.
        child: MotionScope(
          choice: motion,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const StatusIsland(),
              const EncryptionRecoveryNotice(),
            ],
          ),
        ),
      ),
      navigatorObservers: [KeyboardGuard()],
      routes: {
        AppRoutes.models: (_) => const ModelsScreen(),
        AppRoutes.settings: (_) => const SettingsScreen(),
      },
      home: onboarded.when(
        loading: () => const Scaffold(body: SizedBox.shrink()),
        error: (_, _) => const ChatScreen(),
        data: (done) => done ? const ChatScreen() : const OnboardingScreen(),
      ),
    );
  }
}

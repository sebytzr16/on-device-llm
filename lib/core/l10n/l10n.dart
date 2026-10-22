import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

export '../../l10n/app_localizations.dart';
export '../../l10n/app_localizations_en.dart' show AppLocalizationsEn;

/// `context.l10n` everywhere; falls back to English when a widget is built
/// outside a localised app (widget tests, previews).
extension L10nContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}

/// Locales offered in Settings (FX-15); '' follows the phone.
const supportedLanguageCodes = ['', 'en', 'fr', 'es'];

/// Strings for code that runs without a [BuildContext] (chat notices,
/// errors): [code] is the Settings language, '' follows the phone, and an
/// unsupported language falls back to English.
AppLocalizations stringsFor(String code) {
  final lang = code.isNotEmpty
      ? code
      : PlatformDispatcher.instance.locale.languageCode;
  return supportedLanguageCodes.contains(lang) && lang.isNotEmpty
      ? lookupAppLocalizations(Locale(lang))
      : AppLocalizationsEn();
}

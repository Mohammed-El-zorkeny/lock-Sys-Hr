import 'package:flutter/material.dart';

import 'app_locales.dart';

/// Lightweight localization layer.
/// Holds translated strings per locale. Keys grow as features are added.
/// Can be migrated to Flutter `gen-l10n` later (arb files live in `l10n/`).
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const Map<String, Map<String, String>> _values = {
    'en': {'appName': 'LockSys HR'},
    'ar': {'appName': 'لوكسيس HR'},
  };

  String tr(String key) {
    final lang = locale.languageCode;
    return _values[lang]?[key] ?? _values['en']?[key] ?? key;
  }

  String get appName => tr('appName');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocales.supported.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

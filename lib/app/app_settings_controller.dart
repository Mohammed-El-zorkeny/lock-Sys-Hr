import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/app_locales.dart';

/// App-level settings controller (locale + theme mode + font size scaling).
/// Features persistence using [SharedPreferences].
class AppSettingsController extends ChangeNotifier {
  static final AppSettingsController instance = AppSettingsController._();

  AppSettingsController._() {
    _loadFromPrefs();
  }

  Locale _locale = AppLocales.arabic;
  ThemeMode _themeMode = ThemeMode.light;
  double _fontSizeScale = 1.0;

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  double get fontSizeScale => _fontSizeScale;
  bool get isArabic => AppLocales.isArabic(_locale);

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _fontSizeScale = prefs.getDouble('font_size_scale') ?? 1.0;
      final localeCode = prefs.getString('locale_code');
      if (localeCode != null) {
        _locale = Locale(localeCode);
      }
      final themeIndex = prefs.getInt('theme_mode');
      if (themeIndex != null) {
        _themeMode = ThemeMode.values[themeIndex];
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings from prefs: $e');
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale_code', locale.languageCode);
  }

  Future<void> toggleLanguage() async {
    await setLocale(isArabic ? AppLocales.english : AppLocales.arabic);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setFontSizeScale(double scale) async {
    if (_fontSizeScale == scale) return;
    _fontSizeScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_size_scale', scale);
  }
}


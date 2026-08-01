import 'package:flutter/material.dart';

/// Supported locales for the app. Arabic (RTL) and English (LTR).
class AppLocales {
  AppLocales._();

  static const Locale arabic = Locale('ar');
  static const Locale english = Locale('en');

  static const List<Locale> supported = [english, arabic];

  static const Locale fallback = english;

  static bool isArabic(Locale locale) => locale.languageCode == 'ar';

  static TextDirection directionOf(Locale locale) =>
      isArabic(locale) ? TextDirection.rtl : TextDirection.ltr;
}

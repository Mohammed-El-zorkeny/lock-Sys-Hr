import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography for the app.
/// English -> Poppins, Arabic -> Cairo (resolved per-locale in [AppTheme]).
class AppTextStyles {
  AppTextStyles._();

  static const String englishFont = 'Poppins';
  static const String arabicFont = 'Cairo';

  static TextTheme englishTextTheme(TextTheme base) =>
      GoogleFonts.poppinsTextTheme(base).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );

  static TextTheme arabicTextTheme(TextTheme base) => base.apply(
    fontFamily: arabicFont,
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );
}
